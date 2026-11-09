#!/usr/bin/env python3
"""mxpf.py — perfiles del PL del MSXimus Z en la microSD de TF1 (formato MXPF; companion/mxpf.c). Solo stdlib.

  mxpf.py empaquetar <perfil.bin|perfil.bit> --id ID --version V --serie N [-o salida.mxp] [--crudo] [--nivel 9]
                      [--bloque DIRECCION=FICHERO ...] [--tr-bios]
        Crea el .mxp (cabecera de 512 B + el .bin comprimido con zlib). Un .bit se convierte antes con bootgen
        (-process_bitstream bin: palabras con los bytes girados, que es lo que acepta la PCAP). Un .bin se comprueba.
        --bloque añade un fichero que el companion copia a esa direccion de la DDR al cargar el perfil, con el MSX parado
        (companion/tr_bios.c: formato y destinos permitidos). --tr-bios pone ademas el bit tr_bios del buzon.
  mxpf.py info <fichero.mxp>                  cabecera, CRC, SHA-256 y prueba de descompresion
  mxpf.py imagen crear <img> --mb N [--fat MB] [--dedicada]
        imagen de disco FICHERO con MBR (y una particion FAT16 vacia opcional). --dedicada: la deja como una tarjeta ya preparada
        para la TF1 «solo perfiles» (P1 FAT32 de 128 MiB + P2 MXPF de 512 MiB, byte a byte como mxpf_prepara_dedicada del companion)
  mxpf.py imagen preparar [--dedicada] <img>   preparar = crear la particion MXPF tras la ultima particion (17..32 MB); con
        --dedicada, la preparacion de la TF1 «solo perfiles» sobre lo que haya (BORRA: es un fichero, no pregunta)
  mxpf.py imagen listar|vaciar <img>
  mxpf.py imagen instalar <img> <fichero.mxp>   escribe en un hueco libre y confirma el directorio (como el companion)
  mxpf.py imagen borrar <img> <ID>
  NO escribe en discos fisicos: 'imagen' solo acepta ficheros normales. Para una tarjeta real se instala con
  tools/perfiles.tcl por JTAG (o desde el panel F12 del MSXimus Z).

Formato (companion/mxpf.c lo describe entero): particion tipo 0xDA; sector 0 superbloque 'MXPF'; sectores 1 y 2 directorio
doble 'MXPD' (secuencia + CRC-32; manda el mas alto valido); sector 3 copia del MBR original; desde el sector 2048 huecos
de 4 MB con el contenido guardado. Entrada de 80 B: id[8], serie, version[16], metodo, banderas, lba, bytes guardados,
bytes del .bin, SHA-256 de lo guardado."""
import argparse, hashlib, os, shutil, struct, subprocess, sys, tempfile, zlib

SEC = 512
MAX_PERF = 6
ALIN = 2048                 # 1 MB
MIN_SECS = 17 * 2048
PREF_SECS = 32 * 2048
PRIMER = 2048               # primer hueco (sectores, relativo a la particion)
HUECO = 8192                # 4 MB
COPIA_MBR = 3
DED_P1_LBA = 2048           # TF1 «solo perfiles» (8/11/2026): P1 FAT32 128 MiB + P2 MXPF 512 MiB; mxpf.c lo describe entero
DED_P1_SECS = 262144
DED_P2_LBA = DED_P1_LBA + DED_P1_SECS
DED_P2_SECS = 1048576
DED_FIN = DED_P2_LBA + DED_P2_SECS
F32_RSVD = 32
F32_FATSZ = 2017
F32_DATA = F32_RSVD + 2 * F32_FATSZ
F32_META = F32_DATA + 3
LEEME = (b"MSXimus Z - tarjeta TF1 de PERFILES / PROFILES card\r\n\r\n"
         b"Esta tarjeta la usa el MSXimus Z para guardar los perfiles del sistema. No la uses en el MSX\r\n"
         b"ni guardes aqui tus ficheros: la segunda particion (tipo DA) es de los perfiles y Windows no la muestra.\r\n"
         b"Puedes copiar aqui BOOT.bin para arrancar desde SD (SW1 en SD); arrancando desde esta tarjeta no se puede preparar ni borrar.\r\n\r\n"
         b"This card holds the MSXimus Z system profiles. Do not use it in the MSX or store files here: the second\r\n"
         b"partition (type DA) belongs to the profiles. BOOT.bin may be copied here to boot from SD (SW1 on SD).\r\n")
MAXPAY = 0x380000           # mayor contenido guardado
PF_MAX = 0x400000 - 0x1000  # mayor .bin que acepta perfil_cargar
ID_CARS = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")


def crc32(b):
    return zlib.crc32(bytes(b)) & 0xFFFFFFFF


class Error(Exception):
    pass


# ---------------------------------------------------------------- entradas y .mxp
def ent_pack(id_, serie, version, metodo, lba, tam, tam_bin, sha):
    e = bytearray(80)
    e[0:8] = id_.encode("ascii").ljust(8, b"\0")
    struct.pack_into("<I", e, 8, serie)
    e[12:28] = version.encode("ascii").ljust(16, b"\0")
    e[28] = metodo
    e[29] = 1
    struct.pack_into("<III", e, 32, lba, tam, tam_bin)
    e[48:80] = sha
    return bytes(e)


def ent_unpack(e):
    idb = bytes(e[0:8]).rstrip(b"\0")
    ver = bytes(e[12:28]).rstrip(b"\0")
    if not (e[29] & 1) or not idb or any(c not in ID_CARS for c in idb) or bytes(e[0:8]).rstrip(b"\0").ljust(8, b"\0") != bytes(e[0:8]):
        raise Error("entrada mal formada")
    if any(c < 0x20 or c > 0x7E for c in ver) or bytes(e[12:28]).rstrip(b"\0").ljust(16, b"\0") != bytes(e[12:28]):
        raise Error("version mal formada")
    d = dict(id=idb.decode(), version=ver.decode(), serie=struct.unpack_from("<I", e, 8)[0], metodo=e[28])
    d["lba"], d["tam"], d["tam_bin"] = struct.unpack_from("<III", e, 32)
    d["sha"] = bytes(e[48:80])
    if d["metodo"] > 1 or d["tam"] == 0 or d["tam"] > MAXPAY or d["tam_bin"] < 4096 or d["tam_bin"] > PF_MAX or d["tam_bin"] & 3:
        raise Error("tamanos fuera de rango")
    if d["metodo"] == 0 and d["tam"] != d["tam_bin"]:
        raise Error("perfil crudo con tamanos distintos")
    return d


def mxp_pack(id_, serie, version, metodo, guardado, tam_bin):
    sha = hashlib.sha256(guardado).digest()
    ent = ent_pack(id_, serie, version, metodo, 0, len(guardado), tam_bin, sha)
    cab = b"MXP1" + struct.pack("<III", 1, SEC, crc32(ent)) + ent
    cab = cab.ljust(SEC, b"\0")
    pad = (-len(guardado)) % SEC
    return cab + guardado + b"\0" * pad


def mxp_unpack(datos):
    if len(datos) < SEC or datos[0:4] != b"MXP1":
        raise Error("no es un .mxp (falta MXP1)")
    ver, hl, crc = struct.unpack_from("<III", datos, 4)
    ent = datos[16:96]
    if ver != 1 or hl != SEC or crc != crc32(ent):
        raise Error("cabecera del .mxp mal (version, tamano o CRC)")
    d = ent_unpack(ent)
    if len(datos) < SEC + d["tam"]:
        raise Error(".mxp truncado")
    d["guardado"] = datos[SEC:SEC + d["tam"]]
    return d


def comprueba_bin(b):
    if len(b) % 4 or len(b) < 4096 or len(b) > PF_MAX:
        raise Error("el .bin mide %d B: tiene que ser multiplo de 4, >= 4096 y <= %d" % (len(b), PF_MAX))
    c = b[:512]
    if b"\x66\x55\x99\xaa" not in c:
        if b"\xaa\x99\x55\x66" in c:
            raise Error("el .bin esta SIN girar (AA 99 55 66): hace falta bootgen -arch zynq -image x.bif -process_bitstream bin")
        raise Error("no hay sincronismo 66 55 99 AA en los primeros 512 B: no es un .bin de bootgen")


def buscar_bootgen():
    for c in (os.environ.get("BOOTGEN"), shutil.which("bootgen"), shutil.which("bootgen.bat"),
              "D:/Xilinx/Vivado/2019.2/bin/bootgen.bat", "C:/Xilinx/Vivado/2019.2/bin/bootgen.bat"):
        if c and os.path.exists(c):
            return c
    raise Error("no encuentro bootgen: pasa el .bin ya girado o define BOOTGEN=ruta")


def bit_a_bin(ruta):
    bg = buscar_bootgen()
    with tempfile.TemporaryDirectory() as t:
        bit = os.path.join(t, "x.bit")
        shutil.copyfile(ruta, bit)
        bif = os.path.join(t, "x.bif")
        open(bif, "w").write("all:\n{\n    %s\n}\n" % bit.replace("\\", "/"))
        r = subprocess.run([bg, "-arch", "zynq", "-image", bif, "-process_bitstream", "bin", "-w", "on"], cwd=t, capture_output=True, text=True)
        for n in ("x.bit.bin", "x.bin"):
            if os.path.exists(os.path.join(t, n)):
                return open(os.path.join(t, n), "rb").read()
        raise Error("bootgen no ha dado el .bin:\n" + r.stdout + r.stderr)


EX_MAGIA = b"MXEX"
EX_PIE = 20
EX_MAX = 16
EX_ZONAS = ((0x0E400000, 0x400000), (0x10F40000, 0x20000))


def con_bloques(b, bloques, tr_bios):
    """.bin | bloques | tabla | pie: companion/tr_bios.c lo describe"""
    if len(bloques) > EX_MAX:
        raise Error("mas de %d bloques" % EX_MAX)
    salida, tabla = bytearray(b), []
    for txt in bloques:
        dirtxt, sep, ruta = txt.partition("=")
        if not sep:
            raise Error("--bloque: DIRECCION=FICHERO")
        ddr, d = int(dirtxt, 0), open(ruta, "rb").read()
        if ddr % 4 or len(d) == 0 or len(d) % 4:
            raise Error("--bloque %s: direccion y tamano tienen que ser multiplos de 4" % txt)
        if not any(z <= ddr and ddr + len(d) <= z + t for z, t in EX_ZONAS):
            raise Error("--bloque %s: destino no permitido" % txt)
        tabla.append((len(salida), ddr, len(d)))
        salida += d
    for t in tabla:
        salida += struct.pack("<III", *t)
    return bytes(salida + EX_MAGIA + struct.pack("<IIII", 1, len(b), len(tabla), 1 if tr_bios else 0))


def lee_bloques(b):
    """(bytes del .bin, [(desplazamiento, direccion, bytes)], banderas); sin pie, todo es .bin"""
    if len(b) < EX_PIE or b[-EX_PIE:-EX_PIE + 4] != EX_MAGIA:
        return len(b), [], 0
    _v, tam, n, fl = struct.unpack_from("<IIII", b, len(b) - 16)
    return tam, [struct.unpack_from("<III", b, len(b) - EX_PIE - (n - i) * 12) for i in range(n)], fl


def cmd_empaquetar(a):
    datos = open(a.entrada, "rb").read()
    if a.entrada.lower().endswith(".bit") or datos[:2] == b"\x00\x09":
        datos = bit_a_bin(a.entrada)
    comprueba_bin(datos)
    if a.bloque or a.tr_bios:
        datos = con_bloques(datos, a.bloque, a.tr_bios)
        comprueba_bin(datos)
    idu = a.id.upper()
    if not idu or len(idu) > 8 or any(ord(c) not in ID_CARS for c in idu):
        raise Error("--id: 1 a 8 caracteres A-Z 0-9 _ -")
    if len(a.version) > 15 or any(not 0x20 <= ord(c) < 0x7F for c in a.version):
        raise Error("--version: hasta 15 caracteres ASCII")
    if a.crudo:
        guardado, metodo = datos, 0
    else:
        guardado, metodo = zlib.compress(datos, a.nivel), 1
    if len(guardado) > MAXPAY:
        raise Error("el contenido guardado (%d B) no cabe en un hueco (%d B)" % (len(guardado), MAXPAY))
    salida = a.o or os.path.splitext(a.entrada)[0] + ".mxp"
    mxp = mxp_pack(idu, a.serie, a.version, metodo, guardado, len(datos))
    open(salida, "wb").write(mxp)
    print("%s: %s %s serie %d, %s %d B -> bin %d B (%.1f %%), fichero %d B" % (
        salida, idu, a.version, a.serie, "crudo" if metodo == 0 else "zlib", len(guardado), len(datos), 100.0 * len(guardado) / len(datos), len(mxp)))


def desempaqueta(d):
    try:
        return zlib.decompress(d["guardado"]) if d["metodo"] else d["guardado"]
    except zlib.error as e:
        raise Error("zlib roto: %s" % e)


def cmd_info(a):
    d = mxp_unpack(open(a.fichero, "rb").read())
    print("id %s  version %s  serie %d  metodo %s" % (d["id"], d["version"], d["serie"], "zlib" if d["metodo"] else "crudo"))
    print("guardado %d B  bin %d B  sha256 %s" % (d["tam"], d["tam_bin"], d["sha"].hex()))
    if hashlib.sha256(d["guardado"]).digest() != d["sha"]:
        raise Error("SHA-256 del contenido NO coincide")
    print("SHA-256 del contenido: bien")
    b = desempaqueta(d)
    if len(b) != d["tam_bin"]:
        raise Error("el .bin descomprimido mide %d B, no %d" % (len(b), d["tam_bin"]))
    comprueba_bin(b)
    tam, bloques, fl = lee_bloques(b)
    print("descompresion: bien, .bin con sincronismo 66 55 99 AA, md5 del .bin %s" % hashlib.md5(b[:tam]).hexdigest())
    if bloques or fl:
        print(".bin %d B, %d bloques, banderas %d" % (tam, len(bloques), fl))
        for off, ddr, n in bloques:
            print("  DDR %08X  %6d B  sha256 %s" % (ddr, n, hashlib.sha256(b[off:off + n]).hexdigest()[:16]))


# ---------------------------------------------------------------- imagenes de disco (ficheros)
class Disco:
    def __init__(self, ruta, escribir=False):
        if not os.path.isfile(ruta):
            raise Error("%s no es un fichero normal (este programa nunca toca discos fisicos)" % ruta)
        self.f = open(ruta, "r+b" if escribir else "rb")
        self.f.seek(0, 2)
        self.secs = self.f.tell() // SEC

    def lee(self, sec, n=1):
        self.f.seek(sec * SEC)
        b = self.f.read(n * SEC)
        if len(b) != n * SEC:
            raise Error("lectura fuera de la imagen")
        return b

    def escribe(self, sec, datos):
        assert len(datos) % SEC == 0
        if sec * SEC + len(datos) > self.secs * SEC:
            raise Error("escritura fuera de la imagen")
        self.f.seek(sec * SEC)
        self.f.write(datos)
        self.f.flush()


def es_vbr(s):
    if s[3:11] in (b"EXFAT   ", b"NTFS    "):
        return True
    if s[0] not in (0xEB, 0xE9):
        return False
    c = s[13]
    return s[11] == 0 and s[12] == 2 and c and not (c & (c - 1)) and s[16] in (1, 2)


def mbr_analiza(s):
    if s[510] != 0x55 or s[511] != 0xAA or es_vbr(s):
        raise Error("el sector 0 no es un MBR normal")
    ents = []
    for i in range(4):
        e = s[0x1BE + 16 * i:0x1BE + 16 * i + 16]
        if e[0] not in (0, 0x80) or e[4] == 0xEE:
            raise Error("tabla de particiones dudosa o GPT")
        lba, n = struct.unpack_from("<II", e, 8)
        ents.append(dict(tipo=e[4], lba=lba, n=n, libre=(e == b"\0" * 16)))
    return ents


def mbr_plan(ents, secs):
    libres = [i for i, e in enumerate(ents) if e["libre"]]
    if not libres:
        raise Error("las 4 entradas del MBR estan ocupadas")
    fin = max([e["lba"] + e["n"] for e in ents if not e["libre"]] or [0])
    ini = max((fin + ALIN - 1) // ALIN * ALIN, ALIN)
    if ini + MIN_SECS > secs:
        raise Error("no hay 17 MB sin particionar al final de la tarjeta")
    libre = secs - ini
    return libres[0], ini, (PREF_SECS if libre >= PREF_SECS else libre // ALIN * ALIN)


def sb_pack(tam, dedicada=False):
    sb = bytearray(SEC)
    sb[0:4] = b"MXPF"
    n = min((tam - PRIMER) // HUECO, MAX_PERF)
    struct.pack_into("<IIIIII", sb, 4, 1, tam, PRIMER, HUECO, n, COPIA_MBR)
    if dedicada:
        struct.pack_into("<I", sb, 28, 1)           # +28 bit 0: tarjeta dedicada (campo libre en las betas)
    sb[32:41] = b"MSXimus Z"
    struct.pack_into("<I", sb, 0x1FC, crc32(sb[:0x1FC]))
    return bytes(sb)


def dir_pack(seq, ents):
    s = bytearray(SEC)
    s[0:4] = b"MXPD"
    struct.pack_into("<II", s, 4, seq, len(ents))
    for i, e in enumerate(ents):
        s[16 + 80 * i:16 + 80 * i + 80] = ent_pack(e["id"], e["serie"], e["version"], e["metodo"], e["lba"], e["tam"], e["tam_bin"], e["sha"])
    struct.pack_into("<I", s, 0x1FC, crc32(s[:0x1FC]))
    return bytes(s)


def montar(d):
    """Devuelve dict(part, secs, sf, ss, sn, cur, seq, perfiles) o None si no hay particion MXPF."""
    ents = mbr_analiza(d.lee(0))
    for e in ents:
        if e["tipo"] != 0xDA or e["n"] == 0 or e["lba"] + e["n"] > d.secs:
            continue
        sb = d.lee(e["lba"])
        if sb[0:4] != b"MXPF" or struct.unpack_from("<I", sb, 0x1FC)[0] != crc32(sb[:0x1FC]):
            continue
        ver, psecs, sf, ss, sn, _cm = struct.unpack_from("<IIIIII", sb, 4)
        if ver != 1 or psecs != e["n"] or not 0 < sn <= MAX_PERF or ss == 0 or sf <= COPIA_MBR or sf + sn * ss > psecs:
            continue
        m = dict(part=e["lba"], secs=psecs, sf=sf, ss=ss, sn=sn, perfiles=[], cur=None, seq=0,
                 dedicada=bool(struct.unpack_from("<I", sb, 28)[0] & 1))
        dirs = []
        for k in (0, 1):
            s = d.lee(e["lba"] + 1 + k)
            try:
                if s[0:4] != b"MXPD" or struct.unpack_from("<I", s, 0x1FC)[0] != crc32(s[:0x1FC]):
                    raise Error("dir")
                seq, n = struct.unpack_from("<II", s, 4)
                if n > MAX_PERF:
                    raise Error("dir")
                lst = []
                for i in range(n):
                    p = ent_unpack(s[16 + 80 * i:16 + 80 * i + 80])
                    if p["lba"] < sf or (p["lba"] - sf) % ss or (p["lba"] - sf) // ss >= sn or p["tam"] > ss * SEC:
                        raise Error("dir")
                    p["hueco"] = (p["lba"] - sf) // ss
                    if any(q["hueco"] == p["hueco"] or q["id"] == p["id"] for q in lst):
                        raise Error("dir")
                    lst.append(p)
                dirs.append((seq, lst))
            except Error:
                dirs.append(None)
        if dirs[0] is None and dirs[1] is None:
            m["danada"] = True
            return m
        if dirs[0] and dirs[1]:
            m["cur"] = 1 if ((dirs[1][0] - dirs[0][0]) & 0xFFFFFFFF) < 0x80000000 and dirs[1][0] != dirs[0][0] else 0
        else:
            m["cur"] = 0 if dirs[0] else 1
        m["seq"], m["perfiles"] = dirs[m["cur"]]
        return m
    return None


def p1_sector(n, volid):
    """sector n de P1 (n < F32_META): la FAT32 pequena de la TF1 «solo perfiles»; igual que p1_sector() de mxpf.c"""
    s = bytearray(SEC)
    if n in (0, 6):
        s[0:3] = b"\xeb\x58\x90"
        s[3:11] = b"MSXIMUSZ"
        struct.pack_into("<HBHB", s, 11, SEC, 1, F32_RSVD, 2)
        s[21] = 0xF8
        struct.pack_into("<HH", s, 24, 63, 255)
        struct.pack_into("<III", s, 28, DED_P1_LBA, DED_P1_SECS, F32_FATSZ)
        struct.pack_into("<IHH", s, 44, 2, 1, 6)
        s[64] = 0x80
        s[66] = 0x29
        struct.pack_into("<I", s, 67, volid)
        s[71:82] = b"MSXIMUS-Z  "
        s[82:90] = b"FAT32   "
        s[510:512] = b"\x55\xaa"
    elif n in (1, 7):
        struct.pack_into("<I", s, 0, 0x41615252)
        struct.pack_into("<I", s, 484, 0x61417272)
        struct.pack_into("<II", s, 488, DED_P1_SECS - F32_DATA - 3, 5)
        struct.pack_into("<I", s, 508, 0xAA550000)
    elif n in (2, 8):
        struct.pack_into("<I", s, 508, 0xAA550000)
    elif n in (F32_RSVD, F32_RSVD + F32_FATSZ):
        struct.pack_into("<IIIII", s, 0, 0x0FFFFFF8, 0x0FFFFFFF, 0x0FFFFFFF, 4, 0x0FFFFFFF)
    elif n == F32_DATA:
        s[0:11] = b"MSXIMUS-Z  "
        s[11] = 0x08
        s[32:43] = b"LEEME   TXT"
        s[43] = 0x20
        fecha = ((2026 - 1980) << 9) | (11 << 5) | 8
        struct.pack_into("<H", s, 32 + 16, fecha)
        struct.pack_into("<H", s, 32 + 24, fecha)
        struct.pack_into("<H", s, 32 + 26, 3)
        struct.pack_into("<I", s, 32 + 28, len(LEEME))
    elif n in (F32_DATA + 1, F32_DATA + 2):
        off = (n - F32_DATA - 1) * SEC
        trozo = LEEME[off:off + SEC]
        s[0:len(trozo)] = trozo
    return bytes(s)


def prepara_dedicada(d):
    """La preparacion de mxpf_prepara_dedicada (companion/mxpf.c) sobre una imagen: BORRA, no pregunta."""
    if d.secs < DED_FIN:
        raise Error("la imagen mide %d MB: hacen falta %d" % (d.secs // 2048, (DED_FIN + 2047) // 2048))
    mbr = d.lee(0)
    viejas = []
    if mbr[510:512] == b"\x55\xaa" and not es_vbr(mbr):
        for i in range(4):
            e = mbr[0x1BE + 16 * i:0x1BE + 16 * i + 16]
            lba, n = struct.unpack_from("<II", e, 8)
            viejas.append((e[4], lba, n))
    d.escribe(DED_P2_LBA + COPIA_MBR, mbr)
    d.escribe(DED_P2_LBA + 2, bytes(SEC))
    d.escribe(DED_P2_LBA + 1, dir_pack(1, []))
    d.escribe(DED_P2_LBA, sb_pack(DED_P2_SECS, True))
    volid = 0x4D5A0000 ^ d.secs
    for n in range(F32_META):
        d.escribe(DED_P1_LBA + n, p1_sector(n, volid))
    for tipo, lba, n in viejas:
        if tipo == 0 or n == 0:
            continue
        if tipo == 0xEE:
            d.escribe(1, bytes(SEC))
            d.escribe(d.secs - 1, bytes(SEC))
            continue
        if lba == 0 or lba >= d.secs or DED_P1_LBA <= lba < DED_P1_LBA + F32_META or DED_P2_LBA <= lba < DED_P2_LBA + 4:
            continue
        d.escribe(lba, bytes(SEC))
    nm = bytearray(SEC)
    struct.pack_into("<I", nm, 0x1B8, volid ^ 0x5A5AA5A5)
    nm[0x1BE:0x1CE] = bytes([0, 0xFE, 0xFF, 0xFF, 0x0C, 0xFE, 0xFF, 0xFF]) + struct.pack("<II", DED_P1_LBA, DED_P1_SECS)
    nm[0x1CE:0x1DE] = bytes([0, 0xFE, 0xFF, 0xFF, 0xDA, 0xFE, 0xFF, 0xFF]) + struct.pack("<II", DED_P2_LBA, DED_P2_SECS)
    nm[510:512] = b"\x55\xaa"
    d.escribe(0, bytes(nm))


def cmd_crear(a):
    secs = a.mb * 2048
    with open(a.img, "wb") as f:
        f.truncate(secs * SEC)
    d = Disco(a.img, True)
    mbr = bytearray(SEC)
    mbr[0x1B8:0x1BC] = b"\x4d\x58\x44\x31"
    mbr[510:512] = b"\x55\xaa"
    if a.fat:
        e = bytearray(16)
        e[0] = 0x80
        e[4] = 0x06
        struct.pack_into("<II", e, 8, 2048, a.fat * 2048)
        mbr[0x1BE:0x1CE] = e
        d.escribe(2048, (b"\xeb\x3c\x90MSDOS5.0" + struct.pack("<HBHBHHBHHHII", 512, 4, 1, 2, 512, 0, 0xF8, 64, 32, 2, 0, a.fat * 2048)).ljust(SEC, b"\0"))
    d.escribe(0, bytes(mbr))
    if a.dedicada:
        if a.fat:
            raise Error("--dedicada y --fat no van juntos")
        d.escribe(0, bytes(SEC))                    # tarjeta en blanco: la copia del sector 0 original (P2+3) es ceros, como en el companion
        prepara_dedicada(d)
    print("%s: %d MB, MBR%s%s" % (a.img, a.mb, " + FAT16 de %d MB" % a.fat if a.fat else "", " + dedicada (P1 FAT32 + P2 MXPF)" if a.dedicada else ""))


def cmd_preparar(a):
    d = Disco(a.img, True)
    if a.dedicada:
        prepara_dedicada(d)
        print("tarjeta dedicada preparada: P1 FAT32 %d MB, P2 MXPF %d MB" % (DED_P1_SECS // 2048, DED_P2_SECS // 2048))
        return
    if montar(d):
        raise Error("ya hay una particion MXPF")
    mbr = d.lee(0)
    e, ini, tam = mbr_plan(mbr_analiza(mbr), d.secs)
    d.escribe(ini + COPIA_MBR, mbr)
    d.escribe(ini + 2, bytes(SEC))
    d.escribe(ini + 1, dir_pack(1, []))
    d.escribe(ini, sb_pack(tam))
    nm = bytearray(mbr)
    x = 0x1BE + 16 * e
    nm[x:x + 16] = bytes([0, 0xFE, 0xFF, 0xFF, 0xDA, 0xFE, 0xFF, 0xFF]) + struct.pack("<II", ini, tam)
    d.escribe(0, bytes(nm))
    print("particion MXPF: entrada %d, sector %d, %d MB" % (e + 1, ini, tam // 2048))


def cmd_listar(a):
    d = Disco(a.img)
    m = montar(d)
    if not m:
        print("sin particion MXPF")
        return
    if m.get("danada"):
        print("particion MXPF danada (directorios rotos)")
        return
    print("particion MXPF%s en el sector %d: %d MB, %d huecos de %d MB, directorio %s secuencia %d" % (
        " DEDICADA" if m["dedicada"] else "", m["part"], m["secs"] // 2048, m["sn"], m["ss"] // 2048, "AB"[m["cur"]], m["seq"]))
    for i, p in enumerate(m["perfiles"]):
        print(" %d) %-8s %-10s serie %d  %s %d B -> bin %d B  hueco %d  sha %s" % (
            i + 1, p["id"], p["version"], p["serie"], "zlib" if p["metodo"] else "crudo", p["tam"], p["tam_bin"], p["hueco"], p["sha"].hex()[:8]))


def cmd_instalar(a):
    d = Disco(a.img, True)
    m = montar(d)
    if not m or m.get("danada"):
        raise Error("no hay particion MXPF utilizable")
    x = mxp_unpack(open(a.mxp, "rb").read())
    if hashlib.sha256(x["guardado"]).digest() != x["sha"]:
        raise Error("SHA-256 del .mxp mal")
    b = desempaqueta(x)
    if len(b) != x["tam_bin"]:
        raise Error("tamano del .bin no coincide")
    comprueba_bin(b)
    usados = {p["hueco"] for p in m["perfiles"]}
    libres = [h for h in range(m["sn"]) if h not in usados]
    if not libres:
        raise Error("no queda ningun hueco libre")
    h = libres[0]
    x["hueco"] = h
    x["lba"] = m["sf"] + h * m["ss"]
    pad = (-len(x["guardado"])) % SEC
    d.escribe(m["part"] + x["lba"], x["guardado"] + b"\0" * pad)
    lista = [p for p in m["perfiles"] if p["id"] != x["id"]] + [x]
    d.escribe(m["part"] + 1 + (m["cur"] ^ 1), dir_pack((m["seq"] + 1) & 0xFFFFFFFF, lista))
    print("instalado %s en el hueco %d" % (x["id"], h))


def cmd_borrar(a):
    d = Disco(a.img, True)
    m = montar(d)
    if not m or m.get("danada"):
        raise Error("no hay particion MXPF utilizable")
    lista = [p for p in m["perfiles"] if p["id"] != a.id.upper()]
    if len(lista) == len(m["perfiles"]):
        raise Error("no hay ningun perfil %s" % a.id)
    d.escribe(m["part"] + 1 + (m["cur"] ^ 1), dir_pack((m["seq"] + 1) & 0xFFFFFFFF, lista))
    print("borrado %s" % a.id.upper())


def cmd_vaciar(a):
    d = Disco(a.img, True)
    d.escribe(0, bytes(510) + b"\x55\xaa")
    print("MBR a cero (solo la firma 55AA)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("empaquetar")
    p.add_argument("entrada")
    p.add_argument("--id", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--serie", type=int, required=True)
    p.add_argument("-o")
    p.add_argument("--crudo", action="store_true")
    p.add_argument("--nivel", type=int, default=9)
    p.add_argument("--bloque", action="append", default=[])
    p.add_argument("--tr-bios", action="store_true")
    p.set_defaults(f=cmd_empaquetar)
    p = sub.add_parser("info")
    p.add_argument("fichero")
    p.set_defaults(f=cmd_info)
    im = sub.add_parser("imagen").add_subparsers(dest="sub", required=True)
    p = im.add_parser("crear")
    p.add_argument("img")
    p.add_argument("--mb", type=int, required=True)
    p.add_argument("--fat", type=int, default=0)
    p.add_argument("--dedicada", action="store_true")
    p.set_defaults(f=cmd_crear)
    for nom, fn in (("preparar", cmd_preparar), ("listar", cmd_listar), ("vaciar", cmd_vaciar)):
        p = im.add_parser(nom)
        p.add_argument("img")
        if nom == "preparar":
            p.add_argument("--dedicada", action="store_true")
        p.set_defaults(f=fn)
    p = im.add_parser("instalar")
    p.add_argument("img")
    p.add_argument("mxp")
    p.set_defaults(f=cmd_instalar)
    p = im.add_parser("borrar")
    p.add_argument("img")
    p.add_argument("id")
    p.set_defaults(f=cmd_borrar)
    a = ap.parse_args()
    try:
        a.f(a)
    except Error as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
