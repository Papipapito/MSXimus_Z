"""mk_sort_img.py — imagen SD de prueba del navegador ORDENADO para la Zynq (modo imagen, BOOT_IMG=2).
Raiz con nombres 8.3 desordenados, dos entradas OCULTAS/SISTEMA que NO deben salir y ficheros .ROM/.DSK
de relleno. Usa fpga/zynq/tools/make_fat_img.py (sin LFN: nombres 8.3 en mayusculas) y despues marca
los atributos (byte 11 de la entrada de directorio) a mano. Salida: sortest.img en SORTIMG_DIR (por defecto, esta carpeta)."""
import os, subprocess, sys, struct
HERE = os.environ.get("SORTIMG_DIR", os.path.dirname(os.path.abspath(__file__)))
ZT = os.path.dirname(os.path.abspath(__file__))
folder = os.path.join(HERE, "sortdir"); os.makedirs(folder, exist_ok=True)
for f in os.listdir(folder): os.remove(os.path.join(folder, f))
rom = b"AB" + bytes(16382)            # 16 KB "ROM" de relleno (nunca se lanza)
dsk = bytes(720 * 1024)               # 720 KB disco vacio
# orden de creacion = orden fisico en el directorio (make_fat_img recorre la carpeta tal cual la lista)
files = [("ZEBRA.ROM", rom), ("MARIO.DSK", dsk), ("ALPHA.ROM", rom), ("OCULTO.ROM", rom),
         ("SISTEMA.ROM", rom), ("KNIGHT.ROM", rom), ("ALESTE.ROM", rom), ("BETA.DSK", dsk),
         ("Z1.ROM", rom), ("A1.ROM", rom)]
for n, d in files:
    open(os.path.join(folder, n), "wb").write(d)
out = os.path.join(HERE, "sortest.img")
subprocess.check_call([sys.executable, os.path.join(ZT, "make_fat_img.py"), out, "20", folder])
img = bytearray(open(out, "rb").read())
# localizar la raiz: MBR -> LBA 2048 -> BPB
bs = 2048 * 512
bps, spc, res, nfat, nroot, _, _, spf = struct.unpack_from("<HBHBHHBH", img, bs + 11)
root = bs + (res + nfat * spf) * bps
marked = 0
for i in range(nroot):
    e = root + i * 32
    name = bytes(img[e:e + 11])
    if name == b"OCULTO  ROM": img[e + 11] |= 0x02; marked += 1     # oculto
    if name == b"SISTEMA ROM": img[e + 11] |= 0x04; marked += 1     # sistema
open(out, "wb").write(img)
print("imagen", out, len(img), "bytes; atributos marcados:", marked, "(quiero 2)")
print("orden fisico:", [n for n, _ in files])
print("orden esperado en el menu (sin OCULTO ni SISTEMA):", sorted([n for n, _ in files if n not in ("OCULTO.ROM", "SISTEMA.ROM")], key=str.upper))
