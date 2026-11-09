/* esp_tls.c — sesiones TLS (Mbed TLS 3.6) sobre las conexiones TCP de lwIP del companion (26/09/2026, Ethernet P2).
 *
 * Una sesion envuelve un pcb de lwIP ya conectado: lo que llega por TCP (la cadena rxq del dueno) lo lee el BIO de
 * Mbed TLS, lo que Mbed TLS quiere mandar va por tcp_write. Nada bloquea: tls_poll() empuja el handshake y saca el
 * texto en claro a un anillo del que leen TCP_RCV del MSX o la descarga TSX. La usan esp_tcp.c (TCP_OPEN con el bit
 * de TLS) y esp_tsx.c (bajar cintas de tsx.eslamejor.com por https).
 *
 * Memoria: la criptografia sobre memoria strongly-ordered seria lentisima, asi que el asignador de buffer de Mbed TLS
 * trabaja sobre TLS_HEAP en la seccion .tlsheap (salida .tls, region "tls" de lscript.ld, 0x00A00000, que mmu.c mapea NORMAL con
 * cache: solo la toca este core, sin DMA). Entropia: el Zynq no tiene TRNG: se mezclan el timer global, el contador
 * de ciclos del A9, los contadores del GEM y 1 KB de DDR sin inicializar en un SHA-256 (CTR-DRBG encima).
 * Sin verificacion de certificado (VERIFY_NONE, como el ESP con setInsecure): no hay almacen de CA todavia. */
#include "xil_types.h"
#include "xil_io.h"
#include "lwip/sys.h"
#include "lwip/tcp.h"
#include "lwip/pbuf.h"
#include "mbedtls/ssl.h"
#include "mbedtls/net_sockets.h"                    /* solo por MBEDTLS_ERR_NET_CONN_RESET (sin MBEDTLS_NET_C) */
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/memory_buffer_alloc.h"
#include "mbedtls/sha256.h"
#include "mbedtls/platform.h"
#include "log.h"
#include "esp.h"

#define TLS_HEAP_SIZE   (768U * 1024U)
#define TLS_PT_SIZE     16384U                     /* anillo de texto en claro por sesion */
#define TLS_HS_MS       15000U

extern u64 gt_now(void);
extern volatile u32 loop_ms;                        /* main.c */

static u8 tls_heap[TLS_HEAP_SIZE] __attribute__((section(".tlsheap"), aligned(64)));
static mbedtls_entropy_context entropy;
static mbedtls_ctr_drbg_context drbg;
static mbedtls_ssl_config conf;
static int tls_ready;

struct esp_tls {
    mbedtls_ssl_context ssl;
    struct tcp_pcb *pcb;
    struct pbuf **rxq;                              /* del dueno: lo recibido por TCP sin descifrar */
    u32 *rx_total;
    u8  *pt;                                        /* texto en claro descifrado, anillo */
    u32 pt_rd, pt_wr, pt_n;
    u32 t0;
    int state;                                      /* 0 handshake, 1 lista, -1 error, 2 el par cerro */
    u8  remote_closed;
};

/* ---- entropia -------------------------------------------------------------------------------------- */
static u32 cycles(void)
{
    u32 v;
    __asm__ volatile ("mrc p15, 0, %0, c9, c13, 0" : "=r"(v));
    return v;
}

int mbedtls_hardware_poll(void *data, unsigned char *output, size_t len, size_t *olen)
{
    static int primed;
    mbedtls_sha256_context sh;
    u8 dig[32];
    u32 i, s[8];
    (void)data;
    mbedtls_sha256_init(&sh); mbedtls_sha256_starts(&sh, 0);
    if (!primed) {                                   /* 1 KB de DDR sin inicializar (final del heap TLS) y el estado del PL */
        mbedtls_sha256_update(&sh, tls_heap + TLS_HEAP_SIZE - 1024U, 1024U);
        primed = 1;
    }
    for (i = 0; i < 64U; i++) {
        u64 t = gt_now();
        s[0] = (u32)t; s[1] = (u32)(t >> 32); s[2] = cycles(); s[3] = Xil_In32(0xE000B158U); s[4] = Xil_In32(0xE000B15CU);
        s[5] = loop_ms;                              /* vueltas del bucle del companion (main.c) */
        s[6] = Xil_In32(0xF8F00200U); s[7] = i;
        mbedtls_sha256_update(&sh, (const u8 *)s, sizeof s);
        while ((cycles() & 0x3FU) != (i & 0x3FU)) { }   /* espera desigual: jitter del contador de ciclos */
    }
    mbedtls_sha256_finish(&sh, dig); mbedtls_sha256_free(&sh);
    if (len > 32U) len = 32U;
    for (i = 0; i < len; i++) output[i] = dig[i];
    *olen = len;
    return 0;
}

/* ---- BIO sobre lwIP ---------------------------------------------------------------------------------- */
static int bio_send(void *ctx, const unsigned char *buf, size_t len)
{
    struct esp_tls *t = (struct esp_tls *)ctx;
    u32 room;
    if (t->pcb == NULL) return MBEDTLS_ERR_NET_CONN_RESET;
    room = tcp_sndbuf(t->pcb);
    if (room == 0U) return MBEDTLS_ERR_SSL_WANT_WRITE;
    if (len > room) len = room;
    if (tcp_write(t->pcb, buf, (u16)len, TCP_WRITE_FLAG_COPY) != ERR_OK) return MBEDTLS_ERR_SSL_WANT_WRITE;
    tcp_output(t->pcb);
    return (int)len;
}

static int bio_recv(void *ctx, unsigned char *buf, size_t len)
{
    struct esp_tls *t = (struct esp_tls *)ctx;
    u32 n = *t->rx_total;
    if (n == 0U) return t->remote_closed ? 0 : MBEDTLS_ERR_SSL_WANT_READ;
    if (n > len) n = (u32)len;
    pbuf_copy_partial(*t->rxq, buf, (u16)n, 0);
    *t->rxq = pbuf_free_header(*t->rxq, (u16)n);
    *t->rx_total -= n;
    if (t->pcb) tcp_recved(t->pcb, (u16)n);
    return (int)n;
}

/* ---- arranque -------------------------------------------------------------------------------------- */
int tls_init(void)
{
    u32 v;
    __asm__ volatile ("mrc p15, 0, %0, c9, c12, 0" : "=r"(v));          /* PMU: contador de ciclos en marcha (entropia) */
    v |= 5U;
    __asm__ volatile ("mcr p15, 0, %0, c9, c12, 0" :: "r"(v));
    __asm__ volatile ("mcr p15, 0, %0, c9, c12, 1" :: "r"(0x80000000U));
    mbedtls_memory_buffer_alloc_init(tls_heap, TLS_HEAP_SIZE);
    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&drbg);
    if (mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy, (const unsigned char *)"msximus-z", 9) != 0) { log_str("tls: sin semilla\n"); return -1; }
    mbedtls_ssl_config_init(&conf);
    if (mbedtls_ssl_config_defaults(&conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT) != 0) { log_str("tls: sin config\n"); return -1; }
    mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &drbg);
    mbedtls_ssl_conf_max_frag_len(&conf, MBEDTLS_SSL_MAX_FRAG_LEN_4096);
    tls_ready = 1;
    log_str("tls: Mbed TLS " MBEDTLS_VERSION_STRING " listo (TLS 1.2, sin verificar certificados)\n");
    return 0;
}

int tls_available(void) { return tls_ready; }

/* ---- sesiones -------------------------------------------------------------------------------------- */
esp_tls_t *tls_new(struct tcp_pcb *pcb, struct pbuf **rxq, u32 *rx_total, const char *host)
{
    struct esp_tls *t;
    if (!tls_ready) return NULL;
    t = (struct esp_tls *)mbedtls_calloc(1, sizeof *t);
    if (t == NULL) return NULL;
    t->pt = (u8 *)mbedtls_calloc(1, TLS_PT_SIZE);
    if (t->pt == NULL) { mbedtls_free(t); return NULL; }
    t->pcb = pcb; t->rxq = rxq; t->rx_total = rx_total; t->t0 = sys_now();
    mbedtls_ssl_init(&t->ssl);
    if (mbedtls_ssl_setup(&t->ssl, &conf) != 0 || (host && host[0] && mbedtls_ssl_set_hostname(&t->ssl, host) != 0)) {
        log_str("tls: sin memoria para la sesion\n");
        mbedtls_ssl_free(&t->ssl); mbedtls_free(t->pt); mbedtls_free(t);
        return NULL;
    }
    mbedtls_ssl_set_bio(&t->ssl, t, bio_send, bio_recv, NULL);
    return t;
}

void tls_remote_closed(esp_tls_t *t) { if (t) t->remote_closed = 1; }
void tls_detach(esp_tls_t *t) { if (t) t->pcb = NULL; }        /* lwIP libero el pcb (error/reset) */

static void pt_pull(struct esp_tls *t)              /* del descifrador al anillo, mientras quepa */
{
    while (t->pt_n < TLS_PT_SIZE) {
        u32 room = TLS_PT_SIZE - t->pt_n, chunk = TLS_PT_SIZE - t->pt_wr;
        int r;
        if (chunk > room) chunk = room;
        r = mbedtls_ssl_read(&t->ssl, t->pt + t->pt_wr, chunk);
        if (r > 0) { t->pt_wr = (t->pt_wr + (u32)r) % TLS_PT_SIZE; t->pt_n += (u32)r; continue; }
        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE) return;
        if (r == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || r == 0) { t->state = 2; return; }
        t->state = -1; return;
    }
}

int tls_poll(esp_tls_t *t)
{
    int r;
    if (t == NULL) return -1;
    if (t->state == 0) {
        r = mbedtls_ssl_handshake(&t->ssl);
        if (r == 0) { t->state = 1; log_str("tls: handshake "); log_str(mbedtls_ssl_get_ciphersuite(&t->ssl)); log_str(" en "); log_dec(sys_now() - t->t0); log_str(" ms\n"); }
        else if (r != MBEDTLS_ERR_SSL_WANT_READ && r != MBEDTLS_ERR_SSL_WANT_WRITE) { t->state = -1; log_str("tls: handshake fallo -0x"); log_hex((u32)(-r)); log_str("\n"); }
        else if ((s32)(sys_now() - t->t0) > (s32)TLS_HS_MS) { t->state = -1; log_str("tls: handshake sin respuesta\n"); }
        else if (t->remote_closed && *t->rx_total == 0U) { t->state = -1; log_str("tls: el servidor cerro durante el handshake\n"); }
    }
    if (t->state == 1) pt_pull(t);
    return t->state;
}

u32 tls_avail(esp_tls_t *t) { return t ? t->pt_n : 0U; }

u32 tls_read(esp_tls_t *t, u8 *dst, u32 n)
{
    u32 i;
    if (t == NULL) return 0;
    if (n > t->pt_n) n = t->pt_n;
    for (i = 0; i < n; i++) { dst[i] = t->pt[t->pt_rd]; t->pt_rd = (t->pt_rd + 1U) % TLS_PT_SIZE; }
    t->pt_n -= n;
    if (t->state == 1) pt_pull(t);
    return n;
}

int tls_write(esp_tls_t *t, const u8 *src, u32 n)  /* todo o nada: >0 escrito, 0 sin sitio (reintentar), <0 error */
{
    int r;
    if (t == NULL || t->state != 1) return -1;
    if (t->pcb == NULL || tcp_sndbuf(t->pcb) < n + 128U) return 0;
    r = mbedtls_ssl_write(&t->ssl, src, n);
    if (r == MBEDTLS_ERR_SSL_WANT_WRITE || r == MBEDTLS_ERR_SSL_WANT_READ) return 0;
    if (r < 0) { t->state = -1; return -1; }
    return r;
}

int tls_state(esp_tls_t *t) { return t ? t->state : -1; }
int tls_closed(esp_tls_t *t) { return t == NULL || t->state == 2 || t->state < 0 || (t->remote_closed && *t->rx_total == 0U && t->pt_n == 0U); }

void tls_debug(esp_tls_t *t)
{
    if (t == NULL) { log_str("tls: (sin sesion)\n"); return; }
    log_str("tls: st="); log_dec((u32)(s32)t->state); log_str(" rxq="); log_dec(*t->rx_total);
    log_str(" dentro="); log_dec((u32)mbedtls_ssl_get_bytes_avail(&t->ssl)); log_str(" claro="); log_dec(t->pt_n);
    log_str(" cerrado="); log_dec(t->remote_closed);
    if (t->pcb) { log_str(" pcb="); log_dec((u32)t->pcb->state); log_str(" rcv_wnd="); log_dec(t->pcb->rcv_wnd); log_str("/"); log_dec(t->pcb->rcv_ann_wnd); log_str(" snd_buf="); log_dec(tcp_sndbuf(t->pcb)); }
    else log_str(" pcb=NULL");
    log_str(" gem rx="); log_dec(Xil_In32(0xE000B158U)); log_str(" res_err="); log_dec(Xil_In32(0xE000B1A0U)); log_str(" overrun="); log_dec(Xil_In32(0xE000B1A4U));
    log_str(" len_err="); log_dec(Xil_In32(0xE000B1A8U)); log_str(" fcs="); log_dec(Xil_In32(0xE000B190U)); log_str("\n");
}

void tls_free(esp_tls_t *t)
{
    if (t == NULL) return;
    if (t->state == 1 && t->pcb) (void)mbedtls_ssl_close_notify(&t->ssl);
    mbedtls_ssl_free(&t->ssl);
    mbedtls_free(t->pt);
    mbedtls_free(t);
}
