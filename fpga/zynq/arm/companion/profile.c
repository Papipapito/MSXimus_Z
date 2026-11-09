/* profile.c — carga de un bitstream del PL por PCAP desde el companion, con el PS vivo (30/10/2026, fase 4 del estudio
 * de perfiles: el estudio interno de perfiles, apartado 6.5).
 *
 * La secuencia es la del gestor de FPGA de Linux (drivers/fpga/zynq-fpga.c) y UG585 cap. 6, con el driver devcfg de
 * Xilinx (fsbl/devcfg/, el mismo del FSBL):
 *   1. comprobar el bitstream y que nadie use el PL (OTA, la S3 por la UART1): hasta aqui nada se ha tocado y un
 *      error se devuelve (PF_E_*);
 *   2. parar lo que habla con el PL: WaveGame, cinta, MSX_RUN = 0;
 *   3. aislar el PL: FPGA_RST_CTRL en reset (los backends de memoria drenan), LVL_SHFTR_EN a solo PS->PL;
 *   4. PROG_B (init del PL), DMA de la PCAP desde la DDR, esperar PCFG_DONE;
 *   5. abrir los desplazadores, soltar los resets y esperar a que el buzon del PL nuevo conteste (magia 'MBOX');
 *   6. volver a sembrar lo que sembraba el arranque (pl_resembra, main.c) y soltar el MSX; despues, UART/OLED/ESP.
 * Si algo falla desde el paso 3: informe en la zona de la prueba, log y reinicio del PS (ota_reinicia_ps): el BootROM
 * vuelve a cargar el perfil 1 desde la QSPI o la SD. Con SW1 en JTAG no hay BootROM que cargue nada: el PS se queda parado.
 *
 * Quien toca el PL desde el companion (auditoria 30/10): NADIE por AXI GP (no hay un solo acceso a 0x4xxxxxxx..0xBxxxxxxx).
 * Habla con el PL por (a) la DDR (buzon, SDBOX/SDBUF, anillos del WaveGame, de la cinta y del V9990) y (b) EMIO: UART0
 * (OSD), UART1 (ESP/S3) y GPIO (OLED), mas IRQ_F2P[0] solo para despertar el WFI. Todo el companion corre en un solo
 * hilo con las interrupciones enmascaradas: mientras esta funcion tiene el control no se ejecuta NINGUN poll (usb, osd,
 * wg, tape, fdd, net, esp, ota, v99desk) ni se atiende al PL. USB0 y GEM0 (MIO) siguen con su DMA, que no depende del PL.
 *
 * Formato: el .bin que saca bootgen -process_bitstream bin (palabras con los bytes girados: la palabra de sincronismo
 * 0xAA995566 aparece como los bytes 66 55 99 AA), que es lo que acepta la PCAP. El .bit de Vivado (con cabecera) y el .bin
 * de write_bitstream -bin_file (sin girar) se rechazan. Es lo mismo que el FSBL carga del BOOT.bin.
 * Memoria: el bitstream puede estar en memoria con cache (se limpia la L1 antes del DMA; la L2 esta apagada). */
#include "xil_types.h"
#include "xparameters.h"
#include "sleep.h"
#include "log.h"
#include "profile.h"
#include "tr_bios.h"
#ifdef PERFIL_HOST
#include "pf_host.h"                                       /* banco en el PC (tests/host_perfil_test.c): memoria y registros de imitacion */
#else
#include "xdevcfg.h"                                       /* arm/fsbl/devcfg */
#include "ota.h"
#include "osd.h"
static inline volatile u32 *pf_w(u32 a) { return (volatile u32 *)(uintptr_t)a; }
#define PF_DSB()    __asm__ volatile ("dsb" ::: "memory")
#endif

#define MBOX        0x1FF00000U
#define MBOX_CTL    (MBOX + 0x1CU)
#define MBOX_MAGIA  (MBOX + 0x40U)                         /* telemetria del PL: 'MBOX' (0x4D424F58) cada ~1 ms */
#define SLCR_LOCK       0xF8000004U
#define SLCR_UNLOCK     0xF8000008U
#define SLCR_PCAP_CLK   0xF8000168U                        /* bit 0: reloj de la PCAP */
#define SLCR_FPGA_RST   0xF8000240U
#define SLCR_LVL_SHFTR  0xF8000900U
#define DEVCFG_BASE     0xF8007000U
#define PF_MCTRL_POR_B  0x00000100U                         /* MCTRL: el PL tiene alimentacion (pcap.h del FSBL) */
#define RST_TODO        0xFU                               /* FPGA3..0_OUT_RST: como Linux (FPGA_RST_ALL_MASK) y ota.c */
#define RST_Y_AXI       0x01F33F0FU                        /* ademas ACP, AXDS0-3 (HP), FSSW, FMSW (GP) y DMA: solo con PF_FLAG_AXI_RST (experimental) */
#define LVL_PS_PL       0xAU
#define LVL_TODO        0xFU

#define PF_US_RUN       5000U                              /* el buzon lee el control cada ~1 ms: que vea MSX_RUN = 0 */
#define PF_US_DRENA     20000U                             /* masters del PL en reset, drenando (ota.c espera 150 ms; aqui se mide) */
#define PF_MS_INIT      500U                               /* PROG_B / INIT */
#define PF_MS_DMA       3000U                              /* DMA de 2,65 MB: decenas de ms */
#define PF_MS_DONE      3000U
#define PF_MS_VIVO      1000U                              /* magia del buzon del PL nuevo */
#define PF_US_TELE      3000U                              /* la ronda de telemetria del PL entera antes de sembrar */
#define MAGIA_MBOX      0x4D424F58U

extern u64  gt_now(void);
extern void tape_stop(void);                               /* tape.c */
extern void tape_init(void);
extern void wg_pl_parar(void);                             /* wavegame.c */
extern void cfg_resync(void);                              /* qspi_cfg.c */
extern void osd_pl_rearma(void);                           /* osd.c */
extern void esp_pl_rearma(void);                           /* esp_link.c */
extern void pl_resembra(void);                             /* main.c */

static XDcfg dc;
static u32 pf_flags;                                       /* cabecera +0x0C, de perfil_poll */

static inline volatile u32 *zona(void) { return pf_w(PF_ZONA); }

static u32 us_desde(u64 t0) { return (u32)((gt_now() - t0) / (u64)(COUNTS_PER_SECOND / 1000000U)); }
static u64 plazo_ms(u32 ms) { return gt_now() + (u64)ms * (u64)(COUNTS_PER_SECOND / 1000U); }

static void informe(u32 st, u32 et)
{
    volatile u32 *z = zona();
    z[0x14 / 4] = et;
    z[0x10 / 4] = st;
    PF_DSB();
}
static void informe_t(u32 i, u32 us) { zona()[(0x18U + 4U * i) / 4U] = us; PF_DSB(); }
static void informe_regs(u32 sts, u32 st, u32 cod)
{
    volatile u32 *z = zona();
    z[0x34 / 4] = sts; z[0x38 / 4] = st; z[0x3C / 4] = cod;
    PF_DSB();
}

/* limpia la L1 de datos del rango (a la DDR) para que el DMA de la PCAP vea lo escrito por la CPU; la L2 esta apagada */
static void dc_clean(const void *p, u32 n)
{
#ifndef PERFIL_HOST
    u32 a = (u32)(uintptr_t)p & ~31U, fin = (u32)(uintptr_t)p + n;
    for (; a < fin; a += 32U) __asm__ volatile ("mcr p15, 0, %0, c7, c10, 1" :: "r"(a) : "memory");   /* DCCMVAC */
    __asm__ volatile ("dsb" ::: "memory");
#else
    (void)p; (void)n;
#endif
}

static void slcr_unlock(void) { Xil_Out32(SLCR_UNLOCK, 0xDF0DU); }
static void slcr_lock(void)   { Xil_Out32(SLCR_LOCK, 0x767BU); }

static void recupera(u32 etapa, u32 cod, u32 sts)             /* no vuelve */
{
    informe_regs(sts, XDcfg_GetStatusRegister(&dc), cod);
    informe(PF_ST_CURSO, etapa);
    log_str("pcap: FALLO etapa "); log_dec(etapa); log_str(" cod "); log_dec(cod);
    log_str(" INT "); log_hex(sts); log_str(" ST "); log_hex(XDcfg_GetStatusRegister(&dc)); log_str(": reinicio el PS\n");
    ota_reinicia_ps();
    slcr_unlock();                                            /* ota_reinicia_ps solo vuelve si MULTIBOOT no se deja escribir */
    Xil_Out32(0xF8000200U, 1U);                               /* PSS_RST_CTRL: PS_SRST */
    for (;;) { }
}

static int espera_init(u32 nivel, u32 ms)                    /* PCFG_INIT al nivel pedido */
{
    u64 fin = plazo_ms(ms);
    while (((XDcfg_GetStatusRegister(&dc) & XDCFG_STATUS_PCFG_INIT_MASK) != 0U) != (nivel != 0U))
        if (gt_now() > fin) return 0;
    return 1;
}

/* sincronismo de la PCAP en el .bin de bootgen: los bytes 66 55 99 AA (palabra 0xAA995566), en los primeros 512 B.
 * Sin girar (AA 99 55 66) es el .bin de write_bitstream -bin_file o un .bit con cabecera. 0 = bien, 1 = nada, 2 = sin girar */
static int formato(const volatile u32 *w, u32 len)
{
    u32 i, n = len < 512U ? len / 4U : 128U;
    int girar = 0;
    for (i = 0; i < n; i++) {
        if (w[i] == 0xAA995566U) return 0;
        if (w[i] == 0x665599AAU) girar = 1;
    }
    return girar ? 2 : 1;
}

int perfil_cargar(const u8 *buf, u32 len)
{
    volatile u32 *ctl = pf_w(MBOX_CTL);
    XDcfg_Config cfgc;
    u64 t0;
    u32 ctrl, sts, st, r, base = DEVCFG_BASE;

    if (((u32)(uintptr_t)buf & 3U) || (len & 3U) || len < 4096U || len > PF_MAX) return PF_E_PARAM;
    r = (u32)formato((const volatile u32 *)buf, len);
    if (r) {
        log_str(r == 2U ? "pcap: bitstream sin girar (hace falta bootgen -process_bitstream bin)\n"
                        : "pcap: no hay sincronismo 66 55 99 AA: no es un .bin de bootgen\n");
        return PF_E_FORMATO;
    }
    if (ota_ocupada() || (*ctl & 0x10U)) { log_str("pcap: ocupado (actualizacion por red o S3 en la UART1)\n"); return PF_E_OCUPADO; }

    /* --- desde aqui se toca el sistema --- */
    t0 = gt_now();
    log_str("pcap: "); log_dec(len); log_str(" B, MSX parado");
    if (pf_flags & PF_FLAG_AXI_RST) log_str(", con reset de las interfaces AXI");
    log_str("\n");
    informe(PF_ST_CURSO, PF_ET_NINGUNA);
    wg_pl_parar();                                            /* el anillo PCM a 0: el PL nuevo nace con rd = 0 */
    tape_stop();
    *ctl &= ~1U;                                              /* MSX_RUN = 0 */
    PF_DSB();
    usleep(PF_US_RUN);
    tr_ex_aplica();                                           /* los bloques del .mxp, o quitar los del perfil anterior */
    dc_clean(buf, len);
    informe_t(0, us_desde(t0)); informe(PF_ST_CURSO, PF_ET_PARADO);

    /* aislar: resets de FPGA, drenar, desplazadores solo PS->PL */
    slcr_unlock();
    Xil_Out32(SLCR_FPGA_RST, (pf_flags & PF_FLAG_AXI_RST) ? RST_Y_AXI : RST_TODO);
    PF_DSB();
    usleep(PF_US_DRENA);
    Xil_Out32(SLCR_LVL_SHFTR, 0U);
    Xil_Out32(SLCR_LVL_SHFTR, LVL_PS_PL);
    if (!(Xil_In32(SLCR_PCAP_CLK) & 1U)) Xil_Out32(SLCR_PCAP_CLK, Xil_In32(SLCR_PCAP_CLK) | 1U);
    slcr_lock();
    informe_t(1, us_desde(t0)); informe(PF_ST_CURSO, PF_ET_AISLADO);

    /* PROG_B: init del PL (subida, bajada y subida de PCFG_INIT, como Linux) */
    cfgc.DeviceId = 0U; cfgc.BaseAddr = base;
    dc.IsStarted = 0;
    (void)XDcfg_CfgInitialize(&dc, &cfgc, base);
    if ((XDcfg_GetMiscControlRegister(&dc) >> XDCFG_MCTRL_PCAP_PS_VERSION_SHIFT) >= 3U &&
        !(XDcfg_GetMiscControlRegister(&dc) & PF_MCTRL_POR_B)) recupera(PF_ET_AISLADO, 1, 0);   /* PL sin alimentar */
    ctrl = XDcfg_GetControlRegister(&dc);
    XDcfg_WriteReg(base, XDCFG_CTRL_OFFSET, ctrl | XDCFG_CTRL_PCFG_PROG_B_MASK);
    if (!espera_init(1U, PF_MS_INIT)) recupera(PF_ET_AISLADO, 2, 0);
    XDcfg_WriteReg(base, XDCFG_CTRL_OFFSET, ctrl & ~XDCFG_CTRL_PCFG_PROG_B_MASK);
    if (!espera_init(0U, PF_MS_INIT)) recupera(PF_ET_AISLADO, 3, 0);
    XDcfg_WriteReg(base, XDCFG_CTRL_OFFSET, ctrl | XDCFG_CTRL_PCFG_PROG_B_MASK);
    if (!espera_init(1U, PF_MS_INIT)) recupera(PF_ET_AISLADO, 4, 0);
    XDcfg_SetControlRegister(&dc, XDCFG_CTRL_PCAP_PR_MASK | XDCFG_CTRL_PCAP_MODE_MASK);
    st = XDcfg_GetStatusRegister(&dc);
    if (!(st & XDCFG_STATUS_DMA_CMD_Q_E_MASK) || (st & XDCFG_STATUS_DMA_CMD_Q_F_MASK)) recupera(PF_ET_AISLADO, 5, 0);   /* cola de DMA ocupada */
    informe_t(2, us_desde(t0)); informe(PF_ST_CURSO, PF_ET_INIT);

    /* DMA: origen con el bit 0 = ultimo comando, destino 0xFFFFFFFF (la PCAP), longitud en palabras, destino 0 */
    XDcfg_IntrClear(&dc, XDCFG_IXR_ALL_MASK);
    r = XDcfg_Transfer(&dc, (void *)((uintptr_t)buf | 1U), len / 4U, (void *)(uintptr_t)XDCFG_DMA_INVALID_ADDRESS, 0U,
                       XDCFG_NON_SECURE_PCAP_WRITE);
    if (r != XST_SUCCESS) recupera(PF_ET_INIT, 6, 0);
    {
        u64 fin = plazo_ms(PF_MS_DMA);
        for (;;) {
            sts = XDcfg_IntrGetStatus(&dc);
            if (sts & XDCFG_IXR_ERROR_FLAGS_MASK) recupera(PF_ET_INIT, 7, sts);
            if (sts & XDCFG_IXR_D_P_DONE_MASK) break;
            if (gt_now() > fin) recupera(PF_ET_INIT, 8, sts);
        }
    }
    informe_t(3, us_desde(t0)); informe(PF_ST_CURSO, PF_ET_DMA);
    {
        u64 fin = plazo_ms(PF_MS_DONE);
        for (;;) {
            sts = XDcfg_IntrGetStatus(&dc);
            if (sts & XDCFG_IXR_ERROR_FLAGS_MASK) recupera(PF_ET_DMA, 9, sts);
            if (sts & XDCFG_IXR_PCFG_DONE_MASK) break;
            if (gt_now() > fin) recupera(PF_ET_DMA, 10, sts);
        }
    }
    XDcfg_ClearControlRegister(&dc, XDCFG_CTRL_PCAP_PR_MASK);   /* la PCAP ya no es para reconfiguracion parcial */
    informe_t(4, us_desde(t0)); informe(PF_ST_CURSO, PF_ET_DONE);
    informe_regs(sts, XDcfg_GetStatusRegister(&dc), 0);

    /* PL nuevo: desplazadores, resets fuera, y esperar a su buzon */
    pf_w(MBOX_MAGIA)[0] = 0U;                                 /* la de la telemetria del PL viejo ya no vale */
    PF_DSB();
    slcr_unlock();
    Xil_Out32(SLCR_LVL_SHFTR, LVL_TODO);
    Xil_Out32(SLCR_FPGA_RST, 0U);
    slcr_lock();
    {
        u64 fin = plazo_ms(PF_MS_VIVO);
        while (pf_w(MBOX_MAGIA)[0] != MAGIA_MBOX)
            if (gt_now() > fin) recupera(PF_ET_DONE, 11, sts);
    }
    informe_t(5, us_desde(t0)); informe(PF_ST_CURSO, PF_ET_VIVO);
    usleep(PF_US_TELE);

    /* sembrar como el arranque y soltar el MSX */
    pl_resembra();
    cfg_resync();                                             /* cfg_poll: el toggle de "guardar" del PL nuevo no es el del viejo */
    informe(PF_ST_CURSO, PF_ET_RESEMBRADO);
    *ctl |= 1U;                                               /* MSX_RUN */
    PF_DSB();
    r = us_desde(t0);
    informe_t(6, r); informe(PF_ST_OK, PF_ET_RUN);
    log_str("pcap: OK, us: parado "); log_dec(zona()[0x18 / 4]);
    log_str(" aislado "); log_dec(zona()[0x1C / 4]);
    log_str(" init "); log_dec(zona()[0x20 / 4]);
    log_str(" dma "); log_dec(zona()[0x24 / 4]);
    log_str(" done "); log_dec(zona()[0x28 / 4]);
    log_str(" vivo "); log_dec(zona()[0x2C / 4]);
    log_str(" run "); log_dec(r); log_str("\n");

    osd_pl_rearma();                                          /* UART0/OLED y UART1/ESP de nuevo: ya con el MSX en marcha */
    esp_pl_rearma();
    log_str("pcap: servicios rearmados a los "); log_dec(us_desde(t0)); log_str(" us\n");
    return 0;
}

int perfil_poll(void)
{
    volatile u32 *z = zona();
    u32 tam, i;
    int rc;
    if (z[0] != PF_MAGIA) return 0;
    z[0] = 0U;                                                /* una sola vez, pase lo que pase */
    PF_DSB();
    tam = z[1];
    pf_flags = z[3];
    for (i = 0x10U / 4U; i < 0x40U / 4U; i++) z[i] = 0U;     /* informe limpio */
    informe(PF_ST_CURSO, PF_ET_NINGUNA);
    log_str("pcap: peticion, "); log_dec(tam); log_str(" B\n");
    if (z[2] != (PF_MAGIA ^ tam ^ 0xA5A5A5A5U)) {
        informe(PF_ST_ERR | PF_E_CABECERA, PF_ET_NINGUNA);
        log_str("pcap: cabecera invalida\n");
        return 0;
    }
    rc = perfil_cargar((const u8 *)pf_w(PF_DATOS), tam);
    pf_flags = 0U;                                            /* las banderas son solo de esta peticion: mxpf.c tambien llama a perfil_cargar */
    if (rc) {
        informe(PF_ST_ERR | (u32)rc, PF_ET_NINGUNA);
        log_str("pcap: rechazado, error "); log_dec((u32)rc); log_str(" (el PL no se ha tocado)\n");
        return 0;
    }
    return 1;
}
