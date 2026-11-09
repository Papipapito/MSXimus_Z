#!/usr/bin/env python3
"""gen_nextor_b_h.py — Nextor-B (MSX-DOS en la maquina B del perfil Dual, Z1.3.2b9) embebido en el companion. Solo stdlib.

  gen_nextor_b_h.py [--rom bios/nextor214/Nextor-2.1.4.MSXimusB.ROM] [--salida arm/companion/nextor_b_rom.h] [--fecha AAAA-MM-DD]

Lee la ROM de 128 KB de Nextor-B (Nextor 2.1.4 de Konamiman con el driver de la maquina B, bios/nextor214/driver_b.inc), la comprime con
zlib (nivel 9, el formato que descomprime inflate.c: cabecera de 2 bytes, deflate, Adler-32) y escribe arm/companion/nextor_b_rom.h con el
flujo comprimido y las dos longitudes. dual_disco.c lo descomprime con mx_zlib y compone el cartucho de B en la DDR. Hay que regenerarlo
cada vez que cambia la ROM (el driver o el kernel): el banco del PC (tests/dual_host) compara lo descomprimido con el .ROM del repo y falla si
no coinciden."""
import argparse
import datetime
import hashlib
import os
import sys
import zlib

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.normpath(os.path.join(AQUI, "..", "..", ".."))                # la raiz del repo
ROM = os.path.join(RAIZ, "bios", "nextor214", "Nextor-2.1.4.MSXimusB.ROM")
SALIDA = os.path.join(AQUI, "..", "arm", "companion", "nextor_b_rom.h")
TAM = 131072                                                                  # 128 KB: el cartucho de Nextor-B entero


def main():
    ap = argparse.ArgumentParser(description="Genera companion/nextor_b_rom.h (Nextor-B comprimido con zlib)")
    ap.add_argument("--rom", default=ROM)
    ap.add_argument("--salida", default=SALIDA)
    ap.add_argument("--fecha", default=datetime.date.today().isoformat())
    a = ap.parse_args()
    rom = open(a.rom, "rb").read()
    if len(rom) != TAM:
        sys.exit("%s mide %d bytes y tiene que medir %d" % (a.rom, len(rom), TAM))
    z = zlib.compress(rom, 9)
    assert zlib.decompress(z) == rom
    rel = os.path.relpath(a.rom, RAIZ).replace(os.sep, "/")
    lineas = []
    for i in range(0, len(z), 16):
        lineas.append("    " + ", ".join("0x%02X" % b for b in z[i:i + 16]) + ",")
    txt = """/* nextor_b_rom.h — Nextor-B (MSX-DOS en la maquina B del perfil Dual) comprimido con zlib. GENERADO por tools/gen_nextor_b_h.py: no se edita a mano.
 * Origen: %s (Nextor 2.1.4 de Konamiman con el driver de B, bios/nextor214/driver_b.inc), %d bytes, SHA-256 %s.
 * Generado el %s. Si cambia la ROM (el driver o el kernel) se vuelve a ejecutar la herramienta; el banco del PC (tests/dual_host) compara lo
 * descomprimido con el .ROM del repo. dual_disco.c lo descomprime con mx_zlib (inflate.c) y lo pone en el cartucho de B. */
#ifndef NEXTOR_B_ROM_H
#define NEXTOR_B_ROM_H
#include "xil_types.h"

#define NEXTOR_B_ROM_LEN   %s /* bytes de la ROM descomprimida */
#define NEXTOR_B_ROM_ZLEN  %s /* bytes del flujo zlib */

static const u8 nextor_b_rom_z[NEXTOR_B_ROM_ZLEN] = {
%s
};
#endif
""" % (rel, len(rom), hashlib.sha256(rom).hexdigest(), a.fecha, ("%dU" % len(rom)).ljust(8), ("%dU" % len(z)).ljust(8), "\n".join(lineas))
    with open(a.salida, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    print("%s: %d bytes -> %d comprimidos (%s)" % (os.path.relpath(a.salida, RAIZ).replace(os.sep, "/"), len(rom), len(z), a.fecha))


if __name__ == "__main__":
    main()
