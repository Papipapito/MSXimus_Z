/* dual.h — la maquina B del perfil Dual desde el companion (2/11/2026): lo que el menu del MSX pide por el 93h ('W', '0'+MAPPER_ID: esta
 * ROM a B) y el panel F12 "Maquina B". dual.c; wavegame.c recoge el mensaje del Z80 y llama a dual_pide, dual_poll() lo ejecuta desde el
 * bucle principal, osd.c reparte las teclas y dibuja la pagina. */
#ifndef DUAL_H
#define DUAL_H
#include "xil_types.h"
#include "osd.h"

/* ---- el menu y el bucle principal -------------------------------------------------------------------------------------------- */
void dual_pide(u8 mapper, u32 part, u32 dir, u32 file);   /* 'W', '0'+MAPPER_ID + PART_LBA + CUR_CLUS + FILE_CLUS: la ROM elegida en el navegador, ya en la megaram de A */
void dual_poll(void);                                     /* ejecuta lo pedido (la copia tarda: no se hace dentro de wg_poll) y atiende el raton del escritorio de dos columnas */
void dual_marco_listo(u16 x, u16 y);                      /* v99desk.c: acaba de publicar el marco de B en (x, y): ahora se mueve la imagen de B (la posicion fina), para que las dos lleguen a la vez */
void dual_escritorio(u8 lay);                             /* v99desk.c, al empezar un escritorio ("V","5"/"7"/"D"/"A"): con lay 9 (dos columnas, Shift+D: la ROM en B) o 10 (D sola: la ROM en A y B arranca MSX-DOS, Nextor-B, y se queda con la SD), B a su sitio, foco en A, los dos sonidos activos y las ventanas arrastrables; con 5 o 7, B en la posicion de siempre */
const char *dual_b_etiqueta(void);                        /* lo que corre en B, para la barra de su ventana: "MSX-DOS", "BASIC" o el nombre del cartucho del menu */
u32  dual_b_ctl(void);                                    /* la palabra de control de B (16 bits bajos; 0 si no lleva la clave): dual_disco.c mira el cartucho y el mapper */
void dual_init(void);                                     /* arranque y PL recargado: la palabra de control de B a cero (en la DDR hay basura o restos) */
int  dual_activo(void);                                   /* 1 = corre el perfil Dual (el id DUAL de mxpf) */

/* ---- el panel F12 --------------------------------------------------------------------------------------------------------------- */
void dual_abre(void);                                     /* al entrar en la pagina */
void dual_tecla(u8 usage);                                /* S soltar, P parar, R reiniciar, C quitar el cartucho, T teclado A/B, V ventana, A y B silenciar / activar el sonido de A y de B, D la SD de TF2 de A o de B, M MSX-DOS en B */
int  dual_cambio(void);                                   /* 1 = hay que repintar (cambio de estado, aviso nuevo) */
void dual_pagina(osd_pag p);
extern void osd_abre_dual(void);                          /* osd.c: enciende el OSD en la pagina de B tal como esta (un aviso de dual.c) */
extern u8   v99desk_lay(void);                            /* v99desk.c: el escritorio en curso (9 = dos columnas, 5 y 7 = los otros, 0 = ninguno) */
extern void v99desk_dual_pon(u16 x, u16 y, u8 foco, u8 arrastrando);   /* v99desk.c: el marco de B con la imagen en (x, y) puntos y ese foco (1 = B) */
extern void v99desk_dual_fin(void);                       /* v99desk.c: se solto la ventana de B (si paso por las tarjetas, se repintan) */
extern void v99desk_dual_silencio(u8 a, u8 b, u8 corre);  /* v99desk.c: A y B en silencio (1) y si B corre: el cuadradito cian de la barra de B y la linea "Sonido" de la tarjeta */
extern void v99desk_dual_sd(u8 duena);                    /* v99desk.c: la duena de la SD (0 = A, 1 = B): la linea "SD" de la tarjeta de abajo */

/* ---- la parte pura (se prueba en el PC contra las mismas 24 comprobaciones de tb/check_dual_rom.py) --------------------------------------- */
/* Lo que se pide, como los argumentos de `dual_rom.tcl cargar`: mapper -1 = ninguno, 0 konami4, 1 ascii8, 2 scc, 3 ascii16; lineal 1 =
 * "lineal"; plano -1 = no, 3 = "plain" (la pagina por la cabecera), 0..2 = "plain0/1/2". Sin pedir nada: hasta 32 KB plana, mas, konami4. */
typedef struct { int mapper, lineal, plano; } dual_pedido_t;
enum { DP_OK = 0, DP_PLAIN_Y_MAPPER, DP_PLANA_GRANDE, DP_NO_CABE, DP_GRANDE, DP_VACIA };       /* por que no se puede */
enum { DM_AB_INIT2 = 0, DM_AB_INIT1, DM_AB_SINPUNT, DM_AB_GRANDE, DM_AB_4000, DM_SIN_AB, DM_PEDIDA, DM_MAPPER };   /* por que ahi */
typedef struct {
    int plano;                  /* 1 = ROM plana dentro de una imagen de 64 KB (FFh alrededor); 0 = la ROM desde el principio */
    u32 off;                    /* plana: 0, 4000h u 8000h */
    int map, lin;               /* B_CTL[4:3] y B_CTL[5] */
    int motivo;                 /* DM_* */
} dual_plan_t;
int  dual_plan(const volatile u8 *rom, u32 tam, const dual_pedido_t *pd, dual_plan_t *pl);       /* DP_* */
void dual_compone(const volatile u32 *src, u32 tam, const dual_plan_t *pl, volatile u32 *dst);    /* la imagen del cartucho en dst (palabras) */
void dual_aplica(const volatile u32 *src, u32 tam, const dual_plan_t *pl);                       /* parar B, componer en el cartucho, declararlo y soltar */
int  dual_pedido_menu(u8 mapper_id, dual_pedido_t *pd);                                          /* MAPPER_ID del menu -> pedido; 0 = B no lo admite */

extern u32 fat_nombre_tam(void);                          /* wavegame.c: tamano del fichero del ultimo fat_nombre */
extern int fat_nombre(u32 part, u32 dir_clus, u32 file, char *out, u32 cap);
#endif
