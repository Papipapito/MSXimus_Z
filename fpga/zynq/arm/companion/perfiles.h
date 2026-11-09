/* perfiles.h — la pagina «Perfiles» del panel F12 (tecla P desde la pagina de informacion): perfiles del PL en la TF1 (mxpf.c). */
#ifndef PERFILES_H
#define PERFILES_H
#include "xil_types.h"
#include "osd.h"

void perfiles_abre(void);                 /* al entrar en la pagina: relee la tarjeta (vista de la tarjeta) */
void perfiles_abre_servidor(void);        /* la vista del servidor (perfil= del manifiesto); busca si aun no se ha buscado */
void perfiles_aviso_abre(const char *txt, int ok, const char *id);   /* la vista de la tarjeta con un aviso, el cursor sobre `id` (puede ser 0) */
void perfiles_tecla(u8 usage);            /* teclas HID: flechas, Intro, D, A, S, T, R, U, B, ESC (si hay algo armado o se esta en el servidor) */
int  perfiles_armado(void);               /* 1 = ESC es de esta pagina: hay algo armado o se esta en la vista del servidor */
int  perfiles_cambio(void);               /* 1 = la pagina ha cambiado (mensaje, aviso que caduca, la descarga) desde la ultima llamada */
void perfiles_pagina(osd_pag p);          /* dibuja la pagina */
int  perfiles_aviso_tf1(void);            /* TF1 solo perfiles: 0 nada, 1 tarjeta nueva sin preparar, 2 tarjeta de las betas (se puede convertir). No bloquea nada */
void perfiles_aviso_revisa(void);         /* clasifica la tarjeta de TF1 y fija el aviso (main.c lo llama cuando la tarjeta aparece o se va) */
const char *perfiles_error(int mxpf_e);   /* el texto (castellano o ingles) de un codigo MXPF_E_* */
const char *perfil_nombre(const char *id);   /* el nombre que se ENSENA de un perfil (MUSICA -> "Música" / "Music", DUAL -> "Dual"); el id interno no cambia */
extern void osd_repinta(void);            /* osd.c: dibuja y manda la pagina ahora (un aviso antes de una operacion larga) */
extern void osd_abre_perfiles(void);      /* osd.c: enciende el OSD en la pagina de perfiles tal como esta (perfiles_aviso_abre / perfiles_abre_servidor) */
#endif
