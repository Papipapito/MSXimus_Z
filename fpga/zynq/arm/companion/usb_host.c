/* usb_host.c — USB host del companion (Zynq USB0 + PHY USB3320C por ULPI) con
 * TinyUSB: hub + HID + XInput + disquetera (ufi_host.c/fdd.c). Teclado, raton y mandos llegan
 * al MSX por el buzon HID de la DDR (MBOX 0x1FF00000) que el PL (dbg_mailbox_axi) lee cada ~1 ms:
 *   +0x00 .. +0x0F : bitmap de 128 bits, bit = usage HID (modificadores en 104+i),
 *                    el mismo formato que usb_kbd_decode.v (y que tools/key.tcl)
 *   +0x10 : joy1[15:0] | joy2[31:16]  formato SNES del companion BL616 (comando 9):
 *           bit 11 R, 10 L, 9 X, 8 A, 7 RT, 6 LT, 5 DOWN, 4 UP, 3 START, 2 SEL, 1 Y, 0 B
 *   +0x14 : mouse_btn[7:0] | mouse_seq[15:8]
 *   +0x18 : mouse_ax[15:0] | mouse_ay[31:16]  (acumulados, int16 con desbordamiento;
 *           el PL saca el delta entre dos lecturas: no se pierde movimiento)
 * Teclado + raton por protocolo boot; mandos genericos por descriptor HID (hid_pad.c). */
#include "tusb.h"
#include "xil_types.h"
#include "log.h"
#include "sleep.h"
#include "hid_pad.h"
#include "portable/ehci/ehci_api.h"                         /* ehci_split_signature (parche de TinyUSB) */
#include "usb_vigila.h"

#define MBOX        0x1FF00000u
#define GPIO_BASE   0xE000A000u
#define GPIO_DATA_1 (*(volatile u32 *)(GPIO_BASE + 0x044u))
#define GPIO_DIRM_1 (*(volatile u32 *)(GPIO_BASE + 0x244u))
#define GPIO_OEN_1  (*(volatile u32 *)(GPIO_BASE + 0x248u))
#define PHY_RST_BIT (1u << (46 - 32))                       /* USBPHY_nRSET = MIO 46 (banco 1) */
#define USB0_ULPI   (*(volatile u32 *)0xE0002170u)          /* ULPI_VIEWPORT */
#define USB0_PORTSC (*(volatile u32 *)0xE0002184u)
#define USB0_USBMODE (*(volatile u32 *)0xE00021A8u)

static volatile u32 * const mbox = (volatile u32 *)MBOX;
u32 usb_stats_mount, usb_stats_reports;
u32 usb_stats_reinicios;                                    /* veces que el vigilante (o JTAG) ha reiniciado la pila USB (1/11; osd_info.c) */
u32 usb_n_kbd, usb_n_mouse, usb_n_pad;                      /* interfaces HID montadas (osd.c) */
volatile u32 osd_hotkey;                                    /* pulsaciones de F12 (osd.c las cuenta) */
volatile u8  osd_teclas[16];                                /* 30/09: anillo de pulsaciones (uso HID) para el OSD */
volatile u32 osd_teclas_wr;

/* 30/09: que hay conectado AHORA, por dispositivo (la pagina de informacion del OSD): bit 0 teclado, 1 raton, 2 mando,
 * 3 disco (MSC: disquetera o memoria). Los hubs son las direcciones de mas de CFG_TUH_DEVICE_MAX (usbh.c). Los montajes
 * de clase (HID, MSC, XInput) llegan ANTES que tuh_mount_cb: el tipo se borra al quitar el dispositivo, no al montarlo. */
#define USB_DIRS (CFG_TUH_DEVICE_MAX + CFG_TUH_HUB + 1)
static u8 dev_vivo[USB_DIRS], dev_tipo[USB_DIRS];
static void dev_marca(u8 dev, u8 bit) { if (dev < USB_DIRS) dev_tipo[dev] |= bit; }

void usb_resumen(u32 *n_disp, u32 t[6])                    /* t: teclados, ratones, mandos, discos, hubs, otros */
{
    u32 d, k;
    *n_disp = 0;
    for (k = 0; k < 6U; k++) t[k] = 0;
    for (d = 1; d < USB_DIRS; d++) {
        if (!dev_vivo[d]) continue;
        (*n_disp)++;
        if (d > CFG_TUH_DEVICE_MAX) { t[4]++; continue; }
        for (k = 0; k < 4U; k++) if (dev_tipo[d] & (1u << k)) t[k]++;
        if (!dev_tipo[d]) t[5]++;
    }
}

/* ---------------- ULPI viewport ---------------- */
static int ulpi_wait_run(void)
{
    for (u32 i = 0; i < 100000u; i++) if ((USB0_ULPI & (1u << 30)) == 0u) return 1;
    return 0;
}
static int ulpi_write(u8 addr, u8 data)
{
    USB0_ULPI = (1u << 30) | (1u << 29) | ((u32)addr << 16) | data;
    return ulpi_wait_run();
}
static int ulpi_read(u8 addr, u8 *data)
{
    USB0_ULPI = (1u << 30) | ((u32)addr << 16);
    if (!ulpi_wait_run()) return 0;
    *data = (u8)(USB0_ULPI >> 8);
    return 1;
}

/* Gancho de hcd_init (CI_HS_SET_AHB_BURST): tras el reset del controlador y
 * USBMODE=host, antes de ehci_init. */
void zynq_usb_pre_ehci(void)
{
    u32 p = USB0_PORTSC & ~0x2Au;                            /* sin los bits W1C */
    USB0_PORTSC = (p & ~(3u << 30)) | (2u << 30);            /* PTS = ULPI, 8 bits */
    USB0_ULPI = 1u << 31;                                    /* despertar el PHY */
    for (u32 i = 0; i < 100000u; i++) if ((USB0_ULPI & (1u << 31)) == 0u) break;
    u8 id0 = 0, id1 = 0;
    ulpi_read(0x00, &id0);                                   /* la primera transaccion tras despertar el viewport devuelve 0 */
    ulpi_read(0x00, &id0); ulpi_read(0x01, &id1);            /* USB3320: 0x0424 (Microchip/SMSC) */
    log_str("ULPI PHY id "); log_hex(((u32)id1 << 8) | id0); log_str("\n");
    /* (22/09: se probo un ciclo de VBUS aqui para despertar un hub mudo; no sirve, en esta placa el 5 V
     * del USB-A no lo gobierna el PHY (VbusValid=0, CPEN sin efecto). El hub "mudo" era el propio EHCI
     * colgado por el reentrenamiento de la DDR con su DMA en vuelo: lo arregla boot.tcl parando el
     * USB0 antes de ps7_init.) */
    ulpi_write(0x0B, 0x60);                                  /* OTG Control SET: DrvVbus + DrvVbusExternal (CPEN) */
    ulpi_write(0x0B, 0x06);                                  /* DpPulldown + DmPulldown (host) */
}

static void phy_reset(void)
{
    /* ps7_init no toca MIO_PIN_46 (queda en reset: tri-state): ponerlo como GPIO LVCMOS18 salida */
    *(volatile u32 *)0xF8000008u = 0xDF0Du;                  /* SLCR unlock */
    *(volatile u32 *)0xF80007B8u = 0x00000200u;              /* MIO_PIN_46: GPIO, LVCMOS18, sin tri-state */
    *(volatile u32 *)0xF8000004u = 0x767Bu;                  /* SLCR lock */
    GPIO_DIRM_1 |= PHY_RST_BIT; GPIO_OEN_1 |= PHY_RST_BIT;
    GPIO_DATA_1 &= ~PHY_RST_BIT; usleep(20000);              /* RESETB bajo 20 ms */
    GPIO_DATA_1 |=  PHY_RST_BIT; usleep(50000);              /* el PHY arranca su CLKOUT de 60 MHz */
}

/* ---------------- estado HID -> buzon ---------------- */
#define MAX_KBD 4
static struct { u8 dev, idx, used; u32 bits[4]; } kbd[MAX_KBD];
static u32 kbd_or[4];
static u8  mouse_btn, mouse_seq;
static u8  f12_prev;                                       /* F12 estaba pulsada en el ultimo informe de teclado */
static s16 mouse_ax, mouse_ay;
static u16 joy[2];

static u32 kbd_synth[4];                                  /* Z1.1: teclas "de mentira" (tape.c: SHIFT al arrancar, RUN"CAS:") */
static void mbox_kbd_flush(void)
{
    u32 acc[4] = {kbd_synth[0], kbd_synth[1], kbd_synth[2], kbd_synth[3]};
    for (int k = 0; k < MAX_KBD; k++) if (kbd[k].used) for (int w = 0; w < 4; w++) acc[w] |= kbd[k].bits[w];
    for (int w = 0; w < 4; w++) { kbd_or[w] = acc[w]; mbox[w] = acc[w]; }
    dsb();
}
void kbd_synth_set(const u32 b[4])
{
    for (int w = 0; w < 4; w++) kbd_synth[w] = b[w];
    mbox_kbd_flush();
}
static void mbox_misc_flush(void)
{
    mbox[4] = (u32)joy[0] | ((u32)joy[1] << 16);
    mbox[5] = (u32)mouse_btn | ((u32)mouse_seq << 8);
    mbox[6] = ((u32)(u16)mouse_ax) | ((u32)(u16)mouse_ay << 16);
    dsb();
}
static void kbd_set(u32 *bits, u32 usage) { if (usage < 128u) bits[usage >> 5] |= 1u << (usage & 31u); }

static void on_keyboard(u8 dev, u8 idx, const hid_keyboard_report_t *r)
{
    int slot = -1;
    for (int k = 0; k < MAX_KBD; k++) if (kbd[k].used && kbd[k].dev == dev && kbd[k].idx == idx) slot = k;
    if (slot < 0) for (int k = 0; k < MAX_KBD; k++) if (!kbd[k].used) { slot = k; kbd[k].used = 1; kbd[k].dev = dev; kbd[k].idx = idx; break; }
    if (slot < 0) return;
    u32 b[4] = {0, 0, 0, 0};
    u8 f12 = 0;
    for (int i = 0; i < 8; i++) if (r->modifier & (1u << i)) kbd_set(b, 104u + (u32)i);
    for (int i = 0; i < 6; i++) if (r->keycode[i] > 3u) { kbd_set(b, r->keycode[i]); if (r->keycode[i] == 69u) f12 = 1; }
    for (int i = 0; i < 6; i++) {                          /* 30/09: pulsaciones nuevas -> teclas del OSD (osd.c/ota.c) */
        u32 u = r->keycode[i];
        if (u > 3u && u < 128u && !(kbd[slot].bits[u >> 5] & (1u << (u & 31u)))) { osd_teclas[osd_teclas_wr & 15u] = (u8)u; osd_teclas_wr++; }
    }
    if (f12 && !f12_prev) osd_hotkey++;                    /* F12: pagina de informacion (osd.c) */
    f12_prev = f12;
    for (int w = 0; w < 4; w++) kbd[slot].bits[w] = b[w];
    mbox_kbd_flush();
}

static void on_mouse(const hid_mouse_report_t *r)
{
    mouse_btn = r->buttons;
    mouse_ax = (s16)(mouse_ax + r->x);
    mouse_ay = (s16)(mouse_ay + r->y);
    mouse_seq++;
    mbox_misc_flush();
}

/* ---------------- callbacks de TinyUSB ---------------- */
void tuh_mount_cb(uint8_t daddr)
{
    uint16_t vid = 0, pid = 0;
    usb_stats_mount++;
    if (daddr < USB_DIRS) dev_vivo[daddr] = 1;
    tuh_vid_pid_get(daddr, &vid, &pid);
    log_str("USB: dispositivo "); log_dec(daddr); log_str(" montado, VID:PID "); log_hex(((u32)vid << 16) | pid);
    log_str(", interfaces HID "); log_dec(tuh_hid_itf_get_count(daddr)); log_str("\n");
}
void tuh_umount_cb(uint8_t daddr)
{
    if (daddr < USB_DIRS) { dev_vivo[daddr] = 0; dev_tipo[daddr] = 0; }
    log_str("USB: dispositivo "); log_dec(daddr); log_str(" quitado\n");
}

void tuh_hid_mount_cb(uint8_t dev, uint8_t idx, const uint8_t *desc_report, uint16_t desc_len)
{
    u8 proto = tuh_hid_interface_protocol(dev, idx);
    log_str("HID "); log_dec(dev); log_str("/"); log_dec(idx); log_str(": ");
    log_str(proto == HID_ITF_PROTOCOL_KEYBOARD ? "teclado" : proto == HID_ITF_PROTOCOL_MOUSE ? "raton" : "generico");
    if (proto == HID_ITF_PROTOCOL_KEYBOARD) { usb_n_kbd++; dev_marca(dev, 1u); }
    else if (proto == HID_ITF_PROTOCOL_MOUSE) { usb_n_mouse++; dev_marca(dev, 2u); }
    if (proto == HID_ITF_PROTOCOL_NONE) {                    /* mando? (descriptor: ejes/hat/botones) */
        int pl = hid_pad_mount(dev, idx, desc_report, desc_len);
        if (pl >= 0) { usb_n_pad++; dev_marca(dev, 4u); log_str(" -> mando jugador "); log_dec((u32)pl + 1u); }
        else log_str(" (sin ejes ni botones, o ya hay 2 mandos)");
        /* DualShock 4 y sus clones (054C:05C4/09CC): muchos no transmiten hasta que el host
         * lee el informe de calibracion (feature 0x02, 37 B) */
        if (pl >= 0) {
            uint16_t vid = 0, pid = 0;
            tuh_vid_pid_get(dev, &vid, &pid);
            if (vid == 0x054Cu) {
                static u8 ds4_feat[64];
                log_str(" [DS4: pido feature 02]");
                if (!tuh_hid_get_report(dev, idx, 0x02, HID_REPORT_TYPE_FEATURE, ds4_feat, 37)) log_str(" (fallo)");
            }
        }
    }
    log_str("\n");
    if (!tuh_hid_receive_report(dev, idx)) log_str("HID: no se pudo pedir el primer informe\n");
}

void tuh_hid_get_report_complete_cb(uint8_t dev, uint8_t idx, uint8_t report_id, uint8_t report_type, uint16_t len)
{
    (void)report_type;
    log_str("HID "); log_dec(dev); log_str("/"); log_dec(idx); log_str(": feature "); log_hex(report_id);
    log_str(" recibido, "); log_dec(len); log_str(" B\n");
    tuh_hid_receive_report(dev, idx);                        /* por si el IN no estaba en vuelo */
}

void tuh_hid_umount_cb(uint8_t dev, uint8_t idx)
{
    int pl;
    u8 proto = tuh_hid_interface_protocol(dev, idx);
    if (proto == HID_ITF_PROTOCOL_KEYBOARD && usb_n_kbd) usb_n_kbd--;
    else if (proto == HID_ITF_PROTOCOL_MOUSE && usb_n_mouse) usb_n_mouse--;
    for (int k = 0; k < MAX_KBD; k++) if (kbd[k].used && kbd[k].dev == dev && kbd[k].idx == idx) { kbd[k].used = 0; mbox_kbd_flush(); }
    if ((pl = hid_pad_umount(dev, idx)) >= 0) { joy[pl] = 0; mbox_misc_flush(); if (usb_n_pad) usb_n_pad--; }
    log_str("HID "); log_dec(dev); log_str("/"); log_dec(idx); log_str(" quitado\n");
}

void tuh_hid_report_received_cb(uint8_t dev, uint8_t idx, const uint8_t *report, uint16_t len)
{
    u8 proto = tuh_hid_interface_protocol(dev, idx);
    usb_stats_reports++;
    if (proto == HID_ITF_PROTOCOL_KEYBOARD && len >= 8) on_keyboard(dev, idx, (const hid_keyboard_report_t *)report);
    else if (proto == HID_ITF_PROTOCOL_MOUSE && len >= 3) on_mouse((const hid_mouse_report_t *)report);
    else {                                                   /* generico: mando (hid_pad.c) */
        uint16_t w; int pl = hid_pad_report(dev, idx, report, len, &w);
        if (pl >= 0 && joy[pl] != w) { joy[pl] = w; mbox_misc_flush(); }
    }
    tuh_hid_receive_report(dev, idx);
}

/* ---------------- drivers de clase propios: mandos XInput + disquetera UFI ----------------
 * TinyUSB pide los drivers extra con usbh_app_driver_get_cb: UN array contiguo y persistente, que se
 * consulta ANTES que los drivers de serie (CDC/MSC/HID/HUB). Copiar usbh_xinput_driver en un
 * inicializador estatico no es una expresion constante en C: se nombran sus funciones (globales).
 *   [0] XInput: mandos Xbox y genericos con dongle (clase 0xFF, no HID), driver de Ryzee119/tusb_xinput
 *       (xinput/, MIT). Misma palabra SNES que hid_pad.c; jugador = primer hueco.
 *   [1] UFI: disqueteras USB (clase 08, subclase 04/05 con CBI/CB/BOT, y 06/BOT: ufi_host.c). Va por
 *       delante del msc_host de TinyUSB, que con una disquetera sin disco se queda en un bucle
 *       TEST UNIT READY / REQUEST SENSE y bloquea la enumeracion de todo el hub. Los mount/umount
 *       van a fdd.c, que solo toma nota (estamos dentro de tuh_task_ext) y sondea desde el bucle. */
#include "xinput_host.h"
#include "ufi_host.h"
#include "fdd.h"
#define XI_TRACE 0                                           /* 1 = volcar el paquete crudo al anillo cada ~1 s */

extern bool     xinputh_init(void);                          /* xinput_host.c (globales, sin cabecera) */
extern uint16_t xinputh_open(uint8_t rhport, uint8_t dev_addr, tusb_desc_interface_t const *desc_itf, uint16_t max_len);
extern bool     xinputh_set_config(uint8_t dev_addr, uint8_t itf_num);
extern bool     xinputh_xfer_cb(uint8_t dev_addr, uint8_t ep_addr, xfer_result_t result, uint32_t xferred_bytes);
extern void     xinputh_close(uint8_t dev_addr);

static usbh_class_driver_t const app_drivers[2] = {
    { .name = "XINPUT", .init = xinputh_init, .deinit = NULL, .open = xinputh_open,
      .set_config = xinputh_set_config, .xfer_cb = xinputh_xfer_cb, .close = xinputh_close },
    { .name = "UFI",    .init = ufih_init,    .deinit = NULL, .open = ufih_open,
      .set_config = ufih_set_config,    .xfer_cb = ufih_xfer_cb,    .close = ufih_close },
};

usbh_class_driver_t const *usbh_app_driver_get_cb(uint8_t *driver_count)
{
    *driver_count = 2;
    return app_drivers;
}

/* disquetera: ufi_host.c (propio) y msc_host (TinyUSB, subclase 06/BOT si UFI_CLAIM_SCSI_BOT = 0) -> fdd.c */
void tuh_ufi_mount_cb(uint8_t daddr)  { fdd_ufi_mount(daddr); }
void tuh_ufi_umount_cb(uint8_t daddr) { fdd_ufi_umount(daddr); }
#if CFG_TUH_MSC
void tuh_msc_mount_cb(uint8_t daddr)  { dev_marca(daddr, 8u); fdd_msc_mount(daddr); }
void tuh_msc_umount_cb(uint8_t daddr) { fdd_msc_umount(daddr); }
#endif

static struct { u8 used, dev, inst; } xi[2];

static u16 xinput_to_snes(const xinput_gamepad_t *p)
{
    u16 b = p->wButtons, w = 0;
    if ((b & XINPUT_GAMEPAD_DPAD_UP)    || p->sThumbLY >  16000) w |= 1u << 4;
    if ((b & XINPUT_GAMEPAD_DPAD_DOWN)  || p->sThumbLY < -16000) w |= 1u << 5;
    if ((b & XINPUT_GAMEPAD_DPAD_LEFT)  || p->sThumbLX < -16000) w |= 1u << 6;
    if ((b & XINPUT_GAMEPAD_DPAD_RIGHT) || p->sThumbLX >  16000) w |= 1u << 7;
    if (b & XINPUT_GAMEPAD_A)              w |= 1u << 8;
    if (b & XINPUT_GAMEPAD_B)              w |= 1u << 0;
    if (b & XINPUT_GAMEPAD_X)              w |= 1u << 9;
    if (b & XINPUT_GAMEPAD_Y)              w |= 1u << 1;
    if (b & XINPUT_GAMEPAD_LEFT_SHOULDER)  w |= 1u << 10;
    if (b & XINPUT_GAMEPAD_RIGHT_SHOULDER) w |= 1u << 11;
    if (b & XINPUT_GAMEPAD_BACK)           w |= 1u << 2;
    if (b & XINPUT_GAMEPAD_START)          w |= 1u << 3;
    return w;
}

static int xi_find(u8 dev, u8 inst)
{
    for (int k = 0; k < 2; k++) if (xi[k].used && xi[k].dev == dev && xi[k].inst == inst) return k;
    return -1;
}

void tuh_xinput_mount_cb(uint8_t dev, uint8_t inst, const xinputh_interface_t *itf)
{
    int k = -1;
    for (int i = 0; i < 2; i++) if (!xi[i].used) { k = i; break; }
    log_str("XInput "); log_dec(dev); log_str("/"); log_dec(inst); log_str(" tipo "); log_dec(itf->type);
    if (k < 0) { log_str(": ya hay 2 mandos\n"); return; }
    xi[k].used = 1; xi[k].dev = dev; xi[k].inst = inst;
    usb_n_pad++; dev_marca(dev, 4u);
    log_str(" -> mando jugador "); log_dec((u32)k + 1u); log_str("\n");
    tuh_xinput_set_led(dev, inst, (uint8_t)(k + 1), false);
    tuh_xinput_receive_report(dev, inst);
}

void tuh_xinput_umount_cb(uint8_t dev, uint8_t inst)
{
    int k = xi_find(dev, inst);
    if (k >= 0) { xi[k].used = 0; joy[k] = 0; mbox_misc_flush(); if (usb_n_pad) usb_n_pad--; }
    log_str("XInput "); log_dec(dev); log_str("/"); log_dec(inst); log_str(" quitado\n");
}

void tuh_xinput_report_received_cb(uint8_t dev, uint8_t inst, xinputh_interface_t const *itf, uint16_t len)
{
    (void)len;
    static u32 dbg_n;
    int k = xi_find(dev, inst);
    usb_stats_reports++;
    if (k >= 0 && itf->connected && itf->new_pad_data) {
        u16 w = xinput_to_snes(&itf->pad);
        if (joy[k] != w) { joy[k] = w; mbox_misc_flush(); }
    }
    if (XI_TRACE && (++dbg_n % 500u) == 0u) {                /* traza de bring-up: estado crudo cada ~1 s */
        log_str("XI con="); log_dec(itf->connected); log_str(" new="); log_dec(itf->new_pad_data);
        log_str(" btn="); log_hex(itf->pad.wButtons); log_str(" LX="); log_dec((u32)(u16)itf->pad.sThumbLX);
        log_str(" LY="); log_dec((u32)(u16)itf->pad.sThumbLY); log_str(" len="); log_dec(len); log_str(" raw=");
        for (int i = 0; i < 12; i++) { log_hex(itf->epin_buf[i] | 0x100u); log_str(" "); }   /* 1xx = byte */
        log_str("\n");
    }
    tuh_xinput_receive_report(dev, inst);
}

/* ---------------- API para main ---------------- */
static vigila_t vig;                                         /* vigilante del EHCI (usb_vigila.c) */
static u8 usb_activo;                                        /* la pila USB esta arrancada */

/* 22/09: reset del controlador USB0 desde el SLCR (USB_RST_CTRL bit 0) antes del PHY: un reinicio
 * del PS por JTAG (boot.tcl) no lo toca y el EHCI arranca con el estado de la sesion anterior.
 * (No cura un EHCI colgado por el DDRC: eso lo evita boot.tcl parandolo antes de ps7_init.)
 * 1/11: es tambien lo que saca de verdad a un EHCI colgado (usb_reinicia): lo deja con USBCMD = 0 y el DMA parado. */
static void usb0_reset(void)
{
    *(volatile u32 *)0xF8000008u = 0xDF0Du;                  /* SLCR unlock */
    *(volatile u32 *)0xF8000210u = 0x00000001u;              /* USB0_CPU1X_RST */
    usleep(1000);
    *(volatile u32 *)0xF8000210u = 0x00000000u;
    *(volatile u32 *)0xF8000004u = 0x767Bu;                  /* SLCR lock */
    usleep(1000);
}

static int usb_arranca(void)
{
    usb0_reset();
    phy_reset();
    tuh_hid_set_default_protocol(HID_PROTOCOL_BOOT);
    tusb_rhport_init_t rh = { .role = TUSB_ROLE_HOST, .speed = TUSB_SPEED_AUTO };
    usb_activo = 0;
    if (!tusb_rhport_init(0, &rh)) { log_str("USB: tusb_rhport_init FALLO\n"); return 0; }
    usb_activo = 1;
    vigila_inicia(&vig, tusb_time_millis_api());
    log_str("USB host: OK (PORTSC "); log_hex(USB0_PORTSC); log_str(")\n");
    return 1;
}

int usb_host_init(void)
{
    for (int w = 0; w < 7; w++) mbox[w] = 0;
    return usb_arranca();
}

void usb_host_poll(void)
{
    static u32 t_rescan;
    u32 t = tusb_time_millis_api();
    tuh_int_handler(0, false);
    if (tuh_inited() && (u32)(t - t_rescan) >= 8u) {         /* 1/11/2026: red contra un USBINT perdido (ehci.c, parche): */
        t_rescan = t;                                        /* repasar los QH aunque no haya aviso; sin nada retirado no hace nada */
        ehci_rescan(0);
    }
    tuh_task_ext(0, false);
}

/* ---------------- vigilante del EHCI (1/11/2026) ----------------
 * Tras horas encendida el EHCI se cuelga: su motor periodico se para (los QH con split dejan de avanzar), USBCMD.RS = 0 y
 * PSE = 0 no hacen efecto y ni reconectando el teclado o el hub vuelve nada; solo el reset de USB0 por el SLCR lo saca. Cada
 * ~500 ms se mira ehci_split_signature() (tinyusb ehci.c); la decision es de usb_vigila.c (ver su cabecera, con el limite:
 * sin QH con split activos no se decide nada). Al colgarse se reinicia toda la pila: se sueltan las teclas, el raton y los
 * mandos del buzon, tuh_deinit(0) (cierra los dispositivos con sus umount: hid_pad, XInput, UFI/fdd) y usb_arranca() (reset
 * de USB0 y del PHY como al encender: el hub se vuelve a enumerar entero). Los drivers propios (XInput, UFI) no tienen deinit:
 * usbh solo llama al deinit de los que lo tienen y ambos limpian su estado en init. Desde JTAG se fuerza escribiendo
 * USB_FORZAR_MAGIA en USB_FORZAR (tools/usbreset.tcl); el companion la pone a cero al atenderla. */
#define USB0_FRINDEX     (*(volatile u32 *)0xE000214Cu)
#define USB_FORZAR       (*(volatile u32 *)0x1FF00FF0u)      /* MBOX+0xFF0: tras el log (acaba en +0xF08) y antes de la traza del PL (+0x1000) */
#define USB_FORZAR_MAGIA 0x52425355u                         /* 'USBR' */

static void usb_reinicia(const char *motivo)
{
    u32 t0 = tusb_time_millis_api();
    usb_stats_reinicios++;
    log_str("USB: "); log_str(motivo); log_str(" ("); log_dec(usb_stats_reinicios); log_str("), reinicio del controlador\n");

    /* 1. que el MSX no se quede con una tecla, un boton o un mando pulsados (el raton conserva sus acumulados: el PL saca el delta) */
    for (int k = 0; k < MAX_KBD; k++) { kbd[k].used = 0; for (int w = 0; w < 4; w++) kbd[k].bits[w] = 0; }
    mbox_kbd_flush();
    joy[0] = joy[1] = 0; mouse_btn = 0; mouse_seq++;
    mbox_misc_flush();

    /* 2. primero el reset de USB0 (el DMA de un EHCI colgado deja de leer las listas que se van a deshacer) y luego la pila:
     * tuh_deinit cierra los dispositivos con sus umount_cb; ehci_deinit espera con tope (tras el reset HCHalted puede no verse) */
    usb0_reset();
    tuh_deinit(0);

    /* 3. el estado propio, por si algun dispositivo no pasara por su umount */
    for (int d = 0; d < USB_DIRS; d++) { dev_vivo[d] = 0; dev_tipo[d] = 0; }
    usb_n_kbd = usb_n_mouse = usb_n_pad = 0;
    for (int k = 0; k < 2; k++) xi[k].used = 0;
    f12_prev = 0;
    hid_pad_reset();
    mbox_kbd_flush(); mbox_misc_flush();                     /* (los umount_cb ya habran publicado; esto deja el buzon limpio) */

    /* 4. de nuevo como al encender (otro reset de USB0, el del PHY y tusb_rhport_init) */
    usb_arranca();
    vigila_reiniciado(&vig, tusb_time_millis_api());
    log_str("USB: reinicio hecho en "); log_dec((u32)(tusb_time_millis_api() - t0)); log_str(" ms\n");
}

void usb_host_vigila(void)
{
    u32 ahora = tusb_time_millis_api(), n = 0, firma;
    if (USB_FORZAR == USB_FORZAR_MAGIA) {                    /* tools/usbreset.tcl */
        USB_FORZAR = 0;
        usb_reinicia("forzado por JTAG");
        return;
    }
    if (!usb_activo || !vigila_toca(&vig, ahora)) return;
    firma = ehci_split_signature(&n);
    if (vigila_muestra(&vig, ahora, firma, n, USB0_FRINDEX)) usb_reinicia("EHCI colgado");
}
