# vsel.tcl — fuente de la HDMI desde el ARM (lo que hara el OSD del companion) por la palabra +0x2C del
# buzon (dbg_mailbox_axi.v) = {seq[15:8], 6'b0, auto_off[1], sel[0]}. top_zynq.v aplica sel (0 = V9968,
# 1 = V9990) cada vez que cambia seq; la tecla Pausa sigue conmutando a mano; y desde la build 14 (21/09)
# el AUTOMATICO: al encender el programa la pantalla del V9990 (R#8 bit 7) la HDMI pasa al V9990 y al
# apagarla (o resetear el MSX) vuelve al V9968. auto_off = 1 lo desactiva.
# Uso: xsdb.bat tools/vsel.tcl 0|1         fuerza la fuente (sube seq; deja auto_off como este)
#      xsdb.bat tools/vsel.tcl auto 0|1    apaga (0) o enciende (1) el automatico, sin forzar nada
#      xsdb.bat tools/vsel.tcl v9k 0|1     V9991 (28/10/2026): bit 3 = 1 fuerza el modo 3 del compositor
#                                          ("Video9000": el V9990 encima del V9968, transparente donde
#                                          YSE = 1 y el bit YS de la paleta); 0 = modos 0/1 segun sel
# El estado real de la HDMI sale en tel.tcl (+0x60 bit 31) y aqui tras el cambio.
set MBOX 0x1FF00000
if {[llength $argv] < 1} { puts "uso: vsel.tcl 0|1  |  vsel.tcl auto 0|1  |  vsel.tcl v9k 0|1"; exit 1 }
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
set cur [mrd -value [expr {$MBOX + 0x2C}]]
if {[lindex $argv 0] eq "v9k"} {
    set on [expr {[lindex $argv 1] & 1}]
    set new [expr {($cur & 0xFFF7) | ($on ? 8 : 0)}]          ;# solo el bit3, seq intacto
    mwr [expr {$MBOX + 0x2C}] $new
    puts [format "vsel: modo Video9000 %s (palabra %04X)" [expr {$on ? "ON" : "OFF"}] $new]
} elseif {[lindex $argv 0] eq "auto"} {
    set on [expr {[lindex $argv 1] & 1}]
    set new [expr {($cur & 0xFFFD) | ($on ? 0 : 2)}]          ;# solo el bit1, seq intacto
    mwr [expr {$MBOX + 0x2C}] $new
    puts [format "vsel: automatico %s (palabra %04X)" [expr {$on ? "ON" : "OFF"}] $new]
} else {
    set sel [expr {[lindex $argv 0] & 1}]
    set seq [expr {(($cur >> 8) + 1) & 0xFF}]
    mwr [expr {$MBOX + 0x2C}] [expr {($seq << 8) | ($cur & 2) | $sel}]
    after 20
    set d4 [mrd -value [expr {$MBOX + 0x60}]]
    puts [format "vsel: pedido %s (seq %d); HDMI muestra ahora %s" [expr {$sel ? "V9990" : "V9968"}] $seq [expr {($d4 >> 31) & 1 ? "V9990" : "V9968"}]]
}
