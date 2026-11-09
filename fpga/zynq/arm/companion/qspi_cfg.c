/* qspi_cfg.c — config persistente del MSXimus en la QSPI de la ZYNQ MINI (16/09/2026).
 *
 * En el Tang el menu graba el bloque de config en la flash SPI y el stream de arranque lo siembra;
 * en la Zynq el PL no tiene flash, asi que lo hace el companion:
 *   cfg_load(): al arrancar lee el bloque del ultimo sector de 4 KB de la QSPI (0xFFF000) y, si es
 *               valido, lo pone en MBOX+0x1C bits [28:8] con valid=1; el PL siembra los registros
 *               mientras el MSX sigue en reset. Hay que llamarla ANTES de poner MSX_RUN.
 *   cfg_poll(): en el bucle principal vigila MBOX+0x70 (bloque vigente + toggle en el bit 31, que el
 *               PL cambia cuando el menu pulsa "guardar" = puerto #42 bit 6) y graba el sector.
 * Bloque en flash (16 bytes): "MSXC", config1, config2, turbo(0/1), gain(0..7), suma xor de esos 4
 * con 0x5A, y relleno 0xFF. Driver: xqspips en modo IO (transferencias sondeadas, CS forzado),
 * ordenes clasicas de 3 bytes de direccion del W25Q128: 06 WREN, 05 RDSR, 03 READ, 20 SE 4K, 02 PP.
 * V3.7 (17/09): bytes [9..12] = niveles del mezclador (7 canales x 4 bits, little-endian, top.v mix_lvl)
 * y [13] = xor de esos 4 con 0xA5. Un bloque viejo (0xFF ahi) no pasa esa suma -> el PL se queda con
 * sus defectos (8/8). Al arrancar los niveles van a MBOX+0x24 con valid=1 (mismas reglas que +0x1C);
 * al guardar se leen de MBOX+0xC0 cuando su toggle (bit 31) coincide con el de +0x70.
 * 31/10/2026 (perfiles): bytes [16..23] = id del "perfil al arrancar" (ASCII, relleno de 0; todo a 0 = ninguno) y [24] = xor de
 * esos 8 con 0x6B; un bloque viejo (0xFF ahi) no pasa la suma = ninguno. Lo lee main.c al arrancar (cfg_perfil_arranque) para
 * cargar ese perfil de la TF1 antes de soltar el MSX y lo fija la pagina Perfiles (cfg_perfil_fija). Las tres rutinas que
 * graban el sector (cfg_poll, cfg_video43_cambia, cfg_perfil_fija) escriben los 32 primeros bytes: el sector se borra entero.
 * 30/09/2026: tambien es el dueno de la QSPI para la actualizacion por red (ota.c): qspi_open/qspi_read/
 * qspi_busy/qspi_erase64k_start/qspi_erase4k_start/qspi_prog_start al final. Las ordenes "_start" no esperan
 * (el borrado de 64 KB tarda hasta 2 s): ota.c mira qspi_busy() en cada vuelta del bucle. Por eso q_erase4k y
 * q_prog esperan ANTES de mandar nada: si cfg_poll llega con la flash ocupada por ota.c, su WREN se perderia.
 */
#include "xqspips.h"
#include "xparameters.h"
#include "sleep.h"

#define CFG_FLASH_ADDR   0xFFF000U          /* ultimo sector de 4 KB de los 16 MB */
#define MBOX_CTRL        (*(volatile u32 *)0x1FF0001CU)
#define MBOX_MIX_IN      (*(volatile u32 *)0x1FF00024U)     /* {valid[31], niveles[27:0]} -> siembra del PL */
#define MBOX_CFG_TEL     (*(volatile u32 *)0x1FF00070U)
#define MBOX_MIX_TEL     (*(volatile u32 *)0x1FF000C0U)     /* {toggle[31], niveles[27:0]} al pulsar "guardar" */
#define MIX_DEFAULT      0x08888888U                        /* 8/8 = x1 en los 7 canales */

extern void log_str(const char *s);
extern void log_hex(u32 v);

static XQspiPs q;
static int q_ok = 0;
static u32 last_tog = 0xFFFFFFFFU;       /* toggle visto (0xFFFFFFFF = aun no sincronizado) */

static int q_init(void)
{
    XQspiPs_Config *c = XQspiPs_LookupConfig(XPAR_XQSPIPS_0_DEVICE_ID);
    if (!c) return 0;
    if (XQspiPs_CfgInitialize(&q, c, c->BaseAddress) != XST_SUCCESS) return 0;
    XQspiPs_SetOptions(&q, XQSPIPS_MANUAL_START_OPTION | XQSPIPS_FORCE_SSELECT_OPTION | XQSPIPS_HOLD_B_DRIVE_OPTION);
    XQspiPs_SetClkPrescaler(&q, XQSPIPS_CLK_PRESCALE_8);   /* 200 / 8 = 25 MHz */
    return 1;
}

static void q_wren(void)
{
    u8 c[1] = { 0x06 };
    XQspiPs_PolledTransfer(&q, c, NULL, 1);
}

static void q_wait(void)
{
    u8 c[2] = { 0x05, 0x00 }, r[2];
    u32 n = 0;
    do {
        XQspiPs_PolledTransfer(&q, c, r, 2);
        if (++n > 2000000U) break;                 /* nunca colgarse por la flash */
    } while (r[1] & 0x01);
}

static void q_read(u32 addr, u8 *d, u32 n)        /* n <= 64 */
{
    u8 b[4 + 64];
    u32 i;
    q_wait();                                        /* con la flash borrando o programando (la actualizacion) una lectura devuelve FF: un bloque "sin MSXC" */
    b[0] = 0x03; b[1] = (u8)(addr >> 16); b[2] = (u8)(addr >> 8); b[3] = (u8)addr;
    XQspiPs_PolledTransfer(&q, b, b, 4 + n);
    for (i = 0; i < n; i++) d[i] = b[4 + i];
}

static void q_erase4k(u32 addr)
{
    u8 b[4];
    q_wait();
    q_wren();
    b[0] = 0x20; b[1] = (u8)(addr >> 16); b[2] = (u8)(addr >> 8); b[3] = (u8)addr;
    XQspiPs_PolledTransfer(&q, b, NULL, 4);
    q_wait();
}

static void q_prog(u32 addr, const u8 *d, u32 n)  /* n <= 64, dentro de una pagina */
{
    u8 b[4 + 64];
    u32 i;
    q_wait();
    q_wren();
    b[0] = 0x02; b[1] = (u8)(addr >> 16); b[2] = (u8)(addr >> 8); b[3] = (u8)addr;
    for (i = 0; i < n; i++) b[4 + i] = d[i];
    XQspiPs_PolledTransfer(&q, b, NULL, 4 + n);
    q_wait();
}

int qspi_open(void)                                  /* idempotente: ota_arranque() llega antes que cfg_load() */
{
    if (!q_ok) q_ok = q_init();
    return q_ok;
}

static u8 cfg_sum(const u8 *b) { return (u8)(b[4] ^ b[5] ^ b[6] ^ b[7] ^ 0x5A); }
#define CFG_LEN 32U                                  /* bytes que se leen y se graban del sector de ajustes */
static char perfil_boot[9];                          /* "" = ninguno */
static u8 perfil_sum(const u8 *b) { u8 s = 0x6B; u32 i; for (i = 16; i < 24U; i++) s ^= b[i]; return s; }
static int id_valido(const char *id)
{
    u32 i;
    if (!id[0]) return 0;
    for (i = 0; i < 8U && id[i]; i++)
        if (!((id[i] >= 'A' && id[i] <= 'Z') || (id[i] >= '0' && id[i] <= '9') || id[i] == '_' || id[i] == '-')) return 0;
    return id[i] == 0;
}
static void perfil_a_bytes(u8 *b)                    /* [16..31] del bloque que se graba */
{
    u32 i;
    for (i = 16; i < CFG_LEN; i++) b[i] = 0xFF;
    for (i = 0; i < 8U; i++) b[16 + i] = (u8)perfil_boot[i];   /* perfil_boot tiene 9 bytes y 0 al final: sobran ceros */
    b[24] = perfil_sum(b);
}
/* rama beta (30/10/2026): [14] = opciones de video (bit 0: el V9968 a pantalla completa en 4:3 con Scale3x), [15] = [14]
 * xor 0x3C. Un bloque viejo lleva 0xFF, 0xFF ahi: no cuadra y queda 16:9. Va al PL en MBOX+0x2C bit 4 (top_zynq.v). */
#define MBOX_VID         (*(volatile u32 *)0x1FF0002CU)
static u8 vid_flags;
static void vid_aplica(void) { MBOX_VID = (MBOX_VID & ~0x10U) | ((vid_flags & 1U) ? 0x10U : 0U); __asm__ volatile ("dsb" ::: "memory"); }
int cfg_video43(void) { return vid_flags & 1U; }
static u8 mix_sum(const u8 *b) { return (u8)(b[9] ^ b[10] ^ b[11] ^ b[12] ^ 0xA5); }

/* bits [28:8] del control: {valid[28], gain[27:25], turbo[24], config2[23:16], config1[15:8]} */
int cfg_load(u32 *cfgbits)
{
    u8 b[CFG_LEN];
    u32 i;
    if (!qspi_open()) { log_str("cfg: QSPI no inicializa\n"); return 0; }
    q_read(CFG_FLASH_ADDR, b, CFG_LEN);
    vid_flags = (b[0] == 'M' && b[1] == 'S' && b[2] == 'X' && b[3] == 'C' && b[15] == (u8)(b[14] ^ 0x3C)) ? b[14] : 0U;
    vid_aplica();
    for (i = 0; i < 9U; i++) perfil_boot[i] = 0;
    if (b[0] == 'M' && b[1] == 'S' && b[2] == 'X' && b[3] == 'C' && b[24] == perfil_sum(b)) {
        for (i = 0; i < 8U; i++) perfil_boot[i] = (char)b[16 + i];
        if (!id_valido(perfil_boot)) for (i = 0; i < 9U; i++) perfil_boot[i] = 0;
        else { log_str("cfg: perfil al arrancar "); log_str(perfil_boot); log_str("\n"); }
    }
    if (vid_flags & 1U) log_str("cfg: V9968 a pantalla completa en 4:3 con Scale3x\n");
    if (b[0] != 'M' || b[1] != 'S' || b[2] != 'X' || b[3] != 'C' || b[8] != cfg_sum(b) || b[4] == 0U) {
        /* config1 = 0 no es una config real (mapper y megaram van siempre a 1): bloque fantasma -> defectos */
        log_str("cfg: sin bloque valido en la QSPI (defectos)\n");
        return 0;
    }
    *cfgbits = ((u32)b[4] << 8) | ((u32)b[5] << 16) | (((u32)b[6] & 1U) << 24) | (((u32)b[7] & 7U) << 25) | (1U << 28);
    log_str("cfg: QSPI config1="); log_hex(b[4]); log_str(" config2="); log_hex(b[5]);
    log_str(" turbo="); log_hex(b[6]); log_str(" gain="); log_hex(b[7]);
    {   /* V3.7: niveles del mezclador (bloque v2); sin ellos, defectos explicitos */
        u32 mix = MIX_DEFAULT;
        if (b[13] == mix_sum(b))
            mix = ((u32)b[9] | ((u32)b[10] << 8) | ((u32)b[11] << 16) | ((u32)b[12] << 24)) & 0x0FFFFFFFU;
        MBOX_MIX_IN = 0x80000000U | mix;
        log_str(" mix="); log_hex(mix);
    }
    log_str("\n");
    return 1;
}

void cfg_poll(void)
{
    u32 t = MBOX_CFG_TEL;
    u32 m;
    u8 b[CFG_LEN];
    u32 i;
    if (last_tog == 0xFFFFFFFFU) { last_tog = t & 0x80000000U; return; }   /* primera vez: solo sincronizar */
    if ((t & 0x80000000U) == last_tog) return;
    /* V3.7: el PL escribe +0x70 y despues +0xC0 en la misma ronda (~1 ms): esperar a que el toggle del
     * mezclador coincida para no leer los niveles de la ronda anterior. Con un PL sin la palabra
     * (+0xC0 siempre 0) se sale por el tope y los niveles 0 = "sin dato" -> defectos. */
    for (i = 0; i < 200U; i++) { m = MBOX_MIX_TEL; if ((m & 0x80000000U) == (t & 0x80000000U)) break; usleep(100); }
    last_tog = t & 0x80000000U;
    if (!q_ok) return;
    /* 17/09: un PL recien (re)configurado escribe +0x70 = 0 (toggle 0, bloque sin latchear); si el companion habia
     * sincronizado el toggle con el PL anterior (arranque por JTAG), veia un "guardar" y grababa CEROS en la QSPI
     * (menu apagado, ganancia x1, slots a 0). config1 = 0 no es una config real: se ignora. */
    if ((t & 0xFFU) == 0U) { log_str("cfg: toggle sin bloque (config1=0): ignorado\n"); return; }
    m &= 0x0FFFFFFFU;
    if (m == 0U) m = MIX_DEFAULT;
    b[0] = 'M'; b[1] = 'S'; b[2] = 'X'; b[3] = 'C';
    b[4] = (u8)(t & 0xFFU); b[5] = (u8)((t >> 8) & 0xFFU); b[6] = (u8)((t >> 16) & 1U); b[7] = (u8)((t >> 17) & 7U);
    b[8] = cfg_sum(b);
    b[9] = (u8)(m & 0xFFU); b[10] = (u8)((m >> 8) & 0xFFU); b[11] = (u8)((m >> 16) & 0xFFU); b[12] = (u8)((m >> 24) & 0xFFU);
    b[13] = mix_sum(b);
    b[14] = vid_flags; b[15] = (u8)(vid_flags ^ 0x3C);   /* rama beta: las opciones de video se conservan */
    perfil_a_bytes(b);                                   /* y el perfil al arrancar */
    q_erase4k(CFG_FLASH_ADDR);
    q_prog(CFG_FLASH_ADDR, b, CFG_LEN);
    log_str("cfg: guardado en la QSPI config1="); log_hex(b[4]); log_str(" config2="); log_hex(b[5]);
    log_str(" turbo="); log_hex(b[6]); log_str(" gain="); log_hex(b[7]); log_str(" mix="); log_hex(m); log_str("\n");
}

/* profile.c (PCAP, 30/10): el PL recien cargado trae otro toggle de "guardar"; la proxima vuelta de cfg_poll solo sincroniza */
void cfg_resync(void) { last_tog = 0xFFFFFFFFU; }

/* rama beta: F12 -> V. Cambia el modo, lo aplica y lo guarda en el bloque (si no hay bloque valido, uno con config1 = 0
 * que cfg_load ignora para la config pero del que si lee [14]) */
void cfg_video43_cambia(void)
{
    u8 b[CFG_LEN];
    u32 i;
    vid_flags ^= 1U;
    vid_aplica();
    log_str(vid_flags & 1U ? "cfg: V9968 en 4:3 con Scale3x\n" : "cfg: V9968 en 16:9\n");
    if (!q_ok) return;
    q_read(CFG_FLASH_ADDR, b, CFG_LEN);
    if (b[0] != 'M' || b[1] != 'S' || b[2] != 'X' || b[3] != 'C') {
        for (i = 0; i < CFG_LEN; i++) b[i] = 0xFF;
        b[0] = 'M'; b[1] = 'S'; b[2] = 'X'; b[3] = 'C'; b[4] = 0;
    }
    b[14] = vid_flags; b[15] = (u8)(vid_flags ^ 0x3C);
    perfil_a_bytes(b);
    q_erase4k(CFG_FLASH_ADDR);
    q_prog(CFG_FLASH_ADDR, b, CFG_LEN);
}

/* perfil al arrancar (31/10/2026): main.c lo pide antes de soltar el MSX; perfiles.c (tecla A) lo cambia */
int cfg_perfil_arranque(char id[9])
{
    u32 i;
    for (i = 0; i < 9U; i++) id[i] = perfil_boot[i];
    return perfil_boot[0] != 0;
}

int cfg_perfil_fija(const char *id)                  /* 0 o "" = ninguno. 1 = grabado y releido */
{
    u8 b[CFG_LEN], c[CFG_LEN];
    u32 i;
    char antes[9];
    for (i = 0; i < 9U; i++) antes[i] = perfil_boot[i];
    if (id && id[0] && !id_valido(id)) return 0;
    for (i = 0; i < 9U; i++) perfil_boot[i] = 0;
    if (id) for (i = 0; i < 8U && id[i]; i++) perfil_boot[i] = id[i];
    if (!q_ok) { for (i = 0; i < 9U; i++) perfil_boot[i] = antes[i]; return 0; }
    q_read(CFG_FLASH_ADDR, b, CFG_LEN);
    if (b[0] != 'M' || b[1] != 'S' || b[2] != 'X' || b[3] != 'C') {      /* sin bloque: uno con config1 = 0 (cfg_load lo ignora para la config) */
        for (i = 0; i < CFG_LEN; i++) b[i] = 0xFF;
        b[0] = 'M'; b[1] = 'S'; b[2] = 'X'; b[3] = 'C'; b[4] = 0;
        b[14] = vid_flags; b[15] = (u8)(vid_flags ^ 0x3C);
    }
    perfil_a_bytes(b);
    q_erase4k(CFG_FLASH_ADDR);
    q_prog(CFG_FLASH_ADDR, b, CFG_LEN);
    q_read(CFG_FLASH_ADDR, c, CFG_LEN);
    for (i = 0; i < CFG_LEN; i++) if (c[i] != b[i]) { log_str("cfg: perfil al arrancar: la QSPI no ha guardado el ajuste\n"); return 0; }
    log_str("cfg: perfil al arrancar "); log_str(perfil_boot[0] ? perfil_boot : "ninguno"); log_str("\n");
    return 1;
}

/* ---- 30/09/2026: acceso general para la actualizacion por red (ota.c) ------------------------------------- */
static u8 qb[4 + 1024];                              /* orden + datos de una transferencia */

void qspi_read(u32 addr, u8 *d, u32 n)               /* cualquier n, en trozos de 1 KB */
{
    while (n) {
        u32 k = n > 1024U ? 1024U : n, i;
        q_wait();
        qb[0] = 0x03; qb[1] = (u8)(addr >> 16); qb[2] = (u8)(addr >> 8); qb[3] = (u8)addr;
        XQspiPs_PolledTransfer(&q, qb, qb, 4 + k);
        for (i = 0; i < k; i++) d[i] = qb[4 + i];
        addr += k; d += k; n -= k;
    }
}

int qspi_busy(void)                                  /* 1 = borrando o programando (RDSR bit 0) */
{
    u8 c[2] = { 0x05, 0x00 }, r[2];
    XQspiPs_PolledTransfer(&q, c, r, 2);
    return r[1] & 0x01;
}

static void q_cmd_addr(u8 op, u32 addr)
{
    u8 b[4];
    q_wait();
    q_wren();
    b[0] = op; b[1] = (u8)(addr >> 16); b[2] = (u8)(addr >> 8); b[3] = (u8)addr;
    XQspiPs_PolledTransfer(&q, b, NULL, 4);
}

void qspi_erase64k_start(u32 addr) { q_cmd_addr(0xD8, addr); }   /* bloque de 64 KB (addr alineada) */
void qspi_erase4k_start(u32 addr)  { q_cmd_addr(0x20, addr); }   /* sector de 4 KB */

void qspi_prog_start(u32 addr, const u8 *d, u32 n)   /* n <= 256 y sin cruzar la pagina de 256 B */
{
    u32 i;
    if (n > 256U) n = 256U;
    q_wait();
    q_wren();
    qb[0] = 0x02; qb[1] = (u8)(addr >> 16); qb[2] = (u8)(addr >> 8); qb[3] = (u8)addr;
    for (i = 0; i < n; i++) qb[4 + i] = d[i];
    XQspiPs_PolledTransfer(&q, qb, NULL, 4 + n);
}

void qspi_wait(void) { q_wait(); }
