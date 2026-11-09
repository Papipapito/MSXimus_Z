/* xemacps_g.c — a mano (sin SDK): tabla de configuracion del driver emacps (GEM0 del PS). */
#include "xemacps.h"
#include "xparameters.h"

XEmacPs_Config XEmacPs_ConfigTable[XPAR_XEMACPS_NUM_INSTANCES] = {
    {
        (u16)XPAR_XEMACPS_0_DEVICE_ID,
        (UINTPTR)XPAR_XEMACPS_0_BASEADDR,
        (u8)XPAR_XEMACPS_0_IS_CACHE_COHERENT,
    },
};
