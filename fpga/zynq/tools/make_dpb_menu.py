#!/usr/bin/env python3
"""
make_dpb_menu.py — genera la memoria del OSD de la Zynq (30/09/2026: con COLOR):
  zynq/gowin_dpb_menu.v   RAM de doble puerto 2048 x 16 inferible (un RAMB36), mismos puertos que la IP DPB de Gowin
                          pero de 16 bits:
                            0x000-0x3FF  celdas 32 x 32 (se ven las filas 0..27): {atributo[15:8], caracter[7:0]},
                                         atributo = {fondo[3:0], tinta[3:0]} (osd_paleta.v); texto inicial = el de
                                         src/iosys/gowin_dpb_menu.v (INIT_RAM), atributo 0 = el aspecto de siempre
                            0x400-0x7FF  fuente: palabra (0x400 | c*8 + fila) = {glifo c+128, glifo c} (c = 0..127)
  zynq/osd_paleta.v       la paleta de 16 colores (tinta y fondo), BGR555
  arm/companion/osd_glifos.h  codigos de los glifos 128..255, indices de la paleta y la tabla UTF-8 -> glifo
Todo sale de tools/osd_fuente.py (tambien lo usa tools/osd_render.py para las vistas previas).
Antes (hasta la Z1.2.1): 2048 x 8, 128 caracteres, un solo color y un logo en 0x380 que tapaba las filas 25-26.
"""
import os
import re

import osd_fuente as F

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "..", "src", "iosys", "gowin_dpb_menu.v"))
DST = os.path.normpath(os.path.join(HERE, "..", "gowin_dpb_menu.v"))
PAL = os.path.normpath(os.path.join(HERE, "..", "osd_paleta.v"))
HDR = os.path.normpath(os.path.join(HERE, "..", "arm", "companion", "osd_glifos.h"))

# ---- texto inicial de las celdas (el de la IP de Gowin) ---------------------------------------------------------------
s = open(SRC, encoding="utf-8", errors="ignore").read()
init = {}
for m in re.finditer(r"INIT_RAM_([0-9A-F]{2})\s*=\s*256'h([0-9A-Fa-f]{64})", s):
    init[int(m.group(1), 16)] = m.group(2)
assert len(init) == 64, f"esperaba 64 INIT_RAM, hay {len(init)}"
viejo = []
for k in range(64):
    h = init[k]
    for b in range(32):                                       # byte 0 = los 2 hex de la derecha
        viejo.append(int(h[62 - 2 * b:64 - 2 * b], 16))
assert len(viejo) == 2048

fuente = F.fuente()
for c in range(128):                                          # la fuente ASCII de la IP = la de font.vh
    for f in range(8):
        assert viejo[0x400 + c * 8 + f] == fuente[c][f], (c, f)

mem = [0] * 2048
for a in range(0x380):
    mem[a] = viejo[a] if viejo[a] < 0x80 else 0x20          # texto inicial, atributo 0
for c in range(128):
    for f in range(8):
        mem[0x400 + c * 8 + f] = (fuente[c + 128][f] << 8) | fuente[c][f]

out = []
out.append("// gowin_dpb_menu.v — GENERADO por zynq/tools/make_dpb_menu.py (fuente y paleta en tools/osd_fuente.py).")
out.append("// Memoria del OSD de la Zynq: RAM de doble puerto 2048 x 16 inferible (un RAMB36). Celdas {atributo, caracter}")
out.append("// en 0x000-0x3FF; fuente de 256 glifos en 0x400-0x7FF (palabra = {glifo c+128, glifo c}).")
out.append("// Puerto A: lectura/escritura (textdisp escribe). Puerto B: solo lectura. Dato al ciclo siguiente.")
out.append("module gowin_dpb_menu (douta, doutb, clka, ocea, cea, reseta, wrea, clkb, oceb, ceb, resetb, wreb, ada, dina, adb, dinb);")
out.append("    output reg [15:0] douta;")
out.append("    output reg [15:0] doutb;")
out.append("    input clka, ocea, cea, reseta, wrea;")
out.append("    input clkb, oceb, ceb, resetb, wreb;")
out.append("    input [10:0] ada, adb;")
out.append("    input [15:0] dina, dinb;")
out.append("")
out.append("    (* ram_style = \"block\" *) reg [15:0] mem [0:2047];")
out.append("    integer i;")
out.append("    initial begin")
out.append("        for (i = 0; i < 2048; i = i + 1) mem[i] = 16'h0000;")
for a, v in enumerate(mem):
    if v:
        if a < 0x400:
            c = chr(v & 0xFF) if 32 <= (v & 0xFF) < 127 else "."
            out.append("        mem[%4d] = 16'h%04X;  // '%s'" % (a, v, c))
        else:
            out.append("        mem[%4d] = 16'h%04X;" % (a, v))
out.append("    end")
out.append("")
out.append("    always @(posedge clka) begin")
out.append("        if (cea) begin")
out.append("            if (wrea) mem[ada] <= dina;")
out.append("            if (reseta) douta <= 16'h0000; else douta <= mem[ada];")
out.append("        end")
out.append("    end")
out.append("    always @(posedge clkb) begin")
out.append("        if (ceb) begin")
out.append("            if (wreb) mem[adb] <= dinb;")
out.append("            if (resetb) doutb <= 16'h0000; else doutb <= mem[adb];")
out.append("        end")
out.append("    end")
out.append("endmodule")
open(DST, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")

# ---- paleta ------------------------------------------------------------------------------------------------------------
p = ["// osd_paleta.v — GENERADO por zynq/tools/make_dpb_menu.py (tools/osd_fuente.py). Paleta del OSD, BGR555.",
     "// Atributo de una celda = {fondo[3:0], tinta[3:0]}; el 0 es el aspecto de siempre (tinta amarilla, fondo negro).",
     "module osd_paleta (input [3:0] ti, input [3:0] fo, output reg [14:0] tinta, output reg [14:0] fondo);",
     "    always @* begin", "        case (ti)"]
for i, (n, t, f) in enumerate(F.PALETA):
    p.append("            4'd%-2d: tinta = 15'h%04X;   // %s" % (i, F.bgr555(t), n))
p += ["        endcase", "        case (fo)"]
for i, (n, t, f) in enumerate(F.PALETA):
    p.append("            4'd%-2d: fondo = 15'h%04X;   // %s" % (i, F.bgr555(f), n))
p += ["        endcase", "    end", "endmodule"]
open(PAL, "w", encoding="utf-8", newline="\n").write("\n".join(p) + "\n")

# ---- cabecera del companion ---------------------------------------------------------------------------------------------
h = ["/* osd_glifos.h — GENERADO por fpga/zynq/tools/make_dpb_menu.py (tools/osd_fuente.py): glifos 128..255 y paleta del",
     " * OSD con color (textdisp de la Z1.2.2). Atributo = OSD_A(fondo, tinta). */",
     "#ifndef OSD_GLIFOS_H", "#define OSD_GLIFOS_H", ""]
for i, (n, t, f) in enumerate(F.PALETA):
    h.append("#define C_%-12s %2dU" % (n, i))
h.append("#define OSD_A(fondo, tinta) ((u8)(((fondo) << 4) | (tinta)))")
h.append("")
for c, n, b, u in F.GLIFOS:
    if not n.startswith("LIBRE"):
        h.append("#define G_%-14s 0x%02XU%s" % (n, c, ("   /* %s */" % u) if u else ""))
h.append("")
h.append("/* UTF-8 -> glifo: los caracteres de fuera del ASCII que entiende osd_txt() */")
h.append("#ifdef OSD_UTF8_TABLA                      /* solo osd_dib.c */")
h.append("static const struct { u16 cp; u8 g; } osd_utf8[] = {")
pares = sorted((ord(u), c) for c, n, b, u in F.GLIFOS if u and len(u) == 1 and ord(u) < 0x10000)
for cp, c in pares:
    h.append("    { 0x%04X, 0x%02X }," % (cp, c))
h.append("};")
h.append("#endif")
h.append("#endif")
open(HDR, "w", encoding="utf-8", newline="\n").write("\n".join(h) + "\n")

print(DST, "-", sum(1 for x in mem if x), "palabras con contenido")
print(PAL)
print(HDR, "-", len(pares), "caracteres UTF-8")
