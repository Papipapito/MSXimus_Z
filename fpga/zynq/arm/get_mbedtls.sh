#!/bin/bash
# get_mbedtls.sh — baja Mbed TLS (version fijada) a arm/mbedtls para el TLS del companion (Ethernet P2:
# conexiones https del "ESP32" del MSX: hget, msxai2, descarga de cintas TSX). Mismo patron que
# get_tinyusb.sh / get_minimp3.sh: arm/mbedtls/ esta en .gitignore, NO se vendoriza codigo de terceros.
#   Mbed TLS 3.6 (LTS, Apache-2.0): compila bare-metal sin sistema operativo con su propia configuracion
#   (companion/bsp/mbedtls_config.h); el tarball de la release trae los ficheros generados, sin Python.
set -e
cd "$(dirname "$0")"
VER=3.6.7
if [ ! -d mbedtls ]; then
    curl -L -o mbedtls.tar.bz2 "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$VER/mbedtls-$VER.tar.bz2"
    mkdir -p mbedtls && tar xjf mbedtls.tar.bz2 -C mbedtls --strip-components=1
    rm -f mbedtls.tar.bz2
fi
grep -m1 "MBEDTLS_VERSION_STRING " mbedtls/include/mbedtls/build_info.h
