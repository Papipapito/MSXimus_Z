# pcap_prueba.tcl — prueba de carga de un bitstream por PCAP desde el companion (30/10/2026, fase 4 de los perfiles).
# Deja el .bin de bootgen (-process_bitstream bin) en la zona de la prueba de la DDR (0x1F400000, companion/profile.h),
# escribe la cabecera {magia 'PCAP', tamano, comprobacion} y espera el informe. El companion sondea la zona en su bucle,
# la ve, borra la magia y carga el bitstream: el PL se reconfigura con el PS vivo y el MSX reinicia. No para ninguna CPU
# (se entra por el DAP, objetivo APU: la DDR por el bus del sistema, sin pasar por la cache del core 0).
# Uso:  xsdb.bat tools/pcap_prueba.tcl <fichero.bin>      (hw_server corriendo)
#       xsdb.bat tools/pcap_prueba.tcl <fichero.bin> axi   ademas resetea las interfaces AXI del PS al aislar el PL (experimental: solo si un puerto HP se queda colgado)
#       xsdb.bat tools/pcap_prueba.tcl log                solo mira el informe y el final del log del companion
#       xsdb.bat tools/pcap_prueba.tcl cargar <fichero.bin> [axi]   igual que sin "cargar" (el bitstream de la DDR, sin pasar por la TF1)
#       xsdb.bat tools/pcap_prueba.tcl instalar <fichero.mxp> [cortar N]   (fase 5, perfiles en la TF1) instala un .mxp de tools/mxpf.py
#                                                        en la particion MXPF de la TF1; tambien estado, preparar, borrar, perfil1, tarjeta_vacia, tecla:
#                                                        todo eso es tools/perfiles.tcl (ahi esta la explicacion). El .bin de "cargar" sigue
#                                                        sin tocar la TF1; para cargar un perfil INSTALADO: perfiles.tcl cargar <ID>
# El informe lo deja el companion en la misma zona: +0x10 estado (1 en curso, 2 OK, 0x80+n rechazado sin tocar el PL),
# +0x14 etapa, +0x18.. tiempos en us (parado, aislado, init, DMA, DONE, PL vivo, MSX suelto), +0x34 INT_STS, +0x38 STATUS,
# +0x3C codigo del error. Si el bitstream es malo el companion reinicia el PS (se pierde el informe y el log: la DDR
# del buzon se vuelve a poner a cero; mirar que la placa vuelve a arrancar la version de la QSPI/SD).
set ZONA   0x1F400000
set DATOS  [expr {$ZONA + 0x1000}]
set MAXB   [expr {0x400000 - 0x1000}]
set MBOX   0x1FF00000
set SDBOX  0x1FF00100
set LOG    0x1FF00800
set LOGSZ  0x700
set MAGIA  0x50414350

proc leer_log {n} {
    global LOG LOGSZ
    set h [mrd -value $LOG 2]
    if {[lindex $h 0] != 0x474F4C41} { return "(sin log del ARM)\n" }
    set wr [lindex $h 1]
    set start [expr {$wr > $n ? $wr - $n : 0}]
    if {$wr > $LOGSZ && $start < $wr - $LOGSZ} { set start [expr {$wr - $LOGSZ}] }
    set w [mrd -value [expr {$LOG + 8}] [expr {$LOGSZ / 4}]]
    set txt ""
    for {set i $start} {$i < $wr} {incr i} {
        set j [expr {$i % $LOGSZ}]
        append txt [format %c [expr {([lindex $w [expr {$j / 4}]] >> (($j % 4) * 8)) & 255}]]
    }
    return $txt
}

proc informe {} {
    global ZONA
    set r [mrd -value [expr {$ZONA + 0x10}] 16]
    set st [lindex $r 0]; set et [lindex $r 1]
    set nom_st [expr {$st == 0 ? "sin informe" : $st == 1 ? "EN CURSO" : $st == 2 ? "OK (cargado y MSX suelto)" : $st >= 0x80 ? [format "RECHAZADO sin tocar el PL (error %d)" [expr {$st - 0x80}]] : "?"}]
    set nom_et [lindex {ninguna parado aislado init dma done vivo resembrado run} $et]
    puts [format "informe: estado=%d (%s) etapa=%d (%s)" $st $nom_st $et $nom_et]
    if {$st == 2 || $et >= 2} {
        puts [format "  tiempos (us desde el inicio de la carga): parado=%u aislado=%u init=%u DMA=%u DONE=%u PL_vivo=%u MSX_suelto=%u" \
            [lindex $r 2] [lindex $r 3] [lindex $r 4] [lindex $r 5] [lindex $r 6] [lindex $r 7] [lindex $r 8]]
    }
    puts [format "  INT_STS=%08X STATUS=%08X codigo_error=%u" [lindex $r 13] [lindex $r 14] [lindex $r 15]]
    return [list $st $et]
}

# muestras de la DDR que la PCAP no debe tocar (el controlador de DDR es del PS): ROM de ondas, pack de BIOS (el menu),
# megaram baja (donde el menu carga las ROMs) y alta; solo se leen
proc muestras {} {
    set m {}
    foreach {a n} {0x0F000000 8 0x0F1FFFE0 8 0x10F00000 8 0x10F7FFE0 8 0x10C00000 16 0x0E000000 16} { lappend m [mrd -value $a $n] }
    return $m
}

# fase 5: lo de la TF1 es de perfiles.tcl (el mismo xsdb; sus ordenes empiezan por el verbo)
if {$argc >= 1 && [lsearch -exact {instalar estado preparar borrar perfil1 tarjeta_vacia tecla} [lindex $argv 0]] >= 0} {
    set aqui [file dirname [info script]]
    if {![file exists [file join $aqui perfiles.tcl]]} { set aqui tools }
    source [file join $aqui perfiles.tcl]
    exit
}
if {$argc >= 2 && [lindex $argv 0] eq "cargar"} { set argv [lrange $argv 1 end]; incr argc -1 }

connect -url tcp:127.0.0.1:3121
after 500
targets -set -filter {name =~ "APU*"}

if {$argc < 1} { puts "uso: pcap_prueba.tcl <fichero.bin>|log|cargar <fichero.bin>|instalar <fichero.mxp>"; exit 1 }
set f [lindex $argv 0]
if {$f eq "log"} {
    informe
    puts "---- log del ARM ----"
    puts -nonewline [leer_log 1200]
    exit
}
set flags [expr {($argc > 1 && [lindex $argv 1] eq "axi") ? 1 : 0}]   ;# axi: FPGA_RST_CTRL tambien resetea las interfaces AXI (experimental, si un HP se cuelga)
if {![file exists $f]} { puts "ERROR: no existe $f"; exit 1 }
set tam [file size $f]
if {($tam % 4) != 0 || $tam < 4096 || $tam > $MAXB} { puts "ERROR: $tam bytes: tiene que ser multiplo de 4, >= 4096 y <= $MAXB"; exit 1 }
# el bitstream tiene que ser el .bin de bootgen: la palabra de sincronismo 0xAA995566 aparece como los bytes 66 55 99 AA
set fh [open $f rb]; set cab [read $fh 512]; close $fh
if {[string first "\x66\x55\x99\xAA" $cab] < 0} {
    if {[string first "\xAA\x99\x55\x66" $cab] >= 0} {
        puts "ERROR: $f esta SIN girar (AA 99 55 66): hace falta bootgen -arch zynq -image x.bif -process_bitstream bin"
    } else { puts "ERROR: $f no tiene el sincronismo 66 55 99 AA en los primeros 512 bytes: no es un .bin de bootgen" }
    exit 1
}

# el companion tiene que estar girando (SDBOX+0x30 = vueltas del bucle) y la zona no tener una peticion colgada
set v0 [mrd -value [expr {$SDBOX + 0x30}]]; after 300; set v1 [mrd -value [expr {$SDBOX + 0x30}]]
if {$v0 == $v1} { puts "ERROR: el companion no gira (vueltas $v0 -> $v1): parado por JTAG (dale 'con' a la CPU 0) o sin arrancar"; exit 1 }
puts [format "companion vivo (vueltas %u -> %u). Zona de la prueba %08X, datos en %08X" $v0 $v1 $ZONA $DATOS]
if {[mrd -value $ZONA] == $MAGIA} { puts "AVISO: ya habia una peticion sin atender en la zona; se sobrescribe" }

# informe a cero, bitstream, comprobacion y por ultimo la cabecera con la magia (el companion la mira en cada vuelta)
mwr $ZONA [lrepeat 16 0] 16
set t0 [clock milliseconds]
mwr -bin -file $f $DATOS [expr {$tam / 4}]
set t1 [clock milliseconds]
puts [format "bitstream: %s (%d bytes) -> %08X en %d ms por JTAG (esto no cuenta en los tiempos del companion)" [file tail $f] $tam $DATOS [expr {$t1 - $t0}]]
set fh [open $f rb]; set ref [read $fh $tam]; close $fh
binary scan [string range $ref 0 63] i16 cab16
binary scan [string range $ref [expr {$tam - 64}] end] i16 col16
set la [mrd -value $DATOS 16]; set lb [mrd -value [expr {$DATOS + $tam - 64}] 16]
foreach p {{la cab16 cabeza} {lb col16 cola}} {
    lassign $p got want nom
    set a [set $got]; set b [set $want]
    for {set i 0} {$i < 16} {incr i} {
        if {([lindex $a $i] & 0xFFFFFFFF) != ([lindex $b $i] & 0xFFFFFFFF)} { puts "ERROR: la $nom del bitstream no coincide en la DDR (palabra $i): $a / $b"; exit 1 }
    }
}
puts "bitstream: cabeza y cola verificadas en la DDR"
set chk [expr {($MAGIA ^ $tam ^ 0xA5A5A5A5) & 0xFFFFFFFF}]
mwr [expr {$ZONA + 4}] [list $tam $chk $flags] 3
mwr $ZONA $MAGIA
set antes [muestras]
set tdisp [clock milliseconds]
puts [format "cabecera escrita (tamano %d, comprobacion %08X). Esperando al companion..." $tam $chk]

# esperar: la magia la borra el companion al verla; el informe pasa de 1 (en curso) a 2 (OK) o 0x8n (rechazado)
set fin 0
set st 0
for {set i 0} {$i < 200 && !$fin} {incr i} {
    after 100
    if {[catch { set r [mrd -value [expr {$ZONA + 0x10}] 2]; set st [lindex $r 0] } err]} {
        puts "el PS no contesta por JTAG ($err): se esta reiniciando (carga fallida) o reconfigurando"
        set fin 2
    } elseif {$st == 2 || $st >= 0x80} { set fin 1 }
}
puts [format "tiempo desde la cabecera hasta el informe: %d ms (incluye 100 ms de sondeo de esta herramienta)" [expr {[clock milliseconds] - $tdisp}]]
if {$fin == 2 || !$fin} {
    puts "SIN INFORME FINAL. Si el bitstream era malo es lo esperado: el companion reinicia el PS y la placa vuelve a la version"
    puts "de la QSPI/SD en unos 10 s (con SW1 en JTAG se queda parada). Mira la pantalla, Ajustes (version) y 'pcap_prueba.tcl log'."
    catch { informe }
    exit 2
}
after 500
informe
set despues [muestras]
set nom {YRW801-cabeza YRW801-cola pack-cabeza pack-cola megaram-baja megaram-alta}
set dif {}
for {set i 0} {$i < 6} {incr i} { if {[lindex $antes $i] ne [lindex $despues $i]} { lappend dif [lindex $nom $i] } }
puts [expr {[llength $dif] ? "DDR: CAMBIADA en [join $dif {, }] (la megaram puede cambiar por el propio MSX; YRW801 y pack no)" : "DDR: conservada (YRW801, pack y megaram: las mismas palabras antes y despues)"}]
puts "---- log del ARM (final) ----"
puts -nonewline [leer_log 1200]
exit
