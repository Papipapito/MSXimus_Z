/* v99desk.c — el escritorio vivo (rama beta, 30/10/2026): el companion pinta en el V9990 mientras el Z80 juega en el
 * V9968 dentro de la ventana (teclas V y B del menu).
 *
 * El menu pinta un escritorio provisional (bios/src/v9991.asm: B5 o B7 a 4 bpp, lineas de 512 B), lanza la ROM y
 * avisa por el puerto 93h con "V5" o "V7" y el nombre de la ROM. Desde ahi el V9990 es del companion (el juego no lo
 * usa) y aqui se repinta entero con un aspecto moderno: paleta propia (oscura, acento cian), fondo en degradado, una
 * barra arriba con el nombre de la maquina, la version y la hora, y dos tarjetas con sombra: "Jugando" (la ROM) y
 * "Sistema" (red, temperatura, tiempo encendido, USB). Solo se redibujan los caracteres que cambian.
 *
 * Perfil Dual (2/11/2026): el "V","D" del menu (Shift+D) y el "V","A" (D sola, b8) pintan el escritorio de DOS COLUMNAS (layout 9): A a la izquierda (el gestor de ventanas
 * por hardware, a x0,5), B a la derecha (su imagen la pone el PL en el frame buffer del V9990; aqui se pinta su marco, su barra de titulo con
 * "MSX - B" y el nombre del juego, y los botones) y las tarjetas en la franja de abajo. dual.c lee el puntero del PL y llama a
 * v99desk_dual_pon para mover el marco y cambiar el foco. Z1.3.2b8: el "V","A" del menu (tecla D sola) es el mismo escritorio con el juego en A
 * ("JUGANDO" con la ROM de A) y B de segunda maquina (su barra dice "MSX - B  BASIC" o lo que corra); el cuadradito cian de la barra de B es el
 * silencio de su sonido (gris y hueco si esta en silencio) y la tarjeta de la izquierda lleva la linea "Sonido  A: si  B: no" (v99desk_dual_silencio).
 * Z1.3.2b9: y la linea "SD: escribe B" / "SD: escribe A", la maquina que tiene la SD de TF2 (v99desk_dual_sd).
 *
 * La hora: la de la red (SNTP por cable, o la que da la S3 por WiFi al empezar el escritorio). Con ella el companion
 * pinta su reloj y apaga el del gestor de ventanas (R#55 bit 0); sin ella se queda el reloj del hardware (el RTC del
 * MSX), que el gestor pinta en el mismo sitio de la barra.
 *
 * Camino: las escrituras a los puertos del V9990 van a un anillo en la DDR (V9_RING, 16384 entradas de 16 bits) y el PL
 * (dbg_mailbox_axi + v9990_arm_port) las ejecuta cuando el Z80 no usa el V9990, y solo con el compositor en el modo
 * ventana con el gestor activo: tras un reset del MSX el V9990 se reinicia, el modo ventana se va y lo que quede en el
 * anillo espera; el "V5"/"V7" siguiente lo vacia y repinta. Entrada: [15:14] tipo (0 escribir, 1 NOP, 2 esperar
 * hasta (P & m) == 0, 3 esperar hasta (P & m) != 0), [11:8] puerto P#0..P#15, [7:0] dato o mascara. El PL trae el
 * anillo en rafagas de 64 entradas: cada tanda se rellena con NOP hasta un multiplo de 64.
 * Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later. */
#include "xil_types.h"
#include "sleep.h"
#include "log.h"
#include "ota.h"
#include "osd.h"
#include "s3.h"

#ifdef V99_HOST
#define DSB() ((void)0)
#else
#define DSB() __asm__ volatile ("dsb" ::: "memory")
#endif

#define V9_N        16384U
#ifdef V99_HOST                                               /* banco en el PC (tb_v99desk/): el anillo en memoria */
extern volatile u32 host_ctl, host_tel;
extern volatile u16 host_ring[V9_N];
#define V9_CTL      host_ctl
#define V9_RING     host_ring
#define TEL_V9      host_tel
#else
#define V9_BASE     0x1FFB0000U
#define V9_CTL      (*(volatile u32 *)V9_BASE)                 /* {en[31], wr[15:0]} */
#define V9_RING     ((volatile u16 *)(V9_BASE + 0x8000U))
#define MBOX        0x1FF00000U
#define TEL_V9      (*(volatile u32 *)(MBOX + 0xC4U))           /* PL: {rd[31:16], ...} (dbg_mailbox_axi) */
#endif
#define PL_TR       (((TEL_V9 >> 2) & 1U) && !((TEL_V9 >> 8) & 1U))                       /* +0xC4 bit 2: el PL es el perfil TR (sin V9990, dbg_mailbox_axi.v): no hay a quien pintar */

#define E_WR(p, d)   ((u16)((((p) & 15U) << 8) | ((d) & 0xFFU)))
#define E_NOP        ((u16)0x4000U)
#define E_W0(p, m)   ((u16)(0x8000U | (((p) & 15U) << 8) | ((m) & 0xFFU)))

extern u64  gt_now(void);
extern void net_ip(u8 ip[4]);
extern int  esp_net_ok(void);
extern void epoch_to_dt(u32 t, u8 *o);
extern u32  usb_n_kbd, usb_n_mouse, usb_n_pad;
extern s32  osd_temp_dc;
extern int  osd_turbo(void);                                 /* osd.c: el turbo del iosys (5,37 MHz) */
extern void dual_escritorio(u8 lay);                         /* dual.c: perfil Dual, al empezar un escritorio (9 = dos columnas con la ROM en B, 10 = con la ROM en A y B de segunda maquina) */
extern const char *dual_b_etiqueta(void);                    /* dual.c: lo que corre en B para la barra de su ventana ("BASIC" o el nombre del cartucho) */
extern void dual_marco_listo(u16 x, u16 y);                  /* dual.c: el marco de B esta en (x, y) en la tanda que se acaba de publicar */
u32 osd_uptime_s(void);

/* ---- la paleta (5 bits por canal; la entrada 0 es la transparente del menu) ---------------------------------------- */
enum { P_FONDO0 = 1, P_FONDO1, P_FONDO2, P_FONDO3, P_BARRA, P_TARJ, P_CABE, P_ACENTO, P_NARANJA, P_TEXTO, P_TENUE,
       P_VERDE, P_ROJO, P_SOMBRA, P_CLARO };
static const u8 paleta[16][3] = {
    { 0x80, 0, 0 },                                           /* 0: negro transparente (YS), como el menu */
    { 2, 3, 7 }, { 3, 4, 9 }, { 4, 5, 11 }, { 5, 6, 13 },     /* 1-4: el degradado del fondo, de arriba abajo */
    { 1, 2, 4 },                                              /* 5: la barra (= C_BAR del gestor de ventanas, 081020) */
    { 5, 7, 11 },                                             /* 6: tarjeta (= 293A5A) */
    { 8, 10, 16 },                                            /* 7: cabecera (= 425284) */
    { 3, 22, 28 },                                            /* 8: acento cian (= 19B5E6) */
    { 31, 17, 3 },                                            /* 9: naranja */
    { 29, 30, 31 },                                           /* 10: texto (= EEF6FF) */
    { 17, 19, 23 },                                           /* 11: texto tenue (= 8C9CBD) */
    { 6, 25, 12 },                                            /* 12: verde */
    { 29, 7, 7 },                                             /* 13: rojo */
    { 0, 1, 2 },                                              /* 14: sombra */
    { 11, 13, 19 },                                           /* 15: biselado claro (= 5A6E9C, el del gestor de ventanas; solo el layout 9) */
};

/* ---- el anillo ------------------------------------------------------------------------------------------------- */
static u16 wr;                                                /* entradas escritas (mod 65536) */
static u16 pend[8192];                                        /* una tanda */
static u32 npend;
static u8  lleno;                                             /* la tanda se lleno: queda trabajo para la siguiente */
static void q(u16 e) { if (npend < sizeof pend / sizeof pend[0]) pend[npend++] = e; }
static int  q_hay(u32 n) { if (npend + n > sizeof pend / sizeof pend[0]) { lleno = 1; return 0; } return 1; }
static void reg(u8 r, u8 v) { q(E_WR(4, r)); q(E_WR(3, v)); }   /* P#4 = numero de registro, P#3 = dato */

static int publicar(void)                                     /* 0 si el PL va atrasado (se reintenta) */
{
    u32 n = (npend + 63U) & ~63U, i;
    u16 rd = (u16)(TEL_V9 >> 16);
    if (!n) return 1;
    if ((u32)(u16)(wr - rd) + n > V9_N - 64U) return 0;
    for (i = 0; i < n; i++) V9_RING[(u16)(wr + i) & (V9_N - 1U)] = i < npend ? pend[i] : E_NOP;
    DSB();
    wr = (u16)(wr + n);
    V9_CTL = (1U << 31) | wr;
    DSB();
    npend = 0;
    return 1;
}

/* ---- dibujo --------------------------------------------------------------------------------------------------- */
static void rect2(u16 x, u16 y, u16 w, u16 h, u8 cc);
static void rect(u16 x, u16 y, u16 w, u16 h, u8 c) { rect2(x, y, w, h, (u8)((c << 4) | c)); }   /* LMMV, c = color de 4 bits */
static void rect2(u16 x, u16 y, u16 w, u16 h, u8 cc)          /* cc = dos puntos: con dos colores, un tramado de rayas */
{
    if (!w || !h) return;
    q(E_W0(5, 0x01));                                         /* motor libre */
    reg(36, (u8)x); reg(37, (u8)(x >> 8)); reg(38, (u8)y); reg(39, (u8)(y >> 8));
    reg(40, (u8)w); reg(41, (u8)(w >> 8)); reg(42, (u8)h); reg(43, (u8)(h >> 8));
    reg(44, 0x00); reg(45, 0x0C); reg(46, 0xFF); reg(47, 0xFF); reg(48, cc); reg(49, cc);
    reg(52, 0x20);
    q(E_W0(5, 0x01));
}

#include "v99font.h"                                          /* filas, bit 7 = pixel izquierdo, ASCII 32..126 */

/* un caracter en (x, y) puntos (x par), escala sx (1 o 2) en horizontal y sy en vertical; por VRAM (P#0) */
static void car(u16 x, u16 y, char ch, u8 fg, u8 bg, u8 sx, u8 sy)
{
    const u8 *g = v99font[(ch < 32 || ch > 126) ? 0 : ch - 32];
    for (u32 f = 0; f < 8U * sy; f++) {
        u32 a = (u32)(y + f) * 512U + (u32)(x >> 1);
        u8 b = g[f / sy];
        reg(0, (u8)a); reg(1, (u8)(a >> 8)); reg(2, (u8)((a >> 16) & 0x07));   /* bit 7 = 0: autoincremento */
        if (sx == 1) {
            for (u32 k = 0; k < 4U; k++, b = (u8)(b << 2))
                q(E_WR(0, (u8)((((b & 0x80U) ? fg : bg) << 4) | ((b & 0x40U) ? fg : bg))));
        } else {
            for (u32 k = 0; k < 8U; k++, b = (u8)(b << 1)) { u8 c = (b & 0x80U) ? fg : bg; q(E_WR(0, (u8)((c << 4) | c))); }
        }
    }
}

/* ---- campos de texto: lo pintado se recuerda y solo cambia lo distinto ------------------------------------------ */
#define LMAX 26
typedef struct { u16 x, y; u8 sx, sy, fg, bg, len; char vis[LMAX]; } campo_t;
enum { K_TITULO, K_VER, K_FECHA, K_HORA, K_CAB_A, K_ROM, K_PISTA, K_CAB_B, K_RED, K_TEMP, K_ENC, K_CPU, K_USB, K_AYUDA, K_SONIDO, K_SD, K_N };
static campo_t k[K_N];

static void campo(campo_t *c, u16 x, u16 y, u8 sx, u8 sy, u8 fg, u8 bg, u8 len)
{
    c->x = x; c->y = y; c->sx = sx; c->sy = sy; c->fg = fg; c->bg = bg; c->len = len > LMAX ? LMAX : len;
    for (u32 i = 0; i < LMAX; i++) c->vis[i] = 0;
}

static int tapado(u16 x, u16 y, u16 w, u16 h);                /* perfil Dual (layout 9): la celda cae bajo el marco de B; mas abajo */
static void pon_campo(campo_t *c, const char *s)
{
    u32 coste = 8U * c->sy * (6U + 4U * c->sx);
    int fin = 0;
    for (u32 i = 0; i < c->len; i++) {
        char ch;
        if (!fin && s[i]) ch = s[i]; else { fin = 1; ch = ' '; }
        if (c->vis[i] == ch) continue;
        if (tapado((u16)(c->x + i * 8U * c->sx), c->y, (u16)(8U * c->sx), (u16)(8U * c->sy))) { c->vis[i] = ch; continue; }
        if (!q_hay(coste)) return;
        car((u16)(c->x + i * 8U * c->sx), c->y, ch, c->fg, c->bg, c->sx, c->sy);
        c->vis[i] = ch;
    }
}

/* ---- el estado ------------------------------------------------------------------------------------------------- */
static u8  activo, layout, todo, r55;
#define ANCHO   (layout == 7 || layout == 9)                  /* tarjetas de 24 caracteres (B7 y las dos columnas) en vez de las estrechas de 19 (B5) */
static u8  reloj_red;                                         /* 1 = el companion pinta la hora (R#55 bit 0 puesto) */
static char rom[25];
static u64 t_next;
/* sin cable, por la S3 (una vez por escritorio; si no hay hora, se reintenta cada minuto, tres veces) */
static u32 s3_utc;                                            /* segundos UTC desde 1970 cuando llego (0 = no hay) */
static u64 s3_g;                                              /* gt_now() de ese momento */
static u8  s3_fase, s3_intentos, s3_udp, s3_estado;
static const char *s3_diag;                                   /* en que se quedo la S3 (la linea de red del panel) */
static u64 s3_t0, s3_tf;
static u8  ntp_ip[4];

static char *pon(char *p, const char *s) { while (*s) *p++ = *s++; *p = 0; return p; }
static char *num(char *p, u32 v) { char t[10]; int n = 0; do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v); while (n) *p++ = t[--n]; *p = 0; return p; }
static char *dos(char *p, u32 v) { *p++ = (char)('0' + (v / 10U) % 10U); *p++ = (char)('0' + v % 10U); *p = 0; return p; }
static char *ip_txt(char *p, const u8 *ip) { p = num(p, ip[0]); *p++ = '.'; p = num(p, ip[1]); *p++ = '.'; p = num(p, ip[2]); *p++ = '.'; return num(p, ip[3]); }

static u32 dias_desde_civil(int y, unsigned m, unsigned d)   /* dias desde 1970-01-01 (days_from_civil) */
{
    y -= m <= 2U;
    int era = (y >= 0 ? y : y - 399) / 400;
    unsigned yoe = (unsigned)(y - era * 400), doy = (153U * (m > 2U ? m - 3U : m + 9U) + 2U) / 5U + d - 1U;
    unsigned doe = yoe * 365U + yoe / 4U - yoe / 100U + doy;
    return (u32)(era * 146097 + (int)doe - 719468);
}

extern int esp_hora_utc(u32 *t);
extern int esp_gmt_horas(void);
static u32 dia_semana(u32 d) { return (d + 4U) % 7U; }        /* 0 = domingo (1970-01-01 fue jueves) */
static u32 local_de_utc(u32 utc)                              /* la zona del driver y, en Europa (UTC+0..+2), el horario de verano */
{
    int g = esp_gmt_horas();
    u32 t = utc + (u32)(g * 3600);
    if (g >= 0 && g <= 2) {
        u8 dt[7];
        int y;
        u32 m, o;
        epoch_to_dt(utc, dt);
        y = dt[5] | (dt[6] << 8);
        m = dias_desde_civil(y, 3, 31); m -= dia_semana(m);   /* ultimo domingo de marzo y de octubre, 01:00 UTC */
        o = dias_desde_civil(y, 10, 31); o -= dia_semana(o);
        if (utc >= m * 86400U + 3600U && utc < o * 86400U + 3600U) t += 3600U;
    }
    return t;
}

static int hora_local(u32 *t)                                  /* segundos locales desde 1970, 0 si no hay hora de red */
{
    u32 u;
    if (esp_hora_utc(&u)) { *t = local_de_utc(u); return 1; }
    if (s3_utc) { *t = local_de_utc(s3_utc + (u32)((gt_now() - s3_g) / (u64)COUNTS_PER_SECOND)); return 1; }
    return 0;
}

/* la S3 sin bloquear, como la actualizacion (ota.c, busca_s3): estado, un DNS que despierta la radio, la IP y la hora por
 * NTP (UDP a pool.ntp.org por la propia S3); si el NTP no contesta, el reloj de la S3 ('G', en su hora local) */
enum { S_NADA, S_TOMA, S_LISTA, S_ESTADO, S_DNS, S_NTP, S_RELOJ, S_FIN };
#define SEG(n) ((u64)(n) * (u64)COUNTS_PER_SECOND)

static void s3_cierra(const char *por, const char *diag)
{
    s3_diag = diag;
    if (s3_udp) { s3_udp_cierra(s3_udp); s3_udp = 0; }
    s3_suelta(); s3_fase = S_FIN; s3_tf = gt_now();
    log_str("v99desk: S3 "); log_str(por); log_str(s3_utc ? ", con hora\n" : ", sin hora\n");
}

static void s3_poll(void)
{
    u64 now = gt_now();
    int r;
    switch (s3_fase) {
    case S_TOMA:
        if (esp_net_ok() || ota_ocupada()) { s3_fase = S_FIN; s3_tf = now; return; }
        if (s3_tomada()) { s3_diag = T("WiFi: S3 ocupada", "WiFi: S3 busy"); return; }   /* otro la tiene: se espera */
        s3_toma(); s3_t0 = now; s3_fase = S_LISTA;
        s3_diag = T("WiFi: esperando la S3", "WiFi: waiting S3");
        return;
    case S_LISTA:
        if (now - s3_t0 > SEG(8)) { s3_cierra("no contesta", T("WiFi: la S3 no contesta", "WiFi: S3 silent")); return; }
        if (!s3_lista()) return;
        (void)s3_pide(3, 0, 0, 1500U);                        /* estado de la red */
        s3_fase = S_ESTADO;
        return;
    case S_ESTADO:
        if ((r = s3_resp()) == 0) return;
        if (r < 0) { s3_cierra("sin estado", T("WiFi: sin estado", "WiFi: no status")); return; }
        s3_estado = s3r.n ? s3r.d[0] : 0U;                    /* 2 conectada, 1 conectando, 0 radio parada o sin red */
        s3_diag = T("WiFi: consultando", "WiFi: asking");
        (void)s3_pide(6, (const u8 *)"pool.ntp.org", 12, 4000U);   /* el DNS despierta la radio */
        s3_fase = S_DNS;
        return;
    case S_DNS:
        if ((r = s3_resp()) == 0) return;
        if (r > 0 && s3r.err == 0U && s3r.n >= 4U) { ntp_ip[0] = s3r.d[0]; ntp_ip[1] = s3r.d[1]; ntp_ip[2] = s3r.d[2]; ntp_ip[3] = s3r.d[3]; }
        else ntp_ip[0] = 0;
        s3_ip_lee();
        if (!ntp_ip[0]) { s3_cierra("sin DNS", s3_estado == 2U ? T("WiFi: sin DNS", "WiFi: no DNS")
                                                              : s3_estado == 1U ? T("WiFi: conectando (1)", "WiFi: connecting (1)")
                                                                                : T("WiFi: parada (0)", "WiFi: off (0)")); return; }                                          /* la IP de la S3 (ya despierta) para el panel */
        if (ntp_ip[0] && (s3_udp = s3_udp_abre()) != 0) {
            u8 q[48] = { 0x1B };                              /* NTP v3, cliente */
            if (s3_udp_manda(s3_udp, ntp_ip, 123, q, 48) == 1) { s3_t0 = now; s3_fase = S_NTP; return; }
        }
        (void)s3_pide('G', 0, 0, 1500U); s3_fase = S_RELOJ;
        return;
    case S_NTP: {
        u8 d[48], ip[4];
        int n = s3_udp_lee(s3_udp, d, sizeof d, ip);
        if (n >= 44) {
            u32 ntp = ((u32)d[40] << 24) | ((u32)d[41] << 16) | ((u32)d[42] << 8) | d[43];
            if (ntp > 2208988800U + 1577836800U) { s3_utc = ntp - 2208988800U; s3_g = gt_now(); }   /* despues de 2020 */
            { u8 x[4]; if (!s3_ip(x)) s3_ip_lee(); }               /* con el NTP contestado la WiFi ya esta: la IP si falto antes */
            s3_cierra("NTP", s3_utc ? 0 : T("WiFi: NTP raro", "WiFi: bad NTP"));
            return;
        }
        if (n < 0 || now - s3_t0 > SEG(2)) { s3_udp_cierra(s3_udp); s3_udp = 0; (void)s3_pide('G', 0, 0, 1500U); s3_fase = S_RELOJ; }
        return;
    }
    case S_RELOJ:
        if ((r = s3_resp()) == 0) return;
        if (r > 0 && s3r.err == 0U && s3r.n >= 7U && (s3r.d[5] | (s3r.d[6] << 8)) >= 2020U) {   /* s, m, h, dia, mes, anio: local */
            u32 d = dias_desde_civil((int)(s3r.d[5] | (s3r.d[6] << 8)), s3r.d[4], s3r.d[3]);
            u32 loc = d * 86400U + s3r.d[2] * 3600U + s3r.d[1] * 60U + s3r.d[0];
            s3_utc = loc - (u32)(esp_gmt_horas() * 3600);    /* la zona; si local_de_utc pone el verano, se quita */
            if (local_de_utc(s3_utc) != loc) s3_utc -= 3600U;
            s3_g = gt_now();
        }
        s3_cierra("reloj", s3_utc ? 0 : T("WiFi: sin hora", "WiFi: no time"));
        return;
    case S_FIN:
        if (!esp_net_ok() && (!s3_utc || !s3_ip(ntp_ip)) && s3_intentos < 8U && now - s3_tf > SEG(15)) { s3_intentos++; s3_fase = S_TOMA; }
        return;
    default:
        return;
    }
}

/* ---- el escritorio ------------------------------------------------------------------------------------------------- */
static void tarjeta(u16 x, u16 y, u16 w, u16 h, u16 cab)      /* sombra, cuerpo, cabecera y franja de acento */
{
    rect((u16)(x + 3), (u16)(y + 2), w, h, P_SOMBRA);
    rect(x, y, w, h, P_TARJ);
    rect(x, y, w, cab, P_CABE);
    rect(x, y, 2, h, P_ACENTO);
}

/* ---- perfil Dual: el marco de la ventana de B (layout 9) -------------------------------------------------------------------------------- */
/* La imagen de B (256 x 212 puntos del frame buffer del V9990) la escribe el PL donde dice dual.c; el marco se pinta aqui, en la VRAM, alrededor:
 * 2 puntos a cada lado (4 px), 16 filas arriba (la barra de 24 px) y 3 abajo, con el aspecto del marco de A (el gestor de ventanas): contorno,
 * biselado claro/oscuro, barra azul si tiene el foco (si no, del color del cuerpo), "MSX - B" y el nombre del juego, y dos botones de adorno. Al
 * moverla se pinta el degradado del fondo donde ya no esta el marco y se repinta el marco; la imagen de B no se toca (no es de la VRAM). */
#define BW      256U
#define BH      212U
#define MB_L    2U
#define MB_T    16U
#define MB_B    3U
#define FW      (BW + 2U * MB_L)
#define FH      (BH + MB_T + MB_B)
static u16 bf_x, bf_y, bn_x, bn_y;                            /* esquina de la imagen de B: pintada / pedida */
static u8  bf_foco, bn_foco, bf_arr, bn_arr, bf_hay, tocado;  /* foco (1 = B), arrastrando, hay marco pintado, el marco paso por las tarjetas */
static u8  a_juega;                                           /* "V","A" (D sola): el juego es el de A y B es la segunda maquina; con "V","D" (Shift+D) el juego esta en B */
static u8  bn_sd;                                             /* la duena de la SD de TF2 (0 = A, 1 = B) */
static u8  bn_sa, bn_sb, bn_corre = 1, bf_sb;                 /* sonido: A y B en silencio (pedido), B corre; el silencio de B tal como esta pintado en su marco */
static u8  marco_falta;                                       /* tras repintar el escritorio entero el marco se pinta el ultimo (cuando ya no queda texto por poner) */
static u8  marco_pub;                                         /* el marco de (bf_x, bf_y) esta en una tanda aun sin publicar: al publicarla, dual.c mueve la imagen de B (dual_marco_listo) */
static int tapado(u16 x, u16 y, u16 w, u16 h)                /* la celda [x, x+w) x [y, y+h) cae bajo el marco de B: no se pinta (no se repintan los textos de las tarjetas encima) */
{
    int fx = (int)bf_x - (int)MB_L, fy = (int)bf_y - (int)MB_T;
    return layout == 9 && bf_hay && (int)x < fx + (int)FW && (int)x + (int)w > fx && (int)y < fy + (int)FH && (int)y + (int)h > fy;
}

static void marco_dibuja(u16 x, u16 y, u8 foco, u8 agujero, u8 sil)
{
    u16 fx = (u16)(x - MB_L), fy = (u16)(y - MB_T);
    u8 barra = foco ? P_CABE : P_TARJ;
    const char *lab = a_juega ? dual_b_etiqueta() : rom;            /* con el juego en A, B dice lo que corre (BASIC); si no, el nombre del juego que le mando el menu */
    char t[40], *p;
    u32 i;
    rect(fx, fy, FW, 1, P_SOMBRA);                                      /* contorno de arriba */
    rect((u16)(fx + 1), (u16)(fy + 1), (u16)(FW - 2), 1, P_CLARO);      /* biselado claro de arriba */
    rect(fx, (u16)(fy + 1), 1, (u16)(FH - 1), P_SOMBRA);                /* contorno de la izquierda (con la esquina de abajo) */
    rect((u16)(fx + 1), (u16)(fy + 2), 1, (u16)(FH - 4), P_CLARO);      /* biselado claro de la izquierda */
    rect((u16)(fx + FW - 2), (u16)(fy + 2), 1, (u16)(FH - 3), P_BARRA); /* biselado oscuro de la derecha */
    rect((u16)(fx + FW - 1), (u16)(fy + 1), 1, (u16)(FH - 1), P_SOMBRA);   /* contorno de la derecha */
    rect((u16)(fx + 1), (u16)(fy + FH - 2), (u16)(FW - 2), 1, P_BARRA); /* biselado oscuro de abajo */
    rect((u16)(fx + 1), (u16)(fy + FH - 1), (u16)(FW - 1), 1, P_SOMBRA);   /* contorno de abajo */
    rect((u16)(fx + MB_L), (u16)(fy + 2), BW, 12, barra);               /* la barra de titulo */
    rect((u16)(fx + MB_L), (u16)(fy + 14), BW, 2, P_TARJ);              /* el cuerpo bajo la barra */
    rect((u16)(fx + MB_L), (u16)(fy + FH - 3), BW, 1, P_TARJ);          /* y bajo la imagen */
    rect((u16)(fx + FW - 14), (u16)(fy + 4), 8, 8, P_ROJO);             /* botones de adorno, como los de A */
    if (sil) {                                                          /* el cuadradito cian es el sonido de B: en silencio, gris y hueco */
        rect((u16)(fx + FW - 24), (u16)(fy + 4), 8, 8, P_TENUE);
        rect((u16)(fx + FW - 22), (u16)(fy + 6), 4, 4, barra);
    } else rect((u16)(fx + FW - 24), (u16)(fy + 4), 8, 8, P_ACENTO);
    if (agujero) rect(x, y, BW, BH, P_SOMBRA);                          /* la imagen de B: si B no corre, el escritorio la deja negra */
    p = pon(t, "MSX - B  ");
    for (i = 0; i < 18U && lab[i]; i++) *p++ = lab[i];
    *p = 0;
    for (i = 0; t[i]; i++) car((u16)((((u32)fx + 6U) & ~1U) + 8U * i), (u16)(fy + 4), t[i], P_TEXTO, barra, 1, 1);
}

/* el degradado de fondo (el de fondo()) en el rectangulo [x0, x1) x [y0, y1) de puntos, sin salirse de debajo de la barra de arriba; x par */
static void repone(int x0, int y0, int x1, int y1)
{
    const int B = 24, H = 400, banda = (H - B) / 7;
    int i;
    x0 &= ~1; x1 = (x1 + 1) & ~1;
    if (x0 < 0) x0 = 0;
    if (x1 > 640) x1 = 640;
    if (y0 < B) y0 = B;
    if (y1 > H) y1 = H;
    for (i = 0; i < 7; i++) {
        int b0 = B + i * banda, b1 = (i == 6) ? H : b0 + banda;
        int ya = y0 > b0 ? y0 : b0, yb = y1 < b1 ? y1 : b1;
        if (yb > ya && x1 > x0)
            rect2((u16)x0, (u16)ya, (u16)(x1 - x0), (u16)(yb - ya), (u8)(((P_FONDO0 + i / 2) << 4) | (P_FONDO0 + (i + 1) / 2)));
    }
}

/* el marco que estaba en (ox, oy) y ahora esta en (nx, ny): el fondo en lo que queda al descubierto (el marco nuevo se pinta encima del resto) */
static void expuesto(u16 ox, u16 oy, u16 nx, u16 ny)
{
    int ox0 = (int)ox - (int)MB_L, oy0 = (int)oy - (int)MB_T, ox1 = ox0 + (int)FW, oy1 = oy0 + (int)FH;
    int nx0 = (int)nx - (int)MB_L, ny0 = (int)ny - (int)MB_T, nx1 = nx0 + (int)FW, ny1 = ny0 + (int)FH;
    int ix0 = nx0 > ox0 ? nx0 : ox0, ix1 = nx1 < ox1 ? nx1 : ox1, iy0 = ny0 > oy0 ? ny0 : oy0, iy1 = ny1 < oy1 ? ny1 : oy1;
    if (oy1 > 288 || ny1 > 288) tocado = 1;                             /* las tarjetas (a partir de la fila 290) quedan a medias: se repintan al soltar */
    if (ix0 >= ix1 || iy0 >= iy1) { repone(ox0, oy0, ox1, oy1); return; }   /* no se tocan: todo el viejo */
    if (oy0 < iy0) repone(ox0, oy0, ox1, iy0);                          /* lo de arriba */
    if (oy1 > iy1) repone(ox0, iy1, ox1, oy1);                          /* lo de abajo */
    if (ox0 < ix0) repone(ox0, iy0, ix0, iy1);                          /* lo de la izquierda */
    if (ox1 > ix1) repone(ix1, iy0, ox1, iy1);                          /* lo de la derecha */
}

static void marco_mueve(void)
{
    int mov = bf_hay && (bn_x != bf_x || bn_y != bf_y);
    if (bf_hay && !mov && bn_foco == bf_foco && bn_arr == bf_arr && bn_sb == bf_sb) return;
    if (!q_hay(3300)) return;
    if (mov) expuesto(bf_x, bf_y, bn_x, bn_y);
    marco_dibuja(bn_x, bn_y, bn_foco, !bn_arr, bn_sb);
    bf_x = bn_x; bf_y = bn_y; bf_foco = bn_foco; bf_arr = bn_arr; bf_sb = bn_sb; bf_hay = 1; marco_pub = 1;
}

static void fondo(void)
{
    u16 W = layout == 7 ? 1024 : 640, H = layout == 7 ? 212 : 400, B = layout == 7 ? 20 : 24;
    u16 banda = (u16)((H - B) / 7U);
    u8 i;
    q(E_WR(7, 0));                                            /* P#7: SRS = 0, MCS = 0 (como el menu) */
    reg(14, 0);                                               /* la paleta desde la entrada 0 */
    for (i = 0; i < (layout == 9 ? 16U : 15U); i++) { q(E_WR(1, paleta[i][0])); q(E_WR(1, paleta[i][1])); q(E_WR(1, paleta[i][2])); }
    reg(15, P_SOMBRA);                                        /* el borde */
    for (i = 0; i < 7U; i++) {                                /* degradado: 4 colores y, entre ellos, el tramado de los dos */
        u8 a = (u8)(P_FONDO0 + i / 2U), b = (u8)(P_FONDO0 + (i + 1U) / 2U);
        rect2(0, (u16)(B + i * banda), W, (u16)(i == 6U ? H - B - 6U * banda : banda), (u8)((a << 4) | b));
    }
    rect(0, 0, W, (u16)(B - 1U), P_BARRA);
    rect(0, (u16)(B - 1U), W, 1, P_ACENTO);
    if (layout == 7) { tarjeta(16, 30, 224, 42, 11); tarjeta(16, 84, 224, 78, 11); }
    else if (layout == 9) {                                   /* dos columnas: A y B arriba, las tarjetas en la franja de abajo */
        tarjeta(8, 290, 300, 86, 14); tarjeta(320, 290, 312, 96, 14);
        bf_x = bn_x; bf_y = bn_y; bf_foco = bn_foco; bf_arr = bn_arr; bf_sb = bn_sb; bf_hay = 1; tocado = 0; marco_falta = 1;   /* el marco, al final de pintar() */
    }
    else             { tarjeta(6, 34, 164, 48, 14);  tarjeta(6, 94, 164, 90, 14); }   /* B5: estrechas, la ventana V
                                                                 (x0,75 con bordes: 456 puntos) empieza en el 180 */
}

static void campos(void)
{
    if (layout == 7) {                                        /* B7: 1024 x 212, un punto = 1 x 3 px: el texto grande va x2 en horizontal */
        campo(&k[K_TITULO], 12, 6, 2, 1, P_ACENTO, P_BARRA, 9);
        campo(&k[K_VER], 164, 6, 1, 1, P_TENUE, P_BARRA, 12);
        campo(&k[K_FECHA], 790, 6, 1, 1, P_TENUE, P_BARRA, 10);
        campo(&k[K_HORA], 880, 6, 2, 1, P_TEXTO, P_BARRA, 8);
        campo(&k[K_CAB_A], 26, 32, 1, 1, P_ACENTO, P_CABE, 24);
        campo(&k[K_ROM], 26, 47, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_PISTA], 26, 59, 1, 1, P_TENUE, P_TARJ, 24);
        campo(&k[K_CAB_B], 26, 86, 1, 1, P_ACENTO, P_CABE, 24);
        campo(&k[K_RED], 26, 101, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_TEMP], 26, 113, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_ENC], 26, 125, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_CPU], 26, 137, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_USB], 26, 149, 1, 1, P_TENUE, P_TARJ, 24);
    } else if (layout == 9) {                                 /* dos columnas: barra como en B5, las tarjetas debajo (y 290, 14 de cabecera, lineas cada 14) */
        campo(&k[K_TITULO], 8, 4, 2, 2, P_ACENTO, P_BARRA, 9);
        campo(&k[K_VER], 160, 8, 1, 1, P_TENUE, P_BARRA, 12);
        campo(&k[K_FECHA], 416, 8, 1, 1, P_TENUE, P_BARRA, 10);
        campo(&k[K_HORA], 504, 4, 2, 2, P_TEXTO, P_BARRA, 8);
        campo(&k[K_CAB_A], 22, 293, 1, 1, P_ACENTO, P_CABE, 24);
        campo(&k[K_ROM], 22, 310, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_PISTA], 22, 324, 1, 1, P_TENUE, P_TARJ, 24);
        campo(&k[K_AYUDA], 22, 338, 1, 1, P_TENUE, P_TARJ, 24);
        campo(&k[K_SONIDO], 22, 352, 1, 1, P_TEXTO, P_TARJ, 24);        /* Z1.3.2b8: "Sonido  A: si  B: no" */
        campo(&k[K_SD], 22, 366, 1, 1, P_TEXTO, P_TARJ, 24);            /* Z1.3.2b9: quien tiene la SD de TF2 (la tarjeta mide hasta la fila 376) */
        campo(&k[K_CAB_B], 334, 293, 1, 1, P_ACENTO, P_CABE, 24);
        campo(&k[K_RED], 334, 310, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_TEMP], 334, 324, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_ENC], 334, 338, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_CPU], 334, 352, 1, 1, P_TEXTO, P_TARJ, 24);
        campo(&k[K_USB], 334, 366, 1, 1, P_TENUE, P_TARJ, 24);
    } else {                                                  /* B5: 640 x 400, un punto = 2 x 1,5 px */
        campo(&k[K_TITULO], 8, 4, 2, 2, P_ACENTO, P_BARRA, 9);
        campo(&k[K_VER], 160, 8, 1, 1, P_TENUE, P_BARRA, 12);
        campo(&k[K_FECHA], 416, 8, 1, 1, P_TENUE, P_BARRA, 10);
        campo(&k[K_HORA], 504, 4, 2, 2, P_TEXTO, P_BARRA, 8);
        campo(&k[K_CAB_A], 14, 37, 1, 1, P_ACENTO, P_CABE, 19);
        campo(&k[K_ROM], 14, 54, 1, 1, P_TEXTO, P_TARJ, 19);
        campo(&k[K_PISTA], 14, 68, 1, 1, P_TENUE, P_TARJ, 19);
        campo(&k[K_CAB_B], 14, 97, 1, 1, P_ACENTO, P_CABE, 19);
        campo(&k[K_RED], 14, 114, 1, 1, P_TEXTO, P_TARJ, 19);
        campo(&k[K_TEMP], 14, 128, 1, 1, P_TEXTO, P_TARJ, 19);
        campo(&k[K_ENC], 14, 142, 1, 1, P_TEXTO, P_TARJ, 19);
        campo(&k[K_CPU], 14, 156, 1, 1, P_TEXTO, P_TARJ, 19);
        campo(&k[K_USB], 14, 170, 1, 1, P_TENUE, P_TARJ, 19);
    }
}

static void pintar(void)
{
    char t[40], *p;
    u8 ip[4];
    u32 up = osd_uptime_s(), lt = 0;
    s32 tc = osd_temp_dc;
    int hay_hora = hora_local(&lt);
    if (todo) { fondo(); campos(); todo = 0; reloj_red = 2; }
    else if (layout == 9 && !marco_falta) marco_mueve();       /* dual.c ha movido la ventana de B o cambiado el foco */
    /* el reloj: con hora de red, el del companion; sin ella, el del gestor (R#55 bit 0 a 0) */
    if ((u8)hay_hora != reloj_red) {
        reloj_red = (u8)hay_hora;
        reg(55, (u8)(r55 | (hay_hora ? 1U : 0U)));
        if (!hay_hora) { pon_campo(&k[K_FECHA], ""); pon_campo(&k[K_HORA], ""); }
    }
    pon_campo(&k[K_TITULO], "MSXimus Z");
    pon_campo(&k[K_VER], ota_version());
    if (hay_hora) {
        u8 dt[7];
        epoch_to_dt(lt, dt);
        p = dos(t, dt[3]); *p++ = '/'; p = dos(p, dt[4]); *p++ = '/'; num(p, (u32)(dt[5] | (dt[6] << 8)));
        pon_campo(&k[K_FECHA], t);
        p = dos(t, dt[2]); *p++ = ':'; p = dos(p, dt[1]); *p++ = ':'; dos(p, dt[0]);
        pon_campo(&k[K_HORA], t);
    }
    pon_campo(&k[K_CAB_A], layout == 9 && !a_juega ? T("JUGANDO EN B", "NOW PLAYING ON B") : T("JUGANDO", "NOW PLAYING"));
    pon_campo(&k[K_ROM], rom[0] ? rom : "-");
    if (layout == 9) {
        static u8 ant_sil = 2;
        char c[24], *s;
        pon_campo(&k[K_AYUDA], bn_foco ? T("Teclado en B (Insert)", "Keyboard on B (Insert)") : T("Teclado en A (Insert)", "Keyboard on A (Insert)"));
        s = pon(c, T("Sonido  A: ", "Sound  A: "));                 /* Z1.3.2b8: el sonido de cada maquina (los cuadraditos cian de las barras) */
        s = pon(s, bn_sa ? T("no", "off") : T("si", "on"));
        s = pon(s, "  B: ");
        pon(s, !bn_corre ? "--" : bn_sb ? T("no", "off") : T("si", "on"));
        if (ant_sil != (u8)(bn_sa | bn_sb)) { for (u32 i = 0; i < LMAX; i++) k[K_SONIDO].vis[i] = 0; ant_sil = (u8)(bn_sa | bn_sb); }
        k[K_SONIDO].fg = (bn_sa || bn_sb) ? P_NARANJA : P_TEXTO;   /* con algo en silencio, la linea en naranja */
        pon_campo(&k[K_SONIDO], c);
        pon_campo(&k[K_SD], bn_sd ? T("SD: escribe B", "SD: B writes") : T("SD: escribe A", "SD: A writes"));   /* Z1.3.2b9 */
    }
    {   /* B5 (tecla V): tarjetas de 19 caracteres; el tipo de red va a la cabecera y debajo solo la IP */
        int b5 = !ANCHO;
        char c[24];
        pon_campo(&k[K_PISTA], layout == 9 ? T("Raton: arrastra ventanas", "Mouse: drag windows")
                               : b5 ? T("Raton: arrastrar", "Mouse: drag window") : T("Raton: arrastra la ventana", "Mouse: drag the window"));
        net_ip(ip);
        if (ip[0]) {
            p = pon(t, b5 ? "IP  " : T("Red   ", "LAN   ")); ip_txt(p, ip);
            pon(c, b5 ? T("SISTEMA  Red", "SYSTEM  LAN") : T("SISTEMA", "SYSTEM"));
        } else if (s3_ip(ip)) {
            p = pon(t, b5 ? "IP  " : "WiFi  "); ip_txt(p, ip);
            pon(c, b5 ? T("SISTEMA  WiFi", "SYSTEM  WiFi") : T("SISTEMA", "SYSTEM"));
        } else {
            pon(t, s3_diag ? s3_diag : T("Sin red", "No network"));
            pon(c, T("SISTEMA", "SYSTEM"));
        }
        pon_campo(&k[K_CAB_B], c);
        pon_campo(&k[K_RED], t);
    }
    p = pon(t, "Temp  "); if (tc < 0) { *p++ = '-'; tc = -tc; } p = num(p, (u32)tc / 10U); *p++ = ','; p = num(p, (u32)tc % 10U); pon(p, " C");
    pon_campo(&k[K_TEMP], t);
    p = pon(t, T("Encendida ", "Uptime ")); p = num(p, up / 3600U); *p++ = ':'; p = dos(p, (up / 60U) % 60U); *p++ = ':'; dos(p, up % 60U);
    pon_campo(&k[K_ENC], t);
    {                                                         /* el turbo: si cambia, la linea entera con su color */
        static int ant = -1;
        int tb = osd_turbo();
        if (tb != ant) { for (u32 i = 0; i < LMAX; i++) k[K_CPU].vis[i] = 0; ant = tb; }
    }
    if (osd_turbo()) { k[K_CPU].fg = P_NARANJA; pon_campo(&k[K_CPU], !ANCHO ? "CPU 5.37 MHz turbo" : "CPU   5.37 MHz turbo"); }
    else             { k[K_CPU].fg = P_TEXTO;   pon_campo(&k[K_CPU], !ANCHO ? "CPU 3.58 MHz" : "CPU   3.58 MHz"); }
    if (!ANCHO) {                                             /* B5: "USB kbd2 mse1 pad0" (18) */
        p = pon(t, T("USB tec", "USB kbd")); p = num(p, usb_n_kbd); p = pon(p, T(" rat", " mse")); p = num(p, usb_n_mouse);
        p = pon(p, T(" man", " pad")); num(p, usb_n_pad);
    } else {
        p = pon(t, T("USB  tec ", "USB  kbd ")); p = num(p, usb_n_kbd); p = pon(p, T("  rat ", "  mse ")); p = num(p, usb_n_mouse);
        p = pon(p, T("  man ", "  pad ")); num(p, usb_n_pad);
    }
    pon_campo(&k[K_USB], t);
    if (layout == 9 && marco_falta && !lleno && q_hay(3300)) {   /* escritorio recien repintado y todo el texto puesto: el marco de B encima */
        marco_dibuja(bn_x, bn_y, bn_foco, !bn_arr, bn_sb);
        bf_x = bn_x; bf_y = bn_y; bf_foco = bn_foco; bf_arr = bn_arr; bf_sb = bn_sb; bf_hay = 1; marco_falta = 0; marco_pub = 1;
    }
}

/* ---- API --------------------------------------------------------------------------------------------------------- */
/* al arrancar, antes de soltar el MSX: el control vive fuera del buzon que el FSBL pone a cero, y con basura en la
 * DDR (en = 1 y un wr cualquiera) el PL se ponia a ejecutar el anillo, tambien basura, en cuanto el compositor daba
 * permiso (teclas V y B): pantalla verde con el juego sonando (placa, Z1.3b1) */
void v99desk_init(void)
{
    wr = 0; npend = 0; activo = 0;
    V9_CTL = 0U;                                              /* en = 0: el PL vacia la FIFO y su rd sigue a wr (0) */
    DSB();
}

void v99desk_inicio(u8 lay, const char *nombre)              /* "V5" / "V7" + nombre del menu (wavegame.c) */
{
    u32 i;
    if (PL_TR) { log_str("v99desk: perfil TR, sin V9990: nada que pintar\n"); return; }   /* el menu pinta en el vacio y lanza la ROM; la tecla V/B es un Enter */
    V9_CTL = wr;                                              /* en = 0 con el mismo wr: el PL tira lo pendiente y rd = wr */
    DSB();
    for (i = 0; i < 24U && nombre[i]; i++) rom[i] = nombre[i];
    rom[i] = 0;
    a_juega = (u8)(lay == 10);                                /* "V","A" (D sola): dos columnas con el juego en A */
    if (lay == 10) lay = 9;
    npend = 0; activo = 1; layout = lay; todo = 1; lleno = 0;
    r55 = (lay == 7 || lay == 9) ? 0xB6 : 0xBE;               /* lo que deja el menu (v9k_wregs_b7 / _b5 / _dual), con bordes */
    bf_hay = 0; tocado = 0; bn_arr = 0; bn_foco = 0; bn_sa = 0; bn_sb = 0; bn_corre = 1; bf_sb = 0; marco_falta = 0; marco_pub = 0;
    s3_fase = S_TOMA; s3_intentos = 0; s3_diag = 0;
    t_next = gt_now() + (u64)COUNTS_PER_SECOND / 100U;       /* 10 ms: el PL ve en = 0 en su ronda (~1 ms) */
    log_str("v99desk: escritorio B"); log_dec(lay); log_str(a_juega ? "A " : " "); log_str(rom); log_str("\n");
    dual_escritorio(a_juega ? 10 : lay);                                     /* perfil Dual (dual.c): B a su sitio (layout 9) o a la posicion de siempre; v99desk_dual_pon */
}

/* ---- perfil Dual: lo que dual.c pide al escritorio de dos columnas ---------------------------------------------------------------------- */
void v99desk_dual_pon(u16 x, u16 y, u8 foco, u8 arrastrando)  /* el marco de B con la imagen en (x, y) puntos, con ese foco; se pinta en la vuelta siguiente */
{
    bn_x = x; bn_y = y; bn_foco = foco; bn_arr = arrastrando;
}
void v99desk_dual_silencio(u8 a, u8 b, u8 corre) { bn_sa = a; bn_sb = b; bn_corre = corre; }   /* el sonido de A y de B (1 = en silencio) y si B corre: el cuadradito de la barra de B y la linea de la tarjeta */
u8 v99desk_lay(void) { return activo ? layout : 0U; }       /* 9 = escritorio de dos columnas en curso, 5 y 7 = los otros, 0 = ninguno */
void v99desk_dual_sd(u8 duena) { bn_sd = duena; }             /* la duena de la SD de TF2 (0 = A, 1 = B): la linea "SD" de la tarjeta */
void v99desk_dual_fin(void) { if (tocado) { tocado = 0; todo = 1; } }   /* soltada la ventana: si paso por las tarjetas, todo se repinta */

void v99desk_poll(void)
{
    u64 now;
    if (!activo) return;
    s3_poll();
    now = gt_now();
    if (now < t_next) return;
    if (npend == 0U) { lleno = 0; pintar(); }
    if (publicar() && marco_pub) { marco_pub = 0; dual_marco_listo(bf_x, bf_y); }   /* el marco ya va a la VRAM: la imagen de B se mueve con el (dual.c) */
    t_next = now + (u64)COUNTS_PER_SECOND / (lleno || npend ? 20U : (layout == 9 && (bf_x != bn_x || bf_y != bn_y || bf_foco != bn_foco || bf_arr != bn_arr || bf_sb != bn_sb)) ? 60U : 4U);   /* con trabajo pendiente, cada 50 ms (cada 16 si B se mueve) */
}
