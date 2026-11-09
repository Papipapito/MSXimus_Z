#!/usr/bin/env python3
"""osd_render.py — vista previa del OSD de la Zynq con color (30/09/2026): pinta una pagina de celdas como lo haria
zynq/textdisp_z.v (misma fuente y paleta: tools/osd_fuente.py).

    python osd_render.py celdas.txt salida.png [escala]     (PNG si hay Pillow; si no, o con salida .ppm, PPM)

celdas.txt: 28 lineas de 32 palabras hexadecimales AACC (atributo, caracter), como las vuelca el banco del companion
(arm/companion/tests/ota_host) o tb_textdisp_z. Sirve para disenar las paginas sin compilar el bitstream y para
comparar pixel a pixel con la simulacion del RTL (--comparar frame.ppm).
"""
import sys

import osd_fuente as F

FUENTE = F.fuente()


def rgb8(c5):
    return tuple(v * 255 // 31 for v in c5)


def leer_celdas(ruta):
    filas = []
    for linea in open(ruta, encoding="ascii"):
        p = linea.split()
        if p:
            filas.append([int(x, 16) for x in p[:32]] + [0] * (32 - len(p[:32])))
    while len(filas) < 28:
        filas.append([0] * 32)
    return filas[:28]


def pintar(celdas):
    """256 x 224 pixeles RGB555 (tuplas 0..31)."""
    img = []
    for y in range(224):
        fila = []
        for x in range(256):
            c = celdas[y >> 3][x >> 3]
            ch, at = c & 0xFF, c >> 8
            bit = FUENTE[ch][y & 7] >> (x & 7) & 1
            fila.append(F.PALETA[at & 15][1] if bit else F.PALETA[at >> 4][2])
        img.append(fila)
    return img


def guardar(img, ruta, escala=3):
    h, w = len(img), len(img[0])
    if not ruta.lower().endswith(".ppm"):
        try:
            from PIL import Image
            im = Image.new("RGB", (w, h))
            im.putdata([rgb8(p) for fila in img for p in fila])
            im = im.resize((w * escala, h * escala), Image.NEAREST)
            im.save(ruta)
            return
        except ImportError:
            ruta = ruta.rsplit(".", 1)[0] + ".ppm"
    with open(ruta, "wb") as f:
        f.write(b"P6 %d %d 255\n" % (w, h))
        f.write(bytes(v for fila in img for p in fila for v in rgb8(p)))


def leer_ppm(ruta):
    d = open(ruta, "rb").read()
    partes = d.split(maxsplit=4)
    w, h = int(partes[1]), int(partes[2])
    px = partes[4]
    return [[tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3]) for x in range(w)] for y in range(h)]


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[2] == "--comparar":
        img = [[rgb8(p) for p in fila] for fila in pintar(leer_celdas(sys.argv[1]))]
        sim = leer_ppm(sys.argv[3])
        mal = [(x, y) for y in range(224) for x in range(256) if img[y][x] != sim[y][x]]
        print("pixeles distintos: %d de %d" % (len(mal), 256 * 224) + ("" if not mal else ", el primero en %s" % (mal[0],)))
        sys.exit(1 if mal else 0)
    guardar(pintar(leer_celdas(sys.argv[1])), sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 3)
