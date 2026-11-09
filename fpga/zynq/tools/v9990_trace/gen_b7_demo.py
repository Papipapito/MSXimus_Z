# -*- coding: utf-8 -*-
# gen_b7_demo.py [salida.rpl] [il | b3 | b2 | b4 | b5]
#   Traza de E/S (formato de mk_replay.py: "W pp vv ms") que pone el V9990 en B7 (1024 x 212, 4 bpp; con "il",
#   1024 x 424 entrelazado) y pinta un escritorio de prueba: marco de 1 px en el borde de la imagen, marcas de
#   columna cada 128 px, barras de 1 px alternas (abajo a la izquierda, para ver el mapeo 1:1 del punto), una
#   ventana "Info" con texto y el hueco transparente de la ventana del V9968 (512 x 106 en (256,53): el MSX entero a x0,5).
#   Para pasarla por la cadena entera del V9990 (tb/run_v9990_chain.sh ... +FRAMEOUT= y EXTRA=+FRAMEFULL=1) y
#   VER lo que saldria por el HDMI sin placa. La fuente es la de la BIOS (CGTABL, del pack). 28/10/2026.
#   b5 (29/10): el mismo escritorio en B5 (640 x 400, HSCN; XIMM 1024 a 4 bpp = 512 B por linea) con el hueco de
#   256 x 212 en (192,94): a x2 / x1,5 son los mismos 512 x 318 px de pantalla (384..896 x 201..519) que en B7.
import os, struct, sys
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "b7_demo.rpl")
il = len(sys.argv) > 2 and sys.argv[2] == "il"
b3 = len(sys.argv) > 2 and sys.argv[2] == "b3"      # el mismo escritorio en B3 (512 puntos), para comparar la alineacion del core
b2 = len(sys.argv) > 2 and sys.argv[2] == "b2"      # y en B2 (384 puntos, overscan, maestro de 14 MHz)
b4 = len(sys.argv) > 2 and sys.argv[2] == "b4"      # y en B4 (768 puntos, overscan, 14 MHz a 1/1)
b5 = len(sys.argv) > 2 and sys.argv[2] == "b5"      # y en B5 (640 x 400, HSCN, 21 MHz a 1/1; 29/10/2026)
pack = os.path.join(here, "..", "..", "..", "..", "bios", "packs", "msximus", "nextor-2.1.4", "pack_bios_msximus.bin")
d = open(pack, "rb").read()
bios = 0x60000
cg = struct.unpack("<H", d[bios + 4:bios + 6])[0]
font = d[bios + cg: bios + cg + 256 * 8]

H = 424 if il else 212          # lineas de la imagen
W = 384 if b2 else 512 if b3 else 768 if b4 else 640 if b5 else 1024    # puntos por linea
STRIDE = 256 if b2 else 512 if (b4 or b5) else W // 2    # bytes por linea de VRAM a 4 bpp (B2: XIMM 512; B4/B5: XIMM 1024)
H = 240 if (b2 or b4) else 400 if b5 else H              # B2/B4: 240 lineas (overscan); B5: 400
ry = 2 if il else 1             # filas por fila de glifo (entrelazado: texto de 8 x 16)
# el hueco de la ventana del V9968 (el MSX entero a x0,5): B5 256 x 212 puntos en (192,94); el resto 512 x 106 en (W/4, 53)
hx, hy, hw, hh = (192, 94, 256, 212) if b5 else (W // 4, 53 * ry, W // 2, 106 * ry)
ev = []
t = [0]
def w(port, val):
    ev.append("W %02X %02X %d" % (port, val & 0xFF, t[0] // 1000))
    t[0] += 2
def reg(r, v): w(0x64, r); w(0x63, v)

w(0x67, 1 if (b2 or b4) else 0)          # P#7 bit 0 = MCS: maestro de 14 MHz en B2/B4
# R#6 = 1010 1001: bitmap, DCKM 1/1, XIMM 1024, 4 bpp; R#7: MCS 0 (21 MHz) (+ EO e IL si entrelazado)
for r, v in [(8, 0x00), (6, 0x95 if (b3 or b2) else 0xA9), (7, 0x06 if il else 0x01 if b5 else 0x00), (13, 0x00), (14, 0x00), (15, 0x02)]: reg(r, v)   # B3/B2: DCKM 1/2, XIMM 512; B5: HSCN
# paleta: 0 negro transp, 1 naranja, 2 azul, 3 blanco, 4 gris, 5 negro TRANSPARENTE (el hueco), 6 verde, 7 rojo
for b in [0x80, 0x00, 0x00,  0x1F, 0x10, 0x00,  0x08, 0x08, 0x1F,  0x1F, 0x1F, 0x1F,  0x08, 0x08, 0x08,  0x80, 0x00, 0x00,
          0x00, 0x1F, 0x00,  0x1F, 0x00, 0x00]: w(0x61, b)
def fill(x, y, wd, h, c):              # LMMV, color c en los dos nibbles
    reg(36, x & 255); reg(37, x >> 8); reg(38, y & 255); reg(39, y >> 8)
    reg(40, wd & 255); reg(41, wd >> 8); reg(42, h & 255); reg(43, h >> 8)
    reg(45, 0x0C); reg(46, 0xFF); reg(47, 0xFF); reg(48, c); reg(49, c); reg(52, 0x20)
    t[0] += 3000
fill(0, 0, W, H, 0x22)                            # fondo azul
fill(0, 0, W, 1, 0x33); fill(0, H - 1, W, 1, 0x33)           # marco de 1 px (blanco)
fill(0, 0, 1, H, 0x33); fill(W - 1, 0, 1, H, 0x33)
for x in range(W // 8, W, W // 8):                # marcas de columna (verde), 1 px de ancho
    fill(x, 0, 1, 8 * ry, 0x66)
for x in range(0, 64, 2):                         # barras alternas blanco/rojo de 1 px, abajo a la izquierda
    fill(x, H - 12 * ry, 1, 8 * ry, 0x33); fill(x + 1, H - 12 * ry, 1, 8 * ry, 0x77)
fill(8, 16 * ry, 232, 48 * ry, 0x11); fill(10, 18 * ry, 228, 44 * ry, 0x44)      # ventana Info (marco naranja, gris)
fx, fy, fw, fh = (190, 92, 260, 216) if b5 else (W // 4 - 2, 51 * ry, W // 2 + 4, 110 * ry)   # su marco (en B7 IL, 2 lineas mas que el hueco doblado)
fill(fx, fy, fw, fh, 0x11)                        # marco de la ventana del V9968 (naranja)
fill(hx, hy, hw, hh, 0x55)                        # hueco transparente: el MSX entero a x0,5 (512 x 318 px = 106 lineas de B7, 212 de B5)
def char(ch, x, y, col):               # 8 x 8 (x 1 o 2 filas), direccion = y * 512 + x / 2 (1024 px a 4 bpp)
    g = font[ch * 8: ch * 8 + 8]
    for row in range(8):
        for rr in range(ry):
            a = (y + row * ry + rr) * STRIDE + x // 2
            reg(0, a & 255); reg(1, (a >> 8) & 255); reg(2, (a >> 16) & 7)
            bits = g[row]
            for i in range(4):
                hi = (col & 0xF0) if (bits & 0x80) else ((col & 0x0F) << 4)
                bits = (bits << 1) & 0xFF
                lo = (col >> 4) if (bits & 0x80) else (col & 0x0F)
                bits = (bits << 1) & 0xFF
                w(0x60, hi | lo)
def text(s, x, y, col):
    for i, ch in enumerate(s):
        char(ord(ch), x + 8 * i, y, col)
text("MSXimus Z  V9991", 14, 20 * ry, 0x34)
text("%s %dx%d%s" % ("B2" if b2 else "B3" if b3 else "B4" if b4 else "B5" if b5 else "B7", W, H, " IL" if il else ""), 14, 30 * ry, 0x34)
text("V9968 x0.5 ->", 14, 40 * ry, 0x34)
for x in range(W // 8, W, W // 8):
    text("%d" % x, x + 2, 2 * ry, 0x32)
text("%d" % (W - 1), W - 1 - 36, 2 * ry, 0x32)
text("V9968 ->", hx - 70, 202 if b5 else 100 * ry, 0x31)
for r, v in [(55, 0xA4), (56, hx & 255), (57, hx >> 8), (58, hy & 255), (59, hy >> 8), (60, 0), (61, 0), (62, 0)]: reg(r, v)   # ventana en WX = hx, WY = hy, x0,5
reg(8, 0xE0)
open(out, "w", newline="\n").write("\n".join(ev) + "\n")
print("eventos:", len(ev), "->", out, "|", "B2" if b2 else "B3" if b3 else "B4" if b4 else "B5" if b5 else "B7", W, "x", H, "entrelazado" if il else "", "| fuente CGTABL", hex(cg))
