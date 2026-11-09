# fps_sample.tcl — muestrea (magia de demo, contador de cuadros) en C104h/C100h del Z80 (DDR 0x10800104/0x10800100)
# cada P segundos durante N muestras y calcula cuadros/s por demo entre muestras consecutivas con la misma magia.
# Uso: xsdb.bat fps_sample.tcl [muestras] [periodo_s]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
set n [expr {$argc > 0 ? [lindex $argv 0] : 40}]
set p [expr {$argc > 1 ? [lindex $argv 1] : 4}]
array set NOM {3301 msximus 3302 msximus_hs 3303 faces 3304 faces_hs 3305 tex 3306 wire 3307 wire_hs}
set pm -1; set pc 0; set pt 0
array set acc {}
for {set i 0} {$i < $n} {incr i} {
    set c [expr {[mrd -value 0x10800100] & 0xFFFFFFFF}]
    set m [expr {[mrd -value 0x10800104] & 0xFFFF}]
    set t [clock milliseconds]
    set nom [expr {[info exists NOM([format %04x $m])] ? $NOM([format %04x $m]) : [format %04x $m]}]
    if {$m == $pm && $c > $pc && $c < 512} {
        set fps [expr {1000.0 * ($c - $pc) / ($t - $pt)}]
        puts [format "  %-11s %4d -> %4d cuadros en %5.2f s = %6.2f cuadros/s (%6.2f ms)" $nom $pc $c [expr {($t - $pt) / 1000.0}] $fps [expr {1000.0 / $fps}]]
        lappend acc($nom) $fps
    } else {
        puts [format "  %-11s contador %d (nueva demo o parada)" $nom $c]
    }
    set pm $m; set pc $c; set pt $t
    after [expr {$p * 1000}]
}
puts "RESUMEN (media de los tramos validos):"
foreach k [lsort [array names acc]] {
    set s 0.0; foreach v $acc($k) { set s [expr {$s + $v}] }
    puts [format "  %-11s %6.2f cuadros/s  (%d tramos)" $k [expr {$s / [llength $acc($k)]}] [llength $acc($k)]]
}
