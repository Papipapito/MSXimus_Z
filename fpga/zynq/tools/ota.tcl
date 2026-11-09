# ota.tcl — la actualizacion por red (companion/ota.c) desde XSDB, sin teclado: manda la tecla al companion por
# MBOX+0x3C (osd.c la reparte como si fuera del teclado USB) y enseña el final del log del ARM.
# Uso: xsdb.bat tools/ota.tcl U|I|R|F|log [n_chars=900]
#   U buscar   I instalar   R reiniciar (prueba la B)   F volver a la de fabrica (mandarla DOS veces)   log solo mirar
# Para verlo en la tele: tools/osd.tcl on (el OSD congela el Z80).
set KEY 0x1FF0003C
set LOG 0x1FF00800
set LOGSZ 0x700
set tecla [string toupper [lindex $argv 0]]
set n [expr {$argc > 1 ? [lindex $argv 1] : 900}]
array set uso {U 0x18 I 0x0C R 0x15 F 0x09}
connect -url tcp:127.0.0.1:3121
if {[catch { targets -set -filter {name =~ "ARM*#1"}; catch {stop}; mrd -value $LOG }]} { targets -set -filter {name =~ "APU*"} }
if {[info exists uso($tecla)]} {
    mwr $KEY $uso($tecla)
    puts "tecla $tecla enviada"
    after 1500
} elseif {$tecla ne "LOG"} { puts "uso: ota.tcl U|I|R|F|log"; exit 1 }
set h [mrd -value $LOG 2]
set wr [lindex $h 1]
if {[lindex $h 0] != 0x474F4C41} { puts "sin log del ARM"; exit }
set start [expr {$wr > $n ? $wr - $n : 0}]
if {$wr > $LOGSZ && $start < $wr - $LOGSZ} { set start [expr {$wr - $LOGSZ}] }
set w [mrd -value [expr {$LOG + 8}] [expr {$LOGSZ / 4}]]
set txt ""
for {set i $start} {$i < $wr} {incr i} {
    set j [expr {$i % $LOGSZ}]
    append txt [format %c [expr {([lindex $w [expr {$j / 4}]] >> (($j % 4) * 8)) & 255}]]
}
puts "---- log del ARM ----"
puts -nonewline $txt
exit
