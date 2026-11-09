#!/bin/bash
# get_minimp3.sh — clona minimp3 (commit fijado) en arm/minimp3, para el reproductor de MP3 del menu
# Mismo patron que get_tinyusb.sh: arm/minimp3/ esta en .gitignore, NO se
# vendoriza codigo de terceros en el repositorio.
#   minimp3 (lieff): descodificador MP3 de una sola cabecera, CC0 (dominio publico), sin malloc,
#   sin libm y con salida int16 -> justo lo que necesita un bare-metal.
# Comprobado el 22/09/2026 con arm-none-eabi-gcc y las banderas del companion:
#   -mfloat-abi=soft          text 24.836 B, bss 11.276 B, 302 llamadas a coma flotante POR SOFTWARE
#   -mfloat-abi=softfp -mfpu=neon  text 22.504 B, bss 11.276 B, coma flotante en hardware
# Simbolos externos que pide: memcpy/memmove/memset y los __aeabi_?idiv de libgcc; nada mas.
# 23/09: en uso (companion/mp3.c). start.S enciende la FPU y mmu.c la MMU (minimp3 necesita memoria
# normal: el memcpy de newlib aborta en strongly-ordered); companion/build.sh compila solo mp3.c con NEON.
set -e
cd "$(dirname "$0")"
REV=ea99364
[ -d minimp3 ] || git clone https://github.com/lieff/minimp3.git minimp3
git -C minimp3 checkout -q $REV
git -C minimp3 log --oneline -1
