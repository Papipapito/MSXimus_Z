/* perfiles_ext.h — lo que el MENU del MSX pide a los perfiles por el puerto 93h (31/10/2026): instalar un .mxp que esta en la
 * tarjeta de TF2 y cargar el perfil que pide la etiqueta [P:ID] del nombre de una ROM. perfiles_ext.c; wavegame.c recoge los
 * mensajes del Z80 y llama a pext_pide_*; pext_poll() los ejecuta desde el bucle principal. */
#ifndef PERFILES_EXT_H
#define PERFILES_EXT_H
#include "xil_types.h"

void pext_pide_instalar(u32 part, u32 dir, u32 file);    /* 'W','I' + PART_LBA + CUR_CLUS + FILE_CLUS: el fichero .MXP elegido en el navegador */
void pext_pide_etiqueta(u32 part, u32 dir, u32 file);    /* 'W','Q' (RETURN sobre una ROM) y 'W','G' (lanzarla): mira si su nombre pide un perfil */
void pext_poll(void);                                    /* ejecuta lo pedido (un trabajo largo no puede hacerse dentro de wg_poll) */

/* la parte pura (se prueba en el PC): el id de perfil que pide un nombre de fichero, "" si ninguno. id: 9 bytes */
int  pext_etiqueta_de(const char *nombre, char id[9]);

extern int  fat_nombre(u32 part, u32 dir_clus, u32 file, char *out, u32 cap);      /* wavegame.c: nombre largo (o el 8.3) del fichero */
extern int  tape_fat_locate(u32 part, u32 dir_clus, u32 file, u32 *size, char *ext3);
extern int  tape_file_read(u32 first, u32 size, u32 pos, u8 *dst, u32 n);
extern void sd_ceder(void);                             /* main.c: sirve la peticion de SD del MSX que haya pendiente */
extern void wg_pl_parar(void);                           /* wavegame.c: para la musica y el anillo PCM */
extern void wg_pl_rearma(void);                          /* wavegame.c: el anillo Z80 -> ARM del PL nuevo empieza en 0 */
#endif
