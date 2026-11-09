/* tr_bios.h — lo que un .mxp trae ademas del .bin (la BIOS del perfil TR y su Nextor) y su paso a la DDR. Ver tr_bios.c. */
#ifndef TR_BIOS_H
#define TR_BIOS_H
#include "xil_types.h"

enum { TR_BIOS_NO = 0,      /* no es el perfil TR */
       TR_BIOS_PERFIL,      /* vino en el .mxp: MBOX+0x1C bit 6 = 1 */
       TR_BIOS_JTAG,        /* el bit 6 ya venia a 1 (boot.tcl con TR_ROM) */
       TR_BIOS_FALTAN };    /* perfil TR sin BIOS: el PL arranca el MSX2+ normal */

int  tr_ex_prepara(const u8 *datos, u32 total, u32 *bin);  /* comprueba y apunta los bloques; *bin = bytes del .bin. 0 = bien */
void tr_ex_olvida(void);                                   /* suelta lo apuntado, se haya usado o no */
void tr_ex_aplica(void);                                   /* perfil_cargar, con el MSX parado: bloques a la DDR y, antes, deshace el perfil anterior */
int  tr_bios_estado(void);                                 /* TR_BIOS_* */

#endif
