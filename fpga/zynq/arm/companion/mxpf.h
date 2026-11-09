/* mxpf.h — perfiles del PL en la microSD de TF1 (30/10/2026, fase 5 del estudio de perfiles:
 * el estudio interno de perfiles, apartados 6.2 a 6.6). Formato y funcionamiento: mxpf.c y docs/tecnica/12-companion.md. */
#ifndef MXPF_H
#define MXPF_H
#include "xil_types.h"

/* --- lo que da el sistema (main.c; el banco del PC lo imita con un fichero) --------------------------------------- */
u32  tf1_sectores(void);                              /* sectores de 512 B de TF1; 0 = sin tarjeta */
int  tf1_leer(u32 sec, u32 cnt, void *buf);           /* 1 = bien. buf en memoria SIN cache (DMA de la SD) */
int  tf1_escribir(u32 sec, u32 cnt, const void *buf); /* idem */
void sd_ceder(void);                                 /* sirve la peticion de Nextor que haya pendiente (main.c) */
int  cfg_perfil_arranque(char id[9]);                 /* qspi_cfg.c: el "perfil al arrancar" (1 = hay; su id, 9 bytes) */
/* --- lo que da ota.c ----------------------------------------------------------------------------------------------- */
int  ota_ocupada(void);
u32  ota_serie(void);                                 /* serie del BOOT.bin que corre; 0 = no se sabe (JTAG) */
const char *ota_version(void);

enum { MXPF_OK = 0, MXPF_E_TARJETA, MXPF_E_MBR, MXPF_E_ENTRADAS, MXPF_E_SITIO, MXPF_E_YA, MXPF_E_SINPART, MXPF_E_DIR,
       MXPF_E_LLENO, MXPF_E_FORMATO, MXPF_E_SHA, MXPF_E_ZLIB, MXPF_E_SERIE, MXPF_E_OCUPADO, MXPF_E_PARAM, MXPF_E_NOEXISTE,
       MXPF_E_IO, MXPF_E_PCAP, MXPF_E_CORTE, MXPF_E_CONFIRMA, MXPF_E_VERIFICA, MXPF_E_JTAG,
       MXPF_E_ARRANQUE_SD, MXPF_E_FALSA, MXPF_E_N };

enum { MXS_SIN_TARJETA = 0, MXS_ERROR_TARJETA, MXS_SIN_PARTICION, MXS_OK, MXS_DANADA };

#define MXPF_MAX_PERF 6                               /* perfiles por tarjeta (una entrada de directorio cada uno) */

typedef struct {
    char id[9], version[17];
    u32  serie, lba, tam, tam_bin;                    /* lba: relativo al inicio de la particion */
    u8   metodo, hueco, sha[32];                      /* metodo: 0 crudo, 1 zlib */
} mxpf_perfil;

typedef struct {
    u8   estado;                                      /* MXS_* */
    u8   motivo;                                      /* SIN_PARTICION: MXPF_E_* por el que no se puede preparar; 0 = se puede */
    u8   n, libres, huecos;                           /* perfiles, huecos libres y huecos de la particion */
    u32  mb;                                          /* tamano de la tarjeta (MB) */
    u32  part_lba, part_secs;                         /* la particion MXPF (estado OK o DANADA) */
    u32  prep_lba, prep_secs;                         /* la que se crearia al preparar (estado SIN_PARTICION y motivo 0) */
    u32  seq;                                         /* secuencia del directorio vigente */
    u8   dir;                                         /* cual: 0 = A (sector 1), 1 = B (sector 2) */
    u8   dedicada;                                    /* el superbloque lleva el indicador de «tarjeta dedicada» (+28 bit 0); la clase NUESTRA exige ademas la disposicion */
    mxpf_perfil p[MXPF_MAX_PERF];
} mxpf_info_t;

/* tiempos de la ultima operacion (us): lee la SD, escribe la SD, relee para verificar, copia a memoria con cache, SHA-256,
 * zlib, carga por PCAP (todo perfil_cargar), total */
enum { MXT_LEE = 0, MXT_ESC, MXT_VER, MXT_COPIA, MXT_SHA, MXT_ZLIB, MXT_PCAP, MXT_TOTAL, MXT_N };
extern u32 mxpf_t[MXT_N];

const mxpf_info_t *mxpf_monta(void);                  /* relee MBR, superbloque y directorios */
const mxpf_info_t *mxpf_estado(void);                 /* el de la ultima vez */
int  mxpf_prepara(void);                              /* LEGADO (bancos y JTAG): crea una particion MXPF COMPARTIDA en el hueco libre, sin borrar nada (o rehace sus directorios). La app usa mxpf_prepara_dedicada */
int  mxpf_instala(const u8 *mxp, u32 len);            /* .mxp en la zona sin cache (PF_ZONA + 0x1000) */
int  mxpf_carga(const char *id);                      /* carga el perfil por PCAP; 0 = cargado y el MSX suelto */
int  mxpf_borra(const char *id);                      /* quien llama pide la confirmacion */
int  mxpf_vacia(u32 mb);                              /* SOLO PRUEBA: deja el MBR sin particiones. mb = tamano de la tarjeta */
int  mxpf_perfil1(void);                              /* reinicio del PS: vuelve al perfil del BOOT.bin. Solo vuelve si no se puede */
void mxpf_corte(u32 sectores);                        /* SOLO PRUEBA: la proxima operacion deja de escribir tras N sectores (apagon simulado) */
enum { MXA_PERFIL1 = 0, MXA_TARJETA, MXA_OTRO };      /* que corre ahora: el del BOOT.bin, uno de la tarjeta, uno cargado por la prueba de la DDR */
int  mxpf_pide(const char *id, int *cargado);         /* pide un perfil (etiqueta de una ROM): si ya corre, nada; si no, lo carga. MXPF_OK o por que no */
const char *mxpf_id_activo(void);                     /* "" = el perfil 1 (BOOT.bin); si no, el id del cargado de la tarjeta */
int  mxpf_arranque(const char *id);                   /* perfil al arrancar: 1 = cargado. Con una marca anti-bucle en la DDR (main.c, antes de soltar el MSX) */
int  mxpf_activo(void);
const mxpf_perfil *mxpf_activo_perfil(void);          /* el de la tarjeta si MXA_TARJETA */
void mxpf_activo_otro(void);                          /* profile.c lo ha cargado desde la DDR (perfil_poll) */
/* --- TF1 solo para perfiles (8/11/2026): clasificacion de la tarjeta y preparacion dedicada (P1 FAT32 128 MiB + P2 MXPF 512 MiB) --- */
enum { MXC_SIN_TARJETA = 0, MXC_ERROR, MXC_NUESTRA, MXC_NUESTRA_ANTIGUA, MXC_DANADA, MXC_INTERRUMPIDA, MXC_VACIA, MXC_AJENA, MXC_DEFECTUOSA };
enum { MXF_DESCONOCIDO = 0, MXF_SIN_TABLA, MXF_FAT12, MXF_FAT16, MXF_FAT32, MXF_EXFAT, MXF_NTFS, MXF_GPT, MXF_OTRO };
typedef struct {
    u8  clase;                                        /* MXC_* */
    u8  formato;                                      /* MXF_*: lo que hay en la tarjeta (de la primera particion, o del sector 0) */
    u8  nparts;                                       /* entradas usadas del MBR (0 = no se sabe, p. ej. GPT) */
    u8  msxdos;                                       /* 1 = hay una particion FAT16 (datos de MSX-DOS: la antigua B: de Nextor) */
    u8  motivo;                                       /* DEFECTUOSA: MXPF_E_SITIO (pequena) o MXPF_E_FALSA (tarjeta falsa) */
    u32 mb;                                           /* tamano (MB) */
} mxpf_clase_t;
const mxpf_clase_t *mxpf_clasifica(void);             /* solo LEE (hasta 1 MiB). Ver mxpf.c: las clases y que se hace con cada una */
const mxpf_clase_t *mxpf_clase(void);                 /* la de la ultima vez */
int  mxpf_ded_arma(void);                             /* PRIMERA tecla (B): 1 = la clase pide confirmacion y queda armada (10 s, esta tarjeta); 0 = no hace falta o no se puede */
void mxpf_ded_desarma(void);
int  mxpf_prepara_dedicada(int segunda);              /* segunda = Intro. Escribe SOLO si: no se arranco desde SD y (clase que no pide nada, o armada + segunda) */
int  mxpf_arranque_sd(void);                          /* 1 = la placa arranco desde SD (BOOT_MODE 5): la TF1 es la tarjeta de arranque y no se prepara */
int  mxpf_ded_armada(void);                           /* 1 = armada y sin caducar */
const char *mxpf_err_es(int e);
int  mxpf_poll(void);                                 /* ordenes por la zona (tools/perfiles.tcl); 1 si ha cargado un perfil */
#endif
