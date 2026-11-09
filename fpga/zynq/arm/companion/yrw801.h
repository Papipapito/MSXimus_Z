/* yrw801.h — comprobacion de la ROM de ondas del OPL4 (YRW801) que el FSBL deja en la DDR. Ver yrw801.c. */
#ifndef YRW801_H
#define YRW801_H
#include "xil_types.h"

enum { YRW801_COMPROBANDO = 0, YRW801_OK, YRW801_MAL };

void yrw801_poll(void);                 /* cada vuelta del bucle SIN peticion de la SD pendiente: suma un tramo, hasta acabar */
int  yrw801_estado(void);               /* YRW801_* (COMPROBANDO hasta que se han sumado los 2 MB) */

#endif
