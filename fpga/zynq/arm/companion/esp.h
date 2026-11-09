/* esp.h — el companion como "ESP32" del MSX (25/09/2026, Ethernet P1).
 *
 * Habla el protocolo serie del ESP32-UNAPI-Firmware de ducasp (msx/ESP32-UNAPI-Firmware, documentation/README.md)
 * por la UART1 del PS (EMIO -> wifi_lite, I/O 06/07h del MSX), asi que el driver UNAPI del pack, la tecla W del menu
 * y el File-Hunter no cambian: ven un "ESP" con una sola red ("Ethernet") siempre conectada. El TCP/IP es lwIP sobre
 * el GEM0 (net.c). Tres ficheros: esp_link.c (UART, cola TX, analizador y despacho), esp_cmd.c (comandos propios y
 * UNAPI simples, ajustes, hora) y esp_tcp.c (TCP/UDP/DNS sobre la API raw de lwIP, sin bloquear el bucle). */
#ifndef ESP_H
#define ESP_H
#include "xil_types.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"

#define ESP_MAX_DATA    2148U                   /* MAX_CMD_DATA_LEN del firmware */
#define ESP_NCONN       4U
#define ESP_UDPQ        8U                      /* datagramas UDP en espera por conexion */
#define ESP_TRACE       0                       /* 1 = comandos, respuestas (con ms) y consultas DNS al log del ARM (lo inunda) */
#define ESP_VER_MAJOR   1U
#define ESP_VER_MINOR   0U

/* codigos de error TCP/IP UNAPI (los del firmware) */
enum { UE_OK = 0, UE_NOT_IMP, UE_NO_NETWORK, UE_NO_DATA, UE_INV_PARAM, UE_QUERY_EXISTS, UE_INV_IP, UE_NO_DNS, UE_DNS,
       UE_NO_FREE_CONN, UE_CONN_EXISTS, UE_NO_CONN, UE_CONN_STATE, UE_BUFFER, UE_LARGE_DGRAM, UE_INV_OPER };

enum { CONN_CLOSED = 0, CONN_UDP = 1, CONN_TCP_ACTIVE = 2, CONN_TCP_PASSIVE = 3, CONN_TCP_VIRT = 4 };   /* VIRT: tsx.msximus (esp_tsx.c) */

typedef struct { struct pbuf *p; u8 ip[4]; u16 port; } esp_dgram_t;
struct esp_tls;                                 /* esp_tls.c */

typedef struct {
    u8  type;                                   /* CONN_* */
    u8  transient;                              /* se cierra con CLOSE/ABORT 0 */
    u8  remote_closed;                          /* el otro extremo cerro (o error): estado 7 */
    u8  n_dgram;                                /* UDP: datagramas en cola */
    u16 local_port, remote_port;
    u8  remote_ip[4];
    struct tcp_pcb *tpcb;                       /* TCP activa o aceptada */
    struct tcp_pcb *lpcb;                       /* TCP pasiva: el listen */
    struct udp_pcb *upcb;
    struct pbuf *rxq;                           /* TCP: cadena de pbufs pendientes de que el MSX los lea */
    u32 rx_total;                               /* bytes en rxq */
    struct esp_tls *tls;                        /* TCP activa con TLS (26/09): rxq es el cifrado, se lee via tls_read */
    u8  tls_want;                               /* TCP_OPEN pidio TLS (motivo 19 si falla) */
    esp_dgram_t dq[ESP_UDPQ];                   /* UDP: cola de datagramas (el mas viejo en dq[0]) */
} esp_conn_t;

/* respuesta pendiente (una operacion que tarda: TCP_OPEN, DNS, hora); el enlace no lee mas hasta resolverla */
enum { PEND_NONE = 0, PEND_TCP_OPEN, PEND_DNS, PEND_TIME };
typedef struct {
    u8  kind, cmd, conn;
    u32 deadline;                               /* sys_now() limite */
} esp_pend_t;

/* ---- esp_link.c ---- */
void esp_init(void);
void esp_poll(void);
void esp_send(u8 cmd, u8 err, const u8 *data, u32 n);   /* CMD, ERR, tam MSB, tam LSB, datos (y se guarda para 'r') */
void esp_send_quick(u8 cmd, u8 err);                    /* CMD, ERR */
void esp_send_raw(const u8 *p, u32 n);                  /* sin cabecera ("OK", "Ready", 'V'...) */
void esp_pend_set(u8 kind, u8 cmd, u8 conn, u32 ms);
void esp_pend_clear(void);
extern esp_pend_t esp_pend;
extern u8 esp_data[ESP_MAX_DATA + 1];                   /* parametros del comando en curso (+1 para el 0 final) */

/* ---- esp_cmd.c ---- */
void esp_exec(u8 cmd, u32 len);                          /* despacho de un comando completo (datos en esp_data) */
void esp_cmd_poll(void);                                 /* pendientes de esp_cmd (hora) */
void esp_warm_reset(void);
int  esp_net_ok(void);                                   /* enlace + IP */
int  esp_link_up(void);
void esp_time_set(unsigned long sec);                    /* SNTP -> hora (lwipopts.h SNTP_SET_SYSTEM_TIME) */
extern u8 esp_nagle;                                     /* 1 = Nagle activo (comando 'D'), 0 = desactivado ('N') */

/* ---- esp_tcp.c ---- */
void esp_tcp_exec(u8 cmd, u32 len);                      /* comandos UNAPI de conexiones y DNS */
void esp_tcp_poll(void);                                 /* vencimientos de TCP_OPEN / DNS */
void esp_tcp_close_all(int only_transient);
u8   esp_tcp_open_count(void);
extern esp_conn_t esp_conn[ESP_NCONN];

/* ---- esp_tls.c: sesiones TLS (Mbed TLS) sobre un pcb de lwIP; nada bloquea (tls_poll cada vuelta) ---- */
struct tcp_pcb; struct pbuf;
typedef struct esp_tls esp_tls_t;
int  tls_init(void);                                     /* tras net_init: entropia, DRBG, config */
int  tls_available(void);
esp_tls_t *tls_new(struct tcp_pcb *pcb, struct pbuf **rxq, u32 *rx_total, const char *host);   /* pcb ya conectado */
int  tls_poll(esp_tls_t *t);                             /* 0 handshake, 1 lista, 2 el par cerro, <0 error */
int  tls_state(esp_tls_t *t);
int  tls_closed(esp_tls_t *t);
u32  tls_avail(esp_tls_t *t);
u32  tls_read(esp_tls_t *t, u8 *dst, u32 n);
int  tls_write(esp_tls_t *t, const u8 *src, u32 n);      /* todo o nada: >0 escrito, 0 sin sitio, <0 error */
void tls_remote_closed(esp_tls_t *t);
void tls_debug(esp_tls_t *t);                            /* al log: estado, bytes en rxq, en Mbed TLS y en claro, ventana TCP, GEM */
void tls_detach(esp_tls_t *t);
void tls_free(esp_tls_t *t);

/* ---- esp_tsx.c: el host virtual tsx.msximus (catalogo de cintas TSX, formato del File-Hunter) ---- */
int  tsx_is_magic(const char *name);
void tsx_open(u8 slot);
void tsx_close(u8 slot);
void tsx_write(u8 slot, const u8 *p, u32 n);
u32  tsx_avail(u8 slot);
u32  tsx_read(u8 slot, u8 *dst, u32 n);
int  tsx_connected(u8 slot);
int  tsx_finished(u8 slot);
void tsx_poll(void);                                     /* la descarga https de una cinta (esp_tcp_poll) */
#endif
