/* yrw801.c — comprobacion de la ROM de ondas del OPL4 (YRW801) en la DDR (13/10/2026).
 *
 * La YRW801 (2 MB) no la carga el RTL: el FSBL la deja en la DDR en 0x0F000000 (boot.bif) y el PL la lee por
 * wave_axi (S_AXI_GP0). Un BOOT.bin montado con otra ROM, una partición sin cargar o un arranque por JTAG sin
 * WAVE_ROM dejan la zona con basura o a cero y el OPL4 suena a nada o a ruido sin avisar. Aqui se suman los bytes
 * de los 2 MB y se comparan con los de la YRW801 de verdad (md5 42af93619160..., suma 270522894 = 101FDA0Eh; la
 * misma comprobacion que hace yrw801_loader.v en el MoonTANG). NO bloquea nada: solo deja el resultado para el
 * panel F12 (osd_info.c) y la OLED (oled.c); el OPL4 sigue funcionando igual.
 *
 * Coste: la zona es strongly-ordered (mmu.c la deja como al resto de la DDR, solo la toca esta CPU y nadie la
 * escribe), asi que cada palabra es un acceso suelto a la DDR: 524288 lecturas de 32 bits, del orden de 30 a 100 ms
 * con el reloj del A9 (no medido en placa: el tiempo real queda en el log del ARM al terminar, ver abajo). Por eso
 * NO va antes de MSX_RUN: yrw801_poll() la hace despues, por tramos de 32 KB en las vueltas del bucle de main()
 * en las que el PL no espera una peticion de la SD (<= ~1,6 ms por vuelta; el arranque del MSX no se retrasa).
 *
 * No hay un sitio en el buzon para que el menu del MSX lo lea: la telemetria (MBOX+0x40..) la escribe el PL y lo que
 * el PL lee del ARM (MBOX+0x00..0x27, SDBOX W0/W3) no llega al Z80 sin RTL. De momento solo el panel y la OLED.   */
#include "xil_types.h"
#include "log.h"
#include "yrw801.h"
#ifndef YRW801_HOST                                 /* banco en el PC (tests/host_yrw801_test.c): ROM, reloj y COUNTS_PER_SECOND propios */
#include "xparameters.h"
#define YRW801_ROM ((const u32 *)0x0F000000U)       /* DDR: la deja el FSBL (boot.bif, load=0x0F000000) */
#endif

#define YRW801_PAL    0x80000U                      /* 2 MB en palabras de 32 bits */
#define YRW801_SUMA   0x101FDA0EU                   /* suma de los bytes de la YRW801 real */
#define TRAMO_PAL     8192U                         /* palabras por vuelta (32 KB) */

extern u64 gt_now(void);

static int estado;                                  /* YRW801_*: a cero (COMPROBANDO) hasta acabar */
static u32 suma, pal;                               /* suma de bytes y palabras ya sumadas */
static u64 t_ini, t_act;                            /* primera vuelta, y tiempo que se ha ido de verdad en sumar */

int yrw801_estado(void) { return estado; }

void yrw801_poll(void)
{
    const u32 *rom = YRW801_ROM + pal;
    u32 n = YRW801_PAL - pal;
    u64 a, b;
    if (estado != YRW801_COMPROBANDO) return;
    a = gt_now();
    if (pal == 0U) t_ini = a;
    if (n > TRAMO_PAL) n = TRAMO_PAL;
    for (u32 i = 0; i < n; i++) {
        u32 w = rom[i];
        suma += (w & 0xFFU) + ((w >> 8) & 0xFFU) + ((w >> 16) & 0xFFU) + (w >> 24);
    }
    pal += n;
    b = gt_now();
    t_act += b - a;
    if (pal < YRW801_PAL) return;
    estado = (suma == YRW801_SUMA) ? YRW801_OK : YRW801_MAL;
    log_str("YRW801: suma "); log_hex(suma);
    if (estado == YRW801_OK) log_str(" OK");
    else { log_str(" NO VALIDA (esperada "); log_hex(YRW801_SUMA); log_str(", cabeza "); log_hex(YRW801_ROM[0]); log_str(")"); }
    log_str(", "); log_dec((u32)(t_act / (u64)(COUNTS_PER_SECOND / 1000000U))); log_str(" us sumando, ");
    log_dec((u32)((b - t_ini) / (u64)(COUNTS_PER_SECOND / 1000U))); log_str(" ms desde la primera vuelta\n");
}
