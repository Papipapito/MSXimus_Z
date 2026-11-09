/* mmu.c — MMU del core 0 (23/09/2026, para el MP3). La regla: NO CAMBIAR NADA DE LO QUE YA FUNCIONA.
 *
 * Sin MMU, toda la memoria de datos del A9 es strongly-ordered: el companion vive de eso (el DMA de la SD,
 * el EHCI del USB, el buzon, el anillo del WaveGame y la imagen de la DDR los ven sin mantener cache).
 * Aqui se enciende la MMU con TODO mapeado strongly-ordered igual que antes, salvo dos zonas que nadie
 * mas que este core toca:
 *   - el CODIGO y las constantes: de 0x00100000 a __rw_start (.vectors, .text, .rodata, .ARM.exidx),
 *     paginas de 4 KB normales con cache. Nadie escribe ahi (el enlazador alinea .data a 4 KB);
 *   - la zona del MP3 (seccion .mp3, 0x00500000, 1 MB): buffer de entrada, PCM, descodificador y su pila.
 *     minimp3 NECESITA memoria normal: el memcpy de newlib lee palabras desalineadas y en strongly-ordered
 *     eso es DATA ABORT (medido el 23/09 en el core 1: ldr r3,[r1,#-4] dentro de memcpy).
 *   - 26/09 el heap de Mbed TLS (0x00A00000, 4 MB) y 30/09 la zona de la actualizacion por red (0x01000000,
 *     9 MB: el BOOT.bin bajado, el manifiesto y el SHA-256; ota.c). Solo las toca la CPU.
 * .data, .bss y la pila del companion siguen strongly-ordered, asi que los buffers de DMA no cambian.
 * La L2 (PL310) la apaga main() antes (l2_disable): la cache es solo la L1 de este core.
 *
 * Descriptores (ARMv7 corto): seccion 1 MB normal WBWA = TEX 001, C=1, B=1, AP=11 -> 0x1C0E;
 * seccion strongly-ordered = TEX 000, C=0, B=0, AP=11 -> 0x0C02; pagina 4 KB normal WBWA -> 0x07E;
 * pagina 4 KB strongly-ordered -> 0x032. Tabla de 2o nivel = direccion | 0x1.                          */
#include "xil_types.h"

extern void dcache_inval_all(void);
extern void mmu_enable(u32 *l1);
extern char __rw_start[];                    /* lscript.ld: fin del codigo, alineado a 4 KB */

#define SEC_NORMAL  0x00001C0EU
#define SEC_SO      0x00000C02U
#define PAGE_NORMAL 0x0000007EU
#define PAGE_SO     0x00000032U
#define MB_CODE     0x001U                   /* 0x00100000: el companion */
#define MB_MP3      0x005U                   /* 0x00500000: seccion .mp3 */
#define MB_TLS      0x00AU                   /* 0x00A00000..0x00DFFFFF: heap de Mbed TLS (26/09), 4 MB, solo este core */
#define MB_OTA      0x010U                   /* 0x01000000..0x018FFFFF: actualizacion por red (ota.c, 30/09), 9 MB, solo este core */

static u32 l1[4096] __attribute__((aligned(16384)));
static u32 l2_code[256] __attribute__((aligned(1024)));

void mmu_init(void)
{
    u32 rw = (u32)__rw_start;
    for (u32 i = 0; i < 4096U; i++) l1[i] = (i << 20) | SEC_SO;
    l1[MB_MP3] = (MB_MP3 << 20) | SEC_NORMAL;
    for (u32 k = 0; k < 4U; k++) l1[MB_TLS + k] = ((MB_TLS + k) << 20) | SEC_NORMAL;
    for (u32 k = 0; k < 9U; k++) l1[MB_OTA + k] = ((MB_OTA + k) << 20) | SEC_NORMAL;
    for (u32 j = 0; j < 256U; j++) {
        u32 a = (MB_CODE << 20) | (j << 12);
        l2_code[j] = a | (a < rw ? PAGE_NORMAL : PAGE_SO);
    }
    l1[MB_CODE] = (u32)l2_code | 0x1U;
    __asm__ volatile ("dsb" ::: "memory");
    dcache_inval_all();                      /* la L1 D sale del FSBL/JTAG con contenido indefinido */
    mmu_enable(l1);
}
