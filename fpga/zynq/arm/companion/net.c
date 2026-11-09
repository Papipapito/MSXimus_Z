/* net.c — P0 Ethernet (25/09/2026): GEM0 del PS (RTL8211E U18 en MIO 16-27, MDIO 52/53) con lwIP 2.1.1
 * en modo SONDEO desde el bucle principal del companion. El companion no usa interrupciones: cada vuelta
 * (~1 ms) se llama a mano a XEmacPs_IntrHandler, que despacha RX/TX/errores a los manejadores del puerto
 * Xilinx igual que haria el GIC, y xemacif_input pasa los paquetes a lwIP. Sin cache que mantener: .bss
 * es strongly-ordered (mmu.c), asi que los descriptores y los pbufs los ve la DMA del GEM tal cual.
 *
 * Que hay: DHCP (nombre "msximus"), DNS, ARP, ICMP y un eco TCP en el puerto 7 para probar desde el PC.
 * La IP sale en el log del ARM (tools/armlog.tcl). Lo que ve el MSX (protocolo del ESP, UNAPI) es P1:
 * Ver docs/tecnica/12-companion.md.
 *
 * Guardia: si el GEM0 no tiene reloj (ps7_init/FSBL anteriores al 25/09, sin ENET0 en el bd) no se
 * toca: un acceso APB a un periferico sin reloj cuelga el bus y la lectura MDIO esperaria para siempre.
 *
 * Enlace: la maquina de estados es propia (link_poll), NO la eth_link_detect del puerto: aquella no mira
 * lo que devuelve phy_setup_emacps (asume que bloquea hasta tener velocidad) y con la version sin esperas
 * de net_phy.c pasaba XST_FAILURE a XEmacPs_SetOperatingSpeed -> Xil_Assert -> companion colgado (visto
 * el 25/09 al reiniciar con el cable puesto: el PHY tarda unos segundos en volver a negociar). */
#include "xparameters.h"
#include "xil_io.h"
#include "sleep.h"
#include "xemacps.h"
#include "lwip/init.h"
#include "lwip/netif.h"
#include "lwip/dhcp.h"
#include "lwip/dns.h"
#include "lwip/tcp.h"
#include "lwip/timeouts.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "netif/ethernet.h"
#include "xemac_ieee_reg.h"
#include "log.h"
#include "net.h"

extern u64 gt_now(void);                                       /* support.c: timer global (CPU/2) */
extern char __net_start[], __net_end[];                        /* lscript.ld: seccion .netbss (region net, 0x00600000) */

#define SLCR_UNLOCK          0xF8000008U
#define SLCR_LOCK            0xF8000004U
#define SLCR_APER_CLK_CTRL   0xF800012CU
#define SLCR_GEM_RST_CTRL    0xF8000214U
#define GEM0_RST_MASK        0x51U                             /* GEM0: RX (bit 0), REF (bit 4), CPU1X (bit 6) */
#define SLCR_GEM0_CLK_CTRL   0xF8000140U
#define APER_GEM0_CLKACT     (1U << 6)
#define POLL_MAX_FRAMES      32U                               /* paquetes por vuelta como mucho: el bucle sigue vivo */

extern u32_t phyaddrforemac;                                   /* xadapter.c: la pone init_emacps (detect_phy) */
extern enum ethernet_link_status eth_link_status;              /* xadapter.c: UP/DOWN tras init_emacps */
extern u32_t phymapemac0[32];                                  /* net_phy.c: direcciones donde detect_phy vio un PHY */
static struct netif nif;

/* ---- traza de segmentos TCP de un puerto (26/09, caza del TLS): texto en la DDR 0x00E00000 (64 KB, fuera de todas
 * las regiones del companion), lo lee tools/pkttrace.tcl. Cada linea: R/T ms flags seq ack len ventana. Apagada
 * (NET_PKT_PORT 0); con p. ej. 443 engancha netif->input y netif->linkoutput y apunta ese puerto. ---- */
#define NET_PKT_PORT   0U
#define PKT_BASE       0x00E00000U
#define PKT_SIZE       0x10000U
#if NET_PKT_PORT
static netif_input_fn      real_input;
static netif_linkoutput_fn real_linkoutput;
static void pkt_putc(char c) { u32 *wr = (u32 *)(PKT_BASE + 4U); ((volatile u8 *)PKT_BASE)[8U + (*wr % (PKT_SIZE - 8U))] = (u8)c; (*wr)++; }
static void pkt_puts(const char *t) { while (*t) pkt_putc(*t++); }
static void pkt_hex(u32 v, int n) { while (n--) pkt_putc("0123456789abcdef"[(v >> (4 * n)) & 15U]); }
static void pkt_dec(u32 v) { char t[11]; int n = 0; do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v); while (n) pkt_putc(t[--n]); }
static void pkt_trace(char dir, struct pbuf *p)
{
    u8 h[54];
    u32 ihl, sport, dport, flags;
    if (p->tot_len < 54U) return;
    pbuf_copy_partial(p, h, 54, 0);
    if (h[12] != 0x08U || h[13] != 0x00U || h[23] != 6U) return;           /* IPv4 + TCP */
    ihl = (u32)(h[14] & 15U) * 4U;
    if (ihl != 20U) return;
    sport = ((u32)h[34] << 8) | h[35]; dport = ((u32)h[36] << 8) | h[37];
    if (sport != NET_PKT_PORT && dport != NET_PKT_PORT) return;
    flags = h[47];
    if (*(u32 *)PKT_BASE != 0x544B5041U) { *(u32 *)PKT_BASE = 0x544B5041U; *(u32 *)(PKT_BASE + 4U) = 0; }
    pkt_putc(dir); pkt_putc(' ');
    pkt_dec(sys_now()); pkt_putc(' ');
    pkt_putc((flags & 2U) ? 'S' : '.'); pkt_putc((flags & 16U) ? 'A' : '.'); pkt_putc((flags & 8U) ? 'P' : '.'); pkt_putc((flags & 1U) ? 'F' : '.'); pkt_putc((flags & 4U) ? 'R' : '.');
    pkt_puts(" s="); pkt_hex(((u32)h[38] << 24) | ((u32)h[39] << 16) | ((u32)h[40] << 8) | h[41], 8);
    pkt_puts(" a="); pkt_hex(((u32)h[42] << 24) | ((u32)h[43] << 16) | ((u32)h[44] << 8) | h[45], 8);
    pkt_puts(" l="); pkt_dec((((u32)h[16] << 8) | h[17]) - ihl - (u32)((h[46] >> 4) * 4U));
    pkt_puts(" w="); pkt_dec(((u32)h[48] << 8) | h[49]);
    pkt_putc('\n');
}
static err_t trace_input(struct pbuf *p, struct netif *n) { pkt_trace('R', p); return real_input(p, n); }
static err_t trace_linkoutput(struct netif *n, struct pbuf *p) { pkt_trace('T', p); return real_linkoutput(n, p); }
#endif
static int started;
static int link_up;                                            /* lo que hemos dicho a lwIP */
static u32 t_link, t_rxrst;
static const u8 mac[6] = { 0x02, 0x4D, 0x53, 0x58, 0x5A, 0x01 };   /* local (bit 1): 'M','S','X','Z' + 01 */

/* ---- traza de tramas (NET_TRACE): las primeras 48 tramas que entran/salen, al log ------------------- */
#define NET_TRACE 0                                            /* 1 = las primeras 48 tramas al log (lo inunda: anillo de 1,8 KB) */
#if NET_TRACE
static u32 trace_n;
static netif_linkoutput_fn real_linkoutput;
static void trace_frame(const char *dir, struct pbuf *p)
{
    const u8 *b = (const u8 *)p->payload;
    u32 type;
    if (trace_n >= 48U || p->len < 14U) return;
    trace_n++;
    type = ((u32)b[12] << 8) | b[13];
    log_str(dir); log_str(" tipo "); log_hex(type);
    log_str(" dst "); log_hex(((u32)b[0] << 24) | ((u32)b[1] << 16) | ((u32)b[2] << 8) | b[3]); log_hex(((u32)b[4] << 8) | b[5]);
    log_str(" src "); log_hex(((u32)b[6] << 24) | ((u32)b[7] << 16) | ((u32)b[8] << 8) | b[9]); log_hex(((u32)b[10] << 8) | b[11]);
    log_str(" len "); log_dec(p->tot_len);
    if (type == 0x0806U && p->len >= 42U) {
        log_str(" ARP op "); log_dec(b[21]);
        log_str(" de "); log_dec(b[28]); log_str("."); log_dec(b[29]); log_str("."); log_dec(b[30]); log_str("."); log_dec(b[31]);
        log_str(" a "); log_dec(b[38]); log_str("."); log_dec(b[39]); log_str("."); log_dec(b[40]); log_str("."); log_dec(b[41]);
    } else if (type == 0x0800U && p->len >= 34U) {
        log_str(" IP proto "); log_dec(b[23]);
        log_str(" de "); log_dec(b[26]); log_str("."); log_dec(b[27]); log_str("."); log_dec(b[28]); log_str("."); log_dec(b[29]);
        log_str(" a "); log_dec(b[30]); log_str("."); log_dec(b[31]); log_str("."); log_dec(b[32]); log_str("."); log_dec(b[33]);
    }
    log_str("\n");
}
static err_t trace_input(struct pbuf *p, struct netif *n) { trace_frame("rx", p); return ethernet_input(p, n); }
static err_t trace_output(struct netif *n, struct pbuf *p) { trace_frame("tx", p); return real_linkoutput(n, p); }
#endif

u32_t sys_now(void)                                            /* lo pide lwIP (timeouts): milisegundos */
{
    return (u32_t)(gt_now() / (COUNTS_PER_SECOND / 1000U));
}

static void log_ip(const char *pre, const ip4_addr_t *a)
{
    log_str(pre); log_dec(ip4_addr1(a)); log_str("."); log_dec(ip4_addr2(a)); log_str(".");
    log_dec(ip4_addr3(a)); log_str("."); log_dec(ip4_addr4(a));
}

static void status_cb(struct netif *n)                         /* interfaz arriba/abajo o cambio de direccion (DHCP) */
{
    if (netif_is_up(n) && !ip4_addr_isany_val(*netif_ip4_addr(n))) {
        log_ip("net: IP ", netif_ip4_addr(n)); log_ip(" mascara ", netif_ip4_netmask(n));
        log_ip(" puerta ", netif_ip4_gw(n)); log_ip(" DNS ", ip_2_ip4(dns_getserver(0))); log_str("\n");
    } else {
        log_str("net: sin direccion IP\n");
    }
}

static void link_cb(struct netif *n)
{
    log_str(netif_is_link_up(n) ? "net: enlace ARRIBA\n" : "net: enlace CAIDO\n");
}

/* ---- eco TCP en el puerto 7 (prueba desde el PC: ncat IP 7) ------------------------------------ */
static err_t echo_recv(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err)
{
    (void)arg; (void)err;
    if (p == NULL) { tcp_close(pcb); log_str("net: eco: cierre\n"); return ERR_OK; }
    tcp_recved(pcb, p->tot_len);
    for (struct pbuf *q = p; q != NULL; q = q->next)
        (void)tcp_write(pcb, q->payload, q->len, TCP_WRITE_FLAG_COPY);
    (void)tcp_output(pcb);
    pbuf_free(p);
    return ERR_OK;
}

static err_t echo_accept(void *arg, struct tcp_pcb *pcb, err_t err)
{
    (void)arg; (void)err;
    log_str("net: eco: conexion\n");
    tcp_recv(pcb, echo_recv);
    return ERR_OK;
}

static void echo_init(void)
{
    struct tcp_pcb *pcb = tcp_new();
    if (pcb == NULL || tcp_bind(pcb, IP_ADDR_ANY, 7) != ERR_OK) { log_str("net: eco: sin pcb\n"); return; }
    pcb = tcp_listen(pcb);
    if (pcb != NULL) tcp_accept(pcb, echo_accept);
}

/* ---- arranque -------------------------------------------------------------------------------- */
void net_init(void)
{
    ip4_addr_t ip, mask, gw;
    if ((Xil_In32(SLCR_APER_CLK_CTRL) & APER_GEM0_CLKACT) == 0U || (Xil_In32(SLCR_GEM0_CLK_CTRL) & 1U) == 0U) {
        log_str("net: GEM0 sin reloj (ps7_init sin ENET0): red desactivada\n");
        return;
    }
    /* Reset hardware del GEM0 (SLCR): la DMA puede venir colgada de la sesion anterior. En un arranque por
     * JTAG (y en un reset en caliente) ps7_init reentrena la DDR con el GEM del companion previo aun
     * activo y la transaccion AXI que pilla a medias deja la DMA muerta sin error alguno (25/09: anillo
     * TX con 7 DISCOVER en cola y el puntero sin moverse; el MAC contaba tramas). Igual que el USBCMD.RST
     * del EHCI en boot.tcl, pero desde aqui vale para todos los arranques. */
    Xil_Out32(SLCR_UNLOCK, 0xDF0DU);
    Xil_Out32(SLCR_GEM_RST_CTRL, Xil_In32(SLCR_GEM_RST_CTRL) | GEM0_RST_MASK);
    usleep(10);
    Xil_Out32(SLCR_GEM_RST_CTRL, Xil_In32(SLCR_GEM_RST_CTRL) & ~GEM0_RST_MASK);
    Xil_Out32(SLCR_LOCK, 0x767BU);
    usleep(10);
    ip4_addr_set_zero(&ip); ip4_addr_set_zero(&mask); ip4_addr_set_zero(&gw);
    for (u32 *p = (u32 *)__net_start; p < (u32 *)__net_end; p++) *p = 0U;   /* .netbss: start.S solo limpia .bss */
    lwip_init();
    if (xemac_add(&nif, &ip, &mask, &gw, (unsigned char *)mac, XPAR_XEMACPS_0_BASEADDR) == NULL) {
        log_str("net: xemac_add FALLO\n");
        return;
    }
    nif.hostname = "msximus";
#if NET_TRACE
    nif.input = trace_input;
    real_linkoutput = nif.linkoutput;
    nif.linkoutput = trace_output;
#endif
    netif_set_default(&nif);
    netif_set_status_callback(&nif, status_cb);
    netif_set_link_callback(&nif, link_cb);
    link_up = (eth_link_status == ETH_LINK_UP);                /* init_emacps: UP si el cable ya estaba y hay velocidad */
    if (!link_up) netif_set_link_down(&nif);                   /* low_level_init pone LINK_UP siempre; que lwIP sepa la verdad */
#if NET_PKT_PORT
    real_input = nif.input; nif.input = trace_input;
    real_linkoutput = nif.linkoutput; nif.linkoutput = trace_linkoutput;
#endif
    netif_set_up(&nif);
    (void)dhcp_start(&nif);
    echo_init();
    t_link = t_rxrst = sys_now();
    started = 1;
    log_str("net: GEM0 listo, MAC 02:4D:53:58:5A:01, DHCP en marcha, eco TCP en el puerto 7\n");
}

/* ---- enlace: cada 250 ms, sin esperas; velocidad solo cuando el PHY la tiene resuelta ---------- */
static void link_poll(xemacpsif_s *xif)
{
    XEmacPs *e = &xif->emacps;
    u16 bmsr;
    u32 speed;
    if (phyaddrforemac == 0U) {                                 /* sin PHY al arrancar (en reset, lento): volver a buscarlo */
        u32 a;
        detect_phy(e);
        for (a = 31U; a > 0U; a--) if (phymapemac0[a] != 0U) { phyaddrforemac = a; break; }
        if (phyaddrforemac == 0U) return;
    }
    XEmacPs_PhyRead(e, phyaddrforemac, IEEE_STATUS_REG_OFFSET, &bmsr);
    XEmacPs_PhyRead(e, phyaddrforemac, IEEE_STATUS_REG_OFFSET, &bmsr);     /* el bit de enlace se pega a 0: dos lecturas */
    if (link_up) {
        if ((bmsr & IEEE_STAT_LINK_STATUS) == 0U) { link_up = 0; netif_set_link_down(&nif); }
        return;
    }
    if ((bmsr & IEEE_STAT_LINK_STATUS) == 0U || (bmsr & IEEE_STAT_AUTONEGOTIATE_COMPLETE) == 0U) return;
    speed = phy_setup_emacps(e, phyaddrforemac);                /* net_phy.c: 10/100/1000 o XST_FAILURE (reintento en 250 ms) */
    if (speed != 10U && speed != 100U && speed != 1000U) return;
    XEmacPs_SetOperatingSpeed(e, (u16)speed);
    link_up = 1;
    netif_set_link_up(&nif);                                    /* lwIP reinicia el DHCP */
}

int net_started(void) { return started; }                          /* esp_link.c: solo hay "ESP" si hay GEM */

void net_ip(u8 ip[4])                                              /* osd.c (30/09): la IP, 0.0.0.0 sin enlace o sin DHCP */
{
    const ip4_addr_t *a = netif_ip4_addr(&nif);
    if (!started || !link_up || !netif_is_up(&nif) || ip4_addr_isany_val(*a)) { ip[0] = ip[1] = ip[2] = ip[3] = 0; return; }
    ip[0] = ip4_addr1(a); ip[1] = ip4_addr2(a); ip[2] = ip4_addr3(a); ip[3] = ip4_addr4(a);
}

/* ---- una vuelta del bucle principal ---------------------------------------------------------- */
void net_poll(void)
{
    struct xemac_s *xemac;
    xemacpsif_s *xif;
    u32 now, n;
    if (!started) return;
    xemac = (struct xemac_s *)nif.state;
    xif = (xemacpsif_s *)xemac->state;
    XEmacPs_IntrHandler(&xif->emacps);                         /* "ISR" por sondeo: RX/TX completos y errores */
    for (n = 0; n < POLL_MAX_FRAMES && xemacif_input(&nif) > 0; n++) { }   /* cola RX -> ethernet_input */
    sys_check_timeouts();                                      /* ARP, TCP, DHCP, DNS */
    now = sys_now();
    if (now - t_link >= 250U)  { t_link = now;  link_poll(xif); }                    /* cable puesto/quitado */
    if (now - t_rxrst >= 100U) { t_rxrst = now; xemacpsif_resetrx_on_no_rxdata(&nif); }  /* errata del GEM v2 */
}
