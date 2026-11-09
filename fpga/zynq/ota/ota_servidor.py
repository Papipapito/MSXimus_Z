"""ota_servidor.py — servidor de actualizaciones de la MSXimus Z para el PC (desarrollo, antes de msx.barcelona).

    python ota_servidor.py [--puerto 8000] [--dir servidor]

Sirve por HTTP la carpeta servidor/ (la que llena ota_publicar.py: servidor/zynq/manifiesto.txt y los BOOT.bin) y
contesta a la pregunta que la placa manda por difusion UDP al puerto 9474 al pulsar U en el OSD:
    placa -> "MSXIMUS-OTA? zynq7020-mini"      PC -> "MSXIMUS-OTA http://<IP del PC>:<puerto>/zynq/"
asi la placa no necesita saber la IP del PC. Si nadie contesta, la placa va a https://msx.barcelona/wp-content/ota/zynq/.
La placa solo instala lo que venga firmado con la clave de ota_claves.py: el servidor no tiene que ser de fiar.
La primera vez Windows preguntara si deja a Python usar la red: hay que permitirlo en redes privadas.
"""
import argparse
import functools
import http.server
import os
import socket
import threading

AQUI = os.path.dirname(os.path.abspath(__file__))
PUERTO_UDP = 9474


def ip_hacia(destino):
    """La IP de este PC que ve 'destino' (la interfaz por la que se sale hacia el)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((destino, 9))
        return s.getsockname()[0]
    finally:
        s.close()


def descubrimiento(puerto_http, ip=""):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((ip, PUERTO_UDP))
    while True:
        datos, (origen, puerto) = s.recvfrom(512)
        if not datos.startswith(b"MSXIMUS-OTA?"):
            continue
        url = "http://%s:%d/zynq/" % (ip_hacia(origen), puerto_http)
        s.sendto(("MSXIMUS-OTA " + url + "\n").encode("ascii"), (origen, puerto))
        print("udp: %s pregunta (%s) -> %s" % (origen, datos.decode("ascii", "replace").strip(), url), flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--puerto", type=int, default=8000)
    ap.add_argument("--dir", default=os.path.join(AQUI, "servidor"))
    ap.add_argument("--ip", default="", help="interfaz (por defecto todas; 127.0.0.1 para probar sin red)")
    a = ap.parse_args()
    man = os.path.join(a.dir, "zynq", "manifiesto.txt")
    if not os.path.exists(man):
        print("AVISO: no hay %s (ota_publicar.py lo crea)" % man)
    threading.Thread(target=descubrimiento, args=(a.puerto, a.ip), daemon=True).start()
    manejador = functools.partial(http.server.SimpleHTTPRequestHandler, directory=a.dir)
    srv = http.server.ThreadingHTTPServer((a.ip, a.puerto), manejador)
    print("MSXimus Z OTA: http://%s:%d/zynq/ (carpeta %s), descubrimiento UDP %d. Ctrl+C para parar."
          % (ip_hacia("8.8.8.8"), a.puerto, os.path.abspath(a.dir), PUERTO_UDP), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
