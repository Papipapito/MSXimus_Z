# -*- coding: utf-8 -*-
# gen_v9991_demo.py [salida.rpl] [nombre_de_rom] [b7]
#   Genera la traza de E/S (formato de mk_replay.py: "W pp vv ms") que hace v9991_desktop (bios/src/v9991.asm)
#   -- el escritorio del V9990 de la demo de la ventana del V9968: tecla V (B1) o, con "b7", tecla B (B7 y el
#   juego entero a x0,5) -- para pasarla por la cadena entera del V9990 (tb/run_v9990_chain.sh ... +FRAMEOUT=)
#   y VER el escritorio que saldria por el HDMI sin placa. Es un espejo en Python del asm: los mismos registros,
#   la misma paleta, los mismos rellenos del blitter (16 bits) y el mismo texto por columnas con la fuente de
#   la BIOS (CGTABL, sacada del pack). Si se cambia uno hay que cambiar el otro.
import os, struct, sys
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "v9991_demo.rpl")
romname = sys.argv[2] if len(sys.argv) > 2 else "ANTARCTIC ADVENTURE.ROM"
b7 = len(sys.argv) > 3 and sys.argv[3] == "b7"
pack = os.path.join(here, "..", "..", "..", "..", "bios", "packs", "msximus", "nextor-2.1.4", "pack_bios_msximus.bin")
d = open(pack, "rb").read()
bios = 0x60000
cg = struct.unpack("<H", d[bios + 4:bios + 6])[0]
font = d[bios + cg: bios + cg + 256 * 8]
STRIDE = 512 if b7 else 128

ev = []
t = [0]
def w(port, val):
    ev.append("W %02X %02X %d" % (port, val & 0xFF, t[0] // 1000))
    t[0] += 2          # ~2 us por OUT (orden de magnitud de un OUT (n),A a 3,58 MHz)
def reg(r, v): w(0x64, r); w(0x63, v)

# v9991_desktop
w(0x67, 0)
for r, v in [(8, 0x00), (6, 0xA9 if b7 else 0x81), (7, 0x00), (13, 0x00), (14, 0x00), (15, 0x02)]: reg(r, v)
for b in [0x80, 0x00, 0x00,  0x1F, 0x10, 0x00,  0x08, 0x08, 0x1F,  0x1F, 0x1F, 0x1F,  0x08, 0x08, 0x08,  0x80, 0x00, 0x00]: w(0x61, b)
def fill(x, y, wd, h, c):              # v9k_fill: LMMV con {dx, dy, nx, ny} de 16 bits
    reg(36, x & 255); reg(37, x >> 8); reg(38, y & 255); reg(39, 0)
    reg(40, wd & 255); reg(41, wd >> 8); reg(42, h & 255); reg(43, 0)
    reg(45, 0x0C); reg(46, 0xFF); reg(47, 0xFF); reg(48, c); reg(49, c); reg(52, 0x20)
    t[0] += 3000                        # el asm espera CE = 0 (el banco tambien)
if b7:
    rects = [(0, 0, 1024, 212, 0x22), (8, 8, 200, 40, 0x11), (10, 10, 196, 36, 0x44),
             (254, 41, 516, 120, 0x11), (256, 53, 512, 106, 0x55)]   # 5 = transparente: el MSX entero a x0,5
else:
    rects = [(0, 0, 256, 212, 0x22), (6, 6, 90, 34, 0x11), (8, 8, 86, 30, 0x44),
             (100, 6, 150, 200, 0x11), (102, 16, 146, 190, 0x55)]   # 5 = transparente (el 0 es el borde)
for x, y, wd, h, c in rects:
    fill(x, y, wd, h, c)
def char(ch, col, y, color):           # v9k_char: columna de 8 px, direccion = y * STRIDE + col * 4
    g = font[ch * 8: ch * 8 + 8]
    for row in range(8):
        a = (y + row) * STRIDE + col * 4
        reg(0, a & 255); reg(1, (a >> 8) & 255); reg(2, (a >> 16) & 7)
        bits = g[row]
        for i in range(4):
            hi = (color & 0xF0) if (bits & 0x80) else ((color & 0x0F) << 4)
            bits = (bits << 1) & 0xFF
            lo = (color >> 4) if (bits & 0x80) else (color & 0x0F)
            bits = (bits << 1) & 0xFF
            w(0x60, hi | lo)
def text(s, col, y, color, nmax=64):
    for i, ch in enumerate(s[:nmax]):
        char(ord(ch), col + i, y, color)
if b7:
    text("MSXimus Z", 2, 12, 0x34); text("V9991 B7", 2, 22, 0x34); text("x0,5 ->", 2, 32, 0x34)
    text(romname, 33, 43, 0x31, 18)
    wregs = [(55, 0xA4), (56, 0), (57, 1), (58, 53), (59, 0), (60, 0), (61, 0), (62, 0)]
else:
    text("MSXimus Z", 2, 10, 0x34); text("V9991 demo", 2, 20, 0x34); text("Ventana ->", 2, 30, 0x34)
    text(romname, 13, 8, 0x31, 18)
    wregs = [(55, 0xA0), (56, 102), (57, 0), (58, 16), (59, 0), (60, 55), (61, 11), (62, 190)]
for r, v in wregs: reg(r, v)
reg(8, 0xE0)
open(out, "w", newline="\n").write("\n".join(ev) + "\n")
print("eventos:", len(ev), "->", out, "|", "B7 x0,5" if b7 else "B1", "| fuente CGTABL", hex(cg))
