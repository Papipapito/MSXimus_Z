/* osd_glifos.h — GENERADO por fpga/zynq/tools/make_dpb_menu.py (tools/osd_fuente.py): glifos 128..255 y paleta del
 * OSD con color (textdisp de la Z1.2.2). Atributo = OSD_A(fondo, tinta). */
#ifndef OSD_GLIFOS_H
#define OSD_GLIFOS_H

#define C_CLASICO       0U
#define C_BLANCO        1U
#define C_GRIS_CL       2U
#define C_GRIS          3U
#define C_GRIS_OSC      4U
#define C_NOCHE         5U
#define C_AZUL          6U
#define C_CIAN          7U
#define C_VERDE         8U
#define C_VERDE_OSC     9U
#define C_AMARILLO     10U
#define C_NARANJA      11U
#define C_ROJO         12U
#define C_VIOLETA      13U
#define C_MARINO       14U
#define C_NEGRO        15U
#define OSD_A(fondo, tinta) ((u8)(((fondo) << 4) | (tinta)))

#define G_BLOQUE         0x80U   /* █ */
#define G_IZQ1           0x81U   /* ▏ */
#define G_IZQ2           0x82U   /* ▎ */
#define G_IZQ3           0x83U   /* ▍ */
#define G_IZQ4           0x84U   /* ▌ */
#define G_IZQ5           0x85U   /* ▋ */
#define G_IZQ6           0x86U   /* ▊ */
#define G_IZQ7           0x87U   /* ▉ */
#define G_MITAD_SUP      0x88U   /* ▀ */
#define G_MITAD_INF      0x89U   /* ▄ */
#define G_SOMBRA1        0x8AU   /* ░ */
#define G_SOMBRA2        0x8BU   /* ▒ */
#define G_SOMBRA3        0x8CU   /* ▓ */
#define G_H              0x8DU   /* ─ */
#define G_V              0x8EU   /* │ */
#define G_ESQ_SI         0x8FU   /* ┌ */
#define G_ESQ_SD         0x90U   /* ┐ */
#define G_ESQ_II         0x91U   /* └ */
#define G_ESQ_ID         0x92U   /* ┘ */
#define G_T_IZQ          0x93U   /* ├ */
#define G_T_DER          0x94U   /* ┤ */
#define G_T_ARR          0x95U   /* ┬ */
#define G_T_ABA          0x96U   /* ┴ */
#define G_CRUZ           0x97U   /* ┼ */
#define G_RED_SI         0x98U   /* ╭ */
#define G_RED_SD         0x99U   /* ╮ */
#define G_RED_II         0x9AU   /* ╰ */
#define G_RED_ID         0x9BU   /* ╯ */
#define G_H2             0x9CU   /* ═ */
#define G_V2             0x9DU   /* ║ */
#define G_OK             0x9EU   /* ✓ */
#define G_NO             0x9FU   /* ✗ */
#define G_TRI_DER        0xA0U   /* ► */
#define G_TRI_IZQ        0xA1U   /* ◄ */
#define G_TRI_ARR        0xA2U   /* ▲ */
#define G_TRI_ABA        0xA3U   /* ▼ */
#define G_CIRCULO        0xA4U   /* ● */
#define G_ARO            0xA5U   /* ○ */
#define G_ROMBO          0xA6U   /* ◆ */
#define G_ESTRELLA       0xA7U   /* ★ */
#define G_BAJAR          0xA8U   /* ⤓ */
#define G_SUBIR          0xA9U   /* ⤒ */
#define G_AVISO          0xAAU   /* ⚠ */
#define G_RED            0xABU   /* 🖧 */
#define G_CHIP           0xACU   /* ▣ */
#define G_SD             0xADU   /* ▤ */
#define G_NOTA           0xAEU   /* ♪ */
#define G_FLECHA_IZQ     0xAFU   /* ← */
#define G_FLECHA_DER     0xB0U   /* → */
#define G_PUNTO_MEDIO    0xB1U   /* · */
#define G_VINETA         0xB2U   /* • */
#define G_PUNTOS         0xB3U   /* … */
#define G_POR            0xB4U   /* × */
#define G_GRADO          0xB5U   /* ° */
#define G_GIRO0          0xB6U   /* ◴ */
#define G_GIRO1          0xB7U   /* ◷ */
#define G_GIRO2          0xB8U   /* ◶ */
#define G_GIRO3          0xB9U   /* ◵ */
#define G_TAPA_IZQ       0xBAU   /* ◖ */
#define G_TAPA_DER       0xBBU   /* ◗ */
#define G_DER_MITAD      0xBCU   /* ▐ */
#define G_LINEA_SUP      0xBDU   /* ▔ */
#define G_LINEA_INF      0xBEU   /* ▁ */
#define G_ABA1           0xBFU
#define G_ABA2           0xC0U
#define G_ABA3           0xC1U
#define G_ABA4           0xC2U
#define G_ABA5           0xC3U
#define G_ABA6           0xC4U
#define G_ABA7           0xC5U
#define G_a_AGUDO        0xC6U   /* á */
#define G_e_AGUDO        0xC7U   /* é */
#define G_i_AGUDO        0xC8U   /* í */
#define G_o_AGUDO        0xC9U   /* ó */
#define G_u_AGUDO        0xCAU   /* ú */
#define G_a_GRAVE        0xCBU   /* à */
#define G_e_GRAVE        0xCCU   /* è */
#define G_o_GRAVE        0xCDU   /* ò */
#define G_u_DIER         0xCEU   /* ü */
#define G_i_DIER         0xCFU   /* ï */
#define G_n_TILDE        0xD0U   /* ñ */
#define G_c_CEDILLA      0xD1U   /* ç */
#define G_A_AGUDO        0xD2U   /* Á */
#define G_E_AGUDO        0xD3U   /* É */
#define G_I_AGUDO        0xD4U   /* Í */
#define G_O_AGUDO        0xD5U   /* Ó */
#define G_U_AGUDO        0xD6U   /* Ú */
#define G_N_TILDE        0xD7U   /* Ñ */
#define G_C_CEDILLA      0xD8U   /* Ç */
#define G_ABRE_INTERROG  0xD9U   /* ¿ */
#define G_ABRE_EXCLAM    0xDAU   /* ¡ */
#define G_ORDINAL_O      0xDBU   /* º */
#define G_ORDINAL_A      0xDCU   /* ª */
#define G_EURO           0xDDU   /* € */
#define G_CUAD0          0xF0U
#define G_CUAD1          0xF1U
#define G_CUAD2          0xF2U
#define G_CUAD3          0xF3U
#define G_CUAD4          0xF4U
#define G_CUAD5          0xF5U
#define G_CUAD6          0xF6U
#define G_CUAD7          0xF7U
#define G_CUAD8          0xF8U
#define G_CUAD9          0xF9U
#define G_CUADA          0xFAU
#define G_CUADB          0xFBU
#define G_CUADC          0xFCU
#define G_CUADD          0xFDU
#define G_CUADE          0xFEU
#define G_CUADF          0xFFU

/* UTF-8 -> glifo: los caracteres de fuera del ASCII que entiende osd_txt() */
#ifdef OSD_UTF8_TABLA                      /* solo osd_dib.c */
static const struct { u16 cp; u8 g; } osd_utf8[] = {
    { 0x00A1, 0xDA },
    { 0x00AA, 0xDC },
    { 0x00B0, 0xB5 },
    { 0x00B7, 0xB1 },
    { 0x00BA, 0xDB },
    { 0x00BF, 0xD9 },
    { 0x00C1, 0xD2 },
    { 0x00C7, 0xD8 },
    { 0x00C9, 0xD3 },
    { 0x00CD, 0xD4 },
    { 0x00D1, 0xD7 },
    { 0x00D3, 0xD5 },
    { 0x00D7, 0xB4 },
    { 0x00DA, 0xD6 },
    { 0x00E0, 0xCB },
    { 0x00E1, 0xC6 },
    { 0x00E7, 0xD1 },
    { 0x00E8, 0xCC },
    { 0x00E9, 0xC7 },
    { 0x00ED, 0xC8 },
    { 0x00EF, 0xCF },
    { 0x00F1, 0xD0 },
    { 0x00F2, 0xCD },
    { 0x00F3, 0xC9 },
    { 0x00FA, 0xCA },
    { 0x00FC, 0xCE },
    { 0x2022, 0xB2 },
    { 0x2026, 0xB3 },
    { 0x20AC, 0xDD },
    { 0x2190, 0xAF },
    { 0x2192, 0xB0 },
    { 0x2500, 0x8D },
    { 0x2502, 0x8E },
    { 0x250C, 0x8F },
    { 0x2510, 0x90 },
    { 0x2514, 0x91 },
    { 0x2518, 0x92 },
    { 0x251C, 0x93 },
    { 0x2524, 0x94 },
    { 0x252C, 0x95 },
    { 0x2534, 0x96 },
    { 0x253C, 0x97 },
    { 0x2550, 0x9C },
    { 0x2551, 0x9D },
    { 0x256D, 0x98 },
    { 0x256E, 0x99 },
    { 0x256F, 0x9B },
    { 0x2570, 0x9A },
    { 0x2580, 0x88 },
    { 0x2581, 0xBE },
    { 0x2584, 0x89 },
    { 0x2588, 0x80 },
    { 0x2589, 0x87 },
    { 0x258A, 0x86 },
    { 0x258B, 0x85 },
    { 0x258C, 0x84 },
    { 0x258D, 0x83 },
    { 0x258E, 0x82 },
    { 0x258F, 0x81 },
    { 0x2590, 0xBC },
    { 0x2591, 0x8A },
    { 0x2592, 0x8B },
    { 0x2593, 0x8C },
    { 0x2594, 0xBD },
    { 0x25A3, 0xAC },
    { 0x25A4, 0xAD },
    { 0x25B2, 0xA2 },
    { 0x25BA, 0xA0 },
    { 0x25BC, 0xA3 },
    { 0x25C4, 0xA1 },
    { 0x25C6, 0xA6 },
    { 0x25CB, 0xA5 },
    { 0x25CF, 0xA4 },
    { 0x25D6, 0xBA },
    { 0x25D7, 0xBB },
    { 0x25F4, 0xB6 },
    { 0x25F5, 0xB9 },
    { 0x25F6, 0xB8 },
    { 0x25F7, 0xB7 },
    { 0x2605, 0xA7 },
    { 0x266A, 0xAE },
    { 0x26A0, 0xAA },
    { 0x2713, 0x9E },
    { 0x2717, 0x9F },
    { 0x2912, 0xA9 },
    { 0x2913, 0xA8 },
};
#endif
#endif
