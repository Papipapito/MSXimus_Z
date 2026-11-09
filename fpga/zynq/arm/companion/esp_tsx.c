/* esp_tsx.c — el host virtual "tsx.msximus" del companion (26/09/2026): el catalogo de cintas TSX de
 * tsx.eslamejor.com servido al menu con el formato del File-Hunter, calcado de TsxWeb.ino (el ESP32; repo Papipapito/ESP32-for-FPGA, rama c6).
 *
 * El menu resuelve "tsx.msximus" (esp_tcp.c contesta 127.0.0.1) y abre un TCP a esa IP: en vez de un socket es una
 * CONEXION VIRTUAL de estas: lo que el MSX escribe (TCP_SEND) es la peticion GET y lo que lee (TCP_RCV) la respuesta;
 * "conectada" hasta que se ha leido todo. Sin esto el DNS falla y el menu entra en su despertador (~36 s por busqueda).
 *   GET /MSXnano.php?base=1BA0&type=tsx&msx=&char=<busqueda>            -> 200 + registros de 7 B + nombres
 *   GET ...&download=N -> 200 + "size:..,load:X,crc:..,name:..tsx\n" + el fichero, que ESTE fichero va bajando por
 *      HTTPS de tsx.eslamejor.com/tsx-files/<nombre>.tsx (esp_tls.c, P2) a un anillo del que lee el menu: sin
 *      bloquear nada (DNS -> TCP -> TLS -> GET -> cabecera -> cuerpo, en tsx_poll), CRC32 al vuelo contra el catalogo,
 *      una descarga a la vez; si falla, la conexion virtual se da por cerrada y el menu lo dice.
 * El catalogo es el MISMO fichero que compila el ESP (tsxcat.h, copia del que compila el ESP; 2565 cintas, ~240 KB en .rodata). */
#include "xil_types.h"
#include "lwip/sys.h"
#include "lwip/tcp.h"
#include "lwip/dns.h"
#include "log.h"
#include "esp.h"

typedef struct TsxCatEntry TsxCatEntry;         /* tsxcat.h esta escrito en C++: usa el nombre sin "struct" */
#include "tsxcat.h"                              /* copia de tsxcat.h del repo del ESP (a la vez, en esta carpeta) */

#define TSX_MAXLIST     115U                    /* FH_MAXENT del menu */
#define TSX_NAMEMAX     73U                     /* como los nombres del API de File-Hunter */
#define TSX_FHBASE      0x1BA0U
#define TSX_REQMAX      700U
#define TSX_RSPMAX      (200U + TSX_MAXLIST * (7U + TSX_NAMEMAX + 1U) + 4U)
#define TSX_HOST        "tsx.eslamejor.com"
#define TSX_UA          "MSXimus/1.2 (cinta web)"
#define DL_RING         32768U                  /* fichero descifrado a la espera de que el menu lo lea */
#define DL_CONNECT_MS   15000U
#define DL_IDLE_MS      30000U

typedef struct {
    u8  open, answered, dl;
    u32 reqlen, rsplen, rsppos, fin_ms;
    char req[TSX_REQMAX + 1];
} tsx_vc_t;

enum { DL_IDLE = 0, DL_DNS, DL_CONNECT, DL_HANDSHAKE, DL_REQUEST, DL_HEADER, DL_BODY, DL_DONE, DL_FAIL };

typedef struct {
    u8  state, slot, remote_closed, chunked, stall_logged;
    u32 chunk_left, cl_len;                      /* Transfer-Encoding: chunked (por si acaso; Cloudflare manda Content-Length) */
    char cl[24];
    u16 idx;
    u32 size, crc, got, delivered, crc_run, t_last, t0;
    struct tcp_pcb *pcb;
    struct pbuf *rxq;
    u32 rx_total;
    esp_tls_t *tls;
    u32 hlen;
    char hdr[2048];                              /* Cloudflare y compania pasan de 512 B de cabeceras */
    u32 rd, wr, n;                               /* anillo dl_ring */
    ip_addr_t ip;
} tsx_dl_t;

static tsx_vc_t vc[ESP_NCONN];
static u8 rsp[ESP_NCONN][TSX_RSPMAX];
static u16 hits[TSX_MAXLIST];
static tsx_dl_t dl;
static u8 dl_ring[DL_RING];

int tsx_is_magic(const char *name)
{
    const char *m = "tsx.msximus";
    while (*m && *name == *m) { m++; name++; }
    return *m == 0 && *name == 0;
}

/* ---- texto: UTF-8 -> ASCII de la pantalla del MSX, minusculas, decodificacion del GET (como TsxWeb) ---- */
static char fold_char(u32 cp)
{
    static const char tbl[] = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTsaaaaaaaceeeeiiiidnooooo/ouuuuyty";
    if (cp < 0x80U) return (char)cp;
    if (cp >= 0xC0U && cp <= 0xFFU) return tbl[cp - 0xC0U];
    return '?';
}

static void fold(const char *in, char *out, u32 cap)
{
    u32 o = 0;
    const u8 *p = (const u8 *)in;
    while (*p && o < cap - 1U) {
        u32 cp, n, i;
        if (*p < 0x80U) { cp = *p; n = 1; }
        else if ((*p & 0xE0U) == 0xC0U) { cp = *p & 0x1FU; n = 2; }
        else if ((*p & 0xF0U) == 0xE0U) { cp = *p & 0x0FU; n = 3; }
        else { cp = *p & 0x07U; n = 4; }
        for (i = 1; i < n; i++) { if ((p[i] & 0xC0U) != 0x80U) { n = i; break; } cp = (cp << 6) | (p[i] & 0x3FU); }
        out[o++] = fold_char(cp);
        p += n;
    }
    out[o] = 0;
}

static void lower(char *s) { for (; *s; s++) if (*s >= 'A' && *s <= 'Z') *s += 32; }
static u32 slen(const char *s) { u32 n = 0; while (s[n]) n++; return n; }
static int hexv(char c) { return (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : -1; }

static void query_decode(const char *p, char *out, u32 cap)      /* '+' = espacio, %XX */
{
    u32 o = 0;
    while (*p && *p != '&' && *p != ' ' && *p != '\r' && *p != '\n' && o < cap - 1U) {
        char c = *p++;
        if (c == '+') c = ' ';
        else if (c == '%' && hexv(p[0]) >= 0 && hexv(p[1]) >= 0) { c = (char)(hexv(p[0]) * 16 + hexv(p[1])); p += 2; }
        out[o++] = c;
    }
    out[o] = 0;
}

static const char *find(const char *hay, const char *needle)
{
    u32 n = slen(needle);
    if (!n) return hay;
    for (; *hay; hay++) { u32 i; for (i = 0; i < n && hay[i] == needle[i]; i++) { } if (i == n) return hay; }
    return 0;
}

static char load_char(u8 k) { return k == 0 ? 'R' : k == 1 ? 'B' : k == 2 ? 'C' : '?'; }

static u32 search(const char *q, u16 *idx, u32 cap)              /* subcadena sin mayusculas ni acentos */
{
    char ql[64], nm[200];
    u32 i, n = 0;
    fold(q, ql, sizeof ql); lower(ql);
    if (!ql[0]) return 0;
    for (i = 0; i < TSXCAT_N && n < cap; i++) {
        fold(tsxcat_names + tsxcat[i].nameOff, nm, sizeof nm); lower(nm);
        if (find(nm, ql)) idx[n++] = (u16)i;
    }
    return n;
}

/* ---- respuesta ---------------------------------------------------------------------------------------- */
static u32 put_str(u8 *d, const char *s) { u32 n = 0; while (*s) d[n++] = (u8)*s++; return n; }
static u32 put_dec(u8 *d, u32 v) { char t[12]; u32 n = 0, i; do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v); for (i = 0; i < n; i++) d[i] = (u8)t[n - 1U - i]; return n; }
static u32 put_hex8(u8 *d, u32 v) { u32 i; for (i = 0; i < 8U; i++) { u32 k = (v >> (28U - 4U * i)) & 15U; d[i] = (u8)(k < 10U ? '0' + k : 'a' + k - 10U); } return 8; }

static u32 head(u8 *d, u32 code, u32 len)                         /* el menu solo mira "2xx" y CRLFCRLF */
{
    u32 n = 0;
    n += put_str(d + n, "HTTP/1.1 "); n += put_dec(d + n, code); n += put_str(d + n, code == 200U ? " OK" : " Error");
    n += put_str(d + n, "\r\nContent-Type: application/octet-stream\r\nContent-Length: "); n += put_dec(d + n, len);
    n += put_str(d + n, "\r\nConnection: close\r\n\r\n");
    return n;
}

/* ---- la descarga HTTPS de una cinta (una a la vez) --------------------------------------------------------- */
static u32 crc32_step(u32 crc, const u8 *p, u32 n)
{
    while (n--) { u32 k; crc ^= *p++; for (k = 0; k < 8U; k++) crc = (crc >> 1) ^ (0xEDB88320U & (0U - (crc & 1U))); }
    return crc;
}

static void dl_release_net(void)
{
    if (dl.tls) { tls_free(dl.tls); dl.tls = NULL; }
    if (dl.pcb) { tcp_arg(dl.pcb, NULL); tcp_recv(dl.pcb, NULL); tcp_err(dl.pcb, NULL); if (tcp_close(dl.pcb) != ERR_OK) tcp_abort(dl.pcb); dl.pcb = NULL; }
    if (dl.rxq) { pbuf_free(dl.rxq); dl.rxq = NULL; }
    dl.rx_total = 0;
}

static void dl_fail(const char *why)
{
    log_str("esp: tsx descarga fallida ("); log_str(why); log_str(") con "); log_dec(dl.got); log_str("/"); log_dec(dl.size); log_str(" B\n");
    dl_release_net();
    dl.state = DL_FAIL;
}

static err_t dl_recv_cb(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err)
{
    (void)arg; (void)pcb; (void)err;
    if (p == NULL) { dl.remote_closed = 1; if (dl.tls) tls_remote_closed(dl.tls); return ERR_OK; }
    if (dl.rxq) pbuf_cat(dl.rxq, p); else dl.rxq = p;
    dl.rx_total += p->tot_len;
    return ERR_OK;
}

static void dl_err_cb(void *arg, err_t err)      /* lwIP ya libero el pcb */
{
    (void)arg; (void)err;
    dl.pcb = NULL; dl.remote_closed = 1;
    if (dl.tls) { tls_detach(dl.tls); tls_remote_closed(dl.tls); }
    if (dl.state < DL_BODY) dl_fail("conexion rechazada o perdida");
}

static err_t dl_connected_cb(void *arg, struct tcp_pcb *pcb, err_t err)
{
    (void)arg; (void)err;
    dl.tls = tls_new(pcb, &dl.rxq, &dl.rx_total, TSX_HOST);
    if (dl.tls == NULL) { tcp_arg(pcb, NULL); tcp_recv(pcb, NULL); tcp_err(pcb, NULL); tcp_abort(pcb); dl.pcb = NULL; dl_fail("sin memoria TLS"); return ERR_ABRT; }
    dl.state = DL_HANDSHAKE; dl.t_last = sys_now();
    return ERR_OK;
}

static void dl_connect(void)
{
    dl.pcb = tcp_new();
    if (dl.pcb == NULL) { dl_fail("sin pcb"); return; }
    tcp_arg(dl.pcb, &dl); tcp_recv(dl.pcb, dl_recv_cb); tcp_err(dl.pcb, dl_err_cb);
    tcp_nagle_disable(dl.pcb);                     /* el handshake manda CCS+Finished sin esperar al ACK (50 ms menos) */
    dl.state = DL_CONNECT; dl.t_last = sys_now();
    if (tcp_connect(dl.pcb, &dl.ip, 443, dl_connected_cb) != ERR_OK) { tcp_abort(dl.pcb); dl.pcb = NULL; dl_fail("tcp_connect"); }
}

static void dl_dns_cb(const char *name, const ip_addr_t *ipaddr, void *arg)
{
    (void)name; (void)arg;
    if (dl.state != DL_DNS) return;
    if (ipaddr == NULL || ip_addr_isany(ipaddr)) { dl_fail("DNS"); return; }
    dl.ip = *ipaddr;
    dl_connect();
}

static int dl_start(u16 idx, u8 slot)
{
    err_t e;
    if (dl.state != DL_IDLE && dl.state != DL_DONE && dl.state != DL_FAIL) return 0;   /* hay una en marcha */
    dl_release_net();
    dl.state = DL_DNS; dl.slot = slot; dl.idx = idx; dl.remote_closed = 0;
    dl.size = tsxcat[idx].size; dl.crc = tsxcat[idx].crc; dl.got = 0; dl.delivered = 0; dl.crc_run = 0xFFFFFFFFU;
    dl.hlen = 0; dl.rd = dl.wr = dl.n = 0; dl.t0 = dl.t_last = sys_now();
    dl.chunked = 0; dl.chunk_left = 0; dl.cl_len = 0; dl.stall_logged = 0;
    e = dns_gethostbyname(TSX_HOST, &dl.ip, dl_dns_cb, NULL);
    if (e == ERR_OK) dl_connect();
    else if (e != ERR_INPROGRESS) { dl_fail("DNS"); return 0; }
    return 1;
}

static void dl_send_request(void)
{
    static u8 req[1024];
    static const char hexd[] = "0123456789ABCDEF";
    const u8 *name = (const u8 *)(tsxcat_names + tsxcat[dl.idx].nameOff);
    u32 n = 0;
    int r;
    n += put_str(req + n, "GET /tsx-files/");
    for (; *name && n < 800U; name++) {                              /* URL: letras, cifras, -_.~ tal cual; el resto %XX */
        u8 c = *name;
        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.' || c == '~') req[n++] = c;
        else { req[n++] = '%'; req[n++] = (u8)hexd[c >> 4]; req[n++] = (u8)hexd[c & 15U]; }
    }
    /* HTTP/1.1 como el HTTPClient del ESP: Cloudflare contesta 403 a una peticion HTTP/1.0 (probado con curl, 26/09) */
    n += put_str(req + n, ".tsx HTTP/1.1\r\nHost: " TSX_HOST "\r\nUser-Agent: " TSX_UA "\r\nReferer: https://" TSX_HOST "/\r\nAccept: */*\r\nConnection: close\r\n\r\n");
    r = tls_write(dl.tls, req, n);
    if (r > 0) { dl.state = DL_HEADER; dl.t_last = sys_now(); }
    else if (r < 0) dl_fail("GET");
}

static const char *hdr_field(const char *key)      /* valor de una cabecera (sin mayusculas) o 0 */
{
    const char *p = dl.hdr;
    u32 kl = slen(key);
    while ((p = find(p, "\n")) != 0) {
        u32 i;
        p++;
        for (i = 0; i < kl; i++) { char c = p[i]; if (c >= 'A' && c <= 'Z') c += 32; if (c != key[i]) break; }
        if (i == kl) { p += kl; while (*p == ' ') p++; return p; }
    }
    return 0;
}

static int body_done(void)                         /* fin del cuerpo: CRC contra el catalogo */
{
    u32 crc = ~dl.crc_run;
    if (dl.got != dl.size) { dl_fail("tamano distinto"); return 0; }
    if (crc != dl.crc) { log_str("esp: tsx crc "); log_hex(crc); log_str(" != "); log_hex(dl.crc); log_str("\n"); dl_fail("CRC"); return 0; }
    log_str("esp: tsx bajada: "); log_dec(dl.size); log_str(" B en "); log_dec(sys_now() - dl.t0); log_str(" ms, crc bien\n");
    dl_release_net();
    dl.state = DL_DONE;
    return 1;
}

static void dl_pull(void)                          /* texto en claro del TLS -> cabecera HTTP y luego el anillo */
{
    u8 b;
    while (dl.state == DL_HEADER && tls_avail(dl.tls)) {
        tls_read(dl.tls, &b, 1);
        if (dl.hlen < sizeof dl.hdr - 1U) dl.hdr[dl.hlen++] = (char)b;
        else { dl_fail("cabecera HTTP larga"); return; }
        if (dl.hlen >= 4U && dl.hdr[dl.hlen - 4U] == '\r' && dl.hdr[dl.hlen - 3U] == '\n' && dl.hdr[dl.hlen - 2U] == '\r' && dl.hdr[dl.hlen - 1U] == '\n') {
            u32 code = 0, i;
            dl.hdr[dl.hlen] = 0;
            for (i = 0; dl.hdr[i] && dl.hdr[i] != ' '; i++) { }
            for (i++; dl.hdr[i] >= '0' && dl.hdr[i] <= '9'; i++) code = code * 10U + (u32)(dl.hdr[i] - '0');
            if (code != 200U) { log_str("esp: tsx "); log_dec(code); log_str(" de "); log_str(TSX_HOST); log_str("\n"); dl_fail("HTTP"); return; }
            {
                const char *te = hdr_field("transfer-encoding:"), *clen = hdr_field("content-length:");
                if (te && find(te, "chunked") && find(te, "chunked") < find(te, "\n")) dl.chunked = 1;
                else if (clen) {
                    u32 v = 0;
                    for (; *clen >= '0' && *clen <= '9'; clen++) v = v * 10U + (u32)(*clen - '0');
                    if (v != dl.size) { log_str("esp: tsx Content-Length "); log_dec(v); log_str(" != catalogo "); log_dec(dl.size); log_str("\n"); dl_fail("tamano distinto"); return; }
                }
            }
            dl.state = DL_BODY; dl.t_last = sys_now();
        }
    }
    while (dl.state == DL_BODY) {
        u32 k = DL_RING - dl.n, a = tls_avail(dl.tls), left = dl.size - dl.got;
        if (dl.chunked && dl.chunk_left == 0U) {          /* linea "<hex>\r\n" (la vacia es el CRLF del trozo anterior) */
            u32 v = 0, i;
            int hex = 0;
            b = 0;
            while (a-- && dl.cl_len < sizeof dl.cl - 1U) { tls_read(dl.tls, &b, 1); if (b == '\n') break; dl.cl[dl.cl_len++] = (char)b; }
            if (b != '\n') { if (dl.cl_len >= sizeof dl.cl - 1U) dl_fail("chunked"); break; }
            for (i = 0; i < dl.cl_len && hexv(dl.cl[i]) >= 0; i++) { v = (v << 4) | (u32)hexv(dl.cl[i]); hex = 1; }
            dl.cl_len = 0;
            if (!hex) continue;
            if (v == 0U) { (void)body_done(); return; }
            dl.chunk_left = v;
            continue;
        }
        if (k > DL_RING - dl.wr) k = DL_RING - dl.wr;
        if (k > a) k = a;
        if (k > left) k = left;
        if (dl.chunked && k > dl.chunk_left) k = dl.chunk_left;
        if (k == 0U) {
            if (left == 0U && !dl.chunked) { (void)body_done(); return; }
            if (left == 0U && dl.chunked && dl.chunk_left) { dl_fail("tamano distinto"); return; }
            break;
        }
        k = tls_read(dl.tls, dl_ring + dl.wr, k);
        dl.crc_run = crc32_step(dl.crc_run, dl_ring + dl.wr, k);
        dl.wr = (dl.wr + k) % DL_RING; dl.n += k; dl.got += k; dl.t_last = sys_now();
        if (dl.chunked) dl.chunk_left -= k;
        else if (dl.got >= dl.size) { (void)body_done(); return; }
    }
}

/* 26/09: los plazos con resta CON SIGNO y 'now' leido despues de dl_pull: dl_pull pone t_last = sys_now() y el
 * descifrado puede cruzar un milisegundo, asi que con el 'now' de antes la resta sin signo daba ~4e9 y la descarga
 * se daba por muerta ("30 s sin datos") a los pocos ms del primer bloque. */
static int dl_elapsed(u32 ms) { return (s32)(sys_now() - dl.t_last) > (s32)ms; }

void tsx_poll(void)
{
    int st;
    switch (dl.state) {
        case DL_DNS: case DL_CONNECT:
            if (dl_elapsed(DL_CONNECT_MS)) dl_fail("sin respuesta del servidor");
            break;
        case DL_HANDSHAKE:
            st = tls_poll(dl.tls);
            if (st < 0) dl_fail("TLS");
            else if (st == 1) { dl.state = DL_REQUEST; dl_send_request(); }
            break;
        case DL_REQUEST:
            dl_send_request();
            break;
        case DL_HEADER: case DL_BODY:
            st = tls_poll(dl.tls);
            dl_pull();
            if (dl.state == DL_BODY && !dl.stall_logged && dl_elapsed(5000U)) {   /* 5 s parada: una foto al log (una vez) */
                log_str("esp: tsx parada con "); log_dec(dl.got); log_str(" B, anillo="); log_dec(dl.n); log_str("\n");
                tls_debug(dl.tls);
                dl.stall_logged = 1;
            }
            if (dl.state != DL_HEADER && dl.state != DL_BODY) break;
            if (tls_avail(dl.tls) == 0U && (st < 0 || tls_closed(dl.tls))) dl_fail("el servidor cerro");
            else if (dl_elapsed(DL_IDLE_MS)) dl_fail("30 s sin datos");
            break;
        default: break;
    }
}

static void answer(u8 slot)
{
    tsx_vc_t *v = &vc[slot];
    u8 *d = rsp[slot];
    char q[64] = {0}, nm[TSX_NAMEMAX + 1];
    const char *pq = find(v->req, "char="), *pd = find(v->req, "download=");
    u32 n, k, body, ptr, hl;
    v->answered = 1; v->rsppos = 0; v->dl = 0;
    if (pq) query_decode(pq + 5, q, sizeof q);
    if (!find(v->req, "type=tsx") || !(v->req[0] == 'G' && v->req[1] == 'E' && v->req[2] == 'T' && v->req[3] == ' ')) { v->rsplen = head(d, 404, 0); return; }
    n = search(q, hits, TSX_MAXLIST);
    if (pd) {                                                      /* descarga: meta + fichero (lo va bajando tsx_poll por HTTPS) */
        char folded[160];
        const TsxCatEntry *e;
        u32 item = 0;
        for (pd += 9; *pd >= '0' && *pd <= '9'; pd++) item = item * 10U + (u32)(*pd - '0');
        if (item >= n) { v->rsplen = head(d, 404, 0); return; }
        e = &tsxcat[hits[item]];
        if (!tls_available() || !esp_net_ok() || !dl_start(hits[item], slot)) {
            v->rsplen = head(d, 503, 0);
            log_str("esp: tsx descarga no posible (sin TLS/red u otra en marcha): 503\n");
            return;
        }
        fold(tsxcat_names + e->nameOff, folded, sizeof folded);
        hl = head(d, 200, 0);                                      /* provisional: la longitud real va abajo */
        k = 0;
        k += put_str(d + hl + k, "size:"); k += put_dec(d + hl + k, e->size);
        k += put_str(d + hl + k, ",load:"); d[hl + k++] = (u8)load_char(e->load);
        k += put_str(d + hl + k, ",crc:"); k += put_hex8(d + hl + k, e->crc);
        k += put_str(d + hl + k, ",name:"); k += put_str(d + hl + k, folded); k += put_str(d + hl + k, ".tsx\n");
        {   /* cabecera definitiva con Content-Length = meta + fichero (misma longitud de texto salvo la cifra) */
            u8 meta[240];
            u32 i;
            for (i = 0; i < k; i++) meta[i] = d[hl + i];
            hl = head(d, 200, k + e->size);
            for (i = 0; i < k; i++) d[hl + i] = meta[i];
        }
        v->rsplen = hl + k; v->dl = 1;
        log_str("esp: tsx descarga "); log_dec(item); log_str(": "); log_str(folded); log_str(" ("); log_dec(e->size); log_str(" B) por https\n");
        return;
    }
    body = n * 7U + 4U;
    for (k = 0; k < n; k++) { fold(tsxcat_names + tsxcat[hits[k]].nameOff, nm, sizeof nm); body += slen(nm) + 1U; }
    hl = head(d, 200, body);
    ptr = TSX_FHBASE;
    for (k = 0; k < n; k++) {                                      /* registros {u32 ptr, u16 KB, u8 carga} */
        const TsxCatEntry *e = &tsxcat[hits[k]];
        u32 kb = (e->size + 1023U) / 1024U;
        u8 *p = d + hl + k * 7U;
        if (kb > 65535U) kb = 65535U;
        p[0] = (u8)ptr; p[1] = (u8)(ptr >> 8); p[2] = (u8)(ptr >> 16); p[3] = (u8)(ptr >> 24);
        p[4] = (u8)kb; p[5] = (u8)(kb >> 8); p[6] = (u8)load_char(e->load);
        fold(tsxcat_names + e->nameOff, nm, sizeof nm); ptr += slen(nm) + 1U;
    }
    hl += n * 7U;
    d[hl] = 0; d[hl + 1U] = 0; d[hl + 2U] = 0; d[hl + 3U] = 0; hl += 4U;
    for (k = 0; k < n; k++) { u32 l; fold(tsxcat_names + tsxcat[hits[k]].nameOff, nm, sizeof nm); l = slen(nm) + 1U; put_str(d + hl, nm); d[hl + l - 1U] = 0; hl += l; }
    v->rsplen = hl;
    log_str("esp: tsx lista \""); log_str(q); log_str("\": "); log_dec(n); log_str(" cintas\n");
}

/* ---- la conexion virtual vista desde esp_tcp.c ------------------------------------------------------------ */
static int owns_dl(u8 slot) { return vc[slot].dl && dl.slot == slot && dl.state != DL_IDLE; }

void tsx_open(u8 slot) { tsx_vc_t *v = &vc[slot]; v->open = 1; v->answered = 0; v->dl = 0; v->reqlen = 0; v->rsplen = 0; v->rsppos = 0; v->fin_ms = 0; v->req[0] = 0; }

void tsx_close(u8 slot)
{
    if (owns_dl(slot)) {
        if (dl.state < DL_DONE) dl_fail("abortada por el menu");
        dl.state = DL_IDLE;
    }
    vc[slot].open = 0; vc[slot].dl = 0;
}

void tsx_write(u8 slot, const u8 *p, u32 n)
{
    tsx_vc_t *v = &vc[slot];
    if (!v->open || v->answered) return;
    while (n-- && v->reqlen < TSX_REQMAX) v->req[v->reqlen++] = (char)*p++;
    v->req[v->reqlen] = 0;
    if (find(v->req, "\r\n\r\n") || find(v->req, "\n\n")) answer(slot);
}

u32 tsx_avail(u8 slot)
{
    tsx_vc_t *v = &vc[slot];
    if (!v->open) return 0;
    return v->rsplen - v->rsppos + (owns_dl(slot) ? dl.n : 0U);
}

u32 tsx_read(u8 slot, u8 *dst, u32 n)
{
    tsx_vc_t *v = &vc[slot];
    u32 k = v->rsplen - v->rsppos, i, got = 0;
    if (!v->open) return 0;
    if (k > n) k = n;
    for (i = 0; i < k; i++) dst[i] = rsp[slot][v->rsppos + i];
    v->rsppos += k; got = k;
    if (owns_dl(slot) && got < n) {
        k = dl.n; if (k > n - got) k = n - got;
        for (i = 0; i < k; i++) { dst[got + i] = dl_ring[dl.rd]; dl.rd = (dl.rd + 1U) % DL_RING; }
        dl.n -= k; dl.delivered += k; got += k;
    }
    if (!v->fin_ms && v->answered && v->rsppos >= v->rsplen && (!v->dl || (owns_dl(slot) && dl.state == DL_DONE && dl.delivered >= dl.size))) v->fin_ms = sys_now() | 1U;
    return got;
}

int tsx_connected(u8 slot)                                         /* 0 = cerrada: todo entregado (o error) */
{
    tsx_vc_t *v = &vc[slot];
    if (!v->open) return 0;
    if (!v->answered) return 1;
    if (v->rsppos < v->rsplen) return 1;
    if (!v->dl) return 0;
    if (!owns_dl(slot) || dl.state == DL_FAIL) { if (!v->fin_ms) v->fin_ms = sys_now() | 1U; return 0; }
    if (dl.state == DL_DONE && dl.delivered >= dl.size) return 0;
    return 1;
}

int tsx_finished(u8 slot)                                          /* entregada hace > 3 s: autocierre (el menu suele abortar antes) */
{
    tsx_vc_t *v = &vc[slot];
    return v->open && v->fin_ms && (s32)(sys_now() - v->fin_ms) > 3000;
}
