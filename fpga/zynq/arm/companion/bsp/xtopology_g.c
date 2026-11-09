/* xtopology_g.c — a mano (sin SDK): un solo EMAC, el GEM0 del PS (0xE000B000). El puerto Xilinx de
 * lwIP busca aqui el tipo de MAC por su direccion base (xadapter.c). Sin interrupciones: el GIC no se
 * usa (ver net.c, modo sondeo), pero la tabla lleva sus campos por forma. */
#include "netif/xtopology.h"
#include "xparameters.h"

struct xtopology_t xtopology[] = {
    { XPAR_XEMACPS_0_BASEADDR, xemac_type_emacps, 0x0, 0x0, XPAR_SCUGIC_0_CPU_BASEADDR, XPAR_XEMACPS_0_INTR },
};
int xtopology_n_emacs = 1;
