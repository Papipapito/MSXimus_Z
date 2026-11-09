/* esp_cmd.c — comandos del "ESP32" del companion: los propios del firmware de ducasp (reset, consulta, version,
 * "red WiFi", ajustes, hora por SNTP) y los UNAPI que no son de conexion (capacidades, IP, estado de red, config).
 * Los de conexion y DNS estan en esp_tcp.c. 25/09/2026, Ethernet P1.
 *
 * Al MSX se le presenta UNA red, "Ethernet", abierta y siempre conectada mientras haya cable e IP: SCAN la
 * devuelve, CONNECT_AP acepta cualquier nombre, GETAPSTS dice "conectado con IP" (5). Los ajustes (Nagle, tiempo de
 * apagado de la radio, reloj automatico + zona horaria) viven en RAM: TODO guardarlos con el bloque de la QSPI. */
#include "xil_types.h"
#include "lwip/sys.h"
#include "lwip/netif.h"
#include "lwip/dns.h"
#include "lwip/dhcp.h"
#include "lwip/apps/sntp.h"
#include "log.h"
#include "esp.h"

#define FIRMWARETYPE    "MSXIMUS-ZYNQ"
#define AP_NAME         "Ethernet"

u8 esp_nagle;                                   /* 0 = sin Nagle (defecto del firmware) */
static u16 radio_timeout = 120U;
static u8  auto_clock;                          /* 0..3 (lo usa el driver ROM) */
static s8  gmt_hours = 1;                       /* Espana (el ESP trae -3, Brasil); la hora la ajusta el driver con esto */
static u8  ip_auto = 1, dns_auto = 1;
static u32 time_base;                           /* epoch - sys_now()/1000, 0 = sin hora */
static int sntp_on;

/* ---- estado de la red --------------------------------------------------------------------------------- */
int esp_link_up(void) { return netif_default != NULL && netif_is_link_up(netif_default); }
int esp_net_ok(void)
{
    return netif_default != NULL && netif_is_up(netif_default) && netif_is_link_up(netif_default) &&
           !ip4_addr_isany_val(*netif_ip4_addr(netif_default));
}
static u8 conn_status(void) { return esp_net_ok() ? 5U : (esp_link_up() ? 1U : 0U); }   /* 5 conectado con IP, 1 conectando, 0 parado */

static void put_ip(u8 *d, const ip4_addr_t *a)
{
    d[0] = ip4_addr1(a); d[1] = ip4_addr2(a); d[2] = ip4_addr3(a); d[3] = ip4_addr4(a);
}

/* ---- hora (SNTP de lwIP; el driver la pide con 'G' al arrancar si auto_clock lo dice) ---------------- */
void esp_time_set(unsigned long sec) { time_base = (u32)sec - sys_now() / 1000U; }
static u32 time_now(void) { return time_base ? time_base + sys_now() / 1000U : 0U; }

void epoch_to_dt(u32 t, u8 *o)                   /* s, m, h, dia, mes, anno LSB, anno MSB (civil_from_days); v99desk.c tambien */
{
    u32 rem = t % 86400U;
    long z = (long)(t / 86400U) + 719468L, era = (z >= 0 ? z : z - 146096L) / 146097L;
    unsigned doe = (unsigned)(z - era * 146097L), yoe = (doe - doe / 1460U + doe / 36524U - doe / 146096U) / 365U;
    long y = (long)yoe + era * 400L;
    unsigned doy = doe - (365U * yoe + yoe / 4U - yoe / 100U), mp = (5U * doy + 2U) / 153U;
    unsigned d = doy - (153U * mp + 2U) / 5U + 1U, m = mp < 10U ? mp + 3U : mp - 9U;
    if (m <= 2U) y++;
    o[0] = (u8)(rem % 60U); o[1] = (u8)((rem / 60U) % 60U); o[2] = (u8)(rem / 3600U);
    o[3] = (u8)d; o[4] = (u8)m; o[5] = (u8)(y & 0xFF); o[6] = (u8)((y >> 8) & 0xFF);
}

/* la hora local por SNTP (cable), en segundos desde 1970 con la zona del driver; 0 si aun no hay (v99desk.c, rama beta) */
int esp_hora_local(u32 *t) { if (!time_base) return 0; *t = time_now() + (u32)((s32)gmt_hours * 3600); return 1; }
int esp_hora_utc(u32 *t) { if (!time_base) return 0; *t = time_now(); return 1; }   /* SNTP por cable, UTC (v99desk.c) */
int esp_gmt_horas(void) { return gmt_hours; }                                      /* la zona del driver (v99desk.c) */

static void send_time(void)
{
    u8 dt[7];
    epoch_to_dt(time_now() + (u32)((s32)gmt_hours * 3600), dt);
    esp_send('G', UE_OK, dt, 7);
}

void esp_cmd_poll(void)
{
    if (!sntp_on && esp_net_ok()) { sntp_setoperatingmode(SNTP_OPMODE_POLL); sntp_setservername(0, "pool.ntp.org"); sntp_init(); sntp_on = 1; }
    if (esp_pend.kind == PEND_TIME) {
        if (time_base) { send_time(); esp_pend_clear(); }
        else if ((s32)(sys_now() - esp_pend.deadline) >= 0) { esp_send_quick('G', UE_NO_NETWORK); esp_pend_clear(); }
    }
}

/* ---- reset ------------------------------------------------------------------------------------------- */
void esp_warm_reset(void)
{
    esp_tcp_close_all(0);
    esp_pend_clear();
}

/* ---- comandos UNAPI sin conexion -------------------------------------------------------------------- */
static void unapi_capab(u32 len)
{
    u8 r[6];
    if (len != 1U || esp_data[0] == 0U || esp_data[0] > 4U) { esp_send(1, UE_INV_PARAM, 0, 0); return; }
    switch (esp_data[0]) {
        case 1:  /* capacidades: DNS, TCP activo, TCP pasivo sin socket remoto, UDP, IP automatica; enlace 3 = Ethernet */
            r[0] = 0x2C; r[1] = 0x44;
            r[2] = 0x94; r[3] = 0x0C;           /* rasgos: pool compartido, hardware externo, fragmentacion; DNS y TCP_OPEN bloqueantes (sin "inalambrico"; sin bit 12: el certificado NO se verifica) */
            r[4] = 3; esp_send(1, UE_OK, r, 5); break;
        case 2:
            r[0] = 4; r[1] = 4; r[2] = (u8)(4U - esp_tcp_open_count()); r[3] = r[2]; r[4] = 0; r[5] = 0;
            esp_send(1, UE_OK, r, 6); break;
        case 3:
            r[0] = (u8)(1500 & 0xFF); r[1] = 1500 >> 8; r[2] = (u8)(2048 & 0xFF); r[3] = 2048 >> 8;
            esp_send(1, UE_OK, r, 4); break;
        default: /* 4: segundas capacidades: IP y DNS automaticas, IP/mascara/puerta/DNS manuales; bit 8 = TLS en TCP activas (26/09, esp_tls.c) */
            r[0] = 0xF7; r[1] = tls_available() ? 0x01 : 0x00; r[2] = 0; r[3] = 0; r[4] = 0;
            esp_send(1, UE_OK, r, 5); break;
    }
}

static void unapi_ipinfo(u32 len)
{
    u8 r[4] = {0, 0, 0, 0};
    struct netif *n = netif_default;
    if (len != 1U || esp_data[0] == 0U || esp_data[0] > 6U || n == NULL) { esp_send(2, UE_INV_PARAM, 0, 0); return; }
    switch (esp_data[0]) {
        case 1: put_ip(r, netif_ip4_addr(n)); break;
        case 3: put_ip(r, netif_ip4_netmask(n)); break;
        case 4: put_ip(r, netif_ip4_gw(n)); break;
        case 5: put_ip(r, ip_2_ip4(dns_getserver(0))); break;
        case 6: put_ip(r, ip_2_ip4(dns_getserver(1))); break;
        default: break;                          /* 2: IP del par = 0.0.0.0, como el firmware */
    }
    esp_send(2, UE_OK, r, 4);
}

static void unapi_config_autoip(u32 len)
{
    u8 cfg;
    if (len != 2U || esp_data[0] > 1U || esp_data[1] > 3U) { esp_send(25, UE_INV_PARAM, 0, 0); return; }
    if (esp_data[0]) {
        u8 want = (esp_data[1] & 1U) ? 1U : 0U;
        if (want != ip_auto && netif_default) { if (want) dhcp_start(netif_default); else dhcp_stop(netif_default); }
        ip_auto = want; dns_auto = (esp_data[1] & 2U) ? 1U : 0U;
    }
    cfg = (u8)((ip_auto ? 1U : 0U) | (dns_auto ? 2U : 0U));
    esp_send(25, UE_OK, &cfg, 1);
}

static void unapi_config_ip(u32 len)
{
    ip4_addr_t a;
    struct netif *n = netif_default;
    if (len != 5U || esp_data[0] == 0U || esp_data[0] == 2U || esp_data[0] > 6U || n == NULL) { esp_send(26, UE_INV_PARAM, 0, 0); return; }
    IP4_ADDR(&a, esp_data[1], esp_data[2], esp_data[3], esp_data[4]);
    if (!ip_auto && esp_data[0] <= 4U) {
        if (esp_data[0] == 1U) netif_set_ipaddr(n, &a);
        else if (esp_data[0] == 3U) netif_set_netmask(n, &a);
        else netif_set_gw(n, &a);
        esp_send(26, UE_OK, 0, 0);
    } else if (!dns_auto && esp_data[0] >= 5U) {
        ip_addr_t d; ip_addr_copy_from_ip4(d, a);
        dns_setserver((u8)(esp_data[0] - 5U), &d);
        esp_send(26, UE_OK, 0, 0);
    } else esp_send(26, UE_INV_PARAM, 0, 0);
}

/* ---- despacho ---------------------------------------------------------------------------------------- */
void esp_exec(u8 cmd, u32 len)
{
    u8 r[40];
    u32 i;
    switch (cmd) {
        case '?': esp_send_raw((const u8 *)"OK", 2); break;
        case 'R': esp_send_raw((const u8 *)"R0", 2); esp_warm_reset(); break;
        case 'W': esp_warm_reset(); esp_send_raw((const u8 *)"Ready\r\n", 7); break;
        case 'V': r[0] = 'V'; r[1] = ESP_VER_MAJOR; r[2] = ESP_VER_MINOR; esp_send_raw(r, 3); break;
        case 'b': esp_send('b', UE_OK, (const u8 *)FIRMWARETYPE, sizeof(FIRMWARETYPE)); break;
        case 'g':                                                          /* estado + nombre de la "red" */
            r[0] = conn_status();
            for (i = 0; AP_NAME[i]; i++) r[1 + i] = (u8)AP_NAME[i];
            r[1 + i] = 0;
            esp_send('g', UE_OK, r, 2 + i); break;
        case 'S': esp_send_quick('S', UE_OK); break;
        case 's':                                                          /* resultado del "escaneo": una red si hay cable */
            r[0] = 's';
            if (esp_link_up()) {
                r[1] = UE_OK; r[2] = 1;
                for (i = 0; AP_NAME[i]; i++) r[3 + i] = (u8)AP_NAME[i];
                r[3 + i] = 0; r[4 + i] = 'O';
                esp_send_raw(r, 5 + i);
            } else { r[1] = UE_NO_NETWORK; esp_send_raw(r, 2); }
            break;
        case 'A':                                                          /* "conectar": vale cualquier nombre si hay enlace */
            if (len < 3U) esp_send_quick('A', UE_INV_PARAM);
            else esp_send_quick('A', esp_link_up() ? UE_OK : UE_NO_NETWORK);
            break;
        case 'a': case 'H': case 'h': case 'O': case 'o': case 'I': case 'd': case 'B':
            esp_send_quick(cmd, UE_OK); break;
        case 'N': esp_nagle = 0; esp_send_quick(cmd, UE_OK); break;
        case 'D': esp_nagle = 1; esp_send_quick(cmd, UE_OK); break;
        case 'T':
            if (len != 2U) esp_send_quick('T', UE_INV_PARAM);
            else {
                u16 t = (u16)(esp_data[0] | (esp_data[1] << 8));
                radio_timeout = t < 30U ? 30U : (t > 600U ? 600U : t);
                esp_send_quick('T', UE_OK);
            }
            break;
        case 'Q': {                                                        /* "ON:120" / "OFF:120" */
            u32 n = 0, v = radio_timeout, d = 100;
            const char *s = esp_nagle ? "ON:" : "OFF:";
            while (*s) r[n++] = (u8)*s++;
            while (d > 1U && v / d == 0U) d /= 10U;
            while (d) { r[n++] = (u8)('0' + (v / d) % 10U); d /= 10U; }
            esp_send('Q', UE_OK, r, n); break;
        }
        case 'c':
            r[0] = auto_clock; r[1] = gmt_hours >= 0 ? (u8)gmt_hours : (u8)((-gmt_hours) | 0x80);
            esp_send('c', UE_OK, r, 2); break;
        case 'C':
            if (len != 2U || esp_data[0] > 3U || (esp_data[1] & 0x7F) > 12U) esp_send_quick('C', UE_INV_PARAM);
            else { auto_clock = esp_data[0]; gmt_hours = (esp_data[1] & 0x80) ? -(s8)(esp_data[1] & 0x7F) : (s8)esp_data[1]; esp_send_quick('C', UE_OK); }
            break;
        case 'G':
            if (time_base) send_time();
            else if (!esp_net_ok()) esp_send_quick('G', UE_NO_NETWORK);
            else esp_pend_set(PEND_TIME, 'G', 0, 5000U);
            break;
        case 'U': case 'u': case 'Z': case 'Y': case 'z': case 'E':         /* actualizaciones de firmware/certificados: no */
            esp_send_quick(cmd, UE_INV_PARAM); break;
        case 1: unapi_capab(len); break;
        case 2: unapi_ipinfo(len); break;
        case 3:
            if (len != 0U) esp_send(3, UE_INV_PARAM, 0, 0);
            else { r[0] = esp_net_ok() ? 2U : (esp_link_up() ? 1U : 0U); esp_send(3, UE_OK, r, 1); }
            break;
        case 25: unapi_config_autoip(len); break;
        case 26: unapi_config_ip(len); break;
        case 6: case 206: case 8: case 9: case 10: case 11: case 12: case 13: case 14: case 15: case 16: case 17: case 18:
            esp_tcp_exec(cmd, len); break;
        default:                                                           /* HTTP_* (200-202), SSH_* (129+): no implementados */
            esp_send(cmd, UE_NOT_IMP, 0, 0); break;
    }
}
