# pkttrace.tcl — vuelca la traza de segmentos TCP del companion (net.c, NET_PKT_PORT: texto en la DDR 0x00E00000,
# 64 KB; magic 'APKT' + indice de escritura). Cada linea: R/T ms flags seq ack len ventana.
# Uso: xsdb.bat tools/pkttrace.tcl [n_chars=4000]
set n [expr {$argc > 0 ? [lindex $argv 0] : 4000}]
set BASE 0x00E00000
set SZ   [expr {0x10000 - 8}]
connect -url tcp:127.0.0.1:3121
if {[catch { targets -set -filter {name =~ "ARM*#1"}; mrd -value $BASE }]} { targets -set -filter {name =~ "APU*"} }
set h [mrd -value $BASE 2]
set magic [lindex $h 0]; set wr [lindex $h 1]
if {$magic != 0x544B5041} { puts "sin traza (magic [format %08X $magic])"; exit }
set start [expr {$wr > $n ? $wr - $n : 0}]
if {$wr > $SZ && $start < $wr - $SZ} { set start [expr {$wr - $SZ}] }
set w [mrd -value [expr {$BASE + 8}] [expr {$SZ / 4}]]
set txt ""
for {set i $start} {$i < $wr} {incr i} {
    set j [expr {$i % $SZ}]
    set b [expr {([lindex $w [expr {$j / 4}]] >> (($j % 4) * 8)) & 255}]
    append txt [format %c $b]
}
puts "---- traza TCP ($wr bytes) ----"
puts -nonewline $txt
exit
