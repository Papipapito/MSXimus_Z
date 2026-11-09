#!/bin/bash
# make_boot.sh — BOOT.bin del MSXimus para la ZYNQ MINI (arranque autonomo desde la SD de
# TF1/SD0 o, mas adelante, desde la QSPI). Orden de carga del FSBL (= orden del .bif; el FSBL
# de Xilinx EXIGE el bitstream justo despues del bootloader, "Partition order invalid" si no):
#   1) fsbl.elf            (bootloader: ps7_init + DDR)
#   2) msximus_zynq.bit    (el PL arranca; MSX_RUN lo lee de la DDR: basura unos ms, luego 0)
#   3) companion.elf       (proxy de SD + USB + OSD; pone MSX_RUN cuando la tarjeta esta lista).
#                          TIENE que ser la PRIMERA particion PS: el FSBL toma la direccion de
#                          arranque de la primera que ve ("first PS partition", image_mover.c)
#   4) zeros.bin           -> DDR 0x1FF00000: buzon + SDBOX a cero (MSX_RUN = 0: el MSX espera)
#   5) pack.bin            -> DDR 0x10F00000: pack de BIOS (lo mismo que hace boot.tcl por JTAG)
#   6) yrw801.rom          -> DDR 0x0F000000: memoria de ondas del OPL4 (wave_axi, S_AXI_GP0)
#   7) ota_info.bin        -> DDR 0x00E10000: quien es esta imagen para la actualizacion por red (30/09/2026,
#                          companion/ota.c): "MOTI1\nversion=..\nserie=..\nvariante=..\nplaca=..\nfecha=..\n".
#                          OTA_VERSION, OTA_SERIE (entero creciente, p. ej. AAAAMMDDNN) y OTA_CANAL (oficial, por
#                          defecto, o beta: Z1.3) del entorno; sin las dos primeras,
#                          "dev" y 0 (cualquier actualizacion publicada se ofrecera). La variante sale del pack:
#                          nextor214 / nextor3 (castellano) o nextor214-en / nextor3-en (menu en ingles, 01/10/2026),
#                          y "idioma=es|en". El companion habla en el OSD el idioma del menu de su imagen.
#   (el FSBL carga TODAS las particiones y despues salta al companion)
# Uso: make_boot.sh [pack.bin] [yrw801.rom]   -> BOOT.bin en este directorio. Copiarlo a la
# raiz de una SD FAT32 y meterla en TF1 con el BOOT switch en SD.
set -e
cd "$(dirname "$0")"
# Los packs (llevan ROMs con copyright) y la ROM de ondas YRW801 viven en el repo PRIVADO bios-msxnano-msximus,
# carpeta hermana de este repo (o donde diga MSXIMUS_BIOS_PRIV), en packs/zynq/.
PRIV=${MSXIMUS_BIOS_PRIV:-../../../../../bios-msxnano-msximus}
PACK=${1:-$PRIV/packs/zynq/msximus/nextor-2.1.4/pack_bios_msximus.bin}   # nextor-3.0.0/ para Nextor 3
WAVE=${2:-$PRIV/packs/zynq/roms/yrw801.rom}                             # la tabla de ondas del OPL4 (2 MB)
BIT=../../msximus_zynq.bit
for f in ../fsbl/fsbl.elf ../companion/companion.elf "$BIT" "$PACK" "$WAVE"; do
    [ -f "$f" ] || { echo "ERROR: falta $f"; exit 1; }
done
python -c "open('zeros.bin','wb').write(bytes(65536))"
python - "$PACK" "${OTA_VERSION:-dev}" "${OTA_SERIE:-0}" "${OTA_CANAL:-oficial}" <<'PYEOF'
import datetime, sys
pack, version, serie, canal = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
assert canal in ("oficial", "beta"), "OTA_CANAL: oficial o beta"
datos = open(pack, "rb").read()
ingles = b"MSXimus - Settings" in datos                             # el menu con ENGLISH=1 (bios/build.sh)
variante = ("nextor3" if b"NEXTORv3_DRIVER" in datos else "nextor214") + ("-en" if ingles else "")
t = "MOTI1\nversion=%s\nserie=%d\nvariante=%s\nidioma=%s\nplaca=zynq7020-mini\nfecha=%s\ncanal=%s\n" % (
    version, serie, variante, "en" if ingles else "es", datetime.date.today().isoformat(), canal)
assert len(version) <= 15 and len(t) < 250
open("ota_info.bin", "wb").write(t.encode("ascii").ljust(256, b"\0"))
print("ota_info: " + t.replace("\n", " "))
PYEOF
cp "$PACK" pack.bin
[ "$WAVE" -ef yrw801.rom ] || cp "$WAVE" yrw801.rom
cat > boot.bif <<EOF
the_ROM_image:
{
    [bootloader] ../fsbl/fsbl.elf
    $BIT
    ../companion/companion.elf
    [load=0x1FF00000] zeros.bin
    [load=0x10F00000] pack.bin
    [load=0x0F000000] yrw801.rom
    [load=0x00E10000] ota_info.bin
}
EOF
BOOTGEN="${BOOTGEN:-${XILINX_VIVADO:-/d/Xilinx/Vivado/2019.2}/bin/bootgen.bat}"   # otra ruta de Vivado: XILINX_VIVADO=...; o BOOTGEN=...
"$BOOTGEN" -arch zynq -image boot.bif -o BOOT.bin -w on
ls -la BOOT.bin
echo "BOOT_OK: $(pwd)/BOOT.bin (pack: $PACK, wave: $WAVE)"
