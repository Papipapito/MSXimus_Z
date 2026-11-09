# medir_latencia.tcl — latencia de memoria de la CPU de A (memory_axi, HP1 @ clk_54m), leida del buzon de la DDR.
# Perfil TR, fase 0 (02/11/2026). Solo contadores en el PL (memory_axi.v: lat_tel / lat_clr): no cambian el comportamiento.
#
# Uso:  xsdb.bat tools/medir_latencia.tcl [segundos] [-leer | -clr]       (hw_server.bat aparte; el MSX ya arrancado)
#   segundos   ventana de medida tras la puesta a cero (por defecto 10). Mientras tanto hay que USAR el MSX
#              (juego, BASIC, MSX-DOS, un benchmark...): los contadores solo cuentan lecturas de RAM.
#   -clr       solo pone a cero (hits/miss incluidos) y sale.
#   -leer      solo lee lo acumulado (sin poner a cero).
#
# Que cuenta (ciclos de clk_54m = 18,52 ns, saturan en 4095), SOLO LECTURAS de la RAM del MSX por la cache de 64 KB:
#   total   : ram_req sube -> ram_busy baja. Un ACIERTO vale 4; en un FALLO es lo que ve la CPU (en el Z80 el CEN se recorta ese rato).
#   AR->R   : fallos: ARVALID sube -> llega la 2.a palabra de la linea (latencia pura HP1 + DDR del PS, linea de 16 B = 2 beats).
#   espera AR: fallos: ram_req sube -> sale el AR (barrera de escrituras en vuelo; normalmente 2).
# MBOX = 0x1FF00000. El PL escribe cada ~1 ms:
#   +0x48 {miss[63:32], hits[31:0]} (memory_axi.dbg_miss/dbg_hits; tambien se ponen a cero)
#   +0xD8 {suma total fallos[63:32], 0, max[27:16], 0, min[11:0]}   +0xE0 igual para AR->R   +0xE8 {suma espera AR, 0, max[27:16], 0, max acierto[11:0]}
#   +0xF0 histograma del total, cajones 0..3 (16 bits c/u, el 0 abajo)   +0xF8 cajones 4..7
#   cajones del total (ciclos): <16 | 16-19 | 20-23 | 24-27 | 28-31 | 32-39 | 40-63 | >=64
# La puesta a cero es el bit 5 de MBOX+0x1C (flanco de subida); se hace leer-modificar-escribir: el resto de la palabra es del companion.
set MBOX 0x1FF00000
set NS 18.5185
set secs 10
set modo medir
foreach a $argv {
    if {$a eq "-leer"} { set modo leer } elseif {$a eq "-clr"} { set modo clr } elseif {[string is double -strict $a]} { set secs $a }
}
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}

proc clr {MBOX} {
    set ctl [lindex [mrd -value [expr {$MBOX + 0x1C}]] 0]
    mwr -force [expr {$MBOX + 0x1C}] [expr {$ctl | 0x20}]
    after 20                                  ;# el PL lee el control cada ~1 ms
    set ctl [lindex [mrd -value [expr {$MBOX + 0x1C}]] 0]
    mwr -force [expr {$MBOX + 0x1C}] [expr {$ctl & ~0x20}]
    after 20
}

if {$modo ne "leer"} {
    clr $MBOX
    puts "contadores a cero"
    if {$modo eq "clr"} { exit }
}
if {$modo eq "medir"} {
    puts "midiendo $secs s: usa el MSX ahora..."
    after [expr {int($secs * 1000)}]
}

set m [mrd -value [expr {$MBOX + 0x48}] 2]
lassign $m hits miss
set w [mrd -value [expr {$MBOX + 0xD8}] 10]
lassign $w w0l w0h w1l w1h w2l w2h w3l w3h w4l w4h
set tmin [expr {$w0l & 0xFFF}]; set tmax [expr {($w0l >> 16) & 0xFFF}]; set tsum $w0h
set amin [expr {$w1l & 0xFFF}]; set amax [expr {($w1l >> 16) & 0xFFF}]; set asum $w1h
set hmax [expr {$w2l & 0xFFF}]; set wmax [expr {($w2l >> 16) & 0xFFF}]; set wsum $w2h
set hist [list [expr {$w3l & 0xFFFF}] [expr {($w3l >> 16) & 0xFFFF}] [expr {$w3h & 0xFFFF}] [expr {($w3h >> 16) & 0xFFFF}] \
               [expr {$w4l & 0xFFFF}] [expr {($w4l >> 16) & 0xFFFF}] [expr {$w4h & 0xFFFF}] [expr {($w4h >> 16) & 0xFFFF}]]
set nh 0; foreach h $hist { incr nh $h }
puts [format "lecturas de RAM: aciertos=%u fallos=%u  (tasa de fallos %.2f %%)" $hits $miss [expr {($hits + $miss) ? 100.0 * $miss / ($hits + $miss) : 0.0}]]
if {$nh == 0} { puts "sin fallos medidos (histograma vacio): el MSX no ha leido RAM no cacheada en la ventana, o el PL no es el de la fase 0"; exit }
puts [format "acierto: peor caso %d ciclos (%.0f ns)  (esperado 4 = 74 ns)" $hmax [expr {$hmax * $NS}]]
puts [format "FALLO, total visto por la CPU : min %d  media %.1f  max %d ciclos  = %.0f / %.0f / %.0f ns" \
    $tmin [expr {double($tsum) / $nh}] $tmax [expr {$tmin * $NS}] [expr {double($tsum) / $nh * $NS}] [expr {$tmax * $NS}]]
puts [format "FALLO, AR->2.a palabra (HP1+DDR): min %d  media %.1f  max %d ciclos  = %.0f / %.0f / %.0f ns" \
    $amin [expr {double($asum) / $nh}] $amax [expr {$amin * $NS}] [expr {double($asum) / $nh * $NS}] [expr {$amax * $NS}]]
puts [format "FALLO, espera hasta el AR       : media %.2f  max %d ciclos (barrera de escrituras)" [expr {double($wsum) / $nh}] $wmax]
set nom {"<16" "16-19" "20-23" "24-27" "28-31" "32-39" "40-63" ">=64"}
set i 0
foreach h $hist {
    puts [format "  total %-6s ciclos: %8u  %5.1f %%  %s%s" [lindex $nom $i] $h [expr {100.0 * $h / $nh}] [string repeat # [expr {int(50.0 * $h / $nh)}]] [expr {$h == 65535 ? "  (SATURADO)" : ""}]]
    incr i
}
exit
