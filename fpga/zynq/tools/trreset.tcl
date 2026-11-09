# trreset.tcl — arma el trazador de bus (solo E/S), hace un reset suave del MSX, espera y vuelca el trazador rotado
# y el anillo de saltos. Uso: xsdb trreset.tcl <salida> [ms_espera] [io_only]
set MBOX 0x1FF00000
set out [lindex $argv 0]
set ms [expr {$argc > 1 ? [lindex $argv 1] : 4000}]
set ioonly [expr {$argc > 2 ? [lindex $argv 2] : 1}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set vc [lindex [mrd -value [expr {$MBOX + 0x2C}]] 0]
set vc [expr {($vc & ~0x4D) | ($ioonly ? 4 : 0)}]
mwr [expr {$MBOX + 0x2C}] $vc
mwr [expr {$MBOX + 0x2C}] [expr {$vc | 0x40}]
mwr [expr {$MBOX + 0x2C}] $vc
set ctl [mrd -value [expr {$MBOX + 0x1C}]]
mwr [expr {$MBOX + 0x1C}] [expr {$ctl & ~1}]
after 100
mwr [expr {$MBOX + 0x1C}] [expr {$ctl | 1}]
puts "reset hecho"
after $ms
lassign [mrd -value [expr {$MBOX + 0x60}] 4] a b c d
puts [format "antes de congelar: pcR=%04X pcZ=%04X sw=%d frz=%d wp=%d flags=%02X ioA=%04X" [expr {$a>>16}] [expr {$a&0xFFFF}] [expr {($d>>8)&127}] [expr {$d>>31}] [expr {($d>>16)&1023}] [expr {$d&255}] [expr {$b>>16}]]
mwr [expr {$MBOX + 0x2C}] [expr {$vc | 0x8}]
after 50
lassign [mrd -value [expr {$MBOX + 0x60}] 4] a b c d
set wp [expr {($d>>16)&1023}]
set v [mrd -value [expr {$MBOX + 0x1000}] 1024]
set fh [open $out w]
for {set i 0} {$i < 1024} {incr i} { set w [lindex $v [expr {($wp + $i) % 1024}]]
  set k [expr {$w >> 30}]; set cpu [expr {($w >> 29) & 1}]; set ad [expr {($w >> 12) & 0xFFFF}]; set dt [expr {($w >> 4) & 0xFF}]
  puts $fh [format "%s %s %04X %02X ram=%d m3=%d p3=%d e0=%d xf=%d" [expr {$cpu ? "R" : "Z"}] [lindex {M1 RD WR IO} $k] $ad $dt [expr {($w>>28)&1}] [expr {($w>>3)&1}] [expr {($w>>2)&1}] [expr {($w>>1)&1}] [expr {$w&1}]] }
set r [mrd -value [expr {$MBOX + 0x78}] 16]
set s "anillo:"
foreach w $r { append s [format " %04X %04X" [expr {$w & 0xFFFF}] [expr {$w >> 16}]] }
puts $fh $s
close $fh
mwr [expr {$MBOX + 0x2C}] $vc
puts "OK $out"
exit
