#!/bin/sh
# Compila CHGCPU.COM con pasmo (WSL Ubuntu-24.04) y lo deja en files/tr_fase5b
set -e
cd "$(dirname "$0")"
pasmo --bin src/chgcpu.asm CHGCPU.COM
mkdir -p ../../files/tr_fase5b
cp CHGCPU.COM ../../files/tr_fase5b/CHGCPU.COM
ls -l CHGCPU.COM
