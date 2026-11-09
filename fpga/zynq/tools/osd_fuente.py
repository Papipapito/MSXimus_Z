"""osd_fuente.py — fuente de 256 caracteres y paleta del OSD de la MSXimus Z (30/09/2026).

Una sola fuente de verdad para tres cosas:
  - la BRAM del textdisp (make_dpb_menu.py -> gowin_dpb_menu.v): 0..127 = la fuente ASCII de siempre (src/iosys/font.vh),
    128..255 = los glifos de aqui (bloques, marcos, iconos, letras con tilde);
  - la paleta de 16 colores del textdisp (make_dpb_menu.py -> osd_paleta.v): cada celda lleva un atributo
    {fondo[3:0], tinta[3:0]}; el 0 da el aspecto de antes (tinta amarilla, fondo negro);
  - companion/osd_glifos.h (codigos y tabla UTF-8 -> glifo) y tools/osd_render.py (vista previa en PNG).
Formato de un glifo: 8 filas de arriba abajo; en cada fila el caracter 0 es la columna de la IZQUIERDA (= bit 0, como
en font.vh y en textdisp: mem_do_b[x[2:0]]).
"""
import os
import re

AQUI = os.path.dirname(os.path.abspath(__file__))
FONT_VH = os.path.normpath(os.path.join(AQUI, "..", "..", "src", "iosys", "font.vh"))

# ---- paleta: (nombre, tinta RGB 0..31, fondo RGB 0..31) -----------------------------------------------------------
PALETA = [
    ("CLASICO",   (31, 31, 16), (0, 0, 0)),     # 0: tinta amarilla de siempre / fondo negro
    ("BLANCO",    (31, 31, 31), (31, 31, 31)),
    ("GRIS_CL",   (21, 22, 24), (21, 22, 24)),
    ("GRIS",      (13, 14, 16), (13, 14, 16)),
    ("GRIS_OSC",  (6, 7, 9),    (6, 7, 9)),
    ("NOCHE",     (2, 3, 7),    (2, 3, 7)),      # fondo de pagina
    ("AZUL",      (5, 11, 25),  (5, 11, 25)),
    ("CIAN",      (7, 24, 29),  (7, 24, 29)),
    ("VERDE",     (8, 26, 11),  (8, 26, 11)),
    ("VERDE_OSC", (2, 11, 5),   (2, 11, 5)),
    ("AMARILLO",  (31, 27, 5),  (31, 27, 5)),
    ("NARANJA",   (31, 16, 3),  (31, 16, 3)),
    ("ROJO",      (28, 6, 6),   (28, 6, 6)),
    ("VIOLETA",   (19, 9, 28),  (19, 9, 28)),
    ("MARINO",    (3, 6, 15),   (3, 6, 15)),     # paneles
    ("NEGRO",     (0, 0, 0),    (0, 0, 0)),
]


def bgr555(rgb):
    r, g, b = rgb
    return (b << 10) | (g << 5) | r


# ---- glifos 128..255 ------------------------------------------------------------------------------------------------
def _fila(bits):
    return sum(1 << i for i in range(8) if bits[i] == "#")


def _dib(*filas):
    assert len(filas) == 8 and all(len(f) == 8 for f in filas), filas
    return [_fila(f) for f in filas]


def _uni(v):
    return [v] * 8


def _ascii():
    s = open(FONT_VH, encoding="utf-8", errors="ignore").read()
    g = [[int(x.strip().split("'h")[1], 16) for x in r.split(",")] for r in re.findall(r"'\{([^}]*)\}", s)]
    assert len(g) == 128
    return g


ASCII = _ascii()


def _acento(base, acento, mayus=False):
    """base = caracter ASCII; acento = fila 0 (y fila 1 si es una lista de dos). Mayusculas: la letra se comprime a
    las filas 1..6 (se quita su fila 3) para dejar sitio arriba."""
    g = list(ASCII[ord(base)])
    if mayus:
        g = [0] + g[0:3] + g[4:7] + [0]
    acc = acento if isinstance(acento, list) else [acento]
    for i, f in enumerate(acc):
        g[i] = _fila(f)
    return g


GLIFOS = []          # (codigo, NOMBRE, bitmap[8], caracter unicode o None)


def glifo(nombre, bitmap, uni=None):
    GLIFOS.append((0x80 + len(GLIFOS), nombre, bitmap, uni))


# bloques
glifo("BLOQUE", _uni(0xFF), "█")
for n in range(1, 8):                                           # izquierda n/8: barras de progreso suaves
    glifo("IZQ%d" % n, _uni((1 << n) - 1), "▏▎▍▌▋▊▉"[n - 1])
glifo("MITAD_SUP", [0xFF] * 4 + [0] * 4, "▀")
glifo("MITAD_INF", [0] * 4 + [0xFF] * 4, "▄")
glifo("SOMBRA1", [0x11, 0x44] * 4, "░")
glifo("SOMBRA2", [0x55, 0xAA] * 4, "▒")
glifo("SOMBRA3", [0xEE, 0xBB] * 4, "▓")
# marcos (linea horizontal en la fila 3, vertical en la columna 3)
H, V = 0xFF, 0x08
glifo("H", [0, 0, 0, H, 0, 0, 0, 0], "─")
glifo("V", _uni(V), "│")
glifo("ESQ_SI", [0, 0, 0, 0xF8, V, V, V, V], "┌")
glifo("ESQ_SD", [0, 0, 0, 0x0F, V, V, V, V], "┐")
glifo("ESQ_II", [V, V, V, 0xF8, 0, 0, 0, 0], "└")
glifo("ESQ_ID", [V, V, V, 0x0F, 0, 0, 0, 0], "┘")
glifo("T_IZQ", [V, V, V, 0xF8, V, V, V, V], "├")
glifo("T_DER", [V, V, V, 0x0F, V, V, V, V], "┤")
glifo("T_ARR", [0, 0, 0, H, V, V, V, V], "┬")
glifo("T_ABA", [V, V, V, H, 0, 0, 0, 0], "┴")
glifo("CRUZ", [V, V, V, H, V, V, V, V], "┼")
glifo("RED_SI", _dib("........", "........", "........", ".....###", "....#...", "...#....", "...#....", "...#...."), "╭")
glifo("RED_SD", _dib("........", "........", "........", "###.....", "...#....", "...#....", "...#....", "...#...."), "╮")
glifo("RED_II", _dib("...#....", "...#....", "....#...", ".....###", "........", "........", "........", "........"), "╰")
glifo("RED_ID", _dib("...#....", "...#....", "..#.....", "###.....", "........", "........", "........", "........"), "╯")
glifo("H2", [0, 0, 0xFF, 0, 0xFF, 0, 0, 0], "═")
glifo("V2", _uni(0x14), "║")
# iconos
glifo("OK", _dib("........", ".......#", "......##", ".....##.", "#...##..", "##.##...", ".###....", "..#....."), "✓")
glifo("NO", _dib("........", "##....##", ".##..##.", "..####..", "...##...", "..####..", ".##..##.", "##....##"), "✗")
glifo("TRI_DER", _dib(".#......", ".##.....", ".###....", ".####...", ".###....", ".##.....", ".#......", "........"), "►")
glifo("TRI_IZQ", _dib("....#...", "...##...", "..###...", ".####...", "..###...", "...##...", "....#...", "........"), "◄")
glifo("TRI_ARR", _dib("........", "...#....", "..###...", ".#####..", "#######.", "........", "........", "........"), "▲")
glifo("TRI_ABA", _dib("........", "#######.", ".#####..", "..###...", "...#....", "........", "........", "........"), "▼")
glifo("CIRCULO", _dib("........", "..###...", ".#####..", ".#####..", ".#####..", "..###...", "........", "........"), "●")
glifo("ARO", _dib("........", "..###...", ".#...#..", ".#...#..", ".#...#..", "..###...", "........", "........"), "○")
glifo("ROMBO", _dib("...#....", "..###...", ".#####..", "#######.", ".#####..", "..###...", "...#....", "........"), "◆")
glifo("ESTRELLA", _dib("...#....", "...#....", "#######.", ".#####..", "..###...", ".##.##..", ".#...#..", "........"), "★")
glifo("BAJAR", _dib("..##....", "..##....", "..##....", "######..", ".####...", "..##....", "........", "######.."), "⤓")
glifo("SUBIR", _dib("######..", "........", "..##....", ".####...", "######..", "..##....", "..##....", "..##...."), "⤒")
glifo("AVISO", _dib("...##...", "..#..#..", "..#..#..", ".##..##.", ".######.", "###..###", "########", "........"), "⚠")
glifo("RED", _dib("........", ".######.", ".#.##.#.", ".#....#.", ".#....#.", ".##..##.", "..####..", "........"), "🖧")
glifo("CHIP", _dib("..#..#..", ".######.", "##....##", ".#.##.#.", ".#.##.#.", "##....##", ".######.", "..#..#.."), "▣")
glifo("SD", _dib("..#####.", ".##.#.#.", "#######.", "#######.", "#######.", "#######.", "#######.", "........"), "▤")
glifo("NOTA", _dib("...####.", "...#..#.", "...#..#.", "...#..#.", ".###.##.", "####.##.", ".##.....", "........"), "♪")
glifo("FLECHA_IZQ", _dib("........", "..#.....", ".##.....", "#######.", ".##.....", "..#.....", "........", "........"), "←")
glifo("FLECHA_DER", _dib("........", ".....#..", ".....##.", "#######.", ".....##.", ".....#..", "........", "........"), "→")
glifo("PUNTO_MEDIO", _dib("........", "........", "........", "...##...", "...##...", "........", "........", "........"), "·")
glifo("VINETA", _dib("........", "........", "..###...", "..###...", "..###...", "........", "........", "........"), "•")
glifo("PUNTOS", _dib("........", "........", "........", "........", "........", "........", "#..#..#.", "........"), "…")
glifo("POR", _dib("........", "........", ".#...#..", "..#.#...", "...#....", "..#.#...", ".#...#..", "........"), "×")
glifo("GRADO", _dib(".###....", "#...#...", ".###....", "........", "........", "........", "........", "........"), "°")
GIRO = [                                                        # "buscando": un cuarto lleno que gira (reloj)
    ("..####..", ".#..###.", "#...####", "#...####", "#......#", "#......#", ".#....#.", "..####.."),
    ("..####..", ".#....#.", "#......#", "#......#", "#...####", "#...####", ".#..###.", "..####.."),
    ("..####..", ".#....#.", "#......#", "#......#", "####...#", "####...#", ".###..#.", "..####.."),
    ("..####..", ".###..#.", "####...#", "####...#", "#......#", "#......#", ".#....#.", "..####.."),
]
for i, u in enumerate("◴◷◶◵"):
    glifo("GIRO%d" % i, _dib(*GIRO[i]), u)
glifo("TAPA_IZQ", _dib("...#####", ".#######", "########", "########", "########", "########", ".#######", "...#####"), "◖")
glifo("TAPA_DER", _dib("#####...", "#######.", "########", "########", "########", "########", "#######.", "#####..."), "◗")
glifo("DER_MITAD", _uni(0xF0), "▐")
glifo("LINEA_SUP", [0xFF, 0, 0, 0, 0, 0, 0, 0], "▔")
glifo("LINEA_INF", [0, 0, 0, 0, 0, 0, 0, 0xFF], "▁")
for n in range(1, 8):                                           # abajo n/8: medidores verticales
    glifo("ABA%d" % n, [0] * (8 - n) + [0xFF] * n, None)
# letras (castellano y catalan)
AGUDO, GRAVE, DIER = "...##...", ".##.....", "##..##.."
glifo("a_AGUDO", _acento("a", AGUDO), "á")
glifo("e_AGUDO", _acento("e", AGUDO), "é")
glifo("i_AGUDO", _acento("i", "...##..."), "í")
glifo("o_AGUDO", _acento("o", AGUDO), "ó")
glifo("u_AGUDO", _acento("u", AGUDO), "ú")
glifo("a_GRAVE", _acento("a", GRAVE), "à")
glifo("e_GRAVE", _acento("e", GRAVE), "è")
glifo("o_GRAVE", _acento("o", GRAVE), "ò")
glifo("u_DIER", _acento("u", DIER), "ü")
glifo("i_DIER", _acento("i", ".##.##.."), "ï")
glifo("n_TILDE", _acento("n", [".##..#..", "#..##..."]), "ñ")
glifo("c_CEDILLA", ASCII[ord("c")][:7] + [_fila("..##....")], "ç")
glifo("A_AGUDO", _acento("A", AGUDO, True), "Á")
glifo("E_AGUDO", _acento("E", "...##...", True), "É")
glifo("I_AGUDO", _acento("I", "...##...", True), "Í")
glifo("O_AGUDO", _acento("O", AGUDO, True), "Ó")
glifo("U_AGUDO", _acento("U", AGUDO, True), "Ú")
glifo("N_TILDE", _acento("N", "..####..", True), "Ñ")
glifo("C_CEDILLA", ASCII[ord("C")][:7] + [_fila("..##....")], "Ç")
def _espejo6(v):                                                 # simetria dentro de las 6 columnas de la letra
    return sum(1 << (5 - i) for i in range(6) if v >> i & 1)


glifo("ABRE_INTERROG", [_espejo6(ASCII[ord("?")][6 - i]) for i in range(7)] + [0], "¿")
glifo("ABRE_EXCLAM", [ASCII[ord("!")][6 - i] for i in range(7)] + [0], "¡")
glifo("ORDINAL_O", _dib(".##.....", "#..#....", ".##.....", "####....", "........", "........", "........", "........"), "º")
glifo("ORDINAL_A", _dib(".##.....", "..##....", "####....", "####....", "........", "........", "........", "........"), "ª")
glifo("EURO", _dib("..####..", ".##..##.", "#####...", ".##.....", "#####...", ".##..##.", "..####..", "........"), "€")
# cuadrantes (numeros grandes): bit 0 arriba-izq, 1 arriba-der, 2 abajo-izq, 3 abajo-der
while len(GLIFOS) < 0x70:
    glifo("LIBRE%02X" % (0x80 + len(GLIFOS)), [0] * 8)
for m in range(16):
    f = []
    for y in range(8):
        v = 0
        if m & (1 << (0 if y < 4 else 2)):
            v |= 0x0F
        if m & (1 << (1 if y < 4 else 3)):
            v |= 0xF0
        f.append(v)
    glifo("CUAD%X" % m, f, None)
assert len(GLIFOS) == 128, len(GLIFOS)


def fuente():
    """256 glifos x 8 filas."""
    return ASCII + [g[2] for g in GLIFOS]


def unicode_a_codigo():
    return {g[3]: g[0] for g in GLIFOS if g[3]}
