#!/usr/bin/env python3
"""frames_to_png.py — las paginas volcadas por tb_geo3d_sys.sv (o tb_system.v de Alex) a PNG y GIF.
SCREEN 5: 2 pixeles por byte, x par en el nibble alto. La paleta es la de run_kanon_rom.py (r g b en 0..7).
Uso: frames_to_png.py frames.hex palette.txt <prefijo_salida> [escala=2] [gif_fps=15]
  -> <prefijo>_NNN.png por pagina y <prefijo>.gif con todas."""
import sys
from PIL import Image

W, H = 256, 212
PAGE = H * 128
hexf, palf, pre = sys.argv[1:4]
scale = int(sys.argv[4]) if len(sys.argv) > 4 else 2
fps = int(sys.argv[5]) if len(sys.argv) > 5 else 15
pal = [tuple(int(c) for c in l.split()) for l in open(palf) if l.strip()]
flat = []
for r, g, b in pal:
    flat += [round(r * 255 / 7), round(g * 255 / 7), round(b * 255 / 7)]
raw = bytes(int(l, 16) for l in open(hexf) if l.strip())
imgs = []
for n in range(len(raw) // PAGE):
    p = raw[n * PAGE:(n + 1) * PAGE]
    pix = bytearray(W * H)
    pix[0::2] = bytes(b >> 4 for b in p)
    pix[1::2] = bytes(b & 15 for b in p)
    img = Image.frombytes("P", (W, H), bytes(pix))
    img.putpalette(flat + [0] * (768 - len(flat)))
    img = img.convert("RGB").resize((W * scale, H * scale), Image.NEAREST)
    img.save(f"{pre}_{n:03d}.png")
    imgs.append(img)
if imgs:
    imgs[0].save(f"{pre}.gif", save_all=True, append_images=imgs[1:], duration=1000 // fps, loop=0)
print(f"{len(imgs)} paginas -> {pre}_NNN.png, {pre}.gif")
