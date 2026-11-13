/* perfiles_ext.c — el menu del MSX y los perfiles (31/10/2026). Dos peticiones que el Z80 manda por el puerto 93h (wavegame.c las
 * recoge: el mismo mensaje de 14 bytes que 'W','G' y 'T','S') y que se atienden aqui desde el bucle principal:
 *
 *  'W','I' + PART_LBA + CUR_CLUS + FILE_CLUS   INSTALAR DESDE LA TF2. RETURN en el navegador sobre un fichero .MXP (tipo 7 del menu).
 *      El companion localiza el fichero por su primer cluster (tape_fat_locate), lo lee entero a la zona sin cache de los perfiles
 *      (PF_DATOS, donde lo espera mxpf_instala) y lo instala en la TF1: cabecera, SHA-256 del contenido, prueba de zlib, hueco
 *      libre, relectura, directorio. El resultado sale en el panel F12 (pagina Perfiles, con el perfil elegido): el menu no tiene
 *      como leer una respuesta (el 93h es solo de escritura) y el panel congela el Z80 mientras se lee. Sin particion o sin TF1 lo dice.
 *
 *  'W','Q' / 'W','G'   ETIQUETA [P:ID] EN EL NOMBRE DE UNA ROM. El menu manda 'W','Q' (la misma trama que 'W','G') al dar RETURN sobre una
 *      ROM, antes de cargarla, y 'W','G' al lanzarla. El companion lee el nombre largo del fichero (entradas LFN de la carpeta) y,
 *      si lleva [P:SONIDO] (hasta 8 caracteres A-Z 0-9 _ -, sin distinguir mayusculas), mira que perfil corre:
 *        - el mismo: nada;
 *        - otro y esta en la tarjeta con la serie del sistema: lo carga por PCAP (el MSX se reinicia, la DDR y la megaram se
 *          conservan) y el panel avisa de que hay que volver a lanzar el juego. El lanzamiento NO continua solo: tras el PCAP el
 *          Z80 arranca la BIOS de cero y el menu pierde sus variables (p1_init pone a cero #C000-#E7FF) y el estado de la megaram
 *          (registros del PL), asi que reanudarlo pediria bastante Z80 que no cabe en el menu; ver docs/tecnica/12-companion.md;
 *        - no puede cargarse (no esta instalado, otra serie, sin tarjeta...): el panel dice por que y el MSX se reinicia, que
 *          cancela el lanzamiento.
 *      Tabla de alias ([SND] -> SONIDO...) preparada y SIN activar: PERFIL_ALIAS_ACTIVOS. */
#include "xil_types.h"
#include "log.h"
#include "osd.h"
#include "ota.h"
#include "mxpf.h"
#include "profile.h"
#include "perfiles.h"
#include "perfiles_ext.h"
#ifdef PEXT_HOST
#include "pext_host.h"                                     /* banco del PC: usleep, MBOX en memoria compartida... */
#else
#include "sleep.h"
#define PEXT_DSB()      __asm__ volatile ("dsb" ::: "memory")
#endif

#define MBOX_CTRL       ((volatile u32 *)0x1FF0001CU)      /* bit 0: MSX_RUN */
#define MXP_MAX         0x003EF000U                        /* lo que cabe entre PF_DATOS y los sectores de trabajo de mxpf.c */
#define TROZO           0x10000U

/* alias de etiqueta -> id de perfil: "[SND]" ademas de "[P:SONIDO]". PREPARADA, SIN ACTIVAR: PERFIL_ALIAS_ACTIVOS = 0. Para activar
 * los N primeros hay que cambiar esa constante (y que esos perfiles existan en el servidor). Los alias van en MAYUSCULAS. */
static const struct { const char *alias, *id; } alias_tab[] = { { "SND", "SONIDO" }, { "SFG", "SONIDO" }, { "SN76", "SONIDO" } };
#define N_ALIAS (sizeof alias_tab / sizeof alias_tab[0])
#define PERFIL_ALIAS_ACTIVOS 0U

static struct { u8 que; u32 part, dir, file; } pend;      /* que: 0 nada, 1 instalar, 2 etiqueta */

void pext_pide_instalar(u32 part, u32 dir, u32 file) { pend.que = 1; pend.part = part; pend.dir = dir; pend.file = file; }
void pext_pide_etiqueta(u32 part, u32 dir, u32 file)
{
    if (pend.que == 1) return;                              /* una instalacion pedida no se pisa */
    pend.que = 2; pend.part = part; pend.dir = dir; pend.file = file;
}

/* ---- textos ------------------------------------------------------------------------------------------------------------- */
static char *cat(char *d, const char *s) { while (*s) *d++ = *s++; *d = 0; return d; }

/* ---- la etiqueta ---------------------------------------------------------------------------------------------------------- */
static int id_car(char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-'; }
static char mayus(char c) { return (c >= 'a' && c <= 'z') ? (char)(c - 32) : c; }
/* Z1.3.2b8: el perfil de la musica se llama "Music" en ingles y la etiqueta [P:MUSIC] tambien vale: es el id MUSICA (el interno no cambia) */
static void id_canon(char id[9]) { if (id[0] == 'M' && id[1] == 'U' && id[2] == 'S' && id[3] == 'I' && id[4] == 'C' && !id[5]) { id[5] = 'A'; id[6] = 0; } }

int pext_etiqueta_de(const char *n, char id[9])
{
    u32 i, k, a;
    id[0] = 0;
    for (i = 0; n[i]; i++) {
        if (n[i] != '[') continue;
        if ((n[i + 1] | 0x20) == 'p' && n[i + 2] == ':') {
            for (k = 0; k < 8U && id_car(n[i + 3 + k]); k++) id[k] = mayus(n[i + 3 + k]);
            if (k && n[i + 3 + k] == ']') { id[k] = 0; id_canon(id); return 1; }
            id[0] = 0;
        }
        for (a = 0; a < PERFIL_ALIAS_ACTIVOS && a < N_ALIAS; a++) {          /* "[SND]" */
            const char *s = alias_tab[a].alias;
            for (k = 0; s[k] && mayus(n[i + 1 + k]) == s[k]; k++) { }
            if (!s[k] && n[i + 1 + k] == ']') { for (k = 0; alias_tab[a].id[k]; k++) id[k] = alias_tab[a].id[k]; id[k] = 0; return 1; }
        }
    }
    return 0;
}

/* ---- el panel ---------------------------------------------------------------------------------------------------------------- */
static void panel(const char *txt, int ok, const char *id)
{
    perfiles_aviso_abre(txt, ok, id);
    osd_abre_perfiles();
}

static void msx_reset(void)                                  /* el MSX_RUN a 0 y otra vez a 1: la BIOS de cero (la DDR no se toca) */
{
    *MBOX_CTRL &= ~1U; PEXT_DSB();
    usleep(20000);
    *MBOX_CTRL |= 1U; PEXT_DSB();
}

/* ---- instalar desde la TF2 ----------------------------------------------------------------------------------------------------- */
static void instala_tf2(u32 part, u32 dir, u32 file)
{
    u32 size = 0, pos, n, i;
    char ext[3], id[9], b[120], *q;
    volatile u8 *dst = (volatile u8 *)(uintptr_t)PF_DATOS;
    int r;
    wg_pl_parar();                                            /* la musica del menu guarda su sector en el mismo buzon de la FAT: se para antes de leer otro fichero */
    if (!tape_fat_locate(part, dir, file, &size, ext)) { panel(T("No encuentro el fichero en la TF2", "Can't find the file on TF2"), 0, 0); return; }
    if (ext[0] != 'M' || ext[1] != 'X' || ext[2] != 'P') { panel(T("El fichero no es un .MXP", "The file is not a .MXP"), 0, 0); return; }
    if (size < 512U || size > MXP_MAX) { panel(T("El fichero .MXP no es válido (tamaño)", "The .MXP file is not valid (size)"), 0, 0); return; }
    log_str("pext: instalando desde la TF2, "); log_dec(size); log_str(" B\n");
    for (pos = 0; pos < size; pos += n) {
        n = size - pos < TROZO ? size - pos : TROZO;
        if (!tape_file_read(file, size, pos, (u8 *)(uintptr_t)(PF_DATOS + pos), n)) { panel(T("Error al leer la TF2", "TF2 read error"), 0, 0); return; }
        sd_ceder();
    }
    for (i = 0; i < 8U; i++) id[i] = (char)dst[16 + i];       /* el id de la cabecera (mxpf_instala lo valida) */
    id[8] = 0;
    r = mxpf_instala((const u8 *)(uintptr_t)PF_DATOS, size);
    if (r != MXPF_OK) {
        log_str("pext: no instalado: "); log_str(mxpf_err_es(r)); log_str("\n");
        panel(perfiles_error(r), 0, 0);
        return;
    }
    q = cat(b, perfil_nombre(id));
    cat(q, T(" instalado desde la TF2.", " installed from TF2."));
    log_str("pext: "); log_str(id); log_str(" instalado\n");
    panel(b, 1, id);
}

/* ---- la etiqueta de una ROM ------------------------------------------------------------------------------------------------------ */
static void etiqueta(u32 part, u32 dir, u32 file)
{
    char nombre[256], id[9], b[160], *q;
    int r, cargado = 0;
    if (!fat_nombre(part, dir, file, nombre, sizeof nombre)) return;
    if (!pext_etiqueta_de(nombre, id)) return;
    log_str("pext: la ROM pide el perfil "); log_str(id); log_str("\n");
    if (id[0] == '1' && !id[1]) {                             /* el perfil 1 es el del BOOT.bin: volver a el reinicia la placa entera */
        if (mxpf_id_activo()[0] == 0) return;
        msx_reset();
        panel(T("Esta ROM pide el perfil Normal: Intro sobre Normal lo recupera (reinicia la placa).",
                "This ROM wants the Standard profile: Enter on Standard restores it (restarts the board)."), 0, 0);
        return;
    }
    r = mxpf_pide(id, &cargado);
    if (r == MXPF_OK && !cargado) return;                     /* ya corre */
    if (cargado) {
        wg_pl_rearma();
        q = cat(b, perfil_nombre(id));
        cat(q, T(" cargado. Vuelve a lanzar el juego.", " loaded. Launch the game again."));
        log_str("pext: perfil "); log_str(id); log_str(" cargado por la etiqueta de la ROM\n");
        panel(b, 1, id);
        return;
    }
    log_str("pext: perfil "); log_str(id); log_str(" no cargado: "); log_str(mxpf_err_es(r)); log_str("\n");
    msx_reset();                                              /* sin el perfil que pide, el juego no se lanza */
    q = cat(b, T("Esta ROM pide el perfil ", "This ROM wants profile "));
    q = cat(q, perfil_nombre(id));
    q = cat(q, ": ");
    q = cat(q, r == MXPF_E_NOEXISTE ? T("no está instalado (S lo busca en el servidor).", "it is not installed (S looks for it on the server).")
                                    : perfiles_error(r));
    panel(b, 0, 0);
}

void pext_poll(void)
{
    u8 que = pend.que;
    if (!que) return;
    pend.que = 0;
    if (que == 1) instala_tf2(pend.part, pend.dir, pend.file);
    else etiqueta(pend.part, pend.dir, pend.file);
}
