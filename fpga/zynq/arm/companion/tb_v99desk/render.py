#!/usr/bin/env python3
"""render.py - dibuja lo que v99desk.c deja en la VRAM del V9990 (B5: 640 x 400 a 4 bpp, lineas de 1024 puntos = 512 B) a partir de la salida
"hex" de host.c (una entrada del anillo por linea: [15:14] tipo, [11:8] puerto, [7:0] dato; "#SNAP n" = guardar una imagen aqui).

Un modelo minimo del V9990 (no es el core): P#4 elige el registro y P#3 lo escribe (el registro se autoincrementa), P#0 escribe la VRAM en R#0-2
(bit 7 de R#2 = sin autoincremento), P#1 escribe la paleta en R#14 (R, G, B de 5 bits, con autoincremento) y R#52 = 20h es LMMV (R#36-43 =
DX, DY, NX, NY; R#48/49 = el color: un nibble por punto, el alto en los puntos pares). Los NOP y las esperas no hacen nada.
Uso: render.py <entradas.hex> <prefijo>   -> <prefijo>_<n>.png por cada #SNAP y <prefijo>_fin.png"""
import sys
from PIL import Image

vram = bytearray(512 * 1024)
pal = [(0, 0, 0)] * 16
regs = [0] * 64
rsel = 0
rinc = True
pal_i = 0
pal_c = 0
pal_t = [0, 0, 0]


def r16(a):
    return regs[a] | (regs[a + 1] << 8)


def vaddr():
    return regs[0] | (regs[1] << 8) | ((regs[2] & 7) << 16)


def set_vaddr(a):
    regs[0] = a & 255
    regs[1] = (a >> 8) & 255
    regs[2] = (regs[2] & 0xF8) | ((a >> 16) & 7)


def put_dot(x, y, c):
    a = y * 512 + (x >> 1)
    if a >= len(vram) or x < 0 or y < 0:
        return
    if x & 1:
        vram[a] = (vram[a] & 0xF0) | (c & 15)
    else:
        vram[a] = (vram[a] & 0x0F) | ((c & 15) << 4)


def lmmv():
    dx, dy, nx, ny = r16(36), r16(38), r16(40), r16(42)
    for j in range(ny):
        for i in range(nx):
            x = dx + i
            c = (regs[48] >> 4) if (x & 1) == 0 else (regs[48] & 15)
            put_dot(x, dy + j, c)


def escribe_reg(v):
    global rsel, pal_i, pal_c
    regs[rsel] = v
    if rsel == 52 and v == 0x20:
        lmmv()
    if rsel == 14:
        pal_i = v & 15
        pal_c = 0
    if rinc:
        rsel = (rsel + 1) & 63


def entrada(e):
    global rsel, pal_i, pal_c
    t, p, d = e >> 14, (e >> 8) & 15, e & 255
    if t != 0:
        return
    if p == 4:
        rsel = d & 63
    elif p == 3:
        escribe_reg(d)
    elif p == 0:
        a = vaddr()
        if a < len(vram):
            vram[a] = d
        if not (regs[2] & 0x80):
            set_vaddr(a + 1)
    elif p == 1:
        pal_t[pal_c] = d & 31
        pal_c += 1
        if pal_c == 3:
            pal[pal_i] = tuple((c << 3) | (c >> 2) for c in pal_t)
            pal_i = (pal_i + 1) & 15
            pal_c = 0


def imagen(ruta, ancho=640, alto=400):
    im = Image.new('RGB', (ancho, alto))
    px = im.load()
    for y in range(alto):
        for x in range(ancho):
            b = vram[y * 512 + (x >> 1)]
            px[x, y] = pal[(b >> 4) if (x & 1) == 0 else (b & 15)]
    im.save(ruta)


def main():
    hexf, pref = sys.argv[1], sys.argv[2]
    n = 0
    for l in open(hexf):
        l = l.strip()
        if l.startswith('#SNAP'):
            imagen('%s_%s.png' % (pref, l.split()[1]))
            continue
        if len(l) == 4:
            entrada(int(l, 16))
            n += 1
    imagen('%s_fin.png' % pref)
    print('render: %d entradas' % n)


main()
