# vdpsnap.tcl — trazador del V9968 en modo circular (perfil TR): arma el anillo sin las escrituras de VRAM (MBOX+0x2C bit 5),
# espera a que se congele solo (R2LATE: R#2 escrito fuera de su ventana; r1_run; r2_bad) o lo congela por JTAG al agotar el
# tiempo, y vuelca los 1024 eventos rotados por el puntero (+0x68 bits 9:0) decodificados.
# Uso: xsdb.bat tools/vdpsnap.tcl <salida> [segundos_max] [con_vram 0|1]
set MBOX 0x1FF00000
set out [lindex $argv 0]
set smax [expr {$argc > 1 ? [lindex $argv 1] : 20}]
set vram [expr {$argc > 2 ? [lindex $argv 2] : 0}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set vc [lindex [mrd -value [expr {$MBOX + 0x2C}]] 0]
set vc [expr {($vc & ~0x29) | 1 | ($vram ? 0 : 0x20)}]     ;# bit0 = volcado del VDP, bit3 = 0 (sin congelar), bit5 = sin VRAM
mwr [expr {$MBOX + 0x2C}] $vc
mwr [expr {$MBOX + 0x1000 + 0xFF8}] {0 0} 2
set ctl [mrd -value [expr {$MBOX + 0x1C}]]
mwr [expr {$MBOX + 0x1C}] [expr {$ctl & ~2}]
after 5
mwr [expr {$MBOX + 0x1C}] [expr {$ctl | 2}]
set t0 [clock milliseconds]
set frozen 0
while {[clock milliseconds] - $t0 < $smax * 1000} {
    after 100
    set w [mrd -value [expr {$MBOX + 0x1000 + 0xFF8}] 2]
    if {[lindex $w 1] != 0} { set frozen 1; break }
}
if {!$frozen} { puts "sin disparo en $smax s: congelo por JTAG"; mwr [expr {$MBOX + 0x2C}] [expr {$vc | 8}]; after 300 }
set wp [expr {[lindex [mrd -value [expr {$MBOX + 0x68}]] 0] & 0x3FF}]
set v [mrd -value [expr {$MBOX + 0x1000}] 1024]
mwr [expr {$MBOX + 0x1C}] [expr {$ctl & ~2}]
mwr [expr {$MBOX + 0x2C}] [expr {$vc & ~9}]
set fh [open $out w]
puts $fh "disparo=$frozen wp=$wp"
set names {W99 R99 W9B INT+ INT- VS W98 R98}
set pend -1; set r15 0
for {set i 0} {$i < 1024} {incr i} {
    set e [lindex $v [expr {($wp + $i) % 1024}]]
    set evt [expr {($e >> 29) & 7}]; set line [expr {($e >> 20) & 511}]; set dat [expr {($e >> 12) & 255}]; set hpos [expr {$e & 4095}]
    set txt ""
    switch $evt {
        0 { if {$pend < 0} { set pend $dat } else {
                if {$dat & 0x80} { set r [expr {$dat & 0x3F}]; set txt [format "R#%-2d <= %02X" $r $pend]; if {$r == 15} { set r15 [expr {$pend & 15}] }
                } else { set txt [format "VRAM <= %02X%02X %s" [expr {$dat & 0x3F}] $pend [expr {($dat & 0x40) ? "W" : "R"}]] }
                set pend -1 } }
        1 { set txt [format "S#%d = %02X" $r15 $dat] }
        2 { set txt [format "9Bh <= %02X" $dat] }
    }
    puts $fh [format "%4d %-4s l=%3d h=%4d %02X  %s" $i [lindex $names $evt] $line $hpos $dat $txt]
}
close $fh
puts "OK $out disparo=$frozen"
exit
