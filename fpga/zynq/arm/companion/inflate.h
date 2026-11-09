/* inflate.h — descompresor zlib (RFC 1950/1951) del companion, para los perfiles de la TF1 (mxpf.c). */
#ifndef INFLATE_H
#define INFLATE_H
#include "xil_types.h"

enum { MZ_OK = 0, MZ_E_CAB = -1, MZ_E_DICC = -2, MZ_E_ENTRADA = -3, MZ_E_BLOQUE = -4, MZ_E_SALIDA = -5, MZ_E_ADLER = -6, MZ_E_HUFF = -7 };

/* Tablas y estado del descompresor (unos 1,5 KB). Tienen que estar en memoria CON cache: el companion corre en
 * memoria strongly-ordered (mmu.c) salvo unas zonas, y un acceso a las tablas por cada bit leido costaria segundos. */
typedef struct { u16 cuenta[16]; u16 simbolo[288]; } mz_huff;
typedef struct {
    const u8 *src; u32 srclen, pos, bb;
    int bn, err;
    u8 *dst; u32 cap, n;
    mz_huff lit, dist;
} mz_work;

/* Descomprime un flujo zlib (cabecera de 2 bytes, deflate, Adler-32) de src a dst. dstcap = bytes que caben en dst;
 * *outlen = bytes descomprimidos (solo si devuelve 0). 0 = bien; < 0 = MZ_E_*. src, dst y w: memoria con cache;
 * no hace falta alineacion (solo accede a bytes). */
int mx_zlib(const u8 *src, u32 srclen, u8 *dst, u32 dstcap, u32 *outlen, mz_work *w);
#endif
