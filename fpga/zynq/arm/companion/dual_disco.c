/* dual_disco.c — MSX-DOS en la maquina B del perfil Dual y la SD de TF2 compartida (Z1.3.2b9; bios/nextor214/driver_b.inc es el lado Z80,
 * tb/emu_b_nextor.py (ArmB) el modelo en Python de este lado). B NO tiene imagen de disco propia: ve la MISMA tarjeta de TF2 que A (la tarjeta
 * entera, con su MBR, como dispositivo 1 de Nextor-B) a traves de un BUZON en la DDR. Sin PL nuevo.
 *
 * EL CARTUCHO. Nextor-B (128 KB, nextor_b_rom.h comprimido con zlib: tools/gen_nextor_b_h.py) va al cartucho de B (0x0C400000) con el mapper 2
 * (Konami SCC, sin lineal: la megaram_scc de B, que el driver usa como RAM). El banco del driver (bancos SCC 14 y 15 = DDR 0x0C41C000-0x0C41FFFF)
 * es la ventana de B al buzon:
 *     0x0C41FC00  los 512 bytes del sector (7C00h-7DFFh para el Z80)
 *     0x0C41FE00  los registros R (7E00h-7E3Fh): R+0 ENABLE (sin uso), R+1 CMD (el Z80 escribe 1 leer / 2 escribir; el ARM lo pone a 0),
 *                 R+2 STATUS (el Z80 escribe 80h = ocupado ANTES de CMD; el ARM escribe el final: bit 7 = 0, bit 0 error de E/S, bit 1 sin
 *                 tarjeta, bit 2 PROTEGIDO CONTRA ESCRITURA), R+3..R+6 SADDR (el LBA absoluto de la TF2, 32 bits little endian), R+0Ch CTYPE
 *                 (0 sin tarjeta, 3 SDHC), R+1Bh SEQ (la secuencia de la orden: la escribe el Z80 antes de CMD), R+1Ch ACK (la secuencia de la
 *                 ultima orden atendida: la escribe el ARM ANTES de STATUS), R+1Dh OWN (1 = B es la duena), R+20h..23h la firma "NXTB",
 *                 R+24h..27h NSEC (sectores de la TF2, u32).
 * CMD, STATUS y SADDR0 comparten palabra de 32 bits (R+0..R+3) y el Z80 escribe bytes por el puerto HP con strobes de byte: el ARM escribe los
 * REGISTROS SIEMPRE DE BYTE EN BYTE (reg_wr8), nunca una palabra (pisaria un byte que el Z80 acaba de escribir). Los datos del sector si van por
 * palabras. Toda la memoria del companion es strongly-ordered (mmu.c): no hay cache que limpiar; la cache de B es incoherente con la DDR y eso lo
 * resuelve el driver Z80 (expulsa la linea antes de leer). Orden de una orden: leer CMD (byte) != 0 -> leer SADDR (4 bytes) y SEQ -> CMD = 0
 * (byte) -> atender -> lectura: sd_read a un buffer estatico alineado (el DMA de la SD no ve la cache) y copiarlo a la ventana de datos; escritura:
 * copiar la ventana a ese buffer y escribir -> dsb, releer la ultima palabra de datos escrita (fuerza a que la escritura llegue) y POR ULTIMO ACK
 * y STATUS (byte) y dsb. El Z80 solo da por buena una respuesta con ACK = su SEQ: una respuesta tardia de una orden que ya abandono se ignora.
 * Solo se atiende con la firma "NXTB" en la DDR, el cartucho de B con el mapper 2 y la marca de dual_disco_compone: si alguien (xsdb, un juego
 * de Shift+D) cambia el cartucho, el buzon deja de existir.
 *
 * LA DUENA. En cada momento UNA maquina escribe en la SD y la otra va en SOLO LECTURA (arranque y PL recargado: A). Una escritura de la que no
 * es duena se rechaza: B con STATUS bit 2 (el driver da .WPROT); A con st = 2 en sd_servir (el PL lo convierte siempre en el bit "timeout" del
 * core, asi que el driver de A pregunta el MOTIVO con el bloque de estado). Excepcion: dual_disco_rangos_a(lo, n, k) deja a A escribir DENTRO de
 * esos rangos de sectores aunque no sea la duena (dual.c los saca de los descriptores de SRAM del menu: el .SRM de la partida y el de la Game
 * Master 2). Sin el perfil Dual A se comporta como siempre.
 *
 * NO HAY "CAMBIADO". Nextor trata un DEV_STATUS = 2 como un cambio de tarjeta y desmapea todas las unidades del dispositivo (UNMAPALL), lo que
 * rompe las tarjetas con varias particiones y sus MAPDRV: los LUN de las dos maquinas son FIJOS. La que lee sin ser duena puede ver datos viejos
 * en los bufer de Nextor; la que GANA la escritura se reinicia (dual.c recompone Nextor-B en B; en A solo se avisa). dual_disco_toma_aviso_a()
 * dice si A ha ganado la SD despues de que B escribiera (una sola vez).
 *
 * LA TARJETA. Si la tarjeta de TF2 se retira o se cambia mientras B tiene Nextor-B (dual_disco_tarjeta_cambio, main.c), B se queda con una tabla
 * de particiones y un tamano que ya no son los de la tarjeta: sus ordenes se contestan "sin tarjeta" hasta que se recomponga Nextor-B (tecla M).
 *
 * EL BLOQUE DE ESTADO DE A. A lo pide como una lectura de un solo sector por el proxy normal (sd_servir, main.c): LBA 0x7FFFFFFD. Solo con el
 * perfil Dual (sin el, ese LBA cae fuera de la tarjeta, como siempre). 512 B (el resto a cero): +0 "DUAL", +4 version (2), +5 duena (0 A, 1 B), +6
 * A solo lee (1 si la duena es B: A no puede escribir salvo en sus rangos).
 *
 * TIEMPO. B pregunta por el buzon cuando le da la gana: el bucle principal duerme en WFI y solo le despierta el timer de 10 ms o una peticion
 * de A. Mientras B usa el buzon (dual_disco_activo: ha pasado una orden hace menos de 250 ms) main.c no duerme y atiende a B sin esperar. Las
 * esperas largas del companion (sd_ceder: instalar un perfil, leer carpetas grandes) tambien llaman a dual_disco_poll.
 * Todo corre en el hilo del bucle principal (como la TF1): A y B nunca tocan la tarjeta a la vez. */
#include "xil_types.h"
#include "log.h"
#include "inflate.h"
#include "dual.h"
#include "dual_disco.h"
#include "nextor_b_rom.h"
#include "xparameters.h"                                   /* COUNTS_PER_SECOND */
#ifdef DUAL_HOST                                           /* banco del PC (tests/dual_host): las mismas direcciones, con mmap */
#define DD_DSB()        ((void)0)
extern void dd_traza(int esc, int ancho, u32 dir);        /* el banco apunta cada acceso al buzon y a la ventana de datos */
#define DD_TRAZA(e, a, d) dd_traza(e, a, d)
#else
#define DD_DSB()        __asm__ volatile ("dsb" ::: "memory")
#define DD_TRAZA(e, a, d) ((void)0)
#endif

#define DD_DATOS        0x0C41FC00U                        /* los 512 bytes del sector (7C00h) */
#define DD_REG          0x0C41FE00U                        /* los registros (7E00h) */
#define DD_OFF_REG      0x1FE00U                           /* y su sitio dentro de la ROM de 128 KB */
#define R_CMD           0x01U
#define R_STATUS        0x02U
#define R_SADDR         0x03U
#define R_CTYPE         0x0CU
#define R_SEQ           0x1BU
#define R_ACK           0x1CU
#define R_OWN           0x1DU
#define R_SIG           0x20U
#define R_NSEC          0x24U
#define ST_IO           0x01U                              /* STATUS: error de E/S (y orden o LBA no validos) */
#define ST_SINTARJ      0x02U                              /* sin tarjeta */
#define ST_PROT         0x04U                              /* protegido contra escritura: B no es la duena */
#define DD_CTL_MASCARA  0x3AU                              /* B_CTL: cartucho (bit 1), mapper (4:3), lineal (5)... */
#define DD_CTL_NEXTOR   0x12U                              /* ... = cartucho puesto, mapper 2 (Konami SCC), sin lineal */
#define DD_CTL_CORRE    0x01U                              /* B corre */
#define DD_ACTIVO_MS    250U
#define DD_MAX_RG       16                                 /* rangos de excepcion de A: el .SRM (32 KB) y el .SRM de la GM2 (8 KB), cluster a cluster si estan partidos */

/* ---- el acceso al buzon: los registros SOLO de byte en byte, los datos por palabras (nada mas toca esas direcciones) ----------------------- */
static u8   reg_rd8(u32 off) { DD_TRAZA(0, 1, DD_REG + off); return *(volatile u8 *)(uintptr_t)(DD_REG + off); }
static void reg_wr8(u32 off, u8 v) { DD_TRAZA(1, 1, DD_REG + off); *(volatile u8 *)(uintptr_t)(DD_REG + off) = v; }
static u32  dat_rd32(u32 i) { DD_TRAZA(0, 4, DD_DATOS + 4U * i); return *(volatile u32 *)(uintptr_t)(DD_DATOS + 4U * i); }
static void dat_wr32(u32 i, u32 v) { DD_TRAZA(1, 4, DD_DATOS + 4U * i); *(volatile u32 *)(uintptr_t)(DD_DATOS + 4U * i) = v; }

/* ---- el estado ---------------------------------------------------------------------------------------------------------------------------- */
static u8   dd_nextor;                                     /* dual_disco_compone puso Nextor-B y nadie ha cambiado el cartucho desde entonces */
static u8   dd_duena;                                      /* 0 = A, 1 = B */
static u32  dd_wr_b;                                       /* escrituras buenas de B desde que es la duena (si A recupera la SD, su DOS puede tener datos viejos) */
static u8   dd_aviso_a;                                    /* A ha ganado la SD despues de que B escribiera: avisar una vez */
static u32  dd_rg_lo[DD_MAX_RG], dd_rg_n[DD_MAX_RG];       /* A escribe dentro de [lo, lo+n) aunque no sea la duena */
static u8   dd_rg_k;
static u32  dd_ns;                                         /* sectores de la TF2 cuando se compuso Nextor-B (B los tiene en su area de trabajo) */
static u8   dd_tarjeta_nueva;                              /* la tarjeta se ha retirado o cambiado desde que se compuso: B ya no puede fiarse de lo que sabe */
static u8   dd_usado;                                      /* B ha usado el buzon alguna vez desde que se compuso... */
static u64  dd_t_uso;                                      /* ... y la ultima fue en este gt_now() */
static u32  dd_n_rech_a;                                   /* escrituras de A rechazadas (A no era la duena) */
static u32  dd_n_lee_b, dd_n_esc_b, dd_n_prot_b, dd_n_err_b;
static u32  dd_buf[128] __attribute__((aligned(32)));      /* el sector en curso (512 B): la SD lee y escribe aqui (DMA, memoria sin cache) */
static u8   dd_rom[NEXTOR_B_ROM_LEN] __attribute__((aligned(32)));   /* Nextor-B descomprimido, tal como va al cartucho */
static mz_work dd_zw;

void dual_disco_init(void)
{
    dd_nextor = 0; dd_duena = 0; dd_wr_b = 0; dd_aviso_a = 0; dd_rg_k = 0; dd_ns = 0; dd_tarjeta_nueva = 0;
    dd_usado = 0; dd_t_uso = 0;
    dd_n_rech_a = 0; dd_n_lee_b = 0; dd_n_esc_b = 0; dd_n_prot_b = 0; dd_n_err_b = 0;
}

int dual_disco_duena(void) { return dd_duena; }

/* B tiene Nextor-B: la marca, el cartucho y el mapper de B_CTL y la firma de la DDR (el cartucho lo puede cambiar xsdb o un juego de Shift+D) */
int dual_disco_nextor_b(void)
{
    if (!dd_nextor || !dual_activo()) return 0;
    if ((dual_b_ctl() & DD_CTL_MASCARA) != DD_CTL_NEXTOR) return 0;
    return reg_rd8(R_SIG) == 'N' && reg_rd8(R_SIG + 1U) == 'X' && reg_rd8(R_SIG + 2U) == 'T' && reg_rd8(R_SIG + 3U) == 'B';
}

/* ... y corre: parada con P (o con xsdb) no atiende el buzon ni puede tener la SD */
int dual_disco_b_corre(void) { return (dual_b_ctl() & DD_CTL_CORRE) && dual_disco_nextor_b(); }

void dual_disco_quita_nextor_b(void)
{
    dd_nextor = 0;                                         /* antes de nada: asi dual_disco_pon_duena no escribe en un cartucho que ya no es suyo */
    dd_usado = 0;
    dual_disco_pon_duena(0);
}

/* OWN al buzon (informativo: el driver de B no lo lee; se ve con xsdb) */
static void dd_publica(void)
{
    if (!dual_disco_nextor_b()) return;
    reg_wr8(R_OWN, dd_duena);
    DD_DSB();
}

void dual_disco_pon_duena(int quien)
{
    quien = quien ? 1 : 0;
    if (quien == dd_duena) return;
    dd_duena = (u8)quien;
    if (quien) dd_wr_b = 0;                                /* empieza el turno de B */
    else {
        if (dd_wr_b) dd_aviso_a = 1;                       /* B ha escrito mientras la tenia: lo que A tenga en sus bufer de Nextor puede ser viejo */
        dd_rg_k = 0;                                       /* A es la duena: ya no hace falta la excepcion */
    }
    dd_publica();
    log_str("dual: la SD es de "); log_str(quien ? "B" : "A"); log_str("\n");
}

int dual_disco_toma_aviso_a(void) { int r = dd_aviso_a; dd_aviso_a = 0; return r; }

/* ---- componer Nextor-B en el cartucho de B ---------------------------------------------------------------------------------------------- */
int dual_disco_compone(void)
{
    static const dual_plan_t pl = { 0, 0, 2, 0, DM_PEDIDA };      /* la ROM desde el principio, mapper 2 (Konami SCC), sin lineal */
    u32 n = 0, ns = sd_sectores();
    int r = mx_zlib(nextor_b_rom_z, NEXTOR_B_ROM_ZLEN, dd_rom, sizeof dd_rom, &n, &dd_zw);
    if (r != MZ_OK || n != NEXTOR_B_ROM_LEN) {
        log_str("dual: Nextor-B no se descomprime ("); log_dec((u32)(0 - r)); log_str(")\n");
        return 0;                                          /* B ni se ha tocado */
    }
    dd_rom[DD_OFF_REG + R_CMD] = 0;                        /* los registros del buzon van en la imagen: se escriben con B parada, antes de soltarla */
    dd_rom[DD_OFF_REG + R_STATUS] = 0;
    dd_rom[DD_OFF_REG + R_CTYPE] = sd_presente() ? 3U : 0U;
    dd_rom[DD_OFF_REG + R_SIG] = 'N'; dd_rom[DD_OFF_REG + R_SIG + 1U] = 'X'; dd_rom[DD_OFF_REG + R_SIG + 2U] = 'T'; dd_rom[DD_OFF_REG + R_SIG + 3U] = 'B';
    dd_rom[DD_OFF_REG + R_NSEC] = (u8)ns; dd_rom[DD_OFF_REG + R_NSEC + 1U] = (u8)(ns >> 8);
    dd_rom[DD_OFF_REG + R_NSEC + 2U] = (u8)(ns >> 16); dd_rom[DD_OFF_REG + R_NSEC + 3U] = (u8)(ns >> 24);
    dd_rom[DD_OFF_REG + R_SEQ] = 0; dd_rom[DD_OFF_REG + R_ACK] = 0;
    dd_rom[DD_OFF_REG + R_OWN] = dd_duena;
    dd_nextor = 0;                                         /* mientras se compone, el buzon no existe */
    dual_aplica((const volatile u32 *)(const void *)dd_rom, NEXTOR_B_ROM_LEN, &pl);   /* parar B, escribir, declarar el cartucho y soltar */
    dd_nextor = 1; dd_usado = 0; dd_ns = ns; dd_tarjeta_nueva = 0;
    log_str("dual: Nextor-B en B (MSX-DOS), "); log_dec(ns); log_str(" sectores\n");
    return 1;
}

/* la tarjeta de TF2 se ha retirado o se ha puesto otra (main.c): lo que Nextor-B sabe de ella ya no vale */
void dual_disco_tarjeta_cambio(void)
{
    if (dd_nextor && !dd_tarjeta_nueva) { dd_tarjeta_nueva = 1; log_str("dual: tarjeta de TF2 cambiada: Nextor-B sin tarjeta hasta recomponerlo\n"); }
}
int dual_disco_tarjeta_nueva(void) { return dd_nextor && dd_tarjeta_nueva; }

/* ---- el buzon ---------------------------------------------------------------------------------------------------------------------------- */
static u8 dd_atiende(u32 cmd, u32 lba)                    /* devuelve el STATUS final */
{
    u32 i, ns = sd_sectores();
    if (dd_tarjeta_nueva || (ns != dd_ns && dd_ns)) return ST_SINTARJ;     /* la tarjeta ya no es la que B conoce: ni leer ni, sobre todo, escribir */
    if (cmd == 1U) {                                       /* leer */
        if (!sd_presente()) return ST_SINTARJ;
        if (lba >= ns) return ST_IO;
        if (!sd_read(lba, 1U, (u8 *)dd_buf)) { dd_n_err_b++; return ST_IO; }
        for (i = 0; i < 128U; i++) dat_wr32(i, dd_buf[i]);
        dd_n_lee_b++;
        return 0;
    }
    if (cmd == 2U) {                                       /* escribir */
        if (!dd_duena) { dd_n_prot_b++; return ST_PROT; }  /* la SD no se toca */
        if (!sd_presente()) return ST_SINTARJ;
        if (lba >= ns) return ST_IO;
        for (i = 0; i < 128U; i++) dd_buf[i] = dat_rd32(i);
        if (!sd_write(lba, 1U, (const u8 *)dd_buf)) { dd_n_err_b++; return ST_IO; }
        dd_n_esc_b++; dd_wr_b++;
        return 0;
    }
    return ST_IO;                                          /* orden que no existe */
}

void dual_disco_poll(void)
{
    u32 cmd, lba;
    u8 st, seq;
    if (!dd_nextor) return;
    cmd = reg_rd8(R_CMD);
    if (!cmd || !dual_disco_nextor_b()) return;
    seq = reg_rd8(R_SEQ);
    lba = (u32)reg_rd8(R_SADDR) | ((u32)reg_rd8(R_SADDR + 1U) << 8) | ((u32)reg_rd8(R_SADDR + 2U) << 16) | ((u32)reg_rd8(R_SADDR + 3U) << 24);
    reg_wr8(R_CMD, 0);                                     /* recogida: el Z80 ya puede preparar la siguiente (espera a STATUS) */
    st = dd_atiende(cmd, lba);
    DD_DSB();
    if (cmd == 1U && !st) (void)dat_rd32(127U);            /* releer la ultima palabra escrita: cuando vuelve, las anteriores tambien han llegado */
    reg_wr8(R_ACK, seq);                                   /* de que orden es esta respuesta: ANTES de STATUS */
    reg_wr8(R_STATUS, st);                                 /* LO ULTIMO: el Z80 sondea esto */
    DD_DSB();
    dd_usado = 1; dd_t_uso = gt_now();
}

int dual_disco_activo(void)
{
    return dd_usado && gt_now() - dd_t_uso < (u64)(COUNTS_PER_SECOND / 1000U) * DD_ACTIVO_MS;
}

/* ---- A: lo que pregunta sd_servir -------------------------------------------------------------------------------------------------------- */
static int dd_en_rango(u32 sec, u32 cnt)                  /* [sec, sec+cnt) cae entero dentro de uno de los rangos [lo, lo+n) */
{
    int i;
    for (i = 0; i < dd_rg_k; i++)
        if (cnt <= dd_rg_n[i] && sec >= dd_rg_lo[i] && (u64)sec + cnt <= (u64)dd_rg_lo[i] + dd_rg_n[i]) return 1;
    return 0;
}

void dual_disco_rangos_a(const u32 *lo, const u32 *n, int k)
{
    int i;
    dd_rg_k = 0;
    for (i = 0; i < k && i < DD_MAX_RG; i++) if (n[i]) { dd_rg_lo[dd_rg_k] = lo[i]; dd_rg_n[dd_rg_k] = n[i]; dd_rg_k++; }
}

int dual_disco_a_puede_escribir(u32 sec, u32 cnt)
{
    if (!dual_activo() || !dd_duena) return 1;             /* sin el Dual, o A es la duena: como siempre */
    return dd_en_rango(sec, cnt);
}

void dual_disco_a_rechazo(u32 sec, u32 cnt)
{
    if (!dd_n_rech_a++) {                                  /* solo la primera vez: el motivo exacto lo pregunta el driver de A con el bloque de estado */
        log_str("dual: A escribe en la SD y la duena es B: se rechaza (sector "); log_hex(sec); log_str(", "); log_dec(cnt); log_str(")\n");
    }
}

int dual_disco_a_estado(u32 sec, u8 *bloque)
{
    volatile u32 *w = (volatile u32 *)(void *)bloque;      /* SDBUF: memoria sin cache, alineada a 4 */
    u32 i;
    if (sec != DD_LBA_ESTADO || !dual_activo()) return 0;
    for (i = 0; i < 128U; i++) w[i] = 0U;
    w[0] = 0x4C415544U;                                    /* 'D' 'U' 'A' 'L' */
    w[1] = 2U | ((u32)dd_duena << 8) | ((u32)dd_duena << 16);   /* +4 version, +5 duena, +6 A solo lee */
    DD_DSB();
    return 1;
}
