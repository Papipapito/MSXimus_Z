#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Basado en gen_face_tables.py de Alex Moncks (MIT). MSXimus Z, 27/09/2026.
"""geo_msximus_tables.asm para geo3d_msximus_demo.asm: la palabra "MSXIMUS" como bloques extruidos y sombreados
(29 bloques, 232 vertices, 174 caras), paleta roja/azul, luz y la tabla de rotacion de gen_tables.py."""
import math
import gen_face_tables as gf
from gen_tables import FRAMES, matrix as spin_matrix, words_db, db_lines

# letras nuevas en la rejilla 5 x 7 de gf.FONT: (x, y, w, h), y hacia arriba
gf.FONT.update({
    "M": [(0, 0, 1, 7), (4, 0, 1, 7), (1, 5, 1, 1), (3, 5, 1, 1), (2, 4, 1, 1)],
    "S": [(0, 6, 5, 1), (0, 4, 1, 2), (0, 3, 5, 1), (4, 1, 1, 2), (0, 0, 5, 1)],
    "X": [(0, 4, 2, 3), (3, 4, 2, 3), (2, 3, 1, 1), (0, 0, 2, 3), (3, 0, 2, 3)],
    "I": [(2, 0, 1, 7)],
    "U": [(0, 1, 1, 6), (4, 1, 1, 6), (0, 0, 5, 1)],
})
gf.TEXT = "MSXIMUS"
gf.U = 15               # 7 letras (42,2 unidades) al ancho de "GEO3D" (29,8 a U = 22)
gf.DEPTH = 18
TZ = 820
LIGHT = (-0.45, 0.55, -0.70)


def palette():
    """0 negro, 1..7 rampa roja (tapas), 8..14 rampa azul (lados), 15 blanco."""
    def ramp(rgb):
        return [tuple(min(7, round(c * (0.28 + 0.72 * l / 6))) for c in rgb) for l in range(7)]
    cols = [(0, 0, 0)] + ramp((7, 2, 2)) + ramp((2, 4, 7)) + [(7, 7, 7)]
    b = []
    for r, g, bl in cols:
        b += [(r << 4) | bl, g]
    return cols, b


def main():
    verts, faces = gf.model()
    ln = math.sqrt(sum(c * c for c in LIGHT))
    light = [round(c / ln * 16384) for c in LIGHT]
    cols, pal = palette()
    lines = ["; generado por gen_msximus_tables.py, no editar",
             f"NVERT:\tequ {len(verts)}", f"NFACE:\tequ {len(faces)}", f"NFRAMES:\tequ {FRAMES}", ""]
    vb = []
    for v in verts:
        vb += words_db(v)
    lines += db_lines("model_vertices", vb)
    fb = []
    for ids, n, base in faces:
        fb += ids + words_db(n) + [base]
    lines += db_lines("model_faces", fb, per=11)
    lines += db_lines("light_words", words_db(light))
    lines += db_lines("palette", pal, per=16)
    mt = []
    for k in range(FRAMES):
        m = spin_matrix(k)
        mt += words_db(m[:9] + [0, 0, TZ])
    lines += db_lines("matrix_table", mt, per=24)
    open("geo_msximus_tables.asm", "w").write("\n".join(lines) + "\n")
    open("msximus_palette.txt", "w").write("\n".join(f"{r} {g} {b}" for r, g, b in cols) + "\n")
    print(f"MSXIMUS: {len(verts)} vertices, {len(faces)} caras, luz {light}, {FRAMES} matrices")


if __name__ == "__main__":
    main()
