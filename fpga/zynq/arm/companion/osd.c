/* osd.c — pagina de informacion del sistema en el OSD del MSXimus (textdisp 32x28 de
 * iosys_bl616) hablando el protocolo BL616<->FPGA por la UART0 del PS (EMIO):
 *   0xAA len[15:8] len[7:0] cmd params...   len = 1 + n_params
 *   cmd 4 x y = cursor; cmd 5 <texto> = imprimir desde el cursor; cmd 8 b = overlay on/off
 * Con el overlay encendido el top congela el Z80 (iosys_frz): es una pausa con datos.
 * Se enciende/apaga con F12 del teclado USB (usb_host.c) o con MBOX+0x30 bit 0
 * (tools/osd.tcl). Mientras esta apagado se reenvia "overlay off" cada segundo: el PL
 * puede cargarse DESPUES que este programa (boot.tcl) y su overlay nace encendido.
 * Temperatura y tensiones: XADC por el interfaz del PS (devcfg 0xF8007100..), como
 * tools/temp.tcl. Estado del PL: la telemetria que dbg_mailbox_axi deja en MBOX+0x40.
 * Z1.2.2 (30/09/2026): con COLOR (textdisp_z.v: orden 0x10 = atributo {fondo, tinta} de lo que se imprime despues).
 * Tres paginas dibujadas en memoria: la de informacion (osd_info.c), la de la actualizacion por red (ota.c, con U) y la de
 * perfiles del PL en la TF1 (perfiles.c, con P); ESC vuelve. Solo se mandan las filas que cambian. */
#include "xil_types.h"
#include "sleep.h"
#include "log.h"
#include "oled.h"
#include "ota.h"
#include "osd.h"
#include "osd_info.h"
#include "perfiles.h"
#include "dual.h"
#include "yrw801.h"
#include "tr_bios.h"
#include "s3.h"
extern int  cfg_video43(void);                       /* qspi_cfg.c (rama beta) */
extern void cfg_video43_cambia(void);

#define REG(a)          (*(volatile u32 *)(a))
#define MBOX            0x1FF00000u
#define SDBOX           0x1FF00100u
#define OSD_CTRL        REG(MBOX + 0x30)             /* bit 0: OSD pedido desde xsdb */
#define OSD_STAT        REG(MBOX + 0x34)             /* [0] osd on, [31:16] temp en decimas de C */
#define OTA_KEY         REG(MBOX + 0x3C)             /* 30/09: tecla de la actualizacion desde xsdb (tools/ota.tcl) */

#define UART0           0xE0000000u
#define UART_CR         REG(UART0 + 0x00)
#define UART_MR         REG(UART0 + 0x04)
#define UART_BAUDGEN    REG(UART0 + 0x18)
#define UART_SR         REG(UART0 + 0x2C)
#define UART_FIFO       REG(UART0 + 0x30)
#define UART_BAUDDIV    REG(UART0 + 0x34)
#define SLCR_LOCK       REG(0xF8000004u)
#define SLCR_UNLOCK     REG(0xF8000008u)
#define IO_PLL_CTRL     REG(0xF8000108u)
#define APER_CLK_CTRL   REG(0xF800012Cu)
#define UART_CLK_CTRL   REG(0xF8000154u)
#define PS_CLK_HZ       33333333u

#define XADC_CFG        REG(0xF8007100u)
#define XADC_CMDF       REG(0xF8007110u)
#define XADC_RDF        REG(0xF8007114u)
#define XADC_MCTL       REG(0xF8007118u)

extern u64 gt_now(void);
extern void net_ip(u8 ip[4]);                        /* net.c: la IP (0.0.0.0 sin red) */
extern u32 usb_stats_mount, usb_stats_reports, usb_n_kbd, usb_n_mouse, usb_n_pad, usb_stats_reinicios;
extern volatile u32 osd_hotkey;                       /* usb_host.c: pulsaciones de F12 */
extern volatile u8  osd_teclas[16];                   /* usb_host.c: pulsaciones (uso HID), anillo */
extern volatile u32 osd_teclas_wr;

s32         osd_temp_dc;                              /* die en decimas de C; lo lee tambien oled.c */
static int  osd_on;
static u32  hotkey_seen, ctrl_seen;
static u32  teclas_rd;                                /* 30/09: teclas del OSD ya repartidas (ota.c) */
static u64  t_redraw;                                 /* refresco rapido (4 por segundo) cuando ota.c cambia */
static u64  t_next, t_start;                          /* t_start: el timer global no se resetea al recargar el programa */

/* ---------------- UART0 -> iosys ---------------- */
static void uart_init(void)
{
    u32 fdiv = (IO_PLL_CTRL >> 12) & 0x7Fu;
    u32 div  = (UART_CLK_CTRL >> 8) & 0x3Fu;
    u32 ref  = (u32)((u64)PS_CLK_HZ * fdiv / (div ? div : 1u));   /* 100 MHz con IO PLL 1800/18 */
    u32 cd   = (ref + 5000000u) / 10000000u;                       /* 2 Mbps = ref / (cd * (4+1)) */
    SLCR_UNLOCK = 0xDF0Du;
    UART_CLK_CTRL |= 1u;                                            /* CLKACT0 */
    APER_CLK_CTRL |= 1u << 20;                                      /* reloj AMBA de UART0 */
    SLCR_LOCK = 0x767Bu;
    UART_CR = 0x28u | 0x03u;                                        /* TX/RX off + reset de FIFOs */
    while (UART_CR & 0x03u) ;
    UART_MR = 0x20u;                                                /* 8N1, reloj de referencia */
    UART_BAUDGEN = cd ? cd : 10u; UART_BAUDDIV = 4u;
    UART_CR = 0x14u | 0x40u;                                        /* RXEN TXEN RSTTO */
    log_str("OSD: UART0 ref "); log_dec(ref / 1000000u); log_str(" MHz, CD "); log_dec(cd); log_str("\n");
}
static void uart_putc(u8 c) { while (UART_SR & (1u << 4)) ; UART_FIFO = c; }          /* TXFULL */
/* lo que manda el iosys: tramas 0xAA len[15:8] len[7:0] tipo datos. Z1.2.3: se lee la respuesta a la orden 14 (tipo 8,
 * 8 bytes de estado; el primero {3'b0, kana, mayusculas, ventilador, hay SD, turbo}: iosys_status de top_zynq.v) para
 * que la pagina de informacion diga si el turbo (F11) esta puesto. El resto (mandos cada 20 ms...) se descarta. */
static void iosys_frame(u8 cmd, const u8 *p, u16 n);
static u8  iosys_st[8];
static int iosys_st_ok;
static void uart_rx(void)
{
    static u8 fase, tipo;
    static u16 largo, n;
    static u8 buf[8];
    while (!(UART_SR & (1u << 1))) {                                /* RXEMPTY */
        u8 c = (u8)UART_FIFO;
        switch (fase) {
            case 0: if (c == 0xAAu) fase = 1; break;
            case 1: largo = (u16)(c << 8); fase = 2; break;
            case 2: largo |= c; fase = largo ? 3 : 0; break;
            case 3: tipo = c; n = 0; fase = (largo > 1u) ? 4 : 0; break;
            default:
                if (tipo == 8u && n < 8u) buf[n] = c;
                if (++n >= largo - 1u) {
                    if (tipo == 8u && n == 8u) { for (int i = 0; i < 8; i++) iosys_st[i] = buf[i]; iosys_st_ok = 1; }
                    fase = 0;
                }
                break;
        }
    }
}
static void iosys_pide_estado(void) { iosys_frame(14, 0, 0); }       /* respuesta en ~70 us: la recoge uart_rx() */
int osd_turbo(void) { return iosys_st_ok ? (iosys_st[0] & 1u) : 0; }   /* oled.c tambien */

static void iosys_frame(u8 cmd, const u8 *p, u16 n)
{
    u16 len = (u16)(n + 1u);
    uart_putc(0xAA); uart_putc((u8)(len >> 8)); uart_putc((u8)len); uart_putc(cmd);
    for (u16 i = 0; i < n; i++) uart_putc(p[i]);
}
static void osd_overlay(int on) { u8 b = on ? 1u : 0u; iosys_frame(8, &b, 1); }
/* ---------------- XADC ---------------- */
static void xadc_init(void)
{
    XADC_MCTL = 0x10u; XADC_MCTL = 0u;
    XADC_CFG  = 0x80001114u;                                        /* enable, TCKRATE /4, IGAP 20 */
}
static u16 xadc_rd(u32 addr)
{
    XADC_CMDF = (1u << 26) | (addr << 16);                          /* lectura DRP */
    usleep(20); (void)XADC_RDF;                                     /* respuesta del comando anterior */
    XADC_CMDF = 0u;                                                 /* NOP: empuja la respuesta */
    usleep(20);
    return (u16)(XADC_RDF & 0xFFFFu);
}
/* T(C) = code * 503.975 / 65536 - 273.15  ->  decimas de C */
static s32 xadc_temp_dc(u16 code) { return (s32)((u64)code * 503975u / 6553600u) - 2731; }
static u32 xadc_mv(u16 code)      { return (u32)((u64)code * 3000u / 65536u); }

/* ---------------- las paginas (Z1.2.2: con color) ---------------- */
/* Dos paginas: la de informacion (F12) y la de la actualizacion por red (U desde la de informacion; ESC vuelve).
 * Se dibujan en memoria (osd_info.c, ota.c con osd_dib.c) y se mandan al iosys solo las filas que han cambiado:
 * por fila, cursor al principio y tramos {orden 0x10 atributo, orden 5 texto}. Al encender el OSD se manda todo
 * (la BRAM del textdisp nace con el texto de demostracion del bitstream y hay que taparlo). */
enum { PAG_INFO = 0, PAG_OTA, PAG_PERF, PAG_DUAL };
static int pagina;
static osd_celda pag[OSD_FILAS][OSD_COLS], env[OSD_FILAS][OSD_COLS];
static int env_ok;

static void enviar_fila(int y)
{
    u8 xy[2] = { 0, (u8)y }, txt[OSD_COLS];
    int x = 0;
    iosys_frame(4, xy, 2);
    while (x < OSD_COLS) {
        u8 a = (u8)(pag[y][x] >> 8);
        u16 n = 0;
        while (x < OSD_COLS && (u8)(pag[y][x] >> 8) == a) txt[n++] = (u8)pag[y][x++];
        iosys_frame(0x10, &a, 1);                                    /* atributo del tramo (textdisp_z.v) */
        iosys_frame(5, txt, n);
    }
}

static void enviar(void)
{
    for (int y = 0; y < OSD_FILAS; y++) {
        int igual = env_ok;
        for (int x = 0; igual && x < OSD_COLS; x++) if (pag[y][x] != env[y][x]) igual = 0;
        if (igual) continue;
        enviar_fila(y);
        for (int x = 0; x < OSD_COLS; x++) env[y][x] = pag[y][x];
    }
    env_ok = 1;
}

static void osd_render(void)
{
    volatile u32 *sb  = (volatile u32 *)SDBOX;
    volatile u32 *tel = (volatile u32 *)(MBOX + 0x40);
    volatile u8  *z80 = (volatile u8 *)0x10800000u;                /* pagina 3 del Z80: DDR + (A - 0xC000) */
    s32 t = xadc_temp_dc(xadc_rd(0x00));
    osd_temp_dc = t;
    OSD_STAT = 1u | ((u32)(t & 0xFFFF) << 16);
    if (pagina == PAG_OTA) ota_pagina(pag);
    else if (pagina == PAG_PERF) perfiles_pagina(pag);
    else if (pagina == PAG_DUAL) dual_pagina(pag);                 /* perfil Dual (2/11): la maquina B */
    else {
        osd_info_t d;
        extern void usb_resumen(u32 *n_disp, u32 t[6]);
        d.version = ota_version();
        d.temp_dc = t; d.tmax_dc = xadc_temp_dc(xadc_rd(0x20));
        d.vint_mv = xadc_mv(xadc_rd(0x01)); d.vaux_mv = xadc_mv(xadc_rd(0x02)); d.vbram_mv = xadc_mv(xadc_rd(0x06));
        d.uptime_s = (u32)((gt_now() - t_start) / (u64)COUNTS_PER_SECOND);
        d.sd_mb = (sb[1] & 1u) ? sb[1] >> 16 : 0u; d.sd_err = sb[10];
        usb_resumen(&d.usb_disp, d.usb_tipo);
        d.usb_reinicios = usb_stats_reinicios;                      /* vigilante del EHCI (usb_host.c): solo se ensena si no es 0 */
        d.screen = z80[0xFCAF - 0xC000];
        d.turbo = iosys_st_ok ? (iosys_st[0] & 1u) : 0u;           /* estado del iosys (orden 14): turbo_eff */
        d.v9990 = (tel[8] >> 31) ? ((tel[8] >> 10) & 1u) + 1u : 0u;  /* +0x60 bit 31 (con ENABLE_V9990): el HDMI saca el V9990; bit 10: con el V9968 compuesto */
        net_ip(d.ip);
        d.wifi = 0;
        d.v43 = (u8)cfg_video43();
        if (!d.ip[0] && s3_ip(d.ip)) d.wifi = 1;                    /* rama beta: sin cable, la IP de la S3 (la ultima leida) */
        d.yrw801 = (u8)yrw801_estado();                             /* suma de los 2 MB de la ROM de ondas (yrw801.c) */
        d.tf1_aviso = (u8)perfiles_aviso_tf1();                      /* TF1 solo perfiles: tarjeta nueva sin preparar */
        d.dual = (u8)dual_activo();                                 /* perfil Dual: la tecla B abre la pagina de la maquina B */
        d.tr = (u8)((tel[33] >> 2) & 1u);
        d.tr_v99 = (u8)((tel[33] >> 8) & 1u);                       /* perfil TRV: el TR con V9990 */                           /* perfil TR: +0xC4 bit 2 (tel = MBOX + 0x40) */
        d.tr_bios = (u8)tr_bios_estado();                           /* perfil TR (fase 2): la BIOS del turbo R de la TF2 (tr_bios.c) */
        osd_pagina_info(pag, &d);
    }
    osd_overlay(1);
    enviar();
}

/* reparto de las teclas con el OSD abierto: U abre la pagina de la actualizacion, P la de perfiles, ESC vuelve; el resto a la pagina */
static void tecla(u8 u)
{
    if (pagina == PAG_INFO) {
        if (u == 0x18u) { pagina = PAG_OTA; ota_tecla(u); }
        else if (u == 0x13u) { pagina = PAG_PERF; perfiles_abre(); }  /* P: perfiles del PL en la TF1 */
        else if (u == 0x19u) cfg_video43_cambia();                 /* V (rama beta): el V9968 a pantalla completa, 16:9 / 4:3 Scale3x */
        else if (u == 0x05u && dual_activo()) { pagina = PAG_DUAL; dual_abre(); }   /* B (perfil Dual): la maquina B */
    } else if (pagina == PAG_DUAL) {
        if (u == 0x29u) pagina = PAG_INFO;                          /* ESC */
        else dual_tecla(u);
    } else if (pagina == PAG_PERF) {
        if (u == 0x29u && !perfiles_armado()) pagina = PAG_INFO;    /* ESC: cancela lo armado; sin nada armado, vuelve */
        else perfiles_tecla(u);
    } else if (u == 0x29u) pagina = PAG_INFO;                       /* ESC */
    else if (u == 0x13u) { pagina = PAG_PERF; perfiles_abre_servidor(); }   /* P (31/10): los perfiles del servidor (tras instalar un BOOT.bin los de la tarjeta quedan viejos) */
    else ota_tecla(u);
}

/* dual.c (2/11): enciende el OSD en la pagina de la maquina B tal como esta (un aviso: la ROM que el menu manda a B no cabe, el mapper no vale...) */
void osd_abre_dual(void)
{
    if (!osd_on) { osd_on = 1; env_ok = 0; }
    pagina = PAG_DUAL;
}

/* perfiles.c (31/10): enciende el OSD en la pagina de perfiles tal como esta (un aviso: perfil instalado desde la TF2, perfil cargado
 * por la etiqueta de una ROM...). El Z80 queda congelado por el overlay hasta que se cierra con F12 o ESC. */
void osd_abre_perfiles(void)
{
    if (!osd_on) { osd_on = 1; env_ok = 0; }
    pagina = PAG_PERF;
}

/* ota.c (31/10): un perfil bajado va a instalarse y eso ocupa el bucle ~1 s: con el panel abierto el Z80 esta congelado, con "Ocultar (sigue)"
 * no. Si ya se esta mirando la pagina de perfiles se deja como esta. */
void osd_abre_servidor(void)
{
    if (osd_on && pagina == PAG_PERF) return;
    if (!osd_on) { osd_on = 1; env_ok = 0; }
    pagina = PAG_PERF;
    perfiles_abre_servidor();
    osd_render();                                                  /* ya: el overlay congela el Z80 ahora, no en la proxima vuelta */
}

/* perfiles.c: dibujar y mandar la pagina ya, para poner un aviso antes de una operacion larga que no deja repintar */
void osd_repinta(void)
{
    if (osd_on) osd_render();
}

/* ---------------- API ---------------- */
u32 osd_uptime_s(void) { return (u32)((gt_now() - t_start) / (u64)COUNTS_PER_SECOND); }   /* v99desk.c (rama beta) */

void osd_init(void)
{
    uart_init();
    xadc_init();
    oled_init();                                       /* OLED de la placa (J4): estado permanente */
    osd_on = 0; hotkey_seen = osd_hotkey; ctrl_seen = OSD_CTRL & 1u;
    OSD_STAT = 0u;
    OTA_KEY = 0u;                                      /* por si el buzon trae basura (arranque por JTAG) */
    osd_overlay(0);
    t_start = gt_now();
    t_next = t_start;
}

void osd_pl_rearma(void)                           /* profile.c (PCAP, 30/10): el PL nuevo no sabe nada del OSD ni de la OLED */
{
    uart_init();                                       /* FIFOs a cero: con el PL en blanco el RX de la EMIO llego con basura */
    oled_init();
    osd_on = 0; env_ok = 0; pagina = PAG_INFO;
    hotkey_seen = osd_hotkey; ctrl_seen = OSD_CTRL & 1u; teclas_rd = osd_teclas_wr;
    OSD_STAT = 0u;
    iosys_st_ok = 0;
    osd_overlay(0);
    t_next = gt_now();                                 /* t_start (el tiempo encendida) no se toca */
}

void osd_poll(void)
{
    static int pendiente;
    u64 now = gt_now();
    u32 c = OSD_CTRL & 1u;
    int changed = 0;
    uart_rx();                                                      /* respuestas del iosys (y los mandos, que se tiran) */
    if (osd_hotkey != hotkey_seen) { hotkey_seen = osd_hotkey; osd_on = !osd_on; changed = 1; }
    if (c != ctrl_seen)            { ctrl_seen = c; osd_on = (int)c; changed = 1; }
    if (changed) {
        log_str(osd_on ? "OSD on\n" : "OSD off\n");
        env_ok = 0;                                                 /* al abrir, todo de nuevo */
        pagina = ota_ocupada() ? PAG_OTA : PAG_INFO;
        if (ota_perfil_en_curso()) { pagina = PAG_PERF; perfiles_abre_servidor(); }   /* bajando un perfil: su progreso esta en la vista del servidor */
    }
    if (OTA_KEY) {                                                  /* tools/ota.tcl: abre el OSD si hace falta */
        u8 k = (u8)OTA_KEY;
        OTA_KEY = 0u;
        if (!osd_on) { osd_on = 1; env_ok = 0; pagina = PAG_INFO; }
        tecla(k); changed = 1;
    }
    if (osd_on) {
        while (osd_on && teclas_rd != osd_teclas_wr) {
            u32 antes = teclas_rd;
            tecla(osd_teclas[antes & 15u]);
            if (teclas_rd == antes) teclas_rd++;                    /* perfiles.c: cargar un perfil rearma el OSD (osd_pl_rearma) y lo deja al dia */
            changed = 1;
        }
        if (pagina == PAG_OTA && ota_cambio()) changed = 1;
        if (pagina == PAG_PERF && perfiles_cambio()) changed = 1;
        if (pagina == PAG_DUAL && dual_cambio()) changed = 1;
    } else teclas_rd = osd_teclas_wr;                               /* con el OSD cerrado las teclas son del MSX */
    if (changed || now >= t_next) pendiente = 1;
    if (!pendiente) return;
    if (osd_on && env_ok && now < t_redraw) return;                 /* 4 repintados por segundo como mucho */
    pendiente = 0;
    t_next = now + (u64)COUNTS_PER_SECOND;
    t_redraw = now + (u64)COUNTS_PER_SECOND / 4u;
    iosys_pide_estado(); usleep(200); uart_rx();                    /* turbo al dia para la pagina y el OLED */
    if (osd_on) osd_render();
    else { osd_overlay(0); osd_temp_dc = xadc_temp_dc(xadc_rd(0x00)); OSD_STAT = (u32)(osd_temp_dc & 0xFFFF) << 16; }
    oled_tick();                                                    /* el OLED se refresca con el OSD encendido o apagado */
}
