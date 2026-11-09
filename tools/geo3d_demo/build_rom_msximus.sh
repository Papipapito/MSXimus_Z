#!/bin/bash
# build_rom_msximus.sh - la ROM de demos de geo3d de Alex Moncks con nuestra demo "MSXIMUS" (7 demos, puertos 98h,
# firma ROM_AS16 en 0010h): "MSXIMUS GEO3D.ROM".
#
# Uso (WSL): bash build_rom_msximus.sh <copia>
#   <copia> = carpeta con el geo3d/ de alexmoncks/V9968_Cartridge (main eeb13f4 o posterior), extraido con LF:
#     git -C <clon> -c core.autocrlf=false -c core.eol=lf archive eeb13f4 geo3d | tar -x -C <copia>
#   La copia se modifica (patch, tablas, out/): no usar el clon.
# Deja <copia>/geo3d/rom/out/GEO3D_98.ROM y la comprueba (firma y su run_rom_z80.py con las 7 demos).
# Herramientas: python3 con z80 y pillow, z80asm y las fuentes DejaVu (sin root, en $G3TOOLS = ~/g3tools: ver LEEME.txt).
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
G="$(cd "$1" && pwd)/geo3d"
G3="${G3TOOLS:-$HOME/g3tools}"
command -v z80asm >/dev/null || export PATH="$G3/usr/bin:$PATH"
[ -d "$G/rom" ] && [ -d "$G/z80" ] || { echo "no es una copia de geo3d: $G" >&2; exit 1; }

# nuestra demo con LF (el checkout de Windows deja el .asm en CRLF); su build_rom.py la ensambla como captured()
sed 's/\r$//' "$AQUI/gen_msximus_tables.py" > "$G/z80/gen_msximus_tables.py"
sed 's/\r$//' "$AQUI/geo3d_msximus_demo88.asm" > "$G/z80/geo3d_msximus_demo.asm"
grep -q gen_msximus_tables "$G/rom/build_rom.py" ||
    sed 's/\r$//' "$AQUI/build_rom_msximus.patch" | (cd "$G/.." && patch -p1 --forward)

# sus scripts buscan las fuentes en /usr/share/fonts/truetype/dejavu (core + extra); sin root estan en $G3
DV=/usr/share/fonts/truetype/dejavu/
[ -f "${DV}DejaVuSansCondensed-Bold.ttf" ] ||
    sed -i "s#\"$DV#\"$G3$DV#g" "$G/rom/build_rom.py" "$G/showcase/showcase.py"

(cd "$G/z80" && python3 gen_msximus_tables.py)
(cd "$G/rom" && python3 build_rom.py --base 0x98)
ROM="$G/rom/out/GEO3D_98.ROM"
[ "$(dd if="$ROM" bs=1 skip=16 count=8 2>/dev/null)" = "ROM_AS16" ] || { echo "falta la firma ROM_AS16 en 0010h" >&2; exit 1; }
(cd "$G/rom" && python3 run_rom_z80.py --base 152 --lang en --keys digit | tail -n 3)
md5sum "$ROM"
