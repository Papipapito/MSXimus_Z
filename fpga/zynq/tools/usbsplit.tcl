# usbsplit.tcl — ¿el EHCI sigue ejecutando los QH con split? Muestrea 6 veces cada QH periodico FS/LS en uso: token,
# punteros de buffer 0/1/2 (C-prog-mask, S-bytes y FrameTag, que el controlador reescribe en cada trama) y el alt-next.
# Con el EHCI sano el FrameTag y el SplitX (token bit 1) cambian de una muestra a otra; congelados = motor periodico colgado
# (es la firma que vigila ehci_split_signature en arm/tinyusb-zynq7000.patch). Solo lecturas, por el core 1 parado.
# Los QH se buscan solos: ehci_data empieza en PERIODICLISTBASE (0xE0002154) y qhd_pool en +0x360 (65 QH de 64 B con
# CFG_TUH_DEVICE_MAX = 4, CFG_TUH_HUB = 1, CFG_TUH_ENDPOINT_MAX = 16 de tusb_config.h; si cambian, cambia este desplazamiento).
# Uso: xsdb.bat tools/usbsplit.tcl
connect -url tcp:127.0.0.1:3121
after 300
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set QHD_MAX 65
set base [expr {[mrd -value 0xE0002154] & 0xFFFFF000}]
set pool [expr {$base + 0x360}]
# QH periodicos con split en uso: {direccion etiqueta ...}
proc qh_split {pool n} {
    set d [mrd -value $pool [expr {$n * 16}]]
    set r {}
    for {set i 0} {$i < $n} {incr i} {
        set w [lrange $d [expr {$i * 16}] [expr {$i * 16 + 15}]]
        set c1 [lindex $w 1]; set c2 [lindex $w 2]; set u [lindex $w 12]
        if {!($u & 0xFF) || ($u & 0xFF00) || !($c2 & 0xFF)} continue       ;# usado, sin retirar, con S-mask
        if {(($c1 >> 12) & 3) == 2} continue                                 ;# alta velocidad: sin split
        lappend r [format %08X [expr {$pool + 64 * $i}]] [format "d%d.e%d" [expr {$c1 & 0x7F}] [expr {($c1 >> 8) & 15}]]
    }
    return $r
}
set lista [qh_split $pool $QHD_MAX]
puts [format "ehci_data %08X, qhd_pool %08X: %d QH con split en uso" $base $pool [expr {[llength $lista] / 2}]]
foreach {a n} $lista {
    for {set k 0} {$k < 6} {incr k} {
        set d [mrd -value 0x$a 12]
        puts [format "%-7s alt %08X tok %08X buf0 %08X buf1 %08X buf2 %08X | FRINDEX %08X" $n [lindex $d 5] [lindex $d 6] [lindex $d 7] [lindex $d 8] [lindex $d 9] [mrd -value 0xE000214C]]
        after 37
    }
}
puts "PORTSC [format %08X [mrd -value 0xE0002184]] USBSTS [format %08X [mrd -value 0xE0002144]] USBCMD [format %08X [mrd -value 0xE0002140]]"
puts "frame list: [mrd -value $base 8]"
puts "log escrito: [lindex [mrd -value 0x1FF00800 2] 1] bytes"
exit
