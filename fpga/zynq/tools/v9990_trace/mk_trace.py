# -*- coding: utf-8 -*-
# mk_trace.py <ROM> <romtype> <segundos> <tag> [tecla_seg]
#   Genera y ejecuta un script tcl de openMSX (sin el MCP) que traza TODO el trafico de E/S del V9990
#   (puertos 60h-6Fh, escrituras y lecturas, con el tiempo emulado en ms) con la extension gfx9000, y al
#   final vuelca los registros, la paleta y la VRAM del V9990.
#   Salida en esta carpeta: <tag>_io.txt, <tag>_regs.txt, <tag>_vram.bin, <tag>_pal.bin, <tag>_log.txt.
#   tecla_seg: si se da, pulsa ESPACIO (matriz 8 bit 0) en ese segundo (para pasar del titulo al juego).
#   Variables de entorno:
#     KEYS=18,26     mas pulsaciones de ESPACIO (segundos, separados por comas)
#     DUMPS=25,26.5  volcados intermedios <tag>_vram_<s>.bin (y registros, PC y estado en el log)
#     SHOTS=1        con ventana (sin "renderer none") y con videosource GFX9000: captura
#                    <tag>_shot_<s>.png en cada volcado. Sin SHOTS va sin pantalla.
#   Lecturas: en un watchpoint read_io, $::wp_last_value NO trae el dato leido; el valor se toma del puerto
#   con "debug read ioports" (peek, sin efectos laterales; el watchpoint salta antes de la lectura).
#   Debuggables del GFX9000 en openMSX: "Sunrise GFX9000 regs/VRAM/palette". La VRAM sale en el orden
#   FISICO de los dos bancos (diff_vram.py la pasa al logico). wp_last_address trae A/B en el byte alto
#   (OUT (n),A / OUT (C),r): se enmascara a 8 bits.
import os, sys, subprocess, io
rom, romtype, secs, tag = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
keys = [k for k in os.environ.get("KEYS", "").split(",") if k]
if len(sys.argv) > 5: keys.insert(0, sys.argv[5])
shots = os.environ.get("SHOTS", "") not in ("", "0")
here = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
tcl = here + "/" + tag + ".tcl"
io.open(tcl, "w", newline="\n").write(r'''
%(video)s
set throttle off
set ::io_fh [open "%(here)s/%(tag)s_io.txt" w]
set ::log_fh [open "%(here)s/%(tag)s_log.txt" w]
puts $::log_fh "debuggables: [debug list]"
proc tms {} { return [expr {int([machine_info time] * 1000)}] }
debug set_watchpoint write_io {0x60 0x6F} {} { puts $::io_fh "W [format %%02X [expr {$::wp_last_address & 0xFF}]] [format %%02X $::wp_last_value] [tms]" }
debug set_watchpoint read_io  {0x60 0x6F} {} { set a [expr {$::wp_last_address & 0xFF}]; puts $::io_fh "R [format %%02X $a] [format %%02X [debug read ioports $a]] [tms]" }
%(key)s
proc rr {n} { if {[catch {reg $n} v]} { return "?" }; return [format %%X $v] }
proc dump_at {s} {
    set vf [open "%(here)s/%(tag)s_vram_$s.bin" w]
    fconfigure $vf -translation binary
    puts -nonewline $vf [debug read_block {Sunrise GFX9000 VRAM} 0 [debug size {Sunrise GFX9000 VRAM}]]
    close $vf
    set r ""
    for {set i 0} {$i < 64} {incr i} { append r [format "R#%%d=%%02X " $i [debug read {Sunrise GFX9000 regs} $i]] }
    puts $::log_fh "dump $s s: PC=[rr pc] IFF=[rr iff] IM=[rr im] I=[rr i] SP=[rr sp] st65=[format %%02X [debug read ioports 0x65]] st66=[format %%02X [debug read ioports 0x66]] $r"
    puts $::io_fh "D $s"
    catch { screenshot -raw "%(here)s/%(tag)s_shot_$s.png" }
}
%(dumps)s
after time %(secs)d {
    set rf [open "%(here)s/%(tag)s_regs.txt" w]
    foreach nm [debug list] {
        if {[string match "Sunrise*" $nm]} { puts $rf "$nm size=[debug size $nm]" }
    }
    set s ""
    for {set i 0} {$i < 64} {incr i} { catch { append s [format "R#%%d=%%02X " $i [debug read {Sunrise GFX9000 regs} $i]] } }
    puts $rf $s
    close $rf
    set vf [open "%(here)s/%(tag)s_vram.bin" w]
    fconfigure $vf -translation binary
    catch { puts -nonewline $vf [debug read_block {Sunrise GFX9000 VRAM} 0 [debug size {Sunrise GFX9000 VRAM}]] } e
    puts $::log_fh "vram err: $e"
    close $vf
    set pf [open "%(here)s/%(tag)s_pal.bin" w]
    fconfigure $pf -translation binary
    catch { puts -nonewline $pf [debug read_block {Sunrise GFX9000 palette} 0 [debug size {Sunrise GFX9000 palette}]] } e
    puts $::log_fh "pal err: $e"
    close $pf
    puts $::log_fh "fin t=[machine_info time]"
    close $::io_fh
    close $::log_fh
    exit
}
''' % dict(here=here, tag=tag, secs=secs,
           video="after time 1.0 { catch { set videosource GFX9000 } }" if shots else "set renderer none",
           key=chr(10).join("after time %s { keymatrixdown 8 1; after time 0.3 { keymatrixup 8 1 } }" % k for k in keys),
           dumps=chr(10).join("after time %s { dump_at %s }" % (s, s) for s in os.environ.get("DUMPS", "").split(",") if s)))
cmd = ["C:/Program Files/openMSX/openmsx.exe", "-machine", "C-BIOS_MSX2+", "-ext", "gfx9000",
       "-carta", rom, "-romtype", romtype, "-script", tcl]
print(" ".join(cmd))
r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
print("exit", r.returncode, (r.stdout or "")[-300:], (r.stderr or "")[-300:])
for f in ("_io.txt", "_regs.txt", "_vram.bin", "_pal.bin", "_log.txt"):
    p = here + "/" + tag + f
    print(f, os.path.getsize(p) if os.path.exists(p) else "NO")
