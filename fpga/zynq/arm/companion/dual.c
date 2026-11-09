/* dual.c — la maquina B del perfil Dual desde el companion (2/11/2026; docs/tecnica/14-perfil-dual.md). Dos cosas:
 *
 *  1) LANZAR UN JUEGO EN B DESDE EL MENU DE A. En la pantalla "Lanzar ROM" la tecla D manda por el 93h (wavegame.c) 'W', '0'+MAPPER_ID +
 *     PART_LBA + CUR_CLUS + FILE_CLUS: la misma trama de 14 bytes que 'W','G', con el mapper que eligio el menu en el segundo byte. La ROM
 *     YA esta en la megaram de A (el menu la carga antes de preguntar): la imagen lineal empieza en 0x10C00000 (segmentos 0-255, A21 = 0;
 *     una ROM de B llega a 2 MB). Aqui se COPIA a la zona del cartucho de B (0x0C400000) componiendo la imagen igual que
 *     tools/dual_rom.tcl cargar (las mismas 24 comprobaciones de tb/check_dual_rom.py, contra este C en tests/dual_host):
 *       - hasta 32 KB (mapper "Plain" del menu): PLANA, en la pagina que dice su cabecera (8000h-BFFFh para una ROM de pagina 2 como
 *         Stop the Express), dentro de una imagen de 64 KB con FFh alrededor, y el cartucho en modo lineal (B_CTL[5]);
 *       - mas de 32 KB, o con mapper elegido: Konami (0), ASCII8 (1), Konami-SCC (2, sin sonido) o ASCII16 (3), la ROM desde el principio;
 *       - "Plain 0000h": lineal, desde 0000h;
 *       - NEO-8, NEO-16 y ASCII16-X no existen en B, ni una ROM de mas de 2 MB: el panel lo dice.
 *     Como el script: parar B (reset ordenado, el PL mira la palabra cada ~1 ms: 30 ms), escribir la imagen, declarar el cartucho y soltar.
 *     No toca el foco del teclado (bit 2) ni la ventana (bits 6 y 8-15). Solo con el perfil Dual (mxpf_id_activo() == "DUAL"): si no, el
 *     panel F12 dice "B solo existe en el perfil Dual". CACHE: la DDR de B la lee el PL por AXI, y aqui no hay nada que limpiar: toda esta
 *     memoria es strongly-ordered (mmu.c solo da cache al codigo, al MP3, al heap de TLS y a la zona de la OTA), asi que basta un dsb.
 *     La ROM de A y su cabecera: el menu, tras mandar la trama, envenena el "AB" de la megaram de A (meg_disarm_esc, como al salir con
 *     ESC); lo hace DESPUES de pintar el escritorio (decenas de ms) y la copia empieza por el principio de la ROM.
 *
 *  2) EL PANEL F12 "Maquina B" (tecla B de la pagina de informacion, solo con el Dual): estado (corre/parada, foco del teclado, ventana),
 *     el cartucho (nombre y mapper si lo puso el menu) y las teclas S soltar, P parar, R reiniciar, C quitar el cartucho (B vuelve a
 *     BASIC), T teclado a B/libre y V ventana de B visible/oculta. El foco "A" es "libre": la tecla Insert sigue alternando A y B (el PL
 *     lleva su propio flip-flop y el ARM no lo ve); T fuerza el teclado a B (B_CTL[2]) y otra T lo suelta.
 *
 *  3) EL ESCRITORIO DE DOS COLUMNAS (2/11/2026, tecla D del menu: v99desk.c layout 9): A a la izquierda (el gestor de ventanas por hardware) y B a
 *     la derecha, las dos arrastrables con el raton y con foco. Aqui: la posicion FINA de B (punto a punto: bit 7 de la palabra de control y
 *     una segunda palabra en 0x1FFB0008), el foco del teclado (el ARM pide A o B por esa segunda palabra y lee el que hay en la telemetria) y
 *     el raton: el PL deja en MBOX+0xD0 el puntero, el boton y la esquina de la ventana de A una vez por cuadro; un clic dentro de una ventana
 *     le da el foco, un clic en la barra de titulo de B la arrastra (v99desk.c repinta su marco). Insert sigue alternando el teclado.
 *
 *  4) (Z1.3.2b8) LA D SOLA DEL MENU lanza la ROM en A (el camino de RETURN y V) con este mismo escritorio ("V","A", dual_escritorio(10)) y deja a
 *     B corriendo SIN cartucho (MSX BASIC) como segunda maquina, si no corria ya; Shift+D es lo de siempre (la ROM a B, "V","D"). Y EL SILENCIO POR
 *     MAQUINA: el cuadradito cian de la barra de cada ventana silencia o activa el sonido de esa maquina (clic detectado aqui con el puntero de la
 *     telemetria; A: el que pinta el gestor de ventanas, B: el que pinta v99desk.c), y en el panel F12 las teclas A y B. Es la segunda palabra: bits
 *     [22]/[23] y [24]/[25] = peticion (cada cambio) y valor del silencio de A y de B; el PL (dual_mute.v) los aplica y los quita solo con B parada;
 *     el estado real vuelve en la telemetria (bits 47 y 48).
 *
 *  5) (Z1.3.2b9) MSX-DOS EN B (dual_disco.c): la D sola del menu lanza la ROM en A y B arranca Nextor-B y se queda con la SD de TF2, que ve a traves
 *     de un buzon en la DDR (la misma tarjeta que A; la duena escribe, la otra solo lee). Reglas (docs/tecnica/14, apartado 14.4):
 *       - la que GANA la escritura y corre DOS se reinicia: B recompone Nextor-B (como la tecla M); A solo recibe un aviso en el panel ("reinicia A"),
 *         porque no hay forma de reiniciarla desde aqui sin perder lo que haga. Excepcion: la D sola con B ya corriendo Nextor-B Y ya duena no
 *         la toca (puede estar copiando ficheros).
 *       - la SD vuelve SOLA a A cuando B deja de correr Nextor-B (P, reinicio al BASIC, C, Shift+D, un cartucho cambiado por JTAG): dual_poll.
 *       - la D sola deja a A con la escritura SOLO en los sectores de sus .SRM (la partida y la Game Master 2; rangos sacados de los descriptores
 *         del menu): asi A guarda la SRAM al volver al menu aunque B tenga la SD. Todo lo demas que A escriba se rechaza.
 *     Shift+D carga una ROM en B: Nextor-B se va y la SD vuelve a A. En el panel F12: D cambia la duena de la SD (solo con Nextor-B en B) y M pone
 *     Nextor-B en B (sin cambiar la duena); C quita el cartucho (tambien Nextor-B). dual_b_etiqueta() dice "MSX-DOS" mientras B lo corre.
 *
 * La palabra de control (MBOX V9_BASE+4 = 0x1FFB0004) solo vale con la clave D0A1h en [31:16]; la DDR arranca con basura. Bits: [0] B corre,
 * [1] hay cartucho, [2] teclado a B, [4:3] mapper, [5] lineal, [6] sin el rectangulo de B, [7] posicion fina, [11:8]/[15:12] posicion. */
#include "xil_types.h"
#include "log.h"
#include "osd.h"
#include "mxpf.h"
#include "perfiles.h"
#include "dual.h"
#include "dual_disco.h"
#ifdef DUAL_HOST                                           /* banco del PC (tests/dual_host): las mismas direcciones, con mmap */
#define D_DSB()         ((void)0)
extern void dual_usleep(unsigned long us);
#define D_USLEEP(us)    dual_usleep(us)
#else
#include "sleep.h"
#define D_DSB()         __asm__ volatile ("dsb" ::: "memory")
#define D_USLEEP(us)    usleep(us)
#endif
#define D_CTLW          ((volatile u32 *)0x1FFB0004U)      /* palabra de control de B */
#define D_CART          ((volatile u32 *)0x0C400000U)      /* cartucho de B (A21 = 0), hasta 2 MB */
#define D_MEG           ((const volatile u32 *)0x10C00000U) /* megaram de A, segmentos 0-255 */
#define D_DESC_SRM      ((const volatile u8 *)0x10BFE000U)  /* "SRM1" de bios/src/srm_saves.asm: segmento 511 de la megaram de A (A21 = 1: ram_addr = 0x3FE000): +4 cluster de FHUNT, +6 cluster del .SRM (32 KB) */
#define D_DESC_GM2      ((const volatile u8 *)0x10BF2000U)  /* "GM2S" de bios/src/gm2.asm: segmento 497 (0x3F2000): +6 cluster de GM2.SRM (8 KB) */
#define MAX_RG          16                                   /* rangos de excepcion de A (dual_disco_rangos_a) */
extern int fat_extents(u32 part, u32 first, u32 nbytes, u32 *lo, u32 *n, int max);   /* wavegame.c: los rangos de sectores de la cadena de clusters de un fichero */
extern u32 wg_part_lanzada(void);                            /* wavegame.c: PART_LBA del ultimo 'W','G' (la ROM que se acaba de lanzar) */

#define BC_CLAVE        0xD0A10000U
#define BC_CORRE        0x0001U
#define BC_CART         0x0002U
#define BC_TECLADO      0x0004U
#define BC_LINEAL       0x0020U
#define BC_SINVENT      0x0040U
#define BC_FINA         0x0080U                            /* posicion fina: la columna y la fila salen de la segunda palabra */
#define D_CTL2W         ((volatile u32 *)0x1FFB0008U)      /* segunda palabra: [9:0] columna, [18:10] fila (puntos del frame buffer), [20] y [21] peticion de foco */
#define D_TELW          ((volatile u32 *)0x1FF000D0U)      /* telemetria del PL (64 bits, MBOX+0xD0): puntero, ventana de A, foco */
#define C2_TGL          (1U << 20)                         /* cada cambio de este bit es una peticion de foco ... */
#define C2_FOCO_B       (1U << 21)                         /* ... a B (1) o a A (0) */
#define C2_SIL_A_TGL    (1U << 22)                         /* Z1.3.2b8: cada cambio de este bit es una peticion de silencio de A ... */
#define C2_SIL_A        (1U << 23)                         /* ... 1 = silenciar A, 0 = dejarla sonar */
#define C2_SIL_B_TGL    (1U << 24)                         /* lo mismo para B */
#define C2_SIL_B        (1U << 25)
#define C2_CTRL         (C2_TGL | C2_FOCO_B | C2_SIL_A_TGL | C2_SIL_A | C2_SIL_B_TGL | C2_SIL_B)   /* lo que NO es posicion en la segunda palabra */
#define MAX_ROM         0x200000U
#define IMG_PALABRAS    0x4000U                            /* la imagen de 64 KB del cartucho plano / el multiplo de 64 KB que se rellena de FFh */

/* ---- la palabra de control ----------------------------------------------------------------------------------------------------- */
static u32  ctl_get(void) { u32 c = *D_CTLW; return (c & 0xFFFF0000U) == BC_CLAVE ? (c & 0xFFFFU) : 0U; }
static void ctl_set(u32 v) { *D_CTLW = BC_CLAVE | (v & 0xFFFFU); D_DSB(); }
static void ctl_bits(u32 mask, u32 val) { ctl_set((ctl_get() & ~mask) | (val & mask)); }

int dual_activo(void)
{
    const char *id = mxpf_id_activo();
    return id[0] == 'D' && id[1] == 'U' && id[2] == 'A' && id[3] == 'L' && !id[4];
}

/* ---- la parte pura: que cartucho se compone ----------------------------------------------------------------------------------------- */
static u32 le16(const volatile u8 *p) { return (u32)p[0] | ((u32)p[1] << 8); }

/* pagina (0, 1 o 2 = 0000h, 4000h, 8000h) de una ROM plana de hasta 32 KB: la cabecera decide, como rom_plana_pagina de dual_rom.tcl y como
 * el menu de A (lin0_detect y mir16_calc de bios/src) */
static int pagina_plana(const volatile u8 *rom, u32 tam, int *motivo)
{
    if (tam >= 2U && rom[0] == 'A' && rom[1] == 'B') {
        u32 k;
        if (tam > 0x4000U) { *motivo = DM_AB_GRANDE; return 1; }                  /* 17-32 KB: 4000h-BFFFh */
        for (k = 0; k < 4U; k++) {                                                /* INIT, STATEMENT, DEVICE, TEXT */
            u32 p = (3U + 2U * k < tam) ? le16(rom + 2U + 2U * k) : 0U;
            if (p) {
                if ((p >> 14) == 2U) { *motivo = DM_AB_INIT2; return 2; }         /* ROM de pagina 2 (Stop the Express, INIT = BFF0h) */
                *motivo = DM_AB_INIT1;
                return 1;
            }
        }
        *motivo = DM_AB_SINPUNT;
        return 1;
    }
    if (tam >= 0x4004U && rom[0x4000] == 'A' && rom[0x4001] == 'B') {              /* "Plain 0000h" del menu */
        u32 init = le16(rom + 0x4002);
        if (init >= 0x4000U && init < 0x8000U) { *motivo = DM_AB_4000; return 0; }
    }
    *motivo = DM_SIN_AB;                                                          /* la BIOS no la arrancara sola */
    return 1;
}

int dual_plan(const volatile u8 *rom, u32 tam, const dual_pedido_t *pd, dual_plan_t *pl)
{
    int plano = pd->plano, pedido = pd->mapper >= 0 || pd->lineal;
    pl->plano = 0; pl->off = 0; pl->map = 0; pl->lin = 0; pl->motivo = DM_PEDIDA;
    if (!tam) return DP_VACIA;
    if (tam > MAX_ROM) return DP_GRANDE;
    if (plano >= 0 && pedido) return DP_PLAIN_Y_MAPPER;
    if (plano < 0 && !pedido && tam <= 0x8000U) plano = 3;                         /* como el menu de A: hasta 32 KB, plana */
    if (plano >= 0) {
        int pag;
        if (tam > 0x8000U) return DP_PLANA_GRANDE;
        if (plano == 3) pag = pagina_plana(rom, tam, &pl->motivo);
        else pag = plano;
        pl->off = (u32)pag * 0x4000U;
        if (pl->off + tam > 0xC000U) return DP_NO_CABE;                            /* un cartucho llega hasta BFFFh */
        pl->plano = 1; pl->map = 0; pl->lin = 1;                                   /* el modo plano es el lineal de megaram_scc */
        return DP_OK;
    }
    pl->map = pd->mapper >= 0 ? pd->mapper : 0;                                    /* sin decir nada y mas de 32 KB: konami4 */
    pl->lin = pd->lineal ? 1 : 0;
    pl->motivo = pedido ? DM_PEDIDA : DM_MAPPER;
    return DP_OK;
}

static void copia(volatile u32 *d, const volatile u32 *s, u32 n) { while (n--) *d++ = *s++; }
static void rellena(volatile u32 *d, u32 n, u32 v) { while (n--) *d++ = v; }

/* la imagen de dual_rom.tcl cargar: plana = FFh hasta la pagina, la ROM y FFh hasta los 64 KB; si no, la ROM desde el principio y FFh hasta el
 * siguiente multiplo de 64 KB (para que el cartucho no ensene basura donde acaba) */
void dual_compone(const volatile u32 *src, u32 tam, const dual_plan_t *pl, volatile u32 *dst)
{
    u32 nw = (tam + 3U) >> 2, ow = pl->plano ? pl->off >> 2 : 0U, fin = ow + nw, tope;
    if (ow) rellena(dst, ow, 0xFFFFFFFFU);
    copia(dst + ow, src, nw);
    tope = pl->plano ? IMG_PALABRAS : (((tam + 0xFFFFU) & ~0xFFFFU) >> 2);
    if (fin < tope) rellena(dst + fin, tope - fin, 0xFFFFFFFFU);
}

/* MAPPER_ID del menu (bios/src/menu_main.asm) -> lo que se le pide a B. 0 = B no lo admite */
int dual_pedido_menu(u8 id, dual_pedido_t *pd)
{
    pd->mapper = -1; pd->lineal = 0; pd->plano = -1;
    switch (id) {
        case 0: return 1;                                      /* Plain: la eleccion automatica */
        case 2: pd->mapper = 0; return 1;                      /* Konami */
        case 3: pd->mapper = 2; return 1;                      /* Konami-SCC */
        case 4: pd->mapper = 1; return 1;                      /* ASCII8 */
        case 5: pd->mapper = 3; return 1;                      /* ASCII16 */
        case 8: pd->lineal = 1; return 1;                      /* Plain 0000h */
        default: return 0;                                     /* NEO-8, NEO-16, ASCII16-X, desconocido */
    }
}

/* ---- el estado que enseña el panel ---------------------------------------------------------------------------------------------- */
static struct {
    u8   hay;                                                  /* el cartucho lo puso el menu y sigue puesto */
    char nombre[48];
    u32  tam;
    u32  bits;                                                 /* B_CTL[5:3] que puso el menu: si la palabra dice otra cosa, el cartucho ya no es el suyo */
    dual_plan_t pl;
} cart;
static char aviso_txt[96];
static u8   aviso_ok, sucio = 1;
static u32  ctl_vista;

static u32 ctl2;                                                    /* lo ultimo escrito en la segunda palabra (el ARM es su dueno) */
static struct { u8 on, arr, btn, foco, espera, vista, sa, sb, esa, esb, corre; u16 bx, by, cnt; int ox, oy; } rt;   /* el escritorio de dos columnas (sa, sb: A y B en silencio; esa, esb: muestras que se ignoran tras pedirlo) */
static u32 sil_vista;                                               /* el silencio real que vio el panel por ultima vez: bit 0 = A, bit 1 = B */

void dual_init(void) { *D_CTLW = 0U; *D_CTL2W = 0U; ctl2 = 0U; rt.on = 0; rt.sa = 0; rt.sb = 0; D_DSB(); cart.hay = 0; dual_disco_init(); }       /* arranque y PL recargado (sin Nextor-B, la SD es de A) */
u32 dual_b_ctl(void) { return ctl_get(); }

static void scpy(char *d, const char *s, u32 cap) { u32 i = 0; while (s[i] && i + 1U < cap) { d[i] = s[i]; i++; } d[i] = 0; }
static void pon(const char *s, int ok) { scpy(aviso_txt, s, sizeof aviso_txt); aviso_ok = (u8)ok; sucio = 1; }
static char *cat(char *d, const char *s) { while (*s) *d++ = *s++; *d = 0; return d; }

static const char *dp_txt(int r)
{
    switch (r) {
        case DP_VACIA:         return T("La ROM está vacía.", "The ROM is empty.");
        case DP_GRANDE:        return T("La ROM no cabe en B (máximo 2 MB).", "The ROM does not fit in B (2 MB max).");
        case DP_PLANA_GRANDE:  return T("Una ROM plana mide hasta 32 KB.", "A plain ROM is 32 KB at most.");
        case DP_NO_CABE:       return T("La ROM no cabe en esa página.", "The ROM does not fit in that page.");
        default:               return T("Petición no válida.", "Invalid request.");
    }
}

/* un aviso a quien mira: con el Dual, la pagina de B; con otro perfil, la de perfiles (que es donde se carga el Dual) */
static void aviso(const char *txt, int ok)
{
    pon(txt, ok);
    log_str("dual: "); log_str(txt); log_str("\n");
    if (dual_activo()) osd_abre_dual();
    else { perfiles_aviso_abre(txt, ok, 0); osd_abre_perfiles(); }
}

/* ---- B: soltar, parar... (lo que hace dual_rom.tcl) --------------------------------------------------------------------------------------- */
static void parar(void) { ctl_bits(BC_CORRE, 0U); D_USLEEP(30000); }      /* el PL lee la palabra cada ~1 ms y la parada ordenada tarda ~1 us */
static void soltar(void) { ctl_bits(BC_CORRE, BC_CORRE); }
static void sd_vista(void) { v99desk_dual_sd((u8)dual_disco_duena()); }   /* la duena de la SD en la tarjeta de abajo del escritorio de dos columnas (v99desk.c): tras cada cambio posible */

/* la SD vuelve a A (B deja de correr Nextor-B). Si B escribio mientras la tenia, el MSX-DOS de A puede tener datos viejos en sus bufer: aviso en el
 * panel (no se abre solo: A puede estar jugando). Devuelve 1 si hubo aviso */
static int sd_a(void)
{
    int aviso;
    dual_disco_pon_duena(0);
    sd_vista();
    aviso = dual_disco_toma_aviso_a();
    if (aviso) pon(T("SD de A. Reinicia A si usa MSX-DOS (B escribió).", "SD is A's. Restart A if it runs MSX-DOS (B wrote)."), 1);
    return aviso;
}

/* A conserva la escritura en los .SRM de su partida (y de la Game Master 2) cuando B pase a ser la duena de la SD: el menu los crea o los carga en el
 * lanzamiento (srm_launch, ANTES de mandar "V","A") y deja sus descriptores en la megaram; aqui se sacan de ellos los rangos de sectores (cluster a
 * cluster: el .SRM puede estar partido). Sin descriptor, sin FAT16 montada o con el fichero mas largo de DD_MAX_RG rangos: A no escribe nada */
static int rangos_de(const volatile u8 *d, const char *magic, u32 bytes, u32 part, u32 *lo, u32 *n, int max)
{
    u32 clus;
    int k, i;
    for (i = 0; i < 4; i++) if (d[i] != (u8)magic[i]) return 0;
    clus = le16(d + 6);
    if (clus < 2U) return 0;
    k = fat_extents(part, clus, bytes, lo, n, max);
    return k > 0 ? k : 0;
}

static void rangos_a(void)
{
    u32 lo[MAX_RG], n[MAX_RG], part = wg_part_lanzada();
    int k = rangos_de(D_DESC_SRM, "SRM1", 0x8000U, part, lo, n, MAX_RG);
    k += rangos_de(D_DESC_GM2, "GM2S", 0x2000U, part, lo + k, n + k, MAX_RG - k);
    dual_disco_rangos_a(lo, n, k);
    log_str("dual: A conserva la escritura en "); log_dec((u32)k); log_str(" rangos de sectores (sus .SRM)\n");
}

/* parar B, escribir el cartucho, declararlo y soltar (lo que hace `dual_rom.tcl cargar`); src = la ROM en palabras */
void dual_aplica(const volatile u32 *src, u32 tam, const dual_plan_t *pl)
{
    parar();                                                   /* B en reset: su cache de RAM se invalida y nadie lee la zona */
    dual_compone(src, tam, pl, D_CART);
    D_DSB();
    ctl_bits(0x3BU, BC_CART | ((u32)pl->map << 3) | (pl->lin ? BC_LINEAL : 0U));   /* cartucho + mapper + lineal; no toca el teclado (2) ni la ventana */
    D_USLEEP(10000);
    soltar();
}

/* ---- lo que pide el menu ------------------------------------------------------------------------------------------------------------------ */
static struct { u8 que, mapper; u32 part, dir, file; } pend;

void dual_pide(u8 mapper, u32 part, u32 dir, u32 file)
{
    pend.mapper = mapper; pend.part = part; pend.dir = dir; pend.file = file; pend.que = 1;
}

static void carga_menu(u8 mapper, u32 part, u32 dir, u32 file)
{
    char nombre[sizeof cart.nombre];
    dual_pedido_t pd;
    dual_plan_t pl;
    u32 tam;
    int r;
    if (!dual_activo()) { aviso(T("B solo existe en el perfil Dual.", "B only exists in the Dual profile."), 0); return; }
    if (!fat_nombre(part, dir, file, nombre, sizeof nombre)) { aviso(T("No encuentro la ROM en la TF2.", "Can't find the ROM on TF2."), 0); return; }
    tam = fat_nombre_tam();
    if (!dual_pedido_menu(mapper, &pd)) { aviso(T("B no admite este mapper (NEO, ASCII16-X).", "B doesn't support this mapper (NEO, ASCII16-X)."), 0); return; }
    r = dual_plan((const volatile u8 *)D_MEG, tam, &pd, &pl);
    if (r != DP_OK) { aviso(dp_txt(r), 0); return; }
    dual_disco_quita_nextor_b();                           /* el cartucho de B va a ser otro: Nextor-B se va y la SD vuelve a A */
    (void)dual_disco_toma_aviso_a();                       /* (A esta en el menu, sin MSX-DOS en marcha: nada que reiniciar) */
    dual_aplica(D_MEG, tam, &pl);
    sd_vista();
    cart.hay = 1; scpy(cart.nombre, nombre, sizeof cart.nombre); cart.tam = tam; cart.pl = pl;
    cart.bits = ((u32)pl.map << 3) | (pl.lin ? BC_LINEAL : 0U);
    sucio = 1;
    aviso_txt[0] = 0;
    log_str("dual: "); log_str(nombre); log_str(" a B, "); log_dec(tam); log_str(" B, mapper "); log_dec((u32)pl.map);
    if (pl.plano) { log_str(", plana en "); log_hex(pl.off); } else if (pl.lin) log_str(", lineal");
    log_str("\n");
}

static void dual_raton(void);
void dual_poll(void)
{
    dual_raton();
    if (dual_disco_duena() && !dual_disco_b_corre()) {      /* B ya no corre Nextor-B (P, un cartucho cambiado por JTAG...): la SD vuelve sola a A */
        if (!sd_a()) pon(T("SD de A: B ya no corre MSX-DOS.", "SD is A's: B no longer runs MSX-DOS."), 1);
        log_str("dual: B ya no corre MSX-DOS: la SD vuelve a A\n");
    }
    if (!pend.que) return;
    pend.que = 0;
    carga_menu(pend.mapper, pend.part, pend.dir, pend.file);
}

/* ---- el escritorio de dos columnas: posicion fina de B, foco y raton ------------------------------------------------------------------- */
/* Geometria (puntos del B5 de 640 x 400; en la HDMI un punto mide 2 px de ancho y 1,5 de alto y la imagen empieza en la fila 60): la imagen de B
 * (256 x 212 puntos) por defecto en (362, 48), con su marco de 2 puntos a cada lado, 16 arriba (la barra de 24 px) y 3 abajo; A (608 x 318 px) en
 * (44, 132) px con su marco de 4 px a los lados y 24 arriba (R#56-R#59 del menu: v9k_wregs_dual). */
#define DEF_X       362U
#define DEF_Y       48U
#define MX_MIN      2U                                     /* el marco (2 puntos a la izquierda) entero en el escritorio */
#define MX_MAX      382U                                   /* 640 - 258 */
#define MY_MIN      41U                                    /* el marco (16 filas arriba) por debajo de la barra de 24 filas */
#define MY_MAX      185U                                   /* 400 - 215 */
#define A_W         608                                    /* la ventana de A: 608 x 318 px */
#define A_H         318
#define ESPERA_FOCO 3                                      /* muestras del PL que se ignoran tras pedir un foco (la telemetria aun trae el de antes) */

static void ctl2_set(u32 v) { ctl2 = v; *D_CTL2W = v; D_DSB(); }
static void ctl2_pos(u16 x, u16 y) { ctl2_set((ctl2 & C2_CTRL) | (u32)(x & 0x3FFU) | ((u32)(y & 0x1FFU) << 10)); }
static void pide_foco(int b)                              /* cada peticion invierte C2_TGL; el PL la ve en su ronda (~1 ms) */
{
    u32 v = (ctl2 & ~(C2_TGL | C2_FOCO_B)) | (~ctl2 & C2_TGL) | (b ? C2_FOCO_B : 0U);
    ctl2_set(v);
    rt.foco = (u8)(b != 0); rt.espera = ESPERA_FOCO;
}

/* Z1.3.2b8: silencio de A (b = 0) o de B (b = 1): como el foco, una peticion es invertir el bit de peticion y poner el valor (1 = en silencio).
 * Solo vale con la posicion fina encendida y B corriendo (dual_mute.v: con B parada, un reset de A o el PL recien cargado se quitan solos). */
#define ESPERA_SIL  3                                      /* muestras del PL que se ignoran tras pedirlo (la telemetria aun trae el estado de antes) */
static void pide_silencio(int b, int sil)
{
    u32 tgl = b ? C2_SIL_B_TGL : C2_SIL_A_TGL, val = b ? C2_SIL_B : C2_SIL_A;
    ctl2_set((ctl2 & ~(tgl | val)) | (~ctl2 & tgl) | (sil ? val : 0U));
    if (b) { rt.sb = (u8)(sil != 0); rt.esb = ESPERA_SIL; } else { rt.sa = (u8)(sil != 0); rt.esa = ESPERA_SIL; }
}

/* el silencio de A (bit 0) y de B (bit 1): el real de la telemetria salvo el de una peticion en vuelo, que aun no sale en ella (dos teclas A en
 * la misma vuelta del panel parten de lo pedido por la primera, y la fila "Sonido" del panel no contradice al aviso) */
static int tel_lee(u32 *lo, u32 *hi);
static u32 sil_actual(void)
{
    u32 lo, hi, s = sil_vista;
    if (tel_lee(&lo, &hi)) s = (hi >> 15) & 3U;
    if (!rt.on || v99desk_lay() != 9) return s;            /* sin el escritorio de dos columnas dual_raton no mira las muestras: solo la telemetria */
    if (rt.esa) s = (s & ~1U) | rt.sa;
    if (rt.esb) s = (s & ~2U) | ((u32)rt.sb << 1);
    return s;
}

/* la telemetria del PL (dos lecturas del alto y una del bajo: si el PL escribio entre medias, 0 y se reintenta) */
static int tel_lee(u32 *lo, u32 *hi)
{
    u32 h1 = D_TELW[1], l = D_TELW[0], h2 = D_TELW[1];
    if (h1 != h2) return 0;
    *lo = l; *hi = h2;
    return 1;
}

/* la D sola del menu: B corre MSX-DOS (Nextor-B) como segunda maquina y se queda con la SD. B GANA la escritura, asi que se recompone Nextor-B (se
 * reinicia: sus bufer pueden estar viejos) SALVO que ya corriera Nextor-B Y ya fuera la duena: entonces no se la toca (puede estar copiando ficheros).
 * Sin el perfil Dual, o si Nextor-B no se puede preparar: como antes, B corre sin cartucho (MSX BASIC) si no corria ya */
static void b_arranca(void)
{
    if (dual_activo()) {
        int antes = dual_disco_duena();
        if (antes && dual_disco_b_corre()) {
            sd_vista();
            log_str("dual: B ya corre MSX-DOS con la SD: se queda como esta (la D del menu)\n");
            return;
        }
        dual_disco_pon_duena(1);                           /* ANTES de componer: la imagen ya lleva la duena buena cuando B arranca */
        if (dual_disco_compone()) {
            ctl_bits(BC_TECLADO, 0U);                      /* el teclado de A (una T del panel lo habia forzado a B) */
            cart.hay = 0;                                  /* el cartucho que pusiera el menu ya no esta */
            sd_vista();
            log_str("dual: B arranca Nextor-B (MSX-DOS) y se queda con la SD (la D del menu)\n");
            return;
        }
        dual_disco_pon_duena(antes);                       /* no se pudo: B ni se ha tocado y la SD no cambia */
    }
    if (ctl_get() & BC_CORRE) return;
    ctl_bits(BC_CART | BC_TECLADO, 0U);                    /* B esta en reset: sin cartucho (el de antes ya no vale) y el teclado de A */
    cart.hay = 0;
    soltar();
    log_str("dual: B arranca sin cartucho (la D del menu)\n");
}

/* lo que corre en B, para la barra de su ventana (v99desk.c, escritorio con el juego en A) */
const char *dual_b_etiqueta(void)
{
    if (dual_disco_nextor_b()) return "MSX-DOS";
    if (!(ctl_get() & BC_CART)) return "BASIC";
    return cart.hay ? cart.nombre : T("cartucho", "cartridge");
}

void dual_escritorio(u8 lay)
{
    int a_juega = (lay == 10);                             /* la D sola (b8): el juego esta en A y B arranca como segunda maquina */
    rt.on = 0; rt.arr = 0; rt.btn = 0; rt.vista = 0; rt.sa = 0; rt.sb = 0; rt.esa = 0; rt.esb = 0; rt.corre = 1;
    if (a_juega) lay = 9;
    if (lay != 9) {                                        /* V y B: B en su sitio de siempre (columna 192, fila 188) */
        if (ctl_get() & BC_FINA) {                         /* sin la posicion fina el PL no mira los silencios: se quitan antes de apagarla (A no queda muda sin que se vea) */
            pide_silencio(0, 0); pide_silencio(1, 0);
            D_USLEEP(3000);
        }
        ctl_bits(BC_FINA, 0U);
        return;
    }
    rt.bx = DEF_X; rt.by = DEF_Y; rt.foco = 0;
    ctl2_pos(rt.bx, rt.by);
    D_USLEEP(3000);                                        /* el PL ve la segunda palabra con la posicion fina aun apagada: sigue la cuenta de peticiones sin hacerles caso */
    ctl_bits(BC_FINA, BC_FINA);
    D_USLEEP(3000);
    pide_foco(0);                                          /* el teclado empieza en A */
    pide_silencio(0, 0); pide_silencio(1, 0);              /* cada escritorio nuevo empieza con el sonido de las dos maquinas (y se ignoran unas muestras: la telemetria aun trae lo de antes) */
    if (a_juega) { if (dual_activo()) rangos_a(); b_arranca(); }   /* D sola: A conserva la escritura en sus .SRM y B de segunda maquina, con MSX-DOS; Shift+D (lay 9): B recibe la ROM de la trama del menu */
    sd_vista();
    rt.corre = (u8)((ctl_get() & BC_CORRE) != 0);          /* con Shift+D, B sigue parada hasta que acaba la copia */
    v99desk_dual_pon(rt.bx, rt.by, 0, 0);
    v99desk_dual_silencio(0, 0, rt.corre);
    rt.on = 1;
}

/* v99desk.c publico el marco de B en (x, y): la imagen de B se mueve a ese sitio (si el puntero no la ha llevado ya a otro: entonces llegara otra tanda).
 * Asi marco e imagen van juntos en vez de la imagen ~2 cuadros por delante del marco al arrastrar deprisa. */
void dual_marco_listo(u16 x, u16 y) { if (rt.on && x == rt.bx && y == rt.by) ctl2_pos(x, y); }

/* el raton: una muestra por cuadro. [10:0] x, [20:11] y del puntero (px de la HDMI), [21] boton izquierdo, [22] arrastra A, [23] el gestor de
 * ventanas esta en pantalla, [34:24] x, [44:35] y de la ventana de A, [45] el teclado esta en B, [46] B corre, [47] A en silencio, [48] B en silencio, [63:49] cuenta de muestras (15 bits) */
static void dual_raton(void)
{
    u32 lo, hi;
    int px, py, wx, wy, dx, dy, btn, wact, corre, f_real, en_a, en_b, en_barra, en_sa, en_sb;
    if (!rt.on || v99desk_lay() != 9) return;
    if (!tel_lee(&lo, &hi)) return;                        /* el PL escribio entre las dos lecturas: la proxima vez */
    if (rt.vista && (u16)(hi >> 17) == rt.cnt) return;     /* sin muestra nueva (la cuenta son 15 bits desde la b8) */
    rt.vista = 1; rt.cnt = (u16)(hi >> 17);
    px = (int)(lo & 0x7FFU); py = (int)((lo >> 11) & 0x3FFU); btn = (int)((lo >> 21) & 1U); wact = (int)((lo >> 23) & 1U);
    wx = (int)(((lo >> 24) | (hi << 8)) & 0x7FFU); wy = (int)((hi >> 3) & 0x3FFU);
    f_real = (int)((hi >> 13) & 1U); corre = (int)((hi >> 14) & 1U);
    if (rt.espera) rt.espera--;
    else if (f_real != rt.foco) rt.foco = (u8)f_real;      /* Insert (o la tecla T del panel) cambio el foco */
    if (rt.esa && ((hi >> 15) & 1U) != rt.sa) rt.esa--;    /* el silencio real: tambien lo quitan solos la parada de B y el reset de A; */
    else { rt.esa = 0; rt.sa = (u8)((hi >> 15) & 1U); }    /* una peticion que ya se ve en la telemetria no espera mas */
    if (rt.esb && ((hi >> 16) & 1U) != rt.sb) rt.esb--;
    else { rt.esb = 0; rt.sb = (u8)((hi >> 16) & 1U); }
    rt.corre = (u8)corre;
    v99desk_dual_silencio(rt.sa, rt.sb, rt.corre);
    if (!wact) { rt.arr = 0; rt.btn = (u8)btn; v99desk_dual_pon(rt.bx, rt.by, rt.foco, 0); return; }   /* el gestor no esta en pantalla (Pausa, A entera) */
    dx = px >> 1; dy = py >= 60 ? ((py - 60) * 2) / 3 : -1;   /* el punto del B5 bajo el puntero */
    en_a = px >= wx - 4 && px < wx + A_W + 4 && py >= wy - 24 && py < wy + A_H + 4;
    en_b = dy >= 0 && dx >= (int)rt.bx - 2 && dx < (int)rt.bx + 258 && dy >= (int)rt.by - 16 && dy < (int)rt.by + 215;
    en_barra = en_b && dy < (int)rt.by;
    /* los cuadraditos cian de las barras (el sonido): el de A lo pinta el gestor de ventanas (16 x 13 px a 40 px del borde derecho de la ventana, a 6 px
     * de la barra: 2 px de margen), el de B v99desk.c (8 x 8 puntos en el marco de B, 1 punto de margen) */
    en_sa = px >= wx + A_W - 42 && px < wx + A_W - 22 && py >= wy - 21 && py < wy - 4;
    en_sb = en_b && dx >= (int)rt.bx + 233 && dx < (int)rt.bx + 243 && dy >= (int)rt.by - 13 && dy < (int)rt.by - 3;
    if (btn && !rt.btn) {                                  /* clic: A esta por encima de B */
        if (en_sa) { if (corre) pide_silencio(0, !rt.sa); }   /* sin B corriendo el PL no mira los silencios */
        else if (en_a) { if (rt.foco) pide_foco(0); }
        else if (en_sb) { if (corre) pide_silencio(1, !rt.sb); }
        else if (en_b) {
            if (corre && !rt.foco) pide_foco(1);
            if (en_barra) { rt.arr = 1; rt.ox = dx - (int)rt.bx; rt.oy = dy - (int)rt.by; }
        }
    } else if (btn && rt.arr) {                            /* arrastrando la barra de B: la imagen sigue al puntero, de punto en punto */
        int nx = dx - rt.ox, ny = (dy < 0 ? 0 : dy) - rt.oy;
        if (nx < (int)MX_MIN) nx = (int)MX_MIN;
        if (nx > (int)MX_MAX) nx = (int)MX_MAX;
        if (ny < (int)MY_MIN) ny = (int)MY_MIN;
        if (ny > (int)MY_MAX) ny = (int)MY_MAX;
        if ((u16)nx != rt.bx || (u16)ny != rt.by) { rt.bx = (u16)nx; rt.by = (u16)ny; }   /* la imagen se mueve cuando el marco ya va a la VRAM: dual_marco_listo */
    } else if (!btn && rt.arr) {                           /* soltada */
        rt.arr = 0;
        v99desk_dual_pon(rt.bx, rt.by, rt.foco, 0);
        v99desk_dual_fin();
    }
    rt.btn = (u8)btn;
    v99desk_dual_pon(rt.bx, rt.by, rt.foco, rt.arr);
    v99desk_dual_silencio(rt.sa, rt.sb, rt.corre);         /* tras el clic: el cuadradito de B y la tarjeta ya lo dicen */
}

/* ---- el panel F12 ----------------------------------------------------------------------------------------------------------------------- */
void dual_abre(void) { aviso_txt[0] = 0; sucio = 1; ctl_vista = ctl_get(); sil_vista = sil_actual(); }

int dual_cambio(void)
{
    static u8 tarj_vista, duena_vista;
    u32 c = ctl_get(), s, sv = sil_actual();               /* los silencios: tambien cambian con el clic en las barras */
    if (c != ctl_vista || sv != sil_vista) { ctl_vista = c; sil_vista = sv; sucio = 1; }
    if (tarj_vista != (u8)dual_disco_tarjeta_nueva() || duena_vista != (u8)dual_disco_duena()) {   /* la tarjeta cambia sola; la duena tambien (B deja de correr Nextor-B) */
        tarj_vista = (u8)dual_disco_tarjeta_nueva(); duena_vista = (u8)dual_disco_duena(); sucio = 1;
    }
    s = sucio; sucio = 0;
    return (int)s;
}

void dual_tecla(u8 u)
{
    u32 c = ctl_get();
    aviso_txt[0] = 0; sucio = 1;
    switch (u) {
        case 0x16:                                                    /* S: soltar */
            if (c & BC_CORRE) pon(T("B ya corre.", "B is already running."), 1);
            else { soltar(); pon(T("B corre.", "B is running."), 1); }
            break;
        case 0x13:                                                    /* P: parar */
            if (!(c & BC_CORRE)) pon(T("B ya está parada.", "B is already stopped."), 1);
            else if (dual_disco_duena()) {                            /* parar B le quita la SD: vuelve a A (dual_poll lo haria igual, pero sin este mensaje) */
                parar();
                if (!sd_a()) pon(T("B parada. La SD vuelve a A.", "B stopped. The SD goes back to A."), 1);
            } else { parar(); pon(T("B parada.", "B stopped."), 1); }
            break;
        case 0x15:                                                    /* R: reiniciar (la BIOS vuelve a empezar; la RAM de B no se limpia) */
            parar(); soltar();
            pon(T("B reiniciada.", "B restarted."), 1);
            break;
        case 0x06:                                                    /* C: quitar el cartucho -> BASIC (tambien Nextor-B: la SD vuelve a A) */
            dual_disco_quita_nextor_b();
            parar(); ctl_bits(BC_CART, 0U); soltar();
            cart.hay = 0;
            sd_vista();
            if (dual_disco_toma_aviso_a()) pon(T("Sin cartucho: BASIC. Reinicia A si usa MSX-DOS.", "No cartridge: BASIC. Restart A if it runs MSX-DOS."), 1);
            else pon(T("Sin cartucho: B arranca el BASIC.", "No cartridge: B boots BASIC."), 1);
            break;
        case 0x07:                                                    /* D: la SD de TF2 es de A o de B (la otra solo lee); solo con Nextor-B en B */
            if (!dual_disco_nextor_b()) {                             /* sin MSX-DOS en B la SD es de A y no hay nada que pasar: se dice y no se toca */
                pon(T("B no corre MSX-DOS: la SD es de A (M lo pone).", "B isn't running MSX-DOS: the SD is A's (M starts it)."), 0);
            } else if (!dual_disco_duena()) {                         /* A -> B: B GANA la escritura, asi que se reinicia con Nextor-B nuevo (sus bufer pueden estar viejos) */
                dual_disco_pon_duena(1);
                if (dual_disco_compone()) { cart.hay = 0; pon(T("SD de B: B escribe y A solo lee. B reiniciada.", "SD is B's: B writes, A is read-only. B restarted."), 1); }
                else { dual_disco_pon_duena(0); pon(T("No se pudo preparar MSX-DOS.", "Couldn't prepare MSX-DOS."), 0); }
                sd_vista();
            } else {                                                  /* B -> A: A gana la escritura; si B escribio, aviso de que reinicie A */
                if (!sd_a()) pon(T("SD de A: A escribe y B solo lee.", "SD is A's: A writes, B is read-only."), 1);
            }
            break;
        case 0x10:                                                    /* M: MSX-DOS (Nextor-B) en B; B se reinicia y la duena de la SD no cambia */
            if (dual_disco_compone()) { cart.hay = 0; pon(T("MSX-DOS en B. B reiniciada.", "MSX-DOS on B. B restarted."), 1); }
            else pon(T("No se pudo preparar MSX-DOS.", "Couldn't prepare MSX-DOS."), 0);
            break;
        case 0x17:                                                    /* T: teclado forzado a B / libre */
            ctl_bits(BC_TECLADO, c & BC_TECLADO ? 0U : BC_TECLADO);
            if (c & BC_TECLADO) pon(T("Teclado libre: Insert alterna A y B.", "Keyboard free: Insert toggles A and B."), 1);
            else pon(T("Teclado en B. T lo suelta.", "Keyboard on B. T releases it."), 1);
            break;
        case 0x04:                                                    /* A: sonido de A / B: sonido de B (silenciar o activar) */
        case 0x05: {
            int b = (u == 0x05), sil;
            if (!(c & BC_CORRE)) { pon(T("B está parada: sin silencio por máquina.", "B is stopped: no per-machine mute."), 0); break; }
            if (!(c & BC_FINA)) { pon(T("Solo con el escritorio de dos columnas (tecla D).", "Only with the two-column desktop (D key)."), 0); break; }
            sil = (int)((sil_actual() >> b) & 1U);                    /* el estado real (o el pedido aun en vuelo), no el que se creia */
            pide_silencio(b, !sil);
            if (!sil) pon(b ? T("Sonido de B silenciado.", "B sound muted.") : T("Sonido de A silenciado.", "A sound muted."), 1);
            else      pon(b ? T("Sonido de B activado.", "B sound on.") : T("Sonido de A activado.", "A sound on."), 1);
            sil_vista = (sil_vista & ~(1U << b)) | ((u32)(!sil) << b);
            break;
        }
        case 0x19:                                                    /* V: la ventana de B en el escritorio del V9990 */
            ctl_bits(BC_SINVENT, c & BC_SINVENT ? 0U : BC_SINVENT);
            pon(c & BC_SINVENT ? T("Ventana de B visible.", "B window shown.") : T("Ventana de B oculta.", "B window hidden."), 1);
            break;
        default:
            sucio = 0;
            break;
    }
    ctl_vista = ctl_get();
}

#define PF   C_NOCHE

static void seccion(osd_pag p, int y, const char *t)
{
    int x = osd_txt(p, 1, y, OSD_A(PF, C_CIAN), t);
    osd_rellena(p, x + 1, y, OSD_ANCHO - 1 - (x + 1), 1, OSD_A(PF, C_GRIS_OSC), G_H);
}

/* texto con salto de linea por palabras en un ancho dado; devuelve la fila siguiente (como perfiles.c) */
static int parrafo(osd_pag p, int x, int y, int ancho, int max_filas, u8 tinta, const char *s)
{
    int col = 0, filas = 1;
    while (*s) {
        const char *w = s;
        char pal[40];
        u32 n = 0;
        while (*w && *w != ' ' && n + 1U < sizeof pal) pal[n++] = *w++;
        pal[n] = 0;
        while (*w && *w != ' ') w++;
        if (col && col + 1 + osd_txt_len(pal) > ancho) { y++; filas++; col = 0; }
        if (filas > max_filas) return y;
        if (col) col++;
        osd_txt(p, x + col, y, OSD_A(PF, tinta), pal);
        col += osd_txt_len(pal);
        s = w;
        while (*s == ' ') s++;
    }
    return y + 1;
}

static const char *mapper_txt(u32 c)
{
    static const char *const es[4] = { "Konami", "ASCII8", "Konami-SCC", "ASCII16" };
    return es[(c >> 3) & 3U];
}

void dual_pagina(osd_pag p)
{
    u32 c = ctl_get();
    char b[64], *q;
    int x, y, mio = cart.hay && (c & 0x38U) == cart.bits;                  /* el cartucho lo puso el menu (y no xsdb despues) */
    u32 sil = sil_actual();                                                /* el silencio de A (bit 0) y de B (bit 1) */
    osd_limpia(p, OSD_A(PF, C_BLANCO));
    osd_cabecera(p, G_CHIP, T("Máquina B", "Machine B"), "Dual");

    seccion(p, 3, T("Estado", "Status"));
    if (c & BC_CORRE) {
        osd_car(p, 2, 4, OSD_A(PF, C_VERDE), G_CIRCULO);
        osd_txt(p, 4, 4, OSD_A(PF, C_VERDE), T("Corre", "Running"));
    } else {
        osd_car(p, 2, 4, OSD_A(PF, C_NARANJA), G_ARO);
        osd_txt(p, 4, 4, OSD_A(PF, C_NARANJA), T("Parada", "Stopped"));
    }
    x = osd_txt(p, 2, 5, OSD_A(PF, C_GRIS), T("Teclado ", "Keyboard "));
    if (c & BC_TECLADO) osd_txt(p, x, 5, OSD_A(PF, C_AMARILLO), T("en B (forzado)", "on B (forced)"));
    else {
        x = osd_txt(p, x, 5, OSD_A(PF, C_BLANCO), "A");
        osd_txt(p, x, 5, OSD_A(PF, C_GRIS), T(" · Insert alterna", " · Insert toggles"));
    }
    x = osd_txt(p, 2, 6, OSD_A(PF, C_GRIS), T("Ventana ", "Window "));
    if (c & BC_SINVENT) osd_txt(p, x, 6, OSD_A(PF, C_NARANJA), T("oculta", "hidden"));
    else osd_txt(p, x, 6, OSD_A(PF, C_BLANCO), T("visible", "shown"));
    x = osd_txt(p, 2, 7, OSD_A(PF, C_GRIS), T("Sonido ", "Sound "));         /* Z1.3.2b8: A sí · B sí; en naranja lo que esta en silencio */
    x = osd_txt(p, x, 7, OSD_A(PF, C_GRIS), "A ");
    x = osd_txt(p, x, 7, OSD_A(PF, (sil & 1U) ? C_NARANJA : C_BLANCO), (sil & 1U) ? T("no", "off") : T("sí", "on"));
    x = osd_txt(p, x, 7, OSD_A(PF, C_GRIS), " · B ");
    if (!(c & BC_CORRE)) osd_txt(p, x, 7, OSD_A(PF, C_GRIS_CL), T("parada", "stopped"));
    else osd_txt(p, x, 7, OSD_A(PF, (sil & 2U) ? C_NARANJA : C_BLANCO), (sil & 2U) ? T("no", "off") : T("sí", "on"));
    x = osd_txt(p, 2, 8, OSD_A(PF, C_GRIS), "SD  ");                         /* Z1.3.2b9: quien escribe en la SD de TF2 (la otra solo lee); en amarillo si es B */
    if (dual_disco_duena()) {
        x = osd_txt(p, x, 8, OSD_A(PF, C_AMARILLO), T("B escribe", "B writes"));
        osd_txt(p, x, 8, OSD_A(PF, C_GRIS), T(" · A solo lee", " · A read-only"));
    } else {
        x = osd_txt(p, x, 8, OSD_A(PF, C_BLANCO), T("A escribe", "A writes"));
        osd_txt(p, x, 8, OSD_A(PF, C_GRIS), T(" · B solo lee", " · B read-only"));
    }

    seccion(p, 9, T("Cartucho", "Cartridge"));
    if (dual_disco_nextor_b()) {                                            /* Nextor-B: no es un cartucho del menu ni "puesto por JTAG" */
        osd_txt(p, 2, 10, OSD_A(PF, C_BLANCO), "MSX-DOS");
        osd_txt(p, 2, 11, OSD_A(PF, C_GRIS_CL), "Nextor 2.1.4 · 128 KB");
    } else if (!(c & BC_CART)) {
        osd_txt(p, 2, 10, OSD_A(PF, C_GRIS_CL), T("ninguno · MSX BASIC", "none · MSX BASIC"));
    } else {
        if (mio) {                                                              /* el nombre, cortado con "…" si no cabe en las columnas 2-28 */
            if (osd_txt_len(cart.nombre) > 27) osd_txt(p, osd_txt_n(p, 2, 10, OSD_A(PF, C_BLANCO), cart.nombre, 26), 10, OSD_A(PF, C_BLANCO), "…");
            else osd_txt(p, 2, 10, OSD_A(PF, C_BLANCO), cart.nombre);
        }
        else osd_txt(p, 2, 10, OSD_A(PF, C_GRIS_CL), T("puesto por JTAG", "set over JTAG"));
        q = cat(b, (c & BC_LINEAL) ? (mio && cart.pl.plano ? T("Plana", "Plain") : T("Lineal", "Linear")) : mapper_txt(c));
        if (mio && cart.pl.plano) {                                             /* donde: 4000h-7FFFh... */
            static const char hex[] = "0123456789ABCDEF";
            u32 a = cart.pl.off, f = cart.pl.off + cart.tam - 1U;
            *q++ = ' ';
            *q++ = hex[(a >> 12) & 15U]; *q++ = hex[(a >> 8) & 15U]; *q++ = hex[(a >> 4) & 15U]; *q++ = hex[a & 15U]; *q++ = 'h'; *q++ = '-';
            *q++ = hex[(f >> 12) & 15U]; *q++ = hex[(f >> 8) & 15U]; *q++ = hex[(f >> 4) & 15U]; *q++ = hex[f & 15U]; *q++ = 'h';
        }
        if (mio) {
            q = cat(q, " · ");
            q = osd_num(q, (cart.tam + 1023U) >> 10);
            q = cat(q, " KB");
        }
        *q = 0;
        osd_txt(p, 2, 11, OSD_A(PF, C_GRIS_CL), b);
    }

    y = 13;
    if (aviso_txt[0]) {
        osd_car(p, 1, y, OSD_A(PF, aviso_ok ? C_VERDE : C_ROJO), aviso_ok ? G_OK : G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, aviso_ok ? C_BLANCO : C_ROJO, aviso_txt);
    } else if (dual_disco_tarjeta_nueva()) {                                 /* la tarjeta de TF2 ha cambiado: Nextor-B contesta "sin tarjeta" hasta recomponerlo */
        (void)parrafo(p, 1, y, 28, 3, C_NARANJA, T("La tarjeta de TF2 ha cambiado: M reinicia MSX-DOS en B.", "The TF2 card changed: M restarts MSX-DOS on B."));
    } else if (dual_disco_nextor_b()) {                                     /* Z1.3.2b9: la que gana la SD se reinicia (B) o se avisa (A) */
        (void)parrafo(p, 1, y, 28, 3, C_AMARILLO, T("D pasa la SD de A a B o de B a A; B se reinicia al ganarla.", "D moves the SD between A and B; B restarts when it wins it."));
    } else if (c & BC_CORRE) {
        (void)parrafo(p, 1, y, 28, 2, C_GRIS, (c & BC_SINVENT) ? T("Sin ventana: el escritorio del V9990 no la pinta.", "No window: the V9990 desktop does not show it.")
                                                              : T("Se ve en el escritorio del V9990 (tecla Pausa).", "Shown on the V9990 desktop (Pause key)."));
    }

    x = osd_boton(p, 1, 16, PF, C_AMARILLO, "S", T("Soltar", "Start"));               /* un boton por fila y una fila libre entre ellos: las pastillas no se juntan */
    (void)osd_boton(p, x, 16, PF, C_AMARILLO, "P", T("Parar", "Power off"));
    x = osd_boton(p, 1, 18, PF, C_AMARILLO, "R", T("Reiniciar", "Reset"));              /* Z1.3.2b9: R y D comparten fila (justas: 30 columnas) */
    (void)osd_boton(p, x, 18, PF, C_AMARILLO, "D", "SD A/B");
    (void)osd_boton(p, 1, 20, PF, C_AMARILLO, "C", T("Quitar cartucho", "Remove cartridge"));
    x = osd_boton(p, 1, 22, PF, C_AMARILLO, "T", T("Teclado", "Keyboard"));              /* T y V comparten fila para dejar una al sonido */
    (void)osd_boton(p, x, 22, PF, C_AMARILLO, "V", T("Ventana", "Window"));
    x = osd_boton(p, 1, 24, PF, C_AMARILLO, "A", T("Mudo A", "Mute A"));                 /* Z1.3.2b8: silenciar / activar el sonido de cada maquina (con 30 columnas no cabe "Sonido A") */
    (void)osd_boton(p, x, 24, PF, C_AMARILLO, "B", T("Mudo B", "Mute B"));
    x = osd_boton(p, 1, 26, PF, C_AMARILLO, "M", "MSX-DOS");                             /* Z1.3.2b9: Nextor-B en B */
    (void)osd_boton(p, x, 26, PF, C_GRIS_CL, "ESC", T("Volver", "Back"));
    osd_txt(p, 1, 27, OSD_A(PF, C_GRIS), T("A está en pausa; B sigue.", "A is paused; B keeps running."));
}
