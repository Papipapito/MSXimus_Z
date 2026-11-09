# usbreset.tcl — fuerza el reinicio del USB host del companion: la misma recuperacion que hace el vigilante del EHCI
# (arm/companion/usb_host.c, usb_reinicia) cuando ve el controlador colgado: suelta teclas, raton y mandos del buzon, tuh_deinit,
# reset de USB0 por el SLCR y del PHY, y vuelve a enumerar el hub entero. Para probar la recuperacion sin esperar al cuelgue.
# Hace falta un companion de una build con el vigilante (si no, nadie atiende la palabra y el script lo dice).
# Uso: xsdb.bat tools/usbreset.tcl [espera_s=4]
#   Escribe la magia 'USBR' (0x52425355) en MBOX+0xFF0 (0x1FF00FF0); el companion la pone a cero al atenderla. Pasados
#   [espera_s] segundos saca el estado del USB0 (USBCMD / USBSTS / FRINDEX / PORTSC) y el final del log del ARM. Tiene que
#   salir "USB: forzado por JTAG (n), reinicio del controlador", los dispositivos quitados, "USB host: OK", "USB: reinicio
#   hecho en ... ms" y los dispositivos montados de nuevo. Un EHCI colgado de verdad deja la misma traza, con "USB: EHCI
#   colgado (n), ..." en la primera linea. El contador n tambien sale en la pagina de informacion del OSD (F12): "USB reiniciado: n".
set espera [expr {$argc > 0 ? [lindex $argv 0] : 4}]
set ADDR  0x1FF00FF0
set MAGIA 0x52425355
set LOG   0x1FF00800
set LOGSZ 0x700
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
proc h {a} { return [format %08X [mrd -value $a]] }
proc usb0 {} {
    return [format "USBCMD %s USBSTS %s FRINDEX %s PORTSC %s" [h 0xE0002140] [h 0xE0002144] [h 0xE000214C] [h 0xE0002184]]
}
proc logtail {n} {
    global LOG LOGSZ
    set hd [mrd -value $LOG 2]
    if {[lindex $hd 0] != 0x474F4C41} { return "(sin log del ARM)" }
    set wr [lindex $hd 1]
    set start [expr {$wr > $n ? $wr - $n : 0}]
    if {$wr > $LOGSZ && $start < $wr - $LOGSZ} { set start [expr {$wr - $LOGSZ}] }
    set w [mrd -value [expr {$LOG + 8}] [expr {$LOGSZ / 4}]]
    set txt ""
    for {set i $start} {$i < $wr} {incr i} {
        set j [expr {$i % $LOGSZ}]
        append txt [format %c [expr {([lindex $w [expr {$j / 4}]] >> (($j % 4) * 8)) & 255}]]
    }
    return $txt
}
puts "antes:   [usb0]"
puts "buzon HID: kbd [h 0x1FF00000] [h 0x1FF00004] [h 0x1FF00008] [h 0x1FF0000C] joy [h 0x1FF00010] raton [h 0x1FF00014] [h 0x1FF00018]"
set t0 [clock milliseconds]
mwr $ADDR $MAGIA
set atendido 0
for {set i 0} {$i < 100} {incr i} {
    after 50
    if {[mrd -value $ADDR] == 0} { set atendido 1; break }
}
if {!$atendido} {
    mwr $ADDR 0                       ;# que una build antigua no lo vea mas tarde
    puts "NO atendido en 5 s: el companion no corre o es de una build sin el vigilante (la palabra se ha vuelto a poner a cero)"
    exit 1
}
puts "atendido a los [expr {[clock milliseconds] - $t0}] ms (el reinicio dura unas decimas de segundo; los dispositivos tardan unos segundos en volver)"
after [expr {int($espera * 1000)}]
puts "despues: [usb0]"
puts "---- log del ARM (ultimos 1200 B) ----"
puts -nonewline [logtail 1200]
puts "----"
exit
