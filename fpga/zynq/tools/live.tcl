connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
for {set k 0} {$k<12} {incr k} {
  lassign [mrd -value 0x1FF00060 4] a b c d
  set h [mrd -value 0x1FF00048 2]
  puts [format "pcR=%04X ioA=%04X busA=%04X ioD=%02X ext=%02X cntR=%u flags=%02X hits=%u miss=%u" [expr {$a>>16}] [expr {$b>>16}] [expr {$b&0xFFFF}] [expr {$c>>24}] [expr {($c>>16)&255}] [expr {$c&0xFFFF}] [expr {$d&255}] [lindex $h 0] [lindex $h 1]]
  after 300
}
