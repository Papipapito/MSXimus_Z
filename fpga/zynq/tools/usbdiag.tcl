# usbdiag.tcl — estado del USB host del companion sin tocar nada (solo lecturas; el core 0 se para un instante
# para muestrear el PC y sigue): registros del EHCI, buzon HID, log del ARM y 5 muestras del PC/LR del core 0.
# Si FRINDEX no cambia, el controlador esta parado; si cambia y los teclados no responden, mirar usbsplit.tcl / usbqh.tcl.
# Uso: xsdb.bat tools/usbdiag.tcl
connect -url tcp:127.0.0.1:3121
after 300
puts "---- targets ----"
puts [targets]
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
proc r {a} { return [format %08X [mrd -value $a]] }
puts "---- EHCI USB0 ----"
puts "USBCMD   [r 0xE0002140]  USBSTS [r 0xE0002144]  USBINTR [r 0xE0002148]  FRINDEX [r 0xE000214C]"
puts "PERIODIC [r 0xE0002154]  ASYNC  [r 0xE0002158]  PORTSC  [r 0xE0002184]  USBMODE [r 0xE00021A8]"
after 200
puts "FRINDEX otra vez [r 0xE000214C] (si no cambia, el controlador esta parado)"
puts "---- buzon HID (MBOX) ----"
puts "kbd [r 0x1FF00000] [r 0x1FF00004] [r 0x1FF00008] [r 0x1FF0000C]  joy [r 0x1FF00010]  mouse [r 0x1FF00014] [r 0x1FF00018]"
set LOG 0x1FF00800; set LOGSZ 0x700; set n 1600
set h [mrd -value $LOG 2]
set wr [lindex $h 1]
set start [expr {$wr > $n ? $wr - $n : 0}]
if {$wr > $LOGSZ && $start < $wr - $LOGSZ} { set start [expr {$wr - $LOGSZ}] }
set w [mrd -value [expr {$LOG + 8}] [expr {$LOGSZ / 4}]]
set txt ""
for {set i $start} {$i < $wr} {incr i} {
    set j [expr {$i % $LOGSZ}]
    set b [expr {([lindex $w [expr {$j / 4}]] >> (($j % 4) * 8)) & 255}]
    append txt [format %c $b]
}
puts "---- log del ARM (magic [format %08X [lindex $h 0]], $wr bytes) ----"
puts $txt
puts "---- PC del core 0 (5 muestras) ----"
targets -set -filter {name =~ "ARM*#0"}
for {set k 0} {$k < 5} {incr k} {
    catch {stop}
    after 20
    set pc "?"; set lr "?"
    catch { set pc [rrd -novalue pc] }
    catch { set pc [rrd pc] }
    catch { set lr [rrd lr] }
    puts "$pc | $lr"
    catch {con}
    after 150
}
exit
