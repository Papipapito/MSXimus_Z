# packswap.tcl — cambia el pack de BIOS EN CALIENTE, sin reprogramar la FPGA ni tocar el PS:
#   1) MSX_RUN=0 (MBOX+0x1C): el MSX entra en reset; con bus_reset_n=0 memory_axi invalida la cache
#   2) el pack nuevo a la DDR (0x10F00000, donde memory_axi mapea el banco D)
#   3) VRAM a cero (como el companion al arrancar) y los 64 KB de RAM principal del Z80 a cero:
#      la BIOS del menu guarda banderas en RAM que SOBREVIVEN al reset (BOOT_FLAG, DSK_PEND,
#      BOOT_SP/BOOT_RET en #E800+) y con otro pack debajo la llevaban a un bucle (15/09)
#   4) MSX_RUN=1: el MSX arranca con el BIOS nuevo como si fuera un arranque frio
# El companion sigue corriendo (sirve la SD). Sirve para iterar BIOS sin perder el JTAG, que se
# cae al reprogramar la FPGA. Uso: xsdb.bat tools/packswap.tcl <pack.bin>
set here [file dirname [file normalize [info script]]]
if {$argc < 1} { puts "Uso: packswap.tcl <pack.bin>"; exit 1 }
set pack [lindex $argv 0]
if {![file exists $pack]} { puts "ERROR: no existe $pack"; exit 1 }
set MBOX 0x1FF00000
set PACK 0x10F00000
set VRAM 0x10280000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
mwr [expr {$MBOX + 0x1C}] 0
after 100
puts "pack: $pack ([file size $pack] bytes) -> [format 0x%08X $PACK]"
mwr -bin -file $pack $PACK [expr {([file size $pack] + 3) / 4}]
set head [mrd -value $PACK 2]
puts [format "DDR: cabeza %08X %08X" [lindex $head 0] [lindex $head 1]]
mwr -force $VRAM [lrepeat 65536 0] 65536
mwr -force 0x10800000 [lrepeat 16384 0] 16384      ;# RAM principal (segmentos 0-3 del mapper, 64 KB)
mwr [expr {$MBOX + 0x1C}] 1
puts "PACKSWAP_OK: MSX arrancando con el pack nuevo"
exit
