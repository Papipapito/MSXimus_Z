/* mp3.c — fuente MP3 de la musica del menu sobre minimp3 (lieff, CC0; arm/get_minimp3.sh).
 *
 * Se compila con la FPU (-mfloat-abi=softfp -mfpu=neon): minimp3 es coma flotante y, medido en esta placa
 * (23/09, banco en el core 1), una trama de 320 kbps estereo tarda 446 us con NEON y cache = 1,7 % de CPU,
 * 8,8 ms en coma flotante por software. softfp mantiene la convencion de llamada de soft-float: se enlaza
 * con el resto del companion (soft) y con la newlib de siempre sin tocarlos.
 *
 * 🚨 minimp3 NECESITA MEMORIA NORMAL (MMU encendida): el memcpy de newlib hace lecturas desalineadas, que en
 * memoria strongly-ordered (la del companion sin MMU) son DATA ABORT. Por eso todo su estado va en la
 * seccion .mp3 (buffer de entrada, PCM, decodificador) y el enlazador la pone en la zona con cache.
 *
 * Reglas de minimp3 que mandan aqui:
 *  - para engancharse busca la cabecera de la trama SIGUIENTE: el buffer de entrada va casi lleno (16 KB);
 *  - frame_bytes = bytes a saltar; con 0 muestras es basura o una trama incompleta (hay que recargar);
 *  - una trama son 1152 muestras (576 en MPEG-2/2.5) = 26 ms a 44,1 kHz: se descodifica UNA cada vez que
 *    se acaban las muestras, nunca en rafaga, para no quitarle tiempo al proxy de la SD (plazo de 2 s). */
#define MINIMP3_IMPLEMENTATION
#define MINIMP3_ONLY_MP3
#include "minimp3.h"
#include "mp3.h"

#define IBUF      16384U
#define REFILL_AT (IBUF / 2U)                /* recargar cuando queden menos de 8 KB */

#define MP3SEC __attribute__((section(".mp3")))
static u8            ibuf[IBUF] MP3SEC __attribute__((aligned(32)));
static mp3d_sample_t pcm[MINIMP3_MAX_SAMPLES_PER_FRAME] MP3SEC __attribute__((aligned(32)));
static mp3dec_t      dec MP3SEC;
static mp3dec_frame_info_t info MP3SEC;
static u8            dstack[32768] MP3SEC __attribute__((aligned(16)));   /* pila del descodificador */


static mp3_read_fn rdfn;
static void *rdctx;
static u32 ib_n, ib_pos;                     /* bytes validos y posicion de lectura en ibuf */
static int eof;
static int pcm_n, pcm_i, pcm_ch;             /* muestras (por canal) de la trama en curso */
static u32 st_frames, st_max, st_sum;

extern int call_on_stack(void *arg, int (*fn)(void *), void *sp_top);   /* start.S */
static int dec_frame(void *a)                /* corre sobre dstack: su scratch de ~16 KB y sus memcpy en memoria normal */
{
    (void)a;
    return mp3dec_decode_frame(&dec, ibuf + ib_pos, (int)(ib_n - ib_pos), pcm, &info);
}

static void refill(void)
{
    u32 keep = ib_n - ib_pos, got;
    if (eof || keep >= REFILL_AT) return;
    for (u32 i = 0; i < keep; i++) ibuf[i] = ibuf[ib_pos + i];    /* sin memmove: ibuf es memoria normal, pero asi no depende */
    ib_n = keep; ib_pos = 0;
    got = rdfn(rdctx, ibuf + ib_n, IBUF - ib_n);
    ib_n += got;
    if (got < IBUF - keep) eof = 1;
}

/* descodifica la siguiente trama con audio; 0 = fin del fichero (o basura hasta el final) */
static int decode_one(void)
{
    for (int tries = 0; tries < 64; tries++) {
        u32 avail, t0, dt;
        int n;
        refill();
        avail = ib_n - ib_pos;
        if (avail == 0U) return 0;
        t0 = mp3_now();
        n = call_on_stack(0, dec_frame, dstack + sizeof dstack);
        dt = mp3_now() - t0;
        if (info.frame_bytes == 0) {                     /* trama incompleta al principio del buffer */
            if (eof) return 0;
            if (avail >= REFILL_AT) return 0;            /* con 8 KB y sin trama entera: basura */
            continue;                                    /* si no, recargar y volver a probar */
        }
        ib_pos += (u32)info.frame_bytes;
        if (n > 0) {
            pcm_n = n; pcm_i = 0; pcm_ch = info.channels;
            st_frames++; st_sum += dt; if (dt > st_max) st_max = dt;
            return 1;
        }
        /* 0 muestras con bytes saltados: basura, etiqueta o trama sin audio -> seguir */
    }
    return 0;
}

int mp3_open(mp3_read_fn rd, void *ctx, u32 *hz, u32 *ch)
{
    rdfn = rd; rdctx = ctx;
    ib_n = ib_pos = 0; eof = 0;
    pcm_n = pcm_i = 0; pcm_ch = 1;
    st_frames = st_max = st_sum = 0;
    mp3dec_init(&dec);
    if (!decode_one()) return 0;                         /* la 1a trama se queda en pcm: no se pierde */
    *hz = (u32)info.hz; *ch = (u32)info.channels;
    return 1;
}

int mp3_next2(s32 *l, s32 *r)                /* 23/09 (fase 7c): los dos canales tal cual */
{
    while (pcm_i >= pcm_n) if (!decode_one()) return 0;
    if (pcm_ch == 2) { *l = pcm[2 * pcm_i]; *r = pcm[2 * pcm_i + 1]; }
    else             { *l = pcm[pcm_i];     *r = *l; }
    pcm_i++;
    return 1;
}

int mp3_next(s32 *out)
{
    s32 l, r;
    if (!mp3_next2(&l, &r)) return 0;
    *out = (l + r) / 2;
    return 1;
}

void mp3_stats(u32 *frames, u32 *t_max, u32 *t_sum) { *frames = st_frames; *t_max = st_max; *t_sum = st_sum; }
