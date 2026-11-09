// ============================================================================
// v9990_fb.v — Frame buffer del V9990 en la DDR (20/09/2026, noche).
//
// Por que: el genlock del 720p al frame del V9990 (frame HDMI de 751..760
// lineas, variable con los fallos de la cache de VRAM) lo tragaba la
// capturadora pero NINGUN monitor real ("fuera de rango"). Con esto la salida
// HDMI corre LIBRE a 720p60 exacto (750 lineas siempre) y muestra el ultimo
// frame COMPLETO del V9990 guardado en la DDR: sin genlock, sin jitter, y un
// frame repetido de vez en cuando (59,9 Hz contra 60,0) que nadie ve.
//
// Tres buffers (slots) de 240 lineas x 1536 B (768 px x 2 B, RGB555 en 16 bits,
// 2 px por palabra de 32) en FB_BASE: el escritor llena el slot W, el lector
// muestra el slot R = ultimo completo publicado, y siempre queda un tercero.
//
// ESCRITOR (dominio clk, pixeles cualificados por ce): empaqueta 2 px por
// palabra en una FIFO (BRAM 1024 x 34: {tag, dato}; tag 1 = inicio de linea con
// su numero, 2 = fin de frame con su modo) y RELLENA cada linea a multiplo de
// 16 palabras al acabarla (en el blanking, sobra tiempo). El motor AXI solo
// emite una rafaga (AW + 16 W) cuando las 16 palabras YA estan en la FIFO
// (contador de rafagas listas): nunca deja el canal W abierto esperando pixeles
// (bloquearia al arbitro y con el a las escrituras del cliente de VRAM). Al fin
// de frame espera las B, publica {slot, modo} por toggle y elige el slot
// siguiente (ni el publicado ni el que muestra el lector).
//
// LECTOR (dominio clk, AXI): cuando el mostrador pide un frame (rd_req_tgl, en
// cy == 720 del 720p = 30 lineas antes de la imagen) trae al anillo de 32 lineas
// del puente las lineas del slot pedido, manteniendose PREFETCH lineas por
// delante de la que muestra (rd_yy_gray) y nunca 32 o mas (sobreescribiria la
// que se esta mostrando). Cada beat = 2 px -> 2 escrituras al anillo (RREADY
// alterno). Underrun (el mostrador alcanza al lector) se cuenta por frame.
//
// 28/10/2026 (V9991, B7): lineas de hasta 1136 px (B7 = 1024 + 2 x 56 de borde, 36
// rafagas) y ENTRELAZADO: con IL el escritor guarda cada campo en las lineas de su
// paridad (cap_line = 2 x linea + campo, hasta 480) del MISMO slot y solo publica al
// acabar el campo impar (el puente filtra frame_end): el lector muestra cuadros
// completos de 480 lineas a x1,5. B5 (29/10/2026): 400 lineas de 640 px (20 rafagas).
// `reso` lleva el modo y el bit de entrelazado
// ({il, T9990_RESO}). RING_LINES lineas de anillo (16 en el V9990, por BRAM) y
// PREFETCH < RING_LINES.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9990_fb #(
    parameter [31:0] FB_BASE   = 32'h1040_0000,
    parameter [31:0] SLOT_SIZE = 32'h0006_0000,   // 393216 B >= 240 x 1536
    parameter [31:0] STRIDE    = 32'd1536,        // bytes por linea (768 px x 2)
    parameter        PREFETCH  = 16,              // lineas de adelanto del lector (< RING_LINES)
    // V9991 (28/10/2026): el mismo modulo sirve al V9968 (ventana): anillo de 640 columnas,
    // 20 rafagas por linea fijas (640 px / 2 por palabra / 16) e IDs 6/7 (el arbitro interior
    // del GP1 ruta por el bit 2). Con BURSTS_FIXED = 0 las rafagas van por `reso` (V9990).
    parameter        RING_W       = 768,
    parameter        RING_LINES   = 32,
    parameter [5:0]  BURSTS_FIXED = 6'd0,
    parameter [5:0]  AWID_V       = 6'd2,
    parameter [5:0]  ARID_V       = 6'd3,
    // Perfil Dual (31/10/2026): SKIP = 1 deja un RECTANGULO del frame buffer para otro escritor (bwin_fb, la imagen de la maquina B):
    // en las palabras de ese rectangulo el escritor del V9990 manda WSTRB = 0 (la rafaga y sus datos salen igual, pero la DDR no
    // cambia). El rectangulo son las filas skip_y0 .. skip_y1 - 1 (cap_line) y las palabras skip_wx0 .. skip_wx1 - 1 de cada una
    // (2 px por palabra). Con SKIP = 0 (lo de siempre) los puertos skip_* no se usan y el modulo es el de siempre.
    // Posicion fina (2/11/2026): con skip_odd = 1 la palabra skip_wx0 - 1 (su mitad alta es de B) sale con WSTRB = 0011 y la palabra skip_wx1
    // (su mitad baja es de B) con 1100: el escritor del V9990 pinta solo su mitad. Con skip_odd = 0 no cambia nada.
    parameter        SKIP         = 0
)(
    input  wire        clk,            // clk_86
    input  wire        resetn,         // dominio VDP
    input  wire        aresetn,        // reset AXI (FCLK_RESET0_N sincronizado)

    // ---- captura (clk, cualificada por ce) ----
    input  wire        ce,
    input  wire        wr_enable,      // 1 = capturar. 0 (V9991, el V9968 fuera del modo 2): se cierra la linea abierta,
                                       // no se publica nada y el escritor se desarma: al volver a 1 espera un VS y
                                       // captura el primer frame ENTERO
    input  wire        cap_en,         // pixel visible que hay que guardar
    input  wire        cap_sol,        // primer pixel de la linea (junto con cap_en)
    input  wire [8:0]  cap_line,       // linea nativa 0..239 (B5: 0..399; entrelazado: 2 x linea + campo, 0..479)
    input  wire [15:0] cap_rgb,        // {ys, r5, g5, b5}; ys = 1 transparente (V9991, 28/10/2026): va en el bit 15
                                       // de cada pixel de 16 bits en la DDR y en el bit 12 de la palabra de 18 del
                                       // anillo (el sitio de la replica del LSB de R, que el lector reconstruye)
    input  wire        frame_end,      // pulso (con ce): VS, el frame capturado esta completo
    input  wire [3:0]  reso,           // {entrelazado, T9990_RESO} del frame que se captura

    // ---- anillo del lector (clk) ----
    output reg         ring_we,
    output reg  [14:0] ring_addr,
    output reg  [17:0] ring_data,

    // ---- mostrador (dominio clk_pixel) ----
    input  wire        clk_pixel,
    input  wire        rd_req_tgl,     // cambia cuando el mostrador pide el frame siguiente
    input  wire [1:0]  rd_slot,        // slot pedido (estable antes de cambiar rd_req_tgl)
    input  wire [3:0]  rd_reso,        // {il, modo} de ese slot
    input  wire [8:0]  rd_yy_gray,     // linea nativa que muestra (0..240, 0..400 en B5 o 0..480, gray)

    // ---- rectangulo que el escritor se salta (solo con SKIP = 1) ----
    input  wire        skip_en,
    input  wire [9:0]  skip_y0,
    input  wire [9:0]  skip_y1,
    input  wire [9:0]  skip_wx0,
    input  wire [9:0]  skip_wx1,
    input  wire        skip_odd,       // el rectangulo empieza en un punto impar (posicion fina de B): las dos palabras del borde son compartidas
    output wire [1:0]  wslot_o,        // slot que esta escribiendo el escritor (para bwin_fb)
    output reg  [1:0]  pubx_slot,      // clk_pixel: ultimo frame completo
    output reg  [3:0]  pubx_reso,
    output reg         pubx_valid,

    // ---- telemetria (clk) ----
    output reg  [4:0]  dbg_underrun,   // lineas alcanzadas por el mostrador en el ultimo frame (satura en 31)
    output reg  [8:0]  dbg_wr_lines,   // lineas escritas a la DDR en el ultimo frame (esperado 240; 400 B5; 480 entrelazado)
    output wire [31:0] dbg_state,      // 29/10 (diagnostico B5): {rst_st[1:0], r_active, ARVALID, r_line[8:0], yy_dec[8:0], r_burst[3:0], wst[2:0], wr_outstanding[2:0]}

    // ---- AXI3 master 32 bits ----
    output wire [5:0]  M_AWID,
    output reg  [31:0] M_AWADDR,
    output wire [3:0]  M_AWLEN,
    output wire [2:0]  M_AWSIZE,
    output wire [1:0]  M_AWBURST,
    output wire [1:0]  M_AWLOCK,
    output wire [3:0]  M_AWCACHE,
    output wire [2:0]  M_AWPROT,
    output wire [3:0]  M_AWQOS,
    output reg         M_AWVALID,
    input  wire        M_AWREADY,
    output wire [5:0]  M_WID,
    output wire [31:0] M_WDATA,
    output wire [3:0]  M_WSTRB,
    output wire        M_WLAST,
    output reg         M_WVALID,
    input  wire        M_WREADY,
    input  wire [5:0]  M_BID,
    input  wire [1:0]  M_BRESP,
    input  wire        M_BVALID,
    output wire        M_BREADY,
    output wire [5:0]  M_ARID,
    output reg  [31:0] M_ARADDR,
    output wire [3:0]  M_ARLEN,
    output wire [2:0]  M_ARSIZE,
    output wire [1:0]  M_ARBURST,
    output wire [1:0]  M_ARLOCK,
    output wire [3:0]  M_ARCACHE,
    output wire [2:0]  M_ARPROT,
    output wire [3:0]  M_ARQOS,
    output reg         M_ARVALID,
    input  wire        M_ARREADY,
    input  wire [5:0]  M_RID,
    input  wire [31:0] M_RDATA,
    input  wire [1:0]  M_RRESP,
    input  wire        M_RLAST,
    input  wire        M_RVALID,
    output wire        M_RREADY
);
    // IDs distintos de los del cliente de VRAM (AW 0 / AR 1): el arbitro rutea B y R por el bit 1
    assign M_AWID = AWID_V;  assign M_WID = AWID_V;  assign M_ARID = ARID_V;
    assign M_AWLEN = 4'd15; assign M_ARLEN = 4'd15;          // rafagas de 16 x 32 bits
    assign M_AWSIZE = 3'd2; assign M_ARSIZE = 3'd2;
    assign M_AWBURST = 2'b01; assign M_ARBURST = 2'b01;
    assign M_AWLOCK = 2'b00; assign M_ARLOCK = 2'b00;
    assign M_AWCACHE = 4'b0011; assign M_ARCACHE = 4'b0011;
    assign M_AWPROT = 3'b000; assign M_ARPROT = 3'b000;
    assign M_AWQOS = 4'd0; assign M_ARQOS = 4'd0;
    assign M_BREADY = 1'b1;
    localparam signed [10:0] PF_S = PREFETCH;
    localparam RL_BITS = $clog2(RING_LINES);

    // rafagas por linea (2 px por palabra, redondeado a 16 palabras)
    function [5:0] bursts_of(input [3:0] m);
        case (m[2:0])
            3'd1:    bursts_of = 6'd12;   // B2 384 px -> 192 palabras
            3'd2:    bursts_of = 6'd18;   // B3 568 px -> 284 -> 288
            3'd3:    bursts_of = 6'd24;   // B4 768 px -> 384
            3'd4:    bursts_of = 6'd20;   // B5 640 px -> 320 (29/10/2026)
            3'd6:    bursts_of = 6'd36;   // B7 1136 px -> 568 -> 576 (28/10/2026)
            default: bursts_of = 6'd9;    // B1 284 px -> 142 -> 144
        endcase
    endfunction

    // ========================================================================
    // CDC: peticiones del mostrador (clk_pixel -> clk) y publicacion (clk -> clk_pixel)
    // ========================================================================
    reg [2:0] req_s = 3'b000;
    always @(posedge clk) req_s <= {req_s[1:0], rd_req_tgl};
    wire       req_edge = req_s[2] ^ req_s[1];     // rd_slot / rd_reso llevan >= 3 ciclos estables
    reg [8:0]  yyg_s0 = 9'd0, yyg_s1 = 9'd0;
    always @(posedge clk) begin yyg_s0 <= rd_yy_gray; yyg_s1 <= yyg_s0; end
    wire [8:0] yy_dec = yyg_s1 ^ (yyg_s1 >> 1) ^ (yyg_s1 >> 2) ^ (yyg_s1 >> 3) ^
                        (yyg_s1 >> 4) ^ (yyg_s1 >> 5) ^ (yyg_s1 >> 6) ^ (yyg_s1 >> 7) ^ (yyg_s1 >> 8);

    reg        pub_tgl = 1'b0;
    reg [1:0]  pub_slot = 2'd0;
    reg [3:0]  pub_reso = 4'd0;
    reg        pub_valid = 1'b0;
    reg [2:0]  pubt_s = 3'b000;
    initial begin pubx_slot = 2'd0; pubx_reso = 4'd0; pubx_valid = 1'b0; end
    always @(posedge clk_pixel) begin
        pubt_s <= {pubt_s[1:0], pub_tgl};
        if (pubt_s[2] ^ pubt_s[1]) begin            // los datos cambiaron >= 2 ciclos antes del toggle
            pubx_slot <= pub_slot; pubx_reso <= pub_reso; pubx_valid <= pub_valid;
        end
    end

    // ========================================================================
    // ESCRITOR, lado pixel: empaquetado, relleno y FIFO
    // ========================================================================
    localparam [1:0] TAG_DATA = 2'd0, TAG_SOL = 2'd1, TAG_EOF = 2'd2;
    (* ram_style = "block" *) reg [33:0] fifo [0:1023];
    reg  [9:0]  f_wp, f_rp;
    reg  [10:0] f_cnt;
    reg         f_push;
    reg  [33:0] f_din;
    reg  [33:0] f_dout;                 // = fifo[f_rp] un ciclo despues de fijar f_rp
    wire        f_pop;                  // combinacional (motor)
    wire [9:0]  f_rp_next = f_rp + {9'd0, f_pop};
    always @(posedge clk) begin
        if (f_push) fifo[f_wp] <= f_din;
        f_dout <= fifo[f_rp_next];
    end
    always @(posedge clk) begin
        if (!resetn) begin f_wp <= 10'd0; f_rp <= 10'd0; f_cnt <= 11'd0; end
        else begin
            if (f_push) f_wp <= f_wp + 10'd1;
            f_rp  <= f_rp_next;
            f_cnt <= f_cnt + {10'd0, f_push} - {10'd0, f_pop};
        end
    end
    reg f_pop_q = 1'b0;
    reg [10:0] f_cnt_q = 11'd0;
    always @(posedge clk) begin f_pop_q <= resetn ? f_pop : 1'b0; f_cnt_q <= f_cnt; end
    // f_dout refleja la cabecera: la entrada lleva >= 2 flancos escrita (f_cnt_q) y no se acaba de sacar
    wire head_valid = (f_cnt_q != 11'd0) && !f_pop_q;

    reg         armed;              // ya se vio un fin de frame: solo se guardan frames enteros
    reg         px_odd;             // px par pendiente en px_lo
    reg  [15:0] px_lo;
    reg  [3:0]  lw;                 // palabras de la linea mod 16
    reg         line_open;          // linea empezada y sin rellenar
    reg  [3:0]  pad_n;              // palabras de relleno pendientes
    reg         eof_pend;
    reg  [3:0]  eof_reso;
    reg         burst_done;         // +1 rafaga completa en la FIFO
    wire        line_done = ce && armed && line_open && (!cap_en || frame_end || !wr_enable);
    always @(posedge clk) begin
        if (!resetn) begin
            armed <= 1'b0; px_odd <= 1'b0; px_lo <= 16'd0; lw <= 4'd0; line_open <= 1'b0;
            pad_n <= 4'd0; eof_pend <= 1'b0; eof_reso <= 4'd0; f_push <= 1'b0; f_din <= 34'd0; burst_done <= 1'b0;
        end else begin
            f_push <= 1'b0; burst_done <= 1'b0;
            if (pad_n != 4'd0) begin
                // relleno a multiplo de 16 palabras (en el blanking, una palabra por ciclo)
                f_push <= 1'b1; f_din <= {TAG_DATA, 32'd0};
                pad_n <= pad_n - 4'd1; lw <= lw + 4'd1;
                if (pad_n == 4'd1) begin burst_done <= 1'b1; line_open <= 1'b0; end
            end
            else if (eof_pend) begin
                f_push <= 1'b1; f_din <= {TAG_EOF, 28'd0, eof_reso};
                eof_pend <= 1'b0;
            end
            else if (ce) begin
                if (!wr_enable) armed <= 1'b0;
                else if (frame_end) begin
                    if (armed) begin eof_pend <= 1'b1; eof_reso <= reso; end
                    armed <= 1'b1;
                end
                if (line_done) begin
                    // fin de la linea visible: px impar suelto + relleno
                    if (px_odd) begin
                        f_push <= 1'b1; f_din <= {TAG_DATA, 16'd0, px_lo}; px_odd <= 1'b0; lw <= lw + 4'd1;
                        if (lw == 4'd15) begin burst_done <= 1'b1; line_open <= 1'b0; end
                        else pad_n <= 4'd15 - lw;
                    end else begin
                        if (lw == 4'd0) line_open <= 1'b0; else pad_n <= (4'd0 - lw);
                    end
                end
                else if (armed && cap_en && !frame_end) begin
                    if (cap_sol) begin
                        f_push <= 1'b1; f_din <= {TAG_SOL, 23'd0, cap_line};
                        lw <= 4'd0; px_odd <= 1'b1; px_lo <= cap_rgb; line_open <= 1'b1;
                    end
                    else if (px_odd) begin
                        f_push <= 1'b1; f_din <= {TAG_DATA, cap_rgb, px_lo};
                        px_odd <= 1'b0; lw <= lw + 4'd1;
                        if (lw == 4'd15) burst_done <= 1'b1;
                    end
                    else begin
                        px_odd <= 1'b1; px_lo <= cap_rgb;
                    end
                end
            end
        end
    end

    // ========================================================================
    // ESCRITOR, motor AXI: SOL -> direccion; rafaga lista -> AW + 16 W; EOF -> publicar
    // ========================================================================
    localparam [2:0] W_IDLE = 3'd0, W_AW = 3'd1, W_DATA = 3'd2, W_EOF = 3'd3, W_PUB = 3'd4;
    reg [2:0]  wst;
    reg [1:0]  w_slot;             // slot que se esta escribiendo
    reg [31:0] w_line_base;
    reg [5:0]  w_burst;
    reg [3:0]  w_beat;
    reg [3:0]  wr_outstanding;
    reg [8:0]  w_lines;
    reg [3:0]  w_reso;
    reg [5:0]  bursts_avail;       // rafagas completas en la FIFO aun no emitidas (B7: 36 por linea)
    reg        burst_take;
    reg [1:0]  rd_slot_used;       // slot que muestra el lector (para no pisarlo)
    wire aw_acc = M_AWVALID && M_AWREADY;
    wire w_acc  = M_WVALID  && M_WREADY;
    wire b_acc  = M_BVALID  && M_BREADY;
    wire [1:0] head_tag = f_dout[33:32];
    wire w_start = (wst == W_IDLE) && head_valid && (head_tag == TAG_DATA) &&
                   (bursts_avail != 6'd0) && !wr_outstanding[3];
    assign f_pop  = ((wst == W_IDLE) && head_valid && (head_tag != TAG_DATA)) ||   // consumir SOL / EOF
                    ((wst == W_DATA) && w_acc);                                     // siguiente palabra de la rafaga
    assign M_WDATA = f_dout[31:0];
    assign M_WLAST = (w_beat == 4'd15);
    assign wslot_o = w_slot;
    generate if (SKIP != 0) begin : g_skip
        // fila (cap_line) de la linea en escritura: se guarda al consumir su SOL
        reg [8:0] w_cline = 9'd0;
        always @(posedge clk) if (wst == W_IDLE && head_valid && head_tag == TAG_SOL) w_cline <= f_dout[8:0];
        wire [9:0] w_word  = {w_burst, w_beat};
        wire       rows_ok = skip_en && ({1'b0, w_cline} >= skip_y0) && ({1'b0, w_cline} < skip_y1);
        wire       in_rect = rows_ok && (w_word >= skip_wx0) && (w_word < skip_wx1);
        wire       p_lo    = rows_ok && skip_odd && (w_word + 10'd1 == skip_wx0);
        wire       p_hi    = rows_ok && skip_odd && (w_word == skip_wx1);
        assign M_WSTRB = in_rect ? 4'b0000 : p_lo ? 4'b0011 : p_hi ? 4'b1100 : 4'b1111;
    end else begin : g_noskip
        assign M_WSTRB = 4'b1111;
    end endgenerate
    always @(posedge clk) begin
        if (!resetn) bursts_avail <= 6'd0;
        else bursts_avail <= bursts_avail + {5'd0, burst_done} - {5'd0, burst_take};
    end
    always @(posedge clk) begin
        if (!aresetn) begin
            wst <= W_IDLE; M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_AWADDR <= 32'd0;
            w_slot <= 2'd0; w_line_base <= FB_BASE; w_burst <= 6'd0; w_beat <= 4'd0;
            wr_outstanding <= 4'd0; burst_take <= 1'b0;
            pub_tgl <= 1'b0; pub_slot <= 2'd0; pub_reso <= 4'd0; pub_valid <= 1'b0;
            w_lines <= 9'd0; w_reso <= 4'd0; dbg_wr_lines <= 9'd0; rd_slot_used <= 2'd3;
        end else begin
            burst_take <= 1'b0;
            wr_outstanding <= wr_outstanding + {3'd0, aw_acc} - {3'd0, b_acc};
            if (req_edge) rd_slot_used <= rd_slot;
            case (wst)
            W_IDLE: if (head_valid) begin
                case (head_tag)
                TAG_SOL: begin
                    w_line_base <= FB_BASE + w_slot * SLOT_SIZE + f_dout[8:0] * STRIDE;
                    w_burst <= 6'd0; w_lines <= w_lines + 9'd1;
                end
                TAG_EOF: begin w_reso <= f_dout[3:0]; wst <= W_EOF; end
                default: if (w_start) begin
                    M_AWADDR <= w_line_base + {20'd0, w_burst, 6'd0};
                    M_AWVALID <= 1'b1; burst_take <= 1'b1;
                    w_beat <= 4'd0; wst <= W_AW;
                end
                endcase
            end
            W_AW: if (aw_acc) begin
                M_AWVALID <= 1'b0; M_WVALID <= 1'b1; wst <= W_DATA;    // f_dout = palabra 0
            end
            W_DATA: if (w_acc) begin
                w_beat <= w_beat + 4'd1;
                if (w_beat == 4'd15) begin M_WVALID <= 1'b0; w_burst <= w_burst + 6'd1; wst <= W_IDLE; end
            end
            W_EOF: if (wr_outstanding == 4'd0) begin
                pub_slot <= w_slot; pub_reso <= w_reso; pub_valid <= 1'b1;
                dbg_wr_lines <= w_lines; w_lines <= 9'd0;
                wst <= W_PUB;
            end
            W_PUB: begin
                pub_tgl <= ~pub_tgl;        // pub_* ya estables desde el ciclo anterior
                w_slot <= (w_slot == 2'd0) ? ((rd_slot_used == 2'd1) ? 2'd2 : 2'd1) :
                          (w_slot == 2'd1) ? ((rd_slot_used == 2'd2) ? 2'd0 : 2'd2) :
                                             ((rd_slot_used == 2'd0) ? 2'd1 : 2'd0);
                wst <= W_IDLE;
            end
            default: wst <= W_IDLE;
            endcase
        end
    end

    assign dbg_state = {rst_st, r_active, M_ARVALID, r_line, yy_dec, r_burst[3:0], wst, wr_outstanding[2:0]};

    // ========================================================================
    // LECTOR: trae lineas del slot pedido al anillo, PREFETCH por delante del mostrador
    // ========================================================================
    // Lecturas en vuelo (29/10/2026, el de zynq 87e88fe con los parametros de esta rama): hasta RD_OUT (4) rafagas a la
    // vez (el AR de la siguiente sale sin esperar los R de la anterior). Con una rafaga por vez (AR -> 16 R -> siguiente AR)
    // la latencia real del GP1 + PS no daba para 480 filas por cuadro con IL (franja negra arriba en zynq) y B7 entrelazado
    // pide 36 rafagas por fila compartiendo el GP1 con el frame buffer del V9968. Los R vuelven en orden (mismo ARID). Al
    // llegar un cuadro nuevo las rafagas aun en vuelo del anterior se tiran (r_disc): antes una peticion a mitad de rafaga
    // ponia r_line / r_burst a 0 sin descartar la que llegaba y la fila 0 de ese cuadro salia con basura.
    localparam [2:0] RD_OUT = 3'd4;
    reg [1:0]  rst_st;             // telemetria (dbg_state): 0 parado, 1 AR pendiente, 2 recibiendo
    reg [1:0]  r_slot;
    reg [8:0]  ar_line;            // fila de la siguiente rafaga que se pide (0..240, 400 en B5, 480 entrelazado)
    reg [5:0]  ar_burst;
    reg [8:0]  r_line;             // fila que se esta recibiendo (las anteriores ya estan en el anillo)
    reg [8:0]  r_lines;            // filas del slot pedido: 240, 400 (B5) o 480 entrelazado
    reg [5:0]  r_burst, r_nb;      // rafaga en recepcion / rafagas por fila
    reg [2:0]  r_out;              // rafagas pedidas (con el AR aun por aceptar) cuyo RLAST no ha llegado
    reg [2:0]  r_disc;             // de ellas, las que son de un cuadro anterior
    reg        r_active;
    reg        r_pend;             // px impar del ultimo beat pendiente de escribir al anillo
    reg        r_eol;              // ... y ese beat cierra la fila
    reg [15:0] r_pend_data;
    reg [10:0] r_x;
    reg [14:0] r_linew;            // fila del anillo x RING_W
    reg [4:0]  und_cnt;
    reg [8:0]  yy_prev;
    wire signed [10:0] ahead    = $signed({2'b00, ar_line}) - $signed({2'b00, yy_dec});   // filas pedidas por delante
    wire signed [10:0] ahead_rx = $signed({2'b00, r_line})  - $signed({2'b00, yy_dec});   // filas ya en el anillo
    wire [8:0] r_line_n = r_line + 9'd1;
    assign M_RREADY = !r_pend;
    wire r_acc  = M_RVALID && M_RREADY;
    wire r_last = r_acc && M_RLAST;
    wire ar_go  = r_active && !req_edge && !M_ARVALID && ar_line < r_lines && ahead < PF_S && r_out < RD_OUT;
    always @(posedge clk) rst_st <= M_ARVALID ? 2'd1 : (r_out != 3'd0) ? 2'd2 : 2'd0;
    // {r5, ys, g5, g5[4], b5, b5[4]}: el bit 12 lleva la transparencia en vez de la replica del LSB de R
    function [17:0] px18(input [15:0] p);
        px18 = {p[14:10], p[15], p[9:5], p[9], p[4:0], p[4]};
    endfunction
    always @(posedge clk) begin
        if (!aresetn) begin
            M_ARVALID <= 1'b0; M_ARADDR <= 32'd0;
            r_slot <= 2'd0; ar_line <= 9'd480; ar_burst <= 6'd0; r_line <= 9'd480; r_lines <= 9'd240; r_burst <= 6'd0; r_nb <= 6'd9;
            r_out <= 3'd0; r_disc <= 3'd0;
            r_active <= 1'b0; r_pend <= 1'b0; r_eol <= 1'b0; r_pend_data <= 16'd0; r_x <= 11'd0; r_linew <= 15'd0;
            ring_we <= 1'b0; ring_addr <= 15'd0; ring_data <= 18'd0; und_cnt <= 5'd0; dbg_underrun <= 5'd0; yy_prev <= 9'd0;
        end else begin
            ring_we <= 1'b0;
            yy_prev <= yy_dec;
            if (M_ARVALID && M_ARREADY) M_ARVALID <= 1'b0;
            r_out <= r_out + {2'b00, ar_go} - {2'b00, r_last};
            // segundo px del ultimo beat
            if (r_pend) begin
                ring_we <= 1'b1; ring_addr <= r_linew + {4'd0, r_x}; ring_data <= px18(r_pend_data);
                r_pend <= 1'b0;
                if (r_eol) begin
                    r_eol <= 1'b0; r_x <= 11'd0; r_line <= r_line_n;
                    r_linew <= r_line_n[RL_BITS-1:0] * RING_W[14:0];
                end else r_x <= r_x + 11'd1;
            end
            if (req_edge) begin
                r_slot <= rd_slot; r_nb <= (BURSTS_FIXED != 6'd0) ? BURSTS_FIXED : bursts_of(rd_reso);
                r_lines <= rd_reso[3] ? 9'd480 : (rd_reso[2:0] == 3'd4) ? 9'd400 : 9'd240;   // B5: 400 (29/10/2026)
                ar_line <= 9'd0; ar_burst <= 6'd0; r_line <= 9'd0; r_burst <= 6'd0; r_x <= 11'd0; r_linew <= 15'd0;
                r_active <= 1'b1;
                r_disc <= r_out - {2'b00, r_last};      // lo aun en vuelo es del cuadro anterior
                dbg_underrun <= und_cnt; und_cnt <= 5'd0;
            end
            else begin
                if (r_active && yy_dec != yy_prev && yy_dec < r_lines && ahead_rx <= 11'sd0 && und_cnt != 5'd31)
                    und_cnt <= und_cnt + 5'd1;      // el mostrador entra en una fila que aun no esta
                // pedir la siguiente rafaga
                if (ar_go) begin
                    M_ARADDR  <= FB_BASE + r_slot * SLOT_SIZE + ar_line * STRIDE + {20'd0, ar_burst, 6'd0};
                    M_ARVALID <= 1'b1;
                    if (ar_burst == r_nb - 6'd1) begin ar_burst <= 6'd0; ar_line <= ar_line + 9'd1; end
                    else ar_burst <= ar_burst + 6'd1;
                end
                // recibir
                if (r_acc) begin
                    if (r_disc != 3'd0) begin
                        if (M_RLAST) r_disc <= r_disc - 3'd1;
                    end else begin
                        ring_we <= 1'b1; ring_addr <= r_linew + {4'd0, r_x}; ring_data <= px18(M_RDATA[15:0]);
                        r_x <= r_x + 11'd1;
                        r_pend <= 1'b1; r_pend_data <= M_RDATA[31:16];
                        if (M_RLAST) begin
                            if (r_burst == r_nb - 6'd1) begin r_burst <= 6'd0; r_eol <= 1'b1; end
                            else r_burst <= r_burst + 6'd1;
                        end
                    end
                end
            end
        end
    end
endmodule
