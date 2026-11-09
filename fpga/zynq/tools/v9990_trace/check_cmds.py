# -*- coding: utf-8 -*-
# check_cmds.py <tag>_io.txt <prefijo_dumps> <k0> <k1> [bpp] [ancho_px] — modelo de referencia de LMMV, LMMM,
# CMMC y CMMM del V9990 en los modos Bx (bpp 2/4/8/16, por defecto 4; ancho = XIMM 256/512/1024/2048 px, por
# defecto 512) aplicado al volcado del banco tras el comando k-1 (tb_t9990_timing +CDUMPS=: <prefijo>_c<k>.bin)
# y comparado con el volcado tras el comando k, para k0..k1. Imprime el primer pixel malo de cada comando que
# difiera. Semantica (manual de aplicacion del V9990 y openMSX V9990CmdEngine):
#   - pixel (x, y) en la direccion logica y*pitch + x*bpp/8 (pitch = ancho*bpp/8; x da la vuelta en la fila);
#     dentro del byte, el pixel de la izquierda en los bits altos; a 16 bpp, byte bajo en la direccion par.
#   - FC (R#48/49), BC (R#50/51) y WM (R#46/47): a 2/4/8 bpp, el byte bajo para la direccion par y el alto
#     para la impar (el manual pide repetir el mismo valor en los dos); a 16 bpp, la palabra entera.
#   - LOP: solo 0C (IMP) y 1C (IMP con TP: el pixel fuente 0 no se escribe; a 16 bpp, los 16 bits a 0).
#   - CMMC: 8 pixeles por byte de P#2 (los W 62 de la traza tras el R#52), bit 7 primero, 1 = FC, 0 = BC;
#     los bits siguen de una fila a la siguiente y los que sobran del ultimo byte se tiran.
#   - CMMM: lo mismo con los bytes de la VRAM de antes desde SA = R#32 | R#34<<8 | (R#35&7)<<16 (R#33 no
#     cuenta), uno detras de otro.
# Limites: sin P1/P2, sin LOP distintos de 0C/1C, sin LINE/PSET/SRCH/BMxx (salen como "no modelado").
import sys
fn, pre, k0, k1 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
BPP = int(sys.argv[5]) if len(sys.argv) > 5 else 4
W = int(sys.argv[6]) if len(sys.argv) > 6 else 512
PITCH = W * BPP // 8
MASK = (1 << BPP) - 1
NAMES = {0x20: "LMMV", 0x40: "LMMM", 0x50: "CMMC", 0x70: "CMMM"}
regs = [0] * 64; sel = 0; inc = True; cmds = []
for line in open(fn):
    p = line.split()
    if len(p) < 4 or p[0] != "W": continue
    port, val = int(p[1], 16), int(p[2], 16)
    if port == 0x64: sel = val & 0x3F; inc = not (val & 0x80)
    elif port == 0x62 and cmds: cmds[-1]["p2"].append(val)
    elif port == 0x63:
        regs[sel] = val
        if sel == 52:
            r = lambda n: regs[n] | regs[n + 1] << 8
            cmds.append(dict(op=val, sx=r(32) & 0x7FF, sy=r(34) & 0xFFF, dx=r(36) & 0x7FF, dy=r(38) & 0xFFF,
                             nx=(r(40) & 0x7FF) or 2048, ny=(r(42) & 0xFFF) or 4096,
                             arg=regs[44], lop=regs[45], wm=r(46), fc=r(48), bc=r(50),
                             sa=regs[32] | regs[34] << 8 | (regs[35] & 7) << 16, p2=[]))
        if inc: sel = (sel + 1) & 0x3F
def addr(x, y):
    return (y * PITCH + ((x & (W - 1)) * BPP) // 8) & 0x7FFFF
def sh(x):                                      # posicion del campo del pixel dentro del byte (2/4 bpp)
    return 8 - BPP - ((x * BPP) & 7)
def getpx(v, x, y):
    a = addr(x, y)
    if BPP == 16: return v[a] | v[a + 1] << 8
    if BPP == 8: return v[a]
    return (v[a] >> sh(x)) & MASK
def by_addr(val16, x, y):                       # FC/BC/WM del pixel (x, y): byte segun la paridad de la direccion
    if BPP == 16: return val16
    b = (val16 >> 8) if (addr(x, y) & 1) else (val16 & 0xFF)
    return b if BPP == 8 else (b >> sh(x)) & MASK
def setpx(v, x, y, c, m):
    a = addr(x, y)
    if BPP == 16:
        old = v[a] | v[a + 1] << 8; new = (old & ~m) | (c & m)
        v[a] = new & 0xFF; v[a + 1] = new >> 8
    elif BPP == 8:
        v[a] = (v[a] & ~m | c & m) & 0xFF
    else:
        s = sh(x); v[a] = (v[a] & ~(m << s) | (c & m) << s) & 0xFF
for k in range(k0, k1 + 1):
    c = cmds[k - 1]
    before = bytearray(open("%s_c%d.bin" % (pre, k - 1), "rb").read())
    after = open("%s_c%d.bin" % (pre, k), "rb").read()
    v = bytearray(before)
    op = c["op"] & 0xF0; tp = bool(c["lop"] & 0x10)
    dix = -1 if c["arg"] & 4 else 1; diy = -1 if c["arg"] & 8 else 1
    if op not in NAMES or (c["lop"] & 0xEF) != 0x0C:
        print("cmd %d: op %02X lop %02X no modelado" % (k, c["op"], c["lop"])); continue
    if op == 0x70: bits = before[c["sa"]:c["sa"] + (c["nx"] * c["ny"] + 7) // 8]
    elif op == 0x50: bits = bytes(c["p2"])
    for j in range(c["ny"]):
        for i in range(c["nx"]):
            x, y = c["dx"] + dix * i, c["dy"] + diy * j
            if op == 0x40: s = getpx(before, c["sx"] + dix * i, c["sy"] + diy * j)
            elif op == 0x20: s = by_addr(c["fc"], x, y)
            else:
                n = j * c["nx"] + i
                bit = (bits[n // 8] >> (7 - n % 8)) & 1 if n // 8 < len(bits) else 0
                s = by_addr(c["fc"] if bit else c["bc"], x, y)
            if tp and s == 0: continue
            setpx(v, x, y, s, by_addr(c["wm"], x, y))
    diff = [i for i in range(524288) if v[i] != after[i]]
    desc = "%s sx=%d sy=%d sa=%05X dx=%d dy=%d nx=%d ny=%d lop=%02X fc=%04X bc=%04X" % (
        NAMES[op], c["sx"], c["sy"], c["sa"], c["dx"], c["dy"], c["nx"], c["ny"], c["lop"], c["fc"], c["bc"])
    if not diff:
        print("cmd %2d OK   %s" % (k, desc))
    else:
        i = diff[0]; y, xb = divmod(i, PITCH)
        print("cmd %2d MAL  %s: %d bytes; primero y=%d xbyte=%d (px %d) modelo=%02X banco=%02X antes=%02X" % (
            k, desc, len(diff), y, xb, xb * 8 // BPP, v[i], after[i], before[i]))
        for i in diff[:8]:
            y, xb = divmod(i, PITCH)
            print("        y=%d xbyte=%d (px %d): modelo=%02X banco=%02X antes=%02X" % (y, xb, xb * 8 // BPP, v[i], after[i], before[i]))
