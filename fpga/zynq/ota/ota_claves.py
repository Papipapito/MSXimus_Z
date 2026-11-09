"""ota_claves.py — crea el par de claves ECDSA P-256 con el que se firman las actualizaciones de la MSXimus Z.

    python ota_claves.py            crea la clave (si no existe) y escribe la publica en el companion
    python ota_claves.py --publica  solo vuelve a escribir la publica (a partir de la privada que ya hay)

La PRIVADA se guarda FUERA de cualquier repositorio, en %USERPROFILE%\\.msximus_ota\\ota_privada.pem (o donde diga
MSXIMUS_OTA_CLAVE). No se sube nunca: con ella cualquiera podria firmar un BOOT.bin que las placas aceptarian.
Copia de seguridad: si se pierde, las placas ya grabadas solo aceptan actualizaciones firmadas con ella, asi que
habria que volver a grabarlas por JTAG con una clave nueva.

La PUBLICA va compilada en el companion (fpga/zynq/arm/companion/ota_clave.h, 65 bytes: el punto sin comprimir
04||X||Y) y a ota_publica.pem, junto a este fichero, para quien quiera comprobar una firma a mano.
"""
import os
import sys

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

AQUI = os.path.dirname(os.path.abspath(__file__))
CABECERA = os.path.join(AQUI, "..", "arm", "companion", "ota_clave.h")
PUBLICA_PEM = os.path.join(AQUI, "ota_publica.pem")


def ruta_privada():
    return os.environ.get("MSXIMUS_OTA_CLAVE") or os.path.join(os.path.expanduser("~"), ".msximus_ota", "ota_privada.pem")


def cargar_privada():
    ruta = ruta_privada()
    if not os.path.exists(ruta):
        sys.exit("No hay clave privada en %s: crea una con 'python ota_claves.py'" % ruta)
    with open(ruta, "rb") as f:
        return serialization.load_pem_private_key(f.read(), password=None)


def escribir_publica(priv):
    pub = priv.public_key()
    punto = pub.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    assert len(punto) == 65 and punto[0] == 4
    filas = []
    for i in range(0, 65, 13):
        filas.append("    " + ", ".join("0x%02X" % b for b in punto[i:i + 13]) + ",")
    texto = (
        "/* ota_clave.h — clave PUBLICA de las actualizaciones por red (ECDSA P-256, punto sin comprimir 04||X||Y).\n"
        " * La escribe fpga/zynq/ota/ota_claves.py; la privada no esta en ningun repositorio. Un BOOT.bin solo se\n"
        " * instala si su manifiesto viene firmado con la privada que corresponde a esta. */\n"
        "#ifndef OTA_CLAVE_H\n#define OTA_CLAVE_H\n"
        "static const unsigned char ota_clave_publica[65] = {\n" + "\n".join(filas) + "\n};\n#endif\n")
    with open(CABECERA, "w", encoding="utf-8", newline="\n") as f:
        f.write(texto)
    with open(PUBLICA_PEM, "wb") as f:
        f.write(pub.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    print("publica -> %s y %s" % (os.path.normpath(CABECERA), os.path.normpath(PUBLICA_PEM)))
    print("huella: " + punto[1:9].hex())


def main():
    if "--publica" in sys.argv[1:]:
        escribir_publica(cargar_privada())
        return
    ruta = ruta_privada()
    if os.path.exists(ruta):
        print("Ya hay clave privada en %s (no se toca)." % ruta)
        priv = cargar_privada()
    else:
        os.makedirs(os.path.dirname(ruta), exist_ok=True)
        priv = ec.generate_private_key(ec.SECP256R1())
        pem = priv.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                 serialization.NoEncryption())
        with open(ruta, "xb") as f:
            f.write(pem)
        print("Clave privada NUEVA en %s — haz una copia de seguridad y no la subas a ningun sitio." % ruta)
    escribir_publica(priv)


if __name__ == "__main__":
    main()
