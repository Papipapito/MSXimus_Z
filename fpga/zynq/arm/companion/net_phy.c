/* net_phy.c — PHY RTL8211E del GEM0 (U18, MDIO en MIO 52/53) SIN ESPERAS. Sustituye al
 * xemacpsif_physpeed.c del puerto Xilinx de lwIP (P0 Ethernet, 25/09/2026).
 *
 * El de Xilinx reinicia el PHY y espera la autonegociacion con sleep(1) hasta 30 s si no hay cable,
 * y el companion no puede pararse (sirve la SD, el USB y la cinta al MSX). Aqui phy_setup_emacps solo
 * LEE el PHY: si hay enlace y la autonegociacion ha terminado devuelve la velocidad (y programa los
 * divisores del GEM0_CLK_CTRL); si no, XST_FAILURE al momento. init_emacps (xemacpsif_hw.c) deja
 * entonces eth_link_status = ETH_LINK_DOWN y eth_link_detect (xadapter.c, cada 250 ms desde
 * net_poll) vuelve a llamar aqui cuando el PHY vea cable. Sin tocar la publicidad de la autoneg:
 * el RTL8211E sale de reset anunciando 10/100/1000 full y negocia solo al enchufar el cable.
 *
 * Simbolos que el puerto espera de este fichero: detect_phy, phy_setup_emacps, phymapemac0/1. */
#include "xparameters.h"
#include "xemacps.h"
#include "xstatus.h"
#include "xil_io.h"
#include "lwipopts.h"
#include "xlwipconfig.h"
#include "netif/xemacpsif.h"
#include "xemac_ieee_reg.h"
#include "log.h"

u32_t phymapemac0[32];
u32_t phymapemac1[32];

#define PHY_DETECT_REG          1               /* BMSR: extended + autoneg capable + 10BASE-T */
#define PHY_DETECT_MASK         0x1808
#define PHY_ID1_REG             2
#define PHY_ID1_REALTEK         0x001C
#define PHYSR_LINK              0x0400          /* RTL8211E reg 17 (PHYSR): enlace en tiempo real */
#define PHYSR_RESOLVED          0x0800          /*   velocidad y duplex resueltos */
#define PHYSR_DUPLEX            0x2000
#define PHYSR_SPEED_MASK        0xC000
#define PHYSR_SPEED_1000        0x8000
#define PHYSR_SPEED_100         0x4000

#define SLCR_LOCK               (XPS_SYS_CTRL_BASEADDR + 0x004U)
#define SLCR_UNLOCK             (XPS_SYS_CTRL_BASEADDR + 0x008U)
#define SLCR_GEM0_CLK_CTRL      (XPS_SYS_CTRL_BASEADDR + 0x140U)
#define SLCR_GEM_SRCSEL_EMIO    0x40U
#define SLCR_GEM_DIV_MASK       0xFC0FC0FFU     /* fuera DIVISOR1 [25:20] y DIVISOR0 [13:8] */

/* Divisores del reloj de transmision RGMII del GEM0 (IO PLL 1000 MHz): 125 / 25 / 2,5 MHz. */
static void slcr_gem0_divisors(u32 speed)
{
    u32 d0 = XPAR_XEMACPS_0_ENET_SLCR_1000MBPS_DIV0, d1 = XPAR_XEMACPS_0_ENET_SLCR_1000MBPS_DIV1, v;
    if (speed == 100U)      { d0 = XPAR_XEMACPS_0_ENET_SLCR_100MBPS_DIV0; d1 = XPAR_XEMACPS_0_ENET_SLCR_100MBPS_DIV1; }
    else if (speed == 10U)  { d0 = XPAR_XEMACPS_0_ENET_SLCR_10MBPS_DIV0;  d1 = XPAR_XEMACPS_0_ENET_SLCR_10MBPS_DIV1; }
    Xil_Out32(SLCR_UNLOCK, 0xDF0DU);
    v = Xil_In32(SLCR_GEM0_CLK_CTRL);
    if ((v & SLCR_GEM_SRCSEL_EMIO) == 0U) {
        v = (v & SLCR_GEM_DIV_MASK) | (d1 << 20) | (d0 << 8);
        Xil_Out32(SLCR_GEM0_CLK_CTRL, v);
    }
    Xil_Out32(SLCR_LOCK, 0x767BU);
}

/* Busca el PHY en el bus MDIO (de 31 a 1, como el puerto) y apunta su direccion en phymapemac0. */
void detect_phy(XEmacPs *xemacpsp)
{
    u16 reg, id1;
    u32 addr, n = 0;
    for (addr = 31U; addr > 0U; addr--) {
        XEmacPs_PhyRead(xemacpsp, addr, PHY_DETECT_REG, &reg);
        if (reg != 0xFFFFU && (reg & PHY_DETECT_MASK) == PHY_DETECT_MASK) {
            XEmacPs_PhyRead(xemacpsp, addr, PHY_ID1_REG, &id1);
            if (xemacpsp->Config.BaseAddress == XPAR_XEMACPS_0_BASEADDR) phymapemac0[addr] = 1U;
            else phymapemac1[addr] = 1U;
            log_str("net: PHY en la direccion "); log_dec(addr); log_str(", id1 "); log_hex(id1);
            log_str(id1 == PHY_ID1_REALTEK ? " (Realtek)\n" : " (no es el RTL8211E esperado)\n");
            n++;
        }
    }
    if (n == 0U) log_str("net: ningun PHY responde en el MDIO (MIO 52/53): revisar ps7_init / cableado\n");
}

/* Sin esperas: velocidad negociada o XST_FAILURE. Llamada por init_emacps y por eth_link_detect. */
u32_t phy_setup_emacps(XEmacPs *xemacpsp, u32_t phy_addr)
{
    u16 bmsr, physr;
    u32 speed;
    XEmacPs_PhyRead(xemacpsp, phy_addr, IEEE_STATUS_REG_OFFSET, &bmsr);
    XEmacPs_PhyRead(xemacpsp, phy_addr, IEEE_STATUS_REG_OFFSET, &bmsr);     /* el bit de enlace se queda a 0 tras una caida: dos lecturas */
    if ((bmsr & IEEE_STAT_LINK_STATUS) == 0U || (bmsr & IEEE_STAT_AUTONEGOTIATE_COMPLETE) == 0U)
        return (u32_t)XST_FAILURE;
    XEmacPs_PhyRead(xemacpsp, phy_addr, IEEE_SPECIFIC_STATUS_REG, &physr);
    if ((physr & PHYSR_LINK) == 0U || (physr & PHYSR_RESOLVED) == 0U)
        return (u32_t)XST_FAILURE;
    switch (physr & PHYSR_SPEED_MASK) {
        case PHYSR_SPEED_1000: speed = 1000U; break;
        case PHYSR_SPEED_100:  speed = 100U;  break;
        case 0U:               speed = 10U;   break;
        default:               return (u32_t)XST_FAILURE;
    }
    slcr_gem0_divisors(speed);
    log_str("net: enlace "); log_dec(speed); log_str((physr & PHYSR_DUPLEX) ? " Mbps full duplex\n" : " Mbps HALF duplex\n");
    return speed;
}
