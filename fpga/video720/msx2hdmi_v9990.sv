// ============================================================================
// msx2hdmi_v9990.sv — Puente de video del V9990 (tiny9990, clk_86 con
// DCLK_EN por pixel) a 720p, variante del msx2hdmi_v9968 (misma arquitectura
// nand2mario: ring BRAM dual-clock de 32 lineas, lectura escalada en el dominio
// 74,25 MHz y codificador HDMI VIC 4) PERO con FRAME BUFFER EN LA DDR (v9990_fb):
//
//  * La captura (HS/VS/DE, contadores de linea y pixel) ya no escribe el ring:
//    entrega el flujo de pixeles a v9990_fb, que guarda cada frame ENTERO en la
//    DDR (3 slots) por AXI (GP1 a traves de axi_arb2, junto con la VRAM).
//  * La salida 720p corre LIBRE (750 lineas SIEMPRE, 60,00 Hz): en cy == 720
//    (30 lineas antes de la imagen) el mostrador elige el ultimo frame completo
//    publicado por el escritor y se lo pide al lector de v9990_fb, que lo trae
//    al ring linea a linea, 16 por delante del mostrador. Sin genlock ni jitter:
//    cualquier monitor lo acepta; el frame del V9990 (59,9 Hz y los stalls de la
//    cache) solo produce, muy de tarde en tarde, un frame repetido.
//    (20/09 noche: el genlock de linea entera daba 751-760 lineas variables con
//    el msx-samurai y los monitores lo rechazaban "fuera de rango".)
//
// Deltas respecto al del V9968 que se mantienen:
//  * Entrada: RGB555 nativo del T9990 (5 -> 6 bits replicando el MSB), HS/VS
//    ACTIVOS ALTOS, DE = periodo visible con bordes (salida nueva del core).
//    Un pixel por DCLK_EN (5,4 / 7,2 / 10,7 / 14,3 MHz segun el modo).
//  * Lineas a 15 kHz SIN doblar (262 por frame): se guardan las 240 con DE.
//  * Escalado horizontal POR MODO (RESO del frame mostrado), entero para que el
//    pixel salga uniforme y el contenido de 256/512 px mida lo MISMO que en el
//    V9968 (1024 columnas): B1 284 px x4 = 1136 · B2 384 x3 = 1152 · B3 568 x2 =
//    1136 · B4 768 x1,5 = 1152; ventana centrada en los 1280, negro fuera.
//    Vertical 240 -> 720 x3 como el V9968. B7 (28/10/2026): 1136 px x1 = 1136 (como B1 y B3).
//  * B5 (29/10/2026, V9991 paso 5: 640 x 400 a 25,3 kHz, HSCN): 640 px x2 = los 1280 ENTEROS (xstart 0:
//    el raster se mira 3 px adelantado, cxp, para que la primera columna salga en cx 0) y 400 lineas
//    x1,5 = 600, centradas (cy 60..659; negro y transparente fuera). Asi el V9968 a x0,5 son
//    exactamente 256 x 212 puntos de B5 (el "256x212 dentro de 640x400" de Nishi) y el patron de
//    lineas es el 2,1 del entrelazado. x1,8 (los 720) habria dado lineas 2,2,2,2,1 y una ventana inexacta.
//  * ENTRELAZADO (28/10/2026, IL + EO en R#7): los dos campos se TEJEN en el frame buffer
//    (480 lineas, 2 x linea + campo, el cuadro se publica al acabar el campo impar) y el
//    mostrador escala 480 -> 720 (x1,5: patron 2,1,2,1; el aspecto es el de 240 x3).
//  * SIN serializer: entrega los 30 bits TMDS codificados (`tmds_out`) y
//    `vblank` (hasta el 28/10/2026 iban al mux hdmi_tmds_switch.sv). Audio: el
//    mismo mezclador que la otra instancia.
//  * V9991 (28/10/2026, parametro EXT_TIMING): sin codificador propio. El raster
//    cx/cy llega del hdmi de msx2hdmi_v9968 (enganchado al frame del V9968 y
//    reseteado una vez por frame a (rst_cx, 720)); este puente sigue leyendo su
//    frame buffer con el, y entrega el pixel (rgb_out_ext) y su transparencia
//    (ys_out: bit YS del T9990, que viaja por la DDR y el anillo en el bit 15 /
//    bit 12) al compositor v9991_compose. La peticion de frame va armada una vez
//    por frame de salida (cy == 0) y se dispara en cy == 722.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module msx2hdmi_v9990 #(
    // V9991 (28/10/2026): 1 = sin codificador propio; el raster cx/cy entra por ext_cx/ext_cy (el del
    // hdmi de msx2hdmi_v9968) y el pixel sale por rgb_out_ext/ys_out hacia el compositor (v9991_compose).
    // 0 = como siempre (codificador HDMI propio, salida libre, tmds_out): los bancos de este puente.
    parameter EXT_TIMING = 0,
    // Perfil Dual (31/10/2026): 1 = el escritor del frame buffer se salta el rectangulo skip_* (v9990_fb SKIP) y publica en wslot_o el
    // slot que esta escribiendo, para que bwin_fb pinte ahi la imagen de la maquina B. Con 0 (lo de siempre) los puertos skip_* no se usan.
    parameter SKIP_RECT = 0
) (
    input  wire        clk,          // 85.909 MHz, dominio del T9990
    input  wire        resetn,
    input  wire        aresetn,      // reset AXI (FCLK_RESET0_N sincronizado a clk)
    input  wire        ce,           // DCLK_EN del T9990 (1 pulso por pixel)
    input  wire [4:0]  r,
    input  wire [4:0]  g,
    input  wire [4:0]  b,
    input  wire        ys,           // 1 = pixel transparente (Ys del T9990: YSE y bit YS de paleta), con r/g/b
    input  wire        hs,           // ACTIVO ALTO
    input  wire        vs,           // ACTIVO ALTO
    input  wire        de,           // 1 = pixel visible (bordes incluidos)
    input  wire [2:0]  reso,         // T9990_RESO: 0 B1, 1 B2, 2 B3, 3 B4, 4 B5 (29/10/2026), 6 B7 (5 = B6, sin soporte)
    input  wire        il,           // entrelazado con lineas dobles (IL y EO en R#7), clk
    input  wire        eo,           // campo en curso (STATUS.EO), clk
    input  wire        scanlines,    // 1 = atenuar al 50% la tercera linea
    input  wire [15:0] audio_l,
    input  wire [15:0] audio_r,
    input  wire        clk_pixel,    // 74.25 MHz
    input  wire        clk_5x_pixel, // 371.25 MHz (solo lo usa el hdmi para nada aqui; se mantiene la interfaz)
    input  wire        skip_en,      // Dual: rectangulo (filas de captura y palabras de 2 px) que el escritor no toca; sin uso con SKIP_RECT = 0
    input  wire [9:0]  skip_y0,
    input  wire [9:0]  skip_y1,
    input  wire [9:0]  skip_wx0,
    input  wire [9:0]  skip_wx1,
    input  wire        skip_odd,     // Dual: el rectangulo empieza en un punto impar (posicion fina)
    output wire [1:0]  wslot_o,      // Dual: slot del frame buffer que esta escribiendo el V9990
    input  wire [10:0] ext_cx,       // V9991 (EXT_TIMING = 1): raster comun, del hdmi de msx2hdmi_v9968
    input  wire [9:0]  ext_cy,
    output wire [23:0] rgb_out_ext,  // V9991: el pixel del V9990 en (cx,cy) (negro fuera de su ventana), con scanlines
    output wire        ys_out,       // V9991: 1 = transparente (bit YS del pixel; fuera de la ventana del V9990 tambien)
    output wire        in_out,       // V9991: 1 = el pixel esta dentro de la imagen del V9990 (alineado con ys_out)
    output wire [2:0]  reso_out,     // V9991: modo (T9990_RESO) del frame que se muestra, para la geometria de la ventana
    output wire        il_out,       // V9991: ese frame es entrelazado (480 lineas, x1,5)
    output wire [29:0] tmds_out,     // {ch2, ch1, ch0} codificados, dominio clk_pixel (0 con EXT_TIMING)
    output wire        vblank,       // clk_pixel: cy >= 720
    output wire        dbg_lock_tgl, // clk: toggle de frame publicado por el frame buffer
    output wire        dbg_hdmi_rst, // (sin uso: la salida corre libre) = 0
    output wire        dbg_wr_act,   // clk: stretch de escritura al ring (lector del frame buffer)
    output reg  [8:0]  dbg_lines,    // clk: lineas capturadas en el ULTIMO frame (esperado 240; 400 en B5)
    output reg  [21:0] dbg_pixels,   // clk: pixeles capturados en el ultimo frame (B1: 240 x 284 = 68160)
    output wire [4:0]  dbg_yank_drop,// clk: UNDERRUN del lector (lineas que el mostrador alcanzo) en el ultimo frame
    output wire [31:0] dbg_rd,       // clk: estado del lector/escritor del frame buffer (v9990_fb.dbg_state; diagnostico 29/10)
    // ---- AXI3 master 32 bits del frame buffer (va al arbitro axi_arb2, maestro B) ----
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
    output wire        M_RREADY
);
    localparam RING_W          = 1136;    // B7: 1024 + 2 x 56 de borde (28/10/2026)
    localparam RING_LINES      = 16;      // 16 x 1136 x 18 = 9 BRAM36 (32 x 768 eran 12)
    localparam NATIVE_LINES    = 240;
    localparam AUDIO_RATE      = 44100;
    localparam AUDIO_BIT_WIDTH = 16;
    localparam NUM_CHANNELS    = 3;

    // ========================================================================
    // Dominio clk: captura auto-cronometrada -> flujo de pixeles al frame buffer
    // ========================================================================
    logic [17:0] mem [0:RING_LINES*RING_W-1];

    reg        hs_q, hs_qq, vs_q, vs_qq, de_q, ys_q, il_q, eo_q, il_f, eo_f;
    reg [5:0]  r_q, g_q, b_q;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            hs_q <= 1'b0; hs_qq <= 1'b0;
            vs_q <= 1'b0; vs_qq <= 1'b0;
            de_q <= 1'b0; ys_q <= 1'b0; il_q <= 1'b0; eo_q <= 1'b0; il_f <= 1'b0; eo_f <= 1'b0;
            r_q <= 6'd0; g_q <= 6'd0; b_q <= 6'd0;
        end else if (ce) begin
            hs_q  <= hs;  hs_qq <= hs_q;
            vs_q  <= vs;  vs_qq <= vs_q;
            de_q  <= de;  ys_q  <= ys;
            il_q  <= il;  eo_q  <= eo;
            if (vs_q & ~vs_qq) begin il_f <= il_q; eo_f <= eo_q; end   // el campo que empieza (EO ya ha cambiado con el VS)
            r_q <= {r, r[4]}; g_q <= {g, g[4]}; b_q <= {b, b[4]};
        end
    end
    wire hs_lead = hs_q & ~hs_qq;   // inicio de linea (15 kHz)
    wire vs_lead = vs_q & ~vs_qq;   // inicio de frame

    reg  [9:0] out_line;
    reg  [10:0] x_cnt;
    reg  [9:0] y0;
    reg        y0_valid;
    reg        frame_started;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            out_line      <= 10'd0;
            x_cnt         <= 11'h7FF;
            y0            <= 10'd0;
            y0_valid      <= 1'b0;
            frame_started <= 1'b0;
        end else if (ce) begin
            if (hs_lead)
                x_cnt <= 11'd0;
            else if (de_q && x_cnt != 11'h7FF)
                x_cnt <= x_cnt + 11'd1;
            if (vs_lead) begin
                out_line      <= 10'd0;
                y0_valid      <= 1'b0;
                frame_started <= 1'b1;
            end else if (hs_lead)
                out_line <= out_line + 10'd1;
            if (!vs_lead && frame_started && de_q && !y0_valid) begin
                y0       <= out_line;
                y0_valid <= 1'b1;
            end
        end
    end
    wire [9:0] y0_eff = y0_valid ? y0 : out_line;
    wire [9:0] rel    = out_line - y0_eff;      // linea nativa relativa
    wire [8:0] cap_lines = (reso == 3'd4) ? 9'd400 : NATIVE_LINES[8:0];   // B5: 400 lineas (29/10/2026)
    wire cap_ok = frame_started && de_q &&
                  (rel < {1'b0, cap_lines}) &&
                  (x_cnt < RING_W);
    // Entrelazado (28/10/2026): el campo se guarda en las lineas de su paridad (2 x linea + campo) del mismo
    // slot y el frame solo se cierra al acabar el campo IMPAR: el escritor se arma en un fin de campo impar,
    // captura el par entero y el impar y publica un cuadro de 480 lineas. il_f / eo_f son el modo y la
    // paridad del campo en curso (tomados en el VS). El fin de frame se decide con il_q / eo_q, que en el VS
    // ya son los del campo que EMPIEZA (EO cambia con el VS): se cierra si no empieza un campo impar. Asi no
    // depende de nada latcheado (con il_f/eo_f el primer VS tras el reset armaba el escritor en un campo par
    // y el primer cuadro salia con 240 lineas, tb_msx2hdmi_v9990 -DIL=1).
    wire [8:0] cap_line_w   = il_f ? {rel[7:0], eo_f} : rel[8:0];
    wire       frame_end_fb = vs_lead && !(il_q && eo_q);

    // telemetria de captura: lineas y pixeles por frame (latch en cada VS; tel.tcl)
    reg [8:0]  ln_frame = 9'd0;
    reg [21:0] px_frame = 22'd0;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ln_frame <= 9'd0; px_frame <= 22'd0; dbg_lines <= 9'd0; dbg_pixels <= 22'd0;
        end else if (ce) begin
            if (vs_lead) begin
                dbg_lines <= ln_frame; dbg_pixels <= px_frame;
                ln_frame <= 9'd0; px_frame <= 22'd0;
            end else begin
                if (cap_ok) px_frame <= px_frame + 22'd1;
                if (cap_ok && x_cnt == 11'd0) ln_frame <= ln_frame + 9'd1;
            end
        end
    end

    // ========================================================================
    // Frame buffer en la DDR: escritor (flujo de captura) y lector (al ring)
    // ========================================================================
    wire        ring_we;
    wire [14:0] ring_addr;
    wire [17:0] ring_data;
    reg         rd_req_tgl = 1'b0;      // clk_pixel
    reg  [1:0]  rd_slot_r  = 2'd0;
    reg  [3:0]  rd_reso_r  = 4'd0;
    reg  [8:0]  yy_gray    = 9'd0;
    wire [1:0]  pubx_slot;
    wire [3:0]  pubx_reso;
    wire        pubx_valid;
    wire [4:0]  fb_underrun;
    wire [8:0]  fb_wr_lines;
    // 3 slots de 480 x 2304 B (0x110000) en 0x1040_0000 (hasta 0x1073_0000); anillo de 16 lineas, 12 de adelanto
    v9990_fb #(.SLOT_SIZE(32'h0011_0000), .STRIDE(32'd2304), .PREFETCH(12), .RING_W(RING_W), .RING_LINES(RING_LINES), .SKIP(SKIP_RECT)) u_fb (
        .clk(clk), .resetn(resetn), .aresetn(aresetn),
        .ce(ce), .wr_enable(1'b1), .cap_en(cap_ok), .cap_sol(cap_ok && (x_cnt == 11'd0)), .cap_line(cap_line_w),
        .cap_rgb({ys_q, r_q[5:1], g_q[5:1], b_q[5:1]}), .frame_end(frame_end_fb), .reso({il_f, reso}),
        .ring_we(ring_we), .ring_addr(ring_addr), .ring_data(ring_data),
        .clk_pixel(clk_pixel), .rd_req_tgl(rd_req_tgl), .rd_slot(rd_slot_r), .rd_reso(rd_reso_r),
        .rd_yy_gray(yy_gray), .pubx_slot(pubx_slot), .pubx_reso(pubx_reso), .pubx_valid(pubx_valid),
        .skip_en(skip_en), .skip_y0(skip_y0), .skip_y1(skip_y1), .skip_wx0(skip_wx0), .skip_wx1(skip_wx1), .skip_odd(skip_odd), .wslot_o(wslot_o),
        .dbg_underrun(fb_underrun), .dbg_wr_lines(fb_wr_lines), .dbg_state(dbg_rd),
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
    always @(posedge clk) begin
        if (ring_we)
            mem[ring_addr] <= ring_data;
    end
    assign dbg_yank_drop = fb_underrun;
    assign dbg_lock_tgl  = u_fb.pub_tgl;
    assign dbg_hdmi_rst  = 1'b0;
    localparam DBG_W_CLK = 20;
    reg [DBG_W_CLK-1:0] str_wr = '0;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) str_wr <= '0;
        else if (ring_we) str_wr <= {DBG_W_CLK{1'b1}};
        else if (str_wr != 0) str_wr <= str_wr - 1'b1;
    end
    assign dbg_wr_act = (str_wr != 0);

    // ========================================================================
    // Dominio clk_pixel: salida LIBRE a 720p60. En cy == 720 se elige el frame.
    // ========================================================================
    logic [10:0] cx;
    logic [9:0]  cy;
    reg  [3:0]  cur_reso  = 4'd0;      // {il, modo} del frame que se muestra
    reg         cur_valid = 1'b0;      // hay un frame completo que mostrar
    // V9991 (28/10/2026): la peticion del frame va ARMADA una vez por frame de salida (se arma en cy == 0)
    // y se dispara en cy == 722, 28 lineas antes de la imagen. Con EXT_TIMING el raster lo resetea el
    // puente del V9968 a (rst_cx, 720) una vez por frame del VDP (alrededor de cy 721): asi no hay dos
    // peticiones por frame ni una perdida, caiga donde caiga el reset. Con el raster libre es lo de
    // siempre (cy == 720) dos lineas mas tarde; el prefetch de 16 lineas sobra igual.
    reg         req_armed = 1'b1;
    always @(posedge clk_pixel) begin
        if (cy == 10'd0 && cx == 11'd0) req_armed <= 1'b1;
        if (req_armed && cy == 10'd722 && cx == 11'd0) begin
            // datos primero, toggle dos ciclos despues (protocolo dato + toggle)
            rd_slot_r <= pubx_slot; rd_reso_r <= pubx_reso;
            cur_reso  <= pubx_reso; cur_valid <= pubx_valid;
        end
        if (req_armed && cy == 10'd722 && cx == 11'd2) begin
            if (cur_valid) rd_req_tgl <= ~rd_req_tgl;
            req_armed <= 1'b0;
        end
    end

    // sincronizadores de las entradas cuasi-estaticas
    reg [1:0] scan_sync = 2'b00;
    always @(posedge clk_pixel) scan_sync <= {scan_sync[0], scanlines};
    wire scan_x = scan_sync[1];
    wire [2:0] reso_x = cur_reso[2:0];
    wire       cur_il = cur_reso[3];
    assign reso_out = cur_reso[2:0];
    assign il_out   = cur_il;

    // ========================================================================
    // Escalado por modo: ventana centrada, factor entero (o 3/2 en B4)
    // ========================================================================
    reg [1:0]  xinc, xthr;      // avance de pixel nativo: xcnt += xinc, umbral xthr
    reg [10:0] xstart, xstop;
    reg [9:0]  ystart, ystop;   // lineas de salida con imagen (B5: 60..659; el resto 0..719)
    reg [10:0] yadd;            // paso del acumulador vertical: 240 = x3 (yy = cy/3), 480 = x1,5 (entrelazado, B5)
    // always_comb y no always @(*): en Icarus un @(*) cuyo unico operando nunca cambia (B1:
    // cur_reso se queda en 0 desde el reset) no se evalua nunca y xstart/xstop quedan en X
    // (la ventana entera salia X en tb_msx2hdmi_v9990 con RESO=0; en el silicio es lo mismo).
    always_comb begin
        case (reso_x)
            3'd1:    begin xinc = 2'd1; xthr = 2'd3; xstart = 11'd64; xstop = 11'd1216; end   // B2 384 x3
            3'd2:    begin xinc = 2'd1; xthr = 2'd2; xstart = 11'd72; xstop = 11'd1208; end   // B3 568 x2
            3'd3:    begin xinc = 2'd2; xthr = 2'd3; xstart = 11'd64; xstop = 11'd1216; end   // B4 768 x1.5
            3'd4:    begin xinc = 2'd1; xthr = 2'd2; xstart = 11'd0;  xstop = 11'd1280; end   // B5 640 x2, los 1280 enteros (29/10/2026)
            3'd6:    begin xinc = 2'd1; xthr = 2'd1; xstart = 11'd72; xstop = 11'd1208; end   // B7 1136 x1 (28/10/2026)
            default: begin xinc = 2'd1; xthr = 2'd0; xstart = 11'd72; xstop = 11'd1208; end   // B1 284 x4 (xthr 0 = 4, ver abajo)
        endcase
        ystart = (reso_x == 3'd4) ? 10'd60  : 10'd0;
        ystop  = (reso_x == 3'd4) ? 10'd660 : 10'd720;
        yadd   = (cur_il || reso_x == 3'd4) ? 11'd480 : 11'd240;
    end
    reg [10:0] xx   = 11'd0;
    reg [2:0]  xcnt = 3'd0;
    reg [8:0]  yy   = 9'd0;
    reg [10:0] ycnt = 11'd0;
    // B5 (29/10/2026): la ventana del V9990 puede empezar en cx 0 (640 x2 = 1280) y el camino del pixel lleva 3 ciclos
    // (reset de xx, direccion del anillo, dato, rgb): el raster se mira 3 px ADELANTADO (cxp = cx + 3 modulo 1650: en los
    // 3 ultimos px de una linea ya es el principio de la siguiente, cy_eff) y la linea del anillo (yy) se avanza en cx 1646
    // para la linea que viene (cyn). Con xstart >= 3 es exactamente lo de antes (xrst en xstart - 3, etc.).
    wire [10:0] cxp    = (cx >= 11'd1647) ? (cx - 11'd1647) : (cx + 11'd3);
    wire [9:0]  cyn    = (cy == 10'd749) ? 10'd0 : (cy + 10'd1);
    wire [9:0]  cy_eff = (cx >= 11'd1647) ? cyn : cy;
    wire        xrst_now = (cxp == xstart);
    wire        xacc_en  = (cxp >= xstart + 11'd1) && (cxp < xstop + 11'd1);
    wire [2:0]  xthr_v   = (xthr == 2'd0) ? 3'd4 : {1'b0, xthr};
    always @(posedge clk_pixel) begin : scaler
        reg [3:0]  xcnt_next;
        reg [10:0] ycnt_next;
        xcnt_next = {1'b0, xcnt} + {2'b00, xinc};
        ycnt_next = ycnt + yadd;                             // 240: x3 (yy = cy/3); 480: x1,5 (entrelazado y B5)
        if (xacc_en) begin
            if (xcnt_next >= {1'b0, xthr_v}) begin
                xcnt <= xcnt_next[2:0] - xthr_v;
                xx   <= xx + 1'b1;
            end else
                xcnt <= xcnt_next[2:0];
        end
        // la linea que viene: yy y el acumulador a 0 hasta la primera linea con imagen INCLUIDA (ystart, como el cy 0 de
        // antes: el primer paso se da PARA la segunda, y asi salen 2,1,2,1: lineas 0,0,1,2,2,...) y desde ystop; si no, un paso.
        // Con "cyn < ystart" el paso se daba ya para la linea 60 y B5 salia 1,2,1,2 (una linea antes; tb_msx2hdmi_v9990 RESO=4).
        if (cx == 11'd1646) begin
            if (cyn <= ystart || cyn >= ystop) begin
                yy   <= 9'd0;
                ycnt <= 11'd0;
            end else if (ycnt_next >= 11'd720) begin
                ycnt <= ycnt_next - 11'd720;
                yy   <= yy + 1'b1;
            end else
                ycnt <= ycnt_next;
        end
        if (xrst_now) begin
            xx   <= 11'd0;
            xcnt <= 3'd0;
        end
        // yy a 0 durante TODO el vblank (cy 720..749): el raster externo (V9991) se resetea a (rst_cx, 720) en
        // cualquier cx, y el lector del frame buffer se mide contra yy (un yy que contase ahi, como antes del
        // 28/10, le daba underruns falsos en B3/B4 y le comia margen de prefetch).
        if (cy >= 10'd720) begin
            yy   <= 9'd0;
            ycnt <= 11'd0;
        end
        yy_gray <= yy[8:0] ^ (yy[8:0] >> 1);
    end
    reg [14:0] yyw_r = 15'd0;
    always @(posedge clk_pixel) yyw_r <= yy[$clog2(RING_LINES)-1:0] * RING_W[14:0];
    wire [14:0] rd_addr = yyw_r + {4'd0, xx};
    reg  [17:0] rd_data = 18'd0;
    reg  [23:0] rgb     = 24'd0;
    reg         ys_r    = 1'b1;         // V9991: transparencia del pixel de rgb (1 fuera de la ventana)
    reg         in_r    = 1'b0;         // dentro de la ventana (la tecla V: fuera, el escritorio no tiene hueco)
    wire win_next = (cxp >= xstart + 11'd2) && (cxp < xstop + 11'd2) && (cy_eff >= ystart) && (cy_eff < ystop) && cur_valid;
    always @(posedge clk_pixel) begin
        rd_data <= mem[rd_addr];
        // palabra del anillo {r5, ys, g5, g5[4], b5, b5[4]} (v9990_fb.px18): el LSB de R se reconstruye
        rgb     <= win_next ? {rd_data[17:13], rd_data[17], 2'b00,
                               rd_data[11:6],  2'b00,
                               rd_data[5:0],   2'b00}
                            : 24'h000000;
        ys_r    <= win_next ? rd_data[12] : 1'b1;
        in_r    <= win_next;
    end
    assign ys_out = ys_r;
    assign in_out = in_r;
    // scanlines: 1 de cada 3 lineas de salida al 50%
    reg [1:0] ph3   = 2'd0;
    reg       dim_r = 1'b0;
    wire [1:0] ph3_nx = (cy >= 10'd749) ? 2'd0 : ((ph3 == 2'd2) ? 2'd0 : ph3 + 2'd1);
    always @(posedge clk_pixel) begin
        if (cx == 11'd1649) begin
            ph3   <= ph3_nx;
            dim_r <= scan_x && (ph3_nx == 2'd2);
        end
    end
    wire [23:0] rgb_out = dim_r ? {1'b0, rgb[23:17], 1'b0, rgb[15:9], 1'b0, rgb[7:1]} : rgb;
    assign rgb_out_ext = rgb_out;

    // ========================================================================
    // Audio: 44100 Hz exactos por acumulador fraccional + filtro de estabilidad
    // (identico al del V9968, ver alli la historia del bug #14)
    // ========================================================================
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
    reg [15:0] aud_c0 [1:0], aud_c1 [1:0], aud_c2 [1:0];
    reg [15:0] audio_sample_word [1:0];
    always @(posedge clk_pixel) begin
        aud_c0[0] <= audio_l;      aud_c1[0] <= aud_c0[0];   aud_c2[0] <= aud_c1[0];
        aud_c0[1] <= audio_r;      aud_c1[1] <= aud_c0[1];   aud_c2[1] <= aud_c1[1];
        if (aud_c1[0] == aud_c2[0]) audio_sample_word[0] <= aud_c2[0];
        if (aud_c1[1] == aud_c2[1]) audio_sample_word[1] <= aud_c2[1];
    end

    // ========================================================================
    // Codificador HDMI (VIC 4 = 720p60), libre, sin serializer — o, con EXT_TIMING
    // (V9991), ningun codificador: el raster viene del puente del V9968
    // ========================================================================
    generate
    if (EXT_TIMING != 0) begin : g_ext
        assign cx = ext_cx;
        assign cy = ext_cy;
        assign tmds_out = 30'd0;
    end
    else begin : g_int
`ifndef SIM_NO_HDMI
    logic [9:0] tmds_ntsc [NUM_CHANNELS-1:0];
    hdmi #( .VIDEO_ID_CODE(4),
            .DVI_OUTPUT(0),
            .VIDEO_REFRESH_RATE(60.0),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_RATE),
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .VENDOR_NAME({"Unknown", 8'd0}),
            .PRODUCT_DESCRIPTION({"FPGA", 96'd0}),
            .SOURCE_DEVICE_INFORMATION(8'h00),
            .START_X(0),
            .START_Y(0),
            .NUM_CHANNELS(NUM_CHANNELS),
            .PIPELINE_QM(1'b1)
            )
    hdmi_ntsc ( .clk_pixel_x5(clk_5x_pixel),
          .clk_pixel(clk_pixel),
          .audio_ce(audio_ce),
          .rgb(rgb_out),
          .reset( 1'b0 ),
          .reset_cx( 11'd0 ),
          .audio_sample_word(audio_sample_word),
          .aspect_16_9(1'b0),
          .cx(cx),
          .cy(cy),
          .tmds_internal(tmds_ntsc),
          .audio_pkt_pulse(),
          .audio_ovr_pulse()
        );
    assign tmds_out = {tmds_ntsc[2], tmds_ntsc[1], tmds_ntsc[0]};
`else
    initial begin cx = 11'd0; cy = 10'd0; end
    always @(posedge clk_pixel) begin
        cx <= (cx == 11'd1649) ? 11'd0 : cx + 1'b1;
        if (cx == 11'd1649)
            cy <= (cy == 10'd749) ? 10'd0 : cy + 1'b1;
    end
    assign tmds_out = 30'd0;
`endif
    end
    endgenerate
    reg vblank_r = 1'b1;
    always @(posedge clk_pixel) vblank_r <= (cy >= 10'd720);
    assign vblank = vblank_r;
endmodule
