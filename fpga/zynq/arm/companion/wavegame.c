/* wavegame.c — WaveGame en la ZYNQ MINI (16/09/2026): musica WAV en streaming controlada por el juego.
 *
 * Protocolo (Jeroen Taverne / Mauricio Braga; lo usan MSX Pico, PicoVerse y openMSX): el juego
 * escribe 1 byte en el puerto 92h, fire-and-forget:
 *   01xxxxxx  toca la cancion xx una vez        10xxxxxx  toca xx en bucle
 *   0000xxxx  fade-out de x s (0 = 1 s)         11000000  pausa / continua
 *   11010000  difiere la proxima orden al final de la cancion
 *   11100000  retoma la anterior con fade-in de 1 s
 *   11110000  toca pause.wav
 * Ficheros: NN.wav (00..63, 48 kHz mono 16 bits) + NN.cfg opcional (linea 1 = offset de bucle en
 * MUESTRAS, linea 2 = offset de inicio) + pause.wav, en la MISMA carpeta que la ROM.
 *
 * Camino en la Zynq: el PL mete cada OUT 92h/93h en un anillo que el buzon vuelca en MBOX+0x78 (32
 * entradas {tag, dato}, indice en +0xBF). El menu, al lanzar una ROM, manda por el 93h (el 47h es la orden del controlador SD) "WG" + PART_LBA
 * + CUR_CLUS + FILE_CLUS: con eso montamos la FAT (16/32) de la tarjeta de TF2 y buscamos los NN.wav
 * en esa carpeta. Las muestras se remuestrean a 44,1 kHz (lineal), con la ganancia/fade aplicada, y
 * se escriben en un anillo de 32768 int16 en la DDR (WG_RING); el PL las trae en rafagas de 64 y las
 * mezcla x1 con el resto del audio. Control: MBOX+0x20 = {play[31], wr[15:0]}; con play=0 el PL vacia
 * su FIFO y pone rd=wr (cambio de cancion instantaneo). Telemetria: +0xBE = rd (u16), +0xBA nivel.
 * SIEMPRE se escriben multiplos de 64 muestras (el PL solo trae bloques de 64).
 * Inyeccion para pruebas desde xsdb: MBOX+0x38 = {seq[31:24], tag[15:8], dato[7:0]} (tools/wg.tcl).
 *
 * 22/09/2026 — MUSICA DEL MENU sobre el mismo motor. Ordenes nuevas por el 93h:
 *   'W','P' + PART_LBA(4) + cluster de la CARPETA(4) + indice de pista(4)  -> lista los .WAV de esa
 *       carpeta (CUALQUIER nombre, no solo los NN.wav del WaveGame) y toca esa pista; al acabar pasa
 *       sola a la siguiente hasta el final de la lista.
 *   'W','F' + PART_LBA(4) + cluster de la CARPETA(4) + cluster del FICHERO(4) -> la misma lista,
 *       pero empezando por ese fichero (RETURN sobre un .WAV en el navegador, 23/09)
 *   'W','N'  -> pista siguiente      'W','X'  -> parar
 * Todo lo demas se comparte con el WaveGame: mismo anillo PCM, mismo remuestreo a 44,1 kHz, misma
 * ganancia y mismo mezclador. Esto es solo OTRO DISPARADOR. (Lanzar una ROM manda 'W','G', que para
 * la lista: la musica del menu no se cuela en el juego salvo que se pida a proposito.)
 *
 * 31/10/2026 — PERFILES (perfiles_ext.c). Mismo mensaje de 14 bytes con dos ordenes mas:
 *   'W','I' + PART_LBA + cluster de la CARPETA + cluster del FICHERO  -> instalar en la TF1 el .MXP elegido en el navegador
 *   'W','Q' + (igual)  -> RETURN sobre una ROM, antes de cargarla: si su nombre lleva [P:ID], cargar ese perfil
 * ('W','G', al lanzar la ROM, hace la misma comprobacion). Aqui solo se recogen; se ejecutan desde pext_poll().
 */
#include "xil_types.h"
#include "sleep.h"
#include "log.h"
#include "mp3.h"
#include "perfiles_ext.h"
#include "dual.h"

#define MBOX        0x1FF00000U
#define REG(a)      (*(volatile u32 *)(a))
#define WG_CTL      REG(MBOX + 0x20U)
#define WG_INJ      REG(MBOX + 0x38U)
#define WG_TEL_LO   REG(MBOX + 0xB8U)            /* {8'd0, nivel FIFO[23:16], fetches[15:8], 7'd0, play} */
#define WG_TEL_HI   REG(MBOX + 0xBCU)            /* {z2a_wi[31:24], 8'd0, rd[15:0]} */
#define Z2A_RING    ((volatile u16 *)(MBOX + 0x78U))
#define WG_RING     ((volatile s16 *)(MBOX + 0x80000U))
#define RING_MASK   0x7FFFU
#define LOOKAHEAD   4096U                        /* muestras por delante del PL (93 ms) */
#define OUT_RATE    44100U
#define MAX_SONGS   64

extern int  sd_read(u32 sec, u32 cnt, u8 *buf);  /* main.c: XSdPs_ReadPolled sobre la tarjeta de TF2 */

/* ------------------------------------------------------------------ FAT 16/32 de solo lectura */
static struct {
    u32 part_lba, fat_lba, root_lba, data_lba, root_clus, spf;
    u16 root_ents; u8 spc, fat32, ok;
} fs;
static u8  fatbuf[512] __attribute__((aligned(32)));
static u32 fatbuf_lba = 0xFFFFFFFFU;
static u8  secbuf[512 * 8] __attribute__((aligned(32)));

static u16 rd16(const u8 *p) { return (u16)(p[0] | (p[1] << 8)); }
static u32 rd32(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24); }

static int fat_mount_buf(u32 part_lba, u8 *b)       /* b: donde se lee el sector de arranque (secbuf, o uno propio si hay un WAV sonando) */
{
    u16 bps, rsvd; u8 nfats; u32 spf16, spf32;
    fs.ok = 0; fatbuf_lba = 0xFFFFFFFFU;
    if (!sd_read(part_lba, 1, b)) return 0;
    bps = rd16(b + 11); fs.spc = b[13]; rsvd = rd16(b + 14); nfats = b[16]; fs.root_ents = rd16(b + 17);
    spf16 = rd16(b + 22); spf32 = rd32(b + 36); fs.root_clus = rd32(b + 44);
    if (bps != 512 || fs.spc == 0 || nfats == 0) return 0;
    fs.part_lba = part_lba;
    fs.fat32 = (spf16 == 0);
    fs.spf = fs.fat32 ? spf32 : spf16;
    fs.fat_lba = part_lba + rsvd;
    fs.root_lba = fs.fat_lba + (u32)nfats * fs.spf;
    fs.data_lba = fs.root_lba + (fs.fat32 ? 0U : (((u32)fs.root_ents * 32U + 511U) / 512U));
    fs.ok = 1;
    return 1;
}
static int fat_mount(u32 part_lba) { return fat_mount_buf(part_lba, secbuf); }

static u32 clus_lba(u32 c) { return fs.data_lba + (c - 2U) * fs.spc; }

static u32 fat_next(u32 c)                         /* 0 = fin de cadena / error */
{
    u32 off = fs.fat32 ? c * 4U : c * 2U;
    u32 lba = fs.fat_lba + off / 512U;
    u32 v;
    if (lba != fatbuf_lba) { if (!sd_read(lba, 1, fatbuf)) return 0; fatbuf_lba = lba; }
    v = fs.fat32 ? (rd32(fatbuf + (off % 512U)) & 0x0FFFFFFFU) : rd16(fatbuf + (off % 512U));
    if (fs.fat32 ? (v >= 0x0FFFFFF8U) : (v >= 0xFFF8U)) return 0;
    if (v < 2U) return 0;
    return v;
}

/* fichero secuencial por la cadena de clusters, con un buffer de hasta 8 sectores */
typedef struct {
    u32 first, size;          /* primer cluster y tamano en bytes */
    u32 clus, cidx;           /* cluster actual y su indice en la cadena */
    u32 pos;                  /* posicion en bytes */
    u32 blba, bcnt;           /* sectores en secbuf: LBA del primero y cuantos (0 = nada) */
} wfile;

static u32 file_clus_at(wfile *f, u32 cidx)        /* cluster numero cidx de la cadena (camina desde donde este) */
{
    if (cidx < f->cidx) { f->clus = f->first; f->cidx = 0; }
    while (f->cidx < cidx && f->clus) { f->clus = fat_next(f->clus); f->cidx++; }
    return f->clus;
}

static void wf_open(wfile *f, u32 first, u32 size) { f->first = first; f->size = size; f->clus = first; f->cidx = 0; f->pos = 0; f->bcnt = 0; }
static void wf_seek(wfile *f, u32 pos) { if (pos > f->size) pos = f->size; f->pos = pos; f->bcnt = 0; }

static u32 wf_read(wfile *f, u8 *dst, u32 n)      /* devuelve los bytes leidos (< n al final o con error) */
{
    u32 got = 0;
    if (f->pos + n > f->size) n = f->size - f->pos;
    while (n) {
        u32 cbytes = (u32)fs.spc * 512U;
        u32 cidx = f->pos / cbytes, cin = f->pos % cbytes;
        u32 sec = cin / 512U, soff = cin % 512U;
        u32 lba, k;
        if (!file_clus_at(f, cidx)) break;
        lba = clus_lba(f->clus) + sec;
        if (f->bcnt == 0 || lba < f->blba || lba >= f->blba + f->bcnt) {
            u32 cnt = fs.spc - sec; if (cnt > 8U) cnt = 8U;             /* sin cruzar el cluster */
            if (!sd_read(lba, cnt, secbuf)) break;
            f->blba = lba; f->bcnt = cnt;
        }
        k = (f->blba + f->bcnt - lba) * 512U - soff;                  /* bytes disponibles en el buffer */
        if (k > n) k = n;
        { const u8 *src = secbuf + (lba - f->blba) * 512U + soff; for (u32 i = 0; i < k; i++) dst[i] = src[i]; }
        dst += k; f->pos += k; n -= k; got += k;
    }
    return got;
}

/* ------------------------------------------------------------------ catalogo de la carpeta */
typedef struct { u32 clus, size; u32 cfg_clus, cfg_size; u8 mp3; } dirent_t;   /* mp3: solo pistas del menu */
static dirent_t songs[MAX_SONGS], pausewav;
#define MAX_TRACKS 64
static dirent_t tracks[MAX_TRACKS];      /* .wav de la carpeta que el menu esta mirando */
static dirent_t onefile;                 /* la pista en curso (song_start la pide con idx 101) */
static int      n_tracks = 0;
static int      track_idx = -1;          /* >= 0: lista del menu en marcha */
static u32      list_dir = 0;            /* carpeta de esa lista: repetir 'W','P' sobre ella = pausa/sigue */
static int      list_paused = 0;         /* 23/09: lista del menu en pausa (pausa blanda, ver list_pause) */
static u16      pause_wr;                /* wr del ARM al pausar: hasta aqui esta escrito en el anillo */
static u8 have_song[MAX_SONGS], have_pause, mounted;

static void dir_scan(u32 dir_clus)
{
    u32 lba, nsec, sec = 0, clus;
    if (fs.fat32 && dir_clus == 0U) dir_clus = fs.root_clus;   /* raiz de FAT32: resolverla ANTES del bucle */
    clus = dir_clus;
    for (int i = 0; i < MAX_SONGS; i++) have_song[i] = 0;
    have_pause = 0;
    for (;;) {
        if (!fs.fat32 && dir_clus == 0U) { lba = fs.root_lba + sec; nsec = ((u32)fs.root_ents * 32U + 511U) / 512U; if (sec >= nsec) return; }
        else {
            if (clus == 0U) return;
            lba = clus_lba(clus) + (sec % fs.spc);
        }
        if (!sd_read(lba, 1, secbuf)) return;
        for (u32 e = 0; e < 16U; e++) {
            const u8 *d = secbuf + e * 32U;
            u8 attr = d[11];
            if (d[0] == 0x00U) return;
            if (d[0] == 0xE5U || attr == 0x0FU || (attr & 0x18U)) continue;
            {
                u32 first = ((u32)rd16(d + 20) << 16) | rd16(d + 26);
                u32 size = rd32(d + 28);
                int is_wav = (d[8] == 'W' && d[9] == 'A' && d[10] == 'V');
                int is_cfg = (d[8] == 'C' && d[9] == 'F' && d[10] == 'G');
                if (d[0] >= '0' && d[0] <= '9' && d[1] >= '0' && d[1] <= '9' && d[2] == ' ' && (is_wav || is_cfg)) {
                    int n = (d[0] - '0') * 10 + (d[1] - '0');
                    if (n < MAX_SONGS) {
                        if (is_wav) { songs[n].clus = first; songs[n].size = size; have_song[n] |= 1; }
                        else        { songs[n].cfg_clus = first; songs[n].cfg_size = size; have_song[n] |= 2; }
                    }
                } else if (is_wav && d[0] == 'P' && d[1] == 'A' && d[2] == 'U' && d[3] == 'S' && d[4] == 'E' && d[5] == ' ') {
                    pausewav.clus = first; pausewav.size = size; have_pause = 1;
                }
            }
        }
        sec++;
        if (!(!fs.fat32 && dir_clus == 0U) && (sec % fs.spc) == 0U) clus = fat_next(clus);
    }
}

/* ------------------------------------------------------------------ motor de reproduccion */
typedef struct {
    wfile f;
    u32 data_off, data_len;    /* chunk 'data' */
    u32 rate; u8 ch, bytes;    /* formato (mono/estereo, 8/16 bits) */
    u32 loop_smp;              /* offset de bucle en muestras (0xFFFFFFFF = sin cfg -> 0) */
    u32 start_smp;
    u32 nsmp;                  /* muestras totales */
    u32 pos_smp;               /* proxima muestra de entrada a leer */
    u8  kind;                  /* 0 = WAV, 1 = MP3 (mp3.c; nsmp desconocido = 0xFFFFFFFF) */
} song_t;

static song_t cur;
static int  cur_idx = -1, cur_loop = 0, playing = 0, paused = 0;
static u32  step_q16;                      /* rate/44100 en Q16 */
static u32  frac_q16;
static s32  s0, s1;                        /* dos ultimas muestras de entrada */
static s32  s0r, s1r;                      /* 23/09: las del canal derecho (estereo) */
static int  wg_st = 0;                     /* 23/09: la cancion en curso va en ESTEREO (bit 30 de +0x20) */
/* 28/09 (F.7c, pendiente 9): ENSANCHADO de las pistas MONO del menu. L = M + S, R = M - S, con S = width x
 * [paso-alto 250 Hz -> paso-todo 500 Hz -> paso-todo 2 kHz -> paso-bajo 6 kHz](M), a 44,1 kHz (tras el remuestreo).
 * L + R = 2M EXACTO: con "Stereo Sound" apagado el PL mezcla (L+R)/2 y sale el mono de siempre; en un televisor
 * mono tampoco se pierde nada. Los paso-todo giran la fase de S respecto a M por la banda media, que es lo que
 * separa los lados sin muescas; sin bajos (quedan al centro) y sin agudos (no silba). Solo las pistas del menu
 * (idx 101) de 1 canal; el WaveGame de los juegos, pause.wav y el tono siguen en mono a proposito.        */
static s32  wid_q15 = 9830;                /* anchura 0.30 (inyeccion tag 3E: 0..255 -> 0..1; 0 = apagado) */
static int  wid_on = 0;                    /* la cancion en curso lleva ensanchado */
static s32  wid_hx, wid_hy, wid_a1x, wid_a1y, wid_a2x, wid_a2y, wid_ly;
static void wid_reset(void) { wid_hx = wid_hy = wid_a1x = wid_a1y = wid_a2x = wid_a2y = wid_ly = 0; }
static s32  wid_side(s32 m)
{
    s32 x, y;
    y = ((wid_hy + m - wid_hx) * 31624) >> 15;        wid_hx = m;  wid_hy = y;      /* HP 250 Hz: a = 0,9651 */
    x = y; y = (((wid_a1y - x) * 30517) >> 15) + wid_a1x; wid_a1x = x; wid_a1y = y;  /* AP 500 Hz: c = 0,9313 */
    x = y; y = (((wid_a2y - x) * 24556) >> 15) + wid_a2x; wid_a2x = x; wid_a2y = y;  /* AP 2 kHz: c = 0,7494 */
    wid_ly += ((y - wid_ly) * 18841) >> 15;                                          /* LP 6 kHz: 1 - e^-w = 0,575 */
    return (wid_ly * wid_q15) >> 15;
}
static int  in_valid;
static s32  gain_q23 = 32768 << 8;         /* ganancia actual (fade), 1.0 = 32768<<8 */
static s32  gain_step = 0;                 /* por muestra de salida (Q23) */
static s32  gain_master = 32768;           /* volumen fino 0..1 (inyeccion tag 3C: 0..255) */
static u32  gain_shift = 0;                /* ganancia del PL: x1/x2/x4/x8 (inyeccion tag 3D: 0..3). x1 = maximo LIMPIO: los WAV vienen a fondo de escala y el limitador (rodilla 24576, tope 32767) recorta a partir de ahi; x4 distorsionaba (Albert 17/09) */
static int  stop_at_zero = 0;
static u16  wr = 0;                        /* puntero de escritura del anillo (libre, mod 65536) */
static u32  produced = 0;                  /* muestras de salida producidas para la cancion actual */
static int  defer_next = 0, deferred = -1;
static struct { int idx, loop; u32 pos_smp; int valid; } prev;
static u8   inbuf[2048] __attribute__((aligned(32)));
static u32  inbuf_n = 0, inbuf_i = 0;

static int parse_cfg(dirent_t *d, u32 *loop, u32 *start)
{
    wfile f; u8 b[64]; u32 n, i = 0, v = 0, line = 0; int got = 0;
    *loop = 0xFFFFFFFFU; *start = 0;
    if (!d->cfg_clus) return 0;
    wf_open(&f, d->cfg_clus, d->cfg_size);
    n = wf_read(&f, b, sizeof b - 1); b[n] = 0;
    for (; i <= n; i++) {
        if (b[i] >= '0' && b[i] <= '9') { v = v * 10U + (b[i] - '0'); got = 1; }
        else if (b[i] == '\n' || b[i] == 0) {
            if (got) { if (line == 0) *loop = v; else if (line == 1) *start = v; line++; }
            v = 0; got = 0;
            if (b[i] == 0) break;
        }
    }
    return 1;
}

static u32 mp3_rd(void *ctx, u8 *dst, u32 n) { return wf_read((wfile *)ctx, dst, n); }
static int mp3_logged = 1;

static int song_open_mp3(song_t *s, dirent_t *d)
{
    u8 h[10]; u32 skip = 0, hz, ch;
    wf_open(&s->f, d->clus, d->size);
    if (wf_read(&s->f, h, 10) == 10 && h[0] == 'I' && h[1] == 'D' && h[2] == '3') {   /* ID3v2: tamano syncsafe */
        skip = 10U + (((u32)(h[6] & 0x7FU) << 21) | ((u32)(h[7] & 0x7FU) << 14) | ((u32)(h[8] & 0x7FU) << 7) | (u32)(h[9] & 0x7FU));
        if (h[5] & 0x10U) skip += 10U;                                              /* con pie */
    }
    wf_seek(&s->f, skip);
    s->data_off = skip; s->data_len = d->size > skip ? d->size - skip : 0U;
    if (!mp3_open(mp3_rd, &s->f, &hz, &ch)) return 0;
    s->kind = 1; s->rate = hz; s->ch = (u8)ch; s->bytes = 2;
    s->nsmp = 0xFFFFFFFFU; s->pos_smp = 0;
    mp3_logged = 0;
    return 1;
}

static void mp3_log_stats(void)                      /* una vez por cancion: cuanto le cuesta cada trama al ARM */
{
    u32 fr, tmax, tsum;
    if (mp3_logged || cur.kind != 1) return;
    mp3_logged = 1;
    mp3_stats(&fr, &tmax, &tsum);
    if (!fr) return;
    log_str("mp3: "); log_dec(fr); log_str(" tramas, media "); log_dec((tsum / fr) * 3U / 1000U);
    log_str(" us, max "); log_dec(tmax * 3U / 1000U); log_str(" us\n");     /* temporizador global = 333 MHz */
}

static int song_open(song_t *s, dirent_t *d)      /* cabecera RIFF/WAVE: fmt + data */
{
    u8 h[64]; u32 off = 12, n;
    if (d->mp3) return song_open_mp3(s, d);
    s->kind = 0;
    wf_open(&s->f, d->clus, d->size);
    if (wf_read(&s->f, h, 12) != 12 || h[0] != 'R' || h[1] != 'I' || h[2] != 'F' || h[3] != 'F' || h[8] != 'W' || h[9] != 'A' || h[10] != 'V' || h[11] != 'E') return 0;
    s->rate = 0; s->data_off = 0;
    while (off + 8 <= d->size) {
        u32 csz;
        wf_seek(&s->f, off);
        if (wf_read(&s->f, h, 8) != 8) return 0;
        csz = rd32(h + 4);
        if (h[0] == 'f' && h[1] == 'm' && h[2] == 't' && h[3] == ' ') {
            n = csz > 16U ? 16U : csz;
            if (wf_read(&s->f, h + 8, n) != n) return 0;
            s->ch = h[8 + 2]; s->rate = rd32(h + 8 + 4); s->bytes = h[8 + 14] / 8U;
        } else if (h[0] == 'd' && h[1] == 'a' && h[2] == 't' && h[3] == 'a') {
            s->data_off = off + 8; s->data_len = csz;
            if (s->data_off + s->data_len > d->size) s->data_len = d->size - s->data_off;
            break;
        }
        off += 8 + csz + (csz & 1U);
    }
    if (!s->rate || !s->data_off || s->ch == 0 || s->ch > 2 || (s->bytes != 1 && s->bytes != 2)) return 0;
    s->nsmp = s->data_len / ((u32)s->ch * s->bytes);
    s->pos_smp = 0;
    return 1;
}

static void song_seek(song_t *s, u32 smp)
{
    if (smp >= s->nsmp) smp = 0;
    s->pos_smp = smp;
    wf_seek(&s->f, s->data_off + smp * (u32)s->ch * s->bytes);
    inbuf_n = 0; inbuf_i = 0;
}

/* siguiente muestra de entrada (mono, 16 bits); 0 = fin (o con bucle: salta) */
/* siguiente muestra de entrada, los DOS canales (23/09, fase 7c); en mono, l = r. 0 = fin */
static int in_next2(s32 *l, s32 *r)
{
    u32 fs_ = (u32)cur.ch * cur.bytes;
    int tries = 0;
    if (cur.kind == 1) {                                  /* MP3: 16 bits, ya separado por canales */
        if (!mp3_next2(l, r)) return 0;
        cur.pos_smp++;
        return 1;
    }
    while (inbuf_i >= inbuf_n) {
        u32 want;
        if (++tries > 3) return 0;                        /* tarjeta ilegible: acabar sin colgarse */
        if (cur.pos_smp >= cur.nsmp) {
            if (!cur_loop) return 0;
            song_seek(&cur, (cur.loop_smp == 0xFFFFFFFFU) ? 0U : cur.loop_smp);
            if (cur.pos_smp >= cur.nsmp) return 0;
        }
        want = (cur.nsmp - cur.pos_smp) * fs_; if (want > sizeof inbuf) want = sizeof inbuf;
        want -= want % fs_;
        inbuf_n = wf_read(&cur.f, inbuf, want); inbuf_i = 0;
        if (inbuf_n < fs_) { cur.pos_smp = cur.nsmp; inbuf_n = 0; continue; }
        inbuf_n -= inbuf_n % fs_;
    }
    {
        const u8 *p = inbuf + inbuf_i;
        if (cur.bytes == 2) { *l = (s16)rd16(p); *r = (cur.ch == 2) ? (s32)(s16)rd16(p + 2) : *l; }
        else { *l = ((s32)p[0] - 128) * 256; *r = (cur.ch == 2) ? ((s32)p[1] - 128) * 256 : *l; }
        inbuf_i += fs_; cur.pos_smp++;
    }
    return 1;
}

/* la de siempre, en mono: la media de los dos canales (identica a la mezcla que hacia antes) */
static int in_next(s32 *out)
{
    s32 l, r;
    if (!in_next2(&l, &r)) return 0;
    *out = (l + r) / 2;
    return 1;
}

static void ring_put(s32 v)
{
    s32 g = ((gain_q23 >> 8) * gain_master) >> 15;
    v = (v * g) >> 15;
    if (v > 32767) v = 32767; else if (v < -32768) v = -32768;
    WG_RING[wr & RING_MASK] = (s16)v;
    wr++;
    if (gain_step) {
        gain_q23 += gain_step;
        if (gain_q23 <= 0) { gain_q23 = 0; gain_step = 0; }
        else if (gain_q23 >= (32768 << 8)) { gain_q23 = 32768 << 8; gain_step = 0; }
    }
}

static void ring_put2(s32 l, s32 r)                /* 23/09: un par {L, R} con la misma ganancia */
{
    s32 g = ((gain_q23 >> 8) * gain_master) >> 15;
    l = (l * g) >> 15; r = (r * g) >> 15;
    if (l > 32767) l = 32767; else if (l < -32768) l = -32768;
    if (r > 32767) r = 32767; else if (r < -32768) r = -32768;
    WG_RING[wr & RING_MASK] = (s16)l; wr++;
    WG_RING[wr & RING_MASK] = (s16)r; wr++;
    if (gain_step) {
        gain_q23 += gain_step;
        if (gain_q23 <= 0) { gain_q23 = 0; gain_step = 0; }
        else if (gain_q23 >= (32768 << 8)) { gain_q23 = 32768 << 8; gain_step = 0; }
    }
}

static void wg_publish(int play) { WG_CTL = ((u32)play << 31) | ((u32)wg_st << 30) | ((gain_shift & 3U) << 28) | wr; __asm__ volatile ("dsb" ::: "memory"); }

static void song_stop(void)
{
    mp3_log_stats();
    list_paused = 0;
    playing = 0; paused = 0; cur_idx = -1; gain_step = 0; stop_at_zero = 0;
    wg_publish(0);
}

/* ---- nota de prueba del mezclador (menu: 'W','T' por el 93h): 300 ms a 440 Hz, -6 dBFS, sin fichero ---- */
static int tone_mode = 0; static u32 tone_left = 0, tone_pos = 0, tone_ph = 0;
static s32 tone_sample(void)
{
    u32 ph = tone_ph & 0xFFFFU, x = ph & 0x7FFFU;
    s32 y = (s32)((x * (32768U - x)) >> 14);              /* parabola por semiciclo (~seno, pico 16384) */
    if (ph & 0x8000U) y = -y;
    tone_ph += (440U << 16) / OUT_RATE;
    return y;
}
static void tone_block(void)
{
    for (int i = 0; i < 64; i++) {
        s32 v = 0;
        if (tone_left) {
            u32 e = tone_pos < 441U ? tone_pos : 441U;      /* 10 ms de entrada y de salida: sin clics */
            if (tone_left < e) e = tone_left;
            v = (tone_sample() * (s32)e) / 441;
            tone_left--; tone_pos++;
        }
        ring_put(v);
    }
}

/* produce 64 muestras de salida; devuelve 0 si la cancion se ha acabado (bloque rellenado con ceros) */
static int produce_block(void)
{
    int alive = 1;
    if (tone_mode) {
        tone_block();
        if (tone_left == 0U) { tone_mode = 0; return 0; }
        return 1;
    }
    if (wg_st) {                                          /* 23/09: estereo, 64 pares = 128 muestras */
        for (int i = 0; i < 64; i++) {
            s32 vl = 0, vr = 0;
            if (alive) {
                while (frac_q16 >= 65536U) {
                    s32 nl, nr;
                    if (!in_next2(&nl, &nr)) { alive = 0; break; }
                    s0 = s1; s1 = nl; s0r = s1r; s1r = nr; in_valid = 1; frac_q16 -= 65536U;
                }
                if (alive && in_valid) {
                    s32 f = (s32)(frac_q16 >> 4);
                    vl = s0 + (((s1 - s0) * f) >> 12);
                    vr = s0r + (((s1r - s0r) * f) >> 12);
                }
                if (alive) frac_q16 += step_q16;
            }
            if (wid_on) { s32 sd = wid_side(vl); vr = vl - sd; vl += sd; }   /* 28/09: mono ensanchado (vl == vr de entrada) */
            ring_put2(vl, vr);
            produced++;
            if (stop_at_zero && gain_q23 == 0) alive = 0;
        }
        return alive;
    }
    for (int i = 0; i < 64; i++) {
        s32 v = 0;
        if (alive) {
            while (frac_q16 >= 65536U) {
                s32 nx;
                if (!in_next(&nx)) { alive = 0; break; }
                s0 = s1; s1 = nx; in_valid = 1; frac_q16 -= 65536U;
            }
            if (alive) { v = in_valid ? (s0 + (((s1 - s0) * (s32)(frac_q16 >> 4)) >> 12)) : 0; frac_q16 += step_q16; }
        }
        ring_put(v);
        produced++;
        if (stop_at_zero && gain_q23 == 0) alive = 0;
    }
    return alive;
}

static void song_start(int idx, int loop, u32 from_smp, int fadein)
{
    dirent_t *d = (idx == 100) ? &pausewav : (idx == 101) ? &onefile : &songs[idx];   /* 101 = pista del menu */
    u32 loop_smp, start_smp;
    if (playing) { prev.idx = cur_idx; prev.loop = cur_loop; prev.pos_smp = cur.pos_smp; prev.valid = 1; }
    wg_publish(0);                                        /* el PL vacia la FIFO y pone rd=wr */
    playing = 0;
    mp3_log_stats();
    if (!song_open(&cur, d)) { log_str(d->mp3 ? "wg: MP3 invalido\n" : "wg: WAV invalido\n"); wg_publish(0); return; }
    if (idx >= 100) { loop_smp = 0xFFFFFFFFU; start_smp = 0; }   /* pause.wav y las pistas del menu no llevan .cfg */
    else parse_cfg(d, &loop_smp, &start_smp);
    cur.loop_smp = loop_smp; cur.start_smp = start_smp;
    if (cur.kind == 0) song_seek(&cur, from_smp ? from_smp : start_smp);   /* el MP3 ya esta en su 1a trama */
    step_q16 = (cur.rate << 16) / OUT_RATE;
    frac_q16 = 65536U; s0 = s1 = 0; s0r = s1r = 0; in_valid = 0;
    wg_st = (idx == 101) ? 1 : 0;                         /* 23/09: las pistas del menu van en pares L/R; 28/09: tambien las mono (ensanchadas) */
    wid_on = (idx == 101 && cur.ch == 1 && wid_q15 != 0) ? 1 : 0;
    wid_reset();
    gain_q23 = fadein ? 0 : (32768 << 8); gain_step = fadein ? ((32768 << 8) / (s32)OUT_RATE) : 0; stop_at_zero = 0;
    cur_idx = idx; cur_loop = loop; paused = 0; produced = 0; list_paused = 0;
    usleep(2500);                                         /* >= 1 ronda del buzon con play=0: rd ya = wr */
    for (u32 k = 0; k < LOOKAHEAD / 64U; k++) if (!produce_block()) break;
    playing = 1;
    wg_publish(1);
    log_str("wg: cancion "); log_dec((u32)idx); log_str(loop ? " (bucle)" : ""); log_str(cur.kind ? " MP3" : ""); log_str(" rate="); log_dec(cur.rate);
    log_str(" ch="); log_dec(cur.ch); log_str(wid_on ? " ENSANCHADO" : wg_st ? " ESTEREO" : ""); if (cur.kind == 0) { log_str(" muestras="); log_dec(cur.nsmp); } log_str(" loop="); log_dec(loop_smp); log_str("\n");
}

/* ------------------------------------------------------------ musica del menu: lista de una carpeta */
/* Como dir_scan pero sin el corse de los nombres NN.wav: vale cualquier fichero con extension WAV,
 * en el orden en que estan en el directorio (que es el que ve el usuario en el navegador).         */
static void track_scan(u32 dir_clus)
{
    u32 lba, nsec, sec = 0, clus;
    if (fs.fat32 && dir_clus == 0U) dir_clus = fs.root_clus;   /* raiz de FAT32: resolverla ANTES del bucle */
    clus = dir_clus;
    n_tracks = 0;
    for (;;) {
        if (!fs.fat32 && dir_clus == 0U) {
            lba = fs.root_lba + sec; nsec = ((u32)fs.root_ents * 32U + 511U) / 512U;
            if (sec >= nsec) return;
        } else {
            if (clus == 0U) return;
            lba = clus_lba(clus) + (sec % fs.spc);
        }
        if (!sd_read(lba, 1, secbuf)) return;
        for (u32 e = 0; e < 16U; e++) {
            const u8 *d = secbuf + e * 32U;
            u8 attr = d[11];
            if (d[0] == 0x00U) return;                                  /* fin del directorio */
            if (d[0] == 0xE5U || attr == 0x0FU || (attr & 0x18U)) continue;   /* borrada, nombre largo, dir, volumen */
            int is_mp3 = (d[8] == 'M' && d[9] == 'P' && d[10] == '3');
            if (((d[8] == 'W' && d[9] == 'A' && d[10] == 'V') || is_mp3) && n_tracks < MAX_TRACKS) {
                tracks[n_tracks].clus = ((u32)rd16(d + 20) << 16) | rd16(d + 26);
                tracks[n_tracks].size = rd32(d + 28);
                tracks[n_tracks].cfg_clus = 0; tracks[n_tracks].cfg_size = 0;
                tracks[n_tracks].mp3 = (u8)is_mp3;
                n_tracks++;
            }
        }
        sec++;
        if (!(!fs.fat32 && dir_clus == 0U) && (sec % fs.spc) == 0U) clus = fat_next(clus);
    }
}

/* Pausa BLANDA de la lista del menu: vale para WAV y MP3 (un MP3 no se puede reabrir y buscar como hace
 * song_pause con los juegos). El descodificador se queda donde esta; lo escrito y aun no oido sigue en el
 * anillo de la DDR, asi que se publica play=0 con wr = la primera muestra no oida (rd del PL menos lo que
 * tiene en la FIFO): el PL pone ahi su rd y vacia la FIFO. Al seguir se vuelve a publicar el wr de verdad
 * con play=1 y el PL toca desde ese punto: no se pierde ni se repite nada (salvo lo de una ronda del
 * buzon, ~1 ms). */
static void list_pause(void)
{
    u16 rd = (u16)(WG_TEL_HI & 0xFFFFU);
    u32 level = (WG_TEL_LO >> 16) & 0xFFU;
    if (!playing) return;
    pause_wr = wr;
    wr = (u16)(rd - level * 4U);                          /* primera muestra escrita y no oida */
    playing = 0; list_paused = 1;
    wg_publish(0);
    wr = pause_wr;
    log_str("wg: pausa (lista del menu)\n");
}

static void list_resume(void)
{
    if (!list_paused) return;
    list_paused = 0; playing = 1;
    wg_publish(1);                                        /* wr = pause_wr: el PL sigue desde lo no oido */
    log_str("wg: sigue\n");
}

static void wg_stop_list(void)
{
    track_idx = -1; list_dir = 0; list_paused = 0;
    if (playing || paused) song_stop();
    wg_publish(0);
}

static void wg_play_track(int i)
{
    u32 dir = list_dir;
    if (i < 0 || i >= n_tracks) { log_str("wg: fin de la lista\n"); wg_stop_list(); return; }
    list_dir = dir;
    track_idx = i;
    onefile = tracks[i];
    log_str("wg: pista "); log_dec((u32)i + 1U); log_str("/"); log_dec((u32)n_tracks); log_str("\n");
    song_start(101, 0, 0, 0);
}

/* monta la FAT, lista los .WAV de la carpeta y la deja como la de la lista: 0 = no hay nada que tocar */
static int wg_list_load(u32 part, u32 dir)
{
    wg_stop_list();
    if (!fat_mount(part)) { log_str("wg: FAT no montada en LBA "); log_dec(part); log_str("\n"); return 0; }
    track_scan(dir);
    list_dir = dir;
    log_str("wg: "); log_dec((u32)n_tracks); log_str(" pistas (.wav/.mp3) en la carpeta (cluster "); log_dec(dir); log_str(")\n");
    return n_tracks;
}

static void wg_playlist(u32 part, u32 dir, u32 idx)
{
    /* La tecla P del menu es un INTERRUPTOR y el estado vive AQUI, no en el MSX: sobre la misma carpeta
     * que ya suena, 'W','P' PAUSA y el siguiente SIGUE (23/09; antes paraba). Otra carpeta = otra lista. */
    if (track_idx >= 0 && dir == list_dir && idx == 0U) {
        if (list_paused) list_resume(); else list_pause();
        return;
    }
    if (wg_list_load(part, dir)) wg_play_track((int)idx < n_tracks ? (int)idx : 0);
}

/* RETURN sobre un .WAV: la lista de su carpeta, empezando por ESE fichero (se busca por su primer
 * cluster, que es lo que el menu tiene en el registro; si no aparece, desde la primera). */
static void wg_playlist_file(u32 part, u32 dir, u32 fclus)
{
    int i;
    if (!wg_list_load(part, dir)) return;
    for (i = 0; i < n_tracks; i++) if (tracks[i].clus == fclus) break;
    if (i == n_tracks) { log_str("wg: el fichero no esta en la lista, desde la primera\n"); i = 0; }
    wg_play_track(i);
}

static void wg_tone(void)
{
    if (playing || paused) song_stop();
    wg_st = 0;                                            /* el tono es mono */
    wg_publish(0);                                        /* el PL vacia la FIFO y pone rd=wr */
    tone_mode = 1; tone_left = OUT_RATE * 3U / 10U; tone_pos = 0; tone_ph = 0;
    gain_q23 = 32768 << 8; gain_step = 0; stop_at_zero = 0; produced = 0; cur_idx = -1; paused = 0;
    usleep(2500);
    for (u32 k = 0; k < LOOKAHEAD / 64U; k++) if (!produce_block()) break;
    playing = 1;
    wg_publish(1);
}

static void song_pause(void)
{
    u16 rd = (u16)(WG_TEL_HI & 0xFFFFU);
    u32 level = (WG_TEL_LO >> 16) & 0xFFU;
    u32 unheard = (u16)(wr - rd) + level * 4U;            /* muestras de salida escritas pero no oidas */
    u32 back = (unheard * cur.rate) / OUT_RATE;           /* en muestras de entrada */
    if (!playing) return;
    paused = 1; playing = 0;
    prev.idx = cur_idx; prev.loop = cur_loop; prev.valid = 1;
    prev.pos_smp = (cur.pos_smp > back) ? cur.pos_smp - back : 0;
    wg_publish(0);
    log_str("wg: pausa\n");
}

static void wg_cmd(u8 b)
{
    if (defer_next && playing && !cur_loop && !(b == 0xC0U)) {   /* la proxima orden espera al final */
        deferred = b; defer_next = 0; log_str("wg: orden diferida "); log_hex(b); log_str("\n"); return;
    }
    defer_next = 0;
    if ((b & 0xC0U) == 0x40U || (b & 0xC0U) == 0x80U) {   /* tocar xx (una vez / bucle) */
        int n = b & 0x3FU;
        if (mounted && (have_song[n] & 1)) song_start(n, (b & 0x80U) != 0, 0, 0);
        else { log_str("wg: no hay "); log_dec((u32)n); log_str(".wav\n"); }
    } else if ((b & 0xF0U) == 0x00U) {                    /* fade-out de x s */
        u32 secs = (b & 0x0FU) ? (b & 0x0FU) : 1U;
        if (playing) { gain_step = -((32768 << 8) / (s32)(secs * OUT_RATE)); if (gain_step == 0) gain_step = -1; stop_at_zero = 1; }
    } else switch (b) {
        case 0xC0U:                                       /* pausa / continua */
            if (playing) song_pause();
            else if (paused && prev.valid) { paused = 0; song_start(prev.idx, prev.loop, prev.pos_smp, 0); }
            break;
        case 0xD0U: defer_next = 1; break;
        case 0xE0U:                                       /* retoma la anterior con fade-in de 1 s */
            if (prev.valid) song_start(prev.idx, prev.loop, prev.pos_smp, 1);
            break;
        case 0xF0U:                                       /* pause.wav */
            if (mounted && have_pause) song_start(100, 0, 0, 0);
            break;
        default: log_str("wg: orden desconocida "); log_hex(b); log_str("\n"); break;
    }
}

/* ------------------------------------------------------------------ mensaje del menu (47h) */
static u8  msg[16]; static u32 msg_n = 0;

/* ---- Z1.1 cinta virtual (tape.c): el fichero .tsx/.cas de la SD por su primer cluster ---- */
/* nombre del fichero cuyo primer cluster es `file` en la carpeta `dir` (perfiles_ext.c: la etiqueta [P:ID] de una ROM): el LARGO (entradas
 * LFN que preceden a la corta, 13 caracteres UCS-2 cada una; solo ASCII, el resto sale '?') si su suma de comprobacion cuadra con la
 * entrada corta, y si no el 8.3 ("NOMBRE.EXT"). 1 = encontrado.
 * No molesta a la musica del menu: lee con un sector propio (nbuf, no secbuf, donde un WAV o un MP3 sonando guarda el suyo) y, si la
 * particion pedida no es la montada, monta la otra y deja `fs` como estaba. Se llama con CADA ROM que se lanza ('W','Q'). */
static u8 nbuf[512] __attribute__((aligned(32)));
static u32 fat_ult_tam;                                                /* tamano del fichero de la ultima busqueda (dual.c: la ROM que va a B) */
static int fat_nombre_(u32 dir_clus, u32 file, char *out, u32 cap)
{
    static const u8 off[13] = { 1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30 };
    char lfn[13 * 21 + 1];
    u32 lba, nsec, sec = 0, clus = dir_clus, e, i, k;
    int lfn_ok = 0;
    u8 lfn_ck = 0;
    for (;;) {
        if (!fs.fat32 && dir_clus == 0U) { lba = fs.root_lba + sec; nsec = ((u32)fs.root_ents * 32U + 511U) / 512U; if (sec >= nsec) return 0; }
        else {
            if (clus == 0U) return 0;
            if (fs.fat32 && dir_clus == 0U) { clus = fs.root_clus; dir_clus = clus; }
            lba = clus_lba(clus) + (sec % fs.spc);
        }
        sd_ceder();                                                   /* una carpeta grande son muchos sectores: que el MSX no espere los 2 s del proxy */
        if (!sd_read(lba, 1, nbuf)) return 0;
        for (e = 0; e < 16U; e++) {
            const u8 *d = nbuf + e * 32U;
            u8 attr = d[11];
            if (d[0] == 0x00U) return 0;
            if (d[0] == 0xE5U) { lfn_ok = 0; continue; }
            if (attr == 0x0FU) {                                       /* entrada LFN: la ultima del nombre va primero */
                u32 ord = d[0] & 0x1FU;
                if (d[0] & 0x40U) { for (i = 0; i < sizeof lfn; i++) lfn[i] = 0; lfn_ok = (ord >= 1U && ord <= 20U); lfn_ck = d[13]; }
                else if (!lfn_ok || d[13] != lfn_ck || ord < 1U || ord > 20U) lfn_ok = 0;
                if (lfn_ok)
                    for (k = 0; k < 13U; k++) {
                        u32 lo = d[off[k]], hi = d[off[k] + 1U];
                        lfn[(ord - 1U) * 13U + k] = (hi == 0U && lo >= 0x20U && lo < 0x7FU) ? (char)lo : (hi == 0U && lo == 0U) ? 0 : (hi == 0xFFU && lo == 0xFFU) ? 0 : '?';
                    }
                continue;
            }
            if (attr & 0x18U) { lfn_ok = 0; continue; }
            if ((((u32)rd16(d + 20) << 16) | rd16(d + 26)) == file) {
                u8 s = 0;
                fat_ult_tam = rd32(d + 28);
                for (i = 0; i < 11U; i++) s = (u8)((((s & 1U) ? 0x80U : 0U) + (s >> 1)) + d[i]);
                if (lfn_ok && s == lfn_ck && lfn[0]) {
                    for (i = 0; i + 1U < cap && lfn[i]; i++) out[i] = lfn[i];
                    out[i] = 0;
                } else {
                    u32 n = 0, m = 8;
                    while (m && d[m - 1U] == ' ') m--;
                    for (i = 0; i < m; i++) out[n++] = (char)d[i];
                    m = 3;
                    while (m && d[8U + m - 1U] == ' ') m--;
                    if (m) { out[n++] = '.'; for (i = 0; i < m; i++) out[n++] = (char)d[8U + i]; }
                    out[n] = 0;
                }
                return 1;
            }
            lfn_ok = 0;
        }
        sec++;
        if (!(!fs.fat32 && dir_clus == 0U) && (sec % fs.spc) == 0U) clus = fat_next(clus);
    }
}

u32 fat_nombre_tam(void) { return fat_ult_tam; }                       /* tras un fat_nombre que devolvio 1 */
static u32 wg_part_ult;                                                /* PART_LBA del ultimo 'W','G' */
u32 wg_part_lanzada(void) { return wg_part_ult; }

/* Los rangos de sectores de la cadena de clusters de un fichero (dual.c: los .SRM de la partida, a los que A conserva la escritura cuando B tiene la SD).
 * `nbytes` bytes desde el cluster `first` de la particion `part` (FAT16: los descriptores del menu llevan clusters de 16 bits); los clusters
 * contiguos se unen en un solo rango. Devuelve cuantos rangos (lo[i], n[i] en sectores) hay en lo/n, o -1 si no es FAT16, la cadena se acaba antes de
 * tiempo, se sale de la tarjeta o no caben en `max`. Usa los buffers propios (nbuf y fatbuf) y deja la FAT montada como estaba */
int fat_extents(u32 part, u32 first, u32 nbytes, u32 *lo, u32 *n, int max)
{
    __typeof__(fs) viejo = fs;
    int montada = fs.ok && fs.part_lba == part, k = 0;
    u32 clus = first, restan = (nbytes + 511U) / 512U;
    if (!montada && !fat_mount_buf(part, nbuf)) { fs = viejo; fatbuf_lba = 0xFFFFFFFFU; return -1; }
    if (fs.fat32 || first < 2U) k = -1;
    while (k >= 0 && restan) {
        u32 l = clus_lba(clus), c = fs.spc < restan ? (u32)fs.spc : restan;
        if (k && lo[k - 1] + n[k - 1] == l) n[k - 1] += c;
        else if (k == max) k = -1;
        else { lo[k] = l; n[k] = c; k++; }
        if (k < 0) break;
        restan -= c;
        if (restan) {
            clus = fat_next(clus);
            if (!clus) k = -1;                                         /* la cadena acaba antes de lo que dice el tamano */
        }
    }
    if (!montada) fs = viejo;
    fatbuf_lba = 0xFFFFFFFFU;                                          /* el sector de FAT en cache puede dejar de ser el vigente: otra lectura */
    return k;
}

int fat_nombre(u32 part, u32 dir_clus, u32 file, char *out, u32 cap)
{
    __typeof__(fs) viejo = fs;
    int montada = fs.ok && fs.part_lba == part, r;
    if (cap < 14U) return 0;
    if (!montada && !fat_mount_buf(part, nbuf)) { fs = viejo; fatbuf_lba = 0xFFFFFFFFU; return 0; }
    r = fat_nombre_(dir_clus, file, out, cap);
    if (!montada) { fs = viejo; fatbuf_lba = 0xFFFFFFFFU; }
    return r;
}

extern void tape_start(u32 part, u32 dir, u32 file);
extern void tape_stop(void);
int tape_fat_locate(u32 part, u32 dir_clus, u32 file, u32 *size, char *ext3)
{
    u32 lba, nsec, sec = 0, clus = dir_clus;
    if (!fat_mount(part)) return 0;
    for (;;) {
        if (!fs.fat32 && dir_clus == 0U) { lba = fs.root_lba + sec; nsec = ((u32)fs.root_ents * 32U + 511U) / 512U; if (sec >= nsec) return 0; }
        else {
            if (clus == 0U) return 0;
            if (fs.fat32 && dir_clus == 0U) { clus = fs.root_clus; dir_clus = clus; }
            lba = clus_lba(clus) + (sec % fs.spc);
        }
        if (!sd_read(lba, 1, secbuf)) return 0;
        for (u32 e = 0; e < 16U; e++) {
            const u8 *d = secbuf + e * 32U;
            u8 attr = d[11];
            if (d[0] == 0x00U) return 0;
            if (d[0] == 0xE5U || attr == 0x0FU || (attr & 0x18U)) continue;
            if ((((u32)rd16(d + 20) << 16) | rd16(d + 26)) == file) {
                *size = rd32(d + 28); ext3[0] = (char)d[8]; ext3[1] = (char)d[9]; ext3[2] = (char)d[10];
                return 1;
            }
        }
        sec++;
        if (!(!fs.fat32 && dir_clus == 0U) && (sec % fs.spc) == 0U) clus = fat_next(clus);
    }
}
int tape_file_read(u32 first, u32 size, u32 pos, u8 *dst, u32 n)
{
    static wfile f; static u32 f_first = 0xFFFFFFFFU, f_size = 0;
    if (f_first != first || f_size != size) { wf_open(&f, first, size); f_first = first; f_size = size; }
    if (f.pos != pos) wf_seek(&f, pos);
    return wf_read(&f, dst, n) == n;
}

extern void v99desk_inicio(u8 lay, const char *rom);      /* v99desk.c (rama beta) */
extern void tape_nextor(int con);                          /* tape.c (rama beta): bit 28, sin Nextor */
static void wg_msg_byte(u8 b)
{
    static u8 v_lay, v_n;                                               /* rama beta: 'V','5'/'7' + nombre de la ROM + 0 */
    static char v_nom[25];
    if (v_lay) {
        if (b != 0 && v_n < 24U) { v_nom[v_n++] = (char)b; return; }
        v_nom[v_n] = 0; v99desk_inicio(v_lay, v_nom); v_lay = 0; v_n = 0;
        if (b != 0) return;
        return;
    }
    if (msg_n == 0 && b != 'W' && b != 'T' && b != 'V' && b != 'N') return;
    if (msg_n == 1 && msg[0] == 'N') {                                  /* 'N','X' sin Nextor / 'N','N' con Nextor (rama beta) */
        msg_n = 0;
        if (b == 'X') tape_nextor(0); else if (b == 'N') tape_nextor(1);
        return;
    }
    if (msg_n == 1 && msg[0] == 'V') {                                  /* escritorio del V9990 pintado: el nombre llega detras */
        msg_n = 0;
        if (b == '5' || b == '7') { v_lay = (u8)(b - '0'); v_n = 0; }
        else if (b == 'D') { v_lay = 9; v_n = 0; }                      /* perfil Dual: el escritorio de dos columnas con la ROM en B (Shift+D del menu) */
        else if (b == 'A') { v_lay = 10; v_n = 0; }                     /* Z1.3.2b8: el mismo escritorio con la ROM en A y B de segunda maquina (D sola) */
        return;
    }
    if (msg_n == 1 && msg[0] == 'T') {                                  /* 'T','S' + clusters = cinta; 'T','X' = parar */
        if (b == 'X') { msg_n = 0; tape_stop(); return; }
        if (b != 'S') { msg_n = 0; return; }
    }
    if (msg_n == 1 && msg[0] == 'W' && b == 'T') { msg_n = 0; wg_tone(); return; }   /* 'W','T' = nota de prueba del mezclador */
    if (msg_n == 1 && msg[0] == 'W' && b == 'X') { msg_n = 0; wg_stop_list(); return; }        /* parar la musica */
    if (msg_n == 1 && msg[0] == 'W' && b == 'N') {                                            /* pista siguiente */
        msg_n = 0;
        if (track_idx >= 0) wg_play_track(track_idx + 1);
        return;
    }
    if (msg_n == 1 && msg[0] == 'W' && b != 'G' && b != 'P' && b != 'F' && b != 'I' && b != 'Q' && (b < '0' || b > '9')) { msg_n = 0; return; }
    msg[msg_n++] = b;
    if (msg_n == 14) {
        u32 part = rd32(msg + 2), dir = rd32(msg + 6), file = rd32(msg + 10);
        if (msg[0] == 'W' && msg[1] == 'G') wg_part_ult = part;         /* la ROM que se lanza: su particion es la de FHUNT y la de sus .SRM (dual.c los necesita) */
        if (msg[0] == 'T') { msg_n = 0; tape_start(part, dir, file); return; }
        if (msg[1] >= '0' && msg[1] <= '9') { msg_n = 0; dual_pide((u8)(msg[1] - '0'), part, dir, file); return; }   /* perfil Dual (dual.c): 'W', '0'+MAPPER_ID = esta ROM a la maquina B */
        if (msg[1] == 'P') { msg_n = 0; wg_playlist(part, dir, file); return; }   /* musica del menu (file = pista) */
        if (msg[1] == 'F') { msg_n = 0; wg_playlist_file(part, dir, file); return; }   /* RETURN sobre un .WAV (file = cluster) */
        if (msg[1] == 'I') { msg_n = 0; pext_pide_instalar(part, dir, file); return; }   /* RETURN sobre un .MXP: instalar el perfil (perfiles_ext.c) */
        if (msg[1] == 'Q') { msg_n = 0; pext_pide_etiqueta(part, dir, file); return; }   /* RETURN sobre una ROM, antes de cargarla: perfil de su etiqueta */
        int n = 0;
        msg_n = 0;
        pext_pide_etiqueta(part, dir, file);              /* 'W','G' = lanzar la ROM: la misma comprobacion de la etiqueta [P:ID] (perfiles_ext.c) */
        mounted = 0;
        track_idx = -1;                                   /* lanzar una ROM corta la lista del menu */
        if (playing || paused) song_stop();
        if (!fat_mount(part)) { log_str("wg: FAT no montada en LBA "); log_dec(part); log_str("\n"); return; }
        dir_scan(dir);
        for (int i = 0; i < MAX_SONGS; i++) if (have_song[i] & 1) n++;
        mounted = (n > 0);
        log_str("wg: ROM cluster "); log_dec(file); log_str(" en dir "); log_dec(dir); log_str(fs.fat32 ? " (FAT32): " : " (FAT16): ");
        log_dec((u32)n); log_str(" wav"); log_str(have_pause ? " + pause.wav\n" : "\n");
    }
}

/* ------------------------------------------------------------------ bucle */
static u8  z2a_rd = 0; static int z2a_init = 0;
static u32 inj_seq = 0;

/* perfiles_ext.c: tras cargar un perfil por PCAP el anillo Z80 -> ARM del PL nuevo empieza en 0 (y puede venir con restos de la
 * ronda anterior): wg_poll lo vuelve a sincronizar con la primera lectura */
void wg_pl_rearma(void) { z2a_init = 0; msg_n = 0; }

void wg_poll(void)
{
    u8 wi = (u8)(WG_TEL_HI >> 24);
    u32 inj = WG_INJ;
    static u32 last_seq;
    u32 seq = REG(MBOX + 0x44U);                           /* secuencia de rondas del buzon: si baja, el PL se ha reprogramado */
    if (!z2a_init) { z2a_rd = wi; z2a_init = 1; inj_seq = inj >> 24; }
    else if (seq < last_seq && z2a_rd != wi) {              /* 18/09: por JTAG el PL viejo dejaba wi=14 en +0xBC antes de reprogramarse
                                                              * y el companion se sincronizaba con el; el PL nuevo vuelve a 0 y el
                                                              * mensaje del menu ('T','S'...) llegaba justo a wi=14 = ignorado */
        log_str("wg: PL reprogramado, resincronizo el anillo\n"); z2a_rd = wi;
    }
    last_seq = seq;
    if ((u8)(wi - z2a_rd) > 32U) {                           /* el anillo dio la vuelta (mas de 32 bytes entre dos lecturas): lo mas
                                                              * viejo ya esta pisado; se leen las 32 ultimas y se rearma el mensaje */
        log_str("wg: anillo Z80->ARM desbordado, "); log_dec((u8)(wi - z2a_rd) - 32U); log_str(" perdidos\n");
        z2a_rd = (u8)(wi - 32U);
        msg_n = 0;
    }
    while (z2a_rd != wi) {
        u16 e = Z2A_RING[z2a_rd & 31U];
        u8 tag = (u8)(e >> 8), dat = (u8)e;
        z2a_rd++;
        if (tag == 0x92U) wg_cmd(dat); else if (tag == 0x93U) wg_msg_byte(dat);
    }
    if ((inj >> 24) != inj_seq) {                          /* inyeccion desde xsdb */
        inj_seq = inj >> 24;
        if (((inj >> 8) & 0xFFU) == 0x92U) wg_cmd((u8)inj); else if (((inj >> 8) & 0xFFU) == 0x93U) wg_msg_byte((u8)inj);
        else if (((inj >> 8) & 0xFFU) == 0x3CU) gain_master = (s32)((inj & 0xFFU) << 7);    /* volumen 0..255 -> Q15 */
        else if (((inj >> 8) & 0xFFU) == 0x3DU) { gain_shift = inj & 3U; wg_publish(playing); }  /* x1/x2/x4/x8 */
        else if (((inj >> 8) & 0xFFU) == 0x3EU) { wid_q15 = (s32)((inj & 0xFFU) << 7); log_str("wg: anchura "); log_dec(inj & 0xFFU); log_str("/255\n"); }   /* 28/09: ensanchado */
    }
    if (playing) {
        u16 rd = (u16)(WG_TEL_HI & 0xFFFFU);
        int blocks = 0;
        u32 blk = wg_st ? 128U : 64U, look = wg_st ? 2U * LOOKAHEAD : LOOKAHEAD;   /* 23/09: estereo */
        while ((u16)(wr - rd) + blk <= look && blocks < 24) {
            blocks++;
            if (!produce_block()) {                       /* fin de la cancion (o fade completado) */
                int d = deferred;
                wg_publish(1);
                log_str("wg: fin\n");
                mp3_log_stats();
                playing = 0; cur_idx = -1; gain_step = 0; stop_at_zero = 0;
                deferred = -1;
                if (d >= 0) wg_cmd((u8)d);
                else if (track_idx >= 0) wg_play_track(track_idx + 1);   /* lista del menu: siguiente pista */
                return;
            }
        }
        if (blocks) wg_publish(1);
    }
}

/* profile.c (PCAP, 30/10): el PL va a recargarse. Todo parado y el puntero del anillo a 0: el PL nuevo nace con rd = 0 y
 * play = 0 (con play = 0 su rd sigue a wr), asi que la primera cancion empieza limpia en vez de tocar 0..wr de lo viejo. */
void wg_pl_parar(void)
{
    wg_stop_list();
    tone_mode = 0;
    wr = 0;
    wg_publish(0);
}
