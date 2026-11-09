# usblinks.tcl — enlaces horizontales de todos los QH del EHCI (cabezas periodicas, QH de control y reserva) y estado de los
# qTD en uso de la reserva: un qTD que aparece como Next/current de dos QH es el fallo de la carrera de qhd_xfer_complete_isr
# (arreglada en arm/tinyusb-zynq7000.patch). Solo lecturas, por el core 1 parado.
# Las direcciones salen de PERIODICLISTBASE (0xE0002154) = ehci_data: period_head_arr en +0x20 (4 QH), control[] en +0x120
# (6 x 96 B, QH + qTD), qhd_pool en +0x360 (65 QH de 64 B) y qtd_pool en +0x13A0 (65 qTD de 32 B), con CFG_TUH_DEVICE_MAX = 4,
# CFG_TUH_HUB = 1 y CFG_TUH_ENDPOINT_MAX = 16 (tusb_config.h); si cambian, cambian estos desplazamientos.
# Uso: xsdb.bat tools/usblinks.tcl
connect -url tcp:127.0.0.1:3121
after 300
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set base [expr {[mrd -value 0xE0002154] & 0xFFFFF000}]
puts [format "ehci_data %08X" $base]
puts "---- QH: dw0 (enlace) dw1 dw2 dw3 (cur) | overlay next alt tok ----"
proc qh {a nombre} {
    set d [mrd -value $a 7]
    puts [format "QH %08X %-9s: %08X %08X %08X %08X | %08X %08X %08X" $a $nombre {*}$d]
}
for {set i 0} {$i < 4} {incr i} { qh [expr {$base + 0x20 + 0x40 * $i}] "cabeza$i" }
for {set i 0} {$i < 6} {incr i} { qh [expr {$base + 0x120 + 0x60 * $i}] "control$i" }
set pool [expr {$base + 0x360}]
set d [mrd -value $pool [expr {65 * 16}]]
for {set i 0} {$i < 65} {incr i} {
    if {[lindex $d [expr {$i * 16 + 12}]] & 0xFF} { qh [expr {$pool + 64 * $i}] "pool$i" }
}
puts "---- qTD en uso de la reserva (next alt tok buf0 | buf1 buf2 buf3) ----"
set q0 [expr {$base + 0x13A0}]
set d [mrd -value $q0 [expr {65 * 8}]]
for {set i 0} {$i < 65} {incr i} {
    set w [lrange $d [expr {$i * 8}] [expr {$i * 8 + 7}]]
    if {[lindex $w 1] & 0x20} {
        puts [format "qTD %08X: %08X %08X %08X %08X | %08X %08X %08X" [expr {$q0 + 32 * $i}] {*}[lrange $w 0 3] {*}[lrange $w 5 7]]
    }
}
exit
