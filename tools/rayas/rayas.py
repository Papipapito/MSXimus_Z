# -*- coding: utf-8 -*-
# rayas.py <video.avi> [salida_dir] [umbral]: busca RAYAS TRANSITORIAS en una grabacion de la capturadora a 60 fps:
# pixeles que difieren (en ALGUN canal RGB) de al menos 3 de sus 4 vecinos temporales (n-2, n-1, n+1, n+2),
# agrupados en manchas bajas (<= 8 px de alto) y anchas (>= 10 px). Guarda el fotograma entero, un recorte
# ampliado y la tira anterior/actual/siguiente de cada hallazgo. Los cambios persistentes (cambio de pantalla)
# no cuentan; se listan aparte los fotogramas con mucho cambio respecto al anterior, como referencia de tiempo.
import sys, os, subprocess, numpy as np
from PIL import Image
W, H = 1280, 720
vid = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(vid)[0] + '_hits'
T = int(sys.argv[3]) if len(sys.argv) > 3 else 60
os.makedirs(out, exist_ok=True)
# -vsync 0: la capturadora entrega a veces un flujo VFR con r_frame_rate=600 y ffmpeg, sin esto, DUPLICA
# cada fotograma real ~10-50 veces para rellenar la linea de tiempo -> las rayas dejan de ser "transitorias".
p = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-vsync', '0', '-i', vid, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                     stdout=subprocess.PIPE, bufsize=W * H * 3 * 4)
def rd():
    b = p.stdout.read(W * H * 3)
    if len(b) < W * H * 3: return None
    return np.frombuffer(b, np.uint8).reshape(H, W, 3)
def dif(a, b):  # True donde algun canal difiere mas de T
    return (np.abs(a.astype(np.int16) - b.astype(np.int16)) > T).any(axis=2)
win = []
for _ in range(5):
    f = rd()
    if f is None: break
    win.append(f)
n = 2; hits = 0; resumen = []; cambios = []
while len(win) == 5:
    p2, p1, cur, n1, n2 = win
    d = dif(cur, p1)
    if d.sum() > W * H * 0.05: cambios.append(n)
    votos = d.astype(np.uint8) + dif(cur, p2) + dif(cur, n1) + dif(cur, n2)
    tr = votos >= 3
    cnt = int(tr.sum())
    if 20 <= cnt <= W * H * 0.02:
        rows = np.where(tr.sum(axis=1) >= 6)[0]
        if len(rows):
            for rb in np.split(rows, np.where(np.diff(rows) > 2)[0] + 1):
                y0, y1 = int(rb[0]), int(rb[-1])
                cols = np.where(tr[y0:y1 + 1].any(axis=0))[0]
                for c in np.split(cols, np.where(np.diff(cols) > 6)[0] + 1):
                    x0, x1 = int(c[0]), int(c[-1])
                    h, w = y1 - y0 + 1, x1 - x0 + 1
                    if h <= 8 and w >= 10 and y0 > 1:
                        hits += 1
                        resumen.append((n, y0, y1, x0, x1))
                        if hits <= 40:
                            Image.fromarray(cur).save(os.path.join(out, 'f%04d.png' % n))
                            cy0, cy1 = max(0, y0 - 12), min(H, y1 + 13)
                            cx0, cx1 = max(0, x0 - 24), min(W, x1 + 25)
                            Image.fromarray(cur[cy0:cy1, cx0:cx1]).resize(((cx1 - cx0) * 3, (cy1 - cy0) * 3), Image.NEAREST).save(
                                os.path.join(out, 'f%04d_y%03d_x%04d.png' % (n, y0, x0)))
                            Image.fromarray(np.concatenate([p1[cy0:cy1, cx0:cx1], cur[cy0:cy1, cx0:cx1], n1[cy0:cy1, cx0:cx1]], axis=0)).resize(
                                ((cx1 - cx0) * 3, (cy1 - cy0) * 9), Image.NEAREST).save(os.path.join(out, 'f%04d_y%03d_x%04d_pcn.png' % (n, y0, x0)))
    f = rd()
    if f is None: break
    win = win[1:] + [f]
    n += 1
print('fotogramas: %d   cambios de pantalla en f=%s' % (n + 3, cambios))
print('rayas transitorias:', hits)
for r in resumen[:80]:
    print('  f=%4d (%5.2f s)  y=%3d-%3d  x=%4d-%4d  (%d px ancho)' % (r[0], r[0] / 60.0, r[1], r[2], r[3], r[4], r[4] - r[3] + 1))
