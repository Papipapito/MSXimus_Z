/* mxpf.c — perfiles del PL en la microSD de TF1 (30/10/2026, fase 5 del estudio de perfiles:
 * el estudio interno de perfiles, apartados 6.2 a 6.6). "MXPF" = el formato de una particion propia, SIN sistema
 * de ficheros, de tipo 0xDA, que solo ve el companion (Nextor solo monta FAT12/FAT16/FAT16S/FAT16L y salta cualquier
 * otro tipo: Nextor-research/source/kernel/bank4/partit.mac, AA_PX_NOEX).
 *
 * FORMATO (todo little-endian, sectores de 512 B; los LBA de los campos son RELATIVOS al inicio de la particion)
 *   MBR del usuario: una entrada libre pasa a tipo 0xDA, inicio alineado a 1 MB tras la ultima particion, 17..32 MB.
 *   sector 0   superbloque: "MXPF", version (1), tamano de la particion (sectores), primer hueco (2048), sectores por hueco
 *              (8192 = 4 MB), numero de huecos (<= 6), sector de la copia del MBR (3), CRC-32 de los 508 primeros bytes.
 *   sector 1,2 directorio A y B: "MXPD", secuencia, numero de entradas, hasta 6 entradas de 80 B, CRC-32. Vale el mas alto
 *              con CRC bueno. Se escribe SIEMPRE el que no manda, con secuencia + 1.
 *   sector 3   copia del sector 0 original de la tarjeta (el MBR de antes de preparar).
 *   desde 2048 los huecos de 4 MB: el contenido guardado de cada perfil, que empieza al principio de su hueco.
 *   entrada (80 B): +0 id (8, ASCII mayusculas/cifras/_/-, relleno de 0), +8 serie del sistema, +12 version (16),
 *              +28 metodo (0 crudo, 1 zlib), +29 banderas (1 = usada), +32 LBA (hueco), +36 bytes guardados, +40 bytes del
 *              .bin (el que acepta la PCAP: bootgen -process_bitstream bin), +44 reservado, +48 SHA-256 de lo guardado.
 *   Apagon: los datos van a un hueco libre (nadie los referencia), se releen y se comprueba el SHA-256, y solo entonces se
 *   escribe UN sector de directorio. Un sector a medias falla el CRC y manda el otro: queda el estado de antes o el nuevo.
 *   Preparar tarjeta: primero la particion entera (copia del MBR, directorios, superbloque el ULTIMO), se relee, y solo
 *   entonces se toca el sector 0 de la tarjeta (una entrada de 16 bytes). Nunca se mueve ni se cambia otra particion.
 * FICHERO .mxp (tools/mxpf.py): sector 0 = "MXP1", version (1), 512, CRC-32 de la entrada, entrada de 80 B con el LBA a 0;
 *   desde el byte 512 el contenido guardado, relleno a 512.
 *
 * MEMORIA. El companion corre en memoria strongly-ordered (mmu.c) salvo unas zonas; sin cache el DMA de la SD ve lo que
 * escribe la CPU, pero cada acceso cuesta ~100 ns, y Xil_DCache* son vacios. Por eso: la SD lee y escribe SOLO en la zona
 * de PF_ZONA (sin cache) y todo lo que se recorre muchas veces (SHA-256, zlib) se copia antes a la zona CON cache de la
 * actualizacion por red (0x01000000, la misma de ota.c: no se usa si ota_ocupada()).
 *   PF_ZONA + 0x100 ordenes, + 0x200 informe, + 0x400 texto, + 0x1000 el .mxp (o el contenido leido), + 0x3F0000 64 KB de
 *   sectores de trabajo; cache: +0 contenido guardado (3,5 MB), +0x380000 rebote de 64 KB, +0x390000 tablas de zlib y SHA,
 *   +0x400000 el .bin descomprimido (hasta 4 MB), que es lo que recibe perfil_cargar.
 * LA PILA TAMBIEN es strongly-ordered: el SHA-256 de Mbed TLS (324 B de pila y 296 escrituras de byte en cada bloque para borrarla)
 * y zlib hacen miles de accesos a la pila por cada KB, y a ~100 ns cada uno el SHA de 1,3 MB costaba 1,2 a 2 s (revision del
 * 31/10). Por eso el SHA-256 y zlib corren con SP en la zona con cache (en_pila: +0x392000, 16 KB).
 * TF1 la comparte con Nextor: todo corre en el hilo del bucle principal (no hay dos accesos a la vez) y entre trozos de
 * 128 KB se llama a sd_ceder(), que sirve la peticion de Nextor pendiente (el proxy del PL da error a los 2 s sin acuse). */
#include "xil_types.h"
#include "profile.h"
#include "inflate.h"
#include "mxpf.h"
#include "tr_bios.h"
#include "log.h"
#include "mbedtls/sha256.h"
#ifdef MXPF_HOST
#include "mxpf_host.h"
#else
#include "xparameters.h"
#include "xil_io.h"
extern u64  gt_now(void);
extern void ota_reinicia_ps(void);
#define MX_SO           ((u8 *)(uintptr_t)PF_ZONA)
#define MX_CA           ((u8 *)(uintptr_t)0x01000000U)
#define MX_BOOT_MODO()  (Xil_In32(0xF800025CU) & 7U)       /* BOOT_MODE: 0 JTAG, 1 QSPI, 5 SD */
#endif

#define SEC             512U
#define MX_ALIN         2048U                              /* alineacion de la particion: 1 MB */
#define MX_MIN_SECS     (17U * 2048U)
#define MX_PREF_SECS    (32U * 2048U)
#define MX_PRIMER       2048U                              /* primer hueco: tras 1 MB de cabecera */
#define MX_HUECO        8192U                              /* sectores por hueco: 4 MB */
#define MX_MAXPAY       0x00380000U                        /* mayor contenido guardado: 3,5 MB */
#define MX_COPIA_MBR    3U
#define ENT             80U                                /* bytes de una entrada */
#define CHUNK           256U                               /* sectores por llamada a la SD (128 KB) */

#define Z_ORD           0x100U
#define Z_INF           0x200U
#define Z_TXT           0x400U
#define Z_TXTSZ         0xC00U
#define Z_DATOS         0x1000U
#define Z_SCR           0x3F0000U
#define SC_MBR          0x000U
#define SC_SB           0x200U
#define SC_DA           0x400U
#define SC_DB           0x600U
#define SC_AUX          0x800U
#define SC_TMP          0xA00U
#define SC_IO           0x1000U                            /* 60 KB: 120 sectores */
#define IO_SECS         120U
#define CA_A            0x000000U
#define CA_BNC          0x380000U
#define CA_W            0x390000U
#define CA_SHA          0x390800U
#define CA_PILA         0x392000U                          /* 16 KB: la pila del SHA-256 y de zlib (en_pila) */
#define PILA_TAM        0x4000U
#define CA_B            0x400000U

u32 mxpf_t[MXT_N];

static mxpf_info_t I;
static u32 G_part, G_psecs, G_sf, G_ss, G_sn, G_seq, G_cur;
static u8  act_tipo;
static mxpf_perfil act_p;
static u32 corte_n;                                        /* apagon simulado: sectores que aun se escriben */
static u8  corte_on, corte_hecho, rd_idx;
static u64 t_op;

/* ---- utilidades (bytes: memcpy de newlib y la memoria strongly-ordered no se llevan) ------------------------------ */
static u32 rd32(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24); }
static void wr32(u8 *p, u32 v) { p[0] = (u8)v; p[1] = (u8)(v >> 8); p[2] = (u8)(v >> 16); p[3] = (u8)(v >> 24); }
static void mx_set(u8 *d, u8 v, u32 n) { while (n--) *d++ = v; }
static void mx_cp(u8 *d, const u8 *s, u32 n) { while (n--) *d++ = *s++; }
static int  mx_eq(const u8 *a, const u8 *b, u32 n) { while (n--) if (*a++ != *b++) return 0; return 1; }
static u8 *sc(u32 off) { return MX_SO + Z_SCR + off; }
static u8 *ca(u32 off) { return MX_CA + off; }

static u32 crc32(const u8 *p, u32 n)
{
    u32 c = 0xFFFFFFFFU, k;
    while (n--) {
        c ^= *p++;
        for (k = 0; k < 8U; k++) c = (c >> 1) ^ (0xEDB88320U & (0U - (c & 1U)));
    }
    return ~c;
}

/* copia de la zona sin cache a la zona con cache, por palabras (n se redondea a 4; hay margen en los dos lados) */
static void so2ca(u8 *dst, const u8 *src, u32 n)
{
    u32 *d = (u32 *)(void *)dst;
    const volatile u32 *s = (const volatile u32 *)(const void *)src;
    for (n = (n + 3U) >> 2; n; n--) *d++ = *s++;
}
static void ca2ca(u8 *dst, const u8 *src, u32 n)
{
    u32 *d = (u32 *)(void *)dst;
    const u32 *s = (const u32 *)(const void *)src;
    for (n = (n + 3U) >> 2; n; n--) *d++ = *s++;
}

static u32 us_de(u64 t) { return (u32)((gt_now() - t) / (u64)(COUNTS_PER_SECOND / 1000000U)); }

static void op_ini(void)
{
    u32 i;
    for (i = 0; i < MXT_N; i++) mxpf_t[i] = 0U;
    rd_idx = MXT_LEE;
    t_op = gt_now();
    sd_ceder();
}
static int op_fin(int r)
{
    if (corte_hecho) r = MXPF_E_CORTE;
    corte_on = 0; corte_hecho = 0;
    mxpf_t[MXT_TOTAL] = us_de(t_op);
    return r;
}
void mxpf_corte(u32 sectores) { corte_n = sectores; corte_on = 1; corte_hecho = 0; }

/* ---- E/S de bloques de la TF1 con tiempos y apagon simulado ---------------------------------------------------------- */
static int blk_rd(u32 sec, u32 n, u8 *b)
{
    u64 t = gt_now();
    int r = tf1_leer(sec, n, b);
    mxpf_t[rd_idx] += us_de(t);
    return r;
}
static int blk_wr(u32 sec, u32 n, const u8 *b)
{
    u64 t = gt_now();
    int r;
    if (corte_on) {
        if (corte_n < n) {                                 /* se va la luz aqui: llegan corte_n sectores */
            if (corte_n) (void)tf1_escribir(sec, corte_n, b);
            corte_n = 0; corte_hecho = 1;
            log_str("mxpf: CORTE SIMULADO\n");
            return 0;
        }
        corte_n -= n;
    }
    r = tf1_escribir(sec, n, b);
    mxpf_t[MXT_ESC] += us_de(t);
    return r;
}
static int rd_largo(u32 sec, u32 n, u8 *b)
{
    while (n) {
        u32 k = n < CHUNK ? n : CHUNK;
        if (!blk_rd(sec, k, b)) return 0;
        sec += k; n -= k; b += k * SEC;
        sd_ceder();
    }
    return 1;
}
static int wr_largo(u32 sec, u32 n, const u8 *b)
{
    while (n) {
        u32 k = n < CHUNK ? n : CHUNK;
        if (!blk_wr(sec, k, b)) return 0;
        sec += k; n -= k; b += k * SEC;
        sd_ceder();
    }
    return 1;
}

/* ---- calculo pesado con la pila en la zona con cache -------------------------------------------------------------------- */
/* Llama a f(a) con SP en la zona con cache y vuelve a la pila de siempre. Una sola hebra, interrupciones enmascaradas y f no
 * sale por longjmp: no hay quien use la pila mientras tanto. f solo puede usar hasta PILA_TAM bytes (SHA-256 y zlib: < 2 KB). */
#ifdef MXPF_HOST
static u32 en_pila(u32 (*f)(void *), void *a) { return f(a); }
#else
static u32 en_pila(u32 (*f)(void *), void *a)
{
    register u32 r0 __asm__("r0") = (u32)(uintptr_t)a;
    register u32 r1 __asm__("r1") = (u32)(uintptr_t)f;
    register u32 r2 __asm__("r2") = (u32)(uintptr_t)(MX_CA + CA_PILA + PILA_TAM);
    __asm__ volatile ("mov r4, sp\n\tmov sp, r2\n\tblx r1\n\tmov sp, r4\n"
                      : "+r"(r0), "+r"(r1), "+r"(r2) : : "r3", "r4", "r12", "lr", "memory", "cc");
    return r0;
}
#endif

/* ---- SHA-256: contexto en la zona con cache -------------------------------------------------------------------------- */
typedef struct { const u8 *p; u32 n; u8 *out; } sha_job;
static mbedtls_sha256_context *shac(void) { return (mbedtls_sha256_context *)(void *)ca(CA_SHA); }
static u32 sha_t_ini(void *v) { (void)v; mbedtls_sha256_init(shac()); (void)mbedtls_sha256_starts(shac(), 0); return 0; }
static u32 sha_t_upd(void *v) { sha_job *j = (sha_job *)v; (void)mbedtls_sha256_update(shac(), j->p, j->n); return 0; }
static u32 sha_t_fin(void *v) { sha_job *j = (sha_job *)v; (void)mbedtls_sha256_finish(shac(), j->out); mbedtls_sha256_free(shac()); return 0; }
static void sha_ini(void) { (void)en_pila(sha_t_ini, 0); }
static void sha_upd(const u8 *p, u32 n) { sha_job j; j.p = p; j.n = n; j.out = 0; (void)en_pila(sha_t_upd, &j); }
static void sha_fin(u8 *out) { sha_job j; j.p = 0; j.n = 0; j.out = out; (void)en_pila(sha_t_fin, &j); }
static void sha_todo(const u8 *p, u32 n, u8 *out)           /* trozos de 64 KB (multiplo de 64): entre uno y otro se atiende a Nextor */
{
    u32 off;
    sha_ini();
    for (off = 0; off < n; off += 0x10000U) { sha_upd(p + off, n - off < 0x10000U ? n - off : 0x10000U); sd_ceder(); }
    sha_fin(out);
}

typedef struct { const u8 *src; u32 srclen; u8 *dst; u32 dstcap; u32 n; int r; } z_job;
static u32 z_trabajo(void *v)
{
    z_job *j = (z_job *)v;
    j->r = mx_zlib(j->src, j->srclen, j->dst, j->dstcap, &j->n, (mz_work *)(void *)ca(CA_W));
    return 0;
}

/* ---- entradas y directorios ---------------------------------------------------------------------------------------- */
static int id_ok(const u8 *id)                              /* 1..8 caracteres ASCII mayusculas, cifras, _ y - ; relleno de 0 */
{
    u32 i, n = 0;
    for (i = 0; i < 8U && id[i]; i++, n++)
        if (!((id[i] >= 'A' && id[i] <= 'Z') || (id[i] >= '0' && id[i] <= '9') || id[i] == '_' || id[i] == '-')) return 0;
    for (i = n; i < 8U; i++) if (id[i]) return 0;
    return n > 0U;
}

static int ent_lee(const u8 *e, mxpf_perfil *p)               /* 1 = entrada bien formada (la geometria la mira dir_lee) */
{
    u32 i;
    if (!(e[29] & 1U) || !id_ok(e)) return 0;
    for (i = 0; i < 8U; i++) p->id[i] = (char)e[i];
    p->id[8] = 0;
    for (i = 0; i < 16U && e[12 + i]; i++) { if (e[12 + i] < 0x20U || e[12 + i] > 0x7EU) return 0; p->version[i] = (char)e[12 + i]; }
    for (p->version[i] = 0, i++; i < 16U; i++) if (e[12 + i]) return 0;
    p->serie = rd32(e + 8); p->metodo = e[28]; p->lba = rd32(e + 32); p->tam = rd32(e + 36); p->tam_bin = rd32(e + 40);
    mx_cp(p->sha, e + 48, 32);
    if (p->metodo > 1U || p->tam == 0U || p->tam > MX_MAXPAY || p->tam_bin < 4096U || p->tam_bin > PF_MAX || (p->tam_bin & 3U)) return 0;
    if (p->metodo == 0U && p->tam != p->tam_bin) return 0;
    return 1;
}
static void ent_escribe(u8 *e, const mxpf_perfil *p)
{
    u32 i;
    mx_set(e, 0, ENT);
    for (i = 0; i < 8U && p->id[i]; i++) e[i] = (u8)p->id[i];
    wr32(e + 8, p->serie);
    for (i = 0; i < 16U && p->version[i]; i++) e[12 + i] = (u8)p->version[i];
    e[28] = p->metodo; e[29] = 1U;
    wr32(e + 32, p->lba); wr32(e + 36, p->tam); wr32(e + 40, p->tam_bin);
    mx_cp(e + 48, p->sha, 32);
}

static void dir_arma(u8 *s, u32 seq, const mxpf_perfil *p, int n)
{
    int i;
    mx_set(s, 0, SEC);
    mx_cp(s, (const u8 *)"MXPD", 4);
    wr32(s + 4, seq); wr32(s + 8, (u32)n);
    for (i = 0; i < n; i++) ent_escribe(s + 16 + (u32)i * ENT, &p[i]);
    wr32(s + 0x1FC, crc32(s, 0x1FC));
}

/* 1 = directorio valido; rellena seq y las entradas (n) si p != 0. Usa la geometria de la particion montada (G_sf...) */
static int dir_lee(const u8 *s, u32 *seq, mxpf_perfil *p, int *n)
{
    u32 k, i, j;
    mxpf_perfil t;
    if (!mx_eq(s, (const u8 *)"MXPD", 4) || rd32(s + 0x1FC) != crc32(s, 0x1FC)) return 0;
    k = rd32(s + 8);
    if (k > MXPF_MAX_PERF) return 0;
    for (i = 0; i < k; i++) {
        u32 h;
        if (!ent_lee(s + 16 + i * ENT, &t)) return 0;
        if (t.lba < G_sf || (t.lba - G_sf) % G_ss) return 0;
        h = (t.lba - G_sf) / G_ss;
        if (h >= G_sn || t.tam > G_ss * SEC) return 0;
        t.hueco = (u8)h;
        for (j = 0; j < i; j++) if (p && (p[j].hueco == t.hueco || mx_eq((const u8 *)p[j].id, (const u8 *)t.id, 9))) return 0;
        if (p) p[i] = t;
    }
    *seq = rd32(s + 4);
    *n = (int)k;
    return 1;
}

/* ---- MBR ------------------------------------------------------------------------------------------------------------ */
typedef struct { u8 tipo[4]; u32 lba[4], n[4]; u8 libre[4]; } mbr_t;

static int es_vbr(const u8 *s)                              /* sector de arranque de un volumen sin tabla de particiones */
{
    u32 c;
    if (mx_eq(s + 3, (const u8 *)"EXFAT   ", 8) || mx_eq(s + 3, (const u8 *)"NTFS    ", 8)) return 1;
    if (!(s[0] == 0xEB || s[0] == 0xE9)) return 0;
    c = s[13];
    return s[11] == 0x00 && s[12] == 0x02 && c && !(c & (c - 1U)) && (s[16] == 1U || s[16] == 2U);
}

static int mbr_analiza(const u8 *s, mbr_t *m)
{
    u32 i, k;
    if (s[510] != 0x55 || s[511] != 0xAA || es_vbr(s)) return MXPF_E_MBR;
    for (i = 0; i < 4U; i++) {
        const u8 *e = s + 0x1BE + 16U * i;
        if (e[0] != 0x00 && e[0] != 0x80) return MXPF_E_MBR;
        m->tipo[i] = e[4]; m->lba[i] = rd32(e + 8); m->n[i] = rd32(e + 12);
        if (e[4] == 0xEE) return MXPF_E_MBR;                /* GPT protector: esta tarjeta no es para tocar */
        m->libre[i] = 1U;
        for (k = 0; k < 16U; k++) if (e[k]) m->libre[i] = 0U;
    }
    return MXPF_OK;
}

/* donde cabria la particion: entrada libre, inicio alineado tras la ultima particion, tamano */
static int mbr_plan(const mbr_t *m, u32 secs, int *ent, u32 *ini, u32 *tam)
{
    u64 fin = 0, ini64, libre;
    int i, e = -1;
    for (i = 0; i < 4; i++) {
        if (m->libre[i]) { if (e < 0) e = i; }
        else { u64 f = (u64)m->lba[i] + (u64)m->n[i]; if (f > fin) fin = f; }
    }
    if (e < 0) return MXPF_E_ENTRADAS;
    ini64 = (fin + MX_ALIN - 1U) / MX_ALIN * MX_ALIN;
    if (ini64 < MX_ALIN) ini64 = MX_ALIN;
    if (ini64 + MX_MIN_SECS > (u64)secs) return MXPF_E_SITIO;
    libre = (u64)secs - ini64;
    *ent = e; *ini = (u32)ini64;
    *tam = libre >= MX_PREF_SECS ? MX_PREF_SECS : (u32)(libre / MX_ALIN * MX_ALIN);
    return MXPF_OK;
}

/* ---- superbloque y montaje ------------------------------------------------------------------------------------------ */
static int sb_valida(const u8 *s, u32 largo_mbr)             /* sin efectos: el superbloque es bueno y mide lo que dice el MBR */
{
    u32 psecs, sf, ss, sn;
    if (!mx_eq(s, (const u8 *)"MXPF", 4) || rd32(s + 0x1FC) != crc32(s, 0x1FC) || rd32(s + 4) != 1U) return 0;
    psecs = rd32(s + 8); sf = rd32(s + 12); ss = rd32(s + 16); sn = rd32(s + 20);
    if (psecs != largo_mbr || sn == 0U || sn > MXPF_MAX_PERF || ss == 0U || sf <= MX_COPIA_MBR) return 0;
    if ((u64)sf + (u64)sn * ss > (u64)psecs) return 0;
    return 1;
}
static int sb_ok(const u8 *s, u32 largo_mbr)
{
    if (!sb_valida(s, largo_mbr)) return 0;
    G_psecs = rd32(s + 8); G_sf = rd32(s + 12); G_ss = rd32(s + 16); G_sn = rd32(s + 20);
    return 1;
}

static void libres_calcula(void)
{
    u32 usado = 0;
    int i;
    for (i = 0; i < I.n; i++) usado |= 1U << I.p[i].hueco;
    I.huecos = (u8)G_sn;
    I.libres = 0;
    for (i = 0; i < (int)G_sn; i++) if (!(usado & (1U << i))) I.libres++;
}

const mxpf_info_t *mxpf_estado(void) { return &I; }

const mxpf_info_t *mxpf_monta(void)
{
    mbr_t m;
    u32 secs = tf1_sectores(), i;
    int r, hallada = 0;
    u8 *s = sc(SC_MBR);
    mx_set((u8 *)&I, 0, sizeof I);
    if (secs == 0U) { I.estado = MXS_SIN_TARJETA; return &I; }
    I.mb = secs >> 11;
    rd_idx = MXT_LEE;
    if (!blk_rd(0, 1, s)) { I.estado = MXS_ERROR_TARJETA; return &I; }
    r = mbr_analiza(s, &m);
    I.estado = MXS_SIN_PARTICION;
    if (r) { I.motivo = (u8)r; return &I; }
    for (i = 0; i < 4U && !hallada; i++) {
        if (m.tipo[i] != 0xDA || m.n[i] == 0U) continue;
        if ((u64)m.lba[i] + m.n[i] > (u64)secs) continue;
        if (!blk_rd(m.lba[i], 1, sc(SC_SB))) { I.estado = MXS_ERROR_TARJETA; return &I; }
        if (!sb_ok(sc(SC_SB), m.n[i])) continue;           /* una 0xDA ajena: no se toca */
        G_part = m.lba[i];
        I.dedicada = (u8)(rd32(sc(SC_SB) + 28) & 1U);      /* +28 era un campo libre (0 en las betas) */
        hallada = 1;
    }
    if (hallada) {
        u32 s1, s2;
        int n1 = 0, n2 = 0, v1, v2;
        mxpf_perfil p1[MXPF_MAX_PERF], p2[MXPF_MAX_PERF];
        I.part_lba = G_part; I.part_secs = G_psecs;
        if (!blk_rd(G_part + 1, 2, sc(SC_DA))) { I.estado = MXS_ERROR_TARJETA; return &I; }     /* A y B seguidos: SC_DA y SC_DB */
        v1 = dir_lee(sc(SC_DA), &s1, p1, &n1);
        v2 = dir_lee(sc(SC_DB), &s2, p2, &n2);
        if (!v1 && !v2) { I.estado = MXS_DANADA; I.motivo = MXPF_E_DIR; return &I; }
        if (v1 && v2) G_cur = ((s32)(s2 - s1) > 0) ? 1U : 0U; else G_cur = v2 ? 1U : 0U;
        G_seq = G_cur ? s2 : s1;
        I.n = (u8)(G_cur ? n2 : n1);
        for (i = 0; i < I.n; i++) I.p[i] = G_cur ? p2[i] : p1[i];
        I.seq = G_seq; I.dir = (u8)G_cur;
        I.estado = MXS_OK;
        libres_calcula();
        return &I;
    }
    {
        int e;
        u32 ini, tam;
        r = mbr_plan(&m, secs, &e, &ini, &tam);
        I.motivo = (u8)r;
        if (!r) { I.prep_lba = ini; I.prep_secs = tam; }
    }
    return &I;
}

static int estado_a_error(void)
{
    switch (I.estado) {
        case MXS_OK: return MXPF_OK;
        case MXS_SIN_PARTICION: return MXPF_E_SINPART;
        case MXS_DANADA: return MXPF_E_DIR;
        default: return MXPF_E_TARJETA;
    }
}

/* ---- preparar la tarjeta -------------------------------------------------------------------------------------------- */
static int verifica_sec(u32 sec, const u8 *esperado)
{
    u8 *v = sc(SC_TMP);
    rd_idx = MXT_VER;
    return blk_rd(sec, 1, v) && mx_eq(v, esperado, SEC);
}

static int prepara_(void)
{
    mbr_t m;
    u32 secs = tf1_sectores(), ini, tam, a;
    int e, r;
    u8 *mbr = sc(SC_MBR), *sb = sc(SC_SB), *da = sc(SC_DA), *db = sc(SC_DB), *aux = sc(SC_AUX);
    const mxpf_info_t *in = mxpf_monta();
    if (in->estado == MXS_SIN_TARJETA || in->estado == MXS_ERROR_TARJETA) return MXPF_E_TARJETA;
    if (in->estado == MXS_DANADA) {                         /* superbloque bueno y directorios rotos: se rehacen, el MBR no se toca */
        mx_set(da, 0, SEC);
        dir_arma(da, 1U, 0, 0);
        mx_set(db, 0, SEC);
        if (!blk_wr(G_part + 2, 1, db) || !blk_wr(G_part + 1, 1, da)) return MXPF_E_IO;
        if (!verifica_sec(G_part + 1, da) || !verifica_sec(G_part + 2, db)) return MXPF_E_VERIFICA;
        log_str("mxpf: directorios rehechos\n");
        (void)mxpf_monta();
        return MXPF_OK;
    }
    if (in->estado == MXS_OK) return MXPF_E_YA;
    if (in->motivo) return in->motivo;
    if (!blk_rd(0, 1, mbr)) return MXPF_E_TARJETA;          /* in->motivo == 0: el sector 0 vale; se vuelve a leer y a planear */
    r = mbr_analiza(mbr, &m);
    if (!r) r = mbr_plan(&m, secs, &e, &ini, &tam);
    if (r) return r;
    /* 1. la particion entera, con el superbloque el ULTIMO */
    mx_set(sb, 0, SEC);
    mx_cp(sb, (const u8 *)"MXPF", 4);
    wr32(sb + 4, 1U); wr32(sb + 8, tam); wr32(sb + 12, MX_PRIMER); wr32(sb + 16, MX_HUECO);
    a = (tam - MX_PRIMER) / MX_HUECO; if (a > MXPF_MAX_PERF) a = MXPF_MAX_PERF;
    wr32(sb + 20, a); wr32(sb + 24, MX_COPIA_MBR);
    mx_cp(sb + 32, (const u8 *)"MSXimus Z", 9);
    wr32(sb + 0x1FC, crc32(sb, 0x1FC));
    dir_arma(da, 1U, 0, 0);
    mx_set(db, 0, SEC);
    if (!blk_wr(ini + MX_COPIA_MBR, 1, mbr) || !blk_wr(ini + 2, 1, db) || !blk_wr(ini + 1, 1, da) || !blk_wr(ini, 1, sb)) return MXPF_E_IO;
    if (!verifica_sec(ini + MX_COPIA_MBR, mbr) || !verifica_sec(ini + 2, db) || !verifica_sec(ini + 1, da) || !verifica_sec(ini, sb)) return MXPF_E_VERIFICA;
    /* 2. recien ahora el MBR: una sola entrada de 16 bytes, el resto del sector tal cual */
    mx_cp(aux, mbr, SEC);
    {
        u8 *x = aux + 0x1BE + 16U * (u32)e;
        x[0] = 0x00; x[1] = 0xFE; x[2] = 0xFF; x[3] = 0xFF; x[4] = 0xDA; x[5] = 0xFE; x[6] = 0xFF; x[7] = 0xFF;
        wr32(x + 8, ini); wr32(x + 12, tam);
    }
    if (!blk_wr(0, 1, aux)) return MXPF_E_IO;
    if (!verifica_sec(0, aux)) return MXPF_E_VERIFICA;
    log_str("mxpf: tarjeta preparada, entrada "); log_dec((u32)e + 1U); log_str(", sector "); log_dec(ini);
    log_str(", "); log_dec(tam >> 11); log_str(" MB\n");
    (void)mxpf_monta();
    return MXPF_OK;
}
int mxpf_prepara(void) { op_ini(); return op_fin(prepara_()); }

static int vacia_(u32 mb)
{
    u8 *aux = sc(SC_AUX);
    u32 secs = tf1_sectores();
    if (secs == 0U) return MXPF_E_TARJETA;
    if (mb != (secs >> 11)) return MXPF_E_PARAM;
    mx_set(aux, 0, SEC);
    aux[510] = 0x55; aux[511] = 0xAA;
    if (!blk_wr(0, 1, aux)) return MXPF_E_IO;
    if (!verifica_sec(0, aux)) return MXPF_E_VERIFICA;
    log_str("mxpf: PRUEBA: MBR a cero (tarjeta sin particiones)\n");
    (void)mxpf_monta();
    return MXPF_OK;
}
int mxpf_vacia(u32 mb) { op_ini(); return op_fin(vacia_(mb)); }

/* ============================================================================================================================
 * TF1 SOLO PARA PERFILES (8/11/2026). La microSD de TF1 deja de ser un disco de Nextor (la unidad B:); es la tarjeta de perfiles.
 * DISPOSICION "dedicada" (todo escrito por mxpf_prepara_dedicada; tools/mxpf.py imagen crear --dedicada la imita byte a byte):
 *   MBR: P1 tipo 0x0C (FAT32 LBA) en el sector 2048, 262144 sectores (128 MiB); P2 tipo 0xDA en el sector 264192, 1048576 sectores
 *        (512 MiB). Entradas 3 y 4 vacias. El resto de la tarjeta, sin usar.
 *   P1: FAT32 de 512 B por cluster, etiqueta MSXIMUS-Z, un LEEME.TXT. Ahi puede ir BOOT.bin (arranque desde SD) y Windows no ofrece formatear.
 *   P2: MXPF v1 (la de siempre) con el superbloque +28 = 1 («dedicada»). Las betas la ignoran: ese campo estaba a 0 y libre.
 * CLASES (mxpf_clasifica; solo LEE) y que se hace con cada una:
 *   SIN_TARJETA / ERROR        nada.
 *   NUESTRA                    dedicada y entera: nada que preparar.
 *   NUESTRA_ANTIGUA           0xDA compartida con FAT (las betas): sigue funcionando tal cual; «Convertir» = preparar (borra la tarjeta; los
 *                              perfiles instalados se pierden, se bajan otra vez) con la MISMA confirmacion que una ajena.
 *   DANADA                     superbloque bueno y los dos directorios rotos: se rehacen sin preguntar (no se borra nada).
 *   INTERRUMPIDA               superbloque dedicado en la posicion fija de P2 pero el MBR no es el nuestro (se fue la luz preparando):
 *                              «Terminar de preparar», con la primera tecla (la tarjeta ya se decidio borrar).
 *   VACIA                      el primer MiB entero a 0 (o FF): se prepara sin preguntar.
 *   AJENA                      cualquier otra cosa: confirmacion fuerte (primera tecla + segunda) y se borra ENTERA.
 *   DEFECTUOSA                 no sirve: mas pequena que 641 MiB (MXPF_E_SITIO) o fallo la prueba de tarjeta falsa (MXPF_E_FALSA).
 * SALVAGUARDAS (mxpf_prepara_dedicada; cada una tiene su prueba en tests/mxpf_host):
 *   1. Si la placa arranco desde SD (BOOT_MODE 5) la TF1 es la tarjeta de arranque: NUNCA se prepara, ni confirmada.
 *   2. AJENA y NUESTRA_ANTIGUA solo con las dos teclas: mxpf_ded_arma (primera) y mxpf_prepara_dedicada(1) (segunda) en menos de 12 s,
 *      con la misma tarjeta (tamano y CRC del sector 0). INTERRUMPIDA, con la primera. Cualquier otra orden cancela.
 *   3. Prueba de tarjeta falsa ANTES de tocar nada util: sectores con patrones distintos en P2+0, P2+256 MiB, el ultimo de P2, el ultimo
 *      de la tarjeta y las potencias de 2 desde 2^20; se escriben todos y luego se leen: una tarjeta que repite direcciones o tira
 *      lo que cae mas alla de su capacidad real no los conserva (pos_prueba). No sustituye a H2testw.
 *   4. Orden de escritura contra apagones: P2 entera (copia del sector 0 original, directorios, superbloque el ULTIMO), P1, los primeros
 *      sectores de las particiones viejas que no han quedado tapadas (y las cabeceras GPT), y el MBR AL FINAL. Cada sector se relee.
 *      Hasta el MBR la tarjeta sigue siendo la de antes (clase AJENA) o INTERRUMPIDA (superbloque ya escrito): nunca un estado raro.
 */
#define DED_P1_LBA      2048U
#define DED_P1_SECS     262144U
#define DED_P2_LBA      (DED_P1_LBA + DED_P1_SECS)
#define DED_P2_SECS     1048576U
#define DED_FIN         (DED_P2_LBA + DED_P2_SECS)         /* sectores que necesita la tarjeta: 641 MiB */
#define DED_FLAG        1U                                 /* superbloque +28 bit 0 */
#define F32_RSVD        32U
#define F32_FATSZ       2017U                              /* ceil((262144 - 30) / 130): FAT32 de 1 sector por cluster */
#define F32_DATA        (F32_RSVD + 2U * F32_FATSZ)        /* primer sector de datos = cluster 2 = directorio raiz */
#define F32_META        (F32_DATA + 3U)                    /* sectores de P1 que se escriben: reservados, FAT1, FAT2, raiz, LEEME (2 clusters) */
#define P1_CH           56U                                /* sectores por trozo al escribir P1 (28 KB, y otros 28 KB para releer) */
#define K_CADUCA        12U                                /* segundos que dura una confirmacion armada (la pagina cancela a los 10) */

static const char leeme_txt[] =
    "MSXimus Z - tarjeta TF1 de PERFILES / PROFILES card\r\n\r\n"
    "Esta tarjeta la usa el MSXimus Z para guardar los perfiles del sistema. No la uses en el MSX\r\n"
    "ni guardes aqui tus ficheros: la segunda particion (tipo DA) es de los perfiles y Windows no la muestra.\r\n"
    "Puedes copiar aqui BOOT.bin para arrancar desde SD (SW1 en SD); arrancando desde esta tarjeta no se puede preparar ni borrar.\r\n\r\n"
    "This card holds the MSXimus Z system profiles. Do not use it in the MSX or store files here: the second\r\n"
    "partition (type DA) belongs to the profiles. BOOT.bin may be copied here to boot from SD (SW1 on SD).\r\n";

static mxpf_clase_t K;
static u32 g_falsa_secs, g_falsa_crc;                      /* tamano y CRC del sector 0 de la tarjeta que fallo la prueba de tarjeta falsa (0 = ninguna) */
static struct { u8 on; u8 clase; u32 secs, crc; u64 t; } arma;

const mxpf_clase_t *mxpf_clase(void) { return &K; }

static u32 rd16(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8); }

/* formato, entradas y datos de MSX-DOS de lo que haya en el sector 0 */
static void formato_analiza(const u8 *s)
{
    u32 i;
    K.formato = MXF_DESCONOCIDO; K.nparts = 0; K.msxdos = 0;
    if (es_vbr(s)) {
        K.nparts = 1U;
        if (mx_eq(s + 3, (const u8 *)"EXFAT   ", 8)) K.formato = MXF_EXFAT;
        else if (mx_eq(s + 3, (const u8 *)"NTFS    ", 8)) K.formato = MXF_NTFS;
        else if (rd16(s + 22) == 0U) K.formato = MXF_FAT32;
        else if (mx_eq(s + 54, (const u8 *)"FAT12", 5)) K.formato = MXF_FAT12;
        else { K.formato = MXF_FAT16; K.msxdos = 1U; }
        return;
    }
    if (s[510] != 0x55 || s[511] != 0xAA) { K.formato = MXF_SIN_TABLA; return; }
    for (i = 0; i < 4U; i++) {
        const u8 *e = s + 0x1BE + 16U * i;
        u8 t = e[4];
        if (t == 0U || rd32(e + 12) == 0U) continue;
        K.nparts++;
        if (t == 0x04 || t == 0x06 || t == 0x0E || t == 0x16) K.msxdos = 1U;
        if (K.formato == MXF_DESCONOCIDO || K.formato == MXF_OTRO) {   /* la primera particion con tipo conocido manda; GPT manda sobre todo */
            K.formato = t == 0x01 ? MXF_FAT12 : (t == 0x04 || t == 0x06 || t == 0x0E || t == 0x16) ? MXF_FAT16
                      : (t == 0x0B || t == 0x0C) ? MXF_FAT32 : t == 0x07 ? MXF_EXFAT : MXF_OTRO;
        }
        if (t == 0xEE) K.formato = MXF_GPT;
    }
    if (K.nparts == 0U) K.formato = MXF_SIN_TABLA;
}

static int ded_mbr_ok(const u8 *s)                         /* el MBR que escribe la preparacion dedicada */
{
    const u8 *a = s + 0x1BE, *b = a + 16, *c = a + 32, *d = a + 48;
    u32 i;
    if (s[510] != 0x55 || s[511] != 0xAA) return 0;
    if (a[4] != 0x0C || rd32(a + 8) != DED_P1_LBA || rd32(a + 12) != DED_P1_SECS) return 0;
    if (b[4] != 0xDA || rd32(b + 8) != DED_P2_LBA || rd32(b + 12) != DED_P2_SECS) return 0;
    for (i = 0; i < 16U; i++) if (c[i] || d[i]) return 0;
    return 1;
}
static int ded_sb_ok(const u8 *s) { return sb_valida(s, DED_P2_SECS) && (rd32(s + 28) & DED_FLAG); }

/* el primer MiB entero a 0 (el sector 0 puede llevar ademas 55 AA) o entero a FF */
static int primer_mib_vacio(void)
{
    u32 n, i, cero = 1, ff = 1;
    for (n = 0; n < MX_ALIN && (cero || ff); n += IO_SECS) {
        u8 *b = sc(SC_IO);
        u32 c = MX_ALIN - n < IO_SECS ? MX_ALIN - n : IO_SECS;
        if (!blk_rd(n, c, b)) return 0;
        sd_ceder();
        for (i = 0; i < c * SEC; i++) {
            u8 v = b[i];
            if (n == 0U && i == 510U) { if (v != 0x55 && v != 0U) cero = 0; if (v != 0xFF) ff = 0; continue; }
            if (n == 0U && i == 511U) { if (v != 0xAA && v != 0U) cero = 0; if (v != 0xFF) ff = 0; continue; }
            if (v != 0U) cero = 0;
            if (v != 0xFF) ff = 0;
            if (!cero && !ff) break;
        }
    }
    return cero || ff;
}

const mxpf_clase_t *mxpf_clasifica(void)
{
    u32 secs = tf1_sectores();
    u8 *s = sc(SC_MBR);
    int fijo = 0, mbr_ded;
    const mxpf_info_t *in;
    mx_set((u8 *)&K, 0, sizeof K);
    rd_idx = MXT_LEE;
    if (secs == 0U) { K.clase = MXC_SIN_TARJETA; g_falsa_secs = 0U; return &K; }
    K.mb = secs >> 11;
    if (!blk_rd(0, 1, s)) { K.clase = MXC_ERROR; return &K; }
    formato_analiza(s);
    if (secs >= DED_FIN && blk_rd(DED_P2_LBA, 1, sc(SC_SB))) fijo = ded_sb_ok(sc(SC_SB));
    mbr_ded = ded_mbr_ok(s);
    if (fijo && !mbr_ded) { K.clase = MXC_INTERRUMPIDA; return &K; }
    in = mxpf_monta();
    if (in->estado == MXS_ERROR_TARJETA) { K.clase = MXC_ERROR; return &K; }
    if (mbr_ded && in->part_lba == DED_P2_LBA && in->dedicada && (in->estado == MXS_OK || in->estado == MXS_DANADA)) {
        u8 *b = sc(SC_TMP);
        if (blk_rd(DED_P1_LBA, 1, b) && b[510] == 0x55 && b[511] == 0xAA && mx_eq(b + 82, (const u8 *)"FAT32   ", 8)) {
            K.clase = in->estado == MXS_OK ? MXC_NUESTRA : MXC_DANADA;
            return &K;
        }
    } else if (!mbr_ded && !in->dedicada && in->estado == MXS_OK) { K.clase = MXC_NUESTRA_ANTIGUA; return &K; }
    else if (!mbr_ded && !in->dedicada && in->estado == MXS_DANADA) { K.clase = MXC_DANADA; return &K; }
    /* cualquier otra cosa (incluida una dedicada a medias o con el MBR cambiado): vacia o ajena */
    K.clase = primer_mib_vacio() ? MXC_VACIA : MXC_AJENA;
    if (secs < DED_FIN) { K.clase = MXC_DEFECTUOSA; K.motivo = MXPF_E_SITIO; }
    else if (g_falsa_secs == secs && g_falsa_crc == crc32(s, SEC)) { K.clase = MXC_DEFECTUOSA; K.motivo = MXPF_E_FALSA; }
    return &K;
}

/* ---- P1: la FAT32 pequena ------------------------------------------------------------------------------------------------- */
static void wr16(u8 *p, u32 v) { p[0] = (u8)v; p[1] = (u8)(v >> 8); }
static u32 volid_de(u32 secs) { return 0x4D5A0000U ^ secs; }

/* sector n de P1 (n < F32_META); los que no se nombran son ceros */
static void p1_sector(u32 n, u8 *s, u32 volid)
{
    mx_set(s, 0, SEC);
    if (n == 0U || n == 6U) {
        s[0] = 0xEB; s[1] = 0x58; s[2] = 0x90;
        mx_cp(s + 3, (const u8 *)"MSXIMUSZ", 8);
        wr16(s + 11, SEC); s[13] = 1U; wr16(s + 14, F32_RSVD); s[16] = 2U; s[21] = 0xF8U;
        wr16(s + 24, 63U); wr16(s + 26, 255U);
        wr32(s + 28, DED_P1_LBA); wr32(s + 32, DED_P1_SECS); wr32(s + 36, F32_FATSZ);
        wr32(s + 44, 2U); wr16(s + 48, 1U); wr16(s + 50, 6U);
        s[64] = 0x80U; s[66] = 0x29U; wr32(s + 67, volid);
        mx_cp(s + 71, (const u8 *)"MSXIMUS-Z  ", 11);
        mx_cp(s + 82, (const u8 *)"FAT32   ", 8);
        s[510] = 0x55; s[511] = 0xAA;
    } else if (n == 1U || n == 7U) {
        wr32(s, 0x41615252U); wr32(s + 484, 0x61417272U);
        wr32(s + 488, DED_P1_SECS - F32_DATA - 3U); wr32(s + 492, 5U);   /* clusters libres y siguiente libre (el 2 es la raiz, el 3 y 4 el LEEME) */
        wr32(s + 508, 0xAA550000U);
    } else if (n == 2U || n == 8U) {
        wr32(s + 508, 0xAA550000U);
    } else if (n == F32_RSVD || n == F32_RSVD + F32_FATSZ) {
        wr32(s, 0x0FFFFFF8U); wr32(s + 4, 0x0FFFFFFFU); wr32(s + 8, 0x0FFFFFFFU);
        wr32(s + 12, 4U); wr32(s + 16, 0x0FFFFFFFU);
    } else if (n == F32_DATA) {
        mx_cp(s, (const u8 *)"MSXIMUS-Z  ", 11); s[11] = 0x08U;
        mx_cp(s + 32, (const u8 *)"LEEME   TXT", 11); s[32 + 11] = 0x20U;
        wr16(s + 32 + 16, ((2026U - 1980U) << 9) | (11U << 5) | 8U); wr16(s + 32 + 24, ((2026U - 1980U) << 9) | (11U << 5) | 8U);
        wr16(s + 32 + 26, 3U); wr32(s + 32 + 28, (u32)sizeof leeme_txt - 1U);
    } else if (n == F32_DATA + 1U || n == F32_DATA + 2U) {
        u32 off = (n - F32_DATA - 1U) * SEC, len = (u32)sizeof leeme_txt - 1U, i;
        for (i = 0; i < SEC && off + i < len; i++) s[i] = (u8)leeme_txt[off + i];
    }
}

static int p1_escribe(u32 secs)
{
    u32 n, volid = volid_de(secs);
    u8 *w = sc(SC_IO), *v = sc(SC_IO) + P1_CH * SEC;
    for (n = 0; n < F32_META; n += P1_CH) {
        u32 c = F32_META - n < P1_CH ? F32_META - n : P1_CH, i;
        for (i = 0; i < c; i++) p1_sector(n + i, w + i * SEC, volid);
        if (!blk_wr(DED_P1_LBA + n, c, w)) return MXPF_E_IO;
        sd_ceder();
        rd_idx = MXT_VER;
        if (!blk_rd(DED_P1_LBA + n, c, v)) return MXPF_E_VERIFICA;
        if (!mx_eq(w, v, c * SEC)) return MXPF_E_VERIFICA;
        sd_ceder();
    }
    return MXPF_OK;
}

/* ---- prueba de tarjeta falsa ---------------------------------------------------------------------------------------------- */
static void patron(u32 lba, u8 *b)
{
    u32 x = lba * 2654435761U + 0x9E3779B9U, i;
    for (i = 0; i < SEC / 4U; i++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; wr32(b + 4U * i, x); }
}
/* Sectores de la prueba: P2+0, P2+256 MiB, el ultimo de P2, el ultimo de la tarjeta y los sectores 2^20 .. 2^31. Una tarjeta falsa
 * (capacidad declarada mayor que la real) o repite direcciones (entonces dos potencias de 2 por encima de su capacidad real caen en
 * el mismo sitio y se pisan) o tira lo que se escribe mas alla (y la relectura falla). No es H2testw: no prueba toda la tarjeta. */
static u32 pos_prueba(u32 secs, u32 *p)
{
    u32 n = 0, k, i, v;
    p[n++] = DED_P2_LBA; p[n++] = DED_P2_LBA + 524288U; p[n++] = DED_P2_LBA + DED_P2_SECS - 1U;
    for (k = 20U; k <= 32U; k++) {
        v = k == 32U ? secs - 1U : (1U << k);
        if (k < 32U && v >= secs) continue;
        for (i = 0; i < n && p[i] != v; i++) { }
        if (i == n) p[n++] = v;
    }
    return n;
}
static int prueba_falsa(u32 secs)
{
    u32 pos[16], n = pos_prueba(secs, pos), i;
    u8 *w = sc(SC_IO), *v = sc(SC_IO) + SEC;
    int ok = 1;
    for (i = 0; i < n && ok; i++) {
        patron(pos[i], w);
        if (!blk_wr(pos[i], 1, w)) ok = 0;
    }
    for (i = 0; i < n && ok; i++) {
        patron(pos[i], w);
        rd_idx = MXT_VER;
        if (!blk_rd(pos[i], 1, v) || !mx_eq(w, v, SEC)) ok = 0;
    }
    mx_set(w, 0, SEC);                                      /* no dejar los patrones por la tarjeta */
    for (i = 1; i < n; i++) (void)blk_wr(pos[i], 1, w);     /* (el primero, P2+0, lo pisa el superbloque) */
    return ok;
}

/* ---- confirmacion en dos pasos ----------------------------------------------------------------------------------------------- */
static u32 crc_sector0(void)
{
    u8 *s = sc(SC_AUX);
    return blk_rd(0, 1, s) ? crc32(s, SEC) : 0U;
}
void mxpf_ded_desarma(void) { arma.on = 0U; }
int mxpf_arranque_sd(void) { return MX_BOOT_MODO() == 5U; }
int mxpf_ded_arma(void)
{
    const mxpf_clase_t *c;
    arma.on = 0U;
    if (MX_BOOT_MODO() == 5U) return 0;                    /* arranco desde SD: ni se arma */
    c = mxpf_clasifica();
    if (c->clase != MXC_AJENA && c->clase != MXC_NUESTRA_ANTIGUA && c->clase != MXC_INTERRUMPIDA) return 0;
    arma.clase = c->clase; arma.secs = tf1_sectores(); arma.crc = crc_sector0(); arma.t = gt_now(); arma.on = 1U;
    return 1;
}
int mxpf_ded_armada(void)
{
    return arma.on && (gt_now() - arma.t) <= (u64)K_CADUCA * (u64)COUNTS_PER_SECOND;
}

/* ---- preparar ------------------------------------------------------------------------------------------------------------- */
static int prepara_ded_(int segunda)
{
    u32 secs, i, oldt[4], oldl[4], oldn[4];
    int clase, r;
    u8 *mbr = sc(SC_MBR), *sb = sc(SC_SB), *da = sc(SC_DA), *db = sc(SC_DB), *aux = sc(SC_AUX);
    const mxpf_clase_t *c;
    if (MX_BOOT_MODO() == 5U) { arma.on = 0U; log_str("mxpf: arranque desde SD: la TF1 no se prepara\n"); return MXPF_E_ARRANQUE_SD; }
    c = mxpf_clasifica();
    clase = c->clase;
    switch (clase) {
        case MXC_SIN_TARJETA: case MXC_ERROR: return MXPF_E_TARJETA;
        case MXC_NUESTRA: return MXPF_E_YA;
        case MXC_DEFECTUOSA: return c->motivo ? c->motivo : MXPF_E_FALSA;
        case MXC_DANADA: return prepara_();                /* directorios rotos: se rehacen, no se borra nada */
        case MXC_VACIA: break;
        case MXC_INTERRUMPIDA: case MXC_AJENA: case MXC_NUESTRA_ANTIGUA: {
            int ok = arma.on && arma.clase == clase && arma.secs == tf1_sectores() && arma.crc == crc_sector0() && mxpf_ded_armada();
            if (ok && clase != MXC_INTERRUMPIDA) ok = segunda;      /* ajena o antigua: las dos teclas */
            arma.on = 0U;                                   /* se gasta, salga lo que salga */
            if (!ok) return MXPF_E_CONFIRMA;
            break;
        }
        default: return MXPF_E_PARAM;
    }
    secs = tf1_sectores();
    if (secs < DED_FIN) return MXPF_E_SITIO;
    /* el sector 0 de ahora (el original, o el MBR viejo si se interrumpio) y las particiones viejas que habra que tapar */
    if (!blk_rd(0, 1, mbr)) return MXPF_E_TARJETA;
    for (i = 0; i < 4U; i++) {
        const u8 *e = mbr + 0x1BE + 16U * i;
        int tabla = mbr[510] == 0x55 && mbr[511] == 0xAA && !es_vbr(mbr);
        oldt[i] = tabla ? e[4] : 0U; oldl[i] = tabla ? rd32(e + 8) : 0U; oldn[i] = tabla ? rd32(e + 12) : 0U;
    }
    if (clase != MXC_INTERRUMPIDA) {
        /* 1. prueba de tarjeta falsa y la P2 entera, con el superbloque el ULTIMO */
        if (!prueba_falsa(secs)) {
            g_falsa_secs = secs; g_falsa_crc = crc32(mbr, SEC);
            (void)blk_wr(0, 1, mbr);                        /* una tarjeta que repite direcciones puede haber pisado el sector 0 con un patron: se deja como estaba */
            log_str("mxpf: la tarjeta no guarda lo que se le escribe (falsa?)\n");
            return MXPF_E_FALSA;
        }
        mx_set(sb, 0, SEC);
        mx_cp(sb, (const u8 *)"MXPF", 4);
        wr32(sb + 4, 1U); wr32(sb + 8, DED_P2_SECS); wr32(sb + 12, MX_PRIMER); wr32(sb + 16, MX_HUECO);
        wr32(sb + 20, MXPF_MAX_PERF); wr32(sb + 24, MX_COPIA_MBR); wr32(sb + 28, DED_FLAG);
        mx_cp(sb + 32, (const u8 *)"MSXimus Z", 9);
        wr32(sb + 0x1FC, crc32(sb, 0x1FC));
        dir_arma(da, 1U, 0, 0);
        mx_set(db, 0, SEC);
        if (!blk_wr(DED_P2_LBA + MX_COPIA_MBR, 1, mbr) || !blk_wr(DED_P2_LBA + 2, 1, db) || !blk_wr(DED_P2_LBA + 1, 1, da)
            || !blk_wr(DED_P2_LBA, 1, sb)) return MXPF_E_IO;
        if (!verifica_sec(DED_P2_LBA + MX_COPIA_MBR, mbr) || !verifica_sec(DED_P2_LBA + 2, db) || !verifica_sec(DED_P2_LBA + 1, da)
            || !verifica_sec(DED_P2_LBA, sb)) return MXPF_E_VERIFICA;
    }
    /* 2. P1 */
    if ((r = p1_escribe(secs)) != MXPF_OK) return r;
    /* 3. el primer sector de las particiones viejas que no han quedado tapadas, y las cabeceras GPT */
    mx_set(aux, 0, SEC);
    for (i = 0; i < 4U; i++) {
        u32 l = oldl[i];
        if (oldt[i] == 0U || oldn[i] == 0U) continue;
        if (oldt[i] == 0xEE) {                              /* GPT: cabecera primaria (LBA 1) y copia del final */
            if (!blk_wr(1, 1, aux) || !blk_wr(secs - 1U, 1, aux)) return MXPF_E_IO;
            if (!verifica_sec(1, aux) || !verifica_sec(secs - 1U, aux)) return MXPF_E_VERIFICA;
            continue;
        }
        if (l == 0U || l >= secs) continue;
        if (l >= DED_P1_LBA && l < DED_P1_LBA + F32_META) continue;
        if (l >= DED_P2_LBA && l < DED_P2_LBA + 4U) continue;
        if (!blk_wr(l, 1, aux)) return MXPF_E_IO;
        if (!verifica_sec(l, aux)) return MXPF_E_VERIFICA;
    }
    /* 4. el MBR, AL FINAL */
    mx_set(aux, 0, SEC);
    wr32(aux + 0x1B8, volid_de(secs) ^ 0x5A5AA5A5U);
    {
        u8 *x = aux + 0x1BE;
        x[1] = 0xFE; x[2] = 0xFF; x[3] = 0xFF; x[4] = 0x0C; x[5] = 0xFE; x[6] = 0xFF; x[7] = 0xFF; wr32(x + 8, DED_P1_LBA); wr32(x + 12, DED_P1_SECS);
        x += 16;
        x[1] = 0xFE; x[2] = 0xFF; x[3] = 0xFF; x[4] = 0xDA; x[5] = 0xFE; x[6] = 0xFF; x[7] = 0xFF; wr32(x + 8, DED_P2_LBA); wr32(x + 12, DED_P2_SECS);
    }
    aux[510] = 0x55; aux[511] = 0xAA;
    if (!blk_wr(0, 1, aux)) return MXPF_E_IO;
    if (!verifica_sec(0, aux)) return MXPF_E_VERIFICA;
    (void)mxpf_monta();
    if (mxpf_clasifica()->clase != MXC_NUESTRA) return MXPF_E_VERIFICA;
    g_falsa_secs = 0U;
    log_str("mxpf: tarjeta dedicada preparada: P1 FAT32 "); log_dec(DED_P1_SECS >> 11); log_str(" MB, P2 MXPF "); log_dec(DED_P2_SECS >> 11); log_str(" MB\n");
    return MXPF_OK;
}
int mxpf_prepara_dedicada(int segunda) { op_ini(); return op_fin(prepara_ded_(segunda)); }

/* ---- contenido de un perfil: comprobaciones comunes ------------------------------------------------------------------ */
static int sincronismo(const u8 *b, u32 n)                  /* 66 55 99 AA en los primeros 512 B: el .bin de bootgen */
{
    u32 i, m = n < 512U ? n : 512U;
    for (i = 0; i + 3U < m; i++) if (b[i] == 0x66 && b[i + 1] == 0x55 && b[i + 2] == 0x99 && b[i + 3] == 0xAA) return 1;
    return 0;
}

/* el contenido guardado (en CA_A) -> el .bin (en CA_B): SHA-256 ya comprobado por quien llama */
static int desempaqueta(const mxpf_perfil *p)
{
    u64 t = gt_now();
    if (p->metodo == 1U) {
        z_job j;
        u32 n;
        int r;
        j.src = ca(CA_A); j.srclen = p->tam; j.dst = ca(CA_B); j.dstcap = PF_MAX; j.n = 0; j.r = 0;
        (void)en_pila(z_trabajo, &j);
        r = j.r; n = j.n;
        mxpf_t[MXT_ZLIB] += us_de(t);
        sd_ceder();
        if (r != 0) { log_str("mxpf: zlib error "); log_dec((u32)(0 - r)); log_str("\n"); return MXPF_E_ZLIB; }
        if (n != p->tam_bin) return MXPF_E_ZLIB;
    } else {
        ca2ca(ca(CA_B), ca(CA_A), p->tam);
        mxpf_t[MXT_COPIA] += us_de(t);
    }
    if (!sincronismo(ca(CA_B), p->tam_bin)) return MXPF_E_FORMATO;
    return MXPF_OK;
}

/* ---- instalar -------------------------------------------------------------------------------------------------------- */
static int mxp_cabecera(const u8 *mxp, u32 len, mxpf_perfil *p)
{
    u8 *h = sc(SC_TMP);                                     /* los 512 B de la cabecera, leidos por palabras de la zona sin cache */
    u32 i;
    const volatile u32 *s = (const volatile u32 *)(const void *)mxp;
    u32 *d = (u32 *)(void *)h;
    if (len < SEC) return MXPF_E_FORMATO;
    for (i = 0; i < SEC / 4U; i++) d[i] = s[i];
    if (!mx_eq(h, (const u8 *)"MXP1", 4) || rd32(h + 4) != 1U || rd32(h + 8) != SEC || rd32(h + 12) != crc32(h + 16, ENT)) return MXPF_E_FORMATO;
    if (!ent_lee(h + 16, p)) return MXPF_E_FORMATO;
    if (len < SEC + p->tam) return MXPF_E_FORMATO;
    return MXPF_OK;
}

static int instala_(const u8 *mxp, u32 len)
{
    mxpf_perfil nuevo, lista[MXPF_MAX_PERF];
    u8 h[32];
    u32 nsec, usado = 0, slot, i, resto, sec;
    int n = 0, r;
    u64 t;
    if (ota_ocupada()) return MXPF_E_OCUPADO;
    (void)mxpf_monta();
    if ((r = estado_a_error()) != MXPF_OK) return r;
    if ((r = mxp_cabecera(mxp, len, &nuevo)) != MXPF_OK) return r;
    if (nuevo.tam > G_ss * SEC) return MXPF_E_FORMATO;
    /* el contenido, a memoria con cache: SHA-256 y prueba de descompresion antes de escribir nada */
    t = gt_now(); so2ca(ca(CA_A), mxp + SEC, nuevo.tam); mxpf_t[MXT_COPIA] += us_de(t);
    sd_ceder();
    t = gt_now(); sha_todo(ca(CA_A), nuevo.tam, h); mxpf_t[MXT_SHA] += us_de(t);
    if (!mx_eq(h, nuevo.sha, 32)) return MXPF_E_SHA;
    if ((r = desempaqueta(&nuevo)) != MXPF_OK) return r;
    /* hueco libre: ninguno de los que cuenta el directorio vigente (el perfil del mismo id sigue en el suyo hasta el commit) */
    for (i = 0; i < I.n; i++) usado |= 1U << I.p[i].hueco;
    for (slot = 0; slot < G_sn && (usado & (1U << slot)); slot++) { }
    if (slot >= G_sn) return MXPF_E_LLENO;
    nuevo.hueco = (u8)slot; nuevo.lba = G_sf + slot * G_ss;
    nsec = (nuevo.tam + SEC - 1U) / SEC;
    resto = nsec * SEC - nuevo.tam;                         /* el ultimo sector, relleno de ceros (el .mxp puede venir sin rellenar) */
    for (i = 0; i < resto; i++) ((volatile u8 *)(mxp + SEC + nuevo.tam))[i] = 0U;
    if (!wr_largo(G_part + nuevo.lba, nsec, mxp + SEC)) return MXPF_E_IO;
    /* relectura y SHA-256 del hueco */
    rd_idx = MXT_VER;
    sha_ini();
    for (sec = 0, i = nuevo.tam; sec < nsec; sec += IO_SECS) {
        u32 k = nsec - sec < IO_SECS ? nsec - sec : IO_SECS, b = k * SEC < i ? k * SEC : i;
        if (!blk_rd(G_part + nuevo.lba + sec, k, sc(SC_IO))) return MXPF_E_IO;
        t = gt_now(); so2ca(ca(CA_BNC), sc(SC_IO), b); mxpf_t[MXT_COPIA] += us_de(t);
        t = gt_now(); sha_upd(ca(CA_BNC), b); mxpf_t[MXT_SHA] += us_de(t);
        i -= b;
        sd_ceder();
    }
    sha_fin(h);
    if (!mx_eq(h, nuevo.sha, 32)) return MXPF_E_VERIFICA;
    /* el directorio nuevo: el vigente sin el del mismo id, mas este */
    for (i = 0; i < I.n; i++) if (!mx_eq((const u8 *)I.p[i].id, (const u8 *)nuevo.id, 9)) lista[n++] = I.p[i];
    lista[n++] = nuevo;
    {
        u32 destino = G_cur ^ 1U, seq = G_seq + 1U;
        u8 *s = sc(SC_AUX);
        dir_arma(s, seq, lista, n);
        if (!blk_wr(G_part + 1U + destino, 1, s)) return MXPF_E_IO;
        if (!verifica_sec(G_part + 1U + destino, s)) return MXPF_E_VERIFICA;
    }
    log_str("mxpf: instalado "); log_str(nuevo.id); log_str(" "); log_str(nuevo.version); log_str(" en el hueco "); log_dec(slot); log_str("\n");
    (void)mxpf_monta();
    return MXPF_OK;
}
int mxpf_instala(const u8 *mxp, u32 len) { op_ini(); return op_fin(instala_(mxp, len)); }

/* ---- cargar y borrar ------------------------------------------------------------------------------------------------- */
static const mxpf_perfil *busca(const char *id)
{
    int i;
    for (i = 0; i < I.n; i++) {
        u32 k = 0;
        while (k < 9U && I.p[i].id[k] == id[k] && id[k]) k++;
        if (I.p[i].id[k] == id[k]) return &I.p[i];
    }
    return 0;
}

static int carga_(const char *id)
{
    const mxpf_perfil *q;
    mxpf_perfil p;
    u8 h[32];
    u32 s, nsec;
    int r;
    u64 t;
    if (ota_ocupada()) return MXPF_E_OCUPADO;
    (void)mxpf_monta();
    if ((r = estado_a_error()) != MXPF_OK) return r;
    if (!(q = busca(id))) return MXPF_E_NOEXISTE;
    p = *q;
    s = ota_serie();
    if (s != 0U && p.serie != s) return MXPF_E_SERIE;
    nsec = (p.tam + SEC - 1U) / SEC;
    rd_idx = MXT_LEE;
    if (!rd_largo(G_part + p.lba, nsec, MX_SO + Z_DATOS)) return MXPF_E_IO;
    t = gt_now(); so2ca(ca(CA_A), MX_SO + Z_DATOS, p.tam); mxpf_t[MXT_COPIA] += us_de(t);
    sd_ceder();
    t = gt_now(); sha_todo(ca(CA_A), p.tam, h); mxpf_t[MXT_SHA] += us_de(t);
    if (!mx_eq(h, p.sha, 32)) return MXPF_E_SHA;
    if ((r = desempaqueta(&p)) != MXPF_OK) return r;
    log_str("mxpf: "); log_str(p.id); log_str(" listo: leer "); log_dec(mxpf_t[MXT_LEE] / 1000U); log_str(" ms, sha ");
    log_dec(mxpf_t[MXT_SHA] / 1000U); log_str(" ms, zlib "); log_dec(mxpf_t[MXT_ZLIB] / 1000U); log_str(" ms, ahora PCAP\n");
    t = gt_now();
    {
        u32 bin;
        if (tr_ex_prepara(ca(CA_B), p.tam_bin, &bin)) return MXPF_E_FORMATO;
        r = perfil_cargar(ca(CA_B), bin);                 /* 0 = cargado y el MSX suelto; si falla despues de tocar el PL, no vuelve */
        tr_ex_olvida();
    }
    mxpf_t[MXT_PCAP] = us_de(t);
    if (r) return MXPF_E_PCAP;
    act_tipo = MXA_TARJETA; act_p = p;
    log_str("mxpf: ACTIVO "); log_str(p.id); log_str(" "); log_str(p.version); log_str(" serie "); log_dec(p.serie);
    log_str(" bin "); log_dec(p.tam_bin); log_str(" B sha "); log_hex(((u32)p.sha[0] << 24) | ((u32)p.sha[1] << 16) | ((u32)p.sha[2] << 8) | p.sha[3]);
    log_str("\n");                                          /* lo que distingue un perfil de otro tras la carga (el PL no expone su version al ARM) */
    return MXPF_OK;
}
int mxpf_carga(const char *id) { op_ini(); return op_fin(carga_(id)); }

static int borra_(const char *id)
{
    mxpf_perfil lista[MXPF_MAX_PERF];
    u32 destino, seq;
    u8 *s = sc(SC_AUX);
    const mxpf_perfil *q;
    int i, n = 0, r;
    (void)mxpf_monta();
    if ((r = estado_a_error()) != MXPF_OK) return r;
    if (!(q = busca(id))) return MXPF_E_NOEXISTE;
    for (i = 0; i < I.n; i++) if (&I.p[i] != q) lista[n++] = I.p[i];
    destino = G_cur ^ 1U; seq = G_seq + 1U;
    dir_arma(s, seq, lista, n);
    if (!blk_wr(G_part + 1U + destino, 1, s)) return MXPF_E_IO;
    if (!verifica_sec(G_part + 1U + destino, s)) return MXPF_E_VERIFICA;
    log_str("mxpf: borrado "); log_str(id); log_str("\n");
    (void)mxpf_monta();
    return MXPF_OK;
}
int mxpf_borra(const char *id) { op_ini(); return op_fin(borra_(id)); }

#define Z_SALTA         0x88U                              /* dos palabras: "el perfil al arrancar, esta vez no" (mxpf_perfil1 -> mxpf_arranque) */
#define SALTA_MAGIA     0x504B5341U                        /* 'ASKP' */
int mxpf_perfil1(void)
{
    volatile u32 *m = (volatile u32 *)(MX_SO + Z_SALTA);
    if (MX_BOOT_MODO() == 0U) return MXPF_E_JTAG;           /* SW1 en JTAG: no hay BootROM que cargue nada tras el reinicio */
    m[0] = SALTA_MAGIA; m[1] = ~SALTA_MAGIA;                /* sin esto, con un perfil al arrancar puesto la placa volveria a arrancar con el (la DDR sobrevive al reinicio del PS) */
    log_str("mxpf: perfil 1: reinicio del PS\n");
    ota_reinicia_ps();                                      /* el BootROM vuelve a cargar el BOOT.bin de la QSPI o de la SD */
    return MXPF_E_PARAM;                                    /* solo se llega aqui si no se ha podido */
}

/* ---- elegir el perfil (31/10/2026) ------------------------------------------------------------------------------------ */
static int id_igual(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }

/* id del perfil que corre: "" = el 1 (el BOOT.bin); el de la tarjeta si se cargo uno; "?" = uno cargado por la prueba de la DDR */
const char *mxpf_id_activo(void) { return act_tipo == MXA_TARJETA ? act_p.id : act_tipo == MXA_OTRO ? "?" : ""; }

/* una ROM (etiqueta [P:ID]) o el usuario piden este perfil: si ya corre, nada; si no, se carga de la tarjeta (el MSX se reinicia;
 * la DDR y la megaram se conservan). *cargado = 1 si ha cargado. Devuelve MXPF_OK o por que no (NOEXISTE, SERIE, TARJETA...). */
int mxpf_pide(const char *id, int *cargado)
{
    int r;
    *cargado = 0;
    if (act_tipo == MXA_TARJETA && id_igual(act_p.id, id)) return MXPF_OK;
    r = mxpf_carga(id);
    *cargado = (r == MXPF_OK);
    return r;
}

/* perfil al arrancar (ajuste de la QSPI, qspi_cfg.c): main.c lo llama con el MSX aun en reset. Una marca en la DDR (sobrevive al
 * reinicio del PS) vigila que no se entre en un bucle: si cargar el perfil dejo el PL roto, perfil_cargar reinicia el PS, y la
 * vez siguiente la marca sigue puesta: se arranca el perfil 1 y se borra. Con SW1 en JTAG no se hace (sin BootROM no se
 * recupera). 0 = nada que hacer o no se pudo (siguen el perfil 1); 1 = cargado. */
#define Z_ARR           0x80U
#define ARR_MAGIA       0x52524158U                        /* 'XARR' */
int mxpf_arranque(const char *id)
{
    volatile u32 *m = (volatile u32 *)(MX_SO + Z_ARR), *s = (volatile u32 *)(MX_SO + Z_SALTA);
    int r;
    if (s[0] == SALTA_MAGIA && s[1] == ~SALTA_MAGIA) {      /* "Perfil 1" desde la pagina: esta vez no se carga el de arranque (la vez siguiente, si) */
        s[0] = 0U; s[1] = 0U;
        log_str("mxpf: volvieron al perfil 1 a proposito: no se carga "); log_str(id && id[0] ? id : "ninguno"); log_str("\n");
        return 0;
    }
    if (!id || !id[0]) return 0;
    if (m[0] == ARR_MAGIA && m[1] == ~ARR_MAGIA) {
        m[0] = 0U; m[1] = 0U;
        log_str("mxpf: la carga de "); log_str(id); log_str(" al arrancar no termino: perfil 1\n");
        return 0;
    }
    if (MX_BOOT_MODO() == 0U) { log_str("mxpf: JTAG: no se carga el perfil de arranque "); log_str(id); log_str("\n"); return 0; }
    m[0] = ARR_MAGIA; m[1] = ~ARR_MAGIA;
    r = mxpf_carga(id);
    m[0] = 0U; m[1] = 0U;
    if (r != MXPF_OK) { log_str("mxpf: perfil de arranque "); log_str(id); log_str(": "); log_str(mxpf_err_es(r)); log_str(": perfil 1\n"); return 0; }
    return 1;
}

int mxpf_activo(void) { return act_tipo; }
const mxpf_perfil *mxpf_activo_perfil(void) { return act_tipo == MXA_TARJETA ? &act_p : 0; }
void mxpf_activo_otro(void) { act_tipo = MXA_OTRO; }

const char *mxpf_err_es(int e)
{
    static const char *const t[MXPF_E_N] = {
        "bien", "sin tarjeta o error de lectura", "la tarjeta no tiene una tabla de particiones MBR normal (GPT, sin tabla o dudosa)",
        "las 4 entradas del MBR estan ocupadas", "no hay 17 MB sin particionar al final de la tarjeta", "ya hay una particion MXPF",
        "la tarjeta no tiene particion MXPF", "los dos directorios de la particion estan rotos", "no queda ningun hueco libre (borra un perfil)",
        "fichero .mxp mal formado o bitstream sin sincronismo", "el SHA-256 no coincide", "error de zlib", "perfil de otra serie del sistema",
        "actualizacion por red en curso", "parametro no valido", "no hay ningun perfil con ese nombre", "error de lectura o escritura de la SD",
        "perfil_cargar rechazo el bitstream (el PL no se ha tocado)", "corte simulado de la luz (prueba)", "falta la confirmacion",
        "la relectura no coincide con lo escrito", "SW1 en JTAG: sin BootROM no se puede reiniciar",
        "se arranco desde esta tarjeta: pon SW1 en QSPI para prepararla", "la tarjeta no guarda lo que se le escribe (falsa o defectuosa)"
    };
    return (e >= 0 && e < MXPF_E_N) ? t[e] : "?";
}

/* ---- ordenes por la zona de la DDR (tools/perfiles.tcl): para probar sin teclado ni pantalla -------------------------
 *   +0x100 magia 'MXOR' (la escribe xsdb la ULTIMA)  +0x104 orden  +0x108 arg0  +0x10C arg1  +0x110 id (16 B, texto)
 *   +0x120 'CON1'  +0x124 'CON2'  +0x128 comprobacion = XOR de las palabras anteriores ^ 0xA5A5A5A5
 *   ordenes: 1 estado, 2 preparar*, 3 instalar (arg0 = bytes del .mxp en +0x1000, arg1 = cortar la luz tras N sectores, 0 = no),
 *            4 cargar, 5 borrar*, 6 perfil1, 7 tarjeta_vacia* (arg1 = MB de la tarjeta; PRUEBA), 8 preparar_dedicada* (arg1 = MB de la tarjeta;
 *            la unica que borra una tarjeta ajena; nunca con arranque desde SD).  * = pide CON1 y CON2.
 *   cargar y borrar: id en +0x110, o arg0 = numero de la lista (1..n) si el id va vacio.
 * informe en +0x200: seq (sube al terminar), orden, estado (1 en curso, 2 OK, 0x80 + codigo), codigo, 8 tiempos (us: lee,
 *   escribe, verifica, copia, sha, zlib, pcap, total), activo (MXA_*), n perfiles, estado MXS_*, bytes de texto; el texto, ASCII, en +0x400. */
#define OR_MAGIA        0x524F584DU
#define CONF1           0x314E4F43U
#define CONF2           0x324E4F43U
enum { OR_ESTADO = 1, OR_PREPARAR, OR_INSTALAR, OR_CARGAR, OR_BORRAR, OR_PERFIL1, OR_VACIA, OR_DEDICADA };

static u32 tx_n;
static volatile u8 *tx_buf(void) { return (volatile u8 *)(MX_SO + Z_TXT); }
static void tx_c(char c) { if (tx_n < Z_TXTSZ - 1U) tx_buf()[tx_n++] = (u8)c; }
static void tx_s(const char *s) { while (*s) tx_c(*s++); }
static void tx_u(u32 v) { char t[11]; int n = 0; do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v); while (n) tx_c(t[--n]); }
static void tx_h(const u8 *b, u32 n) { static const char x[] = "0123456789abcdef"; u32 i; for (i = 0; i < n; i++) { tx_c(x[b[i] >> 4]); tx_c(x[b[i] & 15U]); } }
static void tx_fin(void) { tx_buf()[tx_n] = 0U; }

static void tx_estado(void)
{
    const mxpf_info_t *in = &I;
    char arr[9];
    int i;
    static const char *const cl[] = { "sin tarjeta", "error de lectura", "NUESTRA (dedicada)", "NUESTRA_ANTIGUA (0xDA compartida con FAT)", "DANADA (directorios rotos)",
                                      "INTERRUMPIDA (preparacion a medias)", "VACIA", "AJENA", "DEFECTUOSA" };
    static const char *const fm[] = { "?", "sin tabla", "FAT12", "FAT16", "FAT32", "exFAT", "NTFS", "GPT", "otro" };
    const mxpf_clase_t *k = mxpf_clasifica();
    tx_s("TF1: ");
    tx_s("clase "); tx_s(cl[k->clase]); tx_s(", "); tx_s(fm[k->formato]); tx_s(", "); tx_u(k->nparts); tx_s(" particiones");
    if (k->msxdos) tx_s(", datos de MSX-DOS");
    tx_c('\n'); tx_s("TF1: ");
    if (in->estado == MXS_SIN_TARJETA) { tx_s("sin tarjeta\n"); }
    else if (in->estado == MXS_ERROR_TARJETA) { tx_u(in->mb); tx_s(" MB, error de lectura\n"); }
    else {
        tx_u(in->mb); tx_s(" MB\n");
        if (in->estado == MXS_SIN_PARTICION) {
            if (in->motivo) { tx_s("Sin particion MXPF; no se puede preparar: "); tx_s(mxpf_err_es(in->motivo)); tx_c('\n'); }
            else { tx_s("Sin particion MXPF; se puede preparar: "); tx_u(in->prep_secs >> 11); tx_s(" MB desde el sector "); tx_u(in->prep_lba); tx_c('\n'); }
        } else {
            tx_s(in->estado == MXS_DANADA ? "Particion MXPF DANADA (directorios rotos): " : "Particion MXPF OK: ");
            tx_u(in->part_secs >> 11); tx_s(" MB desde el sector "); tx_u(in->part_lba);
            if (in->estado == MXS_OK) {
                tx_s(", "); tx_u(in->huecos); tx_s(" huecos de "); tx_u(G_ss >> 11); tx_s(" MB ("); tx_u(in->libres); tx_s(" libres), directorio ");
                tx_c(in->dir ? 'B' : 'A'); tx_s(" secuencia "); tx_u(in->seq);
            }
            tx_c('\n');
        }
    }
    tx_s("Perfil activo: ");
    if (act_tipo == MXA_TARJETA) {
        tx_s(act_p.id); tx_c(' '); tx_s(act_p.version); tx_s(" (de la tarjeta, serie "); tx_u(act_p.serie);
        tx_s(", bin "); tx_u(act_p.tam_bin); tx_s(" B, sha "); tx_h(act_p.sha, 4); tx_s(")\n");
    }
    else if (act_tipo == MXA_OTRO) tx_s("otro (cargado desde la DDR por la prueba de PCAP)\n");
    else { tx_s("1 = BOOT.bin "); tx_s(ota_version()); tx_s(", serie "); tx_u(ota_serie()); tx_c('\n'); }
    tx_s("Al encender: "); if (cfg_perfil_arranque(arr)) tx_s(arr); else tx_s("perfil 1"); tx_c('\n');
    if (in->estado == MXS_OK) {
        for (i = 0; i < in->n; i++) {
            const mxpf_perfil *p = &in->p[i];
            tx_c(' '); tx_u((u32)i + 1U); tx_s(") "); tx_s(p->id); tx_s("  "); tx_s(p->version); tx_s("  serie "); tx_u(p->serie);
            tx_s(p->metodo ? "  zlib " : "  crudo "); tx_u(p->tam); tx_s(" B -> bin "); tx_u(p->tam_bin);
            tx_s(" B  hueco "); tx_u(p->hueco); tx_s("  sha "); tx_h(p->sha, 4);
            if (ota_serie() && p->serie != ota_serie()) tx_s("  [de otra serie: no se carga]");
            if (act_tipo == MXA_TARJETA && mx_eq((const u8 *)act_p.id, (const u8 *)p->id, 9) && mx_eq(act_p.sha, p->sha, 32)) tx_s("  <== ACTIVO");
            tx_c('\n');
        }
        if (!in->n) tx_s(" (ningun perfil instalado)\n");
    }
}

static void tx_tiempos(void)
{
    tx_s("tiempos (ms): lee SD "); tx_u(mxpf_t[MXT_LEE] / 1000U); tx_s(", escribe SD "); tx_u(mxpf_t[MXT_ESC] / 1000U);
    tx_s(", verifica SD "); tx_u(mxpf_t[MXT_VER] / 1000U); tx_s(", copia "); tx_u(mxpf_t[MXT_COPIA] / 1000U);
    tx_s(", SHA-256 "); tx_u(mxpf_t[MXT_SHA] / 1000U); tx_s(", zlib "); tx_u(mxpf_t[MXT_ZLIB] / 1000U);
    tx_s(", PCAP "); tx_u(mxpf_t[MXT_PCAP] / 1000U); tx_s(", total "); tx_u(mxpf_t[MXT_TOTAL] / 1000U); tx_c('\n');
}

static void informe_ini(u32 orden)
{
    volatile u32 *r = (volatile u32 *)(MX_SO + Z_INF);
    r[1] = orden; r[3] = 0U; r[2] = 1U;
    tx_n = 0; tx_fin();
}
static void informe_fin(u32 st, u32 cod)
{
    volatile u32 *r = (volatile u32 *)(MX_SO + Z_INF);
    u32 i;
    tx_fin();
    for (i = 0; i < MXT_N; i++) r[4 + i] = mxpf_t[i];
    r[12] = (u32)act_tipo; r[13] = I.n; r[14] = I.estado; r[15] = tx_n;
    r[3] = cod; r[2] = st;
    r[0] = r[0] + 1U;                                       /* lo ultimo: quien espera mira esto */
}

static int arg_perfil(const volatile u32 *o, char *id)      /* id de la orden: texto en +0x110 o numero en arg0 (1..n); 1 = hay */
{
    u32 i, a0 = o[2];
    for (i = 0; i < 16U; i++) {
        u8 c = (u8)(o[4 + i / 4U] >> (8U * (i % 4U)));
        if (i < 8U) id[i] = (char)((c >= 'a' && c <= 'z') ? c - 32 : c);
        else if (c) return 0;
    }
    id[8] = 0;
    if (id[0]) return 1;
    if (a0 >= 1U && a0 <= I.n) { u32 k; for (k = 0; k < 9U; k++) id[k] = I.p[a0 - 1U].id[k]; return 1; }
    return 0;
}

int mxpf_poll(void)
{
    volatile u32 *o = (volatile u32 *)(MX_SO + Z_ORD);
    u32 orden, a0, a1, c1, c2, w[10], i, chk;
    char id[17];
    int r = MXPF_OK, cargo = 0;
    if (o[0] != OR_MAGIA) return 0;
    for (i = 0; i < 10U; i++) w[i] = o[i];
    chk = o[10];
    o[0] = 0U;                                              /* una sola vez, pase lo que pase */
    orden = w[1]; a0 = w[2]; a1 = w[3]; c1 = w[8]; c2 = w[9];
    for (i = 0, chk ^= 0xA5A5A5A5U; i < 10U; i++) chk ^= w[i];
    informe_ini(orden);
    log_str("mxpf: orden "); log_dec(orden); log_str("\n");
    if (chk != 0U) { r = MXPF_E_PARAM; tx_s("comprobacion de la orden mal: se ignora\n"); informe_fin(0x80U | (u32)r, (u32)r); return 0; }
    op_ini();
    switch (orden) {
        case OR_ESTADO:
            (void)mxpf_monta();
            break;
        case OR_PREPARAR:
            if (c1 != CONF1 || c2 != CONF2) { r = MXPF_E_CONFIRMA; break; }
            r = prepara_();
            break;
        case OR_INSTALAR:
            if (a0 < SEC || a0 > Z_SCR - Z_DATOS) { r = MXPF_E_PARAM; break; }
            if (a1) mxpf_corte(a1);
            r = instala_(MX_SO + Z_DATOS, a0);
            break;
        case OR_CARGAR:
            (void)mxpf_monta();
            if (!arg_perfil(o, id)) { r = MXPF_E_PARAM; break; }
            tx_s("cargando "); tx_s(id); tx_c('\n');
            r = carga_(id);
            cargo = (r == MXPF_OK);
            break;
        case OR_BORRAR:
            if (c1 != CONF1 || c2 != CONF2) { r = MXPF_E_CONFIRMA; break; }
            (void)mxpf_monta();
            if (!arg_perfil(o, id)) { r = MXPF_E_PARAM; break; }
            r = borra_(id);
            break;
        case OR_PERFIL1:
            (void)mxpf_monta();
            if (MX_BOOT_MODO() != 0U) {                     /* el informe va ANTES: el reinicio del PS se lleva la ejecucion */
                tx_s("RESULTADO: OK - reiniciando el PS; vuelve el perfil del BOOT.bin\n");
                tx_estado();
                (void)op_fin(0);
                informe_fin(2U, 0U);
            }
            r = mxpf_perfil1();                             /* solo vuelve si no ha podido */
            break;
        case OR_VACIA:
            if (c1 != CONF1 || c2 != CONF2) { r = MXPF_E_CONFIRMA; break; }
            r = vacia_(a1);
            break;
        case OR_DEDICADA:
            if (c1 != CONF1 || c2 != CONF2) { r = MXPF_E_CONFIRMA; break; }
            if (a1 != (tf1_sectores() >> 11)) { r = MXPF_E_PARAM; break; }   /* arg1 = MB de la tarjeta (sale en «estado»), como tarjeta_vacia */
            (void)mxpf_ded_arma();                          /* las dos confirmaciones vienen en la orden */
            r = prepara_ded_(1);
            break;
        default:
            r = MXPF_E_PARAM;
            break;
    }
    r = op_fin(r);
    (void)mxpf_monta();
    tx_c('\n'); tx_s(r == MXPF_OK ? "RESULTADO: OK\n" : "RESULTADO: ERROR - "); if (r != MXPF_OK) { tx_s(mxpf_err_es(r)); tx_c('\n'); }
    tx_tiempos();
    tx_estado();
    log_str("mxpf: orden "); log_dec(orden); log_str(r == MXPF_OK ? " OK, " : " ERROR "); if (r != MXPF_OK) log_dec((u32)r);
    log_str(" total "); log_dec(mxpf_t[MXT_TOTAL] / 1000U); log_str(" ms\n");
    informe_fin(r == MXPF_OK ? 2U : (0x80U | (u32)r), (u32)r);
    return cargo;
}
