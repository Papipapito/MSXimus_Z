# -*- coding: utf-8 -*-
# io_summary.py <tag>_io.txt [ms_max] — resume la traza de E/S del V9990: linea de tiempo de los registros
# de modo (R#6/7/8/13/9), comandos (R#52 con SX..FC), trafico de P#0/P#1/P#2 y lecturas de estado.
import sys, collections
fn = sys.argv[1]; ms_max = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9
regs = [0] * 64; sel = 0; inc = True
cnt = collections.Counter(); ev = []; cmds = []
last_mode = None; rd_status = collections.Counter(); p2w = 0; p2r = 0; p0w = 0; p0r = 0; p1w = 0
CMD = {0x00: "STOP", 0x10: "LMMC", 0x20: "LMMV", 0x30: "LMCM", 0x40: "LMMM", 0x50: "CMMC", 0x60: "CMMK", 0x70: "CMMM",
       0x80: "BMXL", 0x90: "BMLX", 0xA0: "BMLL", 0xB0: "LINE", 0xC0: "SRCH", 0xD0: "POINT", 0xE0: "PSET", 0xF0: "ADVN"}
first_ms = None
for line in open(fn):
    p = line.split()
    if len(p) < 4: continue
    d, port, val, ms = p[0], int(p[1], 16), int(p[2], 16), int(p[3])
    if ms > ms_max: break
    if first_ms is None: first_ms = ms
    cnt[(d, port)] += 1
    if d == "W":
        if port == 0x64:
            sel = val & 0x3F; inc = not (val & 0x80)
        elif port == 0x63:
            regs[sel] = val
            if sel in (6, 7, 8, 9, 13, 16, 17, 18, 19, 20, 21, 22, 23, 24):
                key = (sel, val)
                if key != last_mode:
                    ev.append("%6d ms  R#%d=%02X" % (ms, sel, val)); last_mode = key
            if sel == 52:
                cmds.append("%6d ms  %s(%02X) SX=%d SY=%d DX=%d DY=%d NX=%d NY=%d ARG=%02X LOP=%02X WM=%04X FC=%04X BC=%04X" % (
                    ms, CMD.get(val & 0xF0, "?"), val, regs[32] | regs[33] << 8, regs[34] | regs[35] << 8, regs[36] | regs[37] << 8,
                    regs[38] | regs[39] << 8, regs[40] | regs[41] << 8, regs[42] | regs[43] << 8, regs[44], regs[45],
                    regs[46] | regs[47] << 8, regs[48] | regs[49] << 8, regs[50] | regs[51] << 8))
            if inc: sel = (sel + 1) & 0x3F
        elif port == 0x67:
            ev.append("%6d ms  P#7(sys)=%02X" % (ms, val))
        elif port == 0x66:
            pass
        elif port == 0x62: p2w += 1
        elif port == 0x60: p0w += 1
        elif port == 0x61: p1w += 1
    else:
        if port in (0x65, 0x66): rd_status[(port, val)] += 1
        elif port == 0x62: p2r += 1
        elif port == 0x60: p0r += 1
        elif port == 0x63:
            pass
print("eventos: W60=%d R60=%d W61=%d W62=%d R62=%d W63=%d W64=%d; R65/R66 distintos: %s" % (
    p0w, p0r, p1w, p2w, p2r, cnt[("W", 0x63)], cnt[("W", 0x64)],
    ", ".join("%02X=%02X x%d" % (k[0], k[1], v) for k, v in sorted(rd_status.items()))[:300]))
print("-- registros de modo (cambios) --")
for e in ev[:60]: print(e)
print("-- comandos: %d --" % len(cmds))
c = collections.Counter(x.split()[2].split("(")[0] for x in cmds)
print("   por tipo:", dict(c))
for x in cmds[:40]: print(x)
if len(cmds) > 40: print("   ... (%d mas)" % (len(cmds) - 40))
