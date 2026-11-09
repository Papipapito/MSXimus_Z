/* inflate.c — descompresor zlib (RFC 1950/1951) del companion (30/10/2026), para los perfiles de la TF1 (mxpf.c).
 *
 * Codigo propio, sin fuentes de terceros: el esquema de decodificacion es el canonico de la RFC 1951 (cuentas de
 * codigos por longitud y simbolos ordenados, como en puff.c de Mark Adler y en tinf), leyendo el flujo bit a bit.
 * Se prueba en el PC contra zlib de Python con datos de todo tipo y con flujos rotos (tests/mxpf_host/test_inflate.c).
 * Comprueba todo: cabecera, bloques, codigos Huffman sobresuscritos o incompletos, distancias, desbordes de entrada y de
 * salida y el Adler-32. Solo accede a bytes (nada de memcpy ni accesos desalineados). Las tablas y el estado van en
 * mz_work, que el llamador pone en memoria con cache (ver inflate.h). */
#include "inflate.h"

#define MAXBITS 15

static const u16 lbase[29] = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
static const u8  lext[29]  = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
static const u16 dbase[30] = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
static const u8  dext[30]  = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };
static const u8  orden_cl[19] = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

/* need bits (0..16) del flujo, el primero en el bit menos significativo; 0 y s->err si se acaba la entrada */
static u32 mz_bits(mz_work *s, int need)
{
    u32 v = s->bb;
    int bn = s->bn;
    while (bn < need) {
        if (s->pos >= s->srclen) { s->err = MZ_E_ENTRADA; return 0; }
        v |= (u32)s->src[s->pos++] << bn;
        bn += 8;
    }
    s->bb = v >> need;
    s->bn = bn - need;
    return v & ((1UL << need) - 1U);
}

/* un simbolo Huffman; < 0 si el codigo no existe o se acaba la entrada (s->err puesto) */
static int mz_decode(mz_work *s, const mz_huff *h)
{
    int code = 0, first = 0, index = 0, len;
    u32 bb = s->bb;
    int bn = s->bn;
    for (len = 1; len <= MAXBITS; len++) {
        int cuenta;
        if (bn == 0) {
            if (s->pos >= s->srclen) { s->err = MZ_E_ENTRADA; s->bb = bb; s->bn = bn; return -1; }
            bb = s->src[s->pos++];
            bn = 8;
        }
        code |= (int)(bb & 1U);
        bb >>= 1;
        bn--;
        cuenta = h->cuenta[len];
        if (code - cuenta < first) { s->bb = bb; s->bn = bn; return h->simbolo[index + (code - first)]; }
        index += cuenta;
        first += cuenta;
        first <<= 1;
        code <<= 1;
    }
    s->bb = bb; s->bn = bn;
    s->err = MZ_E_HUFF;
    return -1;
}

/* construye la tabla de n longitudes; 0 = codigo completo, > 0 = incompleto, < 0 = sobresuscrito */
static int mz_construye(mz_huff *h, const u16 *largo, int n)
{
    u16 offs[MAXBITS + 1];
    int len, sym, left;
    for (len = 0; len <= MAXBITS; len++) h->cuenta[len] = 0;
    for (sym = 0; sym < n; sym++) h->cuenta[largo[sym]]++;
    if (h->cuenta[0] == n) return 0;
    left = 1;
    for (len = 1; len <= MAXBITS; len++) {
        left <<= 1;
        left -= h->cuenta[len];
        if (left < 0) return left;
    }
    offs[1] = 0;
    for (len = 1; len < MAXBITS; len++) offs[len + 1] = (u16)(offs[len] + h->cuenta[len]);
    for (sym = 0; sym < n; sym++) if (largo[sym] != 0U) h->simbolo[offs[largo[sym]]++] = (u16)sym;
    return left;
}

/* literales y pares (longitud, distancia) hasta el fin de bloque */
static int mz_codigos(mz_work *s)
{
    for (;;) {
        int sym = mz_decode(s, &s->lit);
        if (sym < 0) return s->err;
        if (sym < 256) {
            if (s->n >= s->cap) return MZ_E_SALIDA;
            s->dst[s->n++] = (u8)sym;
        } else if (sym == 256) {
            return 0;
        } else {
            u32 largo, dist, i;
            int ds;
            sym -= 257;
            if (sym >= 29) return MZ_E_BLOQUE;
            largo = lbase[sym] + mz_bits(s, lext[sym]);
            ds = mz_decode(s, &s->dist);
            if (ds < 0) return s->err;
            if (ds >= 30) return MZ_E_BLOQUE;
            dist = dbase[ds] + mz_bits(s, dext[ds]);
            if (s->err) return s->err;
            if (dist > s->n) return MZ_E_BLOQUE;
            if (largo > s->cap - s->n) return MZ_E_SALIDA;
            for (i = 0; i < largo; i++) { s->dst[s->n] = s->dst[s->n - dist]; s->n++; }
        }
    }
}

static int mz_almacenado(mz_work *s)
{
    u32 largo, i;
    s->bb = 0; s->bn = 0;                                     /* a la frontera de byte */
    if (s->pos + 4U > s->srclen) return MZ_E_ENTRADA;
    largo = (u32)s->src[s->pos] | ((u32)s->src[s->pos + 1] << 8);
    if (largo != (~((u32)s->src[s->pos + 2] | ((u32)s->src[s->pos + 3] << 8)) & 0xFFFFU)) return MZ_E_BLOQUE;
    s->pos += 4U;
    if (largo > s->srclen - s->pos) return MZ_E_ENTRADA;
    if (largo > s->cap - s->n) return MZ_E_SALIDA;
    for (i = 0; i < largo; i++) s->dst[s->n++] = s->src[s->pos++];
    return 0;
}

static int mz_fijo(mz_work *s)
{
    u16 largo[288];
    int sym;
    for (sym = 0; sym < 144; sym++) largo[sym] = 8;
    for (; sym < 256; sym++) largo[sym] = 9;
    for (; sym < 280; sym++) largo[sym] = 7;
    for (; sym < 288; sym++) largo[sym] = 8;
    mz_construye(&s->lit, largo, 288);
    for (sym = 0; sym < 30; sym++) largo[sym] = 5;
    mz_construye(&s->dist, largo, 30);
    return mz_codigos(s);
}

static int mz_dinamico(mz_work *s)
{
    u16 largo[286 + 30];
    mz_huff cl;
    int nlen, ndist, ncode, i, r;
    nlen = (int)mz_bits(s, 5) + 257;
    ndist = (int)mz_bits(s, 5) + 1;
    ncode = (int)mz_bits(s, 4) + 4;
    if (s->err) return s->err;
    if (nlen > 286 || ndist > 30) return MZ_E_BLOQUE;
    for (i = 0; i < 19; i++) largo[orden_cl[i]] = 0;
    for (i = 0; i < ncode; i++) largo[orden_cl[i]] = (u16)mz_bits(s, 3);
    if (s->err) return s->err;
    if (mz_construye(&cl, largo, 19) != 0) return MZ_E_HUFF;       /* el codigo de longitudes tiene que ser completo */
    i = 0;
    while (i < nlen + ndist) {
        int sym = mz_decode(s, &cl);
        if (sym < 0) return s->err;
        if (sym < 16) {
            largo[i++] = (u16)sym;
        } else {
            u16 val = 0;
            int rep;
            if (sym == 16) {
                if (i == 0) return MZ_E_BLOQUE;
                val = largo[i - 1];
                rep = 3 + (int)mz_bits(s, 2);
            } else if (sym == 17) {
                rep = 3 + (int)mz_bits(s, 3);
            } else {
                rep = 11 + (int)mz_bits(s, 7);
            }
            if (s->err) return s->err;
            if (i + rep > nlen + ndist) return MZ_E_BLOQUE;
            while (rep--) largo[i++] = val;
        }
    }
    if (largo[256] == 0U) return MZ_E_BLOQUE;                       /* sin codigo de fin de bloque */
    r = mz_construye(&s->lit, largo, nlen);
    if (r < 0 || (r > 0 && nlen - s->lit.cuenta[0] != 1)) return MZ_E_HUFF;
    r = mz_construye(&s->dist, largo + nlen, ndist);
    if (r < 0 || (r > 0 && ndist - s->dist.cuenta[0] != 1)) return MZ_E_HUFF;
    return mz_codigos(s);
}

static u32 mz_adler(const u8 *p, u32 n)
{
    u32 a = 1U, b = 0U;
    while (n) {
        u32 k = n < 5552U ? n : 5552U;
        n -= k;
        while (k--) { a += *p++; b += a; }
        a %= 65521U;
        b %= 65521U;
    }
    return (b << 16) | a;
}

int mx_zlib(const u8 *src, u32 srclen, u8 *dst, u32 dstcap, u32 *outlen, mz_work *s)
{
    u32 fin, tipo, esperado;
    int r;
    if (srclen < 6U) return MZ_E_ENTRADA;
    if ((src[0] & 0x0FU) != 8U || (src[0] >> 4) > 7U || (((u32)src[0] << 8 | src[1]) % 31U) != 0U) return MZ_E_CAB;
    if (src[1] & 0x20U) return MZ_E_DICC;
    s->src = src; s->srclen = srclen; s->pos = 2U; s->bb = 0U; s->bn = 0; s->err = 0;
    s->dst = dst; s->cap = dstcap; s->n = 0U;
    do {
        fin = mz_bits(s, 1);
        tipo = mz_bits(s, 2);
        if (s->err) return s->err;
        if (tipo == 0U) r = mz_almacenado(s);
        else if (tipo == 1U) r = mz_fijo(s);
        else if (tipo == 2U) r = mz_dinamico(s);
        else return MZ_E_BLOQUE;
        if (r) return r;
    } while (!fin);
    if (s->pos + 4U > srclen) return MZ_E_ENTRADA;
    esperado = ((u32)src[s->pos] << 24) | ((u32)src[s->pos + 1] << 16) | ((u32)src[s->pos + 2] << 8) | src[s->pos + 3];
    if (mz_adler(dst, s->n) != esperado) return MZ_E_ADLER;
    *outlen = s->n;
    return 0;
}
