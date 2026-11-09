# clear_megaram.tcl — pone a cero los primeros 64 KB de la megaram del MSXimus Z
# (DDR 0x10C00000): un ROM cargado por el menu se queda alli como un cartucho
# y la BIOS lo autoarranca en cada reset. Uso: xsdb wrap.tcl clear_megaram.tcl
connect
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
mwr -size w 0x10C00000 [lrepeat 16384 0]
puts "MEGARAM_CLEARED: 64 KB a cero en 0x10C00000"
exit
