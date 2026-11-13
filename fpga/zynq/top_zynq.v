// ======================================================================
//  top_zynq.v — GENERADO por zynq/tools/make_top_zynq.py a partir de top.v
//  NO EDITAR A MANO: los cambios van al script (o a top.v si son comunes).
// ======================================================================
`define ZYNQ                 // ZYNQ MINI (XC7Z020)
`define ENABLE_MIXER         // V3.7: mezclador por fuente (puerto #44 extendido); en la Zynq sobra area
`ifndef PERFIL_MUSICA
`ifndef PERFIL_DUAL
`ifndef PERFIL_TR
`define ENABLE_GEO3D         // 27/09/2026: geo3d (Alex Moncks, MIT, fpga/geo3d/): coprocesador 3D en 9Dh/9Fh que escribe LINE/LRMM en el motor de comandos del V9968
`endif
`endif
`endif
`define ENABLE_V9958
`define ENABLE_BIOS
`define ENABLE_SOUND //v9958, bios required
`define ENABLE_MAPPER //bios required
`define ENABLE_SCAN_LINES
`define ENABLE_SDCARD
`define ENABLE_CONFIG
//`define ENABLE_MIXER //V3.7 (17/09/2026): mezclador por fuente (puerto #44 extendido, ~11 multiplicadores 19x5). ON en la Zynq (make_top_zynq.py); en el Tang a decidir por area
`define ENABLE_WAIT //extra wait state for mreq+wr
//`define ENABLE_WAIT_ADAPTIVE //wait required
`define ENABLE_M1_WAIT //STANDALONE: 1 wait-state per M1 opcode fetch (the real-MSX brake). Comment out to disable.
//`define SWAP23
// ============ v3.0 BASE MINIMA (Fase 1-REDUX, 2026-07-09) ============
// Video 720p por puente BRAM (video720/msx2hdmi.sv) + subsistemas fuera.
// IMPORTANTE: VIDEO720 tambien esta `define'd en tn_vdp_v3_v9958/src/
// v9958_top.v (ficheros de compilacion distintos) — mantener SINCRONIZADOS.
`define VIDEO720
`define ENABLE_WIFI       // F1 (_73): WiFi UNAPI por el BL616 ONBOARD (UART en V14/U15, ver uwifi)
`define ENABLE_WIFI_ESP32 // _153: la UART del WiFi va al ESP32-C6 externo por el conector J10 (2x20 libre, fila PAR: 12=GND, 14=TX(W21), 16=RX(N17)) en vez del BL616 (sin antena/fw). Mismo wifi_lite, mismo baud 27M/31: el fw ducasp/ESP32-UNAPI a 859372 ya esta validado con este prescaler en el MSXnano.
//`define WIFI_PMOD_TEST  // (_77diag) UART del WiFi al PMOD1 — apagado
//`define WIFI_TAP_BL616TX  // _78diag (APAGADO en _111c: llevaba desde la _78 robandole E22 a todo; la telemetria _111 nunca salio por su culpa)
`define ENABLE_OPLL         // F3 (_38): OPLL de vuelta — 1a pieza re-añadida sobre la base validada
`ifndef PERFIL_TR
`define ENABLE_Y8950        // F2 (_79): MSX-Audio (Y8950) FM via jtopl2 (core ya vendido en fpga/jtopl/), puertos C0/C1. VALIDADO EN HW (juego OK)
`define ENABLE_Y8950_ADPCM  // F2 (_80): ADPCM-B del Y8950 — y8950_adpcm.v (glue openMSX-exacto) + decoder jt10_adpcmb + RAM samples 32KB BSRAM (NMS-1205 de serie). VALIDADO HW+VGMPlay
`define ENABLE_Y8950_IRQ    // F2 (_81): IRQ del Y8950 (timers+EOS+BUF ya enmascarados) al /INT del Z80 (wired-AND como el Music Module real). Arranca todo enmascarado = sin IRQ hasta que el software la pida
`endif
`ifndef PERFIL_DUAL
`define ENABLE_OPL4FM       // F2 (_82-_85): MoonSound FM (OPL3) en C4-C7 + stub wave 7E/7F. VALIDADO EN HW (reloj 96/98, limpio)
`endif
//`define ENABLE_WAVE_DDR3    // F2 (_86): bring-up de la DDR3 del SOM para la memoria de ondas OPL4 (cliente independiente + puerto debug I/O 34-37h). Fase wavetable
//`define ENABLE_WAVE_LOADER  // F2 (_87): carga de la YRW801 (2MB) de flash 0x500000 a DDR3 en BACKGROUND tras el boot (no bloquea el arranque). Status: bit2 de IN 36h = cargando
`ifndef PERFIL_DUAL
`define ENABLE_OPL4_WAVE    // F2 (_89): motor PCM 24 slots del OPL4 (YMF278B.sv de srg320 + permiso) en clk_x1 de la DDR3, CE fraccionario 44.1kHz con stall. REQUIERE ENABLE_WAVE_DDR3+LOADER. Con esto el MoonSound esta COMPLETO (FM+wavetable)
`endif
`define ENABLE_USB_KBD      // F3 (_39): teclado por USB-A DIRECTO al fabric (usb_hid_host, sin hub)
`define ENABLE_SCC          // F3 (_40): SCC de vuelta — scc_wave2v Verilog puro (el VHDL scc_wave_mul era BARRIDO por la sintesis GW5A)
`define ENABLE_TURBO       // P1: turbo WSX 5.37 de vuelta con la receta v1.9 (turbo_eff sin glitch + boot-turbo solo en frio)
// ¡OJO! ENABLE_V9968_VDP y ENABLE_VRAM_AXI se ven comentados AQUI y aun
// asi ESTAN ACTIVOS en las entregas: tools/lanzar_campana.ps1 los descomenta
// en el CLON antes de sintetizar (y aborta si no lo consigue). O sea que
// leer este fichero a secas te dice lo que NO lleva el bitstream. Para saber
// que hay de verdad en un .fs, mira el script de campana, no estas lineas.
`define ENABLE_V9968_VDP   // F1 V9968: VDP de HRA! (fpga/v9968, tag+eco) + shim VRAM a SDRAM compartida (puerto wv2) + puente 800px (msx2hdmi_v9968). Sustituye v9958_top ENTERO. Activar en el build _117
`define ENABLE_VRAM_AXI   // Zynq: v9968_axi_backend (HP0). Era ENABLE_VRAM_AXI   // _128X EXPERIMENTO: la VRAM del V9968 en la DDR3 del SOM (v9968_ddr3_backend; requiere ENABLE_V9968_VDP y USE_VRAM_DDR3=1 en build.tcl). ADVERTENCIA: DDR3 analogicamente marginal en esta placa (saga _94-_103)
//`define TURBO_SIN_GUARDA_SDRAM  // 🧪 EXPERIMENTO 26/08 — **PROBADO Y DESCARTADO**: sin la guarda el MSX SE CUELGA al poner el turbo (placa, 26/08). La guarda NO estaba obsoleta pese a que la VRAM se mudo a la DDR3: lo que la justifica no es la CONTENCION del VDP sino la LATENCIA de la SDRAM (y su refresco), que a 5,37 no cabe en un T-estado de 186 ns. Se deja el define por si algun dia se acelera el controlador. Coste medido de la guarda: 18% (4,41 de 5,37).
`define ENABLE_S1990_TIMER // Z1.4 (30/10/2026): del S1990 solo el temporizador E6h/E7h (las demos geo3d de kanon-ai lo usan); sin ENABLE_TURBOR_ID no hay firma de turboR ni CHGCPU
//`define ENABLE_TURBOR_ID // rama beta 30/10/2026: QUITADO por orden de Albert (sin turbo R ni R800 que identificar; un programa que lo detecte por el S1990 llamaria a rutinas de BIOS de turbo R que no hay). V3.1: S1990 del turboR (E4h-E7h) — la maquina se identifica como turboR y CHGCPU mueve el turbo. NO hay R800: ver fpga/src/msx_s1990.v
`define ENABLE_V9990       // V9990 (tiny9990, fpga/v9990) en los puertos 60h-6Fh con VRAM en la DDR (S_AXI_GP1) y su propio puente a 720p; Pausa conmuta la HDMI entre el V9968 y el V9990 (desde el 28/10/2026 por el compositor por pixel v9991_compose con un solo codificador; antes hdmi_tmds_switch). Deja sin motor el puerto de depuracion 34h-37h de la wave (era el dueno del GP1).
`define ENABLE_IOSYS       // V3.1 PELDANO 1 (TangCore): iosys_bl616 + textdisp por la UART del BL616 (V14/U15) y overlay sobre el HDMI. Sin firmware en el MCU todavia: el overlay se enciende solo unos segundos al arrancar para demostrar la cadena y luego se aparta.
//`define DISABLE_BOOT_MENU  // _127D: arranque MSX DIRECTO (enmascara la firma AB del menu; tambien salta el init FM de esa pagina). Solo builds de prueba.
// Perfil "Musica" (31/10/2026): build.tcl ... bit musica define PERFIL_MUSICA=1. Mismo sistema que el estandar pero SIN geo3d y CON
// YM2151 (Yamaha SFG-01/05, ranura 0-1, jt51) y SN76489 (Franky 48h-49h, PlaySoniq 2Ah-2Bh; jt89): fpga/zynq/musica_sound.v.
`ifdef PERFIL_MUSICA
`define ENABLE_MUSICA
`endif
// Perfil "Dual" (31/10/2026, prueba de concepto; 2.a version): build.tcl ... bit dual define PERFIL_DUAL=1. El sistema de siempre SIN geo3d
// y SIN el OPL4 (ENABLE_OPL4FM y ENABLE_OPL4_WAVE: el motor PCM, la FM y la memoria de ondas del PS; el Y8950, el OPLL, el SCC y los PSG se
// quedan) y CON una segunda maquina MSX2+ (B: su Z80, su V9968 con su cache de VRAM, su PSG, su RAM y su cartucho en la DDR; fpga/zynq/
// msx_b.v). El V9990 se queda, con su escritorio del ARM: la imagen de B es un rectangulo dentro del frame buffer del V9990 (bwin_fb, por el
// S_AXI_GP0 que deja libre la memoria de ondas del OPL4; el escritor del frame buffer se salta ese rectangulo) y A sigue en la ventana
// del gestor de ventanas. Docs: docs/tecnica/14-perfil-dual.md
`ifdef PERFIL_DUAL
`define ENABLE_DUAL
`endif
// Perfil "TR" (Turbo R, fase 1, 02/11/2026): build.tcl ... bit tr define PERFIL_TR=1. El MSX2+ del estandar SIN geo3d, SIN V9990 (el chip, su puente
// a 720p, su escritor de frame buffer y el puerto del ARM: los puertos 60h-6Fh quedan vacios), SIN el OPL4 (FM, PCM y memoria de ondas) y SIN el Y8950
// (FM + ADPCM). Del video se queda el compositor v9991_compose FIJO en el modo 0 (V9968 a pantalla completa por su frame buffer: 4:3 Scale3x, 60 Hz
// libres, overlay del F12) con el GP1 solo para ese frame buffer. Aun sin R800 (fase 2). Bit 6 del puerto #45 = "este core es el perfil TR".
// Docs: docs/tecnica/15-perfil-tr.md
`ifdef PERFIL_TR
`define ENABLE_TR
`ifndef TR_V9990
`define TR_SIN_V9990   // perfil candidato trv (build.tcl ... bit trv): el TR con V9990; sin el, los puertos 60h-6Fh van vacios
`endif
`define TRPCM_SHIFT 1
`endif

// _159: la RAM de muestras del ADPCM-B pasa de 32KB en BSRAM a los 256KB
// COMPLETOS del Y8950 servidos desde la SDRAM (adpcm_sdram.v -> puerto wv2,
// filas 5120+). Esto NO se decide a mano: se DERIVA, porque solo es legal
// cuando wv2 esta libre. Lo esta con el V9968 apagado y con el V9968 + VRAM
// en DDR3 (la linea principal _138); en la linea de respaldo _137 (VRAM del
// V9968 en la SDRAM) lo conduce el bridge del V9968 y el ADPCM cae solo a
// los 32KB de BSRAM de siempre (adpcm_sdram con FALLBACK_BSRAM=1). Derivarlo
// hace IMPOSIBLE por construccion la combinacion con dos drivers de wv2.
`ifdef ENABLE_Y8950_ADPCM
 `ifndef ENABLE_V9968_VDP
  `define ENABLE_ADPCM_SDRAM
 `else
  `ifdef ENABLE_VRAM_AXI
   //`define ENABLE_ADPCM_SDRAM   // Zynq: ADPCM en BRAM (FALLBACK_BSRAM=1)
  `endif
 `endif
`endif

module top_zynq
#(
    parameter SD_SLOT = 3             // (como el Tang: slot de la microSD)
)(
    // ---- ZYNQ MINI: pines dedicados ----
    input  wire        clk50,          // K17, 50 MHz (el "ex_clk_27m" del Tang)
    input  wire        key_s1_n,       // M19 (K2)
    input  wire        key_s2_n,       // M20 (K3)
    // 25/09 (Ethernet P0): el reset del RTL8211E del PS (U18, GEM0) cuelga de G20 por R73 (1 k) ademas
    // del pull-up de 4,7 k. Sin puerto, el bitstream deja G20 con pull-down (UNUSEDPIN) y el PHY se
    // queda en reset o en un nivel marginal (MDIO a 0xFFFF, red muerta a ratos). Fijo a 1.
    output wire        phy_ps_rst_n,   // G20 -> R73 -> PHYRSTB del PHY del PS
    output wire [3:0]  led_z,          // W13 V12 U12 T12 (activos a 1)

    // HDMI (mismos nombres que el Tang: data_p/n, clk_p/n; H16/D19/C20/B19)
    output wire [2:0]  data_p,
    output wire [2:0]  data_n,
    output wire        clk_p,
    output wire        clk_n,
    output wire        hdmi_out_en,    // H18

    // microSD del MSXimus (sd_reader del PL, modo SD 1 bit). La placa NO tiene
    // microSD en el PL (TF1/TF2 son SD0/SD1 del PS por MIO): breakout pasivo 3V3
    // en el header CAM1, pines 31..36 (GND en 37/38, 3V3 en 39/40).
    output wire        sd_sclk,        // N18 (CAM1-34)
    inout  wire        sd_cmd,         // T20 (CAM1-33)
    inout  wire        sd_dat0,        // P20 (CAM1-35)
    output wire        sd_dat1,        // N20 (CAM1-36)
    output wire        sd_dat2,        // U20 (CAM1-31)
    output wire        sd_dat3,        // P18 (CAM1-32)

    // ESP32 (C6 o S3): WiFi UNAPI por UART (wifi_lite, I/O 06/07h, 27M/31 baud) + aviso
    // de turbo. Mismos 3 hilos que el J10 de la Tang. CAM1 26/28/30 (top_zynq_esp.xdc).
    input  wire        esp_rx_i,       // W16 (CAM1-26) <- TX del ESP (PULLUP: reposo sin modulo)
    output wire        esp_tx_o,       // R18 (CAM1-28) -> RX del ESP
    output wire        esp_turbo_o,    // P19 (CAM1-30) -> GPIO del ESP (estado del turbo)

    // OLED 128x64 del conector J4 (SSD1306, SPI de 4 hilos). NO lo conduce el PL: son 4
    // GPIO EMIO del PS y el protocolo lo hace el ARM (arm/companion/oled.c), asi se puede
    // cambiar sin recompilar. Pines en top_zynq_oled.xdc. Van como INOUT porque el bd saca
    // el GPIO con sus IOBUF dentro (puerto unico OLED_GPIO_tri_io); el sentido lo manda
    // el ARM con DIRM/OEN del GPIO, que oled_init pone a salida.
    inout  wire        oled_sclk,      // E18 -> D0 del modulo (reloj)
    inout  wire        oled_sdin,      // E19 -> D1 del modulo (dato)
    inout  wire        oled_dc,        // F16 -> D/C
    inout  wire        oled_rst_n,     // F17 -> RST

    // ---- PS7: DDR3 + MIO (pines fijos del PS, sin .xdc) ----
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [1:0]  DDR_dm,
    inout  wire [15:0] DDR_dq,
    inout  wire [1:0]  DDR_dqs_n,
    inout  wire [1:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);
    // ================================================================
    //  ZYNQ: los puertos del Tang que aqui no existen pasan a wires
    //  internos con tie-off. La logica que los consume NO se toca:
    //  Vivado la poda. Cuando un subsistema se conecte de verdad
    //  (USB al header, SD1, ESP32, UART del PS por EMIO) su wire se
    //  sustituye por el puerto real y su .xdc.
    // ================================================================
    wire ex_clk_27m = clk50;          // nombre historico (lleva 50 MHz tambien en el Tang)
    wire s1 = key_s1_n;
    wire s2 = key_s2_n;
    assign hdmi_out_en = 1'b1;
    assign phy_ps_rst_n = 1'b1;                 // PHY del PS fuera de reset (ver el puerto)

    // BL616 (SPI companion + UART iosys + JTAG select): no existe en la Zynq
    wire spi_sclk = 1'b0, spi_csn = 1'b1, spi_dat = 1'b0;
    wire spi_dir, spi_irqn;
    wire bl616_jtagsel;               // = RX de la UART del iosys <- UART0 del PS (EMIO): el ARM hace de BL616
    wire jtagseln, iosys_uart_tx;     // iosys_uart_tx -> UART0_RX del PS
    wire uart1_tx_w, uart1_rtsn_w;    // UART1 del PS por EMIO (25/09, Ethernet P1): lo que el ARM manda al MSX y su RTS (1 = pausa)
    wire uart1_rx_w, uart1_ctsn_w;    //   y lo que el MSX escribe en el 07h hacia el ARM; CTSN a 0 (el ARM manda siempre)
    wire wait_net_n;                  //   WAIT al Z80 mientras el ARM pida pausa (se asigna junto a uwifi)
    // (ESP32: puertos reales esp_* en el header CAM1 26/28/30, ver cabecera)
    // LEDs del Tang (6, activos a 0) -> 4 de la placa (activos a 1)
    wire [5:0] led;
    assign led_z = ~led[3:0];
    wire ws2812_led;
    wire [4:0] dbg_pmod1, dbg_pmod0;  // (el ILA sustituye a los PMOD)
    wire uart_pmod_rx = 1'b1;
    // Flash SPI del Tang: el pack lo carga el PS en la DDR (cargador a IDLE)
    wire mspi_cs, mspi_sclk, mspi_wp, mspi_hold;
    wire mspi_miso, mspi_mosi;
    // (microSD: puertos reales sd_* en el header, ver cabecera)
    wire usb_uart_tx;
    // USB-A x2 (soft-host en el PL): pendiente de 4 pines del header
    wire usb1_dp, usb1_dn, usb2_dp, usb2_dn;
    // SDRAM y DDR3 del Tang: no existen (memory_axi / v9968_axi_backend)
    wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n, O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n;
    wire [15:0] IO_sdram_dq;
    wire [12:0] O_sdram_addr;
    wire [1:0]  O_sdram_ba, O_sdram_dqm;
    wire [14:0] ddr_addr;
    wire [2:0]  ddr_bank;
    wire ddr_cs, ddr_ras, ddr_cas, ddr_we, ddr_ck, ddr_ck_n, ddr_cke, ddr_odt, ddr_reset_n;
    wire [1:0]  ddr_dm;
    wire [15:0] ddr_dq;
    wire [1:0]  ddr_dqs, ddr_dqs_n;
    wire fan_en_o;

    // ---- PS7: relojes/reset y los dos puertos HP (instancia al final) ----
    wire        fclk0;                // 150 MHz: aclk de la VRAM
    wire        frst0_n;              // FCLK_RESET0_N (lo suelta ps7_post_config)
    wire [5:0]  hp0_awid;   wire [31:0] hp0_awaddr;  wire [3:0] hp0_awlen;   wire [2:0] hp0_awsize;
    wire [1:0]  hp0_awburst, hp0_awlock; wire [3:0] hp0_awcache; wire [2:0] hp0_awprot; wire [3:0] hp0_awqos;
    wire        hp0_awvalid, hp0_awready;
    wire [5:0]  hp0_wid;    wire [63:0] hp0_wdata;   wire [7:0] hp0_wstrb;  wire hp0_wlast, hp0_wvalid, hp0_wready;
    wire [5:0]  hp0_bid;    wire [1:0]  hp0_bresp;   wire hp0_bvalid, hp0_bready;
    wire [5:0]  hp0_arid;   wire [31:0] hp0_araddr;  wire [3:0] hp0_arlen;   wire [2:0] hp0_arsize;
    wire [1:0]  hp0_arburst, hp0_arlock; wire [3:0] hp0_arcache; wire [2:0] hp0_arprot; wire [3:0] hp0_arqos;
    wire        hp0_arvalid, hp0_arready;
    wire [5:0]  hp0_rid;    wire [63:0] hp0_rdata;   wire [1:0] hp0_rresp;  wire hp0_rlast, hp0_rvalid, hp0_rready;
    wire [5:0]  hp1_awid;   wire [31:0] hp1_awaddr;  wire [3:0] hp1_awlen;   wire [2:0] hp1_awsize;
    wire [1:0]  hp1_awburst, hp1_awlock; wire [3:0] hp1_awcache; wire [2:0] hp1_awprot; wire [3:0] hp1_awqos;
    wire        hp1_awvalid, hp1_awready;
    wire [5:0]  hp1_wid;    wire [63:0] hp1_wdata;   wire [7:0] hp1_wstrb;  wire hp1_wlast, hp1_wvalid, hp1_wready;
    wire [5:0]  hp1_bid;    wire [1:0]  hp1_bresp;   wire hp1_bvalid, hp1_bready;
    wire [5:0]  hp1_arid;   wire [31:0] hp1_araddr;  wire [3:0] hp1_arlen;   wire [2:0] hp1_arsize;
    wire [1:0]  hp1_arburst, hp1_arlock; wire [3:0] hp1_arcache; wire [2:0] hp1_arprot; wire [3:0] hp1_arqos;
    wire        hp1_arvalid, hp1_arready;
    wire [5:0]  hp1_rid;    wire [63:0] hp1_rdata;   wire [1:0] hp1_rresp;  wire hp1_rlast, hp1_rvalid, hp1_rready;
    // HP2 = buzon de depuracion (zynq/dbg_mailbox_axi.v): teclado desde xsdb + telemetria
    wire [5:0]  hp2_awid;   wire [31:0] hp2_awaddr;  wire [3:0] hp2_awlen;   wire [2:0] hp2_awsize;
    wire [1:0]  hp2_awburst, hp2_awlock; wire [3:0] hp2_awcache; wire [2:0] hp2_awprot; wire [3:0] hp2_awqos;
    wire        hp2_awvalid, hp2_awready;
    wire [5:0]  hp2_wid;    wire [63:0] hp2_wdata;   wire [7:0] hp2_wstrb;  wire hp2_wlast, hp2_wvalid, hp2_wready;
    wire [5:0]  hp2_bid;    wire [1:0]  hp2_bresp;   wire hp2_bvalid, hp2_bready;
    wire [5:0]  hp2_arid;   wire [31:0] hp2_araddr;  wire [3:0] hp2_arlen;   wire [2:0] hp2_arsize;
    wire [1:0]  hp2_arburst, hp2_arlock; wire [3:0] hp2_arcache; wire [2:0] hp2_arprot; wire [3:0] hp2_arqos;
    wire        hp2_arvalid, hp2_arready;
    wire [5:0]  hp2_rid;    wire [63:0] hp2_rdata;   wire [1:0] hp2_rresp;  wire hp2_rlast, hp2_rvalid, hp2_rready;
    wire [127:0] kbd_mbox;            // bitmap HID leido del buzon (dominio clk_54m)
    wire [15:0] joy1_mbox, joy2_mbox; // joysticks USB del companion (formato SNES del BL616), clk_54m
    wire [7:0]  mb_mouse_btn, mb_mouse_dx, mb_mouse_dy;   // raton USB del companion: delta por informe
    wire        mb_mouse_rep;         // pulso clk_54m: nuevo informe de raton
    wire        mb_msx_run;           // MBOX+0x1C bit 0: 0 = MSX en reset hasta que el pack este en la DDR
`ifdef PERFIL_TR
    wire        mb_tr_bios;           // MBOX+0x1C bit 6 (perfil TR, fase 2): la BIOS del turbo R esta en la DDR (0x0E400000)
`endif
    wire        mb_net_ps;            // MBOX+0x1C bit 3 (25/09): la UART del ESP va a la UART1 del PS (companion = "ESP32" por Ethernet)
    wire        mb_s3_ps;             // MBOX+0x1C bit 4 (02/10): la S3 del CAM1 habla con la UART1 del PS (actualizacion por su WiFi)
    // ZYNQ 16/09: bloque de config PERSISTENTE. En el Tang el menu lo graba en la flash SPI (puerto #42
    // bit 6) y el stream de la flash lo siembra al arrancar (ventana config_init); aqui no hay flash
    // en el PL: el companion lo guarda en un sector de la QSPI, lo pone en MBOX+0x1C[28:8] ANTES de
    // soltar el MSX y el PL siembra config1/config2/turbo-boot/ganancia hasta que el MSX corre. Al
    // pulsar "guardar", el bloque vigente sale por MBOX+0x70 con un toggle y el companion lo graba.
    wire [20:0] mb_cfg;               // {valid, gain[2:0], turbo, config2[7:0], config1[7:0]} (clk_54m)
    wire [31:0] mb_vid_ctl;           // +0x2C {seq[15:8], 6'b0, auto_off[1], sel[0]}: fuente HDMI pedida por el ARM (V9990; clk_54m).
                                      // [3] Video9000 forzado. [4] (rama beta, 30/10/2026) fs43: el V9968 a pantalla completa (modo 0
                                      // del compositor) en 4:3 + Scale3x (960 x 720 centrado; msx2hdmi_v9968, 512 puntos a 1,5 px);
                                      // cuasi-estatico, no lleva seq: lo lee el puente (2FF en clk_pixel) y aplica en el vblank
    reg  [20:0] zq_cfg_s1 = 21'd0, zq_cfg_s2 = 21'd0;
    reg  [1:0]  zq_run_s = 2'b00;
    reg  [1:0]  zq_netps_s = 2'b00;
    reg  [1:0]  zq_s3ps_s = 2'b00;
    reg         zq_seeded = 1'b0;
    always @(posedge clk_27m) begin
        zq_cfg_s1 <= mb_cfg; zq_cfg_s2 <= zq_cfg_s1;
        zq_run_s  <= {zq_run_s[0], mb_msx_run};
        zq_netps_s <= {zq_netps_s[0], mb_net_ps};
        zq_s3ps_s  <= {zq_s3ps_s[0], mb_s3_ps};
        if (zq_cfg_s2[20] && zq_run_s[1]) zq_seeded <= 1'b1;
    end
    wire        zq_cfg_seed   = zq_cfg_s2[20] && !zq_seeded;                  // siembra hasta que el MSX corre
    wire        zq_turbo_seed = zq_cfg_s2[20] && zq_run_s[1] && !zq_seeded;   // un ciclo, con bus_reset_n ya alto
    reg  [31:0] zq_cfg_tel = 32'd0;   // +0x70: bloque vigente + toggle[31] al guardar
    reg  [2:0]  zq_cfw_d = 3'b000;
    // V3.7 (17/09): niveles del mezclador (top.v mix_lvl, 7 canales x 4 bits). Siembra desde MBOX+0x24
    // {valid[31], 3'b0, niveles[27:0]} con las mismas reglas que mb_cfg; al guardar salen por MBOX+0xC0
    // {toggle[31], 3'b0, niveles[27:0]} (el toggle va sincronizado con el de +0x70: el companion espera a
    // que los dos coincidan antes de grabar, asi nunca lee los niveles de la ronda anterior).
    wire [31:0] mb_mix;
    reg  [31:0] zq_mix_s1 = 32'd0, zq_mix_s2 = 32'd0;
    always @(posedge clk_27m) begin zq_mix_s1 <= mb_mix; zq_mix_s2 <= zq_mix_s1; end
    reg  [31:0] zq_mix_tel = 32'd0;
    // La siembra del mezclador lleva su PROPIO "sembrado": +0x24 llega un beat despues que +0x1C (beat 4 vs 3) y
    // en el arranque por JTAG (MSX_RUN ya a 1 antes de configurar el PL) la ventana de zq_cfg_seed es de UN ciclo
    // de 27 MHz: segun la fase del beat, zq_mix_s2 aun no era valido y los niveles no se sembraban (17/09).
    reg         zq_mix_seeded = 1'b0;
    always @(posedge clk_27m) if (zq_mix_s2[31] && zq_run_s[1]) zq_mix_seeded <= 1'b1;
    wire        zq_mix_seed = zq_mix_s2[31] && !zq_mix_seeded;
    reg  [6:0]  zq_cfw_blank = 7'd0;  // ventana anti-rebote del toggle de "guardar" (un OUT = varios pulsos)
    // ZYNQ 16/09: canal Z80 -> ARM. Todo OUT al puerto 92h (WaveGame: 1 byte por orden, fire-and-forget,
    // protocolo de Jeroen Taverne) y al 93h (mensajes del menu al companion; el 47h es la orden del SD: al lanzar una ROM manda
    // "WG" + PART_LBA + CUR_CLUS + FILE_CLUS para que el companion encuentre los NN.wav de la carpeta)
    // entra en un anillo de 32 entradas {tag, dato} que el buzon vuelca cada ronda (+0x78..+0xB8).
    wire        zq_wg_req  = (bus_addr[7:0] == 8'h92 && bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_wr_n == 1'b0);
    wire        zq_msg_req = (bus_addr[7:0] == 8'h93 && bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_wr_n == 1'b0);
    reg         zq_wg_d = 1'b0, zq_msg_d = 1'b0;
    reg  [511:0] zq_ring = 512'd0;
    reg  [7:0]  zq_wi = 8'd0;
    always @(posedge clk_27m) begin
        if (clk_enable_3m6_27) begin
            zq_wg_d <= zq_wg_req; zq_msg_d <= zq_msg_req;
            if (zq_wg_req && !zq_wg_d) begin
                zq_ring[{zq_wi[4:0], 4'b0000} +: 16] <= {8'h92, cpu_dout}; zq_wi <= zq_wi + 8'd1;
            end else if (zq_msg_req && !zq_msg_d) begin
                zq_ring[{zq_wi[4:0], 4'b0000} +: 16] <= {8'h93, cpu_dout}; zq_wi <= zq_wi + 8'd1;
            end
        end
    end
    // 17/09 caza de los SSID corruptos: cada lectura del Z80 del puerto 06h (dato del UART del ESP) deja el byte
    // que devolvio el core (uart_dout al final del ciclo de lectura) en el trazador como evento 7 (logica junto a uart_req).
    reg        zq_uart_rd_d = 1'b0, zq_uart_tgl = 1'b0;
    reg  [7:0] zq_uart_byte = 8'd0, zq_uart_last = 8'd0;
    // WaveGame: muestra de la voz (clk_54m, 44,1 kHz) -> mezclador (clk_27m, relojes hermanos del MMCM)
    wire signed [18:0] wg_smp;           // ya con la ganancia x1..x8 aplicada en el buzon
    wire signed [18:0] wg_smp_r;         // 23/09: canal derecho (estereo, bit 30 de MBOX+0x20); en mono = wg_smp
    reg  signed [18:0] wg_smp_27 = 19'sd0, wg_smp_r_27 = 19'sd0;
    always @(posedge clk_27m) begin wg_smp_27 <= wg_smp; wg_smp_r_27 <= wg_smp_r; end
    // Z1.1 (18/09): CINTA VIRTUAL. El buzon reproduce un anillo de pulsos {nivel, duracion} que el companion
    // genera del .tsx/.cas (dbg_mailbox_axi.v); el nivel entra por el bit 7 del registro 14 del PSG (CASRD, que
    // hasta hoy leia 1 fijo), solo corre con el motor del casete (PPI PC4 = 0) y, mientras hay cinta cargada,
    // el turbo se inhibe (las rutinas de casete de la BIOS son bucles contados a 3,58 MHz). Con el monitor
    // activo la senal suena bajita en el mezclador (se oye cargar).
    wire        tape_in, tape_play, tape_mon, tape_nonextor;
    reg         tape_in_27 = 1'b1, tape_play_27 = 1'b0, tape_mon_27 = 1'b0;
    always @(posedge clk_27m) begin tape_in_27 <= tape_in; tape_play_27 <= tape_play; tape_mon_27 <= tape_mon; end
`ifdef ENABLE_DUAL
    wire        a_mute_27, b_mute_27;                                // Dual (Z1.3.2b8): silencio de la maquina A / B en clk_27m (dual_mute.v, mas abajo)
    wire signed [18:0] tp_snd_27 = (tape_mon_27 & tape_play_27 & ~a_mute_27) ? (tape_in_27 ? 19'sd1536 : -19'sd1536) : 19'sd0;   // la cinta es de A
`else
    wire signed [18:0] tp_snd_27 = (tape_mon_27 & tape_play_27) ? (tape_in_27 ? 19'sd1536 : -19'sd1536) : 19'sd0;
`endif
    // HP3 = proxy de sectores "SD" (zynq/sd_axi_proxy.v) a clk_27m
    wire [5:0]  hp3_awid;   wire [31:0] hp3_awaddr;  wire [3:0] hp3_awlen;   wire [2:0] hp3_awsize;
    wire [1:0]  hp3_awburst, hp3_awlock; wire [3:0] hp3_awcache; wire [2:0] hp3_awprot; wire [3:0] hp3_awqos;
    wire        hp3_awvalid, hp3_awready;
    wire [5:0]  hp3_wid;    wire [63:0] hp3_wdata;   wire [7:0] hp3_wstrb;  wire hp3_wlast, hp3_wvalid, hp3_wready;
    wire [5:0]  hp3_bid;    wire [1:0]  hp3_bresp;   wire hp3_bvalid, hp3_bready;
    wire [5:0]  hp3_arid;   wire [31:0] hp3_araddr;  wire [3:0] hp3_arlen;   wire [2:0] hp3_arsize;
    wire [1:0]  hp3_arburst, hp3_arlock; wire [3:0] hp3_arcache; wire [2:0] hp3_arprot; wire [3:0] hp3_arqos;
    wire        hp3_arvalid, hp3_arready;
    wire [5:0]  hp3_rid;    wire [63:0] hp3_rdata;   wire [1:0] hp3_rresp;  wire hp3_rlast, hp3_rvalid, hp3_rready;
    // GP0 = memoria de ondas del OPL4 (zynq/wave_axi.v, 32 bits) a clk_wave375
    wire [5:0]  gp0_awid;   wire [31:0] gp0_awaddr;  wire [3:0] gp0_awlen;   wire [2:0] gp0_awsize;
    wire [1:0]  gp0_awburst, gp0_awlock; wire [3:0] gp0_awcache; wire [2:0] gp0_awprot; wire [3:0] gp0_awqos;
    wire        gp0_awvalid, gp0_awready;
    wire [5:0]  gp0_wid;    wire [31:0] gp0_wdata;   wire [3:0] gp0_wstrb;  wire gp0_wlast, gp0_wvalid, gp0_wready;
    wire [5:0]  gp0_bid;    wire [1:0]  gp0_bresp;   wire gp0_bvalid, gp0_bready;
    wire [5:0]  gp0_arid;   wire [31:0] gp0_araddr;  wire [3:0] gp0_arlen;   wire [2:0] gp0_arsize;
    wire [1:0]  gp0_arburst, gp0_arlock; wire [3:0] gp0_arcache; wire [2:0] gp0_arprot; wire [3:0] gp0_arqos;
    wire        gp0_arvalid, gp0_arready;
    wire [5:0]  gp0_rid;    wire [31:0] gp0_rdata;   wire [1:0] gp0_rresp;  wire gp0_rlast, gp0_rvalid, gp0_rready;
    wire [23:0] wave_tel;             // telemetria de wave_axi: {lat_max, rd_cnt, wr_cnt}
    // GP1 = puerto de depuracion 34-37h de la memoria de ondas (2a wave_axi, 32 bits) a clk_54m
    wire [5:0]  gp1_awid;   wire [31:0] gp1_awaddr;  wire [3:0] gp1_awlen;   wire [2:0] gp1_awsize;
    wire [1:0]  gp1_awburst, gp1_awlock; wire [3:0] gp1_awcache; wire [2:0] gp1_awprot; wire [3:0] gp1_awqos;
    wire        gp1_awvalid, gp1_awready;
    wire [5:0]  gp1_wid;    wire [31:0] gp1_wdata;   wire [3:0] gp1_wstrb;  wire gp1_wlast, gp1_wvalid, gp1_wready;
    wire [5:0]  gp1_bid;    wire [1:0]  gp1_bresp;   wire gp1_bvalid, gp1_bready;
    wire [5:0]  gp1_arid;   wire [31:0] gp1_araddr;  wire [3:0] gp1_arlen;   wire [2:0] gp1_arsize;
    wire [1:0]  gp1_arburst, gp1_arlock; wire [3:0] gp1_arcache; wire [2:0] gp1_arprot; wire [3:0] gp1_arqos;
    wire        gp1_arvalid, gp1_arready;
    wire [5:0]  gp1_rid;    wire [31:0] gp1_rdata;   wire [1:0] gp1_rresp;  wire gp1_rlast, gp1_rvalid, gp1_rready;

// ============================================================================
// GUARDAS de la matriz ENABLE_* (niquelado B, bug #22 del informe): las
// combinaciones rotas COMPILABAN con nets implicitas de 1 bit sin driver
// (el patron que ya mordio en la _40). Ahora fallan en sintesis instanciando
// un modulo inexistente cuyo NOMBRE es el mensaje de error. Coste cero en
// builds sanos.
`ifdef ENABLE_OPL4_WAVE
 // ZYNQ: la memoria de ondas es zynq/wave_axi.v (DDR del PS): sin WAVE_DDR3 ni LOADER
 `ifndef ENABLE_OPL4FM
    ERROR_ENABLE_OPL4_WAVE_requiere_ENABLE_OPL4FM u_guarda_def3();
 `endif
`endif
`ifdef ENABLE_WAVE_LOADER
 `ifndef ENABLE_WAVE_DDR3
    ERROR_ENABLE_WAVE_LOADER_requiere_ENABLE_WAVE_DDR3 u_guarda_def4();
 `endif
`endif
`ifdef ENABLE_VRAM_AXI
 `ifndef ENABLE_V9968_VDP
    ERROR_ENABLE_VRAM_AXI_requiere_ENABLE_V9968_VDP u_guarda_def5();
 `endif
`endif
// Stubs para builds SIN estos subsistemas (nets que el resto del top consume
// incondicionalmente — sin ellos, net implicita sin driver):
`ifndef ENABLE_CONFIG
    wire config_reset_req = 1'b0;   // warm-reset: sin bloque config no hay peticion
    wire pana41_wr        = 1'b0;   // turbo Panasonic: sin config no hay decode
`endif
`ifndef ENABLE_SDCARD
    wire sd_busy_w = 1'b0;
`endif

initial begin

end
    //`default_nettype none

    //assign SLTSL3 = bus_mreq_disable ^ bus_iorq_disable ^ xffh ^ xffl ^ mapper_read ^ exp_slotx_req_r ^ bios_req ^ subrom_req ^ vdp_csr_n;

    // ===== STANDALONE MERGE: internalized MSX bus signals =====
    // These used to be top-level ports driven/sensed by a real MSX board.
    // Now: data bus is internal, WAIT/INT tied inactive, RESET from button + PLL lock,
    // 3.58MHz CPU clock generated internally. (Ported verbatim from MSXnano/fpga/top.v.)
    wire [7:0] ex_bus_data;          // internal (no external bus); see assign below
    wire ex_bus_wait_n  = 1'b1;      // no external wait
    wire opl4pcm_wait_n;             // _89: /WAIT del motor PCM OPL4 (IN 7Fh)
    wire ex_bus_int_n   = 1'b1;      // INT comes from internal VDP only

    wire clock_locked;
    wire ex_bus_reset_n;
    // Console 60K: los botones S1/S2 son ACTIVOS A NIVEL BAJO (PULL_UP en el CST,
    // reposo=1, pulsado=0 — C64Nano los llama key_*_n). En el TN20K eran activos
    // a nivel ALTO: con el pull-up del 60K, el ~s1 original dejaba ex_bus_reset_n
    // =0 PERMANENTE = todo el core MSX en reset eterno (causa raiz del bring-up
    // muerto 2026-07-07/08). Normalizamos a "press" activo-alto:
    wire s1_press = ~s1;
    wire s2_press = ~s2;
    assign ex_bus_reset_n = ~s1_press && clock_locked && mb_msx_run;   // s1 pulsado = reset; ZYNQ: + MSX_RUN del buzon


    // 108 MHz / 30 = 3.6 MHz internal CPU clock (replaces ex_bus_clk_3m6 pin)
    wire ex_bus_clk_3m6;
    reg [4:0] div30_cnt;
    reg clk_3m6_internal;

    // dangling sinks for the (now internal) bus-control nets the old logic still drives
    wire [1:0] ex_msel;
    wire ex_bus_m1_n;
    wire ex_bus_rfsh_n;
    wire ex_bus_mreq_n;
    wire ex_bus_iorq_n;
    wire ex_bus_rd_n;
    wire ex_bus_wr_n;
    wire ex_bus_data_reverse_n;
    wire [7:0] ex_bus_mp;

    //clocks
    // Console 60K: un unico Gowin_PLL (PLLA GW5A) sustituye a las 3 IPs GW2A
    // (rPLL CLK_108P + CLKDIV /4 + CLKDIV /2). clk_108m_n (fase CLKOUTP del
    // rPLL viejo) no tenia consumidores y se ha eliminado.
    wire clk_108m;
    wire clk_135;               // TMDS x5 del HDMI (mismo VCO: 135 = 5 x 27 exacto)
    wire clk_wave375; // _104: 37.5 MHz del PLLA (motor OPL4) — declarado ANTES
                      // de su primer uso (leccion Gowin de los implicitos)
    // ---- ZYNQ MMCM_A: 50 x 27 = VCO 1350 (el mismo VCO que el PLLA del Tang) ----
    wire mA_fb, mA_fb_b, mA_108, mA_54, mA_27, mA_135, mA_375;
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(20.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(27.000), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(12.500), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),   // 108
        .CLKOUT1_DIVIDE(25),       .CLKOUT1_DUTY_CYCLE(0.5), .CLKOUT1_PHASE(0.0),   //  54
        .CLKOUT2_DIVIDE(50),       .CLKOUT2_DUTY_CYCLE(0.5), .CLKOUT2_PHASE(0.0),   //  27
        .CLKOUT3_DIVIDE(10),       .CLKOUT3_DUTY_CYCLE(0.5), .CLKOUT3_PHASE(0.0),   // 135
        .CLKOUT4_DIVIDE(36),       .CLKOUT4_DUTY_CYCLE(0.5), .CLKOUT4_PHASE(0.0),   //  37.5
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll_main (
        .CLKIN1(ex_clk_27m), .CLKFBIN(mA_fb_b), .CLKFBOUT(mA_fb), .CLKFBOUTB(),
        .CLKOUT0(mA_108), .CLKOUT0B(), .CLKOUT1(mA_54), .CLKOUT1B(),
        .CLKOUT2(mA_27),  .CLKOUT2B(), .CLKOUT3(mA_135), .CLKOUT3B(),
        .CLKOUT4(mA_375), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(clock_locked), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG bA_fb  (.I(mA_fb),  .O(mA_fb_b));
    BUFG bA_108 (.I(mA_108), .O(clk_108m));
    BUFG bA_54  (.I(mA_54),  .O(clk_54m));
    BUFG bA_27  (.I(mA_27),  .O(clk_27m));
    BUFG bA_135 (.I(mA_135), .O(clk_135));
    BUFG bA_375 (.I(mA_375), .O(clk_wave375));

    // clk_27m = CLKDIV ÷5 del 135 (patrón nestang/z8086/Gowin en GW5A): el par
    // PCLK(27)/FCLK(135) de los OSER10 del TMDS queda alineado POR CONSTRUCCIÓN.
    // Dos salidas independientes del PLLA NO garantizan la fase de arranque de
    // sus divisores → serialización TMDS muerta (bring-up 2026-07-07: z8086
    // funcionaba en la placa y nuestro _06 no; este era el delta restante).
    // v2.4: CLKDIV/5 RESTAURADO (el OSER10 lo exige; _28 lo demostro en placa).
    // Su fase vs 54M es arbitraria -> NADA con bus de CPU debe clockear a 27M:
    // el PSG se movio al dominio 54M (v2.4); el arbitro DH/DL queda como unico
    // frente de fase pendiente (F11) — plan B: cruce en el linebuffer.
    // ================================================================
    // v3.0 FASE 1-REDUX: cadena de video 720p CALCADA de monitorcore
    // (la plantilla oficial de nand2mario para esta placa, validada por
    // Albert 10/10 arranques compilada con NUESTRA toolchain). Cascada
    // 50(pad) -> pll_27 -> 27 -> pll_74 -> 74.25 (pixel) + 371.25 (x5
    // TMDS), PLLA crudas identicas a las suyas. El CLKDIV desaparece:
    // clk_27m del MSX sale ahora del PLLA principal (clkout2, arriba) y
    // el HDMI ya no comparte NADA con el arbol del MSX — el cruce es
    // solo el ring BRAM dual-clock + toggles 2FF de msx2hdmi.
    // ================================================================
    wire clk27_video;           // 27M intermedio de la cascada (SOLO alimenta pll_74)
    wire clk_hdmi;              // 74.25 MHz pixel 720p
    wire clk_hdmi5;             // 371.25 MHz TMDS x5
    wire pll27_lock;            // _87: gatea el reset del PLL DDR3 (calib estable)
    // ---- ZYNQ: clk27_video = el 27 de MMCM_A (el Tang usaba un PLL aparte) ----
    assign clk27_video = clk_27m;
    assign pll27_lock  = clock_locked;
    // ---- ZYNQ MMCM_C: 27 x 27.5 = VCO 742.5 -> /10 = 74.25 ; /2 = 371.25 (validado en bringup/hdmi720) ----
    wire mC_fb, mC_fb_b, mC_74, mC_371, mC_lock;
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(37.037), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(27.500), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(2.000), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),   // 371.25
        .CLKOUT1_DIVIDE(10),      .CLKOUT1_DUTY_CYCLE(0.5), .CLKOUT1_PHASE(0.0),   //  74.25
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll74_video (
        .CLKIN1(clk27_video), .CLKFBIN(mC_fb_b), .CLKFBOUT(mC_fb), .CLKFBOUTB(),
        .CLKOUT0(mC_371), .CLKOUT0B(), .CLKOUT1(mC_74), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(mC_lock), .PWRDWN(1'b0), .RST(~clock_locked)
    );
    BUFG bC_fb  (.I(mC_fb),  .O(mC_fb_b));
    BUFG bC_74  (.I(mC_74),  .O(clk_hdmi));
    BUFG bC_371 (.I(mC_371), .O(clk_hdmi5));

    // _84: el OPL3 corre en clk_27m (PLLA principal, HERMANO de clk_54m):
    // cruce host_if emparentado que el STA cronometra (la afifo llevaba
    // ASYNC_REG de Xilinx que Gowin ignora — con PLLs distintos el CDC iba
    // sin blindar: candidato a las escrituras poco fiables de la _82/_83).
    // Sin 3er PLL. El pkg compensa: CLK_DIV_COUNT=545 -> fs 49.541 kHz
    // (+0.05%). pll_3375.v queda en el arbol por si se quiere volver.

    // JTAG→SPI del companion (estilo C64Nano): los pines JTAG se entregan al
    // fabric (SPI del BL616) solo con el PLL en lock y sin petición de JTAG del
    // BL616 (bl616_jtagsel, PULL_UP). Sin término de botón: s2 es el reset MSX
    // y no debe flapear el modo JTAG.
`ifdef ENABLE_WIFI
    // F1 (_73): GPIO28 del BL616 pasa a ser su UART TX (idle ALTO + trafico) ->
    // la mecanica jtagsel/companion queda invalida (el companion-SPI se
    // sacrifica: el teclado sigue por el soft-host USB-A). JTAG fijo en modo
    // JTAG: el flasheo del FPGA via partner queda intacto y sin flapeos.
    assign jtagseln = 1'b0;
`else
`ifdef ENABLE_IOSYS
    // 🚨 CON EL FIRMWARE TANGCORE, V14 YA NO SIGNIFICA "reclamo el JTAG":
    // es el TX de la UART del MCU (GPIO28) a 2 Mbps. Mantener la mecanica
    // C64Nano aqui haria que el fabric arrebatase y soltase los pines JTAG
    // con CADA BIT que mande el MCU -- y son justo los pines por los que el
    // BL616 programa la FPGA.
    // Se le dejan al BL616 y punto. No cuesta nada: el companion SPI que
    // vivia en ellos se mudo al J10 hace tiempo, asi que hoy no hay ni una
    // senal del diseno en esos pads (verificado en el .cst).
    assign jtagseln = 1'b0;
`else
    assign jtagseln = clock_locked & ~bl616_jtagsel;
`endif
`endif

    // ================================================================
    //  VENTILADOR por temperatura, TOMA 2 (_122): en HW la toma 1 no
    //  disparo con el disipador caliente (umbral +30C demasiado alto o
    //  pendiente del anillo menor que la estimada). Albert pide disparo
    //  ~40C: umbral RELATIVO bajado a ~+7-10C sobre el arranque
    //  (K_ON=10/1024 ~1%, K_OFF=5/1024) — con el die tibio deberia
    //  arrancar solo. Fail-safe intacto (anillo muerto -> ON).
    //  TOMA 3 (_123): en HW _122 TAMPOCO disparo con el disipador bien
    //  caliente — la pendiente real del anillo es aun menor. Umbral a
    //  K_ON=5/1024 (~0.5%) y, sobre todo, dbg_cnt del termometro SALE
    //  por el COM11 (4a palabra de la telemetria) para calibrar de una
    //  vez con lecturas reales frio/caliente en vez de seguir adivinando.
    //  TOMA 4 (_124): CALIBRADO con la telemetria de HW _123 — pendiente
    //  real ~6x menor (frio 386400, caliente-que-Albert-quiere-fan
    //  ~385400, WIN 2^17). Umbrales ABSOLUTOS (inmunes al reflasheo en
    //  caliente que envenenaba la baseline relativa) con WIN doblada a
    //  2^18 (menos ruido; cuentas x2: frio ~772800, ON <771600,
    //  OFF >772300).
    // ================================================================
    wire        fan_ro_en, fan_ro_rst;
    wire [19:0] fan_ro_cnt;
    wire [19:0] fan_dbg_cnt;
    //  TOMA 5 (_125): los umbrales ABSOLUTOS de la toma 4 murieron al
    //  rebuild (el anillo de la _124 corria un 8% mas rapido que el de la
    //  _123: la frecuencia depende del placement). Modo RELATIVO con la K
    //  real medida (K_ON=2/1024 = -0.195%, el punto de Albert era -0.26%)
    //  + garantia por tiempo: fan FIJO a los 6 min si no ha disparado.
    // _152: ventilador ~5 grados MAS TARDE + EL DOBLE DE HISTERESIS.
    // Albert reporto DOS cosas: que arranca pronto y que "se enciende y apaga
    // bastante" (ciclado audible, visible en el COM11: la columna fan alterna
    // ON/of cada pocos segundos). Lo segundo es histeresis corta, no umbral.
    // Un paso de K vale 1/1024 = 0.0977% de la cuenta del anillo; con la
    // pendiente REAL medida en placa (~0.0167%/grado, ver cabecera de
    // fan_ctrl.v: 6x menor que la teorica de 0.1%/grado) eso son ~5.9 grados.
    // Subiendo SOLO K_ON se arreglan las dos a la vez: el arranque sube ~5.9
    // grados y la banda pasa de 1 a 2 unidades (~5.9 -> ~11.7 grados), asi que
    // una vez encendido sopla el doble antes de parar y cicla la mitad.
    //   K_ON  2->3 : arranca a ~17.5 grados sobre el frio (antes ~11.7)
    //   K_OFF 1    : para    a  ~5.9 grados sobre el frio (SIN CAMBIO)
    // _173 EXPERIMENTO (peticion de Albert, 03/08): VENTILADOR SIEMPRE ON.
    // Motivo doble: (1) en placa el ventilador NO gira NUNCA, ni siquiera
    // pasados los 360 s de la garantia FORCE_ON_SEC — o sea que o el control
    // no llega al pin o el camino fisico (conector/polaridad/fan) esta mal, y
    // clavar el pin a 1 separa las dos cosas; (2) hay sospecha de margen
    // TERMICO en el arranque (bucle de resets en SCREEN 1 con la placa
    // caliente): con el fan fijo la temperatura deja de ser variable.
    // El fan_ctrl se queda instanciado SOLO como termometro: fan_dbg_cnt
    // sigue saliendo por el COM11 (columna T), su decision se ignora.
    wire fan_en_ctrl;  // decision del control, hoy ignorada (telemetria)
    // ZYNQ: sin ventilador (fan_ctrl + ro_osc fuera)
    assign fan_en_ctrl = 1'b0;
    assign fan_dbg_cnt = 20'd0;
    assign fan_ro_en = 1'b0; assign fan_ro_rst = 1'b0;
    // _175: experimento _173 CERRADO — con el pin a 1 el ventilador giro
    // perfecto en placa (03/08): el camino fisico (AB12/conector/fan) esta
    // BIEN. El "no gira nunca" de las s006/s007 tiene explicacion mundana:
    // sesiones con power-cycle cada 100-200s (up_sec nunca llega a los 360
    // de FORCE_ON_SEC) + baseline envenenada por reflasheo en caliente
    // (leccion _124). Vuelta al control automatico como en la v2.0.
    assign fan_en_o = fan_en_ctrl;
    assign fan_ro_cnt = 20'd0;

    // ================================================================
    //  DEBUG BRING-UP 60K — latidos de reloj y estado vital por PMODs
    // ================================================================
    wire [5:0] dbg_video_w;   // sondas de video r2: {reset_w, video_reset, tick_pal, tick_ntsc, vdp_hdmi_reset, pal_mode}
`ifdef VIDEO720
    wire [5:0] dbg_bridge_w;  // v3.1: diagnostico del puente msx2hdmi (a PMOD0)
`endif
    reg [24:0] dbg_cnt50  = 0;  always @(posedge ex_clk_27m) dbg_cnt50  <= dbg_cnt50  + 1'b1;  // XO 50MHz REAL (independiente del PLL)
    reg [23:0] dbg_cnt27  = 0;  always @(posedge clk_27m)    dbg_cnt27  <= dbg_cnt27  + 1'b1;
    reg [24:0] dbg_cnt54  = 0;  always @(posedge clk_54m)    dbg_cnt54  <= dbg_cnt54  + 1'b1;
    reg [25:0] dbg_cnt108 = 0;  always @(posedge clk_108m)   dbg_cnt108 <= dbg_cnt108 + 1'b1;
    reg [26:0] dbg_cnt135 = 0;  always @(posedge clk_135)    dbg_cnt135 <= dbg_cnt135 + 1'b1;

    // PMOD1 = relojes: [0] lock fijo · [1] 50M · [2] 27M · [3] 54M · [4] 108M · [5] 135M(TMDS)
    // (los assigns de dbg_pmod1 viven en el bloque de debug del final del
    //  fichero, junto a los divisores de frame que los alimentan)

    wire clk_enable_27m;
    wire clk_enable_54m;
    reg [1:0] cnt_clk_enable_27m;
    always @ (posedge clk_108m) begin
        cnt_clk_enable_27m <= cnt_clk_enable_27m + 1;
    end
    assign clk_enable_27m = ( cnt_clk_enable_27m == 2'b00 ) ? 1: 0;
    assign clk_enable_54m = ( cnt_clk_enable_27m[0] == 1 ) ? 1: 0;


    wire bus_clk_3m6;
    PINFILTER dn1(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_clk_3m6),
        .dout(bus_clk_3m6)
    );

    reg bus_clk_3m6_27;
    reg bus_clk_3m6_27_0;
    reg bus_clk_3m6_27_1;
    reg bus_clk_3m6_27_2;
    reg bus_clk_3m6_27_3;
    reg bus_clk_3m6_27_4;
    reg bus_clk_3m6_27_5;
    reg bus_clk_3m6_27_6;

    always @ (posedge clk_27m) begin
        bus_clk_3m6_27_6 <= bus_clk_3m6;
        bus_clk_3m6_27_5 <= bus_clk_3m6_27_6;
        bus_clk_3m6_27_4 <= bus_clk_3m6_27_5;
        bus_clk_3m6_27_3 <= bus_clk_3m6_27_4;
        bus_clk_3m6_27_2 <= bus_clk_3m6_27_3;
        bus_clk_3m6_27_1 <= bus_clk_3m6_27_2;
        bus_clk_3m6_27_0 <= bus_clk_3m6_27_1;
        bus_clk_3m6_27 <= bus_clk_3m6_27_0;
    end

    wire clk_enable_3m6_27;
    wire clk_falling_3m6_27;
    reg bus_clk_3m6_prev_27;
    always @ (posedge clk_27m) begin
        bus_clk_3m6_prev_27 <= bus_clk_3m6_27;
    end
    assign clk_enable_3m6_27 = (bus_clk_3m6_prev_27 == 0 && bus_clk_3m6_27 == 1);
    assign clk_falling_3m6_27 = (bus_clk_3m6_prev_27 == 1 && bus_clk_3m6_27 == 0);

    wire clk_54m;   // Console 60K: generado por pll_main (clkout1); antes Gowin_CLKDIV2 /2

    wire clk_enable_3m6_54;
    wire clk_falling_3m6_54;
    reg bus_clk_3m6_54;
    reg bus_clk_3m6_prev_54;
    always @ (posedge clk_54m) begin
        bus_clk_3m6_54 <= bus_clk_3m6;
        bus_clk_3m6_prev_54 <= bus_clk_3m6_54;
    end
    assign clk_enable_3m6_54 = (bus_clk_3m6_54 == 0 && bus_clk_3m6 == 1);
    assign clk_falling_3m6_54 = (bus_clk_3m6_54 == 1 && bus_clk_3m6 == 0);

    wire bus_wait_n;
    PINFILTER dn2(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_wait_n),
        .dout(bus_wait_n)
    );

    wire bus_reset_n;
    // (Se probo meter aqui un warm-reset pedido por el lanzador y se REVIRTIO:
    // pulsar S1 -- que hace exactamente eso -- NO recuperaba la maquina, o sea
    // que el problema no era ese. Y tocar bus_reset_n es de las cosas mas caras
    // de equivocar: si el termino se queda pegado, la maquina no arranca nunca.)
    PINFILTER dn3(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_reset_n & ~config_reset),
        .dout(bus_reset_n)
    );

    // STANDALONE: generate the 3.58MHz CPU bus clock internally (was ex_bus_clk_3m6 pin).
    // 108 MHz / 30 = 3.6 MHz. (Ported verbatim from MSXnano/fpga/top.v.)
    always @(posedge clk_108m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            div30_cnt <= 0;
            clk_3m6_internal <= 0;
        end else begin
            if (div30_cnt == 5'd14) begin
                clk_3m6_internal <= ~clk_3m6_internal;
                div30_cnt <= 0;
            end else begin
                div30_cnt <= div30_cnt + 1;
            end
        end
    end
    assign ex_bus_clk_3m6 = clk_3m6_internal;

    wire bus_int_n;
//    PINFILTER dn4(
//        .clk(clk_108m),
//        .reset_n(1),
//        .din(ex_bus_int_n),
//        .dout(bus_int_n)
//    );
    denoise dn4 (
		.data_in (ex_bus_int_n),
		.clock(clk_54m),
		.data_out (bus_int_n)
    );

    reg [7:0] bus_data;
    genvar i;
    generate
        for (i = 0; i <= 7; i++)
        begin: bus_din
            PINFILTER dn(
                .clk(clk_54m),
                .reset_n(1),
                .din(ex_bus_data[i]),
                .dout(bus_data[i])
            );
//            denoise2 dn (
//                .data_in (ex_bus_data[i]),
//                .clock(clk_108m),
//                .data_out (bus_data[i])
//            );
        end
    endgenerate

//    always @ (posedge clk_108m) begin
//        bus_data <= ex_bus_data;
//    end

    //startup logic
    reg reset1_n_ff;
    reg reset2_n_ff;
    reg reset3_n_ff;
    wire reset1_n;
    wire reset2_n;
    wire reset3_n;

    reg [20:0] counter_reset = 0;
    reg [1:0] rst_seq;
    reg rst_step;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            rst_step <= 0;
            counter_reset <= 0;
        end
        else begin
            rst_step <= 0;
            if ( counter_reset <= 21'b100000000000000000000 ) 
                counter_reset <= counter_reset + 1;
            else begin
                rst_step <= 1;
                counter_reset <= 0;
            end
        end
    end

    always @ (posedge clk_27m or negedge bus_reset_n ) begin
        if (bus_reset_n == 0 ) begin
            rst_seq <= 2'b00;
            reset1_n_ff <= 0;
            reset2_n_ff <= 0;
            reset3_n_ff <= 0;
        end
        else begin
            case ( rst_seq )
                2'b00: 
                    if (rst_step == 1 ) begin
                        reset1_n_ff <= 1;
                        rst_seq <= 2'b01;
                    end
                2'b01: 
                    if (rst_step == 1) begin
                        reset2_n_ff <= 1;
                        rst_seq <= 2'b10;
                    end
                2'b10:
                    if (rst_step == 1) begin
                        reset3_n_ff <= 1;
                        rst_seq <= 2'b11;
                    end
            endcase
        end
    end
    assign reset1_n = reset1_n_ff;
    assign reset2_n = reset2_n_ff;
    assign reset3_n = reset3_n_ff;

    //bus demux
    reg [1:0] msel;
    reg [7:0] bus_mp;
    reg [4:0] mp_cnt;
    wire [15:0] bus_addr;
    assign ex_msel = msel;
    assign ex_bus_mp = bus_mp;

    localparam IDLE = 2'd0;
    localparam LATCH = 2'd1;
    localparam FINISH1 = 2'd3;
    localparam FINISH2 = 2'd2;
    localparam [3:0] TON = 4'd3;
    localparam [3:0] TP = 4'd1; //prefetch time
    reg [1:0] state_demux;
    reg [3:0] counter_demux_n;
    reg [3:0] counter_demux;
    reg low_byte_demux;
    wire update_demux;
    assign bus_mp = ( low_byte_demux == 0 ) ? bus_addr[15:8] : bus_addr[7:0];
    always @ (posedge clk_108m) begin
        if (~bus_reset_n) begin
            state_demux <= LATCH;
            counter_demux <= 4'd0;
            low_byte_demux <= 0;
        end 
        else begin
            counter_demux_n = counter_demux + 4'd1;   // ZYNQ: sin asignacion mixta
            counter_demux <= counter_demux_n;
            casex ({state_demux, counter_demux_n})
                {IDLE, 4'bxxxx}: begin
                    msel <= 2'b00;
                    counter_demux <= 4'd0;
                    low_byte_demux <= 0;
                    if (update_addr == 1 ) begin
                        state_demux <= LATCH;
                    end
                end
                {LATCH, 4'd1} : begin
                    msel[1] <= 1;
                end
                {LATCH, 4'd1 + TON} : begin
                    msel[1] <= 0;
                end
                {LATCH, 4'd1 + TON + TP} : begin
                    low_byte_demux <= 1;
                end
                {LATCH, 4'd1 + TON + TP + TP} : begin
                    msel[0] <= 1;
                end
                {LATCH, 4'd1 + TON + TP + TP + TON} : begin
                    msel[0] <= 0;
                    msel[1] <= 0;
                    state_demux <= FINISH1;
                end
                {FINISH1, 4'bxxxx}: begin
                    if (update_addr == 0 ) begin
                        state_demux <= IDLE;
                    end
                end
                {FINISH2, 4'bxxxx}: begin
                    if (update_addr == 0 ) begin
                        state_demux <= IDLE;
                    end
                end
            endcase
        end
    end




    //bus isolation
    wire bus_data_reverse;
    wire bus_m1_n;
    wire bus_mreq_n;
    wire bus_iorq_n;
    wire bus_rd_n;
    wire bus_wr_n;
    wire bus_rfsh_n;
    reg [7:0] cpu_din;
    wire [7:0] cpu_dout;
    // Perfil TR (fase 2): mapa de slots del FS-A1ST cuando el companion ha dejado la BIOS del turbo R en la DDR (MBOX+0x1C bit 6).
    // Se declaran aqui porque el mux de lectura (cpu_din) y el de ram_addr los usan antes de su logica (mas abajo, "perfil TR").
    // Sin ENABLE_TR son constantes y la sintesis es la de siempre.
`ifdef ENABLE_TR
    reg         tr_map = 1'b0;           // 1 = mapa FS-A1ST (BIOS turbo R en la DDR); 0 = el MSX2+ normal con R800 disponible
    wire        trm_req;                 // lectura de una ROM/DRAM del firmware: ram_addr = trm_addr (tr_rommap)
    wire [23:0] trm_addr;
    wire [7:0]  trm_ovd;
    wire        trm_ovr;                // tr_rommap: esta lectura devuelve 00h (firma "APRLOPLL" de la ventana del menu en el 0-1)
    wire        dram_mode_w;             // S1990 R#6 bit 6 = 0 (en 54 MHz)
    wire        tr_mapper_rd;            // lectura de FCh-FFh (los registros del mapper se pueden releer)
    wire [7:0]  tr_mapper_rdv;
    wire        trpcm_rd;                // lectura de A4h/A5h: PCM del turbo R (tr_pcm)
    wire [7:0]  trpcm_dout;
    wire [7:0]  trpcm_dac;
    wire        trpcm_mute;              // A5h bit 1 = 0: todo el sonido en silencio
`else
    wire        tr_map = 1'b0;
    wire        trm_req = 1'b0;
    wire [23:0] trm_addr = 24'd0;
    wire        dram_mode_w = 1'b0;
`endif
    wire bus_mreq_disable;
    wire bus_iorq_disable;
    wire bus_disable;
    assign ex_bus_m1_n = bus_m1_n;
    assign ex_bus_rfsh_n = bus_rfsh_n;
    assign ex_bus_data_reverse_n = ~ bus_data_reverse;
    //assign ex_bus_data_reverse = bus_data_reverse;
    //assign ex_bus_mreq_n = bus_mreq_n;
    //assign ex_bus_iorq_n = bus_iorq_n;
    //assign ex_bus_rd_n = bus_rd_n;
    //assign ex_bus_wr_n = bus_wr_n;

    assign bus_mreq_disable = 0;
    assign bus_iorq_disable = (
                                0
                        `ifdef ENABLE_V9958
                                || vdp_csr_n == 0 || vdp_csw_n == 0 
                        `endif 
                                ) ? 1 : 0;

    assign bus_disable = bus_mreq_disable | bus_iorq_disable;
//    assign ex_bus_data = ( bus_data_reverse == 1 && slot0_req_w == 0 ) ? cpu_dout : 
//                         ( slot0_req_w == 1 ) ? 8'hff :  8'hzz;
`ifndef SWAP23
    assign ex_bus_data =  ( bus_data_reverse == 1 ) ? cpu_dout : 8'hzz;
`else

    function [1:0] swap;
        input [1:0] entrada;
        begin
            case (entrada)
                2'b00: swap = 2'b00;
                2'b01: swap = 2'b01;
                2'b10: swap = 2'b11;
                2'b11: swap = 2'b10;
                default: swap = 2'b00; // Por seguridad
            endcase
        end
    endfunction

    wire [7:0] cpu_dout_swap;
    assign cpu_dout_swap = { swap(cpu_dout[7:6]), swap(cpu_dout[5:4]), swap(cpu_dout[3:2]), swap(cpu_dout[1:0]) };

    reg ppi_swap;
    always @ (posedge clk_27m) begin
        if (~bus_reset_n) begin
            ppi_swap <= 0;
        end
        else begin
            if (ppi_swap == 0) begin
                if (bus_data_reverse == 1  && ppi_req_w == 1) begin
                    ppi_swap <= 1;
                end
            end
            else begin
                if (bus_data_reverse == 0) begin
                    ppi_swap <= 0;
                end
            end
        end
    end

    assign ex_bus_data =  ( bus_data_reverse == 1  && ppi_swap == 0) ? cpu_dout :
                          ( bus_data_reverse == 1  && ppi_swap == 1) ? cpu_dout_swap : 8'hzz;
`endif

// ===== STANDALONE MERGE: USB joystick (PSG 0xA2/reg14) — ported from MSXnano/fpga/top.v =====
wire psg_req_r;
assign psg_req_r = (bus_addr[7:0] == 8'hA2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0) ? 1 : 0;

// Gamepads USB. Antes los servia el companion SPI (el ESP32-S3); desde el
// 25/08 los lee el BL616 y llegan por hid1/hid2 del iosys (comando 9).
wire [7:0] joystick0;
wire [7:0] joystick1;

// Track which PSG register was last latched via I/O A0h
reg [3:0] psg_addr_latch;
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n)
        psg_addr_latch <= 4'd0;
    else if (bus_addr[7:0] == 8'hA0 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1)
        psg_addr_latch <= cpu_dout[3:0];
end

// Seleccion de puerto de joystick: registro 15 del PSG, BIT 6 Y SOLO EL BIT 6.
//   bit6 = 0 -> puerto 1     bit6 = 1 -> puerto 2
//
// ⚠️ CORREGIDO 18/08. Antes esto miraba los bits [7:6] y trataba el bit 7 como
// "seleccionar puerto 2" activo a nivel bajo. El bit 7 del registro 15 NO es
// un selector: es el LED DE KANA. Con el bit 7 en alto (que es lo normal, LED
// apagado) el puerto 2 devolvia 0xFF SIEMPRE, hiciera lo que hiciera el
// software. Por eso el raton no se detectaba, y por eso el joystick USB del
// puerto 2 tampoco podia funcionar.
//
// Verificado contra el One Chip MSX (esemsx3/src/sound/psg/psg.vhd:115-119),
// que lo dice con todas las letras:
//     -- psg register #15 bit6 - joystick select : 0=port-a, 1=port-b
// y en la misma fuente, los pines 8: stra <= regb(4), strb <= regb(5).
reg psg_reg15_port2;
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n)
        psg_reg15_port2 <= 1'b0;
    else if (bus_addr[7:0] == 8'hA1 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1
             && psg_addr_latch == 4'd15)
        psg_reg15_port2 <= cpu_dout[6];
end

// ===== AUTOFIRE (turbo) on the otherwise-unused joystick buttons 3 & 4 =====
// The FPGA-Companion joy byte uses bits 0-5 (dirs + A + B); bits 6/7 carry the
// extra pad buttons 3/4 (unused by the MSX 2-button joystick). While button 3
// is held it pulses TrigA, button 4 pulses TrigB, at ~10 Hz (50 ms ON / 50 ms
// OFF). Each phase must outlast one MSX PSG scan (~1 frame @50/60 Hz) so every
// press AND release is sampled; 50 ms = 2.5-3 frames is safe even on PAL.
// Ported from the goauld+RP2040 fork (there it lived in firmware; here, no
// RP2040 -> it lives in the FPGA on the PSG joystick-injection path).
//   54 MHz * 0.050 s = 2,700,000 cycles per half period.
reg        af_phase = 1'b0;
reg [21:0] af_cnt   = 22'd0;
always @(posedge clk_54m) begin
    if (af_cnt >= 22'd2700000) begin
        af_cnt   <= 22'd0;
        af_phase <= ~af_phase;
    end else begin
        af_cnt   <= af_cnt + 22'd1;
    end
end
// fire = manual press OR (autofire button held AND square-wave high). If the pad
// has no button 3/4 (bits 6/7 stay 0) this reduces to the original behaviour.
wire af_fa0 = joystick0[4] | (joystick0[6] & af_phase);   // joy0 TrigA: manual + btn3 turbo
wire af_fb0 = joystick0[5] | (joystick0[7] & af_phase);   // joy0 TrigB: manual + btn4 turbo
wire af_fa1 = joystick1[4] | (joystick1[6] & af_phase);   // joy1 TrigA
wire af_fb1 = joystick1[5] | (joystick1[7] & af_phase);   // joy1 TrigB

// Companion joy byte (active-high): bit0=Right, bit1=Left, bit2=Down, bit3=Up, bit4=A, bit5=B
// MSX PSG Port A (active-low):      bit0=Up,    bit1=Down,  bit2=Left, bit3=Right, bit4=TrigA, bit5=TrigB
wire [7:0] joy0_msx = {2'b11, ~af_fb0, ~af_fa0, ~joystick0[0], ~joystick0[1], ~joystick0[2], ~joystick0[3]};
wire [7:0] joy1_msx = {2'b11, ~af_fb1, ~af_fa1, ~joystick1[0], ~joystick1[1], ~joystick1[2], ~joystick1[3]};
// ===== RATON MSX (era V3) =====
// Emulado sobre un raton USB de PC. Vive en el PUERTO 2, que es donde lo
// espera el software de MSX, y solo se hace cargo del puerto cuando hay un
// raton USB enchufado; si no lo hay, el puerto 2 sigue siendo joystick como
// siempre. El protocolo entero esta en fpga/src/msx_mouse.v (y su banco en
// tools/mouse_sim). Los drivers detectan el raton solos ejecutando el
// handshake, asi que no hay nada que configurar en el MSX.
wire [7:0] msx_mouse_data;      // lo que el raton presenta en el registro 14
wire       msx_mouse_present;   // hay un raton USB vivo

wire [7:0] psg_joy_data_raw = (!psg_reg15_port2) ? joy0_msx
                                                  : (msx_mouse_present ? msx_mouse_data
                                                                       : joy1_msx);
wire [7:0] psg_joy_data = {tape_in_27, psg_joy_data_raw[6:0]};   // ZYNQ Z1.1: bit 7 = CASRD (cinta virtual del buzon)

// ===== STANDALONE MERGE: USB keyboard (PPI port B 0xA9 read / port C 0xAA latch) =====
wire ppi_portb_req_r = (bus_addr[7:0] == 8'hA9 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0) ? 1 : 0;
wire ppi_portc_req_w = (bus_addr[7:0] == 8'hAA && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0);

// 🚨 PUERTO ABh — REGISTRO DE CONTROL DEL 8255. Faltaba, y por eso el LED de
// CAPS no funcionaba NUNCA (descubierto el 26/08 al no verse en el OSD).
//
// El MSX no enciende el CAPS escribiendo el puerto C entero por AAh: la rutina
// CHGCAP de la BIOS hace `OUT (0ABh),A` con el comando de BIT SET/RESET del
// 8255. Sin decodificar ABh esa escritura se perdia y ppi_port_c[6] se quedaba
// como estuviera. Como su unico consumidor era la tira WS2812 (que no siempre
// esta conectada), el fallo llevaba ahi sin que nadie lo viera.
//
// Formato del comando (bit 7 = 0 lo distingue del comando de MODO, que no nos
// afecta porque el modo del PPI del MSX es fijo):
//     bit 7   = 0   -> bit set/reset
//     bits 3:1      -> que bit del puerto C
//     bit 0         -> 1 = ponerlo, 0 = quitarlo
// Con esto funcionan de golpe los tres usos reales del MSX: LED de CAPS (bit 6),
// click de tecla (bit 7) y motor del casete (bit 4).
wire ppi_ctrl_req_w = (bus_addr[7:0] == 8'hAB && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0);

// 🚨 LECTURA DEL PUERTO C (AAh) — FALTABA, Y ERA LA CAUSA DE RAIZ.
//
// El 8255 en modo 0 con el puerto C de salida deja RELEER el latch, y la BIOS
// del MSX cuenta con ello: para cambiar de fila de teclado hace
//     IN A,(0AAh) / AND 0F0h / OR fila / OUT (0AAh),A
// o sea LEE, conserva los bits altos (CAPS, click, motor) y devuelve el byte.
//
// Sin camino de lectura, ese IN devolvia FF del bus flotante -> la BIOS se
// quedaba con F0 -> y escribia F0|fila, BORRANDO los tres bits altos en CADA
// barrido del teclado (~60 veces por segundo).
//
// Medido en placa el 26/08 con la sonda del OSD: `ab6 225` (la BIOS SI escribia
// el bit del CAPS por ABh, 225 veces) y `PC FA` (= F0|fila 10) -- el valor
// exacto que predice esta explicacion.
//
// Esto es tambien la causa REAL del bug del motor de casete del MSXnano, que
// alli se parcheo con un registro aparte (`cas_motor_on`): no era solo que
// faltara decodificar ABh, es que ademas le borraban el bit.
wire ppi_portc_req_r = (bus_addr[7:0] == 8'hAA && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0);

wire [3:0] keyboard_addr;
reg [7:0] keyboard_data;
wire [1:12] function_keys;

reg [7:0] ppi_port_c = 8'h00;   // R4: ppi_port_c did not exist in base — created here
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n)
        ppi_port_c <= 8'h00;
    else if (ppi_portc_req_w)
        ppi_port_c <= cpu_dout;
    else if (ab_fin && ab_dat[7] == 1'b0)
        ppi_port_c[ab_dat[3:1]] <= ab_dat[0];
end

// 🚨 EL BIT SET/RESET SE APLICA UNA VEZ, AL TERMINAR LA ESCRITURA.
//
// La primera version lo hacia por NIVEL (`if (ppi_ctrl_req_w) ...`), igual que
// la escritura de AAh. Para AAh eso es inofensivo: escribe el byte ENTERO en
// cada flanco y gana el ultimo, que es el estable. Pero aqui el dato elige
// QUE BIT se toca, asi que un valor intermedio inestable escribe un bit AL AZAR
// -- incluyendo los bits 0..3, que son la SELECCION DE FILA DEL TECLADO.
//
// La pista estaba delante y la desprecie: la sonda del 26/08 veia pasar valores
// como 0xD0 y 0xF7, con el bit 7 a uno, o sea comandos de MODO del 8255 que
// ninguna BIOS manda a ese ritmo. Eran datos a medio formar. Con el uso normal
// no se notaba porque la BIOS reescribe constantemente; con INDEV.COM, que
// sondea el hardware a conciencia, la maquina se colgaba.
//
// Ahora se sigue el dato mientras dura la escritura y se aplica UNA sola vez,
// en el flanco de subida de la peticion, con el ultimo valor -- que es el que el
// Z80 mantiene hasta el final del ciclo.
reg       ab_req_d = 1'b0;
reg [7:0] ab_dat   = 8'd0;
wire      ab_fin   = ab_req_d & ~ppi_ctrl_req_w;
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n) begin
        ab_req_d <= 1'b0; ab_dat <= 8'd0;
    end else begin
        ab_req_d <= ppi_ctrl_req_w;
        if (ppi_ctrl_req_w) ab_dat <= cpu_dout;
    end
end

// SONDA (26/08): ¿escribe la BIOS en ABh, y con que? Sin esto solo se puede
// adivinar. Se manda en el estado del OSD reaprovechando los dos bytes que
// eran del termometro (retirado por inutil).
assign keyboard_addr = ppi_port_c[3:0];

    // FPGA/bitstream version readable on I/O port 0x2F. The boot menu reads it and
    // warns if you flashed mismatched .fs/.bin (e.g. a v1.8 bitstream + a v1.7 BIOS pack).
    // Encoding 0xMN = version M.N. Bump FPGA_VERSION each release together with the pack.
    //
    // era V3 (18/08): 0x19 -> 0x30. La linea v3 es la version 3.0, la primera
    // sin SSRAM (problema de silicio del GW5AT-60B) y la que estrena el raton
    // MSX sobre raton USB.
    //
    // ⚠️ ESTO VA EMPAREJADO CON EL PACK. El menu de arranque compara este byte
    // con el que espera y AVISA si no cuadra. El fuente del menu NO esta en
    // este repo (docs/ROADMAP.md:39: "traerlo a la carpeta menu/ cuando toque
    // tocarlo"), asi que hasta que se regenere el pack con el menu esperando
    // 0x30, arrancar este bitstream con el pack_bios_v2.1b da un aviso de
    // version desemparejada. Es cosmetico -- el sistema arranca igual -- pero
    // hay que cerrarlo antes de publicar la 3.0.
    // V3.5 (06/09/2026): 0x30 -> 0x35. Ajustes lo muestra como "3.5".
    localparam [7:0] FPGA_VERSION = 8'hA4;   // ZYNQ Z1.4 (04/11/2026: perfiles y todo lo acumulado en las betas). Antes, Z1.3 (Z1.3.1 = 30/10/2026: la beta pasa a version, como arreglo de la Z1.3; orden de Albert) (escritorio del V9990 por el ARM, reloj, ROM con disco, 4:3 Scale3x; del S1990 solo el temporizador). A3 = Z1.3 (30/10/2026): la fusion HDMI (compositor V9991: una sola salida a 60 Hz, ventana del V9968 en el V9990). A2 = Z1.2 (18/09/2026): Z1.1 + TSX.LOAD, File-Hunter cas/tsx (cinta web)
    // 27/09/2026: tercer digito de version (arreglos) por el puerto #29, como en el 60K (3.7.1).
    // Z1.2.1 (30/09/2026): los tres arreglos del upstream de HRA del 29/09 (latch del puerto 1, DIY con el origen arriba,
    // paso de pixel registrado) sobre todo lo acumulado desde la Z1.2.
    // Z1.2.2 (30/09/2026): OSD con color (textdisp_z.v: atributo por celda, paleta de 16, 256 glifos) y actualizacion
    // por red (companion/ota.c, FSBL propio con la ranura B).
    // Z1.2.3 (01/10/2026): el mismo hardware que la Z1.2.2; el numero acompana al paquete nuevo (menu, Ajustes y OSD
    // en castellano o en ingles, cuatro variantes por red: Nextor 2.1.4/3 x castellano/ingles).
    // Z1.2.4 (05/10/2026): arreglo del OPL4: los registros de slot del wavetable se releen bien a la primera por 7Fh
    // (f5f71a6). Arreglo = tercer digito; solo por actualizacion desde msx.barcelona, sin release.
    // Z1.2.5 (13/10/2026): el OPL4 en canon: F8 = 1Bh tras el reset (FM a -9 dB, como el chip), vibrato y tremolo del
    // FM como el YMF262 (fpga/opl3: LFO una vez por muestra y con signo, AM del propio slot), timer parado en el ciclo
    // critico; el companion comprueba la suma de la YRW801 (panel F12). Solo por actualizacion desde msx.barcelona.
    // Z1.2.6 (13/10/2026): NEW2 del OPL4 tambien con el dato por C5h (el chip tiene un solo latch de direccion FM):
    // los discos del "MoonBlaster Wave BASIC driver" de Moonsoft (OUT C6h,05h + OUT C5h,03h) callaban sin error.
    // Z1.2.7 (13/10/2026): el motor wave del OPL4 como el chip: margen de 24 canales (-15 dB por canal y 19 bits; antes
    // recortaba y envolvia), TL con LD=0 bien, envolvente (OCT+RC, pasos, ataque) y pan a -3 dB/paso; el wave entra x2
    // (-3 dB por canal frente a la Z1.2.6).
    localparam [7:0] FPGA_PATCH   = 8'd7;   // Z1.4.7 (beta 11/11/2026: V9990 con los arreglos de openMSX de noviembre -LINE, NX=4096, BD/BX, P1 LMMV, SY/DY de vuelta- y el shim con el mux del VB AND-OR). Z1.4.6 (beta 10/11/2026: latch de R#23 y LMCM de HRA!, cache de sprites del shim por Space Manbow). Z1.4.5 (beta 10/11/2026: V9968 de HRA! v0.96-v0.98: 5S AND NOT F, mezcla de sprites en la fase 4, franja B de los comandos). Z1.4.2 a Z1.4.4 no tocaron el PL. Z1.4.1 (05/11/2026: ROM de 4 MB o mas en TR, perfil TRV). Z1.4.0. Antes, Z1.3.2 (beta 30/10/2026: espejo del geo3d en 8Dh/8Fh). Z1.3.1 (30/10/2026): escritorio del V9990 por el ARM, reloj, ROM con disco, 4:3 Scale3x, S1990 solo temporizador. Z1.3.0 (30/10/2026): primera de la linea Z1.3. En la rama del V9991 llego a 20 (V9991h); antes, Z1.2.13 = 12 (Ajustes lo pintaba en hex: Z1.2.C)
                                            // Z1.2.11 = 21/10/2026: V9990, R#17/R#21 reinician la cuenta de lineas (split de Xybots), G de la paleta por P#1, glue a prueba de rebotes
                                            // Z1.2.10 = 16/10/2026: envolvente del OPL4 parada en -60 dB, DL=0 directo, LFO exacto, flags de LD A,I/LD A,R
                                            // Z1.2.9 = 15/10/2026: ruido de MBWave (LevelAddTLALFO), mux REG_RD, LFORST, DL, NEW2, shadow, modo memoria
    wire ver_req_r = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0 && bus_addr[7:0] == 8'h2F);
`ifdef ENABLE_MUSICA
    // perfil Musica: salidas de musica_sound (la instancia esta junto a la E/S conmutada, cuando ya existen config_ok y pana_sel)
    wire        mus_sel;                 // musica_sound contesta la lectura en curso
    wire [7:0]  mus_dout;
    wire        mus_int_n;               // IRQ de los temporizadores del YM2151
    wire signed [15:0] mus_sfg_l, mus_sfg_r;   // YM2151
    wire signed [10:0] mus_sn;                 // SN76489
`endif
    // 2Fh y 29h en UN solo termino del mux de cpu_din (un escalon mas en esa cadena costo -0,1 ns en el 60K): las dos
    // constantes se eligen por bus_addr[2] (2Fh = ...1111, 29h = ...1001) y la sintesis las pliega por bit.
    wire verpat_req_r = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0 && bus_addr[7:3] == 5'b00101 && bus_addr[0] == 1'b1 && bus_addr[2] == bus_addr[1]);
    wire [7:0] verpat_data = bus_addr[2] ? FPGA_VERSION : FPGA_PATCH;

    // Puerto 0x2E — DIAGNOSTICO DEL RATON. Desde BASIC: PRINT HEX$(INP(&H2E))
    //   bit7 = hay raton USB detectado (typ==2 en alguno de los USB-A)
    //   bit6 = el MSX tiene seleccionado el PUERTO 2 (reg15 bit6)
    //   bit5 = nivel del pin 8 del puerto 2 (reg15 bit5) = el strobe
    //   bit4..2 = fase de la maquina del raton (0..7)
    //   bit1..0 = cuenta de informes USB recibidos (deberia cambiar al mover)
    // Lo que dice cada cosa si el raton no va:
    //   bit7=0            -> el USB no lo ha enumerado como raton
    //   bit7=1, bit6=0    -> el software esta sondeando el PUERTO 1, no el 2
    //   bit5 no cambia    -> el software no mueve el pin 8: no habla el protocolo
    //   bits1..0 quietos  -> el raton USB no envia informes
    wire mdbg_req_r = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0 && bus_addr[7:0] == 8'h2E);
    wire [7:0] mouse_dbg = {msx_mouse_present, psg_reg15_port2, psgPB[5], msx_mouse_phase, mo_rep_cnt[1:0]};

    // Puerto 0x2D — DIAGNOSTICO DEL LADO USB. PRINT HEX$(INP(&H2D))
    //   bit7   = error de conexion en USB2
    //   bit6   = error de conexion en USB1
    //   bit5-4 = typ de USB2   (0 nada, 1 teclado, 2 RATON, 3 gamepad)
    //   bit3-2 = typ de USB1
    //   bit1-0 = cuenta de informes de CUALQUIER tipo (mueve el raton: si esto
    //            cambia, el USB habla; si no, no llega nada)
    // Este puerto existe porque el 0x2E solo dice "no hay raton" sin decir POR
    // QUE: con el typ a la vista se distingue "no enumerado" de "enumerado como
    // otra cosa" (que es lo que pasaba: los ratones sin subclass Boot se
    // clasificaban como gamepad).
    wire udbg_req_r = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0 && bus_addr[7:0] == 8'h2D);
    wire [7:0] usb_dbg = {usb2_conerr, usb1_conerr, usb2_typ, usb1_typ, any_rep_cnt[1:0]};
    always @ (posedge clk_54m) begin
        cpu_din <=
                ( verpat_req_r == 1 ) ? verpat_data :
                ( mdbg_req_r == 1 ) ? mouse_dbg :
                ( udbg_req_r == 1 ) ? usb_dbg :
                // 🚨 14/09: el reg. 15 TIENE que releerse (psgPB = lo ultimo escrito). Devolviendo FFh,
                // la interrupcion de la BIOS (gatillos: `AND AFh OR 03h` puerto 1 / `AND DFh OR 4Ch`
                // puerto 2, lee-modifica-escribe) conmutaba el pin 8 del puerto 2 CADA FRAME y el
                // raton MSX (msx_mouse) perdia sus deltas en ciclos fantasma (PAD(17/18) = 0).
                // Cazado en la Zynq con la telemetria de escrituras al reg. 15 (valores DF/AF/DF...).
                ( psg_req_r == 1 ) ? ((psg_addr_latch == 4'd14) ? psg_joy_data :
                                      (psg_addr_latch == 4'd15) ? psgPB : psg_dout) :   // 31/10: 0-13 = el registro (antes FFh: VGMPlay no veia el PSG interno)
                `ifdef ENABLE_SOUND
                     ( psg2_req_r == 1 ) ? psg2_dout :
                `endif
                ( ppi_portb_req_r == 1 ) ? keyboard_data :
                `ifdef ENABLE_V9958
                     ( vdp_csr_n == 0) ? vdp_dout_m :
                `endif
                `ifdef ENABLE_V9990
                     ( v99_csr_n == 0) ? v99_dout_m :    // V9990: puertos 60h-6Fh
                `endif
                `ifdef ENABLE_MAPPER
                     ( mapper_read == 1) ? ram_dout :
                `endif
                `ifdef ENABLE_TR
                     ( trm_req == 1 ) ? (trm_ovr ? trm_ovd : ram_dout) :   // TR: ROM del firmware / DRAM (BIOS, SUB-ROM, MSX-MUSIC, apertura, driver kanji, menu, ROM del ESP)
                     ( trpcm_rd == 1 ) ? trpcm_dout :                  // TR: PCM A4h/A5h
                     ( tr_mapper_rd == 1 ) ? tr_mapper_rdv :    // TR: los registros del mapper (FCh-FFh) se releen (7 bits: 128 segmentos)
                `endif
                `ifdef ENABLE_BIOS
                     ( exp_slot0_req_r == 1) ? ~exp_slot0  :
                     ( exp_slotx_req_r == 1) ? ~exp_slotx  :
                     ( bios_req == 1) ? ram_dout :
`ifdef DISABLE_BOOT_MENU
                     // _127D: SIN MENU — se enmascara la firma "AB" del menu
                     // (slot expandido, bytes 0x4000/0x4001): el slot-scan de
                     // la BIOS no ve cartucho y el MSX arranca DIRECTO.
                     // OJO: tambien salta el init encadenado de esa pagina
                     // (FM-BIOS del pack) — build de prueba, no de uso diario.
                     ( subrom_logo_req == 1 ) ? ((bus_addr[14:1] == 14'h2000) ? 8'h00 : ram_dout) :
`else
                     ( subrom_logo_req == 1 ) ? ram_dout :
`endif
                `endif
                `ifdef ENABLE_SDCARD
                     ( sd_busreq_w == 1) ? sd_cd_w :
                     ( sram_busreq_w == 1) ? sram_cd_w :
                     ( megarom_req == 1) ? ram_dout :
                     //( slot3_req_r == 1) ? 8'hff :
                 `endif
                `ifdef ENABLE_SOUND
                     ( megaram_req == 1 ) ? ram_dout:
                     ( gm2_mem_req == 1 ) ? ram_dout:      // V3.5f: Game Master 2 en el slot 1
                     ( scc_rd_r == 1 ) ? scc_dout:
                     ( scc2x_rd_r == 1 ) ? scc2x_dout:
                    `ifdef ENABLE_Y8950
                     ( y8950_rd_r == 1 ) ? y8950_dout :   // C0/C1: status (IRQ/timer) del MSX-Audio
                    `endif
                    `ifdef ENABLE_OPL4FM
                     ( opl4fm_rd_w == 1 ) ? opl4fm_dout :     // C4-C7: status/shadow del OPL3
                     `ifdef ENABLE_OPL4_WAVE
                     ( opl4pcm_rd_w == 1 ) ? opl4pcm_dout :   // 7E/7F: motor PCM real (_89)
                     `else
                     ( opl4wave_rd_w == 1 ) ? opl4wave_dout : // 7F: stub wave (device ID)
                     `endif
                    `endif
                    `ifdef ENABLE_OPL4_WAVE   // ZYNQ: puerto 34-37h sobre wave_axi/GP1
                     ( wdbg_rd34_w == 1 ) ? wdbg_diag_ddr3 :  // 34h: diag DDR3 (_95)
                     ( wdbg_rd35_w == 1 ) ? wdbg_diag_eng :   // 35h: diag motor (_95)
                     ( wdbg_rd36_w == 1 ) ? wdbg_status :     // 36h: {err,ret,done,act,busy,rdy}
                     ( wdbg_rd37_w == 1 ) ? wdbg_rdata :      // 37h: byte DDR3 prefetchado
                    `endif
                `endif
                `ifdef ENABLE_MUSICA
                     ( mus_sel == 1 ) ? mus_dout :   // perfil Musica: SFG (ROM propia y estado del OPM, ranura 0-1), contadores de Franky (48h-49h), PlaySoniq (2Bh)
                `endif
                `ifdef ENABLE_CONFIG
                `ifdef ENABLE_TR
                     // D4h (OCM) y 08h (Panasonic) responden, pero leer 40h no los delata: Z80BENCH y SofaRun buscan OUT 40h,id / IN 40h = ~id. Un turbo R real sale sin marca
                     ( config_req == 1 && bus_addr[7:0] == 8'h40 && (config0_ff == 8'h2b || config0_ff == 8'hf7) ) ? 8'hff :
                `endif
                     ( config_req == 1 && pana_sel == 1 ) ? pana_dout :
                     ( config_req == 1 && config_ok == 1) ? config_dout :
                     ( config_req == 1 && config_ok == 0) ? swio_dout :
                `endif
                     ( menu2_req == 1 ) ? ram_dout :
                     ( kanji_data_req_r == 1 ) ? ram_dout :
                `ifdef ENABLE_WIFI
                     ( wifi_req == 1 ) ? ram_dout :
                     ( f2_req_r == 1 ) ? f2_port :
                     ( uart_req == 1 ) ? uart_dout :
                `endif
                     ( logo_req == 1 ) ? ram_dout :
                `ifdef ENABLE_S1990_TIMER
                     ( s1990_req == 1 ) ? s1990_dout :   // E6h-E7h (E4h-E7h con ENABLE_TURBOR_ID): S1990 del turboR
                `endif
                     ( rtc_req_r == 1 ) ? rtc_dout :
                     ( ppi_portc_req_r == 1 ) ? ppi_port_c :   // AAh: releer el latch del puerto C
                     ( ppi_req_r == 1 ) ? ppi_port_a :
                     ( slot0_req_r == 1 ) ? 8'hff :
                     ( slotx_req_r == 1 ) ? 8'hff :
                      8'hFF;   // STANDALONE: was bus_data (external MSX board). No bus -> FF.
    end


//    wire ex_bus_rd_n_test;
//    wire ex_bus_wr_n_test;
//    wire ex_bus_iorq_n_test;
//    wire ex_bus_mreq_n_test;
    reg ex_bus_rd_n_ff;
    reg ex_bus_wr_n_ff;
    reg ex_bus_iorq_n_ff;
    reg ex_bus_mreq_n_ff;
    localparam IDLE_ISO = 2'd0;
    localparam ACTIVE_ISO = 2'd1;
    localparam WAIT_ISO = 2'd2;
    reg [1:0] state_iso;
    reg [2:0] counter_iso_n;
    reg [2:0] counter_iso;
    wire io_active;

    //assign ex_bus_rd_n = ( bus_rd_n | ex_bus_rd_n_ff | bus_disable);
    assign ex_bus_rd_n = bus_rd_n;
    //assign ex_bus_wr_n = ( bus_wr_n | ex_bus_wr_n_ff | bus_disable);
    assign ex_bus_wr_n = bus_wr_n;
    assign ex_bus_iorq_n = ( bus_iorq_n | bus_iorq_disable );
    assign ex_bus_mreq_n = ( bus_mreq_n | bus_mreq_disable );
    assign io_active = ( state_iso != IDLE_ISO ) ? 1 : 0;

    always @ ( posedge clk_108m ) begin
        if (~bus_reset_n) begin
            state_iso <= IDLE_ISO;
            ex_bus_rd_n_ff <= 1;
            ex_bus_wr_n_ff <= 1;
        end 
        else begin
            counter_iso_n = counter_iso + 3'd1;       // ZYNQ: sin asignacion mixta
            counter_iso <= counter_iso_n;
            casex ({state_iso, counter_iso_n})
                {IDLE_ISO, 3'bxxx}: begin
                    ex_bus_rd_n_ff <= 1;
                    ex_bus_wr_n_ff <= 1;
                    counter_iso <= 3'd0;
                    if (bus_rd_n == 0 || bus_wr_n == 0 ) begin
                        state_iso <= ACTIVE_ISO;
                    end
                end
                {ACTIVE_ISO, 3'd2} : begin
                    ex_bus_rd_n_ff <= bus_rd_n;
                    ex_bus_wr_n_ff <= bus_wr_n;
                    state_iso <= WAIT_ISO;
                end
                {WAIT_ISO, 3'bxxx} : begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1 ) begin
                        state_iso <= IDLE_ISO;
                    end
                end
            endcase
        end
    end

    // v2.1 60K: declarados AQUI (antes del FSM de waits) para poder alinear la
    // LIBERACION del wait al tren ACTIVO de la CPU en turbo. En el 60K el tren
    // 3m6 nace del dominio 27M (CLKDIV, fase arbitraria) y el 5m4 del 108M:
    // liberar con uno y consumir con el otro = carrera dependiente de fase
    // (en el TN20K ambos dominios salian ALINEADOS del mismo rPLL).
    reg  turbo = 1'b0;
    reg  turbo_eff = 1'b0;   // P1-iter.2: adelantado (el FSM de waits lo consume)
    wire clk_enable_cpu_54;
    wire clk_falling_cpu_54;

`ifdef ENABLE_WAIT
    wire wait_io;
    reg wait_io_ff = 1;

    reg [6:0] wait_cycles;
    reg [6:0] state_wait;
    localparam WAIT_IDLE = 7'd0;
    localparam WAIT_STATE1 = 7'd1;
    localparam WAIT_STATE2 = 7'd3;
    localparam WAIT_STATE3 = 7'd2;
    localparam WAIT_STATE4 = 7'd4;
    localparam WAIT_RELEASE = 7'd5;

    assign wait_io = wait_io_ff;

  `ifndef ENABLE_WAIT_ADAPTIVE
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end 
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    // P1-iter.2 (_64): handshake de LECTURA con la SDRAM, SOLO en
                    // turbo (turbo_eff) — a 5.37 los T-states (186ns) ya no tapan
                    // la latencia/contencion de la SDRAM externa (VDP+refresh) y
                    // la CPU leia basura ("se vuelve loco y se cuelga"; la nota
                    // iter.2 del port lo predijo). A 3.58 el termino es INERTE:
                    // camino validado byte-identico.
                    // P1-iter.2b (_66, DEFINITIVA): guard por NIVEL en TODA lectura
                    // SDRAM turbo, ciclos M1 incluidos. Post-mortem de las variantes:
                    //  - iter.2c (_67, flanco): bench 10-12 "MHz" de basura -> lecturas
                    //    corruptas. RETIRADA.
                    //  - iter.2d (_68, eximir M1): NI ARRANCA en turbo -> el T-state del
                    //    freno M1 NO cubre la latencia real de la SDRAM; los fetch salian
                    //    corruptos. RETIRADA.
                    // Moraleja: cuando ram_busy=1 los datos NO estan; no hay margen en el
                    // handshake. Ir mas alla de ~4.3 efectivos exige acelerar el propio
                    // controlador de memoria (P1c), no apostar en el guard.
`ifdef TURBO_SIN_GUARDA_SDRAM
                    // 🧪 sin el termino de ram_busy: queda EXACTAMENTE la
                    // condicion del MSXnano, que llega a 5,36 sin problemas.
                    if ( ram_write == 1 || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin
`else
`ifdef ZYNQ
                    // ZYNQ: las lecturas de RAM solo frenan en los FALLOS de cache (ram_slow),
                    // en los DOS modos. memory_axi acepta en el primer ciclo y entrega los
                    // aciertos ~75 ns despues de ram_req, asi que caben en el ciclo de lectura
                    // del Z80 tambien a 5,37 MHz (muestrea a ~280 ns). Historia: con ram_busy
                    // en todas las lecturas el Z80 iba a 2,95 a velocidad normal y a 4,33 en
                    // turbo (14/09); el Tang si lo necesita porque su SDRAM tiene contencion.
                    if ( ram_write == 1 || (bus_mreq_n == 0 && bus_rd_n == 0 && ram_slow == 1) || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin
`else
                    if ( ram_write == 1 || (turbo_eff == 1 && bus_mreq_n == 0 && bus_rd_n == 0 && ram_busy == 1) || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin  // P2: sin Compatible Mode (= v1.9 nano)
`endif
`endif
                        wait_io_ff <= 0;
                        state_wait <= WAIT_STATE1;
                    end
                end
                // P1-iter.2b (_66): medir y liberar con el tren ACTIVO de la CPU
                // (la intencion declarada del v2.1). Con el release fijo a 3m6,
                // cada espera en turbo costaba hasta 280ns (cuantizacion del tren
                // lento) y z80bench leia 4.11 en vez de 5.37 (medido en HW). A
                // 3.58 (turbo_eff=0) las expresiones colapsan al 3m6 original:
                // camino validado byte-identico. OJO: pulsos SIN gatear (los
                // gateados estan parados por el propio wait -> deadlock).
                WAIT_STATE1: begin
                    if ( (turbo_eff ? clk_enable_5m4_54 : clk_enable_3m6_54) == 1 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                // P1-iter.2: en turbo, ademas, NO liberar con la SDRAM ocupada.
                WAIT_STATE2: begin
`ifdef TURBO_SIN_GUARDA_SDRAM
                    if ( (turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54) == 1 ) begin
`else
                    if ( (turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54) == 1 && (
`ifdef ZYNQ
                         ram_busy == 0      // ZYNQ: en los dos modos, la CPU no sigue hasta que la memoria ha terminado
`else
                         turbo_eff == 0 || ram_busy == 0
`endif
                         ) ) begin
`endif
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end
  `else
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end 
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    if ( (ex_bus_iorq_n == 0 || bus_mreq_n == 0 ) && (bus_rd_n == 0 || bus_wr_n == 0) ) begin
                        wait_io_ff <= 0;
                        wait_cycles <= 7'd6;
                        state_wait <= WAIT_STATE1;
                    end
                end
                WAIT_STATE1: begin
                    wait_cycles <= wait_cycles - 1;
                    if ( wait_cycles == 0 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                WAIT_STATE2: begin
                    if ( ram_busy == 0 && clk_enable_3m6_54 == 1 ) begin
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    // v2.2: semantica v1.9 restaurada — con la fase 27<->54
                    // alineada (clk27_align) la disciplina original es valida
                    if ( clk_falling_3m6_54 == 1 ) begin
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE4;
                    end
                end
                WAIT_STATE4: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end
  `endif

`endif

    // v1.9: los wires de cadencia de CPU estan declarados ARRIBA (v2.1) junto
    // al FSM de waits; se asignan en el bloque de turbo de abajo.

`ifdef ENABLE_M1_WAIT
    // ===== STANDALONE M1 wait-state generator (frenado a ~100% MSX) =====
    // A real MSX inserts exactly 1 wait-state in every M1 (opcode-fetch) cycle.
    // The goauld got this from the MSX board via ex_bus_wait_n; standalone tied
    // ex_bus_wait_n=1 (top.v ~95), losing the brake -> CPU ran ~16% too fast.
    //
    // MECHANISM: GATE the CPU clock-enable, do NOT use WAIT_n.
    // The earlier WAIT_n version released the pulse at the T1->T2 boundary, so it
    // was already high when the core sampled WAIT_n inside T2 -> no wait inserted
    // (bench stayed at 116%). Instead we mirror the proven wait_io stall: mask
    // exactly one full CPU-clock period (one clk_enable_cpu_54 + one
    // clk_falling_cpu_54, i.e. the ACTIVE cadence) per M1 opcode fetch. Skipping one
    // removes exactly one T-state of progress = one wait-state, independent of
    // the core's internal T-state sampling. RFSH is T3/T4 with M1_n already high
    // (t80.vhd:1077), so refresh cycles are NOT slowed. clk_54m domain.
    reg  wait_m1 = 1'b1;            // active-high CPU clock-enable allow (0 = stall)
    reg  bus_m1_n_prev_54 = 1'b1;
    reg  m1_active = 1'b0;          // currently inserting the wait for this M1
    reg  m1_masked_en = 1'b0;       // masked one clk_enable pulse this wait
    reg  m1_masked_fall = 1'b0;     // masked one clk_falling pulse this wait

    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            wait_m1          <= 1'b1;
            bus_m1_n_prev_54 <= 1'b1;
            m1_active        <= 1'b0;
            m1_masked_en     <= 1'b0;
            m1_masked_fall   <= 1'b0;
        end else begin
            bus_m1_n_prev_54 <= bus_m1_n;
            if (!m1_active) begin
                // Falling edge of M1_n = new opcode fetch -> start one wait.
                if (bus_m1_n_prev_54 == 1'b1 && bus_m1_n == 1'b0) begin
                    m1_active      <= 1'b1;
                    wait_m1        <= 1'b0;   // stall CPU clock from next cycle
                    m1_masked_en   <= 1'b0;
                    m1_masked_fall <= 1'b0;
                end
            end else begin
                // While stalled (wait_m1==0) the coincident enable/falling pulses
                // are masked out of the CPU clock-enable. Track one of each, then
                // release -> exactly one CPU-clock period (one T-state) inserted.
                // v1.9: tracks the MUXED cadence so the wait is exactly 1 T-state
                // in both 3.6 (normal) and 5.37 (turbo) modes.
                if (clk_enable_cpu_54)  m1_masked_en   <= 1'b1;
                if (clk_falling_cpu_54) m1_masked_fall <= 1'b1;
                if ((m1_masked_en  || clk_enable_cpu_54) &&
                    (m1_masked_fall || clk_falling_cpu_54)) begin
                    wait_m1   <= 1'b1;   // release on next cycle
                    m1_active <= 1'b0;
                end
            end
        end
    end
`endif

    // ===== v1.9-fh: retraso de power-on para el ESP-01S (WiFi) =====
    // El INIT del driver ESP corre en el escaneo de slots ~1-2s tras dar
    // corriente, pero el ESP-01S tarda ~3-5s en arrancar: quedaba instalado
    // "sin ESP" (discovery UNAPI = 0 implementaciones) hasta re-init manual
    // via el setup W. Retener el Z80 en reset ~3s SOLO en el power-on da
    // tiempo al ESP y el INIT lo encuentra a la primera. El contador SATURA
    // y no se re-arma: los soft-reset siguen siendo instantaneos (regla de la
    // megaram) y el coste real es ~1.5-2s extra (el stream de flash ya tapa
    // parte). Sin ENABLE_WIFI no aplica.
    // El LANZADOR POR SPI DEL ESP32-S3 (destinos 2 y 3) se RETIRA el 25/08.
    // Nunca llego a leer la SD de forma fiable y el enlace SPI resulto
    // intermitente; su sustituto es el iosys_bl616 de TangCore por UART, que
    // ya pinta y detecta el core (core_id=77 validado en placa).
    // Con el se van launcher_svc, sdc_bridge, mcu_spi, hid y sysctrl:
    // ~3.325 LUT y ~4.749 registros, y -- lo que mas importa -- CINCO
    // multiplexores que vivian en el bus del V9968, en clk_86.

`ifdef ENABLE_WIFI
    reg [26:0] esp_boot_cnt = 0;
    reg        esp_boot_tmr = 0;
    always @(posedge clk_27m) begin
        if (!esp_boot_tmr) begin
            if (esp_boot_cnt == 27'd81000000)   // ~3.0s @ 27 MHz
                esp_boot_tmr <= 1;
            else
                esp_boot_cnt <= esp_boot_cnt + 1'b1;
        end
    end
    // Sin lanzador, el temporizador vuelve a ser lo que era: dar tiempo al ESP
    // antes de soltar al Z80.
    wire esp_boot_ok = esp_boot_tmr;
`else
    wire esp_boot_ok = 1'b1;
`endif

    // ===== S1990 del turboR (puertos E4h-E7h) =====
    // Se declara aqui porque el mux de lectura de E/S vive mas arriba en el
    // fichero; la instancia va abajo, junto al resto de dispositivos.
    wire [7:0] s1990_dout;
    wire       s1990_req;
    wire       s1990_turbo_set, s1990_turbo_val;

    // ===== Turbo mode toggle (F11) =====
    // Default turbo=0 -> M1 wait active -> ~100% real-MSX speed (3.58MHz behaviour).
    // Press F11 (USB HID usage 0x44 = keyboard[68]) to toggle. v1.9: turbo=1 switches
    // the CPU cadence to 5.37 MHz (WSX-style) while the per-M1 wait STAYS active, like
    // the real T9769 does at 5.37 MHz -> benchmarks report ~5.37 (150%). (The v1.8
    // "bypass M1 wait" turbo stacked on the 5.4 clock read as ~6.2 MHz on HW.)
    // Toggle survives MSX soft-reset; powers on in real-MSX mode. LED5 shows the state.
    // NOTE: F12 is captured by the BL616 FPGA-Companion firmware (its OSD) and never
    // reaches the FPGA, so F11 (which does reach it, verified on HW) is used instead.
    // (reg turbo declarado arriba, v2.1)
    // P1 (receta MSXnano v1.9 ce46ef9): los eventos escriben `turbo` DIRECTO y el
    // conmutado seguro lo hace turbo_eff (mas abajo): limite de T-estado limpio
    // (fix de cadencia del nano, validado en su HW) COMBINADO con el guard de
    // bus/memoria en reposo propio del 60K (SDRAM externa: no conmutar con un
    // acceso en vuelo). El esquema turbo_req anterior queda sustituido.
`ifdef ENABLE_TURBOR_ID
    // clk_27m -> clk_54m. El pulso se convierte en un TOGGLE que sobrevive al
    // cruce; el valor viaja al lado y se muestrea cuando el toggle cambia (para
    // entonces lleva ciclos estable).
    reg s1990_tg = 1'b0, s1990_val_h = 1'b0;
    always @(posedge clk_27m) if (s1990_turbo_set) begin
        s1990_tg    <= ~s1990_tg;
        s1990_val_h <= s1990_turbo_val;
    end
    reg s1990_tg_s1 = 1'b0, s1990_tg_s2 = 1'b0, s1990_tg_s3 = 1'b0;
    reg s1990_val_s1 = 1'b0, s1990_val_s2 = 1'b0;
    always @(posedge clk_54m) begin
        s1990_tg_s1 <= s1990_tg;   s1990_tg_s2 <= s1990_tg_s1;  s1990_tg_s3 <= s1990_tg_s2;
        s1990_val_s1 <= s1990_val_h; s1990_val_s2 <= s1990_val_s1;
    end
`endif

    reg boot_done = 1'b0;   // 1 tras la PRIMERA (fria) salida de reset; sobrevive warm resets
    reg f11_s0  = 1'b0;
    reg f11_s1  = 1'b0;
    reg f11_prev= 1'b0;
    always @ (posedge clk_54m) begin
        f11_s0   <= keyboard[68];   // sync HID F11 state into clk_54m domain
        f11_s1   <= f11_s0;
        f11_prev <= f11_s1;
`ifdef ENABLE_TURBO
        if (f11_s1 & ~f11_prev)     // rising edge = F11 pressed
            turbo <= ~turbo;        // toggle real-MSX <-> turbo
`endif
`ifdef ENABLE_TURBOR_ID
        // Tercera fuente: CHGCPU por el S1990. El software pide "R800" y aqui
        // eso significa turbo. Llega de clk_27m, asi que se cruza por TOGGLE
        // (un pulso de un ciclo de 27 MHz podria no verse desde 54, o verse dos
        // veces). FIJA el valor, no conmuta: el software dice cual quiere.
        if (s1990_tg_s2 != s1990_tg_s3)
            turbo <= s1990_val_s2;
`endif
        // v1.9: control software Panasonic — OUT &H41,n con el dispositivo 8
        // seleccionado (decode pana41_wr junto al bloque config). bit0 activo-bajo:
        // 0 = turbo 5.37 MHz, 1 = 3.58. Puesto tras el F11: si coinciden en el
        // mismo ciclo gana el software (en el T9769 real el puerto es el unico control).
`ifdef ENABLE_TURBO
        if (pana41_wr)
            turbo <= ~cpu_dout[0];
`endif
        // v1.9: "Boot Turbo" persistido (ajuste del menu, puerto #45). Siembra el
        // turbo durante la ventana config_init del stream de flash. Va el ULTIMO
        // del bloque de eventos: domina sobre F11/puerto durante el boot.
        // v1.9b FIX pantalla-negra Save&Reset-con-turbo: el boot-turbo (5.37) SOLO
        // se aplica en arranque en FRIO (boot_done=0). En warm reset -> 3.58 (= un
        // Save&Reset normal); el boot-turbo entra al PROXIMO encendido.
`ifdef ENABLE_TURBO
        if (config_init)
            turbo <= (~boot_done && !s2_press && config_sig[4] == 8'h54) ? 1'b1 : 1'b0;
        if (zq_turbo_seed)                   // ZYNQ: boot-turbo del bloque guardado, un ciclo tras soltar el MSX
            turbo <= (!s2_press && zq_cfg_s2[16]) ? 1'b1 : 1'b0;
        // estado conocido de `turbo` en cualquier reset (mirror del cold boot). Ultimo = prioridad.
        if (~bus_reset_n)
            turbo <= 1'b0;
`endif
    end
    // boot_done: se pone a 1 la primera vez que el CPU sale de reset (arranque en
    // frio) y NO se borra nunca (sin clausula de reset -> sobrevive warm resets;
    // GSR lo inicia a 0 al encender). Discriminador frio/warm del boot-turbo.
    always @ (posedge clk_54m)
        if (bus_reset_n & reset3_n & flash_idle & esp_boot_ok & ~config_init)
            boot_done <= 1'b1;   // ~config_init: no marcar boot_done durante la siembra

    // ===== v1.9 Panasonic-WSX turbo: 5.37 MHz CPU cadence =====
    // /20 divider on 108 MHz -> 5.40 MHz base cadence + "period swallow" trim ->
    // EXACT WSX 5.369318 MHz (see below). The sound chips keep the /30
    // clk_enable_3m6_27 (untouched). At turbo=0 the CPU uses the ORIGINAL
    // clk_enable_3m6_54 verbatim (3.58 behaviour byte-identical). NOTE: NO
    // ram_busy handshake yet, so if HW shows corruption during active display,
    // add the handshake (dormant ENABLE_WAIT_ADAPTIVE, top.v ~707) in iter.2.
    //
    // Divisor /20 PURO (mitades de 10 ciclos, pares: fase constante vs clk_54m).
    // NOTA: durante el desarrollo se probo un divisor fraccionario (17x10+1x11,
    // 5.37 directo reformando el reloj) y se descarto; los "cuelgues" que se le
    // atribuyeron resultaron ser un falso contacto del teclado, pero el esquema
    // /20 puro + trago (abajo) es mas simple, conserva las fases 108->54
    // validadas y da el 5.37 EXACTO. Validado en HW (juegos/DOS en turbo).
    reg [4:0] div20_cnt;
    reg       clk_5m4_internal;
    always @(posedge clk_108m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin div20_cnt <= 0; clk_5m4_internal <= 0; end
        else if (div20_cnt >= 5'd9) begin clk_5m4_internal <= ~clk_5m4_internal; div20_cnt <= 0; end
        else div20_cnt <= div20_cnt + 1;
    end
    wire clk_enable_5m4_raw, clk_falling_5m4_raw;
    reg  s5m4_a, s5m4_b;
    always @(posedge clk_54m) begin s5m4_a <= clk_5m4_internal; s5m4_b <= s5m4_a; end
    assign clk_enable_5m4_raw  = (s5m4_b == 0 && s5m4_a == 1);
    assign clk_falling_5m4_raw = (s5m4_b == 1 && s5m4_a == 0);

    // Ajuste EXACTO a 5.37: "trago" de periodo. De cada 176 periodos de 5.4 MHz
    // se enmascara 1 completo (su enable Y su falling, en pareja) ->
    // 5.4 MHz * 175/176 = 5 369 318 Hz = el turbo WSX exacto (315/88 * 1.5 MHz).
    // Mismo mecanismo probado que los waits M1/IO (saltar pulsos de enable en el
    // dominio 54), SIN tocar la forma del reloj 5m4 ni sus fases 108->54. El CPU
    // solo percibe una pausa de 1 T-state cada ~33 us; la alternancia
    // enable/falling se conserva (se traga la pareja completa).
    reg [7:0] pana_per_cnt   = 0;
    reg       pana_skip_pend = 0;   // enmascarando el falling del periodo tragado
    wire      pana_skip_now  = (pana_per_cnt == 8'd175) && clk_enable_5m4_raw;
    always @(posedge clk_54m) begin
        if (~bus_reset_n) begin
            pana_per_cnt   <= 0;
            pana_skip_pend <= 0;
        end else begin
            if (clk_enable_5m4_raw) begin
                if (pana_per_cnt == 8'd175) begin
                    pana_per_cnt   <= 0;
                    pana_skip_pend <= 1;    // el falling de ESTE periodo tambien se traga
                end else
                    pana_per_cnt <= pana_per_cnt + 1'b1;
            end
            if (pana_skip_pend && clk_falling_5m4_raw)
                pana_skip_pend <= 0;
        end
    end
    wire clk_enable_5m4_54  = clk_enable_5m4_raw  & ~pana_skip_now;
    wire clk_falling_5m4_54 = clk_falling_5m4_raw & ~pana_skip_pend;
    // ===== v1.9: conmutado de cadencia SIN glitch =====
    // El mux elige entre dos cadencias de FASE INDEPENDIENTE (3.6 del /30, 5.37
    // del /20). Conmutar sobre `turbo` crudo a mitad de T-estado puede entregar
    // al Z80 dos ENABLE (o dos FALLING) seguidos sin pareja -> opcode mal
    // latcheado -> cuelgue (el F11 en el menu del nano). turbo_eff (el select
    // REAL) solo adopta `turbo` cuando AMBAS cadencias estan bajas Y el CPU no
    // esta en ningun wait (receta v1.9, validada en el TN20K) Y ADEMAS el bus
    // Z80 y la SDRAM estan en reposo (guard 60K: memoria externa, no conmutar
    // con un acceso en vuelo). En reset adopta directo (semilla del boot-turbo).
    wire cadence_safe = (bus_clk_3m6 == 1'b0 && bus_clk_3m6_54 == 1'b0) &&
                        (s5m4_a == 1'b0 && s5m4_b == 1'b0);
    // v1.9b: un warm reset EN CURSO debe CRUZAR la entrada del reset a 3.58
    // (la grabacion en flash tarda decenas de ms con bus_reset_n aun alto).
    wire warm_reset_pending = flash_write_busy | config_reset_req;
    // _177: /WAIT del puerto CPU del V9968 (glue en clk_86) re-sincronizado
    // al dominio del T80 con 2FF. Latencia de asercion total ~60-70ns desde
    // la caida de IORQ — dentro de la ventana de muestreo de WAIT del Z80
    // incluso en turbo (T=186ns). Seguro por diseno: el glue lo gatea al
    // ciclo I/O del VDP y lleva timeout fail-open (~12us); el stall ya no
    // puede matar de hambre al refresco de la SDRAM (autonomo desde _175).
    wire v68_wait86_n;
`ifdef ENABLE_TR
    // TR (04/11): el WAIT del glue es combinacional (varios registros de clk_86 + el nivel del strobe): se registra en clk_86 antes de cruzar (un transitorio
    // de esa logica llegaba al sincronizador y soltaba al R800 antes de tiempo) y el sincronizador pasa a 3 etapas: el WAIT sube >= 1 ciclo de clk_54m despues
    // de que el dato (vdp_dout_q2) este estable. report_cdc marcaba CDC-10 (logica combinacional antes del sincronizador) en este camino.
    wire v68_wait86_r;
    (* ASYNC_REG = "TRUE" *) reg [2:0] v68_wait_s = 3'b111;
    always @(posedge clk_54m) v68_wait_s <= {v68_wait_s[1:0], v68_wait86_r};
    wire v68_wait_out = v68_wait_s[2];
`else
    reg [1:0] v68_wait_s = 2'b11;
    always @(posedge clk_54m) v68_wait_s <= {v68_wait_s[0], v68_wait86_n};
    wire v68_wait_out = v68_wait_s[1];
`endif
    // V9990 por el ARM (dbg_mailbox_axi + v9990_arm_port): entradas de la FIFO del buzon, propiedad del bus y telemetria
    wire        v9a_en, v9a_ent_v;
    wire [15:0] v9a_ent;
`ifdef ENABLE_V9990
    wire [7:0] v99_dout_m;             // dato de lectura del V9990 hacia cpu_din (TRV: con 2 registros de retencion)
    wire v99_wait54_n;                 // /WAIT del V9990 (glue 60h-6Fh) ya en 54 M; lo conduce el bloque V9990
    wire v99_int_n;                    // INT0_n & INT1_n del V9990 (nivel)
    wire v9a_wait_z_n;                 // WAIT hacia el T80: el del glue, mas la retencion del traspaso Z80/ARM (v9990_arm_port)
    wire v9a_pop, v9a_own, v9a_busy;
    wire [3:0] v9a_tmo;
`else
    wire [7:0] v99_dout_m = 8'hFF;
    wire v99_wait54_n = 1'b1;
    wire v99_int_n    = 1'b1;
    wire v9a_wait_z_n = 1'b1;
    wire v9a_pop = 1'b0, v9a_own = 1'b0, v9a_busy = 1'b0;
    wire [3:0] v9a_tmo = 4'd0;
`endif
    wire vdp_wait54_n = v68_wait_out & v9a_wait_z_n;
    // TRV (05/11): el WAIT del Z80 se registra a clk_54m. Con el R800, bus_addr sale de su ALU, pasa por rd_dat de opl4_pcm y llegaba a Wait_s del T80 (flanco de bajada: medio ciclo,
    // 15 niveles, -0,716 ns). El Z80 muestrea WAIT mucho despues del strobe (>= 186 ns en turbo): 18,5 ns mas no cambian el numero de ciclos de espera.
`ifdef TR_V9990
    reg z_wait_ent = 1'b1;
    always @(posedge clk_54m) z_wait_ent <= bus_wait_n & wait_uart & wait_net_n & opl4pcm_wait_n & vdp_wait54_n;
`else
    wire z_wait_ent = bus_wait_n & wait_uart & wait_net_n & opl4pcm_wait_n & vdp_wait54_n;
`endif
    // V3.6: DMA de la SD (sd_dma.sv). frz = CPU congelada con el bus en reposo:
    // el puerto de RAM de la CPU pasa a la DMA por el camino del streamer de la
    // flash (stream_*, mas abajo). Se declaran aqui porque el T80 y el mux de
    // ram_addr los usan antes de la instancia (Gowin crea implicitos de 1 bit).
    wire        dma_frz;
    wire        dma_active;
    wire        dma_rfsh_ok;
    wire        dma_ram_req;
`ifdef NEO16_16M
    wire [24:0] dma_ram_addr;
`else
    wire [23:0] dma_ram_addr;       // 23/09/2026: 24 bits (bit 23 = zona EXT de memory_axi)
`endif
    wire [7:0]  dma_ram_din;
    // (reg turbo_eff adelantado junto al FSM de waits, P1-iter.2)
    always @ (posedge clk_54m) begin
        if (!(bus_reset_n & reset3_n & flash_idle & esp_boot_ok))
            turbo_eff <= turbo;                                 // en reset: sigue a turbo (semilla / 0)
        else if (cadence_safe & wait_io & wait_m1
                 & bus_rd_n & bus_wr_n & bus_mreq_n & ex_bus_iorq_n & (ram_busy == 0))
            turbo_eff <= (warm_reset_pending | (tape_play & ~ppi_port_c[4])) ? 1'b0 : turbo;     // corriendo: 3.58 si hay warm-reset pendiente o la cinta esta cargada Y el motor en marcha (ZYNQ Z1.1: los bucles contados de la BIOS solo corren con el motor; al acabar de cargar vuelve el turbo)
    end
    // CPU cadence mux: turbo_eff (conmutado sin glitch) elige 5.37; si no, la 3.6 intacta.
    assign clk_enable_cpu_54  = turbo_eff ? clk_enable_5m4_54  : clk_enable_3m6_54;
    assign clk_falling_cpu_54 = turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54;

    // ----- M1-wait fallback (divisor) -----
    // If on real HW the benchmark still does not land near 100% with the WAIT_n
    // brake above, comment out `define ENABLE_M1_WAIT and instead SLOW the CPU
    // clock by changing the 108MHz divider at top.v ~223 from /30 (3.6MHz) to
    // /35 (~3.09MHz): replace `if (div30_cnt == 5'd14)` with a half-period of
    // ~17.5 -> alternate 17/18, e.g.:
    //     reg div_tgl;  // toggles every edge to alternate 17/18
    //     if (div30_cnt == (div_tgl ? 5'd17 : 5'd16)) begin
    //         clk_3m6_internal <= ~clk_3m6_internal; div30_cnt <= 0; div_tgl <= ~div_tgl;
    //     end else div30_cnt <= div30_cnt + 1;
    // This lowers the clock instead of inserting a wait (less authentic, but a
    // guaranteed % knob). Do NOT enable both at once.

    // ---- el Z80 (G80a): sus senales de bus van a z_*; sin ENABLE_TR son directamente las del bus ----
`ifdef ENABLE_TR
    wire        z_run_w, z_wait_ovr, z_int_mask;     // los pone tr_cpu (mas abajo)
    wire [7:0]  z_di_w;
    // 04/11: el Z80 sale del reset a la vez que tr_cpu (tr_vdp_ready, ~40 ms tras el V9968, mas abajo): si el Z80 corriera antes, una peticion de cambio
    // de CPU de la S1990 (la BIOS la hace en sus primeras instrucciones) llegaria con tr_cpu aun en reset y se perderia
    wire        tr_vdp_ready;
    wire        z_rst_tr = tr_vdp_ready;
`else
    wire        z_run_w = 1'b1, z_wait_ovr = 1'b0, z_int_mask = 1'b0;
    wire [7:0]  z_di_w = cpu_din;
    wire        z_rst_tr = 1'b1;
`endif
    wire        z_m1_n, z_mreq_n, z_iorq_n, z_rd_n, z_wr_n, z_rfsh_n;
    wire [15:0] z_a;
    wire [7:0]  z_do;
`ifndef ENABLE_TR
    assign bus_m1_n = z_m1_n;  assign bus_mreq_n = z_mreq_n;  assign bus_iorq_n = z_iorq_n;
    assign bus_rd_n = z_rd_n;  assign bus_wr_n = z_wr_n;  assign bus_rfsh_n = z_rfsh_n;
    assign bus_addr = z_a;  assign cpu_dout = z_do;
`endif
    // clk_enable / clk_falling del Z80 ANTES de aplicarle z_run (la parada de tr_cpu): lo de siempre, segun las banderas
`ifdef ENABLE_WAIT
  `ifdef ENABLE_M1_WAIT
    // v1.9: M1 wait is NOT bypassed in turbo (real WSX keeps it at 5.37 MHz);
    // the speed change comes only from the 3.6/5.37 cadence mux.
    wire z_en_pre   = clk_enable_cpu_54 & wait_io & wait_m1 & ~dma_frz & ~iosys_frz;
    wire z_fall_pre = clk_falling_cpu_54 & wait_io & wait_m1 & ~dma_frz & ~iosys_frz;
  `else
    wire z_en_pre   = clk_enable_3m6_54 & wait_io & ~dma_frz & ~iosys_frz;
    wire z_fall_pre = clk_falling_3m6_54 & wait_io & ~dma_frz & ~iosys_frz;
  `endif
`else
  `ifdef ENABLE_M1_WAIT
    // (inactive branch) v1.9 semantics: cadence mux + M1 wait always on
    wire z_en_pre   = clk_enable_cpu_54 & wait_m1 & ~dma_frz & ~iosys_frz;
    wire z_fall_pre = clk_falling_cpu_54 & wait_m1 & ~dma_frz & ~iosys_frz;
  `else
    wire z_en_pre   = clk_enable_3m6_54 & ~dma_frz & ~iosys_frz;
    wire z_fall_pre = clk_falling_3m6_54 & ~dma_frz & ~iosys_frz;
  `endif
`endif
    wire update_addr;
    G80a  #(
        .Mode    (0),     // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        //.T2Write (0),     //0 => WR_n active in T3, /=0 => WR_n active in T2
        .IOWait   (1)      // 0 => Single I/O cycle, 1 => Std I/O cycle
    ) cpu1 (
        .RESET_n   (bus_reset_n & reset3_n & flash_idle & esp_boot_ok & z_rst_tr),
        .CLK_n     (clk_54m),
        .clk_enable (z_en_pre & z_run_w),
        .clk_falling (z_fall_pre & z_run_w),
    `ifdef ENABLE_WIFI
      `ifndef ENABLE_WAIT_ADAPTIVE
        .WAIT_n    (z_wait_ent | z_wait_ovr),
      `else
        .WAIT_n    (wait_uart & wait_net_n & opl4pcm_wait_n & vdp_wait54_n),
      `endif
    `else
      `ifndef ENABLE_WAIT_ADAPTIVE
        .WAIT_n    (bus_wait_n & opl4pcm_wait_n & vdp_wait54_n | z_wait_ovr),
      `else
        .WAIT_n    (opl4pcm_wait_n & vdp_wait54_n),
      `endif
    `endif
    `ifdef ENABLE_V9958
      `ifdef ENABLE_MUSICA
        .INT_n     ((bus_int_n & vdp_int & y8950_int_n & opl4_int_n & v99_int_n & mus_int_n) | z_int_mask),  // _81 Y8950 + _108 OPL4 + V9990 + YM2151 del SFG (perfil Musica)
      `else
        .INT_n     ((bus_int_n & vdp_int & y8950_int_n & opl4_int_n & v99_int_n) | z_int_mask),  // _81 Y8950 + _108 OPL4 + V9990
      `endif
    `else
        .INT_n     (bus_int_n & y8950_int_n & opl4_int_n),
    `endif
        .NMI_n     (1),
        .BUSRQ_n   (1),
        .M1_n      (z_m1_n),
        .MREQ_n    (z_mreq_n),
        .IORQ_n    (z_iorq_n),
        .RD_n      (z_rd_n),
        .WR_n      (z_wr_n),
        .RFSH_n    (z_rfsh_n),
        .HALT_n    ( ),
        .BUSAK_n   ( ),
        .A         (z_a),
        .update_addr(update_addr),
        .DI         (z_di_w),
        .DO         (z_do),
        .Data_Reverse (bus_data_reverse)
    );

    //slots decoding
    reg [7:0] ppi_port_a = 8'h00;
    wire ppi_req_r;
    wire ppi_req_w;
    wire [1:0] pri_slot;
    wire [3:0] pri_slot_num;
    wire [3:0] page_num;

    //----------------------------------------------------------------
    //-- PPI(8255) / primary-slot
    //----------------------------------------------------------------
    assign ppi_req_r = (bus_addr[7:0] == 8'ha8 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign ppi_req_w = (bus_addr[7:0] == 8'ha8 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            ppi_port_a <= 8'h00;
        else begin
            if (ppi_req_w == 1 ) begin
                ppi_port_a <= cpu_dout;
            end
        end
    end

    //expanded slots 0 & 3
    reg [7:0] exp_slot0;
    wire [1:0] exp_slot0_page;
    wire [3:0] exp_slot0_num;
    reg exp_slot0_req_r;
    reg exp_slot0_req_w;
    reg [7:0] exp_slotx;
    wire [1:0] exp_slotx_page;
    wire [3:0] exp_slotx_num;
    reg exp_slotx_req_r;
    reg exp_slotx_req_w;
    wire xffff;
    reg xffh;
    reg xffl;
    always @ (posedge clk_54m) begin
        xffh <= bus_addr[15:8] == 8'hff;
        xffl <= bus_addr[7:0] == 8'hff;
        exp_slot0_req_w <= ( bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
        exp_slot0_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
        exp_slotx_req_w <= ( bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[SD_SLOT] == 1 ) ? 1: 0;
        exp_slotx_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[SD_SLOT] == 1 ) ? 1: 0;
    end
    //assign xffff = ( bus_addr == 16'hffff ) ? 1 : 0;
    assign xffff = xffh & xffl;

//    assign exp_slotx_req_w = ( bus_mreq_n == 0 && bus_wr_n == 0 && xffff == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
//    assign exp_slotx_req_r = ( bus_mreq_n == 0 && bus_rd_n == 0 && xffff == 1 && pri_slot_num[0] == 1 ) ? 1: 0;

    // slot #0
    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0 )
            exp_slot0 <= 8'h00;
        else begin
            if (exp_slot0_req_w == 1 ) begin
                exp_slot0 <= cpu_dout;
            end
        end
    end

    // slot #3
    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0 )
            exp_slotx <= 8'h00;
        else begin
            if (exp_slotx_req_w == 1 ) begin
                exp_slotx <= cpu_dout;
            end
        end
    end

    // slots decoding
    assign pri_slot = ( bus_addr[15:14] == 2'b00) ? ppi_port_a[1:0] :
                      ( bus_addr[15:14] == 2'b01) ? ppi_port_a[3:2] :
                      ( bus_addr[15:14] == 2'b10) ? ppi_port_a[5:4] :
                                             ppi_port_a[7:6];

    assign pri_slot_num = ( pri_slot == 2'b00 ) ? 4'b0001 :
                          ( pri_slot == 2'b01 ) ? 4'b0010 :
                          ( pri_slot == 2'b10 ) ? 4'b0100 :
                                                  4'b1000;

    assign page_num = ( bus_addr[15:14] == 2'b00) ? 4'b0001 :
                      ( bus_addr[15:14] == 2'b01) ? 4'b0010 :
                      ( bus_addr[15:14] == 2'b10) ? 4'b0100 :
                                                    4'b1000;
    assign exp_slot0_page = ( bus_addr[15:14] == 2'b00) ? exp_slot0[1:0] :
                            ( bus_addr[15:14] == 2'b01) ? exp_slot0[3:2] :
                            ( bus_addr[15:14] == 2'b10) ? exp_slot0[5:4] :
                                                          exp_slot0[7:6];

    assign exp_slot0_num = ( exp_slot0_page == 2'b00 ) ? 4'b0001 :
                           ( exp_slot0_page == 2'b01 ) ? 4'b0010 :
                           ( exp_slot0_page == 2'b10 ) ? 4'b0100 :
                                                         4'b1000;

    assign exp_slotx_page = ( bus_addr[15:14] == 2'b00) ? exp_slotx[1:0] :
                            ( bus_addr[15:14] == 2'b01) ? exp_slotx[3:2] :
                            ( bus_addr[15:14] == 2'b10) ? exp_slotx[5:4] :
                                                          exp_slotx[7:6];

    assign exp_slotx_num = ( exp_slotx_page == 2'b00 ) ? 4'b0001 :
                           ( exp_slotx_page == 2'b01 ) ? 4'b0010 :
                           ( exp_slotx_page == 2'b10 ) ? 4'b0100 :
                                                         4'b1000;

    reg slot0_req_r;
    reg slotx_req_r;
    always @ (posedge clk_54m) begin
        slot0_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 ) ? 1 : 0;
        slotx_req_r <= ( ( config_enable_mapper3 == 1 || config_enable_megaram3 == 1 || config_enable_sdcard == 1 ) && bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 ) ? 1 : 0;
    end

`ifdef ENABLE_BIOS
    //bios
    reg bios_req;
    wire [7:0] bios_dout;
    always @ (posedge clk_54m) begin
        bios_req <= ( !tr_map && bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 && exp_slot0_num[0] == 1) ? 1 : 0;
    end

    //subrom
    reg subrom_req;
    wire [7:0] subrom_dout;
    always @ (posedge clk_54m) begin
        subrom_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 && page_num[0] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //msx logo
    reg msx_logo_req;
    wire [7:0] msx_logo_dout;
    always @ (posedge clk_54m) begin
        msx_logo_req <= ( !tr_map && bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //subrom + logo
    reg subrom_logo_req;
    always @ (posedge clk_54m) begin
        subrom_logo_req <= ( !tr_map && bus_mreq_n == 0 && bus_rd_n == 0 && (page_num[0] == 1 || page_num[1] == 1) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    // V3.5: SEGUNDA PAGINA DEL MENU. El menu deja de desempaquetarse en RAM y
    // corre desde ROM como cartucho de 32 KB: pagina 1 (4000-7FFF) = la ROM de
    // siempre del pack (0x6C000, con la FM-BIOS), pagina 2 (8000-BFFF) = una
    // ventana NUEVA de 16 KB en la posicion que ocupaba la primera mitad del
    // driver KANJI (pack 0x70000). El driver KANJI (CALL KANJI de BASIC, slot
    // 0-1) desaparece del MSXimus; la FUENTE kanji (256 KB por puertos) sigue.
    // Misma expresion que subrom_logo_req (slot 3-1) pero solo pagina 2.
    reg menu2_req;
    always @ (posedge clk_54m) begin
        menu2_req <= ( !tr_map && bus_mreq_n == 0 && bus_rd_n == 0 && page_num[2] == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end


`else

    wire bios_req;
    wire [7:0] bios_dout;
    wire subrom_req;
    wire [7:0] subrom_dout;
    wire msx_logo_req;
    wire [7:0] msx_logo_dout;
    wire menu2_req;
    wire subrom_logo_req;

`endif

    //logo ROM: SIEMPRE (v3.0 — estaba atrapado en ENABLE_WIFI; es del menu, no del WiFi)
`ifdef ENABLE_WIFI

    //wifi driver
    reg wifi_req;
    always @ (posedge clk_54m) begin
        wifi_req <= ( !tr_map && bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[0] == 1 && exp_slot0_num[2] == 1 ) ? 1 : 0;
    end
`endif

    //logo ROM (FREE16KB del pack @0x7C000) en slot 0-3 pagina 1: pantalla de
    //marca del menu (rutina+imagen autocontenidas; el menu la llama con CALLF)
    reg logo_req;
    always @ (posedge clk_54m) begin
        logo_req <= ( !tr_map && bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[0] == 1 && exp_slot0_num[3] == 1 ) ? 1 : 0;
    end

`ifdef ENABLE_WIFI
    //uart
    wire uart_req;
    wire wait_uart;
    wire [7:0] uart_dout;

    assign uart_req = (bus_addr[7:1] == 7'b0000011 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // ESP ports 06-07h
    // ZYNQ 17/09: byte que el Z80 lee del puerto 06h -> trazador (evento 7); ver zq_uart_* arriba
    always @(posedge clk_27m) begin
        zq_uart_rd_d <= uart_req && !bus_addr[0];
        if (uart_req && !bus_addr[0]) zq_uart_last <= uart_dout;
        if (!(uart_req && !bus_addr[0]) && zq_uart_rd_d) begin
            zq_uart_byte <= zq_uart_last; zq_uart_tgl <= ~zq_uart_tgl;
        end
    end

    // F1 (_73): la UART va al BL616 ONBOARD (firmware UNAPI propio, repo
    // BL616-UNAPI-Firmware). RX = pad bl616_jtagsel (V14 <- GPIO28 TX del
    // BL616, PULL_UP = idle UART correcto). TX = pad spi_irqn (U15 -> GPIO27
    // RX del BL616), robado al companion (sacrificado en F1). Baud del core:
    // 27M/31 = 870968; el firmware BL616 va a 869565 (-0.16%).
    wire bl616_uart_tx_w;
    // _95: BUS REGISTRADO (patron _91) — uwifi vive en clk_27m y decodificaba
    // el bus del T80 (lanzado en bajada de 54M) directo: camino de medio
    // ciclo que perdio la loteria de placement en la _95 (p1r1: -0.905 en
    // cpu1/RD->my_rx_state). Flop directo en 27M = cono trivial; el modulo
    // ve el bus 1 ciclo de 27M tarde (37ns, nada frente a los ~560ns del
    // ciclo I/O en turbo). wait_o llega <100ns tras IORQ: el T80 muestrea
    // /WAIT a >=186ns — margen sobrado. Sin tocar wifi_lite.vhd.
    reg        w27_iorq_n, w27_wr_n, w27_rd_n;
    reg [15:0] w27_addr;
    reg [7:0]  w27_din;
    always @(posedge clk_27m) begin
        w27_iorq_n <= bus_iorq_n;
        w27_wr_n   <= bus_wr_n;
        w27_rd_n   <= bus_rd_n;
        w27_addr   <= bus_addr;
        w27_din    <= cpu_dout;
    end
    // 25/09 (Ethernet P1): con la UART del ESP en la UART1 del PS (net_ps), el companion la lee por SONDEO (FIFO de
    // 64 bytes, ~1 ms por vuelta) y a 870 kbaud se desbordaria: la UART1 sube RTSN al llenarse (FLOWDEL) y aqui se
    // retiene al Z80 con WAIT en su OUT al puerto 07h hasta que vuelva a haber sitio, sin que wifi_lite vea la
    // escritura (wrt_i enmascarado). Tope de 50 ms por si el ARM no responde: antes que colgar el MSX se pierde un
    // byte. Al soltar, wifi_lite ve el OUT y pone su propio WAIT; el nuestro dura 2 ciclos mas para no dejar hueco.
    reg  [1:0]  u1_rtsn_s = 2'b11;
    reg  [1:0]  net_pause_d = 2'b00;
    reg  [20:0] net_pause_cnt = 21'd0;
    reg         net_pause_tmo = 1'b0;
    wire        z80_wr07  = (w27_iorq_n == 1'b0) && (w27_wr_n == 1'b0) && (w27_addr[7:0] == 8'h07);
    wire        net_pause = z80_wr07 & zq_netps_s[1] & u1_rtsn_s[1] & ~net_pause_tmo;
    always @(posedge clk_27m) begin
        u1_rtsn_s   <= {u1_rtsn_s[0], uart1_rtsn_w};
        net_pause_d <= {net_pause_d[0], net_pause};
        if (!z80_wr07) begin net_pause_cnt <= 21'd0; net_pause_tmo <= 1'b0; end
        else if (net_pause) begin
            if (net_pause_cnt == 21'd1350000) net_pause_tmo <= 1'b1;   // 50 ms a 27 MHz
            else net_pause_cnt <= net_pause_cnt + 21'd1;
        end
    end
    assign wait_net_n = ~(net_pause | net_pause_d[0] | net_pause_d[1]);
    wifi uwifi (
        .clk_i      (clk_27m),
        .wait_o     (wait_uart),
        .reset_i    (bus_reset_n),
        .iorq_i     (w27_iorq_n),
        .wrt_i      (w27_wr_n | net_pause),  // 25/09: la escritura al 07h se retiene mientras el ARM pida pausa (RTS)
        .rd_i       (w27_rd_n),
`ifdef WIFI_PMOD_TEST
        .rx_i       (uart_pmod_rx),          // TEST: RX por PMOD1 D22 (CH340 TX / PC-de-ESP)
`elsif ENABLE_WIFI_ESP32
        .rx_i       (zq_s3ps_s[1] ? 1'b1 : zq_netps_s[1] ? uart1_tx_w : esp_rx_i),   // 25/09: net_ps = UART1 del PS (companion "ESP32"); si no, el ESP32 externo del CAM1; 02/10: s3_ps = la S3 es del ARM, el MSX no oye nada
`else
        .rx_i       (bl616_jtagsel),         // onboard: V14 <- BL616 IO28 TX
`endif
        .tx_o       (bl616_uart_tx_w),
        .adr_i      (w27_addr),
        .db_i       (w27_din),
        .db_o       (uart_dout),
        .dbg_overflow_o (wifi_ovf_p),
        .dbg_underrun_o (wifi_unr_p)
    );
    assign uart1_rx_w   = zq_s3ps_s[1] ? esp_rx_i : bl616_uart_tx_w;   // 25/09: lo que el MSX escribe en el 07h llega tambien a la UART1 del PS; 02/10: con s3_ps, lo que contesta la S3
    assign uart1_ctsn_w = 1'b0;              //   el ARM puede mandar siempre (la FIFO de 2080 de wifi_lite, como con el ESP real)

    // ===== V3.1: CAZA DE LAS DESCARGAS CORRUPTAS =====
    // Los DOS unicos mecanismos de perdida, contados por separado porque cada
    // uno apunta a un culpable distinto:
    //   OVERFLOW = el ESP escribio con la FIFO llena -> byte TIRADO. Hasta
    //              ahora esto era INVISIBLE (fifo.vhd tiraba el byte sin
    //              dejar rastro). Si sube: falta control de flujo en el
    //              enlace, y migrar al S3 SE LO LLEVA PUESTO.
    //   UNDERRUN = el Z80 leyo y no habia datos. Si sube y el fichero sale
    //              con bloques a CERO pero alineado -- que es la firma
    //              observada (Fleet cada 25 sectores, Aleste cada 49) --
    //              entonces el driver UNAPI esta entregando ceros sin avisar,
    //              y el bug es del lado MSX.
    // Si NO sube ninguno, los dos mecanismos quedan descartados de golpe.
    wire wifi_ovf_p, wifi_unr_p;
    reg [15:0] wifi_ovf_cnt = 16'd0;
    reg [15:0] wifi_unr_cnt = 16'd0;
    reg        wifi_ovf_d = 1'b0, wifi_unr_d = 1'b0;
    always @(posedge clk_27m) begin
        wifi_ovf_d <= wifi_ovf_p;
        wifi_unr_d <= wifi_unr_p;
        if (wifi_ovf_p && !wifi_ovf_d) wifi_ovf_cnt <= wifi_ovf_cnt + 16'd1;
        if (wifi_unr_p && !wifi_unr_d) wifi_unr_cnt <= wifi_unr_cnt + 16'd1;
    end

`endif 

    //rtc
    wire rtc_req_r;
    wire rtc_req_w;
    wire [7:0] rtc_dout;
    assign rtc_req_w = (bus_addr[7:1] == 7'b1011010 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1 : 0; // I/O:B4-B5h   / RTC
    assign rtc_req_r = (bus_addr[7:1] == 7'b1011010 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // I/O:B4-B5h   / RTC

    wire [38:0] rtc_tod;
    rtc rtc1(
        .clk21m(clk_27m),
        .reset(0),
        .clkena(clk_enable_3m6_27),
        .req(rtc_req_w | rtc_req_r),
        .ack(),
        .wrt(rtc_req_w),
        .adr(bus_addr),
        .dbi(rtc_dout),
        .dbo(cpu_dout),
        .tod(rtc_tod)                 // la hora en BCD: el reloj del gestor de ventanas (rama beta)
    );

    //vdp
	wire vdp_csw_n; //VDP write request
	wire vdp_csr_n; //VDP read request	
    wire [7:0] vdp_dout;
    // dato de lectura del V9968 (cdi_r, clk_86) hacia cpu_din (clk_54m): 2 registros de retencion en TR (bus de 8 bits sin sincronizar; report_cdc: CDC-4)
`ifdef ENABLE_TR
    reg [7:0] vdp_dout_q1 = 8'hFF, vdp_dout_q2 = 8'hFF;
    always @(posedge clk_54m) begin vdp_dout_q1 <= vdp_dout; vdp_dout_q2 <= vdp_dout_q1; end
    wire [7:0] vdp_dout_m = vdp_dout_q2;
`else
    wire [7:0] vdp_dout_m = vdp_dout;
`endif
    wire vdp_int;
    wire WeVdp_n;
    wire [16:0] VdpAdr;
    wire [15:0] VrmDbi;
    wire [7:0] VrmDbo;
    wire VideoDHClk;
    wire VideoDLClk;
    //decode del VDP: 98-9Bh
    wire vdp_io_hit;
`ifdef ENABLE_V9968_VDP
    // _140 ESPEJO 88-8Bh: la demo ru66-v9968-demo y el software de cartucho
    // V9968 EXTERNO hablan SOLO por 88-8Bh (nunca 98-9B). En HW real son dos
    // chips (V9968 externo en 88-8B + VDP interno en 98-9B, "switch to the
    // V9968 display"); en el MSXimus el V9968 YA ES el VDP interno, asi que
    // aliasamos AMBOS rangos al mismo chip. Se ignora bus_addr[4]: 98-9B
    // (bit4=1) y 88-8B (bit4=0) son las UNICAS combinaciones con [7:5]=100 y
    // [3:2]=10 (0x88-8B libre en el MSXimus; vecinos PSG A0-A2/PPI A8-AA/
    // Y8950 C0-C1). mode = bus_addr[1:0] es identico en ambos rangos, asi
    // que el glue recibe el mismo puerto; BIOS/DOS siguen en 98-9B intactos.
    // 15/09 (gen C de HRA, ceeecd7): + puerto #4 = 9Ch (y su espejo 8Ch): flags de
    // interrupcion y el bit 7 que desbloquea R#20/R#21. 9Dh-9Fh/8Dh-8Fh siguen fuera.
    // 27/09 geo3d: + 9Dh (indice/estado) y 9Fh (datos) del coprocesador 3D = mode 5 y 7 del glue; geo3d_bus se los
    // queda (hit) y al VDP no le llega el valid de esos. 9Eh/8Eh siguen fuera; 8Dh/8Fh, espejos del geo3d desde el 30/10.
`ifdef ENABLE_MUSICA
    // perfil Musica (31/10): SIN el espejo 88h-8Ch. 88h-89h son el VDP de la Franky: VGMPlay, al buscarla, escribe R#0 = 0 y
    // R#1 = 0 por 89h; con el espejo le llegaba al V9968 (pantalla apagada e interrupciones fuera: MSX-DOS colgado).
    assign vdp_io_hit = ( bus_addr[7:4] == 4'h9 && (bus_addr[3:2] == 2'b10 || bus_addr[3:0] == 4'b1100) )
`else
    assign vdp_io_hit = ( bus_addr[7:5] == 3'b100 && (bus_addr[3:2] == 2'b10 || bus_addr[3:0] == 4'b1100) )
`endif
`ifdef ENABLE_GEO3D
                     // 30/10/2026: + los espejos 8Dh/8Fh del geo3d. Con el V9968 tambien en 88h-8Ch, el software que
                     // busca primero un V9968 externo (renatus geo3d-motion-stage: MOT2N/MOT8N) lo encuentra en 88h y
                     // pide el geo3d en 8Dh/8Fh; sin espejo daba borde 10 (amarillo, "falta geo3d") y se paraba.
                     || ( bus_addr[7:5] == 3'b100 && bus_addr[3:2] == 2'b11 && bus_addr[0] )
`endif
                     ;
`else
    assign vdp_io_hit = ( bus_addr[7:2] == 6'b100110 );
`endif
    assign vdp_csw_n = (vdp_io_hit == 1 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 0:1; // VDP write
    assign vdp_csr_n = (vdp_io_hit == 1 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 0:1; // VDP read

`ifndef ENABLE_V9968_VDP
    v9958_top vdp4 (
        .clk (clk_27m),
        .clk_135 (clk_135),           // legado (sin uso con VIDEO720)
        .clk_135_lock (clock_locked), // mismo PLL -> mismo lock (antes: lock del CLK_135 propio)
`ifdef VIDEO720
        .clk_hdmi  (clk_hdmi),        // v3.0: pixel 720p 74.25 (pll_74, cascada monitorcore)
        .clk_hdmi5 (clk_hdmi5),       // v3.0: TMDS x5 371.25
        .dbg_bridge(dbg_bridge_w),    // v3.1: diagnostico del puente -> PMOD0
`endif
        .dbg_video (dbg_video_w),     // sondas de video del bring-up
        .s1 (0),
        .clk_50 (0),
        .clk_125 (0),

    `ifdef ENABLE_V9958
        .reset_n (bus_reset_n ),
    `else
        .reset_n (0),
    `endif
        .mode    (bus_addr[1:0]),
        .csw_n   (vdp_csw_n),
        .csr_n   (vdp_csr_n),

        .int_n   (vdp_int),
        .gromclk (),
        .cpuclk  (),
        .cdi     (vdp_dout),
        .cdo     (cpu_dout),

        .audio_sample   (audio_sample),
        .audio_sample_r (audio_sample_r),
        .aspect_16_9    (config_enable_16_9),

        .adc_clk  (),
        .adc_cs   (),
        .adc_mosi (),
        .adc_miso (0),

    `ifdef ENABLE_CONFIG
        .maxspr_n    (~config_enable_8sprites),  // Sprite Limit 8/linea (menu, config2[6]); 1 = limite clasico 4
    `else
        .maxspr_n    (1),
    `endif
    `ifdef ENABLE_SCAN_LINES
        .scanlin_n   (~config_enable_scanlines),
    `else
        .scanlin_n   (1),
    `endif
        .gromclk_ena_n (1),
        .cpuclk_ena_n  (1),

        .WeVdp_n(WeVdp_n),
        .VdpAdr(VdpAdr),
        .VrmDbi(VrmDbi2),
        .VrmDbo(VrmDbo),

        .VideoDHClk(VideoDHClk),
        .VideoDLClk(VideoDLClk),

        .tmds_clk_p    (clk_p),
        .tmds_clk_n    (clk_n),
        .tmds_data_p   (data_p),
        .tmds_data_n   (data_n)
    );

`else  // ==================== ENABLE_V9968_VDP ====================
    // F1 V9968: el VDP de HRA! (fpga/v9968, parche tag+eco) sustituye al
    // v9958_top ENTERO. VRAM en la SDRAM compartida via shim (contrato 8
    // ciclos) + bridge CDC al puerto wv2 de memory.v. Video: puente 800px
    // msx2hdmi_v9968 (ring BRAM, back-end TMDS intacto). v1: NTSC (la
    // geometria 50Hz del V9968 esta sin medir; pal_mode=0).

    // ---- reloj maestro 85.909 MHz (27 x 35/11, 0 ppm vs 24x colorburst) ----
    wire clk_86, pll86_lock;
    // ---- ZYNQ PLLE2_D: 27 x 35 = VCO 945 -> /11 = 85.909 (V9968) ----
    wire pD_fb, pD_fb_b, pD_86, pD_43, clk_43;
    PLLE2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(37.037), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT(35), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE(11), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(22), .CLKOUT1_DUTY_CYCLE(0.5), .CLKOUT1_PHASE(0.0),   // 27/09: 42.95 = clk_86/2 para el motor geo3d
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll86_vdp (
        .CLKIN1(clk27_video), .CLKFBIN(pD_fb_b), .CLKFBOUT(pD_fb),
        .CLKOUT0(pD_86), .CLKOUT1(pD_43), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(pll86_lock), .PWRDWN(1'b0), .RST(~clock_locked)
    );
    BUFG bD_fb (.I(pD_fb), .O(pD_fb_b));
    BUFG bD_86 (.I(pD_86), .O(clk_86));
    BUFG bD_43 (.I(pD_43), .O(clk_43));   // geo3d: misma PLL, flancos alineados -> cruces 86<->43 emparentados

    // _125b: syn_maxfan — rst86_n abanica a TODO el dominio clk_86 (shim +
    // core V9968) y su ultima etapa aparecio como migaja de -0.063 en el
    // roll P235 (rst86_sync[3] -> CEs de pfq). La replica de la herramienta
    // (identica por construccion) acorta las redes del arbol de reset.
    (* syn_maxfan = 16 *) reg [3:0] rst86_sync = 4'd0;
    always @(posedge clk_86) rst86_sync <= {rst86_sync[2:0], bus_reset_n & pll86_lock};
    wire rst86_n = rst86_sync[3];

    // ---- glue bus T80 -> valid/ready (una transaccion por ciclo I/O) ----
    wire [2:0] v68_bus_address;
    wire       v68_ioreq, v68_write, v68_valid, v68_ready;
    wire [7:0] v68_wdata, v68_rdata;
    wire       v68_rdata_en;
`ifdef ENABLE_TR
    // TR (04/11): al glue (clk_86) solo llegan SALIDAS DE REGISTROS de clk_54m, nunca logica combinacional: el strobe (decodificacion de bus_addr/iorq/rd/wr, que puede
    // dar pulsos espurios en los cambios de direccion de un R800 a 7 MHz y el sincronizador de 2 etapas los toma segun la colocacion) se filtra: solo cuenta si lleva
    // >= 3 ciclos de clk_54m (los reales duran >= 36), y la direccion y el dato van registrados (estables mucho antes de que el sincronizador vea el strobe).
    (* ASYNC_REG = "FALSE" *) reg v68_csr_a = 1'b1, v68_csr_b = 1'b1, v68_csr_c = 1'b1, v68_csr_f = 1'b1;
    reg v68_csw_a = 1'b1, v68_csw_b = 1'b1, v68_csw_c = 1'b1, v68_csw_f = 1'b1;
    reg [2:0] v68_mode_q = 3'd0;  reg [7:0] v68_cdo_q = 8'd0;
    always @(posedge clk_54m) begin
        v68_csr_a <= vdp_csr_n;  v68_csr_b <= v68_csr_a;  v68_csr_c <= v68_csr_b;  v68_csr_f <= v68_csr_a | v68_csr_b | v68_csr_c;
        v68_csw_a <= vdp_csw_n;  v68_csw_b <= v68_csw_a;  v68_csw_c <= v68_csw_b;  v68_csw_f <= v68_csw_a | v68_csw_b | v68_csw_c;
        v68_mode_q <= bus_addr[2:0];  v68_cdo_q <= cpu_dout;
    end
    wire v68_csr_g = v68_csr_f, v68_csw_g = v68_csw_f;
    wire [2:0] v68_mode_g = v68_mode_q;  wire [7:0] v68_cdo_g = v68_cdo_q;
`else
    wire v68_csr_g = vdp_csr_n, v68_csw_g = vdp_csw_n;
    wire [2:0] v68_mode_g = bus_addr[2:0];  wire [7:0] v68_cdo_g = cpu_dout;
`endif
    v9968_cpu_glue u_v68glue (
        .clk_86(clk_86), .rst_n(rst86_n),
        .csw_n(v68_csw_g), .csr_n(v68_csr_g),
        .mode(v68_mode_g), .cdo(v68_cdo_g), .cdi_r(vdp_dout),   // [2] = puerto #4 (9Ch)
        .wait_n(v68_wait86_n),   // _177: /WAIT del puerto CPU del V9968
        .bus_address(v68_bus_address), .bus_ioreq(v68_ioreq),
        .bus_write(v68_write), .bus_valid(v68_valid), .bus_ready(v68_ready),
        .bus_wdata(v68_wdata), .bus_rdata(v68_rdata), .bus_rdata_en(v68_rdata_en)
    );

`ifdef ENABLE_TR
    reg v68_wait86_rq = 1'b1;
    always @(posedge clk_86) v68_wait86_rq <= v68_wait86_n;
    assign v68_wait86_r = v68_wait86_rq;
`endif
    // ---- el V9968 ----
    wire [17:2] v68_vram_address;
    wire        v68_vram_write, v68_vram_valid, v68_vram_refresh;
    wire [31:0] v68_vram_wdata, v68_vram_rdata;
    wire [3:0]  v68_vram_mask;
    wire [4:0]  v68_vram_tag, v68_vram_rtag;
    wire        v68_vram_rdata_en;
    wire        v68_vram_stall;
    wire        v68_hs, v68_vs, v68_de;
    wire        v68_hires512;                  // el V9968 esta en SCREEN6/7 o texto de 80 col. (vdp.v, clk_86): el 4:3 no aplica Scale3x
    wire [7:0]  v68_r8, v68_g8, v68_b8;
    // 🏆 AQUI VIVIAN CINCO MULTIPLEXORES, y estaban EN clk_86 -- el reloj por
    // el de los cierres de timing mas justos. Los ponia el
    // lanzador del S3 para robarle el bus del VDP al Z80. Retirado el lanzador,
    // el camino queda directo: los alias los pliega la sintesis y el
    // instanciado de abajo no se toca.
    wire [2:0] v68_addr_mx  = v68_bus_address;
    wire       v68_ioreq_mx = v68_ioreq;
    wire       v68_write_mx = v68_write;
    wire       v68_valid_mx = v68_valid;
    wire [7:0] v68_wdata_mx = v68_wdata;

    // ---- 27/09 geo3d (Alex Moncks, MIT; fpga/geo3d/): coprocesador 3D en 9Dh/9Fh ----
    // Cuelga del MISMO bus valid/ready del glue: geo3d_bus se queda los accesos con mode 5/7 (hit) y el VDP no ve
    // su valid; en las lecturas responde el que emitio rdata_en (son exclusivos). El motor va a clk_43 (CLKOUT1 de la
    // PLL del V9968, /2 exacto y en fase: cruces por toggle como en su cartucho Tang). Sus LINE/LRMM entran en
    // vdp_command por ext_cmd_* solo con CE = 0 (lo vigila el propio motor). Sin acceso a 9Dh/9Fh, el V9968 es el de
    // siempre bit a bit. tb_geo3d_int.sv (tools/v9968_sim) reproduce este enganche con las escenas de su repo.
    wire       v68_valid_vdp, v68_ready_vdp, v68_rdata_en_vdp;
    wire [7:0] v68_rdata_vdp;
    wire       geo_cmd_wr, geo_cmd_ce;
    wire [5:0] geo_cmd_num;
    wire [7:0] geo_cmd_data;
    wire       geo_cmd_fill_span;   // 01/11: R#46 = fila rellena de una cara (LINE + IMP): el VDP la ejecuta como HMMV en SCREEN 8
`ifdef ENABLE_GEO3D
    wire       geo_hit, geo_ready, geo_rdata_en, geo_busy;
    wire [7:0] geo_rdata;
    geo3d_bus u_geo3d (
        .clk(clk_86), .clk_eng(clk_43), .reset_n(rst86_n),
        .bus_address(v68_addr_mx), .bus_ioreq(v68_ioreq_mx), .bus_write(v68_write_mx),
        .bus_valid(v68_valid_mx), .bus_wdata(v68_wdata_mx),
        .hit(geo_hit), .bus_ready(geo_ready), .bus_rdata(geo_rdata), .bus_rdata_en(geo_rdata_en),
        .cmd_wr(geo_cmd_wr), .cmd_num(geo_cmd_num), .cmd_data(geo_cmd_data), .cmd_fill_span(geo_cmd_fill_span),
        .cmd_ce(geo_cmd_ce), .run_busy(geo_busy)
    );
    assign v68_valid_vdp = v68_valid_mx & ~geo_hit;
    assign v68_ready     = geo_hit ? geo_ready : v68_ready_vdp;
    assign v68_rdata     = geo_rdata_en ? geo_rdata : v68_rdata_vdp;
    assign v68_rdata_en  = geo_rdata_en | v68_rdata_en_vdp;
`else
    assign v68_valid_vdp = v68_valid_mx;
    assign v68_ready     = v68_ready_vdp;
    assign v68_rdata     = v68_rdata_vdp;
    assign v68_rdata_en  = v68_rdata_en_vdp;
    assign geo_cmd_wr    = 1'b0;
    assign geo_cmd_num   = 6'd0;
    assign geo_cmd_data  = 8'd0;
    assign geo_cmd_fill_span = 1'b0;
`endif

    vdp u_v9968 (
        .reset_n(rst86_n), .clk(clk_86), .initial_busy(1'b0),
        .bus_address(v68_addr_mx), .bus_ioreq(v68_ioreq_mx), .bus_write(v68_write_mx),
        .bus_valid(v68_valid_vdp), .bus_ready(v68_ready_vdp),
        .bus_wdata(v68_wdata_mx), .bus_rdata(v68_rdata_vdp), .bus_rdata_en(v68_rdata_en_vdp),
        .int_n(vdp_int),
        .vram_address(v68_vram_address), .vram_write(v68_vram_write),
        .vram_valid(v68_vram_valid), .vram_wdata(v68_vram_wdata),
        .vram_wdata_mask(v68_vram_mask),
        .vram_rdata(v68_vram_rdata), .vram_rdata_en(v68_vram_rdata_en),
        .vram_tag(v68_vram_tag), .vram_rtag(v68_vram_rtag),
        .vram_stall(v68_vram_stall),
        .vram_refresh(v68_vram_refresh),
        .display_hs(v68_hs), .display_vs(v68_vs), .display_en(v68_de),
        .display_r(v68_r8), .display_g(v68_g8), .display_b(v68_b8),
        .hires512(v68_hires512),
        .force_highspeed(1'b0), .button(2'b00),
        .ext_cmd_wr(geo_cmd_wr), .ext_cmd_num(geo_cmd_num), .ext_cmd_data(geo_cmd_data), .ext_cmd_fill_span(geo_cmd_fill_span), .ext_cmd_ce(geo_cmd_ce),   // geo3d
        .pulse0(), .pulse1(), .pulse2(), .pulse3(),
        .pulse4(), .pulse5(), .pulse6(), .pulse7()
    );

    // ---- shim VRAM (contrato 8 ciclos) + bridges CDC 85.9<->108 ----
    // _120: DOS canales — las lecturas de palabra piden las dos mitades en
    // paralelo (bk por wv2, bk2 por wv3): los modos de 256B/linea (SC7/8/12)
    // consumen 1 palabra/730ns y un canal solo daba ~800ns.
    wire [31:0] v68dbg_miss, v68dbg_bka, v68dbg_bkb;   // _121diag → COM11
    wire [31:0] v68dbg_park;                           // _124: park del shim
    wire [31:0] v68dbg_drops;                          // _154: {s1_pfq, wq_full} — drops reales
    wire        v68bk_req, v68bk_we, v68bk_done_t;
    wire [21:0] v68bk_addr;
    // _148 FIX B: el shim escribe PALABRAS de 32b con mascara de bytes (1 op de
    // backend por palabra en vez de hasta 4). Ver v9968_vram_shim.v.
    wire [31:0] v68bk_wdata;
    wire [3:0]  v68bk_wmask;
    wire [15:0] v68bk_rword;
    wire        v68bk2_req, v68bk2_done_t;
    wire [21:0] v68bk2_addr;
    wire [15:0] v68bk2_rword;
    v9968_vram_shim #(.VRAM_BASE(22'h280000), .SPC(1)) u_v68shim (     // SPC: cache de sprites aparte (Space Manbow, 10/11/2026)
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .vram_address(v68_vram_address), .vram_write(v68_vram_write),
        .vram_valid(v68_vram_valid), .vram_wdata(v68_vram_wdata),
        .vram_wdata_mask(v68_vram_mask), .vram_tag(v68_vram_tag),
        .vram_rdata(v68_vram_rdata), .vram_rdata_en(v68_vram_rdata_en),
        .vram_rtag(v68_vram_rtag),
        .bk_req(v68bk_req), .bk_we(v68bk_we), .bk_addr(v68bk_addr),
        .bk_wdata(v68bk_wdata), .bk_wmask(v68bk_wmask),
        .bk_rword(v68bk_rword), .bk_done_t(v68bk_done_t),
        .bk2_req(v68bk2_req), .bk2_addr(v68bk2_addr),
        .bk2_rword(v68bk2_rword), .bk2_done_t(v68bk2_done_t),
        .vram_stall(v68_vram_stall),
        .diag(),
        .dbg_miss(v68dbg_miss), .dbg_bka(v68dbg_bka), .dbg_bkb(v68dbg_bkb),
        .dbg_park(v68dbg_park),
        .dbg_drops(v68dbg_drops)
    );
`ifdef ENABLE_VRAM_AXI
    // ==== EXPERIMENTO _128X: la VRAM del V9968 vive en la DDR3 del SOM ====
    // Los MISMOS bridges CDC, con el lado far a clk_x1 (74.25, lo genera la
    // IP DDR3) y hablando con v9968_ddr3_backend en vez de memory.v. Los
    // puertos wv2/wv3 de memory.v quedan inertes (reqs a 0, abajo). El shim
    // NO se toca. ADVERTENCIA saga _94-_103: la DDR3 de esta placa es
    // analogicamente marginal (loteria de calibracion) — telemetria
    // vddr_diag en cnt_c[23:16] del COM11.
    wire        vddr_clk_x1;
    wire        vddr_a_req, vddr_a_we, vddr_b_req;
    wire [21:0] vddr_a_addr, vddr_b_addr;
    wire [31:0] vddr_a_wdata;      // _148 FIX B: palabra de 32b + mascara
    wire [3:0]  vddr_a_wmask;
    wire [15:0] vddr_a_dout, vddr_b_dout;
    wire        vddr_a_done, vddr_b_done;
    wire        vddr_ready;
    wire [7:0]  vddr_diag;
    wire [31:0] vddr_ops;      // _129b: {lecturas[31:16], escrituras[15:0]}

    v9968_sdram_bridge u_v68bridge (
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .bk_req(v68bk_req), .bk_we(v68bk_we), .bk_addr(v68bk_addr),
        .bk_wdata(v68bk_wdata), .bk_wmask(v68bk_wmask),
        .bk_rword(v68bk_rword), .bk_done_t(v68bk_done_t),
        .clk_108m(vddr_clk_x1),
        .wv2_req(vddr_a_req), .wv2_we(vddr_a_we), .wv2_addr(vddr_a_addr),
        .wv2_wdata(vddr_a_wdata), .wv2_wmask(vddr_a_wmask),
        .wv2_dout(vddr_a_dout), .wv2_done(vddr_a_done)
    );
    v9968_sdram_bridge u_v68bridge2 (
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .bk_req(v68bk2_req), .bk_we(1'b0), .bk_addr(v68bk2_addr),
        .bk_wdata(32'd0), .bk_wmask(4'd0),
        .bk_rword(v68bk2_rword), .bk_done_t(v68bk2_done_t),
        .clk_108m(vddr_clk_x1),
        .wv2_req(vddr_b_req), .wv2_we(), .wv2_addr(vddr_b_addr),
        .wv2_wdata(), .wv2_wmask(), .wv2_dout(vddr_b_dout), .wv2_done(vddr_b_done)
    );

    // ==== ZYNQ: la VRAM del V9968 en la DDR del PS (zynq/v9968_axi_backend.v, HP0 @ FCLK0) ====
    // Misma interfaz que v9968_ddr3_backend; los bridges se conectan tal cual.
    reg [1:0] rst150_s = 2'b00;
    always @(posedge fclk0) rst150_s <= {rst150_s[0], frst0_n};
`ifdef ENABLE_DUAL
    v9968_axi_backend #(.VRAM_BASE(32'h1000_0000), .TAG_BITS(5), .ID_PFX(6'd0)) u_vddr3 (   // Dual: HP0 compartido con B (IDs 32-63): A solo usa 0-31
`else
    v9968_axi_backend #(.VRAM_BASE(32'h1000_0000)) u_vddr3 (
`endif
        .a_req(vddr_a_req), .a_we(vddr_a_we), .a_addr(vddr_a_addr),
        .a_wdata(vddr_a_wdata), .a_wmask(vddr_a_wmask),
        .a_dout(vddr_a_dout), .a_done(vddr_a_done),
        .b_req(vddr_b_req), .b_addr(vddr_b_addr),
        .b_dout(vddr_b_dout), .b_done(vddr_b_done),
        .clk_x1_out(vddr_clk_x1), .ready(vddr_ready), .diag(vddr_diag),
        .dbg_ops(vddr_ops),
        .recal_req(1'b0),
        .aclk(fclk0), .aresetn(rst150_s[1]),
        .M_AWID(hp0_awid), .M_AWADDR(hp0_awaddr), .M_AWLEN(hp0_awlen), .M_AWSIZE(hp0_awsize),
        .M_AWBURST(hp0_awburst), .M_AWLOCK(hp0_awlock), .M_AWCACHE(hp0_awcache), .M_AWPROT(hp0_awprot),
        .M_AWQOS(hp0_awqos), .M_AWVALID(hp0_awvalid), .M_AWREADY(hp0_awready),
        .M_WID(hp0_wid), .M_WDATA(hp0_wdata), .M_WSTRB(hp0_wstrb), .M_WLAST(hp0_wlast),
        .M_WVALID(hp0_wvalid), .M_WREADY(hp0_wready),
        .M_BID(hp0_bid), .M_BRESP(hp0_bresp), .M_BVALID(hp0_bvalid), .M_BREADY(hp0_bready),
        .M_ARID(hp0_arid), .M_ARADDR(hp0_araddr), .M_ARLEN(hp0_arlen), .M_ARSIZE(hp0_arsize),
        .M_ARBURST(hp0_arburst), .M_ARLOCK(hp0_arlock), .M_ARCACHE(hp0_arcache), .M_ARPROT(hp0_arprot),
        .M_ARQOS(hp0_arqos), .M_ARVALID(hp0_arvalid), .M_ARREADY(hp0_arready),
        .M_RID(hp0_rid), .M_RDATA(hp0_rdata), .M_RRESP(hp0_rresp), .M_RLAST(hp0_rlast),
        .M_RVALID(hp0_rvalid), .M_RREADY(hp0_rready)
    );
`else
    // _148 FIX B — CAMINO LEGACY (VRAM en la SDRAM compartida, respaldo _137).
    // memory.v solo sabe escribir 1 BYTE por operacion en wv2/wv3 (SdrDat =
    // {wdata,wdata} con la DQM sacada de addr[0]) y NO se toca. El bridge se
    // instancia con NARROW_BYTE=1: acepta la palabra de 32b del shim y la
    // SERIALIZA en hasta 4 round-trips hacia memory.v, devolviendo bk_done_t
    // solo al terminar la palabra entera. Coste identico al esquema byte-a-byte
    // que este camino ya tenia; el shim ve una escritura atomica.
    // FAR_DW=8 mantiene el bus de datos far del ancho de memory.v (sin
    // conexiones de anchura desigual, que Gowin resuelve mal).
    v9968_sdram_bridge #(.NARROW_BYTE(1), .FAR_DW(8)) u_v68bridge (
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .bk_req(v68bk_req), .bk_we(v68bk_we), .bk_addr(v68bk_addr),
        .bk_wdata(v68bk_wdata), .bk_wmask(v68bk_wmask),
        .bk_rword(v68bk_rword), .bk_done_t(v68bk_done_t),
        .clk_108m(clk_108m),
        .wv2_req(wv2_req), .wv2_we(wv2_we), .wv2_addr(wv2_addr),
        .wv2_wdata(wv2_wdata), .wv2_wmask(),
        .wv2_dout(wv2_dout), .wv2_done(wv2_done)
    );
    v9968_sdram_bridge #(.NARROW_BYTE(1), .FAR_DW(8)) u_v68bridge2 (
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .bk_req(v68bk2_req), .bk_we(1'b0), .bk_addr(v68bk2_addr),
        .bk_wdata(32'd0), .bk_wmask(4'd0),
        .bk_rword(v68bk2_rword), .bk_done_t(v68bk2_done_t),
        .clk_108m(clk_108m),
        .wv2_req(wv3_req), .wv2_we(wv3_we), .wv2_addr(wv3_addr),
        .wv2_wdata(wv3_wdata), .wv2_wmask(),
        .wv2_dout(wv3_dout), .wv2_done(wv3_done)
    );
`endif

    // ---- puente de video 800px -> HDMI 720p (back-end TMDS intacto) ----
    // _127H: telemetria del audio — eventos de reset del HDMI y toggles del
    // lock del puente (pulsos estirados ~30ms; 2FF + flanco a clk_54m). El
    // lock togglea a ~30Hz en regimen: su TASA en el lector delata perdidas.
    // Si los cortes de ~3s del audio coinciden con saltos de rst_cnt, el
    // culpable es el re-arranque del stream HDMI (el receptor silencia).
    wire v68_dbg_lock, v68_dbg_rst;
    wire [31:0] v68_dbg_apkt;        // _127I: contadores del packet_picker
    wire [5:0]  v68_dbg_defer;       // _134: yanks del reset diferidos
    wire [4:0]  v68_dbg_tear;        // _134: assert en silicio (esperado 0)
    reg [2:0]  aud_rst_sy = 3'd0, aud_lock_sy = 3'd0;
    reg [15:0] aud_rst_cnt = 16'd0, aud_lock_cnt = 16'd0;
    always @(posedge clk_54m) begin
        aud_rst_sy  <= {aud_rst_sy[1:0],  v68_dbg_rst};
        aud_lock_sy <= {aud_lock_sy[1:0], v68_dbg_lock};
        if (aud_rst_sy[1]  & ~aud_rst_sy[2])  aud_rst_cnt  <= aud_rst_cnt  + 16'd1;
        if (aud_lock_sy[1] & ~aud_lock_sy[2]) aud_lock_cnt <= aud_lock_cnt + 16'd1;
    end
    // ce de pixel: el V9968 emite 1 pixel cada 2 ciclos de 85.9; un toggle
    // libre muestrea cada pixel exactamente una vez (la fase da igual: el
    // dato es estable 2 ciclos y la captura se auto-alinea con HS).
    reg ce86 = 1'b0;
    always @(posedge clk_86) ce86 <= ~ce86;

    wire [15:0] amp_hdmi;   // _133: vumetro del lado HDMI (ver dbg_uart)

    // ========================================================================
    // V3.1 PELDANO 1 -- iosys de TangCore (nand2mario), enlace UART con el BL616
    // ------------------------------------------------------------------------
    // Que se esta probando aqui, y por que asi:
    //
    //  * EL ENLACE NO NECESITA CABLE. bl616_jtagsel es el pad V14, que top.v ya
    //    documenta como "GPIO28 TX del BL616": exactamente el UART_RXD de la
    //    console.cst de nestang. Y U15 (GPIO27 RX del MCU) quedo libre al mudar
    //    el companion SPI al J10. Son los DOS MISMOS pines que usa TangCore.
    //
    //  * TODAVIA NO HAY FIRMWARE EN EL BL616, asi que nadie va a hablar por esa
    //    UART. Para que el bitstream diga ALGO, la BSRAM del overlay se genera
    //    con texto ya escrito en el buffer de caracteres (tools/gen_iosys_bram.py):
    //    al encender, textdisp lo pinta sin que intervenga nadie.
    //
    //  * Y COMO overlay_reg NACE A 1 en iosys_bl616, sin MCU que lo apague el
    //    overlay taparia la pantalla PARA SIEMPRE. De ahi el temporizador: unos
    //    segundos de overlay y se aparta. Asi un solo .fs contesta dos preguntas
    //    -- si la cadena BSRAM->textdisp->mux->HDMI pinta, y si el MSX sigue
    //    arrancando igual con el iosys dentro. El temporizador se va el dia que
    //    el MCU mande el comando 8.
    // ========================================================================
    wire        iosys_overlay;
    wire [7:0]  iosys_ovl_x, iosys_ovl_y;
    wire [14:0] iosys_ovl_color;

`ifdef ENABLE_IOSYS

    // ~6 s a 27 MHz. Cuenta solo mientras el PLL esta enganchado.
    reg [27:0] iosys_demo_cnt = 28'd0;
    always @(posedge clk_27m) begin
        if (!clock_locked)                 iosys_demo_cnt <= 28'd0;
        else if (iosys_demo_cnt != 28'd162_000_000)
                                           iosys_demo_cnt <= iosys_demo_cnt + 28'd1;
    end
    wire iosys_demo_win = (iosys_demo_cnt != 28'd162_000_000);

    // ¿Ha hablado alguien por la UART? En reposo la linea esta ALTA; un bit de
    // arranque a 2 Mbps dura 500 ns = ~13 ciclos de 27 MHz. Con 6 ciclos bajos
    // seguidos basta para distinguirlo de un glitch, y sobra margen.
    //
    // PARA QUE: sin MCU, el temporizador aparta el overlay a los 6 s y la
    // maquina queda usable (lo de siempre). En cuanto el MCU dice algo, el
    // mando es SUYO -- enciende y apaga el overlay con el comando 8 -- y el
    // temporizador deja de existir. Sin esto, el MCU pintaria su menu y a los
    // 6 s se lo tragaria nuestro contador.
    reg  [1:0] v14_sync = 2'b11;
    reg  [2:0] v14_bajo = 3'd0;
    reg        mcu_visto = 1'b0;
    always @(posedge clk_27m) begin
        v14_sync <= {v14_sync[0], bl616_jtagsel};
        if (v14_sync[1]) v14_bajo <= 3'd0;
        else if (v14_bajo != 3'd6) v14_bajo <= v14_bajo + 3'd1;
        if (v14_bajo == 3'd6) mcu_visto <= 1'b1;
    end

    wire iosys_ovl_on = iosys_overlay & (mcu_visto | iosys_demo_win);

    // ========================================================================
    // TECLADO USB -> MENU DEL MCU
    // ------------------------------------------------------------------------
    // Los USB-A de la Console 60K van al FABRIC (ENABLE_USB_KBD, usb_hid_host
    // directo), mientras que el host USB del BL616 esta en el USB-C. Son puertos
    // distintos y no hay forma de que el MCU vea nuestro teclado... ni falta.
    //
    // iosys_bl616 tiene entradas joy1/joy2 que TRANSMITE AL MCU CADA 20 ms
    // (SEND_JOYPAD). O sea que el camino FPGA -> MCU para los mandos ya existe:
    // basta con presentarle el teclado como si fuera un pad. Cero cableado.
    //
    // Bits, sacados de joy_choice() del firmware -- no del comentario del
    // modulo, que enumera los botones pero no dice las mascaras:
    //   0x10 arriba · 0x20 abajo · 0x40/0x80 pagina · 0x100 A · 0x1 B
    //   0x84 = combinacion del OSD (enciende y apaga el overlay)
    //
    // `keyboard` esta indexado por USB HID usage, NO por celda de la matriz MSX
    // (por eso keyboard[68] es F11 mas arriba). Flechas = 79..82, Enter = 40,
    // Esc = 41, F12 = 69.
    //
    // F12 monta 0x84 ENTERO porque joy_choice compara por IGUALDAD EXACTA
    // (joy1 == overlay_key_code), no por mascara: con un solo bit no entraria
    // nunca. Y 0x84 es el valor POR DEFECTO del firmware
    // (OPTION_OSD_KEY_SELECT_RIGHT), asi que funciona sin tocar opciones.
    // ⇒ F12 es la salida de emergencia: aparta el overlay y deja ver el MSX.
    // ========================================================================
    wire k_up  = keyboard[82], k_dn = keyboard[81];
    wire k_lf  = keyboard[80], k_rt = keyboard[79];
    wire k_ent = keyboard[40], k_esc = keyboard[41];
    wire k_f12 = keyboard[69];

    wire [11:0] joy_raw = (k_ent ? 12'h100 : 12'd0) |   // A     = Enter
                          (k_esc ? 12'h001 : 12'd0) |   // B     = Esc
                          (k_up  ? 12'h010 : 12'd0) |   // arriba
                          (k_dn  ? 12'h020 : 12'd0) |   // abajo
                          (k_lf  ? 12'h040 : 12'd0) |   // pagina anterior
                          (k_rt  ? 12'h080 : 12'd0) |   // pagina siguiente
                          (k_f12 ? 12'h084 : 12'd0);    // OSD (exacto)

    // `keyboard` nace en el dominio del host USB. Son pulsaciones humanas que el
    // MCU muestrea cada 20 ms, pero el cruce se sincroniza igual: un bit
    // metaestable aqui sale gratis de evitar.
    reg [11:0] joy_s0 = 12'd0, joy_s1 = 12'd0;
    always @(posedge clk_27m) begin
        joy_s0 <= joy_raw;
        joy_s1 <= joy_s0;
    end
    wire [11:0] iosys_joy = joy_s1;

    // Estado del core hacia el OSD y congelacion del MSX. Se DECLARAN aqui y se
    // arman al final del modulo: caps_on, kana_on y fan_dbg_cnt nacen mucho mas
    // abajo en el fichero.
    wire [63:0] iosys_status;
    reg         iosys_frz = 1'b0;

    // ---- gamepads USB del BL616 -> puertos de joystick del MSX -------------
    // El MCU manda el estado de los mandos con el comando 9. El formato lo dice
    // usb_gamepad.cpp: "SNES: R L X A RT LT DN UP ST SE Y B", o sea bit 11 -> 0:
    //     bit 4 arriba · 5 abajo · 6 izquierda · 7 derecha   (la CRUCETA)
    //     bit 8 A · 9 X · 0 B · 1 Y · 2 Select · 3 Start
    //     bit 10 L · 11 R                                    (los HOMBROS)
    // Comprobado en el firmware, no en el comentario: hidparser.cpp mete
    // right/left/down/up en los bits 0..3 del byte joy y usb_gamepad.cpp:337
    // los sube a 7/6/5/4; los botones 5 y 6 (hombros) van a 10/11. Y es el
    // MISMO mapa que usa joy_choice para el menu del MCU (izquierda/derecha =
    // pagina anterior/siguiente = bits 6/7; kbd_to_joy pone ahi las flechas).
    //
    // Nuestro joystick0/1: [3]=arriba [2]=abajo [1]=izq [0]=der (asi lo consume
    //                      joy0_msx: PSG bit0=arriba=~joystick0[3] ... bit3=der=~joystick0[0])
    //                      [4]=disparo A [5]=disparo B [6]/[7]=autofire
    // 🚨 Historia: desde la v3.1 (25/08) esto estaba escrito como [0]=arriba
    // y con la cruceta en los bits 10/11: en la Console 60K arriba/abajo daban
    // derecha/izquierda, izquierda/derecha no hacian NADA y los hombros movian
    // arriba/abajo. El 14/09 se giro arriba/abajo (cazado en la Zynq) pero se
    // dejo la cruceta en 10/11, que en el BL616 son los hombros; corregido el
    // mismo dia leyendo el firmware. El companion de la Zynq (hid_pad.c) sigue
    // este mismo formato.
    wire [15:0] mcu_hid1_u, mcu_hid2_u;                 // del BL616 (iosys)
    reg  [15:0] joy1_mb_s1 = 16'd0, joy1_mb_s2 = 16'd0;  // ZYNQ: del companion (buzon, clk_54m -> clk_27m)
    reg  [15:0] joy2_mb_s1 = 16'd0, joy2_mb_s2 = 16'd0;
    always @(posedge clk_27m) begin
        joy1_mb_s1 <= joy1_mbox; joy1_mb_s2 <= joy1_mb_s1;
        joy2_mb_s1 <= joy2_mbox; joy2_mb_s2 <= joy2_mb_s1;
    end
    wire [15:0] mcu_hid1 = mcu_hid1_u | joy1_mb_s2;
    wire [15:0] mcu_hid2 = mcu_hid2_u | joy2_mb_s2;
    assign joystick0 = { mcu_hid1[9],  mcu_hid1[1],    // autofire  <- X, Y
                         mcu_hid1[0],  mcu_hid1[8],    // TrigB/A   <- B, A
                         mcu_hid1[4],  mcu_hid1[5],    // [3] arriba / [2] abajo
                         mcu_hid1[6],  mcu_hid1[7] };  // [1] izq    / [0] der
    assign joystick1 = { mcu_hid2[9],  mcu_hid2[1],
                         mcu_hid2[0],  mcu_hid2[8],
                         mcu_hid2[4],  mcu_hid2[5],
                         mcu_hid2[6],  mcu_hid2[7] };

    iosys_bl616 #(
        .FREQ      (27_000_000),      // dominio de clk_27m; el baud (2 Mbps) lo
                                      // saca BaudTickGen con acumulador fraccionario
        .CORE_ID   (16'd77),          // 'M'. nestang=1, snestang=2.
        .COLOR_LOGO(15'b00000_10101_00000)
    ) u_iosys (
        .clk            (clk_27m),
        .hclk           (clk_hdmi),
        .resetn         (clock_locked),

        .overlay        (iosys_overlay),
        .overlay_x      (iosys_ovl_x),
        .overlay_y      (iosys_ovl_y),
        .overlay_color  (iosys_ovl_color),

        .joy1           (iosys_joy),       // el teclado USB que YA lee la FPGA
        .joy2           (12'd0),
        .hid1           (mcu_hid1_u),
        .hid2           (mcu_hid2_u),

        // Peldano 1: la carga de ROM NO se conecta todavia. El sumidero natural
        // ya existe (rom_addr/rom_dout/rom_write con flash_idle, ~linea 2270),
        // pero eso es el peldano siguiente y aqui solo se quiere el coste.
        .rom_loading    (),
        .rom_do         (),
        .rom_do_valid   (),

        // Interfaz de disco del core PCXT: sin usar (nuestra SD sigue siendo de
        // Nextor, que es justo lo que evita el traspaso de mando).
        .mgmt_address   (),
        .mgmt_read      (),
        .mgmt_readdata  (16'd0),
        .mgmt_write     (),
        .mgmt_writedata (),
        .fdd_request    (2'd0),

        .kbd_data       (),
        .kbd_data_valid (),
        .core_config    (),
        .status_in      (iosys_status),   // MSXimus: comando 14

        .uart_rx        (bl616_jtagsel),   // V14 <- TX del BL616
        .uart_tx        (iosys_uart_tx)    // U15 -> RX del BL616
    );
`else
    // Sin iosys: el overlay se apaga y el pad de TX queda en reposo (la UART
    // en reposo es NIVEL ALTO; dejarlo a 0 seria un BREAK permanente para el
    // MCU). Este par de builds A/B es lo que da el coste real en CLS.
    assign iosys_overlay   = 1'b0;
    assign iosys_ovl_color = 15'd0;
    assign iosys_uart_tx   = 1'b1;
`endif

    wire [29:0] v68_tmds;             // (sin uso desde el V9991: el serializer vuelve a vivir aqui dentro)
    wire        v68_vblank;
    // V9991 (28/10/2026): UNA HDMI de verdad. Este puente lleva el unico codificador y el serializer;
    // el puente del V9990 lee su frame buffer con el raster de este hdmi (hd_cx/hd_cy) y el compositor
    // v9991_compose elige por pixel entre los dos (c_rgb68 / c_rgb99 + c_ys99) -> rgb_ext.
    wire [10:0] hd_cx;
    wire [9:0]  hd_cy;
    wire [23:0] c_rgb68, c_rgb99, c_rgb;
    wire        c_ys99, c_in99;
    wire [2:0]  c_reso99;             // modo del frame del V9990 que se muestra (clk_hdmi)
    wire        c_il99;               // ... y si es entrelazado (480 lineas tejidas; 28/10/2026)
    // V9991 ventana (modo 2): lo que el compositor manda al puente del V9968 (clk_hdmi, cambia en el vblank)
    wire        c_win_en;
    wire [1:0]  c_win_scl;            // {x2, x0,5}
    wire signed [11:0] c_win_x0;
    wire signed [10:0] c_win_y0;
    wire [9:0]  c_win_sx0;
    wire [7:0]  c_win_sy0;
    wire        v68_aresetn;          // = rst86a_s[1] (se asigna en el bloque del V9990)
    wire [4:0]  v68_win_underrun;
    wire        v68_win_valid;
    // AXI del frame buffer del V9968 (fb68_*): al arbitro interior del GP1 (con el del V9990)
    wire [5:0]  fb68_awid, fb68_wid, fb68_bid, fb68_arid, fb68_rid;
    wire [31:0] fb68_awaddr, fb68_wdata, fb68_araddr, fb68_rdata;
    wire [3:0]  fb68_awlen, fb68_wstrb, fb68_awcache, fb68_awqos, fb68_arlen, fb68_arcache, fb68_arqos;
    wire [2:0]  fb68_awsize, fb68_awprot, fb68_arsize, fb68_arprot;
    wire [1:0]  fb68_awburst, fb68_awlock, fb68_bresp, fb68_arburst, fb68_arlock, fb68_rresp;
    wire        fb68_awvalid, fb68_awready, fb68_wlast, fb68_wvalid, fb68_wready, fb68_bvalid, fb68_bready;
    wire        fb68_arvalid, fb68_arready, fb68_rlast, fb68_rvalid, fb68_rready;
`ifdef ENABLE_V9990
    // FB del V9968 (modo 2): 3 slots de 0x60000 en 32'h0F80_0000 (28/10/2026: estaba en 0x1060_0000, pero el FB del V9990
    // crece a 3 x 0x110000 desde 0x1040_0000 por B7 y el entrelazado, hasta 0x1073_0000)
    wire       c_desk_free;           // rama beta: el compositor en la ventana con el gestor (clk_pixel): el V9990 es del companion
    wire [1:0] comp_mode_active;      // modo del compositor que sale ahora (clk_pixel); declarado aqui: lo usa el puente del V9968 (free_run)
    msx2hdmi_v9968 #(.EXT_COMPOSE(1), .WINDOW(1), .FB_BASE(32'h0F80_0000)) u_msx2hdmi68 (
        .cx_out       (hd_cx),
        .cy_out       (hd_cy),
        .rgb_pre      (c_rgb68),
        .rgb_ext      (c_rgb),
        .aresetn      (v68_aresetn),
        .win_en       (c_win_en), .free_run (comp_mode_active == 2'd1), .win_x0 (c_win_x0), .win_y0 (c_win_y0), .win_scl (c_win_scl),
        .win_sx0      (c_win_sx0), .win_sy0 (c_win_sy0),
        .fs43         (mb_vid_ctl[4] & (comp_mode_active == 2'd0)), .hires512 (v68_hires512),   // 4:3 + Scale3x solo en el modo 0 (pantalla completa)
        .dbg_win_underrun (v68_win_underrun), .dbg_win_valid (v68_win_valid),
        .M_AWID(fb68_awid), .M_AWADDR(fb68_awaddr), .M_AWLEN(fb68_awlen), .M_AWSIZE(fb68_awsize),
        .M_AWBURST(fb68_awburst), .M_AWLOCK(fb68_awlock), .M_AWCACHE(fb68_awcache), .M_AWPROT(fb68_awprot),
        .M_AWQOS(fb68_awqos), .M_AWVALID(fb68_awvalid), .M_AWREADY(fb68_awready),
        .M_WID(fb68_wid), .M_WDATA(fb68_wdata), .M_WSTRB(fb68_wstrb), .M_WLAST(fb68_wlast),
        .M_WVALID(fb68_wvalid), .M_WREADY(fb68_wready),
        .M_BID(fb68_bid), .M_BRESP(fb68_bresp), .M_BVALID(fb68_bvalid), .M_BREADY(fb68_bready),
        .M_ARID(fb68_arid), .M_ARADDR(fb68_araddr), .M_ARLEN(fb68_arlen), .M_ARSIZE(fb68_arsize),
        .M_ARBURST(fb68_arburst), .M_ARLOCK(fb68_arlock), .M_ARCACHE(fb68_arcache), .M_ARPROT(fb68_arprot),
        .M_ARQOS(fb68_arqos), .M_ARVALID(fb68_arvalid), .M_ARREADY(fb68_arready),
        .M_RID(fb68_rid), .M_RDATA(fb68_rdata), .M_RRESP(fb68_rresp), .M_RLAST(fb68_rlast),
        .M_RVALID(fb68_rvalid), .M_RREADY(fb68_rready),
`else
    msx2hdmi_v9968 u_msx2hdmi68 (
        .cx_out       (hd_cx),
        .cy_out       (hd_cy),
        .rgb_pre      (c_rgb68),
        .rgb_ext      (24'd0),
        .aresetn      (1'b1),
        .win_en       (1'b0), .free_run (1'b0), .win_x0 (12'sd0), .win_y0 (11'sd0), .win_scl (2'b00), .win_sx0 (10'd0), .win_sy0 (8'd0),
        .fs43         (1'b0), .hires512 (1'b0),
        .dbg_win_underrun (), .dbg_win_valid (),
        .M_AWID(), .M_AWADDR(), .M_AWLEN(), .M_AWSIZE(), .M_AWBURST(), .M_AWLOCK(), .M_AWCACHE(), .M_AWPROT(),
        .M_AWQOS(), .M_AWVALID(), .M_AWREADY(1'b0),
        .M_WID(), .M_WDATA(), .M_WSTRB(), .M_WLAST(), .M_WVALID(), .M_WREADY(1'b0),
        .M_BID(6'd0), .M_BRESP(2'd0), .M_BVALID(1'b0), .M_BREADY(),
        .M_ARID(), .M_ARADDR(), .M_ARLEN(), .M_ARSIZE(), .M_ARBURST(), .M_ARLOCK(), .M_ARCACHE(), .M_ARPROT(),
        .M_ARQOS(), .M_ARVALID(), .M_ARREADY(1'b0),
        .M_RID(6'd0), .M_RDATA(32'd0), .M_RRESP(2'd0), .M_RLAST(1'b0), .M_RVALID(1'b0), .M_RREADY(),
`endif
        .clk          (clk_86),
        .resetn       (rst86_n),
        .ce           (ce86),
        .r            (v68_r8[7:2]),
        .g            (v68_g8[7:2]),
        .b            (v68_b8[7:2]),
        .hs_n         (v68_hs),          // ACTIVO ALTO (convencion V9968)
        .vs_n         (v68_vs),
        .blank        (~v68_de),
        .pal_mode     (1'b0),            // v1: solo back-end NTSC (720p60)
`ifdef ENABLE_CONFIG
        .aspect_wide  (config_enable_16_9),
        .scanlines    (config_enable_scanlines),
`else
        .aspect_wide  (1'b0),
        .scanlines    (1'b0),
`endif
        .audio_l      (audio_sample),
        .audio_r      (audio_sample_r),
        .dbg_amp      (amp_hdmi),
        .clk_pixel    (clk_hdmi),
        .clk_5x_pixel (clk_hdmi5),
        .tmds_clk_n   (clk_n),
        .tmds_clk_p   (clk_p),
        .tmds_d_n     (data_n),
        .tmds_d_p     (data_p),
        .dbg_vs_tick  (),
        .dbg_wr_act   (),
        .dbg_nonblack (),
        .dbg_lock_tgl (v68_dbg_lock),    // _127H: telemetria audio
        .dbg_hdmi_rst (v68_dbg_rst),
        .dbg_rd_act   (),
        .dbg_apkt     (v68_dbg_apkt),    // _127I: {ovr, 0, paquetes_audio}
        .dbg_defer    (v68_dbg_defer),   // _134: yanks diferidos (~60/s sano)
        .dbg_tear     (v68_dbg_tear),    // _134: resets en zona de peligro (0 sano)
        .ovl_x        (iosys_ovl_x),
        .ovl_y        (iosys_ovl_y),
        .ovl_color    (iosys_ovl_color),
        .ovl_on       (iosys_ovl_on),
        .tmds_out     (v68_tmds),        // sin uso (el serializer esta dentro)
        .vblank       (v68_vblank)
    );

`ifdef ENABLE_V9990
    // ========================================================================
    // V9990 (tiny9990 de buppu3, BSD-3) en los puertos 60h-6Fh, VRAM de 512 KB
    // en la DDR (0x10300000, S_AXI_GP1 a clk_86), su propio puente a 720p y
    // UNA HDMI conmutada: la tecla Pausa (HID 0x48 = keyboard[72], libre en el
    // mapa MSX de usb_keyboard_msx.vhd) alterna entre el V9968 y el V9990.
    // 🚨 Antes era Bloq Despl (0x47 = keyboard[71]) = la tecla STOP del MSX:
    // pausaba el programa BASIC en marcha cada vez que se conmutaba (20/09).
    // Arranca mostrando el V9968 (la BIOS no sabe del V9990). Ver fpga/v9990/.
    // ========================================================================
    // decode del bus del T80 (mismo patron que vdp_csw_n/vdp_csr_n); el combinacional solo
    // lo usa el mux de cpu_din (dominio 54)
    wire       v99_io_hit = (bus_addr[7:4] == 4'h6);
    wire       v99_csw_n  = (v99_io_hit && bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_wr_n == 1'b0) ? 1'b0 : 1'b1;
    wire       v99_csr_n  = (v99_io_hit && bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0) ? 1'b0 : 1'b1;
    // 18/10: hacia clk_86 va REGISTRADO en clk_54m (chip-selects, MODE y dato del mismo flanco):
    // asi no cruza logica combinacional entre dominios (el glue los sincroniza con 2FF). Cuesta
    // medio ciclo de 54 (RD/WR del T80 cambian en el flanco de bajada) en todo el acceso, la
    // subida y la bajada del WAIT incluidas: cs -> wait_n -> 2FF a 54 llega en <= 3,75 ciclos de 54
    // desde la bajada de RD/WR (3,5 medidos, antes 2,5) y el T80 muestrea WAIT un T despues
    // (10 ciclos en turbo, 15 a 3,58; +1 T con el wait de I/O): margen minimo 307 ns en turbo.
    // Al soltar el WAIT un P#0 cae de vez en cuando en un Tw mas: +0,07 T por acceso P#0 en turbo
    // (~1,6 %), +0,00 a 3,58. Medido con tb/run_v9990_glue.sh (18/10).
    // 30/10 (beta): el registro lo hace v9990_arm_port, que ademas intercala los accesos del ARM (own = 1)
    wire       v99_csw_r_n, v99_csr_r_n;
    wire [3:0] v99_mode_r;
    wire [7:0] v99_cdo_r;
    wire [7:0] v99_dout;
    wire       v99_wait86_n;
`ifdef TR_V9990
    // TRV (05/11): como el V9968 en la fase 4a. El WAIT del glue es combinacional de clk_86: se registra antes de cruzar y el sincronizador pasa a 3 etapas, de modo que sube
    // >= 1 ciclo de clk_54m despues de que el dato (2 registros, abajo) este estable. El strobe del R800 dura >= 36 ciclos (tr_wait_io): la espera llega a tiempo.
    reg v99_wait86_rq = 1'b1;
    always @(posedge clk_86) v99_wait86_rq <= v99_wait86_n;
    (* ASYNC_REG = "TRUE" *) reg [2:0] v99_wait_s = 3'b111;
    always @(posedge clk_54m) v99_wait_s <= {v99_wait_s[1:0], v99_wait86_rq};
    assign v99_wait54_n = v99_wait_s[2];
    reg [7:0] v99_dout_q1 = 8'hFF, v99_dout_q2 = 8'hFF;
    always @(posedge clk_54m) begin v99_dout_q1 <= v99_dout; v99_dout_q2 <= v99_dout_q1; end
    assign v99_dout_m = v99_dout_q2;
`else
    reg  [1:0] v99_wait_s = 2'b11;
    always @(posedge clk_54m) v99_wait_s <= {v99_wait_s[0], v99_wait86_n};
    assign v99_wait54_n = v99_wait_s[1];
    assign v99_dout_m = v99_dout;
`endif
    reg  [1:0] v9a_rst_s = 2'b00;
    always @(posedge clk_54m) v9a_rst_s <= {v9a_rst_s[0], frst0_n};
    reg  [1:0] v9a_allow_s = 2'b00;            // el modo ventana del compositor, a clk_54m (cambia en el vblank)
    always @(posedge clk_54m) v9a_allow_s <= {v9a_allow_s[0], c_desk_free};
`ifdef TR_SIN_V9990
    // perfil TR: sin V9990 ni puerto del ARM. Los puertos 60h-6Fh no tienen dueno: el bus no se retiene y nada se inyecta
    assign v99_csw_r_n = 1'b1;  assign v99_csr_r_n = 1'b1;  assign v99_mode_r = 4'd0;  assign v99_cdo_r = 8'd0;
    assign v9a_wait_z_n = 1'b1;
    assign v9a_pop = 1'b0;  assign v9a_own = 1'b0;  assign v9a_busy = 1'b0;  assign v9a_tmo = 4'd0;
`else
    v9990_arm_port u_v9arm (
        .clk(clk_54m), .rst_n(v9a_rst_s[1]),
        .en(v9a_en), .allow(v9a_allow_s[1]),   // solo con la ventana y el gestor (teclas V y B): el juego no usa el V9990
        .ent(v9a_ent), .ent_v(v9a_ent_v), .pop(v9a_pop),
        .z_csw_n(v99_csw_n), .z_csr_n(v99_csr_n), .z_mode(bus_addr[3:0]), .z_cdo(cpu_dout),
        .o_csw_n(v99_csw_r_n), .o_csr_n(v99_csr_r_n), .o_mode(v99_mode_r), .o_cdo(v99_cdo_r),
        .wait_n(v99_wait54_n), .cdi(v99_dout), .wait_z_n(v9a_wait_z_n),
        .own(v9a_own), .busy(v9a_busy), .tmo(v9a_tmo)
    );
`endif
    // reset AXI del PS sincronizado al dominio del V9990
    reg  [1:0] rst86a_s = 2'b00;
    always @(posedge clk_86) rst86a_s <= {rst86a_s[0], frst0_n};

    wire        v99_de, v99_hs, v99_vs, v99_ys, v99_dclk_en, v99_il, v99_eo, v99_stalled;
    wire [4:0]  v99_r, v99_g, v99_b;
    wire [2:0]  v99_reso;
    wire [31:0] v99_dbg_reads, v99_dbg_miss, v99_dbg_stall, v99_dbg_writes;
    // AXI del cliente de VRAM (vc_*) y del frame buffer (fb_*): los junta axi_arb2 en el GP1
    wire [5:0]  vc_awid, vc_wid, vc_bid, vc_arid, vc_rid, fb_awid, fb_wid, fb_bid, fb_arid, fb_rid;
    wire [31:0] vc_awaddr, vc_wdata, vc_araddr, vc_rdata, fb_awaddr, fb_wdata, fb_araddr, fb_rdata;
    wire [3:0]  vc_awlen, vc_wstrb, vc_awcache, vc_awqos, vc_arlen, vc_arcache, vc_arqos;
    wire [3:0]  fb_awlen, fb_wstrb, fb_awcache, fb_awqos, fb_arlen, fb_arcache, fb_arqos;
    wire [2:0]  vc_awsize, vc_awprot, vc_arsize, vc_arprot, fb_awsize, fb_awprot, fb_arsize, fb_arprot;
    wire [1:0]  vc_awburst, vc_awlock, vc_bresp, vc_arburst, vc_arlock, vc_rresp;
    wire [1:0]  fb_awburst, fb_awlock, fb_bresp, fb_arburst, fb_arlock, fb_rresp;
    wire        vc_awvalid, vc_awready, vc_wlast, vc_wvalid, vc_wready, vc_bvalid, vc_bready;
    wire        vc_arvalid, vc_arready, vc_rlast, vc_rvalid, vc_rready;
    wire        fb_awvalid, fb_awready, fb_wlast, fb_wvalid, fb_wready, fb_bvalid, fb_bready;
    wire        fb_arvalid, fb_arready, fb_rlast, fb_rvalid, fb_rready;
    wire        v99_disp;              // R#8 bit 7 del V9990 (clk_86): conmutacion automatica de la HDMI
    wire [63:0] v99_win;               // V9991: R#55..R#62 del V9990 (la ventana del V9968), clk_86
    assign v68_aresetn = rst86a_s[1];
`ifdef TR_SIN_V9990
    // perfil TR: ni chip ni VRAM en la DDR. Leer 60h-6Fh devuelve FFh salvo P#5 (estado), que devuelve FEh: bit 0 (CE) = 0. El menu de A (v9991.asm,
    // teclas V y B) pinta el escritorio del V9990 y ESPERA CE = 0 tras cada LMMV (v9k_fill: bucle sin tope): con el bus flotante (bit 0 = 1) se colgaria.
    assign v99_dout = (bus_addr[3:0] == 4'd5) ? 8'hFE : 8'hFF;
    assign v99_wait86_n = 1'b1;  assign v99_int_n = 1'b1;
    assign v99_de = 1'b0;  assign v99_disp = 1'b0;  assign v99_hs = 1'b0;  assign v99_vs = 1'b0;
    assign v99_r = 5'd0;  assign v99_g = 5'd0;  assign v99_b = 5'd0;
    assign v99_ys = 1'b0;  assign v99_dclk_en = 1'b0;  assign v99_reso = 3'd0;  assign v99_il = 1'b0;  assign v99_eo = 1'b0;
    assign v99_win = 64'd0;
    assign v99_dbg_reads = 32'd0;  assign v99_dbg_miss = 32'd0;  assign v99_dbg_stall = 32'd0;  assign v99_dbg_writes = 32'd0;  assign v99_stalled = 1'b0;
`else
    v9990_zynq #(.VRAM_BASE(32'h1030_0000)) u_v9990 (
        .clk_86(clk_86), .rst_n(rst86_n), .aresetn(rst86a_s[1]),
        .csw_n(v99_csw_r_n), .csr_n(v99_csr_r_n), .mode(v99_mode_r), .cdo(v99_cdo_r),
        .cdi(v99_dout), .wait_n(v99_wait86_n), .int_n(v99_int_n),
        .v_de(v99_de), .v_disp(v99_disp), .v_hs(v99_hs), .v_vs(v99_vs), .v_r(v99_r), .v_g(v99_g), .v_b(v99_b),
        .v_ys(v99_ys), .v_dclk_en(v99_dclk_en), .v_reso(v99_reso), .v_il(v99_il), .v_eo(v99_eo),
        .v_win(v99_win),
        .dbg_reads(v99_dbg_reads), .dbg_miss(v99_dbg_miss), .dbg_stall(v99_dbg_stall),
        .dbg_writes(v99_dbg_writes), .dbg_stalled(v99_stalled),
        .M_AWID(vc_awid), .M_AWADDR(vc_awaddr), .M_AWLEN(vc_awlen), .M_AWSIZE(vc_awsize),
        .M_AWBURST(vc_awburst), .M_AWLOCK(vc_awlock), .M_AWCACHE(vc_awcache), .M_AWPROT(vc_awprot),
        .M_AWQOS(vc_awqos), .M_AWVALID(vc_awvalid), .M_AWREADY(vc_awready),
        .M_WID(vc_wid), .M_WDATA(vc_wdata), .M_WSTRB(vc_wstrb), .M_WLAST(vc_wlast),
        .M_WVALID(vc_wvalid), .M_WREADY(vc_wready),
        .M_BID(vc_bid), .M_BRESP(vc_bresp), .M_BVALID(vc_bvalid), .M_BREADY(vc_bready),
        .M_ARID(vc_arid), .M_ARADDR(vc_araddr), .M_ARLEN(vc_arlen), .M_ARSIZE(vc_arsize),
        .M_ARBURST(vc_arburst), .M_ARLOCK(vc_arlock), .M_ARCACHE(vc_arcache), .M_ARPROT(vc_arprot),
        .M_ARQOS(vc_arqos), .M_ARVALID(vc_arvalid), .M_ARREADY(vc_arready),
        .M_RID(vc_rid), .M_RDATA(vc_rdata), .M_RRESP(vc_rresp), .M_RLAST(vc_rlast),
        .M_RVALID(vc_rvalid), .M_RREADY(vc_rready)
    );
`endif
    wire        b_skip_en;                 // el rectangulo del frame buffer del V9990 que se queda para la imagen de B (solo Dual; si no, todo a 0)
    wire [9:0]  b_skip_y0, b_skip_y1, b_skip_wx0, b_skip_wx1;
    wire        b_skip_odd;                // posicion fina: el rectangulo empieza en un punto impar (solo Dual; si no, 0)
`ifdef ENABLE_DUAL
    // ========================================================================
    // PERFIL DUAL: la MAQUINA B (fpga/zynq/msx_b.v): otro MSX2+ entero (Z80, V9968 con su cache de VRAM, PSG, PPI, mapper, cartucho, RTC)
    // cuya imagen entra como un RECTANGULO en el frame buffer del V9990 (bwin_fb, por el S_AXI_GP0, que deja libre el OPL4 quitado): el
    // escritor del V9990 se salta ese rectangulo (msx2hdmi_v9990 con SKIP_RECT) y el escritorio que pinta el ARM, la ventana de A (gestor de
    // ventanas) y el compositor son los de siempre.
    // Palabra de control de B: MBOX V9_BASE+4 (0x1FFB0004; la mitad alta del beat de control del V9990, que el companion no toca).
    // La DDR arranca con basura: solo vale con la clave D0A1h en [31:16] (si no, B sigue parada y todo a cero).
    //   [0] B corre (a 0: reset)                                          [1] hay cartucho en el slot 1
    //   [2] el teclado va a B (si no, la tecla Insert alterna A/B)        [4:3] mapper del cartucho: 0 Konami4, 1 ASCII8, 2 SCC, 3 ASCII16
    //   [5] cartucho lineal desde 0000h                                   [6] 1 = sin rectangulo de B en el escritorio (el V9990 pinta todo)
    //   [11:8] columna del rectangulo: 0 = 192, n = 32 x n                [15:12] fila: 0 = 188, n = 12 x n   (256 x 212 puntos del frame buffer)
    //   [7] POSICION FINA (2/11/2026): la posicion sale de la segunda palabra (V9_BASE+8, b_ctl2) y [11:8]/[15:12] no cuentan:
    //       b_ctl2[9:0] = columna (punto cualquiera, <= 896), [18:10] = fila (<= 268), [20] y [21] = peticion de foco del ARM (cada cambio de [20]
    //       fija el foco del teclado: [21] = 1 B, 0 A; el flip-flop del Insert sigue alternando), solo con [7] = 1 (la DDR arranca con basura)
    // ========================================================================
    wire [31:0] b_ctl_raw;
    wire [31:0] b_ctl2_raw;
    wire        b_valid = (b_ctl_raw[31:16] == 16'hD0A1);
    wire [31:0] b_ctl   = b_valid ? b_ctl_raw : 32'd0;
    wire        b_running;
    wire [31:0] b_tel_a, b_tel_b;
    wire signed [16:0] b_psg_ac;
    wire [127:0] kbd_b;
    wire        b_vid_ce, b_vid_hs, b_vid_vs, b_vid_de;
    wire [4:0]  b_vid_r, b_vid_g, b_vid_b;
    wire [5:0] bm0_awid;
    wire [31:0] bm0_awaddr;
    wire [3:0] bm0_awlen;
    wire [2:0] bm0_awsize;
    wire [1:0] bm0_awburst;
    wire [1:0] bm0_awlock;
    wire [3:0] bm0_awcache;
    wire [2:0] bm0_awprot;
    wire [3:0] bm0_awqos;
    wire        bm0_awvalid;
    wire        bm0_awready;
    wire [5:0] bm0_wid;
    wire [63:0] bm0_wdata;
    wire [7:0] bm0_wstrb;
    wire        bm0_wlast;
    wire        bm0_wvalid;
    wire        bm0_wready;
    wire [5:0] bm0_bid;
    wire [1:0] bm0_bresp;
    wire        bm0_bvalid;
    wire        bm0_bready;
    wire [5:0] bm0_arid;
    wire [31:0] bm0_araddr;
    wire [3:0] bm0_arlen;
    wire [2:0] bm0_arsize;
    wire [1:0] bm0_arburst;
    wire [1:0] bm0_arlock;
    wire [3:0] bm0_arcache;
    wire [2:0] bm0_arprot;
    wire [3:0] bm0_arqos;
    wire        bm0_arvalid;
    wire        bm0_arready;
    wire [5:0] bm0_rid;
    wire [63:0] bm0_rdata;
    wire [1:0] bm0_rresp;
    wire        bm0_rlast;
    wire        bm0_rvalid;
    wire        bm0_rready;
    wire [5:0] bm2_awid;
    wire [31:0] bm2_awaddr;
    wire [3:0] bm2_awlen;
    wire [2:0] bm2_awsize;
    wire [1:0] bm2_awburst;
    wire [1:0] bm2_awlock;
    wire [3:0] bm2_awcache;
    wire [2:0] bm2_awprot;
    wire [3:0] bm2_awqos;
    wire        bm2_awvalid;
    wire        bm2_awready;
    wire [5:0] bm2_wid;
    wire [63:0] bm2_wdata;
    wire [7:0] bm2_wstrb;
    wire        bm2_wlast;
    wire        bm2_wvalid;
    wire        bm2_wready;
    wire [5:0] bm2_bid;
    wire [1:0] bm2_bresp;
    wire        bm2_bvalid;
    wire        bm2_bready;
    wire [5:0] bm2_arid;
    wire [31:0] bm2_araddr;
    wire [3:0] bm2_arlen;
    wire [2:0] bm2_arsize;
    wire [1:0] bm2_arburst;
    wire [1:0] bm2_arlock;
    wire [3:0] bm2_arcache;
    wire [2:0] bm2_arprot;
    wire [3:0] bm2_arqos;
    wire        bm2_arvalid;
    wire        bm2_arready;
    wire [5:0] bm2_rid;
    wire [63:0] bm2_rdata;
    wire [1:0] bm2_rresp;
    wire        bm2_rlast;
    wire        bm2_rvalid;
    wire        bm2_rready;
    wire [5:0] hs0_awid;
    wire [31:0] hs0_awaddr;
    wire [3:0] hs0_awlen;
    wire [2:0] hs0_awsize;
    wire [1:0] hs0_awburst;
    wire [1:0] hs0_awlock;
    wire [3:0] hs0_awcache;
    wire [2:0] hs0_awprot;
    wire [3:0] hs0_awqos;
    wire        hs0_awvalid;
    wire        hs0_awready;
    wire [5:0] hs0_wid;
    wire [63:0] hs0_wdata;
    wire [7:0] hs0_wstrb;
    wire        hs0_wlast;
    wire        hs0_wvalid;
    wire        hs0_wready;
    wire [5:0] hs0_bid;
    wire [1:0] hs0_bresp;
    wire        hs0_bvalid;
    wire        hs0_bready;
    wire [5:0] hs0_arid;
    wire [31:0] hs0_araddr;
    wire [3:0] hs0_arlen;
    wire [2:0] hs0_arsize;
    wire [1:0] hs0_arburst;
    wire [1:0] hs0_arlock;
    wire [3:0] hs0_arcache;
    wire [2:0] hs0_arprot;
    wire [3:0] hs0_arqos;
    wire        hs0_arvalid;
    wire        hs0_arready;
    wire [5:0] hs0_rid;
    wire [63:0] hs0_rdata;
    wire [1:0] hs0_rresp;
    wire        hs0_rlast;
    wire        hs0_rvalid;
    wire        hs0_rready;
    wire [5:0] hs2_awid;
    wire [31:0] hs2_awaddr;
    wire [3:0] hs2_awlen;
    wire [2:0] hs2_awsize;
    wire [1:0] hs2_awburst;
    wire [1:0] hs2_awlock;
    wire [3:0] hs2_awcache;
    wire [2:0] hs2_awprot;
    wire [3:0] hs2_awqos;
    wire        hs2_awvalid;
    wire        hs2_awready;
    wire [5:0] hs2_wid;
    wire [63:0] hs2_wdata;
    wire [7:0] hs2_wstrb;
    wire        hs2_wlast;
    wire        hs2_wvalid;
    wire        hs2_wready;
    wire [5:0] hs2_bid;
    wire [1:0] hs2_bresp;
    wire        hs2_bvalid;
    wire        hs2_bready;
    wire [5:0] hs2_arid;
    wire [31:0] hs2_araddr;
    wire [3:0] hs2_arlen;
    wire [2:0] hs2_arsize;
    wire [1:0] hs2_arburst;
    wire [1:0] hs2_arlock;
    wire [3:0] hs2_arcache;
    wire [2:0] hs2_arprot;
    wire [3:0] hs2_arqos;
    wire        hs2_arvalid;
    wire        hs2_arready;
    wire [5:0] hs2_rid;
    wire [63:0] hs2_rdata;
    wire [1:0] hs2_rresp;
    wire        hs2_rlast;
    wire        hs2_rvalid;
    wire        hs2_rready;
    reg  [1:0] dual_rst54_s = 2'b00;
    always @(posedge clk_54m) dual_rst54_s <= {dual_rst54_s[0], frst0_n};
    msx_b #(.RAM_BASE(32'h0C00_0000), .EXT_BASE(32'h1080_0000), .VRAM_BASE(32'h1000_0000), .VRAM_OFF(22'h380000), .LINES_LOG(8)) u_msxb (
        .clk_54m(clk_54m), .clk_27m(clk_27m), .clk_86(clk_86), .fclk0(fclk0),
        .fclk_aresetn(rst150_s[1]), .rst54_n(dual_rst54_s[1]), .sys_rst_n(bus_reset_n), .pll86_lock(pll86_lock),
        .run(b_ctl[0]), .cart_en(b_ctl[1]), .map_sel(b_ctl[4:3]), .map_linear(b_ctl[5]),
        .cen_3m6_54(clk_enable_3m6_54), .cfall_3m6_54(clk_falling_3m6_54), .cen_3m6_27(clk_enable_3m6_27),
        .keyboard(kbd_b), .ce86(ce86),
        .vid_ce(b_vid_ce), .vid_r(b_vid_r), .vid_g(b_vid_g), .vid_b(b_vid_b), .vid_hs(b_vid_hs), .vid_vs(b_vid_vs), .vid_de(b_vid_de),
        .psg_ac(b_psg_ac), .running(b_running), .tel_a(b_tel_a), .tel_b(b_tel_b),
        .M2_AWID(bm2_awid),
        .M2_AWADDR(bm2_awaddr),
        .M2_AWLEN(bm2_awlen),
        .M2_AWSIZE(bm2_awsize),
        .M2_AWBURST(bm2_awburst),
        .M2_AWLOCK(bm2_awlock),
        .M2_AWCACHE(bm2_awcache),
        .M2_AWPROT(bm2_awprot),
        .M2_AWQOS(bm2_awqos),
        .M2_AWVALID(bm2_awvalid),
        .M2_AWREADY(bm2_awready),
        .M2_WID(bm2_wid),
        .M2_WDATA(bm2_wdata),
        .M2_WSTRB(bm2_wstrb),
        .M2_WLAST(bm2_wlast),
        .M2_WVALID(bm2_wvalid),
        .M2_WREADY(bm2_wready),
        .M2_BID(bm2_bid),
        .M2_BRESP(bm2_bresp),
        .M2_BVALID(bm2_bvalid),
        .M2_BREADY(bm2_bready),
        .M2_ARID(bm2_arid),
        .M2_ARADDR(bm2_araddr),
        .M2_ARLEN(bm2_arlen),
        .M2_ARSIZE(bm2_arsize),
        .M2_ARBURST(bm2_arburst),
        .M2_ARLOCK(bm2_arlock),
        .M2_ARCACHE(bm2_arcache),
        .M2_ARPROT(bm2_arprot),
        .M2_ARQOS(bm2_arqos),
        .M2_ARVALID(bm2_arvalid),
        .M2_ARREADY(bm2_arready),
        .M2_RID(bm2_rid),
        .M2_RDATA(bm2_rdata),
        .M2_RRESP(bm2_rresp),
        .M2_RLAST(bm2_rlast),
        .M2_RVALID(bm2_rvalid),
        .M2_RREADY(bm2_rready),
        .M0_AWID(bm0_awid),
        .M0_AWADDR(bm0_awaddr),
        .M0_AWLEN(bm0_awlen),
        .M0_AWSIZE(bm0_awsize),
        .M0_AWBURST(bm0_awburst),
        .M0_AWLOCK(bm0_awlock),
        .M0_AWCACHE(bm0_awcache),
        .M0_AWPROT(bm0_awprot),
        .M0_AWQOS(bm0_awqos),
        .M0_AWVALID(bm0_awvalid),
        .M0_AWREADY(bm0_awready),
        .M0_WID(bm0_wid),
        .M0_WDATA(bm0_wdata),
        .M0_WSTRB(bm0_wstrb),
        .M0_WLAST(bm0_wlast),
        .M0_WVALID(bm0_wvalid),
        .M0_WREADY(bm0_wready),
        .M0_BID(bm0_bid),
        .M0_BRESP(bm0_bresp),
        .M0_BVALID(bm0_bvalid),
        .M0_BREADY(bm0_bready),
        .M0_ARID(bm0_arid),
        .M0_ARADDR(bm0_araddr),
        .M0_ARLEN(bm0_arlen),
        .M0_ARSIZE(bm0_arsize),
        .M0_ARBURST(bm0_arburst),
        .M0_ARLOCK(bm0_arlock),
        .M0_ARCACHE(bm0_arcache),
        .M0_ARPROT(bm0_arprot),
        .M0_ARQOS(bm0_arqos),
        .M0_ARVALID(bm0_arvalid),
        .M0_ARREADY(bm0_arready),
        .M0_RID(bm0_rid),
        .M0_RDATA(bm0_rdata),
        .M0_RRESP(bm0_rresp),
        .M0_RLAST(bm0_rlast),
        .M0_RVALID(bm0_rvalid),
        .M0_RREADY(bm0_rready)
    );
    // HP0 (fclk0): la VRAM de A (a_) y la de B (b_); HP2 (clk_54m): el buzon (a_) y la RAM de B (b_). Los esclavos hs0/hs2 van al PS7.
    axi_arb2w #(.DW(64), .ID_BIT(5), .W_TMO(2048)) u_hp0_arb (
        .clk(fclk0), .aresetn(rst150_s[1]),
        .a_awid(hp0_awid),
        .a_awaddr(hp0_awaddr),
        .a_awlen(hp0_awlen),
        .a_awsize(hp0_awsize),
        .a_awburst(hp0_awburst),
        .a_awlock(hp0_awlock),
        .a_awcache(hp0_awcache),
        .a_awprot(hp0_awprot),
        .a_awqos(hp0_awqos),
        .a_awvalid(hp0_awvalid),
        .a_awready(hp0_awready),
        .a_wid(hp0_wid),
        .a_wdata(hp0_wdata),
        .a_wstrb(hp0_wstrb),
        .a_wlast(hp0_wlast),
        .a_wvalid(hp0_wvalid),
        .a_wready(hp0_wready),
        .a_bid(hp0_bid),
        .a_bresp(hp0_bresp),
        .a_bvalid(hp0_bvalid),
        .a_bready(hp0_bready),
        .a_arid(hp0_arid),
        .a_araddr(hp0_araddr),
        .a_arlen(hp0_arlen),
        .a_arsize(hp0_arsize),
        .a_arburst(hp0_arburst),
        .a_arlock(hp0_arlock),
        .a_arcache(hp0_arcache),
        .a_arprot(hp0_arprot),
        .a_arqos(hp0_arqos),
        .a_arvalid(hp0_arvalid),
        .a_arready(hp0_arready),
        .a_rid(hp0_rid),
        .a_rdata(hp0_rdata),
        .a_rresp(hp0_rresp),
        .a_rlast(hp0_rlast),
        .a_rvalid(hp0_rvalid),
        .a_rready(hp0_rready),
        .b_awid(bm0_awid),
        .b_awaddr(bm0_awaddr),
        .b_awlen(bm0_awlen),
        .b_awsize(bm0_awsize),
        .b_awburst(bm0_awburst),
        .b_awlock(bm0_awlock),
        .b_awcache(bm0_awcache),
        .b_awprot(bm0_awprot),
        .b_awqos(bm0_awqos),
        .b_awvalid(bm0_awvalid),
        .b_awready(bm0_awready),
        .b_wid(bm0_wid),
        .b_wdata(bm0_wdata),
        .b_wstrb(bm0_wstrb),
        .b_wlast(bm0_wlast),
        .b_wvalid(bm0_wvalid),
        .b_wready(bm0_wready),
        .b_bid(bm0_bid),
        .b_bresp(bm0_bresp),
        .b_bvalid(bm0_bvalid),
        .b_bready(bm0_bready),
        .b_arid(bm0_arid),
        .b_araddr(bm0_araddr),
        .b_arlen(bm0_arlen),
        .b_arsize(bm0_arsize),
        .b_arburst(bm0_arburst),
        .b_arlock(bm0_arlock),
        .b_arcache(bm0_arcache),
        .b_arprot(bm0_arprot),
        .b_arqos(bm0_arqos),
        .b_arvalid(bm0_arvalid),
        .b_arready(bm0_arready),
        .b_rid(bm0_rid),
        .b_rdata(bm0_rdata),
        .b_rresp(bm0_rresp),
        .b_rlast(bm0_rlast),
        .b_rvalid(bm0_rvalid),
        .b_rready(bm0_rready),
        .s_awid(hs0_awid),
        .s_awaddr(hs0_awaddr),
        .s_awlen(hs0_awlen),
        .s_awsize(hs0_awsize),
        .s_awburst(hs0_awburst),
        .s_awlock(hs0_awlock),
        .s_awcache(hs0_awcache),
        .s_awprot(hs0_awprot),
        .s_awqos(hs0_awqos),
        .s_awvalid(hs0_awvalid),
        .s_awready(hs0_awready),
        .s_wid(hs0_wid),
        .s_wdata(hs0_wdata),
        .s_wstrb(hs0_wstrb),
        .s_wlast(hs0_wlast),
        .s_wvalid(hs0_wvalid),
        .s_wready(hs0_wready),
        .s_bid(hs0_bid),
        .s_bresp(hs0_bresp),
        .s_bvalid(hs0_bvalid),
        .s_bready(hs0_bready),
        .s_arid(hs0_arid),
        .s_araddr(hs0_araddr),
        .s_arlen(hs0_arlen),
        .s_arsize(hs0_arsize),
        .s_arburst(hs0_arburst),
        .s_arlock(hs0_arlock),
        .s_arcache(hs0_arcache),
        .s_arprot(hs0_arprot),
        .s_arqos(hs0_arqos),
        .s_arvalid(hs0_arvalid),
        .s_arready(hs0_arready),
        .s_rid(hs0_rid),
        .s_rdata(hs0_rdata),
        .s_rresp(hs0_rresp),
        .s_rlast(hs0_rlast),
        .s_rvalid(hs0_rvalid),
        .s_rready(hs0_rready)
    );
    axi_arb2w #(.DW(64), .ID_BIT(5), .W_TMO(2048)) u_hp2_arb (
        .clk(clk_54m), .aresetn(dual_rst54_s[1]),
        .a_awid(hp2_awid),
        .a_awaddr(hp2_awaddr),
        .a_awlen(hp2_awlen),
        .a_awsize(hp2_awsize),
        .a_awburst(hp2_awburst),
        .a_awlock(hp2_awlock),
        .a_awcache(hp2_awcache),
        .a_awprot(hp2_awprot),
        .a_awqos(hp2_awqos),
        .a_awvalid(hp2_awvalid),
        .a_awready(hp2_awready),
        .a_wid(hp2_wid),
        .a_wdata(hp2_wdata),
        .a_wstrb(hp2_wstrb),
        .a_wlast(hp2_wlast),
        .a_wvalid(hp2_wvalid),
        .a_wready(hp2_wready),
        .a_bid(hp2_bid),
        .a_bresp(hp2_bresp),
        .a_bvalid(hp2_bvalid),
        .a_bready(hp2_bready),
        .a_arid(hp2_arid),
        .a_araddr(hp2_araddr),
        .a_arlen(hp2_arlen),
        .a_arsize(hp2_arsize),
        .a_arburst(hp2_arburst),
        .a_arlock(hp2_arlock),
        .a_arcache(hp2_arcache),
        .a_arprot(hp2_arprot),
        .a_arqos(hp2_arqos),
        .a_arvalid(hp2_arvalid),
        .a_arready(hp2_arready),
        .a_rid(hp2_rid),
        .a_rdata(hp2_rdata),
        .a_rresp(hp2_rresp),
        .a_rlast(hp2_rlast),
        .a_rvalid(hp2_rvalid),
        .a_rready(hp2_rready),
        .b_awid(bm2_awid),
        .b_awaddr(bm2_awaddr),
        .b_awlen(bm2_awlen),
        .b_awsize(bm2_awsize),
        .b_awburst(bm2_awburst),
        .b_awlock(bm2_awlock),
        .b_awcache(bm2_awcache),
        .b_awprot(bm2_awprot),
        .b_awqos(bm2_awqos),
        .b_awvalid(bm2_awvalid),
        .b_awready(bm2_awready),
        .b_wid(bm2_wid),
        .b_wdata(bm2_wdata),
        .b_wstrb(bm2_wstrb),
        .b_wlast(bm2_wlast),
        .b_wvalid(bm2_wvalid),
        .b_wready(bm2_wready),
        .b_bid(bm2_bid),
        .b_bresp(bm2_bresp),
        .b_bvalid(bm2_bvalid),
        .b_bready(bm2_bready),
        .b_arid(bm2_arid),
        .b_araddr(bm2_araddr),
        .b_arlen(bm2_arlen),
        .b_arsize(bm2_arsize),
        .b_arburst(bm2_arburst),
        .b_arlock(bm2_arlock),
        .b_arcache(bm2_arcache),
        .b_arprot(bm2_arprot),
        .b_arqos(bm2_arqos),
        .b_arvalid(bm2_arvalid),
        .b_arready(bm2_arready),
        .b_rid(bm2_rid),
        .b_rdata(bm2_rdata),
        .b_rresp(bm2_rresp),
        .b_rlast(bm2_rlast),
        .b_rvalid(bm2_rvalid),
        .b_rready(bm2_rready),
        .s_awid(hs2_awid),
        .s_awaddr(hs2_awaddr),
        .s_awlen(hs2_awlen),
        .s_awsize(hs2_awsize),
        .s_awburst(hs2_awburst),
        .s_awlock(hs2_awlock),
        .s_awcache(hs2_awcache),
        .s_awprot(hs2_awprot),
        .s_awqos(hs2_awqos),
        .s_awvalid(hs2_awvalid),
        .s_awready(hs2_awready),
        .s_wid(hs2_wid),
        .s_wdata(hs2_wdata),
        .s_wstrb(hs2_wstrb),
        .s_wlast(hs2_wlast),
        .s_wvalid(hs2_wvalid),
        .s_wready(hs2_wready),
        .s_bid(hs2_bid),
        .s_bresp(hs2_bresp),
        .s_bvalid(hs2_bvalid),
        .s_bready(hs2_bready),
        .s_arid(hs2_arid),
        .s_araddr(hs2_araddr),
        .s_arlen(hs2_arlen),
        .s_arsize(hs2_arsize),
        .s_arburst(hs2_arburst),
        .s_arlock(hs2_arlock),
        .s_arcache(hs2_arcache),
        .s_arprot(hs2_arprot),
        .s_arqos(hs2_arqos),
        .s_arvalid(hs2_arvalid),
        .s_arready(hs2_arready),
        .s_rid(hs2_rid),
        .s_rdata(hs2_rdata),
        .s_rresp(hs2_rresp),
        .s_rlast(hs2_rlast),
        .s_rvalid(hs2_rvalid),
        .s_rready(hs2_rready)
    );
    // el rectangulo de B en el frame buffer del V9990 (msx2hdmi_v9990 SKIP_RECT + bwin_fb): 256 x 212 puntos; la columna en multiplos de 32
    wire        b_fine = b_ctl[7];                                  // posicion fina (b_ctl solo vale con la clave: b_ctl[7] = 0 si no)
    wire [9:0]  b_fx_raw = b_ctl2_raw[9:0];
    wire [8:0]  b_fy_raw = b_ctl2_raw[18:10];
    wire [10:0] b_x0 = b_fine ? ((b_fx_raw > 10'd896) ? 11'd896 : {1'b0, b_fx_raw})
                              : ((b_ctl[11:8] == 4'd0) ? 11'd192 : {2'b00, b_ctl[11:8], 5'b00000});
    wire [9:0]  b_y0 = b_fine ? ((b_fy_raw > 9'd268) ? 10'd268 : {1'b0, b_fy_raw})
                              : ((b_ctl[15:12] == 4'd0) ? 10'd188 : (({6'd0, b_ctl[15:12]} << 3) + ({6'd0, b_ctl[15:12]} << 2)));
    wire        b_win_en = b_running & ~b_ctl[6];
    assign b_skip_en = b_win_en;
    assign b_skip_y0 = b_y0;
    assign b_skip_y1 = b_y0 + 10'd212;
    assign b_skip_wx0 = b_x0[10:1] + {9'd0, b_x0[0]};                   // primera palabra ENTERA de B (con x0 impar la anterior es compartida)
    assign b_skip_wx1 = b_x0[10:1] + 10'd128;                           // y la siguiente a la ultima entera (con x0 impar esa es la compartida)
    assign b_skip_odd = b_x0[0];
    // teclado: con el foco en B (la tecla Insert, o B_CTL[2]) lo ve solo B; si no, solo A (Pausa sigue siendo el selector V9968/V9990)
    reg  [2:0]  b_key_s = 3'b000;
    reg  [20:0] b_key_lock = 21'd0;
    reg         b_focus_k = 1'b0;
    reg         b_freq_seen = 1'b0;                                // peticion de foco del ARM (b_ctl2[20], cada cambio es una peticion): la ultima vista
    always @(posedge clk_54m) begin
        b_key_s <= {b_key_s[1:0], keyboard[73]};          // Insert (HID 0x49)
        if (b_key_lock != 21'd0) b_key_lock <= b_key_lock - 21'd1;
        else if (b_key_s[1] & ~b_key_s[2]) begin b_focus_k <= ~b_focus_k; b_key_lock <= 21'h1FFFFF; end
        if (!b_fine) b_freq_seen <= b_ctl2_raw[20];             // sin la posicion fina la palabra es basura: solo se sigue
        else if (b_ctl2_raw[20] != b_freq_seen) begin b_freq_seen <= b_ctl2_raw[20]; b_focus_k <= b_ctl2_raw[21]; end
        if (~b_running) b_focus_k <= 1'b0;
    end
    wire        b_focus = b_running & (b_focus_k | b_ctl[2]);
    // SILENCIO POR MAQUINA (Z1.3.2b8): b_ctl2[22] / [23] = peticion / valor del silencio de A, [24] / [25] = lo mismo para B (dual_mute.v); se quitan
    // solos con B parada. Silencio de B = el PSG de B fuera de la suma del PSG; silencio de A = el PSG de A, el SCC, el OPLL, el Y8950, el
    // WaveGame y el monitor de la cinta fuera (sus atenuadores del mezclador a 0, o las puertas en la suma). El estado real va en la telemetria.
    wire        a_mute_s, b_mute_s;
    dual_mute u_mute (.clk_54m(clk_54m), .clk_27m(clk_27m), .fine(b_fine), .running(b_running), .req(b_ctl2_raw[25:22]),
                      .a_mute(a_mute_s), .b_mute(b_mute_s), .a_mute_27(a_mute_27), .b_mute_27(b_mute_27));
    assign kbd_b = b_focus ? keyboard : 128'd0;
    wire [127:0] kbd_a = b_focus ? 128'd0 : keyboard;
    // la imagen de B al frame buffer del V9990: S_AXI_GP0 (32 bits, a clk_86) sin el OPL4. wslot_o = el slot que esta escribiendo el V9990
    wire [1:0]  b_wslot;
    wire [15:0] b_win_lines;
    bwin_fb #(.FB_BASE(32'h1040_0000), .SLOT_SIZE(32'h0011_0000), .STRIDE(32'd2304), .AWID(6'd10)) u_bwin (
        .clk(clk_86), .resetn(rst86_n), .aresetn(rst86a_s[1]),
        .ce(b_vid_ce), .r(b_vid_r), .g(b_vid_g), .b(b_vid_b), .hs(b_vid_hs), .vs(b_vid_vs), .de(b_vid_de),
        .en(b_win_en), .x0(b_x0), .y0(b_y0), .w_slot(b_wslot),
        .M_AWID(gp0_awid), .M_AWADDR(gp0_awaddr), .M_AWLEN(gp0_awlen), .M_AWSIZE(gp0_awsize),
        .M_AWBURST(gp0_awburst), .M_AWLOCK(gp0_awlock), .M_AWCACHE(gp0_awcache), .M_AWPROT(gp0_awprot),
        .M_AWQOS(gp0_awqos), .M_AWVALID(gp0_awvalid), .M_AWREADY(gp0_awready),
        .M_WID(gp0_wid), .M_WDATA(gp0_wdata), .M_WSTRB(gp0_wstrb), .M_WLAST(gp0_wlast),
        .M_WVALID(gp0_wvalid), .M_WREADY(gp0_wready),
        .M_BID(gp0_bid), .M_BRESP(gp0_bresp), .M_BVALID(gp0_bvalid), .M_BREADY(gp0_bready),
        .M_ARID(gp0_arid), .M_ARADDR(gp0_araddr), .M_ARLEN(gp0_arlen), .M_ARSIZE(gp0_arsize),
        .M_ARBURST(gp0_arburst), .M_ARLOCK(gp0_arlock), .M_ARCACHE(gp0_arcache), .M_ARPROT(gp0_arprot),
        .M_ARQOS(gp0_arqos), .M_ARVALID(gp0_arvalid), .M_ARREADY(gp0_arready),
        .M_RID(gp0_rid), .M_RDATA(gp0_rdata), .M_RRESP(gp0_rresp), .M_RLAST(gp0_rlast),
        .M_RVALID(gp0_rvalid), .M_RREADY(gp0_rready),
        .dbg_lines(b_win_lines));
`else
    assign b_skip_en = 1'b0;
    assign b_skip_y0 = 10'd0;
    assign b_skip_y1 = 10'd0;
    assign b_skip_wx0 = 10'd0;
    assign b_skip_wx1 = 10'd0;
    assign b_skip_odd = 1'b0;
    wire [1:0] b_wslot;
`endif
    // V9991: arbitro INTERIOR de los dos frame buffers (A = el del V9990, IDs 2/3; B = el del V9968, IDs 6/7;
    // ruta por el bit 2 del ID). Su salida (fbm_*) es el maestro B del arbitro del GP1 (que ruta por el bit 1:
    // los dos frame buffers lo llevan a 1). El del V9968 solo trafica en el modo 2 (ventana).
    wire [5:0]  fbm_awid, fbm_wid, fbm_bid, fbm_arid, fbm_rid;
    wire [31:0] fbm_awaddr, fbm_wdata, fbm_araddr, fbm_rdata;
    wire [3:0]  fbm_awlen, fbm_wstrb, fbm_awcache, fbm_awqos, fbm_arlen, fbm_arcache, fbm_arqos;
    wire [2:0]  fbm_awsize, fbm_awprot, fbm_arsize, fbm_arprot;
    wire [1:0]  fbm_awburst, fbm_awlock, fbm_bresp, fbm_arburst, fbm_arlock, fbm_rresp;
    wire        fbm_awvalid, fbm_awready, fbm_wlast, fbm_wvalid, fbm_wready, fbm_bvalid, fbm_bready;
    wire        fbm_arvalid, fbm_arready, fbm_rlast, fbm_rvalid, fbm_rready;
`ifdef TR_SIN_V9990
    // perfil TR: el unico maestro del GP1 es el frame buffer del V9968 (modo 0, ventana de pantalla completa): sin arbitros
    assign gp1_awid = fb68_awid;  assign gp1_awaddr = fb68_awaddr;  assign gp1_awlen = fb68_awlen;  assign gp1_awsize = fb68_awsize;
    assign gp1_awburst = fb68_awburst;  assign gp1_awlock = fb68_awlock;  assign gp1_awcache = fb68_awcache;  assign gp1_awprot = fb68_awprot;
    assign gp1_awqos = fb68_awqos;  assign gp1_awvalid = fb68_awvalid;  assign fb68_awready = gp1_awready;
    assign gp1_wid = fb68_wid;  assign gp1_wdata = fb68_wdata;  assign gp1_wstrb = fb68_wstrb;  assign gp1_wlast = fb68_wlast;
    assign gp1_wvalid = fb68_wvalid;  assign fb68_wready = gp1_wready;
    assign fb68_bid = gp1_bid;  assign fb68_bresp = gp1_bresp;  assign fb68_bvalid = gp1_bvalid;  assign gp1_bready = fb68_bready;
    assign gp1_arid = fb68_arid;  assign gp1_araddr = fb68_araddr;  assign gp1_arlen = fb68_arlen;  assign gp1_arsize = fb68_arsize;
    assign gp1_arburst = fb68_arburst;  assign gp1_arlock = fb68_arlock;  assign gp1_arcache = fb68_arcache;  assign gp1_arprot = fb68_arprot;
    assign gp1_arqos = fb68_arqos;  assign gp1_arvalid = fb68_arvalid;  assign fb68_arready = gp1_arready;
    assign fb68_rid = gp1_rid;  assign fb68_rdata = gp1_rdata;  assign fb68_rresp = gp1_rresp;  assign fb68_rlast = gp1_rlast;
    assign fb68_rvalid = gp1_rvalid;  assign gp1_rready = fb68_rready;
`else
    axi_arb2 #(.ID_BIT(2)) u_gp1_arb_fb (
        .clk(clk_86), .aresetn(rst86a_s[1]),
        .a_awid(fb_awid), .a_awaddr(fb_awaddr), .a_awlen(fb_awlen), .a_awsize(fb_awsize),
        .a_awburst(fb_awburst), .a_awlock(fb_awlock), .a_awcache(fb_awcache), .a_awprot(fb_awprot),
        .a_awqos(fb_awqos), .a_awvalid(fb_awvalid), .a_awready(fb_awready),
        .a_wid(fb_wid), .a_wdata(fb_wdata), .a_wstrb(fb_wstrb), .a_wlast(fb_wlast),
        .a_wvalid(fb_wvalid), .a_wready(fb_wready),
        .a_bid(fb_bid), .a_bresp(fb_bresp), .a_bvalid(fb_bvalid), .a_bready(fb_bready),
        .a_arid(fb_arid), .a_araddr(fb_araddr), .a_arlen(fb_arlen), .a_arsize(fb_arsize),
        .a_arburst(fb_arburst), .a_arlock(fb_arlock), .a_arcache(fb_arcache), .a_arprot(fb_arprot),
        .a_arqos(fb_arqos), .a_arvalid(fb_arvalid), .a_arready(fb_arready),
        .a_rid(fb_rid), .a_rdata(fb_rdata), .a_rresp(fb_rresp), .a_rlast(fb_rlast),
        .a_rvalid(fb_rvalid), .a_rready(fb_rready),
        .b_awid(fb68_awid), .b_awaddr(fb68_awaddr), .b_awlen(fb68_awlen), .b_awsize(fb68_awsize),
        .b_awburst(fb68_awburst), .b_awlock(fb68_awlock), .b_awcache(fb68_awcache), .b_awprot(fb68_awprot),
        .b_awqos(fb68_awqos), .b_awvalid(fb68_awvalid), .b_awready(fb68_awready),
        .b_wid(fb68_wid), .b_wdata(fb68_wdata), .b_wstrb(fb68_wstrb), .b_wlast(fb68_wlast),
        .b_wvalid(fb68_wvalid), .b_wready(fb68_wready),
        .b_bid(fb68_bid), .b_bresp(fb68_bresp), .b_bvalid(fb68_bvalid), .b_bready(fb68_bready),
        .b_arid(fb68_arid), .b_araddr(fb68_araddr), .b_arlen(fb68_arlen), .b_arsize(fb68_arsize),
        .b_arburst(fb68_arburst), .b_arlock(fb68_arlock), .b_arcache(fb68_arcache), .b_arprot(fb68_arprot),
        .b_arqos(fb68_arqos), .b_arvalid(fb68_arvalid), .b_arready(fb68_arready),
        .b_rid(fb68_rid), .b_rdata(fb68_rdata), .b_rresp(fb68_rresp), .b_rlast(fb68_rlast),
        .b_rvalid(fb68_rvalid), .b_rready(fb68_rready),
        .s_awid(fbm_awid), .s_awaddr(fbm_awaddr), .s_awlen(fbm_awlen), .s_awsize(fbm_awsize),
        .s_awburst(fbm_awburst), .s_awlock(fbm_awlock), .s_awcache(fbm_awcache), .s_awprot(fbm_awprot),
        .s_awqos(fbm_awqos), .s_awvalid(fbm_awvalid), .s_awready(fbm_awready),
        .s_wid(fbm_wid), .s_wdata(fbm_wdata), .s_wstrb(fbm_wstrb), .s_wlast(fbm_wlast),
        .s_wvalid(fbm_wvalid), .s_wready(fbm_wready),
        .s_bid(fbm_bid), .s_bresp(fbm_bresp), .s_bvalid(fbm_bvalid), .s_bready(fbm_bready),
        .s_arid(fbm_arid), .s_araddr(fbm_araddr), .s_arlen(fbm_arlen), .s_arsize(fbm_arsize),
        .s_arburst(fbm_arburst), .s_arlock(fbm_arlock), .s_arcache(fbm_arcache), .s_arprot(fbm_arprot),
        .s_arqos(fbm_arqos), .s_arvalid(fbm_arvalid), .s_arready(fbm_arready),
        .s_rid(fbm_rid), .s_rdata(fbm_rdata), .s_rresp(fbm_rresp), .s_rlast(fbm_rlast),
        .s_rvalid(fbm_rvalid), .s_rready(fbm_rready)
    );
    // arbitro del GP1: A = cliente de VRAM (prioridad, sus fallos paran el core), B = los dos frame buffers (fbm_*)
    axi_arb2 u_gp1_arb (
        .clk(clk_86), .aresetn(rst86a_s[1]),
        .a_awid(vc_awid),
        .a_awaddr(vc_awaddr),
        .a_awlen(vc_awlen),
        .a_awsize(vc_awsize),
        .a_awburst(vc_awburst),
        .a_awlock(vc_awlock),
        .a_awcache(vc_awcache),
        .a_awprot(vc_awprot),
        .a_awqos(vc_awqos),
        .a_awvalid(vc_awvalid),
        .a_awready(vc_awready),
        .a_wid(vc_wid),
        .a_wdata(vc_wdata),
        .a_wstrb(vc_wstrb),
        .a_wlast(vc_wlast),
        .a_wvalid(vc_wvalid),
        .a_wready(vc_wready),
        .a_bid(vc_bid),
        .a_bresp(vc_bresp),
        .a_bvalid(vc_bvalid),
        .a_bready(vc_bready),
        .a_arid(vc_arid),
        .a_araddr(vc_araddr),
        .a_arlen(vc_arlen),
        .a_arsize(vc_arsize),
        .a_arburst(vc_arburst),
        .a_arlock(vc_arlock),
        .a_arcache(vc_arcache),
        .a_arprot(vc_arprot),
        .a_arqos(vc_arqos),
        .a_arvalid(vc_arvalid),
        .a_arready(vc_arready),
        .a_rid(vc_rid),
        .a_rdata(vc_rdata),
        .a_rresp(vc_rresp),
        .a_rlast(vc_rlast),
        .a_rvalid(vc_rvalid),
        .a_rready(vc_rready),
        .b_awid(fbm_awid),
        .b_awaddr(fbm_awaddr),
        .b_awlen(fbm_awlen),
        .b_awsize(fbm_awsize),
        .b_awburst(fbm_awburst),
        .b_awlock(fbm_awlock),
        .b_awcache(fbm_awcache),
        .b_awprot(fbm_awprot),
        .b_awqos(fbm_awqos),
        .b_awvalid(fbm_awvalid),
        .b_awready(fbm_awready),
        .b_wid(fbm_wid),
        .b_wdata(fbm_wdata),
        .b_wstrb(fbm_wstrb),
        .b_wlast(fbm_wlast),
        .b_wvalid(fbm_wvalid),
        .b_wready(fbm_wready),
        .b_bid(fbm_bid),
        .b_bresp(fbm_bresp),
        .b_bvalid(fbm_bvalid),
        .b_bready(fbm_bready),
        .b_arid(fbm_arid),
        .b_araddr(fbm_araddr),
        .b_arlen(fbm_arlen),
        .b_arsize(fbm_arsize),
        .b_arburst(fbm_arburst),
        .b_arlock(fbm_arlock),
        .b_arcache(fbm_arcache),
        .b_arprot(fbm_arprot),
        .b_arqos(fbm_arqos),
        .b_arvalid(fbm_arvalid),
        .b_arready(fbm_arready),
        .b_rid(fbm_rid),
        .b_rdata(fbm_rdata),
        .b_rresp(fbm_rresp),
        .b_rlast(fbm_rlast),
        .b_rvalid(fbm_rvalid),
        .b_rready(fbm_rready),
        .s_awid(gp1_awid),
        .s_awaddr(gp1_awaddr),
        .s_awlen(gp1_awlen),
        .s_awsize(gp1_awsize),
        .s_awburst(gp1_awburst),
        .s_awlock(gp1_awlock),
        .s_awcache(gp1_awcache),
        .s_awprot(gp1_awprot),
        .s_awqos(gp1_awqos),
        .s_awvalid(gp1_awvalid),
        .s_awready(gp1_awready),
        .s_wid(gp1_wid),
        .s_wdata(gp1_wdata),
        .s_wstrb(gp1_wstrb),
        .s_wlast(gp1_wlast),
        .s_wvalid(gp1_wvalid),
        .s_wready(gp1_wready),
        .s_bid(gp1_bid),
        .s_bresp(gp1_bresp),
        .s_bvalid(gp1_bvalid),
        .s_bready(gp1_bready),
        .s_arid(gp1_arid),
        .s_araddr(gp1_araddr),
        .s_arlen(gp1_arlen),
        .s_arsize(gp1_arsize),
        .s_arburst(gp1_arburst),
        .s_arlock(gp1_arlock),
        .s_arcache(gp1_arcache),
        .s_arprot(gp1_arprot),
        .s_arqos(gp1_arqos),
        .s_arvalid(gp1_arvalid),
        .s_arready(gp1_arready),
        .s_rid(gp1_rid),
        .s_rdata(gp1_rdata),
        .s_rresp(gp1_rresp),
        .s_rlast(gp1_rlast),
        .s_rvalid(gp1_rvalid),
        .s_rready(gp1_rready)
    );
`endif

    // puente de video propio (ring + escalador por modo); V9991: SIN codificador, lee con el raster
    // del hdmi del V9968 (hd_cx/hd_cy) y entrega el pixel y su transparencia al compositor
    wire [29:0] v99_tmds;                // sin uso (EXT_TIMING)
    wire        v99_vblank;
    wire [8:0]  v99_ln_last;             // lineas capturadas al ring en el ultimo frame
    wire [21:0] v99_px_last;             // pixeles capturados en el ultimo frame
    wire [4:0]  v99_yank_drop;           // underrun del lector del frame buffer en el ultimo frame (esperado 0)
    wire [31:0] v99_dbg_rd;              // estado del lector del frame buffer (diagnostico B5, 29/10)
`ifdef TR_SIN_V9990
    // perfil TR: sin puente del V9990. Para el compositor es un V9990 siempre transparente y fuera de imagen (en el modo 0 ni se mira)
    assign c_rgb99 = 24'd0;  assign c_ys99 = 1'b1;  assign c_in99 = 1'b0;  assign c_reso99 = 3'd0;  assign c_il99 = 1'b0;
    assign v99_tmds = 30'd0;  assign v99_vblank = 1'b0;  assign v99_ln_last = 9'd0;  assign v99_px_last = 22'd0;
    assign v99_yank_drop = 5'd0;  assign v99_dbg_rd = 32'd0;
`else
`ifdef ENABLE_DUAL
    msx2hdmi_v9990 #(.EXT_TIMING(1), .SKIP_RECT(1)) u_msx2hdmi99 (   // Dual: el escritor del frame buffer se salta el rectangulo de B
`else
    msx2hdmi_v9990 #(.EXT_TIMING(1)) u_msx2hdmi99 (
`endif
        .clk(clk_86), .resetn(rst86_n), .aresetn(rst86a_s[1]), .ce(v99_dclk_en),
        .r(v99_r), .g(v99_g), .b(v99_b), .ys(v99_ys), .hs(v99_hs), .vs(v99_vs), .de(v99_de), .reso(v99_reso),
        .il(v99_il), .eo(v99_eo),
`ifdef ENABLE_CONFIG
        .scanlines(config_enable_scanlines),
`else
        .scanlines(1'b0),
`endif
        .audio_l(audio_sample), .audio_r(audio_sample_r),
        .clk_pixel(clk_hdmi), .clk_5x_pixel(clk_hdmi5),
        .ext_cx(hd_cx), .ext_cy(hd_cy),
        .skip_en(b_skip_en), .skip_y0(b_skip_y0), .skip_y1(b_skip_y1), .skip_wx0(b_skip_wx0), .skip_wx1(b_skip_wx1), .skip_odd(b_skip_odd), .wslot_o(b_wslot),
        .rgb_out_ext(c_rgb99), .ys_out(c_ys99), .in_out(c_in99), .reso_out(c_reso99), .il_out(c_il99),
        .tmds_out(v99_tmds), .vblank(v99_vblank),
        .dbg_lock_tgl(), .dbg_hdmi_rst(), .dbg_wr_act(),
        .dbg_lines(v99_ln_last), .dbg_pixels(v99_px_last),  // captura por frame (esperado 240 / 68160 en B1)
        .dbg_yank_drop(v99_yank_drop),                       // underrun del lector del frame buffer (esperado 0)
        .dbg_rd(v99_dbg_rd),
        .M_AWID(fb_awid),
        .M_AWADDR(fb_awaddr),
        .M_AWLEN(fb_awlen),
        .M_AWSIZE(fb_awsize),
        .M_AWBURST(fb_awburst),
        .M_AWLOCK(fb_awlock),
        .M_AWCACHE(fb_awcache),
        .M_AWPROT(fb_awprot),
        .M_AWQOS(fb_awqos),
        .M_AWVALID(fb_awvalid),
        .M_AWREADY(fb_awready),
        .M_WID(fb_wid),
        .M_WDATA(fb_wdata),
        .M_WSTRB(fb_wstrb),
        .M_WLAST(fb_wlast),
        .M_WVALID(fb_wvalid),
        .M_WREADY(fb_wready),
        .M_BID(fb_bid),
        .M_BRESP(fb_bresp),
        .M_BVALID(fb_bvalid),
        .M_BREADY(fb_bready),
        .M_ARID(fb_arid),
        .M_ARADDR(fb_araddr),
        .M_ARLEN(fb_arlen),
        .M_ARSIZE(fb_arsize),
        .M_ARBURST(fb_arburst),
        .M_ARLOCK(fb_arlock),
        .M_ARCACHE(fb_arcache),
        .M_ARPROT(fb_arprot),
        .M_ARQOS(fb_arqos),
        .M_ARVALID(fb_arvalid),
        .M_ARREADY(fb_arready),
        .M_RID(fb_rid),
        .M_RDATA(fb_rdata),
        .M_RRESP(fb_rresp),
        .M_RLAST(fb_rlast),
        .M_RVALID(fb_rvalid),
        .M_RREADY(fb_rready)
    );
`endif

    // selector: la tecla Pausa conmuta (flanco de pulsacion, con bloqueo de ~40 ms
    // contra rebotes/repeticion); KEY2 NO: es el reset del MSX. Desde el ARM (OSD /
    // tools/vsel.tcl): palabra +0x2C del buzon {seq[15:8], 4'b0, v9k[3], 0, auto_off[1], sel[0]};
    // cada cambio de seq impone sel (0 = V9968, 1 = V9990).
    // AUTOMATICO "DE IDA" (21/09 noche): cuando el programa enciende la pantalla del V9990
    // (R#8 bit 7, DISP) en un modo que el puente captura (B1-B4 y B7; en B5/B6 no: reso 4/5)
    // la HDMI pasa al V9990 y SE QUEDA: los apagados de pantalla de un juego (cambio de
    // fase, carga) muestran negro, como con un GFX9000 real. (Hasta el 28/10 cada conmutacion
    // costaba al monitor 1-2 s de reenganche porque eran dos flujos 720p sin fase comun; con
    // el compositor V9991 el cambio es un mux por pixel en el vblank del mismo raster, pero
    // se conserva la politica "de ida" por el negro de los apagados de pantalla.) La
    // version con vuelta al V9968 tras 2 s de apagado hacia DOS saltos por cada cambio de
    // pantalla (Albert, GNG). Vuelven al V9968: el reset del MSX (bus_reset_n, que ya
    // resetea el core a traves de rst86_n), la tecla Pausa y el buzon; Pausa y el buzon
    // DESARMAN el automatico hasta el siguiente reset (para poder mirar el V9968 mientras
    // un programa V9990 sigue encendiendo su pantalla). +0x2C bit1 = 1 lo apaga del todo.
    // El menu apaga la pantalla del V9990 al arrancar (p1_init).
    // V9991 (28/10/2026): +0x2C bit 3 = 1 fuerza el modo 3 del compositor ("Video9000": el V9990
    // encima del V9968, transparente donde YSE = 1 y el bit YS de la paleta); con bit 3 = 0 el
    // modo es 0/1 segun vdp_sel, exactamente lo de siempre.
    reg  [2:0]  v99_key_s = 3'b000;
    reg  [20:0] v99_key_lock = 21'd0;
    reg  [7:0]  v99_seq_q = 8'd0;
    reg  [2:0]  v99_disp_s = 3'b000;     // DISP && modo capturable (clk_86) -> clk_54m + flanco
    reg  [1:0]  v99_rst_s = 2'b11;       // bus_reset_n -> clk_54m
    reg         v99_auto_armed = 1'b1;   // se rearma con el reset; Pausa/buzon lo desarman
    reg         vdp_sel = 1'b0;          // 0 = V9968, 1 = V9990
    wire        v99_auto_en = ~mb_vid_ctl[1] & v99_auto_armed;
    always @(posedge clk_54m) begin
        v99_key_s  <= {v99_key_s[1:0], keyboard[72]};   // Pausa (HID 0x48)
        v99_disp_s <= {v99_disp_s[1:0], v99_disp & (v99_reso != 3'd5)};   // B6 (25 MHz) es el unico modo sin captura (B5 desde el 29/10/2026)
        v99_rst_s  <= {v99_rst_s[0], bus_reset_n};
        v99_seq_q  <= mb_vid_ctl[15:8];
        if (v99_key_lock != 21'd0) v99_key_lock <= v99_key_lock - 21'd1;
        if (mb_vid_ctl[15:8] != v99_seq_q) begin
            vdp_sel        <= mb_vid_ctl[0];
            v99_key_lock   <= 21'h1FFFFF;
            v99_auto_armed <= 1'b0;
        end
        else if (v99_key_lock == 21'd0 && v99_key_s[1] & ~v99_key_s[2]) begin
            vdp_sel        <= ~vdp_sel;
            v99_key_lock   <= 21'h1FFFFF;
            v99_auto_armed <= 1'b0;
        end
        else if (v99_auto_en && v99_disp_s[1] & ~v99_disp_s[2])   // pantalla encendida: al V9990
            vdp_sel <= 1'b1;
        if (~v99_rst_s[1]) begin                               // reset del MSX: V9968 y rearmar
            vdp_sel        <= 1'b0;
            v99_auto_armed <= 1'b1;
        end
    end
`ifdef TR_SIN_V9990
    wire [1:0] comp_mode = 2'd0;         // perfil TR: sin V9990, el compositor se queda en el V9968 a pantalla completa (Pausa y el buzon no cambian nada)
`else
    wire [1:0] comp_mode = mb_vid_ctl[3] ? 2'd3 : {1'b0, vdp_sel};
`endif
    // el raton USB para el gestor de ventanas del compositor (R#55 bit 1; 29/10/2026): los mismos informes que el raton
    // MSX del puerto 2, en clk_54m; se asignan abajo, junto a msx_mouse
    wire              wm_m_rep, wm_m_btn;
    wire signed [7:0] wm_m_dx, wm_m_dy;
`ifdef ENABLE_DUAL
    // Dual (2/11/2026): el gestor de ventanas dice al ARM donde esta el puntero y la ventana de A (v9991_compose t_*), y recibe el foco del teclado
    // para apagar la barra de titulo de A cuando el teclado esta en B. Un cambio de t_tgl (linea 300, el resto quieto) captura todo en clk_54m.
    wire [10:0] wmt_px, wmt_wx;
    wire [9:0]  wmt_py, wmt_wy;
    wire        wmt_btn, wmt_drag, wmt_act, wmt_tgl;
    reg  [2:0]  wmt_s = 3'b000;
    reg  [14:0] wm_tel_n = 15'd0;
    reg  [63:0] wm_tel_q = 64'd0;                                   // MBOX+0xD0: [10:0] px [20:11] py [21] boton [22] arrastra A [23] gestor activo
    always @(posedge clk_54m) begin                                 //   [34:24] x de A [44:35] y de A [45] foco en B [46] B corre [47] A en silencio
        wmt_s <= {wmt_s[1:0], wmt_tgl};                             //   [48] B en silencio [63:49] cuenta de muestras (15 bits)
        if (wmt_s[2] ^ wmt_s[1]) begin
            wm_tel_n <= wm_tel_n + 15'd1;
            wm_tel_q <= {wm_tel_n + 15'd1, b_mute_s, a_mute_s, b_running, b_focus, wmt_wy, wmt_wx, wmt_act, wmt_drag, wmt_btn, wmt_py, wmt_px};
        end
    end
`endif
    v9991_compose u_comp (
        .clk_pixel(clk_hdmi), .cx(hd_cx), .cy(hd_cy),
        .rgb68(c_rgb68), .rgb99(c_rgb99), .ys99(c_ys99), .in99(c_in99),
        .mode(comp_mode), .winreg(v99_win), .reso99(c_reso99), .il99(c_il99),
        .rgb(c_rgb), .mode_active(comp_mode_active), .desk_free(c_desk_free),
        .win_en(c_win_en), .win_x0(c_win_x0), .win_y0(c_win_y0), .win_scl(c_win_scl),
        .win_sx0(c_win_sx0), .win_sy0(c_win_sy0),
`ifdef ENABLE_DUAL
        .clk_m(clk_54m), .m_rep(wm_m_rep), .m_dx(wm_m_dx), .m_dy(wm_m_dy), .m_btn(wm_m_btn), .tod(rtc_tod),
        .a_focus(~b_focus), .mute_a(a_mute_s), .t_px(wmt_px), .t_py(wmt_py), .t_btn(wmt_btn), .t_drag(wmt_drag), .t_act(wmt_act),
        .t_wx(wmt_wx), .t_wy(wmt_wy), .t_tgl(wmt_tgl)
`else
        .clk_m(clk_54m), .m_rep(wm_m_rep), .m_dx(wm_m_dx), .m_dy(wm_m_dy), .m_btn(wm_m_btn), .tod(rtc_tod)
`endif
    );
    // telemetria +0x60 (30/10/2026, Z1.3): bit 31 = la HDMI muestra el V9990 (modos 1, 2 y 3; antes solo el bit 0 del
    // modo, y con la ventana la OLED decia V9968), bit 10 = el V9968 compuesto con el V9990 (ventana o Video9000)
    wire vdp_sel_active = |comp_mode_active;
    wire vdp_compuesto  = comp_mode_active[1];
`endif

    // ---- dh/dl: divisor LIBRE clk_108m ÷8/÷16 — el patron EXACTO con el
    // que sdr16_tb valida memory_ctrl (T1-T10, W1-W4). Slots CPU a 6.75MHz:
    // mas huecos vacios para wave+wv2 que con el VDP viejo.
    reg [3:0] v68_phc = 4'd0;
    always @(posedge clk_108m) v68_phc <= v68_phc + 1'b1;
    assign VideoDHClk = ~v68_phc[2];
    assign VideoDLClk = ~v68_phc[3];

    // VRAM del VDP viejo: inactiva (el slot VDP de la SDRAM queda vacio)
    assign WeVdp_n = 1'b1;
    assign VdpAdr  = 17'd0;
    assign VrmDbo  = 8'd0;

    // sondas de video del bring-up: pll86_lock + contador de frames (vs)
    reg [2:0] v68_frm = 3'd0;
    reg       v68_vs_d = 1'b0;
    always @(posedge clk_86) begin
        v68_vs_d <= v68_vs;
        if (v68_vs & ~v68_vs_d) v68_frm <= v68_frm + 1'b1;
    end
    assign dbg_video_w = {1'b0, 1'b0, 1'b0, v68_frm[2], pll86_lock, 1'b0};
`ifdef VIDEO720
    assign dbg_bridge_w = 6'd0;
`endif
`endif // ENABLE_V9968_VDP

`ifdef ENABLE_MAPPER
    //mapper
    wire mapper_read;
    wire mapper_write;
    wire mapper_req;
    reg mapper_req3;
    reg mapper_req12;
    reg [7:0] mapper_dout;
    wire [21:0] mapper_addr;
    reg [7:0] mapper_reg0;
    reg [7:0] mapper_reg1;
    reg [7:0] mapper_reg2;
    reg [7:0] mapper_reg3;
    wire mapper_reg_write;

    // TR: la RAM del FS-A1ST son 256 KB (16 segmentos de 16 KB): solo cuentan los 4 bits bajos del registro (los demas dan alias)
    wire [7:0] mreg0m = tr_map ? {1'b0, mapper_reg0[6:0]} : mapper_reg0;
    wire [7:0] mreg1m = tr_map ? {1'b0, mapper_reg1[6:0]} : mapper_reg1;
    wire [7:0] mreg2m = tr_map ? {1'b0, mapper_reg2[6:0]} : mapper_reg2;
    wire [7:0] mreg3m = tr_map ? {1'b0, mapper_reg3[6:0]} : mapper_reg3;
    assign mapper_addr = (bus_addr [15:14] == 2'b00 ) ? { mreg0m, bus_addr[13:0] } :
                         (bus_addr [15:14] == 2'b01 ) ? { mreg1m, bus_addr[13:0] } :
                         (bus_addr [15:14] == 2'b10 ) ? { mreg2m, bus_addr[13:0] } :
                                                        { mreg3m, bus_addr[13:0] };
`ifdef ENABLE_TR
    assign tr_mapper_rd  = tr_map && (bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0) && (bus_addr[7:2] == 6'b111111);
    assign tr_mapper_rdv = {1'b1, (bus_addr[1:0] == 2'b00) ? mapper_reg0[6:0] : (bus_addr[1:0] == 2'b01) ? mapper_reg1[6:0] :
                                    (bus_addr[1:0] == 2'b10) ? mapper_reg2[6:0] : mapper_reg3[6:0]};
`endif

    always @ (posedge clk_54m) begin
        mapper_req3 <= ( bus_rfsh_n == 1 && config_enable_mapper3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[0] == 1 && xffff == 0) ? 1 : 0;
        mapper_req12 <= ( config_enable_mapper12 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_mapper_slot ) ? 1 : 0;
    end
    assign mapper_req = mapper_req3 | mapper_req12;
    assign mapper_read = mapper_req & ~bus_rd_n;
    assign mapper_write = mapper_req & ~bus_wr_n;
    assign mapper_reg_write = ( (bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0) && (bus_addr [7:2] == 6'b111111) )?1:0;

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            mapper_reg0	<= 8'b00000011;
            mapper_reg1	<= 8'b00000010;
            mapper_reg2	<= 8'b00000001;
            mapper_reg3	<= 8'b00000000;
        end
        else if (mapper_reg_write == 1) begin
            case (bus_addr[1:0])
                2'b00: mapper_reg0 <= cpu_dout[7:0];
                2'b01: mapper_reg1 <= cpu_dout[7:0];
                2'b10: mapper_reg2 <= cpu_dout[7:0];
                2'b11: mapper_reg3 <= cpu_dout[7:0];
            endcase
        end
    end
`else
    wire mapper_read;
    wire mapper_write;
    wire mapper_req;
    reg [7:0] mapper_dout;
    wire [21:0] mapper_addr;
    assign mapper_read = 0;
    assign mapper_write = 0;
    assign mapper_addr = 22'd0;
`endif

    reg [15:0] VrmDbi2;
    reg [7:0] megaram_dout;
`ifdef NEO16_16M
    wire [24:0] ram_addr;           // perfil TR: 25 bits; bit 24 = los 8 MB altos de la megaram (memory_axi, 0x0C000000)
`else
    wire [23:0] ram_addr;           // 23/09/2026: 24 bits; bit 23 = zona EXT de memory_axi (0x0E000000)
`endif
    wire ram_read;
    wire ram_write;
    wire ram_req;
    wire [7:0] ram_din;
    reg [7:0] ram_dout;
    reg ram_busy;
    wire ram_slow;      // ZYNQ (memory_axi): 1 solo en los accesos LARGOS (fallo de cache)

    //rom map, 512 KB, [18:0]
    //876 54321098 76543210
    //111 11xxxxxx xxxxxxxx free, 16 KB, 0x7c000 - 0x7ffff
    //111 10xxxxxx xxxxxxxx esp8266, 16 KB, 0x78000 - 0x7bfff
    //111 0xxxxxxx xxxxxxxx kanji, 32 KB, 0x70000 - 0x77fff
    //110 11xxxxxx xxxxxxxx fm + logo + boot menu, 16 KB, 0x6c000 - 0x6ffff
    //110 10xxxxxx xxxxxxxx msx2+ subrom, 16 KB, 0x68000 - 0x6bfff
    //110 0xxxxxxx xxxxxxxx msx2+ bios, 32 KB, 0x60000 - 0x67fff
    //10x xxxxxxxx xxxxxxxx wondertang disk, 128 KB, 0x40000 - 0x5ffff
    //01x xxxxxxxx xxxxxxxx jis2, 128 KB, 0x20000 - 0x3ffff
    //00x xxxxxxxx xxxxxxxx jis1, 128 KB, 0x00000 - 0x1ffff

    //sdram map, 8 MB, [22:0]
    //2109876 54321098 76543210
    //11111xx xxxxxxxx xxxxxxxx vram, 256 KB, bank D
    //1110111 10xxxxxx xxxxxxxx esp8266, 16 KB, 0x778000 - 0x77bfff
    //1110111 00xxxxxx xxxxxxxx 2a pagina del menu (slot 3-1 pag.2), 16 KB, 0x770000 - 0x773fff (V3.5; era la 1a mitad del driver kanji)
    //1110111 01xxxxxx xxxxxxxx reserva, 16 KB, 0x774000 - 0x777fff (era la 2a mitad del driver kanji; el pack la deja a FF)
    //1110110 11xxxxxx xxxxxxxx fm + logo + boot menu, 16 KB, 0x76c000 - 0x76ffff
    //1110110 10xxxxxx xxxxxxxx msx2+ subrom, 16 KB, 0x768000 - 0x76bfff
    //1110110 0xxxxxxx xxxxxxxx msx2+ bios, 32 KB, 0x760000 - 0x767fff
    //111010x xxxxxxxx xxxxxxxx wondertang disk, 128 KB, bank D, 0x740000 - 0x75ffff
    //11100xx xxxxxxxx xxxxxxxx kanji data jis1 + jis2, 256 KB, 0x700000 - 0x73ffff
    //10xxxxx xxxxxxxx xxxxxxxx megaram, mitad BAJA (A21=0), 2 MB, bank C   (V3.5)
    //01xxxxx xxxxxxxx xxxxxxxx megaram, mitad ALTA (A21=1), 2 MB, bank B   (V3.5)
    //00xxxxx xxxxxxxx xxxxxxxx mapper, 2 MB, bank A                        (V3.5: era 4 MB en A+B)
    //
    // 23/09/2026 (ASCII16-X): ram_addr de 24 bits. Todo lo de arriba lleva el bit 23 a 0 (la
    // ventana de 8 MB de siempre). La megaram crece a 8 MB y sus 4 MB ALTOS (megaram_addr[22] = 1)
    // van a {1, 0, A21, A20-A0} = 800000h-BFFFFFh, que memory_axi manda a EXT_BASE (0x0E000000, DDR
    // baja) en vez de detras de la ventana (ahi empieza la imagen de disco, 0x11000000). Sin
    // sumador: {A22, ~A22 & ~A21, A21} reproduce el {~A21, A21} de siempre cuando A22 = 0.
    //
    // V3.5: el mapper se recorta a 2 MB (bit 7 del registro ignorado: los
    // segmentos 128-255 aliasan sobre 0-127, que es como se comporta un mapper
    // real de 8 bits) y ese hueco se lo lleva la megaram, que pasa a 4 MB. La
    // mitad baja sigue en el banco C: todo lo de <=2 MB cae en las mismas
    // direcciones fisicas que antes. Sin sumador: A21 elige {~A21, A21}.

    // V3.6: el camino "stream" (CPU parada) lo comparten el streamer de la flash
    // del arranque y la DMA de la SD. El mux de arriba sigue siendo de dos ramas:
    // la eleccion flash/DMA va por debajo, sobre registros, fuera del cono de la CPU.
    wire        stream_active = ~flash_idle | dma_frz;
`ifdef NEO16_16M
    wire [24:0] stream_addr   = (~flash_idle) ? { 2'b00, rom_addr[22:0] } : dma_ram_addr;
`else
    wire [23:0] stream_addr   = (~flash_idle) ? { 1'b0, rom_addr[22:0] } : dma_ram_addr;
`endif
    wire [7:0]  stream_dout   = (~flash_idle) ? rom_dout : dma_ram_din;
    wire        stream_write  = (~flash_idle) ? rom_write : dma_ram_req;
    assign ram_addr = (stream_active) ? stream_addr :
                `ifdef ENABLE_MAPPER
                        (mapper_req == 1) ? { 3'b000, mapper_addr[20:0] } :  //bank A (2 MB)
                `endif
                        (trm_req == 1) ? trm_addr :   // TR: firmware del turbo R (bit 23 = zona EXT de memory_axi, 0x0E400000) o DRAM (mapper)
                        (bios_req == 1 ) ? { 9'b011101100, bus_addr[14:0] } : //bank D
                        (subrom_logo_req == 1 ) ? { 9'b011101101, bus_addr[14:0] } : //bank D
                `ifdef ENABLE_SDCARD
                        (megarom_req == 1 ) ? { 7'b0111010, megarom_addr[16:0] } : //bank D
                `endif
                `ifdef NEO16_16M
                        (megaram_req == 1 ) ? { megaram_addr[23], megaram_addr[22], ~megaram_addr[22] & ~megaram_addr[21], megaram_addr[21], megaram_addr[20:0] } :
                `else
                        (megaram_req == 1 ) ? { megaram_addr[22], ~megaram_addr[22] & ~megaram_addr[21], megaram_addr[21], megaram_addr[20:0] } :  //bank C (A21=0) / bank B (A21=1) / 23/09: EXT (A22=1)
                `endif
                        (gm2_mem_req == 1 ) ? { 3'b001, gm2_addr[20:0] } :  //bank B: V3.5f Game Master 2 (segs 480-496 de la megaram, A21=1)
                        (menu2_req == 1 ) ? { 9'b011101110, 1'b0, bus_addr[13:0] } : //bank D: 2a pagina del menu (pack 0x70000, V3.5)
                        (kanji_data_ram_req == 1 ) ? { 6'b011100, kanji_data_ram_addr[17:0] } : //bank D
                `ifdef ENABLE_WIFI
                        (wifi_req == 1 ) ? { 10'b0111011110, bus_addr[13:0] } : //bank D
                `endif
                        // logo SIEMPRE (v3.0): estaba atrapado en ENABLE_WIFI y sin WiFi
                        // se perdia la pantalla de marca del menu
                        (logo_req == 1 ) ? { 10'b0111011111, bus_addr[13:0] } : //bank D (pack 0x7C000)
                        24'h7fffff;
    
    // P1-fix (_64): muxes de habilitacion APLANADOS. Las cascadas ternarias
    // (~10 niveles) devolvian LO MISMO en todas las ramas -> OR plano
    // booleanamente identico (y los reqs son mutuamente exclusivos por decode).
    // Era el grueso del cono strobe->CE (7 niveles de LUT + 1.9ns de net) que
    // la loteria de placement no siempre absorbia; el OR de 2 niveles lo mata
    // de raiz sin pins INS_LOC (leccion del ESC de la _62: los samplers no se
    // mueven).
    wire any_ram_rd_req =
                `ifdef ENABLE_MAPPER
                      mapper_read |
                `endif
                      trm_req | bios_req | subrom_logo_req |
                `ifdef ENABLE_SDCARD
                      megarom_req |
                `endif
                      megaram_req | gm2_mem_req | menu2_req | kanji_data_ram_req |
                `ifdef ENABLE_WIFI
                      wifi_req |
                `endif
                      logo_req;
    wire any_ram_req =
                      mapper_req | trm_req | bios_req | subrom_logo_req |
                `ifdef ENABLE_SDCARD
                      megarom_req |
                `endif
                      megaram_req | gm2_mem_req | menu2_req | kanji_data_ram_req |
                `ifdef ENABLE_WIFI
                      wifi_req |
                `endif
                      logo_req;
    wire any_ram_wr =
                `ifdef ENABLE_MAPPER
                      (mapper_write & ~(tr_map & dram_mode_w & (&mapper_addr[20:16]))) |   // TR: en modo DRAM los ultimos 64 KB de la RAM (la BIOS copiada) son de solo lectura
                `endif
                      megaram_wrt | gm2_mem_wrt;

    assign ram_read  = (stream_active) ? 1'b0      : (any_ram_rd_req & ~bus_rd_n);

    assign ram_write = (stream_active) ? stream_write : (any_ram_wr & ~bus_wr_n);

    // _125c: se EVALUO registrar any_ram_req (el cono T80 ISet/IStatus ->
    // mux A -> mapper -> aceptacion, ~13 niveles, familia final de timing de
    // la campana _125) y el A/B de la W-suite lo RECHAZO: la correccion pasa
    // (W1-W5 OK) pero T10 sostenido cae a la MITAD (296ns vs 148 — el drop
    // retrasado del req hace perder una ventana entre lecturas back-to-back)
    // y T9b pierde 13% de lecturas en 1T @5.369. El turbo manda: la familia
    // se contiene con syn_maxfan (ISet/IStatus en t80.vhd) + sembrado.
    assign ram_req   = (stream_active) ? stream_write : any_ram_req;

    assign ram_din = (stream_active) ? { stream_dout, stream_dout }  : { cpu_dout, cpu_dout };

// SDCLK_INVERT=1 CONFIRMADO EN HW (2026-07-08): con fase normal el auto-test
// da ROJO (errores CPU) y con 180 grados VERDE; el core arranca (serial _18inv).
// _104: puerto WAVE de la SDRAM (declarado ANTES de su primer uso — Gowin
// declara implicitos de 1 bit si no; leccion _95 de los weng_*)
wire        wv_req, wv_we, wv_done;
wire [21:0] wv_addr;
wire [7:0]  wv_wdata;
wire [15:0] wv_dout;
// V9968: puerto wv2 (VRAM del V9968 via bridge CDC); atado a 0 sin el define
wire        wv2_req, wv2_we, wv2_done;
wire [21:0] wv2_addr;
wire [7:0]  wv2_wdata;
wire [15:0] wv2_dout;
// V9968 _120: puerto wv3 (canal B del shim, solo lecturas — mitad alta)
wire        wv3_req, wv3_we, wv3_done;
wire [21:0] wv3_addr;
wire [7:0]  wv3_wdata;
wire [15:0] wv3_dout;
// _159: wv2 lo conduce el shim del ADPCM-B cuando ENABLE_ADPCM_SDRAM esta
// derivado (ver la cabecera); los tie-offs de wv2 solo sobreviven si no.
`ifndef ENABLE_V9968_VDP
`ifndef ENABLE_ADPCM_SDRAM
assign wv2_req   = 1'b0;
assign wv2_we    = 1'b0;
assign wv2_addr  = 22'd0;
assign wv2_wdata = 8'd0;
`endif
assign wv3_req   = 1'b0;
assign wv3_we    = 1'b0;
assign wv3_addr  = 22'd0;
assign wv3_wdata = 8'd0;
`else
`ifdef ENABLE_VRAM_AXI
// _128X: la VRAM vive en la DDR3 — los puertos wv2/wv3 de memory.v inertes
`ifndef ENABLE_ADPCM_SDRAM
assign wv2_req   = 1'b0;
assign wv2_we    = 1'b0;
assign wv2_addr  = 22'd0;
assign wv2_wdata = 8'd0;
`endif
assign wv3_req   = 1'b0;
assign wv3_we    = 1'b0;
assign wv3_addr  = 22'd0;
assign wv3_wdata = 8'd0;
`endif
`endif

// V3.6d: cpu_run REGISTRADO. El termino de abajo junta seis senales de clk_54m
// y entraba directo al RESET del contador rfsh_gap de memory_ctrl, que vive en
// clk_108m: un camino 54 -> 108 MHz que en la campana v36c salio a 0,913 ns en el
// dado entregado y a 0,039 ns en otro. Con este FF el camino empieza registrado.
// El ciclo de retraso es inocuo en los dos sentidos: cuando la DMA deja de permitir
// el refresco, sd_dma todavia espera 40 ciclos (S_GUARD) antes del primer byte del
// bloque; y permitirlo un ciclo mas tarde solo lo hace mas conservador.
reg cpu_run_r = 1'b0;
always @(posedge clk_54m)
    cpu_run_r <= bus_reset_n & reset3_n & flash_idle & esp_boot_ok & ~dma_rfsh_ok;   // ZYNQ: el OSD no toca la cache de memory_axi

// ==== ZYNQ: la RAM del Z80 en la DDR del PS (zynq/memory_axi.v, HP1 @ clk_54m) ====
// Mismo contrato ram_* que memory_ctrl. vram_*/wv*/rfsh no existen aqui (V9968 con
// VRAM en AXI; ADPCM en BRAM; sin wave; el refresco lo hace el DDRC).
wire [31:0] mem_dbg_hits, mem_dbg_miss, mem_dbg_state;
wire [319:0] mem_lat_tel;     // perfil TR fase 0: latencia de memory_axi (MBOX+0xD8..0xFF)
wire        mem_lat_clr;      // MBOX+0x1C bit 5
reg  [1:0]  rst54_s = 2'b00;
always @(posedge clk_54m) rst54_s <= {rst54_s[0], frst0_n};
wire        rst54_n = rst54_s[1];
memory_axi #(.RAM_BASE(32'h1080_0000), .EXT_BASE(32'h0E00_0000), .LINES_LOG(12)) mem1 (   // 23/09: EXT = 4 MB altos de la megaram
    .clk_54m(clk_54m), .bus_reset_n(bus_reset_n),
    .video_dhclk(VideoDHClk), .video_dlclk(VideoDLClk), .cpu_run(cpu_run_r),
    .ram_din(ram_din), .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr),
    .ram_dout(ram_dout), .ram_busy(ram_busy), .ram_slow(ram_slow),
    .dbg_hits(mem_dbg_hits), .dbg_miss(mem_dbg_miss), .dbg_state(mem_dbg_state), .ready(),
    .lat_clr(mem_lat_clr), .lat_tel(mem_lat_tel),
    .aresetn(rst54_n),
    .M_AWID(hp1_awid), .M_AWADDR(hp1_awaddr), .M_AWLEN(hp1_awlen), .M_AWSIZE(hp1_awsize),
    .M_AWBURST(hp1_awburst), .M_AWLOCK(hp1_awlock), .M_AWCACHE(hp1_awcache), .M_AWPROT(hp1_awprot),
    .M_AWQOS(hp1_awqos), .M_AWVALID(hp1_awvalid), .M_AWREADY(hp1_awready),
    .M_WID(hp1_wid), .M_WDATA(hp1_wdata), .M_WSTRB(hp1_wstrb), .M_WLAST(hp1_wlast),
    .M_WVALID(hp1_wvalid), .M_WREADY(hp1_wready),
    .M_BID(hp1_bid), .M_BRESP(hp1_bresp), .M_BVALID(hp1_bvalid), .M_BREADY(hp1_bready),
    .M_ARID(hp1_arid), .M_ARADDR(hp1_araddr), .M_ARLEN(hp1_arlen), .M_ARSIZE(hp1_arsize),
    .M_ARBURST(hp1_arburst), .M_ARLOCK(hp1_arlock), .M_ARCACHE(hp1_arcache), .M_ARPROT(hp1_arprot),
    .M_ARQOS(hp1_arqos), .M_ARVALID(hp1_arvalid), .M_ARREADY(hp1_arready),
    .M_RID(hp1_rid), .M_RDATA(hp1_rdata), .M_RRESP(hp1_rresp), .M_RLAST(hp1_rlast),
    .M_RVALID(hp1_rvalid), .M_RREADY(hp1_rready)
);
// puertos de memory_ctrl que aqui no existen: en reposo
assign VrmDbi2 = 16'd0;
assign wv_dout = 16'd0;  assign wv_done = 1'b0;
assign wv2_dout = 16'd0; assign wv2_done = 1'b0;
assign wv3_dout = 16'd0; assign wv3_done = 1'b0;
assign O_sdram_clk = 1'b0; assign O_sdram_cke = 1'b0; assign O_sdram_cs_n = 1'b1;
assign O_sdram_cas_n = 1'b1; assign O_sdram_ras_n = 1'b1; assign O_sdram_wen_n = 1'b1;
assign O_sdram_addr = 13'd0; assign O_sdram_ba = 2'd0; assign O_sdram_dqm = 2'b11;

`ifdef ENABLE_TR
    // ===== Perfil TR, fase 2: R800, S1990 completo y mapa de slots del FS-A1ST (docs/tecnica/15-perfil-tr.md) =====
    // Las dos CPUs (el G80a de arriba y el R800) cuelgan de tr_cpu, que elige la que manda en el bus y hace el cambio de la S1990.
    // El R800 va en clk_54m con un habilitador ce21 de 21,477 MHz (35/88): el nucleo, su bus y el regulador de tiempo solo avanzan
    // con ce21, asi que sus caminos tienen 2 ciclos de 54 MHz (set_multicycle_path en top_zynq.xdc).
    reg [6:0] ce21_acc = 7'd0;
    reg       ce21 = 1'b0;
    wire [7:0] ce21_acc_n = {1'b0, ce21_acc} + 8'd35;
    always @(posedge clk_54m) begin
        if (ce21_acc_n >= 8'd88) begin ce21_acc <= ce21_acc_n - 8'd88; ce21 <= 1'b1; end
        else                     begin ce21_acc <= ce21_acc_n[6:0];    ce21 <= 1'b0; end
    end

    // el mapa FS-A1ST se decide con la BIOS ya en la DDR (el companion o boot.tcl ponen MBOX+0x1C bit 6 junto con MSX_RUN)
    always @(posedge clk_54m) if (!bus_reset_n) tr_map <= mb_tr_bios;

    // ---- esperas del R800: memoria y E/S ----
    // Lecturas y escrituras de RAM: se espera hasta que memory_axi ha terminado esta operacion (ram_busy sube y baja). any_ram_req
    // llega 1 ciclo despues del strobe, antes de que el R800 mire WAIT_n (2 ciclos como minimo), asi que la espera ya esta armada.
    // 04/11 (INIR del kanji): solo cuenta un ram_busy que SUBE con la peticion en curso. Si la operacion anterior (la escritura en (HL) del INI) sigue en
    // vuelo cuando llega la peticion nueva (el kanji, registrado a 27 MHz), memory_axi no la acepta hasta acabar aquella; con el nivel, la bajada del busy
    // de la escritura daba la lectura por hecha y el R800 tomaba ram_dout con el contenido viejo del bufer (bytes ajenos entre los buenos).
    reg tr_seen_busy = 1'b0, tr_ram_done = 1'b0, tr_busy_q = 1'b0;
    always @(posedge clk_54m) begin
        tr_busy_q <= ram_busy;
        if (!any_ram_req) begin tr_seen_busy <= 1'b0; tr_ram_done <= 1'b0; end
        else begin
            if (ram_busy && !tr_busy_q) tr_seen_busy <= 1'b1;
            else if (tr_seen_busy && !ram_busy) tr_ram_done <= 1'b1;
        end
    end
    wire tr_wait_ram = any_ram_req & ~tr_ram_done;
    // E/S: 8 ciclos de 54 MHz (148 ns) como minimo desde que baja IORQ; los dispositivos registran el bus (clk_27m + cpu_din) y algunos
    // levantan su propio WAIT unos ciclos despues del IORQ (V9968: ~65 ns), mas tarde de lo que mira el R800.
    reg [5:0] tr_ioc = 6'd0;
    // OJO: bus_iorq_n, NO ex_bus_iorq_n (este se fuerza a 1 en los accesos al V9968: bus_iorq_disable) -- con ex_ el VDP se quedaba sin la espera minima
    wire tr_io_cyc = (bus_iorq_n == 1'b0) && (bus_rd_n == 1'b0 || bus_wr_n == 1'b0);
    always @(posedge clk_54m) begin
        if (!tr_io_cyc) tr_ioc <= 6'd0;
        else if (tr_ioc != 6'd63) tr_ioc <= tr_ioc + 6'd1;
    end
    // 03/11 (audio): el strobe de E/S del R800 dura 36 ciclos de clk_54m (667 ns) como minimo, para que cubra al menos dos pulsos del reloj de 3,58 MHz (cada 15,1 ciclos):
    // el OPLL/Y8950 (cen), los puertos de configuracion #40-#46 y el anillo del WaveGame (92h/93h) toman la escritura solo en esos pulsos, y con 8 ciclos (strobe de ~12) el 12,6 %
    // de las escrituras caia entre dos pulsos y se perdia (fpga/r800/sim/run_io.sh: 104 de 824; con 36, 0). El PSG, el SCC y el RTC capturan por nivel o flanco a 27/54 MHz y no lo notaban.
    // OPLL (7Ch/7Dh): separacion minima entre escrituras como la del YM2413 (12 ciclos de phiM tras la direccion, 84 tras el dato) y strobe oculto al chip hasta cumplirla;
    // sin ella los OUT seguidos del R800 se pisaban en el latch de datos del IKAOPLL (fpga/r800/sim/run_opll.sh: audio distinto del de un Z80; con la puerta, igual)
    wire tr_op_wait, tr_op_allow;
    tr_opll_gate u_oplgate (.clk(clk_54m), .rst_n(bus_reset_n), .sel_wr(tr_io_cyc && bus_wr_n == 1'b0 && bus_addr[7:1] == 7'b0111110), .a0(bus_addr[0]), .wait_o(tr_op_wait), .allow(tr_op_allow));
    wire tr_wait_io = (tr_io_cyc && (tr_ioc < 6'd36)) || tr_op_wait;
`ifdef ENABLE_WIFI
    wire tr_wait_base = bus_wait_n & wait_uart & wait_net_n & opl4pcm_wait_n & vdp_wait54_n;
`else
    wire tr_wait_base = bus_wait_n & opl4pcm_wait_n & vdp_wait54_n;
`endif
    wire tr_r_wait_n = tr_wait_base & ~tr_wait_ram & ~tr_wait_io;
    // INT del V9968: sale de un registro de clk_86 y entraba al R800 (clk_54m) sin sincronizar (report_cdc); dos etapas (ASYNC_REG) antes del nucleo
    (* ASYNC_REG = "TRUE" *) reg [1:0] tr_vint_s = 2'b11;
    always @(posedge clk_54m) tr_vint_s <= {tr_vint_s[0], vdp_int};
    `ifdef TR_V9990
    // INT del V9990: combinacional de clk_86 (report_cdc: CDC-10); se registra antes de cruzar y lleva dos etapas hasta el R800
    reg v99_int86_rq = 1'b1;
    always @(posedge clk_86) v99_int86_rq <= v99_int_n;
    (* ASYNC_REG = "TRUE" *) reg [1:0] tr_v99int_s = 2'b11;
    always @(posedge clk_54m) tr_v99int_s <= {tr_v99int_s[0], v99_int86_rq};
    wire tr_int_n = bus_int_n & tr_vint_s[1] & y8950_int_n & opl4_int_n & tr_v99int_s[1];
`else
    wire tr_int_n = bus_int_n & tr_vint_s[1] & y8950_int_n & opl4_int_n & v99_int_n;
`endif

    // ---- S1990 -> tr_cpu (27 -> 54 MHz con 2FF: son niveles casi estaticos) y tr_cpu -> S1990 ----
    wire s1990_cpu_r800, s1990_rom_mode, tr_r800_cur;
    reg  [1:0] tr_want_s = 2'b00, tr_rom_s = 2'b11;
    reg  [1:0] tr_cur_s = 2'b00;
    always @(posedge clk_54m) begin
        tr_want_s <= {tr_want_s[0], s1990_cpu_r800};
        tr_rom_s  <= {tr_rom_s[0], s1990_rom_mode};
    end
    always @(posedge clk_27m) tr_cur_s <= {tr_cur_s[0], tr_r800_cur};
    assign dram_mode_w = ~tr_rom_s[1];

    // telemetria de depuracion (MBOX+0x60..0x6F): {tr_wait_ram, tr_wait_io, vdp_wait54_n, bus_wait_n, opl4pcm_wait_n, wait_uart, wait_net_n, int_n}
    wire [31:0] tr_tel_a, tr_tel_b, tr_tel_c, tr_tel_d;
    wire [511:0] tr_tel_ring;
    wire tr_trc_full;  wire [31:0] tr_trc_data;  wire vtr_arm;
    wire [9:0] vtr_rd_addr;                   // lo maneja el buzon (declarado aqui porque tr_cpu lo usa antes)
`ifdef ENABLE_WIFI
    wire [7:0] tr_ext_flags = {tr_wait_ram, tr_wait_io, vdp_wait54_n, bus_wait_n, opl4pcm_wait_n, wait_uart, wait_net_n, tr_int_n};
`else
    wire [7:0] tr_ext_flags = {tr_wait_ram, tr_wait_io, vdp_wait54_n, bus_wait_n, opl4pcm_wait_n, 2'b11, tr_int_n};
`endif
    // 03/11: el R800 arranca cuando el V9968 lleva ~40 ms fuera de reset (rst86_n sincronizado a clk_54m): sus primeras escrituras de registros (R#0-R#9, R#15...)
    // se perdian o llegaban a un VDP aun sin inicializar y el estado de retrazo (VR/HR de S#2) quedaba fijo: la BIOS se colgaba en sus bucles IN (99h) de espera
    reg [1:0]  tr_v86_s = 2'b00;
    reg [21:0] tr_vdp_dly = 22'd0;
    always @(posedge clk_54m) begin
        tr_v86_s <= {tr_v86_s[0], rst86_n};
        if (!tr_v86_s[1]) tr_vdp_dly <= 22'd0;
        else if (!tr_vdp_dly[21]) tr_vdp_dly <= tr_vdp_dly + 22'd1;
    end
    assign tr_vdp_ready = tr_vdp_dly[21];
    tr_cpu u_trcpu (
        .clk(clk_54m), .reset_n(bus_reset_n & reset3_n & flash_idle & esp_boot_ok & tr_vdp_ready), .ce21(ce21),
        .want_r800(tr_want_s[1]), .dram_mode(dram_mode_w), .r800_cur(tr_r800_cur),
        .cpu_din(cpu_din), .r_wait_sys_n(tr_r_wait_n), .int_n(tr_int_n), .frz(dma_frz), .frz_soft(dma_active | iosys_frz),
        .ppi_a(ppi_port_a), .exp0(exp_slot0), .exp3(exp_slotx),
        .bus_a(bus_addr), .bus_do(cpu_dout),
        .bus_m1_n(bus_m1_n), .bus_mreq_n(bus_mreq_n), .bus_iorq_n(bus_iorq_n),
        .bus_rd_n(bus_rd_n), .bus_wr_n(bus_wr_n), .bus_rfsh_n(bus_rfsh_n),
        .z_m1_n(z_m1_n), .z_mreq_n(z_mreq_n), .z_iorq_n(z_iorq_n), .z_rd_n(z_rd_n), .z_wr_n(z_wr_n), .z_rfsh_n(z_rfsh_n),
        .z_a(z_a), .z_do(z_do), .z_di(z_di_w), .z_en_pre(z_en_pre), .z_run(z_run_w), .z_wait_ovr(z_wait_ovr), .z_int_mask(z_int_mask),
        .dbg(),
        .slot_dbg({any_ram_req, mapper_req3, pri_slot_num[SD_SLOT], exp_slotx_num[0], xffff}), .ext_flags(tr_ext_flags), .tel_a(tr_tel_a), .tel_b(tr_tel_b), .tel_c(tr_tel_c), .tel_d(tr_tel_d), .tel_ring(tr_tel_ring),
        .trc_clr(mb_vid_ctl[6]), .io_only(mb_vid_ctl[2]), .frz_req(mb_vid_ctl[3]), .tr_full(tr_trc_full), .tr_rd_addr(vtr_rd_addr), .tr_rd_data(tr_trc_data)
    );

    // ---- mapa de slots del FS-A1ST (solo con tr_map): las lecturas del firmware y de la DRAM ----
    // firmware en la DDR (0x0E400000 = ram_addr C00000-FFFFFF, el fichero entero); la DRAM son los ultimos 64 KB de la RAM de 256 KB
    // (mapper 030000-03FFFF, que el BIOS rellena y el modo DRAM de la S1990 lee en lugar de la ROM):
    //   0-0 BIOS+BASIC  0000-7FFF : ROM 050000 / DRAM 030000     0-2 MSX-MUSIC 4000-7FFF : ROM 07C000    0-3 apertura 4000-7FFF : ROM 048000
    //   3-1 SUB-ROM     0000-3FFF : ROM 070000 / DRAM 038000     3-1 driver kanji + BASIC 4000-BFFF : ROM 074000 (4000-7FFF: DRAM 03C000)
    wire trpcm_sel = (bus_addr[7:1] == 7'b1010010) && !bus_iorq_n && bus_m1_n;
    assign trpcm_rd = trpcm_sel && !bus_rd_n;
    tr_pcm u_trpcm (
        .clk(clk_54m), .rst_n(bus_reset_n), .cen_3m58(clk_enable_3m6_54),
        .wr_a4(trpcm_sel && !bus_wr_n && !bus_addr[0]), .wr_a5(trpcm_sel && !bus_wr_n && bus_addr[0]),
        .din(cpu_dout), .a0(bus_addr[0]), .dout(trpcm_dout), .dac(trpcm_dac), .mute(trpcm_mute)
    );
    tr_rommap u_trrom (
        .clk(clk_54m), .tr_map(tr_map), .dram_mode(dram_mode_w), .mreq_n(bus_mreq_n), .rd_n(bus_rd_n), .rfsh_n(bus_rfsh_n), .a(bus_addr),
        .s0(pri_slot_num[0]), .s3(pri_slot_num[SD_SLOT]), .e0(exp_slot0_num), .e3(exp_slotx_num),
        .req(trm_req), .addr(trm_addr), .ovr(trm_ovr), .ovd(trm_ovd)
    );
`endif

    // ===== _161 ESTRUCTURA DE GANANCIA: registro de ganancia maestra =====
    // 0:x1  1:x1,5  2:x2  3:x3  4:x4  5:x5  6:x6  7:x8   (defecto x5 = +14,0 dB)
    // x5 = el valor que Albert ajusto a oido en placa (28/07): deja el conjunto
    // a la altura del OPL4/MoonSound sin tocar el balance entre chips.
    // Se escribe por el puerto #44 del bloque config y se persiste en el
    // byte[5] del bloque de config de la flash (hoy sin usar, se escribe 0xFF).
    reg [2:0] snd_gain_ff = 3'd5;

`ifdef ENABLE_MIXER
    // ===== V3.7 MEZCLADOR POR FUENTE (17/09/2026; Albert: "un settings de volumenes de psg, scc, wave,
    // opll, opl3 y opl4 wave"). Atenuador k/8 por fuente (k = 0..8: 8 = x1 = defecto, 0 = mudo) ANTES de
    // la suma; la ganancia maestra (canal 0) y el limitador no cambian. Puerto #44 extendido:
    //   OUT #44, {solo_sel[7], canal[6:4], nivel[3:0]}
    //     canal 0 = ganancia maestra (nivel[2:0] = la tabla x1..x8 de siempre: el OUT #44,0..7 legado
    //               sigue significando lo mismo)
    //     1 = PSG, 2 = SCC, 3 = OPLL (FM-PAC), 4 = MSX-AUDIO (Y8950 + ADPCM), 5 = OPL4 FM (OPL3),
    //     6 = OPL4 wave (PCM del MoonSound), 7 = WaveGame (solo ZYNQ)
    //     bit 7 = 1: no escribe nada, solo deja el canal seleccionado para la lectura
    //   IN #44 -> {0, canal_sel[6:4], nivel[3:0]}; canal 0 -> {0, 000, 0, ganancia[2:0]} = la lectura
    //   legada. SONDA del menu: OUT #44,#F0 + IN #44 = #7n con mezclador; un core sin el devuelve #0g.
    //   Los niveles no se resetean (como snd_gain_ff): en la Zynq los siembra el companion (MBOX+0x24)
    //   y salen por MBOX+0xC0 al pulsar "guardar"; en el Tang quedaria por persistir en la flash.
    reg  [27:0] mix_lvl = 28'h8888888;   // canales 1..7, 4 bits cada uno en [(canal-1)*4 +: 4]
    reg  [2:0]  mix_sel = 3'd0;          // canal seleccionado para la lectura
    wire [3:0]  mix_rd  = (mix_sel == 3'd0) ? {1'b0, snd_gain_ff} : mix_lvl[{mix_sel - 3'd1, 2'b00} +: 4];
`endif

`ifdef ENABLE_SOUND

    //YM219 PSG
    wire psgBdir;
    wire psgBc1;
    wire iorq_wr_n;
    wire iorq_rd_n;
    wire [7:0] psg_dout;
    wire [7:0] psgSound1;
    wire [7:0] psgPA;
    wire [7:0] psgPB;
    reg clk_1m8;
    assign iorq_wr_n = bus_iorq_n | bus_wr_n;
    assign iorq_rd_n = bus_iorq_n | bus_rd_n;
`ifdef ENABLE_TR
    // perfil TR (fase 1): el PSG decodifica SOLO A0h-A3h (el turbo R tiene el PCM en A4h/A5h y el S1990 en E4h-E7h); el estandar, A0h-A7h de siempre
    wire psg_io_hit = (bus_addr[7:2] == 6'b101000);
`else
    wire psg_io_hit = (bus_addr[7:3] == 5'b10100);
`endif
    assign psgBdir = ( psg_io_hit && iorq_wr_n == 0 && bus_addr[1]== 0 ) ?  1 : 0; // I/O:A0-A2h / PSG(AY-3-8910) bdir = 1 when writing to &HA0-&Ha1
    assign psgBc1 = ( psg_io_hit && ((iorq_rd_n==0 && bus_addr[1]== 1) || (bus_addr[1]==0 && iorq_wr_n==0 && bus_addr[0]==0))) ? 1 : 0; // I/O:A0-A2h / PSG(AY-3-8910) bc1 = 1 when writing A0 or reading A2
    assign psgPA =8'h00;
    // niquelado B: aqui habia un `reg psgPB = 8'hff;` DUPLICANDO el wire [7:0]
    // psgPB de arriba (identificador doble, ancho 1 vs 8 — mina de sintesis).
    // El wire con el loopback O_IOB->I_IOB es la conexion correcta del puerto B.

    // v2.4: el PSG vive ENTERO en 54M (su bus BDIR/BC1/I_DA es del dominio 54M;
    // clockearlo a 27M con la fase arbitraria del CLKDIV lo dejaba MUDO). La
    // cadencia 1.79M se regenera con los pulsos 3m6 del dominio 54.
    wire clk_enable_1m8;
    reg clk_1m8_prev;
    always @ (posedge clk_54m) begin
        if (clk_enable_3m6_54) begin
            clk_1m8 <= ~clk_1m8;
        end
    end
    assign clk_enable_1m8 = (clk_enable_3m6_54 == 1 && clk_1m8 == 1);

    // ===== r10 (_30dbg): AUTO-TEST del PSG (beeper sin CPU) =====
    // De t=1s a t=3s tras el reset, un FSM escribe directamente los registros
    // del psg1 (R7=tono A, R0/R1=periodo ~262Hz, R8=vol 15) y al salir lo
    // silencia. Si SUENA el pitido: chip+mezcla OK -> el corte esta en el
    // camino CPU->PSG. Si NO suena: chip/sintesis.
    reg [27:0] psgtest_cnt = 28'd0;
    always @(posedge clk_54m) begin
        if (~bus_reset_n) psgtest_cnt <= 28'd0;
        else if (psgtest_cnt != 28'hFFFFFFF) psgtest_cnt <= psgtest_cnt + 28'd1;
    end
    wire psgtest_win = (psgtest_cnt > 28'd54000000) && (psgtest_cnt < 28'd162000000);
    // secuencia: 5 escrituras (una cada 64 ciclos: fase addr 24c / data 24c / nop)
    reg [2:0]  ptst_idx = 3'd0;
    reg [5:0]  ptst_ph  = 6'd0;
    reg        ptst_done = 1'b0;
    reg [7:0]  ptst_da   = 8'd0;
    reg        ptst_bdir = 1'b0;
    reg        ptst_bc1  = 1'b0;
    wire [7:0] ptst_reg = (ptst_idx==3'd0) ? 8'd7 :
                          (ptst_idx==3'd1) ? 8'd0 :
                          (ptst_idx==3'd2) ? 8'd1 :
                          (ptst_idx==3'd3) ? 8'd8 : 8'd8;
    wire [7:0] ptst_val = (ptst_idx==3'd0) ? 8'hBE :
                          (ptst_idx==3'd1) ? 8'hAC :
                          (ptst_idx==3'd2) ? 8'h01 :
                          (ptst_idx==3'd3) ? 8'h0F : 8'h00;  // idx4 = silencio final
    reg psgtest_win_d = 1'b0;
    always @(posedge clk_54m) begin
        psgtest_win_d <= psgtest_win;
        if (~bus_reset_n) begin
            ptst_idx <= 3'd0; ptst_ph <= 6'd0; ptst_done <= 1'b0;
            ptst_bdir <= 1'b0; ptst_bc1 <= 1'b0; ptst_da <= 8'd0;
        end
        else if (psgtest_win && !ptst_done) begin
            ptst_ph <= ptst_ph + 6'd1;
            if      (ptst_ph < 6'd24) begin ptst_da <= ptst_reg; ptst_bdir <= 1'b1; ptst_bc1 <= 1'b1; end
            else if (ptst_ph < 6'd48) begin ptst_da <= ptst_val; ptst_bdir <= 1'b1; ptst_bc1 <= 1'b0; end
            else begin
                ptst_bdir <= 1'b0; ptst_bc1 <= 1'b0;
                if (ptst_ph == 6'd63) begin
                    if (ptst_idx == 3'd3) ptst_done <= 1'b1;  // beep armado; queda sonando
                    else ptst_idx <= ptst_idx + 3'd1;
                end
            end
        end
        else if (!psgtest_win && psgtest_win_d && ptst_done) begin
            // fin de ventana: re-armar para la escritura de silencio (idx 4)
            ptst_idx <= 3'd4; ptst_ph <= 6'd0; ptst_done <= 1'b0;
        end
        else if (!psgtest_win && !ptst_done && ptst_idx == 3'd4) begin
            ptst_ph <= ptst_ph + 6'd1;
            if      (ptst_ph < 6'd24) begin ptst_da <= ptst_reg; ptst_bdir <= 1'b1; ptst_bc1 <= 1'b1; end
            else if (ptst_ph < 6'd48) begin ptst_da <= ptst_val; ptst_bdir <= 1'b1; ptst_bc1 <= 1'b0; end
            else begin
                ptst_bdir <= 1'b0; ptst_bc1 <= 1'b0;
                if (ptst_ph == 6'd63) ptst_done <= 1'b1;
            end
        end
    end
    // v3.0 BASE MINIMA: beeper de diagnostico DESARMADO (el PSG quedo absuelto
    // en la ronda 9; el FSM queda arriba por si hiciera falta re-armarlo).
    wire ptst_active = 1'b0;
    // wire ptst_active = (psgtest_win && !ptst_done) || (!psgtest_win && !ptst_done && ptst_idx == 3'd4);

    wire [7:0] psg1_a, psg1_b, psg1_c;   // ZYNQ 23/09: amplitud por canal (estereo del PSG)
    YM2149 psg1 (
        .I_DA(ptst_active ? ptst_da : cpu_dout),
        .O_DA(psg_dout),        // 31/10: los registros 0-13 se leen por A2h (VGMPlay comprueba asi que hay PSG interno)
        .O_DA_OE_L(),
        .I_A9_L(0),
        .I_A8(1),
        .I_BDIR(ptst_active ? ptst_bdir : psgBdir),
        .I_BC2(1),
        .I_BC1(ptst_active ? ptst_bc1 : psgBc1),
        .I_SEL_L(1),
        .O_AUDIO(psgSound1), .O_AUDIO_A(psg1_a), .O_AUDIO_B(psg1_b), .O_AUDIO_C(psg1_c),
        .I_IOA(psgPA),
        .O_IOA(),
        .O_IOA_OE_L(),
        .I_IOB(psgPB),
        .O_IOB(psgPB),
        .O_IOB_OE_L(),
        
        .ENA(clk_enable_1m8), // clock enable for higher speed operation
        .RESET_L(bus_reset_n),
        .CLK(clk_54m),        // v2.4: PSG en 54M (bus mismo dominio)
        .clkHigh(clk_54m),
        .debug ()
    );

    // ZYNQ 23/09: ESTEREO POR CANALES DEL PSG (A izquierda, B centro, C derecha), como las modificaciones de
    // estereo del PSG. Izquierda (2A+B)/4, derecha (2C+B)/4 (0..191): la SUMA de los dos lados es la mezcla de
    // siempre (A+B+C)/2, asi que en mono suena igual. Un filtro por lado.
    wire [9:0] psg1_l10 = {1'b0, psg1_a, 1'b0} + {2'b00, psg1_b};
    wire [9:0] psg1_r10 = {1'b0, psg1_c, 1'b0} + {2'b00, psg1_b};
    wire [7:0] psg1_lf, psg1_rf;
    psg_filter filter1l (.clk_27m(clk_27m), .reset(~bus_reset_n), .data_in(psg1_l10[9:2]), .data_out(psg1_lf));
    psg_filter filter1r (.clk_27m(clk_27m), .reset(~bus_reset_n), .data_in(psg1_r10[9:2]), .data_out(psg1_rf));

    // ===== Second PSG (OCM 2nd-gen standard): I/O 10h=latch, 11h=write, 12h=read =====
    wire psg2Bdir;
    wire psg2Bc1;
    assign psg2Bdir = ( bus_addr[7:2] == 6'b000100 && iorq_wr_n == 0 && bus_addr[1] == 0 ) ? 1 : 0;
    assign psg2Bc1  = ( bus_addr[7:2] == 6'b000100 && ((iorq_rd_n == 0 && bus_addr[1] == 1) || (bus_addr[1] == 0 && iorq_wr_n == 0 && bus_addr[0] == 0)) ) ? 1 : 0;

    wire [7:0] psg2Sound1;
    wire [7:0] psg2_dout;

    wire [7:0] psg2_a, psg2_b, psg2_c;   // ZYNQ 23/09: amplitud por canal (estereo del PSG)
    YM2149 psg2 (
        .I_DA(cpu_dout),
        .O_DA(psg2_dout),
        .O_DA_OE_L(),
        .I_A9_L(0),
        .I_A8(1),
        .I_BDIR(psg2Bdir),
        .I_BC2(1),
        .I_BC1(psg2Bc1),
        .I_SEL_L(1),
        .O_AUDIO(psg2Sound1), .O_AUDIO_A(psg2_a), .O_AUDIO_B(psg2_b), .O_AUDIO_C(psg2_c),
        .I_IOA(8'hff),
        .O_IOA(),
        .O_IOA_OE_L(),
        .I_IOB(8'hff),
        .O_IOB(),
        .O_IOB_OE_L(),

        .ENA(clk_enable_1m8),
        .RESET_L(bus_reset_n),
        .CLK(clk_54m),        // v2.4: PSG en 54M
        .clkHigh(clk_54m),
        .debug ()
    );

    wire [9:0] psg2_l10 = {1'b0, psg2_a, 1'b0} + {2'b00, psg2_b};      // ZYNQ 23/09: igual que el PSG1
    wire [9:0] psg2_r10 = {1'b0, psg2_c, 1'b0} + {2'b00, psg2_b};
    wire [7:0] psg2_lf, psg2_rf;
    psg_filter filter2l (.clk_27m(clk_27m), .reset(~bus_reset_n), .data_in(psg2_l10[9:2]), .data_out(psg2_lf));
    psg_filter filter2r (.clk_27m(clk_27m), .reset(~bus_reset_n), .data_in(psg2_r10[9:2]), .data_out(psg2_rf));

    // PSG2 register read-back at port 12h (detection by players/trackers)
    wire psg2_req_r;
    assign psg2_req_r = ( bus_addr[7:0] == 8'h12 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0 ) ? 1 : 0;

    //opll
    wire opll_req_n; 
    wire [9:0] opll_mo;
    wire [9:0] opll_ro;
    reg [11:0] opll_mix;
    wire [15:0] jt2413_wav;
    wire [15:0] jt2413_wav_l, jt2413_wav_r;     // 23/09/2026: estereo por canales (IKAOPLL: l + r = mono)

    // _108: BUS REGISTRADO (medicina _95, patron y54_*): el jt2413 decodificaba
    // el bus CRUDO del T80 (flanco de bajada) y rotaba como perdedor de la
    // loteria de placement (p0r0: -0.269 en cpu1/WR_n -> opll/u_mmr). Flop del
    // bus = cono trivial; el strobe de escritura del Z80 dura cientos de ns.
    reg        o54_iorq_n, o54_wr_n;
    reg        o54_a0;
    reg [6:0]  o54_adr71;
    reg [7:0]  o54_din;
    reg        o54_allow = 1'b1;                       // TR: la puerta de separacion del OPLL deja ver el strobe al chip
    always @(posedge clk_54m) begin
        o54_iorq_n <= bus_iorq_n;
        o54_wr_n   <= bus_wr_n;
        o54_a0     <= bus_addr[0];
        o54_adr71  <= bus_addr[7:1];
        o54_din    <= cpu_dout;
`ifdef ENABLE_TR
        o54_allow  <= tr_op_allow;
`endif
    end
    assign opll_req_n = ( o54_iorq_n == 1'b0 && o54_adr71 == 7'b0111110  &&  o54_wr_n == 1'b0 && o54_allow )  ? 1'b0 : 1'b1;    // I/O:7C-7Dh   / OPLL (YM2413)

`ifdef ENABLE_OPLL
    // 23/09/2026: el OPLL es IKAOPLL (Raki, github.com/ika-musume/IKAOPLL, BSD-2; fpga/ikaopll), reconstruido
    // de las fotos del dado y con el registro de test (0Fh): el PCM por el F-number de kokoro.rom solo suena
    // asi (jt2413 ignora el 0Fh y tocaba un tono). opll_ikaopll tiene la MISMA interfaz que jt2413 y su
    // nivel esta calibrado contra el en simulacion. `define OPLL_JT2413 vuelve al de antes.
    // (El nombre jt2413_wav se queda: lo usa todo el mezclador.)
  `ifdef OPLL_JT2413
    jt2413 opll(
  `else
    opll_ikaopll opll(
  `endif
        .rst (~bus_reset_n),        // rst should be at least 6 clk&cen cycles long
        .clk (clk_54m),        // F3/_38: OPLL a 54M+cen (patron smstang con el MISMO chip:
        .cen (clk_enable_3m6_54),   //  bus mismo-dominio y fuera del arbol 27M — su carga
                                    //  re-sorteaba el hold de la paleta del VDP)
        .din (o54_din),
        .addr (o54_a0),
        .cs_n (opll_req_n),
        .wr_n (1'b0),
        // combined output
        .snd (jt2413_wav),
        .sample   ( )
  `ifndef OPLL_JT2413
        , .snd_l (jt2413_wav_l),    // 23/09: canales 1/4/7 3/4 izq, 2/5/8 3/4 der, 3/6/9 centro;
          .snd_r (jt2413_wav_r)     //  ritmo al centro salvo charles (der) y platillo (izq)
  `endif
    );
  `ifdef OPLL_JT2413
    assign jt2413_wav_l = {jt2413_wav[15], jt2413_wav[15:1]};  // jt2413: al centro, la mitad a cada lado
    assign jt2413_wav_r = {jt2413_wav[15], jt2413_wav[15:1]};
  `endif
`else
    assign jt2413_wav = 16'd0;      // BASE MINIMA v3.0: OPLL fuera
    assign jt2413_wav_l = 16'd0;
    assign jt2413_wav_r = 16'd0;
`endif

    // ===== Y8950 (MSX-Audio) — FM primero via jtopl2 (F2/_79) =====
    // Puertos I/O C0h/C1h (unidad primaria): C0=registro/status, C1=dato.
    // Mismo patron de escritura que el OPLL (write = !cs_n && !wr_n, con wr_n=0
    // y cs_n = strobe de escritura). dout de jtopl es COMBINACIONAL (byte de
    // status: IRQ/timer1/timer2) — se rutea al bus en lecturas de C0/C1, que es
    // lo que la deteccion y los replayers de MSX-Audio necesitan. ADPCM-B en un
    // build posterior (jt10_adpcmb + RAM de samples).
    wire        y8950_req_n;
    wire        y8950_rd_r;
    wire [7:0]  y8950_dout;
    wire [15:0] y8950_wav;
    wire [15:0] y8950_wav_l, y8950_wav_r;       // 23/09/2026: FM del Y8950 por canales (jtopl_acc: l + r = mono)
    wire        y8950_int_n;   // _81: hacia el /INT del Z80 (wired-AND)
    wire        opl4_int_n;    // _108: timer OPL4 -> /INT (VGMPlay/MBWave)
    // _95: BUS REGISTRADO (patron _91) para el jtopl2 — el T80 lanza en el
    // flanco de BAJADA de clk_54m y el decode al de subida deja 9.26ns menos
    // el cono: este camino (IORQ->u_mmr/value_*) rotaba como perdedor de la
    // loteria de placement (p0r1: -0.384). Flop directo del bus = cono
    // trivial que SI cierra; el decode pasa a tener ciclo completo. El
    // strobe de escritura del Z80 dura cientos de ns: +18.5ns es nada.
    // (Las strobes del glue ADPCM de abajo ya iban doble-registradas.)
    reg        y54_iorq_n, y54_wr_n;
    reg [1:0]  y54_addr;               // A[1:0] basta: decode C0-C1 + addr[0]
    reg        y54_adr_c0c1;           // A[7:1]==1100000 registrado
    reg [7:0]  y54_din;
    always @(posedge clk_54m) begin
        y54_iorq_n  <= bus_iorq_n;
        y54_wr_n    <= bus_wr_n;
        y54_addr    <= bus_addr[1:0];
        y54_adr_c0c1<= (bus_addr[7:1] == 7'b1100000);
        y54_din     <= cpu_dout;
    end
    assign y8950_req_n = ( y54_iorq_n == 1'b0 && y54_adr_c0c1 && y54_wr_n == 1'b0 ) ? 1'b0 : 1'b1;   // I/O:C0-C1h escritura
    assign y8950_rd_r  = ( bus_iorq_n == 1'b0 && bus_addr[7:1] == 7'b1100000 && bus_rd_n == 1'b0 ) ? 1'b1 : 1'b0;   // I/O:C0-C1h lectura (status/dato)

`ifdef ENABLE_Y8950
    wire [7:0] jtopl2_dout;          // status del jtopl: {~irq_n, ft1, ft2, 5'd6}
    jtopl2 y8950(
        .rst  (~bus_reset_n),        // rst >= 6 ciclos clk&cen
        .clk  (clk_54m),             // mismo dominio que el OPLL
        .cen  (clk_enable_3m6_54),   // FM 3.58 MHz (identico al OPLL)
        .din  (y54_din),             // _95: bus registrado (coherente con cs_n)
        .addr (y54_addr[0]),         // 0=registro (C0), 1=dato (C1)
        .cs_n (y8950_req_n),         // strobe de escritura (patron OPLL)
        .wr_n (1'b0),
        .dout (jtopl2_dout),
        .irq_n( ),
        // combined output
        .snd  (y8950_wav),
        .sample ( ),
        .snd_l (y8950_wav_l),       // 23/09: canales 1/4/7 3/4 izq, 2/5/8 3/4 der, 3/6/9 centro;
        .snd_r (y8950_wav_r)        //  ritmo: charles der, platillo izq, el resto al centro
    );

`ifdef ENABLE_Y8950_ADPCM
    // ===== ADPCM-B (_80): glue openMSX-exacto + decoder jt10 + 32KB BSRAM =====
    // Strobes de 1 ciclo (54M) con doble registro: el dato del Z80 lleva ya
    // decenas de ns estable cuando dispara el flanco detectado en d1&~d2.
    reg  y8950_wr_d1, y8950_wr_d2, y8950_rdc1_d1, y8950_rdc1_d2;
    wire y8950_wr_any = (bus_iorq_n == 1'b0 && bus_addr[7:1] == 7'b1100000 && bus_wr_n == 1'b0);
    wire y8950_rdc1_any = (bus_iorq_n == 1'b0 && bus_addr[7:0] == 8'hC1 && bus_rd_n == 1'b0 && bus_m1_n == 1'b1);
    always @(posedge clk_54m) begin
        y8950_wr_d1   <= y8950_wr_any;   y8950_wr_d2   <= y8950_wr_d1;
        y8950_rdc1_d1 <= y8950_rdc1_any; y8950_rdc1_d2 <= y8950_rdc1_d1;
    end
    wire y8950_wrc0_stb = y8950_wr_d1 & ~y8950_wr_d2 & ~bus_addr[0];
    wire y8950_wrc1_stb = y8950_wr_d1 & ~y8950_wr_d2 &  bus_addr[0];
    wire y8950_rdc1_stb = y8950_rdc1_d1 & ~y8950_rdc1_d2;

    wire [7:0] y8950_status_c0;
    wire [7:0] y8950_data_c1;
    wire signed [15:0] y8950_adpcm_wav;
    wire y8950_irq_w;

    // _159: puerto de la RAM de muestras (256KB fuera del chip)
    wire        adpcm_mem_req_t, adpcm_mem_we, adpcm_mem_done_t;
    wire [17:0] adpcm_mem_addr;
    wire [7:0]  adpcm_mem_wdata;
    wire [15:0] adpcm_mem_rword;
    wire [7:0]  adpcm_mem_diag;      // {wq_lost, wd_hits} — salud del camino

    y8950_adpcm uadpcm(
        .clk       (clk_54m),
        .cen3m6    (clk_enable_3m6_54),
        .rst_n     (bus_reset_n),
        .wr_c0     (y8950_wrc0_stb),
        .wr_c1     (y8950_wrc1_stb),
        .rd_c1     (y8950_rdc1_stb),
        .din       (cpu_dout),
        .ft1       (jtopl2_dout[6]),
        .ft2       (jtopl2_dout[5]),
        .status    (y8950_status_c0),
        .data_dout (y8950_data_c1),
        .irq       (y8950_irq_w),        // flags visibles (ya enmascarados)
        .pcm_out   (y8950_adpcm_wav),
        .mem_req_t (adpcm_mem_req_t),
        .mem_we    (adpcm_mem_we),
        .mem_addr  (adpcm_mem_addr),
        .mem_wdata (adpcm_mem_wdata),
        .mem_rword (adpcm_mem_rword),
        .mem_done_t(adpcm_mem_done_t),
        .mem_diag  (adpcm_mem_diag)
    );

    // _159: las muestras viven en la SDRAM (puerto wv2, filas 5120+). Con el
    // wv2 ocupado (linea de respaldo _137) el shim cae a los 32KB de BSRAM
    // de siempre — misma interfaz, cero cambios en el modulo de arriba.
`ifdef ENABLE_ADPCM_SDRAM
    adpcm_sdram #(.FALLBACK_BSRAM(0)) uadpcmmem (
        .clk_host   (clk_54m),
        .rst_n      (bus_reset_n),
        .req_toggle (adpcm_mem_req_t),
        .we         (adpcm_mem_we),
        .addr       (adpcm_mem_addr),
        .wdata      (adpcm_mem_wdata),
        .rword      (adpcm_mem_rword),
        .done_toggle(adpcm_mem_done_t),
        .clk_108m   (clk_108m),
        .wv_req     (wv2_req),
        .wv_we      (wv2_we),
        .wv_addr    (wv2_addr),
        .wv_wdata   (wv2_wdata),
        .wv_dout    (wv2_dout),
        .wv_done    (wv2_done)
    );
`else
    adpcm_sdram #(.FALLBACK_BSRAM(1)) uadpcmmem (
        .clk_host   (clk_54m),
        .rst_n      (bus_reset_n),
        .req_toggle (adpcm_mem_req_t),
        .we         (adpcm_mem_we),
        .addr       (adpcm_mem_addr),
        .wdata      (adpcm_mem_wdata),
        .rword      (adpcm_mem_rword),
        .done_toggle(adpcm_mem_done_t),
        .clk_108m   (clk_108m),
        .wv_req     ( ),
        .wv_we      ( ),
        .wv_addr    ( ),
        .wv_wdata   ( ),
        .wv_dout    (16'd0),
        .wv_done    (1'b0)
    );
`endif
    // C0 = status compuesto (timers+EOS+BUF_RDY+PCM_BSY); C1 = puerto de datos
    assign y8950_dout = bus_addr[0] ? y8950_data_c1 : y8950_status_c0;
    // _81: al /INT del Z80 como en el Music Module real (activo-bajo). La
    // mascara del reg 4 arranca toda tapada -> ni una IRQ hasta que el
    // software la pida explicitamente.
  `ifdef ENABLE_Y8950_IRQ
    assign y8950_int_n = ~y8950_irq_w;
  `else
    assign y8950_int_n = 1'b1;
  `endif
`else
    wire signed [15:0] y8950_adpcm_wav = 16'sd0;
    assign y8950_dout = jtopl2_dout;     // _79: status del jtopl en C0/C1
    assign y8950_int_n = 1'b1;
`endif

`else
    assign y8950_wav  = 16'd0;
    assign y8950_wav_l = 16'd0;
    assign y8950_wav_r = 16'd0;
    assign y8950_dout = 8'hFF;
    wire signed [15:0] y8950_adpcm_wav = 16'sd0;
    assign y8950_int_n = 1'b1;
`endif

    // ===== DDR3 wave memory (_86): bring-up + puerto debug 34h-37h =====
    // 34h=addr[7:0] 35h=addr[15:8] 36h=addr[21:16] (write dispara prefetch)
    // 37h: OUT=escribir byte (autoinc al completar) / IN=byte prefetchado
    //      (y dispara prefetch de addr+1 — patron readData del ADPCM)
    // IN 36h = status {6'b0, busy, ready}
    wire        wdbg_rd34_w;             // _95: IN 34h = diag DDR3
    wire        wdbg_rd35_w;             // _95: IN 35h = diag motor
    wire        wdbg_rd36_w;
    wire        wdbg_rd37_w;
    wire [7:0]  wdbg_status;
    wire [7:0]  wdbg_rdata;
    wire [7:0]  wdbg_diag_ddr3;          // {calib_drop, wd_fires[2:0], wd_ops[3:0]}
    wire [7:0]  wdbg_diag_eng;           // {ifw_hits[3:0], alive[3:0]}
    // _95: los weng_* van declarados AQUI, ANTES de la instancia que los usa
    // (Gowin declara implicitos de 1 bit si no — leccion EX3638).
    wire        weng_req, weng_we, weng_done;
    wire [21:0] weng_addr;
    wire [7:0]  weng_wdata, weng_rdata;
    wire [15:0] weng_rword;              // _104: palabra (cache de palabra)
    // _104: reloj del motor = clk_wave375 (37.5MHz, CLKOUT4 del PLLA — misma
    // familia/VCO que 54/108: paths sincronos cronometrados, cero CDC).
    // Margen del CE: 37.5/33.8688 = 10.7% (a 36MHz el credito crecia sin
    // freno en la sim de 7 slots: los stalls superaban el 6.3% de margen).
    // ==== ZYNQ: memoria de ondas del OPL4 en la DDR del PS (zynq/wave_axi.v, S_AXI_GP0 @ clk_wave375) ====
    // Sustituye a wave_sdram (Tang). Sin loader ni puerto 34-37h: la YRW801 (2 MB) la carga
    // boot.tcl / BOOT.bin en WAVE_BASE antes de soltar MSX_RUN, y los 2 MB siguientes son la
    // RAM de muestras; por eso wdbg_ready y wl_done son constantes 1 (opl4pcm_rst_n = bus_reset_n).
    wire        wdbg_ready = 1'b1;
    wire        wl_done    = 1'b1;
    wire [7:0]  wave_diag;            // {err_resp, 3'b0, ops[3:0]} (el 34h del Tang, aqui solo interno)
    reg  [1:0]  rst375_s = 2'b00;
    always @(posedge clk_wave375) rst375_s <= {rst375_s[0], frst0_n};
`ifdef ENABLE_OPL4_WAVE
    wave_axi #(.BASE(32'h0F00_0000)) u_wave_axi (
        .clk(clk_wave375), .aresetn(rst375_s[1]), .eng_rst_n(bus_reset_n),
        .eng_req(weng_req), .eng_we(weng_we), .eng_addr(weng_addr), .eng_wdata(weng_wdata),
        .eng_rdata(weng_rdata), .eng_rword(weng_rword), .eng_done_t(weng_done),
        .diag(wave_diag), .tel(wave_tel),
        .M_AWID(gp0_awid), .M_AWADDR(gp0_awaddr), .M_AWLEN(gp0_awlen), .M_AWSIZE(gp0_awsize),
        .M_AWBURST(gp0_awburst), .M_AWLOCK(gp0_awlock), .M_AWCACHE(gp0_awcache), .M_AWPROT(gp0_awprot),
        .M_AWQOS(gp0_awqos), .M_AWVALID(gp0_awvalid), .M_AWREADY(gp0_awready),
        .M_WID(gp0_wid), .M_WDATA(gp0_wdata), .M_WSTRB(gp0_wstrb), .M_WLAST(gp0_wlast),
        .M_WVALID(gp0_wvalid), .M_WREADY(gp0_wready),
        .M_BID(gp0_bid), .M_BRESP(gp0_bresp), .M_BVALID(gp0_bvalid), .M_BREADY(gp0_bready),
        .M_ARID(gp0_arid), .M_ARADDR(gp0_araddr), .M_ARLEN(gp0_arlen), .M_ARSIZE(gp0_arsize),
        .M_ARBURST(gp0_arburst), .M_ARLOCK(gp0_arlock), .M_ARCACHE(gp0_arcache), .M_ARPROT(gp0_arprot),
        .M_ARQOS(gp0_arqos), .M_ARVALID(gp0_arvalid), .M_ARREADY(gp0_arready),
        .M_RID(gp0_rid), .M_RDATA(gp0_rdata), .M_RRESP(gp0_rresp), .M_RLAST(gp0_rlast),
        .M_RVALID(gp0_rvalid), .M_RREADY(gp0_rready)
    );
    assign wdbg_diag_ddr3 = wave_diag;   // IN 34h: {err_resp, 3'b0, ops[3:0]} del puerto del motor
`else
    // Dual: sin OPL4 no hay memoria de ondas; el S_AXI_GP0 es de bwin_fb (la imagen de B en el frame buffer del V9990)
    assign wave_diag = 8'hFF;
    assign wave_tel = 24'd0;
    assign wdbg_diag_ddr3 = wave_diag;
`ifndef ENABLE_DUAL
    // perfil TR: tampoco hay bwin_fb; el S_AXI_GP0 del PS queda sin maestro (todo en reposo; B y R listas por si acaso)
    assign gp0_awid = 6'd0;  assign gp0_awaddr = 32'd0;  assign gp0_awlen = 4'd0;  assign gp0_awsize = 3'd0;  assign gp0_awburst = 2'd0;
    assign gp0_awlock = 2'd0;  assign gp0_awcache = 4'd0;  assign gp0_awprot = 3'd0;  assign gp0_awqos = 4'd0;  assign gp0_awvalid = 1'b0;
    assign gp0_wid = 6'd0;  assign gp0_wdata = 32'd0;  assign gp0_wstrb = 4'd0;  assign gp0_wlast = 1'b0;  assign gp0_wvalid = 1'b0;
    assign gp0_bready = 1'b1;
    assign gp0_arid = 6'd0;  assign gp0_araddr = 32'd0;  assign gp0_arlen = 4'd0;  assign gp0_arsize = 3'd0;  assign gp0_arburst = 2'd0;
    assign gp0_arlock = 2'd0;  assign gp0_arcache = 4'd0;  assign gp0_arprot = 3'd0;  assign gp0_arqos = 4'd0;  assign gp0_arvalid = 1'b0;
    assign gp0_rready = 1'b1;
`endif
`endif

    // ---- puerto de depuracion 34-37h del Tang (_103) sobre una 2a wave_axi en S_AXI_GP1 @ clk_54m ----
    // opl4test lo usa (test 3: W/R de la memoria de ondas; test 4: lo que lee el motor == lo
    // que hay en la DDR). Mismo protocolo: OUT 34/35/36 = direccion (el 36 dispara prefetch),
    // OUT 37 = escribir byte y autoinc, IN 37 = byte prefetchado + prefetch encadenado de
    // addr+1, IN 36 = {err, 3'b0, done=1, active=0, busy, ready=1}. Sin loader: done=ready=1.
    reg        wdbgb_iorq_n = 1'b1, wdbgb_rd_n = 1'b1, wdbgb_wr_n = 1'b1, wdbgb_m1_n = 1'b1;
    reg [7:0]  wdbgb_addr = 8'd0, wdbgb_din = 8'd0;
    always @(posedge clk_54m) begin
        wdbgb_iorq_n <= bus_iorq_n; wdbgb_rd_n <= bus_rd_n; wdbgb_wr_n <= bus_wr_n; wdbgb_m1_n <= bus_m1_n;
        wdbgb_addr <= bus_addr[7:0]; wdbgb_din <= cpu_dout;
    end
    wire wdbg_sel    = (wdbgb_iorq_n == 1'b0) && (wdbgb_m1_n == 1'b1) && (wdbgb_addr[7:2] == 6'b001101);
    wire wdbg_wr_any = wdbg_sel && (wdbgb_wr_n == 1'b0);
    wire wdbg_rd_any = wdbg_sel && (wdbgb_rd_n == 1'b0);
    assign wdbg_rd34_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b00);
    assign wdbg_rd35_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b01);
    assign wdbg_rd36_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b10);
    assign wdbg_rd37_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b11);
    reg  wdbg_wr_d1 = 1'b0, wdbg_wr_d2 = 1'b0, wdbg_rd37_d1 = 1'b0, wdbg_rd37_d2 = 1'b0;
    always @(posedge clk_54m) begin
        wdbg_wr_d1 <= wdbg_wr_any;  wdbg_wr_d2 <= wdbg_wr_d1;
        wdbg_rd37_d1 <= wdbg_rd37_w; wdbg_rd37_d2 <= wdbg_rd37_d1;
    end
    wire wdbg_wr_stb   = wdbg_wr_d1 & ~wdbg_wr_d2;
    wire wdbg_rd37_stb = ~wdbg_rd37_d1 & wdbg_rd37_d2;   // flanco de BAJADA del IN (_88)
    reg  [21:0] wdbg_addr = 22'd0;
    reg  [7:0]  wdbg_wdata = 8'd0;
    reg         wdbg_req = 1'b0, wdbg_we = 1'b0, wdbg_busy = 1'b0, wdbg_inc_pend = 1'b0, wdbg_done_d = 1'b0;
    wire        wdbg_done_t;
    wire [7:0]  wdbg_diag2;
    assign wdbg_status = {wdbg_diag2[7], 3'b000, 1'b1, 1'b0, wdbg_busy, 1'b1};
    always @(posedge clk_54m) begin
        wdbg_req <= 1'b0;
        wdbg_done_d <= wdbg_done_t;
        if (!bus_reset_n) begin
            wdbg_addr <= 22'd0; wdbg_we <= 1'b0; wdbg_busy <= 1'b0; wdbg_inc_pend <= 1'b0; wdbg_wdata <= 8'd0;
        end else begin
            if (wdbg_busy && (wdbg_done_t != wdbg_done_d)) begin
                wdbg_busy <= 1'b0;
                if (wdbg_inc_pend) begin wdbg_addr <= wdbg_addr + 22'd1; wdbg_inc_pend <= 1'b0; end
            end
            if (wdbg_wr_stb) begin
                case (wdbgb_addr[1:0])
                2'b00: wdbg_addr[7:0]  <= wdbgb_din;
                2'b01: wdbg_addr[15:8] <= wdbgb_din;
                2'b10: begin
                    wdbg_addr[21:16] <= wdbgb_din[5:0];
                    if (!wdbg_busy) begin wdbg_we <= 1'b0; wdbg_req <= 1'b1; wdbg_busy <= 1'b1; end
                end
                2'b11: if (!wdbg_busy) begin
                    wdbg_we <= 1'b1; wdbg_wdata <= wdbgb_din; wdbg_req <= 1'b1; wdbg_busy <= 1'b1; wdbg_inc_pend <= 1'b1;
                end
                endcase
            end else if (wdbg_rd37_stb && !wdbg_busy) begin
                wdbg_addr <= wdbg_addr + 22'd1;
                wdbg_we <= 1'b0; wdbg_req <= 1'b1; wdbg_busy <= 1'b1;
            end
        end
    end
    reg  [1:0]  rst54w_s = 2'b00;
    always @(posedge clk_54m) rst54w_s <= {rst54w_s[0], frst0_n};
`ifndef ENABLE_V9990
    wave_axi #(.BASE(32'h0F00_0000)) u_wave_dbg (
        .clk(clk_54m), .aresetn(rst54w_s[1]), .eng_rst_n(bus_reset_n),
        .eng_req(wdbg_req), .eng_we(wdbg_we), .eng_addr(wdbg_addr), .eng_wdata(wdbg_wdata),
        .eng_rdata(wdbg_rdata), .eng_rword(), .eng_done_t(wdbg_done_t),
        .diag(wdbg_diag2), .tel(),
        .M_AWID(gp1_awid), .M_AWADDR(gp1_awaddr), .M_AWLEN(gp1_awlen), .M_AWSIZE(gp1_awsize),
        .M_AWBURST(gp1_awburst), .M_AWLOCK(gp1_awlock), .M_AWCACHE(gp1_awcache), .M_AWPROT(gp1_awprot),
        .M_AWQOS(gp1_awqos), .M_AWVALID(gp1_awvalid), .M_AWREADY(gp1_awready),
        .M_WID(gp1_wid), .M_WDATA(gp1_wdata), .M_WSTRB(gp1_wstrb), .M_WLAST(gp1_wlast),
        .M_WVALID(gp1_wvalid), .M_WREADY(gp1_wready),
        .M_BID(gp1_bid), .M_BRESP(gp1_bresp), .M_BVALID(gp1_bvalid), .M_BREADY(gp1_bready),
        .M_ARID(gp1_arid), .M_ARADDR(gp1_araddr), .M_ARLEN(gp1_arlen), .M_ARSIZE(gp1_arsize),
        .M_ARBURST(gp1_arburst), .M_ARLOCK(gp1_arlock), .M_ARCACHE(gp1_arcache), .M_ARPROT(gp1_arprot),
        .M_ARQOS(gp1_arqos), .M_ARVALID(gp1_arvalid), .M_ARREADY(gp1_arready),
        .M_RID(gp1_rid), .M_RDATA(gp1_rdata), .M_RRESP(gp1_rresp), .M_RLAST(gp1_rlast),
        .M_RVALID(gp1_rvalid), .M_RREADY(gp1_rready)
    );
`else
    // V9990: el S_AXI_GP1 es de la VRAM del V9990 (u_v9990, mas abajo). El puerto
    // de depuracion 34h-37h de la memoria de ondas se queda sin motor: IN 37h = FFh.
    assign wdbg_rdata  = 8'hFF;
    assign wdbg_done_t = 1'b0;
    assign wdbg_diag2  = 8'h00;
`endif
`ifdef ENABLE_WAVE_DDR3
    // _103: BUS REGISTRADO (regla de oro _91) — este decoder era de la _86,
    // ANTERIOR a la regla, y decodificaba el bus CRUDO del T80 (flanco de
    // bajada): la cadena de prefetch del IN 37h podia ver stbs DOBLES en
    // flancos sucios -> DESLIZAMIENTO de direccion -> el INTEG jamas paso
    // en HW (F2DF estable con TODO lo demas leyendo perfecto) y las sumas
    // 065B/01B9/D187/... eran en parte ESTE artefacto, no (solo) la DDR3.
    reg        wdbgb_iorq_n, wdbgb_rd_n, wdbgb_wr_n, wdbgb_m1_n;
    reg [7:0]  wdbgb_addr, wdbgb_din;
    always @(posedge clk_54m) begin
        wdbgb_iorq_n <= bus_iorq_n;
        wdbgb_rd_n   <= bus_rd_n;
        wdbgb_wr_n   <= bus_wr_n;
        wdbgb_m1_n   <= bus_m1_n;
        wdbgb_addr   <= bus_addr[7:0];
        wdbgb_din    <= cpu_dout;
    end
    wire wdbg_sel    = (wdbgb_iorq_n == 1'b0) && (wdbgb_m1_n == 1'b1) && (wdbgb_addr[7:2] == 6'b001101);
    wire wdbg_wr_any = wdbg_sel && (wdbgb_wr_n == 1'b0);
    wire wdbg_rd_any = wdbg_sel && (wdbgb_rd_n == 1'b0);
    assign wdbg_rd34_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b00);
    assign wdbg_rd35_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b01);
    assign wdbg_rd36_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b10);
    assign wdbg_rd37_w = wdbg_rd_any && (wdbgb_addr[1:0] == 2'b11);

    reg wdbg_wr_d1, wdbg_wr_d2, wdbg_rd37_d1, wdbg_rd37_d2;
    always @(posedge clk_54m) begin
        wdbg_wr_d1   <= wdbg_wr_any;   wdbg_wr_d2   <= wdbg_wr_d1;
        wdbg_rd37_d1 <= wdbg_rd37_w;   wdbg_rd37_d2 <= wdbg_rd37_d1;
    end
    wire wdbg_wr_stb   = wdbg_wr_d1 & ~wdbg_wr_d2;
    // _88: prefetch encadenado en el flanco de BAJADA del IN (RD ya liberado,
    // Z80 ya latcheo). Con el flanco de subida la DDR3 actualizaba rdata ANTES
    // de que el Z80 latchease -> leia siempre 1 byte por delante (DIAG A/B del
    // HW: read(i)=write(i+1)). Las escrituras no tienen esta carrera.
    wire wdbg_rd37_stb = ~wdbg_rd37_d1 & wdbg_rd37_d2;

    reg  [21:0] wdbg_addr;
    reg         wdbg_req, wdbg_we, wdbg_inc_pend, wdbg_busy_d;
    reg  [7:0]  wdbg_wdata;
    wire        wdbg_done, wdbg_ready;
    wire        wdbg_busy = (wdbg_req != wdbg_done);

    // ---- _87: loader YRW801 flash(0x500000, 2MB) -> DDR3 en background ----
    reg         wl_active, wl_done, wl_primed;
    reg  [3:0]  wl_state;      // _100: 4 bits (estados de verificacion)
    reg  [23:0] wl_flash_addr;
    reg  [21:0] wl_count;
    reg         wl_flash_rd, wl_flash_term;
    reg  [21:0] wl_tcnt;       // _90: timeout del cierre; _95: 22 bits — el
                               // bit6 sigue siendo el timeout corto (64c) y
                               // el bit21 es el duro (~39ms) de los estados
    reg  [2:0]  wl_retries;    // _95/_100: intentos copia+verify
    reg         wl_err;        // _95: pegajoso — reintentos agotados
    // _100: VERIFICACION flash-vs-DDR3 — el MAL-FIJO por arranque (sumas
    // 065B/01B9/D187 estables dentro del boot, distintas entre boots) es el
    // OJO de la calibracion DDR3: cada calibracion aterriza distinto y a
    // veces corrompe fijo. Tras copiar, se re-streamea la flash (verdad
    // absoluta) comparando byte a byte contra la DDR3; si hay errores ->
    // recalibracion FORZADA + recopia (hasta 3 intentos). Resultados en la
    // PROPIA DDR3 @0x3FFFF8 (el ROM los imprime): V,intento,verr16,addr24,A5
    reg         wl_verify;     // 0=copiando, 1=verificando
    reg  [15:0] wl_verr;       // errores del verify (saturante)
    reg  [21:0] wl_vfirst;     // direccion del PRIMER error (sentinel=3FFFFF)
    reg  [2:0]  wl_vres_i;     // indice de escritura del bloque de resultados
    reg  [7:0]  wl_fb;         // byte de flash en comparacion
    reg         wl_recal_tgl;  // toggle -> wave_ddr3.recal_req
    // _101: SONDEO RAPIDO — la loteria del ojo dio ~1 bueno de 10 en HW;
    // verificar 2MB por billete (~5s) era demasiado caro. Ahora cada billete
    // se sondea con 64KB (copia+verify ~0.3s) y SOLO con sondeo limpio se
    // hace la copia+verificacion completa. Hasta 24 billetes; recal profunda
    // (PLL incluido) + retardo LFSR entre billetes para decorrelar.
    reg         wl_probe;      // 1=pasada de sondeo (64KB), 0=pasada completa
    reg  [4:0]  wl_att;        // billetes gastados (el acta lo publica)
    // _103: RECAL EN CALIENTE — la calibracion ocurre en t=0, el momento MAS
    // frio que existira jamas; el die sube 20-30C en los primeros 30-60s y
    // el ojo calibrado-en-frio queda desfasado (evidencia HW: fallo identico
    // desde la 1a vuelta y estable tras calentar = ojo rancio estable, no
    // deriva continua). A los 60s de terminar la carga, UNA recalibracion
    // completa con el die ya a temperatura de regimen + recopia + verify.
    reg  [31:0] wl_warm_cnt;
    reg         wl_warm_done;
    reg  [7:0]  wl_lfsr;       // retardo pseudoaleatorio entre billetes
    // _102: LECTURAS FRIAS — la evidencia HW de la _101 (VERIF LIMPIO try=0
    // + INTEG MAL-FIJO en el MISMO arranque, dos veces) demostro que el ojo
    // malo solo corrompe lecturas tras un HUECO de inactividad: el verify
    // leia a ritmo constante (~2us) y aprobaba ojos que el Z80 (pausas) y
    // el motor (rafagas) sufren. Ahora 1 de cada 8 lecturas del verify
    // espera 0-19us antes de disparar: solo aprueban ojos que aguantan
    // lecturas frias — los de los arranques que SONABAN bien.
    reg  [9:0]  wl_gap;        // hueco frio pendiente (ciclos)
    localparam  WL_FLASH_BASE = 24'h500000;
    localparam  WL_LEN        = 22'h200000;   // 2MB
    localparam  WL_PROBE_LEN  = 22'h010000;   // 64KB de sondeo
    localparam  WL_MAX_ATT    = 5'd24;
    localparam  WL_RES_ADDR   = 22'h3FFFF8;   // bloque de resultados en RAM
    // _95: status ampliado — el ROM lo imprime tal cual en el test 3
    assign wdbg_status = {wl_err, wl_retries, wl_done, wl_active, wdbg_busy, wdbg_ready};

    always @(posedge clk_54m or negedge bus_reset_n) begin
        if (!bus_reset_n) begin
            wdbg_addr <= 22'd0; wdbg_req <= 1'b0; wdbg_we <= 1'b0;
            wdbg_wdata <= 8'd0; wdbg_inc_pend <= 1'b0; wdbg_busy_d <= 1'b0;
            wl_active <= 1'b0; wl_done <= 1'b0; wl_primed <= 1'b0;
            wl_state <= 4'd0; wl_flash_addr <= 24'd0; wl_count <= 22'd0;
            wl_flash_rd <= 1'b0; wl_flash_term <= 1'b0; wl_tcnt <= 22'd0;
            wl_retries <= 3'd0; wl_err <= 1'b0;
            wl_verify <= 1'b0; wl_verr <= 16'd0; wl_vfirst <= 22'h3FFFFF;
            wl_vres_i <= 3'd0; wl_fb <= 8'd0; wl_recal_tgl <= 1'b0;
            wl_probe <= 1'b1; wl_att <= 5'd0; wl_lfsr <= 8'hC3;   // _108: semilla nueva = re-tirada de la loteria de placement
            wl_gap <= 10'd0; wl_warm_cnt <= 32'd0;
            wl_warm_done <= 1'b1;   // _104: SDRAM sin calibracion — recal caliente OFF
        end
        else begin
            wdbg_busy_d <= wdbg_busy;
            // autoinc diferido de las ESCRITURAS: al completar el handshake
            // (la direccion debe quedarse quieta mientras la op esta en vuelo)
            if (wdbg_busy_d && !wdbg_busy && wdbg_inc_pend) begin
                wdbg_addr <= wdbg_addr + 22'd1;
                wdbg_inc_pend <= 1'b0;
            end

`ifdef ENABLE_WAVE_LOADER
            // ---- loader en background: protocolo byte a byte del flash
            //      (calcado del stream del pack) + puerto wave reutilizado ----
            // _101: LFSR libre — fase impredecible al muestrearlo en el
            // retardo entre billetes (x^8+x^6+x^5+x^4, maximal)
            wl_lfsr <= {wl_lfsr[6:0], wl_lfsr[7]^wl_lfsr[5]^wl_lfsr[4]^wl_lfsr[3]};
            case (wl_state)
            4'd0:   // esperar: pack streameado + DDR3 calibrada
                if (flash_idle && wdbg_ready && !wl_done) begin
                    wl_active <= 1'b1;
                    wl_flash_addr <= WL_FLASH_BASE;
                    wl_probe <= 1'b1;                  // _101: sondeo primero
                    wl_count <= WL_PROBE_LEN;
                    wl_primed <= 1'b0;
                    wl_tcnt <= 22'd0;
                    wdbg_addr <= 22'd0;
                    wl_state <= 4'd4;
                end
            3'd4: begin // _90: CERRAR el stream rancio del pack ANTES de leer.
                // El FSM del pack pone su terminate en el MISMO ciclo en que
                // wl_active le roba el mux: el terminate se perdia, el stream
                // del pack quedaba ABIERTO y nuestras lecturas continuaban en
                // 0x480006 (zona borrada = FF) en vez de abrir en 0x500000.
                // La YRW801 acababa copiada desplazada +0x7FFFA. Bug desde la
                // _87, enmascarado porque la zona siempre habia estado vacia.
                //
                // _95: cierre INCONDICIONAL — term alto 256 ciclos seguidos
                // (mas que cualquier byte SPI en vuelo, ~35c) y SIN interpretar
                // busy. La version _90-_94 tomaba "busy=1" como "se esta
                // cerrando", pero busy tambien es 1 en mitad de un byte: en
                // esa carrera soltaba el term, el stream quedaba ABIERTO y la
                // copia salia de la direccion equivocada (= FF si era la cola
                // del pack). El flash atiende terminate solo en WAIT_NEXT
                // (entre bytes) y lo ignora cerrado: sujetarlo 256c cubre
                // abierto-parado, en-mitad-de-byte y ya-cerrado por igual.
                wl_flash_term <= 1'b1;
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[8]) begin
                    wl_flash_term <= 1'b0;
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd5;
                end
            end
            4'd5: begin // esperar el reposo del flash (LOAD_CMD: busy=0, CS alto)
                wl_tcnt <= wl_tcnt + 22'd1;
                if (!flash_busy) begin
                    wl_tcnt <= 22'd0;
                    wl_state <= wl_verify ? 4'd9 : 4'd1;  // _100: 2a pasada = verify
                end
                else if (wl_tcnt[21]) begin    // _95: cierre que no acaba (~39ms)
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd6;
                end
            end
            4'd1: begin // bucle: capturar byte y escribirlo en DDR3
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[21]) begin         // _95: ~39ms sin aceptar un byte
                    wl_tcnt <= 22'd0;          // — sea lo que sea, reintentar
                    wl_state <= 4'd6;          // la copia entera desde cero
                end
                else if (flash_busy == 1'b0) begin
                    if (~wl_flash_rd) begin
                        if (!flash_write_busy && !wdbg_busy) begin
                            if (wl_primed) begin
                                wdbg_wdata <= flash_dout;   // byte de la lectura previa
                                wdbg_we <= 1'b1;
                                wdbg_req <= ~wdbg_req;
                                wdbg_inc_pend <= 1'b1;      // autoinc al completar
                            end
                            if (wl_count == 22'd0) begin
                                wl_tcnt <= 22'd0;
                                wl_state <= 4'd2;
                            end
                            else begin
                                // _90: NO incrementar antes de la 1a lectura — la
                                // flash latchea addr con el PRIMER rd (off-by-one:
                                // el stream abria en BASE+1)
                                if (wl_primed) wl_flash_addr <= wl_flash_addr + 24'd1;
                                wl_count <= wl_count - 22'd1;
                                wl_flash_rd <= 1'b1;
                                wl_primed <= 1'b1;
                                wl_tcnt <= 22'd0;           // _95: hay progreso
                            end
                        end
                    end
                end
                else wl_flash_rd <= 1'b0;
            end
            4'd2: begin // cerrar el stream del flash
                wl_flash_term <= 1'b1;
                wl_tcnt <= wl_tcnt + 22'd1;
                // _95: el timeout garantiza avanzar SIEMPRE — el reset del
                // motor (opl4pcm_rst_n) depende de wl_done
                if (!wdbg_busy || wl_tcnt[21]) begin
                    wl_flash_term <= 1'b0;
                    wl_tcnt <= 22'd0;
                    if (!wl_verify) begin
                        // _100: copia hecha -> pasada de VERIFICACION
                        wl_verify <= 1'b1;
                        wl_flash_addr <= WL_FLASH_BASE;
                        wl_count <= wl_probe ? WL_PROBE_LEN : WL_LEN;
                        wl_primed <= 1'b0;
                        wdbg_addr <= 22'd0;
                        wl_verr <= 16'd0;
                        wl_vfirst <= 22'h3FFFFF;
                        wl_state <= 4'd4;      // cerrar + reabrir en BASE
                    end
                    else wl_state <= 4'd12;    // verify cerrado -> decidir
                end
            end
            // ---- _100: VERIFY — flash (verdad) vs DDR3 (copia), byte a byte
            4'd9: begin // pedir el siguiente byte de flash (o terminar)
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[21]) begin wl_tcnt <= 22'd0; wl_state <= 4'd6; end
                else if (!flash_busy && !wl_flash_rd && !flash_write_busy) begin
                    if (wl_count == 22'd0) begin
                        wdbg_addr <= WL_RES_ADDR;   // resultados a la RAM alta
                        wl_vres_i <= 3'd0;
                        wl_tcnt <= 22'd0;
                        wl_state <= 4'd11;
                    end
                    else begin
                        if (wl_primed) wl_flash_addr <= wl_flash_addr + 24'd1;
                        wl_count <= wl_count - 22'd1;
                        wl_flash_rd <= 1'b1;
                        wl_primed <= 1'b1;
                        wl_tcnt <= 22'd0;
                        wl_state <= 4'd13;
                    end
                end
            end
            4'd13: begin // esperar el byte de flash -> lanzar lectura DDR3
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[21]) begin wl_tcnt <= 22'd0; wl_state <= 4'd6; end
                else if (flash_busy) wl_flash_rd <= 1'b0;
                else if (!wl_flash_rd) begin
                    wl_fb <= flash_dout;
                    if (wl_lfsr[2:0] == 3'b000) begin
                        // _102: lectura FRIA — hueco 0-19us antes de leer
                        wl_gap <= {wl_lfsr[7:2], 4'd0};
                        wl_tcnt <= 22'd0;
                        wl_state <= 4'd8;
                    end
                    else begin
                        wdbg_we <= 1'b0;
                        wdbg_req <= ~wdbg_req;  // lectura DDR3 en wdbg_addr
                        wl_tcnt <= 22'd0;
                        wl_state <= 4'd10;
                    end
                end
            end
            4'd8: begin // _102: hueco frio y despues la lectura
                if (wl_gap == 10'd0) begin
                    wdbg_we <= 1'b0;
                    wdbg_req <= ~wdbg_req;
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd10;
                end
                else wl_gap <= wl_gap - 10'd1;
            end
            4'd10: begin // esperar DDR3 y comparar
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[21]) begin wl_tcnt <= 22'd0; wl_state <= 4'd6; end
                else if (!wdbg_busy) begin
                    if (wdbg_rdata != wl_fb) begin
                        if (wl_verr != 16'hFFFF) wl_verr <= wl_verr + 16'd1;
                        if (wl_vfirst == 22'h3FFFFF) wl_vfirst <= wdbg_addr;
                    end
                    wdbg_addr <= wdbg_addr + 22'd1;
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd9;
                end
            end
            4'd11: begin // volcar el bloque de resultados a DDR3 @3FFFF8
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[21]) begin wl_tcnt <= 22'd0; wl_state <= 4'd12; end
                else if (!wdbg_busy) begin
                    wdbg_we <= 1'b1;
                    wdbg_wdata <= (wl_vres_i == 3'd0) ? 8'h56 :             // 'V'
                                  (wl_vres_i == 3'd1) ? {3'd0, wl_att} :    // billetes
                                  (wl_vres_i == 3'd2) ? wl_verr[7:0] :
                                  (wl_vres_i == 3'd3) ? wl_verr[15:8] :
                                  (wl_vres_i == 3'd4) ? wl_vfirst[7:0] :
                                  (wl_vres_i == 3'd5) ? wl_vfirst[15:8] :
                                  (wl_vres_i == 3'd6) ? {2'd0, wl_vfirst[21:16]} :
                                                        8'hA5;              // fin
                    wdbg_req <= ~wdbg_req;
                    wdbg_inc_pend <= 1'b1;
                    wl_tcnt <= 22'd0;
                    if (wl_vres_i == 3'd7) wl_state <= 4'd2;  // cerrar stream
                    else wl_vres_i <= wl_vres_i + 3'd1;
                end
            end
            4'd12: begin // decidir: limpio, mas billetes, o rendirse
                if (wl_verr == 16'd0) begin
                    if (wl_probe) begin
                        // _101: sondeo limpio -> ahora la copia COMPLETA
                        wl_probe <= 1'b0;
                        wl_verify <= 1'b0;
                        wl_flash_addr <= WL_FLASH_BASE;
                        wl_count <= WL_LEN;
                        wl_primed <= 1'b0;
                        wdbg_addr <= 22'd0;
                        wl_tcnt <= 22'd0;
                        wl_state <= 4'd4;
                    end
                    else begin                 // completa verificada: LIMPIO
                        wl_done   <= 1'b1;
                        wl_active <= 1'b0;
                        wl_state  <= 4'd3;
                    end
                end
                else if (wl_att >= WL_MAX_ATT) begin
                    wl_err    <= 1'b1;         // billetes agotados: sonara
                    wl_done   <= 1'b1;         // como pueda, y el acta lo dice
                    wl_active <= 1'b0;
                    wl_state  <= 4'd3;
                end
                else begin
                    // _100/_101: ojo malo — recal PROFUNDA y otro billete
                    wl_recal_tgl <= ~wl_recal_tgl;
                    wl_att <= wl_att + 5'd1;
                    if (wl_retries != 3'd7) wl_retries <= wl_retries + 3'd1;
                    wl_verify <= 1'b0;
                    wl_probe <= 1'b1;          // el fallo full tambien resondea
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd14;
                end
            end
            4'd14: begin // esperar a que la calibracion CAIGA (PLL+IP en reset)
                wl_tcnt <= wl_tcnt + 22'd1;
                if (!wdbg_ready) begin wl_tcnt <= 22'd0; wl_state <= 4'd15; end
                else if (wl_tcnt[21]) begin    // el pulso no llego: reintenta
                    wl_tcnt <= 22'd0; wl_state <= 4'd15;
                end
            end
            4'd15:  // esperar la calibracion NUEVA (el watchdog insiste solo)
                if (wdbg_ready) begin
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd7;          // _101: retardo decorrelador
                end
            4'd7: begin // _101: retardo LFSR (0.3-4.8ms) antes del sondeo
                wl_tcnt <= wl_tcnt + 22'd1;
                if (wl_tcnt[21:14] >= wl_lfsr) begin
                    wl_flash_addr <= WL_FLASH_BASE;
                    wl_count <= WL_PROBE_LEN;
                    wl_primed <= 1'b0;
                    wdbg_addr <= 22'd0;
                    wl_tcnt <= 22'd0;
                    wl_state <= 4'd4;
                end
            end
            4'd3:   // aparcado — _103: timer de RECAL EN CALIENTE (una vez)
                if (!wl_warm_done) begin
                    wl_warm_cnt <= wl_warm_cnt + 32'd1;
                    if (wl_warm_cnt == 32'd3239760000) begin   // 60s a 54MHz
                        wl_warm_done <= 1'b1;
                        wl_recal_tgl <= ~wl_recal_tgl;
                        wl_err    <= 1'b0;
                        wl_done   <= 1'b0;   // motor mudo durante el redo
                        wl_active <= 1'b1;
                        wl_probe  <= 1'b1;
                        wl_verify <= 1'b0;
                        wl_tcnt   <= 22'd0;
                        wl_state  <= 4'd14;
                    end
                end
            4'd6: begin // _95: REINTENTO — cerrar todo y copiar de cero
                wl_flash_term <= 1'b0;
                wl_flash_rd   <= 1'b0;
                wl_verify     <= 1'b0;         // _100: si venia del verify
                if (!wdbg_busy) begin          // (acotado: el watchdog de op
                    wdbg_inc_pend <= 1'b0;     //  de wave_ddr3 lo garantiza)
                    if (wl_retries == 3'd7) begin
                        wl_err    <= 1'b1;     // agotado: rendirse PERO soltar
                        wl_done   <= 1'b1;     // el motor igualmente
                        wl_active <= 1'b0;
                        wl_state  <= 4'd3;
                    end
                    else begin
                        wl_retries <= wl_retries + 3'd1;
                        wl_flash_addr <= WL_FLASH_BASE;
                        wl_count   <= wl_probe ? WL_PROBE_LEN : WL_LEN;
                        wl_primed  <= 1'b0;
                        wdbg_addr  <= 22'd0;
                        wl_tcnt    <= 22'd0;
                        wl_state   <= 4'd4;
                    end
                end
            end
            default: ;
            endcase
`endif

            if (wdbg_wr_stb && !wl_active) begin
                case (wdbgb_addr[1:0])               // _103: bus registrado
                2'b00: wdbg_addr[7:0]   <= wdbgb_din;
                2'b01: wdbg_addr[15:8]  <= wdbgb_din;
                2'b10: begin
                    wdbg_addr[21:16] <= wdbgb_din[5:0];
`ifdef ENABLE_WAVE_LOADER
                    // _103: OUT 36h con bit7 = RECALIBRAR EN CALIENTE a
                    // demanda (recal profunda + recopia + verify; el motor
                    // queda mudo durante el redo). Para el experimento del
                    // ojo-frio-vs-caliente sin esperar el timer.
                    if (wdbgb_din[7] && wl_done) begin
                        wl_recal_tgl <= ~wl_recal_tgl;
                        wl_err    <= 1'b0;
                        wl_done   <= 1'b0;
                        wl_active <= 1'b1;
                        wl_probe  <= 1'b1;
                        wl_verify <= 1'b0;
                        wl_tcnt   <= 22'd0;
                        wl_state  <= 4'd14;
                    end
`endif
                    if (!wdbg_busy) begin            // prefetch de la nueva dir
                        wdbg_we <= 1'b0;
                        wdbg_req <= ~wdbg_req;
                    end
                end
                2'b11: if (!wdbg_busy) begin         // escribir byte
                    wdbg_we <= 1'b1;
                    wdbg_wdata <= wdbgb_din;
                    wdbg_req <= ~wdbg_req;
                    wdbg_inc_pend <= 1'b1;
                end
                endcase
            end
            else if (wdbg_rd37_stb && !wdbg_busy && !wl_active) begin
                // devolvio el byte prefetchado: encadenar prefetch de addr+1
                wdbg_addr <= wdbg_addr + 22'd1;
                wdbg_we <= 1'b0;
                wdbg_req <= ~wdbg_req;
            end
        end
    end

    // _104: la wave vive en la SDRAM del dock (la DDR3 del SOM resulto
    // analogicamente marginal en esta placa — saga _94-_103). El shim
    // conserva la interfaz del wave_ddr3: el loader wl, el verify y el
    // puerto debug 34-37h funcionan SIN CAMBIOS.
    wave_sdram uwsdram (
        .clk_host   (clk_54m),
        .rst_n      (bus_reset_n),
        .req_toggle (wdbg_req),
        .we         (wdbg_we),
        .addr       (wdbg_addr),
        .wdata      (wdbg_wdata),
        .rdata      (wdbg_rdata),
        .done_toggle(wdbg_done),
        .ready      (wdbg_ready),
        .clk_eng    (clk_wave375),
        .eng_req    (weng_req),
        .eng_we     (weng_we),
        .eng_addr   (weng_addr),
        .eng_wdata  (weng_wdata),
        .eng_rdata  (weng_rdata),
        .eng_rword  (weng_rword),
        .eng_done_t (weng_done),
        .diag       (wdbg_diag_ddr3),
        .clk_108m   (clk_108m),
        .wv_req     (wv_req),
        .wv_we      (wv_we),
        .wv_addr    (wv_addr),
        .wv_wdata   (wv_wdata),
        .wv_dout    (wv_dout),
        .wv_done    (wv_done)
    );

`ifndef ENABLE_VRAM_DDR3
    // pines DDR3 del SOM en reposo seguro (la IP y su PLL fuera del build;
    // con _128X los conduce u_vddr3 — la VRAM del V9968 vive alli)
    assign ddr_addr = 15'd0;  assign ddr_bank = 3'd0;
    assign ddr_cs = 1'b1;     assign ddr_ras = 1'b1;
    assign ddr_cas = 1'b1;    assign ddr_we = 1'b1;
    assign ddr_ck = 1'b0;     assign ddr_ck_n = 1'b1;
    assign ddr_cke = 1'b0;    assign ddr_odt = 1'b0;
    assign ddr_reset_n = 1'b0; assign ddr_dm = 2'b11;
    assign ddr_dq = 16'hzzzz; assign ddr_dqs = 2'bzz; assign ddr_dqs_n = 2'bzz;
`endif
`else
    // ZYNQ: wdbg_* (puerto 34-37h) los conduce el bloque wave_axi/GP1 de arriba
`ifndef ENABLE_VRAM_DDR3
    // DDR3 en reposo seguro (con _128X los pines los conduce u_vddr3)
    assign ddr_addr = 15'd0;  assign ddr_bank = 3'd0;
    assign ddr_cs = 1'b1;     assign ddr_ras = 1'b1;
    assign ddr_cas = 1'b1;    assign ddr_we = 1'b1;
    assign ddr_ck = 1'b0;     assign ddr_ck_n = 1'b1;
    assign ddr_cke = 1'b0;    assign ddr_odt = 1'b0;
    assign ddr_reset_n = 1'b0; assign ddr_dm = 2'b11;
    assign ddr_dq = 16'hzzzz; assign ddr_dqs = 2'bzz; assign ddr_dqs_n = 2'bzz;
`endif
`endif

    // ===== MoonSound FM (_82): OPL3 en C4-C7 + stub wave 7E/7F =====
    wire        opl4fm_rd_w;
    wire        opl4wave_rd_w;
    wire [7:0]  opl4fm_dout;
    wire [7:0]  opl4wave_dout;
    wire signed [15:0] opl4fm_wav;
    wire signed [15:0] opl4fm_wav_l, opl4fm_wav_r;   // 23/09/2026: estereo real del OPL3
`ifdef ENABLE_OPL4FM
    opl4fm uopl4fm (
        .rst_n     (bus_reset_n),
        .clk_host  (clk_54m),
        .clk_opl3  (clk_27m),      // _84: reloj hermano (ver nota arriba)
        .iorq_n    (bus_iorq_n),
        .rd_n      (bus_rd_n),
        .wr_n      (bus_wr_n),
        .m1_n      (bus_m1_n),
        .addr      (bus_addr[7:0]),
        .din       (cpu_dout),
        .wave_status (opl4wave_status),  // _89: {LD,BUSY} del motor en C4/C6
        .fm_rd     (opl4fm_rd_w),
        .wave_rd   (opl4wave_rd_w),
        .dout      (opl4fm_dout),
        .wave_dout (opl4wave_dout),
        .pcm_out   (opl4fm_wav),
        .pcm_out_l (opl4fm_wav_l),  // 23/09/2026: estereo real del OPL3
        .pcm_out_r (opl4fm_wav_r),
        .int_n     (opl4_int_n)
    );
`else
    assign opl4fm_rd_w   = 1'b0;
    assign opl4wave_rd_w = 1'b0;
    assign opl4_int_n    = 1'b1;   // _108: sin OPL4, sin IRQ
    assign opl4fm_dout   = 8'hFF;
    assign opl4wave_dout = 8'hFF;
    assign opl4fm_wav    = 16'sd0;
    assign opl4fm_wav_l  = 16'sd0;
    assign opl4fm_wav_r  = 16'sd0;
`endif

    // ===== MoonSound WAVE (_89): motor PCM 24 slots (srg320) en clk_x1 =====
    // El motor vive en el dominio clk_x1 de la propia DDR3 (74.25MHz) con CE
    // fraccionario 33.8688MHz medio -> 44.1kHz exactos; el fetch de onda va
    // directo al puerto eng_* de wave_ddr3 SIN CDC. Arranca en reset hasta
    // que la DDR3 calibra Y el loader ha copiado la YRW801.
    wire        opl4pcm_rd_w;
    wire [7:0]  opl4pcm_dout;
    wire [1:0]  opl4wave_status;
    wire signed [15:0] opl4pcm_l, opl4pcm_r;
    wire [5:0]  opl4_mixfm;    // _110: reg F8 del motor (via opl4_pcm)
    wire        opl4_dbg_tx;   // _111: telemetria UART (E22)
    // (_104: los weng_* estan declarados arriba, junto al bloque wdbg;
    //  el reloj del motor es clk_wave375 = CLKOUT4 del PLLA)
`ifdef ENABLE_OPL4_WAVE
    wire opl4pcm_rst_n = bus_reset_n & wdbg_ready & wl_done;

    opl4_pcm uopl4pcm (
        .rst_n       (bus_reset_n),
        .clk_host    (clk_54m),
        .iorq_n      (bus_iorq_n),
        .rd_n        (bus_rd_n),
        .wr_n        (bus_wr_n),
        .m1_n        (bus_m1_n),
        .addr        (bus_addr[7:0]),
        .din         (cpu_dout),
        .wave_rd     (opl4pcm_rd_w),
        .wave_dout   (opl4pcm_dout),
        .wave_wait_n (opl4pcm_wait_n),
        .wave_status (opl4wave_status),
        .mix_fm      (opl4_mixfm),
        .dbg_tx      (opl4_dbg_tx),
        .pcm_l       (opl4pcm_l),
        .pcm_r       (opl4pcm_r),
        .clk_eng     (clk_wave375),   // _104: 37.5MHz del PLLA (CLKOUT4)
        .eng_rst_n   (opl4pcm_rst_n),
        .mem_req     (weng_req),
        .mem_we      (weng_we),
        .mem_addr    (weng_addr),
        .mem_wdata   (weng_wdata),
        .mem_rdata   (weng_rdata),
        .mem_rword   (weng_rword),    // _104: palabra (cache de palabra)
        .mem_done_t  (weng_done),
        .diag        (wdbg_diag_eng),
        // _114diag: estado del video a la telemetria (COM11). {pll27_lock,
        // frame_cnt[2:0]} del modo activo; opl4_pcm lo cruza a clk_eng.
        .vid_diag    ({pll27_lock, dbg_video_w[0] ? dbg_fdiv_pal[2:0]
                                                  : dbg_fdiv_ntsc[2:0]})
    );
`else
    assign opl4pcm_rd_w   = 1'b0;
    assign opl4pcm_dout   = 8'hFF;
    assign opl4pcm_wait_n = 1'b1;
    assign opl4wave_status = 2'b00;
    assign opl4pcm_l = 16'sd0;
    assign opl4_mixfm = 6'd0;   // _110: sin motor, FM a 0dB
    assign opl4_dbg_tx = 1'b1;  // _111: sin motor, linea en reposo
    assign opl4pcm_r = 16'sd0;
    assign weng_req = 1'b0;  assign weng_we = 1'b0;
    assign weng_addr = 22'd0; assign weng_wdata = 8'd0;
    assign wdbg_diag_eng = 8'hFF;
`endif

    //scc & ghost scc
    wire [14:0] scc_wav;
    wire [14:0] scc_wav_l, scc_wav_r;       // 23/09/2026: estereo por canales (scc_wave2: wave_l + wave_r = wave)
    wire [7:0] scc_dout;
    wire scc_req;
    wire scc_req3_r;
    wire scc_wrt;
    wire x98h;
    wire xb8h;
    wire scc_rd_r;

    // SCC-I mode signals (from megaram1, declared here as they gate the sound window)
    wire scc_mode_plus;     // BFFE bit5: 1 = SCC+ layout active
    wire sccplus_win_en;    // SCC+ window enabled (mode bit5 + bank3 bit7)

    // Glue de ventana/banco/strobes EXTRAIDO VERBATIM a src/scc_glue.v (fix
    // SCC): mismo fichero compartido con tools/scc_tb, semantica identica al
    // bloque inline v2.6 que habia aqui (solo los terminos de config/slot
    // pasan como entradas). Siempre instanciado, como antes (con ENABLE_SCC
    // off el chip queda fuera pero la ventana sigue respondiendo FF).
    // v3.2 FIX REGRESION _40: los gates se DECLARAN aqui (antes del uso) y se
    // ASIGNAN tras el bloque de config (linea ~2420), donde todas sus señales
    // ya estan declaradas. En la _40 las expresiones iban directamente en los
    // puertos ANTES de las declaraciones y Gowin creaba config_megaram_slot
    // IMPLICITO DE 1 BIT (el real es [1:0]) -> comparacion de slot TRUNCADA ->
    // el SCC respondia en slots equivocados (distorsion al bootear la BIOS,
    // lecturas de CPU secuestradas) y callaba en el suyo (mudo). EX3638 en el
    // log fue el delator; solo es benigno con señales de 1 bit.
    wire scc_gate_bank2_wr3;
    wire scc_gate_bank2_wr12;
    wire scc_gate_req3;
    wire scc_gate_req12;
    wire scc_snd_dis_w;
    wire dbg_scc_enable_w;   // panel _42dbg (declarado ANTES del uso — leccion EX3638)
    wire scc_dbg_vol_nz, scc_dbg_sel_nz, scc_dbg_freq_nz;   // _46dbg (idem)
    wire scc_dbg_ptr_lsb, scc_dbg_scan_lsb, scc_dbg_mix_nz;  // _51dbg (idem)
    wire scc_dbg_wavlatch, scc_dbg_capnz, scc_dbg_wave_nz;   // _52/_53dbg (idem)
    wire scc_dbg_mix5_nz;                                    // _54dbg (idem)
    scc_glue sccglue1 (
        .clk (clk_54m),             // v2.6: glue SCC a 54M (bus mismo dominio)
        .reset_n (bus_reset_n),
        .bus_addr (bus_addr),
        .cpu_dout (cpu_dout),
        .bus_mreq_n (bus_mreq_n),
        .bus_wr_n (bus_wr_n),
        .bus_rd_n (bus_rd_n),
        .gate_bank2_wr3 (scc_gate_bank2_wr3),
        .gate_bank2_wr12 (scc_gate_bank2_wr12),
        .gate_req3 (scc_gate_req3),
        .gate_req12 (scc_gate_req12),
        .scc_mode_plus (scc_mode_plus),
        .sccplus_win_en (sccplus_win_en),
        .scc_sound_disable (scc_snd_dis_w),
        .scc_req (scc_req),
        .scc_wrt (scc_wrt),
        .scc_req3_r (scc_req3_r),
        .scc_rd_r (scc_rd_r),
        .x98h (x98h),
        .xb8h (xb8h),
        .dbg_scc_enable (dbg_scc_enable_w)
    );

`ifdef ENABLE_SCC
    // v3.3 (_43): VUELTA al chip VHDL probado del TN20K con el multiplicador
    // inline (fix del sweep DENTRO de scc_wave2.vhd). El scc_wave2v traducido
    // pasaba la sim pero NO sintetiza sonido en placa (panel _42dbg: LED4
    // apagado = chip sin oscilar, clase sim!=sintesis); queda como referencia
    // y para el TB.
    // (beeper de diagnostico _45-_54 ELIMINADO en la _55 final — historia en git;
    //  fue la herramienta que, con el panel de LEDs, acorralo el bug del silicio)
    scc_wave2 SccCh (
        .clk21m (clk_27m),          // v3.4 (_44): config EXACTA del TN20K (27M+cen27),
        .reset (~bus_reset_n),      //  segura desde v3.0 (27 EN FASE con 54, ya sin CLKDIV
        .clkena (clk_enable_3m6_27),// _50dbg: cen ORIGINAL con el PINFILTER ya sin z (fix de raiz)
        .req ( scc_req),
        .ack (),
        .wrt (scc_wrt),
        .adr (bus_addr[7:0]),
        .dbi (scc_dout),
        .dbo (cpu_dout),
        .wave (scc_wav),
        .wave_l (scc_wav_l),        // 23/09: A 3/4 izq, B 1/4, C centro, D 3/4, E 1/4
        .wave_r (scc_wav_r),
        .pan_mirror (1'b0),
        .sccplus (scc_mode_plus),
        .dbg_vol_nz (scc_dbg_vol_nz),
        .dbg_sel_nz (scc_dbg_sel_nz),
        .dbg_freq_nz (scc_dbg_freq_nz),
        .dbg_ptr_lsb (scc_dbg_ptr_lsb),
        .dbg_scan_lsb (scc_dbg_scan_lsb),
        .dbg_mix_nz (scc_dbg_mix_nz),
        .dbg_wavlatch (scc_dbg_wavlatch),
        .dbg_capnz (scc_dbg_capnz),
        .dbg_wave_nz (scc_dbg_wave_nz),
        .dbg_mix5_nz (scc_dbg_mix5_nz)
    );
`else
    assign scc_wav  = 15'd0;        // BASE MINIMA v3.0: SCC fuera (aparcado)
    assign scc_wav_l = 15'd0;
    assign scc_wav_r = 15'd0;
    assign scc_dout = 8'hFF;
`endif

    reg scc2_req3;
    reg scc2_req12;
    wire scc2_req;
    wire scc2_req_r;
    wire scc2_wrt;
    wire [7:0] scc2_dout;
    wire [14:0] scc2_wav;
    wire megaram_req;
`ifdef ENABLE_TR
    wire megaram_req_raw;
`endif
    wire megaram_wrt;
`ifdef NEO16_16M
    wire [23:0] megaram_addr;   // perfil TR: 16 MB
`else
    wire [22:0] megaram_addr;   // V3.5: 4 MB; 23/09/2026: 8 MB (ASCII16-X)
`endif
    wire megaram_enabled;

    always @ (posedge clk_54m) begin
        // NOTE: config1_ff[2] ("ghost SCC", vestigial in standalone) is repurposed below
        // as the SECOND SCC+ enable; it no longer gates the megaram banking path.
        scc2_req3 <= ( config_enable_megaram3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_megaram_slot && exp_slotx_num[3] == 1  && xffff == 0) ? 1 : 0;
        scc2_req12 <= ( config_enable_megaram12 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_megaram_slot ) ? 1 : 0;
        //scc2_req <= ( bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[2] == 1 ) ? 1 : 0;
    end
    assign scc2_req = scc2_req3 | scc2_req12;
    assign scc2_req_r = ( scc2_req == 1 && bus_rd_n == 0 ) ? 1 : 0;
    assign scc2_wrt = ( scc2_req == 1 && bus_wr_n == 0 ) ? 1 : 0;

    wire [1:0] map_sel;
    wire map_linear;
    wire scc_sound_disable;
    assign map_sel = Slot2Mode;
    assign map_linear = iSlt2_linear;

    megaram_scc megaram1 (
        .clk_27m (clk_54m),
        .bus_reset_n (bus_reset_n),
        .bus_addr (bus_addr),
        .cpu_dout (cpu_dout),
        .bus_rd_n (bus_rd_n),
        .bus_wr_n (bus_wr_n),
        .scc_req (scc2_req),
        .scc_wrt (scc2_wrt),
        .map_sel (map_sel),
        .map_linear (map_linear),
        .sram_cfg (config3_ff),
        .map_ext (config6_ff),          // V3.5: puerto #46 (NEO / mitad alta)

`ifdef ENABLE_TR
        .megaram_req (megaram_req_raw),
`else
        .megaram_req (megaram_req),
`endif
        .megaram_wrt (megaram_wrt),
        .megaram_addr (megaram_addr),
        .scc_sound_disable (scc_sound_disable),
        .scc_mode_plus (scc_mode_plus),
        .sccplus_win_en (sccplus_win_en)
    );


    // ===== Second SCC+ ("sound-only SCC-I cartridge" in the other free slot) =====
    // Enabled by config1_ff[2] (former "ghost SCC" bit, repurposed; menu toggle).
    // Lives in slot 1 if the megaram is in slot 2 and vice versa, so trackers that
    // drive two SCC carts in two slots find both. Own bank2/bank3/mode regs (SCC-I),
    // wave-RAM read-back included; no memory behind it (reads elsewhere return FF).
    wire [1:0] scc2x_slot;
    assign scc2x_slot = ( config_megaram_slot == 2'b01 ) ? 2'b10 : 2'b01;

    reg [7:0] scc2x_bank2;
    reg [7:0] scc2x_bank3;
    reg [7:0] scc2x_modeb;
    wire scc2x_slot_hit;
    // V3.5f: si el Game Master 2 esta armado, el slot 1 es suyo (Ajustes lo hace
    // excluyente con el 2o SCC; esto es el cinturon por si el menu no lo hiciera)
    assign scc2x_slot_hit = ( config_enable_ghost_scc == 1 && pri_slot == scc2x_slot && config6_ff[6] == 0 ) ? 1 : 0;

    // ===== V3.5f: Konami GAME MASTER 2 emulado en el slot 1 (bloque 6) =====
    // Memoria en la mitad alta de la megaram (segs 480-495 ROM, 496 SRAM): el
    // menu la carga con el cargador del bloque 5 y luego arma el bit6 de #46.
    // gm2_req se registra como scc2_req: el decode que cuelga del bus del Z80
    // NO puede ir combinacional a 98% de CLS (leccion de la v3.5d).
    reg gm2_req;
    always @ (posedge clk_54m) begin
        gm2_req <= ( config6_ff[6] == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0) && pri_slot == 2'b01 ) ? 1 : 0;
    end
    wire gm2_mem_req;
    wire gm2_mem_wrt;
    wire [21:0] gm2_addr;
    gm2_slot1 gm2_1 (
        .clk (clk_54m),
        .reset_n (bus_reset_n),
        .bus_addr (bus_addr),
        .cpu_dout (cpu_dout),
        .bus_rd_n (bus_rd_n),
        .bus_wr_n (bus_wr_n),
        .gm2_req (gm2_req),
        .gm2_mem_req (gm2_mem_req),
        .gm2_mem_wrt (gm2_mem_wrt),
        .gm2_addr (gm2_addr)
    );

    always @ (posedge clk_54m or negedge bus_reset_n) begin   // v2.6: glue SCC a 54M (bus mismo dominio)
        if (bus_reset_n == 0) begin
            scc2x_bank2 <= 8'h00;
            scc2x_bank3 <= 8'h00;
            scc2x_modeb <= 8'h00;
        end
        else if ( scc2x_slot_hit == 1 && bus_mreq_n == 0 && bus_wr_n == 0 ) begin
            if ( bus_addr[15:11] == 5'b10010 )
                scc2x_bank2 <= cpu_dout;                                    // 9000-97FF
            if ( bus_addr[15:11] == 5'b10110 && scc2x_modeb[4] == 0 )
                scc2x_bank3 <= cpu_dout;                                    // B000-B7FF
            if ( bus_addr[15:11] == 5'b10111 && bus_addr[10:1] == 10'b1111111111 )
                scc2x_modeb <= cpu_dout;                                    // BFFE-BFFF
        end
    end

    wire scc2x_win;
    assign scc2x_win = ( scc2x_modeb[5] == 0 ) ? ( (scc2x_bank2 == 8'h3f ? 1'b1 : 1'b0) & x98h )
                                               : ( scc2x_bank3[7] & xb8h & ~scc2x_modeb[4] );

    reg scc2x_req;
    always @ (posedge clk_54m) begin   // v2.6: glue SCC a 54M (bus mismo dominio)
        scc2x_req <= ( scc2x_slot_hit == 1 && scc2x_win == 1 && bus_mreq_n == 0 && (bus_wr_n == 0 || bus_rd_n == 0) ) ? 1 : 0;
    end
    wire scc2x_wrt;
    wire scc2x_rd_r;
    assign scc2x_wrt = ( scc2x_req == 1 && bus_wr_n == 0 ) ? 1 : 0;
    assign scc2x_rd_r = ( scc2x_req == 1 && bus_rd_n == 0 ) ? 1 : 0;

    wire [7:0] scc2x_dout;
    wire [14:0] scc2x_wav;
    wire [14:0] scc2x_wav_l, scc2x_wav_r;   // 23/09/2026: estereo por canales (en espejo)

    // v4.2 (_57): SEGUNDO SCC RESTAURADO (F3.5 de las prioridades del usuario)
    // — se retiro en la _52 para limpiar el tablero durante la caza del bug;
    // vuelve con el chip CURADO (mismo scc_wave2 via GHDL con los fixes _52+
    // _54). Es el SCC-I "ghost": se habilita con config1_ff[2] (SWIO) y vive
    // en el slot OPUESTO a la megaram. En estereo, desde el 23/09/2026, reparte
    // sus canales en ESPEJO del SCC de la megaram (pan_mirror=1); antes iba
    // entero a la derecha. Test: SCCTEST2.ROM.
`ifdef ENABLE_SCC
    scc_wave2 SccCh2 (
        .clk21m (clk_27m),
        .reset (~bus_reset_n),
        .clkena (clk_enable_3m6_27),
        .req ( scc2x_req),
        .ack (),
        .wrt (scc2x_wrt),
        .adr (bus_addr[7:0]),
        .dbi (scc2x_dout),
        .dbo (cpu_dout),
        .wave (scc2x_wav),
        .wave_l (scc2x_wav_l),      // 23/09: en espejo: A 1/4 izq, B 3/4, C centro, D 1/4, E 3/4
        .wave_r (scc2x_wav_r),
        .pan_mirror (1'b1),
        .sccplus (scc2x_modeb[5]),
        .dbg_vol_nz (),
        .dbg_sel_nz (),
        .dbg_freq_nz (),
        .dbg_ptr_lsb (),
        .dbg_scan_lsb (),
        .dbg_mix_nz (),
        .dbg_wavlatch (),
        .dbg_capnz (),
        .dbg_wave_nz (),
        .dbg_mix5_nz ()
    );
`else
    assign scc2x_wav  = 15'd0;
    assign scc2x_wav_l = 15'd0;
    assign scc2x_wav_r = 15'd0;
    assign scc2x_dout = 8'hFF;
`endif

    //mixer (23/09/2026: estereo = PSG y SCC por canales, OPLL/Y8950 al centro; mono = todo en los dos lados)
    // Y8950 (MSX-Audio FM) se suma en ambos canales igual que el OPLL (mono).
	reg [15:0] audio_sample;
	reg [15:0] audio_sample_r;

    // ===== _161 BUG #10 (INFORME_NIQUELADO): los PSG entraban SIN SIGNO =====
    // {1'b0, psgSound3, 6'b0} es 0..+16320: un PEDESTAL DE CONTINUA que se comia
    // la mitad del recorrido positivo del sat16 (y en mono, con los DOS PSG, se
    // lo comia entero) => el mezclador recortaba SOLO el semiciclo positivo.
    // Bloqueador de continua de 1 polo por PSG: dc = acc>>>16; ac = x-dc; acc+=ac
    // A 3,579545 MHz con N=16 la esquina cae en 8,7 Hz (tau 18 ms): es el
    // condensador de acoplo que el hardware real tiene y nosotros no teniamos.
    // Aritmetica CERRADA (leccion _85/_115): $signed explicito y extension de
    // signo escrita a mano; ningun literal sin signo en el camino.
    // ZYNQ 23/09: un bloqueador de continua por PSG y por lado (misma receta: dc = acc>>>16; ac = x-dc)
    reg  signed [31:0] psg1l_dcacc = 32'sd0, psg1r_dcacc = 32'sd0, psg2l_dcacc = 32'sd0, psg2r_dcacc = 32'sd0;
    wire signed [16:0] psg1l_x  = $signed({2'b00, psg1_lf, 6'b000000});    // 0..12224 (191*64)
    wire signed [16:0] psg1r_x  = $signed({2'b00, psg1_rf, 6'b000000});
    wire signed [16:0] psg2l_x  = $signed({2'b00, psg2_lf, 6'b000000});
    wire signed [16:0] psg2r_x  = $signed({2'b00, psg2_rf, 6'b000000});
    wire signed [16:0] psg1l_ac = psg1l_x - psg1l_dcacc[31:16];
    wire signed [16:0] psg1r_ac = psg1r_x - psg1r_dcacc[31:16];
    wire signed [16:0] psg2l_ac = psg2l_x - psg2l_dcacc[31:16];
    wire signed [16:0] psg2r_ac = psg2r_x - psg2r_dcacc[31:16];
    always @(posedge clk_27m) begin
        if (~bus_reset_n) begin
            psg1l_dcacc <= 32'sd0; psg1r_dcacc <= 32'sd0; psg2l_dcacc <= 32'sd0; psg2r_dcacc <= 32'sd0;
        end
        else if (clk_enable_3m6_27) begin
            psg1l_dcacc <= psg1l_dcacc + {{15{psg1l_ac[16]}}, psg1l_ac};
            psg1r_dcacc <= psg1r_dcacc + {{15{psg1r_ac[16]}}, psg1r_ac};
            psg2l_dcacc <= psg2l_dcacc + {{15{psg2l_ac[16]}}, psg2l_ac};
            psg2r_dcacc <= psg2r_dcacc + {{15{psg2r_ac[16]}}, psg2r_ac};
        end
    end
`ifdef ENABLE_DUAL
    // Dual: + el PSG de la maquina B (mono, a los dos lados): +-36688. Z1.3.2b8: los PSG de A se quedan en 0 con A en silencio y el de B con B en silencio
    wire signed [16:0] psgL_ac = $signed(psg1l_ac & {17{~a_mute_27}}) + $signed(psg2l_ac & {17{~a_mute_27}}) + $signed(b_psg_ac & {17{~b_mute_27}});
    wire signed [16:0] psgR_ac = $signed(psg1r_ac & {17{~a_mute_27}}) + $signed(psg2r_ac & {17{~a_mute_27}}) + $signed(b_psg_ac & {17{~b_mute_27}});
`else
    wire signed [16:0] psgL_ac = psg1l_ac + psg2l_ac;                      // los dos PSG por lado: +-24448
    wire signed [16:0] psgR_ac = psg1r_ac + psg2r_ac;
`endif

    wire [15:0] scc_term;
    assign scc_term = (map_sel == 2'b10) ? { scc_wav, 1'b0 } : 16'd0;  // SCC solo en modo SCC (no Konami4/ASCII)
    wire [15:0] scc_term_l = (map_sel == 2'b10) ? { scc_wav_l, 1'b0 } : 16'd0;   // 23/09: lados del estereo
    wire [15:0] scc_term_r = (map_sel == 2'b10) ? { scc_wav_r, 1'b0 } : 16'd0;


    // ADPCM-B del Y8950 (_80) y MoonSound FM (_82): mono en ambos canales
    // como el FM del Y8950.
    // _159b: BALANCE CANONICO. El ADPCM-B tiene que picar como UNA portadora
    // FM del propio Y8950. Aritmetica cerrada, cadena por cadena:
    //   MSXimus: decoder +-32767 -> volumen FF (pcm*255>>8) = +-32639
    //            con >>>1 al mixer = +-16320, contra los +-4095 de una
    //            portadora del jtopl_acc (INW=13)  =>  3,99x  =  +12,0 dB
    //   openMSX: pd.out +-32767 -> out*volume>>12 = +-2040, contra el
    //            dB2LinTab maximo de 2048 (getAmplificationFactorImpl=1/2048)
    //            =>  1,00x
    // El divisor canonico es >>>3: 32639/8 = 4080 frente a 4095 = 0,99x.
    // Escrito como CONCATENACION con extension de signo EXPLICITA, no como
    // >>>: la leccion _85/_115 (un literal unsigned envenena la signedness de
    // la expresion y el >>> degenera en shift logico) ya costo una build.
    // Si en placa suena demasiado apagado, el intermedio honesto es >>>2
    // ({{2{...[15]}}, ...[15:2]}, -6 dB): quita el 75% del exceso y deja el
    // ADPCM a 2x la portadora.
`ifdef ENABLE_TR
    // TR no tiene Y8950: el PCM ocupa su sitio en la mezcla y su canal 4 del mezclador
    reg  [15:0] y8950_adpcm_term = 16'd0;
    always @(posedge clk_27m) y8950_adpcm_term <= $signed({~trpcm_dac[7], trpcm_dac[6:0], 8'd0}) >>> `TRPCM_SHIFT;
`else
    wire [15:0] y8950_adpcm_term = {{3{y8950_adpcm_wav[15]}}, y8950_adpcm_wav[15:3]};
`endif
    // _83: OPL3 ya sale a nivel nativo (como jt2413_wav) — sin >>1
    // _110: atenuacion del reg F8 (MixCalc del motor: >>> 2*codigo). Hasta
    // ahora F8 se ignoraba y el FM entraba siempre a 0dB aunque el software
    // pidiera bajarlo (MBWave/VGMPlay balancean FM vs wave con F8/F9).
    // _114 canon: pasos de -3dB = {1,0.75,0.5,0.375,...,MUTE} (openMSX). El
    // atajo ">>>{code,1'b0}" (-12dB/paso) convertia el reset canon del F8
    // (3/3 = -8.5dB) en /64: el FM quedaba INAUDIBLE con software que nunca
    // escribe F8 (VGMPlay reproduciendo VGMs YMF262/OPL3 puros).
    // _115: ¡LECCION _85 OTRA VEZ! El 16'd0 UNSIGNED del ternario de la _114
    // envenenaba la signedness de la expresion entera -> el >>> degeneraba en
    // shift LOGICO -> negativos rectificados a positivos enormes = el
    // "horrible distorsionado" de los VGM OPL3 (F8=3 => shift 1 roto; juegos
    // con F8=0 => shift 0 inocuo, por eso sonaban bien). Probado en iverilog:
    // -1000 -> +32268 (bug) vs -500 (fix). El shift vive ahora en un wire
    // SIGNED propio (aritmetica autodeterminada); el ternario solo muxea bits.
    // 16/10/2026: F8 lleva DOS atenuaciones, bits 2:0 para el FM izquierdo y 5:3 para el derecho (manual del YMF278B; el
    // motor ya usaba MIXFM[5:3] para la derecha). Hasta la Z1.2.9 el lado derecho y el mono usaban solo los bits 2:0: con un
    // F8 asimetrico la derecha salia con la atenuacion de la izquierda (con el 1Bh del reset, simetrico, no se notaba).
    // Ahora cada lado con los suyos, y el mono es la media de los dos lados ya atenuados (con F8 simetrico, igual que antes
    // salvo +-1 LSB de redondeo).
    // 23/09/2026: la atenuacion del F8 para cada lado del estereo real del OPL3
    wire signed [15:0] o4fm_sl    = $signed(opl4fm_wav_l);
    wire signed [15:0] o4fm_sr    = $signed(opl4fm_wav_r);
    wire signed [15:0] o4fm_bl    = opl4_mixfm[0] ? (o4fm_sl >>> 1) + (o4fm_sl >>> 2) : o4fm_sl;
    wire signed [15:0] o4fm_br    = opl4_mixfm[3] ? (o4fm_sr >>> 1) + (o4fm_sr >>> 2) : o4fm_sr;
    wire signed [15:0] o4fm_al    = o4fm_bl >>> opl4_mixfm[2:1];
    wire signed [15:0] o4fm_ar    = o4fm_br >>> opl4_mixfm[5:4];
    wire signed [15:0] o4fm_ml    = (opl4_mixfm[2:0] == 3'd7) ? 16'sd0 : o4fm_al;
    wire signed [15:0] o4fm_mr    = (opl4_mixfm[5:3] == 3'd7) ? 16'sd0 : o4fm_ar;
    wire [15:0] opl4fm_term_l    = o4fm_ml;
    wire [15:0] opl4fm_term_r    = o4fm_mr;
    wire signed [16:0] o4fm_sum   = {o4fm_ml[15], o4fm_ml} + {o4fm_mr[15], o4fm_mr};
    wire [15:0] opl4fm_term      = o4fm_sum[16:1];   // mono = (L + R) / 2 de los dos lados atenuados

    // _161 BALANCE: openMSX pone la portadora del OPLL en 3915 LSB y la del
    // Y8950 en 5249 (medido) => el OPLL vale 0,746 de una portadora de
    // MSX-Audio. En el MSXimus las dos valen 4095 (mismo jtopl_acc, INW=13):
    // el OPLL entraba +2,6 dB de mas. x3/4 = -2,5 dB.
    wire signed [15:0] opll_s    = $signed(jt2413_wav);
    wire        [15:0] opll_term = (opll_s >>> 1) + (opll_s >>> 2);
    wire signed [15:0] opll_sl   = $signed(jt2413_wav_l);                // 23/09: los lados, con el mismo x3/4
    wire signed [15:0] opll_sr   = $signed(jt2413_wav_r);
    wire        [15:0] opll_term_l = (opll_sl >>> 1) + (opll_sl >>> 2);
    wire        [15:0] opll_term_r = (opll_sr >>> 1) + (opll_sr >>> 2);

    // _89: PCM del MoonSound (motor YMF278B). Mono = (L+R)/2 con extension de
    // signo EXPLICITA (leccion _85: las concatenaciones son unsigned); en
    // estereo, L y R nativos a cada canal.
    // 13/10/2026 MARGEN del OPL4 wave: el motor ya entrega la suma de los 24 slots con -15 dB por slot (como el chip
    // real: x0,1768 antes de acumular) y recortada a 16 bits (DAC), sin envolver. Antes cada slot entraba a plena
    // escala en 18 bits y, con >>1 aqui, la musica densa (MiG) recortaba el 17-21 % de las muestras dentro del motor.
    // Aqui el wave sube x2,0 (e <<< 1, en 19 bits): cada slot queda a 0,354 de su escala, el nivel de openMSX (y los
    // 23/64 de MoonTANG); -3 dB por slot frente a la Z1.2.6 (que lo dejaba a 0,5). Con x2,8125 se conservaba ese nivel
    // por slot, pero MiG caia el 5-7 % de las muestras en la rodilla del limitador (_180) y con x2,0 solo el 1-2 %.
    // |x| <= 32768 -> |y| <= 65536.
    function signed [18:0] o4gain(input signed [15:0] x);
        reg signed [18:0] e;
        begin
            e = {{3{x[15]}}, x};                                   // extension de signo explicita (leccion _85)
            o4gain = e <<< 1;                                      // x2,0
        end
    endfunction
    wire signed [16:0] opl4pcm_sum = {opl4pcm_l[15], opl4pcm_l} + {opl4pcm_r[15], opl4pcm_r};
    wire signed [18:0] opl4pcm_term   = o4gain(opl4pcm_sum[16:1]);           // (L+R)/2 x2
    wire signed [18:0] opl4pcm_term_l = o4gain(opl4pcm_l);                   // L x2
    wire signed [18:0] opl4pcm_term_r = o4gain(opl4pcm_r);                   // R x2

    // _110: MIXER CON SATURACION. La suma iba en 16 bits "sin saturacion"
    // (comentario historico): con VGMPlay/MBWave (20+ slots wave + FM a la
    // vez) el pico desborda y HACE WRAP al signo contrario = zumbido aspero
    // que en notas sostenidas se percibe como "vibracion" + "saturacion de
    // volumen" + "sonido sucio" (sintomas del usuario en la _109). Suma en
    // 19 bits (9 terminos de 16) y clamp simetrico a 16.
    // _161 GANANCIA MAESTRA: sin multiplicador, sumas de desplazamientos. La
    // entrada son los 19 bits de la suma (+-262143); x8 => cabe en 23 con signo.
    function signed [22:0] gmul(input signed [18:0] v);
        reg signed [22:0] x;
        begin
            x = {{4{v[18]}}, v};                   // extension de signo explicita
            case (snd_gain_ff)
                3'd0: gmul = x;                     // x1     0,0 dB
                3'd1: gmul = x + (x >>> 1);         // x1,5  +3,5 dB
                3'd2: gmul = x <<< 1;               // x2    +6,0 dB
                3'd3: gmul = (x <<< 1) + x;         // x3    +9,5 dB
                3'd4: gmul = x <<< 2;               // x4   +12,0 dB
                3'd5: gmul = (x <<< 2) + x;         // x5   +14,0 dB  <- defecto
                3'd6: gmul = (x <<< 2) + (x <<< 1); // x6   +15,6 dB
                3'd7: gmul = x <<< 3;               // x8   +18,1 dB
            endcase
        end
    endfunction

    // _161 LIMITADOR de rodilla suave: unidad por debajo de 0,75 de fondo de
    // escala y pendiente 1/2 por encima (compresion 2:1 del 25% superior), en
    // vez del recorte duro de antes. Simetrico.
    localparam signed [22:0] SND_KNEE = 23'sd24576;
    function [15:0] sat16k(input signed [22:0] v);
        reg               neg;
        reg signed [22:0] a, y;
        begin
            neg = v[22];
            a   = neg ? -v : v;
            y   = (a <= SND_KNEE) ? a : (SND_KNEE + ((a - SND_KNEE) >>> 1));
            if (y > 23'sd32767) y = 23'sd32767;
            sat16k = neg ? (~y[15:0] + 16'd1) : y[15:0];
        end
    endfunction
    // _180 (regresion de la rc7 cazada por Albert, 04/08: "la tabla de ondas
    // suena como con el volumen subido y distorsiona"; la v2.0 pre-_161 suena
    // limpia): la ganancia maestra _161d (x5, +14dB) multiplicaba TAMBIEN al
    // OPL4 — cuando su proposito declarado era subir los chips flojos "a la
    // altura del OPL4/MoonSound". El OPL4 ya estaba en su sitio: x5 lo metia
    // de lleno en la rodilla del limitador (knee 0,75 FS + techo) = mas
    // volumen y distorsion sostenida. FIX: el grupo CLASICO (PSG/SCC/OPLL/
    // Y8950/ADPCM) pasa por gmul; el OPL4 (FM + wave) entra x1 DESPUES de la
    // ganancia. El mando del puerto #44 vuelve a significar lo que Albert
    // ajusto a oido: el volumen de los clasicos RESPECTO al MoonSound.
    // V3.7 MEZCLADOR: cada fuente entra por su atenuador k/8 (mix_lvl, puerto #44 canales 1..7).
    // mixk: v * k / 8 con k = 0..8 (8 = v intacto). Producto en 24 bits con signo (leccion _85/_115: nada
    // de operandos unsigned en la expresion) y p[21:3] = p >>> 3 (|p| <= 2^21).
    function signed [18:0] mixk(input signed [18:0] v, input [3:0] k);
        reg signed [23:0] p;
        begin
            p    = v * $signed({1'b0, k});
            mixk = p[21:3];
        end
    endfunction
`ifdef ENABLE_MIXER
`ifdef ENABLE_DUAL
    wire [3:0] mk_scc = mix_lvl[7:4]   & {4{~a_mute_27}};            // Dual (Z1.3.2b8): A en silencio = su SCC, OPLL, Y8950 y WaveGame a nivel 0
    wire [3:0] mk_opll = mix_lvl[11:8] & {4{~a_mute_27}};
    wire [3:0] mk_y895 = mix_lvl[15:12] & {4{~a_mute_27}};
    wire [3:0] mk_wg = mix_lvl[27:24] & {4{~a_mute_27}};
`else
    wire [3:0] mk_scc = mix_lvl[7:4];
    wire [3:0] mk_opll = mix_lvl[11:8];
    wire [3:0] mk_y895 = mix_lvl[15:12];
    wire [3:0] mk_wg = mix_lvl[27:24];
`endif
    wire signed [18:0] mx_psgL  = mixk({{2{psgL_ac[16]}}, psgL_ac},               mix_lvl[3:0]);    // 1 PSG (ZYNQ 23/09: por lados)
    wire signed [18:0] mx_psgR  = mixk({{2{psgR_ac[16]}}, psgR_ac},               mix_lvl[3:0]);
    wire signed [18:0] mx_scc   = mixk({{3{scc_term[15]}}, scc_term},             mk_scc);    // 2 SCC
    wire signed [18:0] mx_scc2x = mixk({{3{scc2x_wav[14]}}, scc2x_wav, 1'b0},     mk_scc);
    wire signed [18:0] mx_sccL   = mixk({{3{scc_term_l[15]}}, scc_term_l},        mk_scc);    // 23/09: estereo
    wire signed [18:0] mx_sccR   = mixk({{3{scc_term_r[15]}}, scc_term_r},        mk_scc);
    wire signed [18:0] mx_scc2xL = mixk({{3{scc2x_wav_l[14]}}, scc2x_wav_l, 1'b0}, mk_scc);
    wire signed [18:0] mx_scc2xR = mixk({{3{scc2x_wav_r[14]}}, scc2x_wav_r, 1'b0}, mk_scc);
    wire signed [18:0] mx_opll  = mixk({{3{opll_term[15]}}, opll_term},           mk_opll);   // 3 OPLL
    wire signed [18:0] mx_opllL = mixk({{3{opll_term_l[15]}}, opll_term_l},       mk_opll);   // 23/09: estereo
    wire signed [18:0] mx_opllR = mixk({{3{opll_term_r[15]}}, opll_term_r},       mk_opll);
    wire signed [18:0] mx_y8950 = mixk({{3{y8950_wav[15]}}, y8950_wav}
                                     + {{3{y8950_adpcm_term[15]}}, y8950_adpcm_term}, mk_y895);  // 4 MSX-AUDIO
    // 23/09/2026: estereo = FM por canales + la mitad del ADPCM a cada lado (izq + der = mono)
    wire signed [18:0] y8950_adpcm_h = {{4{y8950_adpcm_term[15]}}, y8950_adpcm_term[15:1]};
    wire signed [18:0] mx_y8950L = mixk({{3{y8950_wav_l[15]}}, y8950_wav_l} + y8950_adpcm_h, mk_y895);
    wire signed [18:0] mx_y8950R = mixk({{3{y8950_wav_r[15]}}, y8950_wav_r} + y8950_adpcm_h, mk_y895);
    wire signed [18:0] mx_o4fm  = mixk({{3{opl4fm_term[15]}}, opl4fm_term},       mix_lvl[19:16]);  // 5 OPL4 FM
    wire signed [18:0] mx_o4fmL = mixk({{3{opl4fm_term_l[15]}}, opl4fm_term_l},   mix_lvl[19:16]);  // 23/09: estereo real
    wire signed [18:0] mx_o4fmR = mixk({{3{opl4fm_term_r[15]}}, opl4fm_term_r},   mix_lvl[19:16]);
    wire signed [18:0] mx_o4pl  = mixk(opl4pcm_term_l, mix_lvl[23:20]);  // 6 OPL4 wave
    wire signed [18:0] mx_o4pr  = mixk(opl4pcm_term_r, mix_lvl[23:20]);
    wire signed [18:0] mx_o4pm  = mixk(opl4pcm_term,   mix_lvl[23:20]);
`else
    wire signed [18:0] mx_psgL  = {{2{psgL_ac[16]}}, psgL_ac};
    wire signed [18:0] mx_psgR  = {{2{psgR_ac[16]}}, psgR_ac};
    wire signed [18:0] mx_scc   = {{3{scc_term[15]}}, scc_term};
    wire signed [18:0] mx_scc2x = {{3{scc2x_wav[14]}}, scc2x_wav, 1'b0};
    wire signed [18:0] mx_sccL   = {{3{scc_term_l[15]}}, scc_term_l};
    wire signed [18:0] mx_sccR   = {{3{scc_term_r[15]}}, scc_term_r};
    wire signed [18:0] mx_scc2xL = {{3{scc2x_wav_l[14]}}, scc2x_wav_l, 1'b0};
    wire signed [18:0] mx_scc2xR = {{3{scc2x_wav_r[14]}}, scc2x_wav_r, 1'b0};
    wire signed [18:0] mx_opll  = {{3{opll_term[15]}}, opll_term};
    wire signed [18:0] mx_opllL = {{3{opll_term_l[15]}}, opll_term_l};
    wire signed [18:0] mx_opllR = {{3{opll_term_r[15]}}, opll_term_r};
    wire signed [18:0] mx_y8950 = {{3{y8950_wav[15]}}, y8950_wav} + {{3{y8950_adpcm_term[15]}}, y8950_adpcm_term};
    wire signed [18:0] y8950_adpcm_h = {{4{y8950_adpcm_term[15]}}, y8950_adpcm_term[15:1]};
    wire signed [18:0] mx_y8950L = {{3{y8950_wav_l[15]}}, y8950_wav_l} + y8950_adpcm_h;
    wire signed [18:0] mx_y8950R = {{3{y8950_wav_r[15]}}, y8950_wav_r} + y8950_adpcm_h;
    wire signed [18:0] mx_o4fm  = {{3{opl4fm_term[15]}}, opl4fm_term};
    wire signed [18:0] mx_o4fmL = {{3{opl4fm_term_l[15]}}, opl4fm_term_l};
    wire signed [18:0] mx_o4fmR = {{3{opl4fm_term_r[15]}}, opl4fm_term_r};
    wire signed [18:0] mx_o4pl  = opl4pcm_term_l;
    wire signed [18:0] mx_o4pr  = opl4pcm_term_r;
    wire signed [18:0] mx_o4pm  = opl4pcm_term;
`endif
    // ZYNQ 23/09: PSG por canales en cada lado; SCC, OPLL y MSX-AUDIO al centro (antes SCC1 izq y SCC2 der: un
    // juego normal con "Stereo Sound" sonaba casi todo por la izquierda). El mono es la misma suma de antes.
    // 23/09 noche: el SCC tambien por canales (lo reparte el propio scc_wave2, izq + der = su mono), el 2o SCC
    // en espejo. OPLL y MSX-AUDIO siguen al centro.
`ifdef ENABLE_MUSICA
    // ---- perfil Musica: canal 8 del mezclador = YM2151 (estereo propio) y canal 9 = SN76489 (mono, al centro) ----
    // Van al grupo clasico (pasan por la ganancia maestra, como el OPLL y el Y8950). Nivel k/8 FIJO a 8 (x1): el puerto #44 solo
    // llega al canal 7 (campo de 3 bits), mix_lvl tiene 28 bits y el buzon (MBOX+0x24) solo 28 y 3 libres; para dar niveles a
    // estos dos canales hay que ampliar a la vez el protocolo del #44, mix_lvl y mix_rd, la siembra y la telemetria del buzon,
    // qspi_cfg.c, el menu y el panel (docs/tecnica/02-puertos-es.md, apartado del perfil Musica). Mientras tanto, estas constantes.
    localparam [3:0] MIX_LVL_SFG = 4'd8;
    localparam [3:0] MIX_LVL_SN  = 4'd8;
    // YM2151: una portadora a TL = 0 da +-8168 (medido en tb/tb_musica.sv +LEVEL); >>>1 la deja en los +-4084 de una portadora del
    // Y8950/OPLL (jtopl_acc, INW = 13). Mono = (L + R) / 2, como el OPL4 FM.
    wire signed [16:0] sfg_sum = {mus_sfg_l[15], mus_sfg_l} + {mus_sfg_r[15], mus_sfg_r};   // |.| <= 65534
    wire signed [18:0] mx_sfgL = mixk({{4{mus_sfg_l[15]}}, mus_sfg_l[15:1]}, MIX_LVL_SFG);
    wire signed [18:0] mx_sfgR = mixk({{4{mus_sfg_r[15]}}, mus_sfg_r[15:1]}, MIX_LVL_SFG);
    wire signed [18:0] mx_sfgM = mixk({{4{sfg_sum[16]}}, sfg_sum[16:2]}, MIX_LVL_SFG);
    // SN76489: un tono a volumen 0 da +-255; x16 = +-4080, el nivel de un canal del PSG a tope en mono (+-4050). En estereo la
    // mitad a cada lado (izq + der = mono, como el PSG y el OPLL).
    wire signed [18:0] mx_snM = mixk({{3{mus_sn[10]}}, mus_sn, 5'b00000}, MIX_LVL_SN);   // 31/10: x2 (en placa sonaba muy bajo)
    wire signed [18:0] mx_snS = mixk({{4{mus_sn[10]}}, mus_sn, 4'b0000}, MIX_LVL_SN);   // 31/10: x2
    reg  signed [18:0] mus_tL = 19'sd0, mus_tR = 19'sd0, mus_tM = 19'sd0;   // las dos fuentes, registradas a 27 MHz para no alargar la suma de abajo
    always @(posedge clk_27m) begin
        mus_tL <= mx_sfgL + mx_snS;
        mus_tR <= mx_sfgR + mx_snS;
        mus_tM <= mx_sfgM + mx_snM;
    end
    // La suma se hace en 20 bits y se satura a 19: con los dos canales nuevos, siete u ocho terminos a plena escala ya no caben
    // en 19 bits (la ganancia maestra y los sumandos de abajo cuentan con 19: gmul x8 = 22 bits + OPL4 + WaveGame < 2^22).
    function signed [18:0] sat19(input signed [19:0] v);
        sat19 = (v[19] != v[18]) ? {v[19], {18{~v[19]}}} : v[18:0];
    endfunction
    wire signed [19:0] mixL_x    = mx_psgL + mx_sccL + mx_scc2xL + mx_opllL + mx_y8950L + mus_tL;
    wire signed [19:0] mixR_x    = mx_psgR + mx_sccR + mx_scc2xR + mx_opllR + mx_y8950R + mus_tR;
    wire signed [19:0] mix_mono_x = mx_psgL + mx_psgR + mx_scc + mx_scc2x + mx_opll + mx_y8950 + mus_tM;
    wire signed [18:0] mixL_st  = sat19(mixL_x);
    wire signed [18:0] mixR_st  = sat19(mixR_x);
    wire signed [18:0] mix_mono = sat19(mix_mono_x);
`else
    wire signed [18:0] mixL_st  = mx_psgL + mx_sccL + mx_scc2xL + mx_opllL + mx_y8950L;
    wire signed [18:0] mixR_st  = mx_psgR + mx_sccR + mx_scc2xR + mx_opllR + mx_y8950R;
    wire signed [18:0] mix_mono = mx_psgL + mx_psgR + mx_scc + mx_scc2x + mx_opll + mx_y8950;
`endif
    // ZYNQ 23/09: el WaveGame trae izquierda y derecha. La seleccion estereo/mono va REGISTRADA en un always
    // (config_enable_stereo se declara mas abajo: en un always vale, como en el bloque (A) del mezclador).
    wire signed [19:0] wg_sum   = {wg_smp_27[18], wg_smp_27} + {wg_smp_r_27[18], wg_smp_r_27};
    reg  signed [18:0] wg_l_sel = 19'sd0, wg_r_sel = 19'sd0;
    always @(posedge clk_27m) begin
        wg_l_sel <= config_enable_stereo ? wg_smp_27   : wg_sum[19:1];   // mono: la media de los dos lados
        wg_r_sel <= config_enable_stereo ? wg_smp_r_27 : wg_sum[19:1];
    end
    wire signed [18:0] mx_wg_l  = mixk(wg_l_sel, mk_wg);      // ZYNQ V3.7: canal 7 = WaveGame
    wire signed [18:0] mx_wg_r  = mixk(wg_r_sel, mk_wg);
    // _180: suma propia del OPL4 (FM + wave), fuera de la ganancia maestra (|fm| < 2^15, |pcm| <= 2^16 con el x2 de
    // o4gain: 98303 < 2^17; 19 bits de margen)
    wire signed [18:0] o4mix_l    = mx_o4fmL + mx_o4pl;   // 23/09: FM por lados; 13/10/2026: 19 bits (antes 17: el PCM ya no es >>1)
    wire signed [18:0] o4mix_r    = mx_o4fmR + mx_o4pr;
    wire signed [18:0] o4mix_mono = mx_o4fm + mx_o4pm;
    // _127H: TONO DE TEST del bug #14 (440Hz cuadrada -12dB directa al puente,
    // puenteando el mezclador). DESARMADO en release (niquelado B, bug #4 del
    // informe): iba colgado del toggle "Sprite Limit" del menu (config2[3]) y
    // cualquier usuario lo pisaba — y persistia en flash. Para reactivarlo en
    // una build de diagnostico: `define DEBUG_TONE_440 (el discriminador
    // sigue siendo valido: tono limpio con musica cortada -> mezclador;
    // tono cortado tambien -> HDMI/receptor).
`ifdef DEBUG_TONE_440
    reg [14:0] tone_cnt = 15'd0;
    reg        tone_sq  = 1'b0;
    always @ (posedge clk_27m) begin
        if (tone_cnt == 15'd30681) begin      // 27e6/(2*440) - 1
            tone_cnt <= 15'd0;
            tone_sq  <= ~tone_sq;
        end else
            tone_cnt <= tone_cnt + 15'd1;
    end
    wire [15:0] tone_smp = tone_sq ? 16'd4096 : 16'hF000;   // +-4096 (-12dB)
`endif

    // _161b SEGMENTACION (el gate de la _161 dio 30 violaciones de setup, todas
    // en el camino uopl4fm/pcm_out -> audio_sample: el cono mezclador + ganancia
    // + valor absoluto + rodilla + saturacion no cabia en un ciclo de clk_27m).
    // Se parte en dos etapas, la variante que el propio INFORME_GANANCIA_AUDIO
    // dejaba preparada: etapa 1 = seleccion + ganancia (registrada), etapa 2 =
    // limitador. clk_enable_3m6_27 solo se activa 1 de cada ~7,5 ciclos de 27M,
    // asi que la muestra sigue lista MUCHO antes del siguiente pulso: el retardo
    // extra (37 ns) es inaudible y no cambia ni un bit del resultado.
    // _161e TRES etapas (la de dos seguia siendo MARGINAL: la _161b paso con
    // setup 0 pero la _161c, que solo anade telemetria, volvio a violar por
    // -1,66 ns en uopl4fm/pcm_out -> snd_g_r: el cono "arbol sumador de 9
    // terminos de 19 bits + ganancia de 23" gana o pierde segun la tirada de
    // placement = loteria). Ahora: (A) SUMA registrada, (B) ganancia, (C)
    // limitador. B y C corren libres a 27 MHz; como clk_enable_3m6_27 solo
    // pulsa 1 de cada ~7,5 ciclos, la muestra esta lista muchisimo antes del
    // siguiente pulso y el resultado no cambia ni un bit.
    reg signed [18:0] snd_mix_l, snd_mix_r;          // (A) suma (grupo clasico)
    reg signed [18:0] snd_o4_l,  snd_o4_r;           // (A) suma OPL4 (_180: x1; 13/10/2026: 19 bits)
    reg signed [22:0] snd_g_l,  snd_g_r;             // (B) con ganancia
    always @ (posedge clk_27m) begin
        if (clk_enable_3m6_27 == 1 ) begin
`ifdef DEBUG_TONE_440
            if (config_enable_8sprites == 1) begin
                snd_mix_l <= {{3{tone_smp[15]}}, tone_smp};
                snd_mix_r <= {{3{tone_smp[15]}}, tone_smp};
                snd_o4_l  <= 19'sd0;
                snd_o4_r  <= 19'sd0;
            end
            else
`endif
            if (config_enable_stereo == 1) begin
                snd_mix_l <= mixL_st;
                snd_mix_r <= mixR_st;
                snd_o4_l  <= o4mix_l;
                snd_o4_r  <= o4mix_r;
            end
            else begin
                snd_mix_l <= mix_mono;
                snd_mix_r <= mix_mono;
                snd_o4_l  <= o4mix_mono;
                snd_o4_r  <= o4mix_mono;
            end
        end
    end

    always @ (posedge clk_27m) begin
        // _180: gmul solo al grupo clasico; el OPL4 entra x1 (sin tocar).
        // Rango: gmul max +-2097144 + OPL4 +-98303 (FM +-32767 + wave x2 +-65536; 19 bits) < 2^22: cabe en 23 bits.
        snd_g_l <= gmul(snd_mix_l) + {{4{snd_o4_l[18]}}, snd_o4_l} + {{4{mx_wg_l[18]}}, mx_wg_l} + {{4{tp_snd_27[18]}}, tp_snd_27};   // ZYNQ: + WaveGame (x1..x8 desde el ARM, x k/8 del mezclador) + monitor de la cinta (+-1536); rango 2097144+262143+262144+1536 < 2^22
        snd_g_r <= gmul(snd_mix_r) + {{4{snd_o4_r[18]}}, snd_o4_r} + {{4{mx_wg_r[18]}}, mx_wg_r} + {{4{tp_snd_27[18]}}, tp_snd_27};   // 23/09: WaveGame con su canal derecho
    end

    always @ (posedge clk_27m) begin
`ifdef ENABLE_TR
        audio_sample   <= trpcm_mute ? 16'd0 : sat16k(snd_g_l);
        audio_sample_r <= trpcm_mute ? 16'd0 : sat16k(snd_g_r);
`else
        audio_sample   <= sat16k(snd_g_l);
        audio_sample_r <= sat16k(snd_g_r);
`endif
    end

`else

    wire scc2_req;
    wire [14:0] scc2_wav;
    wire megaram_req;
`ifdef NEO16_16M
    wire [23:0] megaram_addr;   // perfil TR: 16 MB
`else
    wire [22:0] megaram_addr;   // V3.5: 4 MB; 23/09/2026: 8 MB (ASCII16-X)
`endif
    wire megaram_enabled;
    wire [15:0] audio_sample;
    wire [15:0] audio_sample_r;
    wire megaram_wrt;
    wire y8950_int_n = 1'b1;   // _81: sin sonido no hay Y8950
    wire opl4_int_n  = 1'b1;   // niquelado B (bug #21): sin sonido no hay OPL4 —
                               // faltaba y quedaba una net implicita SIN DRIVER
                               // colgada del INT_n del Z80 (leccion EX3638)
    assign opl4pcm_wait_n = 1'b1;  // _89: sin sonido no hay motor PCM

`endif

    //kanji data
    // Strobes REGISTRADOS a clk_27m: el decode combinacional desde IORQ formaba la
    // ruta critica (IORQ -> decode kanji -> mux ram_addr) a 54MHz. El ciclo I/O del
    // Z80 dura decenas de ciclos, asi que 1 ciclo extra de latencia es inocuo.
    reg kanji_data_req_r;
    reg kanji_data_req_w;
    wire kanji_data_ram_req;
    reg [7:0] kanji_data_dout;
    wire [17:0] kanji_data_ram_addr;
    // TR (04/11): el modulo kanji toma adr/dbo EN VIVO mientras req (registrado a 27 MHz) sigue 1 un ciclo despues de acabar el strobe; el T80 mantiene
    // direccion y dato ese ciclo, el R800 ya ha puesto la direccion del siguiente acceso (el M1 o la escritura (HL) del INI): con A0 = 0 el OUT (D9h)
    // se reaplicaba como OUT (D8h) (puntero a otro caracter) y en los IN del INIR la paridad de (HL) rompia el handshake del puntero (bytes de otro
    // caracter intercalados). Se le dan la direccion y el dato registrados a la vez que req.
    reg [15:0] kanji_adr_q = 16'd0;
    reg [7:0]  kanji_dbo_q = 8'd0;
    always @ (posedge clk_27m) begin
        kanji_data_req_w <= (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1 : 0; // I/O:D8-DBh / Kanji-data
        kanji_data_req_r <= (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // I/O:D8-DBh / Kanji-data
        if (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1) begin kanji_adr_q <= bus_addr; kanji_dbo_q <= cpu_dout; end
    end
`ifdef ENABLE_TR
    wire [15:0] kanji_adr_w = kanji_adr_q;
    wire [7:0]  kanji_dbo_w = kanji_dbo_q;
`else
    wire [15:0] kanji_adr_w = bus_addr;
    wire [7:0]  kanji_dbo_w = cpu_dout;
`endif

    kanji kanji1(
        .clk21m(clk_27m),
        .reset(0),
        .req(kanji_data_req_w | kanji_data_req_r),
        .wrt(kanji_data_req_w),
        .adr(kanji_adr_w),
        .dbo(kanji_dbo_w),
        .ramreq(kanji_data_ram_req),
        .ramadr(kanji_data_ram_addr)
    );

`ifdef ENABLE_WIFI
    //f2 port
    wire f2_req_r;
    wire f2_req_w;
    reg [7:0] f2_port;

    assign f2_req_r = (bus_addr[7:0] == 8'hf2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign f2_req_w = (bus_addr[7:0] == 8'hf2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            f2_port <= 8'h00;
        else begin
            if (f2_req_w == 1 ) begin
                f2_port <= cpu_dout;
            end
        end
    end
`endif

    localparam CONFIG1_DEFAULT = 8'hf3;  // bit3=0 -> Scanlines OFF by default (was 0xfb)
    localparam CONFIG2_DEFAULT = 8'h0f;  // V3.5: bit3 = "Menu al arrancar" (el menu lo guarda en flash): ON por defecto
                                         // en una flash virgen o tras el rescate S2. (Antes bit3 era "Compatible Mode"; el RTL ya no lo mira.)

`ifdef ENABLE_CONFIG
    //config
    reg [7:0] config0_ff = 8'h00;
`ifdef ENABLE_TR
    // TR (04/11): el contenido de la megaram sobrevive al reset (es DDR) y en el slot 2 la BIOS lo arrancaba como un cartucho al salir del menu, con el mapper de encendido
    // (Z80 perdido, medido). Con la BIOS del tR se oculta a las lecturas desde el reset hasta la primera ESCRITURA real en ella (megaram_wrt: el menu y SofaRun al cargar; el sondeo
    // de RAM de la BIOS no cuenta, con mode_a = 0 no llega a memoria). No vale el SWIO: el menu ya lo toca antes de cargar nada. Es solo TR; el cerrojo mode_a ya se borra con el reset.
    reg tr_mega_on = 1'b0;
    always @(posedge clk_54m) begin
        if (!bus_reset_n) tr_mega_on <= 1'b0;
        else if ((megaram_req_raw && !bus_wr_n) || (dma_ram_req && dma_ram_addr >= 24'h200000)) tr_mega_on <= 1'b1;   // cualquier escritura real, por CPU o por DMA a la zona de la megaram (el menu carga por DMA; con ROM >= 4088 KB no escribe nada mas): 05/11
    end
    assign megaram_req = megaram_req_raw & ~(tr_map & ~tr_mega_on & ~bus_rd_n);
`endif
    reg [7:0] config1_ff = CONFIG1_DEFAULT;
    reg [7:0] config1_temp_ff;
    reg [7:0] config2_ff = CONFIG2_DEFAULT;
    reg [7:0] config2_temp_ff;
    reg [1:0] config_mapper_slot_ff = 2'b11;
    reg [1:0] config_megaram_slot_ff = 2'b11;
    reg [1:0] config_sdcard_slot_ff = 2'b11;
    reg config_enable_mapper3;
    reg config_enable_mapper12;
    wire config_enable_megaram;
    wire config_enable_megaram3;
    wire config_enable_megaram12;
    wire config_enable_ghost_scc;
    reg config_enable_sdcard;
    wire config_enable_8sprites;
    wire config_enable_stereo;
    wire config_enable_16_9;
    reg config_reset_ff;
    reg config_flash_write_ff;
    // 23/09/2026 (PLAN F.10): un config_update POR REGISTRO. Antes habia uno solo y cualquier OUT al #41 o
    // al #42 confirmaba LOS DOS temporales; como los temporales arrancan a 0 y ni la siembra de la QSPI ni el
    // D4/0Fh (ocm_update) los tocan, un #42 suelto dejaba config1 = 0 (megaram fuera al momento; con el bit 6,
    // grabado en la QSPI) y un #41 suelto, config2 = 0. El menu (#41 y luego #42) queda igual.
    reg config1_update;
    reg config2_update;
    wire config_enable_scanlines;
    wire [1:0] config_mapper_slot;
    wire [1:0] config_megaram_slot;
    wire [1:0] config_sdcard_slot;
    wire [1:0] config_keyboard;
    wire config0_req;
    wire config1_req;
    wire config2_req;
    wire config3_req;
    wire config4_req;   // _161: puerto #44 = ganancia maestra de audio
    reg [7:0] config3_ff = 0;       // puerto #43: sram_cfg de la megaram (volatil)
    wire config6_req;               // V3.5: puerto #46 = extension de mapper de la megaram
    reg [7:0] config6_ff = 0;       //   bit0 = NEO (ASCII8->NEO-8, ASCII16->NEO-16),
                                    //   bit4 = mitad alta de los 4 MB para el cargador.
                                    //   Volatil como #43: lo escribe el menu al lanzar y
                                    //   SOBREVIVE al reset del MSX (no hay clausula de reset).
    wire config5_req;
    reg config_turbo_boot_ff = 0;   // puerto #45 bit0: arrancar en turbo (PERSISTIDO en
                                    // flash byte[4] del bloque config: 'T'=0x54 -> on;
                                    // 0x00/0xFF legados -> off)
    wire config_reset_req;
    wire config_reset;
    wire config_ok;
    wire [7:0] config_dout;
    wire config_req;

    always @ (posedge clk_27m) begin
        config_reset_ff <= 0;
        config_flash_write_ff <= 0;
        config1_update <= 0;
        config2_update <= 0;
        if (bus_reset_n == 0) begin
            config6_ff <= config6_ff & 8'h07;   // V3.5f: #46 es VOLATIL (NEO, mitad alta, GM2 armado):
        end                             // a cero en cada reset, o el escaneo de slots de la
                                        // 23/09/2026: salvo los bits 0-2 (NEO / Plain 0000h / ASCII16-X):
                                        // tras un reset la BIOS relanza la ROM cargada y sin ellos iba con el
                                        // mapper basico (kokoro.rom acababa en el BASIC). El menu fija el #46
                                        // antes de tocar la megaram (a16x_detect, scan_win_dma, srm_rd, cargador).
                                        // Se borran el GM2 (bit6) y los cuartos del cargador (bits 4-5).
        if (clk_enable_3m6_27 == 1 ) begin  // BIOS se toparia con el "AB" del GM2 en el slot 1
            if (config0_req == 1 ) begin
                config0_ff <= ~cpu_dout;
            end

            if (config1_req == 1 ) begin
                config1_update <= 1;
                config1_temp_ff <= cpu_dout;
            end
            if (config3_req == 1 ) begin
                config3_ff <= cpu_dout;
            end
            if (config6_req == 1 ) begin
                config6_ff <= cpu_dout;
            end
            if (config2_req == 1 ) begin
                config2_update <= 1;
                config2_temp_ff <= cpu_dout[5:0];
                if ( cpu_dout[6] == 1) begin
                    config_flash_write_ff <= 1;
                end
                if ( cpu_dout[7] == 1) begin
                    config_reset_ff <= 1;
                end
            end
        end
    end

    reg [2:0] ocm_slot2_prev; //bit2 = linear ,bits 1,0 = mode
    reg ocm_update;
    always @ (posedge clk_27m) begin
        ocm_update <= 0;
        if ( { iSlt2_linear, Slot2Mode } != ocm_slot2_prev ) begin
            ocm_update <= 1;
        end
    end

    reg config_init_delay = 0;
    // ZYNQ: bloque vigente hacia el buzon (+0x70) al pulsar "guardar"; config1/2_ff ya estan
    // actualizados dos ciclos despues del pulso (config1/2_update van un ciclo por detras)
    always @ (posedge clk_27m) begin
        zq_cfw_d <= {zq_cfw_d[1:0], config_flash_write_ff};
        if (zq_cfw_d[1]) zq_cfg_tel[19:0] <= {snd_gain_ff, config_turbo_boot_ff, config2_ff, config1_ff};
        if (zq_cfw_d[1]) zq_mix_tel[27:0] <= mix_lvl;                 // V3.7: niveles del mezclador (+0xC0)
        // 17/09: config_flash_write_ff pulsa UNA VEZ POR TICK de 3,58 MHz mientras dura el OUT (#42) = 2..4 pulsos;
        // con un toggle por pulso la paridad decidia si el companion veia el guardado (y cambia con el turbo).
        // Un solo toggle por OUT: ventana de 127 ciclos (4,7 us) tras el primer pulso.
        if (zq_cfw_blank != 7'd0) zq_cfw_blank <= zq_cfw_blank - 7'd1;
        if (zq_cfw_d[2] && zq_cfw_blank == 7'd0) begin
            zq_cfg_tel[31] <= ~zq_cfg_tel[31];
            zq_mix_tel[31] <= ~zq_mix_tel[31];
            zq_cfw_blank   <= 7'd127;
        end
    end
    always @ (posedge clk_27m) begin
        config_init_delay <= config_init;
        if (zq_cfg_seed) begin               // ZYNQ: siembra desde el buzon (sustituye a config_init)
            config1_ff <= zq_cfg_s2[7:0];
            config2_ff <= zq_cfg_s2[15:8];
            config_turbo_boot_ff <= zq_cfg_s2[16];
            snd_gain_ff <= zq_cfg_s2[19:17];
        end
        if (zq_mix_seed) mix_lvl <= zq_mix_s2[27:0];   // V3.7: niveles del mezclador (companion nuevo), ventana propia
        if (config_init == 1 ) begin
            if (s2_press) begin
                config1_ff <= CONFIG1_DEFAULT;
                config2_ff <= CONFIG2_DEFAULT;
                config_turbo_boot_ff <= 0;      // rescate S2: boot turbo off
                snd_gain_ff <= 3'd5;            // rescate S2: ganancia por defecto x5
            end
            else begin
                config1_ff <= config_sig[2];
                config2_ff <= config_sig[3];
                config_turbo_boot_ff <= (config_sig[4] == 8'h54) ? 1'b1 : 1'b0;
                // byte[5] de la flash: 0xC0..0xC7 = ganancia valida; 0xFF/0x00
                // (bloques legados) => defecto x3. Mismo patron que 'T'=0x54.
                snd_gain_ff <= (config_sig[5][7:3] == 5'b11000) ? config_sig[5][2:0] : 3'd5;
            end
        end
        // escritura del puerto #45 (menu): mismo bloque que la carga init para un
        // unico driver; config5_req dura todo el ciclo OUT (re-latch inocuo) y no
        // puede coincidir con config_init (el CPU arranca tras el stream de flash)
        if (config5_req == 1 ) begin
            config_turbo_boot_ff <= cpu_dout[0];
        end
        if (config4_req == 1 ) begin
`ifdef ENABLE_MIXER
            mix_sel <= cpu_dout[6:4];           // V3.7: {solo_sel, canal, nivel} (ver mix_lvl)
            if (!cpu_dout[7]) begin
                if (cpu_dout[6:4] == 3'd0) snd_gain_ff <= cpu_dout[2:0];
                else mix_lvl[{cpu_dout[6:4] - 3'd1, 2'b00} +: 4] <= (cpu_dout[3:0] > 4'd8) ? 4'd8 : cpu_dout[3:0];
            end
`else
            snd_gain_ff <= cpu_dout[2:0];       // _161: ganancia de audio 0..7
`endif
        end
        if (config1_update == 1) config1_ff <= config1_temp_ff;     // F.10: cada puerto confirma SOLO el suyo
        if (config2_update == 1) config2_ff <= config2_temp_ff;
        if (ocm_update == 1) begin
            config1_ff[7:6] <= 2'b10;
            config1_ff[1] <= 1;
            ocm_slot2_prev <= { iSlt2_linear, Slot2Mode };
        end
    end

    monostable mono (
        .pulse_in(config_reset_ff),
        .clock(clk_27m),
        .pulse_out(config_reset_req)
    );
    assign config_reset = (config_reset_req == 1 && flash_write_busy == 0) ? 1 : 0;

    assign config_ok = (config0_ff == 8'hb7) ? 1 : 0;
    assign config0_req = (bus_addr[7:0] == 8'h40 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config1_req = (config_ok == 1 && bus_addr[7:0] == 8'h41 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config2_req = (config_ok == 1 && bus_addr[7:0] == 8'h42 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config3_req = (config_ok == 1 && bus_addr[7:0] == 8'h43 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config4_req = (config_ok == 1 && bus_addr[7:0] == 8'h44 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config5_req = (config_ok == 1 && bus_addr[7:0] == 8'h45 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config6_req = (config_ok == 1 && bus_addr[7:0] == 8'h46 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config_enable_scanlines = config1_ff[3];
    //assign config_keyboard = config2_ff[4:3];
    assign config_enable_stereo = config2_ff[5];
    assign config_enable_16_9 = config2_ff[4];
    // Sprite Limit 8/linea (SPMAXSPR del VDP; fix parpadeo screen 2). En el
    // protocolo de #42 SOLO se almacenan los bits [5:0] (bit6=orden de guardar
    // en flash, bit7=orden de reset) -> el bit de config va en el [3], LIBRE
    // desde la P2 (era el Compatible Mode). En el MSXnano este toggle vive en
    // el bit4 (alli el 16:9 no existe); en MSXimus el bit4 SIGUE siendo 16:9.
    assign config_enable_8sprites = config2_ff[3];
    // ===== v1.9 Panasonic switched-I/O device 8 (T9769 turbo, estilo WSX) =====
    // Protocolo (ref. openMSX MSXMatsushita.cc): OUT &H40,8 selecciona el dispositivo;
    // leer $40 devuelve ~8 = 247 (deteccion). $41 write: SOLO bit0, activo-bajo
    // (0 = 5.37 MHz, 1 = 3.58; OUT &H41,154 enciende porque 154 es par). $41 read:
    // bit0 = estado turbo (0=on), bit2 = 0 (turbo disponible), bit7 = 1 (sin
    // firmware switch), resto 1 -> 0xFA turbo / 0xFB normal.
    // config0_ff guarda ~ID, asi que "dispositivo 8 seleccionado" == 0xF7 y el
    // readback de $40 ES config0_ff = 247. Convive con el config goauld (ID 0x48
    // -> config_ok, excluyentes) y con el fallback swio_dout del rango $40-$4F.
    // La escritura del turbo se latchea en el bloque F11 (clk_54m, un solo driver).
    wire pana_sel  = (config0_ff == 8'hf7) ? 1 : 0;
    wire pana41_wr = (pana_sel == 1 && bus_addr[7:0] == 8'h41 &&
                      bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0) ? 1 : 0;
    wire [7:0] pana_dout = ( bus_addr[3:0] == 4'h0 ) ? config0_ff :
                           ( bus_addr[3:0] == 4'h1 ) ? ( turbo ? 8'hfa : 8'hfb ) : 8'hff;

`ifdef ENABLE_MUSICA
    // ===== perfil Musica: Yamaha SFG-01/05 (YM2151) en la ranura 0-1 y SN76489 (Franky 48h-49h, PlaySoniq 2Ah-2Bh) =====
    // 48h-49h son del SN76489 salvo con el dispositivo 48h de la E/S conmutada elegido (SD por puertos, config_ok): para
    // LEER el contador de Franky no puede estar elegido ninguno (48h, 08h de Panasonic ni D4h del OCM; VGMPlay hace OUT 40h,0).
    musica_sound u_musica (
        .clk        (clk_54m),
        .rst_n      (bus_reset_n),
        .cen        (clk_enable_3m6_54),
        .addr       (bus_addr),
        .din        (cpu_dout),
        .mreq_n     (bus_mreq_n),
        .iorq_n     (bus_iorq_n),
        .rd_n       (bus_rd_n),
        .wr_n       (bus_wr_n),
        .m1_n       (bus_m1_n),
        .sfg_slot   (pri_slot_num[SD_SLOT] & exp_slotx_num[2] & page_num[0]),   // 31/10: pagina 0 del slot 3-2 (antes 0-1: el RDSLT de la BIOS no puede leer la pagina 0 de otro subslot del slot 0, VGMPlay no lo encontraba)
        .io48_wr_ok (~config_ok),
        .io48_rd_ok (config0_ff != 8'hb7 && config0_ff != 8'hf7 && config0_ff != 8'h2b),
        .dout       (mus_dout),
        .dout_sel   (mus_sel),
        .int_n      (mus_int_n),
        .sfg_l      (mus_sfg_l),
        .sfg_r      (mus_sfg_r),
        .sn_snd     (mus_sn)
    );
`endif

    assign config_req = (bus_addr[7:4] == 4'h4 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign config_dout = ( bus_addr[3:0] == 4'h0 ) ? config0_ff :
                         ( bus_addr[3:0] == 4'h1 ) ? config1_ff :
                         ( bus_addr[3:0] == 4'h2 ) ? config2_ff :
                         ( bus_addr[3:0] == 4'h3 ) ? config3_ff :
`ifdef ENABLE_MIXER
                         ( bus_addr[3:0] == 4'h4 ) ? {1'b0, mix_sel, mix_rd} :   // V3.7: canal seleccionado + su nivel
`else
                         ( bus_addr[3:0] == 4'h4 ) ? {5'b0, snd_gain_ff} :
`endif
`ifdef ENABLE_TR
                         ( bus_addr[3:0] == 4'h5 ) ? {1'b0, 1'b1, 5'b0, config_turbo_boot_ff} :   // TR (fase 1): bit 6 = "este core es el perfil TR" (sin V9990 ni OPL4)
`elsif ENABLE_DUAL
                         ( bus_addr[3:0] == 4'h5 ) ? {1'b1, 6'b0, config_turbo_boot_ff} :   // Dual (2/11/2026): bit 7 = "este core es el perfil Dual" (el menu de A lo mira antes de ofrecer la tecla D)
`else
                         ( bus_addr[3:0] == 4'h5 ) ? {7'b0, config_turbo_boot_ff} :
`endif
                         ( bus_addr[3:0] == 4'h6 ) ? { 1'b1, config6_ff[6:0] } :   // V3.5f: bit7 = 1 -> "este core trae el Game Master 2" (el menu lo sondea)
                `ifdef ENABLE_SDCARD
                         ( bus_addr[3:0] >= 4'h7 ) ? sdio_dout :     // V3.5c: #47-#4F = SD por puertos
                `endif
                         8'hff;


    always @ (posedge clk_54m) begin
        if (bus_reset_n == 0 || config_init_delay == 1 ) begin
            config_mapper_slot_ff <= config1_ff[5:4];
            config_enable_mapper3 <= (config1_ff[0] == 1 && config1_ff[5:4] == 2'b11);
            config_enable_mapper12 <= (config1_ff[0] == 1 && config1_ff[5:4] != 2'b11);
            //config_megaram_slot_ff <= config1_ff[7:6];
            config_enable_sdcard <= config2_ff[0];
            config_sdcard_slot_ff <= config2_ff[2:1];
        end
    end
    assign config_mapper_slot = config_mapper_slot_ff;
    assign config_megaram_slot = config1_ff[7:6];;
    assign config_sdcard_slot = config_sdcard_slot_ff;
    assign config_enable_megaram = config1_ff[1];
    assign config_enable_megaram3 = (config1_ff[1] == 1 && config1_ff[7:6] == 2'b11 && !tr_map);   // TR: el 3-3 es la ROM del ESP
    assign config_enable_megaram12 = (config1_ff[1] == 1 && config1_ff[7:6] != 2'b11 );
    assign config_enable_ghost_scc = config1_ff[2];

`else

    wire config_enable_mapper3;
    wire config_enable_mapper12;
    wire config_enable_megaram;
    wire config_enable_megaram3;
    wire config_enable_megaram12;
    wire config_enable_ghost_scc;
    wire config_enable_sdcard;
    wire config_enable_scanlines;
    wire [1:0] config_mapper_slot;
    wire [1:0] config_megaram_slot;
    wire [1:0] config_sdcard_slot;
    wire config_reset;
    assign config_enable_mapper3 = 1;
    assign config_enable_mapper12 = 0;
    assign config_enable_megaram = 1;
    assign config_enable_megaram3 = 1;
    assign config_enable_megaram12 = 0;
    assign config_enable_ghost_scc = 0;
    assign config_enable_sdcard = 0;
    assign config_enable_scanlines = 1;
    assign config_mapper_slot = 2'b11;
    assign config_megaram_slot = 2'b11;
    assign config_sdcard_slot= 2'b11;
    assign config_reset = 0;
    wire config_enable_stereo;
    wire config_enable_8sprites;
    assign config_enable_stereo = 0;
    assign config_enable_8sprites = 0;
    wire config_enable_16_9;
    assign config_enable_16_9 = 0;

`endif

    // v3.2 FIX REGRESION _40: gates del scc_glue calculados AQUI, con todas
    // sus señales ya declaradas (config_megaram_slot es [1:0] — ver el
    // comentario en la instancia sccglue1). Expresiones VERBATIM del glue
    // inline v2.6.
    assign scc_gate_bank2_wr3  = ( pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[3] == 1 );
    assign scc_gate_bank2_wr12 = ( config_enable_megaram12 == 1 && pri_slot == config_megaram_slot );
    assign scc_gate_req3       = ( config_enable_megaram3 == 1 && pri_slot == config_megaram_slot && exp_slotx_num[3] == 1 );
    assign scc_gate_req12      = ( config_enable_megaram12 == 1 && pri_slot == config_megaram_slot );
    assign scc_snd_dis_w       = scc_sound_disable;

    /// FLASH ROM LOADER - BIOS
    // ------------------------------------------------------------------
    //  LAYOUT DE FLASH DE LA CONSOLE 60K (W25Q64, 8 MB, compartida BL616):
    //    0x000000 - 0x3FFFFF  bitstream GW5AT-60 (.bin = ~2.26 MB; margen a 4 MB)
    //    0x400000 - 0x47FFFF  pack BIOS (512 KB)          <- antes 0x200000 (TN20K)
    //    0x480000 - 0x480005  config (6 bytes, cola del pack) <- antes 0x280000
    //    0x480006 - 0x7FFFFF  libre (~3.5 MB: futuro SRM/ROMs)
    //  El bitstream del GW5AT-60 PISA el 0x200000 del TN20K (aviso del audit
    //  §5.B confirmado). El pack se flashea ahora en 0x400000.
    // ------------------------------------------------------------------
    localparam FLASH_START_ADDRESS = 24'h400000;
    localparam FLASH_CONFIG_ADDRESS = 24'h480000;   // = FLASH_START + 512KB
    localparam RAM_START_ADDRESS = 23'h6fffff;
    localparam GOAULD_ROM_SIZE = 512*1024 + 6; //512KB + signature (AB) + config
    reg ff_rom_wr = 0;
    reg [24:0] ff_rom_addr;
    
    wire rom_write;
    wire [7:0] rom_dout;
    wire [24:0] rom_addr;
    assign rom_write = flash_busy;
    assign rom_dout = ff_rom_dout;
    assign rom_addr = ff_rom_addr;
    
    reg [31:0] ff_flash_counter;

//flash
    reg [23:0] ff_flash_addr = 24'd0;
    reg ff_flash_rd = 0;
    reg ff_flash_terminate = 0;
    reg [7:0] ff_rom_dout;
    reg flash_wait_n;
    wire[7:0] flash_dout;
    wire flash_data_ready;
    wire flash_busy;
    wire [7:0] flash_write_din;
    wire flash_write_busy;
    wire [7:0] flash_write_counter;
    wire flash_write_terminate;
    assign flash_write_din = (flash_write_counter == 8'd00) ? 8'h41 :
                             (flash_write_counter == 8'd01) ? 8'h42 :
                        `ifdef ENABLE_CONFIG
                             (flash_write_counter == 8'd02) ? config1_ff :
                             (flash_write_counter == 8'd03) ? config2_ff :
                             (flash_write_counter == 8'd04) ? (config_turbo_boot_ff ? 8'h54 : 8'h00) :
                             (flash_write_counter == 8'd05) ? {5'b11000, snd_gain_ff} : 8'hff;
                        `else
                             (flash_write_counter == 8'd02) ? CONFIG1_DEFAULT :
                             (flash_write_counter == 8'd03) ? CONFIG2_DEFAULT : 8'hff;
                        `endif
    assign flash_write_terminate = (flash_write_counter == 8'd6) ? 1 : 0;

    flash # (
        .STARTUP_WAIT(1)
    )
    flash1
    (
        .clk(clk_54m),
        .reset_n(bus_reset_n),
        .SCLK(mspi_sclk),
        .CS(mspi_cs),
        .MISO(mspi_miso),
        .MOSI(mspi_mosi),
`ifdef ENABLE_WAVE_LOADER
        // _87: el loader YRW801 toma el puerto de LECTURA cuando el pack ya
        // esta streameado (flash_idle) — el FSM del pack queda parado en
        // STATE_IDLE y el mux le devuelve el control al terminar
        .addr(wl_active ? wl_flash_addr : ff_flash_addr),
        .rd(wl_active ? wl_flash_rd : ff_flash_rd),
        .terminate(wl_active ? wl_flash_term : ff_flash_terminate),
`else
        .addr(ff_flash_addr),
        .rd(ff_flash_rd),
        .terminate(ff_flash_terminate),
`endif
        .dout(flash_dout),
        .data_ready(flash_data_ready),
        .busy(flash_busy),
        .write_enable(config_flash_write_ff),
        .write_din(flash_write_din),
        .write_busy(flash_write_busy),
        .write_counter(flash_write_counter),
        .write_terminate(flash_write_terminate),
        .write_addr(FLASH_CONFIG_ADDRESS)   // 60K: 0x480000 (antes 0x280000 en TN20K)
    );

    // /WP y /HOLD de la flash QSPI del 60K: desactivados (alto) permanentemente
    assign mspi_wp   = 1'b1;
    assign mspi_hold = 1'b1;

    reg [7:0] ff_flash_state = 8'd0;
    
    localparam STATE_RESET          = 8'd0;
    localparam STATE_READ_START     = 8'd1;
    localparam STATE_READ_LOOP      = 8'd2;
    localparam STATE_IDLE           = 8'd3;
    localparam STATE_INIT1          = 8'd4;
    localparam STATE_INIT2          = 8'd5;
    localparam STATE_INIT3          = 8'd6;
    localparam STATE_INIT4          = 8'd7;
    reg [31:0] nose = 0;
    wire flash_idle;
    assign flash_idle = (ff_flash_state == STATE_IDLE ) ? 1'b1 : 1'b0;
    
    always @(posedge clk_54m, negedge reset3_n) begin
    if (reset3_n == 0) begin
        ff_flash_state = STATE_RESET;
        ff_flash_rd <= 0;
        ff_rom_wr <= 0;
        nose <= 0;
    end else
        case (ff_flash_state)
    
            STATE_RESET: begin   // reset
`ifdef ZYNQ
                ff_flash_state <= STATE_IDLE;    // ZYNQ: el pack lo carga el PS en la DDR
`else
                ff_flash_state <= STATE_READ_START;
`endif
                ff_flash_rd <= 0;
                ff_rom_wr <= 0;
                ff_flash_terminate <= 0;
            end
    
            STATE_INIT1: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= 24'h000000;
                    ff_flash_rd <= 1;
                    ff_flash_state = STATE_INIT2;
                end
            end
    
            STATE_INIT2: begin  // start read
                if (flash_busy == 1) begin
                    ff_flash_rd <= 0;
                    ff_flash_state = STATE_INIT3;
                end
            end
            
            STATE_INIT3: begin  // start read
                if (flash_busy == 0) begin
                    nose <= 0;
                    ff_flash_terminate <= 1;
                    ff_flash_state = STATE_INIT4;
                end
            end
    
            STATE_INIT4: begin  // start read
                nose <= nose + 1;
                if (nose > 10) begin
                    ff_flash_terminate <= 0;
                    ff_flash_state = STATE_READ_START;
                end
            end
    
            STATE_READ_START: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= FLASH_START_ADDRESS;
                    ff_rom_addr <= RAM_START_ADDRESS;
                    ff_flash_rd <= 1;
                    ff_flash_state = STATE_READ_LOOP;
                    ff_flash_counter <= GOAULD_ROM_SIZE;
                end
            end
    
            STATE_READ_LOOP: begin  // loop read
                if (flash_busy == 0) begin
    
                    if (ff_flash_counter > 0) begin
                        
                        if (~ff_flash_rd) begin
    
                            ff_flash_addr <= ff_flash_addr + 1;
                            ff_flash_counter <= ff_flash_counter - 1;
                            ff_flash_rd <= 1;
    
                            ff_rom_wr <= 1;
                            ff_rom_addr <= ff_rom_addr + 1;
                            ff_rom_dout <= flash_dout; 
    
                        end
                    end else begin    
                        ff_rom_wr <= 0;
                        ff_flash_rd <= 0;
                        ff_flash_state <= STATE_IDLE;
                    end
                end else begin
                    ff_rom_wr <= 0;
                    ff_flash_rd <= 0;
                end
            end
    
            STATE_IDLE: begin  // idle
                ff_flash_terminate <= 1;
            end
    
        endcase
    end

    // configuration + signature
    reg [7:0] config_sig [0:5];
    reg [2:0] last_bytes_cnt;
    wire new_byte;
    wire config_init;
    assign new_byte = (~ff_flash_rd && flash_busy == 0);
    assign config_init = (config_sig[0] == 8'h41 && config_sig[1] == 8'h42 && last_bytes_cnt == 3'd1) ? 1 : 0;

    always @(posedge clk_54m or negedge reset3_n) begin
        if (!reset3_n) begin
            last_bytes_cnt <= 3'd0;
            config_sig[0] <= 8'd0;
            config_sig[1] <= 8'd0;
            config_sig[2] <= 8'd0;
            config_sig[3] <= 8'd0;
            config_sig[4] <= 8'd0;
            config_sig[5] <= 8'd0;
        end else begin
            if (ff_flash_counter == 32'd6)
                last_bytes_cnt <= 3'd6;
            if (new_byte && last_bytes_cnt != 3'd0) begin
                case (last_bytes_cnt)
                    3'd6: config_sig[0] <= flash_dout;
                    3'd5: config_sig[1] <= flash_dout;
                    3'd4: config_sig[2] <= flash_dout;
                    3'd3: config_sig[3] <= flash_dout;
                    3'd2: config_sig[4] <= flash_dout;
                    3'd1: config_sig[5] <= flash_dout;
                endcase
                last_bytes_cnt <= last_bytes_cnt - 1;
            end
        end
    end


// ---------------------------------------------------------------------------
// V3.1 — DESCARGAS CORRUPTAS: la tarjeta RECHAZA bloques y nadie se entera.
//
// Medido el 21/08 comparando 4 descargas del File-Hunter contra el CRC32 que
// ahora da la API: el stream llega INTACTO (ni un byte perdido, cero
// desplazamiento en todo el fichero), pero ~1 sector de cada 1120 se queda con
// el contenido ANTIGUO de la tarjeta (FF, E5, o restos de otro fichero). O
// sea: esa escritura no llego al medio, y el menu la dio por buena.
//
// LA CADENA: sd_reader captura el token de respuesta del bloque
// (sd_reader.sv:495 — 010 = aceptado) y levanta crc_error; la FSM termina
// NORMALMENTE (WTAIL->WBUSY->WDONE), busy baja, top.v lo expone en
// SDC_STATUS bit0... y el menu, que en sd_wait_idle hace "and #80", solo mira
// el bit de busy y tira crc_error a la basura. Sin reintento y sin rastro.
//
// El fuente del menu del MSXimus NO esta en este repo, asi que el reintento se
// hace AQUI: si la tarjeta rechaza el bloque no se limpia wstart, la FSM de
// comandos vuelve a IDLING, lo ve alto y repite el CMD24 con el mismo sector y
// el mismo dpram (escribir solo LEE el buffer, no lo destruye). Invisible para
// el menu y vale para las dos maquinas.
// ---------------------------------------------------------------------------

reg [15:0] sd_wr_cnt   = 16'd0;   // escrituras terminadas (TESTIGO DE VIDA)
reg [15:0] sd_wcrc_cnt = 16'd0;   // ...de ellas, RECHAZADAS por la tarjeta

// ---------------------------------------------------------------------------
// V3.1b — TRAZA DE LBA, una linea por escritura.
//
// Los bytes de un sector corrupto (F1 Spirit, sectores 29-30) resultaron ser
// una imagen SCREEN 5 — patron de 128 bytes por linea, nibbles empaquetados —
// que YA estaba en la tarjeta antes de formatearla en rapido. O sea que ese
// sector NUNCA SE ESCRIBIO: no es buffer pisado ni parser, es la escritura que
// no llego a ese LBA.
//
// Con el sistema de ficheros INTACTO (chkdsk limpio en tarjeta virgen), sin
// desplazamiento en el fichero, todas las escrituras completandose y ninguna
// rechazada, lo unico que queda es que algunas vayan a un LBA equivocado. Eso
// deduciendolo no sale: hay que VER la lista de LBA en orden.
//
// A ~53 escrituras/s y 66 bytes por linea son ~3,5 KB/s contra los 11,5 KB/s
// de 115200 baud: cabe con holgura triple.
// ---------------------------------------------------------------------------
reg [31:0] sd_wr_lba     = 32'd0;   // LBA de la ultima escritura terminada
reg        sd_wr_zero    = 1'b0;    // su carga era 512 bytes a CERO
reg        sd_wr_rej     = 1'b0;    // la tarjeta la rechazo (token != 010)
reg        sd_wr_tog     = 1'b0;    // cruce a clk_54m (dominio del dbg_uart)
reg [1:0]  sd_wr_seq     = 2'd0;    // rueda con cada escritura: una linea
                                    // repetida es un LATIDO, no una escritura

`ifdef ENABLE_SDCARD

    
   
    //megarom
    reg megarom_req;
    wire [16:0] megarom_addr;
    reg [2:0] megarom_page_ff;
    reg megarom_page_req;
    wire [2:0] megarom_page;

    always @ (posedge clk_54m) begin
        megarom_req <=     ( config_enable_sdcard == 1 && !tape_nonextor && bus_mreq_n == 0 && bus_rfsh_n == 1 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && (page_num[1] == 1 || page_num[2] == 1) ) ? 1 : 0;
        megarom_page_req <= ( bus_mreq_n == 0 && bus_rfsh_n == 1 && bus_wr_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && bus_addr == 16'h6000 ) ? 1 : 0;
    end
    assign megarom_page = megarom_page_ff;
    assign megarom_addr = { megarom_page, bus_addr[13:0] };

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
           megarom_page_ff <= 3'b0;
        end 
        else begin
`ifdef ENABLE_TR
            // TR: el R800 escribe en cualquier fase: sin la ventana del reloj de 3,58 MHz (con ella se perdian la mayoria de los cambios de banco del Nextor)
            if (1'b1) begin
`else
            if (bus_clk_3m6_27 == 1) begin
`endif
                if (megarom_page_req == 1) begin
                    megarom_page_ff <= cpu_dout[2:0]; // select page
                end
            end
        end
    end




    /*
    reg [7:0] ff_flash_state = 8'd0;

    localparam STATE_RESET          = 8'd0;
    localparam STATE_READ_START     = 8'd1;
    localparam STATE_READ_WAIT      = 8'd2;
    localparam STATE_READ_LOOP      = 8'd3;
    localparam STATE_IDLE           = 8'd4;

    always @(posedge clk_54m, negedge bus_reset_n) begin
    if (bus_reset_n == 0) begin
        ff_flash_state = STATE_RESET;
        ff_flash_rd <= 0;
        flash_wait_n <= 1;
    end else
        case (ff_flash_state)
            STATE_RESET: begin   // reset
                ff_flash_state <= STATE_READ_START;
                ff_flash_rd <= 0;
                ff_flash_terminate <= 1;
            end
            STATE_READ_START: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= 24'h100000;
                    ff_flash_state = STATE_READ_WAIT;
                end
            end
            STATE_READ_WAIT: begin  // start read
                if (megarom_req == 1) begin
                    flash_wait_n <= 0;
                    ff_flash_addr <= megarom_addr ;
                    ff_flash_rd <= 1;
                    ff_flash_terminate <= 0;
                    ff_flash_state = STATE_READ_LOOP;
                end
            end
            STATE_READ_LOOP: begin  // loop read
                if (flash_busy == 0 && ff_flash_rd <= 0) begin
                    ff_rom_dout <= flash_dout; 
                    ff_flash_state <= STATE_IDLE;
                end
                else begin
                    ff_flash_rd <= 0;
                end
            end
            STATE_IDLE: begin  // idle
                flash_wait_n <= 1;
                ff_flash_terminate <= 1;
                if (megarom_req == 0) begin
                    ff_flash_state <= STATE_READ_START;
                end
            end
        endcase
    end*/


    //sd card
    localparam int SDC_SDATA		=  16'h7C00;		 	// rw: 7C00h-7Dff - sector transfer area
    localparam int SDC_ENABLE  	    =  16'h7E00;		    // wo: 1: enable SDC register, 0: disable
    localparam int SDC_CMD			=  SDC_ENABLE+1; 		// wo: cmd to SDC fpga: 1=sd read, 2=sd write
    localparam int SDC_STATUS		=  SDC_CMD+1;	 		// ro: SDC status bits
    localparam int SDC_SADDR		=  SDC_STATUS+1;	 	// wo: 4 bytes: sector addr for read/write
    localparam int SDC_C_SIZE  	    =  SDC_SADDR+4;			// ro: 3 bytes: device size blocks
    localparam int SDC_C_SIZE_MULT	=  SDC_C_SIZE+3;		// ro: 3 bits size multiplier
    localparam int SDC_RD_BL_LEN	=  SDC_C_SIZE_MULT+1;	// ro: 4 bits block length
    localparam int SDC_CTYPE		=  SDC_RD_BL_LEN+1;		// ro: SDC Card type: 0=unknown, 1=SDv1, 2=SDv2, 3=SDHCv2 
    localparam int SDC_MID		    =  SDC_CTYPE+1;		    // ro: manufacture ID: 8 bits unsigned
    localparam int SDC_OID		    =  SDC_MID+1;		    // ro: oem id: 2 character
    localparam int SDC_PNM		    =  SDC_OID+2;		    // ro: product name: 5 character
    localparam int SDC_PSN		    =  SDC_PNM+5;		    // ro: serial number: 32 bits unsigned
    localparam int SCC_ENABLE       =  16'h7E80;            // wo: enable disable SCC+
    localparam int SDC_END          =  16'h7EFF; 
    
    wire [8:0] sram_addr_w;
    reg ff_sram_we = 0;
    reg [7:0] ff_sram_cdin;
    reg [7:0] ff_sram_cdout;
    //
    reg ff_sd_en = 0;
    reg sram_cs_w;
    wire sram_busreq_w;
    wire [7:0] sram_cd_w;
    
    wire [3:0] sd_card_stat_w;
    wire [1:0] sd_card_type_w;
    reg ff_sd_rstart;
    reg ff_sd_init;
    reg [31:0] ff_sd_sector;
    wire sd_busy_w;
    wire sd_done_w;
    wire sd_outen_w;
    wire [8:0] sd_outaddr_w;
    wire [7:0] sd_outbyte_w;
    reg ff_sd_wstart;
    wire [7:0] sd_inbyte_w;
    
    wire [21:0] sd_c_size_w;
    wire [2:0] sd_c_size_mult_w;
    wire [3:0] sd_read_bl_len_w;
    
    wire [7:0] sd_mid_w;
    wire [15:0] sd_oid_w;
    wire [39:0] sd_pnm_w;
    wire [31:0] sd_psn_w;
    wire sd_crc_error_w;
    wire sd_rcrc_error_w;   // V3.5: CRC16 de lectura mal (bit2 de SDC_STATUS)
    wire sd_timeout_error_w;
    // ---- V3.5c: SD por PUERTOS DE E/S (#47-#4F del dispositivo goauld #48) + multibloque ----
    // La ventana de memoria sigue igual. Ver sdc_ioport.sv para el mapa de puertos.
    wire       sd_blk_rdy_w;
    wire       sdio_cmd_wr;
    wire [7:0] sdio_cmd_val;
    wire [3:0] sdio_saddr_wr;
    wire [7:0] sdio_saddr_val;
    wire       sdio_data_sel;
    wire       sdio_data_wr;
    wire [7:0] sdio_data_val;
    wire [8:0] sdio_ptr;
    wire       sdio_ack;
    wire [7:0] sdio_count;
    wire [5:0] sdio_idx;          // V3.6c: 6 bits
`ifdef NEO16_16M
    wire [24:0] sdio_dma_addr;    // perfil TR: arma con C0h/C1h = bit 24
`else
    wire [23:0] sdio_dma_addr;    // V3.6: destino de la DMA (OUT #4F,80h + 3 bytes); 23/09/2026: 81h = bit 23
`endif
    wire        sdio_dma_log;     // V3.6c: modo logico (bit7 del byte alto)
    wire [15:0] dma_cnt_scc, dma_cnt_kon, dma_cnt_a8, dma_cnt_a16;   // V3.6c: patrones de mapper
    wire        dma_buf_rd, dma_ack;
    wire [8:0]  dma_buf_addr;
    wire [7:0]  dma_blocks;
    // V3.5d: la seleccion del dispositivo va REGISTRADA. Combinacional colgaba
    // MAS CARGA del IORQ_n del Z80, que es de donde salen los peores caminos del
    // chip desde siempre (los CE de config2/config6/snd_gain, clk_54m->clk_27m):
    // el dado 3187 se fue a -1,55 ns con ellos. Registrarlo no cambia nada
    // funcional -- un ciclo de clk_27m contra un ciclo de E/S de ~30.
    reg        sdio_sel = 1'b0;
    always @(posedge clk_27m) begin
        sdio_sel <= (config_enable_sdcard == 1) && (config_ok == 1) && (bus_iorq_n == 0) && (bus_m1_n == 1) && (bus_addr[7:4] == 4'h4);
    end
    reg        sd_win_cmd_wr  = 1'b0;      // orden dada por la ventana de memoria (-> count = 1)
    reg  [7:0] sd_win_cmd_val = 8'd0;      // ... y su dato, capturado en el mismo flanco
    sdc_ioport u_sdio (
        .clk(clk_27m),
        .rstn(bus_reset_n),
        .sel(sdio_sel),
        .addr(bus_addr[3:0]),
        .rd_n(bus_rd_n),
        .wr_n(bus_wr_n),
        .din(cpu_dout),
        .force1(sd_win_cmd_wr),
        .cmd_wr(sdio_cmd_wr),
        .cmd_val(sdio_cmd_val),
        .saddr_wr(sdio_saddr_wr),
        .saddr_val(sdio_saddr_val),
        .data_sel(sdio_data_sel),
        .data_wr(sdio_data_wr),
        .data_val(sdio_data_val),
        .ptr(sdio_ptr),
        .buf_ack(sdio_ack),
        .count(sdio_count),
        .info_idx(sdio_idx),
        .dma_addr(sdio_dma_addr),
        .dma_log(sdio_dma_log)
    );
    // estado por puerto: bit7 busy · bit4 bloque listo/bufer libre (multibloque) ·
    // bit3 SIEMPRE 1 (sonda: un core sin puertos devuelve FFh en #47, con los bits 6:5 a 1)
    wire [7:0] sd_io_status = { sd_busy_w | sd_wr_hold | sd_wr_fail, 2'b00, sd_blk_rdy_w, 1'b1, sd_rcrc_error_w, sd_timeout_error_w, sd_crc_error_w };
    // Byte de informacion #4E. Mismo mapa que la ventana (offset desde
    // SDC_ENABLE), pero SOLO lo que alguien lee de verdad por aqui: el CID/CSD
    // completo (MID/OID/PNM/PSN, indices 13-24) lo saca el driver de Nextor por
    // la VENTANA, y replicarlo aqui eran 12 entradas mas de un mux de 8 bits en
    // un chip que ya va al 98% de CLS y con las campanas fallando de rutado.
    wire [7:0] sd_info_dout = (sdio_idx == 5'd2)  ? sd_io_status :
                              (sdio_idx == 5'd7)  ? sd_c_size_w[7:0] :
                              (sdio_idx == 5'd8)  ? sd_c_size_w[15:8] :
                              (sdio_idx == 5'd9)  ? { 2'b0, sd_c_size_w[21:16] } :
                              (sdio_idx == 5'd10) ? { 5'b0, sd_c_size_mult_w } :
                              (sdio_idx == 5'd11) ? { 4'b0, sd_read_bl_len_w } :
                              (sdio_idx == 5'd12) ? { 6'b0, sd_card_type_w } :
                              // V3.5d: cronometro de ms (foto congelada al pedir el 25)
                              (sdio_idx == 5'd25) ? ms_snap[7:0] :
                              (sdio_idx == 5'd26) ? ms_snap[15:8] :
                              (sdio_idx == 5'd27) ? ms_snap[23:16] :
                              (sdio_idx == 5'd28) ? 8'h54 :          // firma 'T' = hay cronometro
                              (sdio_idx == 6'd29) ? 8'h44 :          // V3.6: firma 'D' = hay DMA de lectura
                              (sdio_idx == 6'd31) ? 8'h4D :          // V3.6c: firma 'M' = modo logico + contadores
                              (sdio_idx == 6'd32) ? dma_cnt_scc[7:0] :
                              (sdio_idx == 6'd33) ? dma_cnt_scc[15:8] :
                              (sdio_idx == 6'd34) ? dma_cnt_kon[7:0] :
                              (sdio_idx == 6'd35) ? dma_cnt_kon[15:8] :
                              (sdio_idx == 6'd36) ? dma_cnt_a8[7:0] :
                              (sdio_idx == 6'd37) ? dma_cnt_a8[15:8] :
                              (sdio_idx == 6'd38) ? dma_cnt_a16[7:0] :
                              (sdio_idx == 6'd39) ? dma_cnt_a16[15:8] : 8'hFF;
    // ---- V3.5d: CRONOMETRO LIBRE DE MILISEGUNDOS ----------------------------
    // POR QUE: el menu media la carga con el JIFFY de la BIOS (#FC9E), que solo
    // avanza con las interrupciones ACTIVAS; la carga corre con DI, asi que el
    // reloj se congelaba y salian cifras imposibles (2730 KB/s en placa el
    // 06/09, 16 veces el techo fisico del Z80). Este contador va con clk_27m y
    // no depende de nada del MSX.
    //
    // Se lee por el puerto de informacion que ya existe (#4E, sin decode nuevo):
    //   OUT #4E,25  -> CONGELA los 24 bits (lectura atomica) y devuelve el byte 0
    //   OUT #4E,26 / 27 -> bytes 1 y 2 de ESA MISMA foto
    //   OUT #4E,28  -> firma 'T' (0x54): un core sin cronometro devuelve FF
    reg [14:0] ms_div = 15'd0;
    reg [23:0] ms_cnt = 24'd0;
    reg [23:0] ms_snap = 24'd0;
    // La foto se congela mirando el indice YA REGISTRADO (sdio_idx), no el bus:
    // asi el disparo es puramente sincrono en clk_27m y no cuelga un camino del
    // IORQ_n del Z80, que es justo lo que se llevo por delante el margen del
    // dado 3191 por el lado del bufer.
    reg [4:0] ms_idx_d = 5'd0;
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ms_div   <= 15'd0;
            ms_cnt   <= 24'd0;
            ms_snap  <= 24'd0;
            ms_idx_d <= 5'd0;
        end else begin
            if (ms_div == 15'd26999) begin
                ms_div <= 15'd0;
                ms_cnt <= ms_cnt + 24'd1;
            end else
                ms_div <= ms_div + 15'd1;
            ms_idx_d <= sdio_idx;
            if (sdio_idx == 5'd25 && ms_idx_d != 5'd25) ms_snap <= ms_cnt;
        end
    end

    // Lo que devuelven las lecturas de #47-#4F (config_dout las toma de aqui).
    // El TAMANO de la tarjeta se lee por #4E con los indices 7-9, asi que las
    // copias que habia en #49-#4B sobraban: tres entradas menos de un mux de 8
    // bits, que en este chip (97-98% de CLS y campanas cayendose de rutado) es
    // justo lo que conviene no gastar.
    wire [7:0] sdio_dout = (bus_addr[3:0] == 4'h7) ? sd_io_status :
                           (bus_addr[3:0] == 4'h8) ? { 6'b0, sd_card_type_w } :
                           (bus_addr[3:0] == 4'hD) ? sdio_count :
                           (bus_addr[3:0] == 4'hE) ? sd_info_dout :
                           (bus_addr[3:0] == 4'hF) ? sdio_ptr[7:0] : 8'hFF;
    // un CMD17/CMD24 dado por la ventana o el puerto se reintenta solo (3 veces) si la
    // tarjeta lo rechaza; en multibloque NO: el driver retoma desde el bloque que fallo
    wire       sd_single = (sdio_count <= 8'd1);
    //reg ff_scc_enable;
    //wire scc_enable_w;
    //assign scc_enable_w = ff_scc_enable;
    always @ (posedge clk_27m) begin
        sram_cs_w <= config_enable_sdcard == 1 && bus_reset_n && ff_sd_en && bus_iorq_n == 1 && bus_m1_n == 1 && bus_mreq_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && ( bus_addr >= SDC_SDATA && bus_addr < SDC_ENABLE) ? 1 : 0;
    end
    assign sram_busreq_w = (sram_cs_w && ~bus_rd_n) || (sdio_data_sel && ~bus_rd_n);   // V3.5c: IN #4C lee el bufer
    
    dpram#(
        .widthad_a(9),
        .width_a(8)
    ) dpram1 (
        .clock_a(clk_27m),
        // V3.5c: el puerto #4C accede al mismo bufer con el puntero de sdc_ioport
        // (estable durante todo el ciclo IN/OUT; se repite la escritura del mismo
        // byte en la misma direccion mientras dura el OUT, que es inocuo)
        `ifdef ENABLE_TR
        .wren_a((sram_cs_w && ~bus_wr_n) || sdio_data_wr),   // TR: sin la ventana de 3,58 MHz (el R800 no esta alineado con ella)
`else
        .wren_a((bus_clk_3m6_27 && sram_cs_w && ~bus_wr_n) || sdio_data_wr),
`endif
`ifdef ENABLE_TR
        .rden_a((sram_cs_w && ~bus_rd_n) || (sdio_data_sel && ~bus_rd_n)),
`else
        .rden_a((bus_clk_3m6_27 && sram_cs_w && ~bus_rd_n) || (sdio_data_sel && ~bus_rd_n)),
`endif
        .address_a(sdio_data_sel ? sdio_ptr : bus_addr[8:0]),
        .data_a(sdio_data_wr ? sdio_data_val : cpu_dout),   // V3.5d: dato capturado en el modulo
        .q_a(sram_cd_w),
    
        .clock_b(clk_27m),
        .wren_b(ff_sd_rstart && sd_outen_w),
        // V3.6: la DMA lee el bufer por ESTE puerto (el de la tarjeta, ocioso en
        // RHOLD/IDLING): el mux del puerto A, que es el del camino critico de la
        // v3.5c (cpu1/IORQ_n -> dpram1 ADA), no se toca. Solo mientras dma_buf_rd.
        .rden_b((ff_sd_wstart && sd_outen_w) || dma_buf_rd),
        .address_b(dma_buf_rd ? dma_buf_addr : sd_outaddr_w),
        .data_b(sd_outbyte_w),
        .q_b(sd_inbyte_w)
    );
    
    // V3.5: sdclk a 6,75 MHz (periodo 4 de clk_27m; era 2,25 MHz con CLK_DIV=2).
    // La rafaga de 512 B pasa de 1,7 ms a 0,6 ms. Seguro porque el muestreo de
    // CMD/DAT0 ya no depende del divisor (sd_reader.sv, sddat0_s / sdcmdin_s).
    // Si una placa diera guerra: FAST_DIV 1 = 4,5 MHz, 4 = lo de siempre.
    localparam [15:0] SD_FAST_DIV = 16'd0;
    // ==== ZYNQ: proxy de sectores (zynq/sd_axi_proxy.v, HP3 @ clk_27m) en lugar de sd_reader ====
    // Misma interfaz de cliente. MODE 0: imagen de disco en la DDR cargada por xsdb
    // (tools/boot.tcl <pack> <bit> <img>). MODE 1: el ARM sirve la tarjeta real
    // (TF1/TF2) por el buzon SDBOX + IRQ_F2P. Los pines sd_* del header quedan en
    // reposo hasta que haya un breakout (entonces, sd_reader de nuevo).
    assign sd_sclk = 1'b1;
    reg  [1:0] rst27_s = 2'b00;
    always @(posedge clk_27m) rst27_s <= {rst27_s[0], frst0_n};
    wire [15:0] sd_ram_blocks;
    wire        sd_irq, sd_mode;
    sd_axi_proxy #(.DISK_BASE(32'h1100_0000), .DISK_MB(32'd224),
                   .SDBOX(32'h1FF0_0100), .SDBUF(32'h1FF1_0000)) sd1 (
        .rstn(bus_reset_n), .clk(clk_27m),
        .card_stat(sd_card_stat_w), .card_type(sd_card_type_w),
        .rstart(ff_sd_rstart), .rsector(ff_sd_sector), .rbusy(sd_busy_w), .rdone(sd_done_w),
        .outen(sd_outen_w), .outaddr(sd_outaddr_w), .outbyte(sd_outbyte_w),
        .wstart(ff_sd_wstart), .inbyte(sd_inbyte_w),
        .c_size(sd_c_size_w), .c_size_mult(sd_c_size_mult_w), .read_bl_len(sd_read_bl_len_w),
        .mid(sd_mid_w), .oid(sd_oid_w), .pnm(sd_pnm_w), .psn(sd_psn_w),
        .crc_error(sd_crc_error_w), .rcrc_error(sd_rcrc_error_w), .timeout_error(sd_timeout_error_w),
        .init(ff_sd_init), .rcount(sdio_count), .buf_ack(sdio_ack | dma_ack), .blk_rdy(sd_blk_rdy_w),
        .req_irq(sd_irq), .mode(sd_mode), .dbg_blocks(sd_ram_blocks),
        .aresetn(rst27_s[1]),
        .M_AWID(hp3_awid), .M_AWADDR(hp3_awaddr), .M_AWLEN(hp3_awlen), .M_AWSIZE(hp3_awsize),
        .M_AWBURST(hp3_awburst), .M_AWLOCK(hp3_awlock), .M_AWCACHE(hp3_awcache), .M_AWPROT(hp3_awprot),
        .M_AWQOS(hp3_awqos), .M_AWVALID(hp3_awvalid), .M_AWREADY(hp3_awready),
        .M_WID(hp3_wid), .M_WDATA(hp3_wdata), .M_WSTRB(hp3_wstrb), .M_WLAST(hp3_wlast),
        .M_WVALID(hp3_wvalid), .M_WREADY(hp3_wready),
        .M_BID(hp3_bid), .M_BRESP(hp3_bresp), .M_BVALID(hp3_bvalid), .M_BREADY(hp3_bready),
        .M_ARID(hp3_arid), .M_ARADDR(hp3_araddr), .M_ARLEN(hp3_arlen), .M_ARSIZE(hp3_arsize),
        .M_ARBURST(hp3_arburst), .M_ARLOCK(hp3_arlock), .M_ARCACHE(hp3_arcache), .M_ARPROT(hp3_arprot),
        .M_ARQOS(hp3_arqos), .M_ARVALID(hp3_arvalid), .M_ARREADY(hp3_arready),
        .M_RID(hp3_rid), .M_RDATA(hp3_rdata), .M_RRESP(hp3_rresp), .M_RLAST(hp3_rlast),
        .M_RVALID(hp3_rvalid), .M_RREADY(hp3_rready)
    );

    // ---- V3.6: DMA de LECTURA SD -> RAM (sd_dma.sv) ----------------------------
    // Orden: OUT #4F,80h + 3 bytes de destino fisico (bajo, medio, alto), OUT #4D,n
    // y OUT #47,05h (leer + DMA). La CPU se congela con el bus en reposo, el core
    // copia cada bloque del bufer a la RAM (~150 us por bloque) y da el buf_ack;
    // al acabar la orden (busy=0) suelta la CPU, que sigue en la instruccion
    // siguiente al OUT. Errores como siempre: bits 1-2 del estado.
    sd_dma u_sddma (
        .clk(clk_54m),
        .rstn(bus_reset_n),
        .start(sdio_cmd_wr && sdio_cmd_val[2] && sdio_cmd_val[0]),
        .dest(sdio_dma_addr),
        .logical(sdio_dma_log),
        .mreg0(mreg0m),
        .mreg1(mreg1m),
        .mreg2(mreg2m),
        .mreg3(mreg3m),
        .cnt_en(sdio_cmd_val[3]),
        .cnt_rst(sdio_cmd_val[4]),
        .bus_idle(wait_io & wait_m1 & bus_rd_n & bus_wr_n & bus_mreq_n & ex_bus_iorq_n & (ram_busy == 0)),
        .blk_rdy(sd_blk_rdy_w),
        .rbusy(sd_busy_w),
        .sd_err(sd_rcrc_error_w | sd_timeout_error_w),
        .buf_q(sd_inbyte_w),
        .ram_busy(ram_busy),
        .active(dma_active),
        .frz(dma_frz),
        .buf_addr(dma_buf_addr),
        .buf_rd(dma_buf_rd),
        .ack(dma_ack),
        .ram_req(dma_ram_req),
        .ram_addr(dma_ram_addr),
        .ram_din(dma_ram_din),
        .blocks(dma_blocks),
        .rfsh_ok(dma_rfsh_ok),
        .cnt_scc(dma_cnt_scc),
        .cnt_kon(dma_cnt_kon),
        .cnt_a8(dma_cnt_a8),
        .cnt_a16(dma_cnt_a16)
    );
    
    assign sd_dat1 = 1;
    assign sd_dat2 = 1;
    assign sd_dat3 = 1; // Must set sddat1~3 to 1 to avoid SD card from entering SPI mode
    
    
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ff_sd_en <= 0;
        end else begin
            if (config_enable_sdcard == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && bus_addr == SDC_ENABLE && ~bus_wr_n && bus_iorq_n && bus_m1_n) 
                ff_sd_en <= cpu_dout[0];
        end
    end
    
    reg sd_cs_w;
    always @ (posedge clk_27m) begin
        sd_cs_w <= config_enable_sdcard == 1 && bus_reset_n && ff_sd_en && bus_iorq_n && bus_m1_n && bus_mreq_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && (bus_addr >= SDC_ENABLE && bus_addr <= SDC_END) ? 1 : 0;
    end
    // V3.5c/d: orden dada por la VENTANA. Registrada, por lo mismo que todo lo
    // del modulo de puertos: sin registrar, este termino colgaba del WR_n del
    // Z80 y llegaba al CE de sd_wr_fail (-0,791 ns en el dado 3209).
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            sd_win_cmd_wr  <= 1'b0;
            sd_win_cmd_val <= 8'd0;
        end else begin
            sd_win_cmd_wr  <= sd_cs_w && ~bus_wr_n && (bus_addr == SDC_CMD);
            if (sd_cs_w && ~bus_wr_n && (bus_addr == SDC_CMD)) sd_win_cmd_val <= cpu_dout;
        end
    end
    wire sd_busreq_w;
    assign sd_busreq_w = sd_cs_w && ~bus_rd_n;
    reg [7:0] ff_sd_cd;
    wire [7:0] sd_cd_w;
    assign sd_cd_w = ff_sd_cd;
    
    // acumulador del OR de la carga: si al terminar sigue a 0, iban 512 ceros
    reg sd_wr_nz = 1'b0;
    always @(posedge clk_27m) begin
        if (ff_sd_wstart) sd_wr_nz <= sd_wr_nz | (|sd_inbyte_w);
        if (sd_wr_done_edge) begin
            sd_wr_lba  <= ff_sd_sector;
            sd_wr_zero <= ~(sd_wr_nz | (|sd_inbyte_w));
            sd_wr_rej  <= sd_crc_error_w;
            sd_wr_nz   <= 1'b0;
            sd_wr_tog  <= ~sd_wr_tog;      // un cambio de nivel = una linea
            sd_wr_seq  <= sd_wr_seq + 2'd1;  // distingue escritura de LATIDO
        end
    end

    reg       sd_done_d  = 1'b0;
    reg       sd_tmo_d   = 1'b0;
    reg [1:0] sd_wretry  = 2'd0;
    reg [1:0] sd_rretry  = 2'd0;
    reg       sd_wr_hold = 1'b0;
    reg       sd_wr_fail = 1'b0;

    // V3.5: TODO por FLANCO. rdone es un nivel (y durante un CMD12 de
    // cancelacion se queda alto CIENTOS de ciclos), y timeout_error es sticky
    // hasta el siguiente comando. Con el borrado por nivel, una orden que el
    // Z80 escribiera en esa ventana se perdia SIN error: busy nunca subia y el
    // menu daba por buena una lectura que no habia ocurrido (la "carrera del
    // strobe" cazada el 01/09; el menu la tapa con sd_cmd_go, aqui se cierra en
    // el RTL para que Nextor tampoco la sufra).
    wire sd_done_edge    = sd_done_w && !sd_done_d;
    wire sd_tmo_edge     = sd_timeout_error_w && !sd_tmo_d;
    wire sd_wr_done_edge = sd_done_edge && ff_sd_wstart;
    wire sd_rd_done_edge = sd_done_edge && ff_sd_rstart && !ff_sd_wstart;
    wire sd_wr_rechazado = sd_wr_done_edge && sd_crc_error_w && !sd_timeout_error_w && sd_single;   // V3.5c: solo monobloque
    wire sd_wr_again     = sd_wr_rechazado && (sd_wretry != 2'd3);
    wire sd_wr_giveup    = sd_wr_rechazado && (sd_wretry == 2'd3);
    // V3.5: lectura con CRC16 mal -> repetir el CMD17 (hasta 3 veces), igual que
    // el token de escritura. Si aun asi falla, la lectura TERMINA (no se deja
    // busy pegado: el dato puede ser malo, y bit2 de SDC_STATUS lo dice) para
    // que un driver que no mira bit2 se comporte exactamente como hasta hoy.
    wire sd_rd_rechazado = sd_rd_done_edge && sd_rcrc_error_w && !sd_timeout_error_w && sd_single;   // V3.5c: solo monobloque
    wire sd_rd_again     = sd_rd_rechazado && (sd_rretry != 2'd3);
    wire sd_again        = sd_wr_again | sd_rd_again;

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ff_sd_rstart <= '0;
            ff_sd_wstart <= '0;
            sd_done_d  <= 1'b0;
            sd_tmo_d   <= 1'b0;
            sd_wretry  <= 2'd0;
            sd_rretry  <= 2'd0;
            sd_wr_hold <= 1'b0;
            sd_wr_fail <= 1'b0;
            ff_sd_init <= '0;
        end else begin
            sd_done_d <= sd_done_w;
            sd_tmo_d  <= sd_timeout_error_w;

            // Contadores y reintento SOLO en el flanco de subida de done: rdone
            // es un nivel (vale mientras sdcmd_stat==WRITING2 && WDONE) y por
            // nivel se contaria varias veces la misma escritura.
            if (sd_wr_done_edge) begin
                sd_wr_cnt <= sd_wr_cnt + 16'd1;
                if (sd_crc_error_w) sd_wcrc_cnt <= sd_wcrc_cnt + 16'd1;
                sd_wretry <= sd_wr_again ? (sd_wretry + 2'd1) : 2'd0;
            end
            if (sd_rd_done_edge) begin
                sd_rretry <= sd_rd_again ? (sd_rretry + 2'd1) : 2'd0;
            end

            // Tapa el hueco de busy: entre WDONE y el CMD24 del reintento la
            // FSM pasa por IDLING, y el Z80 sondea SDC_STATUS cada ~12 us. Sin
            // esto podria colarse justo ahi, darlo por escrito y empezar a
            // meter el siguiente sector en el dpram que el reintento esta
            // leyendo. (V3.5: tambien para el reintento de lectura.)
            if (sd_again)         sd_wr_hold <= 1'b1;
            else if (sd_busy_w)   sd_wr_hold <= 1'b0;

            // Reintentos agotados: dejar busy ALTO hasta el siguiente SDC_CMD.
            // Asi el sd_wait_idle del menu agota su backstop (~2-3 s), pone
            // SD_STATUS=3 y la descarga aborta CON ERROR VISIBLE, en vez de
            // seguir y dejar el fichero corrupto en silencio.
            if (sd_wr_giveup) sd_wr_fail <= 1'b1;
            else if (sd_win_cmd_wr || sdio_cmd_wr) sd_wr_fail <= 1'b0;

            // V3.5c: la misma orden y el mismo LBA, por los puertos #47-#4B.
            // V3.5d: el dato viene YA CAPTURADO del modulo (sdio_*_val): aqui no
            // se vuelve a mirar el bus, que es lo que colgaba los caminos malos.
            if (sdio_cmd_wr) begin
                ff_sd_rstart <= ff_sd_rstart | sdio_cmd_val[0];
                ff_sd_wstart <= ff_sd_wstart | sdio_cmd_val[1];
                ff_sd_init   <= ff_sd_init   | sdio_cmd_val[7];
            end
            if (sdio_saddr_wr[0]) ff_sd_sector[ 7: 0] <= sdio_saddr_val;
            if (sdio_saddr_wr[1]) ff_sd_sector[15: 8] <= sdio_saddr_val;
            if (sdio_saddr_wr[2]) ff_sd_sector[23:16] <= sdio_saddr_val;
            if (sdio_saddr_wr[3]) ff_sd_sector[31:24] <= sdio_saddr_val;

            // Los strobes se sueltan en el FLANCO de done o de timeout, nunca
            // por nivel. Un reintento (sd_again) los conserva para que IDLING
            // reemita el mismo comando con el mismo sector.
            if ((sd_done_edge || sd_tmo_edge) && !sd_again) begin
                ff_sd_rstart <= '0;
                ff_sd_wstart <= '0;
            end

            // V3.5d (07/09, doble check): la orden por la VENTANA va por el MISMO
            // strobe registrado que pone count=1 en el modulo (force1), y con su
            // dato capturado en el mismo flanco. POR QUE: al registrar
            // sd_win_cmd_wr, rstart (que se ponia aqui abajo, en el case, desde
            // el bus) iba UN CICLO POR DELANTE de count, y sd_reader elige
            // CMD17/CMD18 en el mismo flanco en que ve rstart: tras un cluster
            // por puertos (count=64) la lectura de la FAT por ventana habria
            // salido como CMD18 sin CMD12 -- la tarjeta se queda en rafaga y
            // todo lo siguiente lee basura. Con el 3169 (force1 combinacional)
            // no pasaba; con el 3257 si. Por eso el 3257 no se entrega.
            if (sd_win_cmd_wr) begin
                ff_sd_rstart <= ff_sd_rstart | sd_win_cmd_val[0];
                ff_sd_wstart <= ff_sd_wstart | sd_win_cmd_val[1];
                ff_sd_init   <= ff_sd_init   | sd_win_cmd_val[7];
            end

            if (sd_cs_w) begin
                if (~bus_wr_n) begin
                    case(bus_addr) 
                        SDC_CMD: begin
                            // V3.5d: ver sd_win_cmd_wr, justo arriba
                        end
                        SDC_SADDR+0:    ff_sd_sector[ 7: 0] <= cpu_dout;
                        SDC_SADDR+1:    ff_sd_sector[15: 8] <= cpu_dout;
                        SDC_SADDR+2:    ff_sd_sector[23:16] <= cpu_dout;
                        SDC_SADDR+3:    ff_sd_sector[31:24] <= cpu_dout;
                    endcase
                end else
                if (~bus_rd_n) begin
                    case(bus_addr) 
                        SDC_ENABLE:     ff_sd_cd <= { 7'b0, ff_sd_en };
                        // bit7 busy · bit2 CRC de LECTURA mal (V3.5) · bit1 timeout · bit0 token de escritura rechazado
                        // (V3.5c: bit4 = bloque listo / bufer libre del multibloque; bit3 queda a 0 en la ventana)
                        SDC_STATUS:     ff_sd_cd <= { sd_busy_w | sd_wr_hold | sd_wr_fail, 2'b0, sd_blk_rdy_w, 1'b0, sd_rcrc_error_w, sd_timeout_error_w, sd_crc_error_w };
                        SDC_C_SIZE+0:   ff_sd_cd <= sd_c_size_w[7:0];
                        SDC_C_SIZE+1:   ff_sd_cd <= sd_c_size_w[15:8];
                        SDC_C_SIZE+2:   ff_sd_cd <= { 2'b0, sd_c_size_w[21:16] };
                        SDC_C_SIZE_MULT:ff_sd_cd <= { 5'b0, sd_c_size_mult_w };
                        SDC_RD_BL_LEN:  ff_sd_cd <= { 4'b0, sd_read_bl_len_w };
                        SDC_CTYPE:      ff_sd_cd <= { 6'b0, sd_card_type_w };
                        SDC_MID:        ff_sd_cd <= sd_mid_w;
                        SDC_OID+0:      ff_sd_cd <= sd_oid_w[7:0];
                        SDC_OID+1:      ff_sd_cd <= sd_oid_w[15:8];
                        SDC_PNM+0:      ff_sd_cd <= sd_pnm_w[7:0];
                        SDC_PNM+1:      ff_sd_cd <= sd_pnm_w[15:8];
                        SDC_PNM+2:      ff_sd_cd <= sd_pnm_w[23:16];
                        SDC_PNM+3:      ff_sd_cd <= sd_pnm_w[31:24];
                        SDC_PNM+4:      ff_sd_cd <= sd_pnm_w[39:32];
                        SDC_PSN+0:      ff_sd_cd <= sd_psn_w[7:0];
                        SDC_PSN+1:      ff_sd_cd <= sd_psn_w[15:8];
                        SDC_PSN+2:      ff_sd_cd <= sd_psn_w[23:16];
                        SDC_PSN+3:      ff_sd_cd <= sd_psn_w[31:24];
                        default:        ff_sd_cd <= '1;
                    endcase
                end
            end
        end
    end

`else

    wire sd_busreq_w;
    wire sram_busreq_w;
    wire sdio_data_sel = 1'b0;      // V3.5c: sin SD no hay puertos
    wire megarom_req;
    wire megarom_page_req;
    wire sram_cs_w;
    wire sd_cs_w;

`endif

    // Switched I/O ports
    reg [1:0] Slot2Mode;
    wire [7:0] io42_id212;
    wire iSlt2_linear;
    wire swio_req;
    wire swio_req_r;
    wire swio_req_w;
    wire [7:0] swio_dout;
    assign swio_req_r = (config_enable_megaram == 1 && bus_addr[7:4] == 4'b0100 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign swio_req_w = (config_enable_megaram == 1 && bus_addr[7:4] == 4'b0100 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign swio_req = swio_req_r | swio_req_w;

    switched_io_ports ocm_ports (
            .clk21m        (clk_27m),
            .reset         (~bus_reset_n) ,
            .power_on_reset(1),
            .req           (swio_req   ),
            .ack           (           ),
            .wrt           (~bus_wr_n ),
            .adr           (bus_addr   ),
            .dbi           (swio_dout     ),
            .dbo           (cpu_dout      ),
            .io42_id212    (io42_id212    ),
            .iSlt2_linear  (iSlt2_linear  )
        );

    // virtual DIP-SW assignment (2/2)
    always @ ( posedge clk_27m )  begin
        Slot2Mode[1]    <=  io42_id212[4];
        Slot2Mode[0]    <=  io42_id212[5];
    end

    wire send;
    monostable mono2 (
        .pulse_in(s2_press),
        .clock(clk_27m),
        .pulse_out(send)
    );

//    msx2p_debug debug1 (
//        .clk_27m(clk_27m),
//        .clk (clk_27m),
//        .reset_n ( bus_reset_n ),
//        .clk_enable (clk_enable_3m6_27),
//        .bus_addr(bus_addr),
//        .bus_data(cpu_din),
//        .bus_iorq_n(bus_iorq_n),
//        .bus_mreq_n(bus_mreq_n),
//        .bus_wr_n(bus_wr_n),
//        .send(send),
//        .uart_tx(usb_uart_tx),
//        .boot_ok( )
//    );

    // timing_debug debug1 removed for production: it registered high-fanout bus
    // strobes + a UART, costing area/routing at 91% CLS for a dev-only feature.
    // Re-add temporarily if bus timing needs probing over the USB-C UART.
`ifdef ENABLE_V9968_VDP
    // _121diag: telemetria del shim V9968 (ASCII 115200): "D <miss>
    // <complA> <complB>" cada 200ms. Sale por E22 (dbg_pmod1[4], donde
    // vive el CH340 de COM11) — ver el mux junto a los assigns de PMOD.
    // _133 VUMETRO (bug #14): pico de |audio_sample| EN LA FUENTE (el
    // registro del mezclador, dominio clk_27m) por ventana de ~0.31s
    // (2^23 ciclos) con retencion. Junto con amp_hdmi (pico de lo que
    // consume el HDMI, desde msx2hdmi_v9968) discrimina durante un corte
    // audible: ambos picos altos = receptor; fuente alta y hdmi bajo =
    // CDC congelado; ambos bajos = el mezclador se calla de verdad.
    reg  [15:0] amp_src_acc = 16'd0, amp_src = 16'd0;
    reg  [22:0] amp_src_win = 23'd0;
    wire [15:0] asrc_abs = audio_sample[15] ? (~audio_sample + 16'd1)
                                            : audio_sample;
    always @(posedge clk_27m) begin
        amp_src_win <= amp_src_win + 23'd1;
        if (amp_src_win == 23'd0) begin
            amp_src     <= amp_src_acc;
            amp_src_acc <= 16'd0;
        end
        else if (asrc_abs > amp_src_acc) amp_src_acc <= asrc_abs;
    end

    wire usb_uart_tx_int;
    // el pulso nace en clk_27m y el dbg_uart vive en clk_54m: 2FF y flanco
    reg [2:0] sd_wr_tog_s = 3'b000;
    always @(posedge clk_54m) sd_wr_tog_s <= {sd_wr_tog_s[1:0], sd_wr_tog};
    wire sd_wr_trig = sd_wr_tog_s[2] ^ sd_wr_tog_s[1];

    dbg_uart #(.CLK_HZ(53_996_000)) u_dbguart (
        .trig(1'b0),        // vuelta al modo PERIODICO: para el bring-up del
                            // SPI interesa una lectura continua, no una linea
                            // por evento de escritura a la SD (que ya no hay)
        .clk(clk_54m), .rst_n(bus_reset_n),
        // _148 FIX C: {miss de SPRITE[15:0], miss de FONDO[15:0]} — antes la
        // palabra entera era el miss de fondo. Los sprites tenian CERO
        // visibilidad en placa (el thrash del DEVCON paso desapercibido).
        // Lectura en dbg_audio_reader.py: spmiss = w0 >> 16, bgmiss = w0 & 0xFFFF.
        .cnt_a(v68dbg_miss),
        .cnt_b({aud_rst_cnt, aud_lock_cnt}),      // _127H: {resets HDMI, toggles lock}
`ifdef ENABLE_VRAM_AXI
        // _128X: los 8 bits libres [23:16] llevan el diag de la DDR3
        // ({calib_drop, wd_fires[2:0], wd_ops[3:0]}); sano = 00
        .cnt_c({v68_dbg_apkt[31:24], vddr_diag, v68_dbg_apkt[15:0]}),
`else
        .cnt_c(v68_dbg_apkt),                     // _127I: {ovr, 0, paquetes_audio}
`endif
        // _134: los 11 bits libres llevan {tear[4:0], defer[5:0]} del yank
        .cnt_d({fan_en_o, v68_dbg_tear, v68_dbg_defer, fan_dbg_cnt}),
`ifdef ENABLE_VRAM_AXI
        .cnt_e(vddr_ops),                         // _129b: ops DDR3 servidas
`else
        .cnt_e({amp_src, amp_hdmi}),              // _133: vumetro {fuente, hdmi}
`endif
        // _154: 6a palabra = drops del shim ({s1_pfq[15:0], wq_full[15:0]}).
        // SANO = 00000000. Cualquier valor distinto en placa = escrituras o
        // prefetches PERDIDOS de verdad — el sismografo del frente Aleste.
        // _161c: los 8 bits ALTOS (hoy siempre 0, el shim solo usa 16+16 en la
        // mitad baja... ojo: usa los 32) NO caben; el diagnostico del ADPCM va
        // en cnt_g, palabra NUEVA (7a) — ver abajo.
        .cnt_f(v68dbg_drops),
        // _161c CAZA DE LOS CRUJIDOS DE LA VOZ: salud del camino de samples
        // del MSX-Audio, que desde la _160 vive en la SDRAM. Nibble alto =
        // wq_lost (bytes de la subida PERDIDOS: el "imposible"), nibble bajo =
        // wd_hits (disparos del watchdog del handshake = lectura que no llego
        // a tiempo). SANO = 00. Si al cantar la voz esto sube, el crujido es
        // del camino de memoria; si se queda en 00, el camino esta impoluto y
        // el culpable es el remuestreador (alias 49,7k->44,1k).
        // CAZA DEL RATON (18/08): los 24 bits que aqui estaban a cero llevan
        // ahora el estado completo del raton USB. El ADPCM conserva su byte.
        //   [31:30] typ de USB2   [29:28] typ de USB1  (0 nada,1 tecl,2 raton,3 gpad)
        //   [27] conerr USB2      [26] conerr USB1
        //   [25] raton visto (pegajoso)   [24] el MSX sondea el puerto 2
        //   [23:21] fase de la maquina    [20] pin 8 del puerto 2
        //   [19:12] informes de RATON     [11:8] informes de cualquier tipo
        //   [7:0]  diag del ADPCM (lo de siempre)
        // Lectura: tools/dbg_mouse_reader.py
        // V3.1: el raton esta APARCADO, asi que esta palabra pasa a la caza
        // de las descargas corruptas, que es lo que bloquea de verdad.
        //   [31:16] ESCRITURAS de sector terminadas  <- TESTIGO DE VIDA
        //   [15:0]  ...de ellas, RECHAZADAS por la tarjeta (token != 010)
        // El testigo es lo que faltaba en la ronda anterior: con los contadores
        // del WiFi no se distinguia "cero fallos" de "no estoy midiendo". Aqui
        // el de arriba TIENE que subir ~1 por sector durante la descarga.
        // Lectura: dbg_wifi_reader.py
        // V3.1b: una linea POR ESCRITURA con el LBA de destino.
        //   [29] la tarjeta la rechazo   [28] la carga eran 512 ceros
        //   [27:0] LBA (28 bits = hasta 128 GB)
        // Lectura: tools/dbg_lba_reader.py
        // V3.1f: la traza de LBA ya no sirve (la BIOS V3.1 no descarga nada),
        // asi que esta palabra pasa al bring-up del enlace con el S3:
        //   [31:16] bytes HID recibidos del S3   <- TESTIGO DE VIDA
        //   [15:0]  cambios del vector de teclado
        // Lectura: tools/dbg_spi_reader.py
        .cnt_g(32'd0),                  // (eran los testigos del SPI del S3)
        .tx(usb_uart_tx_int)
    );
    assign usb_uart_tx = usb_uart_tx_int;   // (por si el USB-C tambien escucha)
`else
    assign usb_uart_tx = 1'b1;      // UART idle
`endif

    // ===== STANDALONE MERGE: discrete status LEDs (active low) — from MSXnano =====
    // LED[5] TURBO: solid = turbo ON (~4.13MHz); blink (~1.8Hz) = real-MSX speed (also "alive"). LED[4] SD busy;
    // LED[3] joy0 fire B; LED[2] joy0 fire A; LED[1] joy0 any dir; LED[0] joy1 any input
    // _71: LED de TURBO en los LEDs VISIBLES del 60K. En esta placa solo
    // led[0] (G11) y led[1] (U12) tienen pin fisico; el indicador de turbo
    // del nano vivia en led[5] = aqui sin pin (nunca visible). Codificacion
    // AGNOSTICA a la polaridad (no confirmada en el 60K): parpadeo RAPIDO
    // ~6.8Hz = turbo ON, LENTO ~1.7Hz = velocidad real MSX (y "estoy vivo").
    // led[1] = actividad SD (transitoria: legible con cualquier polaridad).
    reg [20:0] led_cnt;
    always @(posedge clk_54m or negedge bus_reset_n) begin
        if (!bus_reset_n) led_cnt <= 0;
        else if (clk_enable_3m6_54) led_cnt <= led_cnt + 1'b1;
    end

    // _115: LEDs restaurados (el estado del video vive PERMANENTE en la
    // telemetria UART: byte15 nibble alto = {pll27_lock, frame_cnt[2:0]},
    // lector tools/dbg_video_reader.py — diagnostico de HDMI sin cables).
    assign led[0] = turbo ? led_cnt[18] : led_cnt[20];  // VISIBLE (G11): rapido=turbo, lento=normal
    assign led[1] = ~sd_busy_w;                         // VISIBLE (U12): actividad SD
    assign led[5] = turbo ? 1'b0 : led_cnt[20];         // sin pin en el 60K (semantica nano conservada)
    assign led[4] = ~sd_busy_w;
`ifdef ENABLE_DUAL
    assign led[3] = ~b_focus;                           // Dual: led_z[3] = el teclado esta en B
    assign led[2] = ~b_running;                         //       led_z[2] = B corre
`else
    assign led[3] = ~joystick0[5];
    assign led[2] = ~joystick0[4];
`endif

    // ---- DEBUG BRING-UP 60K, PMOD0 = vitales + sondas de VIDEO ----
    //  [0] fuera de reset · [1] pack cargado · [2] Z80 ejecutando (M1)
    //  [3] FRAME HDMI corriendo (~1Hz) · [4] hdmi_reset pulsando (stretcher)
    wire dbg_m1_led, dbg_vrst_led;
    led_stretch #(.HOLD(1350000)) dbg_st_m1 (
        .clk(clk_27m), .rst_n(bus_reset_n), .trig(~bus_m1_n), .active(dbg_m1_led));
    // ---- SONDAS DE VIDEO r2 (SOLO lo necesario encendido; resto APAGADO) ----
    //  PMOD0: [0]=vdp_hdmi_reset pulsando (stretch) · [1]=video_reset pulsando
    //         (stretch) · [2]=reset_w nivel · [3]=OFF · [4]=OFF
    //  PMOD1: [0]=pal_mode nivel · [1]=frame NTSC ~1Hz · [2]=frame PAL ~1Hz ·
    //         [3..5]=OFF
    wire dbg_vdprst_led, dbg_vidrst_led;
    led_stretch #(.HOLD(1350000)) dbg_st_vdprst (
        .clk(clk_27m), .rst_n(bus_reset_n), .trig(dbg_video_w[1]), .active(dbg_vdprst_led));
    led_stretch #(.HOLD(1350000)) dbg_st_vidrst (
        .clk(clk_27m), .rst_n(bus_reset_n), .trig(dbg_video_w[4]), .active(dbg_vidrst_led));
    reg [5:0] dbg_fdiv_ntsc = 0, dbg_fdiv_pal = 0;
    reg dbg_ftn_d = 0, dbg_ftp_d = 0;
    always @(posedge clk_27m) begin
        dbg_ftn_d <= dbg_video_w[2];
        if (dbg_video_w[2] && !dbg_ftn_d) dbg_fdiv_ntsc <= dbg_fdiv_ntsc + 1'b1;
        dbg_ftp_d <= dbg_video_w[3];
        if (dbg_video_w[3] && !dbg_ftp_d) dbg_fdiv_pal <= dbg_fdiv_pal + 1'b1;
    end
    // ⚠ Modulos PMOD-LED ACTIVOS A NIVEL BAJO (LED ON = pin 0): niveles invertidos
    //   para que "encendido" = "activo"; sobrantes a 1 (= apagados).
    //  r3: vitales del lado MSX (el video ya esta demostrado: señal + frames)
    wire dbg_rambusy_led;
    led_stretch #(.HOLD(1350000)) dbg_st_ram (
        .clk(clk_27m), .rst_n(bus_reset_n), .trig(ram_busy), .active(dbg_rambusy_led));
    // r4: ¿estan vivos los relojes INTERNOS que gobiernan memoria y bus?
    //  - VideoDHClk (strobe del VDP): sin el, mem1 NUNCA acepta peticiones
    //  - clk_enable_3m6_54 (enable del bus 3.58M): sin el, el Z80 no avanza
    reg dbg_dh_d = 0;  reg [22:0] dbg_dh_cnt = 0;
    always @(posedge clk_108m) begin
        dbg_dh_d <= VideoDHClk;
        if (VideoDHClk && !dbg_dh_d) dbg_dh_cnt <= dbg_dh_cnt + 1'b1;
    end
    reg [20:0] dbg_en36_cnt = 0;
    always @(posedge clk_54m) begin
        if (clk_enable_3m6_54) dbg_en36_cnt <= dbg_en36_cnt + 1'b1;
    end
    // r5: ¿bucle de soft-reset o recarga colgada? ¿el menu llega a dibujar?
    wire dbg_vdpwr_led, dbg_cfgrst_led;
    led_stretch #(.HOLD(1350000)) dbg_st_vdpwr (
        .clk(clk_27m), .rst_n(1'b1), .trig(~vdp_csw_n), .active(dbg_vdpwr_led));
    led_stretch #(.HOLD(2000000)) dbg_st_cfgrst (    // ~74ms (max del contador de 21b)
        .clk(clk_27m), .rst_n(1'b1), .trig(config_reset), .active(dbg_cfgrst_led));
    // r7 (_23dbg): FORENSE DE CUELGUES (SCREEN 3 / F11) — clasifica el cuelgue:
    //  wait clavado + ram_busy fijo = arbitro de memoria; INT muerto con CPU
    //  viva = interrupcion del VDP; todo vivo pero sin M1 = CPU en HALT.
    wire dbg_m1act_led;
    // sondas en el dominio de 54M: no cargar el arbol de 27M (hold de paleta)
    led_stretch #(.HOLD(2000000)) dbg_st_m1act (
        .clk(clk_54m), .rst_n(1'b1), .trig(~bus_m1_n), .active(dbg_m1act_led));
    reg [6:0] dbg_intdiv = 0;   // 7b: parpadeo ~0.5Hz (y nudge de placement)
    reg dbg_int_d = 0;
    always @(posedge clk_54m) begin
        dbg_int_d <= bus_int_n;
        if (!bus_int_n && dbg_int_d) dbg_intdiv <= dbg_intdiv + 1'b1;  // flanco INT
    end
`ifdef VIDEO720
    // POLITICA DE LEDs (v3.9, peticion del usuario): TODO apagado por defecto;
    // solo se enciende lo que el diagnostico ACTIVO necesita, y solo en UN
    // modulo (PMOD1). El panel de video del PMOD0 cumplio su mision (_37) y
    // queda APAGADO (activo-bajo: 1 = LED off). Para reactivarlo, restaurar
    // los assigns de dbg_bridge_w de la historia git (commit 1f36a67).
    assign dbg_pmod0[0] = 1'b1;
    assign dbg_pmod0[1] = 1'b1;
    assign dbg_pmod0[2] = 1'b1;
    assign dbg_pmod0[3] = 1'b1;
    assign dbg_pmod0[4] = 1'b1;
`else
    assign dbg_pmod0[0] = wait_io;            // LED ON = CPU RETENIDA EN WAIT (clavado=malo)
    assign dbg_pmod0[1] = ~ram_busy;          // LED ON = ram_busy activo (fijo=arbitro atascado)
    assign dbg_pmod0[2] = dbg_intdiv[6];      // PARPADEO ~0.5Hz = interrupciones VDP vivas
    assign dbg_pmod0[3] = ~dbg_m1act_led;     // LED ON = CPU ejecutando (M1); OFF = congelada
    assign dbg_pmod0[4] = bus_int_n;          // LED ON = LINEA INT ASERTADA (fijo=TORMENTA de int)
`endif

    // r10 (_30dbg): CADENA DEL PSG en PMOD1
    wire dbg_psgwr_led, dbg_psgout_led;
    led_stretch #(.HOLD(2000000)) dbg_st_psgwr (
        .clk(clk_54m), .rst_n(1'b1), .trig(psgBdir), .active(dbg_psgwr_led));
    led_stretch #(.HOLD(2000000)) dbg_st_psgout (
        .clk(clk_54m), .rst_n(1'b1), .trig(|psgSound1), .active(dbg_psgout_led));
    // ===== v4.0 (_55 FINAL): POLITICA DE LEDs — TODO APAGADO =====
    // El panel de diagnostico del SCC (_42.._54) cumplio su mision: el bug del
    // silicio quedo identificado y arreglado (ver scc_wave2 v_54). Paneles
    // anteriores (video _37, PSG r10, SCC _42-54, USB _39) disponibles en git.
    assign dbg_pmod1[0] = 1'b1;
    assign dbg_pmod1[1] = 1'b1;
    assign dbg_pmod1[2] = 1'b1;
    assign dbg_pmod1[3] = 1'b1;
`ifdef WIFI_TAP_BL616TX
    assign dbg_pmod1[4] = bl616_jtagsel;     // E22 = ESPEJO del TX del BL616 (V14) para pinchar con el CH340
`else
    // _111b: la telemetria GANA el pin E22. (La rama ENABLE_WIFI que sacaba
    // aqui el espejo de la UART del WiFi era un resto de diagnostico _77 y
    // le robaba el pin a la telemetria: el lector no veia NADA.)
`ifdef ENABLE_V9968_VDP
    // _121diag: E22 (el CH340 de COM11) pasa a llevar la telemetria del
    // SHIM (dbg_uart ASCII 115200) — la del motor wave (_111) cede el pin
    // en las builds V9968 de diagnostico; usb_uart_tx no llega al PC.
    // DECISION 26/08 (v3.1, Albert): este pin se QUEDA encendido en la release.
    // No es un resto de diagnostico olvidado: el README lo anuncia como
    // caracteristica ("telemetria por puerto serie para diagnostico") y es el
    // unico canal para diagnosticar la placa de alguien a distancia. Sale por
    // E22 y TAMBIEN por la UART del USB-C (usb_uart_tx, mas abajo).
    // Todo lo demas de los dos PMOD esta apagado (a 1: activo-bajo).
    // Candidato a caer en la V4, que se recompila igualmente: cuesta el modulo
    // dbg_uart mas los acumuladores del vumetro, y el CLS va al 76%.
    assign dbg_pmod1[4] = usb_uart_tx_int;
`else
    assign dbg_pmod1[4] = opl4_dbg_tx;   // _111: telemetria del motor wave
`endif
`endif
    // dbg_pmod1[5]/D22 eliminado: pasa a uart_pmod_rx (input) para el modo PMOD test

    // ===== External WS2812B status strip (8 LEDs, e.g. CJMCU-2812-8) on the case =====
    // One data pin (ws2812_led) drives the whole chain; colours from internal state.
    wire caps_on  = ~ppi_port_c[6];                       // MSX CAPS LED (PPI port C bit6, active-low)
    wire kana_on  = keyboard[106];                        // CODE/KANA key held (Left Alt)
    wire joy_on   = (|joystick0[5:0]) | (|joystick1[5:0]);
    wire kbd_raw  = |keyboard;                            // any key held
`ifdef ENABLE_WIFI
`ifdef ENABLE_WIFI_ESP32
    wire wifi_raw = ~bl616_uart_tx_w | ~esp_rx_i | (zq_netps_s[1] & ~uart1_tx_w);   // WiFi UART active (idle = high; _153: ESP32-C6; 25/09: o la UART1 del PS)
`else
    wire wifi_raw = ~bl616_uart_tx_w | ~bl616_jtagsel;    // WiFi UART active (idle = high; F1: enlace BL616)
`endif
`else
    wire wifi_raw = 1'b0;                                 // BASE MINIMA: WiFi fuera
`endif

    wire disk_act, wifi_act, kbd_act;
    led_stretch #(.HOLD(1350000)) st_disk (.clk(clk_27m), .rst_n(bus_reset_n), .trig(sd_busy_w), .active(disk_act)); // ~50ms
    led_stretch #(.HOLD( 540000)) st_wifi (.clk(clk_27m), .rst_n(bus_reset_n), .trig(wifi_raw),  .active(wifi_act)); // ~20ms
    led_stretch #(.HOLD(1350000)) st_kbd  (.clk(clk_27m), .rst_n(bus_reset_n), .trig(kbd_raw),   .active(kbd_act));  // ~50ms

    // 8 colours in GRB (dim). LED0 = first in the chain (DIN side).
    wire [23:0] ws_c0 = 24'h180000;                          // 0 POWER  : solid green
    wire [23:0] ws_c1 = caps_on  ? 24'h180018 : 24'h000000;  // 1 CAPS   : cyan
    wire [23:0] ws_c2 = kana_on  ? 24'h002020 : 24'h000000;  // 2 KANA   : magenta
    wire [23:0] ws_c3 = disk_act ? 24'h102800 : 24'h000000;  // 3 DISK   : amber
    wire [23:0] ws_c4 = turbo    ? 24'h003000 : 24'h040000;  // 4 CPU    : turbo=red / normal=dim green
    wire [23:0] ws_c5 = wifi_act ? 24'h000030 : 24'h000000;  // 5 WiFi   : blue
    wire [23:0] ws_c6 = joy_on   ? 24'h202000 : 24'h000000;  // 6 JOY    : yellow
    wire [23:0] ws_c7 = kbd_act  ? 24'h181818 : 24'h000000;  // 7 KBD    : white flash

    ws2812 #(.NUM_LEDS(8), .CLK_FRE(27)) ws_strip (
        .clk   (clk_27m),
        .rst_n (bus_reset_n),
        .rgb   ({ws_c0, ws_c1, ws_c2, ws_c3, ws_c4, ws_c5, ws_c6, ws_c7}),
        .dout  (ws2812_led)
    );

    // ===== STANDALONE MERGE: USB host (BL616 FPGA Companion) — from MSXnano =====
    wire [127:0] keyboard;
`ifdef ENABLE_USB_KBD
    // F3 (_39): teclado por USB-A directo (usb_hid_host de nand2mario, la
    // version 2025 de snestang/tangcore con retry). Un host por puerto A;
    // el bitmap resultante se OR-ea con el del companion BL616 (que sigue
    // funcionando por su USB-C+hub): las dos fuentes conviven, como en
    // gbatang. Solo teclado en esta pieza; gamepads USB-A = pieza futura.
    wire        clk_usb12;
    wire        pll12_lock;
    // ---- ZYNQ PLLE2_E: 50 x 24 = VCO 1200 -> /100 = 12 (usb_hid_host) ----
    wire pE_fb, pE_fb_b, pE_12;
    PLLE2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKIN1_PERIOD(20.000), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT(24), .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE(100), .CLKOUT0_DUTY_CYCLE(0.5), .CLKOUT0_PHASE(0.0),
        .REF_JITTER1(0.010), .STARTUP_WAIT("FALSE")
    ) pll12_usb (
        .CLKIN1(ex_clk_27m), .CLKFBIN(pE_fb_b), .CLKFBOUT(pE_fb),
        .CLKOUT0(pE_12), .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(pll12_lock), .PWRDWN(1'b0), .RST(1'b0)
    );
    BUFG bE_fb (.I(pE_fb), .O(pE_fb_b));
    BUFG bE_12 (.I(pE_12), .O(clk_usb12));
    wire [1:0] usb1_typ, usb2_typ;
    wire       usb1_report, usb2_report;
    wire       usb1_conerr, usb2_conerr;
    // era V3: raton MSX sobre raton USB de PC (ver fpga/src/msx_mouse.v)
    wire [2:0] msx_mouse_phase;
    wire [7:0] usb1_mbtn, usb2_mbtn;
    wire signed [7:0] usb1_mdx, usb2_mdx, usb1_mdy, usb2_mdy;
    wire [7:0] usb1_mods, usb1_k1, usb1_k2, usb1_k3, usb1_k4;
    wire [7:0] usb2_mods, usb2_k1, usb2_k2, usb2_k3, usb2_k4;
    usb_hid_host usb_host1 (
        .usbclk (clk_usb12), .usbrst_n (pll12_lock),
        .usb_dm (usb1_dn), .usb_dp (usb1_dp),
        .typ (usb1_typ), .report (usb1_report), .conerr (usb1_conerr),
        .key_modifiers (usb1_mods),
        .key1 (usb1_k1), .key2 (usb1_k2), .key3 (usb1_k3), .key4 (usb1_k4),
        .mouse_btn (usb1_mbtn), .mouse_dx (usb1_mdx), .mouse_dy (usb1_mdy),
        .game_snes (), .game_l (), .game_r (), .game_u (), .game_d (),
        .game_a (), .game_b (), .game_x (), .game_y (), .game_sel (), .game_sta (),
        .game_lb (), .game_rb (),
        .dbg_hid_report ()
    );
    usb_hid_host usb_host2 (
        .usbclk (clk_usb12), .usbrst_n (pll12_lock),
        .usb_dm (usb2_dn), .usb_dp (usb2_dp),
        .typ (usb2_typ), .report (usb2_report), .conerr (usb2_conerr),
        .key_modifiers (usb2_mods),
        .key1 (usb2_k1), .key2 (usb2_k2), .key3 (usb2_k3), .key4 (usb2_k4),
        .mouse_btn (usb2_mbtn), .mouse_dx (usb2_mdx), .mouse_dy (usb2_mdy),
        .game_snes (), .game_l (), .game_r (), .game_u (), .game_d (),
        .game_a (), .game_b (), .game_x (), .game_y (), .game_sel (), .game_sta (),
        .game_lb (), .game_rb (),
        .dbg_hid_report ()
    );

    // =======================================================================
    //  RATON MSX sobre raton USB — cruce de dominios e instancia
    //
    //  usb_hid_host entrega mouse_dx/dy en el dominio de 12 MHz y los BORRA
    //  justo despues del pulso `report`, asi que no se pueden muestrear desde
    //  54 MHz: para cuando el pulso cruzase el sincronizador ya valdrian cero.
    //  Se capturan en su propio dominio a un registro cuasi-estatico (estable
    //  hasta el siguiente informe, milisegundos despues) y se avisa con un
    //  toggle, que es el patron que ya usa el resto del proyecto para esto.
    // =======================================================================
    wire usb1_mouse_rep = usb1_report && (usb1_typ == 2'd2);
    wire usb2_mouse_rep = usb2_report && (usb2_typ == 2'd2);

    reg signed [7:0] mo_dx_q = 8'sd0, mo_dy_q = 8'sd0;
    reg        [7:0] mo_btn_q = 8'd0;
    reg              mo_tog = 1'b0;
    reg              mo_seen = 1'b0;

    always @(posedge clk_usb12) begin
        if (!pll12_lock) begin
            mo_tog <= 1'b0;
            mo_seen <= 1'b0;
        end
        else if (usb1_mouse_rep || usb2_mouse_rep) begin
            mo_dx_q  <= usb1_mouse_rep ? usb1_mdx  : usb2_mdx;
            mo_dy_q  <= usb1_mouse_rep ? usb1_mdy  : usb2_mdy;
            mo_btn_q <= usb1_mouse_rep ? usb1_mbtn : usb2_mbtn;
            mo_tog   <= ~mo_tog;
            mo_seen  <= 1'b1;      // una vez visto, el puerto 2 es del raton
        end
    end

    // 2FF al dominio de 54 MHz + deteccion de cambio
    reg [2:0] mo_tog_s = 3'b000;
    reg       mo_seen_s0 = 1'b0, mo_seen_s1 = 1'b0;
    always @(posedge clk_54m) begin
        mo_tog_s   <= {mo_tog_s[1:0], mo_tog};
        mo_seen_s0 <= mo_seen;
        mo_seen_s1 <= mo_seen_s0;
    end
    wire mo_rep_54 = mo_tog_s[2] ^ mo_tog_s[1];

    // ZYNQ: raton del companion (buzon). Mismo dominio (clk_54m) que msx_mouse.
    reg       mb_mouse_seen = 1'b0;
    reg [7:0] mb_rep_cnt = 8'd0;                      // telemetria: informes recibidos del buzon
    reg [1:0] mb_btn_q = 2'b00;                       // botones: NIVEL (msx_mouse los saca por combinacional)
    always @(posedge clk_54m) if (mb_mouse_rep) begin
        mb_mouse_seen <= 1'b1; mb_rep_cnt <= mb_rep_cnt + 8'd1; mb_btn_q <= mb_mouse_btn[1:0];
    end
    wire [11:0] mm_cur_x;                             // telemetria: interior de msx_mouse
    wire [7:0]  mm_rel_x;
    reg  [3:0]  mm_strobe_cnt = 4'd0;                 // flancos del strobe (pin 8 del puerto 2) vistos a clk_54m
    reg         mm_strobe_d = 1'b1;
    always @(posedge clk_54m) begin
        mm_strobe_d <= psgPB[5];
        if (psgPB[5] != mm_strobe_d) mm_strobe_cnt <= mm_strobe_cnt + 4'd1;
    end
    // telemetria: ultimos 3 valores escritos en el registro 15 del PSG + cuenta (quien toca el strobe)
    wire        r15_wr = (bus_addr[7:0] == 8'hA1 && bus_iorq_n == 1'b0 && bus_wr_n == 1'b0 && bus_m1_n == 1'b1
                          && psg_addr_latch == 4'd15);
    reg         r15_wr_d = 1'b0;
    reg  [7:0]  r15_cnt = 8'd0;
    always @(posedge clk_54m) begin
        r15_wr_d <= r15_wr;
        if (r15_wr && !r15_wr_d) r15_cnt <= r15_cnt + 8'd1;
    end
    assign msx_mouse_present = mo_seen_s1 | mb_mouse_seen;

    // Sensibilidad: el delta se divide por 2^MOUSE_SENS. Un raton USB moderno
    // tiene MUCHO mas DPI que uno de MSX, asi que sin dividir el puntero se va
    // volando. 2 (=/4) es el punto de partida; el resto de la division NO se
    // pierde (se guarda en el acumulador), asi que los movimientos lentos
    // siguen moviendo el puntero. ⚠️ Es el numero que habra que ajustar en
    // placa a ojo.
    localparam [2:0] MOUSE_SENS = 3'd2;

`ifdef ENABLE_V9990
    // gestor de ventanas del V9991 (v9991_compose / v9991_wm): los informes tal cual, sin la division de sensibilidad
    // (el puntero va en pixeles de 720p), y el boton izquierdo
    assign wm_m_rep = mo_rep_54 | mb_mouse_rep;
    assign wm_m_dx  = mb_mouse_rep ? mb_mouse_dx : mo_dx_q;
    assign wm_m_dy  = mb_mouse_rep ? mb_mouse_dy : mo_dy_q;
    assign wm_m_btn = mo_btn_q[0] | mb_btn_q[0];
`endif
    msx_mouse u_msx_mouse (
        .clk       (clk_54m),
        .rst_n     (bus_reset_n),
        .rep_pulse (mo_rep_54 | mb_mouse_rep),                              // ZYNQ: + raton del companion
        .dx        (mb_mouse_rep ? mb_mouse_dx : mo_dx_q),
        .dy        (mb_mouse_rep ? mb_mouse_dy : mo_dy_q),
        .btn       ({mo_btn_q[1] | mb_btn_q[1], mo_btn_q[0] | mb_btn_q[0]}),   // {derecho, izquierdo}: nivel, OR de los dos ratones
        .dbg_cur_x (mm_cur_x),
        .dbg_rel_x (mm_rel_x),
        .sens      (MOUSE_SENS),
        .strobe    (psgPB[5]),                     // pin 8 del PUERTO 2
        .data      (msx_mouse_data),
        .dbg_phase (msx_mouse_phase)
    );

    // Cuenta de informes del raton USB, para saber si el USB va o no va.
    reg [7:0] mo_rep_cnt = 8'd0;
    always @(posedge clk_54m) if (mo_rep_54) mo_rep_cnt <= mo_rep_cnt + 8'd1;

    // Y una cuenta de informes de CUALQUIER tipo (sin filtrar por typ): separa
    // "el USB no habla" de "el USB habla pero lo hemos clasificado mal".
    reg       any_tog = 1'b0;
    always @(posedge clk_usb12)
        if (usb1_report || usb2_report) any_tog <= ~any_tog;
    reg [2:0] any_tog_s = 3'b000;
    always @(posedge clk_54m) any_tog_s <= {any_tog_s[1:0], any_tog};
    reg [7:0] any_rep_cnt = 8'd0;
    always @(posedge clk_54m)
        if (any_tog_s[2] ^ any_tog_s[1]) any_rep_cnt <= any_rep_cnt + 8'd1;

    wire [127:0] kbd_usb1, kbd_usb2;
    usb_kbd_decode dec_usb1 (
        .clk12 (clk_usb12), .rst_n (pll12_lock),
        .typ (usb1_typ), .report (usb1_report), .mods (usb1_mods),
        .k1 (usb1_k1), .k2 (usb1_k2), .k3 (usb1_k3), .k4 (usb1_k4),
        .bitmap (kbd_usb1)
    );
    usb_kbd_decode dec_usb2 (
        .clk12 (clk_usb12), .rst_n (pll12_lock),
        .typ (usb2_typ), .report (usb2_report), .mods (usb2_mods),
        .k1 (usb2_k1), .k2 (usb2_k2), .k3 (usb2_k3), .k4 (usb2_k4),
        .bitmap (kbd_usb2)
    );
    // cruce 12M -> 27M: bits cuasi-estaticos (pulsaciones de ms), 2FF por bit
    reg [127:0] kbd_usb_s1 = 128'd0, kbd_usb_s2 = 128'd0;
    always @(posedge clk_27m) begin
        kbd_usb_s1 <= kbd_usb1 | kbd_usb2;
        kbd_usb_s2 <= kbd_usb_s1;
    end
    // ZYNQ: + teclado inyectado desde xsdb (zynq/dbg_mailbox_axi.v, tools/key.tcl)
    reg [127:0] kbd_mbox_s1 = 128'd0, kbd_mbox_s2 = 128'd0;
    always @(posedge clk_27m) begin
        kbd_mbox_s1 <= kbd_mbox;
        kbd_mbox_s2 <= kbd_mbox_s1;
    end
    assign keyboard = kbd_usb_s2 | kbd_mbox_s2;
`else
    // Sin el companion no queda otra fuente: el teclado del MSX se apaga.
    assign keyboard = 128'd0;
`endif
    // F1 (_73): el pad U15 (spi_irqn) se entrega a la UART del BL616 cuando el
    // WiFi onboard esta activo; el companion (ya sin SPI: jtagseln=0) pierde su
    // IRQ — teclado por soft-host USB-A, joysticks USB del companion inertes.
`ifdef ENABLE_WIFI
    assign spi_irqn = bl616_uart_tx_w;
`else
    assign spi_irqn = 1'b1;          // sin companion: en reposo (activo bajo)
`endif
    // _153: el TX del wifi_lite tambien sale por el PMOD0 hacia el ESP32-C6.
    // Se emite SIEMPRE (broadcast inofensivo); sin ENABLE_WIFI queda en idle.
`ifdef ENABLE_WIFI
    assign esp_tx_o = zq_s3ps_s[1] ? uart1_tx_w : bl616_uart_tx_w;   // 02/10: con s3_ps la S3 recibe los comandos del ARM, no los del MSX
`else
    assign esp_tx_o = 1'b1;               // idle UART
`endif
    // _156: estado de turbo hacia el C6 (turbo_eff = el que consume el FSM de
    // waits; cuasi-estatico, sin CDC que valga la pena)
`ifdef ENABLE_TURBO
    assign esp_turbo_o = turbo_eff;
`else
    assign esp_turbo_o = 1'b0;
`endif
    // ---- alias para el lanzador -----------------------------------------
    // El bus del VDP, el lector de SD y el teclado USB viven cada uno bajo su
    // `ifdef; el companion NO. Sin estos alias, apagar cualquiera de los tres
    // dejaria puertos colgando (que en Verilog es una x silenciosa, no un
    // error de compilacion).
    // ========================================================================
    // fpga_companion RETIRADO (25/08)
    // ------------------------------------------------------------------------
    // Aqui vivia el companion SPI del ESP32-S3: mcu_spi + hid + sysctrl +
    // launcher_svc + sdc_bridge. 3.325 LUT y 4.749 registros, de los cuales
    // 4.255 eran el buffer de sector del sdc_bridge -- 512 bytes que la
    // sintesis puso en BIESTABLES en vez de en BSRAM.
    //
    // Lo sustituye el iosys_bl616 de TangCore por UART (413 LUT, 191 registros
    // y 1 BSRAM), que ya pinta el menu del MCU en la tele y detecta el core.
    //
    // El TECLADO no se pierde: los USB-A van directos al fabric
    // (ENABLE_USB_KBD / usb_hid_host) y `keyboard` pasa a ser solo kbd_usb_s2.
    // Los JOYSTICKS si colgaban del `hid`, y por eso se reenganchan abajo a
    // hid1/hid2 del iosys: ahora los gamepads USB los lee el BL616.
    // ========================================================================

    // ========================================================================
    // ESTADO DEL CORE HACIA EL OSD (comando 14) + CONGELACION DEL MSX
    // ------------------------------------------------------------------------
    // POR QUE EXISTE: el MCU ESCRIBE core_config pero hasta ahora no podia LEER
    // nada del core. Sin camino de vuelta el OSD tendria que SUPONER el estado, y
    // en cuanto algo cambiase por otro sitio -- F11, el puerto $41 del MSX, la
    // pantalla de Ajustes de la BIOS -- la pantalla estaria mintiendo.
    //
    //   byte 0  {3'b0, kana, caps, ventilador, hay_SD, turbo}
    //   byte 1  {2'b0, tipo_SD[1:0], estado_SD[3:0]}
    //   byte 2-3  termometro: fan_dbg_cnt[19:4] (oscilador de anillo del u_fanctrl)
    //   byte 4-5  wifi_ovf_cnt  (bytes TIRADOS: falta control de flujo)
    //   byte 6-7  wifi_unr_cnt  (lecturas en vacio: el ESP no entrega)
    // ========================================================================
    wire sd_hay = (sd_card_stat_w != 4'd0);
    assign iosys_status = {
        {3'b000, kana_on, caps_on, fan_en_ctrl, sd_hay, turbo_eff},
        {2'b00, sd_card_type_w, sd_card_stat_w},
        // Termometro: se MANDA pero el OSD no lo pinta -- es el contador de un
        // oscilador de anillo, sube cuando el chip se enfria y no esta calibrado.
        // Se deja en el paquete por si algun dia se calibra.
        fan_dbg_cnt[19:4],
        wifi_ovf_cnt,
        wifi_unr_cnt
    };

    // El MCU enciende y apaga el overlay con el comando 8 (F12 desde el teclado),
    // asi que la congelacion se cuelga del MISMO hilo: no hace falta protocolo
    // nuevo. Sincronizado porque `overlay` nace en clk_27m y cpu_run se consume
    // en otro dominio; un glitch aqui partiria un ciclo del Z80 por la mitad.
    //
    // PARAR cpu_run (no resetear) es lo que hacia el lanzador viejo, y ESA parte
    // si quedo validada en placa: la maquina se paraba y volvia. El refresco de
    // la SDRAM no sufre -- es autonomo justo cuando el Z80 no emite RFSH.
    reg iosys_frz_0 = 1'b0;
    always @(posedge clk_54m) begin
        iosys_frz_0 <= iosys_ovl_on;
        iosys_frz   <= iosys_frz_0;
    end

`ifdef ENABLE_S1990_TIMER
    // ---- S1990: el temporizador (y, con ENABLE_TURBOR_ID, la firma de turboR) --
    // Solo los registros y el temporizador; no hay R800. El bit de modo de CPU
    // va atado al turbo en los dos sentidos (ver la cabecera del modulo).
    reg turbo_eff_27 = 1'b0, turbo_eff_27a = 1'b0;
    always @(posedge clk_27m) begin
        turbo_eff_27a <= turbo_eff;      // cuasi-estatico: 2FF basta
        turbo_eff_27  <= turbo_eff_27a;
    end

    msx_s1990 #(.CLK_HZ(27_000_000),
`ifdef ENABLE_TR
                .ID(2)                   // TR (fase 2): S1990 completo (R#6 = CPU y modo DRAM, F4h, A7h) con el R800 de tr_cpu
`elsif ENABLE_TURBOR_ID
                .ID(1)
`else
                .ID(0)
`endif
    ) u_s1990 (
        .clk(clk_27m), .reset_n(bus_reset_n),
        .iorq_n(bus_iorq_n), .rd_n(bus_rd_n), .wr_n(bus_wr_n), .m1_n(bus_m1_n),
        .addr(bus_addr[7:0]), .din(cpu_dout),
        .dout(s1990_dout), .req(s1990_req),
        .pause_sw(1'b0),                 // la Console no tiene boton PAUSE
`ifdef ENABLE_TR
        .rom_mode(s1990_rom_mode),
        .turbo_on(turbo_eff_27),
        .turbo_set(s1990_turbo_set), .turbo_val(s1990_turbo_val),
        .cpu_r800(s1990_cpu_r800), .cpu_is_r800(tr_cur_s[1])
`else
        .rom_mode(),
        .turbo_on(turbo_eff_27),
        .turbo_set(s1990_turbo_set), .turbo_val(s1990_turbo_val),
        .cpu_r800(), .cpu_is_r800(1'b0)
`endif
    );
`else
    assign s1990_dout = 8'hFF;
    assign s1990_req  = 1'b0;
    assign s1990_turbo_set = 1'b0;
    assign s1990_turbo_val = 1'b0;
`endif

    usb_keyboard_msx usb_keyboard_msx
    (
        .CLK (clk_27m),
        .RESET (~bus_reset_n),

`ifdef ENABLE_DUAL
        .keyboard (kbd_a),                  // Dual: con el foco en B, A no ve el teclado (F11, F12 y Pausa los lee el top directo)
`else
        .keyboard (keyboard),
`endif
        .A (keyboard_addr),
        .DO (keyboard_data),
        .FN (function_keys)
    );


    // ================================================================
    //  ZYNQ: buzon de depuracion en la DDR (HP2 @ clk_54m). Desde xsdb:
    //  teclado (bitmap HID en MBOX+0) y telemetria (MBOX+0x40..0x5F).
    //  tools/key.tcl pulsa teclas; tools/tel.tcl lee la telemetria.
    // ================================================================
    // Trazador de I/O del V9968 (zynq/vdp_trace.v): 1024 eventos del puerto de control
    // (escrituras, lecturas con el dato devuelto, INT, VS) con linea y posicion H. Se
    // arma desde xsdb (bit 1 de MBOX+0x1C) y el buzon lo vuelca en MBOX+0x1000.
`ifndef ENABLE_TR
    wire        vtr_arm;
`endif
    wire        vtr_full;
    wire        vtr_auxonly;          // +0x1C bit 2: trazador solo UART (17/09)
`ifndef ENABLE_TR
    wire [9:0]  vtr_rd_addr;
`endif
    wire [31:0] vtr_rd_data;
    wire [9:0]  vtr_wp;
`ifdef ENABLE_TR
 `ifndef TR_DEBUG
  `define VTR_NINGUNO
 `endif
`endif
`ifdef VTR_NINGUNO
    // TR de produccion: sin trazador del VDP (TR_DEBUG=1 lo recupera con los disparos R2TRIG y R2LATE)
    assign vtr_full = 1'b0;  assign vtr_rd_data = 32'd0;  assign vtr_wp = 10'd0;
`else
`ifdef ENABLE_TR
    vdp_trace #(.TRACE_VRAM(1), .CIRC(1), .R2TRIG(1), .R2LATE(1)) u_vtrace (     // TR (depuracion): tambien las escrituras al 98h (MBOX+0x2C bit 5 las quita); R2LATE: R#2 fuera de ventana
`else
    vdp_trace u_vtrace (
`endif
        .clk(clk_86), .rst_n(rst86_n),
        .bus_address(v68_addr_mx), .bus_write(v68_write_mx), .bus_valid(v68_valid_mx), .bus_ready(v68_ready),
        .bus_wdata(v68_wdata_mx), .bus_rdata(v68_rdata), .bus_rdata_en(v68_rdata_en),
        .int_n(vdp_int), .hs(v68_hs), .vs(v68_vs),
        .aux_tgl(zq_uart_tgl), .aux_data(zq_uart_byte),   // 17/09: bytes que el Z80 lee del UART del ESP (puerto 06h)
        .aux_only(vtr_auxonly), .no_vram(mb_vid_ctl[5]), .frz_in(mb_vid_ctl[3]), .wp_o(vtr_wp),
        .rd_clk(clk_54m), .arm(vtr_arm), .full(vtr_full), .rd_addr(vtr_rd_addr), .rd_data(vtr_rd_data)
    );
`endif
    dbg_mailbox_axi #(.MBOX(32'h1FF0_0000), .PERIOD(54000)) u_mbox (
        .clk(clk_54m), .aresetn(rst54_n),
        .kbd_mbox(kbd_mbox),
        .joy1(joy1_mbox), .joy2(joy2_mbox),
        .mouse_btn(mb_mouse_btn), .mouse_dx(mb_mouse_dx), .mouse_dy(mb_mouse_dy), .mouse_rep(mb_mouse_rep),
        .msx_run(mb_msx_run),
`ifdef PERFIL_TR
        .tr_bios(mb_tr_bios),               // +0x1C bit 6 (perfil TR, fase 2): la BIOS del turbo R esta en la DDR -> mapa de slots FS-A1ST
`endif
        .net_ps(mb_net_ps),                 // +0x1C bit 3: UART del ESP -> UART1 del PS (25/09, Ethernet P1)
        .s3_ps(mb_s3_ps),                   // +0x1C bit 4: la S3 del CAM1 <-> UART1 del PS (02/10, actualizacion por WiFi)
        .cfg_in(mb_cfg),                    // +0x1C[28:8]: bloque de config guardado (companion) -> siembra
        .tel_cfg(zq_cfg_tel),               // +0x70: bloque vigente + toggle al pulsar "guardar"
        .mix_in(mb_mix),                    // +0x24: niveles del mezclador guardados (V3.7) -> siembra
        .vid_ctl(mb_vid_ctl),               // +0x2C: fuente HDMI pedida por el ARM {seq[15:8], 6'b0, auto_off[1], sel[0]} (V9990)
        .tel_mix(zq_mix_tel),               // +0xC0: niveles vigentes + toggle al pulsar "guardar"
        .v9_en(v9a_en), .v9_ent(v9a_ent), .v9_ent_v(v9a_ent_v), .v9_pop(v9a_pop),   // V9990 por el ARM (V9_BASE 0x1FFB0000); telemetria en +0xC4
        .v9_own(v9a_own), .v9_busy(v9a_busy), .v9_tmo(v9a_tmo),
`ifdef ENABLE_DUAL
        .b_ctl(b_ctl_raw),                  // V9_BASE+4: control de la maquina B (perfil Dual)
        .b_ctl2(b_ctl2_raw),                // V9_BASE+8: posicion fina de B y peticion de foco (Dual)
        .tel_wm(wm_tel_q),                  // +0xD0: puntero, ventana de A y foco (Dual)
`endif
        .tel_wifi({wifi_unr_cnt, wifi_ovf_cnt}), // +0x74: FIFO del UART del ESP (17/09: caza de los SSID corruptos)
`ifdef ENABLE_TR
        .z2a_ring(tr_tel_ring), .z2a_wi(8'd0),   // TR: +0x78..+0xB7 llevan el anillo de saltos de tr_cpu (depuracion); wi a 0: el companion no lo consume
`else
        .z2a_ring(zq_ring), .z2a_wi(zq_wi), // +0x78..+0xB8: anillo Z80 -> ARM (92h WaveGame, 93h menu)
`endif
        .wg_smp(wg_smp),                    // WaveGame: voz PCM servida del anillo de la DDR (MBOX+0x80000)
        .wg_smp_r(wg_smp_r),                // 23/09: canal derecho (estereo)
        .tape_in(tape_in), .tape_play(tape_play), .tape_mon(tape_mon), .tape_nonextor(tape_nonextor), .tape_motor(~ppi_port_c[4]),   // Z1.1 cinta virtual (anillo MBOX+0xA0000, ctl +0x28)
        `ifdef ENABLE_TR
        .trace_arm(vtr_arm), .trace_auxonly(vtr_auxonly), .trace_full(mb_vid_ctl[0] ? vtr_full : tr_trc_full), .trace_rd_addr(vtr_rd_addr), .trace_rd_data(mb_vid_ctl[0] ? vtr_rd_data : tr_trc_data),   // MBOX+0x2C bit 0 = 1: el volcado es el del trazador del VDP (vdp_trace)
          // TR: el anillo es el trazador de bus de tr_cpu
`else
        .trace_arm(vtr_arm), .trace_auxonly(vtr_auxonly), .trace_full(vtr_full), .trace_rd_addr(vtr_rd_addr), .trace_rd_data(vtr_rd_data),
`endif
        .tel_hits(mem_dbg_hits), .tel_miss(mem_dbg_miss), .tel_lat(mem_lat_tel), .lat_clr(mem_lat_clr),
        .tel_status({vddr_ops[15:0], sd_mode, sd_irq, sd_busy_w, sd_blk_rdy_w, ff_sd_rstart, ff_sd_wstart,
                     clock_locked, vddr_ready, iosys_frz, cpu_run_r, sd_card_type_w, sd_card_stat_w}),
        .tel_dbg(mem_dbg_state),
        .tel_dbg2({sd_ram_blocks, sdio_count, sd_timeout_error_w, sd_crc_error_w, sd_rcrc_error_w, ff_sd_init, sd_card_stat_w}),
`ifdef ENABLE_TR
        .tel_dbg3(tr_tel_b),                                                     // +0x64 (TR): {direccion de la ultima E/S, direccion viva del bus}
        .tel_dbg4(tr_tel_a),                                                     // +0x60 (TR): {PC de la ultima M1 del R800, PC de la ultima M1 del Z80}
`elsif ENABLE_DUAL
        .tel_dbg3(b_tel_a),                                                      // +0x64 (Dual): {PC de la ultima M1 de B[31:16], escrituras de B al VDP[15:0]}
        .tel_dbg4(b_tel_b),                                                      // +0x60 (Dual): {fotogramas del V9968 de B[31:16], A8h de B[15:8], fallos de cache de B[7:0]}
`elsif ENABLE_V9990
        .tel_dbg3(v99_dbg_rd),                                                   // +0x64 (V9990): DIAGNOSTICO 29/10 B5: estado del lector del FB (antes: ciclos de stall de la VRAM, v99_dbg_stall)
        .tel_dbg4({vdp_sel_active, v99_ln_last, v99_yank_drop, v68_win_underrun, v68_win_valid, vdp_compuesto, v99_px_last[9:0]}),   // +0x60 (V9990): {HDMI muestra el V9990[31], lineas/frame[30:22], underrun del FB del V9990[21:17], underrun del FB del V9968[16:12], frame del V9968 publicado[11], V9968 compuesto (modos 2 y 3)[10], pixeles/frame mod 1024[9:0]}
`else
        // +0x64: raton y mandos (buzon HID): {present, port2, strobe, phase[2:0], turbo_eff, 0}, dx, dy, informes
        .tel_dbg3({msx_mouse_present, psg_reg15_port2, psgPB[5], msx_mouse_phase, turbo_eff, 1'b0, mb_mouse_dx, mb_mouse_dy, mb_rep_cnt}),
        .tel_dbg4({wave_tel, r15_cnt}),     // +0x60: {lat_max AR->R (ciclos 37,5 MHz), lecturas, escrituras} de wave_axi + cuenta r15
`endif
`ifdef ENABLE_TR
        // 12/11/2026: +0x68 bit 15 = la CPU que manda es el R800 y bit 14 = modo DRAM de la S1990 (los dos de clk_54m, casi estaticos): el panel F12
        // dice "R800 ROM", "R800 DRAM" o "Z80" (osd_info.c). Antes esos bits eran 0 y la CPU solo se veia con la telemetria de TR_DEBUG.
        .tel_vmiss(tr_tel_d), .tel_vdrops({tr_tel_c[31:16], tr_r800_cur, dram_mode_w, 4'd0, vtr_wp}),   // +0x6C / +0x68 (TR): ver tr_cpu.v
`else
        .tel_vmiss(v68dbg_miss), .tel_vdrops(v68dbg_drops),   // +0x68: fallos y drops del shim de VRAM (artefactos de 8 px)
`endif   // +0x68: fallos y drops del shim de VRAM (artefactos de 8 px)
        .M_AWID(hp2_awid), .M_AWADDR(hp2_awaddr), .M_AWLEN(hp2_awlen), .M_AWSIZE(hp2_awsize),
        .M_AWBURST(hp2_awburst), .M_AWLOCK(hp2_awlock), .M_AWCACHE(hp2_awcache), .M_AWPROT(hp2_awprot),
        .M_AWQOS(hp2_awqos), .M_AWVALID(hp2_awvalid), .M_AWREADY(hp2_awready),
        .M_WID(hp2_wid), .M_WDATA(hp2_wdata), .M_WSTRB(hp2_wstrb), .M_WLAST(hp2_wlast),
        .M_WVALID(hp2_wvalid), .M_WREADY(hp2_wready),
        .M_BID(hp2_bid), .M_BRESP(hp2_bresp), .M_BVALID(hp2_bvalid), .M_BREADY(hp2_bready),
        .M_ARID(hp2_arid), .M_ARADDR(hp2_araddr), .M_ARLEN(hp2_arlen), .M_ARSIZE(hp2_arsize),
        .M_ARBURST(hp2_arburst), .M_ARLOCK(hp2_arlock), .M_ARCACHE(hp2_arcache), .M_ARPROT(hp2_arprot),
        .M_ARQOS(hp2_arqos), .M_ARVALID(hp2_arvalid), .M_ARREADY(hp2_arready),
        .M_RID(hp2_rid), .M_RDATA(hp2_rdata), .M_RRESP(hp2_rresp), .M_RLAST(hp2_rlast),
        .M_RVALID(hp2_rvalid), .M_RREADY(hp2_rready)
    );

    // ================================================================
    //  ZYNQ: PS7 (DDR3 + MIO + FCLK0 + HP0..HP3 + GP0). Block design: zynq/bd_ps7.tcl
    //  HP0 = VRAM (v9968_axi_backend) a FCLK0 = 150 MHz
    //  HP1 = RAM del Z80 (memory_axi) a clk_54m
    //  HP2 = buzon xsdb (dbg_mailbox_axi) a clk_54m
    //  HP3 = proxy de sectores "SD" (sd_axi_proxy) a clk_27m; su req_irq -> IRQ_F2P[0]
    //  GP0 = memoria de ondas del OPL4 (wave_axi, 32 bits) a clk_wave375
    //  GP1 = puerto de depuracion 34-37h de esa memoria (2a wave_axi) a clk_54m
    //        o, con ENABLE_V9990, la VRAM del V9990 (v9990_vram_axi) a clk_86
    // ================================================================
`ifdef ENABLE_V9990
    wire gp1_aclk = clk_86;      // 🚨 el cliente de VRAM habla en el dominio del VDP: el puerto ha de ir a su reloj
`else
    wire gp1_aclk = clk_54m;
`endif
    ps7_bd_wrapper ps7 (
        .DDR_addr(DDR_addr), .DDR_ba(DDR_ba), .DDR_cas_n(DDR_cas_n), .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p), .DDR_cke(DDR_cke), .DDR_cs_n(DDR_cs_n), .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq), .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p), .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n), .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .FCLK_CLK0(fclk0), .FCLK_RESET0_N(frst0_n), .IRQ_F2P(sd_irq),
        .UART0_TX(bl616_jtagsel), .UART0_RX(iosys_uart_tx),     // el ARM habla con iosys_bl616 (OSD)
        .UART1_TX(uart1_tx_w), .UART1_RX(uart1_rx_w), .UART1_CTSN(uart1_ctsn_w), .UART1_RTSN(uart1_rtsn_w),   // 25/09: el ARM hace de "ESP32" contra wifi_lite
        .HP0_ACLK(fclk0), .HP1_ACLK(clk_54m), .HP2_ACLK(clk_54m), .HP3_ACLK(clk_27m),
`ifdef ENABLE_DUAL
        .GP0_ACLK(clk_86), .GP1_ACLK(gp1_aclk),     // Dual: el GP0 es de bwin_fb, a clk_86 como el frame buffer del V9990
`else
        .GP0_ACLK(clk_wave375), .GP1_ACLK(gp1_aclk),
`endif
`ifdef ENABLE_DUAL
        .S_AXI_HP0_awid(hs0_awid), .S_AXI_HP0_awaddr(hs0_awaddr), .S_AXI_HP0_awlen(hs0_awlen),
        .S_AXI_HP0_awsize(hs0_awsize), .S_AXI_HP0_awburst(hs0_awburst), .S_AXI_HP0_awlock(hs0_awlock),
        .S_AXI_HP0_awcache(hs0_awcache), .S_AXI_HP0_awprot(hs0_awprot), .S_AXI_HP0_awqos(hs0_awqos),
        .S_AXI_HP0_awvalid(hs0_awvalid), .S_AXI_HP0_awready(hs0_awready),
        .S_AXI_HP0_wid(hs0_wid), .S_AXI_HP0_wdata(hs0_wdata), .S_AXI_HP0_wstrb(hs0_wstrb),
        .S_AXI_HP0_wlast(hs0_wlast), .S_AXI_HP0_wvalid(hs0_wvalid), .S_AXI_HP0_wready(hs0_wready),
        .S_AXI_HP0_bid(hs0_bid), .S_AXI_HP0_bresp(hs0_bresp), .S_AXI_HP0_bvalid(hs0_bvalid), .S_AXI_HP0_bready(hs0_bready),
        .S_AXI_HP0_arid(hs0_arid), .S_AXI_HP0_araddr(hs0_araddr), .S_AXI_HP0_arlen(hs0_arlen),
        .S_AXI_HP0_arsize(hs0_arsize), .S_AXI_HP0_arburst(hs0_arburst), .S_AXI_HP0_arlock(hs0_arlock),
        .S_AXI_HP0_arcache(hs0_arcache), .S_AXI_HP0_arprot(hs0_arprot), .S_AXI_HP0_arqos(hs0_arqos),
        .S_AXI_HP0_arvalid(hs0_arvalid), .S_AXI_HP0_arready(hs0_arready),
        .S_AXI_HP0_rid(hs0_rid), .S_AXI_HP0_rdata(hs0_rdata), .S_AXI_HP0_rresp(hs0_rresp),
        .S_AXI_HP0_rlast(hs0_rlast), .S_AXI_HP0_rvalid(hs0_rvalid), .S_AXI_HP0_rready(hs0_rready),
`else
        .S_AXI_HP0_awid(hp0_awid), .S_AXI_HP0_awaddr(hp0_awaddr), .S_AXI_HP0_awlen(hp0_awlen),
        .S_AXI_HP0_awsize(hp0_awsize), .S_AXI_HP0_awburst(hp0_awburst), .S_AXI_HP0_awlock(hp0_awlock),
        .S_AXI_HP0_awcache(hp0_awcache), .S_AXI_HP0_awprot(hp0_awprot), .S_AXI_HP0_awqos(hp0_awqos),
        .S_AXI_HP0_awvalid(hp0_awvalid), .S_AXI_HP0_awready(hp0_awready),
        .S_AXI_HP0_wid(hp0_wid), .S_AXI_HP0_wdata(hp0_wdata), .S_AXI_HP0_wstrb(hp0_wstrb),
        .S_AXI_HP0_wlast(hp0_wlast), .S_AXI_HP0_wvalid(hp0_wvalid), .S_AXI_HP0_wready(hp0_wready),
        .S_AXI_HP0_bid(hp0_bid), .S_AXI_HP0_bresp(hp0_bresp), .S_AXI_HP0_bvalid(hp0_bvalid), .S_AXI_HP0_bready(hp0_bready),
        .S_AXI_HP0_arid(hp0_arid), .S_AXI_HP0_araddr(hp0_araddr), .S_AXI_HP0_arlen(hp0_arlen),
        .S_AXI_HP0_arsize(hp0_arsize), .S_AXI_HP0_arburst(hp0_arburst), .S_AXI_HP0_arlock(hp0_arlock),
        .S_AXI_HP0_arcache(hp0_arcache), .S_AXI_HP0_arprot(hp0_arprot), .S_AXI_HP0_arqos(hp0_arqos),
        .S_AXI_HP0_arvalid(hp0_arvalid), .S_AXI_HP0_arready(hp0_arready),
        .S_AXI_HP0_rid(hp0_rid), .S_AXI_HP0_rdata(hp0_rdata), .S_AXI_HP0_rresp(hp0_rresp),
        .S_AXI_HP0_rlast(hp0_rlast), .S_AXI_HP0_rvalid(hp0_rvalid), .S_AXI_HP0_rready(hp0_rready),
`endif
        .S_AXI_HP1_awid(hp1_awid), .S_AXI_HP1_awaddr(hp1_awaddr), .S_AXI_HP1_awlen(hp1_awlen),
        .S_AXI_HP1_awsize(hp1_awsize), .S_AXI_HP1_awburst(hp1_awburst), .S_AXI_HP1_awlock(hp1_awlock),
        .S_AXI_HP1_awcache(hp1_awcache), .S_AXI_HP1_awprot(hp1_awprot), .S_AXI_HP1_awqos(hp1_awqos),
        .S_AXI_HP1_awvalid(hp1_awvalid), .S_AXI_HP1_awready(hp1_awready),
        .S_AXI_HP1_wid(hp1_wid), .S_AXI_HP1_wdata(hp1_wdata), .S_AXI_HP1_wstrb(hp1_wstrb),
        .S_AXI_HP1_wlast(hp1_wlast), .S_AXI_HP1_wvalid(hp1_wvalid), .S_AXI_HP1_wready(hp1_wready),
        .S_AXI_HP1_bid(hp1_bid), .S_AXI_HP1_bresp(hp1_bresp), .S_AXI_HP1_bvalid(hp1_bvalid), .S_AXI_HP1_bready(hp1_bready),
        .S_AXI_HP1_arid(hp1_arid), .S_AXI_HP1_araddr(hp1_araddr), .S_AXI_HP1_arlen(hp1_arlen),
        .S_AXI_HP1_arsize(hp1_arsize), .S_AXI_HP1_arburst(hp1_arburst), .S_AXI_HP1_arlock(hp1_arlock),
        .S_AXI_HP1_arcache(hp1_arcache), .S_AXI_HP1_arprot(hp1_arprot), .S_AXI_HP1_arqos(hp1_arqos),
        .S_AXI_HP1_arvalid(hp1_arvalid), .S_AXI_HP1_arready(hp1_arready),
        .S_AXI_HP1_rid(hp1_rid), .S_AXI_HP1_rdata(hp1_rdata), .S_AXI_HP1_rresp(hp1_rresp),
        .S_AXI_HP1_rlast(hp1_rlast), .S_AXI_HP1_rvalid(hp1_rvalid), .S_AXI_HP1_rready(hp1_rready),
`ifdef ENABLE_DUAL
        .S_AXI_HP2_awid(hs2_awid), .S_AXI_HP2_awaddr(hs2_awaddr), .S_AXI_HP2_awlen(hs2_awlen),
        .S_AXI_HP2_awsize(hs2_awsize), .S_AXI_HP2_awburst(hs2_awburst), .S_AXI_HP2_awlock(hs2_awlock),
        .S_AXI_HP2_awcache(hs2_awcache), .S_AXI_HP2_awprot(hs2_awprot), .S_AXI_HP2_awqos(hs2_awqos),
        .S_AXI_HP2_awvalid(hs2_awvalid), .S_AXI_HP2_awready(hs2_awready),
        .S_AXI_HP2_wid(hs2_wid), .S_AXI_HP2_wdata(hs2_wdata), .S_AXI_HP2_wstrb(hs2_wstrb),
        .S_AXI_HP2_wlast(hs2_wlast), .S_AXI_HP2_wvalid(hs2_wvalid), .S_AXI_HP2_wready(hs2_wready),
        .S_AXI_HP2_bid(hs2_bid), .S_AXI_HP2_bresp(hs2_bresp), .S_AXI_HP2_bvalid(hs2_bvalid), .S_AXI_HP2_bready(hs2_bready),
        .S_AXI_HP2_arid(hs2_arid), .S_AXI_HP2_araddr(hs2_araddr), .S_AXI_HP2_arlen(hs2_arlen),
        .S_AXI_HP2_arsize(hs2_arsize), .S_AXI_HP2_arburst(hs2_arburst), .S_AXI_HP2_arlock(hs2_arlock),
        .S_AXI_HP2_arcache(hs2_arcache), .S_AXI_HP2_arprot(hs2_arprot), .S_AXI_HP2_arqos(hs2_arqos),
        .S_AXI_HP2_arvalid(hs2_arvalid), .S_AXI_HP2_arready(hs2_arready),
        .S_AXI_HP2_rid(hs2_rid), .S_AXI_HP2_rdata(hs2_rdata), .S_AXI_HP2_rresp(hs2_rresp),
        .S_AXI_HP2_rlast(hs2_rlast), .S_AXI_HP2_rvalid(hs2_rvalid), .S_AXI_HP2_rready(hs2_rready),
`else
        .S_AXI_HP2_awid(hp2_awid), .S_AXI_HP2_awaddr(hp2_awaddr), .S_AXI_HP2_awlen(hp2_awlen),
        .S_AXI_HP2_awsize(hp2_awsize), .S_AXI_HP2_awburst(hp2_awburst), .S_AXI_HP2_awlock(hp2_awlock),
        .S_AXI_HP2_awcache(hp2_awcache), .S_AXI_HP2_awprot(hp2_awprot), .S_AXI_HP2_awqos(hp2_awqos),
        .S_AXI_HP2_awvalid(hp2_awvalid), .S_AXI_HP2_awready(hp2_awready),
        .S_AXI_HP2_wid(hp2_wid), .S_AXI_HP2_wdata(hp2_wdata), .S_AXI_HP2_wstrb(hp2_wstrb),
        .S_AXI_HP2_wlast(hp2_wlast), .S_AXI_HP2_wvalid(hp2_wvalid), .S_AXI_HP2_wready(hp2_wready),
        .S_AXI_HP2_bid(hp2_bid), .S_AXI_HP2_bresp(hp2_bresp), .S_AXI_HP2_bvalid(hp2_bvalid), .S_AXI_HP2_bready(hp2_bready),
        .S_AXI_HP2_arid(hp2_arid), .S_AXI_HP2_araddr(hp2_araddr), .S_AXI_HP2_arlen(hp2_arlen),
        .S_AXI_HP2_arsize(hp2_arsize), .S_AXI_HP2_arburst(hp2_arburst), .S_AXI_HP2_arlock(hp2_arlock),
        .S_AXI_HP2_arcache(hp2_arcache), .S_AXI_HP2_arprot(hp2_arprot), .S_AXI_HP2_arqos(hp2_arqos),
        .S_AXI_HP2_arvalid(hp2_arvalid), .S_AXI_HP2_arready(hp2_arready),
        .S_AXI_HP2_rid(hp2_rid), .S_AXI_HP2_rdata(hp2_rdata), .S_AXI_HP2_rresp(hp2_rresp),
        .S_AXI_HP2_rlast(hp2_rlast), .S_AXI_HP2_rvalid(hp2_rvalid), .S_AXI_HP2_rready(hp2_rready),
`endif
        .S_AXI_HP3_awid(hp3_awid), .S_AXI_HP3_awaddr(hp3_awaddr), .S_AXI_HP3_awlen(hp3_awlen),
        .S_AXI_HP3_awsize(hp3_awsize), .S_AXI_HP3_awburst(hp3_awburst), .S_AXI_HP3_awlock(hp3_awlock),
        .S_AXI_HP3_awcache(hp3_awcache), .S_AXI_HP3_awprot(hp3_awprot), .S_AXI_HP3_awqos(hp3_awqos),
        .S_AXI_HP3_awvalid(hp3_awvalid), .S_AXI_HP3_awready(hp3_awready),
        .S_AXI_HP3_wid(hp3_wid), .S_AXI_HP3_wdata(hp3_wdata), .S_AXI_HP3_wstrb(hp3_wstrb),
        .S_AXI_HP3_wlast(hp3_wlast), .S_AXI_HP3_wvalid(hp3_wvalid), .S_AXI_HP3_wready(hp3_wready),
        .S_AXI_HP3_bid(hp3_bid), .S_AXI_HP3_bresp(hp3_bresp), .S_AXI_HP3_bvalid(hp3_bvalid), .S_AXI_HP3_bready(hp3_bready),
        .S_AXI_HP3_arid(hp3_arid), .S_AXI_HP3_araddr(hp3_araddr), .S_AXI_HP3_arlen(hp3_arlen),
        .S_AXI_HP3_arsize(hp3_arsize), .S_AXI_HP3_arburst(hp3_arburst), .S_AXI_HP3_arlock(hp3_arlock),
        .S_AXI_HP3_arcache(hp3_arcache), .S_AXI_HP3_arprot(hp3_arprot), .S_AXI_HP3_arqos(hp3_arqos),
        .S_AXI_HP3_arvalid(hp3_arvalid), .S_AXI_HP3_arready(hp3_arready),
        .S_AXI_HP3_rid(hp3_rid), .S_AXI_HP3_rdata(hp3_rdata), .S_AXI_HP3_rresp(hp3_rresp),
        .S_AXI_HP3_rlast(hp3_rlast), .S_AXI_HP3_rvalid(hp3_rvalid), .S_AXI_HP3_rready(hp3_rready),
        .S_AXI_GP0_awid(gp0_awid), .S_AXI_GP0_awaddr(gp0_awaddr), .S_AXI_GP0_awlen(gp0_awlen),
        .S_AXI_GP0_awsize(gp0_awsize), .S_AXI_GP0_awburst(gp0_awburst), .S_AXI_GP0_awlock(gp0_awlock),
        .S_AXI_GP0_awcache(gp0_awcache), .S_AXI_GP0_awprot(gp0_awprot), .S_AXI_GP0_awqos(gp0_awqos),
        .S_AXI_GP0_awvalid(gp0_awvalid), .S_AXI_GP0_awready(gp0_awready),
        .S_AXI_GP0_wid(gp0_wid), .S_AXI_GP0_wdata(gp0_wdata), .S_AXI_GP0_wstrb(gp0_wstrb),
        .S_AXI_GP0_wlast(gp0_wlast), .S_AXI_GP0_wvalid(gp0_wvalid), .S_AXI_GP0_wready(gp0_wready),
        .S_AXI_GP0_bid(gp0_bid), .S_AXI_GP0_bresp(gp0_bresp), .S_AXI_GP0_bvalid(gp0_bvalid), .S_AXI_GP0_bready(gp0_bready),
        .S_AXI_GP0_arid(gp0_arid), .S_AXI_GP0_araddr(gp0_araddr), .S_AXI_GP0_arlen(gp0_arlen),
        .S_AXI_GP0_arsize(gp0_arsize), .S_AXI_GP0_arburst(gp0_arburst), .S_AXI_GP0_arlock(gp0_arlock),
        .S_AXI_GP0_arcache(gp0_arcache), .S_AXI_GP0_arprot(gp0_arprot), .S_AXI_GP0_arqos(gp0_arqos),
        .S_AXI_GP0_arvalid(gp0_arvalid), .S_AXI_GP0_arready(gp0_arready),
        .S_AXI_GP0_rid(gp0_rid), .S_AXI_GP0_rdata(gp0_rdata), .S_AXI_GP0_rresp(gp0_rresp),
        .S_AXI_GP0_rlast(gp0_rlast), .S_AXI_GP0_rvalid(gp0_rvalid), .S_AXI_GP0_rready(gp0_rready),
        .S_AXI_GP1_awid(gp1_awid), .S_AXI_GP1_awaddr(gp1_awaddr), .S_AXI_GP1_awlen(gp1_awlen),
        .S_AXI_GP1_awsize(gp1_awsize), .S_AXI_GP1_awburst(gp1_awburst), .S_AXI_GP1_awlock(gp1_awlock),
        .S_AXI_GP1_awcache(gp1_awcache), .S_AXI_GP1_awprot(gp1_awprot), .S_AXI_GP1_awqos(gp1_awqos),
        .S_AXI_GP1_awvalid(gp1_awvalid), .S_AXI_GP1_awready(gp1_awready),
        .S_AXI_GP1_wid(gp1_wid), .S_AXI_GP1_wdata(gp1_wdata), .S_AXI_GP1_wstrb(gp1_wstrb),
        .S_AXI_GP1_wlast(gp1_wlast), .S_AXI_GP1_wvalid(gp1_wvalid), .S_AXI_GP1_wready(gp1_wready),
        .S_AXI_GP1_bid(gp1_bid), .S_AXI_GP1_bresp(gp1_bresp), .S_AXI_GP1_bvalid(gp1_bvalid), .S_AXI_GP1_bready(gp1_bready),
        .S_AXI_GP1_arid(gp1_arid), .S_AXI_GP1_araddr(gp1_araddr), .S_AXI_GP1_arlen(gp1_arlen),
        .S_AXI_GP1_arsize(gp1_arsize), .S_AXI_GP1_arburst(gp1_arburst), .S_AXI_GP1_arlock(gp1_arlock),
        .S_AXI_GP1_arcache(gp1_arcache), .S_AXI_GP1_arprot(gp1_arprot), .S_AXI_GP1_arqos(gp1_arqos),
        .S_AXI_GP1_arvalid(gp1_arvalid), .S_AXI_GP1_arready(gp1_arready),
        .S_AXI_GP1_rid(gp1_rid), .S_AXI_GP1_rdata(gp1_rdata), .S_AXI_GP1_rresp(gp1_rresp),
        .S_AXI_GP1_rlast(gp1_rlast), .S_AXI_GP1_rvalid(gp1_rvalid), .S_AXI_GP1_rready(gp1_rready),
        .OLED_GPIO_tri_io({oled_rst_n, oled_dc, oled_sdin, oled_sclk})   // EMIO 3..0 = RST, D/C, D1, D0
    );

endmodule
