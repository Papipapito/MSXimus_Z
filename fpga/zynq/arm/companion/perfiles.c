/* perfiles.c — la pagina «Perfiles» del panel F12 (tecla P desde la pagina de informacion): perfiles del PL en la TF1 (mxpf.c).
 * Dibuja con osd_dib.c y llama a mxpf.c, ota.c (la lista de perfiles del servidor) y qspi_cfg.c (el perfil al arrancar); nada de
 * hardware aqui. Textos en castellano e ingles con T() (osd.h). Dos vistas:
 *
 * TARJETA (la de siempre)
 *   flechas arriba/abajo   elegir (la primera fila es siempre el perfil 1 = el del BOOT.bin)
 *   Intro                  cargar el elegido (reinicia el MSX); sobre el perfil 1, volver a el (reinicia la placa)
 *   D                      borrar el elegido, pide Intro
 *   A                      "perfil al arrancar": el elegido se carga solo al encender (antes de soltar el MSX); sobre el perfil 1,
 *                          ninguno (31/10/2026). Se guarda en el bloque de ajustes de la QSPI (qspi_cfg.c)
 *   S                      la vista del servidor
 *   T                      preparar la tarjeta si esta vacia, a medias o con los directorios rotos (pide Intro; no borra nada)
 *   B                      tarjeta ajena o de las betas: «Borrar y preparar» / «Convertir». PRIMERA tecla: arma y dice que se borra la
 *                          tarjeta ENTERA; SEGUNDA (Intro): lo hace. Nunca si la placa arranco desde SD (TF1 solo para perfiles, 8/11/2026)
 *   R                      releer la tarjeta (por si se acaba de meter)
 *   ESC                    cancela lo armado; sin nada armado, vuelve a la pagina de informacion
 * SERVIDOR (31/10/2026, la actualizacion por red de ota.c: lineas perfil= del manifiesto firmado)
 *   flechas arriba/abajo   elegir          Intro  bajar el elegido y instalarlo en la tarjeta
 *   A                      bajar todos los que falten o esten viejos (lo que hace falta tras cada actualizacion del sistema)
 *   U / R                  buscar otra vez   B  canal oficial / beta   T  preparar la tarjeta (vacia, a medias o danada)
 *   S o ESC                vuelven a la vista de la tarjeta
 * Lo que toca la tarjeta (D, T) y lo que reinicia la placa (perfil 1) NUNCA se hace con una pulsacion: la primera arma y dice
 * que va a pasar, la segunda (Intro) lo hace; cualquier otra tecla o 10 s sin tocar lo cancelan. Cargar un perfil si es una
 * pulsacion (Intro): no toca la tarjeta y lo unico que pierde el MSX es lo que corria. */
#include "xil_types.h"
#include "xparameters.h"
#include "osd.h"
#include "ota.h"
#include "perfiles.h"
#include "mxpf.h"

extern u64 gt_now(void);
extern int  cfg_perfil_arranque(char id[9]);              /* qspi_cfg.c: 1 = hay perfil al arrancar (su id); 0 = ninguno */
extern int  cfg_perfil_fija(const char *id);              /* id vacio o 0 = ninguno. 1 = guardado */
extern void net_ip(u8 ip[4]);                             /* net.c: la IP del cable (0.0.0.0 = sin cable) */
#define PF   C_NOCHE

enum { A_NADA = 0, A_BORRAR, A_PREPARAR, A_PERFIL1, A_BORRAR_TARJETA };
enum { V_TARJETA = 0, V_SERVIDOR };

static int sel;                                   /* vista tarjeta: 0 = perfil 1; 1.. = instalados */
static int ssel;                                  /* vista servidor: 0.. = lineas perfil= del manifiesto */
static u8  vista, armado, sucio = 1, msg_ok;
static u64 t_armado;
static char msg[96];
static char boot_id[9];                           /* perfil al arrancar ("" = ninguno) */
static mxpf_clase_t cl;                           /* la clase de la tarjeta (mxpf_clasifica) la ultima vez que se miro */
static u8  aviso_tf1;                             /* 0 nada, 1 tarjeta nueva sin preparar, 2 tarjeta de las betas */
static u8  auto_bajar;                            /* tras preparar la tarjeta CON CABLE: esperando la lista del servidor para bajar todos los perfiles (por WiFi no: el S3 deja al MSX sin ESP mientras baja) */

static void scpy(char *d, const char *s, u32 cap) { u32 i = 0; while (s[i] && i + 1U < cap) { d[i] = s[i]; i++; } d[i] = 0; }
static int  igual(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static void pon(const char *s, int ok) { scpy(msg, s, sizeof msg); msg_ok = (u8)ok; }

static int n_perfiles(void) { const mxpf_info_t *in = mxpf_estado(); return in->estado == MXS_OK ? in->n : 0; }

/* El nombre que se ENSENA de un perfil (Z1.3.2b8; el id interno no cambia: los perfiles instalados, el manifiesto de la OTA y las etiquetas [P:ID]
 * de las ROM siguen igual). Mide 8 columnas como mucho (la columna del id de la lista); lo que no se conoce, tal cual. */
const char *perfil_nombre(const char *id)
{
    if (igual(id, "MUSICA")) return T("Música", "Music");
    if (igual(id, "DUAL")) return "Dual";
    if (igual(id, "TR")) return "Turbo R";
    if (igual(id, "TRV")) return "TR V9990";
    return id;
}

/* texto de un codigo de error de mxpf.c */
static const char *error_txt(int e)
{
    switch (e) {
        case MXPF_E_TARJETA:   return T("No hay tarjeta o no se puede leer", "No card, or it can't be read");
        case MXPF_E_MBR:       return T("La tarjeta no tiene una tabla de particiones MBR normal: no se toca", "The card has no normal MBR partition table: left alone");
        case MXPF_E_ENTRADAS:  return T("Las 4 entradas de particiones están ocupadas", "All 4 partition entries are in use");
        case MXPF_E_SITIO:     return T("La tarjeta es demasiado pequeña: hace falta de 1 GB o más", "The card is too small: it must be 1 GB or more");
        case MXPF_E_YA:        return T("La tarjeta ya está preparada", "The card is already set up");
        case MXPF_E_SINPART:   return T("La tarjeta de TF1 no está preparada: ve a la tarjeta (S) y prepárala", "The TF1 card is not set up: go to the card (S) and set it up");
        case MXPF_E_DIR:       return T("La partición está dañada: T rehace los directorios", "The partition is damaged: T rebuilds its directories");
        case MXPF_E_CONFIRMA:  return T("Falta la confirmación: no se ha tocado la tarjeta", "Not confirmed: the card was not touched");
        case MXPF_E_ARRANQUE_SD: return T("Has arrancado desde esta tarjeta. Pon SW1 en QSPI para prepararla", "You booted from this card. Set SW1 to QSPI to set it up");
        case MXPF_E_FALSA:     return T("La tarjeta no guarda lo que se escribe: parece falsa o defectuosa", "The card does not keep what is written: fake or faulty");
        case MXPF_E_LLENO:     return T("No queda hueco: borra un perfil", "No free slot: delete a profile");
        case MXPF_E_FORMATO:   return T("El perfil no es válido", "The profile is not valid");
        case MXPF_E_SHA:       return T("El perfil está dañado (SHA-256 distinto)", "The profile is damaged (SHA-256 differs)");
        case MXPF_E_ZLIB:      return T("El perfil está dañado (zlib)", "The profile is damaged (zlib)");
        case MXPF_E_SERIE:     return T("Es de otra versión del sistema: no se carga", "It is for another system version: not loaded");
        case MXPF_E_OCUPADO:   return T("Hay una actualización por red en curso", "A network update is running");
        case MXPF_E_NOEXISTE:  return T("Ese perfil ya no está", "That profile is gone");
        case MXPF_E_IO:        return T("Error de lectura o escritura de la SD", "SD read or write error");
        case MXPF_E_VERIFICA:  return T("La SD no ha guardado lo escrito", "The SD didn't keep what was written");
        case MXPF_E_PCAP:      return T("El PL no ha aceptado el perfil (no se ha tocado)", "The PL refused the profile (untouched)");
        case MXPF_E_JTAG:      return T("Con SW1 en JTAG no se puede reiniciar", "Can't restart with SW1 on JTAG");
        default:               return T("Error", "Error");
    }
}

const char *perfiles_error(int e) { return error_txt(e); }   /* perfiles_ext.c */

static void lee_boot(void) { if (!cfg_perfil_arranque(boot_id)) boot_id[0] = 0; }

/* relee la tarjeta: sus perfiles (mxpf_monta) y su clase (mxpf_clasifica); la clase puede dejar el estado a medias, asi que se monta otra vez */
static void refresca(void)
{
    cl = *mxpf_clasifica();
    (void)mxpf_monta();
}

/* TF1 solo perfiles: el aviso de tarjeta nueva (OLED + pagina de informacion). No hace nada si se arranco desde SD: ahi la TF1 es la de arranque */
int perfiles_aviso_tf1(void) { return aviso_tf1; }
void perfiles_aviso_revisa(void)
{
    const mxpf_clase_t *c;
    aviso_tf1 = 0;
    if (mxpf_arranque_sd()) return;
    c = mxpf_clasifica();
    if (c->clase == MXC_NUESTRA_ANTIGUA) aviso_tf1 = 2;
    else if (c->clase == MXC_AJENA || c->clase == MXC_VACIA || c->clase == MXC_INTERRUMPIDA || c->clase == MXC_DANADA) aviso_tf1 = 1;
    (void)mxpf_monta();
}

void perfiles_abre(void)
{
    const mxpf_info_t *in;
    const mxpf_perfil *a = mxpf_activo_perfil();
    int i;
    mxpf_ded_desarma();
    auto_bajar = 0;
    refresca();
    in = mxpf_estado();
    vista = V_TARJETA; sel = 0; ssel = 0; armado = A_NADA; msg[0] = 0; sucio = 1;
    lee_boot();
    if (a && in->estado == MXS_OK) {                          /* el cursor, sobre el que corre ahora */
        for (i = 0; i < in->n; i++) if (igual(in->p[i].id, a->id)) sel = i + 1;
    }
}

/* la vista del servidor: se abre desde la pagina de la actualizacion (tecla P tras instalar un BOOT.bin) o con S; si aun no se ha
 * buscado, busca (la misma U de ota_tecla) */
void perfiles_abre_servidor(void)
{
    perfiles_abre();
    vista = V_SERVIDOR;
    if (ota_srv_estado() == OSV_SIN_BUSCAR) (void)ota_busca(2);
    else if (ota_srv_estado() == OSV_LISTO) refresca();
}

/* un aviso con la pagina abierta sobre el perfil `id` (instalado desde un fichero de TF2, perfil cargado por una etiqueta...) */
void perfiles_aviso_abre(const char *txt, int ok, const char *id)
{
    const mxpf_info_t *in;
    int i;
    perfiles_abre();
    in = mxpf_estado();
    if (id && in->estado == MXS_OK) for (i = 0; i < in->n; i++) if (igual(in->p[i].id, id)) sel = i + 1;
    pon(txt, ok);
}

int perfiles_armado(void) { return armado != A_NADA || vista == V_SERVIDOR; }   /* ESC es de esta pagina */

int perfiles_cambio(void)
{
    int c;
    if (armado && gt_now() - t_armado > (u64)COUNTS_PER_SECOND * 10U) { armado = A_NADA; mxpf_ded_desarma(); msg[0] = 0; sucio = 1; }   /* caduca */
    if (vista == V_SERVIDOR && ota_cambio()) sucio = 1;       /* la busqueda y la descarga la llevan ota.c */
    if (auto_bajar) {                                          /* tarjeta recien preparada con cable: cuando llegue la lista, a bajarlo todo */
        int st = ota_srv_estado();
        if (st == OSV_LISTO) {
            auto_bajar = 0; sucio = 1;
            if (ota_perfiles_n() && ota_perfiles_descargables() && !ota_perfil_en_curso()) { ota_perfil_olvida(); (void)ota_perfil_baja(-1); }
        } else if (st == OSV_ERROR || st == OSV_OCUPADO) { auto_bajar = 0; sucio = 1; }
    }
    c = sucio; sucio = 0;
    return c;
}

static void arma(u8 que) { armado = que; t_armado = gt_now(); msg[0] = 0; }

/* T (no borra nada): tarjeta vacia, a medias o con los directorios rotos. B (borra la tarjeta entera): ajena o de las betas. Nada de esto con arranque desde SD */
static int puede_preparar(void) { return !mxpf_arranque_sd() && (cl.clase == MXC_VACIA || cl.clase == MXC_DANADA || cl.clase == MXC_INTERRUMPIDA); }
static int puede_borrar(void) { return !mxpf_arranque_sd() && (cl.clase == MXC_AJENA || cl.clase == MXC_NUESTRA_ANTIGUA); }

static void ejecuta(void)
{
    const mxpf_info_t *in = mxpf_estado();
    char id[9];
    u8 que = armado;
    int r = 0, k;
    armado = A_NADA;
    if (que == A_BORRAR) {
        if (sel < 1 || sel > n_perfiles()) { pon(error_txt(MXPF_E_NOEXISTE), 0); return; }
        for (k = 0; k < 9; k++) id[k] = in->p[sel - 1].id[k];
        r = mxpf_borra(id);
        pon(r ? error_txt(r) : T("Perfil borrado", "Profile deleted"), r == 0);
        if (sel > n_perfiles()) sel = n_perfiles();
    } else if (que == A_PREPARAR || que == A_BORRAR_TARJETA) {
        pon(T("Preparando la tarjeta… no la saques", "Setting up the card… don't remove it"), 1);
        osd_repinta();
        r = mxpf_prepara_dedicada(que == A_BORRAR_TARJETA);   /* la biblioteca vuelve a comprobar: arranque desde SD, las dos teclas, la misma tarjeta */
        refresca();
        perfiles_aviso_revisa();
        pon(r ? error_txt(r) : T("Tarjeta preparada", "Card ready"), r == 0);
        sel = 0;
        if (r == 0) {
            u8 ip[4];
            net_ip(ip);
            if (ip[0] && !ota_ocupada()) {                    /* con cable: busca y baja los perfiles solo (se ve en la vista del servidor) */
                auto_bajar = 1; vista = V_SERVIDOR; ssel = 0;
                ota_perfil_olvida(); (void)ota_busca(0);
            }
        }
    } else if (que == A_PERFIL1) {
        pon(T("Reiniciando la placa…", "Restarting the board…"), 1);
        osd_repinta();
        r = mxpf_perfil1();                                   /* no vuelve si lo consigue */
        pon(error_txt(r), 0);
    }
}

static void carga_elegido(void)
{
    const mxpf_info_t *in = mxpf_estado();
    char id[9];
    int k, r;
    if (sel < 1 || sel > n_perfiles()) return;
    for (k = 0; k < 9; k++) id[k] = in->p[sel - 1].id[k];
    pon(T("Cargando… la pantalla se apaga unos segundos", "Loading… the screen goes dark for a few seconds"), 1);
    osd_repinta();
    r = mxpf_carga(id);                                       /* con exito el panel se cierra solo (osd_pl_rearma) */
    if (r) pon(error_txt(r), 0); else msg[0] = 0;
}

/* A: el perfil elegido se carga al encender; sobre el perfil 1, ninguno. Una pulsacion: es reversible y no toca la tarjeta */
static void fija_arranque(void)
{
    const mxpf_info_t *in = mxpf_estado();
    char b[48], *q = b;
    const char *s;
    if (ota_ocupada()) { pon(error_txt(MXPF_E_OCUPADO), 0); return; }     /* graba la QSPI: no mientras la actualizacion la usa */
    if (sel == 0 || sel > n_perfiles()) {
        if (!cfg_perfil_fija(0)) { pon(T("No se pudo guardar el ajuste", "The setting could not be saved"), 0); return; }
        boot_id[0] = 0;
        pon(T("Al encender: Normal", "At power-on: Standard"), 1);
        return;
    }
    if (!cfg_perfil_fija(in->p[sel - 1].id)) { pon(T("No se pudo guardar el ajuste", "The setting could not be saved"), 0); return; }
    scpy(boot_id, in->p[sel - 1].id, sizeof boot_id);
    for (s = T("Al encender: ", "At power-on: "); *s; ) *q++ = *s++;
    for (s = perfil_nombre(boot_id); *s; ) *q++ = *s++;
    *q = 0;
    pon(b, 1);
}

/* teclas comunes a las dos vistas que tocan la tarjeta */
static void tecla_preparar(void)
{
    if (cl.clase == MXC_SIN_TARJETA || cl.clase == MXC_ERROR) { pon(error_txt(MXPF_E_TARJETA), 0); return; }
    if (mxpf_arranque_sd() && cl.clase != MXC_NUESTRA) { pon(error_txt(MXPF_E_ARRANQUE_SD), 0); return; }
    switch (cl.clase) {
        case MXC_NUESTRA: pon(error_txt(MXPF_E_YA), 0); break;
        case MXC_DEFECTUOSA: pon(error_txt(cl.motivo ? cl.motivo : MXPF_E_FALSA), 0); break;
        case MXC_AJENA: case MXC_NUESTRA_ANTIGUA:
            pon(vista == V_SERVIDOR ? T("Para borrarla y prepararla ve a la tarjeta (S) y pulsa B", "To erase and set it up go to the card (S) and press B")
                                    : T("Esta tarjeta no está vacía: B la borra y la prepara", "This card is not empty: B erases and sets it up"), 0);
            break;
        case MXC_INTERRUMPIDA: if (mxpf_ded_arma()) arma(A_PREPARAR); else pon(error_txt(MXPF_E_TARJETA), 0); break;   /* la primera tecla de la biblioteca */
        default: arma(A_PREPARAR); break;
    }
}

/* B en la vista de la tarjeta: PRIMERA tecla de borrar la tarjeta entera; la SEGUNDA es Intro (perfiles_tecla) */
static void tecla_borrar_tarjeta(void)
{
    if (mxpf_arranque_sd()) { pon(error_txt(MXPF_E_ARRANQUE_SD), 0); return; }
    if (!puede_borrar()) { pon(cl.clase == MXC_NUESTRA ? error_txt(MXPF_E_YA) : T("Esta tarjeta no hace falta borrarla: T la prepara", "This card needs no erasing: T sets it up"), 0); return; }
    if (mxpf_ded_arma()) arma(A_BORRAR_TARJETA); else pon(error_txt(MXPF_E_TARJETA), 0);
}

static void tecla_servidor(u8 u)
{
    int n = ota_perfiles_n();
    switch (u) {
        case 0x52: if (ssel > 0) ssel--; break;                /* arriba */
        case 0x51: if (ssel + 1 < n) ssel++; break;            /* abajo */
        case 0x28:                                             /* Intro: bajar el elegido */
            if (n && !ota_perfil_en_curso()) { ota_perfil_olvida(); (void)ota_perfil_baja(ssel); }
            break;
        case 0x04:                                             /* A: todos los que falten o esten viejos */
            if (n && !ota_perfil_en_curso()) { ota_perfil_olvida(); (void)ota_perfil_baja(-1); }
            break;
        case 0x18: case 0x15:                                  /* U o R: buscar otra vez (corta la que este en marcha, 11/11/2026) */
            ota_perfil_olvida(); (void)mxpf_monta(); (void)ota_busca(0); ssel = 0;
            break;
        case 0x05: ota_perfil_olvida(); (void)ota_busca(1); ssel = 0; break;   /* B: el otro canal, y busca (aunque estuviera buscando) */
        case 0x17: tecla_preparar(); break;
        case 0x16: case 0x29: vista = V_TARJETA; ota_perfil_olvida(); refresca(); break;   /* S o ESC: la tarjeta */
        default: break;
    }
}

void perfiles_tecla(u8 u)
{
    int n = n_perfiles();
    sucio = 1;
    if (armado) {
        if (u == 0x28) ejecuta();                             /* Intro */
        else { armado = A_NADA; mxpf_ded_desarma(); msg[0] = 0; }   /* ESC o cualquier otra */
        return;
    }
    if (u == 0x28 && msg[0]) { msg[0] = 0; return; }           /* Intro con un mensaje a la vista solo lo quita (un T rechazado no recarga nada) */
    msg[0] = 0;
    if (vista == V_SERVIDOR) { tecla_servidor(u); return; }
    switch (u) {
        case 0x52: if (sel > 0) sel--; break;                  /* arriba */
        case 0x51: if (sel < n) sel++; break;                  /* abajo */
        case 0x28:                                             /* Intro */
            if (sel == 0) {
                if (mxpf_activo() == MXA_PERFIL1) pon(T("Ya corre el Normal", "Standard is already running"), 1);
                else arma(A_PERFIL1);
            } else carga_elegido();
            break;
        case 0x07:                                             /* D */
            if (sel >= 1 && sel <= n) arma(A_BORRAR); else pon(T("Elige un perfil instalado", "Pick an installed profile"), 0);
            break;
        case 0x04: fija_arranque(); break;                     /* A */
        case 0x16:                                             /* S: el servidor */
            perfiles_abre_servidor();
            break;
        case 0x17: tecla_preparar(); break;                    /* T */
        case 0x05: tecla_borrar_tarjeta(); break;              /* B */
        case 0x15:                                             /* R */
            refresca();
            perfiles_aviso_revisa();
            if (sel > n_perfiles()) sel = n_perfiles();
            break;
        default:
            break;
    }
}

/* ---- dibujo --------------------------------------------------------------------------------------------------------- */
static void seccion(osd_pag p, int y, const char *t)
{
    int x = osd_txt(p, 1, y, OSD_A(PF, C_CIAN), t);
    osd_rellena(p, x + 1, y, OSD_ANCHO - 1 - (x + 1), 1, OSD_A(PF, C_GRIS_OSC), G_H);
}

/* texto con salto de linea por palabras en un ancho dado; devuelve la fila siguiente */
static int parrafo(osd_pag p, int x, int y, int ancho, int max_filas, u8 tinta, const char *s)
{
    int col = 0, filas = 1;
    while (*s) {
        const char *w = s;
        char pal[40];
        u32 n = 0;
        while (*w && *w != ' ' && n + 1U < sizeof pal) pal[n++] = *w++;
        pal[n] = 0;
        while (*w && *w != ' ') w++;                           /* palabra mas larga que el buffer: se corta */
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

static void mb1(char *d, u32 bytes)                            /* 1,3 MB */
{
    d = osd_fijo(d, (u32)(((u64)bytes * 10U + 524288U) / 1048576U), 1);
    *d++ = ' '; *d++ = 'M'; *d++ = 'B'; *d = 0;
}

/* ¿es este el perfil que corre ahora? (mismo id y mismo contenido) */
static int es_el_activo(const mxpf_perfil *e)
{
    const mxpf_perfil *a = mxpf_activo_perfil();
    u32 k;
    if (!a) return 0;
    if (!igual(e->id, a->id)) return 0;
    for (k = 0; k < 32U; k++) if (e->sha[k] != a->sha[k]) return 0;
    return 1;
}

static void tarjeta(osd_pag p, const mxpf_info_t *in)
{
    char b[48];
    int x;
    seccion(p, 3, T("Tarjeta TF1", "TF1 card"));
    if (in->estado == MXS_SIN_TARJETA) {
        osd_car(p, 2, 4, OSD_A(PF, C_NARANJA), G_SD);
        osd_txt(p, 4, 4, OSD_A(PF, C_NARANJA), T("sin tarjeta", "no card"));
        osd_txt(p, 2, 5, OSD_A(PF, C_GRIS), T("Solo existe el Normal.", "Only Standard exists."));
        return;
    }
    if (in->estado == MXS_ERROR_TARJETA) {
        osd_car(p, 2, 4, OSD_A(PF, C_ROJO), G_SD);
        osd_txt(p, 4, 4, OSD_A(PF, C_ROJO), T("no se puede leer", "can't be read"));
        return;
    }
    osd_car(p, 2, 4, OSD_A(PF, C_CIAN), G_SD);
    osd_num(b, in->mb);
    x = osd_txt(p, 4, 4, OSD_A(PF, C_BLANCO), b);
    osd_txt(p, x, 4, OSD_A(PF, C_GRIS), " MB");
    if (in->estado == MXS_OK) {
        osd_car(p, 2, 5, OSD_A(PF, C_VERDE), G_OK);
        osd_txt(p, 4, 5, OSD_A(PF, C_VERDE), T("partición de perfiles", "profile partition"));
        osd_num(b, in->part_secs >> 11);
        x = osd_txt(p, 2, 6, OSD_A(PF, C_BLANCO), b);
        x = osd_txt(p, x, 6, OSD_A(PF, C_GRIS), " MB · ");
        osd_num(b, in->libres);
        x = osd_txt(p, x, 6, OSD_A(PF, in->libres ? C_BLANCO : C_NARANJA), b);
        osd_txt(p, x, 6, OSD_A(PF, C_GRIS), T(" huecos libres", " free slots"));
        if (cl.clase == MXC_NUESTRA_ANTIGUA) {                    /* la de las betas: sigue funcionando; B la convierte */
            osd_car(p, 2, 7, OSD_A(PF, C_NARANJA), G_AVISO);
            osd_txt(p, 4, 7, OSD_A(PF, C_NARANJA), T("de las betas (con FAT)", "from the betas (with FAT)"));
            osd_txt(p, 4, 8, OSD_A(PF, C_GRIS), T("B la convierte", "B converts it"));
        }
    } else if (in->estado == MXS_DANADA) {
        osd_car(p, 2, 5, OSD_A(PF, C_ROJO), G_NO);
        osd_txt(p, 4, 5, OSD_A(PF, C_ROJO), T("partición dañada", "damaged partition"));
        osd_txt(p, 2, 6, OSD_A(PF, C_GRIS), T("T rehace sus directorios.", "T rebuilds its directories."));
    } else if (cl.clase == MXC_VACIA) {
        osd_car(p, 2, 5, OSD_A(PF, C_NARANJA), G_ARO);
        osd_txt(p, 4, 5, OSD_A(PF, C_NARANJA), T("tarjeta vacía", "empty card"));
        osd_txt(p, 2, 6, OSD_A(PF, C_GRIS), T("T la prepara para perfiles.", "T sets it up for profiles."));
    } else if (cl.clase == MXC_INTERRUMPIDA) {
        osd_car(p, 2, 5, OSD_A(PF, C_NARANJA), G_AVISO);
        osd_txt(p, 4, 5, OSD_A(PF, C_NARANJA), T("preparación a medias", "setup interrupted"));
        osd_txt(p, 2, 6, OSD_A(PF, C_GRIS), T("T la termina.", "T finishes it."));
    } else if (cl.clase == MXC_DEFECTUOSA) {
        osd_car(p, 2, 5, OSD_A(PF, C_ROJO), G_NO);
        osd_txt(p, 4, 5, OSD_A(PF, C_ROJO), T("tarjeta no válida", "card not usable"));
        (void)parrafo(p, 2, 6, 27, 3, C_GRIS, error_txt(cl.motivo ? cl.motivo : MXPF_E_FALSA));
    } else {                                                      /* ajena: ni nuestra ni vacia */
        static const char *const fm_es[] = { "?", "sin tabla", "FAT12", "FAT16", "FAT32", "exFAT", "NTFS", "GPT", "otro" };
        static const char *const fm_en[] = { "?", "no table", "FAT12", "FAT16", "FAT32", "exFAT", "NTFS", "GPT", "other" };
        osd_car(p, 2, 5, OSD_A(PF, C_NARANJA), G_AVISO);
        osd_txt(p, 4, 5, OSD_A(PF, C_NARANJA), T("no es del MSXimus Z", "not an MSXimus Z card"));
        x = osd_txt(p, 2, 6, OSD_A(PF, C_BLANCO), osd_ingles ? fm_en[cl.formato] : fm_es[cl.formato]);
        if (cl.nparts) {
            osd_num(b, cl.nparts);
            x = osd_txt(p, x, 6, OSD_A(PF, C_GRIS), " · ");
            x = osd_txt(p, x, 6, OSD_A(PF, C_BLANCO), b);
            osd_txt(p, x, 6, OSD_A(PF, C_GRIS), cl.nparts == 1 ? T(" partición", " partition") : T(" particiones", " partitions"));
        }
        (void)parrafo(p, 2, 7, 27, 2, C_GRIS, T("Para guardar perfiles hay que BORRARLA ENTERA.", "To keep profiles the card must be ERASED."));
    }
}

/* ¿esta instalado el perfil al arrancar, y es de la serie del sistema? 0 no esta, 1 bien, 2 de otra serie */
static int arranque_estado(const mxpf_info_t *in)
{
    int i;
    u32 serie = ota_serie();
    if (in->estado != MXS_OK) return 0;
    for (i = 0; i < in->n; i++) if (igual(in->p[i].id, boot_id)) return (serie != 0U && in->p[i].serie != serie) ? 2 : 1;
    return 0;
}

static void lista(osd_pag p, const mxpf_info_t *in, int n)
{
    char b[48];
    u32 serie = ota_serie();
    int i;
    seccion(p, 12, T("Perfiles", "Profiles"));
    for (i = 0; i <= n; i++) {
        int y = 13 + i, es_act, mal = 0, es_boot = 0;
        u8 tinta = (sel == i) ? C_BLANCO : C_GRIS;
        osd_car(p, 1, y, OSD_A(PF, C_AMARILLO), sel == i ? G_TRI_DER : ' ');
        osd_num(b, (u32)i + 1U);
        osd_txt(p, 3, y, OSD_A(PF, tinta), b);
        if (i == 0) {
            osd_txt(p, 5, y, OSD_A(PF, tinta), T("Normal", "Standard"));   /* el del BOOT.bin (11/11/2026: antes ponia "BOOT.bin") */
            osd_txt_n(p, 14, y, OSD_A(PF, tinta), ota_version(), 9);
            es_act = mxpf_activo() == MXA_PERFIL1;
        } else {
            const mxpf_perfil *e = &in->p[i - 1];
            mal = serie != 0U && e->serie != serie;
            osd_txt_n(p, 5, y, OSD_A(PF, mal ? C_NARANJA : tinta), perfil_nombre(e->id), 8);
            osd_txt_n(p, 14, y, OSD_A(PF, mal ? C_NARANJA : tinta), e->version, 9);
            mb1(b, e->tam);
            osd_txt_der(p, 29, y, OSD_A(PF, mal ? C_NARANJA : C_GRIS), b);
            es_act = es_el_activo(e);
            es_boot = boot_id[0] && igual(e->id, boot_id);
        }
        if (es_act) osd_car(p, 29, y, OSD_A(PF, C_VERDE), G_OK);
        if (es_boot) osd_car(p, 4, y, OSD_A(PF, C_AMARILLO), G_ESTRELLA);                       /* el perfil que se carga al encender */
    }
    if (n == 0 && in->estado == MXS_OK) {
        osd_txt(p, 3, 14, OSD_A(PF, C_GRIS_OSC), T("(ninguno instalado)", "(none installed)"));
        (void)parrafo(p, 3, 15, 26, 4, C_GRIS, T("Sin perfiles: conecta la red y pulsa S, o elige un .MXP en el navegador del menú.",
                                                  "No profiles: connect the network and press S, or pick a .MXP in the menu browser."));
    }
}

/* aviso: lo armado, el resultado de la ultima operacion o una advertencia del elegido (filas 20 a 23) */
static void aviso_armado(osd_pag p, const mxpf_info_t *in, int n, int y)
{
    char b[48], *q;
    const char *s;
    if (armado == A_BORRAR && sel >= 1 && sel <= n) {
        q = b;
        for (s = T("¿Borrar ", "Delete "); *s; ) *q++ = *s++;
        for (s = perfil_nombre(in->p[sel - 1].id); *s; ) *q++ = *s++;
        *q++ = '?'; *q = 0;
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        osd_txt(p, 3, y, OSD_A(PF, C_NARANJA), b);
    } else if (armado == A_BORRAR_TARJETA) {                      /* SEGUNDA tecla: ¿Seguro? Intro */
        osd_car(p, 1, y, OSD_A(PF, C_ROJO), G_AVISO);
        (void)parrafo(p, 3, y, 26, 2, C_ROJO, cl.clase == MXC_NUESTRA_ANTIGUA
                      ? T("¿Seguro? Se borra la tarjeta entera.", "Sure? The whole card is erased.")
                      : T("¿Seguro? Se BORRA la tarjeta ENTERA.", "Sure? The WHOLE card is ERASED."));
        (void)parrafo(p, 3, y + 2, 26, 2, C_NARANJA, cl.clase == MXC_NUESTRA_ANTIGUA
                      ? T("Los perfiles instalados se pierden.", "Installed profiles are lost.")
                      : cl.msxdos ? T("Tiene datos de MSX-DOS (la antigua B:).", "It holds MSX-DOS data (the old B:).")
                                  : T("Lo que tenga se perderá.", "Whatever it holds is lost."));
    } else if (armado == A_PREPARAR && cl.clase == MXC_INTERRUMPIDA) {
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, C_NARANJA, T("Se termina de preparar la tarjeta.", "The card setup is finished."));
    } else if (armado == A_PREPARAR && cl.clase == MXC_VACIA) {
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, C_NARANJA, T("Se escribe en la tarjeta: FAT32 de 128 MB y perfiles de 512 MB.", "This writes to the card: 128 MB FAT32 and 512 MB of profiles."));
    } else if (armado == A_PREPARAR && in->estado == MXS_DANADA) {
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, C_NARANJA, T("Se rehacen los directorios de la partición: se pierde la lista de perfiles.",
                                                    "The partition directories are rebuilt: the profile list is lost."));
    } else if (armado == A_PERFIL1) {
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, C_NARANJA, T("La placa se reinicia y vuelve el Normal.", "The board restarts and Standard comes back."));
    }
}

static void aviso(osd_pag p, const mxpf_info_t *in, int n)
{
    int y = 20, viejos = 0, i;
    u32 serie = ota_serie();
    if (armado) { aviso_armado(p, in, n, y); return; }
    if (msg[0]) {
        osd_car(p, 1, y, OSD_A(PF, msg_ok ? C_VERDE : C_ROJO), msg_ok ? G_OK : G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, msg_ok ? C_BLANCO : C_ROJO, msg);
    } else if (mxpf_arranque_sd() && cl.clase != MXC_NUESTRA && cl.clase != MXC_SIN_TARJETA && cl.clase != MXC_ERROR) {   /* TF1 solo perfiles: es la tarjeta de arranque */
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 4, C_NARANJA, error_txt(MXPF_E_ARRANQUE_SD));
    } else if (ota_perfil_en_curso()) {
        osd_car(p, 1, y, OSD_A(PF, C_AMARILLO), G_BAJAR);
        (void)parrafo(p, 3, y, 26, 3, C_BLANCO, T("Bajando un perfil del servidor: S lo enseña.", "Downloading a profile: S shows it."));
    } else if (sel >= 1 && sel <= n && serie != 0U && in->p[sel - 1].serie != serie) {
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, C_NARANJA, error_txt(MXPF_E_SERIE));
    } else if (boot_id[0] && arranque_estado(in) != 1) {         /* el perfil al arrancar no se podra cargar */
        osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
        (void)parrafo(p, 3, y, 26, 3, C_NARANJA, arranque_estado(in) == 2
                      ? T("El perfil de arranque es de otra serie: arrancará el Normal.", "The boot profile is for another series: Standard starts.")
                      : T("El perfil de arranque no está instalado: arrancará el Normal.", "The boot profile is not installed: Standard starts."));
    } else {
        for (i = 0; i < in->n && in->estado == MXS_OK; i++) if (serie != 0U && in->p[i].serie != serie) viejos++;
        if (viejos) {                                            /* tras una actualizacion del sistema */
            osd_car(p, 1, y, OSD_A(PF, C_NARANJA), G_AVISO);
            (void)parrafo(p, 3, y, 26, 3, C_NARANJA, T("Hay perfiles de otra serie del sistema: S los busca en el servidor.",
                                                        "Profiles for another series: press S to get the new ones."));
        }
    }
}

static void pagina_tarjeta(osd_pag p)
{
    const mxpf_info_t *in = mxpf_estado();
    const mxpf_perfil *act = mxpf_activo_perfil();
    int x, n = n_perfiles();

    osd_limpia(p, OSD_A(PF, C_BLANCO));
    osd_cabecera(p, G_CHIP, T("Perfiles", "Profiles"), NULL);
    tarjeta(p, in);

    seccion(p, 9, T("Corre ahora", "Running now"));
    if (act) {
        x = osd_txt(p, 2, 10, OSD_A(PF, C_AMARILLO), perfil_nombre(act->id));
        osd_txt(p, x + 1, 10, OSD_A(PF, C_BLANCO), act->version);
    } else if (mxpf_activo() == MXA_OTRO) {
        osd_txt(p, 2, 10, OSD_A(PF, C_AMARILLO), T("otro (prueba por la DDR)", "other (DDR test)"));
    } else {
        x = osd_txt(p, 2, 10, OSD_A(PF, C_AMARILLO), T("1 · Normal ", "1 · Standard "));
        osd_txt(p, x, 10, OSD_A(PF, C_BLANCO), ota_version());
    }
    x = osd_txt(p, 2, 11, OSD_A(PF, C_GRIS), T("Al encender: ", "At power-on: "));
    if (!boot_id[0]) osd_txt(p, x, 11, OSD_A(PF, C_GRIS_CL), T("Normal", "Standard"));
    else {
        int e = arranque_estado(in);
        x = osd_txt(p, x, 11, OSD_A(PF, e == 1 ? C_AMARILLO : C_NARANJA), perfil_nombre(boot_id));
        if (e == 2) osd_txt(p, x + 1, 11, OSD_A(PF, C_NARANJA), T("(otra serie)", "(other series)"));
        else if (e == 0) osd_txt(p, x + 1, 11, OSD_A(PF, C_NARANJA), T("(no está)", "(missing)"));
    }

    lista(p, in, n);
    aviso(p, in, n);

    if (armado) {
        (void)osd_boton(p, 1, 24, PF, C_AMARILLO, T("Intro", "Enter"), T("Confirmar", "Confirm"));
        (void)osd_boton(p, 1, 25, PF, C_GRIS_CL, "ESC", T("Cancelar", "Cancel"));
    } else {
        x = 1;
        if (sel >= 1 && sel <= n) {
            x = osd_boton(p, x, 24, PF, C_AMARILLO, T("Intro", "Enter"), T("Cargar", "Load"));
            (void)osd_boton(p, x, 24, PF, C_GRIS_CL, "D", T("Borrar", "Delete"));
        } else if (puede_preparar()) {                            /* sin perfiles que cargar: lo que hace falta hacer con la tarjeta va primero */
            (void)osd_boton(p, x, 24, PF, C_AMARILLO, "T", cl.clase == MXC_INTERRUMPIDA ? T("Terminar", "Finish") : T("Preparar tarjeta", "Set up card"));
        } else if (puede_borrar() && cl.clase == MXC_AJENA) {
            (void)osd_boton(p, x, 24, PF, C_ROJO, "B", T("Borrar y preparar", "Erase and set up"));
        } else if (sel == 0 && mxpf_activo() != MXA_PERFIL1) {
            (void)osd_boton(p, x, 24, PF, C_AMARILLO, T("Intro", "Enter"), T("Normal", "Standard"));
        }
        x = osd_boton(p, 1, 25, PF, C_AMARILLO, "A", T("Inicio", "Boot"));
        (void)osd_boton(p, x, 25, PF, C_AMARILLO, "S", T("Servidor", "Server"));
        x = 1;
        if (in->estado == MXS_SIN_TARJETA || in->estado == MXS_ERROR_TARJETA || cl.clase == MXC_DEFECTUOSA || cl.clase == MXC_AJENA)
            x = osd_boton(p, x, 26, PF, C_AMARILLO, "R", T("Releer", "Reread"));
        else if (puede_borrar())                                   /* NUESTRA_ANTIGUA: sigue siendo util; convertirla es opcional */
            x = osd_boton(p, x, 26, PF, C_AMARILLO, "B", T("Convertir", "Convert"));
        (void)osd_boton(p, x, 26, PF, C_GRIS_CL, "ESC", T("Volver", "Back"));
    }
    osd_txt(p, 1, 27, OSD_A(PF, C_GRIS), T("El MSX está en pausa.", "The MSX is paused."));
}

/* ---- la vista del servidor ------------------------------------------------------------------------------------------- */
static void canal_servidor(osd_pag p, int y)
{
    int x, b = ota_srv_beta();
    (void)osd_txt(p, 1, y, OSD_A(PF, C_GRIS), T("Canal", "Channel"));
    x = osd_pastilla(p, 8, y, PF, !b ? C_CIAN : C_GRIS_OSC, !b ? C_NEGRO : C_GRIS, T("Oficial", "Official")) + 1;
    x = osd_pastilla(p, x, y, PF, b ? C_CIAN : C_GRIS_OSC, b ? C_NEGRO : C_GRIS, "Beta") + 1;
    osd_car(p, x + 1, y, OSD_A(PF, C_GRIS), 'B');
}

/* palabra y color del estado de un perfil del servidor frente a la tarjeta */
static const char *estado_txt(int s, u8 *color)
{
    switch (s) {
        case OPS_AL_DIA:       *color = C_VERDE;   return T("al día", "ok");
        case OPS_OTRA_SERIE:   *color = C_NARANJA; return T("serie", "series");
        case OPS_OTRA_VERSION: *color = C_NARANJA; return T("versión", "version");
        default:               *color = C_CIAN;    return T("nuevo", "new");
    }
}

static void pagina_servidor(osd_pag p)
{
    const mxpf_info_t *in = mxpf_estado();
    char b[48], *q;
    int x, i, n = ota_perfiles_n(), srv = ota_srv_estado();
    int listo = (srv == OSV_LISTO);

    if (ssel >= n) ssel = n ? n - 1 : 0;
    osd_limpia(p, OSD_A(PF, C_BLANCO));
    osd_cabecera(p, G_BAJAR, T("Perfiles · servidor", "Profiles · server"), NULL);
    seccion(p, 3, T("Servidor", "Server"));
    switch (srv) {
        case OSV_BUSCANDO:
            osd_car(p, 2, 4, OSD_A(PF, C_CIAN), (u8)(G_GIRO0 + (gt_now() / ((u64)COUNTS_PER_SECOND / 4U)) % 4U));
            osd_txt(p, 4, 4, OSD_A(PF, C_BLANCO), T("Buscando…", "Looking…"));
            break;
        case OSV_LISTO:
            osd_car(p, 2, 4, OSD_A(PF, C_VERDE), G_OK);
            osd_txt_n(p, 4, 4, OSD_A(PF, C_BLANCO), ota_srv_texto(), 25);
            break;
        case OSV_ERROR:
            osd_car(p, 2, 4, OSD_A(PF, C_ROJO), G_NO);
            osd_txt_n(p, 4, 4, OSD_A(PF, C_ROJO), ota_srv_texto(), 25);
            break;
        case OSV_OCUPADO:
            osd_car(p, 2, 4, OSD_A(PF, C_NARANJA), G_AVISO);
            osd_txt(p, 4, 4, OSD_A(PF, C_NARANJA), T("Actualizando el sistema…", "Updating the system…"));
            break;
        default:
            x = osd_txt(p, 2, 4, OSD_A(PF, C_GRIS), T("Pulsa", "Press"));
            x = osd_pastilla(p, x + 1, 4, PF, C_AMARILLO, C_NEGRO, " U ");
            osd_txt(p, x + 1, 4, OSD_A(PF, C_GRIS), T("para buscar", "to search"));
            break;
    }
    canal_servidor(p, 5);

    seccion(p, 7, T("Perfiles", "Profiles"));
    if (listo && n == 0) osd_txt(p, 3, 8, OSD_A(PF, C_GRIS_OSC), T("(ninguno en el servidor)", "(none on the server)"));
    for (i = 0; listo && i < n; i++) {
        const ota_perfil_t *e = ota_perfil(i);
        int y = 8 + i, s = ota_perfil_estado(i);
        u8 tinta = (ssel == i) ? C_BLANCO : C_GRIS, col;
        const char *w = estado_txt(s, &col);
        osd_car(p, 1, y, OSD_A(PF, C_AMARILLO), ssel == i ? G_TRI_DER : ' ');
        osd_num(b, (u32)i + 1U);
        osd_txt(p, 3, y, OSD_A(PF, tinta), b);
        osd_txt_n(p, 5, y, OSD_A(PF, tinta), perfil_nombre(e->id), 8);
        {   /* la version usa todo el hueco hasta el estado (con 7 fijos, "Z1.3.2b3" salia "Z1.3.2b") */
            int vw = 29 - osd_txt_len(w) - 1 - 14;
            osd_txt_n(p, 14, y, OSD_A(PF, tinta), e->version, vw > 16 ? 16 : vw);
        }
        osd_txt_der(p, 29, y, OSD_A(PF, col), w);
    }

    if (listo && n > 0 && ssel < n) {                                  /* el elegido, con detalle */
        const ota_perfil_t *e = ota_perfil(ssel);
        int s = ota_perfil_estado(ssel);
        seccion(p, 15, T("Elegido", "Selected"));
        x = osd_txt(p, 2, 16, OSD_A(PF, C_AMARILLO), perfil_nombre(e->id));
        osd_txt(p, x + 1, 16, OSD_A(PF, C_BLANCO), e->version);
        mb1(b, e->tamano);
        x = osd_txt(p, 2, 17, OSD_A(PF, C_GRIS_CL), b);
        osd_num(b, e->serie);
        x = osd_txt(p, x + 1, 17, OSD_A(PF, C_GRIS), T("serie ", "series "));
        osd_txt(p, x, 17, OSD_A(PF, C_GRIS_CL), b);
        if (s == OPS_NO) (void)parrafo(p, 2, 18, 27, 2, C_GRIS, T("No está en la tarjeta.", "It is not on the card."));
        else if (s == OPS_OTRA_SERIE) (void)parrafo(p, 2, 18, 27, 2, C_NARANJA, T("La tarjeta tiene el de otra versión del sistema.", "The card has the one for another system version."));
        else if (s == OPS_OTRA_VERSION) (void)parrafo(p, 2, 18, 27, 2, C_NARANJA, T("En la tarjeta hay otra versión.", "The card has another version."));
        else (void)parrafo(p, 2, 18, 27, 2, C_VERDE, T("Ya está en la tarjeta. Intro lo baja otra vez.", "Already on the card. Enter downloads it again."));
    }

    /* abajo: lo armado, la descarga en curso, el resultado, o el estado de la tarjeta */
    if (armado) aviso_armado(p, in, n_perfiles(), 20);
    else if (ota_perfil_en_curso()) {
        u32 hecho, total;
        int k;
        const ota_perfil_t *e;
        ota_perfil_progreso(&hecho, &total, &k);
        e = ota_perfil(k);
        osd_car(p, 1, 20, OSD_A(PF, C_AMARILLO), G_BAJAR);
        q = b;
        { const char *s = T("Bajando ", "Downloading "); while (*s) *q++ = *s++; }
        if (e) { const char *s = perfil_nombre(e->id); while (*s) *q++ = *s++; }
        *q = 0;
        osd_txt(p, 3, 20, OSD_A(PF, C_BLANCO), b);
        osd_barra(p, 1, 21, 23, PF, C_VERDE, C_GRIS_OSC, hecho, total);
        q = osd_num(b, total ? (u32)((u64)hecho * 100U / total) : 0U); *q++ = '%'; *q = 0;
        osd_txt_der(p, 29, 21, OSD_A(PF, C_BLANCO), b);
        q = osd_fijo(b, (u32)((u64)hecho * 10U / 1048576U), 1); { const char *s = T(" de ", " of "); while (*s) *q++ = *s++; }
        q = osd_fijo(q, (u32)((u64)total * 10U / 1048576U), 1); *q++ = ' '; *q++ = 'M'; *q++ = 'B'; *q = 0;
        osd_txt(p, 1, 22, OSD_A(PF, C_GRIS), b);
    } else {
        int cod, nok;
        const char *t;
        int r = ota_perfil_resultado(&cod, &nok, &t);
        if (msg[0]) {
            osd_car(p, 1, 20, OSD_A(PF, msg_ok ? C_VERDE : C_ROJO), msg_ok ? G_OK : G_AVISO);
            (void)parrafo(p, 3, 20, 26, 3, msg_ok ? C_BLANCO : C_ROJO, msg);
        } else if (r == 1) {
            osd_car(p, 1, 20, OSD_A(PF, C_VERDE), G_OK);
            if (nok > 1) {
                q = osd_num(b, (u32)nok);
                { const char *s = T(" perfiles instalados", " profiles installed"); while (*s) *q++ = *s++; }
            } else {
                q = b;
                { const char *s = perfil_nombre(t); while (*s) *q++ = *s++; }          /* r == 1: t es el id del perfil */
                { const char *s = T(" instalado", " installed"); while (*s) *q++ = *s++; }
            }
            *q = 0;
            osd_txt(p, 3, 20, OSD_A(PF, C_VERDE), b);
            osd_txt(p, 3, 21, OSD_A(PF, C_GRIS), T("Volver (ESC) y Intro lo carga.", "Back (ESC), then Enter loads it."));
        } else if (r == 2 || r == 3) {
            osd_car(p, 1, 20, OSD_A(PF, C_ROJO), G_AVISO);
            (void)parrafo(p, 3, 20, 26, 3, C_ROJO, r == 2 ? error_txt(cod) : t);
        } else if (listo && n > 0 && !ota_perfiles_descargables()) {    /* son de una version del sistema que aun no corre */
            osd_car(p, 1, 20, OSD_A(PF, C_NARANJA), G_AVISO);
            (void)parrafo(p, 3, 20, 26, 3, C_NARANJA, T("Son de una versión del sistema aún sin instalar: instálala antes (U en la actualización).",
                                                        "They are for a system version not installed yet: install it first (U in the update page)."));
        } else if (in->estado != MXS_OK) {                              /* sin donde guardarlos: se dice antes de bajar nada */
            osd_car(p, 1, 20, OSD_A(PF, C_NARANJA), G_AVISO);
            (void)parrafo(p, 3, 20, 26, 3, C_NARANJA, in->estado == MXS_SIN_PARTICION ? error_txt(MXPF_E_SINPART)
                          : in->estado == MXS_DANADA ? error_txt(MXPF_E_DIR) : error_txt(MXPF_E_TARJETA));
        }
    }

    if (armado) {
        (void)osd_boton(p, 1, 24, PF, C_AMARILLO, T("Intro", "Enter"), T("Confirmar", "Confirm"));
        (void)osd_boton(p, 1, 25, PF, C_GRIS_CL, "ESC", T("Cancelar", "Cancel"));
    } else if (ota_perfil_en_curso()) {
        osd_boton(p, 1, 25, PF, C_GRIS_CL, "ESC", T("Ocultar (sigue)", "Hide (keeps going)"));
    } else {
        x = 1;
        if (listo && n > 0 && in->estado == MXS_OK && ota_perfiles_descargables()) {
            x = osd_boton(p, x, 24, PF, C_AMARILLO, T("Intro", "Enter"), T("Bajar", "Get"));
            (void)osd_boton(p, x, 24, PF, C_AMARILLO, "A", T("Todos", "All"));
        } else if (puede_preparar()) (void)osd_boton(p, x, 24, PF, C_AMARILLO, "T", cl.clase == MXC_INTERRUMPIDA ? T("Terminar", "Finish") : T("Preparar tarjeta", "Set up card"));
        x = osd_boton(p, 1, 25, PF, C_AMARILLO, "U", T("Buscar", "Search"));
        (void)osd_boton(p, x, 25, PF, C_AMARILLO, "B", T("Canal", "Channel"));
        (void)osd_boton(p, 1, 26, PF, C_GRIS_CL, "ESC", T("Volver", "Back"));
    }
    osd_txt(p, 1, 27, OSD_A(PF, C_GRIS), T("El MSX está en pausa.", "The MSX is paused."));
}

void perfiles_pagina(osd_pag p)
{
    if (vista == V_SERVIDOR) pagina_servidor(p); else pagina_tarjeta(p);
}
