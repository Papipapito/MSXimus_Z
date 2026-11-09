# -*- coding: utf-8 -*-
# diff_vram.py <openmsx_vram.bin> <tb_vram.bin> <bpp> <ancho_px> [y_max] [--logico] [--zona x0-x1,y0-y1[,nombre]]...
#   Compara la VRAM del V9990 de openMSX con la del banco (modo Bx: direccion lineal, pitch = ancho_px*bpp/8)
#   y resume las diferencias por regiones (filas con bytes distintos, rango de X en pixeles, y primeros ejemplos).
#   El debuggable "Sunrise GFX9000 VRAM" de openMSX (mk_trace.py) esta en el orden FISICO de los dos bancos de
#   256 KB: fisico = ((L & 1) << 18) | (L >> 1), con L la direccion logica de los modos Bx (la del banco).
#   Se pasa al orden logico antes de comparar; --logico si el volcado de openMSX ya esta en orden logico.
#   y_max: solo se comparan las filas 0..y_max-1 (por defecto, toda la VRAM).
#   --zona: cuenta los bytes distintos dentro de un rectangulo en pixeles (puede repetirse), p. ej.
#   --zona 176-207,8-47,retrato
import sys
args = [a for a in sys.argv[1:] if not a.startswith("--")]
logico = "--logico" in sys.argv
zonas = []
for i, a in enumerate(sys.argv):
    if a == "--zona" and i + 1 < len(sys.argv):
        p = sys.argv[i + 1].split(",")
        x0, x1 = (int(v) for v in p[0].split("-")); y0, y1 = (int(v) for v in p[1].split("-"))
        zonas.append((x0, x1, y0, y1, p[2] if len(p) > 2 else "%s,%s" % (p[0], p[1])))
        args.remove(sys.argv[i + 1])
a = open(args[0], "rb").read(); b = open(args[1], "rb").read()
bpp = int(args[2]); w = int(args[3])
pitch = w * bpp // 8
n = min(len(a), len(b))
if not logico:
    a = bytes(a[((L & 1) << 18) | (L >> 1)] for L in range(n))
ymax = int(args[4]) if len(args) > 4 else n // pitch
n = min(n, ymax * pitch)
diff = [i for i in range(n) if a[i] != b[i]]
print("bytes distintos: %d de %d (%.3f %%); no-cero openMSX=%d banco=%d" % (len(diff), n, 100.0 * len(diff) / n,
      sum(1 for x in a[:n] if x), sum(1 for x in b[:n] if x)))
for x0, x1, y0, y1, nom in zonas:
    bx0, bx1 = x0 * bpp // 8, (x1 * bpp + bpp - 1) // 8
    tot = (bx1 - bx0 + 1) * (y1 - y0 + 1)
    nd = sum(1 for y in range(y0, y1 + 1) for xb in range(bx0, bx1 + 1) if a[y * pitch + xb] != b[y * pitch + xb])
    print("zona %s (x %d..%d, filas %d..%d): %d bytes distintos de %d" % (nom, x0, x1, y0, y1, nd, tot))
rows = {}
for i in diff:
    y, x = divmod(i, pitch)
    rows.setdefault(y, []).append(x)
print("filas con diferencias: %d" % len(rows))
# agrupar filas contiguas con rango de columnas parecido
groups = []
for y in sorted(rows):
    xs = rows[y]; x0, x1 = min(xs) * 8 // bpp, max(xs) * 8 // bpp
    if groups and groups[-1][1] == y - 1 and abs(groups[-1][2] - x0) <= 8 and abs(groups[-1][3] - x1) <= 8:
        g = groups[-1]; groups[-1] = (g[0], y, min(g[2], x0), max(g[3], x1), g[4] + len(xs))
    else:
        groups.append((y, y, x0, x1, len(xs)))
for g in groups[:40]:
    print("  filas %4d-%4d  x %4d..%4d px  (%d bytes)" % g)
if len(groups) > 40: print("  ... %d grupos mas" % (len(groups) - 40))
# ejemplos
for i in diff[:12]:
    y, x = divmod(i, pitch)
    print("  ej. y=%d xbyte=%d: openMSX=%02X banco=%02X" % (y, x, a[i], b[i]))
