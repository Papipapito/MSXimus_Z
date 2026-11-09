/* esp_link.c — enlace serie con el MSX para el "ESP32" del companion (25/09/2026, Ethernet P1).
 *
 * UART1 del PS por EMIO -> wifi_lite (I/O 06/07h del MSX) a 869.565 baud (ref 100 MHz: CD 23, BDIV 4; el PL va a
 * 27M/31 = 870.968, -0,16 %). Sin interrupciones: esp_poll() cada vuelta del bucle (~1 ms) vacia la FIFO de
 * recepcion (64 bytes) y rellena la de transmision desde una cola. Como a 870 kbaud llegan 87 bytes por ms, la
 * UART1 lleva el control de flujo automatico (MODEMCR.FCM + FLOWDEL): al llenarse sube RTSN y el PL retiene al Z80
 * en su OUT al 07h (top_zynq.v, net_pause). Hacia el MSX no hace falta: la FIFO de wifi_lite es de 2080 bytes, la
 * misma que con el ESP real y el mismo baud.
 *
 * Protocolo (README del firmware): comando "rapido" = 1 byte; "normal" = byte + tam MSB + tam LSB + datos; si pasan
 * 250 ms entre bytes se descarta. Respuesta: CMD + ERR [+ tam MSB + tam LSB + datos]. 'r' repite la ultima. Mientras
 * hay una respuesta pendiente (TCP_OPEN, DNS, hora) no se leen mas bytes: el ESP real tampoco (bloquea). */
#include "xil_types.h"
#include "xil_io.h"
#include "lwip/sys.h"
#include "log.h"
#include "esp.h"

extern int net_started(void);                   /* net.c: el GEM0 esta en marcha */

#define UART1           0xE0001000U
#define U_CR            (UART1 + 0x00U)
#define U_MR            (UART1 + 0x04U)
#define U_BAUDGEN       (UART1 + 0x18U)
#define U_RXTOUT        (UART1 + 0x1CU)
#define U_RXWM          (UART1 + 0x20U)
#define U_MODEMCR       (UART1 + 0x24U)
#define U_SR            (UART1 + 0x2CU)
#define U_FIFO          (UART1 + 0x30U)
#define U_BAUDDIV       (UART1 + 0x34U)
#define U_FLOWDEL       (UART1 + 0x38U)
#define SR_TXFULL       0x10U
#define SR_RXEMPTY      0x02U
#define APER_CLK_CTRL   0xF800012CU
#define MBOX_CTRL       0x1FF0001CU
#define TXRING          8192U
#define READY_RETRIES   3U

esp_pend_t esp_pend;
u8  esp_data[ESP_MAX_DATA + 1];

static u8  txr[TXRING];
static u32 txr_wr, txr_rd;
static u8  last_cmd, last_err, last_quick, last_data[ESP_MAX_DATA];
static u32 last_n;
static u8  p_state, p_cmd;
static u32 p_len, p_got, p_last_ms;
static u32 ready_left, ready_next, netps_next;
static int got_cmd, started, active, want_prev, uart_ok, s3_on;
enum { P_IDLE = 0, P_SZ1, P_SZ2, P_DATA };

/* ---- UART1 -------------------------------------------------------------------------------------- */
static void uart_init(void)
{
    Xil_Out32(0xF8000008U, 0xDF0DU);
    Xil_Out32(APER_CLK_CTRL, Xil_In32(APER_CLK_CTRL) | (1U << 21));       /* reloj AMBA de la UART1 */
    Xil_Out32(0xF8000004U, 0x767BU);
    Xil_Out32(U_CR, 0x28U | 0x03U);                                       /* TX/RX off + reset de FIFOs */
    while (Xil_In32(U_CR) & 0x03U) { }
    Xil_Out32(U_MR, 0x20U);                                               /* 8N1, reloj de referencia (100 MHz) */
    Xil_Out32(U_BAUDGEN, 23U); Xil_Out32(U_BAUDDIV, 4U);                  /* 100e6 / (23 * 5) = 869.565 */
    Xil_Out32(U_RXTOUT, 0U);
    Xil_Out32(U_RXWM, 32U);
    Xil_Out32(U_FLOWDEL, 32U);                                            /* RTS fuera con 32 bytes en la FIFO RX */
    Xil_Out32(U_MODEMCR, 0x20U | 0x02U);                                  /* FCM (flujo automatico) + RTS */
    Xil_Out32(U_CR, 0x14U | 0x40U);                                       /* RXEN TXEN RSTTO */
    uart_ok = 1;
}

static void uart_baud(u32 cd, u32 bdiv)                                    /* TX/RX parados, FIFOs a cero, otra vez en marcha */
{
    Xil_Out32(U_CR, 0x28U | 0x03U);
    while (Xil_In32(U_CR) & 0x03U) { }
    Xil_Out32(U_BAUDGEN, cd); Xil_Out32(U_BAUDDIV, bdiv);
    Xil_Out32(U_CR, 0x14U | 0x40U);
}

/* 02/10: la S3 del CAM1 para la actualizacion por WiFi (s3_link.c). Con on, el PL (MBOX+0x1C bit 4) la une con la
 * UART1 y aparta al MSX; aqui se deja de hacer de "ESP" (bit 3 fuera, esp_poll quieto) y la UART1 pasa a 862.069 baud
 * (100 MHz / (4 x 29): el firmware va a 859.372). Con off, todo como estaba y esp_poll vuelve a mirar el cable. */
void esp_s3_uart(int on)
{
    if (on) {
        if (!uart_ok) uart_init();
        *(volatile u32 *)MBOX_CTRL = (*(volatile u32 *)MBOX_CTRL & ~8U) | 0x10U;
        active = 0; txr_rd = txr_wr;                                      /* lo que fuera para el MSX ya no le llega */
        uart_baud(4U, 28U);
        s3_on = 1;
    } else if (s3_on) {
        *(volatile u32 *)MBOX_CTRL &= ~0x10U;
        uart_baud(23U, 4U);
        s3_on = 0;
        netps_next = sys_now();                                           /* el cable, en la vuelta siguiente */
    }
}

static void tx_pump(void)
{
    while (txr_rd != txr_wr && !(Xil_In32(U_SR) & SR_TXFULL)) {
        Xil_Out32(U_FIFO, txr[txr_rd]);
        txr_rd = (txr_rd + 1U) % TXRING;
    }
}

static void tx_put(const u8 *p, u32 n)
{
    while (n--) {
        u32 nw = (txr_wr + 1U) % TXRING;
        if (nw == txr_rd) { tx_pump(); if (nw == txr_rd) return; }     /* cola llena: se pierde (no deberia pasar) */
        txr[txr_wr] = *p++; txr_wr = nw;
    }
    tx_pump();
}

/* ---- respuestas ------------------------------------------------------------------------------------ */
void esp_send_raw(const u8 *p, u32 n) { tx_put(p, n); }

#if ESP_TRACE
static u32 trace_t0;
static void trace_cmd(u8 cmd, u32 len) { trace_t0 = sys_now(); log_str(" e:"); if (cmd >= 32U && cmd < 127U) log_char((char)cmd); else log_dec(cmd); log_str("/"); log_dec(len); }
static void trace_rsp(u8 err, u32 n) { log_str(" r:"); log_dec(err); if (n) { log_str("+"); log_dec(n); } log_str("@"); log_dec(sys_now() - trace_t0); }
#else
#define trace_cmd(c, l)
#define trace_rsp(e, n)
#endif

void esp_send_quick(u8 cmd, u8 err)
{
    u8 h[2]; h[0] = cmd; h[1] = err;
    trace_rsp(err, 0);
    last_cmd = cmd; last_err = err; last_quick = 1; last_n = 0;
    tx_put(h, 2);
}

void esp_send(u8 cmd, u8 err, const u8 *data, u32 n)
{
    u8 h[4];
    if (n > ESP_MAX_DATA) n = ESP_MAX_DATA;
    h[0] = cmd; h[1] = err; h[2] = (u8)(n >> 8); h[3] = (u8)n;
    trace_rsp(err, n);
    last_cmd = cmd; last_err = err; last_quick = 0; last_n = n;
    if (n && data != last_data) { u32 i; for (i = 0; i < n; i++) last_data[i] = data[i]; }
    tx_put(h, 4);
    if (n) tx_put(last_data, n);
}

static void send_retry(void)
{
    if (last_quick) esp_send_quick(last_cmd, last_err);
    else esp_send(last_cmd, last_err, last_data, last_n);
}

void esp_pend_set(u8 kind, u8 cmd, u8 conn, u32 ms)
{
    esp_pend.kind = kind; esp_pend.cmd = cmd; esp_pend.conn = conn; esp_pend.deadline = sys_now() + ms;
}
void esp_pend_clear(void) { esp_pend.kind = PEND_NONE; }

/* ---- analizador ------------------------------------------------------------------------------------- */
static int is_quick(u8 c)
{
    switch (c) {
        case 'I': case 'r': case 'W': case 'b': case 'E': case 'R': case 'g': case '?': case 'G': case 'H':
        case 'h': case 'c': case 'Q': case 'V': case 'S': case 's': case 'O': case 'o': case 'a': case 'N': case 'D':
            return 1;
        default: return 0;
    }
}

static int is_regular(u8 c)
{
    if ((c >= 1U && c <= 3U) || c == 6U || (c >= 8U && c <= 18U) || c == 25U || c == 26U || c == 206U) return 1;
    if (c >= 200U && c <= 202U) return 1;                                 /* HTTP_* (no implementados: error 1) */
    if (c >= 129U && c <= 143U) return 1;                                 /* SSH_* (no implementados: error 1) */
    switch (c) {
        case 'A': case 'U': case 'u': case 'Z': case 'Y': case 'z': case 'T': case 'C': case 'B': case 'd': return 1;
        default: return 0;
    }
}

static void rx_byte(u8 b)
{
    u32 now = sys_now();
    if (p_state != P_IDLE && (now - p_last_ms) > 250U) p_state = P_IDLE;    /* 250 ms entre bytes: se descarta */
    p_last_ms = now;
    switch (p_state) {
        case P_IDLE:
            got_cmd = 1;
            if (b == 'r') { send_retry(); break; }
            if (is_quick(b)) { trace_cmd(b, 0); esp_exec(b, 0); break; }
            if (is_regular(b)) { p_cmd = b; p_state = P_SZ1; }
            break;                                                        /* desconocido: se ignora, como el firmware */
        case P_SZ1: p_len = (u32)b << 8; p_state = P_SZ2; break;
        case P_SZ2:
            p_len |= b; p_got = 0;
            if (p_len == 0U) { p_state = P_IDLE; trace_cmd(p_cmd, 0); esp_exec(p_cmd, 0); }
            else p_state = P_DATA;
            break;
        default:
            if (p_got < ESP_MAX_DATA) esp_data[p_got] = b;
            p_got++;
            if (p_got >= p_len) {
                p_state = P_IDLE;
                if (p_len <= ESP_MAX_DATA) { esp_data[p_len] = 0; trace_cmd(p_cmd, p_len); esp_exec(p_cmd, p_len); }
            }
            break;
    }
}

/* ---- arranque y bucle -------------------------------------------------------------------------------- */
void esp_init(void)
{
    if (!net_started()) { log_str("esp: sin red del PS, la UART del ESP se queda en el CAM1\n"); return; }
    uart_init();
    esp_warm_reset();
    ready_left = READY_RETRIES; ready_next = sys_now() + 500U;
    started = 1;
    log_str("esp: UART1 869565 baud con RTS automatico; con cable el MSX ve un ESP32 con la red \"Ethernet\", sin cable manda el CAM1\n");
}

void esp_pl_rearma(void)                                                  /* profile.c (PCAP, 30/10): wifi_lite nuevo, el MSX acaba de arrancar */
{
    if (!started || s3_on) return;
    uart_init();                                                          /* FIFOs a cero y los 869.565 baud */
    txr_rd = txr_wr; p_state = P_IDLE; got_cmd = 0;
    esp_warm_reset();                                                     /* conexiones y pendientes del MSX anterior fuera */
    ready_left = READY_RETRIES; ready_next = sys_now() + 500U;
}

void esp_poll(void)
{
    u32 n;
    if (!started || s3_on) return;                                        /* 02/10: con la S3 tomada, la UART es de s3_link.c */
    tx_pump();
    if ((s32)(sys_now() - netps_next) >= 0) {                            /* cada 500 ms: la UART del ESP es nuestra solo con cable */
        int want = esp_link_up();                                         /* (dos lecturas seguidas iguales: sin rebotes) */
        netps_next = sys_now() + 500U;
        if (want != active && want == want_prev) {
            active = want;
            if (active) { *(volatile u32 *)MBOX_CTRL |= 8U; ready_left = READY_RETRIES; ready_next = sys_now() + 500U; got_cmd = 0;
                          log_str("esp: cable con enlace: la UART del ESP pasa al companion\n"); }
            else { *(volatile u32 *)MBOX_CTRL &= ~8U; esp_warm_reset();
                   log_str("esp: sin enlace: la UART del ESP vuelve al modulo del CAM1\n"); }
        } else if (active && !(*(volatile u32 *)MBOX_CTRL & 8U)) *(volatile u32 *)MBOX_CTRL |= 8U;   /* por si alguien pisa +0x1C */
        want_prev = want;
    }
    if (!active) {                                                        /* el MSX habla con el ESP32 del CAM1: sus bytes nos llegan igual, se tiran */
        while (!(Xil_In32(U_SR) & SR_RXEMPTY)) (void)Xil_In32(U_FIFO);
        return;
    }
    if (!got_cmd && ready_left && (s32)(sys_now() - ready_next) >= 0) {   /* "Ready" hasta que el MSX hable, como el ESP */
        esp_send_raw((const u8 *)"Ready\r\n", 7); ready_left--; ready_next = sys_now() + 5000U;
    }
    esp_tcp_poll();
    esp_cmd_poll();
    if (esp_pend.kind != PEND_NONE) return;                               /* ocupado: el MSX espera (RTS lo frena) */
    for (n = 0; n < 512U && !(Xil_In32(U_SR) & SR_RXEMPTY); n++) {
        rx_byte((u8)Xil_In32(U_FIFO));
        if (esp_pend.kind != PEND_NONE) break;
    }
    tx_pump();
}
