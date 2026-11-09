// ============================================================================
// msx2hdmi.sv — Puente de vídeo VDP (27 MHz) → HDMI 720p (74.25 MHz)
//
// Arquitectura nand2mario (smstang/monitorcore): el HDMI corre en su propio
// dominio de reloj (74.25 / 371.25 MHz) y se alimenta desde el dominio del
// VDP (27 MHz) a través de un ring buffer BRAM dual-clock de 32 líneas
// nativas (720 px × 18 bits).
//
// CAPTURA AUTO-CRONOMETRADA (v2): en lugar de los contadores internos del VDP
// (vdp_cx/vdp_cy, cuya semántica real — H_CNT 0..1715, V_CNT en medias
// líneas — no coincidía con la asumida), la escritura se auto-alinea con las
// señales de vídeo reales del VDP: hs_n, vs_n y blank. Es inmune al offset
// horizontal/vertical del área activa.
//
// POLARIDADES (verificadas en el VHDL del core, fork tn_vdp_v3_v9958):
//  - hs_n = PVIDEOHS_N: ACTIVO BAJO. vdp_vga.vhd:229-241 (FF_HSYNC_N <= '0'
//    en HCOUNTERIN=0 y =858, <= '1' en 40/898; 2 pulsos por línea H_CNT de
//    1716 clocks = raster 31 kHz del doubler). vdp.vhd:1101 lo saca tal cual
//    con DISPMODEVGA=1 (v9958_top instancia el VDP con DISPRESO=1).
//  - vs_n = PVIDEOVS_N: ACTIVO BAJO. vdp_vga.vhd:243-281 (FF_VSYNC_N <= '0'
//    durante 3 líneas de salida, p.ej. V_CNT 18..24 NTSC no interlace).
//  - blank = BLANK_o: 1 = blanking. OJO (vdp_vga.vhd:318 + 298-312): en este
//    fork VIDEOOUTX está clavado a '1' (el gate horizontal está comentado),
//    así que BLANK_o == "VS activo" y NO delimita los 720 px. El diseño lo
//    tolera: sin blanking horizontal, x=0 queda ~1 clk tras el flanco de HS,
//    que con DISP_START_X=0 (vdp_vga.vhd:166) coincide con el píxel 0 real
//    (±2 px constantes). Con blanking de píxel real se auto-alinea exacto.
//  Los detectores son parametrizables (HS_ACTIVE_LOW/VS_ACTIVE_LOW) por si
//  en placa hubiera que invertir.
//
// Lado ESCRITURA (clk 27M):
//  - out_line: 0 en el flanco activo de VS, +1 en cada flanco activo de HS.
//  - x_cnt: 0 en el primer ciclo no-blank tras HS, +1 por ciclo no-blank.
//  - y0: primera out_line con píxeles no-blank tras VS (latch por frame).
//  - línea nativa n = (out_line - y0) >> 1; se captura SOLO la scanline PAR
//    del par line-doubled; clamp n < 288; slot del ring = n mod 32.
//  - frame_tgl (lock) se invierte al INICIO de out_line == y0 + LOCK_LINES.
//
// LOCK_LINES = 6, RELATIVO A y0 (¡no a VS!). Justificación:
//  * En el toggle hay exactamente 3 líneas nativas escritas (rel 0,2,4) sea
//    cual sea el offset vertical → misma geometría validada del diseño _36:
//    rampa de lag ≈ 13 + 0.049·yy (NTSC) / 15.5 + 0.042·yy (PAL); dentro de
//    [3,29] con margen ≥2 por ambos lados (valores medidos: ver TB).
//  * Un LOCK absoluto desde VS NO puede valer a la vez para el TB (activo en
//    línea 40/46) y para el HW real (activo en línea 3, porque el VS del core
//    dura 3 líneas y blank=VS): con lock=50 absoluto, en HW habría ~23
//    nativas escritas en el toggle → lag(yy=0) ≈ 34 > 32 → overrun del ring.
//    Relativo a y0, TB y HW quedan con geometría idéntica.
//
// Lado LECTURA (clk_pixel 74.25M) — sin cambios respecto a la versión
// validada en placa (señal 720p OK): ventana activa 960×720 centrada
// (X ∈ [160,1120)), escalado fraccional 720→960 (×4/3) y 240→720 (×3) /
// 288→720 (×2.5), dos hdmi (VIC 4 = 720p60, VIC 19 = 720p50) reseteados a
// (0,720) por el lock cruzado 2FF, mux de tmds_internal por pal_mode
// sincronizado, UN serializer externo (OSER10 RESET=0) y ELVDS_OBUF con
// clk_pixel crudo — patrón v9958_top.v.
//
// `define SIM_NO_HDMI sustituye hdmi/serializer/ELVDS por contadores cx/cy
// conductuales para simular SOLO la lógica del puente con Icarus.
// ============================================================================

// ============================================================================
// msx2hdmi_v9968.sv — variante para el V9968 (MSXimus 60K). Deltas respecto
// a msx2hdmi.sv (que queda INTACTO para los builds con el VDP clasico):
//   * write-side en clk_86 (85.909 MHz) con `ce` (2 ciclos/pixel del V9968);
//   * ring de 32 lineas x 800 px (el V9968 saca 800 activos: 256x3=768 de
//     contenido + bordes — el ring de 720 croparia 48 px de contenido);
//   * lectura: H 800->1200 (x1,5 EXACTO, _127C) 4:3, 800->1280 16:9;
//     V FIJO 240->720 x3 en AMBOS modos (el V9968 normaliza NTSC y PAL a
//     480 lineas dobladas = 240 nativas);
//   * scanlines: patron x3 (1 de cada 3) tambien en PAL;
//   * hs/vs ACTIVO ALTO (display_hs/vs del V9968), blank = ~display_en.
// Back-ends hdmi_ntsc/hdmi_pal, serializer, ELVDS y audio: SIN CAMBIOS.
// ============================================================================
module msx2hdmi_v9968 #(
    // ========================================================================
    // _168 ENABLE_PAL — 0 = solo back-end NTSC (720p60). Es lo que hay HOY.
    //
    // POR QUE ESTE PARAMETRO. El modulo instancia DOS codificadores HDMI
    // completos (hdmi_ntsc VIC 4 = 720p60 y hdmi_pal VIC 19 = 720p50) y
    // multiplexa sus salidas TMDS con pal_x. Pero pal_mode llega CABLEADO A
    // CERO desde el top (top.v:1969 `.pal_mode (1'b0)`, y el V9968 fuerza
    // ff_50hz_mode <= 1'b0 en vdp_cpu_interface.v:613 y :697): el back-end PAL
    // es LOGICA MUERTA — 606 FF y 835 de logica sintetizados para nada.
    //
    // El sintetizador NO lo podaba solo porque pal_mode cruza un sincronizador
    // de 2 registros (pal_sync, ~linea 341) y eso BLOQUEA la propagacion de
    // constantes. Con este parametro, pal_x pasa a ser una constante de
    // ELABORACION y la poda ocurre sola: se van hdmi_pal, su mux, cx_pal y
    // cy_pal, sin tocar ni una linea de la estructura.
    //
    // El camino PAL queda INTACTO en el fuente. Para recuperarlo: poner este
    // parametro a 1 y darle a .pal_mode una senal de verdad. Sigue pendiente
    // medir la geometria 50 Hz del V9968 (top.v:1746).
    // ========================================================================
    parameter ENABLE_PAL = 0,
    // V9990 (Zynq): 1 = SIN serializer/OBUFDS; los 30 bits TMDS codificados y el
    // vblank salen por tmds_out/vblank a un mux externo (lo fue hdmi_tmds_switch.sv
    // del 21/09 al 28/10/2026; desde el compositor V9991 ya no se usa: 0).
    parameter NO_SERIALIZER = 0,
    // V9991 (28/10/2026): 1 = el pixel que va al codificador entra por rgb_ext (el compositor de top,
    // v9991_compose, que mezcla rgb_pre = el pixel de este puente con el del V9990 por pixel); el raster
    // cx/cy de este hdmi sale por cx_out/cy_out para que el puente del V9990 lea con el. 0 = como siempre.
    parameter EXT_COMPOSE = 0,
    // V9991 (28/10/2026): 1 = la VENTANA: el V9968 tambien por un frame buffer en la DDR (3 slots de
    // 240 x 1280 B en FB_BASE, el mismo v9990_fb que el V9990) y, en el modo 2 del compositor (win_en),
    // el anillo lo llena ese lector y el lado 720p lo lee con origen y escala programables. Ver el bloque
    // g_win al final. 0 = nada de esto en el netlist (la linea Tang).
    parameter WINDOW = 0,
    parameter [31:0] FB_BASE = 32'h1060_0000
) (
    output wire [10:0] cx_out,       // V9991: raster del hdmi (frame 1650 x 750, NTSC)
    output wire [9:0]  cy_out,
    output wire [23:0] rgb_pre,      // V9991: el pixel de este puente en (cx,cy), con scanlines, antes del overlay
    input  wire [23:0] rgb_ext,      // V9991: el pixel compuesto (solo con EXT_COMPOSE = 1)
    // ---- V9991 ventana (WINDOW = 1) ----
    input  wire        aresetn,      // reset AXI (dominio clk)
    input  wire        win_en,       // clk_pixel: modo 2 activo (del compositor; cambia en el vblank)
    input  wire        free_run,     // clk_pixel (EXT_COMPOSE): el compositor muestra el V9990 a pantalla completa (modo 1): el hdmi corre
                                     // LIBRE a 60,000 Hz, sin re-anclarse al frame del V9968 (29/10/2026)
    input  wire signed [11:0] win_x0, // esquina de la ventana en pantalla (px 720p, con signo)
    input  wire signed [10:0] win_y0,
    input  wire [1:0]  win_scl,      // 00 = x1 (2 px por columna, 3 por linea), 10 = x2 (4 y 6), 01 = x0,5 (1 y 1,5; 29/10/2026),
                                    // 11 = x0,75 (1,5 px por columna: 2,1; 2,25 por linea: 3,2,2,2; 29/10/2026, la tecla V en B5)
    input  wire [9:0]  win_sx0,      // origen en el frame del V9968: columna del anillo (0..639)
    input  wire [7:0]  win_sy0,      // linea nativa (0..239)
    input  wire        fs43,         // rama beta (30/10/2026): 4:3 + Scale3x a pantalla completa (WINDOW = 1). Cuasi-estatico, de
                                     // cualquier dominio (se sincroniza aqui). Solo cuenta en la ventana de pantalla completa
                                     // (x0 = y0 = 0, x1, origen 0/0 = el modo 0 del compositor); en cualquier otra, nada cambia
    input  wire        hires512,     // el V9968 esta en un modo de 512 puntos (SCREEN6/7, texto de 80 col.; vdp.v), dominio clk
    output wire [4:0]  dbg_win_underrun, // clk: lineas que el mostrador alcanzo al lector en el ultimo frame
    output wire        dbg_win_valid,    // clk_pixel: hay un frame del V9968 publicado en la DDR
    // AXI3 master 32 bits del frame buffer del V9968 (WINDOW = 1; al arbitro del GP1, IDs 6/7)
    output wire [5:0]  M_AWID,
    output wire [31:0] M_AWADDR,
    output wire [3:0]  M_AWLEN,
    output wire [2:0]  M_AWSIZE,
    output wire [1:0]  M_AWBURST,
    output wire [1:0]  M_AWLOCK,
    output wire [3:0]  M_AWCACHE,
    output wire [2:0]  M_AWPROT,
    output wire [3:0]  M_AWQOS,
    output wire        M_AWVALID,
    input  wire        M_AWREADY,
    output wire [5:0]  M_WID,
    output wire [31:0] M_WDATA,
    output wire [3:0]  M_WSTRB,
    output wire        M_WLAST,
    output wire        M_WVALID,
    input  wire        M_WREADY,
    input  wire [5:0]  M_BID,
    input  wire [1:0]  M_BRESP,
    input  wire        M_BVALID,
    output wire        M_BREADY,
    output wire [5:0]  M_ARID,
    output wire [31:0] M_ARADDR,
    output wire [3:0]  M_ARLEN,
    output wire [2:0]  M_ARSIZE,
    output wire [1:0]  M_ARBURST,
    output wire [1:0]  M_ARLOCK,
    output wire [3:0]  M_ARCACHE,
    output wire [2:0]  M_ARPROT,
    output wire [3:0]  M_ARQOS,
    output wire        M_ARVALID,
    input  wire        M_ARREADY,
    input  wire [5:0]  M_RID,
    input  wire [31:0] M_RDATA,
    input  wire [1:0]  M_RRESP,
    input  wire        M_RLAST,
    input  wire        M_RVALID,
    output wire        M_RREADY,
    input  wire        clk,          // 85.909 MHz, dominio del V9968
    input  wire        resetn,       // reset del dominio VDP (activo bajo)
    input  wire        ce,           // pixel-enable (1 de cada 2 ciclos)
    input  wire [5:0]  r,            // color del VDP (truncado 8->6 fuera)
    input  wire [5:0]  g,
    input  wire [5:0]  b,
    input  wire        hs_n,         // display_hs del V9968 (ACTIVO ALTO)
    input  wire        vs_n,         // display_vs del V9968 (ACTIVO ALTO)
    input  wire        blank,        // ~display_en (1 = blanking)
    input  wire        pal_mode,     // cuasi-estático
    input  wire        aspect_wide,  // _56: 0 = 4:3 (960 centrado), 1 = 16:9
                                     // (720→1280 estirado). Cuasi-estático
                                     // desde la config del menú; el cambio en
                                     // caliente puede dar 1 frame feo.
    input  wire        scanlines,    // _58: 1 = atenuar al 50% la última
                                     // repetición de cada línea nativa
                                     // (1 de 3 NTSC ×3; patrón 3-2 PAL ×2.5).
                                     // Cuasi-estático desde la config del menú.
    input  wire [15:0] audio_l,      // muestras del core (cruce 2FF)
    input  wire [15:0] audio_r,
    output wire [15:0] dbg_amp,      // _133: pico |muestra| que consume el HDMI
    input  wire        clk_pixel,    // 74.25 MHz
    input  wire        clk_5x_pixel, // 371.25 MHz
    output wire        tmds_clk_n,
    output wire        tmds_clk_p,
    output wire [2:0]  tmds_d_n,
    output wire [2:0]  tmds_d_p,
    // ---- diagnóstico (polaridad: activo = 1; el top pone la del LED) ----
    output wire        dbg_vs_tick,  // clk: stretch ~39ms del flanco de VS
    output wire        dbg_wr_act,   // clk: stretch de mem_we (hay captura)
    output wire        dbg_nonblack, // clk: stretch de mem_we con dato != 0
    output wire        dbg_lock_tgl, // clk: frame_tgl tal cual (~30 Hz NTSC)
    output wire        dbg_hdmi_rst, // clk_pixel: stretch del pulso hdmi_rst
    output wire        dbg_rd_act,   // clk_pixel: nivel ventana activa lectura
    output wire [31:0] dbg_apkt,     // _127I: {ovr[7:0], 8'h00, paquetes_audio[15:0]}
    output wire [5:0]  dbg_defer,    // _134: yanks diferidos (esperado ~60/s)
    output wire [4:0]  dbg_tear,     // _134: resets en zona de peligro (esperado 0)
    // ---- V3.1 OVERLAY del iosys (TangCore) --------------------------------
    // El core exporta la posicion del pixel y recibe su color, igual que en
    // nestang_top.sv. Todo esto vive en clk_pixel = su `hclk`.
    output wire [7:0]  ovl_x,        // 0..255
    output wire [7:0]  ovl_y,        // 0..223
    input  wire [14:0] ovl_color,    // BGR5 que devuelve textdisp
    input  wire        ovl_on,       // 1 = tapar la imagen con el overlay
    output wire [29:0] tmds_out,     // NO_SERIALIZER: {ch2, ch1, ch0} codificados (clk_pixel)
    output wire        vblank        // NO_SERIALIZER: cy >= 720 (clk_pixel)
);

    localparam HS_ACTIVE_LOW   = 0;  // V9968: display_hs/vs activos ALTOS
    localparam VS_ACTIVE_LOW   = 0;
    // [v2.0.2 BORDES] 768 -> 640 columnas nativas: el V9968 saca ahora 640
    // columnas (256 px de contenido x2 + 32 puntos de borde por lado x2) y
    // 640 -> 1280 es un x2 EXACTO. Ahorra 4 BSRAM (24 -> 20 bloques).
    localparam RING_W          = 640; // px por linea del ring (V9968)
    localparam NATIVE_LINES    = 240; // lineas nativas (480 dobladas / 2)
    localparam LOCK_LINES      = 6;  // líneas de salida DESDE y0 (ver cabecera)
    localparam CLKFRQ          = 74250;   // kHz de clk_pixel
    localparam AUDIO_RATE      = 44100;
    localparam AUDIO_BIT_WIDTH = 16;
    localparam NUM_CHANNELS    = 3;
    // _127C (BUILD DE PRUEBA): el 4:3 clasico queda INTACTO (960, ventana
    // 4:3 exacta = proporcionado; el x1,2 fraccional es el precio: cada
    // pixel MSX — 3 columnas nativas del core, que ya escala 256->768 —
    // sale a 3 o 4 columnas alternas = palos desiguales en las fuentes).
    // La POSICION 16:9 del menu pasa a ser el modo PIXEL-PERFECTO para
    // comparar en caliente: 800->1066 (x4/3, acumulador +600 umbral 800,
    // patron 2,1,1 por nativa -> CUALQUIER triplete suma 4): pixel MSX =
    // 4 columnas EXACTAS, inmune a la fase de los bordes. Ventana 1066
    // centrada (~11% mas ancha que el 4:3 puro). En la _128 se decide:
    // tercera opcion de menu o sustitucion.
    // _141 4:3 PIXEL-PERFECT x3: ventana 800 (no 960) -> el nativo del V9968
    // (800 = 256*3 contenido + borde) se pasa 1:1 => cada pixel MSX = 3
    // columnas EXACTAS (uniforme, la "H" con los dos palos iguales) y el
    // contenido 768x576 = 4:3 REAL. Antes 960 daba x1.2 (columnas 4,4,4,3
    // por celda = caracteres descuadrados). El 16:9 sigue siendo pixel-perfect
    // x4 (1066). OJO: los modos de TEXTO de 40/80 col (240/480px de contenido)
    // los escala el propio V9968 a 768 con factor no-entero -> ahi la
    // uniformidad la limita el core, no este escalador (SCREEN1 256px = limpio).
    localparam XSTART          = (1280-800)/2;   // 240   (4:3 pixel-perfect x3)
    localparam XSTOP           = (1280+800)/2;   // 1040  (4:3 pixel-perfect x3)
    localparam XSTART_P        = (1280-1066)/2;  // 107   (pixel-perfecto)
    localparam XSTOP_P         = (1280+1066)/2;  // 1173  (pixel-perfecto)
    // _56 (16:9 estirado): ventana a pantalla completa, 720→1280
    localparam XSTART_W        = 0;
    localparam XSTOP_W         = 1280;

    // ========================================================================
    // Dominio clk (27 MHz): captura auto-cronometrada al ring buffer
    // ========================================================================

    // Ring buffer BRAM dual-clock inferida (mismo patrón que sms2hdmi):
    // escritura en always @(posedge clk), lectura registrada en clk_pixel.
    logic [17:0] mem [0:32*RING_W-1];

    wire hs_act = HS_ACTIVE_LOW ? ~hs_n : hs_n;
    wire vs_act = VS_ACTIVE_LOW ? ~vs_n : vs_n;

    // Registro de entradas (una etapa uniforme: syncs, blank y color alineados)
    reg        hs_q, hs_qq, vs_q, vs_qq, blank_q;
    reg [5:0]  r_q, g_q, b_q;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            hs_q <= 1'b0; hs_qq <= 1'b0;
            vs_q <= 1'b0; vs_qq <= 1'b0;
            blank_q <= 1'b1;
            r_q <= 6'd0; g_q <= 6'd0; b_q <= 6'd0;
        end else if (ce) begin
            hs_q  <= hs_act;  hs_qq <= hs_q;
            vs_q  <= vs_act;  vs_qq <= vs_q;
            blank_q <= blank;
            r_q <= r; g_q <= g; b_q <= b;
        end
    end
    wire hs_lead = hs_q & ~hs_qq;   // inicio de línea de salida (31kHz)
    wire vs_lead = vs_q & ~vs_qq;   // inicio de frame

    reg  [9:0] out_line;      // línea de salida desde VS (0..624 máx)
    reg  [9:0] x_cnt;         // píxel dentro de la línea (satura)
    reg  [9:0] y0;            // primera línea con píxeles no-blank del frame
    reg        y0_valid;
    reg        frame_started; // hubo ya un VS tras reset

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            out_line      <= 10'd0;
            x_cnt         <= 10'h3FF;
            y0            <= 10'd0;
            y0_valid      <= 1'b0;
            frame_started <= 1'b0;
        end else if (ce) begin
            // x_cnt: 0 en el primer no-blank tras hs_lead; para en blank
            if (hs_lead)
                x_cnt <= 10'd0;
            else if (!blank_q && x_cnt != 10'h3FF)
                x_cnt <= x_cnt + 10'd1;

            // contador de líneas de salida + re-arme de y0 por frame
            if (vs_lead) begin
                out_line      <= 10'd0;
                y0_valid      <= 1'b0;
                frame_started <= 1'b1;
            end else if (hs_lead)
                out_line <= out_line + 10'd1;

            // latch de la primera línea activa del frame
            if (!vs_lead && frame_started && !blank_q && !y0_valid) begin
                y0       <= out_line;
                y0_valid <= 1'b1;
            end
        end
    end

    // y0 efectivo: durante la primera línea activa (antes del latch) vale
    // out_line, así el primer píxel del frame ya se captura con n = 0.
    wire [9:0] y0_eff = y0_valid ? y0 : out_line;
    wire [9:0] rel    = out_line - y0_eff;      // línea de salida relativa
    wire [8:0] n_nat  = rel[9:1];               // línea nativa 0..287
    wire cap_ok = frame_started && !blank_q &&
                  ~rel[0] &&                    // solo scanline PAR del par
                  (n_nat < NATIVE_LINES) &&     // clamp (V9968: 240)
                  (x_cnt < RING_W);             // clamp (V9968: 800)

    reg  [14:0] wr_addr;
    reg  [17:0] wr_data;
    reg         wr_en;
    reg         wr_sol;      // V9991: primer pixel de la linea (con wr_en)
    reg  [7:0]  wr_line;     // V9991: linea nativa 0..239 (con wr_en)
    reg  [14:0] rel800;      // rel[5:1]*800 registrado (v4-timing)

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            wr_en   <= 1'b0;
            wr_addr <= 15'd0;
            wr_data <= 18'd0;
            wr_sol  <= 1'b0;
            wr_line <= 8'd0;
        end else if (ce) begin
            wr_en <= 1'b0;
            // v4-timing: el producto rel*800 REGISTRADO (camino corto
            // reg->mult->reg, patron _56b del read-side): a 85.9 el x800
            // dentro del mux por-pixel era -2.4ns. rel es estable toda la
            // linea y x_cnt==0 llega >=1 ce tras hs_lead: rel800 ya vale.
            rel800 <= rel[5:1] * 15'd640;
            if (cap_ok) begin
                wr_en   <= 1'b1;
                wr_data <= {r_q, g_q, b_q};
                wr_addr <= (x_cnt == 10'd0) ? rel800 : wr_addr + 15'd1;
                wr_sol  <= (x_cnt == 10'd0);
                wr_line <= n_nat[7:0];
            end
        end
    end

    // V9991: en el modo 2 (ventana) el anillo lo escribe el lector del frame buffer (g_win); si no, la captura
    wire        win_c;           // win_en en el dominio clk (0 sin WINDOW)
    wire        ring_we_m;
    wire [14:0] ring_addr_m;
    wire [17:0] ring_data_m;
    always @(posedge clk) begin
        if (ring_we_m)
            mem[ring_addr_m] <= ring_data_m;
    end

    // Toggle de frame: al INICIO de la línea y0 + LOCK_LINES (relativo a y0)
    reg frame_tgl = 1'b0;
    always @(posedge clk or negedge resetn) begin
        if (!resetn)
            frame_tgl <= 1'b0;
        else if (ce && hs_lead && !vs_lead && y0_valid &&
                 (out_line == y0 + LOCK_LINES - 1))
            frame_tgl <= ~frame_tgl;
    end

    // ========================================================================
    // Dominio clk_pixel (74.25 MHz): sincronizadores
    // ========================================================================

    reg [2:0] tgl_x = 3'b000;
    always @(posedge clk_pixel)
        tgl_x <= {tgl_x[1:0], frame_tgl};
    // V9991: en el modo 2 (ventana) el hdmi corre LIBRE (el V9968 llega por su frame buffer): sin re-anclaje.
    // 29/10/2026: y en el modo 1 (el V9990 entero, que va por su frame buffer y no necesita el V9968): con el
    // compositor la HDMI entera seguia el frame del V9968 (59,92 Hz) tambien en modo V9990, que antes del
    // compositor iba a 60,000 Hz; algunos monitores (BenQ, Dell) parpadean o rechazan los 59,92. Ahora solo los
    // modos 0 (V9968 entero) y 3 (Video9000, el V9968 por el anillo) siguen enganchados al V9968. Desde el V9991f
    // (29/10/2026, noche) el compositor manda tambien esos dos por el frame buffer (win_en, ventana de pantalla
    // completa): con el compositor el enganche ya no se usa nunca; queda para la linea sin WINDOW.
    wire win_lock_off = ((WINDOW != 0) ? win_en : 1'b0) | ((EXT_COMPOSE != 0) ? free_run : 1'b0);
    wire hdmi_rst_raw = (tgl_x[2] ^ tgl_x[1]) & ~win_lock_off;    // pulso de 1 ciclo por frame

    // _134 (bug #14, CAUSA RAIZ PROPUESTA): con los relojes reales
    // (clk_86 = 27*35/11, clk_pixel = 27*55/20, ratio exacto 121/140) el
    // yank por-frame aterrizaba SIEMPRE en cx~1595 = DENTRO de la ventana
    // de data islands del frame VIC4 (cx en [1290,1610), todas las lineas)
    // => truncaba un paquete HDMI (audio/ACR/NULL) en el cable CADA frame,
    // sin ECC ni guard de cierre. El video lo tolera; el audio del receptor
    // no: deficit de muestras + CTS basura ocasional = "30-40s bien y luego
    // va y viene" (el colchon del sink se drena y resbala). La v9958
    // aterriza en zona inocua — por eso la _116 suena perfecta con el MISMO
    // transmisor. Fix: DIFERIR el reset hasta que cx salga de la zona de
    // peligro (preambulo + guard + islands + guard de cierre, ensanchada
    // +-2 por el registro del pulso). Retardo maximo ~340 px = 4.6 us,
    // CONSTANTE (el aterrizaje es deterministico) e invisible para el
    // realineado del conversor. defer_cnt/tear_cnt = assert en silicio:
    // esperado defer ~60/s (el yank SI caia en la ventana) y tear = 0.
    // _136 (leccion HW _134/_135: TRES dados en pantalla negra): diferir el
    // reset SIN compensar movia el anclaje cx/cy ~27 px y el lado de
    // lectura del conversor (ventanas por valor de cx/cy calibradas con la
    // fase del reset) dejaba de casar con el lado de escritura => negro.
    // Ahora el reset diferido re-ancla cx a reset_cx = 1 + ciclos
    // diferidos: la trayectoria cx/cy queda IDENTICA ciclo a ciclo a la
    // del diseno viejo — el conversor NO puede notar la diferencia — y el
    // data island en vuelo se salva igual (el reset ya no cae dentro).
    reg  rst_pend  = 1'b0;
    reg  hdmi_rst  = 1'b0;
    reg  [11:0] rst_dly = 12'd0;     // ciclos desde el yank crudo
    reg  [11:0] rst_cx  = 12'd0;     // re-anclaje compensado para hdmi.sv
    // ventana de DECISION (peligro real ensanchada +-2 por el registro del
    // pulso) y zona de PELIGRO real (para el assert tear)
    wire in_defer_win = pal_x ? (cx >= 12'd1278 && cx < 12'd1870)
                              : (cx >= 12'd1278 && cx < 12'd1620);
    wire in_danger    = pal_x ? (cx >= 12'd1280 && cx < 12'd1868)
                              : (cx >= 12'd1280 && cx < 12'd1618);
    reg [5:0] defer_cnt = 6'd0;
    reg [4:0] tear_cnt  = 5'd0;
    always @(posedge clk_pixel) begin
        hdmi_rst <= 1'b0;
        if (hdmi_rst_raw) begin
            rst_dly <= 12'd1;
            if (in_defer_win) begin
                rst_pend  <= 1'b1;
                defer_cnt <= defer_cnt + 6'd1;
            end
            else begin
                hdmi_rst <= 1'b1;
                rst_cx   <= 12'd1;   // 1 ciclo de registro (vs wire viejo)
            end
        end
        else if (rst_pend) begin
            rst_dly <= rst_dly + 12'd1;
            if (!in_defer_win) begin
                rst_pend <= 1'b0;
                hdmi_rst <= 1'b1;
                rst_cx   <= rst_dly + 12'd1;
            end
        end
        if (hdmi_rst && in_danger) tear_cnt <= tear_cnt + 5'd1;
    end
    assign dbg_defer = defer_cnt;
    assign dbg_tear  = tear_cnt;

    reg [1:0] pal_sync = 2'b00;
    always @(posedge clk_pixel)
        pal_sync <= {pal_sync[0], pal_mode};
    // _168: con ENABLE_PAL=0 esto es una CONSTANTE, no una senal. Ver la
    // cabecera del modulo: es lo que permite al sintetizador podar el back-end
    // PAL entero, que hoy esta muerto porque pal_mode llega cableado a cero.
    wire pal_x = (ENABLE_PAL != 0) ? pal_sync[1] : 1'b0;

    // _56: aspecto cuasi-estático desde la config del menú (2FF por higiene)
    reg [1:0] aspect_sync = 2'b00;
    always @(posedge clk_pixel)
        aspect_sync <= {aspect_sync[0], aspect_wide};
    wire wide_x = aspect_sync[1];

    // _58: scanlines cuasi-estático desde la config del menú (2FF por higiene)
    reg [1:0] scan_sync = 2'b00;
    always @(posedge clk_pixel)
        scan_sync <= {scan_sync[0], scanlines};
    wire scan_x = scan_sync[1];

    // ========================================================================
    // Contadores HDMI (reales o conductuales) y mux NTSC/PAL
    // ========================================================================

    logic [10:0] cx_ntsc;   // VIC 4:  BIT_WIDTH 11 (frame 1650×750)
    logic [9:0]  cy_ntsc;
    logic [11:0] cx_pal;    // VIC 19: BIT_WIDTH 12 (frame 1980×750)
    logic [9:0]  cy_pal;

    wire [11:0] cx = pal_x ? cx_pal : {1'b0, cx_ntsc};
    wire [9:0]  cy = pal_x ? cy_pal : cy_ntsc;

    // ========================================================================
    // Escalado a la ventana activa — conmutable por aspecto (_56):
    //   wide_x=0 (4:3, SIN CAMBIOS): 960×720 centrada (X ∈ [160,1120)),
    //     acumulador xcnt+=720 con umbral 960 (720→960), reset en cx==0.
    //   wide_x=1 (16:9 estirado): 1280×720 completa (X ∈ [0,1280)),
    //     xcnt+=720 con umbral 1280 (720→1280). Como la ventana empieza en
    //     x=0 y xx corre 2 ciclos POR DELANTE (pipeline BRAM+RGB), el
    //     acumulador arranca al FINAL de la línea ANTERIOR: acumula en
    //     cx ∈ {W-2,W-1} ∪ [0,1277) y resetea en cx==W-3, con W = ancho de
    //     línea del frame HDMI activo (1650 NTSC / 1980 PAL).
    //
    // xx/yy se generan 2 ciclos POR DELANTE del cx del hdmi para absorber el
    // pipeline BRAM(1)+RGB(1): así rgb en el ciclo (cx,cy) es EXACTAMENTE el
    // píxel nativo (floor(720·(cx-XSTART)/ANCHO), floor(cy·N/720)) del modo.
    // El escalado VERTICAL no cambia con el aspecto.
    // ========================================================================

    reg [9:0]  xx   = 10'd0;    // 0..799 (píxel nativo del V9968)
    reg [10:0] xcnt = 11'd0;
    reg [8:0]  yy   = 9'd0;     // línea nativa (libre; el addr usa yy[4:0])
    reg [10:0] ycnt = 11'd0;
    reg [9:0]  cy_r = 10'd0;

    // _143 PANTALLA COMPLETA SIEMPRE (como el MSXnano): el escalador llena el
    // 1280 entero -> 256px MSX * 5 = 1280 EXACTO => pixeles UNIFORMES y SIN
    // marco. Se retiran el 4:3 pixel-perfect (_141, imagen pequena con marco
    // que molestaba a Albert) y el 1066 pixel-perfect (_127C): Albert quiere
    // UN modo full-screen como el MSXnano (que no tiene 4:3). wide_x deja de
    // afectar a la geometria (misma ventana full-screen con wrap que el
    // MSXnano, ajustado al nativo de 800 del V9968: xcnt+=800, umbral 1280).
    wire [11:0] wlast    = pal_x ? 12'd1979 : 12'd1649;             // W-1
    wire        xacc_en  = (cx >= wlast - 12'd1) || (cx < XSTOP_W - 12'd3);
    wire [10:0] xthresh  = 11'd1280;                     // ventana = 1280 (full)
    wire [10:0] xinc     = 11'd640;                      // nativo del V9968 = 640
                                                         // => xx = cx>>1 (x2 exacto)
    wire        xrst_now = (cx == wlast - 12'd2);

    always @(posedge clk_pixel) begin : scaler
        reg [10:0] xcnt_next;
        reg [10:0] ycnt_next;
        xcnt_next = xcnt + xinc;                 // V9968 _127C: 800->1066 / 800->1280
        ycnt_next = ycnt + 11'd240;              // V9968: x3 FIJO ambos modos

        // Horizontal: acumula en la ventana adelantada 2 ciclos del modo
        // (4:3: cx ∈ [158,1117) → 959 flancos; 16:9: {W-2,W-1} ∪ [0,1277) →
        // 1279 flancos); xx acaba en 719 y se queda ahí (nunca desborda la
        // línea del ring).
        if (xacc_en) begin
            if (xcnt_next >= xthresh) begin
                xcnt <= xcnt_next - xthresh;
                xx   <= xx + 1'b1;
            end else
                xcnt <= xcnt_next;
        end

        // Vertical: acumula al cambiar de línea (como sms2hdmi). SIN CAMBIOS.
        cy_r <= cy;
        if (cy[0] != cy_r[0]) begin
            if (ycnt_next >= 11'd720) begin
                ycnt <= ycnt_next - 11'd720;
                yy   <= yy + 1'b1;
            end else
                ycnt <= ycnt_next;
        end

        // Resets por posición (prioridad: van los últimos).
        if (xrst_now) begin
            xx   <= 10'd0;
            xcnt <= 11'd0;
        end
        if (cy == 10'd0) begin
            yy   <= 9'd0;
            ycnt <= 11'd0;
        end
    end

    // _56b FIX TIMING (clk_hdmi Setup TNS -341ns, 467 endpoints, TODOS
    // cx → ventana/lookahead → yy*720+xx → ADB de la BRAM en un ciclo de
    // 13.468ns): el producto yy*720 es CONSTANTE durante toda la línea →
    // se precalcula REGISTRADO (yy720_r / yy720_inc_r: camino corto
    // reg→mult-por-constante→reg, sin cx) y la dirección por píxel queda
    // base + xx (sumador de 15 bits). Los flags del lookahead 16:9 también
    // van REGISTRADOS un ciclo antes: los comparadores de cx salen por
    // completo del cono del ADB.
    //
    // Lookahead vertical 16:9 (con la base registrada, un ciclo MÁS que en
    // la _56 original): los fetches cuya línea destino aún no está en
    // yy720_r son los de cx ∈ {W-2, W-1, 0, 1}. En ESOS 4 ciclos la base
    // correcta es EXACTAMENTE yy720_inc_r (el producto de yy_inc registrado
    // el ciclo ANTERIOR): en cx∈{W-2,W-1} yy_inc se calculó con los regs de
    // la línea actual (→ línea siguiente), y en cx∈{0,1} con los de la línea
    // previa (→ línea actual) porque el acumulador vertical actualiza en el
    // flanco 0→1 — en los 4 casos da la línea DESTINO del fetch (verificado
    // caso a caso; el TB lo cubre con la geometría estricta de x=0..3 de
    // cada línea). Si el destino es la línea 0 del frame, base = 0.
    // En 4:3 los flags no aplican: base = yy720_r = yy*720 con 1 ciclo de
    // retardo — idéntico dentro de su ventana (yy estable desde cx=1, sus
    // fetches empiezan en cx=158). Geometría de AMBOS modos sin cambios.
    wire [10:0] ycnt_nx = ycnt + 11'd240;        // V9968: x3 fijo
    wire [8:0]  yy_inc  = (ycnt_nx >= 11'd720) ? yy + 9'd1 : yy;

    reg [14:0] yy720_r     = 15'd0;   // yy[4:0]     * 800, registrado (nombre historico)
    reg [14:0] yy720_inc_r = 15'd0;   // yy_inc[4:0] * 800, registrado
    reg        use_tgt_r   = 1'b0;    // ciclo ACTUAL de prefetch 16:9 (cx ∈ {W-2,W-1,0,1})
    reg        tgt_is0_r   = 1'b0;    // ...y la línea destino es la 0 del frame

    always @(posedge clk_pixel) begin
        yy720_r     <= yy[4:0]     * 15'd640;
        yy720_inc_r <= yy_inc[4:0] * 15'd640;
        // flags para el ciclo SIGUIENTE: cx+1 ∈ {W-2,W-1,0,1} ⟺ cx ∈ {W-3,W-2,W-1,0}
        use_tgt_r   <= (cx >= wlast - 12'd2) || (cx == 12'd0);
        tgt_is0_r   <= ((cx >= wlast - 12'd2) && (cy == 10'd749)) ||
                       ((cx == 12'd0) && (cy == 10'd0));
    end

    // Lectura del ring: base registrada + xx; dato registrado + registro rgb.
    // _143: full-screen SIEMPRE -> el wrap de fin de linea (use_tgt_r) aplica
    // en ambos aspectos (ya no gateado por wide_x).
    wire [14:0] rd_base = use_tgt_r ? (tgt_is0_r ? 15'd0 : yy720_inc_r)
                                    : yy720_r;
    wire [14:0] rd_addr_n = rd_base + {5'd0, xx};
    wire [14:0] rd_addr_w;                               // V9991: direccion de la ventana (g_win)
    wire        win_novalid;                             // por el frame buffer y sin ningun frame publicado (el arranque) -> negro
    wire        s3_act;                                  // 4:3 + Scale3x en este cuadro (g_win; registrada en el vblank)
    wire [14:0] s3_addr;                                 // direccion del anillo del 4:3 (registrada)
    wire [17:0] s3_px;                                   // pixel del 4:3 (registrado, mismo retardo que rd_data; 0 fuera de x 160..1119)
    wire [14:0] rd_addr   = win_lock_off ? (s3_act ? s3_addr : rd_addr_w) : rd_addr_n;
    reg  [17:0] rd_data = 18'd0;
    reg  [23:0] rgb     = 24'd0;
    wire [17:0] rd_pix  = s3_act ? s3_px : rd_data;      // 4:3 + Scale3x: el pixel lo arma g_win (s3_px ya viene alineado con rd_data)

    // _143: ventana activa = PANTALLA COMPLETA (como el MSXnano): cx+1 ∈
    // [0,1280); en cx==wlast el proximo pixel es el x=0 de la linea siguiente
    // (activa si cy<719, o cy==749 -> linea 0). wide_x ya no afecta.
    wire win_next = ((cx < XSTOP_W - 12'd1) && (cy < 10'd720)) ||
                    ((cx == wlast) && ((cy < 10'd719) || (cy == 10'd749)));

    always @(posedge clk_pixel) begin
        rd_data <= mem[rd_addr];
        rgb     <= !win_next  ? 24'h101010 :
                   win_novalid ? 24'h000000 :              // sin frame del V9968 en la DDR: negro, no el anillo viejo (era magenta, diagnostico
                                                           // del 29/10; con la pantalla completa por el frame buffer saldria en cada arranque)
                                 // por el frame buffer (v9990_fb.px18) el bit 12 es el YS, 0 en el V9968: el LSB de R se
                                 // replica del MSB como el de G y B (antes salia 0 y el blanco quedaba F8,FC,FC; 29/10/2026)
                                 {rd_pix[17:13], win_lock_off ? rd_pix[17] : rd_pix[12], 2'b00,
                                  rd_pix[11:6],  2'b00,
                                  rd_pix[5:0],   2'b00};
    end

    // ========================================================================
    // _58: scanlines — atenuación al 50% (el look del core 480p original:
    // {1'b0, Video, 1'b0} = mitad) de la ÚLTIMA repetición de cada línea
    // nativa. Con el acumulador vertical arrancando en ycnt=0 en cy=0, la
    // fase de repetición es una función cerrada de cy:
    //   NTSC ×3:  dim ⟺ cy mod 3 == 2            (1 línea oscura de cada 3)
    //   PAL ×2.5: dim ⟺ cy mod 5 ∈ {2,4}         (patrón 3-2: última de cada
    //                                              grupo de 3 y de 2)
    // dim es constante por línea de salida → se calcula con contadores de
    // fase registrados y se LATCHEA al FINAL de la línea anterior
    // (cx == wlast): válido desde el cx==0 de su línea (cubre el x=0 del
    // 16:9) y fuera de todo camino crítico (nada de esto toca el cono del
    // ADB de la BRAM que dio el TNS -341 de la _56). Con scanlines=0,
    // dim_r=0 y rgb_out ≡ rgb (cero cambio).
    // ========================================================================
    reg [1:0] ph3   = 2'd0;      // fase NTSC 0..2 de la línea ACTUAL
    reg [2:0] ph5   = 3'd0;      // fase PAL  0..4 de la línea ACTUAL
    reg       dim_r = 1'b0;

    wire [1:0] ph3_nx = (cy >= 10'd749) ? 2'd0
                                        : ((ph3 == 2'd2) ? 2'd0 : ph3 + 2'd1);
    wire [2:0] ph5_nx = (cy >= 10'd749) ? 3'd0
                                        : ((ph5 == 3'd4) ? 3'd0 : ph5 + 3'd1);

    always @(posedge clk_pixel) begin
        if (cx == wlast) begin
            ph3   <= ph3_nx;
            ph5   <= ph5_nx;
            // V9968: vertical x3 en AMBOS modos -> patron 1-de-3 tambien en PAL
            // 4:3 + Scale3x: sin scanlines (las tres lineas de HDMI de cada punto ya son distintas)
            dim_r <= scan_x && !s3_act && (ph3_nx == 2'd2);
        end
    end

    wire [23:0] rgb_dim = dim_r ? {1'b0, rgb[23:17],
                                   1'b0, rgb[15:9],
                                   1'b0, rgb[7:1]}
                                : rgb;

    // ========================================================================
    // V3.1 OVERLAY (iosys_bl616 / textdisp de TangCore)
    // ------------------------------------------------------------------------
    // textdisp pinta una imagen de 256x224. Se mapea sobre la ventana activa
    // (1280x720, _143 full-screen) con factores ENTEROS, sin un solo divisor:
    //   horizontal  256 * 5 = 1280  EXACTO  -> ovl_x sube 1 cada 5 pixeles
    //   vertical    224 * 3 =  672          -> banda cy en [24,696), 1 de cada 3
    // Fuera de la banda vertical el overlay pinta negro, para que al encenderlo
    // tape la pantalla ENTERA y no deje dos franjas con imagen del MSX.
    //
    // Los contadores van 2 CICLOS POR DELANTE de cx, igual que xx/yy con el
    // ring: la cabecera de textdisp avisa de "2-cycle latency", asi que el
    // color llega justo en el ciclo del pixel al que corresponde. El desfase
    // residual es de 2 pixeles de 1280 -- invisible, y NO deriva.
    // ========================================================================
    localparam [9:0] OVL_Y0 = 10'd24;    // 720 - 672 = 48, centrada
    localparam [9:0] OVL_Y1 = 10'd696;

    reg [2:0] ox_ph = 3'd0;
    reg [7:0] ox_r  = 8'd0;
    reg [1:0] oy_ph = 2'd0;
    reg [7:0] oy_r  = 8'd0;
    reg       oy_en = 1'b0;

    // misma ancla que el escalador: xrst_now = (cx == wlast - 2)
    wire [9:0] cy_nx = (cy >= 10'd749) ? 10'd0 : cy + 10'd1;

    always @(posedge clk_pixel) begin
        if (xrst_now) begin
            ox_ph <= 3'd0;
            ox_r  <= 8'd0;
            if (cy_nx == OVL_Y0) begin
                oy_ph <= 2'd0; oy_r <= 8'd0; oy_en <= 1'b1;
            end else if (cy_nx == OVL_Y1) begin
                oy_en <= 1'b0;
            end else if (oy_en) begin
                if (oy_ph == 2'd2) begin oy_ph <= 2'd0; oy_r <= oy_r + 8'd1; end
                else                     oy_ph <= oy_ph + 2'd1;
            end
        end else begin
            if (ox_ph == 3'd4) begin ox_ph <= 3'd0; ox_r <= ox_r + 8'd1; end
            else                     ox_ph <= ox_ph + 3'd1;
        end
    end

    assign ovl_x = ox_r;
    assign ovl_y = oy_r;

    // oy_en registrado una vez mas: ovl_color llega 2 ciclos tarde, y la banda
    // tiene que juzgarse con el MISMO retardo o se cuela una linea de basura
    // en los bordes de la banda.
    reg oy_en_d1 = 1'b0, oy_en_d2 = 1'b0;
    always @(posedge clk_pixel) begin
        oy_en_d1 <= oy_en;
        oy_en_d2 <= oy_en_d1;
    end

    // BGR5 -> RGB888. COLOR_TEXT de textdisp es 15'b10000_11111_11111 y se
    // describe como amarillo: eso solo cuadra con [14:10]=B [9:5]=G [4:0]=R.
    wire [23:0] ovl_rgb = { ovl_color[4:0],   3'b000,     // R
                            ovl_color[9:5],   3'b000,     // G
                            ovl_color[14:10], 3'b000 };   // B

    // V9991: con EXT_COMPOSE el pixel compuesto por v9991_compose (a partir de rgb_pre = rgb_dim y del
    // V9990) sustituye a rgb_dim; el overlay del F12 sigue encima de todo.
    assign rgb_pre = rgb_dim;
    assign cx_out  = cx_ntsc;
    assign cy_out  = cy_ntsc;
    wire [23:0] rgb_out = ovl_on ? (oy_en_d2 ? ovl_rgb : 24'h000000)
                                 : ((EXT_COMPOSE != 0) ? rgb_ext : rgb_dim);

    // ========================================================================
    // V9991 VENTANA (WINDOW = 1): el V9968 por un frame buffer en la DDR
    // ------------------------------------------------------------------------
    // En el modo 2 del compositor (win_en) el anillo de 32 lineas no lo escribe
    // la captura del VDP sino el lector del frame buffer (v9990_fb, el mismo
    // modulo que el V9990: 3 slots de 240 x 1280 B en FB_BASE, 20 rafagas por
    // linea, IDs 6/7), y el lado 720p lee el anillo con un origen y una escala
    // programables: para cada pixel de pantalla de la ventana, la columna y la
    // linea del V9968 que tocan (x0, y0, x1/x2, sx0, sy0). El hdmi deja de
    // re-anclarse por frame (corre libre, como el del V9990) y la peticion de
    // frame va armada en cy 0 y disparada en cy 722. La captura al frame buffer
    // solo corre en el modo 2: fuera de el, cero trafico en el GP1.
    //
    // Por que un frame buffer y no el anillo: el anillo solo sirve leyendo a la
    // vez que escribe el VDP (lag fijo de 3..29 lineas); una ventana movida en
    // vertical, o a x2, lee lineas que el anillo ya ha sobreescrito.
    //
    // Alineacion (la del escalador de siempre): el pixel p de la linea L sale en
    // cx = p y su direccion del anillo se calcula en cx = p - 2: la columna va 2
    // ciclos por delante (xx_w, cargada en cx = wx_start - 3) y la linea se
    // prepara al final de la linea anterior (cx = wlast - 4) para cy_nx. Con la
    // esquina fuera de la pantalla (x0 / y0 < 0) el origen se adelanta:
    // columna sx0 + (-x0) / (2 * scl) y linea sy0 + (-y0) / (3 * scl), esta por
    // restas sucesivas durante la linea 720 del vblank (latch en la 721).
    // ========================================================================
    generate
    if (WINDOW != 0) begin : g_win
        reg [1:0] win_s = 2'b00;
        always @(posedge clk) win_s <= {win_s[0], win_en};
        assign win_c = win_s[1];

        // ---- frame buffer: escritor (la captura, solo en el modo 2) y lector (al anillo) ----
        wire        fb_we;
        wire [14:0] fb_addr;
        wire [17:0] fb_data;
        reg         rd_req_tgl = 1'b0;
        reg  [1:0]  rd_slot_r  = 2'd0;
        reg  [7:0]  yy_gray    = 8'd0;
        wire [1:0]  pubx_slot;
        wire [3:0]  pubx_reso;
        wire        pubx_valid;
        reg         cur_valid  = 1'b0;
        v9990_fb #(.FB_BASE(FB_BASE), .SLOT_SIZE(32'h0006_0000), .STRIDE(32'd1280), .PREFETCH(16),
                   .RING_W(640), .BURSTS_FIXED(6'd20), .AWID_V(6'd6), .ARID_V(6'd7)) u_fb68 (
            .clk(clk), .resetn(resetn), .aresetn(aresetn),
            .ce(ce), .wr_enable(win_c), .cap_en(wr_en), .cap_sol(wr_sol), .cap_line({1'b0, wr_line}),
            .cap_rgb({1'b0, wr_data[17:13], wr_data[11:7], wr_data[5:1]}), .frame_end(vs_lead), .reso(4'd0),
            .ring_we(fb_we), .ring_addr(fb_addr), .ring_data(fb_data),
            .clk_pixel(clk_pixel), .rd_req_tgl(rd_req_tgl), .rd_slot(rd_slot_r), .rd_reso(4'd0),
            .rd_yy_gray({1'b0, yy_gray}), .pubx_slot(pubx_slot), .pubx_reso(pubx_reso), .pubx_valid(pubx_valid),
            .skip_en(1'b0), .skip_y0(10'd0), .skip_y1(10'd0), .skip_wx0(10'd0), .skip_wx1(10'd0), .skip_odd(1'b0), .wslot_o(),
            .dbg_underrun(dbg_win_underrun), .dbg_wr_lines(),
            .M_AWID(M_AWID), .M_AWADDR(M_AWADDR), .M_AWLEN(M_AWLEN), .M_AWSIZE(M_AWSIZE),
            .M_AWBURST(M_AWBURST), .M_AWLOCK(M_AWLOCK), .M_AWCACHE(M_AWCACHE), .M_AWPROT(M_AWPROT),
            .M_AWQOS(M_AWQOS), .M_AWVALID(M_AWVALID), .M_AWREADY(M_AWREADY),
            .M_WID(M_WID), .M_WDATA(M_WDATA), .M_WSTRB(M_WSTRB), .M_WLAST(M_WLAST),
            .M_WVALID(M_WVALID), .M_WREADY(M_WREADY),
            .M_BID(M_BID), .M_BRESP(M_BRESP), .M_BVALID(M_BVALID), .M_BREADY(M_BREADY),
            .M_ARID(M_ARID), .M_ARADDR(M_ARADDR), .M_ARLEN(M_ARLEN), .M_ARSIZE(M_ARSIZE),
            .M_ARBURST(M_ARBURST), .M_ARLOCK(M_ARLOCK), .M_ARCACHE(M_ARCACHE), .M_ARPROT(M_ARPROT),
            .M_ARQOS(M_ARQOS), .M_ARVALID(M_ARVALID), .M_ARREADY(M_ARREADY),
            .M_RID(M_RID), .M_RDATA(M_RDATA), .M_RRESP(M_RRESP), .M_RLAST(M_RLAST),
            .M_RVALID(M_RVALID), .M_RREADY(M_RREADY)
        );
        assign ring_we_m     = win_c ? fb_we   : wr_en;
        assign ring_addr_m   = win_c ? fb_addr : wr_addr;
        assign ring_data_m   = win_c ? fb_data : wr_data;
        assign dbg_win_valid = cur_valid;
        assign win_novalid   = win_lock_off & ~cur_valid;

        // ---- peticion de frame: una por frame de salida (armada en cy 0, disparada en cy 722) ----
        reg req_armed = 1'b1;
        always @(posedge clk_pixel) begin
            if (cy == 10'd0 && cx == 12'd0) req_armed <= 1'b1;
            if (req_armed && cy == 10'd722 && cx == 12'd0) begin rd_slot_r <= pubx_slot; cur_valid <= pubx_valid; end
            if (req_armed && cy == 10'd722 && cx == 12'd2) begin
                if (cur_valid) rd_req_tgl <= ~rd_req_tgl;
                req_armed <= 1'b0;
            end
        end

        // ---- origen de la lectura para el frame siguiente (se calcula en el vblank) ----
        reg  [10:0] wx_start = 11'd0;    // primera columna de pantalla de la ventana (0 si x0 < 0)
        reg  [9:0]  wy_start = 10'd0;    // primera linea de pantalla de la ventana (0 si y0 < 0)
        reg  [9:0]  xx0  = 10'd0;        // columna del anillo en wx_start
        reg  [1:0]  xph0 = 2'd0;         // y su fase (0 .. 2*scl-1)
        reg         xalt0 = 1'b0;        // x0,75: la columna de wx_start es la de 1 px (la segunda del par)
        reg  [7:0]  yy0  = 8'd0;         // linea del anillo en wy_start
        reg  [4:0]  yacc0 = 5'd0;        // y su fase: acumulador en dieciochoavos de linea (0..17)
        reg  [13:0] ydiv_rem = 14'd0;    // (-y0) * ystep / 18 por restas sucesivas en la linea 720
        reg  [8:0]  ydiv_q   = 9'd0;
        wire [11:0] negx = -win_x0;      // vale cuando x0 < 0
        wire [10:0] negy = -win_y0;
        // escala (29/10/2026, x0,5 para el MSX entero en 512 x 318 de un escritorio B7; x0,75 para 768 x 477 en B5):
        // lineas por px de salida en DIECIOCHOAVOS: x1 6/18 (3 px por linea), x2 3/18 (6 px), x0,5 12/18 (1,5 px:
        // patron 2,1), x0,75 8/18 (2,25 px: patron 3,2,2,2); columnas: 2, 4, 1 y 1,5 px (pares de columnas de 2 y 1 px)
        wire        scl_q75  = win_scl[0] & win_scl[1];
        wire        scl_x2   = win_scl[1] & ~win_scl[0];
        wire        scl_half = win_scl[0] & ~win_scl[1];
        wire [3:0]  ystep    = scl_x2 ? 4'd3 : scl_half ? 4'd12 : scl_q75 ? 4'd8 : 4'd6;
        // x0,75 con la esquina fuera: -x0 = 3q + r -> columna 2q (r = 0, 1; fase r) o 2q + 1 (r = 2, la de 1 px).
        // q = -x0 * 683 / 2048, exacta hasta 1650
        wire [21:0] negx683 = negx[10:0] * 11'd683;
        wire [9:0]  q3      = negx683[20:11];
        wire [1:0]  r3      = negx[1:0] - {q3[0], 1'b0} - q3[1:0];          // -x0 - 3q (mod 4), vale 0..2
        wire [10:0] xx0_s = {1'b0, win_sx0} + (scl_x2 ? {1'b0, negx[11:2]} : scl_half ? negx[10:0] :
                                               scl_q75 ? {q3, 1'b0} + {10'd0, r3[1]} : negx[11:1]);
        wire [9:0]  yy0_s = {1'b0, win_sy0} + {1'b0, ydiv_q};
        // El compositor cambia win_* en (0,720): la division corre en la linea 720 desde cx = 4 y el origen
        // nuevo se latchea en (0,721), ANTES de la peticion de frame (722): asi el lector arranca ya contra
        // la linea de origen nueva y un cambio de ventana no le cuenta un underrun falso.
        always @(posedge clk_pixel) begin
            if (cy == 10'd720 && cx == 12'd4) begin
                ydiv_rem <= win_y0[10] ? ({3'b000, negy} * {10'd0, ystep}) : 14'd0;  // hasta 720 * 12 = 8640
                ydiv_q   <= 9'd0;
            end else if (cy == 10'd720 && cx > 12'd4 && ydiv_rem >= 14'd18 && ydiv_q != 9'd511) begin
                ydiv_rem <= ydiv_rem - 14'd18;                                       // 480 pasos como mucho (linea de 1650)
                ydiv_q   <= ydiv_q + 9'd1;
            end
            if (cy == 10'd721 && cx == 12'd0) begin
                wx_start <= win_x0[11] ? 11'd0 : win_x0[10:0];
                wy_start <= win_y0[10] ? 10'd0 : win_y0[9:0];
                xx0      <= win_x0[11] ? ((xx0_s > 11'd639) ? 10'd639 : xx0_s[9:0]) : win_sx0;
                xph0     <= win_x0[11] ? (scl_x2 ? negx[1:0] : scl_half ? 2'd0 : scl_q75 ? {1'b0, r3 == 2'd1} : {1'b0, negx[0]}) : 2'd0;
                xalt0    <= win_x0[11] && scl_q75 && (r3 == 2'd2);
                yy0      <= (yy0_s > 10'd239) ? 8'd239 : yy0_s[7:0];
                yacc0    <= ydiv_rem[4:0];
            end
        end

        // ---- columna: 2 ciclos por delante de cx, cargada en wx_start - 3 ----
        reg  [9:0]  xx_w = 10'd0;
        reg  [1:0]  xph  = 2'd0;
        reg         xalt = 1'b0;                                 // x0,75: columna de 1 px (segunda del par)
        wire [1:0]  xph_max = scl_x2 ? 2'd3 : scl_half ? 2'd0 : (scl_q75 && xalt) ? 2'd0 : 2'd1;
        wire [10:0] xrst_w  = (wx_start >= 11'd3) ? (wx_start - 11'd3) : (11'd1647 + wx_start);   // wlast+1-3+wx_start
        always @(posedge clk_pixel) begin
            if (cx == {1'b0, xrst_w}) begin xx_w <= xx0; xph <= xph0; xalt <= xalt0; end
            else if (xph == xph_max) begin xph <= 2'd0; xalt <= scl_q75 & ~xalt; if (xx_w != 10'd639) xx_w <= xx_w + 10'd1; end
            else xph <= xph + 2'd1;
        end

        // ---- linea: preparada en cx = wlast - 4 para la linea siguiente; en el vblank, el origen ----
        reg  [7:0]  yy_w = 8'd0;
        reg  [4:0]  yacc = 5'd0;                                 // dieciochoavos de linea acumulados (0..17)
        wire [5:0]  yacc_n = {1'b0, yacc} + {2'b00, ystep};
        always @(posedge clk_pixel) begin
            if (cx == 12'd1645) begin
                if (cy_nx >= 10'd720 || cy_nx == wy_start) begin yy_w <= yy0; yacc <= yacc0; end
                else if (cy_nx > wy_start) begin
                    if (yacc_n >= 6'd18) begin yacc <= yacc_n[4:0] - 5'd18; if (yy_w != 8'd239) yy_w <= yy_w + 8'd1; end
                    else yacc <= yacc_n[4:0];
                end
            end
            yy_gray <= yy_w ^ (yy_w >> 1);
        end

        // ---- direccion del anillo: la linea (registrada) + la columna ----
        reg [14:0] yyw640_r = 15'd0;
        always @(posedge clk_pixel) yyw640_r <= yy_w[4:0] * 15'd640;
        assign rd_addr_w = yyw640_r + {5'd0, xx_w};

        // ====================================================================
        // 4:3 + SCALE3X (30/10/2026)
        // --------------------------------------------------------------------
        // Con fs43 y SOLO en la ventana de pantalla completa (x0 = y0 = 0, x1, origen 0/0: el modo 0 del compositor; el
        // top ya quita el modo 2 de la tecla V/B) la imagen sale a 960 x 720 centrada (x 160..1119), negro fuera, y cada
        // punto de la rejilla de 320 x 240 (columnas 2d y 2d+1 del anillo) se convierte en un bloque de 3 x 3 px con
        // Scale3x (AdvMAME3x, dominio publico; reglas E0..E8 sobre los vecinos A..I, el borde de la imagen se repite).
        //
        // Las TRES lineas nativas a la vez, SIN BRAM de mas: el anillo tiene un solo puerto de lectura pero un punto
        // dura 3 ciclos de pixel, asi que en cada punto se leen sus tres filas (arriba, actual, abajo) en 3 ciclos, una
        // por ciclo; cada una de las 3 lineas de HDMI de una linea nativa lo repite entero. El anillo conserva las
        // lineas yy-15..yy+15 (el lector va PREFETCH = 16 por delante), asi que yy-1 e yy+1 siempre estan.
        //
        // Tuberia (todo registrado a 74,25 MHz; i = punto, "ranura" de 3 ciclos; cx de la direccion de la ranura i = 149 + 3 i):
        //   dir. (fila U, C, D de la columna i del anillo, 3 ciclos) -> rd_data -> nU / nC / ventana R
        //   -> ventana 3 x 3 (L, M, R x U, C, D; 162 FF) -> banderas (10 comparadores) -> codigos (3 bits)
        //   -> eleccion de los 3 px del bloque -> desplazador de salida (s3_px).  s3_px(cx-1) = pixel cx.
        //
        // 512 PUNTOS (SCREEN6/7, texto de 80 col.): las dos columnas de un punto ya no son iguales, sin Scale3x: 640
        // columnas -> 960 px a 1,5 px por columna (1, 2, 1, 2...), 3 lineas por linea nativa. Lo decide hires512, la senal
        // del propio V9968 (reg_screen_mode = G5, G6 o Text2; vdp.v), sincronizada y latcheada en el vblank con el resto.
        // Un cambio de modo a mitad de cuadro se ve un cuadro con el reparto del modo anterior.
        // ====================================================================
        reg [1:0] fs_s = 2'b00, hi_s = 2'b00;
        always @(posedge clk_pixel) begin fs_s <= {fs_s[0], fs43}; hi_s <= {hi_s[0], hires512}; end
        reg s3_act_r = 1'b0, s3_hi = 1'b0;
        always @(posedge clk_pixel)
            if (cy == 10'd721 && cx == 12'd0) begin
                s3_act_r <= fs_s[1] & win_en & (win_x0 == 12'sd0) & (win_y0 == 11'sd0) & (win_scl == 2'b00) &
                            (win_sx0 == 10'd0) & (win_sy0 == 8'd0);
                s3_hi    <= hi_s[1];
            end
        assign s3_act = s3_act_r;

        // linea de HDMI dentro de la nativa (0..2): cambia con yy_w, al final de la linea anterior
        reg [1:0] rph = 2'd0;
        always @(posedge clk_pixel)
            if (cx == 12'd1645) rph <= (cy_nx == 10'd0 || cy_nx >= 10'd720) ? 2'd0 : (rph == 2'd2) ? 2'd0 : rph + 2'd1;

        // filas del anillo (x 640 registradas): arriba, actual y abajo, con el borde repetido
        wire [7:0] y_up = (yy_w == 8'd0)   ? 8'd0   : yy_w - 8'd1;
        wire [7:0] y_dn = (yy_w == 8'd239) ? 8'd239 : yy_w + 8'd1;
        reg [14:0] b_up = 15'd0, b_dn = 15'd0;
        always @(posedge clk_pixel) begin
            b_up <= y_up[4:0] * 15'd640;
            b_dn <= y_dn[4:0] * 15'd640;
        end

        // etapa 0: contadores de ranura, 2 ciclos por delante de la direccion (visibles en cx = 147)
        reg [1:0] ap = 2'd0;
        reg [8:0] ai = 9'd0;
        always @(posedge clk_pixel)
            if (cx == 12'd146) begin ap <= 2'd0; ai <= 9'd0; end
            else if (ap == 2'd2) begin ap <= 2'd0; if (ai != 9'h1FF) ai <= ai + 9'd1; end
            else ap <= ap + 2'd1;
        // etapa 1: columna del anillo (3x: punto i; 512: columnas 2(i-1) y 2(i-1)+1) y fila; etapa 2: la direccion
        wire [8:0] ci = s3_hi ? ((ai == 9'd0) ? 9'd0 : ai - 9'd1) : ai;
        wire [8:0] cc = (ci > 9'd319) ? 9'd319 : ci;
        reg [9:0]  colw = 10'd0;
        reg [1:0]  rsel = 2'd0;
        reg [14:0] s3_addr_r = 15'd0;
        always @(posedge clk_pixel) begin
            colw      <= {cc, 1'b0} | ((s3_hi && ap != 2'd0) ? 10'd1 : 10'd0);
            rsel      <= s3_hi ? 2'd1 : ap;
            s3_addr_r <= ((rsel == 2'd0) ? b_up : (rsel == 2'd1) ? yyw640_r : b_dn) + {5'd0, colw};
        end
        assign s3_addr = s3_addr_r;

        // contadores alineados con rd_data (un ciclo despues de la direccion, visibles en cx = 150)
        reg [1:0] dp = 2'd0;
        reg [8:0] di = 9'd0;
        always @(posedge clk_pixel)
            if (cx == 12'd149) begin dp <= 2'd0; di <= 9'd0; end
            else if (dp == 2'd2) begin dp <= 2'd0; if (di != 9'h1FF) di <= di + 9'd1; end
            else dp <= dp + 2'd1;

        // ventana 3 x 3: A B C / D E F / G H I = (L,M,R) x (U,C,D). En el punto 0 la izquierda es el propio punto 0
        reg [17:0] nU = 18'd0, nC = 18'd0;
        reg [17:0] wLU = 18'd0, wLC = 18'd0, wLD = 18'd0, wMU = 18'd0, wMC = 18'd0, wMD = 18'd0, wRU = 18'd0, wRC = 18'd0, wRD = 18'd0;
        always @(posedge clk_pixel) begin
            if (dp == 2'd0) nU <= rd_data;
            if (dp == 2'd1) nC <= rd_data;
            if (dp == 2'd2) begin
                wLU <= (di == 9'd1) ? wRU : wMU;  wLC <= (di == 9'd1) ? wRC : wMC;  wLD <= (di == 9'd1) ? wRD : wMD;
                wMU <= wRU;  wMC <= wRC;  wMD <= wRD;
                wRU <= nU;   wRC <= nC;   wRD <= rd_data;
            end
        end

        // banderas (E != X, igualdades de los vecinos), codigos de los 3 px de la linea de HDMI y eleccion
        reg fBH = 1'b0, fDF = 1'b0, eDB = 1'b0, eBF = 1'b0, eDH = 1'b0, eHF = 1'b0, nA = 1'b0, nCr = 1'b0, nG = 1'b0, nI = 1'b0;
        reg t0 = 1'b0, t1 = 1'b0, t2 = 1'b0;
        always @(posedge clk_pixel) begin
            fBH <= (wMU != wMD);  fDF <= (wLC != wRC);
            eDB <= (wLC == wMU);  eBF <= (wMU == wRC);  eDH <= (wLC == wMD);  eHF <= (wMD == wRC);
            nA  <= (wMC != wLU);  nCr <= (wMC != wRU);  nG  <= (wMC != wLD);  nI  <= (wMC != wRD);
            t0 <= fBH & fDF & ((rph == 2'd0) ? eDB : (rph == 2'd1) ? ((eDB & nG) | (eDH & nA)) : eDH);
            t1 <= fBH & fDF & ((rph == 2'd0) ? ((eDB & nCr) | (eBF & nA)) : (rph == 2'd1) ? 1'b0 : ((eDH & nI) | (eHF & nG)));
            t2 <= fBH & fDF & ((rph == 2'd0) ? eBF : (rph == 2'd1) ? ((eBF & nI) | (eHF & nCr)) : eHF);
        end
        reg [17:0] sp = 18'd0, q1 = 18'd0, q2 = 18'd0;
        always @(posedge clk_pixel) begin
            if (dp == 2'd2) begin
                if (di >= 9'd2 && di <= 9'd321) begin        // los 320 puntos: x 160..1119
                    if (s3_hi) begin sp <= wRU; q1 <= wRC; q2 <= wRC; end
                    else begin
                        sp <= t0 ? wLC : wMC;
                        q1 <= t1 ? ((rph == 2'd0) ? wMU : wMD) : wMC;
                        q2 <= t2 ? wRC : wMC;
                    end
                end
                else begin sp <= 18'd0; q1 <= 18'd0; q2 <= 18'd0; end
            end
            else begin sp <= q1; q1 <= q2; q2 <= 18'd0; end
        end
        assign s3_px = sp;
    end
    else begin : g_nowin
        assign win_c       = 1'b0;
        assign ring_we_m   = wr_en;
        assign ring_addr_m = wr_addr;
        assign ring_data_m = wr_data;
        assign rd_addr_w   = 15'd0;
        assign s3_act      = 1'b0;
        assign s3_addr     = 15'd0;
        assign s3_px       = 18'd0;
        assign dbg_win_underrun = 5'd0;
        assign dbg_win_valid    = 1'b0;
        assign win_novalid      = 1'b0;
        assign M_AWID = 6'd0; assign M_AWADDR = 32'd0; assign M_AWLEN = 4'd0; assign M_AWSIZE = 3'd0;
        assign M_AWBURST = 2'd0; assign M_AWLOCK = 2'd0; assign M_AWCACHE = 4'd0; assign M_AWPROT = 3'd0;
        assign M_AWQOS = 4'd0; assign M_AWVALID = 1'b0;
        assign M_WID = 6'd0; assign M_WDATA = 32'd0; assign M_WSTRB = 4'd0; assign M_WLAST = 1'b0; assign M_WVALID = 1'b0;
        assign M_BREADY = 1'b1;
        assign M_ARID = 6'd0; assign M_ARADDR = 32'd0; assign M_ARLEN = 4'd0; assign M_ARSIZE = 3'd0;
        assign M_ARBURST = 2'd0; assign M_ARLOCK = 2'd0; assign M_ARCACHE = 4'd0; assign M_ARPROT = 3'd0;
        assign M_ARQOS = 4'd0; assign M_ARVALID = 1'b0;
        assign M_RREADY = 1'b1;
    end
    endgenerate

    // ========================================================================
    // Audio: divisor a 44100 Hz desde clk_pixel + cruce 2FF (como sms2hdmi)
    // ========================================================================

    // _127G (bug #14, bajones de volumen): el divisor ENTERO truncaba
    // 74.25M/44100/2 = 841.83 -> 841 y el sample rate real era 44144.5 Hz
    // frente a los 44100 que anuncia el ACR (N=6272/CTS=82500): +0.1% de
    // deriva continua. El buffer del receptor la aguanta ~30-40 s y luego
    // corrige a trompicones cada ~3 s — EXACTAMENTE lo observado en HW
    // (OPL4 wave bien 30-40 s y luego cortes ritmicos; FM/SCC "mal desde
    // el principio" porque su musica arranca con la deriva ya saturada).
    // Fix: acumulador FRACCIONAL — 88200 toggles/s exactos de media
    // (2 por muestra) => 44100.000 Hz. Jitter de +-1 ciclo de pixel:
    // irrelevante (el dato cruza por audio_sample_word y el modulo hdmi
    // empaqueta por muestra).
    // _127I (bug #14, LA CAUSA): clk_audio era un REGISTRO usado como reloj —
    // Gowin lo rutaba por fabric generico (PR1014 en el log del PnR:
    // "excessive delay or skew") y el skew intra-dominio en el contador del
    // ACR corrompia el CTS => el monitor re-engancha su PLL de audio a
    // trompicones (cortes ~3s tras 30-40s). Con el diseno v9958 (holgado)
    // el skew no mordia; con el V9968 (congestionado) si. FIX: se ELIMINA el
    // reloj de fabric — clock-enable de 1 ciclo a 44100.000 Hz exactos de
    // media (acumulador fraccional 44100/74250000), todo sincrono a
    // clk_pixel. De regalo el CTS medido queda exacto y el SDC ya no
    // necesita el create_clock clock_audio68 (retirado de msx_v9968.sdc).
    reg  [26:0] audio_acc = 27'd0;
    reg         audio_ce  = 1'b0;

    always_ff @(posedge clk_pixel) begin : audio_div_frac
        reg [27:0] acc_n;
        acc_n = {1'b0, audio_acc} + 28'd44100;
        if (acc_n >= 28'd74250000) begin
            audio_acc <= acc_n[26:0] - 27'd74250000;
            audio_ce  <= 1'b1;
        end else begin
            audio_acc <= acc_n[26:0];
            audio_ce  <= 1'b0;
        end
    end

    // _126 (bug #14, bajones de volumen): el "cruce 2FF" era un 2FF sobre un
    // BUS de 16 bits — protege la metaestabilidad de cada bit pero NO la
    // coherencia del conjunto: una captura a caballo de un cambio del
    // mezclador (27MHz async; p.ej. 0x0001->0xFFFF en un cruce por cero)
    // produce un valor RASGADO = pico fuerte. Picos frecuentes activan el
    // limitador/AGC del televisor -> "bajones y subidas de volumen" en
    // TODAS las fuentes (SCC/OPL4 FM/wave: es el camino comun), y la tasa
    // depende del jitter relativo de PLLs -> variable por build/placement.
    // FILTRO DE ESTABILIDAD: 3 capturas a clk_pixel; la muestra solo se
    // acepta cuando las dos ultimas (ya asentadas) coinciden. El mezclador
    // cambia cada ~280ns y aqui se muestrea cada 13.5ns: como mucho se
    // retrasa una muestra 27ns — inaudible; el rasgado desaparece.
    reg [15:0] aud_c0 [1:0], aud_c1 [1:0], aud_c2 [1:0];
    reg [15:0] audio_sample_word [1:0];
    always @(posedge clk_pixel) begin
        aud_c0[0] <= audio_l;      aud_c1[0] <= aud_c0[0];   aud_c2[0] <= aud_c1[0];
        aud_c0[1] <= audio_r;      aud_c1[1] <= aud_c0[1];   aud_c2[1] <= aud_c1[1];
        if (aud_c1[0] == aud_c2[0]) audio_sample_word[0] <= aud_c2[0];
        if (aud_c1[1] == aud_c2[1]) audio_sample_word[1] <= aud_c2[1];
    end

    // _133 VUMETRO (bug #14): pico de |audio_sample_word[0]| por ventana de
    // ~0.23s (2^24 ciclos de pixel) con registro de retencion — el COM11 lo
    // muestrea cuasi-estatico. Si durante un corte audible este pico se
    // DESPLOMA, las muestras que consume el HDMI van ya muertas (reo aguas
    // arriba); si sigue alto, el reo es el empaquetado o el receptor.
    reg [15:0] amp_acc = 16'd0;
    reg [23:0] amp_win = 24'd0;
    reg [15:0] dbg_amp_r = 16'd0;
    wire [15:0] asw_abs = audio_sample_word[0][15]
                        ? (~audio_sample_word[0] + 16'd1)
                        : audio_sample_word[0];
    always @(posedge clk_pixel) begin
        amp_win <= amp_win + 24'd1;
        if (amp_win == 24'd0) begin
            dbg_amp_r <= amp_acc;
            amp_acc   <= 16'd0;
        end
        else if (asw_abs > amp_acc) amp_acc <= asw_abs;
    end
    assign dbg_amp = dbg_amp_r;

    // ========================================================================
    // Diagnóstico (stretchers retriggerables; activo = 1)
    // ========================================================================

    localparam DBG_W_CLK = 20;  // 2^20 @ 27 MHz  ≈ 38.8 ms
    localparam DBG_W_PIX = 21;  // 2^21 @ 74.25 MHz ≈ 28.2 ms

    reg [DBG_W_CLK-1:0] str_vs = '0, str_wr = '0, str_nb = '0;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            str_vs <= '0; str_wr <= '0; str_nb <= '0;
        end else begin
            if (vs_lead)                  str_vs <= {DBG_W_CLK{1'b1}};
            else if (str_vs != 0)         str_vs <= str_vs - 1'b1;
            if (wr_en)                    str_wr <= {DBG_W_CLK{1'b1}};
            else if (str_wr != 0)         str_wr <= str_wr - 1'b1;
            if (wr_en && wr_data != 0)    str_nb <= {DBG_W_CLK{1'b1}};
            else if (str_nb != 0)         str_nb <= str_nb - 1'b1;
        end
    end
    assign dbg_vs_tick  = (str_vs != 0);
    assign dbg_wr_act   = (str_wr != 0);
    assign dbg_nonblack = (str_nb != 0);
    assign dbg_lock_tgl = frame_tgl;

    reg [DBG_W_PIX-1:0] str_rst = '0;
    always @(posedge clk_pixel) begin
        if (hdmi_rst)          str_rst <= {DBG_W_PIX{1'b1}};
        else if (str_rst != 0) str_rst <= str_rst - 1'b1;
    end
    assign dbg_hdmi_rst = (str_rst != 0);
    assign dbg_rd_act   = win_next;

`ifndef SIM_NO_HDMI

    // ========================================================================
    // HDMI real: dos hdmi (fork tn_vdp con salida tmds_internal), mux por
    // pal_x, serializer externo y ELVDS — patrón v9958_top.v líneas 449-523.
    // ========================================================================

    logic [9:0] tmds_ntsc [NUM_CHANNELS-1:0];
    wire apkt_pulse_ntsc, aovr_pulse_ntsc;      // _127I telemetria bug #14
    hdmi #( .VIDEO_ID_CODE(4),                  // 720p60, frame 1650×750
            .DVI_OUTPUT(0),
            .VIDEO_REFRESH_RATE(60.0),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME({"Unknown", 8'd0}),
            .PRODUCT_DESCRIPTION({"FPGA", 96'd0}),
            .SOURCE_DEVICE_INFORMATION(8'h00),
            .START_X(0),
            .START_Y(720),                      // reset → inicio del vblank
            .NUM_CHANNELS(NUM_CHANNELS),
            // _169: parte el cono del codificador 8b/10b, que es el peor SETUP
            // del diseño (ver el bloque grande en tmds_channel.sv). Se activa
            // SOLO en la linea del V9968: msx2hdmi.sv (la clasica del V9958, ya
            // publicada, 6 instancias) se queda con el valor por defecto 0 y su
            // netlist es identico bit a bit al de siempre.
            // Bit-exactitud demostrada en tb_tmds_equiv.sv: 320.010 ciclos,
            // cero discrepancias en tmds y en acc.
            .PIPELINE_QM(1'b1)
            )
    hdmi_ntsc ( .clk_pixel_x5(clk_5x_pixel),
          .clk_pixel(clk_pixel),
          .audio_ce(audio_ce),
          .rgb(rgb_out),       // _58: con dim de scanlines aplicado
          .reset( hdmi_rst ),
          .reset_cx( rst_cx[10:0] ),   // _136: anclaje compensado
          .audio_sample_word(audio_sample_word),
          .aspect_16_9(1'b0),  // v3.0: con VIC 4/19 el hack VIC+aspect del AVI InfoFrame anunciaria 1080i
          .cx(cx_ntsc),
          .cy(cy_ntsc),
          .tmds_internal(tmds_ntsc),
          .audio_pkt_pulse(apkt_pulse_ntsc),
          .audio_ovr_pulse(aovr_pulse_ntsc)
        );

    // _127I telemetria bug #14: contadores de paquetes de audio despachados
    // y de overruns del doble buffer del packet_picker (instancia NTSC — la
    // salida real; el nucleo es NTSC-only). Esperado: 11025.0 paquetes/s
    // CLAVADOS y ovr=0. Si la tasa baja o hay ovr durante un corte audible,
    // el lado transmisor es culpable; si sigue perfecta -> receptor/cable.
    reg [15:0] apkt_cnt = 16'd0;
    reg [7:0]  aovr_cnt = 8'd0;
    always @(posedge clk_pixel) begin
        if (apkt_pulse_ntsc) apkt_cnt <= apkt_cnt + 1'b1;
        if (aovr_pulse_ntsc) aovr_cnt <= aovr_cnt + 1'b1;
    end
    assign dbg_apkt = {aovr_cnt, 8'h00, apkt_cnt};

    logic [9:0] tmds_pal [NUM_CHANNELS-1:0];

    // ========================================================================
    // _168 BACK-END PAL BAJO generate. Ver la cabecera del modulo: hoy es
    // LOGICA MUERTA (pal_mode llega cableado a 0 desde top.v:1969).
    //
    // ⚠️ POR QUE UN generate Y NO SOLO LA CONSTANTE. El primer intento fue
    // hacer `pal_x` constante de elaboracion y confiar en que la propagacion de
    // constantes podara la instancia sola. NO FUNCIONA: medido en la campana
    // s003, el informe de sintesis seguia listando
    //     name="hdmi_pal" T_Register="606" T_Lut="808"
    // y el CLS no bajo ni un punto. Gowin NO elimina instancias de jerarquia
    // aunque ninguna de sus salidas se use. Hace falta que la instancia no
    // llegue a elaborarse, y eso solo lo da un generate sobre un parametro.
    // (Coste de averiguarlo en la linea ligera: 2 minutos. En la completa
    // habrian sido 50.)
    // ========================================================================
    generate
    if (ENABLE_PAL != 0) begin : g_hdmi_pal
        hdmi #( .VIDEO_ID_CODE(19),                 // 720p50, frame 1980×750
                .DVI_OUTPUT(0),
                .VIDEO_REFRESH_RATE(50.0),
                .IT_CONTENT(1),
                .AUDIO_RATE(AUDIO_RATE),
                .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
                .VENDOR_NAME({"Unknown", 8'd0}),
                .PRODUCT_DESCRIPTION({"FPGA", 96'd0}),
                .SOURCE_DEVICE_INFORMATION(8'h00),
                .START_X(0),
                .START_Y(720),
                .NUM_CHANNELS(NUM_CHANNELS),
                .PIPELINE_QM(1'b1)          // _169, igual que el NTSC
                )
        hdmi_pal ( .clk_pixel_x5(clk_5x_pixel),
              .clk_pixel(clk_pixel),
              .audio_ce(audio_ce),
              .rgb(rgb_out),       // _58: con dim de scanlines aplicado
              .reset( hdmi_rst ),
              .reset_cx( rst_cx[11:0] ),   // _136: anclaje compensado
              .audio_sample_word(audio_sample_word),
              .aspect_16_9(1'b0),  // v3.0: con VIC 4/19 el hack VIC+aspect del AVI InfoFrame anunciaria 1080i
              .cx(cx_pal),
              .cy(cy_pal),
              .tmds_internal(tmds_pal)
            );
    end
    else begin : g_sin_pal
        // Sin back-end PAL: se atan las salidas para no dejarlas sin conducir.
        // Con pal_x constante 0 no las lee nadie (el mux de mas abajo y los
        // cx/cy de la linea ~390 se pliegan al lado NTSC en elaboracion).
        assign cx_pal = 12'd0;
        assign cy_pal = 10'd0;
        for (genvar gp = 0; gp < NUM_CHANNELS; gp = gp + 1) begin : tie_pal
            assign tmds_pal[gp] = 10'd0;
        end
    end
    endgenerate

    logic [2:0] tmds;
    logic [9:0] tmds_internal [NUM_CHANNELS-1:0];

    // mux NTSC/PAL de los 10 bits pre-serializador (elemento a elemento:
    // el ternario sobre arrays unpacked no es portable)
    genvar ch;
    generate
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin : tmds_mux
            assign tmds_internal[ch] = pal_x ? tmds_pal[ch] : tmds_ntsc[ch];
        end
    endgenerate
    // V9990: salida pre-serializador para el mux externo (siempre disponible)
    assign tmds_out = {tmds_internal[2], tmds_internal[1], tmds_internal[0]};
    reg vblank_r = 1'b1;
    always @(posedge clk_pixel) vblank_r <= (cy >= 10'd720);
    assign vblank = vblank_r;

    // El serializer del árbol (tn_vdp_v3_v9958/src/hdmi/serializer.sv) lleva
    // los OSER10 con RESET=1'b0 constante: el reset por-frame (hdmi_rst) solo
    // realinea cx/cy de los hdmi, nunca el gearbox de serialización.
`ifdef ZYNQ
    // ZYNQ (Xilinx): el reloj TMDS sale del propio serializer (OSERDESE2 con
    // 0000011111, alineado con los datos), NO el clk_pixel crudo: un BUFG
    // directo al pad no garantiza la fase. Validado en zynq/bringup/hdmi720.
    // ELVDS_OBUF es aqui el envoltorio de OBUFDS de zynq/gowin_prims.v.
    generate
    if (NO_SERIALIZER == 0) begin : g_ser
        wire tmds_clock_ser;
        serializer #(.NUM_CHANNELS(NUM_CHANNELS), .VIDEO_RATE(0)) serializer(
            .clk_pixel(clk_pixel), .clk_pixel_x5(clk_5x_pixel), .reset(1'b0),
            .tmds_internal(tmds_internal), .tmds(tmds), .tmds_clock(tmds_clock_ser) );
        ELVDS_OBUF tmds_bufds [3:0] (
            .I({tmds_clock_ser, tmds}),
            .O({tmds_clk_p, tmds_d_p}),
            .OB({tmds_clk_n, tmds_d_n})
        );
    end
    else begin : g_noser
        // NO_SERIALIZER: el serializer y los pads viven fuera (sin uso desde el V9991)
        assign tmds       = 3'b000;
        assign tmds_clk_p = 1'b0;
        assign tmds_clk_n = 1'b1;
        assign tmds_d_p   = 3'b000;
        assign tmds_d_n   = 3'b111;
    end
    endgenerate
`else
    serializer #(.NUM_CHANNELS(NUM_CHANNELS), .VIDEO_RATE(0)) serializer(
        .clk_pixel(clk_pixel), .clk_pixel_x5(clk_5x_pixel), .reset(1'b0),
        .tmds_internal(tmds_internal), .tmds(tmds) );

    // Gowin LVDS output buffer — reloj TMDS = clk_pixel crudo (como nestang).
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );
`endif

`else

    // ========================================================================
    // SIM_NO_HDMI: contadores cx/cy conductuales con la misma semántica de
    // reset que hdmi.sv (síncrono, → (START_X, START_Y) = (0,720)).
    // NTSC: frame 1650×750 (VIC 4). PAL: frame 1980×750 (VIC 19).
    // ========================================================================

    initial begin
        cx_ntsc = 11'd0;  cy_ntsc = 10'd720;
        cx_pal  = 12'd0;  cy_pal  = 10'd720;
    end

    always @(posedge clk_pixel) begin
        if (hdmi_rst) begin
            cx_ntsc <= 11'd0;
            cy_ntsc <= 10'd720;
        end else begin
            cx_ntsc <= (cx_ntsc == 11'd1649) ? 11'd0 : cx_ntsc + 1'b1;
            if (cx_ntsc == 11'd1649)
                cy_ntsc <= (cy_ntsc == 10'd749) ? 10'd0 : cy_ntsc + 1'b1;
        end
    end

    always @(posedge clk_pixel) begin
        if (hdmi_rst) begin
            cx_pal <= 12'd0;
            cy_pal <= 10'd720;
        end else begin
            cx_pal <= (cx_pal == 12'd1979) ? 12'd0 : cx_pal + 1'b1;
            if (cx_pal == 12'd1979)
                cy_pal <= (cy_pal == 10'd749) ? 10'd0 : cy_pal + 1'b1;
        end
    end

    assign tmds_clk_p = 1'b0;
    assign tmds_clk_n = 1'b1;
    assign tmds_d_p   = 3'b000;
    assign tmds_d_n   = 3'b111;
    assign tmds_out   = 30'd0;
    assign vblank     = (cy >= 10'd720);

`endif

endmodule
