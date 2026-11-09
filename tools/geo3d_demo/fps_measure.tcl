# fps_measure.tcl — lee el contador de cuadros de las demos _fps (C100h del Z80 = DDR 0x10800100, magia 'G3' en C104h)
# dos veces con N segundos de por medio y da los cuadros por segundo. Uso: xsdb.bat fps_measure.tcl [segundos] [etiqueta]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
set secs [expr {$argc > 0 ? [lindex $argv 0] : 20}]
set tag  [expr {$argc > 1 ? [lindex $argv 1] : "demo"}]
proc cnt {} {
    set lo [mrd -value 0x10800100]
    set hi [mrd -value 0x10800104]
    return [list [expr {$lo & 0xFFFFFFFF}] [expr {$hi & 0xFFFF}]]
}
lassign [cnt] c1 m1
set t1 [clock milliseconds]
after [expr {$secs * 1000}]
lassign [cnt] c2 m2
set t2 [clock milliseconds]
set dt [expr {($t2 - $t1) / 1000.0}]
set df [expr {$c2 - $c1}]
puts [format "FPS %s: magia %04x/%04x  cuadros %u -> %u  (%u en %.2f s) = %.2f cuadros/s  (%.2f ms/cuadro)" \
      $tag $m1 $m2 $c1 $c2 $df $dt [expr {$df / $dt}] [expr {$df > 0 ? 1000.0 * $dt / $df : 0}]]
