/* ota.h — actualizacion por red de la MSXimus Z (ota.c, 30/09/2026). */
#ifndef OTA_H
#define OTA_H
#include "xil_types.h"

void ota_arranque(void);          /* al principio de main (MSX aun en reset): prueba de la ranura B / avisos */
void ota_menu_version(void);      /* antes de soltar el MSX (y del perfil de arranque): Ajustes dira la version de ota_info, no la del PL */
void ota_poll(void);              /* bucle principal: descarga, grabacion, confirmacion de la B */
void ota_tecla(u8 usage);         /* teclas HID con el OSD abierto: U buscar, I instalar, R reiniciar, F fabrica */
void ota_reinicia_ps(void);       /* reinicio del PS en la misma ranura (profile.c, tras un PCAP fallido); solo vuelve si no puede */
u32  ota_serie(void);            /* serie del BOOT.bin que corre (ota_info); 0 = no se sabe (arranque por JTAG) */
int  ota_cambio(void);            /* 1 = la pagina de la actualizacion ha cambiado desde la ultima llamada */
/* la pagina (ota_pagina), ota_version y ota_ocupada: osd.h */

/* Perfiles del manifiesto (lineas perfil=, 31/10/2026): lo que usa la pagina Perfiles (perfiles.c) */
typedef struct { char id[9], version[16]; u32 tamano, tam_bin, serie; } ota_perfil_t;   /* tamano: el .mxp; tam_bin: el bitstream */
enum { OPS_NO = 0, OPS_AL_DIA, OPS_OTRA_SERIE, OPS_OTRA_VERSION };                  /* estado frente a la tarjeta de TF1 */
enum { OSV_SIN_BUSCAR = 0, OSV_BUSCANDO, OSV_LISTO, OSV_ERROR, OSV_OCUPADO };       /* estado de la busqueda en el servidor */
int  ota_srv_estado(void);                  /* OSV_*: LISTO = hay un manifiesto leido y con la firma buena */
const char *ota_srv_texto(void);            /* el servidor ("msx.barcelona", "192.168.1.5 (PC)") o el error */
int  ota_srv_beta(void);                    /* 1 = canal beta */
int  ota_busca(int como);                   /* 0 U/R buscar, 1 B otro canal, 2 al abrir la vista; corta la busqueda en marcha; tambien arrancada desde SD */
int  ota_perfiles_n(void);                  /* los del manifiesto (0 si no hay manifiesto leido) */
const ota_perfil_t *ota_perfil(int i);
int  ota_perfil_estado(int i);              /* OPS_*: mira mxpf_estado(), la lista de la ultima vez que se leyo la tarjeta */
int  ota_perfiles_descargables(void);      /* 1 = se pueden bajar: son de la serie que corre o de la que ya esta grabada en la B (si no, no se baja nada) */
int  ota_perfiles_viejos(void);             /* los OPS_OTRA_SERIE y OPS_OTRA_VERSION: ya en la tarjeta y distintos de los del servidor */
int  ota_perfil_baja(int i);                /* i >= 0: ese; i < 0: todos los que falten o esten viejos. 0 = no empieza (ver ota_perfil_resultado) */
int  ota_perfil_en_curso(void);             /* 1 = bajando o instalando */
void ota_perfil_progreso(u32 *hecho, u32 *total, int *indice);
/* ultimo resultado: 0 nada, 1 instalado(s) (n_ok, id del ultimo), 2 error de mxpf (codigo MXPF_E_*), 3 error de red o contenido (texto) */
int  ota_perfil_resultado(int *codigo, int *n_ok, const char **id_o_texto);
void ota_perfil_olvida(void);               /* borra el resultado (al salir de la vista) */

/* qspi_cfg.c: la QSPI es suya */
int  qspi_open(void);
void qspi_read(u32 addr, u8 *d, u32 n);
int  qspi_busy(void);
void qspi_erase64k_start(u32 addr);
void qspi_erase4k_start(u32 addr);
void qspi_prog_start(u32 addr, const u8 *d, u32 n);
void qspi_wait(void);
#endif
