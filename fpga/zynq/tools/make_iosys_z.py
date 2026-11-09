#!/usr/bin/env python3
"""make_iosys_z.py — genera zynq/iosys_bl616_z.v a partir de src/iosys/iosys_bl616.v (30/09/2026, OSD con color).

Unico cambio: la orden 0x10 del protocolo del BL616 fija el ATRIBUTO {fondo, tinta} de lo que se imprime despues
(orden 0x05), y la escritura al textdisp lo lleva en reg_char_di[31:24] (zynq/textdisp_z.v). Al arrancar el atributo
es 0 (el aspecto de siempre). El fichero de src/ no se toca: sigue siendo el del arbol de Gowin.
"""
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "src", "iosys", "iosys_bl616.v"))
DST = os.path.normpath(os.path.join(HERE, "..", "iosys_bl616_z.v"))

s = io.open(SRC, encoding="utf-8", newline="").read()
nl = "\r\n" if "\r\n" in s else "\n"


def rep(a, b):
    global s
    a2, b2 = a.replace("\n", nl), b.replace("\n", nl)
    assert s.count(a2) == 1, (s.count(a2), a[:70])
    s = s.replace(a2, b2)


rep("reg [7:0] char_wr;\n", "reg [7:0] char_wr;\nreg [7:0] attr_reg;         // Zynq: atributo {fondo, tinta} de lo que se imprime (orden 0x10)\nreg [7:0] attr_wr;\n")
rep("        char_wr <= 0;\n", "        char_wr <= 0;\n        attr_reg <= 0;\n        attr_wr <= 0;\n")
rep("                        char_wr <= rx_data;\n", "                        char_wr <= rx_data;\n                        attr_wr <= attr_reg;\n")
rep("                    default: begin\n                        // unknown command: consume all data and return\n",
    "                    'h10: attr_reg <= rx_data;      // Zynq: atributo del texto (textdisp_z.v)\n"
    "                    default: begin\n                        // unknown command: consume all data and return\n")
rep("wire [31:0] reg_char_di = {8'b0, x_wr, y_wr, char_wr};", "wire [31:0] reg_char_di = {attr_wr, x_wr, y_wr, char_wr};")
cab = ("// iosys_bl616_z.v — GENERADO por zynq/tools/make_iosys_z.py desde src/iosys/iosys_bl616.v: igual salvo la orden\n"
       "// 0x10 (atributo de color del texto, textdisp_z.v). No editar a mano: editar el original y regenerar.\n").replace("\n", nl)
io.open(DST, "w", encoding="utf-8", newline="").write(cab + s)
print(DST)
