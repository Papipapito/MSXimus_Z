# msxreset.tcl — reset del MSX solo (MSX_RUN 0 -> 1 en MBOX+0x1C), sin tocar el PS ni la FPGA.
# El companion sigue sirviendo la SD y el pack sigue en la DDR. La RAM del Z80 se conserva (como el
# boton de reset); con -cold se ponen a cero los 64 KB principales (arranque frio: sin banderas
# del menu ni firmas de juego). Uso: xsdb.bat tools/msxreset.tcl [-cold]
set MBOX 0x1FF00000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
# 25/09: solo el bit 0 (MSX_RUN); el resto de la palabra (bit 3 = UART del ESP en la UART1 del PS, bits 28-8 =
#   siembra de la config) es del companion y pisarlo dejaba al MSX sin "ESP" tras el reset.
set ctl [mrd -value [expr {$MBOX + 0x1C}]]
mwr [expr {$MBOX + 0x1C}] [expr {$ctl & ~1}]
after 100
if {$argc > 0 && [lindex $argv 0] eq "-cold"} { mwr -force 0x10800000 [lrepeat 16384 0] 16384; mwr -force 0x10280000 [lrepeat 65536 0] 65536; puts "RAM y VRAM a cero" }
mwr [expr {$MBOX + 0x1C}] [expr {$ctl | 1}]
puts "MSX_RESET_OK"
exit
