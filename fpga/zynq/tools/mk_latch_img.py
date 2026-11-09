"""mk_latch_img.py — imagen SD de prueba del latch del puerto 1 del VDP en la placa (modo imagen, BOOT_IMG=2).
AUTOEXEC.BAS (Disk BASIC lo ejecuta solo al salir del menu con ESC, sin DOS en la imagen) mete una rutina en D000h que,
con las interrupciones inhibidas, deja un byte HUERFANO en 99h y luego:
  T1  escribe en 98h          -> el V9938 cancela el par (HRA 05f9806; openMSX registerDataStored)
  T2  lee de 98h              -> idem
  T3  lee el status (99h)     -> idem (esto ya lo hacia nuestro _185)
y despues fija la direccion 1800h+n y escribe una marca (A7h, A8h, A9h). Si el par se cancelo, la marca cae en su
sitio y VPEEK la lee: "167 168 169". Si no, la direccion queda corrida y sale otra cosa.
Salida: latchtest.img en LATCHIMG_DIR (o junto a este fichero). Arranque: BOOT_PROXY=1 BOOT_IMG=2 xsdb.bat tools/boot.tcl
<pack> <bit> latchtest.img; ESC en el menu; tools/screen.tcl. 30/09/2026: con la Z1.2 (antes del porte) sale "0 0 169"."""
import os, subprocess, sys
HERE = os.environ.get("LATCHIMG_DIR", os.path.dirname(os.path.abspath(__file__)))
ZT = os.path.dirname(os.path.abspath(__file__))
folder = os.path.join(HERE, "latchdir"); os.makedirs(folder, exist_ok=True)
for f in os.listdir(folder): os.remove(os.path.join(folder, f))

def sub(cancel, lo, mark):
    #        IN A,(99h)   LD A,55h/OUT(99h)      cancel    LD A,lo/OUT(99h)      LD A,58h/OUT(99h)      LD A,mark/OUT(98h)
    return [0xDB, 0x99, 0x3E, 0x55, 0xD3, 0x99] + cancel + [0x3E, lo, 0xD3, 0x99, 0x3E, 0x58, 0xD3, 0x99, 0x3E, mark, 0xD3, 0x98]

ml = [0xF3]
ml += sub([0x3E, 0x00, 0xD3, 0x98], 0x00, 0xA7)     # T1: OUT (98h),0
ml += sub([0xDB, 0x98], 0x01, 0xA8)                 # T2: IN A,(98h)
ml += sub([0xDB, 0x99], 0x02, 0xA9)                 # T3: IN A,(99h)
ml += [0xDB, 0x99, 0xFB, 0xC9]
lines = [
    "10 SCREEN 0:WIDTH 80:VPOKE &H1800,0:VPOKE &H1801,0:VPOKE &H1802,0",
    "20 FOR I=0 TO %d:READ A:POKE &HD000+I,A:NEXT" % (len(ml) - 1),
    "30 DEFUSR=&HD000:A=USR(0)",
    "40 PRINT:PRINT \"LATCH T1 T2 T3 =\";VPEEK(&H1800);VPEEK(&H1801);VPEEK(&H1802);\" (OK = 167 168 169)\"",
    "50 PRINT \"VERSION 2F 29 =\";HEX$(INP(&H2F));\" \";INP(&H29)",
]
n = 100
for i in range(0, len(ml), 16):
    lines.append("%d DATA %s" % (n, ",".join(str(b) for b in ml[i:i + 16]))); n += 10
bas = "\r\n".join(lines) + "\r\n\x1a"
open(os.path.join(folder, "AUTOEXEC.BAS"), "wb").write(bas.encode("ascii"))
open(os.path.join(folder, "RELLENO.ROM"), "wb").write(b"AB" + bytes(16382))
out = os.path.join(HERE, "latchtest.img")
subprocess.check_call([sys.executable, os.path.join(ZT, "make_fat_img.py"), out, "20", folder])
print("rutina de %d bytes; imagen %s" % (len(ml), out))
print(bas[:-1])
