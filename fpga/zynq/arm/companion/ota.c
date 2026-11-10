/* ota.c — actualizacion por red de la MSXimus Z (30/09/2026).
 *
 * La QSPI (16 MB) lleva DOS BOOT.bin:
 *   ranura A en 0x000000: la de fabrica, la que se graba por JTAG (tools/qspi_program.tcl). Esto no la toca nunca.
 *   ranura B en 0x800000: la que baja este fichero (hasta 0x7F0000 B: los 64 KB de 0xFF0000 son registro + config).
 *   registro en 0xFFE000 (sector de 4 KB): que hay en la B y si ya arranco bien (formato abajo).
 *   config en 0xFFF000 (qspi_cfg.c).
 * Arranque (fsbl/fsbl_hooks.c + ota_arranque): el BootROM carga siempre la A; su FSBL salta a la B (MULTIBOOT = 0x100
 * y reinicio del PS) solo si esta CONFIRMADA. Una B nueva la prueba el companion de la A: gasta un intento (tres como
 * mucho) y reinicia en la B; el companion de la B la confirma cuando ve al MSX leer la tarjeta (o, sin tarjeta, 20 s
 * de Z80 vivo). Si la B no llega a confirmarse, al apagar y encender se vuelve a la A y, gastados los tres intentos,
 * la A lo dice en el OSD. Con la placa en modo JTAG no se reinicia nada (no habria BootROM de QSPI que la cargara).
 *
 * Descarga (OSD, F12): U busca. Primero pregunta por UDP (difusion al puerto 9474) si hay un servidor de desarrollo en
 * la red local (fpga/zynq/ota/ota_servidor.py contesta "MSXIMUS-OTA <url>"); si nadie contesta, usa OTA_URL. Baja
 * <url>manifiesto.txt, comprueba su firma ECDSA P-256 con la clave publica compilada (ota_clave.h; la privada no esta
 * en ningun repo) y, si su serie es mayor que la instalada, lo ofrece. I baja el BOOT.bin de la variante de Nextor
 * que lleva la placa a la DDR (0x01000000, 8 MB con cache), comprueba tamano, SHA-256, cabecera de arranque y su
 * particion ota_info (misma serie), BORRA el registro (desde aqui un apagon deja la A), graba la B, la relee entera
 * (SHA-256 otra vez) y escribe el registro nuevo. R reinicia (gastando un intento), F (dos veces) vuelve a la A.
 * Sin verificar certificados TLS (como el ESP): la integridad la da la firma del manifiesto, no el canal.
 *
 * Canal beta (Z1.3, 30/10/2026): B en la pagina alterna Oficial / Beta y busca otra vez. La beta tiene su carpeta
 * (OTA_URL_BETA) y su manifiesto, firmado con la misma clave y con "canal=beta"; lleva las builds de los experimentos
 * en una sola variante (nextor214-en). Cada BOOT.bin dice su canal en ota_info (make_boot.sh, OTA_CANAL), y un cambio
 * de canal se ofrece aunque la serie no sea mayor: asi se vuelve de una beta a la oficial.
 *
 * Sin cable (02/10/2026): por la WiFi del ESP32 del CAM1 (la S3), que el PL le presta al companion mientras dura la
 * busqueda o la descarga (s3_link.c; el MSX se queda sin el). El mismo cliente HTTP, con DNS, TCP y TLS en el ESP: el
 * TLS pide validar el certificado (el firmware de serie trae las raices) y, si no puede, repite sin validar. El
 * descubrimiento del servidor del PC va por UDP del ESP, tras un DNS de msx.barcelona que despierta su radio.
 *
 * Perfiles del PL (31/10/2026): el manifiesto puede llevar lineas perfil=<ID> <version> <fichero> <tamano> <sha256> <tamano del
 * .bin> <serie> (ota_publicar.py --perfil, dentro de la parte firmada; un companion de antes las salta, como cualquier linea que
 * no conoce). La pagina Perfiles (perfiles.c, tecla S) los lista con su estado frente a la tarjeta de TF1 y baja uno ("Intro") o
 * todos los que falten o esten viejos ("A"): el .mxp llega a la misma zona de 9 MB y con el mismo cliente HTTP(S) que el BOOT.bin
 * (SHA-256 al vuelo), se comprueba su cabecera (id, version, serie, tamano del .bin: lo que dice el manifiesto) y se instala en
 * la TF1 con mxpf_instala (hueco libre, relectura, directorio). Un perfil solo se carga con el sistema de su serie, asi que
 * cada BOOT.bin nuevo deja los de la tarjeta "de otra serie": ota_perfiles_viejos() lo cuenta y la pagina de la actualizacion
 * lo avisa (tecla P). La descarga de un perfil NO toca el estado del BOOT (st): lleva su propio estado (pst).
 *
 * Particion ota_info (make_boot.sh, DDR 0x00E10000): "MOTI1\nversion=..\nserie=..\nvariante=..\nplaca=..\n": asi
 * cada BOOT.bin sabe que es. Se borra al leerla (tras un reinicio la DDR conserva la de la imagen anterior).
 *
 * Registro (0xFFE000, primera pagina; lo lee tambien el FSBL):
 *   +0x00 "MOTA"  +0x04 formato (1)  +0x08 serie  +0x0C tamano  +0x10 desplazamiento (0x800000)  +0x14 SHA-256 (32)
 *   +0x34 version (16)  +0x44 variante (16)  +0x54 CRC-32 de +0x00..+0x53
 *   +0x80..+0x82 intentos (0xFF libre, 0x00 gastado)  +0x88 confirmada (0xFF no, 0x00 si)
 * Cada byte de intento o de confirmacion se programa una sola vez de FF a 00, sin borrar el sector. */
#include "xil_types.h"
#include "xil_io.h"
#include "sleep.h"
#include "lwip/sys.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/dns.h"
#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "mbedtls/sha256.h"
#include "mbedtls/ecdsa.h"
#include "mbedtls/ecp.h"
#include "mbedtls/bignum.h"
#include "log.h"
#include "esp.h"
#include "s3.h"
#include "ota.h"
#include "osd.h"
#include "ota_clave.h"
#include "profile.h"                                 /* PF_DATOS: la zona sin cache de los perfiles */
#include "mxpf.h"
#include "bootsd.h"                                  /* leer el BOOT.bin de la TF1 (ranura A desde la SD) */

#define OTA_URL         "https://msx.barcelona/wp-content/ota/zynq/"   /* IONOS: el SFTP solo llega a wp-content */
#define OTA_URL_BETA     OTA_URL "beta/"                                /* canal beta (Z1.3): ota_publicar.py --canal beta */
#define OTA_PLACA        "zynq7020-mini"
#define OTA_UDP          9474U
#define OTA_UA           "MSXimus-Z/OTA"
#define OTA_INTENTOS     3U
#define MAX_PERF         6U                          /* lineas perfil= que se leen: los huecos de la tarjeta (MXPF_MAX_PERF) */
#define PERF_MAX_MXP     0x00380200U                 /* un .mxp: 3,5 MB de contenido + 512 de cabecera (mxpf.c: MX_MAXPAY) */

#define SLOT_B           0x00800000U
#define REG_ADDR         0x00FFE000U
#define IMG_MAX          0x007F0000U
#define MB_B             (SLOT_B / 0x8000U)
#define R_INTENTO        0x80U
#define R_OK             0x88U

#define OTA_MEM          0x01000000U                /* mmu.c: 9 MB con cache (solo este core, sin DMA) */
#define IMG              ((u8 *)OTA_MEM)
#define INFO_DDR         0x00E10000U
#define PACK_DDR         0x10F00000U
#define PACK_LEN         0x00080000U

#define DEVCFG_MULTIBOOT 0xF800702CU
#define BOOT_MODE_REG    0xF800025CU
#define BOOT_MODO_SD     5U                          /* BOOT_MODE[2:0]: 1 = QSPI, 5 = SD, 0 = JTAG */
#define SLCR_UNLOCK     0xF8000008U
#define PSS_RST_CTRL     0xF8000200U
#define MBOX             0x1FF00000U
#define SDBOX            0x1FF00100U

typedef struct {
    char manif[8192];
    char hdr[8192];                                  /* cabeceras: un Location de un CDN pasa de 1 KB */
    u8   rb[16384];                                  /* relectura de la QSPI */
    u8   reg[256];
    mbedtls_sha256_context sha;
} ota_mem_t;
#define W ((ota_mem_t *)(OTA_MEM + 0x00800000U))

/* O_SD_*: la placa arrancada desde SD graba la ranura A con el BOOT.bin de la TF1 (sin Vivado): leyendo, listo para grabar, grabada */
enum { O_REPOSO = 0, O_BUSCA, O_MANIF, O_AL_DIA, O_HAY, O_BAJA, O_GRABA, O_LISTA, O_ERROR, O_SD_LEE, O_SD_LISTO, O_SD_HECHO };

static u8  st, paso, sucio = 1;
static u8  en_b, boot_qspi, boot_sd, reg_ok, reg_conf, reg_usados, info_ok, f_armada;
static u8  a_armada, a_sd;                            /* tecla A pulsada una vez; la grabacion en curso va a la ranura A (no a la B) */
static u8  a_dg;                                      /* el error es "no es FAT16 ni FAT32": la linea de debajo dice lo que se vio (bootsd_diag) */
static char a_ver[16], a_var[16];                     /* version y variante del BOOT.bin leido de la SD */
static u8  beta_act, beta_pide;                       /* canal de la imagen que corre y el que se busca (1 = beta) */
static u32 serie_act, reg_serie;
static char ver_act[16], var_act[16], reg_ver[16];
static char aviso[32], msg[32];
static char url_base[160], servidor[32];
static u32 pos, len, t_paso;
typedef struct { ota_perfil_t p; char fichero[64]; u8 sha[32]; } perf_t;   /* una linea perfil= (p: lo que ve la pagina) */
static struct {
    char version[16], fecha[12];
    u32 serie;
    u8 beta;                                         /* el manifiesto dice canal=beta */
    char notas[3][64];                               /* UTF-8: 25 caracteres pueden ser mas de 25 bytes */
    u8 nn, nimg, sel;                                /* imagenes en el manifiesto (una por variante) y la elegida */
    struct { char var[16]; char fichero[64]; u32 tamano; u8 sha[32]; } img[4];
    u8 np;                                           /* lineas perfil= validas */
    perf_t perf[MAX_PERF];
} mf;
#define IMGSEL (mf.img[mf.sel])
static char reg_var[16];
static u32 conf_t, conf_z80, conf_vivo, t_arranque;
/* descarga de perfiles (31/10): pst 0 reposo, 1 bajando (el cliente HTTP es nuestro), 2 instalando en la TF1 (bloqueante, dentro de
 * una sola llamada). pcola: los que faltan por bajar (bit i = mf.perf[i]). pres: el resultado que ve la pagina Perfiles. */
static u8  pst, pcur, pcola, pres, pn_ok, pnuevo;
static int pcod;
static u32 plen, pt0;
static char pmsg[48], pid[9];

/* ---- utilidades (sin newlib: memcpy de newlib y memoria strongly-ordered no se llevan) ---------------------------- */
static u32 slen(const char *s) { u32 n = 0; while (s[n]) n++; return n; }
static void scpy(char *d, const char *s, u32 cap) { u32 i = 0; while (s[i] && i + 1U < cap) { d[i] = s[i]; i++; } d[i] = 0; }
static int pfx(const char *s, const char *p) { while (*p) if (*s++ != *p++) return 0; return 1; }
static char *put_s(char *d, const char *s) { while (*s) *d++ = *s++; *d = 0; return d; }
static char *put_u(char *d, u32 v) { char t[11]; int n = 0; do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v); while (n) *d++ = t[--n]; *d = 0; return d; }
static int hexv(char c) { return (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : -1; }
static int hex_a_bytes(const char *h, u8 *d, u32 n) { u32 i; for (i = 0; i < n; i++) { int a = hexv(h[2 * i]), b = hexv(h[2 * i + 1]); if (a < 0 || b < 0) return 0; d[i] = (u8)(a * 16 + b); } return 1; }
static u32 rd32(const u8 *p) { return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24); }
static void wr32(u8 *p, u32 v) { p[0] = (u8)v; p[1] = (u8)(v >> 8); p[2] = (u8)(v >> 16); p[3] = (u8)(v >> 24); }
static void set_msg(const char *s) { scpy(msg, s, sizeof msg); sucio = 1; }
static int var_n3(const char *v);
static int var_en(const char *v);
static int igual(const char *a, const char *b);

static u32 crc32(const u8 *p, u32 n)
{
    u32 c = 0xFFFFFFFFU, k;
    while (n--) { c ^= *p++; for (k = 0; k < 8U; k++) c = (c >> 1) ^ (0xEDB88320U & (0U - (c & 1U))); }
    return ~c;
}

/* "clave=valor" de un texto de lineas (info o manifiesto): copia el valor (hasta fin de linea) o 0 si no esta */
static int campo(const char *t, u32 n, const char *clave, char *d, u32 cap)
{
    u32 i = 0, kl = slen(clave);
    while (i < n && t[i]) {
        if (i + kl < n && pfx(t + i, clave) && t[i + kl] == '=') {
            u32 j = i + kl + 1U, k = 0;
            while (j < n && t[j] && t[j] != '\n' && t[j] != '\r' && k + 1U < cap) d[k++] = t[j++];
            d[k] = 0;
            return 1;
        }
        while (i < n && t[i] && t[i] != '\n') i++;
        i++;
    }
    return 0;
}
static u32 a_num(const char *s) { u32 v = 0; while (*s >= '0' && *s <= '9') v = v * 10U + (u32)(*s++ - '0'); return v; }

/* ---- donde estamos ------------------------------------------------------------------------------------------------- */
static void info_leer(void)                          /* particion ota_info de la imagen que ha arrancado */
{
    volatile char *vi = (volatile char *)INFO_DDR;
    char t[256], v[20];
    u32 i;
    for (i = 0; i < sizeof t; i++) t[i] = vi[i];
    t[sizeof t - 1U] = 0;
    info_ok = pfx(t, "MOTI1\n") && pfx(t + 6, "version=");
    vi[0] = 0;                                      /* que un reinicio a una imagen sin info no herede esta */
    if (!info_ok) return;
    if (campo(t, sizeof t, "version", v, sizeof v)) scpy(ver_act, v, sizeof ver_act);
    if (campo(t, sizeof t, "variante", v, sizeof v)) scpy(var_act, v, sizeof var_act);
    if (campo(t, sizeof t, "serie", v, sizeof v)) serie_act = a_num(v);
    beta_act = campo(t, sizeof t, "canal", v, sizeof v) && pfx(v, "beta");   /* sin canal (antes de la Z1.3): oficial */
    beta_pide = beta_act;
}

static int en_el_pack(const char *m)                  /* busca un texto en el pack de BIOS (0x10F00000) */
{
    volatile const u8 *p = (volatile const u8 *)PACK_DDR;
    u32 i, k, n = slen(m);
    for (i = 0; i + n < PACK_LEN; i++) {
        for (k = 0; k < n && p[i + k] == (u8)m[k]; k++) { }
        if (k == n) return 1;
    }
    return 0;
}

static void variante_del_pack(void)                  /* sin info: la variante se ve en el pack (Nextor 3 e idioma) */
{
    char *q = put_s(var_act, en_el_pack("NEXTORv3_DRIVER") ? "nextor3" : "nextor214");
    if (en_el_pack("MSXimus - Settings")) put_s(q, "-en");   /* el menu en ingles (ENGLISH=1) */
}

static void reg_leer(void)
{
    u8 *r = W->reg;
    u32 i;
    qspi_read(REG_ADDR, r, 256);
    reg_ok = r[0] == 'M' && r[1] == 'O' && r[2] == 'T' && r[3] == 'A' && r[4] == 1U && crc32(r, 0x54U) == rd32(r + 0x54)
             && rd32(r + 0x10) == SLOT_B && rd32(r + 0x0C) <= IMG_MAX;
    reg_conf = reg_ok && r[R_OK] == 0x00U;
    reg_usados = 0;
    for (i = 0; i < OTA_INTENTOS; i++) if (r[R_INTENTO + i] != 0xFFU) reg_usados++;
    reg_serie = reg_ok ? rd32(r + 0x08) : 0U;
    reg_ver[0] = 0; reg_var[0] = 0;
    if (reg_ok) {
        for (i = 0; i < 15U; i++) { reg_ver[i] = (char)r[0x34 + i]; reg_var[i] = (char)r[0x44 + i]; }
        reg_ver[15] = 0; reg_var[15] = 0;
    }
}

static int cabecera_b_ok(void)                        /* la misma comprobacion que el FSBL */
{
    u8 h[0x4C];
    u32 a, sum = 0;
    qspi_read(SLOT_B, h, sizeof h);
    if (rd32(h + 0x20) != 0xAA995566U || rd32(h + 0x24) != 0x584C4E58U) return 0;
    for (a = 0x20U; a <= 0x44U; a += 4U) sum += rd32(h + a);
    return ~sum == rd32(h + 0x48);
}

static void prog_byte(u32 addr, u8 v) { qspi_prog_start(addr, &v, 1); qspi_wait(); }

/* reinicio del PS: el BootROM arranca la imagen de MULTIBOOT. Antes se paran TODOS los masters de la DDR, como hace
 * tools/boot.tcl antes de ps7_init (el FSBL que viene reentrena el DDRC): 30/09, primera prueba en placa, tras la R
 * el teclado no volvia hasta quitar la corriente = el EHCI colgado por una lectura de DMA a medias (lo mismo del
 * 22/09 con JTAG). Orden: MSX en reset, USB0 (RS = 0, HCHalted, RST), GEM0 (RX/TX fuera), masters del PL en reset
 * (FCLK_RESET) y level shifters solo PS->PL. */
#define USB0_USBCMD      0xE0002140U
#define USB0_USBSTS      0xE0002144U
#define GEM0_NWCTRL      0xE000B000U
#define SLCR_FPGA_RST    0xF8000240U
#define SLCR_LVL_SHFTR   0xF8000900U
#define SLCR_APER_CLK    0xF800012CU
static void reiniciar(u32 multiboot)
{
    volatile u32 *ctl = (volatile u32 *)(MBOX + 0x1CU);
    u32 i;
    log_str("ota: reinicio (MULTIBOOT "); log_hex(multiboot); log_str(")\n");
    Xil_Out32(DEVCFG_MULTIBOOT, multiboot);
    if ((Xil_In32(DEVCFG_MULTIBOOT) & 0x1FFFU) != multiboot) {   /* devcfg bloqueado: reiniciar volveria aqui */
        log_str("ota: MULTIBOOT no se deja escribir\n");
        set_msg(T("No se puede reiniciar", "Can't restart"));
        return;
    }
    *ctl &= ~1U;                                     /* MSX en reset: el PL deja de tirar de la DDR */
    usleep(20000);
    if (Xil_In32(SLCR_APER_CLK) & (1U << 2)) {      /* solo con reloj: un periferico sin reloj cuelga el bus */
        Xil_Out32(USB0_USBCMD, Xil_In32(USB0_USBCMD) & ~1U); /* EHCI: RS = 0 ... */
        for (i = 0; i < 100U && !(Xil_In32(USB0_USBSTS) & 0x1000U); i++) usleep(1000);   /* ... hasta HCHalted */
        Xil_Out32(USB0_USBCMD, 2U);                  /* RST: la DMA se queda quieta */
    }
    if (Xil_In32(SLCR_APER_CLK) & (1U << 6)) Xil_Out32(GEM0_NWCTRL, 0U);   /* GEM0: RX/TX fuera (su DMA tambien) */
    usleep(20000);
    Xil_Out32(SLCR_UNLOCK, 0xDF0DU);
    Xil_Out32(SLCR_FPGA_RST, 0xFU);                  /* masters del PL en reset: VALID = 0, READY = 1, drenan */
    usleep(150000);
    Xil_Out32(SLCR_LVL_SHFTR, 0xAU);                 /* solo PS->PL hasta que el FSBL lo abra */
    dsb(); isb();
    Xil_Out32(PSS_RST_CTRL, 1U);
    for (;;) { }
}

void ota_reinicia_ps(void)                            /* profile.c: un PCAP fallido deja el PL roto; mismo MULTIBOOT = misma ranura */
{
    reiniciar(Xil_In32(DEVCFG_MULTIBOOT) & 0x1FFFU);
}

static int probar_b(void)                             /* gasta un intento y reinicia en la B; 0 si no se puede */
{
    if (!boot_qspi || !reg_ok || reg_conf || reg_usados >= OTA_INTENTOS || !cabecera_b_ok()) return 0;
    prog_byte(REG_ADDR + R_INTENTO + reg_usados, 0x00);
    log_str("ota: probando la B (intento "); log_dec(reg_usados + 1U); log_str(")\n");
    reiniciar(MB_B);
    return 1;
}

void ota_arranque(void)
{
    u32 mb = Xil_In32(DEVCFG_MULTIBOOT) & 0x1FFFU;
    en_b = (mb == MB_B);
    boot_qspi = (Xil_In32(BOOT_MODE_REG) & 7U) == 1U;
    boot_sd = (Xil_In32(BOOT_MODE_REG) & 7U) == BOOT_MODO_SD;
    t_arranque = sys_now();
    scpy(ver_act, "?", sizeof ver_act);
    info_leer();
    if (!var_act[0]) variante_del_pack();
    osd_ingles = (u8)var_en(var_act);                /* el OSD habla el idioma del menu de esta imagen */
    if (!qspi_open()) { log_str("ota: sin QSPI\n"); return; }
    reg_leer();
    if (en_b && !info_ok && reg_ok) { scpy(ver_act, reg_ver, sizeof ver_act); serie_act = reg_serie; }
    log_str("ota: ranura "); log_str(en_b ? "B" : "A"); log_str(" "); log_str(ver_act); log_str(" "); log_str(var_act);
    log_str(boot_qspi ? " (QSPI)" : boot_sd ? " (SD)" : " (sin QSPI)");
    if (reg_ok) { log_str(", registro "); log_str(reg_ver); log_str(reg_conf ? " confirmada" : " sin confirmar"); }
    log_str("\n");
    if (!reg_ok || en_b) return;
    if (reg_conf) {                                  /* el FSBL deberia haber saltado: FSBL antiguo o cabecera de B mala */
        if (boot_qspi && cabecera_b_ok()) { log_str("ota: el FSBL no salto a la B: salto yo\n"); reiniciar(MB_B); }
        return;
    }
    if (reg_usados == 0U) { (void)probar_b(); return; }   /* recien grabada: la primera prueba es automatica */
    {   /* ya se probo y no llego a confirmarse: se sigue con la A y se dice (R la prueba otra vez) */
        char *p = put_s(aviso, reg_ver);
        put_s(p, T(" no arrancó", " didn't boot"));
    }
}

/* ---- confirmacion de la B: el MSX lee la tarjeta (o 20 s de Z80 vivo sin tarjeta) -------------------------------- */
static void confirmar_poll(void)
{
    volatile u32 *sb = (volatile u32 *)SDBOX, *tel = (volatile u32 *)(MBOX + 0x40U);
    u32 now = sys_now(), z;
    if (!en_b || !reg_ok || reg_conf || st == O_GRABA || now - conf_t < 1000U) return;
    conf_t = now;
    z = tel[2] + tel[3];                             /* aciertos + fallos de la cache de la RAM del Z80 */
    conf_vivo = (z != conf_z80) ? conf_vivo + 1U : 0U;
    conf_z80 = z;
    if (((sb[1] & 1U) && sb[8] > 0U && now - t_arranque > 5000U) || (!(sb[1] & 1U) && conf_vivo >= 20U)) {
        prog_byte(REG_ADDR + R_OK, 0x00);
        reg_leer();
        log_str(reg_conf ? "ota: B confirmada\n" : "ota: B sin poder confirmar\n");
        sucio = 1;
    }
}

/* ---- cliente HTTP/HTTPS (una peticion a la vez; nada bloquea) ------------------------------------------------------- */
enum { H_LIBRE = 0, H_DNS, H_CONECTA, H_TLS, H_PIDE, H_CABECERA, H_CUERPO, H_HECHO, H_FALLO, H_S3 };
static u8 via_s3;                                    /* la busqueda o la descarga en curso van por la S3 (sin cable) */
static u8 s3b[2048];                                 /* lo ultimo que dio TCP_RCV de la S3 */
static struct {
    u8  st, tls_on, cerrado, saltos, con_sha;
    u8  s3, s3c, s3_valida, vacios;                  /* por la S3: conexion (1..4, 0 ninguna), validar el certificado */
    u32 s3_n, s3_pos, t_rcv;
    u16 puerto;
    char host[64];
    char ruta[2048];                                 /* 01/10: los releases de GitHub redirigen a URLs firmadas de >1 KB */
    ip_addr_t ip;
    struct tcp_pcb *pcb;
    struct pbuf *rxq;
    u32 rx_total;
    esp_tls_t *tls;
    u32 hlen, clen, got, cap, t_ult;
    u8 *dst;
    const char *err;
} h;

static void h_soltar(void)
{
    if (h.tls) { tls_free(h.tls); h.tls = NULL; }
    if (h.pcb) { tcp_arg(h.pcb, NULL); tcp_recv(h.pcb, NULL); tcp_err(h.pcb, NULL); if (tcp_close(h.pcb) != ERR_OK) tcp_abort(h.pcb); h.pcb = NULL; }
    if (h.rxq) { pbuf_free(h.rxq); h.rxq = NULL; }
    h.rx_total = 0;
    if (h.s3c) { s3_tcp_cierra(h.s3c); h.s3c = 0; }
    h.s3_n = h.s3_pos = 0;
}

static void h_fallo(const char *why)
{
    log_str("ota: http "); log_str(h.host); log_str(": "); log_str(why); log_str("\n");
    h_soltar();
    h.err = why;
    h.st = H_FALLO;
}

static err_t h_recv_cb(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err)
{
    (void)arg; (void)pcb; (void)err;
    if (p == NULL) { h.cerrado = 1; if (h.tls) tls_remote_closed(h.tls); return ERR_OK; }
    if (h.rxq) pbuf_cat(h.rxq, p); else h.rxq = p;
    h.rx_total += p->tot_len;
    return ERR_OK;
}

static void h_err_cb(void *arg, err_t err)            /* lwIP ya libero el pcb */
{
    (void)arg; (void)err;
    h.pcb = NULL; h.cerrado = 1;
    if (h.tls) { tls_detach(h.tls); tls_remote_closed(h.tls); }
    if (h.st < H_CUERPO) h_fallo("conexion rechazada");
}

static err_t h_conn_cb(void *arg, struct tcp_pcb *pcb, err_t err)
{
    (void)arg; (void)err;
    h.t_ult = sys_now();
    if (!h.tls_on) { h.st = H_PIDE; return ERR_OK; }
    h.tls = tls_new(pcb, &h.rxq, &h.rx_total, h.host);
    if (h.tls == NULL) { tcp_arg(pcb, NULL); tcp_recv(pcb, NULL); tcp_err(pcb, NULL); tcp_abort(pcb); h.pcb = NULL; h_fallo("sin memoria TLS"); return ERR_ABRT; }
    h.st = H_TLS;
    return ERR_OK;
}

/* por la S3: TCP_OPEN {IP, puerto remoto, local 0xFFFF al azar, plazo 0, flags (4 TLS, 8 validar), host para el SNI} */
static void h_conecta_s3(void)
{
    u8 d[11 + 64];
    u32 n = 11U, i;
    const ip4_addr_t *a = ip_2_ip4(&h.ip);
    d[0] = ip4_addr1(a); d[1] = ip4_addr2(a); d[2] = ip4_addr3(a); d[3] = ip4_addr4(a);
    d[4] = (u8)h.puerto; d[5] = (u8)(h.puerto >> 8); d[6] = 0xFFU; d[7] = 0xFFU; d[8] = 0; d[9] = 0;
    d[10] = h.tls_on ? (u8)(4U | (h.s3_valida ? 8U : 0U)) : 0U;
    if (h.tls_on) { for (i = 0; h.host[i]; i++) d[n++] = (u8)h.host[i]; d[n++] = 0; }
    h.st = H_CONECTA; h.t_ult = sys_now();
    if (!s3_pide(13, d, n, 30000U)) h_fallo("sin S3");
}

static void h_conecta(void)
{
    if (h.s3) { h_conecta_s3(); return; }
    h.pcb = tcp_new();
    if (h.pcb == NULL) { h_fallo("sin pcb"); return; }
    tcp_arg(h.pcb, &h); tcp_recv(h.pcb, h_recv_cb); tcp_err(h.pcb, h_err_cb);
    tcp_nagle_disable(h.pcb);
    h.st = H_CONECTA; h.t_ult = sys_now();
    if (tcp_connect(h.pcb, &h.ip, h.puerto, h_conn_cb) != ERR_OK) { tcp_abort(h.pcb); h.pcb = NULL; h_fallo("tcp_connect"); }
}

static void h_dns_cb(const char *name, const ip_addr_t *ip, void *arg)
{
    (void)name; (void)arg;
    if (h.st != H_DNS) return;
    if (ip == NULL || ip_addr_isany(ip)) { h_fallo("DNS"); return; }
    h.ip = *ip;
    h_conecta();
}

static int h_url(const char *url)                     /* http[s]://host[:puerto]/ruta */
{
    const char *p;
    u32 n = 0;
    if (pfx(url, "http://")) { h.tls_on = 0; h.puerto = 80; p = url + 7; }
    else if (pfx(url, "https://")) { h.tls_on = 1; h.puerto = 443; p = url + 8; }
    else return 0;
    while (*p && *p != ':' && *p != '/' && n + 1U < sizeof h.host) h.host[n++] = *p++;
    h.host[n] = 0;
    if (n == 0U) return 0;
    if (*p == ':') { p++; h.puerto = (u16)a_num(p); while (*p >= '0' && *p <= '9') p++; }
    if (*p != '/' && *p != 0) return 0;
    scpy(h.ruta, *p ? p : "/", sizeof h.ruta);
    return h.puerto != 0U;
}

static int ip_literal(const char *s, u8 *o)           /* "a.b.c.d" estricto */
{
    u32 v = 0, n = 0, dig = 0;
    for (; *s; s++) {
        if (*s >= '0' && *s <= '9') { v = v * 10U + (u32)(*s - '0'); if (++dig > 3U || v > 255U) return 0; }
        else if (*s == '.' && dig && n < 3U) { o[n++] = (u8)v; v = 0; dig = 0; }
        else return 0;
    }
    if (n != 3U || !dig) return 0;
    o[3] = (u8)v;
    return 1;
}

static void h_arranca(void)
{
    err_t e;
    h.st = H_DNS; h.cerrado = 0; h.hlen = 0; h.got = 0; h.clen = 0xFFFFFFFFU; h.t_ult = sys_now(); h.err = 0;
    h.vacios = 0; h.t_rcv = sys_now();
    if (h.s3) {                                      /* el DNS lo hace el ESP (una IP escrita, aqui mismo) */
        u8 ip[4];
        if (ip_literal(h.host, ip)) { IP4_ADDR(ip_2_ip4(&h.ip), ip[0], ip[1], ip[2], ip[3]); h_conecta(); }
        else if (!s3_pide(6, (const u8 *)h.host, slen(h.host), 20000U)) h_fallo("sin S3");
        return;
    }
    e = dns_gethostbyname(h.host, &h.ip, h_dns_cb, NULL);   /* una IP escrita en la URL vuelve ERR_OK sin preguntar */
    if (e == ERR_OK) h_conecta();
    else if (e != ERR_INPROGRESS) h_fallo("DNS");
}

static int h_get(const char *url, u8 *dst, u32 cap, int con_sha)
{
    h_soltar();
    h.saltos = 0; h.dst = dst; h.cap = cap; h.con_sha = (u8)con_sha;
    h.s3 = via_s3; h.s3_valida = 1;
    if (!h_url(url)) { h.st = H_FALLO; h.err = "URL"; return 0; }
    if (h.tls_on && !h.s3 && !tls_available()) { h.st = H_FALLO; h.err = "sin TLS"; return 0; }
    if (h.s3 && !s3_lista()) { h.st = H_S3; h.t_ult = sys_now(); return 1; }   /* la S3 recien tomada: 300 ms */
    h_arranca();
    return 1;
}

static void h_pide(void)
{
    static u8 req[2400];
    char *p = (char *)req;
    int r;
    p = put_s(p, "GET "); p = put_s(p, h.ruta); p = put_s(p, " HTTP/1.1\r\nHost: "); p = put_s(p, h.host);
    p = put_s(p, "\r\nUser-Agent: " OTA_UA " ");     /* MSXimus-Z/OTA 1.4.0 (TR): version y perfil, sin nada que identifique a la placa */
    p = put_s(p, ver_act[0] == 'Z' ? ver_act + 1 : ver_act);
    p = put_s(p, " (");
    {
        const char *id = mxpf_id_activo();
        p = put_s(p, id[0] ? id : "STD");
    }
    p = put_s(p, ")\r\nAccept: */*\r\nConnection: close\r\n\r\n");
    if (h.s3) {                                      /* TCP_SEND de hasta 2 KB (la peticion con una URL firmada pasa de 1 KB) */
        u32 n = (u32)(p - (char *)req), o = 0, k;
        while (o < n) {
            k = n - o; if (k > 2000U) k = 2000U;
            if (s3_tcp_manda(h.s3c, req + o, k) < 0) { h_fallo("GET"); return; }
            o += k;
        }
    } else if (h.tls) {
        r = tls_write(h.tls, req, (u32)(p - (char *)req));
        if (r < 0) { h_fallo("GET"); return; }
        if (r == 0) return;                          /* sin sitio: la vuelta siguiente */
    } else {
        if (h.pcb == NULL || tcp_sndbuf(h.pcb) < (u32)(p - (char *)req)) return;
        if (tcp_write(h.pcb, req, (u16)(p - (char *)req), TCP_WRITE_FLAG_COPY) != ERR_OK) { h_fallo("GET"); return; }
        tcp_output(h.pcb);
    }
    h.st = H_CABECERA; h.t_ult = sys_now();
}

static u32 h_disp(void) { return h.s3 ? h.s3_n - h.s3_pos : h.tls ? tls_avail(h.tls) : h.rx_total; }

static u32 h_toma(u8 *d, u32 n)                       /* texto en claro de la respuesta */
{
    if (h.s3) {
        u32 i;
        if (n > h.s3_n - h.s3_pos) n = h.s3_n - h.s3_pos;
        for (i = 0; i < n; i++) d[i] = s3b[h.s3_pos + i];
        h.s3_pos += n;
        return n;
    }
    if (h.tls) return tls_read(h.tls, d, n);
    if (n > h.rx_total) n = h.rx_total;
    if (n > 0xF000U) n = 0xF000U;
    if (n == 0U) return 0;
    pbuf_copy_partial(h.rxq, d, (u16)n, 0);
    h.rxq = pbuf_free_header(h.rxq, (u16)n);
    h.rx_total -= n;
    if (h.pcb) tcp_recved(h.pcb, (u16)n);
    return n;
}

static const char *h_campo(const char *clave)         /* cabecera (en minusculas en 'clave') o 0 */
{
    const char *p = W->hdr;
    u32 kl = slen(clave), i;
    while (*p) {
        while (*p && *p != '\n') p++;
        if (!*p) break;
        p++;
        for (i = 0; i < kl; i++) { char c = p[i]; if (c >= 'A' && c <= 'Z') c += 32; if (c != clave[i]) break; }
        if (i == kl) { p += kl; while (*p == ' ') p++; return p; }
    }
    return 0;
}

static void h_cabecera(void)
{
    u8 b;
    while (h.st == H_CABECERA && h_disp()) {
        h_toma(&b, 1);
        if (h.hlen >= sizeof W->hdr - 1U) { h_fallo("cabecera larga"); return; }
        W->hdr[h.hlen++] = (char)b;
        if (h.hlen >= 4U && W->hdr[h.hlen - 4U] == '\r' && W->hdr[h.hlen - 3U] == '\n' && W->hdr[h.hlen - 2U] == '\r' && b == '\n') {
            const char *v;
            u32 code = 0, i;
            W->hdr[h.hlen] = 0;
            for (i = 0; W->hdr[i] && W->hdr[i] != ' '; i++) { }
            for (i++; W->hdr[i] >= '0' && W->hdr[i] <= '9'; i++) code = code * 10U + (u32)(W->hdr[i] - '0');
            if (code >= 300U && code < 400U && (v = h_campo("location:")) != 0 && h.saltos < 4U) {
                static char nueva[2048];
                u32 k = 0;
                while (v[k] && v[k] != '\r' && v[k] != '\n' && k + 1U < sizeof nueva) { nueva[k] = v[k]; k++; }
                nueva[k] = 0;
                if (v[k] && v[k] != '\r' && v[k] != '\n') { h_fallo("redireccion larga"); return; }
                h_soltar();
                h.saltos++;
                if (nueva[0] == '/') scpy(h.ruta, nueva, sizeof h.ruta);
                else if (!h_url(nueva)) { h_fallo("redireccion"); return; }
                if (h.tls_on && !h.s3 && !tls_available()) { h_fallo("sin TLS"); return; }
                log_str("ota: redireccion a "); log_str(h.host); log_str("\n");
                h_arranca();
                return;
            }
            if (code != 200U) { log_str("ota: HTTP "); log_dec(code); log_str("\n"); h_fallo(code == 404U ? "no esta (404)" : "HTTP"); return; }
            if ((v = h_campo("transfer-encoding:")) != 0 && pfx(v, "chunked")) { h_fallo("chunked"); return; }
            if ((v = h_campo("content-length:")) != 0) h.clen = a_num(v);
            if (h.clen != 0xFFFFFFFFU && h.clen > h.cap) { h_fallo("demasiado grande"); return; }
            h.st = H_CUERPO; h.t_ult = sys_now();
        }
    }
}

static void h_cuerpo(void)
{
    u32 hecho = 0;
    while (h.st == H_CUERPO && hecho < 0x40000U) {    /* 256 KB por vuelta como mucho: el bucle sigue vivo */
        u32 a = h_disp(), k, lim = (h.clen != 0xFFFFFFFFU ? h.clen : h.cap) - h.got;
        if (lim == 0U) break;
        if (a == 0U) break;
        k = a < lim ? a : lim;
        if (k > 0x4000U) k = 0x4000U;
        k = h_toma(h.dst + h.got, k);
        if (h.con_sha) mbedtls_sha256_update(&W->sha, h.dst + h.got, k);
        h.got += k; hecho += k; h.t_ult = sys_now();
    }
    if (h.st != H_CUERPO) return;
    if ((h.clen != 0xFFFFFFFFU && h.got >= h.clen) || (h.clen == 0xFFFFFFFFU && h.got >= h.cap)) { h_soltar(); h.st = H_HECHO; return; }
    if (h.cerrado && h_disp() == 0U && (h.s3 || !h.tls || tls_closed(h.tls))) {
        if (h.clen == 0xFFFFFFFFU) { h_soltar(); h.st = H_HECHO; }   /* sin Content-Length: hasta que cierre */
        else h_fallo("cortada");
    }
}

/* por la S3: las respuestas del DNS y del TCP_OPEN (el ESP tarda: radio dormida, handshake TLS) */
static void h_espera_s3(void)
{
    int r = s3_resp();
    if (r == 0) return;
    if (r < 0) { h_fallo("sin respuesta"); return; }
    if (h.st == H_DNS) {
        if (s3r.err != 0U || s3r.n != 4U) { h_fallo("DNS"); return; }
        IP4_ADDR(ip_2_ip4(&h.ip), s3r.d[0], s3r.d[1], s3r.d[2], s3r.d[3]);
        h_conecta_s3();
        return;
    }
    if (s3r.err == 0U && s3r.n >= 1U) {              /* conectada (con TLS: el handshake ya esta hecho) */
        h.s3c = s3r.d[0];
        log_str("ota: S3 conectada a "); log_str(h.host);
        log_str(h.tls_on ? (h.s3_valida ? " (TLS, certificado validado)\n" : " (TLS sin validar)\n") : "\n");
        h.st = H_PIDE; h.t_ult = sys_now();
        h_pide();
        return;
    }
    if (h.tls_on && h.s3_valida && s3r.err == 11U) { /* UE_NO_CONN: sin raices en el ESP (o TLS roto): sin validar */
        log_str("ota: la S3 no valida el certificado de "); log_str(h.host); log_str(": otra vez sin validar\n");
        h.s3_valida = 0;
        h_conecta_s3();
        return;
    }
    log_str("ota: TCP_OPEN de la S3, error "); log_dec(s3r.err); log_str("\n");
    h_fallo(s3r.err == 2U ? "sin WiFi" : "conexion rechazada");
}

/* por la S3: un TCP_RCV cuando ya se ha usado lo anterior; si no hay nada, otro a los 2 ms y, cada 25 vacios, el
 * estado (el ESP no avisa del cierre: la conexion cerrada y sin bytes por leer = fin) */
static void h_recibe_s3(void)
{
    int n;
    if (h.s3_pos < h.s3_n || h.cerrado || (s32)(sys_now() - h.t_rcv) < 0) return;
    h.s3_n = h.s3_pos = 0;
    n = s3_tcp_lee(h.s3c, s3b, sizeof s3b);
    if (n < 0) { h.cerrado = 1; return; }
    if (n > 0) { h.s3_n = (u32)n; h.vacios = 0; return; }
    h.t_rcv = sys_now() + 2U;
    if (++h.vacios >= 25U) { h.vacios = 0; if (s3_tcp_estado(h.s3c) == 0) h.cerrado = 1; }
}

static void h_poll(void)
{
    int s;
    u32 quieto = sys_now() - h.t_ult;
    switch (h.st) {
        case H_S3:
            if (s3_lista()) h_arranca();
            else if (!s3_tomada()) h_fallo("sin S3");
            break;
        case H_DNS: case H_CONECTA:
            if (h.s3) h_espera_s3();
            else if ((s32)quieto > 10000) h_fallo("sin respuesta");
            break;
        case H_TLS:
            s = tls_poll(h.tls);
            if (s < 0) h_fallo("TLS");
            else if (s == 1) { h.st = H_PIDE; h_pide(); }
            break;
        case H_PIDE:
            h_pide();
            break;
        case H_CABECERA: case H_CUERPO:
            if (h.s3) h_recibe_s3();
            else if (h.tls) (void)tls_poll(h.tls);
            if (h.st == H_CABECERA) h_cabecera();
            if (h.st == H_CUERPO) h_cuerpo();
            if (h.st == H_CABECERA && h.cerrado && h_disp() == 0U) h_fallo("cerrada sin respuesta");
            else if ((h.st == H_CABECERA || h.st == H_CUERPO) && (s32)(sys_now() - h.t_ult) > 20000) h_fallo("20 s sin datos");
            break;
        default: break;
    }
}

/* ---- busqueda del servidor: difusion UDP (servidor de desarrollo en la red local) o OTA_URL ------------------------ */
static struct udp_pcb *disc;
static u8 disc_n;

static const char disc_q[] = "MSXIMUS-OTA? " OTA_PLACA;

static int disc_texto(char *t, const u8 ip[4])          /* "MSXIMUS-OTA <url>" de un PC: 1 si vale */
{
    char *u = t + 12, *e = u, *q;
    if (st != O_BUSCA || !pfx(t, "MSXIMUS-OTA ")) return 0;
    while (*e && *e != ' ' && *e != '\r' && *e != '\n') e++;
    *e = 0;
    if (!(pfx(u, "http://") || pfx(u, "https://")) || e[-1] != '/') return 0;
    scpy(url_base, u, sizeof url_base);
    q = servidor;
    q = put_u(q, ip[0]); *q++ = '.'; q = put_u(q, ip[1]); *q++ = '.'; q = put_u(q, ip[2]); *q++ = '.'; q = put_u(q, ip[3]);
    put_s(q, " (PC)");
    log_str("ota: servidor de desarrollo "); log_str(url_base); log_str("\n");
    return 1;
}

static void disc_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
    char t[180];
    u8 ip[4];
    u16 n;
    (void)arg; (void)pcb; (void)port;
    n = pbuf_copy_partial(p, t, sizeof t - 1U, 0);
    pbuf_free(p);
    t[n] = 0;
    ip[0] = ip4_addr1(ip_2_ip4(addr)); ip[1] = ip4_addr2(ip_2_ip4(addr)); ip[2] = ip4_addr3(ip_2_ip4(addr)); ip[3] = ip4_addr4(ip_2_ip4(addr));
    (void)disc_texto(t, ip);
}

static void disc_manda(void)
{
    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, sizeof disc_q - 1U, PBUF_RAM);
    u32 i;
    if (p == NULL) return;
    for (i = 0; i < sizeof disc_q - 1U; i++) ((u8 *)p->payload)[i] = (u8)disc_q[i];
    (void)udp_sendto(disc, p, IP_ADDR_BROADCAST, OTA_UDP);
    pbuf_free(p);
}

static void disc_cierra(void) { if (disc) { udp_remove(disc); disc = NULL; } }

/* ---- manifiesto ----------------------------------------------------------------------------------------------------- */
static int firma_ok(const u8 *m, u32 n, const u8 *sig)
{
    mbedtls_ecp_group g;
    mbedtls_ecp_point q;
    mbedtls_mpi r, s;
    u8 hash[32];
    int e;
    mbedtls_sha256(m, n, hash, 0);
    mbedtls_ecp_group_init(&g); mbedtls_ecp_point_init(&q); mbedtls_mpi_init(&r); mbedtls_mpi_init(&s);
    e = mbedtls_ecp_group_load(&g, MBEDTLS_ECP_DP_SECP256R1);
    if (!e) e = mbedtls_ecp_point_read_binary(&g, &q, ota_clave_publica, sizeof ota_clave_publica);
    if (!e) e = mbedtls_mpi_read_binary(&r, sig, 32);
    if (!e) e = mbedtls_mpi_read_binary(&s, sig + 32, 32);
    if (!e) e = mbedtls_ecdsa_verify(&g, hash, sizeof hash, &q, &r, &s);
    mbedtls_mpi_free(&s); mbedtls_mpi_free(&r); mbedtls_ecp_point_free(&q); mbedtls_ecp_group_free(&g);
    return e == 0;
}

static int nombre_car(char c) { return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == '_' || c == '-'; }

/* "<ID> <version> <fichero> <tamano> <sha256> <tamano del .bin> <serie>" de una linea perfil=; una linea mal escrita se salta
 * (con aviso en el log): no puede dejar sin actualizar el sistema. La serie tiene que ser la del manifiesto. */
static void perfil_nuevo(const char *s)
{
    perf_t *q = &mf.perf[mf.np];
    u32 n = 0, i;
    if (mf.np >= MAX_PERF) return;
    while (n < 8U && ((*s >= 'A' && *s <= 'Z') || (*s >= '0' && *s <= '9') || *s == '_' || *s == '-')) q->p.id[n++] = *s++;
    if (!n || *s++ != ' ') goto mal;
    q->p.id[n] = 0;
    for (n = 0; n < 15U && nombre_car(*s); ) q->p.version[n++] = *s++;
    if (!n || *s++ != ' ') goto mal;
    q->p.version[n] = 0;
    for (n = 0; n < sizeof q->fichero - 1U && nombre_car(*s); ) q->fichero[n++] = *s++;
    if (!n || *s++ != ' ') goto mal;
    q->fichero[n] = 0;
    if (*s < '0' || *s > '9') goto mal;
    q->p.tamano = a_num(s);
    while (*s >= '0' && *s <= '9') s++;
    if (*s++ != ' ' || !hex_a_bytes(s, q->sha, 32)) goto mal;
    s += 64;
    if (*s++ != ' ' || *s < '0' || *s > '9') goto mal;
    q->p.tam_bin = a_num(s);
    while (*s >= '0' && *s <= '9') s++;
    if (*s++ != ' ' || *s < '0' || *s > '9') goto mal;
    q->p.serie = a_num(s);
    while (*s >= '0' && *s <= '9') s++;
    if (*s && *s != '\n' && *s != '\r') goto mal;
    if (q->p.tamano < 1024U || q->p.tamano > PERF_MAX_MXP || q->p.tam_bin < 4096U || q->p.tam_bin > PF_MAX || (q->p.tam_bin & 3U)) goto mal;
    if (q->p.serie != mf.serie) { log_str("ota: perfil "); log_str(q->p.id); log_str(": su serie no es la del manifiesto, se salta\n"); return; }
    for (i = 0; i < mf.np; i++) if (igual(mf.perf[i].p.id, q->p.id)) { log_str("ota: perfil repetido, se salta\n"); return; }
    mf.np++;
    return;
mal:
    log_str("ota: linea perfil= mal escrita, se salta\n");
}

static const char *manif_leer(u32 n)                  /* 0 = bien; si no, el motivo */
{
    char *t = W->manif, v[160];
    u32 i, fin = 0;
    u8 sig[64];
    t[n] = 0;
    if (!pfx(t, "MSXIMUS-OTA 1\n")) return "manifiesto raro";
    for (i = 0; i + 7U < n; i++) if (t[i] == '\n' && pfx(t + i + 1U, "firma=")) { fin = i + 1U; break; }
    if (!fin || fin + 6U + 128U > n || !hex_a_bytes(t + fin + 6U, sig, 64)) return "sin firma";
    if (!firma_ok((const u8 *)t, fin, sig)) return "FIRMA MALA";
    if (!campo(t, fin, "placa", v, sizeof v) || !pfx(v, OTA_PLACA) || v[slen(OTA_PLACA)]) return "es de otra placa";
    if (!campo(t, fin, "version", mf.version, sizeof mf.version) || !campo(t, fin, "serie", v, sizeof v)) return "sin version";
    mf.serie = a_num(v);
    if (!campo(t, fin, "fecha", mf.fecha, sizeof mf.fecha)) mf.fecha[0] = 0;
    mf.beta = (u8)(campo(t, fin, "canal", v, sizeof v) && pfx(v, "beta"));
    mf.nn = 0; mf.nimg = 0; mf.sel = 0; mf.np = 0;
    for (i = 0; i < fin; ) {                         /* notas= (hasta 3) e imagen=<variante> <fichero> <tamano> <sha256> */
        const char *l = t + i;
        u32 k = 0;
        if (pfx(l, "notas=") && mf.nn < 3U) {
            l += 6;
            while (l[k] && l[k] != '\n' && k < 63U) { mf.notas[mf.nn][k] = l[k]; k++; }
            mf.notas[mf.nn++][k] = 0;
        } else if (pfx(l, "imagen=") && mf.nimg < 4U && (pfx(l + 7, "nextor214 ") || pfx(l + 7, "nextor3 ") ||
                                                          pfx(l + 7, "nextor214-en ") || pfx(l + 7, "nextor3-en "))) {
            const char *p = l + 7;
            u32 j = 0;
            while (*p != ' ') { mf.img[mf.nimg].var[j++] = *p++; }
            mf.img[mf.nimg].var[j] = 0;
            p++;
            while (*p && *p != ' ' && *p != '\n' && k + 1U < sizeof mf.img[0].fichero) {
                char c = *p++;
                if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == '_' || c == '-')) return "nombre raro";
                mf.img[mf.nimg].fichero[k++] = c;
            }
            mf.img[mf.nimg].fichero[k] = 0;
            if (*p++ != ' ') return "imagen mal escrita";
            mf.img[mf.nimg].tamano = a_num(p);
            while (*p >= '0' && *p <= '9') p++;
            if (*p++ != ' ' || !hex_a_bytes(p, mf.img[mf.nimg].sha, 32)) return "imagen mal escrita";
            if (mf.img[mf.nimg].tamano < 0x1000U || mf.img[mf.nimg].tamano > IMG_MAX) return "tamaño imposible";
            if (pfx(mf.img[mf.nimg].var, var_act) && !mf.img[mf.nimg].var[slen(var_act)]) mf.sel = mf.nimg;   /* la de la placa */
            mf.nimg++;
        } else if (pfx(l, "perfil=")) perfil_nuevo(l + 7);
        while (i < fin && t[i] != '\n') i++;
        i++;
    }
    if (!mf.nimg) return "sin imagen para esta placa";
    return 0;
}

static int igual(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }

/* variantes: "nextor214" / "nextor3" (castellano, los nombres de siempre) y "nextor214-en" / "nextor3-en" (ingles) */
static int var_n3(const char *v) { return pfx(v, "nextor3"); }
static int var_en(const char *v) { u32 n = slen(v); return n > 3U && igual(v + n - 3, "-en"); }

/* tras leer el manifiesto o cambiar de variante: que se puede hacer con la imagen elegida */
static void decide(void)
{
    if (reg_ok && !en_b && reg_serie == mf.serie && igual(reg_var, IMGSEL.var)) st = O_LISTA;   /* grabada, sin arrancar */
    else if (mf.serie > serie_act || !igual(IMGSEL.var, var_act) || mf.beta != beta_act) st = O_HAY;   /* mas nueva, otro Nextor u otro canal */
    else st = O_AL_DIA;
    sucio = 1;
}

/* ---- la imagen bajada ----------------------------------------------------------------------------------------------- */
static const char *imagen_ok(void)
{
    u8 hash[32];
    u32 i, a, sum = 0;
    mbedtls_sha256_finish(&W->sha, hash);
    mbedtls_sha256_free(&W->sha);
    for (i = 0; i < 32U; i++) if (hash[i] != IMGSEL.sha[i]) return "SHA-256 distinto";
    if (rd32(IMG + 0x20) != 0xAA995566U || rd32(IMG + 0x24) != 0x584C4E58U) return "no es un BOOT.bin";
    for (a = 0x20U; a <= 0x44U; a += 4U) sum += rd32(IMG + a);
    if (~sum != rd32(IMG + 0x48)) return "cabecera mala";
    /* su particion ota_info: "MOTI1\n" seguido de "version=" (asi, en dos trozos: este programa lleva la cadena
     * "MOTI1\n" suelta y su .elf va antes en el BOOT.bin); la serie tiene que ser la del manifiesto */
    for (i = 0; i + 14U <= len; i++) {               /* es la ULTIMA particion: acaba justo al final de la imagen */
        char v[16];
        if (IMG[i] != 'M' || !pfx((const char *)IMG + i, "MOTI1\n") || !pfx((const char *)IMG + i + 6, "version=")) continue;
        if (campo((const char *)IMG + i, len - i < 256U ? len - i : 256U, "serie", v, sizeof v) && a_num(v) == mf.serie) return 0;
        return "ota_info no cuadra";
    }
    return "sin particion ota_info";
}

static void reg_nuevo(u8 *r)
{
    u32 i;
    for (i = 0; i < 256U; i++) r[i] = 0xFFU;
    r[0] = 'M'; r[1] = 'O'; r[2] = 'T'; r[3] = 'A'; r[4] = 1U; r[5] = 0; r[6] = 0; r[7] = 0;
    wr32(r + 0x08, mf.serie); wr32(r + 0x0C, len); wr32(r + 0x10, SLOT_B);
    for (i = 0; i < 32U; i++) r[0x14 + i] = IMGSEL.sha[i];
    for (i = 0; i < 16U; i++) { r[0x34 + i] = 0; r[0x44 + i] = 0; }
    for (i = 0; i < 15U && mf.version[i]; i++) r[0x34 + i] = (u8)mf.version[i];
    for (i = 0; i < 15U && IMGSEL.var[i]; i++) r[0x44 + i] = (u8)IMGSEL.var[i];   /* la variante que se instala */
    wr32(r + 0x54, crc32(r, 0x54U));
}

/* grabacion de la B, paso a paso: 0 borra el registro, 1 borra bloques, 2 programa, 3 relee, 4 registro.
 * Con a_sd (la placa arrancada desde SD, tecla A) graba la ranura A en 0 con el BOOT.bin de la SD: mismos pasos, sin el SHA-256 del
 * manifiesto (la relectura se compara byte a byte con lo leido de la SD) y sin registro nuevo (queda borrado: no hay B). Si se va la luz
 * a mitad la A queda mal, pero la SD sigue arrancando: se repite. */
static void graba_poll(void)
{
    u32 t = sys_now();
    u32 base = a_sd ? 0U : SLOT_B;
    switch (paso) {
        case 0:
            qspi_erase4k_start(REG_ADDR);            /* desde aqui un apagon deja la A */
            reg_ok = 0; reg_conf = 0;
            paso = 1; pos = 0; t_paso = t;
            break;
        case 1:                                      /* bloques de 64 KB */
            if (qspi_busy()) break;
            if (pos >= ((len + 0xFFFFU) & ~0xFFFFU)) { paso = 2; pos = 0; log_str("ota: borrada en "); log_dec(t - t_paso); log_str(" ms\n"); t_paso = t; break; }
            qspi_erase64k_start(base + pos);
            pos += 0x10000U;
            sucio = 1;
            break;
        case 2: {                                    /* paginas de 256 B: 16 por vuelta o 3 ms, lo que llegue antes */
            u32 pags = 0;
            do {
                u32 n;
                if (qspi_busy()) continue;
                if (pos >= len) { paso = 3; pos = 0; mbedtls_sha256_init(&W->sha); mbedtls_sha256_starts(&W->sha, 0); log_str("ota: grabada en "); log_dec(t - t_paso); log_str(" ms\n"); break; }
                n = len - pos; if (n > 256U) n = 256U;
                qspi_prog_start(base + pos, IMG + pos, n);
                pos += n;
                pags++;
            } while (pags < 16U && sys_now() - t < 3U);
            }
            sucio = 1;
            break;
        case 3: {                                    /* relectura: igual byte a byte y el SHA-256 del manifiesto */
            u32 n = len - pos, i;
            if (n > sizeof W->rb) n = sizeof W->rb;
            qspi_read(base + pos, W->rb, n);
            for (i = 0; i < n; i++) if (W->rb[i] != IMG[pos + i]) break;
            if (i < n) { log_str("ota: relectura distinta en "); log_hex(base + pos + i); log_str("\n"); set_msg(T("Error al grabar la QSPI", "Flash write error")); st = O_ERROR; a_sd = 0; return; }
            if (!a_sd) mbedtls_sha256_update(&W->sha, W->rb, n);
            pos += n;
            if (pos >= len) {
                u8 hash[32];
                if (a_sd) { mbedtls_sha256_free(&W->sha); paso = 4; }          /* A: ya se ha comparado byte a byte con lo leido de la SD */
                else {
                    mbedtls_sha256_finish(&W->sha, hash); mbedtls_sha256_free(&W->sha);
                    for (i = 0; i < 32U; i++) if (hash[i] != IMGSEL.sha[i]) { set_msg(T("Error al grabar la QSPI", "Flash write error")); st = O_ERROR; return; }
                    paso = 4;
                }
            }
            sucio = 1;
            break;
        }
        case 4: {
            u8 *r = W->reg;
            if (a_sd) {                              /* la A grabada: el registro ya esta borrado (paso 0), asi que arranca la A */
                a_sd = 0;
                reg_leer();
                log_str("ota: "); log_str(a_ver); log_str(" grabada en la ranura A desde la SD\n");
                st = O_SD_HECHO; msg[0] = 0; sucio = 1;
                break;
            }
            reg_nuevo(r);
            qspi_prog_start(REG_ADDR, r, 256);
            qspi_wait();
            reg_leer();
            if (!reg_ok || reg_serie != mf.serie) { set_msg(T("Error al grabar la QSPI", "Flash write error")); st = O_ERROR; return; }
            log_str("ota: "); log_str(mf.version); log_str(" instalada en la ranura B\n");
            st = O_LISTA; msg[0] = 0; sucio = 1;
            break;
        }
    }
}

/* ---- la maquina de la pantalla ------------------------------------------------------------------------------------- */
/* lo que ve el usuario de un fallo (el motivo tecnico va al log del ARM) */
static const char *error_usuario(const char *e)
{
    static const char *const red[] = { "DNS", "conexion rechazada", "sin memoria TLS", "sin pcb", "tcp_connect", "sin TLS",
                                       "TLS", "sin respuesta", "cerrada sin respuesta", "20 s sin datos", "cortada", "GET", "sin S3", 0 };
    u32 i;
    log_str("ota: fallo: "); log_str(e); log_str("\n");
    for (i = 0; red[i]; i++) if (igual(e, red[i])) return T("Sin conexión al servidor", "Can't reach the server");
    if (igual(e, "sin WiFi")) return T("La WiFi no conecta", "WiFi not connected");
    if (pfx(e, "no esta")) return T("La actualización no está", "Update not found");
    if (igual(e, "FIRMA MALA")) return T("Firma no válida", "Bad signature");
    if (igual(e, "es de otra placa") || igual(e, "sin imagen para esta placa")) return T("No es para esta placa", "Not for this board");
    if (igual(e, "SHA-256 distinto") || igual(e, "tamano distinto") || igual(e, "no es un BOOT.bin") || igual(e, "cabecera mala") ||
        igual(e, "ota_info no cuadra") || igual(e, "sin particion ota_info")) return T("Descarga dañada", "Corrupted download");
    if (igual(e, "perfil no valido") || igual(e, "perfil no cuadra")) return T("Perfil no válido", "Invalid profile");
    if (igual(e, "manifiesto raro") || igual(e, "sin firma") || igual(e, "nombre raro") || igual(e, "imagen mal escrita") ||
        igual(e, "tamaño imposible") || igual(e, "sin version")) return T("Datos de versión no válidos", "Invalid update data");
    return T("Respuesta no válida", "Invalid server reply");
}

static void falla(const char *tecnico) { set_msg(error_usuario(tecnico)); st = O_ERROR; }

/* sin cable, por la S3: 0 esperar los 300 ms, 1 NET_STATE (esta?), 2 DNS de msx.barcelona (despierta su radio),
 * 3 difusion UDP al servidor del PC (a 255.255.255.255 y a la de su red) y 1,5 s de escucha (la WiFi con ahorro de
 * energia tarda en entregar la respuesta); luego el manifiesto (del PC o de OTA_URL) */
static u8  s3_fase, s3_udp, s3_estado;
static u32 s3_t, s3_t_lee;
static void pide_manifiesto(void);

static void difunde_s3(void)
{
    static const u8 bcast[4] = { 255, 255, 255, 255 };
    u8 red[4];
    (void)s3_udp_manda(s3_udp, bcast, OTA_UDP, (const u8 *)disc_q, sizeof disc_q - 1U);
    if (s3_difusion(red)) (void)s3_udp_manda(s3_udp, red, OTA_UDP, (const u8 *)disc_q, sizeof disc_q - 1U);
}

static void busca_s3(void)
{
    int r;
    switch (s3_fase) {
        case 0:
            if (!s3_lista()) return;
            (void)s3_pide(3, 0, 0, 1500U);
            s3_fase = 1;
            return;
        case 1:
            if ((r = s3_resp()) == 0) return;
            if (r < 0) { s3_suelta(); set_msg(T("Sin red: cable o WiFi", "No network: cable or WiFi")); st = O_ERROR; return; }
            s3_estado = s3r.n ? s3r.d[0] : 0U;      /* 2 conectada, 1 conectando, 0 radio parada o sin red */
            log_str("ota: sin cable, por la WiFi de la S3 (estado "); log_dec(s3_estado); log_str(")\n");
            (void)s3_pide(6, (const u8 *)"msx.barcelona", 13, 20000U);
            s3_fase = 2;
            return;
        case 2:
            if ((r = s3_resp()) == 0) return;
            if (r < 0 || s3r.err != 0U) {
                log_str("ota: la S3 no resuelve msx.barcelona\n");
                if (s3_estado != 2U) { s3_suelta(); set_msg(T("La WiFi no conecta", "WiFi not connected")); st = O_ERROR; return; }
            }
            s3_ip_lee();
            {
                u8 a[4], b[4];
                if (s3_ip(a) && s3_difusion(b)) {
                    log_str("ota: S3 en "); log_dec(a[0]); log_str("."); log_dec(a[1]); log_str("."); log_dec(a[2]); log_str("."); log_dec(a[3]);
                    log_str(", difusion tambien a "); log_dec(b[0]); log_str("."); log_dec(b[1]); log_str("."); log_dec(b[2]); log_str("."); log_dec(b[3]); log_str("\n");
                }
            }
            s3_udp = s3_udp_abre();
            if (s3_udp) difunde_s3();
            disc_n = 1; s3_t = s3_t_lee = sys_now();
            s3_fase = 3;
            return;
        default:
            if (s3_udp && (s32)(sys_now() - s3_t_lee) >= 25) {
                char t[180];
                u8 ip[4];
                int n = s3_udp_lee(s3_udp, (u8 *)t, sizeof t - 1U, ip);
                s3_t_lee = sys_now();
                if (n > 0) { t[n] = 0; if (disc_texto(t, ip)) { s3_udp_cierra(s3_udp); s3_udp = 0; pide_manifiesto(); return; } }
                if (disc_n < 2U && sys_now() - s3_t > 500U) { difunde_s3(); disc_n++; }
            }
            if (sys_now() - s3_t > 1500U) {
                if (s3_udp) s3_udp_cierra(s3_udp);
                s3_udp = 0;
                log_str("ota: ningun PC contesta por la WiFi\n");
                pide_manifiesto();
            }
            return;
    }
}

static void buscar(void)
{
    scpy(url_base, beta_pide ? OTA_URL_BETA : OTA_URL, sizeof url_base);
    scpy(servidor, beta_pide ? "msx.barcelona · beta" : "msx.barcelona", sizeof servidor);
    disc_cierra();
    via_s3 = (u8)!esp_net_ok();
    if (via_s3) {                                    /* sin cable: la WiFi de la S3 */
        s3_toma(); s3_fase = 0; s3_udp = 0;
        st = O_BUSCA; t_paso = sys_now(); msg[0] = 0; sucio = 1;
        return;
    }
    disc = udp_new();
    if (disc && udp_bind(disc, IP_ADDR_ANY, 0) == ERR_OK) { udp_recv(disc, disc_recv, NULL); disc_manda(); }
    disc_n = 1;
    st = O_BUSCA; t_paso = sys_now(); msg[0] = 0; sucio = 1;
}

static void pide_manifiesto(void)
{
    char u[512], *p;
    disc_cierra();
    p = put_s(u, url_base); put_s(p, "manifiesto.txt");
    st = O_MANIF; sucio = 1;
    if (!h_get(u, (u8 *)W->manif, sizeof W->manif - 1U, 0)) falla(h.err);
}

static void instalar(void)
{
    char u[512], *p;
    p = put_s(u, url_base); put_s(p, IMGSEL.fichero);
    len = IMGSEL.tamano;
    via_s3 = (u8)!esp_net_ok();                      /* sin cable: otra vez la S3 (se solto al acabar la busqueda) */
    if (via_s3) s3_toma();
    mbedtls_sha256_init(&W->sha);
    mbedtls_sha256_starts(&W->sha, 0);
    st = O_BAJA; t_paso = sys_now(); sucio = 1;
    log_str("ota: bajando "); log_str(IMGSEL.fichero); log_str("\n");
    if (!h_get(u, IMG, len, 1)) falla(h.err);
}

/* ---- perfiles del manifiesto: estado frente a la tarjeta, bajar e instalar ------------------------------------------------ */
static int perfiles_listo(void) { return st == O_AL_DIA || st == O_HAY || st == O_LISTA; }   /* hay un manifiesto leido y firmado */

int ota_perfil_estado(int i)
{
    const mxpf_info_t *in = mxpf_estado();
    const perf_t *q;
    int k;
    if (i < 0 || i >= (int)mf.np || in->estado != MXS_OK) return OPS_NO;
    q = &mf.perf[i];
    for (k = 0; k < in->n; k++) {
        const mxpf_perfil *e = &in->p[k];
        if (!igual(e->id, q->p.id)) continue;
        if (e->serie != q->p.serie) return OPS_OTRA_SERIE;
        if (!igual(e->version, q->p.version) || e->tam_bin != q->p.tam_bin) return OPS_OTRA_VERSION;
        return OPS_AL_DIA;
    }
    return OPS_NO;
}

/* los perfiles del manifiesto son de ESTA serie (mf.serie): solo se bajan si es la del sistema que corre (o no se sabe cual: arranque por
 * JTAG) o la del BOOT.bin que ya esta grabado en la B. Si no, reemplazarian el perfil bueno de la tarjeta (mismo id) por uno que el
 * sistema de ahora no carga (E_SERIE): hay que instalar antes la version nueva. */
int ota_perfiles_descargables(void)
{
    if (!perfiles_listo()) return 0;
    return serie_act == 0U || mf.serie == serie_act || (reg_ok && reg_serie == mf.serie);
}

int ota_perfiles_n(void) { return perfiles_listo() ? mf.np : 0; }
const ota_perfil_t *ota_perfil(int i) { return (i >= 0 && i < ota_perfiles_n()) ? &mf.perf[i].p : 0; }

int ota_perfiles_viejos(void)                         /* ya en la tarjeta y de otra serie o version que la del servidor */
{
    int i, n = 0, s;
    if (!perfiles_listo()) return 0;
    for (i = 0; i < (int)mf.np; i++) { s = ota_perfil_estado(i); if (s == OPS_OTRA_SERIE || s == OPS_OTRA_VERSION) n++; }
    return n;
}

int ota_perfil_en_curso(void) { return pst != 0; }

void ota_perfil_progreso(u32 *hecho, u32 *total, int *indice)
{
    *hecho = pst == 1 ? h.got : plen; *total = plen; *indice = pcur;
}

/* el ultimo resultado: 0 nada, 1 instalado(s) (n_ok, id del ultimo), 2 error de mxpf (codigo MXPF_E_*), 3 error de red o de contenido (texto) */
int ota_perfil_resultado(int *codigo, int *n_ok, const char **id_o_texto)
{
    *codigo = pcod; *n_ok = pn_ok;
    *id_o_texto = pres == 1 ? pid : pmsg;
    return pres;
}
void ota_perfil_olvida(void) { if (!pst) { pres = 0; pmsg[0] = 0; pn_ok = 0; sucio = 1; } }

static void perfil_fin(u8 res, int cod, const char *texto)
{
    pst = 0; pcola = 0; pres = res; pcod = cod;
    if (texto) scpy(pmsg, texto, sizeof pmsg);
    sucio = 1;
}

static void perfil_inicia(u32 i)
{
    char u[512], *p;
    p = put_s(u, url_base); put_s(p, mf.perf[i].fichero);
    pcur = (u8)i; plen = mf.perf[i].p.tamano; pt0 = sys_now();
    if (pnuevo) {                                     /* el camino (cable o S3) se decide al empezar la cola: si el cable coge IP a mitad, la S3 tomada se soltaria nunca */
        via_s3 = (u8)!esp_net_ok();                   /* sin cable: la S3 (se suelta en ota_poll al acabar) */
        if (via_s3) s3_toma();
        pnuevo = 0;
    }
    mbedtls_sha256_init(&W->sha);
    mbedtls_sha256_starts(&W->sha, 0);
    pst = 1; pres = 0; sucio = 1;
    log_str("ota: bajando el perfil "); log_str(mf.perf[i].p.id); log_str(" ("); log_str(mf.perf[i].fichero); log_str(")\n");
    if (!h_get(u, IMG, plen, 1)) perfil_fin(3, 0, error_usuario(h.err));
}

static void perfil_siguiente(void)
{
    u32 k;
    for (k = 0; k < mf.np && !(pcola & (1U << k)); k++) { }
    if (k >= mf.np) { perfil_fin(pn_ok ? 1 : 0, 0, 0); return; }
    pcola &= (u8)~(1U << k);
    perfil_inicia(k);
}

/* la cabecera del .mxp bajado tiene que decir lo mismo que la linea del manifiesto (que es lo firmado) */
static const char *perfil_cabecera_ok(const perf_t *q)
{
    const u8 *c = IMG;
    u32 i;
    if (c[0] != 'M' || c[1] != 'X' || c[2] != 'P' || c[3] != '1' || rd32(c + 4) != 1U || rd32(c + 8) != 512U || rd32(c + 12) != crc32(c + 16, 80U))
        return "perfil no valido";
    for (i = 0; i < 8U; i++) if (c[16 + i] != (u8)(i < slen(q->p.id) ? q->p.id[i] : 0)) return "perfil no cuadra";
    for (i = 0; i < 16U; i++) if (c[28 + i] != (u8)(i < slen(q->p.version) ? q->p.version[i] : 0)) return "perfil no cuadra";
    if (rd32(c + 24) != q->p.serie || rd32(c + 56) != q->p.tam_bin || rd32(c + 52) + 512U > plen) return "perfil no cuadra";
    return 0;
}

static void perfil_bajado(void)                       /* H_HECHO: comprobar, pasar a la zona sin cache e instalar */
{
    perf_t *q = &mf.perf[pcur];
    u8 hash[32];
    const char *e = 0;
    u32 i, n;
    volatile u32 *d = (volatile u32 *)(uintptr_t)PF_DATOS;
    const u32 *s = (const u32 *)(const void *)IMG;
    int r;
    mbedtls_sha256_finish(&W->sha, hash);
    mbedtls_sha256_free(&W->sha);
    if (h.got != plen) e = "tamano distinto";
    else for (i = 0; i < 32U; i++) if (hash[i] != q->sha[i]) { e = "SHA-256 distinto"; break; }
    if (!e) e = perfil_cabecera_ok(q);
    if (e) { perfil_fin(3, 0, error_usuario(e)); return; }
    log_str("ota: perfil bajado en "); log_dec(sys_now() - pt0); log_str(" ms, SHA bien\n");
    for (n = (plen + 3U) >> 2, i = 0; i < n; i++) d[i] = s[i];   /* la SD hace DMA: el .mxp tiene que estar en la zona sin cache */
    osd_abre_servidor();                                             /* el panel congela el Z80 (con "Ocultar" el MSX seguiria corriendo mientras el bucle esta ocupado ~1 s) y enseña el resultado */
    pst = 2;
    r = mxpf_instala((const u8 *)(uintptr_t)PF_DATOS, plen);
    pst = 1;
    if (r != MXPF_OK) { log_str("ota: perfil no instalado: "); log_str(mxpf_err_es(r)); log_str("\n"); perfil_fin(2, r, 0); return; }
    scpy(pid, q->p.id, sizeof pid);
    pn_ok++;
    log_str("ota: perfil "); log_str(pid); log_str(" instalado\n");
    if (pcola) perfil_siguiente(); else perfil_fin(1, 0, 0);
}

static void pdl_poll(void)
{
    h_poll();
    sucio = 1;
    if (h.st == H_FALLO) perfil_fin(3, 0, error_usuario(h.err));
    else if (h.st == H_HECHO) { h.st = H_LIBRE; perfil_bajado(); }
}

/* i >= 0: ese perfil (aunque este al dia: reinstalar); i < 0: todos los que falten o esten viejos. 0 = no empieza (ota_perfil_resultado dice por que) */
int ota_perfil_baja(int i)
{
    u32 k;
    const mxpf_info_t *in;
    if (!perfiles_listo() || ota_ocupada() || pst) return 0;
    if (!ota_perfiles_descargables()) { perfil_fin(3, 0, T("Instala antes la versión nueva del sistema", "Install the new system version first")); return 0; }
    in = mxpf_monta();
    if (in->estado != MXS_OK) {                       /* sin TF1 o sin particion: se dice antes de bajar nada */
        perfil_fin(2, in->estado == MXS_SIN_PARTICION ? MXPF_E_SINPART : in->estado == MXS_DANADA ? MXPF_E_DIR : MXPF_E_TARJETA, 0);
        return 0;
    }
    if (in->libres == 0) { perfil_fin(2, MXPF_E_LLENO, 0); return 0; }   /* instalar (tambien reemplazar) necesita un hueco libre: antes de bajar 1,3 MB */
    pcola = 0; pn_ok = 0; pnuevo = 1;
    if (i < 0) { for (k = 0; k < mf.np; k++) if (ota_perfil_estado((int)k) != OPS_AL_DIA) pcola |= (u8)(1U << k); }
    else if ((u32)i < mf.np) pcola = (u8)(1U << i);
    if (!pcola) { perfil_fin(0, 0, 0); return 0; }
    perfil_siguiente();
    return pst != 0;
}

/* ---- la ranura A desde la SD (10/11/2026) ----------------------------------------------------------------------------------------
 * Con la placa arrancada desde SD (SW1 en SD) la tecla A de esta pagina lee el BOOT.bin de la TF1 a IMG (bootsd.c), comprueba que es de esta
 * placa y, con una segunda A, lo graba en la ranura A de la QSPI (graba_poll con a_sd): la de fabrica, que hasta ahora solo grababa Vivado por
 * JTAG. Despues: apagar, SW1 en QSPI, y ya funcionan la actualizacion por red a la B, los perfiles y la vuelta a fabrica. */
static const char *a_valida(void)
{
    u32 i, a, sum = 0;
    char v[16];
    if (rd32(IMG + 0x20) != 0xAA995566U || rd32(IMG + 0x24) != 0x584C4E58U) return "no es un BOOT.bin";
    for (a = 0x20U; a <= 0x44U; a += 4U) sum += rd32(IMG + a);
    if (~sum != rd32(IMG + 0x48)) return "cabecera mala";
    for (i = 0; i + 14U <= len; i++) {               /* su ota_info (la ultima particion; "MOTI1\n" suelto tambien lo lleva este programa) */
        u32 n;
        if (IMG[i] != 'M' || !pfx((const char *)IMG + i, "MOTI1\n") || !pfx((const char *)IMG + i + 6, "version=")) continue;
        n = len - i < 256U ? len - i : 256U;
        if (!campo((const char *)IMG + i, n, "placa", v, sizeof v) || !igual(v, OTA_PLACA)) return "es de otra placa";
        if (!campo((const char *)IMG + i, n, "version", a_ver, sizeof a_ver)) return "sin version";
        if (!campo((const char *)IMG + i, n, "variante", a_var, sizeof a_var)) a_var[0] = 0;
        return 0;
    }
    return "sin particion ota_info";
}

static void a_error(int r)                            /* BSD_* -> lo que ve el usuario */
{
    set_msg(r == BSD_SIN_TARJETA ? T("No hay tarjeta en la TF1", "No card in TF1")
          : r == BSD_SIN_FAT32 ? T("La TF1 no es FAT16 ni FAT32", "TF1 is not FAT16/FAT32")
          : r == BSD_SIN_BOOT ? T("No hay BOOT.bin en la TF1", "No BOOT.bin on TF1")
          : r == BSD_TAM ? T("BOOT.bin de tamaño raro", "BOOT.bin size is odd")
          : r == BSD_CADENA ? T("BOOT.bin dañado en la TF1", "BOOT.bin damaged on TF1")
          : T("Error leyendo la TF1", "TF1 read error"));
    log_str("ota: BOOT.bin de la SD: error "); log_dec((u32)r);
    a_dg = r == BSD_SIN_FAT32 && bootsd_diag()[0];
    if (a_dg) { log_str(" ("); log_str(bootsd_diag()); log_str(")"); }
    log_str("\n");
    st = O_ERROR; a_sd = 0;
}

static void a_lee_inicia(void)
{
    u32 tam = 0;
    int r = bootsd_abre(&tam);
    a_armada = 0; a_sd = 0; a_dg = 0; msg[0] = 0;
    if (r != BSD_OK) { a_error(r); return; }
    len = tam; pos = 0; t_paso = sys_now(); a_ver[0] = 0; a_var[0] = 0;
    st = O_SD_LEE; sucio = 1;
    log_str("ota: leyendo BOOT.bin de la SD, "); log_dec(tam); log_str(" bytes\n");
}

static void a_lee_poll(void)                          /* trozos de 32 KB: los que quepan en 3 ms por vuelta */
{
    u32 t = sys_now();
    sucio = 1;
    do {
        u32 n = 0;
        int r = bootsd_sig(IMG + pos, &n);
        if (r != BSD_OK) { a_error(r); return; }
        if (n == 0) { a_error(BSD_CADENA); return; }  /* se acabo el fichero antes de tiempo */
        pos += n;
        if (pos >= len) {
            const char *e = a_valida();
            if (e) {
                log_str("ota: BOOT.bin de la SD no vale: "); log_str(e); log_str("\n");
                set_msg(igual(e, "es de otra placa") ? T("No es para esta placa", "Not for this board") : T("BOOT.bin no válido", "Invalid BOOT.bin"));
                st = O_ERROR;
                return;
            }
            log_str("ota: BOOT.bin de la SD: "); log_str(a_ver); log_str(" "); log_str(a_var); log_str(", leido en "); log_dec(sys_now() - t_paso); log_str(" ms\n");
            st = O_SD_LISTO; msg[0] = 0;
            return;
        }
    } while (sys_now() - t < 3U);
}

void ota_poll(void)
{
    confirmar_poll();
    if (pst == 1) pdl_poll();
    if (st == O_BUSCA || st == O_MANIF) sucio = 1;   /* el icono de "buscando" gira */
    switch (st) {
        case O_BUSCA:
            if (via_s3) { busca_s3(); break; }
            if (url_base[0] && !pfx(url_base, OTA_URL)) { pide_manifiesto(); break; }   /* contesto un PC */
            if (disc_n < 2U && sys_now() - t_paso > 300U) { disc_manda(); disc_n++; }
            if (sys_now() - t_paso > 800U) pide_manifiesto();
            break;
        case O_MANIF:
            h_poll();
            if (h.st == H_FALLO) falla(h.err);
            else if (h.st == H_HECHO) {
                const char *e = manif_leer(h.got);
                h.st = H_LIBRE;
                if (e) falla(e);
                else {
                    log_str("ota: disponible "); log_str(mf.version); log_str(" serie "); log_dec(mf.serie);
                    log_str(", imagenes "); log_dec(mf.nimg); log_str(", perfiles "); log_dec(mf.np); log_str("\n");
                    if (mf.np) (void)mxpf_monta();           /* que la pagina sepa cuales estan ya en la tarjeta */
                    decide();
                }
                sucio = 1;
            }
            break;
        case O_BAJA:
            h_poll();
            sucio = 1;
            if (h.st == H_FALLO) falla(h.err);
            else if (h.st == H_HECHO) {
                const char *e;
                h.st = H_LIBRE;
                if (h.got != len) e = "tamano distinto";
                else e = imagen_ok();
                if (e) { falla(e); break; }
                log_str("ota: bajada en "); log_dec(sys_now() - t_paso); log_str(" ms, SHA bien\n");
                st = O_GRABA; paso = 0;
            }
            break;
        case O_GRABA:
            graba_poll();
            break;
        case O_SD_LEE:
            a_lee_poll();
            break;
        default:
            break;
    }
    /* la S3 vuelve al MSX en cuanto no hace falta, si la tomo la actualizacion (via_s3): la del escritorio del V9990
     * (v99desk.c, rama beta) la soltaba esto en la vuelta siguiente y su panel decia "S3 silent" (Z1.3b7 en placa) */
    if (via_s3 && s3_tomada() && st != O_BUSCA && st != O_MANIF && st != O_BAJA && pst != 1) {
        if (h.s3c) h_soltar();
        s3_suelta();
        via_s3 = 0;
    }
}

/* cambia a la imagen del manifiesto con ese Nextor y ese idioma (si la hay) */
static void elige(int n3, int en)
{
    u32 i;
    for (i = 0; i < mf.nimg; i++)
        if (var_n3(mf.img[i].var) == n3 && var_en(mf.img[i].var) == en) { mf.sel = (u8)i; msg[0] = 0; decide(); return; }
}

void ota_tecla(u8 u)
{
    int ocupada = ota_ocupada();
    int eligiendo = (st == O_HAY || st == O_AL_DIA || st == O_LISTA);
    if (u != 0x09U) f_armada = 0;
    if (u != 0x04U) a_armada = 0;
    if (boot_sd) {                                   /* arrancada desde SD: aqui solo se graba la ranura A con el BOOT.bin de la TF1 */
        if (u == 0x04U && !ocupada) {
            if (st == O_SD_LISTO && !a_armada) { a_armada = 1; set_msg(T("A otra vez: graba la A", "A again: write slot A")); }
            else if (st == O_SD_LISTO) {
                a_armada = 0; msg[0] = 0;
                a_sd = 1; paso = 0; pos = 0; t_paso = sys_now(); st = O_GRABA; sucio = 1;
                log_str("ota: grabando la ranura A\n");
            } else a_lee_inicia();                   /* en reposo, tras un error o tras grabar: leer (otra vez) el BOOT.bin */
        }
        return;
    }
    switch (u) {
        case 0x18:                                   /* U: buscar */
            if (!ocupada) buscar();
            break;
        case 0x05:                                   /* B: canal oficial / beta, y busca en el otro */
            if (ocupada) break;
            beta_pide ^= 1U;
            buscar();
            break;
        case 0x0C:                                   /* I: instalar */
            if (st == O_HAY && !ocupada) { msg[0] = 0; instalar(); }
            break;
        case 0x4F: case 0x50: case 0x11:             /* flechas izquierda/derecha o N: el otro Nextor */
            if (eligiendo) elige(!var_n3(IMGSEL.var), var_en(IMGSEL.var));
            break;
        case 0x51: case 0x52: case 0x0F:             /* flechas arriba/abajo o L: el otro idioma */
            if (eligiendo) elige(var_n3(IMGSEL.var), !var_en(IMGSEL.var));
            break;
        case 0x15:                                   /* R: reiniciar */
            if (ocupada) break;
            if (!boot_qspi) { set_msg(T("SW1 en QSPI y apaga", "SW1 to QSPI, power cycle")); break; }
            if (reg_ok && !reg_conf) { reg_leer(); if (!probar_b()) set_msg(T("No se puede probar la B", "Slot B can't be tested")); break; }
            reiniciar(reg_ok && reg_conf ? MB_B : 0U);
            break;
        case 0x09:                                   /* F: volver a la de fabrica (dos veces) */
            if (ocupada || !reg_ok) break;
            if (!f_armada) { f_armada = 1; set_msg(T("F otra vez: a la de fábrica", "F again: back to factory")); break; }
            f_armada = 0;
            qspi_erase4k_start(REG_ADDR); qspi_wait();
            reg_leer();
            aviso[0] = 0;
            set_msg(reg_ok ? T("No se pudo borrar", "Could not erase") : T("Fábrica elegida: R reinicia", "Factory chosen: R restarts"));
            log_str("ota: registro borrado (vuelta a la A)\n");
            break;
        default:
            break;
    }
    sucio = 1;
}

int ota_cambio(void) { int c = sucio; sucio = 0; return c; }

/* ---- la pagina de la actualizacion (OSD con color) ----------------------------------------------------------------
 * Filas: 0-1 cabecera, 3-6 "Instalada", 8-14 servidor, 15 canal (Z1.3), 16 Nextor, 17 idioma, 18-21 aviso de la SD, 22-23 estado y
 * progreso, 24-25 botones, 27 pie. Todo en las 30 columnas que se ven. */
const char *ota_version(void) { return ver_act; }
u32 ota_serie(void) { return serie_act; }                /* mxpf.c: un perfil solo se carga si es de esta serie */
int ota_ocupada(void) { return st == O_BUSCA || st == O_MANIF || st == O_BAJA || st == O_GRABA || st == O_SD_LEE || pst == 1; }   /* pst == 2 (instalando en la TF1) no: mxpf_instala lo mira */

/* lo que necesita la pagina Perfiles (perfiles.c) del servidor */
int ota_srv_estado(void)
{
    if (st == O_BUSCA || st == O_MANIF) return OSV_BUSCANDO;
    if (perfiles_listo()) return OSV_LISTO;
    if (st == O_ERROR) return OSV_ERROR;
    if (st == O_BAJA || st == O_GRABA) return OSV_OCUPADO;
    return OSV_SIN_BUSCAR;
}
const char *ota_srv_texto(void) { return st == O_ERROR ? msg : servidor[0] ? servidor : T("Servidor", "Server"); }
int ota_srv_beta(void) { return beta_pide; }

#define PF   C_NOCHE                                    /* fondo de la pagina */

static const char *var_nombre(const char *v) { return var_n3(v) ? "Nextor 3" : "Nextor 2"; }
static const char *var_corto(const char *v) { return var_n3(v) ? (var_en(v) ? "N3 EN" : "N3 ES") : (var_en(v) ? "N2 EN" : "N2 ES"); }

static void fecha_es(char *d, const char *iso)        /* 2026-09-30 -> 30/09/2026 (en ingles, 2026-09-30) */
{
    if (!osd_ingles && slen(iso) == 10U && iso[4] == '-' && iso[7] == '-') {
        d[0] = iso[8]; d[1] = iso[9]; d[2] = '/'; d[3] = iso[5]; d[4] = iso[6]; d[5] = '/';
        d[6] = iso[0]; d[7] = iso[1]; d[8] = iso[2]; d[9] = iso[3]; d[10] = 0;
    } else scpy(d, iso, 12);
}

static void tarjeta_instalada(osd_pag p)
{
    const char *ranura;
    u8 punto;
    osd_marco(p, 1, 3, 28, 4, PF, C_GRIS_OSC, T("Instalada", "Installed"), C_GRIS_CL);
    if (en_b && !reg_conf) { punto = C_AMARILLO; ranura = T("ranura B · a prueba", "slot B · on trial"); }
    else if (en_b) { punto = C_VERDE; ranura = T("ranura B · actualización", "slot B · update"); }
    else if (boot_sd) { punto = C_AMARILLO; ranura = T("arranque desde la SD", "booted from the SD"); }
    else { punto = C_VERDE; ranura = T("ranura A · de fábrica", "slot A · factory"); }
    osd_car(p, 3, 4, OSD_A(PF, punto), G_CIRCULO);
    {
        int x = osd_txt(p, 5, 4, OSD_A(PF, C_BLANCO), ver_act);
        if (beta_act) osd_txt(p, x + 1, 4, OSD_A(PF, C_NARANJA), "beta");
    }
    osd_txt_der(p, 27, 4, OSD_A(PF, C_GRIS), var_corto(var_act));
    if (aviso[0]) {
        osd_car(p, 3, 5, OSD_A(PF, C_NARANJA), G_AVISO);
        osd_txt(p, 5, 5, OSD_A(PF, C_NARANJA), aviso);
    } else if (reg_ok && !en_b && !reg_conf) {
        char b[40];
        char *q = put_s(b, "B: "); q = put_s(q, reg_ver); put_s(q, T(" sin probar", " not tried"));
        osd_txt(p, 5, 5, OSD_A(PF, C_AMARILLO), b);
    } else osd_txt(p, 5, 5, OSD_A(PF, C_GRIS), ranura);
}

static void tarjeta_servidor(osd_pag p)
{
    char b[48], *q;
    u32 i;
    int hay = (st == O_HAY || st == O_AL_DIA || st == O_LISTA || st == O_BAJA || st == O_GRABA);
    scpy(b, servidor[0] && st != O_REPOSO && st != O_BUSCA ? servidor : T("Servidor", "Server"), sizeof b);
    osd_marco(p, 1, 8, 28, 7, PF, hay && st != O_AL_DIA ? C_CIAN : C_GRIS_OSC, b, hay && st != O_AL_DIA ? C_CIAN : C_GRIS_CL);
    if (!hay) {
        if (st == O_BUSCA || st == O_MANIF) {
            osd_car(p, 3, 11, OSD_A(PF, C_CIAN), (u8)(G_GIRO0 + (sys_now() / 250U) % 4U));
            osd_txt(p, 5, 11, OSD_A(PF, C_BLANCO), st == O_BUSCA ? T("Buscando el servidor…", "Looking for the server…")
                                                                 : T("Leyendo la versión…", "Reading the version…"));
        } else {
            int x = osd_txt(p, 3, 10, OSD_A(PF, C_GRIS), T("Pulsa", "Press"));
            x = osd_pastilla(p, x + 1, 10, PF, C_AMARILLO, C_NEGRO, " U ");
            osd_txt(p, x + 1, 10, OSD_A(PF, C_GRIS), T("para buscar", "to look for"));
            osd_txt(p, 3, 11, OSD_A(PF, C_GRIS), T("la última versión en red.", "the latest version online."));
        }
        return;
    }
    osd_car(p, 3, 9, OSD_A(PF, st == O_AL_DIA ? C_VERDE : C_AMARILLO), st == O_AL_DIA ? G_OK : G_ESTRELLA);
    osd_txt(p, 5, 9, OSD_A(PF, C_BLANCO), mf.version);
    fecha_es(b, mf.fecha);
    osd_txt_der(p, 27, 9, OSD_A(PF, C_GRIS), b);
    q = osd_fijo(b, (u32)((u64)IMGSEL.tamano * 10U / 1048576U), 1); put_s(q, " MB");
    {
        int x = osd_txt(p, 5, 10, OSD_A(PF, C_GRIS_CL), b);
        x = osd_txt(p, x, 10, OSD_A(PF, C_GRIS), T(" · firma ", " · signed "));
        osd_car(p, x, 10, OSD_A(PF, C_VERDE), G_OK);
    }
    for (i = 0; i < mf.nn; i++)                      /* notas: 25 columnas dentro de la tarjeta (por caracteres, no bytes) */
        osd_txt_n(p, 3, 11 + (int)i, OSD_A(PF, C_GRIS_CL), mf.notas[i], 25);
}

/* arrancada desde SD: la tarjeta de en medio es el BOOT.bin de la TF1 (en lugar del servidor) */
static void tarjeta_sd(osd_pag p)
{
    char b[48], *q;
    int hay = (st == O_SD_LEE || st == O_SD_LISTO || st == O_GRABA || st == O_SD_HECHO);
    osd_marco(p, 1, 8, 28, 7, PF, hay ? C_CIAN : C_GRIS_OSC, T("BOOT.bin de la SD", "BOOT.bin on the SD"), hay ? C_CIAN : C_GRIS_CL);
    if (!hay) {
        int x = osd_txt(p, 3, 10, OSD_A(PF, C_GRIS), T("Pulsa", "Press"));
        x = osd_pastilla(p, x + 1, 10, PF, C_AMARILLO, C_NEGRO, " A ");
        osd_txt(p, x + 1, 10, OSD_A(PF, C_GRIS), T("para leer el", "to read the"));
        osd_txt(p, 3, 11, OSD_A(PF, C_GRIS), T("BOOT.bin de la TF1.", "BOOT.bin from TF1."));
        osd_txt(p, 3, 12, OSD_A(PF, C_GRIS_CL), T("Se graba en la ranura A", "It is written to slot A"));
        osd_txt(p, 3, 13, OSD_A(PF, C_GRIS_CL), T("(la de fábrica, en QSPI)", "(factory image, in QSPI)"));
        return;
    }
    if (st == O_SD_LEE) {
        osd_car(p, 3, 10, OSD_A(PF, C_CIAN), (u8)(G_GIRO0 + (sys_now() / 250U) % 4U));
        osd_txt(p, 5, 10, OSD_A(PF, C_BLANCO), T("Leyendo el BOOT.bin…", "Reading BOOT.bin…"));
        return;
    }
    osd_car(p, 3, 9, OSD_A(PF, st == O_SD_HECHO ? C_VERDE : C_AMARILLO), st == O_SD_HECHO ? G_OK : G_ESTRELLA);
    osd_txt(p, 5, 9, OSD_A(PF, C_BLANCO), a_ver);
    osd_txt_der(p, 27, 9, OSD_A(PF, C_GRIS), var_corto(a_var));
    q = osd_fijo(b, (u32)((u64)len * 10U / 1048576U), 1); put_s(q, " MB");
    osd_txt(p, 5, 10, OSD_A(PF, C_GRIS_CL), b);
    osd_txt(p, 3, 12, OSD_A(PF, C_GRIS_CL), T("Reemplaza la de fábrica.", "Replaces the factory one."));
    osd_txt(p, 3, 13, OSD_A(PF, C_GRIS), T("Si se apaga, se repite.", "If it fails, redo it."));
}

/* una fila de eleccion: etiqueta, dos pastillas (la elegida en cian) y la pista de teclas */
static void fila_eleccion(osd_pag p, int y, const char *etiqueta, const char *a, const char *b, int elegida_b, int hay_b, u8 g1, u8 g2)
{
    int x = osd_txt(p, 1, y, OSD_A(PF, C_GRIS), etiqueta);
    x = (x < 8) ? 8 : x + 1;
    x = osd_pastilla(p, x, y, PF, !elegida_b ? C_CIAN : C_GRIS_OSC, !elegida_b ? C_NEGRO : C_GRIS, a) + 1;
    if (hay_b) {
        x = osd_pastilla(p, x, y, PF, elegida_b ? C_CIAN : C_GRIS_OSC, elegida_b ? C_NEGRO : C_GRIS, b) + 1;
        osd_car(p, x, y, OSD_A(PF, C_GRIS), g1);
        osd_car(p, x + 1, y, OSD_A(PF, C_GRIS), g2);
    }
}

static int hay_imagen(int n3, int en)
{
    u32 i;
    for (i = 0; i < mf.nimg; i++) if (var_n3(mf.img[i].var) == n3 && var_en(mf.img[i].var) == en) return 1;
    return 0;
}

static void eleccion(osd_pag p)
{
    int n3 = var_n3(IMGSEL.var), en = var_en(IMGSEL.var);
    if (!(st == O_HAY || st == O_AL_DIA || st == O_LISTA)) return;
    if (hay_imagen(!n3, en) || n3)
        fila_eleccion(p, 16, "Nextor", "2", "3", n3, hay_imagen(1, en), G_FLECHA_IZQ, G_FLECHA_DER);
    if (hay_imagen(n3, !en) || en)
        fila_eleccion(p, 17, T("Idioma", "Lang."), "Español", "English", en, hay_imagen(n3, 1), G_TRI_ARR, G_TRI_ABA);
    if (n3 != var_n3(var_act)) {                     /* cambio de Nextor: la SD tiene que llevar el suyo */
        char b[40], *q;
        osd_car(p, 1, 18, OSD_A(PF, C_NARANJA), G_AVISO);
        q = put_s(b, T("Cambias a ", "Switch to ")); put_s(q, var_nombre(IMGSEL.var));
        osd_txt(p, 3, 18, OSD_A(PF, C_NARANJA), b);
        osd_txt(p, 3, 19, OSD_A(PF, C_NARANJA), T("Sin su NEXTOR.SYS en la SD", "Without its NEXTOR.SYS on"));
        osd_txt(p, 3, 20, OSD_A(PF, C_NARANJA), T("no arrancará MSX-DOS.", "the SD, MSX-DOS won't boot."));
        osd_txt(p, 3, 21, OSD_A(PF, C_GRIS), T("(MSX SD Maker la prepara)", "(MSX SD Maker prepares it)"));
    } else if (en != var_en(var_act)) {
        osd_car(p, 1, 18, OSD_A(PF, C_CIAN), G_TRI_DER);
        osd_txt(p, 3, 18, OSD_A(PF, C_CIAN), en ? T("Menús en inglés", "Menus in English")
                                               : T("Menús en español", "Menus in Spanish"));
    }
}

/* fila 15: el canal (Z1.3). Se ve siempre que no se esta bajando nada: se elige antes de buscar */
static void canal(osd_pag p)
{
    if (ota_ocupada()) return;
    fila_eleccion(p, 15, T("Canal", "Channel"), T("Oficial", "Official"), "Beta", beta_pide, 1, ' ', 'B');
}

static int aviso_perfiles(void)                      /* perfiles de la tarjeta que el servidor tiene mas nuevos (ya hay manifiesto y no se esta haciendo nada) */
{
    return (st == O_LISTA || st == O_AL_DIA) && !ota_ocupada() && ota_perfiles_descargables() && ota_perfiles_viejos() > 0;
}

static void estado(osd_pag p)
{
    char b[48], *q;
    u32 i;
    static const char *const pasos_es[4] = { "Bajar", "Borrar", "Grabar", "Verif" };
    static const char *const pasos_en[4] = { "Get", "Erase", "Write", "Check" };
    switch (st) {
        case O_AL_DIA:
            osd_car(p, 1, 22, OSD_A(PF, C_VERDE), G_OK);
            osd_txt(p, 3, 22, OSD_A(PF, C_VERDE), T("Estás al día", "You are up to date"));
            break;
        case O_HAY:
            osd_car(p, 1, 22, OSD_A(PF, C_AMARILLO), G_ESTRELLA);
            osd_txt(p, 3, 22, OSD_A(PF, C_AMARILLO), mf.beta != beta_act ? (mf.beta ? T("Beta: experimental", "Beta: experimental")
                                                                                            : T("Vuelta a la oficial", "Back to official")) :
                                                     mf.serie > serie_act ? T("Hay una versión nueva", "A new version is available")
                                                                          : T("Lista para instalar", "Ready to install"));
            break;
        case O_LISTA:
            osd_car(p, 1, 22, OSD_A(PF, C_VERDE), G_OK);
            osd_txt(p, 3, 22, OSD_A(PF, C_VERDE), T("Grabada en la ranura B", "Written to slot B"));
            if (!aviso_perfiles()) osd_txt(p, 3, 23, OSD_A(PF, C_GRIS), T("Si no arranca, vuelve la A", "If it fails, slot A returns"));
            break;
        case O_SD_LISTO:
            osd_car(p, 1, 22, OSD_A(PF, C_AMARILLO), G_ESTRELLA);
            osd_txt(p, 3, 22, OSD_A(PF, C_AMARILLO), T("Lista para grabar en la A", "Ready to write to slot A"));
            break;
        case O_SD_HECHO:
            osd_car(p, 1, 22, OSD_A(PF, C_VERDE), G_OK);
            osd_txt(p, 3, 22, OSD_A(PF, C_VERDE), T("Grabada en la ranura A", "Written to slot A"));
            osd_txt(p, 3, 23, OSD_A(PF, C_BLANCO), T("Apaga y pon SW1 en QSPI", "Power off, SW1 to QSPI"));
            return;
        case O_SD_LEE:
        case O_BAJA:
        case O_GRABA: {
            int sd = (st == O_SD_LEE || a_sd);       /* ranura A desde la SD: el primer paso es leer, no bajar */
            u32 actual = (st == O_BAJA || st == O_SD_LEE) ? 0U : paso <= 1U ? 1U : paso == 2U ? 2U : 3U;
            u32 hecho = st == O_BAJA ? h.got : pos, total = st == O_GRABA && paso <= 1U ? ((len + 0xFFFFU) & ~0xFFFFU) : len;
            for (i = 0; i < 4U; i++) {
                static const int col[4] = { 1, 8, 16, 23 };
                u8 c = i < actual ? C_VERDE : i == actual ? C_AMARILLO : C_GRIS;
                osd_car(p, col[i], 20, OSD_A(PF, c), i < actual ? G_OK : i == actual ? G_TRI_DER : G_ARO);
                osd_txt(p, col[i] + 1, 20, OSD_A(PF, c), (sd && i == 0U) ? T("Leer", "Read") : osd_ingles ? pasos_en[i] : pasos_es[i]);
            }
            osd_barra(p, 1, 21, 23, PF, C_VERDE, C_GRIS_OSC, hecho, total);
            q = osd_num(b, total ? (u32)((u64)hecho * 100U / total) : 0U); put_s(q, "%");
            osd_txt_der(p, 29, 21, OSD_A(PF, C_BLANCO), b);
            if (st == O_BAJA) {
                u32 ms = sys_now() - t_paso;
                q = osd_fijo(b, (u32)((u64)h.got * 10U / 1048576U), 1); q = put_s(q, T(" de ", " of "));
                q = osd_fijo(q, (u32)((u64)len * 10U / 1048576U), 1); q = put_s(q, " MB");
                if (ms > 500U) { q = put_s(q, " · "); q = osd_num(q, (u32)((u64)h.got * 1000U / 1024U / ms)); put_s(q, " KB/s"); }
                osd_txt(p, 1, 22, OSD_A(PF, C_GRIS), b);
            } else if (st == O_SD_LEE) {
                q = osd_fijo(b, (u32)((u64)pos * 10U / 1048576U), 1); q = put_s(q, T(" de ", " of "));
                q = osd_fijo(q, (u32)((u64)len * 10U / 1048576U), 1); put_s(q, " MB");
                osd_txt(p, 1, 22, OSD_A(PF, C_GRIS), b);
            } else if (a_sd) {
                osd_txt(p, 1, 22, OSD_A(PF, C_GRIS_CL), T("No apagues la placa.", "Don't power off the board."));
                osd_txt(p, 1, 23, OSD_A(PF, C_GRIS), T("Si se apaga, repítelo.", "If it does, redo it."));
            } else {
                osd_txt(p, 1, 22, OSD_A(PF, C_GRIS_CL), T("No apagues la placa.", "Don't power off the board."));
                osd_txt(p, 1, 23, OSD_A(PF, C_GRIS), T("Si se apaga, arranca la A.", "If it does, slot A boots."));
            }
            break;
        }
        case O_ERROR:
            osd_car(p, 1, 22, OSD_A(PF, C_ROJO), G_NO);
            osd_txt(p, 3, 22, OSD_A(PF, C_ROJO), msg);
            osd_txt(p, 3, 23, OSD_A(PF, C_GRIS), boot_sd && a_dg ? bootsd_diag()                  /* lo que se vio en la TF1 */
                                                 : boot_sd ? T("A lo intenta otra vez", "A tries again") : T("U lo intenta otra vez", "U tries again"));
            return;
        default:
            break;
    }
    if (msg[0]) {                                    /* avisos que no son error (F, R en JTAG...) */
        osd_car(p, 1, 23, OSD_A(PF, C_NARANJA), G_TRI_DER);
        osd_txt(p, 3, 23, OSD_A(PF, C_NARANJA), msg);
    } else if (aviso_perfiles()) {                   /* cada BOOT.bin nuevo deja los perfiles de la tarjeta de la serie anterior */
        osd_car(p, 1, 23, OSD_A(PF, C_NARANJA), G_AVISO);
        osd_txt(p, 3, 23, OSD_A(PF, C_NARANJA), T("Perfiles viejos: tecla P", "Old profiles: press P"));
    }
}

static void botones(osd_pag p)
{
    int x = 1;
    if (ota_ocupada()) {
        osd_boton(p, 1, 25, PF, C_GRIS_CL, "ESC", T("Ocultar (sigue)", "Hide (keeps going)"));
        return;
    }
    if (boot_sd) {                                   /* arrancada desde SD: leer el BOOT.bin y grabar la ranura A */
        osd_boton(p, 1, 24, PF, C_AMARILLO, "A", st == O_SD_LISTO ? T("Grabar la A", "Write slot A") : T("Leer BOOT.bin", "Read BOOT.bin"));
        osd_boton(p, 1, 25, PF, C_GRIS_CL, "ESC", T("Volver", "Back"));
        return;
    }
    if (st == O_HAY) x = osd_boton(p, x, 24, PF, C_AMARILLO, "I", T("Instalar", "Install"));
    if (st == O_LISTA || (reg_ok && !reg_conf && !en_b)) x = osd_boton(p, x, 24, PF, C_AMARILLO, "R", T("Arrancar", "Boot it"));
    else if (st != O_HAY) x = osd_boton(p, x, 24, PF, C_AMARILLO, "U", T("Buscar", "Search"));
    x = osd_boton(p, 1, 25, PF, C_GRIS_CL, "ESC", T("Volver", "Back"));
    if (reg_ok) osd_boton(p, x, 25, PF, C_GRIS_CL, "F", T("Fábrica", "Factory"));
    if (aviso_perfiles()) osd_boton(p, 1, 26, PF, C_AMARILLO, "P", T("Perfiles", "Profiles"));
}

static void pie(osd_pag p)
{
    extern void net_ip(u8 ip[4]);
    u8 ip[4];
    char b[40], *q;
    int wifi = 0;
    net_ip(ip);
    if (!ip[0] && s3_ip(ip)) wifi = 1;               /* sin cable: la IP de la S3 (la de la ultima busqueda) */
    osd_car(p, 1, 27, OSD_A(PF, ip[0] ? C_VERDE : C_NARANJA), G_RED);
    if (ip[0]) {
        q = b; q = osd_num(q, ip[0]); *q++ = '.'; q = osd_num(q, ip[1]); *q++ = '.'; q = osd_num(q, ip[2]); *q++ = '.'; q = osd_num(q, ip[3]);
        if (wifi) put_s(q, " WiFi");
        osd_txt(p, 3, 27, OSD_A(PF, C_GRIS), b);
    } else osd_txt(p, 3, 27, OSD_A(PF, C_NARANJA), T("sin red: cable o WiFi", "no network: cable or WiFi"));
    osd_txt_der(p, 29, 27, OSD_A(PF, C_GRIS_OSC), boot_qspi ? "QSPI" : boot_sd ? "SD" : "JTAG");
}

void ota_pagina(osd_pag p)
{
    osd_limpia(p, OSD_A(PF, C_BLANCO));
    osd_cabecera(p, G_BAJAR, T("Actualizar por red", "Network update"), NULL);
    tarjeta_instalada(p);
    if (boot_sd) tarjeta_sd(p);                      /* arrancada desde SD: el BOOT.bin de la TF1, no el servidor */
    else {
        tarjeta_servidor(p);
        canal(p);
        eleccion(p);
    }
    estado(p);
    botones(p);
    pie(p);
}
