/* tr_bios.c — los bloques que un .mxp trae detras del .bin. El perfil TR los usa para la BIOS del turbo R y su Nextor.
 *
 * Lo descomprimido de un .mxp con bloques (tools/mxpf.py, little-endian, todo alineado a 4):
 *     .bin | bloques | tabla de n entradas { desplazamiento, direccion de DDR, bytes } | pie
 *     pie (20 B): "MXEX", version (1), bytes del .bin, n, banderas (bit 0: poner MBOX+0x1C bit 6, tr_bios)
 * El campo "bytes del .bin" del directorio cuenta TODO lo descomprimido, asi que el SHA-256, zlib, la instalacion y la OTA
 * no cambian. Sin pie, todo es .bin.
 *
 * El destino solo puede ser la zona de la BIOS del turbo R o la ventana de Nextor del pack. Lo que habia en la ventana se
 * guarda aqui, y se repone al cargar otro perfil: el pack del BOOT.bin solo se relee al reiniciar el PS.
 * La DDR de destino es strongly-ordered (mmu.c): no hay cache que vaciar. La copia va con el MSX parado (perfil_cargar). */
#include "xil_types.h"
#include "log.h"
#include "tr_bios.h"
#ifdef TRBIOS_HOST                                   /* banco en el PC (tests/tr_host): direcciones propias */
#include "tr_host.h"
#else
#define TRB_CTRL      ((volatile u32 *)0x1FF0001CU)  /* bit 6 tr_bios */
#define TRB_TEL       ((volatile u32 *)0x1FF000C4U)  /* telemetria del PL; bit 2 = perfil TR */
#define TRB_DDR(a)    ((volatile u32 *)(a))
#define TRB_DSB()     __asm__ volatile ("dsb" ::: "memory")
#endif

#define BIT_TR_BIOS   0x40U
#define EX_MAGIA      0x5845584DU                    /* "MXEX" */
#define EX_PIE        20U
#define EX_MAX        16U
#define ZONA_BIOS     0x0E400000U
#define ZONA_BIOS_T   0x00400000U
#define VENT_NEXTOR   0x10F40000U
#define VENT_NEXTOR_T 0x00020000U

static const u8 *pend_datos, *pend_tabla;            /* NULL = nada apuntado */
static u32 pend_n, pend_flags;
static u32 activo;                                   /* 1 = el perfil en marcha puso el bit 6 */
static u32 nextor_guardado;
static u32 nextor_base[VENT_NEXTOR_T / 4U];

static u32 rd32(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24); }

static int dentro(u32 a, u32 n, u32 zona, u32 tam) { return a >= zona && n <= tam && a - zona <= tam - n; }

void tr_ex_olvida(void) { pend_datos = 0; pend_tabla = 0; pend_n = 0U; pend_flags = 0U; }

int tr_ex_prepara(const u8 *datos, u32 total, u32 *bin)
{
    const u8 *pie;
    u32 b, n, tabla;
    tr_ex_olvida();
    *bin = total;
    if (total < EX_PIE || (total & 3U)) return 0;
    pie = datos + total - EX_PIE;
    if (rd32(pie) != EX_MAGIA) return 0;
    b = rd32(pie + 8); n = rd32(pie + 12);
    if (rd32(pie + 4) != 1U || n > EX_MAX || b == 0U || (b & 3U)) return -1;
    if (total < EX_PIE + n * 12U) return -1;
    tabla = total - EX_PIE - n * 12U;
    if (b > tabla) return -1;
    for (u32 i = 0; i < n; i++) {
        const u8 *e = datos + tabla + i * 12U;
        u32 off = rd32(e), ddr = rd32(e + 4), tam = rd32(e + 8);
        if ((off & 3U) || (ddr & 3U) || (tam & 3U) || off < b || off > tabla || tam > tabla - off) return -1;
        if (!dentro(ddr, tam, ZONA_BIOS, ZONA_BIOS_T) && !dentro(ddr, tam, VENT_NEXTOR, VENT_NEXTOR_T)) return -1;
    }
    *bin = b;
    pend_datos = datos; pend_tabla = datos + tabla; pend_n = n; pend_flags = rd32(pie + 16);
    return 0;
}

void tr_ex_aplica(void)
{
    if (nextor_guardado) {                           /* lo del perfil anterior fuera, antes de poner nada */
        for (u32 i = 0; i < VENT_NEXTOR_T / 4U; i++) TRB_DDR(VENT_NEXTOR)[i] = nextor_base[i];
        nextor_guardado = 0U;
    }
    if (activo) { *TRB_CTRL &= ~BIT_TR_BIOS; activo = 0U; }
    for (u32 i = 0; i < pend_n; i++) {
        const u8 *e = pend_tabla + i * 12U;
        u32 off = rd32(e), ddr = rd32(e + 4), tam = rd32(e + 8);
        const u8 *s = pend_datos + off;
        if (!nextor_guardado && dentro(ddr, tam, VENT_NEXTOR, VENT_NEXTOR_T)) {
            for (u32 k = 0; k < VENT_NEXTOR_T / 4U; k++) nextor_base[k] = TRB_DDR(VENT_NEXTOR)[k];
            nextor_guardado = 1U;
        }
        for (u32 k = 0; k < tam / 4U; k++) TRB_DDR(ddr)[k] = rd32(s + k * 4U);
    }
    if (pend_flags & 1U) { *TRB_CTRL |= BIT_TR_BIOS; activo = 1U; }
    TRB_DSB();
    if (pend_n) { log_str("mxpf: "); log_dec(pend_n); log_str(" bloques a la DDR\n"); }
}

int tr_bios_estado(void)
{
    if (!((*TRB_TEL >> 2) & 1U)) return TR_BIOS_NO;
    if (activo) return TR_BIOS_PERFIL;
    return (*TRB_CTRL & BIT_TR_BIOS) ? TR_BIOS_JTAG : TR_BIOS_FALTAN;
}
