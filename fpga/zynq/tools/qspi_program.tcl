# qspi_program.tcl — graba (o lee) la flash QSPI (U15, 16 MB) de la ZYNQ MINI desde Vivado, con
# nuestro FSBL como ayudante (Vivado descarga el FSBL por JTAG y le pasa el fichero por trozos;
# no hace falta el program_flash del SDK). Requisitos: hw_server.bat corriendo, SW1 en JTAG
# (ON-ON), el PS7 del bitstream con el QSPI activado (bd_ps7.tcl desde 60fd36c) y el FSBL
# compilado con ese ps7_init (arm/fsbl/fsbl.elf).
#
# Uso (desde fpga/zynq):
#   vivado -mode batch -source tools/qspi_program.tcl -tclargs backup <parte> <salida.bin>
#       lee los 16 MB de la flash (la demo de fabrica) a un fichero, ANTES de pisarla
#   vivado -mode batch -source tools/qspi_program.tcl -tclargs program <parte> <BOOT.bin>
#       borra, graba y verifica BOOT.bin en el offset 0
# <parte> = nombre de Vivado del chip (mirar la serigrafia de U15):
#   Winbond W25Q128xx   -> w25q128fv-qspi-x4-single
#   Micron  MT25QU128   -> mt25qu128-qspi-x4-single
#   Spansion S25FL128S  -> s25fl128s-3.3v-qspi-x4-single   (S25FL129P -> s25fl129p-qspi-x4-single)
# Despues de grabar: SW1 en QSPI (ON-OFF) y encender.
set here [file dirname [file normalize [info script]]]
set mode [lindex $argv 0]
set part [lindex $argv 1]
set file [file normalize [lindex $argv 2]]
set fsbl [file normalize "$here/../arm/fsbl/fsbl.elf"]
if {$mode ne "backup" && $mode ne "program"} { puts "uso: backup|program <parte> <fichero>"; exit 1 }
if {![file exists $fsbl]} { puts "ERROR: no existe $fsbl"; exit 1 }
if {$mode eq "program" && ![file exists $file]} { puts "ERROR: no existe $file"; exit 1 }

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set parts [get_cfgmem_parts $part]
if {[llength $parts] == 0} { puts "ERROR: Vivado no conoce la parte '$part'"; exit 1 }
create_hw_cfgmem -hw_device $dev [lindex $parts 0]
set cm [current_hw_cfgmem]
set_property PROGRAM.ZYNQ_FSBL $fsbl $cm
set_property PROGRAM.ADDRESS_RANGE {use_file} $cm
set_property PROGRAM.BLANK_CHECK 0 $cm
if {$mode eq "backup"} {
    puts "leyendo 16 MB de la QSPI a $file ..."
    set_property PROGRAM.FILES [list] $cm
    set_property PROGRAM.ADDRESS_RANGE {entire_device} $cm
    # 2019.2 no tiene -size: -datacount (en bytes para BIN) y, si tampoco, -all
    if {[catch {readback_hw_cfgmem -hw_cfgmem $cm -file $file -format BIN -offset 0 -datacount 16777216} e]} {
        puts "readback con -datacount fallo ($e); probando -all"
        readback_hw_cfgmem -hw_cfgmem $cm -file $file -format BIN -all
    }
    puts "BACKUP_OK: $file"
} else {
    puts "grabando $file en la QSPI (offset 0) ..."
    set_property PROGRAM.FILES [list $file] $cm
    set_property PROGRAM.ERASE 1 $cm
    set_property PROGRAM.CFG_PROGRAM 1 $cm
    set_property PROGRAM.VERIFY 1 $cm
    set_property PROGRAM.CHECKSUM 0 $cm
    program_hw_cfgmem -hw_cfgmem $cm
    puts "PROGRAM_OK: $file grabado y verificado. SW1 en QSPI (ON-OFF) y a encender."
}
close_hw_manager
exit
