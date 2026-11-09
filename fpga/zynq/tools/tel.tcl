# tel.tcl — telemetria del PL leida del buzon de la DDR (zynq/dbg_mailbox_axi.v, HP2).
# El PL escribe cada ~1 ms en MBOX+0x40:
#   +40 'MBOX' +44 seq | +48 hits(memory_axi) +4C miss | +50 kbd_echo[31:0] +54 status
#   status = {vddr_ops[15:0], 6'b0, mmcm_lock, vddr_ready, iosys_frz, cpu_run, sd_type[1:0], sd_stat[3:0]}
# Uso: xsdb.bat tools/tel.tcl [n_lecturas] [ms_entre_lecturas]
# 22/09: tambien la disquetera USB del companion (SDBOX+0x80..+0x94, ver arm/companion/fdd.h y sd_axi_proxy.v).
set MBOX 0x1FF00000
set SDBOX 0x1FF00100
set n  [expr {$argc > 0 ? [lindex $argv 0] : 2}]
set ms [expr {$argc > 1 ? [lindex $argv 1] : 500}]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
set kbd [mrd -value $MBOX 4]
puts "buzon teclado: [format %08X-%08X-%08X-%08X [lindex $kbd 3] [lindex $kbd 2] [lindex $kbd 1] [lindex $kbd 0]]"
for {set k 0} {$k < $n} {incr k} {
    set v [mrd -value [expr {$MBOX + 0x40}] 14]
    lassign $v magic seq hits miss echo st d2 d d4 d3 drops smiss cfg wifi
    if {$k == 0} { puts [format "   UART del ESP: FIFO overflow (bytes tirados)=%d  underrun (lecturas en vacio)=%d" [expr {$wifi & 0xFFFF}] [expr {($wifi >> 16) & 0xFFFF}]] }
    # +0x70 cfg = {toggle[31], gain[19:17], turbo[16], config2[15:8], config1[7:0]} = bloque vigente al pulsar "guardar"
    if {$k == 0} { puts [format "   config guardada (MBOX+0x70): config1=%02X config2=%02X turbo=%d gain=%d toggle=%d" \
        [expr {$cfg & 255}] [expr {($cfg >> 8) & 255}] [expr {($cfg >> 16) & 1}] [expr {($cfg >> 17) & 7}] [expr {($cfg >> 31) & 1}]] }
    # +0xC0 = {toggle[31], 3'b0, niveles del mezclador[27:0]} (V3.7: 7 canales x 4 bits, 8 = x1) al pulsar "guardar"
    if {$k == 0} { set mx [mrd -value [expr {$MBOX + 0xC0}]]; set s ""
        foreach nom {PSG SCC OPLL MSX-AUDIO OPL4fm OPL4wave WaveGame} c {0 1 2 3 4 5 6} { append s [format " %s=%d" $nom [expr {($mx >> (4 * $c)) & 15}]] }
        puts [format "   mezclador guardado (MBOX+0xC0): toggle=%d%s (n/8)" [expr {($mx >> 31) & 1}] $s] }
    # Disquetera USB (companion, fdd.c; la ventana magica FLOPPY_LBA 0xFFFE0000 del proxy de SD):
    #   SDBOX+0x80 FDD_STAT = {sectores del medio[31:16] (1440/2880, 0 = sin medio), sense key/ASC[15:8] (0 = OK),
    #                          backend[7:4] (0 ninguno, 1 UFI/CBI, 2 UFI/BOT, 3 MSC TinyUSB, 4 falso), wp[1], presente[0]}
    #   +0x84 FDD_CNT = {escrituras[31:16], lecturas[15:0]}   +0x88 FDD_ERR = {montajes USB[31:16], errores[15:0]}
    #   +0x8C 'FDD1' (0x31444446) = disquete FALSO en la DDR (boot.tcl FDD_IMG): +0x90 base, +0x94 sectores
    if {$k == 0} { set fl [mrd -value [expr {$SDBOX + 0x80}] 6]
        lassign $fl fst fcnt ferr ffake fbase fsecs
        set fbk [lindex {ninguno UFI/CBI UFI/BOT MSC-TinyUSB falso} [expr {($fst >> 4) & 15}]]
        if {$fbk eq ""} { set fbk [format "?%d" [expr {($fst >> 4) & 15}]] }
        set fline [format "   disquetera USB: presente=%d wp=%d backend=%s sectores=%u sense=%02X | lecturas=%u escrituras=%u errores=%u montajes=%u" \
            [expr {$fst & 1}] [expr {($fst >> 1) & 1}] $fbk [expr {($fst >> 16) & 0xFFFF}] [expr {($fst >> 8) & 255}] \
            [expr {$fcnt & 0xFFFF}] [expr {($fcnt >> 16) & 0xFFFF}] [expr {$ferr & 0xFFFF}] [expr {($ferr >> 16) & 0xFFFF}]]
        if {$ffake == 0x31444446} { append fline [format " | falsa desde DDR base=%08X sectores=%u" $fbase $fsecs] }
        puts $fline }
    # +0x6C smiss = {spmiss[15:0], bgmiss[15:0]} del shim de VRAM (cada fallo de fondo = 8 px rancios); +0x68 drops = {s1_pfq[15:0], wq_full[15:0]}
    if {$k > 0} { puts [format "   shim VRAM: bgmiss +%u  spmiss +%u  (en %d ms) | drops pfq=%u wq=%u" [expr {($smiss - $smiss_p) & 0xFFFF}] [expr {(($smiss >> 16) - ($smiss_p >> 16)) & 0xFFFF}] $ms [expr {$drops >> 16}] [expr {$drops & 0xFFFF}]] }
    set smiss_p $smiss
    # +0x64 d3 = {present[31], port2[30], strobe[29], phase[28:26], turbo_eff[25], dx[23:16], dy[15:8], informes[7:0]}
    # +0x60 d4 = {wave_axi: lat_max AR->R en ciclos de 37,5 MHz [31:24], lecturas[23:16], escrituras[15:8]; PSG r15 escrituras[7:0]}
    puts [format "   raton: present=%d port2=%d strobe=%d fase=%d dx=%d dy=%d informes=%d | PSG r15: escrituras=%d" \
        [expr {($d3>>31)&1}] [expr {($d3>>30)&1}] [expr {($d3>>29)&1}] [expr {($d3>>26)&7}] \
        [expr {((($d3>>16)&255)^128)-128}] [expr {((($d3>>8)&255)^128)-128}] [expr {$d3&255}] [expr {$d4&255}]]
    puts [format "   CPU: %s" [expr {(($d3>>25)&1) ? "5.37 MHz (turbo)" : "3.58 MHz"}]]
    puts [format "   opl4 wave (GP0): lat_max=%d ciclos (%.0f ns) lecturas=%d escrituras=%d (contadores de 8 bits)" \
        [expr {($d4>>24)&255}] [expr {(($d4>>24)&255)*1000.0/37.5}] [expr {($d4>>16)&255}] [expr {($d4>>8)&255}]]
    # V9990 (build con ENABLE_V9990): +0x60 d4 = {HDMI muestra el V9990[31], lineas capturadas al ring en el ultimo frame[30:22],
    #                                  underrun del lector del frame buffer en el ultimo frame[21:17] (esperado 0; satura en 31),
    #                                  underrun del FB del V9968[16:12], frame del V9968 publicado[11], V9968 compuesto (modos 2 y 3)[10],
    #                                  pixeles/frame mod 1024[9:0]} (Z1.3; hasta la Z1.2.13 los pixeles eran mod 2048 en [10:0])
    #                                  +0x64 d3 (29/10, V9991 paso 5; antes ciclos de stall de la VRAM) = estado del lector/escritor del frame buffer
    #                                  del V9990 (v9990_fb.dbg_state): {rst_st[31:30] (0 idle, 1 AR, 2 datos), r_active[29], ARVALID[28], r_line[27:19],
    #                                  yy_dec[18:10] (linea que muestra el mostrador), r_burst[9:6], wst[5:3], escrituras en vuelo[2:0]}. Un lector sano
    #                                  va 1..12 lineas por delante de yy_dec; r_line fijo con rst_st = 2 es un AR perdido (el arbitro de antes del 29/10).
    puts [format "   v9990 (si ENABLE_V9990): HDMI=%s  captura/frame: lineas=%u pixeles mod 1024=%u (B1: 240/576 (68160); B5: 400/0)  underrun FB=%u lineas" \
        [expr {($d4>>31)&1 ? (($d4>>10)&1 ? "V9991 (compuesto)" : "V9990") : "V9968"}] [expr {($d4>>22)&0x1FF}] [expr {$d4&0x3FF}] [expr {($d4>>17)&0x1F}]]
    puts [format "   lector del FB del V9990: estado=%u (0 idle, 1 AR, 2 datos) activo=%u arvalid=%u r_line=%u yy_dec=%u rafaga=%u | escritor: wst=%u en vuelo=%u" \
        [expr {($d3>>30)&3}] [expr {($d3>>29)&1}] [expr {($d3>>28)&1}] [expr {($d3>>19)&0x1FF}] [expr {($d3>>10)&0x1FF}] [expr {($d3>>6)&15}] [expr {($d3>>3)&7}] [expr {$d3&7}]]
    puts [format "   ventana V9991 (modo 2): frame del V9968 publicado en la DDR=%u  underrun del lector del V9968=%u lineas" \
        [expr {($d4>>11)&1}] [expr {($d4>>12)&0x1F}]]
    # d2 = {sd_ram_blocks[31:16], sdio_count[15:8], timeout[7], crc[6], rcrc[5], init[4], card_stat[3:0]}
    puts [format "   sdproxy: ordenes=%u rcount=%u timeout=%d crc=%d rcrc=%d init=%d stat=%d" \
        [expr {$d2>>16}] [expr {($d2>>8)&255}] [expr {($d2>>7)&1}] [expr {($d2>>6)&1}] [expr {($d2>>5)&1}] [expr {($d2>>4)&1}] [expr {$d2&15}]]
    set tag [format %c%c%c%c [expr {$magic>>24}] [expr {($magic>>16)&255}] [expr {($magic>>8)&255}] [expr {$magic&255}]]
    puts [format "%s seq=%u hits=%u miss=%u echo=%08X | vdp_ops=%u lock=%d vready=%d frz=%d cpu_run=%d sd_type=%d sd_stat=%d | sd: mode=%d irq=%d busy=%d blk_rdy=%d rstart=%d wstart=%d" \
        $tag $seq $hits $miss $echo [expr {$st>>16}] [expr {($st>>9)&1}] [expr {($st>>8)&1}] [expr {($st>>7)&1}] \
        [expr {($st>>6)&1}] [expr {($st>>4)&3}] [expr {$st&15}] \
        [expr {($st>>15)&1}] [expr {($st>>14)&1}] [expr {($st>>13)&1}] [expr {($st>>12)&1}] [expr {($st>>11)&1}] [expr {($st>>10)&1}]]
    # dbg_state: [2:0]seq [3]busy [4]miss_wait [5]filled [6]w_issued [7]inv_run [8]ar_seen [9]arvalid [13:10]wr_pend [19:14]last_rid [27:20]r_cnt [31:28]rd_tag
    puts [format "   memFSM: seq=%d busy=%d miss_wait=%d filled=%d w_issued=%d inv_run=%d ar_seen=%d arvalid=%d wr_pend=%d last_rid=%d r_cnt=%d rd_tag=%d" \
        [expr {$d&7}] [expr {($d>>3)&1}] [expr {($d>>4)&1}] [expr {($d>>5)&1}] [expr {($d>>6)&1}] [expr {($d>>7)&1}] \
        [expr {($d>>8)&1}] [expr {($d>>9)&1}] [expr {($d>>10)&15}] [expr {($d>>14)&63}] [expr {($d>>20)&255}] [expr {($d>>28)&15}]]
    if {$k < $n-1} { after $ms }
}
exit
