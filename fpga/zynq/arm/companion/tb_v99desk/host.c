/* host.c — banco en el PC de v99desk.c (rama beta): lo compila tal cual con V99_HOST, simula unos segundos de
 * companion (el PL se lo come todo) y saca las escrituras a los puertos del V9990 en el formato de mk_replay.py
 * ("W pp vv ms"), para encadenarlas detras del escritorio del menu y verlas en la cadena del V9990.
 * Uso: host [ms] [rpl|hex] [5|7|9|10] [hora 0|1] [mueve|silencio]
 * 10 = el escritorio de dos columnas con el juego en A (la D sola del menu, Z1.3.2b8): B dice "MSX - B  BASIC". Con "silencio" (solo con 9 o 10) el
 * sonido de A y de B esta en silencio desde la vuelta 100 (el cuadradito cian de la barra de B gris y hueco, la linea de la tarjeta en naranja).
 * Con 9 (escritorio de dos columnas del perfil Dual) y "mueve" arrastra el marco de B (como dual.c): en la vuelta 150 lo pide en (250, 120) con el
 * foco y "arrastrando", en la 201 lo suelta, y con "hex" deja lineas "#SNAP n" (en las vueltas 140, 200 y 260) para que tools/render_v99desk.py
 * saque una imagen de cada momento. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "xil_types.h"
#include "s3.h"
volatile u32 host_ctl, host_tel;
volatile u16 host_ring[16384];
u8  osd_ingles = 1;
u32 usb_n_kbd = 2, usb_n_mouse = 1, usb_n_pad = 0;
s32 osd_temp_dc = 512;
s3_resp_t s3r;
static u64 now = 1000;
static u32 up = 46, con_hora = 1;
u64 gt_now(void) { return now; }
u32 osd_uptime_s(void) { return up; }
void net_ip(u8 ip[4]) { ip[0] = 192; ip[1] = 168; ip[2] = 1; ip[3] = 50; }
int esp_net_ok(void) { return 1; }
int esp_hora_utc(u32 *t) { if (!con_hora) return 0; *t = 1793345696u + up; return 1; }   /* 30/10/2026 07:34:56 UTC + up */
int esp_gmt_horas(void) { return 1; }
void epoch_to_dt(u32 t, u8 *o)
{
    u32 rem = t % 86400U; long z = (long)(t / 86400U) + 719468L, era = (z >= 0 ? z : z - 146096L) / 146097L;
    unsigned doe = (unsigned)(z - era * 146097L), yoe = (doe - doe / 1460U + doe / 36524U - doe / 146096U) / 365U;
    long y = (long)yoe + era * 400L; unsigned doy = doe - (365U * yoe + yoe / 4U - yoe / 100U), mp = (5U * doy + 2U) / 153U;
    unsigned d = doy - (153U * mp + 2U) / 5U + 1U, m = mp < 10U ? mp + 3U : mp - 9U; if (m <= 2U) y++;
    o[0] = (u8)(rem % 60U); o[1] = (u8)((rem / 60U) % 60U); o[2] = (u8)(rem / 3600U); o[3] = (u8)d; o[4] = (u8)m; o[5] = (u8)(y & 0xFF); o[6] = (u8)((y >> 8) & 0xFF);
}
int ota_ocupada(void) { return 0; }
int osd_turbo(void) { return 1; }
const char *ota_version(void) { return "Z1.3b3"; }
void s3_toma(void) {} void s3_suelta(void) {} int s3_tomada(void) { return 0; } int s3_lista(void) { return 1; }
int s3_ip(u8 ip[4]) { (void)ip; return 0; } void s3_ip_lee(void) {}
int s3_orden(u8 cmd, const u8 *d, u32 n, u32 plazo) { (void)cmd; (void)d; (void)n; (void)plazo; return -1; }
int s3_pide(u8 cmd, const u8 *d, u32 n, u32 plazo) { (void)cmd; (void)d; (void)n; (void)plazo; return 1; }
int s3_resp(void) { return -1; }
u8 s3_udp_abre(void) { return 0; } void s3_udp_cierra(u8 c) { (void)c; }
int s3_udp_manda(u8 c, const u8 ip[4], u16 p, const u8 *d, u32 n) { (void)c; (void)ip; (void)p; (void)d; (void)n; return -1; }
int s3_udp_lee(u8 c, u8 *d, u32 cap, u8 ip[4]) { (void)c; (void)d; (void)cap; (void)ip; return -1; }
void log_str(const char *s) { fprintf(stderr, "%s", s); }
void log_dec(unsigned v) { fprintf(stderr, "%u", v); }
void v99desk_dual_pon(u16 x, u16 y, u8 foco, u8 arrastrando);
void dual_marco_listo(u16 x, u16 y) { (void)x; (void)y; }
void dual_escritorio(u8 lay) { if (lay == 9 || lay == 10) v99desk_dual_pon(362, 48, 0, 0); }            /* dual.c: no esta en este banco (el escritorio de dos columnas se prueba a mano en tests/dual_host) */
const char *dual_b_etiqueta(void) { return "BASIC"; }
void v99desk_dual_silencio(u8 a, u8 b, u8 corre);
void v99desk_inicio(u8 lay, const char *rom); void v99desk_poll(void);
void v99desk_dual_pon(u16 x, u16 y, u8 foco, u8 arrastrando); void v99desk_dual_fin(void);
int main(int argc, char **argv)
{
    unsigned ms = argc > 1 ? (unsigned)atoi(argv[1]) : 100, rd = 0, n = 0, entradas = 0;
    int hexout = argc > 2 && !strcmp(argv[2], "hex");
    int lay = argc > 3 ? atoi(argv[3]) : 7;
    con_hora = argc > 4 ? (u32)atoi(argv[4]) : 1;
    v99desk_inicio((u8)lay, "PENGUIN ADVENTURE");
    int mueve = argc > 5 && !strcmp(argv[5], "mueve"), sil = argc > 5 && !strcmp(argv[5], "silencio");
    for (int i = 0; i < 400; i++) {                /* 20 s de companion a 50 ms */
        if (sil) {
            if (i == 140 || i == 200 || i == 260) { if (hexout) printf("#SNAP %d\n", i); }
            if (i == 100) v99desk_dual_silencio(1, 1, 1);
        }
        if (mueve) {
            if (i == 140 || i == 200 || i == 260) { if (hexout) printf("#SNAP %d\n", i); }
            if (i == 150) v99desk_dual_pon(250, 120, 1, 1);
            if (i == 201) { v99desk_dual_pon(250, 120, 1, 0); v99desk_dual_fin(); }
        }
        v99desk_poll();
        unsigned wr = host_ctl & 0xFFFF;
        while (rd != wr) {
            u16 e = host_ring[rd & 16383]; rd = (rd + 1) & 0xFFFF; entradas++;
            unsigned t = e >> 14, p = (e >> 8) & 15, d = e & 255;
            if (hexout) printf("%04X\n", e);
            else if (t == 0) { printf("W %02X %02X %u\n", 0x60 + p, d, ms); n++; }
        }
        host_tel = (u32)rd << 16;
        now += 333333333ULL / 20; if (i % 20 == 19) up++;
        ms += 1;
    }
    fprintf(stderr, "host: %u entradas, %u escrituras\n", entradas, n);
    return 0;
}
