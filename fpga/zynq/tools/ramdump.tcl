# ramdump.tcl — vuelca la RAM del mapper (256 KB en 0x10800000) a un fichero. Uso: xsdb ramdump.tcl <fichero>
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
mrd -bin -file [lindex $argv 0] 0x10800000 65536
puts "OK"
exit
