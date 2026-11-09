/* nextor_b_rom.h — COPIA PUBLICA: SIN LA ROM.
 * En el repositorio original este fichero lleva Nextor-B (Nextor 2.1.4 de Konamiman con el driver de la maquina B del perfil Dual)
 * comprimido con zlib. Nextor lleva una licencia que no permite redistribuir su ROM, asi que aqui no esta.
 * Con este fichero el companion se compila igual, y el perfil Dual arranca, pero la maquina B se queda sin MSX-DOS: dual_disco_compone()
 * no puede descomprimir nada, lo apunta en el log y deja B sin tocar.
 * Para tener el verdadero hace falta una ROM de Nextor-B propia (128 KB) y la herramienta que la comprime:
 *     python fpga/zynq/tools/gen_nextor_b_h.py --rom <su Nextor-B de 128 KB> --salida fpga/zynq/arm/companion/nextor_b_rom.h
 * Las dos longitudes de abajo son las del fichero verdadero: NEXTOR_B_ROM_LEN es lo que debe medir la ROM descomprimida. */
#ifndef NEXTOR_B_ROM_H
#define NEXTOR_B_ROM_H
#include "xil_types.h"

#define NEXTOR_B_ROM_LEN   131072U  /* bytes de la ROM descomprimida */
#define NEXTOR_B_ROM_ZLEN  1U       /* sin ROM: un byte, que no es un flujo zlib valido */

static const u8 nextor_b_rom_z[NEXTOR_B_ROM_ZLEN] = { 0 };
#endif
