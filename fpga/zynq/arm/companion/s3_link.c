/* s3_link.c — la S3 (el ESP32 del CAM1) como red del companion cuando no hay cable (02/10/2026).
 *
 * La actualizacion por red (ota.c) sale por el cable si lo hay; si no, por la WiFi del ESP32 del CAM1. Para eso el PL
 * (top_zynq.v, MBOX+0x1C bit 4) une ese ESP con la UART1 del PS y deja al MSX sin el (no oye nada ni le llega nada), y
 * el companion le habla como el driver UNAPI del MSX: el mismo protocolo que imita esp_link.c, ahora del otro lado.
 * DNS, TCP y TLS los hace el ESP (con su firmware de serie valida el certificado; ota.c lo pide asi y, si no puede,
 * otra vez sin validar: la integridad la da la firma del manifiesto).
 *
 * La UART1 va a 862.069 baud (100 MHz / (4 x 29), +0,3 % sobre los 859.372 del firmware y 29 muestras por bit; con el
 * MSX va a 869.565 con 5). Sin control de flujo hacia el ARM: el ESP manda cada respuesta de golpe (TCP_RCV, hasta
 * 2052 B en 24 ms) y la FIFO de la UART1 es de 64 B, asi que las respuestas grandes se leen en un bucle cerrado desde
 * que se manda la orden (s3_orden) y las que tardan (DNS, TCP_OPEN con TLS: segundos) son cortas y se esperan sin
 * bloquear el bucle (s3_pide + s3_resp). Un desborde de la FIFO (ISR.ROVR) invalida la respuesta.
 * Al tomar la S3 se tiran 300 ms de lo que llegue: el firmware descarta un comando a medias tras 250 ms sin bytes,
 * asi que un OUT del MSX cortado al cambiar no se mezcla con lo nuestro. */
#include "xil_types.h"
#include "xil_io.h"
#include "lwip/sys.h"
#include "log.h"
#include "s3.h"

#define UART1           0xE0001000U
#define U_ISR           (UART1 + 0x14U)
#define U_SR            (UART1 + 0x2CU)
#define U_FIFO          (UART1 + 0x30U)
#define SR_TXFULL       0x10U
#define SR_RXEMPTY      0x02U
#define ISR_ROVR        0x20U
#define ASENTAR_MS      300U

extern void esp_s3_uart(int on);                /* esp_link.c: bit 4 del buzon y baud de la UART1 */

s3_resp_t s3r;
static u8  tomada, esperando, cmd_esp, r_fase, ip_ok;
static u16 r_got;
static u32 r_plazo, t_lista;
static u8  ip_s3[4], mascara[4];

static void tira(void)                          /* lo que haya en la FIFO no es para nadie */
{
    while (!(Xil_In32(U_SR) & SR_RXEMPTY)) (void)Xil_In32(U_FIFO);
    Xil_Out32(U_ISR, ISR_ROVR);
}

static void manda(const u8 *p, u32 n)
{
    while (n--) {
        u32 g = 0;
        while ((Xil_In32(U_SR) & SR_TXFULL) && ++g < 2000000U) { }
        Xil_Out32(U_FIFO, *p++);
    }
}

void s3_toma(void)
{
    if (tomada) return;
    esp_s3_uart(1);
    tomada = 1; esperando = 0; r_fase = 0;
    t_lista = sys_now() + ASENTAR_MS;
    log_str("s3: la UART del ESP del CAM1 pasa al companion\n");
}

void s3_suelta(void)
{
    if (!tomada) return;
    esp_s3_uart(0);
    tomada = 0; esperando = 0; r_fase = 0;
    log_str("s3: la UART del ESP vuelve al MSX\n");
}

int s3_tomada(void) { return tomada; }

int s3_lista(void)
{
    if (!tomada) return 0;
    if ((s32)(sys_now() - t_lista) < 0) { tira(); return 0; }
    return 1;
}

/* un byte de la respuesta esperada (CMD ERR tam_MSB tam_LSB datos): 1 completa, 0 sigue. Antes del CMD se salta lo
 * que no lo sea ("Ready\r\n", restos); si lo que sigue es imposible (ERR > 20, tamano > S3_MAX), aquel CMD era basura
 * (el '\r' de "Ready" es un 13 = TCP_OPEN): sus bytes de cabecera vuelven a pasar desde el principio. */
static u8 hdr[3];
static int alimenta(u8 b);
static void otra_vez(u32 k)
{
    u8 h[3];
    u32 i;
    for (i = 0; i < k; i++) h[i] = hdr[i];
    r_fase = 0;
    for (i = 0; i < k; i++) (void)alimenta(h[i]);   /* 3 bytes no completan una respuesta (minimo 4) */
}

static int alimenta(u8 b)
{
    switch (r_fase) {
        case 0: if (b == cmd_esp) { s3r.cmd = b; r_fase = 1; } return 0;
        case 1: hdr[0] = b; if (b > 20U) { otra_vez(1); return 0; } s3r.err = b; r_fase = 2; return 0;
        case 2: hdr[1] = b; s3r.n = (u16)(b << 8); r_fase = 3; return 0;
        case 3:
            hdr[2] = b; s3r.n |= b; r_got = 0;
            if (s3r.n > S3_MAX) { otra_vez(3); return 0; }
            if (s3r.n == 0U) { r_fase = 0; return 1; }
            r_fase = 4;
            return 0;
        default:
            s3r.d[r_got++] = b;
            if (r_got >= s3r.n) { r_fase = 0; return 1; }
            return 0;
    }
}

/* lee la respuesta esperada; desde su primer byte no se suelta hasta el ultimo (50 ms sin bytes = cortada).
 * 1 hecha, 0 aun nada (solo sin 'bloq'), -1 vencida o mal. */
static int lee(int bloq)
{
    u32 t_byte = sys_now();
    for (;;) {
        u8 b;
        if (Xil_In32(U_ISR) & ISR_ROVR) { Xil_Out32(U_ISR, ISR_ROVR); log_str("s3: FIFO desbordada\n"); r_fase = 0; return -1; }
        if (Xil_In32(U_SR) & SR_RXEMPTY) {
            u32 now = sys_now();
            if (r_fase == 0U) {
                if ((s32)(now - r_plazo) >= 0) return -1;
                if (!bloq) return 0;
            } else if (now - t_byte > 50U) { log_str("s3: respuesta cortada\n"); r_fase = 0; return -1; }
            continue;
        }
        b = (u8)Xil_In32(U_FIFO);
        t_byte = sys_now();
        if (alimenta(b)) return 1;
    }
}

int s3_pide(u8 cmd, const u8 *d, u32 n, u32 plazo_ms)
{
    u8 h[3];
    if (!tomada || esperando) return 0;
    tira();
    h[0] = cmd; h[1] = (u8)(n >> 8); h[2] = (u8)n;
    manda(h, 3);
    if (n) manda(d, n);
    cmd_esp = cmd; r_fase = 0; esperando = 1; r_plazo = sys_now() + plazo_ms;
    return 1;
}

int s3_resp(void)
{
    int r;
    if (!esperando) return -1;
    r = lee(0);
    if (r != 0) esperando = 0;
    if (r < 0) { log_str("s3: sin respuesta a "); log_dec(cmd_esp); log_str("\n"); }
    return r;
}

int s3_orden(u8 cmd, const u8 *d, u32 n, u32 plazo_ms)
{
    int r;
    esperando = 0;                              /* una pendiente sin recoger se abandona */
    if (!s3_pide(cmd, d, n, plazo_ms)) return -1;
    r = lee(1);
    esperando = 0;
    if (r < 0) { log_str("s3: sin respuesta a "); log_dec(cmd); log_str("\n"); }
    return r;
}

/* ---- lo que usa la actualizacion ------------------------------------------------------------------------------------ */
int s3_ip(u8 ip[4]) { if (!ip_ok) return 0; ip[0] = ip_s3[0]; ip[1] = ip_s3[1]; ip[2] = ip_s3[2]; ip[3] = ip_s3[3]; return 1; }

void s3_ip_lee(void)                            /* GET_IPINFO 1 = IP local, 3 = mascara */
{
    u8 q = 1;
    if (s3_orden(2, &q, 1, 1000U) == 1 && s3r.err == 0U && s3r.n == 4U && s3r.d[0]) {
        ip_s3[0] = s3r.d[0]; ip_s3[1] = s3r.d[1]; ip_s3[2] = s3r.d[2]; ip_s3[3] = s3r.d[3]; ip_ok = 1;
    }
    q = 3;
    if (s3_orden(2, &q, 1, 1000U) == 1 && s3r.err == 0U && s3r.n == 4U && s3r.d[0]) {
        mascara[0] = s3r.d[0]; mascara[1] = s3r.d[1]; mascara[2] = s3r.d[2]; mascara[3] = s3r.d[3];
    }
}

/* la difusion dirigida de su red (p. ej. 192.168.1.255): hay routers que no pasan de la WiFi al cable la de 255.255.255.255 */
int s3_difusion(u8 d[4])
{
    u32 i;
    if (!ip_ok || !mascara[0]) return 0;
    for (i = 0; i < 4U; i++) d[i] = (u8)(ip_s3[i] | (u8)~mascara[i]);
    return 1;
}

u8 s3_udp_abre(void)
{
    static const u8 q[3] = { 0xFF, 0xFF, 0 };   /* puerto al azar, transitoria */
    if (s3_orden(8, q, 3, 1000U) == 1 && s3r.err == 0U && s3r.n == 1U) return s3r.d[0];
    log_str("s3: UDP_OPEN error "); log_dec(s3r.err); log_str("\n");
    return 0;
}

int s3_udp_manda(u8 c, const u8 ip[4], u16 puerto, const u8 *d, u32 n)
{
    static u8 q[7 + 256];
    u32 i;
    if (n > 256U) return -1;
    q[0] = c; q[1] = ip[0]; q[2] = ip[1]; q[3] = ip[2]; q[4] = ip[3]; q[5] = (u8)puerto; q[6] = (u8)(puerto >> 8);
    for (i = 0; i < n; i++) q[7 + i] = d[i];
    if (s3_orden(11, q, 7U + n, 1000U) == 1 && s3r.err == 0U) return 1;
    log_str("s3: UDP_SEND error "); log_dec(s3r.err); log_str("\n");
    return -1;
}

int s3_udp_lee(u8 c, u8 *d, u32 cap, u8 ip[4])
{
    u8 q[3];
    u32 n, i;
    q[0] = c; q[1] = (u8)cap; q[2] = (u8)(cap >> 8);
    if (s3_orden(12, q, 3, 1000U) < 0) return -1;
    if (s3r.err == 3U) return 0;                /* UE_NO_DATA */
    if (s3r.err != 0U || s3r.n < 6U) return -1;
    ip[0] = s3r.d[0]; ip[1] = s3r.d[1]; ip[2] = s3r.d[2]; ip[3] = s3r.d[3];
    n = s3r.n - 6U; if (n > cap) n = cap;
    for (i = 0; i < n; i++) d[i] = s3r.d[6 + i];
    return (int)n;
}

void s3_udp_cierra(u8 c) { (void)s3_orden(9, &c, 1, 1000U); }

int s3_tcp_manda(u8 c, const u8 *d, u32 n)
{
    static u8 q[2 + 2048];
    u32 i, k;
    if (n > 2048U) return -1;
    q[0] = c; q[1] = 0;
    for (i = 0; i < n; i++) q[2 + i] = d[i];
    for (k = 0; k < 20U; k++) {                 /* UE_BUFFER: el ESP no pudo con todo, otra vez */
        if (s3_orden(17, q, 2U + n, 5000U) < 0) return -1;
        if (s3r.err == 0U) return 1;
        if (s3r.err != 13U) break;
    }
    log_str("s3: TCP_SEND error "); log_dec(s3r.err); log_str("\n");
    return -1;
}

int s3_tcp_lee(u8 c, u8 *d, u32 cap)
{
    u8 q[3];
    u32 n, i;
    if (cap > 2048U) cap = 2048U;
    q[0] = c; q[1] = (u8)cap; q[2] = (u8)(cap >> 8);
    if (s3_orden(18, q, 3, 3000U) < 0) return -1;
    if (s3r.err != 0U) return -1;               /* UE_NO_CONN: ya no esta */
    if (s3r.n <= 2U) return 0;                  /* 2 B de urgentes (0) y los datos */
    n = s3r.n - 2U; if (n > cap) n = cap;
    for (i = 0; i < n; i++) d[i] = s3r.d[2 + i];
    return (int)n;
}

int s3_tcp_estado(u8 c)                         /* el firmware: estado 4 establecida, 0/7 cerrada; luego bytes por leer */
{
    if (s3_orden(16, &c, 1, 2000U) < 0) return -1;
    if (s3r.err != 0U) return 0;
    if (s3r.n < 4U) return -1;
    return (s3r.d[1] == 4U || s3r.d[2] || s3r.d[3]) ? 1 : 0;
}

void s3_tcp_cierra(u8 c) { (void)s3_orden(14, &c, 1, 2000U); }
