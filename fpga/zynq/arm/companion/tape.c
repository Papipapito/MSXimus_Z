/* tape.c — CINTA VIRTUAL del MSXimus Z (Z1.1, 18/09/2026).
 *
 * El menu lanza un .tsx o .cas de la SD de TF2 mandando por el puerto 93h 'T','S' + LBA de la particion (4) +
 * cluster de la carpeta (4) + cluster del fichero (4) (wavegame.c recoge el mensaje y llama a tape_start).
 * Aqui se carga el fichero entero en la DDR (TAPE_BUF), se convierte bloque a bloque en PULSOS {nivel, ciclos
 * de 54 MHz} y se van escribiendo en el anillo TP_RING (MBOX+0xA0000, 16384 entradas de 32 bits) por delante
 * del lector del PL (dbg_mailbox_axi: control +0x28 {play, monitor, sin_motor, wr}, telemetria +0xC8 rd).
 * El PL solo hace avanzar la cinta con el motor del casete en marcha (PPI PC4 = 0): como una cinta de verdad,
 * la BIOS la para y la arranca entre bloques y la reproduccion siempre empieza por el principio del bloque.
 *
 * Formatos: TSX (bloques 10, 11, 12, 13, 14, 15, 20, 21, 22, 30, 32, 35, 4B y 5A, semantica de openMSX
 * TsxParser.cc: T-states a 3,5 MHz) y CAS (sincronismo 1F A6 DE BA CC 13 7D 74; cabeceras EA/D0/D3 con piloto
 * largo, datos con piloto corto; 1200 baudios: cero = 2 pulsos de 1463 T, uno = 4 pulsos de 731 T, start 0 +
 * 8 bits LSB + 2 stop 1; validado en placa en el MSXnano).
 *
 * BASIC LIMPIO: al recibir la cinta se pide al PL "sin Nextor" (bit 28 del control): el slot 3-2 desaparece y el
 * MSX arranca con toda la RAM, como uno sin disco (Nextor 2.1 no se salta con SHIFT ni config2 bit 0 vale en
 * caliente: probado 18/09). "Manos" (auto-teclado por el bitmap HID del buzon): al aparecer "Ok" en la pantalla
 * (SCRMOD/NAMBAS de las variables del sistema + tabla de nombres, todo en la DDR) se teclea la orden de carga que
 * pide la primera cabecera: RUN"CAS:" (ASCII), BLOAD"CAS:",R (binario) o CLOAD + RUN (BASIC tokenizado); sin
 * cabecera reconocible, RUN"CAS:". Tiempos con el temporizador global (por JTAG el bucle gira 100x mas rapido).
 * tools/tape.tcl lo maneja desde xsdb.
 */
#ifdef TAPE_HOST                                  /* banco en el PC (host_tape_test.c): registros y anillo en arrays */
#include <stdint.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64; typedef int32_t s32;
extern u32 host_ctl, host_tel, host_tel2, host_ring[16384]; extern u8 host_buf[1024 * 1024], host_vram[4096];
#define TP_CTL      host_ctl
#define TP_TEL      host_tel
#define TP_TEL2     host_tel2
#define TP_RING     host_ring
#define TAPE_BUF    host_buf
#define VRAM        host_vram
#define TAPE_DSB()  ((void)0)
#else
#include "xil_types.h"
#define REG(a)      (*(volatile u32 *)(a))
#define MBOX        0x1FF00000U
#define TP_CTL      REG(MBOX + 0x28U)
#define TP_TEL      REG(MBOX + 0xC8U)             /* {rd[31:16], 2'b0, flevel[13:8], unr[7:0]} */
#define TP_TEL2     REG(MBOX + 0xCCU)             /* {fetches[31:24], 20'd0, sin_motor, motor, nivel, play} */
#define TP_RING     ((volatile u32 *)(MBOX + 0xA0000U))
#define TAPE_BUF    ((u8 *)0x1FE00000U)           /* el fichero entero (max 1 MB) */
#define VRAM        ((volatile u8 *)0x10280000U)  /* pantalla de texto del V9968 (tabla de nombres en 0) */
#define TAPE_DSB()  __asm__ volatile ("dsb" ::: "memory")
#endif
#define RING_MASK   16383U
#define LOOKAHEAD   8192U                         /* entradas por delante del PL (media vuelta del anillo) */
#define TAPE_MAX    (1024U * 1024U)

extern void log_str(const char *s);
extern void log_hex(u32 v);
extern void log_dec(u32 v);
extern int  tape_fat_locate(u32 part, u32 dir, u32 file, u32 *size, char *ext3);   /* wavegame.c */
extern int  tape_file_read(u32 first, u32 size, u32 pos, u8 *dst, u32 n);          /* wavegame.c */
extern void kbd_synth_set(const u32 b[4]);                                          /* usb_host.c */
#ifdef TAPE_HOST
extern u32 host_ms;
#define TAPE_MS() host_ms
#else
extern u32 tusb_time_millis_api(void);                                              /* bsp/support.c: ms reales del temporizador global */
#define TAPE_MS() tusb_time_millis_api()                                          /* (TAPE_MS() del bucle NO vale: bajo JTAG el WFI es un NOP y gira 100x mas rapido) */
#endif

/* ---------------------------------------------------------------- estado */
static u8  *tp;                 /* fichero en la DDR */
static u32  tp_len;
static int  is_cas;
static int  playing, eof_gen;
static u16  wr;                 /* entradas escritas al anillo (mod 65536) */
static u32  pad_n;              /* entradas de relleno {1,1} al final (hasta la rafaga de 32) */
static u32  n_pulses, n_blocks;
static u32  ctl_flags;          /* monitor / sin_motor (bits 30/29) */
static int  cur_level = 1;      /* nivel del proximo pulso al alternar */

/* generador: un bloque en curso */
static struct {
    int   active;               /* hay bloque a medias */
    int   phase;                /* 0 piloto, 1 sync1, 2 sync2, 3 datos, 4 pausa, 5 fin */
    u32   off, end;             /* datos del bloque en tp[] */
    u32   pilot_t, pilot_n;     /* piloto: duracion y numero de pulsos */
    u32   sync1, sync2;
    u32   zero_t, one_t;        /* duraciones (T) */
    u32   nzero, none;          /* pulsos por bit */
    u32   nstart, nstop;        /* KCS: bits de arranque/parada */
    u32   startv, stopv, msb;
    u32   lastbits;             /* bits utiles del ultimo byte (bloques Spectrum) */
    u32   pause_ms;
    u32   i, bitn, sub;         /* byte, bit dentro del byte (incluye start/stop), pulso dentro del bit */
    u32   pilot_i, cnt;
    int   direct;               /* bloque 15: nivel explicito por muestra */
    u32   bit_t;
} g;
static u32 blk_off;             /* proximo bloque a abrir en tp[] */

/* ---------------------------------------------------------------- teclado automatico */
static int  keys_phase;         /* 0 nada, 1 SHIFT pulsado, 2 esperando Ok, 3 tecleando, 4 esperando 2o Ok, 5 tecleando RUN, 6 fin */
static u32  keys_t0;
static const char *keys_str;
static u32  keys_i, keys_sub;
static u32  ok_count;
static int  load_kind;          /* 0 ascii RUN"CAS:", 1 binario BLOAD"CAS:",R, 2 basic CLOAD+RUN (por la cabecera) */
static char load_cmd[48];       /* Z1.2: la orden que se teclea al ver Ok (acaba en RETURN) */
static char load_cmd2[24];      /* Z1.2: segunda orden tras el 2o Ok ("CLOAD + RUN" de la ficha, o RUN tras CLOAD/LOAD"CAS:") */
static int  load_run_after;     /* 1 = hay segunda orden (load_cmd2) */
static int  load_from_tsx;      /* 1 = la orden viene del bloque 35 TSX.LOAD del propio TSX (la ficha de tsx.eslamejor) */

static u32 t2cyc(u32 t) { return (u32)(((u64)t * 108U + 3U) / 7U); }   /* T-states (3,5 MHz) -> ciclos de 54 MHz */
static u32 ms2cyc(u32 ms) { return ms * 54000U; }

/* ---------------------------------------------------------------- anillo */
static void publish(int play) { TP_CTL = ((u32)play << 31) | ctl_flags | wr; TAPE_DSB(); }
static void ring_put(int level, u32 cyc)
{
    while (cyc > 0x7FFFFFFFU) { TP_RING[wr & RING_MASK] = ((u32)level << 31) | 0x7FFFFFFFU; wr++; cyc -= 0x7FFFFFFFU; }
    if (cyc == 0U) cyc = 1U;
    TP_RING[wr & RING_MASK] = ((u32)level << 31) | cyc;
    wr++; n_pulses++;
}
static void pulse(u32 t)     { ring_put(cur_level, t2cyc(t)); cur_level ^= 1; }   /* un semiperiodo y cambio de nivel */
static void silence(u32 ms)  { if (ms) { ring_put(0, ms2cyc(ms)); cur_level = 1; } }

/* ---------------------------------------------------------------- lectura del fichero */
static u16 rd16(const u8 *p) { return (u16)(p[0] | (p[1] << 8)); }
static u32 rd24(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16); }
static u32 rd32(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24); }
static const u8 CAS_SYNC[8] = {0x1F, 0xA6, 0xDE, 0xBA, 0xCC, 0x13, 0x7D, 0x74};
static int cas_sync_at(u32 o) { if (o + 8U > tp_len) return 0; for (int i = 0; i < 8; i++) if (tp[o + i] != CAS_SYNC[i]) return 0; return 1; }
static int is_hdr16(const u8 *d, u8 v) { for (int i = 0; i < 10; i++) if (d[i] != v) return 0; return 1; }

/* ---------------------------------------------------------------- abrir el siguiente bloque */
static void g_kcs_defaults(void)
{
    g.pilot_t = 731U; g.zero_t = 1463U; g.one_t = 731U; g.nzero = 2U; g.none = 4U;
    g.nstart = 1U; g.startv = 0U; g.nstop = 2U; g.stopv = 1U; g.msb = 0U; g.lastbits = 8U; g.direct = 0;
    g.sync1 = g.sync2 = 0U; g.pause_ms = 0U;
}
static void g_begin_data(void) { g.i = 0; g.bitn = 0; g.sub = 0; g.phase = (g.pilot_n ? 0 : (g.sync1 ? 1 : 3)); g.pilot_i = 0; g.active = 1; }

/* devuelve 1 si ha abierto un bloque con pulsos; 0 = fin de cinta */
static int open_next_block(void)
{
    while (blk_off < tp_len) {
        if (is_cas) {
            if (!cas_sync_at(blk_off)) { blk_off++; continue; }
            u32 o = blk_off + 8U, e = o;
            while (e < tp_len && !cas_sync_at(e)) e++;
            g_kcs_defaults();
            g.off = o; g.end = e; blk_off = e;
            g.pilot_n = ((e - o) == 16U && (is_hdr16(tp + o, 0xEA) || is_hdr16(tp + o, 0xD0) || is_hdr16(tp + o, 0xD3))) ? 8000U : 3000U;
            g.pause_ms = 1000U;
            n_blocks++; g_begin_data();
            return 1;
        }
        u8 id = tp[blk_off];
        u32 o = blk_off + 1U;
        switch (id) {
        case 0x10: {                                         /* standard speed (Spectrum) */
            g_kcs_defaults(); g.pause_ms = rd16(tp + o); u32 ln = rd16(tp + o + 2);
            g.pilot_t = 2168U; g.sync1 = 667U; g.sync2 = 735U; g.zero_t = 855U; g.one_t = 1710U; g.nzero = g.none = 2U;
            g.nstart = g.nstop = 0U; g.msb = 1U; g.pilot_n = (ln && tp[o + 4] < 128U) ? 8063U : 3223U;
            g.off = o + 4U; g.end = g.off + ln; blk_off = g.end; cur_level = 0;
            if (!ln) continue; n_blocks++; g_begin_data(); return 1; }
        case 0x11: {                                         /* turbo speed */
            g_kcs_defaults();
            g.pilot_t = rd16(tp + o); g.sync1 = rd16(tp + o + 2); g.sync2 = rd16(tp + o + 4); g.zero_t = rd16(tp + o + 6); g.one_t = rd16(tp + o + 8);
            g.pilot_n = rd16(tp + o + 10); g.lastbits = tp[o + 12]; g.pause_ms = rd16(tp + o + 13); u32 ln = rd24(tp + o + 15);
            g.nzero = g.none = 2U; g.nstart = g.nstop = 0U; g.msb = 1U;
            g.off = o + 18U; g.end = g.off + ln; blk_off = g.end; cur_level = 0;
            if (!ln) continue; n_blocks++; g_begin_data(); return 1; }
        case 0x12: {                                         /* pure tone */
            g_kcs_defaults(); g.pilot_t = rd16(tp + o); g.pilot_n = rd16(tp + o + 2) & ~1U; blk_off = o + 4U;
            g.off = g.end = blk_off; if (!g.pilot_n) continue; n_blocks++; g.phase = 0; g.pilot_i = 0; g.active = 1; g.i = 0; return 1; }
        case 0x13: {                                         /* pulse sequence: se emite entera aqui mismo */
            u32 n = tp[o]; for (u32 k = 0; k < n; k++) pulse(rd16(tp + o + 1U + 2U * k)); blk_off = o + 1U + 2U * n; continue; }
        case 0x14: {                                         /* pure data */
            g_kcs_defaults(); g.zero_t = rd16(tp + o); g.one_t = rd16(tp + o + 2); g.lastbits = tp[o + 4]; g.pause_ms = rd16(tp + o + 5); u32 ln = rd24(tp + o + 7);
            g.nzero = g.none = 2U; g.nstart = g.nstop = 0U; g.msb = 1U; g.pilot_n = 0U;
            g.off = o + 10U; g.end = g.off + ln; blk_off = g.end; if (!ln) continue; n_blocks++; g_begin_data(); return 1; }
        case 0x15: {                                         /* direct recording: nivel explicito por bit */
            g_kcs_defaults(); g.bit_t = rd16(tp + o); g.pause_ms = rd16(tp + o + 2); g.lastbits = tp[o + 4]; u32 ln = rd24(tp + o + 5);
            g.direct = 1; g.pilot_n = 0U; g.nstart = g.nstop = 0U; g.msb = 1U;
            g.off = o + 8U; g.end = g.off + ln; blk_off = g.end; if (!ln) continue; n_blocks++; g_begin_data(); return 1; }
        case 0x20: { u32 ms = rd16(tp + o); silence(ms ? ms : 2000U); blk_off = o + 2U; continue; }
        case 0x21: blk_off = o + 1U + tp[o]; continue;
        case 0x22: blk_off = o; continue;
        case 0x24: blk_off = o + 2U; continue;
        case 0x25: blk_off = o; continue;
        case 0x2A: blk_off = o + 4U; continue;
        case 0x2B: blk_off = o + 5U; continue;
        case 0x30: blk_off = o + 1U + tp[o]; continue;
        case 0x31: blk_off = o + 2U + tp[o + 1]; continue;
        case 0x32: blk_off = o + 2U + rd16(tp + o); continue;
        case 0x33: blk_off = o + 1U + 3U * tp[o]; continue;
        case 0x35: blk_off = o + 16U + 4U + rd32(tp + o + 16); continue;
        case 0x4B: {                                         /* MSX KCS */
            u32 ln = rd32(tp + o);
            g_kcs_defaults();
            g.pause_ms = rd16(tp + o + 4); g.pilot_t = rd16(tp + o + 6); g.pilot_n = rd16(tp + o + 8);
            g.zero_t = rd16(tp + o + 10); g.one_t = rd16(tp + o + 12);
            { u8 bc = tp[o + 14], yc = tp[o + 15];
              g.nzero = (bc >> 4) ? (bc >> 4) : 16U; g.none = (bc & 15U) ? (bc & 15U) : 16U;
              g.nstart = (yc >> 6) & 3U; g.startv = (yc >> 5) & 1U; g.nstop = (yc >> 3) & 3U; g.stopv = (yc >> 2) & 1U; g.msb = yc & 1U; }
            g.off = o + 16U; g.end = o + 4U + ln; blk_off = g.end;
            if (g.end <= g.off && !g.pilot_n) continue;
            n_blocks++; g_begin_data(); return 1; }
        case 0x5A: blk_off = o + 9U; continue;
        default:
            log_str("tp: bloque desconocido "); log_hex(id); log_str(" en "); log_hex(blk_off); log_str(": fin\n");
            blk_off = tp_len; return 0;
        }
    }
    return 0;
}

/* un pulso mas del bloque en curso; 0 = bloque acabado */
static int gen_step(void)
{
    if (!g.active) return 0;
    switch (g.phase) {
    case 0:                                                  /* piloto */
        if (g.pilot_i < g.pilot_n) { pulse(g.pilot_t); g.pilot_i++; return 1; }
        g.phase = g.sync1 ? 1 : 3; return 1;
    case 1: pulse(g.sync1); g.phase = 2; return 1;
    case 2: pulse(g.sync2); g.phase = 3; return 1;
    case 3: {                                                /* datos */
        if (g.off + g.i >= g.end) { g.phase = 4; return 1; }
        u32 nbits_data = (g.off + g.i + 1U == g.end) ? g.lastbits : 8U;
        u32 total = g.nstart + nbits_data + g.nstop;
        if (g.bitn >= total) { g.i++; g.bitn = 0; g.sub = 0; return 1; }
        u32 bit;
        if (g.bitn < g.nstart) bit = g.startv;
        else if (g.bitn < g.nstart + nbits_data) { u32 k = g.bitn - g.nstart; u8 d = tp[g.off + g.i]; bit = g.msb ? ((d >> (7U - k)) & 1U) : ((d >> k) & 1U); }
        else bit = g.stopv;
        if (g.direct) { ring_put((int)bit, t2cyc(g.bit_t)); n_pulses++; g.bitn++; return 1; }
        { u32 np = bit ? g.none : g.nzero, t = bit ? g.one_t : g.zero_t;
          pulse(t); g.sub++;
          if (g.sub >= np) { g.sub = 0; g.bitn++; } }
        return 1; }
    case 4:
        if (g.pause_ms) { if (g.sync1 || g.msb) pulse(2000U); silence(g.pause_ms); }
        g.phase = 5; g.active = 0; return 0;
    default: g.active = 0; return 0;
    }
}

/* ---------------------------------------------------------------- pantalla y teclas */
/* la pantalla de texto: SCRMOD (FCAFh), NAMBAS (F922h) y LINL40 (F3AEh) de las variables del sistema (RAM de la
 * pagina 3 en la DDR 0x10800000) -> tabla de nombres en VRAM + NAMBAS, 40/80 columnas en SCREEN 0 y 32 en SCREEN 1
 * (el BASIC de este MSX2+ arranca en SCREEN 1: "Ok" en la tabla de nombres de 1800h) */
#ifdef TAPE_HOST
extern u8 host_ram3[16384];
#define RAM3(a) host_ram3[(a) - 0xC000U]
#else
#define RAM3(a) (*(volatile u8 *)(0x10800000U + ((a) - 0xC000U)))
#endif
static u32 count_ok(void)
{
    u32 n = 0, scrmod = RAM3(0xFCAFU), nambas = (u32)RAM3(0xF922U) | ((u32)RAM3(0xF923U) << 8), cols = RAM3(0xF3AEU);
    if (scrmod > 1U) return 0;
    if (scrmod == 1U) cols = 32U;
    if (cols < 32U || cols > 80U || nambas > 0x3F000U) return 0;
    for (u32 r = 0; r < 24U; r++) {                         /* fila = espacios, "Ok", espacios (SCREEN 1 sangra 2 columnas) */
        const volatile u8 *row = VRAM + nambas + r * cols;
        u32 c = 0;
        while (c < 4U && row[c] == ' ') c++;
        if (row[c] == 'O' && row[c + 1] == 'k' && row[c + 2] == ' ' && row[c + 3] == ' ' && row[c + 4] == ' ') n++;
    }
    return n;
}
static void kbd_bits(u32 b[4], u32 code) { b[code >> 5] |= 1U << (code & 31U); }
static int char2hid(char c, u32 *code, u32 *shift)
{
    *shift = 0;
    if (c >= 'a' && c <= 'z') { *code = 4U + (u32)(c - 'a'); return 1; }
    if (c >= 'A' && c <= 'Z') { *code = 4U + (u32)(c - 'A'); *shift = 1; return 1; }
    if (c == '0') { *code = 39U; return 1; }
    if (c >= '1' && c <= '9') { *code = 30U + (u32)(c - '1'); return 1; }
    switch (c) {
    case ' ': *code = 44U; return 1;   case '\r': *code = 40U; return 1;
    case '"': *code = 52U; *shift = 1; return 1;   case ':': *code = 51U; *shift = 1; return 1;
    case ',': *code = 54U; return 1;   case '.': *code = 55U; return 1;
    /* Z1.2: el resto de lo que puede traer un TSX.LOAD (teclado MSX: shift+8 = *, shift+9 = (, shift+0 = ), shift+= = +) */
    case ';': *code = 51U; return 1;   case '\'': *code = 52U; return 1;
    case '-': *code = 45U; return 1;   case '=': *code = 46U; return 1;   case '/': *code = 56U; return 1;
    case '(': *code = 38U; *shift = 1; return 1;   case ')': *code = 39U; *shift = 1; return 1;
    case '*': *code = 37U; *shift = 1; return 1;   case '+': *code = 46U; *shift = 1; return 1;
    case '&': *code = 36U; *shift = 1; return 1;   case '$': *code = 33U; *shift = 1; return 1;
    case '_': *code = 45U; *shift = 1; return 1;   case '!': *code = 30U; *shift = 1; return 1;
    default: return 0;
    }
}
static void keys_type_start(const char *s) { keys_str = s; keys_i = 0; keys_sub = 0; keys_t0 = TAPE_MS(); }
/* devuelve 1 mientras teclea */
static int keys_type_step(void)
{
    u32 b[4] = {0, 0, 0, 0};
    char c = keys_str[keys_i];
    if (!c) { kbd_synth_set(b); return 0; }
    if (keys_sub == 0) {                                     /* pulsar */
        u32 code, sh; if (char2hid(c, &code, &sh)) { kbd_bits(b, code); if (sh) kbd_bits(b, 105U); }
        kbd_synth_set(b); keys_sub = 1; keys_t0 = TAPE_MS();
    } else if (keys_sub == 1 && (u32)(TAPE_MS() - keys_t0) >= 90U) {   /* soltar */
        kbd_synth_set(b); keys_sub = 2; keys_t0 = TAPE_MS();
    } else if (keys_sub == 2 && (u32)(TAPE_MS() - keys_t0) >= 60U) { keys_i++; keys_sub = 0; }
    return 1;
}

/* ---------------------------------------------------------------- TSX.LOAD (bloque 35) */
/* makeTSX deja al principio del TSX bloques 35 ("custom info": clave de 10 bytes + {u32 len, valor}) con la ficha
 * de la cinta: TSX.RIPPER, TOSEC.NAME y TSX.LOAD = la orden de carga (RUN"CAS:" / BLOAD"CAS:",R / CLOAD...). Es la
 * misma que muestra tsx.eslamejor, asi que las manos la teclean tal cual en vez de adivinarla por la cabecera. */
static u32 tsx_blk_len(u8 id, const u8 *o)   /* longitud del cuerpo (tras el id), como el generador; ~0 = desconocido */
{
    switch (id) {
    case 0x10: return 4U + rd16(o + 2);         case 0x11: return 18U + rd24(o + 15);
    case 0x12: return 4U;                       case 0x13: return 1U + 2U * o[0];
    case 0x14: return 10U + rd24(o + 7);        case 0x15: return 8U + rd24(o + 5);
    case 0x20: return 2U;                       case 0x21: return 1U + o[0];
    case 0x22: return 0U;                       case 0x24: return 2U;
    case 0x25: return 0U;                       case 0x2A: return 4U;
    case 0x2B: return 5U;                       case 0x30: return 1U + o[0];
    case 0x31: return 2U + o[1];                case 0x32: return 2U + rd16(o);
    case 0x33: return 1U + 3U * o[0];           case 0x35: return 20U + rd32(o + 16);
    case 0x4B: return 4U + rd32(o);             case 0x5A: return 9U;
    default:   return 0xFFFFFFFFU;
    }
}
static int tsx_find_load(char *dst, u32 cap)
{
    u32 off = 10U;
    while (off + 21U < tp_len) {
        u8 id = tp[off]; const u8 *o = tp + off + 1U;
        u32 ln = tsx_blk_len(id, o);
        if (ln == 0xFFFFFFFFU || off + 1U + ln > tp_len) return 0;
        if (id == 0x35 && o[0] == 'T' && o[1] == 'S' && o[2] == 'X' && o[3] == '.' && o[4] == 'L' && o[5] == 'O' && o[6] == 'A' && o[7] == 'D') {
            u32 vl = rd32(o + 16), n = 0; const u8 *v = o + 20;
            while (n < vl && n + 1U < cap && v[n] >= ' ' && v[n] < 127U) { dst[n] = (char)v[n]; n++; }
            while (n && dst[n - 1] == ' ') n--;
            dst[n] = 0;
            return n > 0;
        }
        off += 1U + ln;
    }
    return 0;
}
static void log_cmd(const char *s) { char b[2] = {0, 0}; while (*s && *s != '\r') { b[0] = *s++; log_str(b); } }

/* ---------------------------------------------------------------- API */
/* Z1.2: al arrancar el companion (QSPI o JTAG) la palabra de control del buzon (+0x28) es lo que hubiera en la DDR:
 * basura en frio o la sesion anterior tras un reset (play=1, sin_nextor=1 = Nextor escondido, sin_motor...). Se deja
 * parada y en sincronia con el rd del PL (que sigue vivo si el PL no se ha reprogramado). */
void tape_init(void)
{
    playing = 0; eof_gen = 1; g.active = 0; keys_phase = 0; ctl_flags = 0;
    wr = (u16)(TP_TEL >> 16);
    publish(0);
}
void tape_stop(void)
{
    u32 b[4] = {0, 0, 0, 0};
    if (playing) log_str("tp: parada\n");
    playing = 0; g.active = 0; eof_gen = 1; keys_phase = 0; kbd_synth_set(b);
    publish(0);
}

void tape_start(u32 part, u32 dir, u32 file)
{
    u32 size = 0; char ext[3];
    u32 b[4] = {0, 0, 0, 0};
    tape_stop();
    if (!tape_fat_locate(part, dir, file, &size, ext)) { log_str("tp: fichero no encontrado\n"); return; }
    if (size > TAPE_MAX || size < 16U) { log_str("tp: tamano invalido "); log_dec(size); log_str("\n"); return; }
    for (u32 pos = 0; pos < size; ) {
        u32 n = size - pos; if (n > 4096U) n = 4096U;
        if (!tape_file_read(file, size, pos, TAPE_BUF + pos, n)) { log_str("tp: error de lectura\n"); return; }
        pos += n;
    }
    tp = TAPE_BUF; tp_len = size;
    is_cas = cas_sync_at(0);
    if (!is_cas) {
        if (!(tp[0] == 'Z' && tp[1] == 'X' && tp[2] == 'T' && tp[3] == 'a' && tp[4] == 'p' && tp[5] == 'e' && tp[6] == '!')) { log_str("tp: ni TSX ni CAS\n"); return; }
        blk_off = 10U;
    } else blk_off = 0U;
    /* orden de carga: la primera cabecera de 16 bytes */
    load_kind = 0;
    { u32 o = blk_off, found = 0;
      for (u32 k = 0; k + 26U < tp_len && !found && k < 4096U; k++) {
          const u8 *d = tp + o + k;
          if (is_hdr16(d, 0xEA)) { load_kind = 0; found = 1; }
          else if (is_hdr16(d, 0xD0)) { load_kind = 1; found = 1; }
          else if (is_hdr16(d, 0xD3)) { load_kind = 2; found = 1; }
      } }
    /* Z1.2: la orden a teclear: la del propio TSX (bloque 35 TSX.LOAD) si la trae; si no, la de la cabecera */
    load_from_tsx = 0; load_run_after = 0;
    if (!is_cas && tsx_find_load(load_cmd, sizeof load_cmd - 2U)) load_from_tsx = 1;
    else { const char *s = load_kind == 0 ? "RUN\"CAS:\"" : load_kind == 1 ? "BLOAD\"CAS:\",R" : "CLOAD"; u32 n = 0;
           while (s[n]) { load_cmd[n] = s[n]; n++; } load_cmd[n] = 0; }
    { u32 n = 0, has_run = 0, ends_r = 0, plus = 0;
      /* la ficha escribe "CLOAD + RUN": la segunda orden va tras el 2o Ok */
      while (load_cmd[n]) { if (load_cmd[n] == '+' && !plus) plus = n; n++; }
      if (plus) { u32 a = plus, b = plus + 1U, m = 0;
                  while (a && load_cmd[a - 1] == ' ') a--;
                  while (load_cmd[b] == ' ') b++;
                  while (load_cmd[b] && m + 2U < sizeof load_cmd2) load_cmd2[m++] = load_cmd[b++];
                  while (m && load_cmd2[m - 1] == ' ') m--;
                  load_cmd2[m] = '\r'; load_cmd2[m + 1] = 0; load_cmd[a] = 0; n = a; load_run_after = (m > 0); }
      for (u32 k = 0; k + 2U < n; k++) if ((load_cmd[k] | 32) == 'r' && (load_cmd[k + 1] | 32) == 'u' && (load_cmd[k + 2] | 32) == 'n') has_run = 1;
      if (n >= 2U && load_cmd[n - 2] == ',' && (load_cmd[n - 1] | 32) == 'r') ends_r = 1;
      if (!plus && !has_run && !ends_r) { load_cmd2[0] = 'R'; load_cmd2[1] = 'U'; load_cmd2[2] = 'N'; load_cmd2[3] = '\r'; load_cmd2[4] = 0; load_run_after = 1; }   /* CLOAD / LOAD"CAS:" -> RUN al acabar */
      load_cmd[n] = '\r'; load_cmd[n + 1] = 0; }
    /* el anillo arranca donde lo dejo el PL: rd sigue a wr con play=0 */
    wr = (u16)(TP_TEL >> 16);
    ctl_flags = 0x40000000U | 0x10000000U;                    /* monitor de audio + SIN NEXTOR (bit 28: el slot 3-2 desaparece hasta
                                                              * el proximo arranque del companion: BASIC limpio con toda la RAM) */
    cur_level = 1; n_pulses = 0; n_blocks = 0; eof_gen = 0; g.active = 0;
    playing = 1;
    publish(1);
    /* manos: la orden de carga al ver "Ok". (Nextor NO se salta con SHIFT, probado 18/09: el BASIC limpio lo
     * consigue el menu apagando la SD (config2 bit 0) antes de arrancar, asi que aqui no se pulsa nada mas.) */
    (void)b;
    keys_phase = 2; keys_t0 = TAPE_MS(); ok_count = 0;
    log_str("tp: "); log_str(is_cas ? "CAS " : "TSX "); log_dec(size); log_str(" bytes, orden ");
    log_cmd(load_cmd); log_str(load_from_tsx ? " (TSX.LOAD)" : " (cabecera)"); if (load_run_after) { log_str(" + "); log_cmd(load_cmd2); } log_str("\n");
}

/* rama beta (30/10/2026): "sin Nextor" para el arranque siguiente, pedido por el menu ('N','X'; 'N','N' lo quita al
 * volver a arrancar el menu). Las ROM con driver de disco (DSK2ROM) no caben con Nextor: "No enough memory" en openMSX,
 * reinicio en el MSXimus. El mismo bit 28 que la cinta. */
void tape_nextor(int con)
{
    if (con) ctl_flags &= ~0x10000000U; else ctl_flags |= 0x10000000U;
    publish(playing);
    log_str(con ? "tp: con Nextor\n" : "tp: sin Nextor (ROM con disco)\n");
}

void tape_poll(void)
{
    if (!playing) return;
    /* --- anillo: mantener LOOKAHEAD entradas por delante del PL; al final rellenar hasta la rafaga --- */
    if (!eof_gen) {
        u16 rd = (u16)(TP_TEL >> 16);
        u32 written = 0;
        while ((u16)(wr - rd) < LOOKAHEAD && written < 2048U) {
            u16 w0 = wr;
            if (!gen_step()) { if (!open_next_block()) { eof_gen = 1; break; } }
            written += (u16)(wr - w0);
        }
        if (eof_gen) { pad_n = 0; while (wr & 31U) { ring_put(1, 1U); pad_n++; } log_str("tp: cinta convertida: "); log_dec(n_blocks); log_str(" bloques, "); log_dec(n_pulses); log_str(" pulsos\n"); }
        publish(1);
    } else {
        /* fin: el PL lo ha traido todo (rd == wr) y en su FIFO solo queda el relleno (que no consume con el motor parado) */
        u32 t = TP_TEL;
        if ((u16)(t >> 16) == wr && ((t >> 8) & 63U) <= pad_n && keys_phase == 0) { playing = 0; publish(0); log_str("tp: fin\n"); }
    }
    /* --- manos --- */
    switch (keys_phase) {
    case 1:                                                  /* SHIFT hasta que el BASIC diga Ok (Nextor ya se ha decidido) o 8 s */
        if (count_ok() > 0 || (u32)(TAPE_MS() - keys_t0) >= 8000U) { u32 b[4] = {0, 0, 0, 0}; kbd_synth_set(b); keys_phase = 2; keys_t0 = TAPE_MS(); }
        break;
    case 2: if (count_ok() > 0) { keys_type_start(load_cmd); keys_phase = 3; ok_count = count_ok(); }
            else if ((u32)(TAPE_MS() - keys_t0) > 15000U) { log_str("tp: sin Ok en 15 s, sin manos\n"); keys_phase = 0; } break;
    case 3: if (!keys_type_step()) keys_phase = load_run_after ? 4 : 0; break;
    case 4: if (count_ok() > ok_count) { keys_type_start(load_cmd2); keys_phase = 5; } break;   /* CLOAD acabado -> RUN (o la 2a orden de la ficha) */
    case 5: if (!keys_type_step()) keys_phase = 0; break;
    default: break;
    }
}
