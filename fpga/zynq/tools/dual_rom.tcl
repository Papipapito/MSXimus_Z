# dual_rom.tcl - la MAQUINA B del perfil Dual (docs/tecnica/14-perfil-dual.md) manejada desde XSDB, sin teclado ni pantalla (31/10/2026).
# B se controla con una palabra del buzon: MBOX V9_BASE+4 = 0x1FFB0004 (la mitad alta del beat de control del V9990, que el companion
# no toca). La DDR arranca con basura, asi que la palabra solo vale con la clave D0A1h en [31:16] (este script la pone siempre; sin
# ella B no arranca). Bits: [0] B corre (a 0 queda en reset) [1] hay cartucho en el slot 1 [2] el teclado va a B (si no, la tecla
# Insert alterna A/B) [4:3] mapper del cartucho (0 Konami4, 1 ASCII8, 2 Konami SCC, 3 ASCII16) [5] cartucho lineal desde 0000h
# [6] sin el rectangulo de B en el escritorio del V9990 [7] posicion fina (la columna y la fila salen de la segunda palabra, 0x1FFB0008; ver
# `posicion`) [11:8] columna del rectangulo (0 = 192, n = 32 x n) [15:12] fila (0 = 188, n = 12 x n).
# La imagen de B (256 x 212 puntos) es un rectangulo dentro del frame buffer del V9990: se ve con el escritorio que pinta el ARM (tecla V
# al lanzar una ROM desde el menu de A, o la tecla Pausa para el V9990 a pantalla completa).
# La RAM y el cartucho de B viven en la DDR en 0x0C000000 (mapper de 2 MB en +0, cartucho con A21 = 0 en +0x400000, hasta 2 MB) y
# su VRAM en 0x10380000 (256 KB). La BIOS y la SUB-ROM son las del pack de A (0x10F60000 y 0x10F68000), solo lectura.
# No para el core 0 (el companion): usa el core 1, como screen.tcl o key.tcl. Hace falta hw_server y el perfil Dual cargado
# (F12 -> P -> DUAL, o perfiles.tcl cargar DUAL).
#
# Uso: xsdb.bat tools/dual_rom.tcl <orden> [argumentos]
#   estado                         la palabra de control y la telemetria de B (PC de la ultima M1, escrituras al VDP, fotogramas)
#   soltar                         B corre: arranca la BIOS (MSX BASIC) o el cartucho si lo hay. Su imagen sale en el rectangulo del escritorio
#   parar                          B en reset (el escritorio vuelve a pintar el rectangulo)
#   reset                          parar, esperar y soltar (B sin tocar la DDR: la RAM conserva lo que tenia, la BIOS la reescribe)
#   cargar <rom> [plain|plain0|plain1|plain2|konami4|ascii8|scc|ascii16] [lineal]
#                                  escribe la ROM (hasta 2 MB) en la zona del cartucho de B, la declara (slot 1) y reinicia B.
#                                  Sin decir mapper (ni lineal) elige solo, como el menu de A: una ROM de hasta 32 KB es PLANA y una mayor,
#                                  konami4. La plana no tiene registros de banco (las escrituras se ignoran) y va donde la pone su cabecera:
#                                  "AB" en +0 con INIT/STATEMENT/DEVICE/TEXT en 8000h-BFFFh = 8000h (ROM de pagina 2, p. ej. Stop the Express,
#                                  INIT = BFF0h); con ellos en 4000h-7FFFh o sin punteros = 4000h; de 17 a 32 KB = 4000h-BFFFh; "AB" en +4000h
#                                  con el INIT en 4000h-7FFFh = desde 0000h (el "Plain 0000h" del menu). El resto del slot 1 lee FFh.
#                                  plain la fuerza (pagina por la cabecera); plain0, plain1 y plain2 la fuerzan en 0000h, 4000h u 8000h.
#                                  En el RTL no hay un modo propio: es el lineal de megaram_scc (B_CTL[5]) con una imagen de 64 KB rellena de FFh.
#                                  Pedir un mapper o lineal desactiva la eleccion automatica (lineal: la ROM desde 0000h, sin relleno antes).
#   sincartucho                    slot 1 vacio y reinicia B (BASIC)
#   foco a|b                       el teclado USB (y el del buzon, key.tcl) va a A o a B (la tecla Insert lo alterna si no esta forzado a B)
#   ventana on|off|<col> <fila>    el rectangulo de B en el escritorio: on/off, o su posicion (col 0..15: 0 = 192, n = 32 x n; fila 0..15: 0 = 188,
#                                  n = 12 x n; el B5 del escritorio mide 640 x 400, el rectangulo 256 x 212). Con una posicion APAGA la fina
#   posicion <x> <y>               la posicion FINA, punto a punto: x de 0 a 896 e y de 0 a 268 en puntos del frame buffer (en el B5 del escritorio
#                                  x <= 384 e y <= 188). Escribe la segunda palabra, espera y enciende el bit 7 (el PL sigue la cuenta de peticiones de
#                                  foco con el bit 7 apagado). `posicion off` vuelve a la columna y fila gruesas
#   pantalla [columnas]            vuelca la pantalla de texto de B (SCREEN 0 o 1) leyendo su VRAM, como screen.tcl hace con A
#   vram_limpiar                   pone a cero los 256 KB de la VRAM de B (con B parada, o se pisa con lo que dibuje)
# Cartucho de prueba: python tools/dual_rom_prueba.py dual_prueba.rom y dual_rom.tcl cargar dual_prueba.rom (16 KB: AB + un contador en pantalla)
set MBOX   0x1FF00000
set CTL    0x1FFB0004
set CTL2   0x1FFB0008
set TELW   0x1FF000D0
set BRAM   0x0C000000
set BCART  0x0C400000
set BVRAM  0x10380000
set MAPPERS {konami4 0 ascii8 1 scc 2 ascii16 3}

proc uso {} { puts "uso: dual_rom.tcl estado|soltar|parar|reset|cargar rom \[plain|plain0|plain1|plain2|mapper\] \[lineal\]|sincartucho|foco a|b|ventana on|off|col fila|posicion x y|off|pantalla \[cols\]|vram_limpiar"; exit 1 }
if {$argc < 1} uso
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set CLAVE 0xD0A10000
proc ctl_get {} { set c [mrd -value $::CTL]; return [expr {($c & 0xFFFF0000) == $::CLAVE ? ($c & 0xFFFF) : 0}] }
proc ctl_set {v} { mwr $::CTL [expr {$::CLAVE | ($v & 0xFFFF)}] }
proc ctl_bits {mask val} { set c [ctl_get]; ctl_set [expr {($c & ~$mask) | ($val & $mask)}] }
proc esperar_ms {n} { after $n }   ;# el PL lee el buzon cada ~1 ms
proc estado {} {
    set c [ctl_get]
    set crudo [mrd -value $::CTL]
    set ta [mrd -value [expr {$::MBOX + 0x64}]]
    set tb [mrd -value [expr {$::MBOX + 0x60}]]
    puts [format "palabra cruda = %08X (%s)" $crudo [expr {($crudo & 0xFFFF0000) == $::CLAVE ? "clave D0A1 valida" : "SIN la clave D0A1: B parada"}]]
    set col [expr {($c >> 8) & 15}]; set fila [expr {($c >> 12) & 15}]
    puts [format "control B = %04X: %s, cartucho %s (mapper %d%s), teclado %s, rectangulo de B %s en la columna %d, fila %d" $c \
        [expr {$c & 1 ? "CORRE" : "PARADA"}] [expr {$c & 2 ? "SI" : "no"}] [expr {($c >> 3) & 3}] [expr {$c & 0x20 ? ", lineal" : ""}] \
        [expr {$c & 4 ? "forzado a B" : "con Insert (A por defecto)"}] [expr {$c & 0x40 ? "APAGADO" : "visible"}] \
        [expr {$col == 0 ? 192 : 32 * $col}] [expr {$fila == 0 ? 188 : 12 * $fila}]]
    if {$c & 0x80} {
        set c2 [mrd -value $::CTL2]
        puts [format "posicion FINA (bit 7): columna %d, fila %d (segunda palabra %08X; peticion de foco: conmuta = %d, a %s)" \
            [expr {$c2 & 0x3FF}] [expr {($c2 >> 10) & 0x1FF}] $c2 [expr {($c2 >> 20) & 1}] [expr {($c2 >> 21) & 1 ? "B" : "A"}]]
    }
    set lo [mrd -value $::TELW]; set hi [mrd -value [expr {$::TELW + 4}]]
    puts [format "raton (telemetria +0xD0, cuenta %d): puntero (%d, %d) boton %d, gestor de ventanas %s%s, ventana de A en (%d, %d), teclado en %s, B %s, silencio A %d B %d" \
        [expr {$hi >> 17}] [expr {$lo & 0x7FF}] [expr {($lo >> 11) & 0x3FF}] [expr {($lo >> 21) & 1}] [expr {($lo >> 23) & 1 ? "en pantalla" : "apagado"}] \
        [expr {($lo >> 22) & 1 ? " (arrastrando A)" : ""}] [expr {(($lo >> 24) | ($hi << 8)) & 0x7FF}] [expr {($hi >> 3) & 0x3FF}] \
        [expr {($hi >> 13) & 1 ? "B" : "A"}] [expr {($hi >> 14) & 1 ? "corre" : "parada"}] [expr {($hi >> 15) & 1}] [expr {($hi >> 16) & 1}]]
    puts [format "telemetria: PC de la ultima M1 = %04X, escrituras de B al VDP = %d, fotogramas del VDP de B = %d, A8h de B = %02X, fallos de cache = %d" \
        [expr {$ta >> 16}] [expr {$ta & 0xFFFF}] [expr {$tb >> 16}] [expr {($tb >> 8) & 255}] [expr {$tb & 255}]]
}
proc soltar {} { ctl_bits 1 1 }
proc parar {} { ctl_bits 1 0; esperar_ms 30 }
proc rb {a} { set w [mrd -value [expr {$::BRAM + (($a - 0xC000) & ~3)}]]; return [expr {($w >> ((($a - 0xC000) & 3) * 8)) & 255}] }
# Pagina (0, 1 o 2 = 0000h, 4000h, 8000h) donde va una ROM plana de hasta 32 KB; la cabecera decide, como el menu de A (lin0_detect y
# mir16_calc de bios/src). Devuelve la pagina y un texto con lo que ha visto.
proc rom_plana_pagina {rom tam} {
    set f [open $rom rb]
    fconfigure $f -translation binary
    set cab [read $f 10]
    if {$tam > 0x4000} { seek $f 0x4000; set cab2 [read $f 4] } else { set cab2 "" }
    close $f
    set id ""; set ptr {}; set id2 ""; set init2 0
    catch { binary scan $cab a2su4 id ptr }
    catch { binary scan $cab2 a2su id2 init2 }
    if {$id eq "AB"} {
        if {$tam > 0x4000} { return [list 1 "cabecera AB en +0, ROM de [expr {$tam / 1024}] KB: 4000h-BFFFh"] }
        foreach {nom p} [list INIT [lindex $ptr 0] STATEMENT [lindex $ptr 1] DEVICE [lindex $ptr 2] TEXT [lindex $ptr 3]] {
            if {$p ne "" && $p != 0} {
                set pag [expr {($p >> 14) == 2 ? 2 : 1}]
                return [list $pag [format "cabecera AB en +0, %s = %04Xh: %s" $nom $p [expr {$pag == 2 ? "ROM de pagina 2 (8000h-BFFFh)" : "4000h-7FFFh"}]]]
            }
        }
        return [list 1 "cabecera AB en +0 sin punteros: 4000h-7FFFh"]
    }
    if {$id2 eq "AB" && $init2 >= 0x4000 && $init2 < 0x8000} { return [list 0 [format "cabecera AB en +4000h, INIT = %04Xh: desde 0000h" $init2]] }
    return [list 1 "sin cabecera AB (la BIOS no la arrancara sola): 4000h"]
}

switch -exact -- [lindex $argv 0] {
    estado { estado }
    soltar { soltar; esperar_ms 50; estado }
    parar  { parar; estado }
    reset  { parar; soltar; esperar_ms 50; estado }
    sincartucho { parar; ctl_bits 2 0; soltar; esperar_ms 50; estado }
    foco {
        if {$argc < 2} uso
        ctl_bits 4 [expr {[string tolower [lindex $argv 1]] eq "b" ? 4 : 0}]
        esperar_ms 20; estado
    }
    ventana {
        if {$argc < 2} uso
        set a [string tolower [lindex $argv 1]]
        if {$a eq "on"} { ctl_bits 0x40 0 } elseif {$a eq "off"} { ctl_bits 0x40 0x40 } else {
            if {$argc < 3} uso
            set col [lindex $argv 1]; set fila [lindex $argv 2]
            if {$col < 0 || $col > 15 || $fila < 0 || $fila > 15} uso
            ctl_bits 0xFF80 [expr {($col << 8) | ($fila << 12)}]       ;# bits 15:8 = la posicion y bit 7 a 0: sin posicion fina
        }
        esperar_ms 20; estado
    }
    posicion {
        if {$argc < 2} uso
        if {[string tolower [lindex $argv 1]] eq "off"} { ctl_bits 0x80 0 } else {
            if {$argc < 3} uso
            set x [lindex $argv 1]; set y [lindex $argv 2]
            if {$x < 0 || $x > 896 || $y < 0 || $y > 268} uso
            set c2 [mrd -value $::CTL2]
            mwr $::CTL2 [expr {($c2 & 0x3F00000) | $x | ($y << 10)}]   ;# conserva las peticiones de foco (bits 20 y 21) y de silencio (22 a 25)
            esperar_ms 5
            ctl_bits 0x80 0x80
        }
        esperar_ms 20; estado
    }
    cargar {
        if {$argc < 2} uso
        set rom [lindex $argv 1]
        if {![file exists $rom]} { puts "no existe $rom"; exit 1 }
        set tam [file size $rom]
        if {$tam > 0x200000} { puts "la ROM mide $tam bytes: el cartucho de B admite hasta 2 MB (A21 = 0)"; exit 1 }
        set map 0; set lin 0; set pedido 0; set plano ""   ;# plano: "" no, auto (pagina por la cabecera) o 0/1/2
        foreach a [lrange $argv 2 end] {
            set a [string tolower $a]
            if {$a eq "lineal"} { set lin 1; set pedido 1 } elseif {$a eq "plain"} { set plano auto } elseif {[regexp {^plain([012])$} $a -> n]} { set plano $n } \
            elseif {[dict exists $::MAPPERS $a]} { set map [dict get $::MAPPERS $a]; set pedido 1 } else { puts "mapper o palabra desconocida: $a"; exit 1 }
        }
        if {$plano ne "" && $pedido} { puts "plain no se combina con un mapper ni con lineal"; exit 1 }
        if {$plano eq "" && !$pedido && $tam <= 0x8000} { set plano auto }   ;# como el menu de A: hasta 32 KB, plana
        set txt "mapper $map[expr {$lin ? { lineal} : {}}]"
        if {$plano ne ""} {
            # PLANA: la ROM en su pagina de una imagen de 64 KB que el cartucho (modo lineal) enseña tal cual; el resto del slot es FF
            if {$tam > 0x8000} { puts "una ROM plana mide hasta 32 KB; esta mide $tam bytes"; exit 1 }
            if {$plano eq "auto"} { lassign [rom_plana_pagina $rom $tam] pag que } else { set pag $plano; set que "pagina $plano pedida" }
            set off [expr {$pag * 0x4000}]
            if {$off + $tam > 0xC000} { puts "la ROM de $tam bytes no cabe desde [format %04Xh $off] (un cartucho llega hasta BFFFh)"; exit 1 }
        }
        parar                                              ;# B en reset: su cache de RAM se invalida y nadie lee la zona
        if {$plano ne ""} {
            if {$off > 0} { mwr -size w $::BCART [lrepeat [expr {$off / 4}] 0xFFFFFFFF] }
            mwr -bin -file $rom [expr {$::BCART + $off}] [expr {($tam + 3) / 4}]
            set fin [expr {$off + (($tam + 3) & ~3)}]
            if {$fin < 0x10000} { mwr -size w [expr {$::BCART + $fin}] [lrepeat [expr {(0x10000 - $fin) / 4}] 0xFFFFFFFF] }
            set map 0; set lin 1
            set txt [format "plana en %04Xh-%04Xh (%s), el resto del slot 1 lee FFh" $off [expr {$off + $tam - 1}] $que]
        } else {
            mwr -bin -file $rom $::BCART [expr {($tam + 3) / 4}]
            # un bloque de FF tras la ROM, para que el cartucho no enseñe basura donde acaba (hasta el siguiente multiplo de 64 KB)
            set resto [expr {(0x10000 - ($tam & 0xFFFF)) & 0xFFFF}]
            if {$resto > 0} { mwr -size w [expr {$::BCART + (($tam + 3) & ~3)}] [lrepeat [expr {$resto / 4}] 0xFFFFFFFF] }
        }
        ctl_bits 0x3F [expr {2 | ($map << 3) | ($lin ? 0x20 : 0)}]
        esperar_ms 10
        soltar; esperar_ms 50
        puts "ROM de $tam bytes escrita en [format 0x%08X $::BCART] ($txt)"
        estado
    }
    vram_limpiar {
        mwr -size w $::BVRAM [lrepeat 65536 0]
        puts "VRAM de B a cero ([format 0x%08X $::BVRAM], 256 KB)"
    }
    pantalla {
        set scrmod [rb 0xFCAF]
        set nambas [expr {[rb 0xF922] | [rb 0xF923] << 8}]
        set linl40 [rb 0xF3AE]
        set csry [rb 0xF3DC]; set csrx [rb 0xF3DD]
        if {$argc > 1} { set cols [lindex $argv 1] } elseif {$scrmod == 0} { set cols $linl40 } else { set cols 32 }
        if {$scrmod > 1 && $argc < 2} { puts "SCREEN $scrmod: no es un modo de texto (NAMBAS=[format %04X $nambas])"; exit }
        set base [expr {$::BVRAM + $nambas}]
        set nwords [expr {($cols * 24 + 3) / 4}]
        set w [mrd -value $base $nwords]
        set bytes {}
        foreach x $w { lappend bytes [expr {$x & 255}] [expr {($x >> 8) & 255}] [expr {($x >> 16) & 255}] [expr {($x >> 24) & 255}] }
        puts "---- B: SCREEN $scrmod, ${cols}x24, NAMBAS [format %04X $nambas] (DDR [format 0x%08X $base]), cursor fila $csry col $csrx ----"
        for {set r 0} {$r < 24} {incr r} {
            set line ""
            for {set c 0} {$c < $cols} {incr c} {
                set b [lindex $bytes [expr {$r * $cols + $c}]]
                append line [expr {$b >= 32 && $b < 127 ? [format %c $b] : ($b == 0 || $b == 32 ? " " : ".")}]
            }
            puts [format "%2d|%s|" [expr {$r + 1}] [string trimright $line]]
        }
    }
    default uso
}
exit
