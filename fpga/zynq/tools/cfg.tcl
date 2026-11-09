# cfg.tcl — config persistente (16/09): mira y simula el bloque de config del buzon.
#   xsdb.bat tools/cfg.tcl show                      control (+0x1C) y bloque vigente (+0x70)
#   xsdb.bat tools/cfg.tcl set <c1> <c2> <turbo> <gain>   pone el bloque en +0x1C[28:8] con valid=1
#                                                     (lo que hace el companion al arrancar; hay que
#                                                     hacerlo con MSX_RUN=0 para que el PL lo siembre)
#   xsdb.bat tools/cfg.tcl mix <psg> <scc> <opll> <msxaudio> <opl4fm> <opl4wave> <wavegame>
#                                                   niveles 0..8 (8 = x1) -> +0x24 con valid=1 (V3.7; el PL
#                                                   los siembra con MSX_RUN=0; con el MSX corriendo usar
#                                                   el menu o key.tcl: OUT #44)
# Bits del control: 0 MSX_RUN, 1 trace_arm, [15:8] config1, [23:16] config2, [24] turbo,
# [27:25] gain, [28] valid.
set MBOX 0x1FF00000
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set cmd [lindex $argv 0]
if {$cmd eq "set"} {
    set c1 [lindex $argv 1]; set c2 [lindex $argv 2]; set tb [lindex $argv 3]; set gn [lindex $argv 4]
    set ctl [mrd -value [expr {$MBOX + 0x1C}]]
    set ctl [expr {($ctl & 0x3) | (($c1 & 255) << 8) | (($c2 & 255) << 16) | (($tb & 1) << 24) | (($gn & 7) << 25) | (1 << 28)}]
    mwr [expr {$MBOX + 0x1C}] $ctl
    puts [format "control <= %08X" $ctl]
}
if {$cmd eq "mix"} {
    set m 0
    for {set c 0} {$c < 7} {incr c} { set m [expr {$m | (([lindex $argv [expr {$c + 1}]] & 15) << (4 * $c))}] }
    mwr [expr {$MBOX + 0x24}] [expr {$m | (1 << 31)}]
    puts [format "mezclador +0x24 <= %08X" [expr {$m | (1 << 31)}]]
}
set ctl [mrd -value [expr {$MBOX + 0x1C}]]
set tel [mrd -value [expr {$MBOX + 0x70}]]
set mix [mrd -value [expr {$MBOX + 0x24}]]
set mtl [mrd -value [expr {$MBOX + 0xC0}]]
proc mixstr {m} {
    set nom {PSG SCC OPLL MSX-AUDIO OPL4fm OPL4wave WaveGame}
    set s ""
    for {set c 0} {$c < 7} {incr c} { append s [format " %s=%d/8" [lindex $nom $c] [expr {($m >> (4 * $c)) & 15}]] }
    return $s
}
puts [format "control +0x1C = %08X: MSX_RUN=%d trace=%d config1=%02X config2=%02X turbo=%d gain=%d valid=%d" \
    $ctl [expr {$ctl & 1}] [expr {($ctl >> 1) & 1}] [expr {($ctl >> 8) & 255}] [expr {($ctl >> 16) & 255}] \
    [expr {($ctl >> 24) & 1}] [expr {($ctl >> 25) & 7}] [expr {($ctl >> 28) & 1}]]
puts [format "vigente +0x70 = %08X: config1=%02X config2=%02X turbo=%d gain=%d toggle=%d" \
    $tel [expr {$tel & 255}] [expr {($tel >> 8) & 255}] [expr {($tel >> 16) & 1}] [expr {($tel >> 17) & 7}] [expr {($tel >> 31) & 1}]]
puts [format "mezclador siembra +0x24 = %08X: valid=%d%s" $mix [expr {($mix >> 31) & 1}] [mixstr $mix]]
puts [format "mezclador guardado +0xC0 = %08X: toggle=%d%s" $mtl [expr {($mtl >> 31) & 1}] [mixstr $mtl]]
exit
