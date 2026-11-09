# trsnap.tcl — foto del trazador de bus de tr_cpu: descongela (trc_clr), espera, congela (frz_req) y vuelca
# MBOX+0x1000 rotado por el puntero de escritura. Uso: xsdb trsnap.tcl <fichero_salida> [io_only 0|1] [ms]
set MBOX 0x1FF00000
set out [lindex $argv 0]
set ioonly [expr {$argc > 1 ? [lindex $argv 1] : 0}]
set ms [expr {$argc > 2 ? [lindex $argv 2] : 200}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
set vc [lindex [mrd -value [expr {$MBOX + 0x2C}]] 0]
set vc [expr {($vc & ~0x4D) | ($ioonly ? 4 : 0)}]     ;# bit0=0 (bus), bit2=io_only, bit3=0, bit6=0
mwr [expr {$MBOX + 0x2C}] $vc
mwr [expr {$MBOX + 0x2C}] [expr {$vc | 0x40}]          ;# trc_clr 0->1
after 20                                                ;# el buzon sondea el registro cada ~1 ms: sin pausa, el flanco se pierde y se vuelca lo anterior
mwr [expr {$MBOX + 0x2C}] $vc                          ;# ->0
after $ms
mwr [expr {$MBOX + 0x2C}] [expr {$vc | 0x8}]           ;# frz_req 0->1
after 400                                               ;# el buzon tarda en volcar el anillo congelado (con 50 ms se leia el volcado anterior)
lassign [mrd -value [expr {$MBOX + 0x60}] 4] a b c d
puts [format "pcR=%04X pcZ=%04X sw=%d frz=%d wp=%d flags=%02X ioA=%04X" [expr {$a>>16}] [expr {$a&0xFFFF}] [expr {($d>>8)&127}] [expr {$d>>31}] [expr {($d>>16)&1023}] [expr {$d&255}] [expr {$b>>16}]]
set wp [expr {($d>>16)&1023}]
set v [mrd -value [expr {$MBOX + 0x1000}] 1024]
set fh [open $out w]
for {set i 0} {$i < 1024} {incr i} { set w [lindex $v [expr {($wp + $i) % 1024}]]
  set k [expr {$w >> 30}]; set cpu [expr {($w >> 29) & 1}]; set ad [expr {($w >> 12) & 0xFFFF}]; set dt [expr {($w >> 4) & 0xFF}]
  puts $fh [format "%s %s %04X %02X ram=%d m3=%d p3=%d e0=%d xf=%d" [expr {$cpu ? "R" : "Z"}] [lindex {M1 RD WR IO} $k] $ad $dt [expr {($w>>28)&1}] [expr {($w>>3)&1}] [expr {($w>>2)&1}] [expr {($w>>1)&1}] [expr {$w&1}]] }
close $fh
mwr [expr {$MBOX + 0x2C}] $vc
puts "OK $out"
exit
