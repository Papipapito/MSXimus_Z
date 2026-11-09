/* osd.h — paginas del OSD de la Zynq con COLOR (Z1.2.2, 30/09/2026).
 *
 * Una pagina son 28 x 32 celdas {atributo, caracter} (textdisp_z.v); atributo = OSD_A(fondo, tinta) con la paleta de
 * osd_glifos.h (generado por fpga/zynq/tools/make_dpb_menu.py) y caracteres 128..255 = glifos (bloques, marcos,
 * iconos, letras con tilde). Se ven 30 columnas (el borde derecho del overlay cae fuera del HDMI): OSD_ANCHO.
 * osd_dib.c dibuja sobre una pagina en memoria (sin hardware: lo usa tambien el banco del PC); osd.c la manda al
 * iosys (solo las filas que cambian). */
#ifndef OSD_H
#define OSD_H
#include "xil_types.h"
#include "osd_glifos.h"

#define OSD_COLS   32
#define OSD_FILAS  28
#define OSD_ANCHO  30
typedef u16 osd_celda;                                   /* {atributo[15:8], caracter[7:0]} */
typedef osd_celda (*osd_pag)[OSD_COLS];

/* idioma de los textos (Z1.2.3): el del menu de la imagen que corre (ota.c lo fija al arrancar) */
extern u8 osd_ingles;
#define T(es, en) (osd_ingles ? (en) : (es))

/* osd_dib.c */
void osd_limpia(osd_pag p, u8 a);
void osd_car(osd_pag p, int x, int y, u8 a, u8 c);
int  osd_txt(osd_pag p, int x, int y, u8 a, const char *utf8);        /* devuelve la columna siguiente */
int  osd_txt_n(osd_pag p, int x, int y, u8 a, const char *utf8, int n);   /* como osd_txt, n caracteres como mucho */
int  osd_txt_len(const char *utf8);                                    /* caracteres que ocupa */
int  osd_txt_der(osd_pag p, int x_fin, int y, u8 a, const char *utf8); /* alineado a la derecha, acaba en x_fin-1 */
void osd_rellena(osd_pag p, int x, int y, int w, int h, u8 a, u8 c);
void osd_marco(osd_pag p, int x, int y, int w, int h, u8 fondo, u8 linea, const char *titulo, u8 tinta_titulo);
void osd_barra(osd_pag p, int x, int y, int w, u8 fondo, u8 lleno, u8 vacio, u32 num, u32 den);
int  osd_pastilla(osd_pag p, int x, int y, u8 fondo, u8 color, u8 tinta, const char *texto);
int  osd_boton(osd_pag p, int x, int y, u8 fondo, u8 color, const char *tecla, const char *texto);
void osd_cabecera(osd_pag p, u8 icono, const char *titulo, const char *derecha);
char *osd_num(char *d, u32 v);                                         /* decimal; devuelve el final (con 0) */
char *osd_fijo(char *d, u32 v, u32 dec);                               /* v en unidades 10^-dec, coma decimal */

/* ota.c */
void ota_pagina(osd_pag p);                              /* la pagina de la actualizacion */
const char *ota_version(void);                           /* la version que corre (ota_info o registro) */
int  ota_ocupada(void);                                  /* buscando, bajando o grabando */
void osd_abre_servidor(void);                            /* osd.c: enciende el OSD en la vista del servidor de Perfiles si no esta ya en esa pagina (ota.c, antes de instalar un perfil) */
#endif
