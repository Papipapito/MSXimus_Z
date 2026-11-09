/* xlwipconfig.h — a mano (sin SDK): configuracion del puerto Xilinx de lwIP para el GEM0 de la
 * ZYNQ MINI (P0 de la Ethernet, 25/09/2026). Solo el GEM; sin AXI Ethernet ni EmacLite. */
#ifndef __XLWIPCONFIG_H_
#define __XLWIPCONFIG_H_

#define XLWIP_CONFIG_INCLUDE_GEM        1
#define XLWIP_CONFIG_EMAC_NUMBER        0
#define XLWIP_CONFIG_N_TX_DESC          64
#define XLWIP_CONFIG_N_RX_DESC          64
#define XLWIP_CONFIG_INCLUDE_DHCP       1

#endif
