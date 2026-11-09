# trpatch.tcl — escribe bytes en la DDR (p. ej. parchear la BIOS cargada por JTAG). Uso: xsdb trpatch.tcl <dir> <byte> [<dir> <byte> ...]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
foreach {a b} $argv { puts [format "antes %08X = %02X" $a [lindex [mrd -value -size b $a] 0]]; mwr -size b $a $b; puts [format "ahora %08X = %02X" $a [lindex [mrd -value -size b $a] 0]] }
exit
