# mk_edge.py <salida.rpl> <modo> [R7 (0x06)]: en cada fila r de 0..423 el pixel 0 = A (azul) y el ultimo pixel = B (verde); resto negro.
#   modo (B3 512 px): bd16 | bd8 | pal8 | pal4 | pal2    (B1 256 px): b1_bd16 | b1_bd8 | b1_pal8
#   paleta: entradas 1 = azul, 2 = verde
import sys
out, modo = sys.argv[1], sys.argv[2]
r7 = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x06
ev = []
def w(p, v): ev.append("W %02X %02X 0" % (p, v))
def reg(i, v): w(0x64, i); w(0x63, v)
w(0x67, 2); w(0x67, 0)
b1 = modo.startswith('b1_'); m = modo[3:] if b1 else modo
W = 256 if b1 else 512
r6 = {'bd16': 0x97, 'bd8': 0x96, 'pal8': 0x96, 'pal4': 0x95, 'pal2': 0x94}[m] - (0x14 if b1 else 0)   # B1: DCKM = 00, XIMM = 00 (0x83 / 0x82)
bits = {'bd16': 16, 'bd8': 8, 'pal8': 8, 'pal4': 4, 'pal2': 2}[m]
bytes_per_row = W * bits // 8
reg(6, r6)
reg(7, r7); reg(8, 0x02); reg(9, 0)
reg(13, 0x40 if m == 'bd8' else 0x00); reg(15, 0)
if m.startswith('pal'):
    reg(14, 0x04)
    for rgb in ((0, 0, 31), (0, 31, 0)):
        for c in rgb: w(0x61, c)
def px_bytes(x, v):
    if m == 'bd16': return [(2 * x, v & 255), (2 * x + 1, v >> 8)]
    if m in ('bd8', 'pal8'): return [(x, v)]
    if m == 'pal4': return [(x // 2, v << 4 if x % 2 == 0 else v)]
    if m == 'pal2': return [(x // 4, v << (6 - 2 * (x % 4)))]
vals = {'bd16': (0x001F, 0x7C00), 'bd8': (0x03, 0xE0), 'pal8': (1, 2), 'pal4': (1, 2), 'pal2': (1, 2)}[m]
for r in range(424):
    for x, v in ((0, vals[0]), (W - 1, vals[1])):
        for off, b in px_bytes(x, v):
            a = r * bytes_per_row + off
            w(0x64, 0); w(0x63, a & 255); w(0x63, (a >> 8) & 255); w(0x63, (a >> 16) & 7)
            w(0x60, b)
reg(8, 0x82)
open(out, "w", newline="\n").write("\n".join(ev) + "\n")
print(len(ev), "eventos ->", out)
