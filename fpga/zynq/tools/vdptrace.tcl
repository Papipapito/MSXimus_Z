# vdptrace.tcl — arma el trazador de I/O del V9968 (zynq/vdp_trace.v), espera a que llene su
# anillo de 1024 eventos y lo decodifica desde la DDR (el buzon lo vuelca en MBOX+0x1000 cada
# ~1 ms mientras esta lleno). Cada evento lleva la linea de pantalla (HS contados desde el VS)
# y la posicion horizontal (ciclos de clk_86/2 desde el HS; ~2736 por linea).
#
# Uso: xsdb.bat tools/vdptrace.tcl [fichero_salida]   (por defecto vdptrace.txt)
#   Las escrituras al puerto 99h se emparejan (dato, registro|80h) y se imprimen como
#   "R#n <= dd"; las lecturas como "S#p = dd" (p = ultimo R#15 visto en la traza).
set MBOX  0x1FF00000
set out   [expr {$argc > 0 ? [lindex $argv 0] : "vdptrace.txt"}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
# armar: bit 1 de la palabra de control (bit 0 = MSX_RUN, no tocar)
set ctl [mrd -value [expr {$MBOX + 0x1C}]]
# el volcado es de un disparo por captura: se borra la ultima palabra del volcado anterior para
# distinguir la captura nueva (el bucle de abajo espera a verla no nula y estable)
mwr [expr {$MBOX + 0x1000 + 0xFF8}] {0 0} 2
mwr [expr {$MBOX + 0x1C}] [expr {$ctl & ~2}]
after 5
mwr [expr {$MBOX + 0x1C}] [expr {$ctl | 2}]
# el buzon reescribe la traza vieja mientras el anillo nuevo se llena: esperamos a que el
# primer evento sea un VS (evt 5, linea 0) y que el ultimo no cambie entre dos lecturas
set last_ok 0
for {set i 0} {$i < 300} {incr i} {   ;# hasta 15 s: una pantalla quieta solo genera ~5 eventos por cuadro
    after 50
    set w [mrd -value [expr {$MBOX + 0x1000 + 0xFF8}] 2]
    set l [lindex $w 1]
    if {$l == $last_ok && $l != 0} { break }
    set last_ok $l
}
mwr [expr {$MBOX + 0x1C}] [expr {$ctl & ~2}]
set v [mrd -value [expr {$MBOX + 0x1000}] 1024]
set fh [open $out w]
set names {W1 R1 W3 INT+ INT- VS W0 UART}
set pend {}
set r15 0
set n 0
set ::uart_bytes {}
foreach e $v {
    set evt  [expr {($e >> 29) & 7}]
    set line [expr {($e >> 20) & 511}]
    set dat  [expr {($e >> 12) & 255}]
    set hpos [expr {$e & 4095}]
    set txt ""
    switch $evt {
        0 {
            if {$pend eq {}} { set pend $dat; set txt [format "99h <= %02X" $dat] } else {
                if {$dat & 0x80} {
                    set r [expr {$dat & 0x3F}]
                    set txt [format "R#%-2d <= %02X" $r $pend]
                    if {$r == 15} { set r15 [expr {$pend & 15}] }
                } else {
                    set txt [format "VRAM addr <= %02X%02X (%s)" [expr {$dat & 0x3F}] $pend [expr {($dat & 0x40) ? "write" : "read"}]]
                }
                set pend {}
            }
        }
        1 { set txt [format "S#%d = %02X" $r15 $dat] }
        2 { set txt [format "9Bh <= %02X" $dat] }
        3 { set txt "INT activa" }
        4 { set txt "INT inactiva" }
        5 { set txt "---- VS (cuadro nuevo) ----" }
        6 { set txt [format "98h <= %02X" $dat] }
        7 { set txt [format "UART ESP -> Z80: %02X %s" $dat [expr {($dat >= 32 && $dat < 127) ? [format "'%c'" $dat] : ""}]]; append ::uart_bytes [format %c $dat] }
        default { set txt [format "evt%d %02X" $evt $dat] }
    }
    puts $fh [format "%4d  L%3d.%4d  %s" $n $line $hpos $txt]
    incr n
}
close $fh
puts "traza: $n eventos -> $out"
if {[string length $::uart_bytes] > 0} {
    set shown [regsub -all {[^ -~]} $::uart_bytes .]
    puts "UART ESP -> Z80 ([string length $::uart_bytes] bytes): $shown"
}
exit
