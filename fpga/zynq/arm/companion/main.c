/* main.c — proxy de SD del MSXimus en la ZYNQ MINI (Cortex-A9 core 0, bare-metal).
 *
 * Sirve la tarjeta REAL de TF2 (SD1, MIO 10..15) al modulo sd_axi_proxy del PL
 * a traves del buzon SDBOX en la DDR (ver fpga/zynq/sd_axi_proxy.v):
 *   W0 +0x00: [0] MODE (1 = proxy)  [32] tarjeta presente  [63:48] tamano (MB)
 *   W1 +0x08: [31:0] REQ_SEQ  [39:32] op (1 lee, 2 escribe)  [47:40] bloques
 *   W2 +0x10: [31:0] sector
 *   W3 +0x18: [31:0] ACK_SEQ  [63:32] estado (0 = OK)
 *   +0x20..: estadisticas del ARM (lecturas, escrituras, errores, reinits, vueltas)
 * Datos en SDBUF (+n*512). Sin MMU ni caches (start.S): coherente sin mas.
 *
 * TF1 (SD0, MIO 40..45) SOLO PARA PERFILES (8/11/2026, rama tf1-perfiles; el PL no cambia). Desde la Z1.2.13 la TF1 era el
 * dispositivo 2 de Nextor (unidad B:, bit 31 del sector); ya no: el MSX no tiene ningun camino a la TF1 y la microSD de TF1 es la
 * tarjeta de perfiles (mxpf.c: tf1_sectores/leer/escribir, siempre desde el hilo de este bucle). Un sector con el bit 31 puesto
 * ya no es de TF1: cae en la ruta de TF2 y se rechaza por estar fuera de la tarjeta (st 2, sin reinicializar). Unica excepcion:
 * el sector 0xFFFFFFFF, el bloque de informacion que leen los drivers de Nextor 2.1.4 y 3 (sin tocarlos) en DRV_INIT: se contesta
 * "TF1!" (+0), 0 sectores (+4), presente 0 (+8), asi que no muestran el dispositivo 2 (bios/tests/test_tf1_nextor.py, 'sin tarjeta').
 *   - W0[32] (tarjeta presente) vale 1 solo si hay tarjeta en TF2.
 *   - SDBOX+0x3C W15: [0] TF1 presente  [1] TF1 sondeada     +0x40 W16: sectores de TF1 (0 = sin tarjeta)  (informativo, JTAG)
 *   - Se sondea una vez al arrancar el bucle y en cada consulta de mxpf.c si no habia tarjeta; sin tarjeta no hay reintentos de
 *     fondo (un init fallido bloquea el bucle). Con tarjeta, SEND_STATUS cada 2 s para detectar la retirada.
 *
 * Bucle de bajo consumo (v2): el core duerme en WFI y lo despiertan
 *   - IRQ_F2P[0] (ID 61 del GIC): req_irq del proxy del PL, nivel alto hasta el acuse;
 *   - el timer privado del core (ID 29) cada 10 ms, para la vigilancia de la tarjeta.
 * Las interrupciones quedan enmascaradas en CPSR (no hay manejadores): WFI se
 * despierta con una IRQ pendiente aunque este enmascarada, y el GIC solo tiene
 * que reenviarlas (distribuidor + interfaz de CPU habilitados).
 * Cambio en caliente: un acceso que falla reinicializa la tarjeta (y reintenta);
 * sin tarjeta, init cada 0,5 s; con tarjeta, SEND_STATUS (ACMD13) cada 2 s.
 *
 * DISQUETERA USB (22/09, fdd.c + ufi_host.c): los sectores [FDD_LBA_BASE, +2880) del mismo
 * "dispositivo SD" son el disquete (ventana magica): aqui se interceptan ANTES de tocar la tarjeta
 * (un LBA fuera de la SD haria fallar XSdPs y reinicializaria la tarjeta) y van a fdd_read/fdd_write
 * (st 1 = sin disco, 2 = error; ambos acaban en el bit1 "timeout" del MSX). fdd_poll() en el bucle
 * detecta el medio (~1 s). El menu del MSX monta la ventana como un .dsk; ni el PL ni Nextor cambian.
 * Modos imagen (SDBOX+0x78, lo deja boot.tcl): 'IMG1' = el PL sirve la imagen de la DDR (MODE=0, el
 * ARM no interviene); 'IMG2' = el ARM sirve la imagen (0x11000000, 224 MB) con MODE=1 y ademas la
 * ventana de la disquetera: asi se prueba todo con un disquete FALSO en la DDR, sin SD ni USB.      */
#include "xil_types.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xsdps.h"
#include "log.h"
#include "sleep.h"
#include "fdd.h"
#include "yrw801.h"                                    /* 13/10: suma de comprobacion de la YRW801 (por tramos, tras MSX_RUN) */
#include "dual_disco.h"                                /* 2/11: perfil Dual, la SD de TF2 compartida con la maquina B (Nextor-B) */

#define SDBOX     0x1FF00100U
#define SDBUF     0x1FF10000U
#define SD_DEVICE 1U                 /* 1 = TF2 (SD1); 0 = TF1 (SD0) */
#define IMG_BASE  0x11000000U        /* imagen de disco en la DDR (modos IMG1/IMG2) */
#define IMG_MB    224U
#define IMG_SECS  (IMG_MB * 2048U)   /* 458752 sectores de 512 B */

enum { W_MODE = 0, W_CARD = 1, W_REQ_SEQ = 2, W_REQ_OPC = 3, W_REQ_SEC = 4,
       W_ACK_SEQ = 6, W_ACK_ST = 7, W_N_RD = 8, W_N_WR = 9, W_N_ERR = 10, W_N_INIT = 11, W_N_LOOP = 12 };

/* GIC (distribuidor 0xF8F01000, interfaz de CPU 0xF8F00100) y timer privado (0xF8F00600) */
#define REG(a)      (*(volatile u32 *)(a))
#define ICDDCR      REG(0xF8F01000U)
#define ICDISER(n)  REG(0xF8F01100U + 4U * (n))
#define ICDIPR(id)  (*(volatile u8 *)(0xF8F01400U + (id)))
#define ICDIPTR(id) (*(volatile u8 *)(0xF8F01800U + (id)))
#define ICDICFR(n)  REG(0xF8F01C00U + 4U * (n))
#define ICCICR      REG(0xF8F00100U)
#define ICCPMR      REG(0xF8F00104U)
#define PTIM_LOAD   REG(0xF8F00600U)
#define PTIM_CTRL   REG(0xF8F00608U)
#define PTIM_ISR    REG(0xF8F0060CU)
#define ID_PTIMER   29U
#define ID_F2P0     61U              /* IRQ_F2P[0] */

static volatile u32 * const box = (volatile u32 *)SDBOX;
static XSdPs sd;
static int   present;
static u32   card_mb;
#define TF1_INFO_SEC  0xFFFFFFFFU    /* bloque de informacion que leen los drivers de Nextor (DRV_INIT): ahora siempre "sin TF1" */
enum { W_TF1_ST = 15, W_TF1_SECS = 16 };
static XSdPs sd1;                    /* TF1 (SD0): solo perfiles (mxpf.c) */
static int   present1, probed1, logged1 = -1;
static u32   card1_secs;
static u8    tf1_evento;                       /* la tarjeta de TF1 aparece o se va (o primera sonda): el bucle principal revisa el aviso */
static u64   t_stat1;
extern u64   gt_now(void);
extern void  l2_disable(void);
extern void  mmu_init(void);
u32 mp3_now(void) { return *(volatile u32 *)0xF8F00200U; }   /* mp3.c: temporizador global (CPU/2 = 333 MHz) */
extern int   usb_host_init(void);
extern void  usb_host_poll(void);
extern void  usb_host_vigila(void);                   /* usb_host.c (1/11): reinicia el USB si el EHCI se cuelga, o si JTAG lo pide (tools/usbreset.tcl) */
extern void  osd_init(void);                          /* osd.c: pagina de informacion por la UART0 -> iosys */
extern void  osd_poll(void);
extern int   cfg_load(u32 *cfgbits);                  /* qspi_cfg.c: bloque de config guardado en la QSPI */
extern void  cfg_poll(void);                          /*   -> MBOX+0x1C[28:8] antes de MSX_RUN; guarda al pulsar "guardar" */
extern u32   usb_stats_mount, usb_stats_reports;
extern void  wg_poll(void);
extern void  pext_poll(void);                          /* perfiles_ext.c (31/10): .MXP de la TF2 y etiqueta [P:ID] de una ROM, pedidos por el menu */
extern void perfiles_aviso_revisa(void);               /* perfiles.c (8/11): clasifica la TF1 y avisa si es una tarjeta nueva */
extern void  dual_init(void);                          /* dual.c (2/11): perfil Dual, la palabra de control de la maquina B a cero (en la DDR hay basura o restos) */
extern void  dual_poll(void);                          /*   y una ROM que el menu manda a B (tecla D de Lanzar ROM) */
extern int   cfg_perfil_arranque(char id[9]);          /* qspi_cfg.c: el "perfil al arrancar" (1 = hay) */
extern void  v99desk_init(void);
extern void  v99desk_poll(void);                       /* rama beta: escritorio vivo (v99desk.c) */
extern void  tape_poll(void);                         /* tape.c: cinta virtual (anillo de pulsos + manos) */
extern void  net_init(void);                          /* net.c (25/09): GEM0 + lwIP por sondeo, DHCP, eco TCP 7 */
extern void  net_poll(void);
extern void  esp_init(void);                          /* esp_link.c (25/09): el companion como "ESP32" del MSX por la UART1 */
extern int   tls_init(void);                          /* esp_tls.c (26/09): Mbed TLS para las conexiones https del "ESP32" */
extern void  esp_poll(void);
extern void  tape_init(void);                         /*   -> control de la cinta a 0 antes de MSX_RUN (basura/sesion anterior) */
#include "ota.h"                                      /* 30/09: actualizacion por red (ranura B de la QSPI) */
#include "profile.h"                                  /* 30/10: carga de un bitstream del PL por PCAP (prueba de los perfiles) */
#include "mxpf.h"                                     /* 30/10: perfiles del PL en la microSD de TF1 (particion MXPF) */
volatile u32 loop_ms;                                 /* vueltas del bucle (~1 ms cada una): reloj de tape.c */                           /* wavegame.c: ordenes 92h del juego + streaming de los WAV */

static void wake_setup(void)
{
    ICDDCR = 0U;
    for (u32 n = 0; n < 3U; n++) {                                     /* la demo de fabrica deja IRQs
        REG(0xF8F01180U + 4U * n) = 0xFFFFFFFFU;                        * habilitadas/pendientes que nadie
        REG(0xF8F01280U + 4U * n) = 0xFFFFFFFFU;                        * acusa: WFI no dormiria nunca */
    }
    ICDIPR(ID_PTIMER) = 0xA0U;  ICDIPR(ID_F2P0) = 0xA0U;
    ICDIPTR(ID_F2P0) = 0x01U;                                         /* -> CPU0 */
    ICDICFR(ID_F2P0 / 16U) = (ICDICFR(ID_F2P0 / 16U) & ~(3U << ((ID_F2P0 % 16U) * 2U)))
                             | (1U << ((ID_F2P0 % 16U) * 2U));         /* nivel alto, 1-N */
    ICDISER(ID_PTIMER / 32U) = 1U << (ID_PTIMER % 32U);
    ICDISER(ID_F2P0 / 32U)   = 1U << (ID_F2P0 % 32U);
    ICCPMR = 0xFFU;
    ICCICR = 0x01U;
    ICDDCR = 0x01U;
    PTIM_CTRL = 0U;
    PTIM_ISR  = 1U;
    PTIM_LOAD = COUNTS_PER_SECOND / 100U;                              /* 10 ms (CPU/2) */
    PTIM_CTRL = 0x07U;                                                 /* enable, auto-reload, IRQ */
}

static int image_mode;                                  /* 18/09: pruebas sin tarjeta: la "SD" es la imagen de la DDR
                                                           (1 = 'IMG1' la sirve el PL, 2 = 'IMG2' la sirve el ARM) */
static void copy_words(u8 *dst, const u8 *src, u32 n)  /* memoria strongly-ordered: a palabras si se puede (x4) */
{
    if ((((u32)(uintptr_t)dst | (u32)(uintptr_t)src | n) & 3U) == 0U) {
        u32 *d = (u32 *)dst; const u32 *s = (const u32 *)src;
        for (n >>= 2; n; n--) *d++ = *s++;
    } else {
        while (n--) *dst++ = *src++;
    }
}
static int img_rw(u32 sec, u32 cnt, u8 *buf, int write) /* imagen de la DDR: 1 = OK (comparar en sectores, no en bytes) */
{
    if (sec >= IMG_SECS || cnt > IMG_SECS - sec) return 0;
    if (write) copy_words((u8 *)(IMG_BASE + sec * 512U), buf, cnt * 512U);
    else       copy_words(buf, (const u8 *)(IMG_BASE + sec * 512U), cnt * 512U);
    return 1;
}
int sd_read(u32 sec, u32 cnt, u8 *buf)                 /* para wavegame.c y tape.c: 1 = OK */
{
    if (image_mode) return img_rw(sec, cnt, buf, 0);   /* boot.tcl BOOT_IMG=1/2: imagen FAT16 en 0x11000000 (224 MB) */
    if (!present) return 0;
    return XSdPs_ReadPolled(&sd, sec, cnt, buf) == XST_SUCCESS;
}
int sd_write(u32 sec, u32 cnt, const u8 *buf)          /* para dual_disco.c (la maquina B escribe en la TF2): 1 = OK; como sd_read */
{
    if (image_mode) return img_rw(sec, cnt, (u8 *)buf, 1);
    if (!present) return 0;
    return XSdPs_WritePolled(&sd, sec, cnt, buf) == XST_SUCCESS;
}
u32 sd_sectores(void)                                  /* sectores de 512 B de la TF2 (0 = sin tarjeta); con imagen en la DDR, la imagen */
{
    if (image_mode) return IMG_SECS;
    return present ? sd.SectorCount : 0U;
}
int sd_presente(void) { return image_mode ? 1 : present; }

static int sd_init_dev(XSdPs *s, u32 dev)
{
    XSdPs_Config *cfg = XSdPs_LookupConfig(dev);
    if (dev == SD_DEVICE) box[W_N_INIT]++;
    if (cfg == NULL) return 0;
    if (XSdPs_CfgInitialize(s, cfg, cfg->BaseAddress) != XST_SUCCESS) return 0;
    if (XSdPs_CardInitialize(s) != XST_SUCCESS) return 0;
    return 1;
}

static int sd_try_init(void)
{
    if (!sd_init_dev(&sd, SD_DEVICE)) return 0;
    card_mb = sd.SectorCount >> 11;                       /* sectores de 512 B -> MB */
    return 1;
}

static void publish_card(void)
{
    if (image_mode == 2) { box[W_CARD] = 1U | (IMG_MB << 16); dsb(); return; }   /* IMG2: "tarjeta" de 224 MB */
    box[W_CARD] = (present ? 1U : 0U) | (card_mb << 16);
    dsb();
}

static void publish_tf1(void)
{
    box[W_TF1_ST]   = (present1 ? 1U : 0U) | (probed1 ? 2U : 0U);
    box[W_TF1_SECS] = present1 ? card1_secs : 0U;
    dsb();
}

static void tf1_probe(void)                            /* init de TF1 y aviso al PL (W0[32]) y al log si cambia */
{
    probed1 = 1;
    present1 = image_mode ? 0 : sd_init_dev(&sd1, 0U);
    card1_secs = present1 ? sd1.SectorCount : 0U;
    publish_tf1();
    publish_card();
    if (logged1 != present1) {
        logged1 = present1;
        tf1_evento = 1U;                               /* perfiles.c: ¿hay que avisar de una tarjeta nueva? (bucle principal) */
        if (present1) { log_str("TF1 (perfiles): tarjeta OK, "); log_dec(card1_secs >> 11); log_str(" MB\n"); }
        else log_str("TF1: sin tarjeta (se sondea otra vez en cada arranque del MSX)\n");
    }
}

static void tf1_info_block(void)                       /* sector 0xFFFFFFFF: "TF1!", 0 sectores, presente 0 (Nextor ya no tiene dispositivo 2) */
{
    volatile u32 *w = (volatile u32 *)SDBUF;
    for (u32 i = 0; i < 128U; i++) w[i] = 0U;
    w[0] = 0x21314654U;                                 /* 'T' 'F' '1' '!' */
    dsb();
}

static void tf1_poll(u64 now)                          /* primera sonda y vigilancia de la retirada */
{
    if (image_mode) return;
    if (!probed1) { t_stat1 = now; tf1_probe(); return; }
    if (present1 && now - t_stat1 > (u64)(COUNTS_PER_SECOND * 2U)) {
        u8 sdstat[64];
        t_stat1 = now;
        if (XSdPs_Get_Status(&sd1, sdstat) != XST_SUCCESS) {
            present1 = 0; card1_secs = 0;
            publish_tf1(); publish_card();
            logged1 = 0;
            log_str("TF1: tarjeta retirada\n");
        }
    }
}

/* La peticion del PL (SDBOX) en curso: la sirve el bucle de main() y sd_ceder() (mxpf.c, entre trozos largos de E/S de TF1).
 * `last` es el ultimo REQ_SEQ atendido; pl_resembra() lo pone a 0 porque el PL nuevo empieza su cuenta en 0. */
static u32 last, n_rd, n_wr, n_err;

static void sd_servir(u32 seq)
{
    u32 opc, op, cnt, sec, st = 0;
    usleep(2);                                    /* la rafaga del PL (seq, op, sector) ya ha aterrizado */
    opc = box[W_REQ_OPC]; op = opc & 0xFFU; cnt = (opc >> 8) & 0xFFU; sec = box[W_REQ_SEC];
    if (cnt == 0U) cnt = 1U;
    if (op != 1U && op != 2U) {
        st = 3U;                                  /* orden desconocida */
    } else if (op == 1U && cnt == 1U && dual_disco_a_estado(sec, (u8 *)SDBUF)) {   /* perfil Dual (Z1.3.2b9): sector magico 7FFFFFFD = bloque de estado de la SD compartida con B; st = 0 */
        st = 0U;
    } else if (fdd_in_window(sec)) {              /* DISQUETERA: ventana magica, sin tocar la tarjeta */
        if (cnt > FDD_MAX_SECS - (sec - FDD_LBA_BASE)) st = 2U;            /* se sale de la ventana */
        else if (op == 1U) st = (u32)fdd_read(sec - FDD_LBA_BASE, cnt, (u8 *)SDBUF);
        else               st = (u32)fdd_write(sec - FDD_LBA_BASE, cnt, (const u8 *)SDBUF);
    } else if (op == 1U && cnt == 1U && sec == TF1_INFO_SEC) {   /* Nextor pregunta por el dispositivo 2: no hay (la TF1 es de los perfiles) */
        tf1_info_block();
        st = 0U;
    } else if (op == 2U && !dual_disco_a_puede_escribir(sec, cnt)) {   /* perfil Dual: la TF2 es de B (solo lee) salvo los .SRM de A; el motivo se lo da a A el bloque de estado. Tambien con la imagen IMG2 */
        st = 2U;
        dual_disco_a_rechazo(sec, cnt);
    } else if (image_mode == 2) {                 /* IMG2: la imagen de la DDR la sirve el ARM */
        st = img_rw(sec, cnt, (u8 *)SDBUF, op == 2U) ? 0U : 2U;
    } else for (int attempt = 0; attempt < 2; attempt++) {
        s32 r;
        if (!present) { st = 1U; break; }         /* sin tarjeta */
        if (sd.SectorCount != 0U && (sec >= sd.SectorCount || cnt > sd.SectorCount - sec)) { st = 2U; break; }   /* fuera de la tarjeta: sin reinit */
        if (op == 1U) r = XSdPs_ReadPolled(&sd, sec, cnt, (u8 *)SDBUF);
        else          r = XSdPs_WritePolled(&sd, sec, cnt, (const u8 *)SDBUF);
        if (r == XST_SUCCESS) { st = 0U; break; }
        st = 2U;                                  /* fallo: ¿se ha ido la tarjeta? reinit y un reintento */
        present = sd_try_init();
        publish_card();
    }
    if (st != 0U) n_err++; else if (op == 1U) n_rd++; else n_wr++;
    box[W_N_RD] = n_rd; box[W_N_WR] = n_wr; box[W_N_ERR] = n_err;
    box[W_ACK_ST] = st;
    dsb();
    box[W_ACK_SEQ] = seq;                         /* el PL espera este valor (y baja req_irq) */
    dsb();
    last = seq;
    if (st != 0U) {
        log_str("ERR op="); log_dec(op); log_str(" sec="); log_hex(sec);
        log_str(" n="); log_dec(cnt); log_str(" st="); log_dec(st); log_str("\n");
    }
}

/* mxpf.c (perfiles en la TF1, 30/10): E/S cruda de TF1 (sd1, que ya no comparte con Nextor). Todo corre en el hilo del bucle
 * principal: no hay dos accesos a la vez. Los buffers tienen que estar en memoria SIN cache (el DMA de la SD; Xil_DCache* son
 * vacios aqui). sd_ceder() sirve la peticion del MSX que haya pendiente: entre trozos de 128 KB el MSX no espera los 2 s del
 * proxy del PL. Un acceso que falla reinicializa la tarjeta y reintenta una vez. */
u32 tf1_sectores(void)
{
    if (!present1 && !image_mode) tf1_probe();         /* quien pregunta quiere saber si hay tarjeta ahora (la han podido meter) */
    return present1 ? card1_secs : 0U;
}

static int tf1_es(u32 sec, u32 cnt) { return present1 && card1_secs != 0U && sec < card1_secs && cnt <= card1_secs - sec; }

int tf1_leer(u32 sec, u32 cnt, void *buf)
{
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!tf1_es(sec, cnt)) return 0;
        if (XSdPs_ReadPolled(&sd1, sec, cnt, (u8 *)buf) == XST_SUCCESS) return 1;
        tf1_probe();
    }
    return 0;
}

int tf1_escribir(u32 sec, u32 cnt, const void *buf)
{
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!tf1_es(sec, cnt)) return 0;
        if (XSdPs_WritePolled(&sd1, sec, cnt, (const u8 *)buf) == XST_SUCCESS) return 1;
        tf1_probe();
    }
    return 0;
}

void sd_ceder(void)
{
    u32 seq = box[W_REQ_SEQ];
    if (seq != last) sd_servir(seq);
    dual_disco_poll();                                 /* y el buzon de la maquina B (perfil Dual): una orden de MSX-DOS tampoco puede esperar a que acabe una instalacion o una carpeta grande */
}

/* profile.c (PCAP, 30/10): el PL recien cargado nace como tras el BOOT.bin y hay que dejarle lo mismo que main() deja en el
 * arranque, con el MSX aun en reset (profile.c suelta MSX_RUN despues): el SDBOX sin peticion ni acuse (el REQ_SEQ del PL nuevo
 * empieza en 0), el modo y la tarjeta, la VRAM del V9968 a cero, la config de la QSPI, la cinta y el canal ARM -> V9990.
 * El companion no tiene mas estado del PL que ese. El `last` del bucle lo pone a 0 main() al ver que perfil_poll() cargo. */
void pl_resembra(void)
{
    volatile u32 *ctl = (volatile u32 *)0x1FF0001CU;
    u32 cfgbits = 0;
    box[W_REQ_SEQ] = 0; box[W_REQ_OPC] = 0; box[W_REQ_SEC] = 0; box[W_ACK_SEQ] = 0; box[W_ACK_ST] = 0;
    last = 0U;
    dsb();
    if (image_mode != 1) { publish_card(); box[W_MODE] = 1U; }
    dsb();
    {
        volatile u32 *vram = (volatile u32 *)0x10280000U;
        for (u32 i = 0; i < 0x40000U / 4U; i++) vram[i] = 0U;
        dsb();
    }
    *(volatile u32 *)0x1FF0002CU = 0U;                    /* video: seq, sel y auto_off a cero (cfg_load pone fs43) */
    if (cfg_load(&cfgbits)) {
        *ctl = (*ctl & 0x5BU) | cfgbits;                  /* se conservan MSX_RUN (0), el trazador, net_ps, s3_ps y tr_bios (6) */
        dsb();
        usleep(5000);
    }
    tape_init();
    v99desk_init();
    dual_init();                                          /* perfil Dual: B parada (el PL nuevo leeria una palabra vieja con la clave valida y arrancaria B) */
    usleep(3000);                                         /* que el buzon (ronda de ~1 ms) lo vea antes de soltar el MSX */
}

int main(void)
{
    u32 n_loop = 0;
    u64 t_retry = 0;

    l2_disable();
    mmu_init();                                           /* 23/09: MMU con todo igual salvo codigo + zona MP3 (mmu.c) */
    log_init();
    log_str("companion v3: SD de TF2 + USB host (TinyUSB)\n");
    ota_arranque();                                       /* 30/09: prueba de la ranura B (puede reiniciar el PS) */
    box[W_N_RD] = 0; box[W_N_WR] = 0; box[W_N_ERR] = 0; box[W_N_INIT] = 0; box[W_N_LOOP] = 0;
    image_mode = (box[30] == 0x494D4731U) ? 1 : (box[30] == 0x494D4732U) ? 2 : 0;   /* 'IMG1'/'IMG2' en SDBOX+0x78 (boot.tcl BOOT_IMG) */
    if (image_mode == 1) log_str("SD: modo IMAGEN (la tarjeta no se toca; sectores desde la DDR por el PL; W0/W1 los deja boot.tcl)\n");
    if (image_mode == 2) log_str("SD: modo IMAGEN 2 (la tarjeta no se toca; el ARM sirve la imagen de la DDR + ventana de la disquetera)\n");
    present = image_mode ? 0 : sd_try_init();
    if (!present) card_mb = 0;
    if (image_mode) {
    } else if (present) {
        log_str("tarjeta OK: "); log_dec(card_mb); log_str(" MB, tipo "); log_dec(sd.CardType);
        log_str(", HCS "); log_dec(sd.HCS); log_str(", bus "); log_dec(sd.BusWidth);
        log_str(" bits, "); log_dec(sd.BusSpeed); log_str(" Hz\n");
    } else {
        log_str("sin tarjeta (reintento cada 0,5 s)\n");
    }
    if (image_mode != 1) publish_card();
    last = box[W_REQ_SEQ];
    box[W_ACK_SEQ] = last;                                /* nada pendiente */
    dsb();
    if (image_mode != 1) box[W_MODE] = 1U;                /* proxy ON: el PL deja de usar la imagen (salvo IMG1) */
    dsb();
    fdd_init();                                           /* disquetera: campos +0x80.. del SDBOX a cero */
    /* VRAM del V9968 a cero ANTES de soltar el MSX. Vive en la DDR (VRAM_BASE 0x10000000 +
     * 0x280000 del shim, 18 bits = 256 KB) y la DDR arranca con basura: cualquier zona que un
     * juego no escriba se veia como ruido blanco (Xevious, 14/09). En el Tang arranca limpia. */
    {
        volatile u32 *vram = (volatile u32 *)0x10280000U;
        for (u32 i = 0; i < 0x40000U / 4U; i++) vram[i] = 0U;
        dsb();
    }
    {   /* config persistente (16/09): el bloque guardado en la QSPI va a MBOX+0x1C[28:8] con valid=1 y
         * el PL siembra config1/config2/turbo-boot/ganancia mientras el MSX sigue en reset. Se respeta
         * el bit 0 por si el arranque por JTAG (boot.tcl) ya lo puso: no resetear el MSX desde aqui. */
        u32 cfgbits = 0;
        if (cfg_load(&cfgbits)) {
            volatile u32 *ctl = (volatile u32 *)0x1FF0001CU;
            *ctl = (*ctl & 0x43U) | cfgbits;                  /* se conservan MSX_RUN y tr_bios (boot.tcl con TR_ROM) */
            dsb();
            usleep(5000);                                 /* el buzon lee el control cada ~1 ms: que llegue antes de soltar */
        }
    }
    tape_init();                                          /* Z1.2: cinta parada y en sincronia con el PL antes de arrancar el MSX */
    v99desk_init();                                       /* rama beta: el canal ARM -> V9990 a cero (en la DDR hay basura) */
    dual_init();                                          /* perfil Dual: la palabra de control de B a cero */
    usleep(3000);                                         /* que el buzon (ronda de ~1 ms) lo vea antes de soltar el MSX */
    ota_menu_version();                                   /* 11/11/2026: Ajustes dice la version de ota_info (Z1.4.9), no el FPGA_PATCH del PL. ANTES
                                                             del perfil de arranque, que suelta el MSX el solo */
    {   /* 31/10/2026, perfil al arrancar (ajuste de la QSPI, pagina Perfiles > A): si esta en la TF1 y es de la serie de este BOOT.bin se
         * carga por PCAP ANTES de soltar el MSX (+0,6 s al encender); perfil_cargar ya deja el PL sembrado y suelta el MSX. Si no se
         * puede (sin tarjeta, otra serie, no esta...) sigue el perfil 1; una marca en la DDR evita un bucle de reinicios. */
        char pid[9];
        if (cfg_perfil_arranque(pid) && mxpf_arranque(pid)) log_str("perfil al arrancar cargado\n");
    }
    *(volatile u32 *)0x1FF0001CU |= 1U;                   /* MSX_RUN: con BOOT.bin el MSX esperaba en reset (sin pisar la config) */
    dsb();
    wake_setup();
    log_str("MODE=1, WFI\n");
    usb_host_init();
    osd_init();
    net_init();                                           /* Ethernet del PS: no bloquea (sin cable, XST_FAILURE y a esperar) */
    tls_init();                                           /* Mbed TLS: entropia, DRBG, configuracion (TLS 1.2 cliente) */
    esp_init();                                           /* y el "ESP32" del MSX sobre ella (UART1 -> wifi_lite) */

    for (;;) {
        u32 seq;
        if (!dual_disco_activo()) __asm__ volatile ("wfi" ::: "memory");   /* con la maquina B usando su disco (MSX-DOS) no se duerme: B no despierta al ARM, y el timer son 10 ms por sector */
        PTIM_ISR = 1U;                                    /* si fue el timer, limpiar su evento */
        box[W_N_LOOP] = ++n_loop;
        loop_ms = n_loop;
        usb_host_poll();                                  /* TinyUSB: interrupciones por sondeo + tarea */
        usb_host_vigila();                                /* vigilante del EHCI: cada ~500 ms mira si el motor periodico avanza */
        osd_poll();                                       /* OSD: F12 / MBOX+0x30; refresco 1 s */
        cfg_poll();                                       /* "guardar" del menu (MBOX+0x70 toggle) -> sector de la QSPI */
        wg_poll();                                        /* WaveGame: ordenes del anillo Z80->ARM y relleno del anillo PCM */
        pext_poll();                                      /* perfiles: lo que el menu ha pedido por el 93h (instalar un .MXP, perfil de una ROM) */
        dual_poll();                                      /* perfil Dual: una ROM que el menu manda a la maquina B */
        dual_disco_poll();                                /* perfil Dual: el disco de la maquina B (Nextor-B) por el buzon de la DDR; la TF2 es la misma que la de A */
        v99desk_poll();                                   /* rama beta: el panel del companion en el escritorio del V9990 */
        tape_poll();                                      /* cinta virtual: anillo de pulsos y teclas automaticas */
        fdd_poll();                                       /* disquetera USB / falsa: medio presente, capacidad, WP */
        net_poll();                                       /* Ethernet: RX/TX del GEM0, temporizadores de lwIP, enlace */
        esp_poll();                                       /* "ESP32": bytes del MSX, respuestas, pendientes */
        ota_poll();                                       /* actualizacion por red: descarga, grabacion, confirmacion */
        if (perfil_poll()) { last = 0U; mxpf_activo_otro(); }   /* prueba de perfiles: cargo otro bitstream por PCAP (de la DDR); el SDBOX vuelve a empezar en 0 */
        if (mxpf_poll()) last = 0U;                       /* ordenes por la zona (tools/perfiles.tcl): instalar, cargar, borrar... en la TF1 */
        box[13] = usb_stats_mount; box[14] = usb_stats_reports;
        seq = box[W_REQ_SEQ];
        if (seq != last) {
            sd_servir(seq);
        } else {
            yrw801_poll();                                /* sin peticion del PL pendiente: un tramo de 32 KB de la suma */
            u64 now = gt_now();
            tf1_poll(now);
            if (tf1_evento) { tf1_evento = 0U; perfiles_aviso_revisa(); }
            if (image_mode) {
            } else if (!present) {
                if (now - t_retry > (u64)(COUNTS_PER_SECOND / 2U)) {     /* sin tarjeta: reintentar init */
                    t_retry = now;
                    present = sd_try_init();
                    if (present) { log_str("tarjeta insertada: "); log_dec(card_mb); log_str(" MB\n"); dual_disco_tarjeta_cambio(); }   /* (Nextor-B ya no conoce esta tarjeta) */
                    else card_mb = 0;
                    publish_card();
                }
            } else if (now - t_retry > (u64)(COUNTS_PER_SECOND * 2U)) {  /* con tarjeta: ¿sigue ahi? (ACMD13) */
                u8 sdstat[64];
                t_retry = now;
                if (XSdPs_Get_Status(&sd, sdstat) != XST_SUCCESS) {
                    present = 0; card_mb = 0;
                    publish_card();
                    log_str("tarjeta retirada\n");
                    dual_disco_tarjeta_cambio();
                }
            }
            usleep(10);                                   /* con JTAG en halting-debug, WFI es un NOP en el A9:
                                                             espera con el timer (sin trafico en la DDR) */
        }
    }
    return 0;
}
