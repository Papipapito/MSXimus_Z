"""ota_publicar.py — prepara una actualizacion de la MSXimus Z: copia los BOOT.bin, escribe manifiesto.txt y lo firma.

    python ota_publicar.py --version Z1.2.2 --serie 2026100101 [--canal beta] \\
        --imagen nextor214=../../../files/20261001/BOOT_z122_nextor214.bin \\
        --imagen nextor3=../../../files/20261001/BOOT_z122_nextor3.bin \\
        --notas "V9968: arreglos de HRA" --notas "Actualizacion por red" \\
        --perfil ../../../files/20261101/sonido.mxp

Cada BOOT.bin tiene que salir de make_boot.sh con OTA_VERSION y OTA_SERIE iguales a los de aqui (su particion
ota_info lo dice, y el companion lo vuelve a mirar antes de grabar). Cada --perfil <fichero.mxp> (tools/mxpf.py empaquetar)
es un perfil del PL para la microSD de TF1: se copia a la salida como PERFIL_<ID>_<version>.mxp y se anuncia con una linea
perfil= dentro de la parte firmada. Su serie TIENE que ser la de --serie (un perfil solo se carga con el sistema para el que se
hizo). Las placas con un companion de antes de los perfiles ignoran esas lineas. Sale todo en servidor/zynq/ (o --salida):
lo que sirve ota_servidor.py en el PC y lo que se sube tal cual a https://msx.barcelona/wp-content/ota/zynq/ (con ota_subir.py).

Manifiesto (texto, LF; el companion lo lee en ota.c):
    MSXIMUS-OTA 1
    placa=zynq7020-mini
    version=Z1.2.2
    serie=2026100101            entero creciente: una placa solo ofrece series mayores que la suya
    fecha=2026-10-01
    canal=beta                  solo en el canal beta (Z1.3): otra carpeta, servidor/zynq/beta/ -> .../ota/zynq/beta/
    notas=...                   hasta 3 lineas de 25 columnas (se ven en el OSD)
    imagen=<variante> <fichero> <tamano> <sha256>    nextor214, nextor3 (castellano), nextor214-en, nextor3-en (ingles)
    perfil=<ID> <version> <fichero> <tamano> <sha256> <tamano del .bin> <serie>    hasta 6 (ver --perfil); los tamanos y el
                                SHA-256 son los del fichero .mxp entero; serie = la de la linea serie= de arriba
    firma=<r||s en hex>         ECDSA P-256 + SHA-256 de todo lo anterior (hasta el salto de linea de antes)
"""
import argparse
import datetime
import hashlib
import os
import re
import shutil
import struct
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature

from ota_claves import cargar_privada

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, "..", "tools"))
import mxpf                                                # formato .mxp (fpga/zynq/tools/mxpf.py)
PLACA = "zynq7020-mini"
IMG_MAX = 0x7F0000                     # ranura B: 0x800000..0xFF0000 (los ultimos 64 KB son registro + config)
# castellano con los nombres de siempre (las placas con un companion de antes de la Z1.2.3 solo conocen estos y solo
# leen las dos primeras imagenes: por eso van primero) e ingles con -en (01/10/2026)
VARIANTES = ("nextor214", "nextor3", "nextor214-en", "nextor3-en")
MAX_PERFILES = mxpf.MAX_PERF           # una entrada de directorio de la microSD cada uno; ota.c lee hasta 6


def info_de(img):
    """La particion ota_info de un BOOT.bin (make_boot.sh) como diccionario."""
    i = img.find(b"MOTI1\nversion=")
    if i < 0:
        return None
    texto = img[i:i + 256].split(b"\0")[0].decode("ascii", "replace")
    return dict(l.split("=", 1) for l in texto.splitlines()[1:] if "=" in l)


def comprobar(ruta, variante, version, serie, canal):
    img = open(ruta, "rb").read()
    if len(img) > IMG_MAX:
        sys.exit("%s: %d B no cabe en la ranura B (%d como mucho)" % (ruta, len(img), IMG_MAX))
    w = struct.unpack_from("<19I", img, 0x00)
    if w[8] != 0xAA995566 or w[9] != 0x584C4E58:
        sys.exit("%s: no es un BOOT.bin de Zynq (sin cabecera de arranque)" % ruta)
    if (~sum(w[8:18]) & 0xFFFFFFFF) != w[18]:
        sys.exit("%s: la suma de la cabecera de arranque no cuadra" % ruta)
    info = info_de(img)
    if info is None:
        sys.exit("%s: sin particion ota_info (hacerlo con make_boot.sh de 30/09 en adelante)" % ruta)
    esperado = {"version": version, "serie": str(serie), "variante": variante, "placa": PLACA, "canal": canal}
    for k, v in esperado.items():
        if info.get(k, "oficial" if k == "canal" else None) != v:   # canal: los BOOT.bin de antes de la Z1.3 no lo llevan
            sys.exit("%s: ota_info dice %s=%s y aqui %s (OTA_VERSION/OTA_SERIE de make_boot.sh)" % (ruta, k, info.get(k), v))
    return img


def comprobar_perfil(ruta, serie):
    """Un .mxp de tools/mxpf.py: cabecera, SHA-256 del contenido, zlib y serie. Devuelve (datos, d de mxpf.mxp_unpack)."""
    datos = open(ruta, "rb").read()
    try:
        d = mxpf.mxp_unpack(datos)
        if hashlib.sha256(d["guardado"]).digest() != d["sha"]:
            raise mxpf.Error("el SHA-256 del contenido guardado no es el de la cabecera")
        b = mxpf.desempaqueta(d)
        if len(b) != d["tam_bin"]:
            raise mxpf.Error("el .bin descomprimido mide %d B y la cabecera dice %d" % (len(b), d["tam_bin"]))
        mxpf.comprueba_bin(b)
    except mxpf.Error as e:
        sys.exit("%s: %s" % (ruta, e))
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,15}", d["version"]):
        sys.exit("%s: la version del perfil (%r) tiene que ser A-Za-z0-9._- (15 como mucho): es lo que va en el manifiesto"
                 % (ruta, d["version"]))
    if d["serie"] != serie:
        sys.exit("%s: es del sistema de serie %d y se publica la serie %d (un perfil solo se carga con el BOOT.bin para el que"
                 " se hizo: rehacerlo con mxpf.py empaquetar --serie %d)" % (ruta, d["serie"], serie, serie))
    return datos, d


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", required=True)
    ap.add_argument("--serie", required=True, type=int)
    ap.add_argument("--fecha", default=datetime.date.today().isoformat())
    ap.add_argument("--notas", action="append", default=[])
    ap.add_argument("--imagen", action="append", required=True, help="variante=ruta (nextor214 / nextor3)")
    ap.add_argument("--perfil", action="append", default=[], metavar="FICHERO.mxp",
                    help="un perfil del PL para la TF1 (tools/mxpf.py empaquetar); repetible, hasta %d; su serie tiene que ser --serie"
                    % MAX_PERFILES)
    ap.add_argument("--canal", choices=("oficial", "beta"), default="oficial",
                    help="beta (Z1.3): las builds de los experimentos, en una sola variante (nextor214-en)")
    ap.add_argument("--salida", default=None, help="por defecto servidor/zynq (oficial) o servidor/zynq/beta")
    a = ap.parse_args()
    if a.salida is None:
        a.salida = os.path.join(AQUI, "servidor", "zynq", *(["beta"] if a.canal == "beta" else []))

    if not re.fullmatch(r"[A-Za-z0-9._-]{1,15}", a.version):
        sys.exit("version: letras, cifras, . _ - (15 como mucho)")
    if len(a.notas) > 3 or any(len(n) > 25 for n in a.notas):
        sys.exit("notas: 3 lineas de 25 columnas como mucho (es lo que cabe en la tarjeta del OSD)")
    if len(a.perfil) > MAX_PERFILES:
        sys.exit("perfil: %d como mucho (una entrada de directorio de la tarjeta cada uno)" % MAX_PERFILES)
    perfiles = [(ruta,) + comprobar_perfil(ruta, a.serie) for ruta in a.perfil]   # nada se escribe si alguno esta mal
    ids = [d["id"] for _, _, d in perfiles]
    if len(set(ids)) != len(ids):
        sys.exit("perfil: id repetido (%s)" % ", ".join(sorted(i for i in set(ids) if ids.count(i) > 1)))
    priv = cargar_privada()
    os.makedirs(a.salida, exist_ok=True)

    lineas = ["MSXIMUS-OTA 1", "placa=" + PLACA, "version=" + a.version, "serie=%d" % a.serie, "fecha=" + a.fecha]
    if a.canal == "beta":
        lineas.append("canal=beta")
    lineas += ["notas=" + n for n in a.notas]
    vistas = set()
    for par in sorted(a.imagen, key=lambda x: VARIANTES.index(x.partition("=")[0]) if x.partition("=")[0] in VARIANTES else 99):
        variante, _, ruta = par.partition("=")
        if variante not in VARIANTES or not ruta:
            sys.exit("--imagen %s: la variante tiene que ser una de %s" % (par, ", ".join(VARIANTES)))
        if variante in vistas:
            sys.exit("variante %s repetida" % variante)
        vistas.add(variante)
        img = comprobar(ruta, variante, a.version, a.serie, a.canal)
        nombre = "BOOT_%s_%s.bin" % (a.version, variante)
        destino = os.path.join(a.salida, nombre)
        if os.path.abspath(ruta) != os.path.abspath(destino):
            shutil.copyfile(ruta, destino)
        sha = hashlib.sha256(img).hexdigest()
        lineas.append("imagen=%s %s %d %s" % (variante, nombre, len(img), sha))
        print("%-12s %s  %d B  sha256 %s..." % (variante, nombre, len(img), sha[:16]))

    for ruta, datos, d in perfiles:
        nombre = "PERFIL_%s_%s.mxp" % (d["id"], d["version"])
        with open(os.path.join(a.salida, nombre), "wb") as f:
            f.write(datos)
        sha = hashlib.sha256(datos).hexdigest()
        lineas.append("perfil=%s %s %s %d %s %d %d" % (d["id"], d["version"], nombre, len(datos), sha, d["tam_bin"], d["serie"]))
        print("perfil %-8s %s  %d B (bin %d B)  sha256 %s..." % (d["id"], nombre, len(datos), d["tam_bin"], sha[:16]))

    firmado = ("\n".join(lineas) + "\n").encode("ascii")
    der = priv.sign(firmado, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    firma = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    priv.public_key().verify(encode_dss_signature(r, s), firmado, ec.ECDSA(hashes.SHA256()))   # por si acaso
    with open(os.path.join(a.salida, "manifiesto.txt"), "wb") as f:
        f.write(firmado + b"firma=" + firma.hex().encode("ascii") + b"\n")
    print("manifiesto firmado -> %s" % os.path.join(a.salida, "manifiesto.txt"))


if __name__ == "__main__":
    main()
