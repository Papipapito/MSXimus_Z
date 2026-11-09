# synth_v9990_ooc.tcl — sintesis FUERA DE CONTEXTO del tiny9990 (fpga/v9990),
# como prueba de humo de compatibilidad SystemVerilog con Vivado 2019.2 y para
# medir su area en el XC7Z020 antes de integrarlo en top_zynq.v.
#
#   vivado -mode batch -source tools/synth_v9990_ooc.tcl -tclargs <dir_salida>
#
# Flujo de PROYECTO (el in-memory con read_verilog -sv moria con
# "invalid command name rt-undefined" sin decir por que): el log de parseo
# queda en <dir>/prj/v9990_ooc.runs/synth_1/runme.log. Deja util.rpt /
# util_hier.rpt / timing.rpt.
set here  [file dirname [file normalize [info script]]]
set v9990 [file normalize $here/../../v9990]
set out   [lindex $argv 0]
if {$out eq ""} { set out $here/../v9990_ooc }
set out [file normalize $out]
file mkdir $out

create_project -force v9990_ooc $out/prj -part xc7z020clg400-2

# Paquetes primero (RAM, T9990_RESO, T9990_REG, T9990_MEM_CONNECT), luego el resto.
set files [list \
    $v9990/config_pkg.sv \
    $v9990/ram_pkg.sv \
    $v9990/gowin_dpb.v \
    $v9990/tiny9990/t9990_port.sv \
    $v9990/tiny9990/t9990.sv \
    $v9990/tiny9990/t9990_timing.sv \
    $v9990/tiny9990/t9990_ram.sv \
    $v9990/tiny9990/t9990_clock.sv \
    $v9990/tiny9990/t9990_bitmap.sv \
    $v9990/tiny9990/t9990_pattern.sv \
    $v9990/tiny9990/t9990_sprite.sv \
    $v9990/tiny9990/t9990_palette.sv \
    $v9990/tiny9990/t9990_color_decode.sv \
    $v9990/tiny9990/t9990_priority.sv \
    $v9990/tiny9990/t9990_selector.sv \
    $v9990/tiny9990/t9990_shift_buffer.sv \
    $v9990/tiny9990/t9990_blit.sv \
    $v9990/tiny9990/t9990_blit_addr.sv \
    $v9990/tiny9990/t9990_blit_bitmask.sv \
    $v9990/tiny9990/t9990_blit_fifo.sv \
]
# Orden de compilacion MANUAL (= orden de la lista): el orden automatico de
# Vivado 2019.2 no ve un paquete referenciado solo con `CONFIG::` (sin import)
# y compilaba t9990_port.sv antes que config_pkg.sv -> "CONFIG is not declared".
set_property source_mgmt_mode DisplayOnly [current_project]
add_files -norecurse $files
set_property file_type SystemVerilog [get_files *.sv]
set_property top T9990 [current_fileset]

# Reloj de referencia para que el informe de timing tenga sentido: 85,909 MHz.
set xdc $out/t9990_ooc.xdc
set f [open $xdc w]
puts $f "create_clock -period 11.640 -name clk_86 \[get_ports CLK\]"
close $f
add_files -fileset constrs_1 -norecurse $xdc

set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "OOC_FAILED: ver $out/prj/v9990_ooc.runs/synth_1/runme.log"
    exit 1
}
open_run synth_1
report_utilization -file $out/util.rpt
report_utilization -hierarchical -hierarchical_depth 2 -file $out/util_hier.rpt
report_timing_summary -max_paths 5 -file $out/timing.rpt
puts "OOC_DONE"
