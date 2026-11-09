# tape.tcl — CINTA VIRTUAL (Z1.1) desde XSDB: estado del reproductor de pulsos del buzon y ordenes al companion.
#   xsdb.bat tools/tape.tcl                            estado: control +0x28 y telemetria +0xC8/+0xCC
#   xsdb.bat tools/tape.tcl msg <part_lba> <dir_clus> <file_clus>   como el menu: 'T','S' + clusters por el 93h
#   xsdb.bat tools/tape.tcl stop                       'T','X': parar la cinta
#   xsdb.bat tools/tape.tcl watch [n] [ms]             estado n veces
# Control +0x28 = {play[31], monitor[30], sin_motor[29], wr[15:0]}; +0xC8 = {rd[31:16], nivel FIFO[13:8], underruns[7:0]};
# +0xCC = {rafagas[31:24], ..., sin_motor[3], motor[2], nivel[1], play[0]}. El anillo vive en MBOX+0xA0000.
set MBOX 0x1FF00000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
proc inj {tag dat} {
    global MBOX
    set v [mrd -value [expr {$MBOX + 0x38}]]
    set seq [expr {(($v >> 24) + 1) & 0xFF}]
    mwr [expr {$MBOX + 0x38}] [expr {($seq << 24) | (($tag & 0xFF) << 8) | ($dat & 0xFF)}]
    after 15
}
proc estado {} {
    global MBOX
    set c [mrd -value [expr {$MBOX + 0x28}]]
    set t [mrd -value [expr {$MBOX + 0xC8}]]
    set s [mrd -value [expr {$MBOX + 0xCC}]]
    puts [format "control +0x28 = %08X: play=%d monitor=%d sin_motor=%d wr=%d | rd=%d FIFO=%d underruns=%d | rafagas=%d motor=%d nivel=%d play=%d" \
        $c [expr {($c >> 31) & 1}] [expr {($c >> 30) & 1}] [expr {($c >> 29) & 1}] [expr {$c & 0xFFFF}] \
        [expr {($t >> 16) & 0xFFFF}] [expr {($t >> 8) & 63}] [expr {$t & 255}] \
        [expr {($s >> 24) & 255}] [expr {($s >> 2) & 1}] [expr {($s >> 1) & 1}] [expr {$s & 1}]]
}
set cmd [lindex $argv 0]
if {$cmd eq "msg"} {
    set part [expr [lindex $argv 1]]; set dir [expr [lindex $argv 2]]; set file [expr [lindex $argv 3]]
    inj 0x93 0x54; inj 0x93 0x53
    foreach v [list $part $dir $file] { for {set k 0} {$k < 4} {incr k} { inj 0x93 [expr {($v >> (8 * $k)) & 0xFF}] } }
    puts [format "mensaje 'TS' part=%d dir=%d file=%d enviado" $part $dir $file]
    after 300
} elseif {$cmd eq "stop"} {
    inj 0x93 0x54; inj 0x93 0x58
    puts "mensaje 'TX' (parar) enviado"
    after 100
} elseif {$cmd eq "watch"} {
    set n [expr {$argc > 1 ? [lindex $argv 1] : 10}]
    set ms [expr {$argc > 2 ? [lindex $argv 2] : 1000}]
    for {set k 0} {$k < $n} {incr k} { estado; if {$k < $n - 1} { after $ms } }
    exit
}
estado
exit
