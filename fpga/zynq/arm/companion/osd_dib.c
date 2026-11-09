/* osd_dib.c — dibujo sobre una pagina del OSD con color (osd.h). Sin hardware: lo usan osd.c, ota.c y el banco del PC
 * (tests/ota_host), que vuelca las paginas y tools/osd_render.py las pinta como el textdisp. */
#define OSD_UTF8_TABLA
#include "osd.h"

u8 osd_ingles;                                           /* 1 = textos en ingles (ota.c) */

void osd_limpia(osd_pag p, u8 a)
{
    int x, y;
    for (y = 0; y < OSD_FILAS; y++) for (x = 0; x < OSD_COLS; x++) p[y][x] = (osd_celda)(((u16)a << 8) | ' ');
}

void osd_car(osd_pag p, int x, int y, u8 a, u8 c)
{
    if (x >= 0 && x < OSD_COLS && y >= 0 && y < OSD_FILAS) p[y][x] = (osd_celda)(((u16)a << 8) | c);
}

static u32 utf8_sig(const char **s)                     /* siguiente codigo de un texto UTF-8 */
{
    const u8 *p = (const u8 *)*s;
    u32 cp = p[0], n = 1, i;
    if (cp >= 0xF0U) { cp &= 0x07U; n = 4; }
    else if (cp >= 0xE0U) { cp &= 0x0FU; n = 3; }
    else if (cp >= 0xC0U) { cp &= 0x1FU; n = 2; }
    for (i = 1; i < n; i++) { if ((p[i] & 0xC0U) != 0x80U) { n = i; break; } cp = (cp << 6) | (p[i] & 0x3FU); }
    *s += n;
    return cp;
}

static u8 glifo_de(u32 cp)
{
    u32 i;
    if (cp >= 0x20U && cp < 0x7FU) return (u8)cp;
    for (i = 0; i < sizeof osd_utf8 / sizeof osd_utf8[0]; i++) if (osd_utf8[i].cp == cp) return osd_utf8[i].g;
    return '?';
}

int osd_txt(osd_pag p, int x, int y, u8 a, const char *s)
{
    while (*s && x < OSD_ANCHO) osd_car(p, x++, y, a, glifo_de(utf8_sig(&s)));
    return x;
}

int osd_txt_n(osd_pag p, int x, int y, u8 a, const char *s, int n)
{
    while (*s && n-- > 0 && x < OSD_ANCHO) osd_car(p, x++, y, a, glifo_de(utf8_sig(&s)));
    return x;
}

int osd_txt_len(const char *s)
{
    int n = 0;
    while (*s) { (void)utf8_sig(&s); n++; }
    return n;
}

int osd_txt_der(osd_pag p, int x_fin, int y, u8 a, const char *s)
{
    return osd_txt(p, x_fin - osd_txt_len(s), y, a, s);
}

void osd_rellena(osd_pag p, int x, int y, int w, int h, u8 a, u8 c)
{
    int i, j;
    for (j = 0; j < h; j++) for (i = 0; i < w; i++) osd_car(p, x + i, y + j, a, c);
}

/* marco de esquinas redondeadas; el titulo va encima de la linea de arriba, entre espacios */
void osd_marco(osd_pag p, int x, int y, int w, int h, u8 fondo, u8 linea, const char *titulo, u8 tinta_titulo)
{
    u8 a = OSD_A(fondo, linea);
    int i;
    osd_car(p, x, y, a, G_RED_SI); osd_car(p, x + w - 1, y, a, G_RED_SD);
    osd_car(p, x, y + h - 1, a, G_RED_II); osd_car(p, x + w - 1, y + h - 1, a, G_RED_ID);
    for (i = 1; i < w - 1; i++) { osd_car(p, x + i, y, a, G_H); osd_car(p, x + i, y + h - 1, a, G_H); }
    for (i = 1; i < h - 1; i++) { osd_car(p, x, y + i, a, G_V); osd_car(p, x + w - 1, y + i, a, G_V); }
    osd_rellena(p, x + 1, y + 1, w - 2, h - 2, OSD_A(fondo, fondo), ' ');
    if (titulo && *titulo) {
        int k = osd_txt(p, x + 2, y, OSD_A(fondo, tinta_titulo), " ");
        k = osd_txt(p, k, y, OSD_A(fondo, tinta_titulo), titulo);
        osd_txt(p, k, y, OSD_A(fondo, tinta_titulo), " ");
    }
}

/* barra de progreso de w celdas con resolucion de 1/8 de celda */
void osd_barra(osd_pag p, int x, int y, int w, u8 fondo, u8 lleno, u8 vacio, u32 num, u32 den)
{
    u32 octavos = den ? (u32)((u64)num * (u32)w * 8U / den) : 0U, i;
    (void)fondo;
    if (octavos > (u32)w * 8U) octavos = (u32)w * 8U;
    for (i = 0; i < (u32)w; i++) {
        u32 o = octavos > i * 8U ? octavos - i * 8U : 0U;
        if (o >= 8U) osd_car(p, x + (int)i, y, OSD_A(vacio, lleno), G_BLOQUE);
        else if (o) osd_car(p, x + (int)i, y, OSD_A(vacio, lleno), (u8)(G_IZQ1 + o - 1U));
        else osd_car(p, x + (int)i, y, OSD_A(vacio, lleno), ' ');
    }
}

/* pastilla: texto sobre una placa de color con las tapas redondeadas; devuelve la columna siguiente */
int osd_pastilla(osd_pag p, int x, int y, u8 fondo, u8 color, u8 tinta, const char *texto)
{
    osd_car(p, x++, y, OSD_A(fondo, color), G_TAPA_IZQ);
    x = osd_txt(p, x, y, OSD_A(color, tinta), texto);
    osd_car(p, x++, y, OSD_A(fondo, color), G_TAPA_DER);
    return x;
}

/* boton: tecla en una pastilla y su texto al lado; devuelve la columna siguiente (con hueco) */
int osd_boton(osd_pag p, int x, int y, u8 fondo, u8 color, const char *tecla, const char *texto)
{
    if (osd_txt_len(tecla) == 1) {
        char t[8], *q = t;
        *q++ = ' '; while (*tecla) *q++ = *tecla++; *q++ = ' '; *q = 0;
        x = osd_pastilla(p, x, y, fondo, color, C_NEGRO, t);
    } else x = osd_pastilla(p, x, y, fondo, color, C_NEGRO, tecla);
    if (texto && *texto) { x++; x = osd_txt(p, x, y, OSD_A(fondo, C_BLANCO), texto); }
    return x + 2;
}

/* cabecera: fila 0 en azul con icono, titulo y un texto a la derecha; la fila 1 hace de borde suave */
void osd_cabecera(osd_pag p, u8 icono, const char *titulo, const char *derecha)
{
    int x;
    osd_rellena(p, 0, 0, OSD_COLS, 1, OSD_A(C_AZUL, C_BLANCO), ' ');
    osd_car(p, 1, 0, OSD_A(C_AZUL, C_AMARILLO), icono);
    x = osd_txt(p, 3, 0, OSD_A(C_AZUL, C_BLANCO), titulo);
    if (derecha && x + 1 < OSD_ANCHO - 1 - osd_txt_len(derecha)) osd_txt_der(p, OSD_ANCHO - 1, 0, OSD_A(C_AZUL, C_CIAN), derecha);
    osd_rellena(p, 0, 1, OSD_COLS, 1, OSD_A(C_NOCHE, C_AZUL), G_MITAD_SUP);
}

char *osd_num(char *d, u32 v)
{
    char t[11];
    int n = 0;
    do { t[n++] = (char)('0' + v % 10U); v /= 10U; } while (v);
    while (n) *d++ = t[--n];
    *d = 0;
    return d;
}

char *osd_fijo(char *d, u32 v, u32 dec)
{
    u32 pw = 1, i, f;
    for (i = 0; i < dec; i++) pw *= 10U;
    d = osd_num(d, v / pw);
    if (dec) {
        *d++ = osd_ingles ? '.' : ',';                  /* 3,58 / 3.58 */
        f = v % pw;
        for (i = pw / 10U; i; i /= 10U) *d++ = (char)('0' + (f / i) % 10U);
        *d = 0;
    }
    return d;
}
