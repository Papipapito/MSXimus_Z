/* osd_info.c — la pagina de informacion del sistema (F12) con color, en castellano o en ingles (T(), osd.h). Solo dibuja:
 * los datos los lee osd.c (XADC, buzon, SDBOX, USB, iosys, red) y se los pasa en un osd_info_t; asi el banco del PC
 * puede pintarla tambien. Solo lo que le sirve a quien usa la maquina (nada de contadores de depuracion). */
#include "osd.h"
#include "osd_info.h"
#include "yrw801.h"
#include "tr_bios.h"

static void seccion(osd_pag p, int y, const char *t)
{
    int x = osd_txt(p, 1, y, OSD_A(C_NOCHE, C_CIAN), t);
    osd_rellena(p, x + 1, y, OSD_ANCHO - 1 - (x + 1), 1, OSD_A(C_NOCHE, C_GRIS_OSC), G_H);
}

static int etiqueta(osd_pag p, int y, const char *t) { osd_txt(p, 2, y, OSD_A(C_NOCHE, C_GRIS), t); return 16; }

static int dato(osd_pag p, int x, int y, u8 tinta, const char *t) { return osd_txt(p, x, y, OSD_A(C_NOCHE, tinta), t); }

/* "1 teclado · 2 mandos · 1 hub": los tipos que hay, en una o dos filas; devuelve la ultima fila usada */
static int tipos_usb(osd_pag p, int y, const osd_info_t *d)
{
    static const char *const es1[USB_TIPOS] = { "teclado", "ratón", "mando", "disco", "hub", "otro" };
    static const char *const esn[USB_TIPOS] = { "teclados", "ratones", "mandos", "discos", "hubs", "otros" };
    static const char *const en1[USB_TIPOS] = { "keyboard", "mouse", "gamepad", "disk", "hub", "other" };
    static const char *const enn[USB_TIPOS] = { "keyboards", "mice", "gamepads", "disks", "hubs", "others" };
    int x = 2, k, primero = 1;
    for (k = 0; k < USB_TIPOS; k++) {
        char b[24], *q;
        const char *t;
        u32 n = d->usb_tipo[k];
        if (!n) continue;
        q = osd_num(b, n); *q++ = ' ';
        t = osd_ingles ? (n == 1U ? en1[k] : enn[k]) : (n == 1U ? es1[k] : esn[k]);
        while (*t) *q++ = *t++;
        *q = 0;
        if (!primero && x + 3 + osd_txt_len(b) > OSD_ANCHO - 1) { x = 2; y++; primero = 1; }
        if (!primero) x = dato(p, x, y, C_GRIS, " · ");
        x = dato(p, x, y, C_BLANCO, b);
        primero = 0;
    }
    return y;
}

void osd_pagina_info(osd_pag p, const osd_info_t *d)
{
    char b[40], *q;
    int x, yusb = 12;
    u8 ct = d->temp_dc < 600 ? C_VERDE : d->temp_dc < 750 ? C_AMARILLO : C_ROJO;
    osd_limpia(p, OSD_A(C_NOCHE, C_BLANCO));
    osd_cabecera(p, G_CHIP, "MSXimus Z", d->version);

    seccion(p, 3, T("Sistema", "System"));
    x = etiqueta(p, 4, T("Temperatura", "Temperature"));
    osd_fijo(b, d->temp_dc > 0 ? (u32)d->temp_dc : 0U, 1);
    x = dato(p, x, 4, ct, b); x = dato(p, x, 4, ct, "°C");
    osd_num(b, d->tmax_dc > 0 ? (u32)d->tmax_dc / 10U : 0U);
    x = dato(p, x + 1, 4, C_GRIS, T("máx ", "max ")); dato(p, x, 4, C_GRIS, b);
    x = etiqueta(p, 5, T("Tensiones (V)", "Voltages (V)"));
    osd_fijo(b, d->vint_mv / 10U, 2); x = dato(p, x, 5, C_BLANCO, b); x = dato(p, x, 5, C_GRIS, "·");
    osd_fijo(b, d->vaux_mv / 10U, 2); x = dato(p, x, 5, C_BLANCO, b); x = dato(p, x, 5, C_GRIS, "·");
    osd_fijo(b, d->vbram_mv / 10U, 2); dato(p, x, 5, C_BLANCO, b);
    x = etiqueta(p, 6, T("Encendida", "Uptime"));
    q = b;
    *q++ = (char)('0' + d->uptime_s / 36000U % 10U); *q++ = (char)('0' + d->uptime_s / 3600U % 10U); *q++ = ':';
    *q++ = (char)('0' + d->uptime_s / 600U % 6U); *q++ = (char)('0' + d->uptime_s / 60U % 10U); *q++ = ':';
    *q++ = (char)('0' + d->uptime_s / 10U % 6U); *q++ = (char)('0' + d->uptime_s % 10U); *q = 0;
    dato(p, x, 6, C_BLANCO, b);

    seccion(p, 8, T("Tarjeta SD", "SD card"));
    osd_car(p, 2, 9, OSD_A(C_NOCHE, d->sd_mb ? C_CIAN : C_NARANJA), G_SD);
    if (d->sd_mb) {
        osd_num(b, d->sd_mb); x = dato(p, 4, 9, C_BLANCO, b); x = dato(p, x, 9, C_GRIS, " MB");
        if (d->sd_err) { x = dato(p, x, 9, C_GRIS, " · "); osd_num(b, d->sd_err); x = dato(p, x, 9, C_ROJO, b); dato(p, x, 9, C_ROJO, T(" errores", " errors")); }
    } else dato(p, 4, 9, C_NARANJA, T("sin tarjeta", "no card"));
    if (d->tf1_aviso) {                                               /* TF1 solo perfiles: aviso no bloqueante */
        osd_car(p, 2, 10, OSD_A(C_NOCHE, C_NARANJA), G_AVISO);
        dato(p, 4, 10, C_NARANJA, d->tf1_aviso == 2 ? T("TF1 de las betas: P", "TF1 beta card: P") : T("TF1 nueva: P la prepara", "TF1 new card: P sets up"));
    }

    seccion(p, 11, "USB");
    if (d->usb_disp) {
        osd_num(b, d->usb_disp); x = dato(p, 2, 12, C_BLANCO, b);
        dato(p, x, 12, C_GRIS, d->usb_disp == 1U ? T(" dispositivo", " device") : T(" dispositivos", " devices"));
        yusb = tipos_usb(p, 13, d);
    } else dato(p, 2, 12, C_GRIS, T("nada conectado", "nothing connected"));
    if (d->usb_reinicios && yusb < 15) {                              /* el vigilante reinicio el USB: fila 15, si los tipos no han llegado a ella */
        osd_num(b, d->usb_reinicios);
        x = dato(p, 2, 15, C_GRIS, T("USB reiniciado: ", "USB restarted: ")); dato(p, x, 15, C_AMARILLO, b);
    }

    seccion(p, 16, "MSX");
    x = dato(p, 2, 17, C_GRIS, "Z80 "); x = dato(p, x, 17, d->turbo ? C_AMARILLO : C_BLANCO, d->turbo ? T("5,37", "5.37") : T("3,58", "3.58"));
    x = dato(p, x, 17, C_GRIS, " MHz");
    if (d->turbo) dato(p, x + 1, 17, C_AMARILLO, "turbo");
    x = dato(p, 2, 18, C_GRIS, "SCREEN "); osd_num(b, d->screen); x = dato(p, x, 18, C_BLANCO, b);
    x = dato(p, x, 18, C_GRIS, T(" · vídeo ", " · video ")); dato(p, x, 18, C_BLANCO, d->v9990 == 2u ? "V9991" : d->v9990 ? "V9990" : "V9968");
    if (d->tr) {                                                      /* perfil TR: sin V9990 ni Y8950; la ROM de ondas del OPL4 va al final de la fila */
        x = dato(p, 2, 19, C_AMARILLO, d->tr_v99 ? "Turbo R V9990" : "Turbo R");
        if (d->tr_bios == TR_BIOS_PERFIL || d->tr_bios == TR_BIOS_JTAG) { x = dato(p, x, 19, C_GRIS, " · "); x = dato(p, x, 19, C_VERDE, "BIOS"); }
        else if (d->tr_bios) {                                        /* la BIOS no esta o no vale: el PL arranca el MSX2+ normal; que falta, en la fila 23 */
            x = dato(p, x, 19, C_GRIS, " · ");
            x = dato(p, x, 19, C_ROJO, T("sin BIOS", "no BIOS"));
        }
        x = dato(p, x, 19, C_GRIS, " · ");
        dato(p, x, 19, d->yrw801 == YRW801_OK ? C_VERDE : d->yrw801 == YRW801_MAL ? C_ROJO : C_GRIS, "YRW801");
    } else {
    x = dato(p, 2, 19, C_GRIS, "OPL4 ");                              /* la ROM de ondas que dejo el FSBL en la DDR (yrw801.c) */
    if (d->yrw801 == YRW801_OK) dato(p, x, 19, C_VERDE, "YRW801 OK");
    else if (d->yrw801 == YRW801_MAL) dato(p, x, 19, C_ROJO, T("YRW801 no válida", "YRW801 invalid"));
    else dato(p, x, 19, C_GRIS, T("YRW801 comprobando", "YRW801 checking"));
    }
    x = dato(p, 2, 20, C_GRIS, T("V9968 completo ", "V9968 full "));    /* rama beta: tecla V */
    x = dato(p, x, 20, d->v43 ? C_AMARILLO : C_BLANCO, d->v43 ? "4:3 Scale3x" : "16:9");
    dato(p, x + 1, 20, C_GRIS, "(V)");

    seccion(p, 21, T("Red", "Network"));
    osd_car(p, 2, 22, OSD_A(C_NOCHE, d->ip[0] ? C_VERDE : C_GRIS), G_RED);
    if (d->ip[0]) {
        q = b; if (d->wifi) { *q++ = 'W'; *q++ = 'i'; *q++ = 'F'; *q++ = 'i'; *q++ = ' '; }
        q = osd_num(q, d->ip[0]); *q++ = '.'; q = osd_num(q, d->ip[1]); *q++ = '.'; q = osd_num(q, d->ip[2]); *q++ = '.'; osd_num(q, d->ip[3]);
        dato(p, 4, 22, C_BLANCO, b);
    } else dato(p, 4, 22, C_GRIS, T("sin cable o sin IP", "no cable or no IP"));

    x = osd_boton(p, 1, 24, C_NOCHE, C_AMARILLO, "U", T("Actualizar", "Update"));
    osd_boton(p, x, 24, C_NOCHE, C_GRIS_CL, "F12", T("Salir", "Exit"));
    osd_boton(p, 1, 25, C_NOCHE, C_AMARILLO, "P", T("Perfiles", "Profiles"));
    if (d->dual) osd_boton(p, 1, 26, C_NOCHE, C_AMARILLO, "B", T("Máquina B", "Machine B"));      /* perfil Dual (2/11): la maquina B */
    dato(p, 1, 27, C_GRIS, T("El MSX está en pausa.", "The MSX is paused."));
}
