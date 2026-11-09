/* profile.h — carga de un bitstream del PL por PCAP desde el companion (fase 4 de los perfiles, 30/10/2026). */
#ifndef PROFILE_H
#define PROFILE_H
#include "xil_types.h"

/* Zona de disparo de la prueba (sin TF1 todavia): 4 MB en la DDR que no usa nadie (capitulo 03), strongly-ordered
 * (mmu.c: lo que no se lista alli no tiene cache), asi que lo que deja xsdb por el DAP lo ve la CPU tal cual.
 *   +0x00  magia 'PCAP' (0x50414350)   la escribe xsdb la ULTIMA; el companion la borra al verla
 *   +0x04  tamano del bitstream en bytes (multiplo de 4)
 *   +0x08  comprobacion = magia ^ tamano ^ 0xA5A5A5A5
 *   +0x0C  banderas (PF_FLAG_*)
 *   +0x10  estado (PF_ST_*)    +0x14 etapa alcanzada (PF_ET_*)
 *   +0x18..+0x30  tiempos en us desde que se empieza a cargar: parado, aislado, init del PL, DMA, DONE, PL vivo, MSX suelto
 *   +0x34  INT_STS del devcfg   +0x38 STATUS del devcfg   +0x3C codigo del ultimo error
 *   +0x1000  el bitstream (.bin de bootgen -process_bitstream bin)                                              */
#define PF_ZONA     0x1F400000U
#define PF_TAM      0x00400000U
#define PF_DATOS    (PF_ZONA + 0x1000U)
#define PF_MAX      (PF_TAM - 0x1000U)
#define PF_MAGIA    0x50414350U
#define PF_FLAG_AXI_RST 1U          /* experimental: al aislar, FPGA_RST_CTRL tambien resetea las interfaces AXI (HP, GP, ACP), no solo FCLK_RESET */

enum { PF_ST_NADA = 0, PF_ST_CURSO = 1, PF_ST_OK = 2, PF_ST_ERR = 0x80 };    /* PF_ST_ERR + codigo: error SIN haber tocado el PL */
enum { PF_E_PARAM = 1, PF_E_FORMATO, PF_E_OCUPADO, PF_E_CABECERA };
enum { PF_ET_NINGUNA = 0, PF_ET_PARADO, PF_ET_AISLADO, PF_ET_INIT, PF_ET_DMA, PF_ET_DONE, PF_ET_VIVO, PF_ET_RESEMBRADO, PF_ET_RUN };

/* 0 = cargado y el MSX suelto otra vez; > 0 = error ANTES de tocar nada (PF_E_*). Una vez tocado el PL, si algo falla no
 * vuelve: se anota el informe y se reinicia el PS (vuelve al perfil de la QSPI o de la SD). buf: palabra alineada. */
int  perfil_cargar(const u8 *buf, u32 len);
/* bucle principal: mira la zona; devuelve 1 si ha cargado un perfil (main.c reinicia su estado de peticiones de SD) */
int  perfil_poll(void);
#endif
