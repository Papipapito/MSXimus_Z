# -*- coding: utf-8 -*-
# mk_replay.py <tag>_io.txt <ms_max> <salida.rpl> — convierte la traza de E/S de openMSX en un fichero de
# replay para tb_t9990_timing (+REPLAY=): solo escrituras a 60h-6Fh y lecturas de 60h/62h (tienen efecto),
# hasta ms_max. Formato: "W pp vv ms" / "R pp 00 ms" por linea (el ms sirve para los volcados +DUMPS=).
# Las lecturas de estado (65h/66h) se quitan: el banco espera CE=0 antes de tocar la VRAM/R#32-52 y TR=1
# antes de P#2.
import sys
fn, ms_max, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
n = 0
with open(out, "w", newline="\n") as o:
    for line in open(fn):
        p = line.split()
        if len(p) < 4: continue
        d, port, val, ms = p[0], int(p[1], 16), int(p[2], 16), int(p[3])
        if ms > ms_max: break
        if d == "W":
            o.write("W %02X %02X %d\n" % (port, val, ms)); n += 1
        elif port in (0x60, 0x62):
            o.write("R %02X 00 %d\n" % (port, ms)); n += 1
print("eventos de replay:", n, "->", out)
