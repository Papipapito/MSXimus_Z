#!/bin/bash
# build.sh — V9991B7.ROM (1024 x 212 progresivo), V9991B7I.ROM (1024 x 424 entrelazado) y V9991B5.ROM (640 x 400,
# 29/10/2026) desde v9991b7.asm (DEMOMOVE se queda a 0: la variante de arrastre automatico es solo para openMSX), con el asmsx de bios/bin. Salida en esta carpeta y copia a files/20261028/. (28/10/2026)
set -e
cd "$(dirname "$0")"
ASM=../../../../bios/bin/asmsx.exe
mkdir -p out
for v in 0 1 2; do
    n=V9991B7; il=0; b5=0
    [ $v = 1 ] && { n=V9991B7I; il=1; }
    [ $v = 2 ] && { n=V9991B5; b5=1; }
    sed -e "s/^ILMODE=0/ILMODE=$il/" -e "s/^B5MODE=0/B5MODE=$b5/" v9991b7.asm > out/$n.asm
    grep -q "^ILMODE=$il" out/$n.asm && grep -q "^B5MODE=$b5" out/$n.asm || { echo "FALLO: ILMODE/B5MODE no se fijaron"; exit 1; }
    ( cd out && "../$ASM" -z $n.asm > $n.log 2>&1 ) || true
    rm -f out/~tmppre.* out/$n.sym
    bin=$(ls out/$n.z80 out/$n.bin out/$n.rom 2>/dev/null | head -1)   # asmsx -z deja el binario como .z80
    if [ -z "$bin" ] || grep -qiE "error" out/$n.log; then echo "FALLO al ensamblar $n:"; grep -iE "error|warning" out/$n.log | head; exit 1; fi
    python - "$bin" "$n.ROM" <<'PYEOF'
import sys
d = open(sys.argv[1], "rb").read()
assert d[:2] == b"AB", "sin cabecera AB"
d = d.ljust(16384, b"\0")[:16384]
open(sys.argv[2], "wb").write(d)
print("%s: %d bytes, INIT %04X" % (sys.argv[2], len(d), d[2] | (d[3] << 8)))
PYEOF
    cp $n.ROM ../../../../files/20261028/$n.ROM
done
