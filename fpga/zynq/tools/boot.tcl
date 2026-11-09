# boot.tcl — arranque del MSXimus en la ZYNQ MINI desde XSDB (sin FSBL, sin SDK):
#   1) parar los dos Cortex-A9 (con el BOOT switch en QSPI corren la demo de fabrica)
#   2) ps7_init: relojes, MIO, entrenamiento de la DDR3
#   3) cargar el pack de BIOS en la DDR donde el cargador de flash del Tang lo
#      dejaba: RAM_START_ADDRESS+1 = 0x700000 de la ventana de memory_axi
#      (RAM_BASE 0x10800000) -> 0x10F00000. 512 KB + 6 (firma AB + config).
#   4) programar el PL   5) ps7_post_config (level shifters + FCLK_RESET0_N)
# Uso:  xsdb.bat tools/boot.tcl [pack.bin] [bitstream.bit] [imagen.img]   (hw_server.bat aparte)
#   Variables de entorno:
#     BOOT_PROXY=1      arranca el companion (arm/companion/companion.elf, o BOOT_ELF=<elf>) en el core 0
#     BOOT_IMG=1        'IMG1': companion en marcha pero la "SD" es la imagen de la DDR servida por el PL (MODE=0)
#     BOOT_IMG=2        'IMG2': la imagen de la DDR la sirve el ARM (MODE=1) + ventana magica de la disquetera
#     FDD_IMG=<x.dsk>   disquete FALSO en la DDR (0x1F000000) para probar la disquetera USB sin hardware
#     WAVE_ROM=<rom>|none, BOOT_QUIESCE=0|1, BOOT_LVL=keep|0xF|0xA|0x0 (ver abajo)
#     BOOT_SAFE=0|1     (1 por defecto) recupera el DAP caido con rst -system antes de empezar y comprueba el bus AHB antes de programar el PL
#     TR_ROM=<fs-a1st_firmware.rom>    perfil TR (fase 2): firmware del FS-A1ST (4194304 bytes) -> DDR 0x0E400000, y MBOX+0x1C bit 6
#                                      (tr_bios) a 1 junto con MSX_RUN: el companion conserva el bit
#     TR_KANJI=<fs-a1st_kanjifont.rom> fuente kanji del FS-A1ST (262144 bytes) -> DDR 0x10F00000, sobre la del pack (que ya esta cargado);
#                                      solo con TR_ROM. Sin ella se usa la fuente kanji del pack
#                                      (PowerShell: $env:TR_ROM="C:\ruta\fs-a1st_firmware.rom"). Sin TR_ROM no cambia nada.
#   Ejemplo:  BOOT_PROXY=1 BOOT_IMG=2 FDD_IMG=juego.dsk xsdb.bat tools/boot.tcl pack.bin msximus_zynq.bit sd.img
set here [file dirname [file normalize [info script]]]
set priv [expr {[info exists ::env(MSXIMUS_BIOS_PRIV)] ? $::env(MSXIMUS_BIOS_PRIV) : "$here/../../../../bios-msxnano-msximus"}]   ;# repo privado con los packs y la YRW801
set pack [expr {$argc > 0 ? [lindex $argv 0] : "$priv/packs/zynq/msximus/nextor-2.1.4/pack_bios_msximus.bin"}]
set bit  [expr {$argc > 1 ? [lindex $argv 1] : "$here/../msximus_zynq.bit"}]
set RAM_BASE  0x10800000
set PACK_OFF  0x700000
set packaddr  [expr {$RAM_BASE + $PACK_OFF}]

if {![file exists $pack]} { puts "ERROR: no existe el pack $pack"; exit 1 }
if {![file exists $bit]}  { puts "ERROR: no existe el bitstream $bit"; exit 1 }
puts "pack: $pack ([file size $pack] bytes) -> [format 0x%08X $packaddr]"
puts "bit : $bit"

connect -url tcp:127.0.0.1:3121
after 1000
# 03/11: BOOT_SAFE=1 (por defecto): el DAP de la Zynq se cae (AHB AP transaction error, DAP status 0x30000021) tras 2-3 cargas seguidas del PL sin quitar la
#     corriente y entonces `targets ARM*#0` no existe (solo DAP y xc7z020) y el script abortaba. `rst -system` por el DAP (receta del 28/09) lo recupera sin ciclo
#     de alimentacion (rst -srst NO basta). Aqui se intenta hasta 3 veces antes de seguir; y antes de programar el PL se vuelve a comprobar que el bus AHB responde.
set SAFE [expr {[info exists ::env(BOOT_SAFE)] ? $::env(BOOT_SAFE) : 1}]
proc dap_sano {} { return [expr {![catch { targets -set -filter {name =~ "ARM*#0"} }]}] }
if {$SAFE && ![dap_sano]} {
    for {set k 1} {$k <= 3} {incr k} {
        puts "DAP: sin targets ARM (AHB AP error): rst -system por el DAP (intento $k)"
        catch { targets -set -filter {name =~ "DAP*"}; rst -system }
        after 3000
        if {[dap_sano]} { puts "DAP: recuperado"; break }
    }
    if {![dap_sano]} { puts "ERROR: el DAP no se recupera por JTAG: hace falta ciclo de alimentacion"; exit 2 }
}
targets -set -filter {name =~ "ARM*#0"}
catch {stop}
targets -set -filter {name =~ "ARM*#1"}
catch {stop}
after 200
targets -set -filter {name =~ "APU*"}

# 1b) 🚨 PARAR EL PL ANTES DE TOCAR EL PS. 14/09: reprogramar en caliente dejaba
#     HP0/HP1 muertos (memory_axi.dbg_state: AR aceptado y r_cnt=0, en 4 bitstreams
#     distintos y con cualquier combinacion de reset previo / level shifters; solo
#     lo limpiaba un reset del PS: tools/psreset.tcl). Causa: ps7_init RESETEA Y
#     REENTRENA EL DDRC mientras la imagen anterior sigue leyendo la DDR por HP
#     (V9968 a 150 MHz, memory_axi, buzon) -> transaccion a medias en el puerto
#     del DDRC. Desde la imagen de fabrica (sin masters AXI) nunca fallaba. Con
#     FCLK_RESET0..3_N bajos los backends del PL entran en reset (VALID=0,
#     READY=1: drenan) y ps7_init trabaja con el HP en silencio. Los level
#     shifters se dejan solo PS->PL (0xA) hasta ps7_post_config, como el FSBL.
#     Experimentos: BOOT_QUIESCE=0/1, BOOT_LVL=keep|0xF|0xA|0x0.
set QUIESCE [expr {[info exists ::env(BOOT_QUIESCE)] ? $::env(BOOT_QUIESCE) : 1}]
set LVL     [expr {[info exists ::env(BOOT_LVL)] ? $::env(BOOT_LVL) : "0xA"}]
puts "pre-init: quiesce=$QUIESCE lvl_shftr=$LVL"
# 1c) 🚨 22/09: EL USB0 TAMBIEN ES UN MASTER DE LA DDR (el EHCI lee sus listas de la DDR por DMA).
#     Con el companion anterior aun corriendo, ps7_init reentrenaba el DDRC con una lectura del EHCI a
#     medias y el controlador quedaba COLGADO para todos los arranques siguientes (no ejecutaba ni un
#     qTD, ni se paraba con RS=0; solo lo curaba quitar la corriente). Con un teclado solo casi nunca
#     tocaba (una lectura cada 8 ms); con la disquetera TEAC reenumerando en bucle, siempre.
#     Parar el controlador (RS=0, esperar HCHalted) y resetearlo ANTES de tocar el DDRC.
#     28/09: de 8 arranques seguidos con el companion en marcha, 1 dejo el PS con el DAP en "AHB AP transaction
#     error": el mwr al USBCMD dio "AP transaction timeout" y el script abortaba (habia que hacer a mano
#     `targets DAP; rst -system` y repetir). Ahora el quiesce va en catch y, si el bus AHB no contesta, se hace ese
#     rst -system del DAP aqui mismo (el PS entero se resetea: el USB y el GEM quedan parados igualmente) y se sigue.
if {$QUIESCE} {
    set qok [catch {
        if {![catch { set ucmd [lindex [mrd -value 0xE0002140 1] 0] }]} {
            mwr -force 0xE0002140 [expr {$ucmd & ~1}]                 ;# USBCMD.RS = 0
            for {set i 0} {$i < 50} {incr i} { after 2; if {[lindex [mrd -value 0xE0002144 1] 0] & 0x1000} break }
            mwr -force 0xE0002140 0x00000002                           ;# USBCMD.RST (el DMA se queda quieto)
            mwr -force 0xE000B000 0x00000000                           ;# GEM0 NWCTRL: RX/TX fuera (25/09: su DMA tambien pisa la DDR)
            after 20
            puts [format "usb0: parado y reseteado (USBSTS=%08X)" [lindex [mrd -value 0xE0002144 1] 0]]
        } else { puts "usb0: registros no accesibles (PS en reset): nada que parar" }
    } qerr]
    if {$qok} {
        puts "quiesce: el bus AHB del PS no contesta ($qerr): rst -system por el DAP y seguimos"
        targets -set -filter {name =~ "DAP*"}
        rst -system
        after 2000
        targets -set -filter {name =~ "ARM*#0"}
        catch {stop}
        targets -set -filter {name =~ "ARM*#1"}
        catch {stop}
        after 200
        targets -set -filter {name =~ "APU*"}
    }
}
mwr -force 0xF8000008 0x0000DF0D                                ;# SLCR unlock
if {$QUIESCE} { mwr -force 0xF8000240 0x0000000F; after 150 }   ;# masters del PL en reset y drenando
if {$LVL ne "keep"} { mwr -force 0xF8000900 [expr {$LVL}] }      ;# 0xA = solo PS->PL
mwr -force 0xF8000004 0x0000767B                                ;# SLCR lock

# 2) ps7_init: relojes, MIO, entrenamiento de la DDR3 (con el PL parado)
source $here/../ps7_init.tcl
ps7_init
# 25/09 (Ethernet P1): la UART1 esta en EMIO y ps7_init ya no toca MIO 48/49; un arranque por JTAG hereda el
#     mux "UART1 en MIO" de la sesion anterior (0x12E0/0x12E1) y entonces el RX de la UART1 se toma del CH340
#     y no del PL (el companion no oye al MSX). A GPIO de entrada, como en un arranque frio.
mwr -force 0xF8000008 0x0000DF0D
mwr -force 0xF80007C0 0x00001201
mwr -force 0xF80007C4 0x00001201
mwr -force 0xF8000004 0x0000767B

# 3) pack a la DDR y comprobacion de las dos puntas
#    (xsdb: mwr -bin -file <fichero> <direccion> <num_palabras>; 524294 B -> 131074 palabras)
mwr -bin -file $pack $packaddr [expr {([file size $pack] + 3) / 4}]
set head [mrd -value $packaddr 2]
set tail [mrd -value [expr {$packaddr + 0x80000 - 4}] 3]
puts "DDR: cabeza [format %08X [lindex $head 0]] [format %08X [lindex $head 1]]  cola+firma [format %08X [lindex $tail 1]] [format %08X [lindex $tail 2]]"

# 3a) memoria de ondas del OPL4 (zynq/wave_axi.v por S_AXI_GP0): la YRW801 (2 MB) en
#     WAVE_BASE 0x0F000000; los 2 MB siguientes son la RAM de muestras del MoonSound.
#     WAVE_ROM=fichero para otra ROM; WAVE_ROM=none para no cargarla.
set WAVE_BASE 0x0F000000
set wave [expr {[info exists ::env(WAVE_ROM)] ? $::env(WAVE_ROM) : "$priv/packs/zynq/roms/yrw801.rom"}]   ;# repo privado
if {$wave ne "none"} {
    if {![file exists $wave]} { puts "ERROR: no existe la ROM de ondas $wave"; exit 1 }
    puts "wave: $wave ([file size $wave] bytes) -> [format 0x%08X $WAVE_BASE]"
    mwr -bin -file $wave $WAVE_BASE [expr {([file size $wave] + 3) / 4}]
    set wh [mrd -value $WAVE_BASE 1]
    puts [format "wave: cabeza %08X (YRW801 real: bytes 40 18 00 00 = 00001840 en little-endian)" [lindex $wh 0]]
}

# 3a1) BIOS del turbo R (perfil TR, fase 2): TR_ROM = firmware (4 MB) en 0x0E400000; TR_KANJI = fuente kanji (256 KB) en 0x10F00000,
#      DESPUES del pack del paso 3 (lo pisa: mismo formato JIS1+JIS2). No se comprueba el SHA-1 (xsdb no trae tcllib): lo hace el companion
#      cuando la lee de la TF2; aqui solo el tamano. El bit 6 de MBOX+0x1C (tr_bios) va en la MISMA escritura que MSX_RUN en 3b (ctl0).
set TR_FW_BASE    0x0E400000
set TR_FW_SIZE    4194304
set TR_KANJI_BASE 0x10F00000
set TR_KANJI_SIZE 262144
set ctl0 1                                    ;# MBOX+0x1C: MSX_RUN (bit 0); con TR_ROM, ademas tr_bios (bit 6)
set trrom   [expr {[info exists ::env(TR_ROM)]   ? $::env(TR_ROM)   : ""}]
set trkanji [expr {[info exists ::env(TR_KANJI)] ? $::env(TR_KANJI) : ""}]
if {$trrom ne ""} {
    if {![file exists $trrom]} { puts "ERROR: no existe el firmware del turbo R $trrom"; exit 1 }
    if {[file size $trrom] != $TR_FW_SIZE} { puts "ERROR: $trrom mide [file size $trrom] bytes y el firmware del FS-A1ST son $TR_FW_SIZE"; exit 1 }
    puts "TR firmware: $trrom ([file size $trrom] bytes) -> [format 0x%08X $TR_FW_BASE]"
    mwr -bin -file $trrom $TR_FW_BASE [expr {$TR_FW_SIZE / 4}]
    puts [format "TR firmware: cabeza %08X, cola %08X" [lindex [mrd -value $TR_FW_BASE 1] 0] [lindex [mrd -value [expr {$TR_FW_BASE + $TR_FW_SIZE - 4}] 1] 0]]
    if {$trkanji ne ""} {
        if {![file exists $trkanji]} { puts "ERROR: no existe la fuente kanji del turbo R $trkanji"; exit 1 }
        if {[file size $trkanji] != $TR_KANJI_SIZE} { puts "ERROR: $trkanji mide [file size $trkanji] bytes y la fuente kanji del FS-A1ST son $TR_KANJI_SIZE"; exit 1 }
        puts "TR kanji: $trkanji ([file size $trkanji] bytes) -> [format 0x%08X $TR_KANJI_BASE] (sobre la del pack)"
        mwr -bin -file $trkanji $TR_KANJI_BASE [expr {$TR_KANJI_SIZE / 4}]
        puts [format "TR kanji: cabeza %08X" [lindex [mrd -value $TR_KANJI_BASE 1] 0]]
    } else {
        puts "AVISO: TR_ROM sin TR_KANJI: el turbo R usara la fuente kanji del pack"
    }
    set ctl0 [expr {$ctl0 | 0x40}]
} elseif {$trkanji ne ""} {
    puts "AVISO: TR_KANJI sin TR_ROM se ignora (la fuente kanji del turbo R solo se carga con su firmware)"
}

# 3a2) VRAM del V9968 a cero (DDR 0x10280000, 256 KB): la DDR arranca con basura y toda zona
#      que un juego no escriba se veia como ruido blanco (Xevious, 14/09). En el Tang nace limpia.
#      (Con BOOT_PROXY=1 el companion lo hace tambien; aqui cubre el caso sin companion.)
set VRAM 0x10280000
mwr -force $VRAM [lrepeat 65536 0] 65536
puts "VRAM: 256 KB a cero en [format 0x%08X $VRAM]"

# 3b) buzon de depuracion (dbg_mailbox_axi, HP2) a cero ANTES de soltar el PL:
#     la DDR arranca con basura y el PL la leeria como teclas pulsadas.
set MBOX 0x1FF00000
#     17/09: TODO el buzon (+0x00..+0xFF), no solo las teclas: la telemetria +0x70/+0xC0 del PL anterior
#     (toggle de guardar a 1) hacia que el companion nuevo viera un guardado al arrancar el PL nuevo (toggle 0)
#     y grabara ceros en la QSPI. (El companion ademas ignora bloques con config1 = 0.)
mwr $MBOX [lrepeat 64 0] 64
if {[info exists ::env(BOOT_CTL_OR)]} { set ctl0 [expr {$ctl0 | $::env(BOOT_CTL_OR)}] }   ;# depuracion: bits extra de MBOX+0x1C en la misma escritura (p. ej. 2 = armar el trazador desde el arranque)
mwr [expr {$MBOX + 0x1C}] $ctl0  ;# MSX_RUN: el pack ya esta en la DDR, el MSX puede arrancar (con TR_ROM, 0x41: + tr_bios, bit 6)
if {$ctl0 != 1} { puts [format "MBOX+0x1C = %02X (MSX_RUN + tr_bios)" $ctl0] }

# BOOT_OTA_INFO=<fichero>: la particion ota_info de make_boot.sh, para probar con serie y version como con un BOOT.bin (panel de perfiles y OTA)
if {[info exists ::env(BOOT_OTA_INFO)]} { mwr -bin -file $::env(BOOT_OTA_INFO) 0x00E10000 64 }

# 3c) "SD" del MSXimus (sd_axi_proxy, HP3): buzon SDBOX en modo IMAGEN (MODE=0),
#     tarjeta presente, tamano = la ventana de la imagen (224 MB). Opcionalmente
#     se carga una imagen de disco (3er argumento) en DISK_BASE 0x11000000.
set SDBOX     0x1FF00100
set DISK_BASE 0x11000000
set DISK_MB   224
mwr $SDBOX [list 0 [expr {($DISK_MB << 16) | 1}] 0 0 0 0 0 0] 8   ;# W0 = {MB<<16|present, MODE=0}; REQ/ACK a cero
#     18/09: BOOT_IMG=1 (con BOOT_PROXY=1) = companion en marcha pero SIN tarjeta: el PL lee la imagen de la DDR
#     y el companion sirve WaveGame/cinta desde ella (marca 'IMG1' en SDBOX+0x78). Para probar sin tocar la SD.
#     22/09: BOOT_IMG=2 = 'IMG2': la imagen de la DDR la sirve EL ARM (el companion pone MODE=1 y copia los
#     sectores de 0x11000000 al SDBUF), asi TODAS las peticiones pasan por el companion y la ventana magica
#     de la disquetera (FLOPPY_LBA 0xFFFE0000) se puede probar con el disquete falso de abajo, sin SD ni USB.
set BIMG [expr {[info exists ::env(BOOT_IMG)] ? $::env(BOOT_IMG) : "0"}]
if {$BIMG eq "1"} {
    mwr [expr {$SDBOX + 0x78}] 0x494D4731; puts "SD: modo IMAGEN con companion ('IMG1': la sirve el PL, MODE=0)"
} elseif {$BIMG eq "2"} {
    mwr [expr {$SDBOX + 0x78}] 0x494D4732; puts "SD: modo IMAGEN servida por el ARM ('IMG2': MODE=1 + ventana de la disquetera)"
} else {
    mwr [expr {$SDBOX + 0x78}] 0
}
if {$argc > 2} {
    set img [lindex $argv 2]
    if {![file exists $img]} { puts "ERROR: no existe la imagen $img"; exit 1 }
    set mb [expr {([file size $img] + 1048575) / 1048576}]
    if {$mb > $DISK_MB} { puts "ERROR: imagen de $mb MB > ventana de $DISK_MB MB"; exit 1 }
    puts "disco: $img ($mb MB) -> [format 0x%08X $DISK_BASE]"
    mwr -bin -file $img $DISK_BASE [expr {([file size $img] + 3) / 4}]
    set s0 [mrd -value [expr {$DISK_BASE + 0x1FC}]]
    puts [format "disco: firma del sector 0 = %04X (55AA = MBR/boot valido)" [expr {($s0 >> 16) & 0xFFFF}]]
}

# 3c2) DISQUETERA USB FALSA (22/09). El companion presenta el disquete de la disquetera USB en la VENTANA
#      MAGICA FLOPPY_LBA = 0xFFFE0000 (hasta 2880 sectores) del mismo "dispositivo SD"; el menu la monta con
#      la tecla U como si fuera un .dsk. Con FDD_IMG=<fichero .dsk> se carga ese fichero en la DDR y se le
#      dice al companion que lo sirva en la ventana SIN disquetera ni USB (backend "falso"):
#        SDBOX+0x8C = 'FDD1' (0x31444446)   +0x90 = direccion DDR de la imagen   +0x94 = sectores (720/1440/2880)
#      FDD_BASE = 0x1F000000: la imagen de disco ocupa 0x11000000..0x1EFFFFFF (224 MB, DISK_BASE+DISK_MB) y la
#      cinta 0x1FE00000..0x1FEFFFFF (TAPE_BUF), asi que 0x1F000000..0x1FDFFFFF (14 MB) no lo usa nadie; 0x1E800000
#      CAERIA DENTRO de la imagen (offset 216 MB = LBA 0x6C000), por eso no se usa. 1,44 MB = 0x168000 bytes.
#      El companion publica en +0x80 (estado), +0x84 (lecturas|escrituras) y +0x88 (errores|montajes): se dejan a
#      cero para que tel.tcl no ensene los de la sesion anterior (arriba solo se limpian MBOX+0x00..+0xFF y
#      SDBOX+0x00..+0x1F). Sin FDD_IMG, +0x8C queda a 0 = sin disquete falso (solo la disquetera USB real).
set FDD_BASE 0x1F000000
set FDD_MAX  1474560                          ;# 2880 sectores (HD 1,44 MB); DD 720 KB = 1440; 360 KB = 720
mwr [expr {$SDBOX + 0x80}] [lrepeat 6 0] 6    ;# +0x80..+0x94: estado, contadores, errores, FDD_FAKE, base, sectores
if {[info exists ::env(FDD_IMG)] && $::env(FDD_IMG) ne ""} {
    set flp $::env(FDD_IMG)
    if {![file exists $flp]} { puts "ERROR: no existe el disquete $flp"; exit 1 }
    set fsz [file size $flp]
    if {$fsz == 0 || ($fsz % 512) != 0 || $fsz > $FDD_MAX} {
        puts "ERROR: disquete de $fsz bytes: tiene que ser multiplo de 512 y <= $FDD_MAX (360/720/1440 KB)"; exit 1
    }
    set fsec [expr {$fsz / 512}]
    if {$fsec != 720 && $fsec != 1440 && $fsec != 2880} { puts "AVISO: $fsec sectores no es un disquete estandar (720/1440/2880); se sirve igual" }
    puts "disquete: $flp ($fsz bytes, $fsec sectores) -> [format 0x%08X $FDD_BASE] (FALSO: sin disquetera ni USB)"
    mwr -bin -file $flp $FDD_BASE [expr {($fsz + 3) / 4}]
    set f0  [mrd -value [expr {$FDD_BASE + 0x1FC}]]
    set bpb [mrd -value [expr {$FDD_BASE + 0x10}] 2]   ;# BPB +0x13 (sectores totales, 16 bits LE) = byte 3 de +0x10 y byte 0 de +0x14
    set tot [expr {(([lindex $bpb 0] >> 24) & 0xFF) | (([lindex $bpb 1] & 0xFF) << 8)}]
    puts [format "disquete: firma del sector 0 = %04X, sectores totales del BPB = %u (el menu usa este valor; 0 o fuera de 720..2880 -> 1440)" \
        [expr {($f0 >> 16) & 0xFFFF}] $tot]
    mwr [expr {$SDBOX + 0x8C}] [list 0x31444446 $FDD_BASE $fsec] 3
    puts [format "disquete: SDBOX+0x8C='FDD1' base=%08X sectores=%d (el companion lo lee al arrancar)" $FDD_BASE $fsec]
}

# 3d) BOOT_PROXY=1: el programa del ARM (arm/sdproxy) sirve la tarjeta REAL de TF2
#     al PL (MODE=1 en SDBOX). Se arranca en el core 0 ANTES de soltar el PL para
#     que el premontaje del menu ya vaya a la tarjeta. Desde aqui el core 0 corre:
#     la memoria y los registros se tocan por el core 1 (parado).
set memtgt "APU*"
if {[info exists ::env(BOOT_PROXY)] && $::env(BOOT_PROXY) eq "1"} {
    set elf [expr {[info exists ::env(BOOT_ELF)] ? $::env(BOOT_ELF) : "$here/../arm/companion/companion.elf"}]
    if {![file exists $elf]} { puts "ERROR: no existe $elf (arm/sdproxy/build.sh)"; exit 1 }
    targets -set -filter {name =~ "ARM*#0"}
    catch {stop}
    # 26/09: el companion que corria deja la MMU activa con sus tablas en su .bss (TTBR0 ~0x188000): un ELF
    # nuevo mas grande las pisa al escribir .text y el dow falla ("MMU page translation fault"). Apagarla antes
    # (SCTLR.M/C/I a cero; el companion nuevo la vuelve a montar en mmu_init).
    catch {
        set sctlr [lindex [split [string trim [rrd cp15 c1 sctlr]] ": "] end]
        rwr cp15 c1 sctlr [expr {"0x$sctlr" & ~0x1005}]
    }
    dow $elf
    # 23/09: dow pone el PC pero NO el CPSR: hereda el del sitio donde se paro el core. Si se paro dentro
    # de una rutina Thumb de la libc (bit T = 1), _start (codigo ARM) se ejecutaba en Thumb y moria en la
    # 2a instruccion (ex_undef, SP=0, MODE a 0). Reproducido forzando cpsr=0x1F3. 0x1D3 = valor de reset
    # del A9: SVC, estado ARM, A/I/F enmascaradas (start.S las abre cuando toca).
    rwr cpsr 0x1D3
    con
    targets -set -filter {name =~ "ARM*#1"}
    catch {stop}
    set memtgt "ARM*#1"
    set ok 0
    for {set i 0} {$i < 50} {incr i} { if {[expr {[mrd -value $SDBOX] & 1}]} { set ok 1; break }; after 100 }
    set card [mrd -value [expr {$SDBOX + 4}]]
    # 03/11: el companion tarda unos segundos en dar la tarjeta por presente (sondeo cada 0,5 s) y el PL no sabe esperarla: con el MSX ya corriendo,
    # el primer acceso de Nextor a la unidad A: llega con CARD = 0, el PL lo rechaza y sale «Not ready reading drive A». Se espera aqui (max. 20 s)
    # a que el companion la vea antes de soltar el PL (con BOOT.bin el companion ya no suelta el MSX hasta tenerla). BOOT_NOWAIT=1 lo salta.
    if {$ok && ![info exists ::env(BOOT_NOWAIT)]} {
        for {set i 0} {$i < 200} {incr i} { set card [mrd -value [expr {$SDBOX + 4}]]; if {$card & 1} { break }; after 100 }
        puts [format "tarjeta: %s tras %d ms" [expr {($card & 1) ? "presente" : "NO detectada (se sigue sin ella)"}] [expr {$i * 100}]]
    }
    puts [format "proxy ARM: %s | tarjeta presente=%d, %d MB" [expr {$ok ? "MODE=1" : "SIN RESPUESTA (MODE sigue 0)"}] [expr {$card & 1}] [expr {$card >> 16}]]
    if {!$ok} { set boot_aviso "el companion NO contesta (MODE sigue 0): armpc.tcl dice donde se quedo el core 0" }
}

# 4) PL   5) suelta el PL (ps7_post_config: level shifters 0xF + FCLK_RESET altos)
# BOOT_SAFE: ultima comprobacion de que el bus del PS responde justo antes de reconfigurar el PL (el companion ya esta parado y el PL en reset: FPGA_RST_CTRL=0xF arriba)
if {$SAFE} {
    targets -set -filter {name =~ "APU*"}
    if {[catch { mrd -value 0xF8000B74 1 } derr]} {
        puts "ERROR: el bus AHB del PS no responde justo antes de programar el PL ($derr): no se programa; rst -system por el DAP y repetir"
        catch { targets -set -filter {name =~ "DAP*"}; rst -system }
        exit 3
    }
    after 200
}
targets -set -filter {name =~ "xc7z020"}
fpga -f $bit
targets -set -filter [format {name =~ "%s"} $memtgt]
ps7_post_config
if {[info exists boot_aviso]} {
    puts "BOOT_FALLO: $boot_aviso"
} else {
    puts "BOOT_OK: el MSX deberia arrancar ahora (logo/menu por HDMI)"
}
exit
