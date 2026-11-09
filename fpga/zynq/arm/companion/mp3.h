/* mp3.h — fuente MP3 para la musica del menu: minimp3 detras de la misma interfaz de
 * "siguiente muestra" que usa el WAV en wavegame.c. Se compila con la FPU (softfp + NEON) y sus datos
 * viven aparte; el resto del companion sigue igual. */
#ifndef MP3_H
#define MP3_H
#include "xil_types.h"

typedef u32 (*mp3_read_fn)(void *ctx, u8 *dst, u32 n);   /* bytes leidos (menos que n = fin del fichero) */

int  mp3_open(mp3_read_fn rd, void *ctx, u32 *hz, u32 *ch);  /* 1 = hay audio: hz y canales de la 1a trama */
int  mp3_next(s32 *out);                                   /* siguiente muestra MONO de 16 bits; 0 = fin */
int  mp3_next2(s32 *l, s32 *r);                            /* 23/09: izquierda y derecha (mono: las dos iguales) */
void mp3_stats(u32 *frames, u32 *t_max, u32 *t_sum);       /* tramas y tics del temporizador por trama */

u32  mp3_now(void);                                        /* la da la plataforma (temporizador global) */

#endif
