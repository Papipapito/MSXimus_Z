# wg.tcl — WaveGame (16/09): estado de la voz y del anillo Z80->ARM, e inyeccion de ordenes al
# companion como si vinieran del Z80 (MBOX+0x38 = {seq[31:24], tag[15:8], dato[7:0]}).
#   xsdb.bat tools/wg.tcl                       estado (control +0x20, telemetria +0xB8, anillo)
#   xsdb.bat tools/wg.tcl cmd <hex>             orden del juego (puerto 92h): 41 = toca 01, 81 = 01 en bucle,
#                                               00 = fade-out 1 s, C0 pausa, E0 retoma, F0 pause.wav
#   xsdb.bat tools/wg.tcl msg <part_lba> <dir_clus> <file_clus>   mensaje del menu (puerto 93h)
#   xsdb.bat tools/wg.tcl wav <part_lba> <dir_clus> [pista]  musica del menu (tecla P): lista los .WAV de
#                                               esa carpeta y toca; repetirlo con pista 0 = PARAR
#   xsdb.bat tools/wg.tcl next                  pista siguiente (tecla N)
#   xsdb.bat tools/wg.tcl stop                  parar la lista
#   xsdb.bat tools/wg.tcl vol <0..255>          volumen fino (255 = x1)
#   xsdb.bat tools/wg.tcl gain <0..3>           ganancia del PL: x1 (defecto, maximo limpio), x2, x4, x8 (recortan)
#   xsdb.bat tools/wg.tcl ring                  volcar el anillo Z80->ARM (32 entradas)
set MBOX 0x1FF00000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
proc inj {tag dat} {
    global MBOX
    set v [mrd -value [expr {$MBOX + 0x38}]]
    set seq [expr {(($v >> 24) + 1) & 0xFF}]
    mwr [expr {$MBOX + 0x38}] [expr {($seq << 24) | (($tag & 0xFF) << 8) | ($dat & 0xFF)}]
    after 15
}
set cmd [lindex $argv 0]
if {$cmd eq "cmd"} {
    set b [expr [lindex $argv 1]]
    inj 0x92 $b
    puts [format "orden 92h <= %02X" $b]
} elseif {$cmd eq "msg"} {
    set part [expr [lindex $argv 1]]; set dir [expr [lindex $argv 2]]; set file [expr [lindex $argv 3]]
    inj 0x93 0x57; inj 0x93 0x47
    foreach v [list $part $dir $file] { for {set i 0} {$i < 4} {incr i} { inj 0x93 [expr {($v >> (8*$i)) & 0xFF}] } }
    puts "mensaje del menu enviado: part=$part dir=$dir file=$file"
} elseif {$cmd eq "wav"} {
    set part [expr [lindex $argv 1]]; set dir [expr [lindex $argv 2]]
    set trk [expr {[llength $argv] > 3 ? [expr [lindex $argv 3]] : 0}]
    inj 0x93 0x57; inj 0x93 0x50
    foreach v [list $part $dir $trk] { for {set i 0} {$i < 4} {incr i} { inj 0x93 [expr {($v >> (8*$i)) & 0xFF}] } }
    puts "musica del menu: part=$part carpeta=$dir pista=$trk (repetirlo con pista 0 = parar)"
} elseif {$cmd eq "next"} {
    inj 0x93 0x57; inj 0x93 0x4E
    puts "pista siguiente"
} elseif {$cmd eq "stop"} {
    inj 0x93 0x57; inj 0x93 0x58
    puts "lista parada"
} elseif {$cmd eq "gain"} {
    inj 0x3D [expr [lindex $argv 1]]
    puts "ganancia <= x[expr {1 << [lindex $argv 1]}]"
} elseif {$cmd eq "vol"} {
    inj 0x3C [expr [lindex $argv 1]]
    puts "volumen <= [lindex $argv 1]"
} elseif {$cmd eq "ring"} {
    set w [mrd -value [expr {$MBOX + 0x78}] 16]
    set wi [expr {[mrd -value [expr {$MBOX + 0xBC}]] >> 24}]
    puts "anillo Z80->ARM (wi=$wi):"
    for {set k 0} {$k < 32} {incr k} {
        set e [expr {([lindex $w [expr {$k / 2}]] >> (16 * ($k % 2))) & 0xFFFF}]
        puts -nonewline [format " %02d:%02X.%02X" $k [expr {$e >> 8}] [expr {$e & 0xFF}]]
        if {$k % 8 == 7} { puts "" }
    }
}
after 30
set ctl [mrd -value [expr {$MBOX + 0x20}]]
set lo  [mrd -value [expr {$MBOX + 0xB8}]]
set hi  [mrd -value [expr {$MBOX + 0xBC}]]
puts [format "control +0x20: play=%d gain=x%d wr=%d | PL: play=%d rd=%d nivel FIFO=%d/128 fetches=%d | z2a wi=%d | pendientes ARM->PL: %d muestras" \
    [expr {($ctl >> 31) & 1}] [expr {1 << (($ctl >> 28) & 3)}] [expr {$ctl & 0xFFFF}] [expr {$lo & 1}] [expr {$hi & 0xFFFF}] [expr {($lo >> 16) & 0xFF}] \
    [expr {($lo >> 8) & 0xFF}] [expr {$hi >> 24}] [expr {(($ctl & 0xFFFF) - ($hi & 0xFFFF)) & 0xFFFF}]]
exit
