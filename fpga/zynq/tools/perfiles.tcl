# perfiles.tcl — los perfiles del PL en la TF1 (companion/mxpf.c) manejados desde XSDB, SIN teclado ni pantalla (30/10/2026).
# Cada orden la deja el companion en la zona de la DDR (0x1F400100), la atiende en su bucle y deja un informe con el resultado,
# los tiempos y un texto legible (estado de la tarjeta, lista de perfiles, perfil activo) en 0x1F400200/0x1F400400. No para
# ninguna CPU (objetivo APU). Hace falta hw_server corriendo y el companion de esta rama (BOOT_mxpf) arrancado.
#
# Uso: xsdb.bat tools/perfiles.tcl <orden> [argumentos]
#   estado                          TF1 (MB, particion MXPF, huecos), perfil activo y lista de perfiles; no toca nada
#   preparar CONFIRMO               LEGADO (bancos): crea una particion MXPF COMPARTIDA en la TF1 sin borrar nada: ESCRIBE EN EL MBR
#   dedicada <MB> PELIGRO           TF1 «solo perfiles»: BORRA LA TARJETA ENTERA y la deja con P1 FAT32 (128 MB, LEEME.TXT) + P2 MXPF (512 MB).
#                                   <MB> = tamano de la tarjeta (sale en "estado"). Nunca con la placa arrancada desde SD (SW1 en SD):
#                                   el companion se niega. Si la tarjeta ya es nuestra, no hace nada. "estado" dice la clase de la tarjeta
#   instalar <fichero.mxp> [cortar N]   sube el .mxp a la DDR y lo instala; "cortar N" = prueba de apagon: el companion deja
#                                   de escribir tras N sectores y dice "corte simulado" (la tarjeta queda como tras quitar la luz)
#   cargar <ID|N>                   carga el perfil (por su id o por su numero en la lista) por PCAP; el MSX se reinicia
#   borrar <ID|N> CONFIRMO          borra el perfil (marca su entrada libre)
#   perfil1                         vuelve al perfil del BOOT.bin: reinicia el PS (con SW1 en JTAG no se puede). Espera y vuelve a mirar
#   tarjeta_vacia <MB> PELIGRO      SOLO PARA EL BANCO DE PLACA: deja la TF1 sin particiones (MBR a cero salvo la firma 55AA).
#                                   <MB> = tamano de la tarjeta (sale en "estado"): otra cifra y no hace nada. NO ESTA EN EL PANEL
#   tecla <P|U|ENTER|ESC|UP|DOWN|D|T|R|...>...  pulsa teclas en el panel F12 por MBOX+0x3C (abre el panel si hace falta): P abre
#                                   la pagina Perfiles; despues DOWN, ENTER (cargar), D y ENTER (borrar), T y ENTER (preparar),
#                                   A (perfil al arrancar: el elegido; sobre el perfil 1, ninguno), S (vista del servidor: U busca,
#                                   B canal, ENTER baja el elegido, A baja todos los que falten o esten viejos, S o ESC vuelven)
#   log [n]                         final del log del companion
# Las ordenes peligrosas (preparar, dedicada, borrar, tarjeta_vacia) piden ademas la palabra de confirmacion de la linea de ordenes y la
# herramienta escribe DOS marcas de confirmacion por separado (CON1, 200 ms, CON2) que el companion exige las dos.
# Salida: 0 bien, 1 error de uso o de la orden, 2 sin informe (companion parado, o el PS se reinicio).
set ZONA   0x1F400000
set ORD    [expr {$ZONA + 0x100}]
set INF    [expr {$ZONA + 0x200}]
set TXT    [expr {$ZONA + 0x400}]
set DATOS  [expr {$ZONA + 0x1000}]
set MAXMXP [expr {0x3EF000}]
set SDBOX  0x1FF00100
set LOG    0x1FF00800
set LOGSZ  0x700
set OTAKEY 0x1FF0003C
set MAGORD 0x524F584D
set CONF1  0x314E4F43
set CONF2  0x324E4F43
array set CMD {estado 1 preparar 2 instalar 3 cargar 4 borrar 5 perfil1 6 tarjeta_vacia 7 dedicada 8}
array set HID {A 4 B 5 C 6 D 7 E 8 F 9 G 10 H 11 I 12 J 13 K 14 L 15 M 16 N 17 O 18 P 19 Q 20 R 21 S 22 T 23 U 24 V 25 W 26 X 27 Y 28 Z 29
               1 30 2 31 3 32 4 33 5 34 6 35 7 36 8 37 9 38 0 39 ENTER 40 RETURN 40 ESC 41 UP 82 DOWN 81 LEFT 80 RIGHT 79}
array set ERR {0 bien 1 TARJETA 2 MBR 3 ENTRADAS 4 SITIO 5 YA 6 SINPART 7 DIR 8 LLENO 9 FORMATO 10 SHA 11 ZLIB 12 SERIE 13 OCUPADO 14 PARAM
               15 NOEXISTE 16 IO 17 PCAP 18 CORTE 19 CONFIRMA 20 VERIFICA 21 JTAG 22 ARRANQUE_SD 23 FALSA}

proc uso {} { puts "uso: perfiles.tcl estado|preparar CONFIRMO|dedicada MB PELIGRO|instalar f.mxp \[cortar N\]|cargar ID|borrar ID CONFIRMO|perfil1|tarjeta_vacia MB PELIGRO|tecla K...|log"; exit 1 }

proc conectar {} {
    connect -url tcp:127.0.0.1:3121
    after 300
    targets -set -filter {name =~ "APU*"}
}

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

proc companion_vivo {} {
    global SDBOX
    set v0 [mrd -value [expr {$SDBOX + 0x30}]]; after 300; set v1 [mrd -value [expr {$SDBOX + 0x30}]]
    return [expr {$v0 != $v1}]
}

# el informe: {seq orden estado codigo t_lee t_esc t_ver t_copia t_sha t_zlib t_pcap t_total activo nperf estado_mxs ntexto}
proc informe {} {
    global INF
    set r [mrd -value $INF 16]
    set o {}
    foreach v $r { lappend o [expr {$v & 0xFFFFFFFF}] }
    return $o
}

proc texto {n} {
    global TXT
    if {$n <= 0 || $n > 0xC00} { return "" }
    set nw [expr {($n + 3) / 4}]
    set w [mrd -value $TXT $nw]
    set s ""
    for {set i 0} {$i < $n} {incr i} {
        set c [expr {([lindex $w [expr {$i / 4}]] >> (($i % 4) * 8)) & 255}]
        if {$c == 0} break
        append s [format %c $c]
    }
    return $s
}

# envia una orden y espera el informe; devuelve {estado codigo} o {sin_informe}
proc orden {cmd a0 a1 id conf {espera_s 180}} {
    global ORD MAGORD CONF1 CONF2
    set w0 [informe]
    set seq0 [lindex $w0 0]
    set idb [string range [string toupper $id] 0 15]
    binary scan [binary format a16 $idb] iu4 idw
    # palabras 1..9 de la orden; la 10 es la comprobacion; la magia (palabra 0) va la ULTIMA
    set w [list $cmd $a0 $a1 {*}$idw 0 0]
    if {$conf} {
        # doble confirmacion: primero CON1 (y se relee), pasados 200 ms CON2
        lset w 7 $CONF1
        mwr [expr {$ORD + 4}] [concat $w 0] 10
        after 200
        if {[expr {[mrd -value [expr {$ORD + 4 + 7 * 4}]] & 0xFFFFFFFF}] != $CONF1} { puts "ERROR: la marca CON1 no se ha quedado escrita"; exit 1 }
        lset w 8 $CONF2
    }
    set chk [expr {$MAGORD ^ 0xA5A5A5A5}]
    foreach v $w { set chk [expr {$chk ^ ($v & 0xFFFFFFFF)}] }
    mwr [expr {$ORD + 4}] [concat $w [list $chk]] 10
    mwr $ORD $MAGORD
    set t0 [clock milliseconds]
    set fin 0
    while {!$fin && ([clock milliseconds] - $t0) < $espera_s * 1000} {
        after 100
        if {[catch {set r [informe]} err]} { puts "el PS no contesta por JTAG ($err): se esta reiniciando"; return {sin_informe} }
        if {[lindex $r 0] != $seq0 && [lindex $r 2] != 1} { set fin 1 }
    }
    if {!$fin} { return {sin_informe} }
    puts [format "orden atendida en %d ms (incluye 100 ms de sondeo de esta herramienta)" [expr {[clock milliseconds] - $t0}]]
    return [list [lindex $r 2] [lindex $r 3]]
}

proc muestra {} {
    set r [informe]
    set t [texto [lindex $r 15]]
    puts "---- informe del companion ----"
    puts -nonewline $t
    puts [format "(tiempos us: lee %d escribe %d verifica %d copia %d sha %d zlib %d pcap %d total %d)" {*}[lrange $r 4 11]]
    return $r
}

proc resultado {res} {
    global ERR
    if {[lindex $res 0] eq "sin_informe"} {
        puts "SIN INFORME: el companion no contesta (parado por JTAG, sin arrancar) o el PS se ha reiniciado (carga fallida / perfil1)."
        exit 2
    }
    lassign $res st cod
    if {$st == 2} { puts "== OK =="; exit 0 }
    set nom [expr {[info exists ERR($cod)] ? $ERR($cod) : "?"}]
    puts "== ERROR $cod ($nom) =="
    exit 1
}

if {$argc < 1} uso
set verbo [lindex $argv 0]
conectar
if {$verbo eq "log"} {
    puts -nonewline [leer_log [expr {$argc > 1 ? [lindex $argv 1] : 1200}]]
    exit 0
}
if {$verbo eq "tecla"} {
    if {$argc < 2} uso
    foreach k [lrange $argv 1 end] {
        set K [string toupper $k]
        if {![info exists HID($K)]} { puts "tecla desconocida: $k"; exit 1 }
        mwr $OTAKEY $HID($K)
        for {set i 0} {$i < 30 && [expr {[mrd -value $OTAKEY] & 0xFF}] != 0} {incr i} { after 100 }
        if {[expr {[mrd -value $OTAKEY] & 0xFF}] != 0} { puts "AVISO: el companion no ha recogido la tecla $K en 3 s" } else { puts "tecla $K enviada" }
        after 300
    }
    puts -nonewline [leer_log 500]
    exit 0
}
if {![info exists CMD($verbo)]} uso
if {![companion_vivo]} { puts "ERROR: el companion no gira (parado por JTAG: dale 'con' a la CPU 0) o sin arrancar"; exit 2 }

switch $verbo {
    estado {
        set res [orden 1 0 0 "" 0 20]
        if {[lindex $res 0] eq "sin_informe"} { resultado $res }
        muestra
        resultado $res
    }
    preparar {
        if {$argc < 2 || [lindex $argv 1] ne "CONFIRMO"} { puts "preparar ESCRIBE EN EL MBR de la TF1. Si estas seguro: perfiles.tcl preparar CONFIRMO"; exit 1 }
        set res [orden 2 0 0 "" 1 60]
        muestra
        resultado $res
    }
    dedicada {
        if {$argc < 3 || [lindex $argv 2] ne "PELIGRO"} { puts "dedicada <MB de la tarjeta> PELIGRO: BORRA la tarjeta de TF1 entera y la prepara para perfiles (P1 FAT32 + P2 MXPF)"; exit 1 }
        set res [orden 8 0 [lindex $argv 1] "" 1 120]
        muestra
        resultado $res
    }
    instalar {
        if {$argc < 2} uso
        set f [lindex $argv 1]
        set corte [expr {($argc >= 4 && [lindex $argv 2] eq "cortar") ? [lindex $argv 3] : 0}]
        if {![file exists $f]} { puts "ERROR: no existe $f"; exit 1 }
        set tam [file size $f]
        if {($tam % 4) != 0 || $tam < 512 || $tam > $MAXMXP} { puts "ERROR: $tam bytes: tiene que ser multiplo de 4 (los .mxp de mxpf.py lo son), >= 512 y <= $MAXMXP"; exit 1 }
        set fh [open $f rb]; set cab [read $fh 4]; close $fh
        if {$cab ne "MXP1"} { puts "ERROR: $f no es un .mxp (falta MXP1): empaquetalo con tools/mxpf.py empaquetar"; exit 1 }
        set t0 [clock milliseconds]
        mwr -bin -file $f $DATOS [expr {$tam / 4}]
        puts [format ".mxp: %s (%d bytes) -> %08X en %d ms por JTAG (no cuenta en los tiempos del companion)" [file tail $f] $tam $DATOS [expr {[clock milliseconds] - $t0}]]
        set fh [open $f rb]; set ref [read $fh $tam]; close $fh
        binary scan [string range $ref 0 63] iu16 cab16
        binary scan [string range $ref [expr {$tam - 64}] end] iu16 col16
        set la [mrd -value $DATOS 16]; set lb [mrd -value [expr {$DATOS + $tam - 64}] 16]
        for {set i 0} {$i < 16} {incr i} {
            if {([lindex $la $i] & 0xFFFFFFFF) != [lindex $cab16 $i] || ([lindex $lb $i] & 0xFFFFFFFF) != [lindex $col16 $i]} { puts "ERROR: el .mxp no ha quedado bien en la DDR (palabra $i de la cabeza o la cola)"; exit 1 }
        }
        puts "cabeza y cola verificadas en la DDR"
        set res [orden 3 $tam $corte "" 0 120]
        muestra
        resultado $res
    }
    cargar {
        if {$argc < 2} uso
        set a [lindex $argv 1]
        set res [expr {[string is integer -strict $a] ? [orden 4 $a 0 "" 0 60] : [orden 4 0 0 $a 0 60]}]
        if {[lindex $res 0] ne "sin_informe"} { muestra }
        resultado $res
    }
    borrar {
        if {$argc < 3 || [lindex $argv 2] ne "CONFIRMO"} { puts "borrar <ID|N> CONFIRMO"; exit 1 }
        set a [lindex $argv 1]
        set res [expr {[string is integer -strict $a] ? [orden 5 $a 0 "" 1 60] : [orden 5 0 0 $a 1 60]}]
        muestra
        resultado $res
    }
    perfil1 {
        set res [orden 6 0 0 "" 0 30]
        if {[lindex $res 0] ne "sin_informe"} { muestra }
        if {[lindex $res 0] eq "sin_informe" || [lindex $res 0] == 2} {
            puts "esperando a que el PS vuelva (BootROM + FSBL + companion, unos 15 s)..."
            after 8000
            for {set i 0} {$i < 40} {incr i} {
                if {![catch { conectar; companion_vivo } vivo] && $vivo == 1} { puts "el companion gira otra vez"; break }
                after 1500
            }
            catch { orden 1 0 0 "" 0 20; muestra }
            exit 0
        }
        resultado $res
    }
    tarjeta_vacia {
        if {$argc < 3 || [lindex $argv 2] ne "PELIGRO"} { puts "tarjeta_vacia <MB de la tarjeta> PELIGRO: borra la tabla de particiones de la TF1 (solo para el banco de placa)"; exit 1 }
        set res [orden 7 0 [lindex $argv 1] "" 1 60]
        muestra
        resultado $res
    }
}
