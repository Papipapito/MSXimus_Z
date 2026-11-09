/* ufi_host.c — driver de clase TinyUSB (host) para disqueteras USB: transportes CBI, CB y BOT.
 * Ver ufi_host.h para el reparto de capas. Aqui esta:
 *
 *  1. Enumeracion (open/set_config/close): acepta clase 08 con subclase 04/05 (UFI/SFF-8070i) y
 *     protocolo 00/01/50, y 06/50 si UFI_CLAIM_SCSI_BOT. Abre los dos bulk y, en CBI, el interrupt IN
 *     de estado (2 bytes). set_config no necesita transferencias: llama SIEMPRE a
 *     usbh_driver_set_config_complete() (si no, la enumeracion de todos los dispositivos se queda
 *     bloqueada) y avisa a la aplicacion con tuh_ufi_mount_cb().
 *
 *  2. Maquina de estados de UNA orden por dispositivo, movida por callbacks:
 *       CBI/CB: ADSC (control 0x21/0, 12 B) -> [datos bulk] -> [interrupt 2 B (solo CBI)] -> done
 *       BOT   : CBW (bulk OUT 31 B)         -> [datos bulk] -> CSW (bulk IN 13 B)          -> done
 *     STALL en un bulk durante los datos: CLEAR_FEATURE(ENDPOINT_HALT) por control + hcd_edpt_clear_stall()
 *     (el QHD del EHCI queda 'halted' y toda transferencia posterior fallaria; nadie en host/ lo limpia)
 *     y se sigue con la fase de estado. STALL al leer el CSW: se limpia y se relee UNA vez (BOT 5.3.3).
 *     CSW con firma/tag malos, bCSWStatus = 2 (phase error) o ADSC/CBW rechazados -> UFI_FAIL: la capa
 *     sincrona hace el reset recovery. Cada callback comprueba que pertenece a la orden en curso
 *     (numero de secuencia en user_data de los controles; etapa != IDLE en los bulk): una orden
 *     abortada por timeout puede dejar completados rancios en la cola de eventos.
 *
 *  3. Capa sincrona (ufi_command, ufi_reset): espera activa con usb_host_poll() y
 *     tusb_time_millis_api(); al vencer el plazo (o si la funcion de ufi_set_cancel() lo pide: fdd.c la
 *     usa para ceder el paso a una peticion de la SD del PL) aborta lo que este en vuelo
 *     (tuh_edpt_abort_xfer: el EHCI no tiene timeout propio y un IN que solo recibe NAK, p.ej. con el
 *     motor arrancando, se queda activo para siempre; OJO: el hcd_edpt_abort_xfer de serie dejaba el
 *     overlay del QH con Active=1 y la transferencia seguia viva -> parcheado en tinyusb-zynq7000.patch)
 *     y vacia la cola de eventos antes de devolver, para que un completado tardio no pise la orden
 *     siguiente. Tras un TIMEOUT/FAIL hace falta ufi_reset() (peor caso ~650 ms): fdd.c lo difiere
 *     al bucle para no agotar los 2 s del PL dentro de una peticion. Durante la espera no corre el resto del bucle principal
 *     (osd/cfg/wavegame/cinta ni otras peticiones del SDBOX): fdd.c acota los plazos (< 2 s del PL).
 *
 * Buffers: todo lo que toca el EHCI va alineado a 32 B (CFG_TUH_MEM_ALIGN) y en la DDR (sin caches,
 * coherente). Sin malloc. Un solo dispositivo por direccion; la disquetera es full-speed
 * (bulk 64 B, interrupt 2 B) y un READ(10) de 16 sectores (8 KB) cabe en un qTD (5 paginas de 4 KB). */
#include "tusb_option.h"
#include "tusb.h"
#include "host/usbh.h"
#include "host/usbh_pvt.h"
#include "host/hcd.h"
#include "class/msc/msc.h"
#include "ufi_host.h"

extern void     usb_host_poll(void);             /* usb_host.c: tuh_int_handler + tuh_task_ext */
extern uint32_t tusb_time_millis_api(void);      /* bsp/support.c: ms reales del temporizador global */
extern void     log_str(const char *s);
extern void     log_dec(uint32_t v);
extern void     log_hex(uint32_t v);

enum { ST_IDLE = 0, ST_CMD, ST_DATA, ST_CLEAR, ST_STATUS, ST_CTRL };

#define ADSC_REQ_TYPE   0x21U        /* host->device, clase, interfaz */
#define ADSC_REQ        0x00U        /* Accept Device-Specific Command */
#define BOT_RESET_REQ   0xFFU        /* Bulk-Only Mass Storage Reset (0x21) */
#define CLEAR_EP_TYPE   0x02U        /* host->device, estandar, endpoint */
#define CBW_LEN         31U
#define CSW_LEN         13U

typedef struct {
    uint8_t used, mounted;
    uint8_t itf_num, subclass, protocol, xport;
    uint8_t ep_in, ep_out, ep_int;
    /* orden en curso */
    volatile uint8_t stage;
    volatile uint8_t done;
    uint8_t  result;                 /* UFI_* */
    uint8_t  dir_in;
    uint8_t  csw_retry;              /* ya se ha releido el CSW tras un STALL */
    uint8_t  stall_ep;               /* endpoint que hizo STALL en los datos (CLEAR_FEATURE en curso) */
    uint8_t  ctrl_result;            /* xfer_result_t del ultimo control sincrono (ST_CTRL) */
    uint8_t *buf;
    uint16_t len;
    uint32_t xferred;
    uint32_t seq;                    /* numero de orden: user_data de los controles */
    uint32_t tag;                    /* dCBWTag (BOT) */
} ufi_dev_t;

typedef struct {
    CFG_TUH_MEM_ALIGN uint8_t cmd[32];       /* ADSC: bloque de orden (12 B UFI, 6/10 SCSI) */
    CFG_TUH_MEM_ALIGN uint8_t cbw[32];       /* msc_cbw_t: 31 B */
    CFG_TUH_MEM_ALIGN uint8_t csw[32];       /* msc_csw_t: 13 B */
    CFG_TUH_MEM_ALIGN uint8_t istat[32];     /* interrupt IN de estado: 2 B */
} ufi_epbuf_t;

static ufi_dev_t   ufi_dev[CFG_TUH_DEVICE_MAX];
static ufi_epbuf_t ufi_buf[CFG_TUH_DEVICE_MAX];

static inline ufi_dev_t *get_dev(uint8_t daddr)
{
    return (daddr >= 1U && daddr <= CFG_TUH_DEVICE_MAX) ? &ufi_dev[daddr - 1U] : NULL;
}
static inline ufi_epbuf_t *get_buf(uint8_t daddr) { return &ufi_buf[daddr - 1U]; }

static void put32le(uint8_t *p, uint32_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24); }
static uint32_t get32le(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

/* ------------------------------------------------------------------ primitivas no bloqueantes */
static void finish(ufi_dev_t *d, uint8_t result)
{
    d->stage = ST_IDLE;
    d->result = result;
    d->done = 1;
}

static uint8_t fail_or_gone(uint8_t daddr) { return tuh_connected(daddr) ? UFI_FAIL : UFI_GONE; }

static bool start_bulk(uint8_t daddr, uint8_t ep, uint8_t *buf, uint16_t len)
{
    if (!usbh_edpt_claim(daddr, ep)) return false;
    if (!usbh_edpt_xfer(daddr, ep, buf, len)) { usbh_edpt_release(daddr, ep); return false; }
    return true;
}

static void ufi_ctrl_cb(tuh_xfer_t *xfer);

/* Control asincrono; el SETUP se copia dentro de TinyUSB, el buffer debe vivir hasta el callback. */
static bool ufi_ctrl(ufi_dev_t *d, uint8_t daddr, uint8_t type, uint8_t req, uint16_t value, uint16_t index,
                     uint8_t *buf, uint16_t length)
{
    tusb_control_request_t const setup = {
        .bmRequestType = type, .bRequest = req,
        .wValue = tu_htole16(value), .wIndex = tu_htole16(index), .wLength = tu_htole16(length)
    };
    tuh_xfer_t x = { .daddr = daddr, .ep_addr = 0, .setup = &setup, .buffer = buf,
                     .complete_cb = ufi_ctrl_cb, .user_data = (uintptr_t)d->seq };
    return tuh_control_xfer(&x);
}

/* Fase de estado: CSW (BOT), interrupt de 2 B (CBI) o nada (CB: un STALL en los datos = orden fallida). */
static void status_stage(uint8_t daddr, ufi_dev_t *d)
{
    ufi_epbuf_t *b = get_buf(daddr);
    if (d->xport == UFI_XPORT_BOT) {
        d->stage = ST_STATUS;
        if (!start_bulk(daddr, d->ep_in, b->csw, CSW_LEN)) finish(d, fail_or_gone(daddr));
    } else if (d->xport == UFI_XPORT_CBI) {
        d->stage = ST_STATUS;
        if (!start_bulk(daddr, d->ep_int, b->istat, 2)) finish(d, fail_or_gone(daddr));
    } else {
        finish(d, d->stall_ep ? UFI_CHECK : UFI_OK);
    }
}

static void start_clear(uint8_t daddr, ufi_dev_t *d, uint8_t ep)
{
    d->stall_ep = ep;
    d->stage = ST_CLEAR;
    if (!ufi_ctrl(d, daddr, CLEAR_EP_TYPE, TUSB_REQ_CLEAR_FEATURE, TUSB_REQ_FEATURE_EDPT_HALT, ep, NULL, 0))
        finish(d, fail_or_gone(daddr));
}

static void data_stage(uint8_t daddr, ufi_dev_t *d)
{
    if (d->len == 0U) { status_stage(daddr, d); return; }
    d->stage = ST_DATA;
    if (!start_bulk(daddr, d->dir_in ? d->ep_in : d->ep_out, d->buf, d->len)) finish(d, fail_or_gone(daddr));
}

static void ufi_ctrl_cb(tuh_xfer_t *xfer)
{
    uint8_t daddr = xfer->daddr;
    ufi_dev_t *d = get_dev(daddr);
    if (d == NULL || !d->used || xfer->user_data != (uintptr_t)d->seq) return;   /* rancio o cerrado */
    if (xfer->result != XFER_RESULT_SUCCESS) {
        log_str("UFI ctrl etapa "); log_dec(d->stage); log_str(" resultado "); log_dec((uint32_t)xfer->result);
        log_str(" req "); log_hex(xfer->setup->bRequest); log_str("\n");
    }
    switch (d->stage) {
    case ST_CMD:                                                  /* ADSC (CBI/CB) */
        if (xfer->result == XFER_RESULT_SUCCESS) data_stage(daddr, d);
        else if (xfer->result == XFER_RESULT_STALLED) finish(d, UFI_CHECK);   /* orden no aceptada */
        else finish(d, fail_or_gone(daddr));
        break;
    case ST_CLEAR:                                                /* CLEAR_FEATURE(ENDPOINT_HALT) */
        hcd_edpt_clear_stall(usbh_get_rhport(daddr), daddr, d->stall_ep);   /* toggle a DATA0 y QHD sin halt */
        if (xfer->result != XFER_RESULT_SUCCESS) { finish(d, fail_or_gone(daddr)); break; }
        status_stage(daddr, d);
        break;
    case ST_CTRL:                                                 /* control de la capa sincrona */
        d->ctrl_result = (uint8_t)xfer->result;
        finish(d, xfer->result == XFER_RESULT_SUCCESS ? UFI_OK : (xfer->result == XFER_RESULT_STALLED ? UFI_CHECK : fail_or_gone(daddr)));
        break;
    default:
        break;
    }
}

bool ufih_xfer_cb(uint8_t daddr, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes)
{
    ufi_dev_t *d = get_dev(daddr);
    ufi_epbuf_t *b;
    if (d == NULL || !d->used) return false;
    b = get_buf(daddr);
    if (result != XFER_RESULT_SUCCESS) {                          /* diagnostico: que fallo y en que etapa */
        log_str("UFI xfer ep "); log_hex(ep_addr); log_str(" etapa "); log_dec(d->stage);
        log_str(" resultado "); log_dec((uint32_t)result); log_str(" bytes "); log_dec(xferred_bytes); log_str("\n");
    }
    switch (d->stage) {
    case ST_CMD:                                                  /* CBW (BOT) */
        if (result == XFER_RESULT_SUCCESS && xferred_bytes == CBW_LEN) data_stage(daddr, d);
        else finish(d, fail_or_gone(daddr));                      /* CBW rechazado/STALL: reset recovery (BOT 6.6.1) */
        break;
    case ST_DATA:
        d->xferred = xferred_bytes;
        if (result == XFER_RESULT_SUCCESS) status_stage(daddr, d);
        else if (result == XFER_RESULT_STALLED) start_clear(daddr, d, ep_addr);
        else finish(d, fail_or_gone(daddr));
        break;
    case ST_STATUS:
        if (d->xport == UFI_XPORT_BOT) {
            if (result == XFER_RESULT_SUCCESS && xferred_bytes == CSW_LEN &&
                get32le(b->csw) == MSC_CSW_SIGNATURE && get32le(b->csw + 4) == d->tag) {
                uint8_t st = b->csw[12];
                finish(d, st == 0U ? UFI_OK : (st == 1U ? UFI_CHECK : UFI_FAIL));
            } else if (result == XFER_RESULT_STALLED && d->csw_retry == 0U) {
                d->csw_retry = 1U;
                start_clear(daddr, d, d->ep_in);                  /* tras el CLEAR se relee el CSW */
            } else {
                finish(d, fail_or_gone(daddr));                   /* CSW invalido o STALL persistente */
            }
        } else {                                                  /* CBI: interrupt de 2 bytes */
            if (result == XFER_RESULT_SUCCESS && xferred_bytes >= 2U) {
                if (d->subclass == MSC_SUBCLASS_SCSI) {           /* bType/bValue: bits 1:0 = estado */
                    uint8_t v = b->istat[1] & 3U;
                    finish(d, v == 0U ? UFI_OK : (v == 1U ? UFI_CHECK : UFI_FAIL));
                } else {                                          /* UFI: ASC, ASCQ; 00 00 = OK */
                    finish(d, (b->istat[0] == 0U && b->istat[1] == 0U) ? UFI_OK : UFI_CHECK);
                }
            } else {
                finish(d, fail_or_gone(daddr));
            }
        }
        break;
    default:
        break;                                                    /* completado rancio de una orden abortada */
    }
    return true;
}

/* ------------------------------------------------------------------ capa sincrona */
static int (*ufi_cancel_fn)(void);                          /* ufi_set_cancel(): la espera se corta si devuelve 1 */
void ufi_set_cancel(int (*fn)(void)) { ufi_cancel_fn = fn; }

static void ufi_abort(uint8_t daddr, ufi_dev_t *d)
{
    uint8_t stage = d->stage;
    ufi_epbuf_t *b = get_buf(daddr);
    d->stage = ST_IDLE;
    d->seq++;                                                     /* callbacks de control rancios: fuera */
    for (int i = 0; i < 12; i++) b->cmd[i] = 0;                   /* si un ADSC quedo en la cola de controles pendientes de
                                                                     TinyUSB y sale mas tarde, que sea un TEST UNIT READY
                                                                     (inocuo) y no el READ/WRITE(10) de la orden abortada */
    if (stage == ST_CLEAR || stage == ST_CTRL || (stage == ST_CMD && d->xport != UFI_XPORT_BOT))
        tuh_edpt_abort_xfer(daddr, 0);                            /* control en vuelo -> callback ABORTED (ignorado) */
    if (d->ep_in  && usbh_edpt_busy(daddr, d->ep_in))  tuh_edpt_abort_xfer(daddr, d->ep_in);
    if (d->ep_out && usbh_edpt_busy(daddr, d->ep_out)) tuh_edpt_abort_xfer(daddr, d->ep_out);
    if (d->ep_int && usbh_edpt_busy(daddr, d->ep_int)) tuh_edpt_abort_xfer(daddr, d->ep_int);
    for (int i = 0; i < 3; i++) usb_host_poll();                  /* vaciar completados ya encolados */
    d->done = 1;
    d->result = UFI_TIMEOUT;
}

/* 1 = done; 0 = timeout (abortado) o dispositivo cerrado durante la espera */
static int ufi_wait(uint8_t daddr, ufi_dev_t *d, uint32_t timeout_ms)
{
    uint32_t t0 = tusb_time_millis_api();
    while (!d->done) {
        usb_host_poll();
        if (!d->used) return 0;
        if ((uint32_t)(tusb_time_millis_api() - t0) > timeout_ms) { ufi_abort(daddr, d); return 0; }
        if (ufi_cancel_fn != NULL && ufi_cancel_fn()) { ufi_abort(daddr, d); return 0; }   /* p.ej. el PL pide la SD */
    }
    return 1;
}

void ufi_delay_ms(uint32_t ms)
{
    uint32_t t0 = tusb_time_millis_api();
    while ((uint32_t)(tusb_time_millis_api() - t0) < ms) usb_host_poll();
}

/* Control sincrono generico (ST_CTRL): reset y clear halt a mano. */
static int ufi_ctrl_sync(uint8_t daddr, ufi_dev_t *d, uint8_t type, uint8_t req, uint16_t value, uint16_t index,
                         uint8_t *buf, uint16_t length, uint32_t timeout_ms)
{
    if (d->stage != ST_IDLE) return UFI_BUSY;
    d->seq++; d->done = 0; d->result = UFI_FAIL; d->stage = ST_CTRL;
    if (!ufi_ctrl(d, daddr, type, req, value, index, buf, length)) { d->stage = ST_IDLE; return UFI_BUSY; }
    if (!ufi_wait(daddr, d, timeout_ms)) return d->used ? UFI_TIMEOUT : UFI_GONE;
    return d->result;
}

static int ufi_clear_halt(uint8_t daddr, ufi_dev_t *d, uint8_t ep)
{
    int r = ufi_ctrl_sync(daddr, d, CLEAR_EP_TYPE, TUSB_REQ_CLEAR_FEATURE, TUSB_REQ_FEATURE_EDPT_HALT, ep, NULL, 0, 100);
    if (d->used) hcd_edpt_clear_stall(usbh_get_rhport(daddr), daddr, ep);
    return r;
}

int ufi_command(uint8_t daddr, const uint8_t *cdb, uint8_t cdb_len, int dir_in,
                uint8_t *buf, uint16_t len, uint32_t timeout_ms, uint32_t *xferred)
{
    ufi_dev_t *d = get_dev(daddr);
    ufi_epbuf_t *b;
    uint8_t clen;
    if (d == NULL || !d->used || !d->mounted) return UFI_GONE;
    if (d->stage != ST_IDLE || cdb_len > 12U) return UFI_BUSY;
    b = get_buf(daddr);
    clen = (d->subclass == MSC_SUBCLASS_SCSI) ? cdb_len : 12U;   /* UFI/SFF: siempre 12 B rellenados con 0 */
    d->seq++; d->done = 0; d->result = UFI_FAIL;
    d->dir_in = (uint8_t)(dir_in ? 1 : 0); d->buf = buf; d->len = len; d->xferred = 0;
    d->csw_retry = 0; d->stall_ep = 0;
    if (xferred) *xferred = 0;
    if (d->xport == UFI_XPORT_BOT) {
        uint8_t *w = b->cbw;
        for (int i = 0; i < 32; i++) w[i] = 0;
        put32le(w, MSC_CBW_SIGNATURE);
        put32le(w + 4, ++d->tag);
        put32le(w + 8, len);
        w[12] = dir_in ? 0x80U : 0x00U;
        w[13] = 0;                                                /* LUN 0 */
        w[14] = clen;
        for (uint8_t i = 0; i < cdb_len; i++) w[15 + i] = cdb[i];
        d->stage = ST_CMD;
        if (!start_bulk(daddr, d->ep_out, w, CBW_LEN)) { d->stage = ST_IDLE; return UFI_BUSY; }
    } else {
        for (int i = 0; i < 12; i++) b->cmd[i] = 0;
        for (uint8_t i = 0; i < cdb_len; i++) b->cmd[i] = cdb[i];
        d->stage = ST_CMD;
        if (!ufi_ctrl(d, daddr, ADSC_REQ_TYPE, ADSC_REQ, 0, d->itf_num, b->cmd, clen)) { d->stage = ST_IDLE; return UFI_BUSY; }
    }
    if (!ufi_wait(daddr, d, timeout_ms)) return d->used ? UFI_TIMEOUT : UFI_GONE;
    if (!d->used) return UFI_GONE;
    if (xferred) *xferred = d->xferred;
    return d->result;
}

int ufi_reset(uint8_t daddr)
{
    ufi_dev_t *d = get_dev(daddr);
    int r;
    if (d == NULL || !d->used) return UFI_GONE;
    if (d->stage != ST_IDLE) return UFI_BUSY;
    if (d->xport == UFI_XPORT_BOT) {
        r = ufi_ctrl_sync(daddr, d, ADSC_REQ_TYPE, BOT_RESET_REQ, 0, d->itf_num, NULL, 0, 300);
    } else {
        /* CBI/CB: la especificacion pide un Command Block Reset (ADSC 1D 04 FF..FF), pero la TEAC FD-05PUB
         * se DESCONECTA del bus al recibirlo (22/09) y vuelve a enumerar en bucle. Se deja solo la limpieza
         * de los endpoints (abajo), que es lo que hace Linux (usb-storage no manda el CBR a las UFI). */
        r = UFI_OK;
    }
    if (!d->used) return UFI_GONE;
    ufi_delay_ms(50);                                             /* que el firmware de la unidad se reponga
                                                                     (peor caso total ~650 ms: cabe en el bucle) */
    if (d->used) ufi_clear_halt(daddr, d, d->ep_in);
    if (d->used) ufi_clear_halt(daddr, d, d->ep_out);
    if (d->used && d->ep_int) ufi_clear_halt(daddr, d, d->ep_int);
    log_str("UFI "); log_dec(daddr); log_str(": reset recovery -> "); log_dec((uint32_t)r); log_str("\n");
    return d->used ? r : UFI_GONE;
}

/* ------------------------------------------------------------------ consultas */
uint8_t ufi_first_daddr(void)
{
    for (uint8_t i = 0; i < CFG_TUH_DEVICE_MAX; i++) if (ufi_dev[i].used && ufi_dev[i].mounted) return (uint8_t)(i + 1U);
    return 0;
}
int     ufi_mounted(uint8_t daddr)   { ufi_dev_t *d = get_dev(daddr); return d != NULL && d->used && d->mounted; }
uint8_t ufi_transport(uint8_t daddr) { ufi_dev_t *d = get_dev(daddr); return (d != NULL && d->used) ? d->xport : UFI_XPORT_NONE; }
uint8_t ufi_subclass(uint8_t daddr)  { ufi_dev_t *d = get_dev(daddr); return (d != NULL && d->used) ? d->subclass : 0; }
const uint8_t *ufi_int_status(uint8_t daddr) { return get_buf(daddr)->istat; }

/* ------------------------------------------------------------------ driver de clase (usbh) */
bool ufih_init(void)
{
    for (int i = 0; i < CFG_TUH_DEVICE_MAX; i++) {
        uint8_t *p = (uint8_t *)&ufi_dev[i];
        for (unsigned k = 0; k < sizeof(ufi_dev_t); k++) p[k] = 0;
    }
    return true;
}

uint16_t ufih_open(uint8_t rhport, uint8_t daddr, tusb_desc_interface_t const *itf, uint16_t max_len)
{
    ufi_dev_t *d;
    uint8_t sub, proto, xport;
    uint8_t ep_in = 0, ep_out = 0, ep_int = 0;
    uint8_t const *p = (uint8_t const *)itf;
    uint16_t pos = 0;
    (void)rhport;
    d = get_dev(daddr);                                           /* el hub (daddr 5) no cabe en las tablas */
    if (d == NULL || itf->bInterfaceClass != TUSB_CLASS_MSC) return 0;
    sub = itf->bInterfaceSubClass; proto = itf->bInterfaceProtocol;
    if (sub != MSC_SUBCLASS_UFI && sub != MSC_SUBCLASS_SFF && sub != MSC_SUBCLASS_SCSI) return 0;   /* RBC/ATAPI/QIC: no */
    if (proto == MSC_PROTOCOL_BOT) {
        if (sub == MSC_SUBCLASS_SCSI && !UFI_CLAIM_SCSI_BOT) return 0;   /* se lo queda msc_host */
        xport = UFI_XPORT_BOT;
    } else if (proto == MSC_PROTOCOL_CBI) xport = UFI_XPORT_CBI;
    else if (proto == MSC_PROTOCOL_CBI_NO_INTERRUPT) xport = UFI_XPORT_CB;
    else return 0;
    if (d->used) return 0;                                        /* segunda interfaz MSC del mismo dispositivo: no */

    /* endpoints hasta la siguiente interfaz (puede haber descriptores de clase intercalados) */
    while (pos < max_len) {
        if (pos > 0 && tu_desc_type(p) == TUSB_DESC_INTERFACE) break;
        if (tu_desc_type(p) == TUSB_DESC_ENDPOINT) {
            tusb_desc_endpoint_t const *ep = (tusb_desc_endpoint_t const *)p;
            uint8_t xfer = ep->bmAttributes.xfer;
            if (xfer == TUSB_XFER_BULK && !ep_in && tu_edpt_dir(ep->bEndpointAddress) == TUSB_DIR_IN) {
                if (tuh_edpt_open(daddr, ep)) ep_in = ep->bEndpointAddress;
            } else if (xfer == TUSB_XFER_BULK && !ep_out && tu_edpt_dir(ep->bEndpointAddress) == TUSB_DIR_OUT) {
                if (tuh_edpt_open(daddr, ep)) ep_out = ep->bEndpointAddress;
            } else if (xfer == TUSB_XFER_INTERRUPT && !ep_int && tu_edpt_dir(ep->bEndpointAddress) == TUSB_DIR_IN
                       && xport == UFI_XPORT_CBI) {
                if (ep->bInterval != 0U && tuh_edpt_open(daddr, ep)) ep_int = ep->bEndpointAddress;
            }
        }
        pos = (uint16_t)(pos + tu_desc_len(p));
        p = tu_desc_next(p);
    }
    if (!ep_in || !ep_out) return 0;
    if (xport == UFI_XPORT_CBI && !ep_int) xport = UFI_XPORT_CB; /* sin interrupt utilizable: estado por REQUEST SENSE */

    d->used = 1; d->mounted = 0;
    d->itf_num = itf->bInterfaceNumber; d->subclass = sub; d->protocol = proto; d->xport = xport;
    d->ep_in = ep_in; d->ep_out = ep_out; d->ep_int = ep_int;
    d->stage = ST_IDLE; d->done = 1; d->result = UFI_OK; d->seq = 0; d->tag = 0x46444431U;   /* 'FDD1' */
    log_str("UFI "); log_dec(daddr); log_str(": interfaz "); log_dec(d->itf_num); log_str(" subclase ");
    log_dec(sub); log_str(" protocolo "); log_hex(proto); log_str(" -> transporte "); log_dec(xport);
    log_str(" (in "); log_hex(ep_in); log_str(" out "); log_hex(ep_out); log_str(" int "); log_hex(ep_int); log_str(")\n");
    return pos;
}

bool ufih_set_config(uint8_t daddr, uint8_t itf_num)
{
    ufi_dev_t *d = get_dev(daddr);
    if (d != NULL && d->used && d->itf_num == itf_num) {
        d->mounted = 1;
        tuh_ufi_mount_cb(daddr);                                  /* fdd.c solo toma nota; sondea desde el bucle */
    }
    usbh_driver_set_config_complete(daddr, itf_num);              /* SIEMPRE: si no se bloquea la enumeracion */
    return true;
}

void ufih_close(uint8_t daddr)
{
    ufi_dev_t *d = get_dev(daddr);
    if (d == NULL || !d->used) return;
    if (d->mounted) tuh_ufi_umount_cb(daddr);
    d->used = 0; d->mounted = 0;
    d->stage = ST_IDLE; d->result = UFI_GONE; d->done = 1;        /* una espera en curso sale con GONE */
}
