/* usb_vigila.c — decision del vigilante del EHCI (usb_vigila.h). Pura: ni registros ni TinyUSB. */
#include "usb_vigila.h"

void vigila_inicia(vigila_t *v, uint32_t ahora)
{
    uint32_t t_reinicio = v->t_reinicio;
    uint8_t  hubo = v->hubo_reinicio;
    unsigned k;
    for (k = 0; k < sizeof(*v); k++) ((uint8_t *)v)[k] = 0;
    v->t_ultima = ahora;
    v->t_reinicio = t_reinicio;               /* el ritmo de reinicios sobrevive al rearranque */
    v->hubo_reinicio = hubo;
}

int vigila_toca(const vigila_t *v, uint32_t ahora)
{
    uint32_t periodo = VIGILA_MUESTRA_MS + (v->alterna ? VIGILA_ALTERNA_MS : 0u);
    return (uint32_t)(ahora - v->t_ultima) >= periodo;
}

int vigila_muestra(vigila_t *v, uint32_t ahora, uint32_t firma, uint32_t n_split, uint32_t frindex)
{
    uint32_t hueco = (uint32_t)(ahora - v->t_ultima);
    uint32_t avance = (frindex - v->fr_prev) & 0x3FFFu;                 /* FRINDEX: 14 bits, microtramas */

    v->t_ultima = ahora;
    v->alterna ^= 1u;
    v->fr_prev = frindex;

    if (n_split == 0u) { v->valida = 0; return 0; }                     /* nada que juzgar */
    if (!v->valida || firma != v->firma || hueco > VIGILA_HUECO_MS) {   /* se mueve, o referencia nueva */
        v->valida = 1; v->firma = firma; v->t_ref = ahora; v->fr_acum = 0;
        return 0;
    }
    v->fr_acum += avance;
    if ((uint32_t)(ahora - v->t_ref) < VIGILA_CUELGUE_MS) return 0;
    if (v->fr_acum < VIGILA_FRAMES_MIN) return 0;                       /* el reloj del EHCI no avanza: otro fallo */
    if (v->hubo_reinicio && (uint32_t)(ahora - v->t_reinicio) < VIGILA_REINICIO_MS) return 0;
    return 1;
}

void vigila_reiniciado(vigila_t *v, uint32_t ahora)
{
    v->hubo_reinicio = 1;
    v->t_reinicio = ahora;
    v->valida = 0;
    v->t_ultima = ahora;
    v->alterna = 0;
}
