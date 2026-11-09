/* dual_disco.h — la SD de TF2 compartida entre las dos maquinas del perfil Dual (Z1.3.2b9): MSX-DOS (Nextor 2.1.4) en la maquina B, que ve la MISMA
 * tarjeta que A a traves de un buzon en la DDR, y quien de las dos puede escribir (la DUENA). dual_disco.c; dual.c lo maneja (D sola, Shift+D, panel F12),
 * main.c le pasa las peticiones de A (sd_servir) y le da el tiempo (dual_disco_poll, dual_disco_activo). */
#ifndef DUAL_DISCO_H
#define DUAL_DISCO_H
#include "xil_types.h"

/* ---- Nextor-B: componer el cartucho y atender el buzon -------------------------------------------------------------------------- */
void dual_disco_init(void);                       /* arranque y PL recargado: sin Nextor-B, la duena es A, sin rangos de excepcion */
int  dual_disco_compone(void);                    /* descomprime Nextor-B (nextor_b_rom.h), pone la firma y los registros, la compone en el cartucho de B (parar, escribir, mapper 2, soltar): B arranca MSX-DOS. NO cambia la duena. 1 = bien; 0 = no se pudo descomprimir (B no se toca). Atiende de nuevo a B aunque la tarjeta hubiera cambiado */
void dual_disco_poll(void);                       /* desde el bucle principal (y sd_ceder): atiende UNA orden del buzon de B si hay (lee/escribe un sector de la SD) */
int  dual_disco_activo(void);                     /* 1 = B ha usado el buzon hace menos de ~250 ms: main.c no duerme (wfi) para atender a B sin esperar a los 10 ms del timer */
int  dual_disco_nextor_b(void);                   /* 1 = B tiene Nextor-B (la marca de dual_disco_compone, el cartucho y el mapper de B_CTL y la firma NXTB en la DDR siguen siendo los suyos) */
int  dual_disco_b_corre(void);                    /* 1 = B tiene Nextor-B Y corre (B_CTL[0]) */
void dual_disco_quita_nextor_b(void);             /* B ya no tiene Nextor-B (otro cartucho, o ninguno): se borra la marca y la SD vuelve a ser de A */
void dual_disco_tarjeta_cambio(void);             /* main.c: la tarjeta de TF2 se ha retirado o se ha puesto otra; Nextor-B contesta "sin tarjeta" hasta que se recomponga */
int  dual_disco_tarjeta_nueva(void);              /* 1 = hay Nextor-B y la tarjeta ha cambiado desde que se compuso (el panel dice que se pulse M) */

/* ---- la duena de la SD ---------------------------------------------------------------------------------------------------------- */
int  dual_disco_duena(void);                      /* 0 = A, 1 = B */
void dual_disco_pon_duena(int quien);             /* 0 = A, 1 = B. Solo cambia la duena (y borra los rangos de A si pasa a A); el REINICIO de la que gana es cosa de dual.c */
int  dual_disco_toma_aviso_a(void);               /* 1 (una sola vez) si A ha ganado la SD despues de que B escribiera en ella: su MSX-DOS puede tener datos viejos */

/* ---- lo que sd_servir (main.c) pregunta por A ------------------------------------------------------------------------------------- */
int  dual_disco_a_puede_escribir(u32 sec, u32 cnt);   /* 1 = A puede escribir [sec, sec+cnt) en TF2: es la duena, no hay perfil Dual, o cae entera dentro de uno de sus rangos */
void dual_disco_a_rechazo(u32 sec, u32 cnt);          /* A intento escribir sin poder: se cuenta y se loguea la primera vez (el motivo se lo da el bloque de estado) */
int  dual_disco_a_estado(u32 sec, u8 *bloque);        /* sector magico de A 0x7FFFFFFD = bloque de estado (duena, A solo lee). 1 = era ese y bloque (512 B, alineado a 4) esta relleno; 0 = no, o no hay perfil Dual */
void dual_disco_rangos_a(const u32 *lo, const u32 *n, int k);   /* A conserva la escritura dentro de [lo[i], lo[i]+n[i]) aunque no sea la duena (k = 0: sin rangos; hasta 16) */

#define DD_LBA_ESTADO       0x7FFFFFFDU            /* sector magico de A: estado de la SD compartida */

/* lo que dual_disco.c pide a main.c (la SD de TF2) */
extern int  sd_read(u32 sec, u32 cnt, u8 *buf);          /* 1 = bien */
extern int  sd_write(u32 sec, u32 cnt, const u8 *buf);   /* 1 = bien */
extern u32  sd_sectores(void);                           /* sectores de 512 B de la tarjeta (0 = sin tarjeta) */
extern int  sd_presente(void);                           /* 1 = hay tarjeta en TF2 */
extern u64  gt_now(void);
#endif
