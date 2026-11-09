/* esp_tcp.c — conexiones TCP/UDP y DNS del "ESP32" del companion sobre la API raw de lwIP (25/09/2026, P1).
 *
 * Cuatro conexiones (como el firmware), numeradas 1..4. Nada bloquea el bucle del companion: TCP_OPEN activo y las
 * consultas DNS dejan la respuesta pendiente (esp_pend) y la mandan desde la llamada de vuelta de lwIP o al vencer
 * el plazo; mientras tanto el enlace no lee mas bytes (el ESP real bloquea, el MSX espera igual). Lo recibido por
 * TCP se encadena en pbufs hasta que el MSX lo pide con TCP_RCV (y entonces se hace tcp_recved); UDP guarda hasta
 * ESP_UDPQ datagramas por conexion. Formatos y codigos de error calcados del firmware (ver README y el .ino).
 * 26/09 (P2): TCP_OPEN con el bit 2 de los flags = TLS (esp_tls.c): la respuesta espera al handshake (o 25 s), el
 * nombre de host (desde el byte 11) va como SNI, fallo = error 11 motivo 19 como el firmware; TCP_STATE lleva 1 (TLS
 * conectada) o 19 en el primer byte; SEND/RCV pasan por Mbed TLS. Sin verificar certificados (el bit 3 se ignora). */
#include "xil_types.h"
#include "lwip/sys.h"
#include "lwip/netif.h"
#include "lwip/dns.h"
#include "lwip/ip4_addr.h"
#include "log.h"
#include "esp.h"

esp_conn_t esp_conn[ESP_NCONN];
static char tls_host[256];                      /* nombre de host del TCP_OPEN con TLS en curso (SNI) */

/* ---- utilidades ---------------------------------------------------------------------------------------- */
static void ip_to_bytes(u8 *d, const ip_addr_t *a)
{
    const ip4_addr_t *a4 = ip_2_ip4(a);
    d[0] = ip4_addr1(a4); d[1] = ip4_addr2(a4); d[2] = ip4_addr3(a4); d[3] = ip4_addr4(a4);
}

u8 esp_tcp_open_count(void)
{
    u8 n = 0, i;
    for (i = 0; i < ESP_NCONN; i++) if (esp_conn[i].type != CONN_CLOSED) n++;
    return n;
}

static int free_slot(void)
{
    int i;
    for (i = 0; i < (int)ESP_NCONN; i++) if (esp_conn[i].type == CONN_CLOSED) return i;
    return -1;
}

static int port_in_use(u16 port)
{
    u8 i;
    for (i = 0; i < ESP_NCONN; i++) if (esp_conn[i].type != CONN_CLOSED && esp_conn[i].local_port == port) return 1;
    return 0;
}

static u16 pick_port(u16 want)                  /* 0xFFFF = uno libre al azar entre 16384 y 32767, como el firmware */
{
    if (want != 0xFFFFU) return want;
    do { want = (u16)(16384U + ((u32)LWIP_RAND() % 16384U)); } while (port_in_use(want));
    return want;
}

static void rxq_free(esp_conn_t *c)
{
    if (c->rxq) pbuf_free(c->rxq);
    c->rxq = NULL; c->rx_total = 0;
}

static void conn_clear(esp_conn_t *c)
{
    u8 i;
    rxq_free(c);
    for (i = 0; i < c->n_dgram; i++) if (c->dq[i].p) pbuf_free(c->dq[i].p);
    c->n_dgram = 0;
    if (c->tls) { tls_free(c->tls); c->tls = NULL; }
    c->tls_want = 0;
    c->type = CONN_CLOSED; c->tpcb = NULL; c->lpcb = NULL; c->upcb = NULL; c->remote_closed = 0;
    c->local_port = 0; c->remote_port = 0; c->remote_ip[0] = c->remote_ip[1] = c->remote_ip[2] = c->remote_ip[3] = 0;
}

/* ---- llamadas de vuelta de lwIP (TCP) ----------------------------------------------------------------- */
static void tcp_err_cb(void *arg, err_t err)     /* lwIP ya ha liberado el pcb */
{
    esp_conn_t *c = (esp_conn_t *)arg;
    (void)err;
    c->tpcb = NULL; c->remote_closed = 1;
    if (c->tls) { tls_detach(c->tls); tls_remote_closed(c->tls); }
    if (esp_pend.kind == PEND_TCP_OPEN && &esp_conn[esp_pend.conn] == c) {   /* fallo al conectar */
        u8 reason = c->tls_want ? 19U : 0U;
        conn_clear(c);
        esp_send(13, UE_NO_CONN, &reason, 1);
        esp_pend_clear();
    }
}

static err_t tcp_recv_cb(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err)
{
    esp_conn_t *c = (esp_conn_t *)arg;
    (void)err;
    if (p == NULL) { c->remote_closed = 1; if (c->tls) tls_remote_closed(c->tls); return ERR_OK; }   /* el otro extremo cerro: estado 7 */
    if (c->rxq) pbuf_cat(c->rxq, p); else c->rxq = p;
    c->rx_total += p->tot_len;
    (void)pcb;
    return ERR_OK;
}

static err_t tcp_connected_cb(void *arg, struct tcp_pcb *pcb, err_t err)
{
    esp_conn_t *c = (esp_conn_t *)arg;
    u8 num = (u8)((c - esp_conn) + 1);
    (void)err;
    c->local_port = pcb->local_port; c->remote_port = pcb->remote_port;
    ip_to_bytes(c->remote_ip, &pcb->remote_ip);
    if (c->tls_want) {                                                     /* TLS: la respuesta sale al acabar el handshake (esp_tcp_poll) */
        c->tls = tls_new(pcb, &c->rxq, &c->rx_total, tls_host[0] ? tls_host : NULL);
        if (c->tls == NULL) {
            u8 reason = 19;
            tcp_arg(pcb, NULL); tcp_recv(pcb, NULL); tcp_err(pcb, NULL); tcp_abort(pcb); c->tpcb = NULL;
            conn_clear(c);
            if (esp_pend.kind == PEND_TCP_OPEN && esp_pend.conn == num - 1U) { esp_send(13, UE_NO_CONN, &reason, 1); esp_pend_clear(); }
            return ERR_ABRT;
        }
        return ERR_OK;
    }
    if (esp_pend.kind == PEND_TCP_OPEN && esp_pend.conn == num - 1U) { esp_send(13, UE_OK, &num, 1); esp_pend_clear(); }
    return ERR_OK;
}

static err_t tcp_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err)
{
    esp_conn_t *c = (esp_conn_t *)arg;
    if (err != ERR_OK || newpcb == NULL) return ERR_VAL;
    if (c->tpcb != NULL) { tcp_abort(newpcb); return ERR_ABRT; }        /* un cliente por escucha, como el firmware */
    c->tpcb = newpcb; c->remote_closed = 0;
    c->remote_port = newpcb->remote_port; ip_to_bytes(c->remote_ip, &newpcb->remote_ip);
    tcp_arg(newpcb, c); tcp_recv(newpcb, tcp_recv_cb); tcp_err(newpcb, tcp_err_cb);
    if (!esp_nagle) tcp_nagle_disable(newpcb);
    return ERR_OK;
}

static void udp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    esp_conn_t *c = (esp_conn_t *)arg;
    (void)pcb;
    if (c->n_dgram >= ESP_UDPQ) { pbuf_free(p); return; }
    c->dq[c->n_dgram].p = p; ip_to_bytes(c->dq[c->n_dgram].ip, addr); c->dq[c->n_dgram].port = port;
    c->n_dgram++;
}

static void dns_found_cb(const char *name, const ip_addr_t *ipaddr, void *arg)
{
    u8 r[4];
    (void)name; (void)arg;
#if ESP_TRACE
    log_str(ipaddr ? " dns_cb:ip" : " dns_cb:NULL");
#endif
    if (esp_pend.kind != PEND_DNS) return;
    if (ipaddr == NULL || ip_addr_isany(ipaddr) || ip4_addr_isbroadcast_u32(ip4_addr_get_u32(ip_2_ip4(ipaddr)), netif_default)) esp_send(esp_pend.cmd, UE_DNS, 0, 0);
    else { ip_to_bytes(r, ipaddr); esp_send(esp_pend.cmd, UE_OK, r, 4); }
    esp_pend_clear();
}

/* ---- cierre --------------------------------------------------------------------------------------------- */
static void tcp_close_conn(esp_conn_t *c)
{
    if (c->type == CONN_TCP_VIRT) tsx_close((u8)(c - esp_conn));
    if (c->tls) { tls_free(c->tls); c->tls = NULL; }                     /* close_notify mientras el pcb vive */
    if (c->tpcb) { tcp_arg(c->tpcb, NULL); tcp_recv(c->tpcb, NULL); tcp_err(c->tpcb, NULL); if (tcp_close(c->tpcb) != ERR_OK) tcp_abort(c->tpcb); }
    if (c->lpcb) tcp_close(c->lpcb);
    conn_clear(c);
}

static void udp_close_conn(esp_conn_t *c)
{
    if (c->upcb) udp_remove(c->upcb);
    conn_clear(c);
}

void esp_tcp_close_all(int only_transient)
{
    u8 i;
    for (i = 0; i < ESP_NCONN; i++) {
        esp_conn_t *c = &esp_conn[i];
        if (c->type == CONN_CLOSED || (only_transient && !c->transient)) continue;
        if (c->type == CONN_UDP) udp_close_conn(c); else tcp_close_conn(c);
    }
}

void esp_tcp_poll(void)
{
    u8 i;
    tsx_poll();                                                         /* la descarga https de una cinta, si la hay */
    for (i = 0; i < ESP_NCONN; i++)                                     /* virtuales entregadas que el menu no cerro */
        if (esp_conn[i].type == CONN_TCP_VIRT && tsx_finished(i)) tcp_close_conn(&esp_conn[i]);
    for (i = 0; i < ESP_NCONN; i++) {                                   /* sesiones TLS: handshake y descifrado */
        esp_conn_t *c = &esp_conn[i];
        int st;
        if (c->tls == NULL) continue;
        st = tls_poll(c->tls);
        if (esp_pend.kind == PEND_TCP_OPEN && esp_pend.conn == i) {
            if (st == 1) { u8 num = (u8)(i + 1U); esp_send(13, UE_OK, &num, 1); esp_pend_clear(); }
            else if (st < 0) { u8 reason = 19; tcp_close_conn(c); esp_send(13, UE_NO_CONN, &reason, 1); esp_pend_clear(); }
        } else if (st < 0 || st == 2) c->remote_closed = 1;
    }
    if (esp_pend.kind == PEND_TCP_OPEN && (s32)(sys_now() - esp_pend.deadline) >= 0) {
        esp_conn_t *c = &esp_conn[esp_pend.conn];
        u8 reason = c->tls_want ? 19U : 0U;
        if (c->tpcb) { tcp_arg(c->tpcb, NULL); tcp_recv(c->tpcb, NULL); tcp_err(c->tpcb, NULL); tcp_abort(c->tpcb); c->tpcb = NULL; }
        if (c->tls) tls_detach(c->tls);
        conn_clear(c);
        esp_send(13, UE_NO_CONN, &reason, 1);
        esp_pend_clear();
    }
    if (esp_pend.kind == PEND_DNS && (s32)(sys_now() - esp_pend.deadline) >= 0) { esp_send(esp_pend.cmd, UE_DNS, 0, 0); esp_pend_clear(); }
}

/* ---- DNS -------------------------------------------------------------------------------------------------- */
static int parse_ip(const char *s, u8 *out)      /* "a.b.c.d" estricto */
{
    u32 v = 0, n = 0, dots = 0, digits = 0;
    for (; *s; s++) {
        if (*s >= '0' && *s <= '9') { v = v * 10U + (u32)(*s - '0'); digits++; if (v > 255U || digits > 3U) return 0; }
        else if (*s == '.') { if (!digits || dots == 3U) return 0; out[n++] = (u8)v; v = 0; digits = 0; dots++; }
        else return 0;
    }
    if (dots != 3U || !digits) return 0;
    out[3] = (u8)v;
    return 1;
}

static void dns_query(u8 cmd, const char *name, u8 flags)
{
    u8 r[4];
    ip_addr_t a;
    err_t e;
#if ESP_TRACE
    log_str(" dns["); log_str(name); log_str("]");
#endif
    if (tsx_is_magic(name)) { r[0] = 127; r[1] = 0; r[2] = 0; r[3] = 1; esp_send(cmd, UE_OK, r, 4); return; }   /* el catalogo TSX, en casa */
    if (parse_ip(name, r)) { esp_send(cmd, UE_OK, r, 4); return; }
    if (flags & 2U) { esp_send(cmd, UE_INV_IP, 0, 0); return; }           /* "es una IP" y no lo era */
    if (!esp_net_ok()) { esp_send(cmd, UE_DNS, 0, 0); return; }
    e = dns_gethostbyname(name, &a, dns_found_cb, NULL);
#if ESP_TRACE
    log_str(" dns_e="); log_dec((u32)(s32)e);
#endif
    if (e == ERR_OK) { ip_to_bytes(r, &a); esp_send(cmd, UE_OK, r, 4); }
    else if (e == ERR_INPROGRESS) esp_pend_set(PEND_DNS, cmd, 0, 15000U);
    else esp_send(cmd, UE_DNS, 0, 0);
}

/* ---- TCP ---------------------------------------------------------------------------------------------- */
static void tcp_open(u32 len)
{
    u8 flags, num, *d = esp_data;
    u16 rport, lport;
    int s;
    ip_addr_t ra;
    esp_conn_t *c;
    if (len < 11U) { esp_send(13, UE_INV_PARAM, 0, 0); return; }
    rport = (u16)(d[4] | (d[5] << 8)); lport = (u16)(d[6] | (d[7] << 8)); flags = d[10];
    if (lport == 0U || (flags & 0xF0U) || ((flags & 4U) && len < 12U) || ((flags & 1U) && (flags & 4U)) ||
        (!(flags & 1U) && !(flags & 4U) && (flags & 8U)) || (!(flags & 1U) && (d[0] | d[1] | d[2] | d[3]) == 0U) ||
        ((flags & 1U) && (d[0] | d[1] | d[2] | d[3]) != 0U)) { esp_send(13, UE_INV_PARAM, 0, 0); return; }
    if (!(flags & 1U) && d[0] == 127U && d[1] == 0U && d[2] == 0U && d[3] == 1U) {   /* 127.0.0.1 = conexion virtual (tsx.msximus) */
        s = free_slot();
        if (s < 0) { esp_send(13, UE_NO_FREE_CONN, 0, 0); return; }
        c = &esp_conn[s]; num = (u8)(s + 1);
        conn_clear(c);
        c->type = CONN_TCP_VIRT; c->transient = (flags & 2U) ? 0U : 1U; c->local_port = pick_port(lport); c->remote_port = rport;
        c->remote_ip[0] = 127; c->remote_ip[3] = 1;
        tsx_open((u8)s);
        esp_send(13, UE_OK, &num, 1);
        return;
    }
    if (!esp_net_ok()) { esp_send(13, UE_NO_NETWORK, 0, 0); return; }
    tls_host[0] = 0;
    if (flags & 4U) {                                                      /* TLS (26/09): SNI = nombre de host si viene */
        u32 k, hl = len - 11U;
        if (!tls_available()) { esp_send(13, UE_NOT_IMP, 0, 0); return; }
        if (hl > sizeof tls_host - 1U) hl = sizeof tls_host - 1U;
        for (k = 0; k < hl && d[11 + k]; k++) tls_host[k] = (char)d[11 + k];
        tls_host[k] = 0;
    }
    s = free_slot();
    if (s < 0) { esp_send(13, UE_NO_FREE_CONN, 0, 0); return; }
    c = &esp_conn[s]; num = (u8)(s + 1);
    conn_clear(c);
    c->transient = (flags & 2U) ? 0U : 1U;
    if (flags & 1U) {                                                      /* pasiva */
        struct tcp_pcb *p = tcp_new();
        lport = pick_port(lport);
        if (p == NULL) { esp_send(13, UE_NO_FREE_CONN, 0, 0); return; }
        if (tcp_bind(p, IP_ADDR_ANY, lport) != ERR_OK) { tcp_abort(p); esp_send(13, UE_CONN_EXISTS, 0, 0); return; }
        c->lpcb = tcp_listen_with_backlog(p, 1);
        if (c->lpcb == NULL) { tcp_abort(p); esp_send(13, UE_NO_FREE_CONN, 0, 0); return; }
        tcp_arg(c->lpcb, c); tcp_accept(c->lpcb, tcp_accept_cb);
        c->type = CONN_TCP_PASSIVE; c->local_port = lport;
        esp_send(13, UE_OK, &num, 1);
        return;
    }
    if (port_in_use(lport) && lport != 0xFFFFU) { esp_send(13, UE_CONN_EXISTS, 0, 0); return; }
    lport = pick_port(lport);
    c->tpcb = tcp_new();
    if (c->tpcb == NULL) { esp_send(13, UE_NO_FREE_CONN, 0, 0); return; }
    if (tcp_bind(c->tpcb, IP_ADDR_ANY, lport) != ERR_OK) { tcp_abort(c->tpcb); c->tpcb = NULL; esp_send(13, UE_CONN_EXISTS, 0, 0); return; }
    IP4_ADDR(ip_2_ip4(&ra), d[0], d[1], d[2], d[3]);
    c->type = CONN_TCP_ACTIVE; c->local_port = lport; c->remote_port = rport; c->tls_want = (flags & 4U) ? 1U : 0U;
    c->remote_ip[0] = d[0]; c->remote_ip[1] = d[1]; c->remote_ip[2] = d[2]; c->remote_ip[3] = d[3];
    tcp_arg(c->tpcb, c); tcp_recv(c->tpcb, tcp_recv_cb); tcp_err(c->tpcb, tcp_err_cb);
    if (!esp_nagle) tcp_nagle_disable(c->tpcb);
    esp_pend_set(PEND_TCP_OPEN, 13, (u8)s, c->tls_want ? 25000U : 10000U); /* la respuesta sale al conectar (o al vencer) */
    if (tcp_connect(c->tpcb, &ra, rport, tcp_connected_cb) != ERR_OK) {
        u8 reason = 0;
        tcp_abort(c->tpcb); c->tpcb = NULL; conn_clear(c); esp_pend_clear();
        esp_send(13, UE_NO_CONN, &reason, 1);
    }
}

static void tcp_close_cmd(u8 cmd, u32 len)
{
    u8 num = esp_data[0];
    if (len != 1U) { esp_send(cmd, UE_INV_PARAM, 0, 0); return; }
    if (num > ESP_NCONN) { esp_send(cmd, UE_NO_CONN, 0, 0); return; }
    if (num == 0U) {                                                       /* todas las transitorias */
        u8 i;
        for (i = 0; i < ESP_NCONN; i++) if (esp_conn[i].type >= CONN_TCP_ACTIVE && esp_conn[i].transient) tcp_close_conn(&esp_conn[i]);
        esp_send(cmd, UE_OK, 0, 0); return;
    }
    if (esp_conn[num - 1U].type < CONN_TCP_ACTIVE) { esp_send(cmd, UE_NO_CONN, 0, 0); return; }
    tcp_close_conn(&esp_conn[num - 1U]);
    esp_send(cmd, UE_OK, 0, 0);
}

static void tcp_state_cmd(u32 len)
{
    u8 num = esp_data[0], r[16];
    esp_conn_t *c;
    u32 i, avail, space;
    if (len != 1U) { esp_send(16, UE_INV_PARAM, 0, 0); return; }
    if (num == 0U || num > ESP_NCONN || esp_conn[num - 1U].type < CONN_TCP_ACTIVE) { esp_send(16, UE_NO_CONN, 0, 0); return; }
    c = &esp_conn[num - 1U];
    for (i = 0; i < 16U; i++) r[i] = 0;
    if (c->type == CONN_TCP_PASSIVE && c->tpcb == NULL) {                 /* escuchando */
        r[1] = 1; r[14] = (u8)c->local_port; r[15] = (u8)(c->local_port >> 8);
        esp_send(16, UE_OK, r, 16); return;
    }
    if (c->type == CONN_TCP_VIRT) {
        avail = tsx_avail((u8)(num - 1U));
        r[1] = (avail || tsx_connected((u8)(num - 1U))) ? 4U : 7U;
        if (avail > 0xFFFFU) avail = 0xFFFFU;
        r[2] = (u8)avail; r[3] = (u8)(avail >> 8); r[6] = 0; r[7] = 8;                     /* 2048 libres */
        r[8] = 127; r[11] = 1; r[12] = (u8)c->remote_port; r[13] = (u8)(c->remote_port >> 8);
        r[14] = (u8)c->local_port; r[15] = (u8)(c->local_port >> 8);
        esp_send(16, UE_OK, r, 16); return;
    }
    if (c->tls) {                                                          /* TLS: byte 0 = 1 conectada / 19 no (como el firmware) */
        int st = tls_state(c->tls);
        avail = tls_avail(c->tls);
        r[0] = (st == 1) ? 1U : 19U;
        r[1] = (avail || (st == 1 && c->tpcb && !c->remote_closed && !tls_closed(c->tls))) ? 4U : 7U;
        if (avail > 0xFFFFU) avail = 0xFFFFU;
        r[2] = (u8)avail; r[3] = (u8)(avail >> 8);
        space = (st == 1 && c->tpcb) ? tcp_sndbuf(c->tpcb) : 0U;
        space = space > 2048U + 160U ? 2048U : (space > 160U ? space - 160U : 0U);   /* 160: cabecera+MAC del registro */
        r[6] = (u8)space; r[7] = (u8)(space >> 8);
        r[8] = c->remote_ip[0]; r[9] = c->remote_ip[1]; r[10] = c->remote_ip[2]; r[11] = c->remote_ip[3];
        r[12] = (u8)c->remote_port; r[13] = (u8)(c->remote_port >> 8);
        r[14] = (u8)c->local_port; r[15] = (u8)(c->local_port >> 8);
        esp_send(16, UE_OK, r, 16); return;
    }
    avail = c->rx_total;
    if (avail) r[1] = 4;                                                   /* con datos, "establecida" aunque el otro cerrara */
    else r[1] = (c->tpcb && !c->remote_closed && c->tpcb->state == ESTABLISHED) ? 4U : 7U;
    if (avail > 0xFFFFU) avail = 0xFFFFU;
    r[2] = (u8)avail; r[3] = (u8)(avail >> 8);
    space = c->tpcb ? tcp_sndbuf(c->tpcb) : 0U;
    if (space > 2048U) space = 2048U;
    r[6] = (u8)space; r[7] = (u8)(space >> 8);
    r[8] = c->remote_ip[0]; r[9] = c->remote_ip[1]; r[10] = c->remote_ip[2]; r[11] = c->remote_ip[3];
    r[12] = (u8)c->remote_port; r[13] = (u8)(c->remote_port >> 8);
    r[14] = (u8)c->local_port; r[15] = (u8)(c->local_port >> 8);
    esp_send(16, UE_OK, r, 16);
}

static void tcp_send_cmd(u32 len)
{
    u8 num = esp_data[0];
    esp_conn_t *c;
    u32 n = len - 2U;
    if (len < 3U || (esp_data[1] & 0xFEU)) { esp_send(17, UE_NO_CONN, 0, 0); return; }   /* como el firmware */
    if (num == 0U || num > ESP_NCONN || esp_conn[num - 1U].type < CONN_TCP_ACTIVE) { esp_send(17, UE_NO_CONN, 0, 0); return; }
    if (esp_conn[num - 1U].type != CONN_TCP_VIRT && !esp_net_ok()) { esp_send(17, UE_NO_NETWORK, 0, 0); return; }
    c = &esp_conn[num - 1U];
    if (c->type == CONN_TCP_VIRT) { tsx_write((u8)(num - 1U), &esp_data[2], n); esp_send(17, UE_OK, 0, 0); return; }
    if (c->tls) {
        int r;
        if (c->tpcb == NULL || c->remote_closed || tls_state(c->tls) != 1) { esp_send(17, UE_CONN_STATE, 0, 0); return; }
        r = tls_write(c->tls, &esp_data[2], n);
        esp_send(17, r > 0 ? UE_OK : (r == 0 ? UE_BUFFER : UE_CONN_STATE), 0, 0);
        return;
    }
    if (c->tpcb == NULL || c->remote_closed || c->tpcb->state != ESTABLISHED) { esp_send(17, UE_CONN_STATE, 0, 0); return; }
    if (tcp_sndbuf(c->tpcb) < n || tcp_write(c->tpcb, &esp_data[2], (u16)n, TCP_WRITE_FLAG_COPY) != ERR_OK) { esp_send(17, UE_BUFFER, 0, 0); return; }
    tcp_output(c->tpcb);
    esp_send(17, UE_OK, 0, 0);
}

static void tcp_rcv_cmd(u32 len)
{
    static u8 out[2 + 2048];
    u8 num = esp_data[0];
    esp_conn_t *c;
    u32 want = (u32)(esp_data[1] | (esp_data[2] << 8)), n;
    if (len != 3U) { esp_send(18, UE_INV_PARAM, 0, 0); return; }
    if (num == 0U || num > ESP_NCONN || esp_conn[num - 1U].type < CONN_TCP_ACTIVE) { esp_send(18, UE_NO_CONN, 0, 0); return; }
    c = &esp_conn[num - 1U];
    if (want > 2048U) want = 2048U;
    if (c->type == CONN_TCP_VIRT) {
        out[0] = 0; out[1] = 0;
        n = tsx_read((u8)(num - 1U), &out[2], want);
        esp_send(18, UE_OK, out, n ? n + 2U : 0U);
        return;
    }
    if (c->tls) {
        if (c->tpcb == NULL && tls_avail(c->tls) == 0U) { esp_send(18, UE_NO_CONN, 0, 0); return; }
        out[0] = 0; out[1] = 0;
        n = tls_read(c->tls, &out[2], want);
        esp_send(18, UE_OK, out, n ? n + 2U : 0U);
        return;
    }
    if (c->tpcb == NULL && c->rxq == NULL) { esp_send(18, UE_NO_CONN, 0, 0); return; }
    n = c->rx_total < want ? c->rx_total : want;
    out[0] = 0; out[1] = 0;                                                /* urgentes: 0 */
    if (n) {
        pbuf_copy_partial(c->rxq, &out[2], (u16)n, 0);
        c->rxq = pbuf_free_header(c->rxq, (u16)n);
        c->rx_total -= n;
        if (c->tpcb) tcp_recved(c->tpcb, (u16)n);
    }
    esp_send(18, UE_OK, out, n ? n + 2U : 0U);
}

/* ---- UDP ---------------------------------------------------------------------------------------------- */
static void udp_open(u32 len)
{
    u16 lport = (u16)(esp_data[0] | (esp_data[1] << 8));
    u8 num;
    int s;
    esp_conn_t *c;
    if (len != 3U || lport == 0U || (lport >= 0xFFF0U && lport != 0xFFFFU) || esp_data[2] > 1U) { esp_send(8, UE_INV_PARAM, 0, 0); return; }
    if (!esp_net_ok()) { esp_send(8, UE_NO_NETWORK, 0, 0); return; }
    if (lport != 0xFFFFU && port_in_use(lport)) { esp_send(8, UE_CONN_EXISTS, 0, 0); return; }
    s = free_slot();
    if (s < 0) { esp_send(8, UE_NO_FREE_CONN, 0, 0); return; }
    c = &esp_conn[s]; num = (u8)(s + 1);
    conn_clear(c);
    lport = pick_port(lport);
    c->upcb = udp_new();
    if (c->upcb == NULL) { esp_send(8, UE_NO_FREE_CONN, 0, 0); return; }
    if (udp_bind(c->upcb, IP_ADDR_ANY, lport) != ERR_OK) { udp_remove(c->upcb); c->upcb = NULL; esp_send(8, UE_CONN_EXISTS, 0, 0); return; }
    udp_recv(c->upcb, udp_recv_cb, c);
    c->type = CONN_UDP; c->local_port = lport; c->transient = esp_data[2];
    esp_send(8, UE_OK, &num, 1);
}

static void udp_close_cmd(u32 len)
{
    u8 num = esp_data[0], i;
    if (len != 1U) { esp_send(9, UE_INV_PARAM, 0, 0); return; }
    if (num > ESP_NCONN) { esp_send(9, UE_NO_CONN, 0, 0); return; }
    if (num == 0U) {
        for (i = 0; i < ESP_NCONN; i++) if (esp_conn[i].type == CONN_UDP && esp_conn[i].transient) udp_close_conn(&esp_conn[i]);
        esp_send(9, UE_OK, 0, 0); return;
    }
    if (esp_conn[num - 1U].type != CONN_UDP) { esp_send(9, UE_NO_CONN, 0, 0); return; }
    udp_close_conn(&esp_conn[num - 1U]);
    esp_send(9, UE_OK, 0, 0);
}

static void udp_state_cmd(u32 len)
{
    u8 num = esp_data[0], r[5];
    esp_conn_t *c;
    u32 sz;
    if (len != 1U) { esp_send(10, UE_INV_PARAM, 0, 0); return; }
    if (num == 0U || num > ESP_NCONN || esp_conn[num - 1U].type != CONN_UDP) { esp_send(10, UE_NO_CONN, 0, 0); return; }
    c = &esp_conn[num - 1U];
    sz = c->n_dgram ? c->dq[0].p->tot_len : 0U;
    r[0] = (u8)c->local_port; r[1] = (u8)(c->local_port >> 8); r[2] = c->n_dgram ? 1U : 0U; r[3] = (u8)sz; r[4] = (u8)(sz >> 8);
    esp_send(10, UE_OK, r, 5);
}

static void udp_send_cmd(u32 len)
{
    u8 num = esp_data[0];
    esp_conn_t *c;
    struct pbuf *p;
    ip_addr_t a;
    u16 port = (u16)(esp_data[5] | (esp_data[6] << 8));
    if (len < 8U) { esp_send(11, UE_INV_PARAM, 0, 0); return; }
    if (num == 0U || num > ESP_NCONN) { esp_send(11, UE_NO_CONN, 0, 0); return; }
    c = &esp_conn[num - 1U];
    if (c->type != CONN_UDP) { esp_send(11, UE_NO_NETWORK, 0, 0); return; }   /* si, el firmware devuelve 2 aqui */
    if (!esp_net_ok()) { esp_send(11, UE_NO_CONN, 0, 0); return; }
    p = pbuf_alloc(PBUF_TRANSPORT, (u16)(len - 7U), PBUF_RAM);
    if (p == NULL) { esp_send(11, UE_BUFFER, 0, 0); return; }
    pbuf_take(p, &esp_data[7], (u16)(len - 7U));
    IP4_ADDR(ip_2_ip4(&a), esp_data[1], esp_data[2], esp_data[3], esp_data[4]);
    udp_sendto(c->upcb, p, &a, port);
    pbuf_free(p);
    esp_send(11, UE_OK, 0, 0);
}

static void udp_rcv_cmd(u32 len)
{
    static u8 out[6 + 2048];
    u8 num = esp_data[0], i;
    esp_conn_t *c;
    u32 want = (u32)(esp_data[1] | (esp_data[2] << 8)), n;
    if (len != 3U) { esp_send(12, UE_INV_PARAM, 0, 0); return; }
    if (num == 0U || num > ESP_NCONN || esp_conn[num - 1U].type != CONN_UDP) { esp_send(12, UE_NO_CONN, 0, 0); return; }
    c = &esp_conn[num - 1U];
    if (c->n_dgram == 0U) { esp_send(12, UE_NO_DATA, 0, 0); return; }
    if (want > 2048U) want = 2048U;
    n = c->dq[0].p->tot_len < want ? c->dq[0].p->tot_len : want;
    out[0] = c->dq[0].ip[0]; out[1] = c->dq[0].ip[1]; out[2] = c->dq[0].ip[2]; out[3] = c->dq[0].ip[3];
    out[4] = (u8)c->dq[0].port; out[5] = (u8)(c->dq[0].port >> 8);
    pbuf_copy_partial(c->dq[0].p, &out[6], (u16)n, 0);
    pbuf_free(c->dq[0].p);
    for (i = 1; i < c->n_dgram; i++) c->dq[i - 1U] = c->dq[i];
    c->n_dgram--;
    esp_send(12, UE_OK, out, 6U + n);
}

/* ---- despacho ---------------------------------------------------------------------------------------- */
void esp_tcp_exec(u8 cmd, u32 len)
{
    switch (cmd) {
        case 6:
            if (len < 1U) esp_send(6, UE_INV_PARAM, 0, 0); else dns_query(6, (const char *)esp_data, 0);
            break;
        case 206:
            if (len < 2U || (esp_data[0] & 0xF8U)) esp_send(206, UE_INV_PARAM, 0, 0);
            else dns_query(206, (const char *)&esp_data[1], esp_data[0]);
            break;
        case 8:  udp_open(len); break;
        case 9:  udp_close_cmd(len); break;
        case 10: udp_state_cmd(len); break;
        case 11: udp_send_cmd(len); break;
        case 12: udp_rcv_cmd(len); break;
        case 13: tcp_open(len); break;
        case 14: case 15: tcp_close_cmd(cmd, len); break;
        case 16: tcp_state_cmd(len); break;
        case 17: tcp_send_cmd(len); break;
        case 18: tcp_rcv_cmd(len); break;
        default: esp_send(cmd, UE_NOT_IMP, 0, 0); break;
    }
}
