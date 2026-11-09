# usbwatch.tcl — vigila [segundos=600] (cada ~100 ms) el buzon del teclado y los QH periodicos FS/LS en uso (teclados, ratones,
# mandos y el estado del hub); imprime solo lo que cambia: buzon, token y qTD actual de cada QH. Aparte avisa cuando el FrameTag
# de todos los QH (que el EHCI reescribe en cada trama) lleva 1,5 s sin cambiar, que es lo que vigila el companion para decidir
# que el EHCI esta colgado (ehci_split_signature, arm/tinyusb-zynq7000.patch), y cuando vuelve a moverse. Solo lecturas, por el
# core 1 parado.
# Los QH se buscan solos: ehci_data empieza en PERIODICLISTBASE (0xE0002154) y qhd_pool en +0x360 (65 QH de 64 B con
# CFG_TUH_DEVICE_MAX = 4, CFG_TUH_HUB = 1, CFG_TUH_ENDPOINT_MAX = 16 de tusb_config.h; si cambian, cambia este desplazamiento).
# Se eligen al empezar: un dispositivo que se enchufe despues no entra (volver a lanzar el script).
# Uso: xsdb.bat tools/usbwatch.tcl [segundos]
set dur [expr {$argc > 0 ? [lindex $argv 0] : 600}]
connect -url tcp:127.0.0.1:3121
after 300
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set QHD_MAX 65
set pool [expr {([mrd -value 0xE0002154] & 0xFFFFF000) + 0x360}]
# QH periodicos FS/LS en uso: {direccion etiqueta ...}; la etiqueta es d<dispositivo>.e<endpoint>
proc qh_split {pool n} {
    set d [mrd -value $pool [expr {$n * 16}]]
    set r {}
    for {set i 0} {$i < $n} {incr i} {
        set w [lrange $d [expr {$i * 16}] [expr {$i * 16 + 15}]]
        set c1 [lindex $w 1]; set c2 [lindex $w 2]; set u [lindex $w 12]
        if {!($u & 0xFF) || ($u & 0xFF00) || !($c2 & 0xFF)} continue
        if {(($c1 >> 12) & 3) == 2} continue
        lappend r [format %08X [expr {$pool + 64 * $i}]] [format "d%d.e%d" [expr {$c1 & 0x7F}] [expr {($c1 >> 8) & 15}]]
    }
    return $r
}
set qhs [qh_split $pool $QHD_MAX]
puts "vigilando [expr {[llength $qhs] / 2}] QH: $qhs"
set prev ""
set tags_prev ""
set congelado 0
set t0 [clock milliseconds]
set t_tags $t0
while {[clock milliseconds] - $t0 < $dur * 1000} {
    set m [mrd -value 0x1FF00000 7]
    set line [format "MBOX %08X %08X %08X %08X joy %08X mouse %08X %08X" {*}$m]
    set tags {}
    foreach {a n} $qhs {
        set d [mrd -value 0x$a 10]
        append line [format " | %s cur %08X tok %08X" $n [lindex $d 3] [lindex $d 6]]
        lappend tags [expr {[lindex $d 9] & 0x1F}]
    }
    set ahora [clock milliseconds]
    set seg [format %.3f [expr {($ahora - $t0) / 1000.0}]]
    if {$line ne $prev} {
        puts "$seg s: $line"
        set prev $line
    }
    if {$tags ne $tags_prev} {
        if {$congelado} { puts "$seg s: el FrameTag vuelve a moverse"; set congelado 0 }
        set tags_prev $tags
        set t_tags $ahora
    } elseif {!$congelado && [llength $tags] > 0 && $ahora - $t_tags > 1500} {
        puts "$seg s: FrameTag de los QH congelado desde hace 1,5 s ($tags) -> EHCI colgado"
        set congelado 1
    }
    after 100
}
puts "FIN"
exit
