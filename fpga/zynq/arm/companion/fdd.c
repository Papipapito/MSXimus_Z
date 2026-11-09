/* fdd.c — DISQUETERA del MSXimus Z: abstraccion de disquete sobre tres backends, cache del disquete
 * en la DDR y su publicacion en el SDBOX. Ver fdd.h (ventana magica) y ufi_host.c (transporte USB).
 *
 * Backends (bits [7:4] de FDD_STAT):
 *   1 UFI/CBI  disquetera USB clasica (TEAC/Y-E Data/NEC/Mitsumi: clase 08, subclase 04/05, CBI o CB)
 *   2 UFI/BOT  disquetera con Bulk-Only (subclase 04/05/06 + protocolo 50) servida por ufi_host.c
 *   3 MSC      subclase 06 + BOT servida por el msc_host de TinyUSB (solo si UFI_CLAIM_SCSI_BOT = 0);
 *              lo que tenga > 2880 bloques o bloques != 512 B (pendrives) se IGNORA: nunca se le escribe
 *   4 falso    imagen de disquete en la DDR que deja boot.tcl (FDD_IMG=fichero.dsk) para probar la
 *              ventana, el menu y Nextor sin hardware: 'FDD1' en SDBOX+0x8C, base en +0x90, sectores en +0x94
 * Manda la unidad USB si hay una montada; si no, el falso; si no, nada.
 *
 * CACHE (22/09): el PL corta cada peticion a los 2,0 s (ACK_TIMEOUT de sd_axi_proxy.v) y Nextor en modo
 *   DOS 1 pide hasta 255 sectores en una sola orden (un BLOAD de 32 KB = 64 sectores): a 30-60 KB/s mas
 *   arranque del motor, una disquetera real NO cabe en ese plazo. Por eso el disquete entero vive en una
 *   copia en la DDR (FDD_CACHE_BASE, 1,44 MB) que se llena en segundo plano desde fdd_poll() por tramos de
 *   16 sectores en cuanto hay medio (720 KB en ~20 s, con teclado y mandos vivos). Una lectura del MSX
 *   se sirve de la cache; si un tramo aun no esta, se lee del disco EN ESE MOMENTO con el plazo de la
 *   peticion (1,5 s: un tramo son ~0,3 s) y se deja cacheado: si no da tiempo, el MSX ve "timeout",
 *   reintenta, y el segundo intento ya lo encuentra. Las escrituras van a la cache y se acusan al
 *   instante (write-back); fdd_poll las vuelca al disco por tramos de sectores sucios ANTES de seguir
 *   con el prefetch (ventana de perdida = segundos, como el "no saques el disco con la luz encendida").
 *   Al retirar el disco se pierde la cache (y lo sucio, con aviso en el log).
 *
 * Ordenes (UFI = SCSI reducido, siempre 12 B; en subclase 06 se usan las longitudes naturales):
 *   INQUIRY (12h) al montar (tipo 0 = disco directo; si no, se ignora la unidad), TEST UNIT READY (00h) cada
 *   ~1 s desde fdd_poll para detectar el medio, REQUEST SENSE (03h) tras cada CHECK CONDITION,
 *   READ FORMAT CAPACITIES (23h) y READ CAPACITY(10) (25h) para los sectores del medio, MODE SENSE(10)
 *   (5Ah, pagina 3Fh/05h) o MODE SENSE(6) (1Ah) para el bit de proteccion, START STOP UNIT (1Bh) si la
 *   unidad pide "initializing command required" (04/02), READ(10) (28h) y WRITE(10) (2Ah) por tramos.
 * Sense: 3A = sin disco -> presente 0; 28/29 (unit attention: cambio de disco o reset) -> presente 0 y el
 *   sondeo siguiente relee capacidad y proteccion; 04/01 = arrancando -> espera corta y reintento;
 *   27 = protegido; 3x/1x = error de medio -> un reintento. Bits [15:8] de FDD_STAT = ASC del ultimo fallo.
 *
 * Tiempos: una peticion del PL tiene un PLAZO unico de 1,5 s (fd.deadline) que heredan todas las ordenes
 *   que cuelgan de ella (READ/WRITE, REQUEST SENSE); el sondeo (TUR/INQUIRY) usa plazos cortos (300 ms) y
 *   el prefetch se corta solo si el PL pide un sector de la SD (ufi_set_cancel). Un timeout o un fallo de
 *   transporte NO hace el reset recovery en linea (hasta 650 ms): lo apunta (need_reset) y lo ejecuta
 *   fdd_poll cuando no hay peticion. Tres fallos de transporte seguidos en el sondeo = unidad ignorada
 *   hasta reenchufarla. TODO se hace desde el bucle principal: las callbacks de TinyUSB (fdd_*_mount/
 *   umount) solo toman nota (dentro de tuh_task_ext no se puede esperar: reentrada). Sin malloc; buffers
 *   alineados a 32 B y en la DDR.                                                                         */
#include "xil_types.h"
#include "fdd.h"
#include "ufi_host.h"
#include "class/msc/msc.h"          /* MSC_SUBCLASS_* (con CFG_TUH_MSC=0 tusb.h no lo incluye) */
#include "log.h"

#define SDBOX          0x1FF00100U
enum { W_REQ_SEQ = 2, W_REQ_SEC = 4, W_ACK_SEQ = 6,
       W_FDD_STAT = 32, W_FDD_CNT = 33, W_FDD_ERR = 34, W_FDD_FAKE = 35, W_FDD_FAKE_BASE = 36, W_FDD_FAKE_SECS = 37 };
#define FDD_FAKE_MAGIC 0x31444446U          /* 'FDD1' */
#define FDD_CACHE_BASE 0x1F200000U          /* 1,44 MB: 0x1F200000..0x1F367FFF (el falso de boot.tcl va en 0x1F000000) */
#define FDD_DSB()      __asm__ volatile ("dsb" ::: "memory")

enum { BE_NONE = 0, BE_UFI_CBI = 1, BE_UFI_BOT = 2, BE_MSC = 3, BE_FAKE = 4 };

#define T_REQ_MS       1500U                /* plazo de una peticion del PL (ACK_TIMEOUT = 2,0 s; 0,5 s de margen) */
#define T_CMD_MS       1500U                /* plazo de una orden larga (capacidad, START UNIT, READ/WRITE) */
#define T_SHORT_MS     300U                 /* plazo de TEST UNIT READY / INQUIRY (una unidad sana contesta en ms) */
#define T_POLL_MS      1000U                /* TEST UNIT READY periodico */
#define T_HOLD_MS      10000U               /* tras un medio ilegible: no volver a sondear la capacidad */
#define CHUNK_SECS     16U                  /* sectores por READ/WRITE(10): 8 KB, un qTD */
#define FAIL_STREAK    3U                   /* fallos de transporte seguidos en el sondeo -> unidad ignorada */
#define FLUSH_TRIES    3U                   /* intentos de volcar un tramo sucio antes de darlo por perdido */

extern void     usb_host_poll(void);
extern uint32_t tusb_time_millis_api(void);

static volatile u32 * const box = (volatile u32 *)SDBOX;

static struct {
    u8  backend;
    u8  daddr;                /* unidad USB (backends 1..3); 0 = ninguna */
    u8  ign_daddr;            /* dispositivo USB que no es un disquete (pendrive): no se toca */
    u8  present, wp;
    u8  probe;                /* unidad nueva: INQUIRY + deteccion pendientes (desde el bucle) */
    u8  start_sent;
    u8  need_reset;           /* reset recovery pendiente (se hace en fdd_poll, nunca dentro de una peticion) */
    u8  fails;                /* fallos de transporte seguidos en el sondeo */
    u8  key, asc, ascq;       /* ultimo REQUEST SENSE */
    u32 secs;                 /* sectores del medio */
    u32 fake_base;
    u32 deadline;             /* ms absoluto: plazo de la operacion en curso (0 = sin plazo comun) */
    u32 t_poll, t_hold;
    u32 n_rd, n_wr, n_err, n_mount;
    u32 msc_seq;              /* backend 3: descarta completados de una orden que ya vencio */
    u32 logged;               /* ultimo sense de TEST UNIT READY volcado al log (no repetir cada segundo) */
    /* cache */
    u8  valid[FDD_MAX_SECS / 8];     /* sector en la cache */
    u8  dirty[FDD_MAX_SECS / 8];     /* sector escrito por el MSX y aun no volcado al disco */
    u32 pf_next;              /* proximo sector del prefetch */
    u32 n_dirty;              /* sectores sucios pendientes */
    u8  pf_done;              /* la cache tiene el disquete entero */
    u8  flush_tries;          /* intentos del tramo sucio en curso */
} fd;

static CFG_TUH_MEM_ALIGN u8 fdbuf[64];                     /* INQUIRY 36 / sense 18 / capacidades / mode sense */
static CFG_TUH_MEM_ALIGN u8 pfbuf[CHUNK_SECS * 512U];      /* tramo leido del disco antes de pasar a la cache */

static u32 now_ms(void) { return tusb_time_millis_api(); }
static inline u8 *cache_sec(u32 s) { return (u8 *)(FDD_CACHE_BASE + s * 512U); }
static inline int bit_get(const u8 *m, u32 i) { return (m[i >> 3] >> (i & 7U)) & 1U; }
static inline void bit_set(u8 *m, u32 i) { m[i >> 3] |= (u8)(1U << (i & 7U)); }
static inline void bit_clr(u8 *m, u32 i) { m[i >> 3] &= (u8)~(1U << (i & 7U)); }

static void publish(void)
{
    u32 st = 0;
    if (fd.present) st |= 1U;
    if (fd.wp) st |= 2U;
    if (fd.present && fd.pf_done) st |= 4U;                      /* cache completa */
    if (fd.n_dirty) st |= 8U;                                    /* escrituras pendientes de volcar */
    st |= ((u32)fd.backend & 0xFU) << 4;
    st |= (u32)fd.asc << 8;
    st |= (fd.present ? (fd.secs & 0xFFFFU) : 0U) << 16;
    box[W_FDD_STAT] = st;
    box[W_FDD_CNT]  = (fd.n_rd & 0xFFFFU) | (fd.n_wr << 16);
    box[W_FDD_ERR]  = (fd.n_err & 0xFFFFU) | (fd.n_mount << 16);
    FDD_DSB();
}

static void copy_bytes(u8 *dst, const u8 *src, u32 n)
{
    if ((((u32)(uintptr_t)dst | (u32)(uintptr_t)src | n) & 3U) == 0U) {
        u32 *d = (u32 *)dst; const u32 *s = (const u32 *)src;
        for (n >>= 2; n; n--) *d++ = *s++;
    } else {
        while (n--) *dst++ = *src++;
    }
}

static void cache_reset(const char *why)
{
    if (fd.n_dirty) { log_str("FDD: "); log_dec(fd.n_dirty); log_str(" sectores sin volcar PERDIDOS ("); log_str(why); log_str(")\n"); }
    for (unsigned i = 0; i < sizeof fd.valid; i++) { fd.valid[i] = 0; fd.dirty[i] = 0; }
    fd.pf_next = 0; fd.n_dirty = 0; fd.pf_done = 0; fd.flush_tries = 0;
}

/* ------------------------------------------------------------------ backend 3: msc_host de TinyUSB */
#if CFG_TUH_MSC
static volatile u8 msc_done;
static u8  msc_st;
static u32 msc_residue;
static bool msc_cb(uint8_t daddr, tuh_msc_complete_data_t const *cb)
{
    (void)daddr;
    if (cb->user_arg != (uintptr_t)fd.msc_seq) return true;      /* de una orden que ya vencio */
    msc_st = cb->csw->status; msc_residue = cb->csw->data_residue; msc_done = 1;
    return true;
}
static int msc_cmd(const u8 *cdb, u8 len, int dir_in, u8 *buf, u16 n, u32 timeout, u32 *xferred)
{
    msc_cbw_t cbw;
    u32 t0;
    u8 *p = (u8 *)&cbw;
    for (unsigned i = 0; i < sizeof cbw; i++) p[i] = 0;
    cbw.signature = MSC_CBW_SIGNATURE; cbw.tag = ++fd.msc_seq; cbw.total_bytes = n;
    cbw.dir = dir_in ? 0x80U : 0U; cbw.lun = 0; cbw.cmd_len = len;
    for (u8 i = 0; i < len; i++) cbw.command[i] = cdb[i];
    msc_done = 0;
    if (!tuh_msc_scsi_command(fd.daddr, &cbw, buf, msc_cb, (uintptr_t)fd.msc_seq)) return UFI_BUSY;
    t0 = now_ms();
    while (!msc_done) {
        usb_host_poll();
        if (!tuh_msc_mounted(fd.daddr)) return UFI_GONE;
        if ((u32)(now_ms() - t0) > timeout) return UFI_TIMEOUT;   /* msc_host no expone los endpoints: no se puede abortar */
    }
    if (xferred) *xferred = (msc_residue <= n) ? n - msc_residue : 0U;
    return msc_st == 0U ? UFI_OK : (msc_st == 1U ? UFI_CHECK : UFI_FAIL);
}
#endif

/* ------------------------------------------------------------------ ordenes */
/* Orden USB con el plazo recortado al de la operacion en curso (fd.deadline): si quedan < 100 ms no se
 * lanza nada (UFI_TIMEOUT sin tocar la unidad). */
static int usb_cmd(const u8 *cdb, u8 len, int dir_in, u8 *buf, u16 n, u32 timeout, u32 *xferred)
{
    if (fd.deadline != 0U) {
        u32 left = fd.deadline - now_ms();
        if (left > 0x80000000U || left < 100U) return UFI_TIMEOUT;   /* ya vencido (o negativo) */
        if (timeout > left) timeout = left;
    }
#if CFG_TUH_MSC
    if (fd.backend == BE_MSC) return msc_cmd(cdb, len, dir_in, buf, n, timeout, xferred);
#endif
    return ufi_command(fd.daddr, cdb, len, dir_in, buf, n, timeout, xferred);
}

static void log_sense(const char *what)
{
    log_str("FDD: "); log_str(what); log_str(" sense "); log_hex(((u32)fd.key << 16) | ((u32)fd.asc << 8) | fd.ascq); log_str("\n");
}

static int req_sense(void)                    /* UFI_* de la propia orden; con UFI_OK el sense queda en fd.key/asc/ascq */
{
    static const u8 cdb[6] = { 0x03, 0, 0, 0, 18, 0 };
    u32 n = 0;
    int r;
    for (int i = 0; i < 18; i++) fdbuf[i] = 0;
    r = usb_cmd(cdb, 6, 1, fdbuf, 18, T_SHORT_MS, &n);
    if (r != UFI_OK || n < 14U) {
        fd.key = 0; fd.asc = 0xFF; fd.ascq = 0;                   /* sin sense: "error desconocido" */
        return r == UFI_OK ? UFI_CHECK : r;
    }
    fd.key = fdbuf[2] & 0x0FU; fd.asc = fdbuf[12]; fd.ascq = fdbuf[13];
    return UFI_OK;
}

/* Orden con el manejo comun: 0 = OK; 1 = CHECK CONDITION (sense en fd.*); 2 = transporte roto (reset
 * recovery APUNTADO para fdd_poll y contado); 3 = unidad desconectada. */
static int run(const u8 *cdb, u8 len, int dir_in, u8 *buf, u16 n, u32 timeout, u32 *xferred)
{
    int r;
    if (fd.need_reset && fd.backend != BE_MSC) return 2;           /* hasta que fdd_poll haga el reset, nada */
    r = usb_cmd(cdb, len, dir_in, buf, n, timeout, xferred);
    if (r == UFI_OK) { fd.asc = 0; fd.fails = 0; return 0; }
    if (r == UFI_CHECK) {
        r = req_sense();
        if (r == UFI_OK || r == UFI_CHECK) { fd.fails = 0; return 1; }   /* (sense desconocido si el propio REQUEST SENSE fallo) */
    }
    if (r == UFI_GONE) return 3;
    fd.n_err++;
    fd.asc = (r == UFI_TIMEOUT) ? 0xFEU : 0xFDU;                  /* resumen para FDD_STAT: FE plazo, FD transporte */
    if (fd.backend != BE_MSC) fd.need_reset = 1;
    log_str("FDD: orden "); log_hex(cdb[0]); log_str(" transporte "); log_dec((u32)r); log_str(" (reset recovery pendiente)\n");
    return 2;
}

static u32 be32(const u8 *p) { return ((u32)p[0] << 24) | ((u32)p[1] << 16) | ((u32)p[2] << 8) | p[3]; }

/* sectores del medio: READ FORMAT CAPACITIES y, si no, READ CAPACITY(10). 1 = OK (secs y bloque de 512 B) */
static int read_capacity(u32 *secs)
{
    static const u8 rfc[10] = { 0x23, 0, 0, 0, 0, 0, 0, 0, 64, 0 };
    static const u8 rc[10]  = { 0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    u32 n = 0, blocks, blen;
    if (run(rfc, 10, 1, fdbuf, 64, T_CMD_MS, &n) == 0 && n >= 12U) {
        u8 code = fdbuf[8] & 3U;                                  /* 1 sin formato, 2 formateado, 3 sin medio */
        blocks = be32(fdbuf + 4); blen = ((u32)fdbuf[9] << 16) | ((u32)fdbuf[10] << 8) | fdbuf[11];
        if (code == 3U) { log_str("FDD: READ FORMAT CAPACITIES: sin medio\n"); return 0; }
        if (code == 1U) { log_str("FDD: disco SIN FORMATO\n"); return 0; }
        if (blen != 512U) { log_str("FDD: bloque de "); log_dec(blen); log_str(" B: no soportado\n"); return 0; }
        *secs = blocks;
        return 1;
    }
    if (run(rc, 10, 1, fdbuf, 8, T_CMD_MS, &n) == 0 && n >= 8U) {
        blocks = be32(fdbuf) + 1U; blen = be32(fdbuf + 4);
        if (blen != 512U) { log_str("FDD: bloque de "); log_dec(blen); log_str(" B: no soportado\n"); return 0; }
        *secs = blocks;
        return 1;
    }
    log_str("FDD: capacidad desconocida\n");
    return 0;
}

static void read_wp(void)
{
    u8 c10[10] = { 0x5A, 0, 0x3F, 0, 0, 0, 0, 0, 8, 0 };         /* MODE SENSE(10): cabecera de 8 B, WP = byte 3 bit 7 */
    u32 n = 0;
    fd.wp = 0;
    if (fd.backend == BE_MSC || ufi_subclass(fd.daddr) == MSC_SUBCLASS_SCSI) {
        static const u8 c6[6] = { 0x1A, 0, 0x3F, 0, 4, 0 };       /* MODE SENSE(6): cabecera de 4 B, WP = byte 2 bit 7 */
        if (run(c6, 6, 1, fdbuf, 4, T_CMD_MS, &n) == 0 && n >= 3U) { fd.wp = (fdbuf[2] >> 7) & 1U; return; }
    }
    if (run(c10, 10, 1, fdbuf, 8, T_CMD_MS, &n) == 0 && n >= 4U) { fd.wp = (fdbuf[3] >> 7) & 1U; return; }
    c10[2] = 0x05; c10[8] = 32;                                   /* pagina 05h (flexible disk) */
    if (run(c10, 10, 1, fdbuf, 32, T_CMD_MS, &n) == 0 && n >= 4U) { fd.wp = (fdbuf[3] >> 7) & 1U; return; }
    log_str("FDD: MODE SENSE no responde: proteccion desconocida (se sabra al escribir)\n");
}

static void start_unit(void)
{
    static const u8 cdb[6] = { 0x1B, 0, 0, 0, 0x01, 0 };
    log_str("FDD: START UNIT\n");
    run(cdb, 6, 0, NULL, 0, T_CMD_MS, NULL);
}

static void drop_usb(const char *why)
{
    log_str("FDD: t="); log_dec(now_ms()); log_str(" PORTSC="); log_hex(*(volatile u32 *)0xE0002184U);
    log_str(" unidad USB "); log_dec(fd.daddr); log_str(" fuera: "); log_str(why); log_str("\n");
    cache_reset(why);
    fd.daddr = 0; fd.backend = BE_NONE; fd.present = 0; fd.secs = 0; fd.wp = 0; fd.probe = 0; fd.asc = 0;
    fd.need_reset = 0; fd.fails = 0;
}

static void medium_gone(const char *why)
{
    if (fd.present) { log_str("FDD: "); log_str(why); log_str("\n"); }
    cache_reset(why);
    fd.present = 0; fd.secs = 0; fd.wp = 0; fd.t_hold = 0;
}

/* TEST UNIT READY ha dicho OK: leer capacidad y proteccion; con todo bien, empieza el prefetch */
static void medium_arrived(void)
{
    u32 secs = 0;
    fd.present = 0;
    if (!read_capacity(&secs)) { fd.t_hold = now_ms(); return; }
    if (secs == 0U || secs > FDD_MAX_SECS) {
        log_str("FDD: medio de "); log_dec(secs); log_str(" bloques: no es un disquete soportado\n");
        if (fd.backend == BE_MSC || ufi_subclass(fd.daddr) == MSC_SUBCLASS_SCSI) {   /* pendrive: no tocarlo nunca */
            fd.ign_daddr = fd.daddr;
            drop_usb("no es un disquete (ignorado)");
        } else {
            fd.t_hold = now_ms();
        }
        return;
    }
    fd.secs = secs;
    read_wp();
    cache_reset("medio nuevo");
    fd.present = 1; fd.start_sent = 0; fd.t_hold = 0;
    log_str("FDD: disco listo, "); log_dec(secs); log_str(" sectores"); if (fd.wp) log_str(", PROTEGIDO"); log_str("; llenando la cache\n");
}

/* devuelve 1 si el transporte fallo (para contar la racha) */
static int media_check(void)
{
    static const u8 tur[6] = { 0, 0, 0, 0, 0, 0 };
    int r = run(tur, 6, 0, NULL, 0, T_SHORT_MS, NULL);
    if (r == 0) {
        if (!fd.present && (fd.t_hold == 0U || (u32)(now_ms() - fd.t_hold) > T_HOLD_MS)) medium_arrived();
        return 0;
    }
    if (r == 2) return 1;
    if (r != 1) return 0;                                         /* desconectada: ya tratado */
    if (fd.asc == 0x3AU) {                                        /* sin disco */
        medium_gone("disco retirado");
    } else if (fd.key == 6U) {                                    /* unit attention: cambio de disco o reset */
        log_sense("unit attention:");
        medium_gone("cambio de disco");
        medium_arrived();
    } else if (fd.asc == 0x04U && fd.ascq == 0x02U && !fd.start_sent) {
        fd.start_sent = 1;
        start_unit();
    } else if (fd.asc == 0x04U) {
        /* arrancando (04/01): al siguiente sondeo */
    } else {
        u32 sense = ((u32)fd.key << 16) | ((u32)fd.asc << 8) | fd.ascq;
        if (sense != fd.logged) { fd.logged = sense; log_sense("TEST UNIT READY:"); }   /* una vez, no cada segundo */
        if (fd.present) medium_gone("el disco ya no responde");
    }
    return 0;
}

static int probe(void)
{
    static const u8 inq[6] = { 0x12, 0, 0, 0, 36, 0 };
    u32 n = 0;
    int r;
    fd.probe = 0;
    r = run(inq, 6, 1, fdbuf, 36, T_SHORT_MS, &n);
    if (r == 3) return 0;
    if (r == 2) { fd.probe = 1; return 1; }                       /* otra vez tras el reset */
    if (r == 0 && n >= 8U) {
        u8 pdt = fdbuf[0] & 0x1FU, rmb = (fdbuf[1] >> 7) & 1U;
        log_str("FDD: INQUIRY tipo "); log_dec(pdt); log_str(" extraible "); log_dec(rmb); log_str(" '");
        for (int i = 8; i < 32 && i < (int)n; i++) log_char((fdbuf[i] >= 32U && fdbuf[i] < 127U) ? (char)fdbuf[i] : '.');
        log_str("'\n");
        if (pdt != 0U) { fd.ign_daddr = fd.daddr; drop_usb("no es un disco de acceso directo (ignorado)"); return 0; }
    } else {
        log_str("FDD: INQUIRY sin respuesta util ("); log_dec((u32)r); log_str(")\n");
    }
    fd.present = 0;
    return media_check();
}

/* ------------------------------------------------------------------ disco: tramos */
/* READ/WRITE(10) de n sectores con hasta 3 intentos dentro del plazo (fd.deadline). FDD_* */
static int rw10(u8 op, u32 lba, u32 n, u8 *buf, int dir_in)
{
    u8 cdb[10] = { op, 0, (u8)(lba >> 24), (u8)(lba >> 16), (u8)(lba >> 8), (u8)lba, 0, (u8)(n >> 8), (u8)n, 0 };
    for (int attempt = 0; attempt < 3; attempt++) {
        u32 x = 0;
        int r = run(cdb, 10, dir_in, buf, (u16)(n * 512U), T_CMD_MS, &x);
        if (r == 0) {
            if (x == n * 512U) return FDD_OK;
            log_str("FDD: transferencia corta "); log_dec(x); log_str(" B\n");
            return FDD_ERROR;
        }
        if (r == 3) return FDD_ERROR;                             /* desconectada: el umount limpia el estado */
        if (r == 2) return FDD_ERROR;                             /* transporte: reset en fdd_poll, que el MSX reintente */
        if (fd.asc == 0x3AU) { medium_gone("sin disco"); return FDD_NO_MEDIUM; }
        if (fd.asc == 0x27U) { fd.wp = 1; log_str("FDD: disco PROTEGIDO\n"); return FDD_ERROR; }
        if (fd.key == 6U) {                                       /* medio cambiado / reset: fdd_poll relee la geometria */
            log_sense("unit attention:");
            medium_gone("cambio de disco");
            return FDD_NO_MEDIUM;
        }
        if (fd.asc == 0x04U) { ufi_delay_ms(300); continue; }     /* arrancando (el plazo lo vigila usb_cmd) */
        log_sense(op == 0x28U ? "READ(10):" : "WRITE(10):");
        if (fd.key == 3U || fd.key == 4U || fd.key == 0x0BU) continue;   /* error de medio/hardware/abortada: un reintento */
        return FDD_ERROR;
    }
    return FDD_ERROR;
}

/* trae del disco el tramo que contiene el sector s (hasta 16 sectores) y lo deja en la cache, sin pisar
 * sectores sucios; marca validos los que ha traido */
static int fetch_chunk(u32 s)
{
    u32 c = s & ~(CHUNK_SECS - 1U), n = CHUNK_SECS;
    int r;
    if (c + n > fd.secs) n = fd.secs - c;
    r = rw10(0x28, c, n, pfbuf, 1);
    if (r != FDD_OK) return r;
    for (u32 i = 0; i < n; i++) {
        if (!bit_get(fd.dirty, c + i)) copy_bytes(cache_sec(c + i), pfbuf + i * 512U, 512U);
        bit_set(fd.valid, c + i);
    }
    return FDD_OK;
}

/* vuelca al disco el primer tramo de sectores sucios (hasta 16 seguidos). 1 = ha hecho algo */
static int flush_one(void)
{
    u32 s, n;
    int r;
    if (fd.n_dirty == 0U || !fd.present) return 0;
    for (s = 0; s < fd.secs && !bit_get(fd.dirty, s); s++) ;
    if (s >= fd.secs) { fd.n_dirty = 0; return 0; }
    for (n = 1; n < CHUNK_SECS && s + n < fd.secs && bit_get(fd.dirty, s + n); n++) ;
    fd.deadline = now_ms() + T_REQ_MS;
    r = rw10(0x2A, s, n, cache_sec(s), 0);
    fd.deadline = 0;
    if (r == FDD_OK) {
        for (u32 i = 0; i < n; i++) bit_clr(fd.dirty, s + i);
        fd.n_dirty = (fd.n_dirty > n) ? fd.n_dirty - n : 0U;
        fd.flush_tries = 0;
        return 1;
    }
    if (r == FDD_NO_MEDIUM || !fd.present) return 1;              /* medium_gone ya limpio la cache */
    fd.n_err++;
    if (++fd.flush_tries >= FLUSH_TRIES || fd.wp) {
        log_str("FDD: tramo sucio "); log_dec(s); log_str("+"); log_dec(n); log_str(" PERDIDO");
        log_str(fd.wp ? " (disco protegido)\n" : " (3 fallos)\n");
        for (u32 i = 0; i < n; i++) bit_clr(fd.dirty, s + i);
        fd.n_dirty = (fd.n_dirty > n) ? fd.n_dirty - n : 0U;
        fd.flush_tries = 0;
    }
    return 1;
}

/* el PL ha pedido un sector de la TARJETA (no de la ventana): el prefetch le cede el paso */
static int cancel_for_sd(void)
{
    return box[W_REQ_SEQ] != box[W_ACK_SEQ] && !fdd_in_window(box[W_REQ_SEC]);
}

/* trae un tramo mas de la cache en segundo plano. 1 = ha hecho algo */
static int prefetch_one(void)
{
    u32 s;
    int r;
    if (!fd.present || fd.pf_done) return 0;
    for (s = fd.pf_next; s < fd.secs && bit_get(fd.valid, s); s++) ;
    if (s >= fd.secs) {
        fd.pf_done = 1;
        log_str("FDD: cache completa ("); log_dec(fd.secs); log_str(" sectores)\n");
        publish();
        return 0;
    }
    fd.deadline = now_ms() + T_REQ_MS;
    ufi_set_cancel(cancel_for_sd);
    r = fetch_chunk(s);
    ufi_set_cancel(NULL);
    fd.deadline = 0;
    if (r == FDD_OK) fd.pf_next = (s & ~(CHUNK_SECS - 1U)) + CHUNK_SECS;
    else if (fd.asc == 0xFEU && cancel_for_sd()) { /* cortado por la SD: mismo tramo la proxima vez */ }
    else fd.pf_next = (s & ~(CHUNK_SECS - 1U)) + CHUNK_SECS;      /* tramo ilegible: se salta, ya lo pedira el MSX */
    return 1;
}

/* ------------------------------------------------------------------ lectura / escritura (peticiones del PL) */
int fdd_read(u32 lba, u32 cnt, u8 *buf)
{
    if (!fd.present) return FDD_NO_MEDIUM;
    if (cnt == 0U || lba >= fd.secs || cnt > fd.secs - lba) { fd.n_err++; publish(); return FDD_ERROR; }
    if (fd.backend == BE_FAKE) {
        copy_bytes(buf, (const u8 *)(fd.fake_base + lba * 512U), cnt * 512U);
        fd.n_rd += cnt; publish();
        return FDD_OK;
    }
    fd.deadline = now_ms() + T_REQ_MS;
    for (u32 s = lba; s < lba + cnt; s++) {
        if (bit_get(fd.valid, s)) continue;
        int r = fetch_chunk(s);                                   /* lo que falte, del disco, dentro del plazo */
        if (r != FDD_OK) { fd.deadline = 0; fd.n_err++; publish(); return r; }
        s |= (CHUNK_SECS - 1U);                                   /* el resto del tramo ya esta */
    }
    fd.deadline = 0;
    copy_bytes(buf, cache_sec(lba), cnt * 512U);
    fd.n_rd += cnt;
    publish();
    return FDD_OK;
}

int fdd_write(u32 lba, u32 cnt, const u8 *buf)
{
    if (!fd.present) return FDD_NO_MEDIUM;
    if (cnt == 0U || lba >= fd.secs || cnt > fd.secs - lba) { fd.n_err++; publish(); return FDD_ERROR; }
    if (fd.wp) { fd.n_err++; publish(); return FDD_ERROR; }      /* Nextor no distingue: "Not ready" */
    if (fd.backend == BE_FAKE) {
        copy_bytes((u8 *)(fd.fake_base + lba * 512U), buf, cnt * 512U);
        fd.n_wr += cnt; publish();
        return FDD_OK;
    }
    copy_bytes(cache_sec(lba), buf, cnt * 512U);                  /* write-back: fdd_poll lo vuelca */
    for (u32 s = lba; s < lba + cnt; s++) {
        bit_set(fd.valid, s);
        if (!bit_get(fd.dirty, s)) { bit_set(fd.dirty, s); fd.n_dirty++; }
    }
    fd.n_wr += cnt;
    publish();
    return FDD_OK;
}

/* ------------------------------------------------------------------ consultas y bucle */
int fdd_present(void)         { return fd.present; }
u32 fdd_sectors(void)         { return fd.present ? fd.secs : 0U; }
int fdd_write_protected(void) { return fd.wp; }

void fdd_init(void)
{
    u8 *p = (u8 *)&fd;
    for (unsigned i = 0; i < sizeof fd; i++) p[i] = 0;
    box[W_FDD_STAT] = 0; box[W_FDD_CNT] = 0; box[W_FDD_ERR] = 0;  /* +0x8C..+0x94 los deja boot.tcl (falso) */
    FDD_DSB();
}

static void fake_poll(void)
{
    u32 base = box[W_FDD_FAKE_BASE], secs = box[W_FDD_FAKE_SECS];
    int fake = box[W_FDD_FAKE] == FDD_FAKE_MAGIC && base != 0U && (base & 3U) == 0U && secs >= 1U && secs <= FDD_MAX_SECS;
    if (fake && fd.backend != BE_FAKE) {
        fd.backend = BE_FAKE; fd.present = 1; fd.wp = 0; fd.secs = secs; fd.fake_base = base; fd.asc = 0; fd.pf_done = 1;
        log_str("FDD: disquete FALSO en la DDR "); log_hex(base); log_str(", "); log_dec(secs); log_str(" sectores\n");
        publish();
    } else if (!fake && fd.backend == BE_FAKE) {
        fd.backend = BE_NONE; fd.present = 0; fd.secs = 0; fd.pf_done = 0;
        log_str("FDD: disquete falso retirado\n");
        publish();
    } else if (fake) {
        fd.secs = secs; fd.fake_base = base;                      /* por si xsdb cambia la imagen en caliente */
    }
}

void fdd_poll(void)
{
    u32 now = now_ms();
    if (fd.daddr == 0U) { fake_poll(); return; }
    if (box[W_REQ_SEQ] != box[W_ACK_SEQ]) return;                 /* hay una peticion del PL esperando: primero ella */
    if (fd.need_reset && fd.backend != BE_MSC) {                  /* reset recovery diferido (hasta ~650 ms) */
        fd.need_reset = 0;
        ufi_reset(fd.daddr);
        return;
    }
    if ((u32)(now - fd.t_poll) >= T_POLL_MS) {                    /* (tambien el probe: tras el tiempo de asentado) */
        int bad;
        fd.t_poll = now;
        fd.deadline = now + T_REQ_MS;                             /* el sondeo entero (capacidad incluida) en un plazo */
        bad = fd.probe ? probe() : media_check();
        fd.deadline = 0;
        if (bad && ++fd.fails >= FAIL_STREAK) {
            fd.ign_daddr = fd.daddr;
            drop_usb("no responde (3 fallos seguidos): ignorada hasta reenchufarla");
        }
        publish();
        return;
    }
    if (fd.present && fd.backend != BE_FAKE && !fd.need_reset) {
        if (flush_one()) { publish(); return; }                   /* lo sucio primero */
        if (prefetch_one()) { publish(); return; }
    }
}

/* ------------------------------------------------------------------ callbacks (dentro de tuh_task_ext) */
void fdd_ufi_mount(uint8_t daddr)
{
    if (daddr == fd.ign_daddr) return;
    if (fd.daddr != 0U) { log_str("FDD: segunda disquetera USB "); log_dec(daddr); log_str(": ignorada\n"); return; }
    if (fd.backend == BE_FAKE) { log_str("FDD: la unidad USB desplaza al disquete falso\n"); fd.backend = BE_NONE; fd.present = 0; fd.pf_done = 0; }
    fd.daddr = daddr;
    fd.backend = (ufi_transport(daddr) == UFI_XPORT_BOT) ? BE_UFI_BOT : BE_UFI_CBI;
    fd.present = 0; fd.secs = 0; fd.wp = 0; fd.probe = 1; fd.start_sent = 0; fd.t_hold = 0; fd.asc = 0;
    fd.t_poll = now_ms();                                         /* la primera orden, al cabo de ~1 s: la TEAC
                                                                     fallaba el INQUIRY nada mas enumerar */
    fd.need_reset = 0; fd.fails = 0;
    cache_reset("unidad nueva");
    fd.n_mount++;
    log_str("FDD: t="); log_dec(now_ms()); log_str(" disquetera USB "); log_dec(daddr); log_str(" montada (backend "); log_dec(fd.backend); log_str(")\n");
    publish();
}

void fdd_ufi_umount(uint8_t daddr)
{
    if (daddr == fd.ign_daddr) fd.ign_daddr = 0;
    if (daddr != fd.daddr) return;
    drop_usb("desconectada");
    publish();
}

void fdd_msc_mount(uint8_t daddr)
{
#if CFG_TUH_MSC
    u32 blocks = tuh_msc_get_block_count(daddr, 0), bsize = tuh_msc_get_block_size(daddr, 0);
    log_str("MSC "); log_dec(daddr); log_str(": "); log_dec(blocks); log_str(" bloques de "); log_dec(bsize); log_str(" B");
    if (bsize != 512U || blocks == 0U || blocks > FDD_MAX_SECS) { log_str(": no es un disquete, ignorado\n"); return; }
    if (fd.daddr != 0U) { log_str(": ya hay una disquetera, ignorado\n"); return; }
    log_str(" -> disquetera (backend 3)\n");
    if (fd.backend == BE_FAKE) { fd.backend = BE_NONE; fd.present = 0; fd.pf_done = 0; }
    fd.daddr = daddr; fd.backend = BE_MSC;
    fd.present = 0; fd.secs = blocks; fd.wp = 0; fd.probe = 1; fd.t_hold = 0; fd.asc = 0;
    cache_reset("unidad nueva");
    fd.n_mount++;
    publish();
#else
    (void)daddr;
#endif
}

void fdd_msc_umount(uint8_t daddr)
{
    if (daddr != fd.daddr || fd.backend != BE_MSC) return;
    drop_usb("desconectada");
    publish();
}
