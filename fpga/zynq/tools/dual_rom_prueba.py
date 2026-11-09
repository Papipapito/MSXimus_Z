#!/usr/bin/env python3
"""dual_rom_prueba.py - un cartucho de prueba de 16 KB para la maquina B del perfil Dual (tools/dual_rom.tcl cargar dual_prueba.rom).

Cabecera AB con INIT en 4010h. El programa limpia la pantalla (CLS, 00C3h), escribe un texto con la rutina CHPUT de la BIOS
(00A2h) y gira un contador de 0 a 9 tras el texto con POSIT (00C6h): si se ve moverse, B arranca su BIOS, encuentra el cartucho del
slot 1, lo inicia y ejecuta desde el, y su V9968 y su RAM funcionan. No usa la RAM de B mas que por la pila de la BIOS.

   dual_rom_prueba.py [salida]      (por defecto dual_prueba.rom)
"""
import sys


class A:
    def __init__(self, org):
        self.b = bytearray([0xFF] * 0x4000)
        self.base = org
        self.pc = org
        self.lab = {}
        self.fix = []

    def e(self, *bs):
        for x in bs:
            self.b[self.pc - self.base] = x & 0xFF
            self.pc += 1

    def label(self, n):
        self.lab[n] = self.pc

    def rel(self, op, n):
        self.e(op)
        self.fix.append((self.pc, n, 'r'))
        self.e(0)

    def call(self, a):
        self.e(0xCD, a & 0xFF, a >> 8)

    def resolve(self):
        for pos, n, k in self.fix:
            d = self.lab[n] - (pos + 1)
            assert -128 <= d <= 127
            self.b[pos - self.base] = d & 0xFF


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'dual_prueba.rom'
    a = A(0x4000)
    a.e(0x41, 0x42, 0x10, 0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)          # 'AB', INIT = 4010h, sin STATEMENT/DEVICE/TEXT
    a.label('init')                                                          # 4010h
    a.call(0x00C3)                                                           # CLS
    a.e(0x21); a.fix.append((a.pc, 'msg', 'a')); a.e(0, 0)                   # LD HL,msg
    a.label('p1')
    a.e(0x7E, 0xB7)                                                          # LD A,(HL) ; OR A
    a.rel(0x28, 'cont')                                                      # JR Z,cont
    a.call(0x00A2)                                                           # CHPUT
    a.e(0x23)                                                                # INC HL
    a.rel(0x18, 'p1')
    a.label('cont')
    a.e(0x06, 0x30)                                                          # LD B,'0'
    a.label('lazo')
    a.e(0x21, 0x03, 0x0B)                                                    # LD HL,0B03h: POSIT toma H = columna (11) y L = fila (3), justo tras 'Contador:'
    a.call(0x00C6)                                                           # POSIT
    a.e(0x78)                                                                # LD A,B
    a.call(0x00A2)                                                           # CHPUT
    a.e(0x11, 0x00, 0x00)                                                    # LD DE,0
    a.label('ret')
    a.e(0x1B, 0x7A, 0xB3)                                                    # DEC DE ; LD A,D ; OR E
    a.rel(0x20, 'ret')
    a.e(0x04, 0x78, 0xFE, 0x3A)                                              # INC B ; LD A,B ; CP '9'+1
    a.rel(0x20, 'lazo')
    a.e(0x06, 0x30)                                                          # LD B,'0'
    a.rel(0x18, 'lazo')
    a.label('msg')
    for ch in "MSXimus Z - perfil Dual: B ejecuta su cartucho\r\n\r\nContador:":
        a.e(ord(ch))
    a.e(0)
    # las referencias absolutas (LD HL,msg)
    for pos, n, k in list(a.fix):
        if k == 'a':
            t = a.lab[n]
            a.b[pos - a.base] = t & 0xFF
            a.b[pos - a.base + 1] = t >> 8
    a.fix = [f for f in a.fix if f[2] == 'r']
    a.resolve()
    open(out, 'wb').write(bytes(a.b))
    print('%s: %d bytes de codigo, msg en %04X' % (out, a.pc - a.base, a.lab['msg']))


if __name__ == '__main__':
    main()
