# -*- coding: utf-8 -*-
# make_fat_img.py <salida.img> <MB> <carpeta> — imagen de tarjeta SD (sin dependencias): MBR con UNA
# particion FAT16 (tipo 06h) que empieza en el LBA 2048, con los ficheros de la carpeta en la raiz,
# nombres 8.3 en mayusculas, ficheros contiguos. Para el modo imagen de la Zynq (BOOT_IMG=1 en
# boot.tcl, la imagen va a DISK_BASE 0x11000000) o para volcar a una SD con dd/Rufus.
#   21/09/2026: el menu del MSXimus monta la tarjeta recorriendo la tabla de particiones del MBR
#   (tipos 01/04/06/0E FAT16, 0B/0C FAT32; menu_main.asm is_fat16): un volumen FAT16 pelado, sin
#   MBR, daba "No se detecta la tarjeta SD" en el modo imagen (asi fallaron las del 20/09).
#   Geometria del volumen: sectores de 512 B, 8 sectores por cluster (4 KiB) -> >= 4085 clusters =
#   FAT16 de verdad, 1 sector reservado, 2 FAT, 512 entradas de raiz.
import sys, os, struct, time

out, mb, folder = sys.argv[1], int(sys.argv[2]), sys.argv[3]
BPS, SPC, RES, NFATS, ROOT_ENT = 512, 8, 1, 2, 512
PART_START = 2048                                   # LBA del volumen (1 MiB)
total_img = mb * 1024 * 1024 // BPS                 # sectores de la imagen entera
total = total_img - PART_START                      # sectores del volumen
root_secs = ROOT_ENT * 32 // BPS
# sectores por FAT: clusters de datos ~ (total - RES - root) / SPC ; entradas de 2 B
clusters_est = (total - RES - root_secs) // SPC
spf = (2 * (clusters_est + 2) + BPS - 1) // BPS
data_start = RES + NFATS * spf + root_secs
nclusters = (total - data_start) // SPC
assert 4085 <= nclusters < 65525, "no es FAT16: %d clusters" % nclusters

img = bytearray(total_img * BPS)
# ---- MBR: una particion primaria FAT16 (06h), CHS de relleno, LBA 2048 ----
mbr = bytearray(BPS)
struct.pack_into("<BBBBBBBBII", mbr, 0x1BE, 0x00, 0xFE, 0xFF, 0xFF, 0x06, 0xFE, 0xFF, 0xFF, PART_START, total)
mbr[510] = 0x55; mbr[511] = 0xAA
img[0:BPS] = mbr
# ---- sector de arranque del volumen (BPB FAT16) ----
bs = bytearray(BPS)
bs[0:3] = b"\xEB\x3C\x90"; bs[3:11] = b"MSXIMUS "
struct.pack_into("<HBHBHHBHHHII", bs, 11, BPS, SPC, RES, NFATS, ROOT_ENT, 0, 0xF8, spf, 63, 255, PART_START, total)
bs[36] = 0x80; bs[38] = 0x29
struct.pack_into("<I", bs, 39, int(time.time()) & 0xFFFFFFFF)
bs[43:54] = b"MSXIMUS    "; bs[54:62] = b"FAT16   "
bs[510] = 0x55; bs[511] = 0xAA
V = PART_START * BPS                                # offset en bytes del volumen dentro de la imagen
img[V:V + BPS] = bs

fat = bytearray(spf * BPS)
struct.pack_into("<HH", fat, 0, 0xFFF8, 0xFFFF)
root = bytearray(root_secs * BPS)
next_cluster = 2
nfiles = 0
def dos_name(n):
    base, _, ext = n.upper().partition(".")
    return (base[:8].ljust(8) + ext[:3].ljust(3)).encode("ascii")
now = time.localtime()
dtime = (now.tm_hour << 11) | (now.tm_min << 5) | (now.tm_sec // 2)
ddate = ((now.tm_year - 1980) << 9) | (now.tm_mon << 5) | now.tm_mday
for name in sorted(os.listdir(folder)):
    p = os.path.join(folder, name)
    if not os.path.isfile(p) or name.lower().startswith("leeme") or name.lower().endswith(".img"):
        continue
    data = open(p, "rb").read()
    ncl = (len(data) + SPC * BPS - 1) // (SPC * BPS)
    first = next_cluster
    if first + ncl - 2 > nclusters:
        raise SystemExit("no cabe " + name)
    for i in range(ncl):
        c = first + i
        struct.pack_into("<H", fat, 2 * c, 0xFFFF if i == ncl - 1 else c + 1)
    off = V + (data_start + (first - 2) * SPC) * BPS
    img[off:off + len(data)] = data
    e = bytearray(32)
    e[0:11] = dos_name(name); e[11] = 0x20
    struct.pack_into("<HHHHHHHI", e, 14, dtime, ddate, ddate, 0, dtime, ddate, first, len(data))
    root[nfiles * 32:(nfiles + 1) * 32] = e
    nfiles += 1; next_cluster += ncl
    print("  + %-12s %8d B  cluster %d..%d" % (dos_name(name).decode(), len(data), first, first + ncl - 1))
for k in range(NFATS):
    o = V + (RES + k * spf) * BPS
    img[o:o + len(fat)] = fat
o = V + (RES + NFATS * spf) * BPS
img[o:o + len(root)] = root
open(out, "wb").write(img)
print("imagen %s: %d MiB, MBR + FAT16 en LBA %d, %d clusters de %d B, %d ficheros, libre %d KiB" %
      (out, mb, PART_START, nclusters, SPC * BPS, nfiles, (nclusters - next_cluster + 2) * SPC * BPS // 1024))
