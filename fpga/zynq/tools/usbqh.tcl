# usbqh.tcl — recorre la lista periodica y la asincrona del EHCI (solo lecturas, por el core 1 parado)
# y saca de cada QH: direccion, endpoint, velocidad, hub/puerto del TT, S/C-mask y el token del overlay.
# No usa direcciones fijas: parte de PERIODICLISTBASE (0xE0002154) y ASYNCLISTADDR (0xE0002158).
# Uso: xsdb.bat tools/usbqh.tcl
connect -url tcp:127.0.0.1:3121
after 300
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
proc w {a} { return [mrd -value $a] }
proc qh {a} {
    set d [mrd -value $a 12]
    set c1 [lindex $d 1]; set c2 [lindex $d 2]; set tok [lindex $d 6]
    set dev [expr {$c1 & 0x7F}]; set ep [expr {($c1 >> 8) & 0xF}]; set eps [expr {($c1 >> 12) & 3}]
    set mps [expr {($c1 >> 16) & 0x7FF}]
    set sm [expr {$c2 & 0xFF}]; set cm [expr {($c2 >> 8) & 0xFF}]; set hub [expr {($c2 >> 16) & 0x7F}]; set prt [expr {($c2 >> 23) & 0x7F}]
    set st [expr {$tok & 0xFF}]; set cerr [expr {($tok >> 10) & 3}]; set nb [expr {($tok >> 16) & 0x7FFF}]
    set fl ""
    foreach {b n} {7 ACTIVE 6 HALTED 5 BUFERR 4 BABBLE 3 XACTERR 2 MMF 1 SPLITX 0 PING/ERR} { if {$st & (1 << $b)} { append fl " $n" } }
    set sp [lindex {FS LS HS ?} $eps]
    puts [format "QH %08X dev %3d ep %d %s mps %3d smask %02X cmask %02X hub %d port %d | cur %08X next %08X tok %08X cerr %d bytes %d |%s" \
        $a $dev $ep $sp $mps $sm $cm $hub $prt [lindex $d 3] [lindex $d 4] $tok $cerr $nb $fl]
    puts [format "     extra: %08X %08X %08X %08X %08X %08X" [lindex $d 11] [w [expr {$a+48}]] [w [expr {$a+52}]] [w [expr {$a+56}]] [w [expr {$a+60}]] [w [expr {$a+64}]]]
    return [lindex $d 0]
}
set fl [expr {[w 0xE0002154] & 0xFFFFF000}]
puts [format "lista periodica en %08X, USBSTS %08X FRINDEX %08X" $fl [w 0xE0002144] [w 0xE000214C]]
set vistos {}
for {set i 0} {$i < 16} {incr i} {
    set l [w [expr {$fl + 4*$i}]]
    set k 0
    while {!($l & 1) && $k < 24} {
        set a [expr {$l & 0xFFFFFFE0}]
        if {[lsearch $vistos $a] >= 0} break
        lappend vistos $a
        if {(($l >> 1) & 3) != 1} { puts [format "  (tipo %d en %08X)" [expr {($l >> 1) & 3}] $a]; break }
        set l [qh $a]
        incr k
    }
}
puts "---- asincrona ----"
set a0 [expr {[w 0xE0002158] & 0xFFFFFFE0}]
set a $a0; set k 0
while {$k < 16} {
    set l [qh $a]
    set a [expr {$l & 0xFFFFFFE0}]
    incr k
    if {$a == $a0} break
}
exit
