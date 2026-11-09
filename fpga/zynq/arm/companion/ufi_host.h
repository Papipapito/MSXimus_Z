/* ufi_host.h — driver de clase TinyUSB (host) para DISQUETERAS USB de 3,5" (clase 08):
 * subclase 04 (UFI), 05 (SFF-8070i) o 06 (SCSI transparente) con transporte
 *   00 CBI  (Control/Bulk/Interrupt: orden por ADSC, datos por bulk, estado por interrupt de 2 bytes)
 *   01 CB   (Control/Bulk sin interrupt: el estado solo se conoce por REQUEST SENSE)
 *   50 BOT  (Bulk-Only: CBW de 31 B, datos, CSW de 13 B)
 * El driver NO interpreta las ordenes: transporta un bloque de orden (CDB) y sus datos y devuelve un
 * resultado de transporte. Quien sabe de INQUIRY, READ(10), sense keys, etc. es fdd.c.
 *
 * Dos capas:
 *   - maquina de estados NO bloqueante (ufih_open/set_config/xfer_cb/close + callbacks de control):
 *     corre dentro de tuh_task_ext() y deja 'done' cuando la orden termina;
 *   - ufi_command()/ufi_reset(): SINCRONAS con timeout, SOLO desde el bucle principal (main.c ->
 *     fdd.c), nunca desde un callback de TinyUSB: esperan bombeando usb_host_poll() (ISR por sondeo +
 *     tarea). Bloquear dentro de un callback anidaria tuh_task_ext() y podria reentrar xfer_cb con la
 *     orden a medias (estado corrupto); y el modo sincrono de TinyUSB (complete_cb == NULL) no vale en
 *     este companion porque espera con tuh_task_ext() sin llamar a hcd_int_handler(): cuelgue seguro.
 *
 * Se registra en usbh_app_driver_get_cb() (usb_host.c) junto al xinput. Un solo dispositivo por
 * direccion USB (1..CFG_TUH_DEVICE_MAX); el hub (daddr 5) se filtra por clase y direccion.    */
#ifndef UFI_HOST_H
#define UFI_HOST_H
#include "tusb.h"
#include "host/usbh_pvt.h"

/* 1 = el driver se queda TAMBIEN con las interfaces 08/06/50 (SCSI + Bulk-Only: pendrives y las pocas
 * disqueteras BOT) por delante del msc_host de TinyUSB; fdd.c ignora lo que tenga mas de 2880 bloques.
 * Motivo: msc_host.c entra en un bucle TEST UNIT READY / REQUEST SENSE SIN LIMITE con una disquetera
 * sin disco y nunca llama a usbh_driver_set_config_complete(): bloquea la enumeracion de TODO lo que
 * cuelgue del hub (teclado incluido). 0 = se las cede a msc_host (backend 3 de fdd.c).                */
#ifndef UFI_CLAIM_SCSI_BOT
#define UFI_CLAIM_SCSI_BOT 1
#endif

enum { UFI_XPORT_NONE = 0, UFI_XPORT_CBI = 1, UFI_XPORT_CB = 2, UFI_XPORT_BOT = 3 };

/* resultado de ufi_command() / ufi_reset() */
enum {
    UFI_OK      = 0,   /* orden aceptada y completada (los datos pueden ser cortos: mirar *xferred) */
    UFI_CHECK   = 1,   /* orden rechazada o fallida por el dispositivo (CHECK CONDITION): REQUEST SENSE */
    UFI_TIMEOUT = 2,   /* sin respuesta en el plazo: transferencias abortadas; conviene ufi_reset() */
    UFI_FAIL    = 3,   /* transporte roto (CSW invalido, fase, STALL persistente, error USB): ufi_reset() */
    UFI_GONE    = 4,   /* dispositivo desconectado o no montado */
    UFI_BUSY    = 5    /* otra orden en curso (reentrada) o endpoint/control ocupado: reintentar luego */
};

/* --- API sincrona (solo bucle principal) --- */
/* Ejecuta un CDB (6/10/12 bytes; se rellena a 12 en UFI/SFF) con hasta 'len' bytes de datos IN (dir_in=1)
 * u OUT. 'buf' alineado a 32 y en DDR (lo lee el EHCI). Devuelve UFI_*; *xferred = bytes movidos. */
int  ufi_command(uint8_t daddr, const uint8_t *cdb, uint8_t cdb_len, int dir_in,
                 uint8_t *buf, uint16_t len, uint32_t timeout_ms, uint32_t *xferred);
/* Reset recovery: BOT = Bulk-Only Mass Storage Reset (0xFF) + CLEAR_FEATURE de los dos bulk;
 * CBI/CB = Command Block Reset (ADSC 1D 04 FF..FF) + CLEAR_FEATURE de los dos bulk. Devuelve UFI_OK/… */
int  ufi_reset(uint8_t daddr);
/* Espera 'ms' bombeando el USB (para dejar arrancar un motor sin congelar teclado/mandos). */
void ufi_delay_ms(uint32_t ms);
void ufi_set_cancel(int (*fn)(void));       /* la espera de la orden en curso se aborta si fn() devuelve 1 (NULL = no) */

/* --- consultas --- */
uint8_t ufi_first_daddr(void);              /* primera disquetera montada (0 = ninguna) */
int     ufi_mounted(uint8_t daddr);
uint8_t ufi_transport(uint8_t daddr);       /* UFI_XPORT_* */
uint8_t ufi_subclass(uint8_t daddr);        /* MSC_SUBCLASS_UFI / SFF / SCSI */
const uint8_t *ufi_int_status(uint8_t daddr);   /* CBI: los 2 bytes del ultimo interrupt (ASC, ASCQ en UFI) */

/* --- callbacks hacia la aplicacion (definidas en usb_host.c -> fdd.c) --- */
void tuh_ufi_mount_cb(uint8_t daddr);       /* dentro de tuh_task_ext(): NO lanzar ordenes desde aqui */
void tuh_ufi_umount_cb(uint8_t daddr);

/* --- API de driver de clase para usbh (tabla de usbh_app_driver_get_cb) --- */
bool     ufih_init(void);
uint16_t ufih_open(uint8_t rhport, uint8_t daddr, tusb_desc_interface_t const *desc_itf, uint16_t max_len);
bool     ufih_set_config(uint8_t daddr, uint8_t itf_num);
bool     ufih_xfer_cb(uint8_t daddr, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes);
void     ufih_close(uint8_t daddr);

#endif
