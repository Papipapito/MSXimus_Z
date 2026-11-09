# build.tcl — MSXimus para la ZYNQ MINI (XC7Z020), Vivado 2019.2 en batch.
#
#   vivado -mode batch -source build.tcl -tclargs elab   -> solo elaboracion RTL (paso 1)
#   vivado -mode batch -source build.tcl -tclargs synth  -> + sintesis y utilizacion (paso 2)
#   vivado -mode batch -source build.tcl [-tclargs bit]  -> + implementacion y bitstream (paso 3)
#   vivado -mode batch -source build.tcl -tclargs bit musica -> el PERFIL "Musica" (31/10/2026): el mismo sistema SIN geo3d y CON
#       YM2151 (Yamaha SFG-01/05) y SN76489 (Franky, PlaySoniq): fpga/zynq/musica_sound.v + fpga/jt51 + fpga/jt89 y
#       `define PERFIL_MUSICA. Salidas con sufijo (msximus_zynq_musica.bit, util_musica.rpt...) y proyecto aparte
#       (vivado_prj_musica): no pisa nada del estandar. Sin el segundo argumento este script hace EXACTAMENTE lo de siempre.
#   vivado -mode batch -source build.tcl -tclargs bit dual   -> el PERFIL "Dual" (31/10/2026, prueba de concepto; 2.a version): el mismo sistema
#       SIN geo3d y SIN el OPL4 (ENABLE_OPL4FM y ENABLE_OPL4_WAVE: top_zynq.v) y CON una segunda maquina MSX2+ (B: fpga/zynq/msx_b.v +
#       axi_arb2w.v) cuya pantalla es un rectangulo del frame buffer del V9990 (fpga/video720/bwin_fb.v, por el S_AXI_GP0) y
#       `define PERFIL_DUAL. Salidas con sufijo _dual y proyecto aparte (vivado_prj_dual). Ver docs/tecnica/14-perfil-dual.md.
#
#   vivado -mode batch -source build.tcl -tclargs bit tr     -> el PERFIL "TR" (Turbo R, fase 1, 02/11/2026): el estandar SIN geo3d, SIN V9990 (chip, puente,
#       escritor del frame buffer y puerto del ARM), SIN el OPL4 (FM, PCM y wave_axi) y SIN el Y8950 (FM + ADPCM); del video se queda el compositor fijo en
#       el modo 0 y el frame buffer del V9968. `define PERFIL_TR. Salidas con sufijo _tr y proyecto aparte (vivado_prj_tr). Ver docs/tecnica/15-perfil-tr.md.
#
# Comparte fpga/src, v9968, video720, jtopl, opl3, G80A... con el Tang.
# Lista de ficheros = la linea V9968 de fpga/build.tcl SIN lo especifico de Gowin
# (gowin_pll*, pll_27/74/86/12, clockdiv, memory.v, fan_ctrl, ro_osc, wave_sdram,
# ddr3/*, v9968_ddr3_backend) y CON zynq/memory_axi.v, zynq/v9968_axi_backend.v.

set here [file dirname [file normalize [info script]]]
set fpga [file normalize "$here/.."]
cd $here
set mode [expr {$argc > 0 ? [lindex $argv 0] : "bit"}]
set perfil [expr {$argc > 1 ? [lindex $argv 1] : ""}]
if {$perfil eq ""} { set sfx "" } elseif {$perfil eq "musica"} { set sfx "_musica" } elseif {$perfil eq "dual"} { set sfx "_dual" } elseif {$perfil eq "tr"} { set sfx "_tr" } elseif {$perfil eq "trv"} { set sfx "_trv" } else { puts "ERROR: perfil '$perfil' desconocido (solo: musica, dual, tr)"; exit 1 }
# BUILD_TAG = varias colocaciones en paralelo: proyecto y salidas aparte (sufijo _trv_a...); PLACE_DIR = directiva de place_design
if {[info exists ::env(BUILD_TAG)] && $::env(BUILD_TAG) ne ""} { append sfx "_$::env(BUILD_TAG)" }
puts "PERFIL = '$perfil'"
set ::FCLK_MHZ 150
# HP0 VRAM, HP1 RAM Z80, HP2 buzon xsdb, HP3 "SD en DDR" (con ZYNQ_NO_MAILBOX=1 el HP2 queda en reposo)
set ::N_HP 4
puts "N_HP = $::N_HP"

create_project -force msximus_zynq$sfx ./vivado_prj$sfx -part xc7z020clg400-2
set_property target_language Verilog [current_project]

# ---- PS7 ----
source $here/bd_ps7.tcl
set bd [get_files ps7_bd.bd]
generate_target all $bd
make_wrapper -files $bd -top
add_files ./vivado_prj$sfx/msximus_zynq$sfx.srcs/sources_1/bd/ps7_bd/hdl/ps7_bd_wrapper.v

# ---- RTL compartido (mismo orden que fpga/build.tcl) ----
set v {}
# ---- V9990 (fpga/v9990): PAQUETES PRIMERO ----
# El orden de compilacion es MANUAL (source_mgmt_mode DisplayOnly, mas abajo): el
# automatico de Vivado 2019.2 no ve los paquetes SV referenciados solo con
# `PKG::` y compilaba t9990_port.sv antes que config_pkg.sv ("CONFIG is not
# declared"). Dependencias: CONFIG/RAM (ficheros propios) -> T9990_REG
# (t9990_port.sv) -> T9990_RESO (t9990.sv) -> T9990_MEM_CONNECT (t9990_timing.sv)
# -> el resto. Medido en OOC (tools/synth_v9990_ooc.tcl): 6.966 LUT, 8,5 BRAM.
if {$perfil ne "tr"} {
foreach f {config_pkg.sv ram_pkg.sv gowin_dpb.v
           tiny9990/t9990_port.sv tiny9990/t9990.sv tiny9990/t9990_timing.sv tiny9990/t9990_ram.sv
           tiny9990/t9990_clock.sv tiny9990/t9990_bitmap.sv tiny9990/t9990_pattern.sv tiny9990/t9990_sprite.sv
           tiny9990/t9990_palette.sv tiny9990/t9990_color_decode.sv tiny9990/t9990_priority.sv
           tiny9990/t9990_selector.sv tiny9990/t9990_shift_buffer.sv tiny9990/t9990_blit.sv
           tiny9990/t9990_blit_addr.sv tiny9990/t9990_blit_bitmask.sv tiny9990/t9990_blit_fifo.sv
           v9990_cpu_glue.v v9990_arm_port.v v9990_vram_axi.v v9990_zynq.v} { lappend v $fpga/v9990/$f }
}
# perfil TR: sin Y8950 (jtopl2, jt10_adpcmb, y8950_adpcm, adpcm_sdram)
# opl3_pkg.sv delante de los calc_*.sv que lo importan (orden manual, ver abajo)
lappend v $fpga/opl3/opl3_pkg.sv
foreach f [glob $fpga/opl3/*.sv $fpga/opl3/*.v] { if {[file tail $f] ne "opl3_pkg.sv"} { lappend v $f } }
lappend v $fpga/src/opl4fm.v
lappend v $fpga/opl4wave/ymf278b_gowin.v   ;# motor PCM YMF278B (sv2v de opl4wave/*.sv, RAMs inferibles)
lappend v $fpga/src/opl4_pcm.v
if {$perfil ne "tr" && $perfil ne "trv"} { foreach f [glob $fpga/jtopl/*.v] { lappend v $f } }
foreach f [glob $fpga/ikaopll/*.v] { lappend v $f }   ;# 23/09/2026: el OPLL es IKAOPLL (jtopl sigue: jtopl2 = Y8950)
if {$perfil ne "tr" && $perfil ne "trv"} {
foreach f [glob $fpga/jt10/*.v] { lappend v $f }
lappend v $fpga/src/y8950_adpcm.v $fpga/src/adpcm_sdram.v
}
lappend v $fpga/src/flash_rw.v
lappend v $fpga/src/megaram.v $fpga/src/gm2_slot1.v $fpga/src/sd_dma.sv
lappend v $fpga/src/scc_wave2_ghdl.v $fpga/src/scc_glue.v $fpga/src/scc_wave2v.v
lappend v $fpga/src/dbg_uart.v $fpga/src/ocm/kanji.v $fpga/src/ocm/rtc.v
lappend v $fpga/src/psg_filter.v $fpga/src/msx_mouse.v $fpga/src/ws2812.v
foreach f {crc16.v dpram.v pinfilter.v sd_reader.sv sdcmd_ctrl.sv sdc_ioport.sv} { lappend v $fpga/src/wondertang/$f }
foreach f [glob $fpga/tn_vdp_v3_v9958/src/hdmi/*.sv] { lappend v $f }
foreach f [glob $fpga/v9968/*.v] { lappend v $f }
if {$perfil eq ""} {
    foreach f [glob $fpga/geo3d/*.v] { lappend v $f }   ;# 27/09/2026: geo3d (Alex Moncks, MIT): coprocesador 3D en 9Dh/9Fh
} elseif {$perfil eq "dual"} {
    # perfil Dual: sin geo3d
} elseif {$perfil eq "tr" || $perfil eq "trv"} {
    # perfil TR: sin geo3d
} else {
    # perfil Musica: sin geo3d; con el YM2151 (jt51) y el SN76489 (jt89) de Jotego (GPLv3)
    foreach f [lsort [glob $fpga/jt51/*.v]] { lappend v $f }
    foreach f [lsort [glob $fpga/jt89/*.v]] { lappend v $f }
}
lappend v $fpga/src/v9968_vram_shim.v $fpga/src/v9968_sdram_bridge.v $fpga/src/v9968_cpu_glue.v
lappend v $fpga/video720/msx2hdmi_v9968.sv
if {$perfil ne "tr"} { lappend v $fpga/v9990/axi_arb2.v }   ;# V9990: arbitro GP1 (VRAM + frame buffer)
lappend v $fpga/video720/v9990_fb.v   ;# frame buffer en DDR (del V9990 y, en WINDOW, del V9968: msx2hdmi_v9968 lo instancia siempre)
if {$perfil ne "tr"} { lappend v $fpga/video720/msx2hdmi_v9990.sv }
lappend v $fpga/video720/v9991_compose.sv $fpga/video720/v9991_wm.sv   ;# V9990: 2o puente (sin codificador) + compositor V9991 (28/10/2026; antes hdmi_tmds_switch.sv)
lappend v $fpga/src/msx_s1990.v
# perfil TR (fase 2): el R800 (rampa069/R800, LGPL) con su bus, el regulador de tiempo y tr_cpu (eleccion de CPU y cambio con los registros conservados)
if {$perfil eq "tr" || $perfil eq "trv"} { foreach f {r800_alu.v r800_reg.v r800_cpu.v r800_bus.v r800_timing.v tr_rommap.v tr_cpu.v tr_pcm.v} { lappend v $fpga/r800/$f } }
# 30/09/2026 (Z1.2.2): OSD con color: iosys y textdisp propios de la Zynq (tools/make_iosys_z.py, textdisp_z.v) y la
# paleta (tools/make_dpb_menu.py); src/iosys solo aporta la UART
lappend v $here/iosys_bl616_z.v $here/textdisp_z.v $here/osd_paleta.v $fpga/src/iosys/uart_fixed.v
lappend v $here/gowin_dpb_menu.v      ;# RAM del menu inferible (tools/make_dpb_menu.py), en vez de la IP DPB
foreach f {usb_hid_host.v usb_kbd_decode.v} { lappend v $fpga/src/usb_direct/$f }
# ---- Zynq ----
lappend v $here/gowin_prims.v $here/memory_axi.v $here/v9968_axi_backend.v $here/dbg_mailbox_axi.v
lappend v $here/sd_axi_proxy.v
lappend v $here/wave_axi.v
lappend v $here/vdp_trace.v
if {$perfil eq "musica"} { lappend v $here/musica_sound.v }
if {$perfil eq "dual"} { lappend v $here/axi_arb2w.v $here/axi_rst_drain.v $here/dual_mute.v $here/msx_b.v $fpga/video720/bwin_fb.v }
lappend v $here/top_zynq.v
# V9990: orden de compilacion MANUAL = el de las listas (paquetes SV/VHDL delante).
# Con el automatico, Vivado 2019.2 ponia los paquetes referenciados con `PKG::`
# detras de sus usuarios. Las listas $v y $vh ya van en orden de dependencias.
set_property source_mgmt_mode DisplayOnly [current_project]
add_files $v
# 🚨 Las macros de top_zynq.v (`define ZYNQ, ENABLE_*) solo las ven los ficheros
# compilados DESPUES de el, y ahora top_zynq.v va el ultimo: msx2hdmi_v9968.sv
# caia en su rama Gowin (`else` del `ifdef ZYNQ`: serializer + ELVDS propios,
# ignorando NO_SERIALIZER) y el diseno llevaba DOS serializadores. ZYNQ se define
# aqui para todo el fileset (VIDEO720/ENABLE_* siguen en top: nadie mas las usa).
if {$perfil eq "musica"} {
    set_property verilog_define {ZYNQ=1 PERFIL_MUSICA=1} [current_fileset]
} elseif {$perfil eq "dual"} {
    set_property verilog_define {ZYNQ=1 PERFIL_DUAL=1} [current_fileset]
} elseif {$perfil eq "trv"} {
    # perfil TRV (05/11/2026): el TR con V9990 y la megaram de 16 MB, sin Y8950
    set_property verilog_define {ZYNQ=1 PERFIL_TR=1 TR_V9990=1 NEO16_16M=1} [current_fileset]
} elseif {$perfil eq "tr"} {
    # TR_DEBUG=1 en el entorno: trazadores, telemetria de tr_cpu y latencia de memory_axi (tools/trsnap, vdpsnap, live, medir_latencia). Sin el, la build de produccion
    if {[info exists ::env(TR_DEBUG)] && $::env(TR_DEBUG) eq "1"} { set_property verilog_define {ZYNQ=1 PERFIL_TR=1 TR_DEBUG=1} [current_fileset]; puts "TR_DEBUG: build de depuracion"
    } else { set_property verilog_define {ZYNQ=1 PERFIL_TR=1} [current_fileset] }
} else {
    set_property verilog_define {ZYNQ=1} [current_fileset]
}
# NEO16M=1 en el entorno: megaram de 16 MB y NEO-16 de 10 bits (NEO16_16M), en cualquier perfil. Solo medido, sin decidir (05/11)
if {[info exists ::env(NEO16M)] && $::env(NEO16M) eq "1"} { set_property verilog_define [concat [get_property verilog_define [current_fileset]] NEO16_16M=1] [current_fileset]; puts "NEO16M: megaram de 16 MB" }
# El build del Tang compila TODO como SystemVerilog (-verilog_std sysv2017) y hay
# .v con `int`, `logic`, `always_ff`... (dpram.v, ...). Misma semantica aqui.
set_property file_type SystemVerilog [get_files $v]
# usb_hid_host.v hace $readmemh("src/usb_direct/usb_hid_host_rom.hex") con ruta
# relativa al proyecto Gowin. Vivado la resuelve desde el DIRECTORIO DEL RUN de
# sintesis (anadir el .hex como fuente no basta si la ruta lleva carpetas), asi
# que un hook TCL.PRE recrea esa ruta dentro del run antes de synth_design.
set hook $here/tools/synth_pre.tcl
set fh [open $hook w]
puts $fh {# generado por build.tcl: $readmemh con ruta relativa al run de sintesis}
puts $fh "file mkdir src/usb_direct"
puts $fh "file copy -force {$fpga/src/usb_direct/usb_hid_host_rom.hex} src/usb_direct/usb_hid_host_rom.hex"
close $fh
set_property STEPS.SYNTH_DESIGN.TCL.PRE $hook [get_runs synth_1]

# VHDL en orden de dependencias (source_mgmt_mode DisplayOnly): los paquetes
# (vdp_package, T80_Pack) delante de quien los usa.
set vh [list $fpga/tn_vdp_v3_v9958/src/vdp/vdp_package.vhd]
foreach f {t80_pack.vhd T80s.vhd g80a.vhd t80.vhd t80_alu.vhd t80_mcode.vhd t80_reg.vhd} { lappend vh $fpga/G80A/$f }
lappend vh $fpga/PSG_YM2149/YM2149.vhdl $fpga/denoise/denoise.vhd $fpga/monostable/monostable.vhd
foreach f {fifo.vhd lpf.vhd swioports.vhd uart_lite.vhd wifi_lite.vhd} { lappend vh $fpga/src/ocm/$f }
lappend vh $fpga/src/usb/usb_keyboard_msx.vhd $fpga/tn_vdp_v3_v9958/src/ram.vhd
# swioports.vhd hace "use work.vdp_package.all" (del VDP clasico). Gowin tolera
# el use sin el paquete si no se usa nada suyo; Vivado exige que exista
# (vdp_package.vhd va el PRIMERO de $vh, arriba).
add_files $vh

add_files -fileset constrs_1 $here/top_zynq.xdc
add_files -fileset constrs_1 $here/top_zynq_esp.xdc
add_files -fileset constrs_1 $here/top_zynq_oled.xdc
if {$perfil eq "tr" || $perfil eq "trv"} { add_files -fileset constrs_1 $here/top_zynq_tr.xdc }   ;# multiciclo 2 dentro del R800 (habilitador de 21,477 MHz)
# microSD en el header: sus pines van aparte; ZYNQ_NO_SD=1 (biseccion) deja los sd_* en tie-off
if {!([info exists ::env(ZYNQ_NO_SD)] && $::env(ZYNQ_NO_SD) eq "1")} {
    add_files -fileset constrs_1 $here/top_zynq_sd.xdc
} else { puts "ZYNQ_NO_SD: sin puertos sd_* (tie-off)" }
set_property top top_zynq [current_fileset]
# SIN update_compile_order: aun en DisplayOnly reordenaba por dependencias
# (paquetes con `import` delante de sus usuarios) y deshacia el orden de las
# listas; los paquetes referenciados solo con `PKG::` (tiny9990) quedaban detras.

# ---------------------------------------------------------------- paso 1: elaboracion
if {$mode eq "elab"} {
    set t0 [clock seconds]
    synth_design -rtl -top top_zynq -part xc7z020clg400-2
    puts "ELAB_OK en [expr {[clock seconds]-$t0}] s"
    exit 0
}

# ---------------------------------------------------------------- paso 2: sintesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "ERROR: sintesis fallida"; exit 1 }
open_run synth_1
report_utilization -file ./util_synth$sfx.rpt
report_utilization -hierarchical -hierarchical_depth 1 -file ./util_synth_hier$sfx.rpt
puts "SYNTH_OK"
if {$mode eq "synth"} { exit 0 }
close_design

# ---------------------------------------------------------------- paso 3: bitstream
if {[info exists ::env(PLACE_DIR)] && $::env(PLACE_DIR) ne ""} { set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE $::env(PLACE_DIR) [get_runs impl_1]; puts "PLACE_DIR = $::env(PLACE_DIR)" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "ERROR: implementacion fallida"; exit 1 }
file copy -force ./vivado_prj$sfx/msximus_zynq$sfx.runs/impl_1/top_zynq.bit ./msximus_zynq$sfx.bit
file copy -force [glob ./vivado_prj$sfx/msximus_zynq$sfx.srcs/sources_1/bd/ps7_bd/ip/ps7_bd_processing_system7_0_0/ps7_init.tcl] ./ps7_init$sfx.tcl
open_run impl_1
report_utilization    -file ./util_impl$sfx.rpt
report_timing_summary -file ./timing$sfx.rpt
report_clocks         -file ./clocks$sfx.rpt
if {$perfil eq "trv"} { report_cdc -details -file ./cdc$sfx.rpt }
puts "=================================================="
puts "OK: [file normalize ./msximus_zynq$sfx.bit]"
puts "=================================================="
exit 0
