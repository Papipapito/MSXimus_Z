/* osd_info.h — datos de la pagina de informacion del OSD (osd_info.c los pinta, osd.c los lee del hardware). */
#ifndef OSD_INFO_H
#define OSD_INFO_H
#include "osd.h"

enum { USB_TECLADO = 0, USB_RATON, USB_MANDO, USB_DISCO, USB_HUB, USB_OTRO, USB_TIPOS };

typedef struct {
    const char *version;                  /* ota_version() */
    s32 temp_dc, tmax_dc;                 /* decimas de grado */
    u32 vint_mv, vaux_mv, vbram_mv;
    u32 uptime_s;
    u32 sd_mb, sd_err;                    /* sd_mb = 0: sin tarjeta */
    u32 usb_disp, usb_tipo[USB_TIPOS];    /* dispositivos conectados ahora y cuantos de cada tipo */
    u32 usb_reinicios;                    /* veces que el vigilante ha reiniciado el USB (0 = no se dibuja nada) */
    u32 screen, turbo, v9990;             /* turbo: estado del iosys (orden 14); v9990: 0 el HDMI saca el V9968, 1 el V9990, 2 los dos compuestos (V9991) */
    u8  ip[4];                            /* 0.0.0.0 = sin red */
    u8  wifi;                             /* rama beta: la IP es la de la S3 (WiFi), no la del cable */
    u8  v43;                              /* rama beta: el V9968 a pantalla completa en 4:3 con Scale3x */
    u8  yrw801;                           /* YRW801_* (yrw801.h): suma de comprobacion de la ROM de ondas del OPL4 */
    u8  dual;                             /* perfil Dual: la pagina de informacion ofrece la tecla B (maquina B) */
    u8  tr;                               /* perfil TR (fase 1): sin V9990 ni OPL4; el PL lo declara en +0xC4 bit 2 (vale tambien cargado por JTAG) */
    u8  tr_v99;                           /* perfil TRV: el TR con V9990 */
    u8  tf1_aviso;                        /* perfiles.c: 1 = hay una tarjeta nueva en la TF1 sin preparar, 2 = es de las betas (se puede convertir); 0 = nada */
    u8  tr_bios;                          /* perfil TR (fase 2): TR_BIOS_* (tr_bios.h), la BIOS del turbo R que pone el usuario en la TF2 */
} osd_info_t;

void osd_pagina_info(osd_pag p, const osd_info_t *d);
#endif
