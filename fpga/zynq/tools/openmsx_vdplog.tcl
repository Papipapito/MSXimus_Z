# openmsx_vdplog.tcl — diagnostico de VDP en openMSX: registra CADA escritura a los registros
# que hacen los "splits" y el scroll (R#0 IE1, R#1, R#2 tabla de nombres, R#9, R#19 linea de
# interrupcion, R#23 desplazamiento vertical), tanto por el puerto 99h como por el 9Bh
# (indirecto via R#17), con el instante emulado; y en los momentos que se le digan vuelca los
# 24 registros, los 128 KB de VRAM y una captura. Con eso se ve como dibuja un juego su
# marcador y se compara con lo que hace el V9968 (15/09: Xevious, R#2=FFh = pagina 3 con
# A17 ignorado en un V9958 real).
#
# Uso (PowerShell/bash), desde el directorio de salida:
#   "C:/Program Files/openMSX/openmsx.exe" -machine C-BIOS_MSX2+ -carta juego.rom \
#       -script openmsx_vdplog.tcl
# Edita abajo la linea de tiempos: pulsaciones (press fila mascara) y volcados (dump etiqueta).
# SPACE = fila 8 mascara 01; RETURN = fila 7 mascara 80. Salida: vdp_log.txt, vram_<tag>.bin
# y las capturas en la carpeta screenshots de openMSX.
set D [pwd]
set fh [open "$D/vdp_log.txt" w]
proc lg {s} { global fh; puts $fh "[format %9.4f [machine_info time]] $s"; flush $fh }
set ::p99 {}
set ::r17 0
debug set_watchpoint write_io 0x99 {} {
    set v $::wp_last_value
    if {$::p99 eq {}} {
        set ::p99 $v
    } else {
        if {$v & 0x80} {
            set r [expr {$v & 0x3F}]
            if {$r == 17} { set ::r17 $::p99 }
            if {$r in {0 1 2 9 19 23}} { lg "R#$r <= [format %3d $::p99] ([format %02X $::p99])" }
        }
        set ::p99 {}
    }
}
debug set_watchpoint write_io 0x9B {} {
    set r [expr {$::r17 & 0x3F}]
    if {$r in {0 1 2 9 19 23}} { lg "9B: R#$r <= [format %3d $::wp_last_value]" }
    if {!($::r17 & 0x80)} { set ::r17 [expr {($::r17 & 0xC0) | (($::r17 + 1) & 0x3F)}] }
}
proc press {row mask} { keymatrixdown $row $mask; after time 0.15 "keymatrixup $row $mask" }
proc dump {tag} {
    global D
    set regs {}
    for {set r 0} {$r < 24} {incr r} { lappend regs [format %02X [debug read "VDP regs" $r]] }
    lg "REGS($tag): $regs"
    set f [open "$D/vram_$tag.bin" wb]
    puts -nonewline $f [debug read_block VRAM 0 0x20000]
    close $f
    screenshot -prefix "vdplog_$tag"
    lg "dump $tag hecho"
}
lg "arranque"
# ---- linea de tiempos (la del Xevious Fardraut Saga: llega a la partida a los ~33 s) ----
after time 8  {press 8 0x01}
after time 12 {press 8 0x01}
after time 16 {press 8 0x01}
after time 20 {press 8 0x01}
after time 24 {press 8 0x01}
after time 28 {press 7 0x80}
after time 32 {press 8 0x01}
after time 36 {dump t36}
after time 38 {lg "fin"; close $fh; exit}
