/* usb_vigila.h — decision del vigilante del EHCI del USB host (la usa usb_host.c). Es una funcion pura, sin
 * hardware ni TinyUSB: la prueba del PC es tests/usb_vigila_host.
 *
 * Que se vigila: el motor periodico del EHCI, el que reparte las transacciones de los endpoints de interrupcion
 * (teclados, ratones, mandos y el estado del hub). Colgado de verdad (placa, tras horas encendida): FRINDEX sigue
 * contando, pero los QH con split de los dispositivos FS/LS detras del hub dejan de avanzar, y el controlador ya
 * no atiende RS = 0 ni PSE = 0. El FrameTag, la C-prog-mask y el SplitX de esos QH (que el EHCI reescribe en cada
 * start/complete split) quedan congelados: ehci_split_signature() (tinyusb ehci.c) los resume en una firma.
 *
 * Decision: hay colgado cuando, con QH con split activos (n_split > 0), la firma NO ha cambiado durante
 * VIGILA_CUELGUE_MS y FRINDEX ha avanzado en ese tiempo.
 *   - Se muestrea cada VIGILA_MUESTRA_MS, alternando +0 y +20 ms: ninguna separacion es multiplo de los 32 ms
 *     del ciclo del FrameTag, asi que un controlador sano no repite la firma por coincidencia de fase.
 *   - Si el bucle estuvo parado (mas de VIGILA_HUECO_MS entre dos muestras) la referencia se empieza de nuevo.
 *   - Reinicios automaticos: como mucho uno cada VIGILA_REINICIO_MS.
 * Limite: sin QH con split activos (nada conectado, o solo dispositivos de alta velocidad) no se decide nada, y un
 * EHCI con FRINDEX parado tampoco se declara colgado: es otro fallo, que este vigilante no ha visto. */
#ifndef USB_VIGILA_H
#define USB_VIGILA_H
#include <stdint.h>

#define VIGILA_MUESTRA_MS   500u     /* periodo base del muestreo */
#define VIGILA_ALTERNA_MS   20u      /* se suma cada dos muestras */
#define VIGILA_CUELGUE_MS   1500u    /* firma sin cambiar durante tanto (con FRINDEX avanzando) = colgado */
#define VIGILA_HUECO_MS     1250u    /* mas que esto entre dos muestras: el bucle estuvo parado, referencia nueva */
#define VIGILA_REINICIO_MS  5000u    /* separacion minima entre dos reinicios automaticos */
#define VIGILA_FRAMES_MIN   4000u    /* microtramas que debe avanzar FRINDEX (de ~12000 esperadas en 1,5 s) */

typedef struct {
    uint32_t firma;          /* firma de referencia */
    uint32_t t_ref;          /* ms en que se vio por primera vez */
    uint32_t fr_acum;        /* microtramas que ha avanzado FRINDEX desde t_ref */
    uint32_t fr_prev;        /* FRINDEX en la muestra anterior */
    uint32_t t_ultima;       /* ms de la ultima muestra */
    uint32_t t_reinicio;     /* ms del ultimo reinicio */
    uint8_t  valida;         /* hay firma de referencia */
    uint8_t  hubo_reinicio;
    uint8_t  alterna;
} vigila_t;

/* Tras (re)arrancar el USB: sin referencia, primera muestra dentro de VIGILA_MUESTRA_MS. */
void vigila_inicia(vigila_t *v, uint32_t ahora);

/* 1 = ya toca tomar otra muestra. */
int  vigila_toca(const vigila_t *v, uint32_t ahora);

/* Una muestra: firma y n_split de ehci_split_signature(), frindex = registro FRINDEX. Devuelve 1 si hay que reiniciar. */
int  vigila_muestra(vigila_t *v, uint32_t ahora, uint32_t firma, uint32_t n_split, uint32_t frindex);

/* Anota que se acaba de reiniciar el USB (limita el ritmo y borra la referencia). Tambien para los forzados. */
void vigila_reiniciado(vigila_t *v, uint32_t ahora);

#endif
