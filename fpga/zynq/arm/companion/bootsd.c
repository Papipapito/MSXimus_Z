/* bootsd.c — leer el BOOT.bin de la raiz de la FAT32 o FAT16 de la TF1. Ver bootsd.h.
 * Solo lectura, por tf1_leer() (main.c): la SD hace DMA, asi que los buffers de lectura son estaticos (.bss, que en el companion es
 * memoria sin cache) y el destino final recibe una copia por palabras. Sin newlib.
 * FAT16 (10/11, segunda prueba en placa): la tarjeta con la que arranco la placa era FAT16 (una particion de tipo 0E) y la pagina decia
 * "no es FAT32". El BootROM del Zynq lee FAT16 y FAT32, asi que esta pagina tiene que poder leer lo mismo que arranca. FAT12 no (volumenes
 * de menos de 4085 clusters: no caben en una tarjeta de verdad). */
#include "bootsd.h"
#include "mxpf.h"                              /* tf1_leer */

#define SEC     512U

static u8 sb[SEC] __attribute__((aligned(32)));                 /* sector suelto: arranque, directorio */
static u8 fb[SEC] __attribute__((aligned(32)));                 /* sector de la FAT que se esta mirando */
static u8 tr[BSD_TROZO] __attribute__((aligned(32)));           /* el trozo que lee la SD */
static u32 fb_lba;

/* geometria del volumen. ncl = clusters de datos (del 2 al ncl + 1). FAT32: la raiz es la cadena que empieza en `root`. FAT16: la raiz son
 * los `rn` sectores fijos desde `rsec` (entre las FAT y los datos) y la FAT tiene entradas de 16 bits. */
static struct { u32 fat, data, root, rsec, rn, spc, ncl; u8 f16; } g;
static struct { u32 clus, sec, quedan; u8 abierto; } c;         /* el fichero: cluster y sector dentro de el, bytes que faltan */
static char diag[BSD_DIAG + 1U];                                 /* bootsd_diag() */
static u32 dn;

static u16 rd16(const u8 *p) { return (u16)(p[0] | (p[1] << 8)); }
static u32 rd32(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24); }

static int lee(u32 lba, u32 n, void *b) { return tf1_leer(lba, n, b); }

static void d_s(const char *s) { while (*s && dn < BSD_DIAG) diag[dn++] = *s++; diag[dn] = 0; }
static void d_x(u8 v) { static const char h[] = "0123456789ABCDEF"; char t[3]; t[0] = h[v >> 4]; t[1] = h[v & 15U]; t[2] = 0; d_s(t); }
const char *bootsd_diag(void) { return diag; }

static int oem(const u8 *s, const char *n) { u32 i; for (i = 0; i < 8U; i++) if (s[3 + i] != (u8)n[i]) return 0; return 1; }

typedef struct { u32 rsvd, nfats, spf, rn, ncl, root; u8 f16; } geo_t;

/* ¿es el sector de arranque de un volumen FAT32 o FAT16? 0 si lo es (y la geometria en *o); si no, por que no (para bootsd_diag).
 * No basta la firma: un MBR tambien la lleva. FAT32 se decide por la ESTRUCTURA, como Windows: raiz en clusters (sin raiz fija) y FAT de
 * 32 bits (FATSz16 = 0), y NO por el numero de clusters de la especificacion (65525): Windows formatea en FAT32 volumenes con menos y los
 * monta (primera prueba en placa, 10/11: la P1 de 128 MiB de la tarjeta de perfiles formateada en Windows). Con raiz fija y FAT de 16 bits
 * es FAT16 o FAT12, y ahi si manda el numero de clusters (menos de 4085: FAT12, que no se lee). */
static const char *fat_mal(const u8 *s, geo_t *o)
{
    u32 spc = s[13], rsvd = rd16(s + 14), nfats = s[16], rootent = rd16(s + 17), f16sz = rd16(s + 22);
    u32 tot = rd16(s + 19) ? rd16(s + 19) : rd32(s + 32), spf, rn, n, cap;
    if (s[510] != 0x55 || s[511] != 0xAA) return "sin55AA";
    if (oem(s, "EXFAT   ")) return "exFAT";
    if (oem(s, "NTFS    ")) return "NTFS";
    if (rd16(s + 11) != SEC || spc == 0 || (spc & (spc - 1U)) || spc > 128U) return "BPB raro";
    if (rsvd == 0 || nfats == 0 || nfats > 2U) return "BPB raro";
    if (rootent == 0 && f16sz == 0) { o->f16 = 0; spf = rd32(s + 36); rn = 0; }                 /* FAT32 */
    else if (rootent != 0 && f16sz != 0) { o->f16 = 1; spf = f16sz; rn = (rootent * 32U + SEC - 1U) / SEC; }   /* FAT16/12 */
    else return "BPB raro";
    if (spf == 0 || tot <= rsvd + rn || spf > (tot - rsvd - rn) / nfats) return "BPB raro";   /* las FAT no caben (y sin desbordar) */
    n = (tot - rsvd - rn - nfats * spf) / spc;
    if (o->f16 && n < 4085U) return "FAT12";
    cap = o->f16 ? spf * (SEC / 2U) : (spf < 0x01000000U ? spf * (SEC / 4U) : 0xFFFFFFFFU);   /* entradas que caben en una FAT */
    if (n > cap - 2U) n = cap - 2U;                                                      /* no mas clusters de los que apunta la FAT */
    if (o->f16 && n > 65524U) n = 65524U;
    o->root = o->f16 ? 0 : rd32(s + 44);
    if (n == 0 || (!o->f16 && (o->root < 2U || o->root > n + 1U))) return "BPB raro";
    o->rsvd = rsvd; o->nfats = nfats; o->spf = spf; o->rn = rn; o->ncl = n;
    return 0;
}

/* sector 0 = un sector de arranque (volumen sin tabla de particiones) y no un MBR: empieza por un salto y dice 512 bytes por sector,
 * o es exFAT/NTFS (que no rellenan el BPB). El MBR de Windows empieza por 33 C0 y el de SD Formatter por ceros. */
static int es_vbr(const u8 *s) { return ((s[0] == 0xEB || s[0] == 0xE9) && rd16(s + 11) == SEC) || oem(s, "EXFAT   ") || oem(s, "NTFS    "); }

static int monta(void)
{
    u32 part = 0, i, lba[4], i1 = 0;
    const char *mal, *mal1 = 0;
    geo_t o;
    fb_lba = 0xFFFFFFFFU;
    dn = 0; diag[0] = 0;
    if (!lee(0, 1, sb)) return BSD_SIN_TARJETA;
    mal = fat_mal(sb, &o);
    if (mal) {
        if (sb[510] != 0x55 || sb[511] != 0xAA) { d_s("Sector 0 sin 55AA"); return BSD_SIN_FAT32; }
        if (es_vbr(sb)) { d_s("Sin MBR: "); d_s(mal); return BSD_SIN_FAT32; }
        d_s("MBR");
        for (i = 0; i < 4U; i++) {                                           /* la tabla, antes de que sb se reutilice */
            const u8 *e = sb + 446 + 16 * i;
            u8 t = e[4];
            d_s(" "); d_x(t);
            lba[i] = (t == 0 || t == 0x05 || t == 0x0F || t == 0x85 || t == 0xEE) ? 0 : rd32(e + 8);   /* vacia, extendida, GPT */
        }
        for (i = 0; i < 4U; i++) {                                           /* la primera particion con una FAT, sea cual sea su tipo */
            if (lba[i] == 0) continue;
            mal = lee(lba[i], 1, sb) ? fat_mal(sb, &o) : "ilegible";
            if (!mal) { part = lba[i]; break; }
            if (!mal1) { mal1 = mal; i1 = i; }
        }
        if (i == 4U) {
            if (mal1) { char t[5] = { ' ', 'P', (char)('1' + i1), ':', 0 }; d_s(t); d_s(mal1); }
            else d_s(" vacio");
            return BSD_SIN_FAT32;
        }
        dn = 0; diag[0] = 0;                                                 /* montada: no hay nada que contar */
    }
    g.spc = sb[13];
    g.f16 = o.f16;
    g.fat = part + o.rsvd;
    g.rsec = g.fat + o.nfats * o.spf;
    g.rn = o.rn;
    g.data = g.rsec + g.rn;
    g.root = o.root;
    g.ncl = o.ncl;
    return BSD_OK;
}

static u32 clus_lba(u32 cl) { return g.data + (cl - 2U) * g.spc; }

/* siguiente cluster de la cadena: >= 2 si lo hay, 0 al final, 0xFFFFFFFF si la cadena esta rota */
static u32 sig_cluster(u32 cl)
{
    u32 off = cl * (g.f16 ? 2U : 4U), lba = g.fat + off / SEC, v;
    if (lba != fb_lba) { if (!lee(lba, 1, fb)) return 0xFFFFFFFFU; fb_lba = lba; }
    if (g.f16) {
        v = rd16(fb + (off % SEC));
        if (v >= 0xFFF8U) return 0;
    } else {
        v = rd32(fb + (off % SEC)) & 0x0FFFFFFFU;
        if (v >= 0x0FFFFFF8U) return 0;
    }
    if (v < 2U || v > g.ncl + 1U) return 0xFFFFFFFFU;                       /* fuera del volumen (o el de cluster malo, FFF7) */
    return v;
}

/* busca BOOT.bin en un sector de la raiz: 0 = seguir con el sector siguiente; si no, el resultado de bootsd_abre */
static int en_sector(const u8 *s, u32 *tam, int *r)
{
    static const u8 nombre[11] = { 'B', 'O', 'O', 'T', ' ', ' ', ' ', ' ', 'B', 'I', 'N' };
    u32 e;
    for (e = 0; e < SEC; e += 32U) {
        const u8 *d = s + e;
        u32 i, size, first;
        if (d[0] == 0) { *r = BSD_SIN_BOOT; return 1; }                      /* fin del directorio */
        if (d[0] == 0xE5 || d[11] == 0x0F || (d[11] & 0x18U)) continue;       /* borrado, nombre largo, carpeta o etiqueta */
        for (i = 0; i < 11U; i++) if (d[i] != nombre[i]) break;
        if (i < 11U) continue;
        first = (g.f16 ? 0U : (u32)rd16(d + 20) << 16) | rd16(d + 26);       /* en FAT16 la palabra alta no cuenta */
        size = rd32(d + 28);
        if (first < 2U || size == 0) { *r = BSD_SIN_BOOT; return 1; }
        if (size < BSD_MIN || size > BSD_MAX) { *r = BSD_TAM; return 1; }
        if (first > g.ncl + 1U) { *r = BSD_CADENA; return 1; }              /* empieza fuera del volumen */
        c.clus = first; c.sec = 0; c.quedan = size; c.abierto = 1;
        *tam = size;
        *r = BSD_OK;
        return 1;
    }
    return 0;
}

int bootsd_abre(u32 *tam)
{
    u32 cl, k, guarda = 0;
    int r = monta();
    c.abierto = 0;
    if (r != BSD_OK) return r;
    if (g.f16) {                                                             /* FAT16: la raiz son sectores fijos */
        for (k = 0; k < g.rn; k++) {
            if (!lee(g.rsec + k, 1, sb)) return BSD_IO;
            if (en_sector(sb, tam, &r)) return r;
        }
        return BSD_SIN_BOOT;
    }
    for (cl = g.root; cl && guarda < 65536U; guarda++) {                     /* FAT32: los clusters de la raiz */
        for (k = 0; k < g.spc; k++) {
            if (!lee(clus_lba(cl) + k, 1, sb)) return BSD_IO;
            if (en_sector(sb, tam, &r)) return r;
        }
        cl = sig_cluster(cl);
        if (cl == 0xFFFFFFFFU) return BSD_CADENA;
    }
    return BSD_SIN_BOOT;
}

int bootsd_sig(u8 *dst, u32 *n)
{
    u32 quedan_s, want, k, lba, cl, nsec, i, bytes;
    *n = 0;
    if (!c.abierto || c.quedan == 0) return BSD_OK;
    quedan_s = (c.quedan + SEC - 1U) / SEC;
    want = BSD_TROZO / SEC;
    if (want > quedan_s) want = quedan_s;
    /* sectores seguidos en la tarjeta a partir de (clus, sec): lo que queda de este cluster y los siguientes si son contiguos */
    lba = clus_lba(c.clus) + c.sec;
    nsec = g.spc - c.sec;
    if (nsec > want) nsec = want;
    for (cl = c.clus; nsec < want; ) {
        u32 nx = sig_cluster(cl);
        if (nx == 0xFFFFFFFFU) return BSD_CADENA;
        if (nx != cl + 1U) break;                                            /* fragmentado: el resto, en la vuelta siguiente */
        cl = nx;
        k = g.spc; if (k > want - nsec) k = want - nsec;
        nsec += k;
    }
    if (!lee(lba, nsec, tr)) return BSD_IO;
    bytes = nsec * SEC; if (bytes > c.quedan) bytes = c.quedan;
    {
        u32 *d = (u32 *)(void *)dst;                                         /* dst alineado a 4: IMG lo esta */
        const u32 *s = (const u32 *)(const void *)tr;
        for (i = 0; i < (bytes >> 2); i++) d[i] = s[i];
        for (i = bytes & ~3U; i < bytes; i++) dst[i] = tr[i];
    }
    c.quedan -= bytes;
    for (i = 0; i < nsec && c.quedan; i++) {                                 /* avanza el cursor un sector por vuelta */
        if (++c.sec == g.spc) {
            u32 nx = sig_cluster(c.clus);
            c.sec = 0;
            if (nx == 0xFFFFFFFFU || nx == 0) return BSD_CADENA;                 /* aun faltan datos: la cadena no puede acabar aqui */
            c.clus = nx;
        }
    }
    *n = bytes;
    return BSD_OK;
}
