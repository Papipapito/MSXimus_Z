#!/usr/bin/env python3
# extraer_de_boot.py - saca el pack de BIOS y la ROM de ondas de un BOOT.bin ya publicado.
#
#   python extraer_de_boot.py BOOT_Z1.3.1_nextor214.bin [carpeta_salida]
#
# Deja en la carpeta (se crea si no existe; por defecto, la actual) pack.bin (512 KB, destino DDR 0x10F00000) y yrw801.rom
# (2 MB, destino DDR 0x0F000000), que son los dos ficheros que pide make_boot.sh: con ellos y un
# bitstream, un companion y un FSBL compilados desde este repositorio se obtiene un BOOT.bin propio
# sin necesitar las ROM con copyright del repositorio privado de BIOS. Usar una carpeta distinta de
# fpga/zynq/arm/boot/: make_boot.sh copia el pack y la ROM de ondas ahi con esos mismos nombres.
#
# Lee la tabla de particiones de la cabecera de arranque de Zynq-7000 (bootgen): cada particion lleva su
# direccion de carga, y el pack y las ondas se reconocen por ella.
import os, struct, sys

DESTINOS = {0x10F00000: ("pack.bin", 512 * 1024), 0x0F000000: ("yrw801.rom", 2 * 1024 * 1024)}

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    d = open(sys.argv[1], "rb").read()
    salida = sys.argv[2] if len(sys.argv) > 2 else "."
    if d[0x24:0x28] != b"XNLX":
        sys.exit("%s: no es un BOOT.bin de Zynq (falta la firma XNLX)" % sys.argv[1])
    iht = struct.unpack_from("<I", d, 0x98)[0]                       # tabla de cabeceras de imagen
    n = struct.unpack_from("<I", d, iht + 4)[0]                      # numero de particiones
    pht = struct.unpack_from("<I", d, iht + 8)[0] * 4                # tabla de cabeceras de particion
    os.makedirs(salida, exist_ok=True)
    hallados = 0
    for i in range(n):
        p = struct.unpack_from("<16I", d, pht + 64 * i)
        longitud, carga, desplazamiento = p[1] * 4, p[3], p[5] * 4
        if carga in DESTINOS:
            nombre, esperado = DESTINOS[carga]
            if longitud != esperado:
                sys.exit("%s: la particion de 0x%08X mide %d bytes y se esperaban %d" % (sys.argv[1], carga, longitud, esperado))
            ruta = os.path.join(salida, nombre)
            open(ruta, "wb").write(d[desplazamiento:desplazamiento + longitud])
            print("%s: %d bytes (DDR 0x%08X)" % (ruta, longitud, carga))
            hallados += 1
    if hallados != len(DESTINOS):
        sys.exit("%s: no se han encontrado las dos particiones (pack y ondas)" % sys.argv[1])

if __name__ == "__main__":
    main()
