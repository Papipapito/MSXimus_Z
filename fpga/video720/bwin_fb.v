// ============================================================================
// bwin_fb.v - la imagen de la maquina B (perfil Dual) dentro del frame buffer del V9990 (31/10/2026).
//
// Por que: el escritorio que pinta el ARM es un frame del V9990 en la DDR (v9990_fb, 3 slots). En lugar de un tercer lector de
// video (con su anillo de BRAM, que ya no cabe en el XC7Z020) la imagen del V9968 de B se escribe como UN RECTANGULO dentro de ese
// frame buffer, y el escritor del V9990 se salta el rectangulo (v9990_fb con SKIP: WSTRB = 0 en esas palabras). El lector del V9990
// lo saca todo junto y el compositor pone encima la ventana de A, como siempre.
//
// Que hace: captura el video de B (clk_86, un pixel por ce, HS/VS/DE activos altos, 5 bits por color, 640 px por linea), se queda
// con las lineas SRC_Y0 .. SRC_Y0 + NLINES - 1 de las que llevan imagen y con 256 de cada 640 pixeles (uno de cada 2,5: los 256
// puntos de un modo de 256, y un aspecto cercano al 4:3 en un escritorio B5, donde un punto mide 2 x 1,5 pixeles), los empaqueta de
// dos en dos (RGB555 en 16 bits, bit 15 = 0: opaco; el mismo formato que v9990_fb) en un buffer de linea de LUTRAM (dos, ping-pong),
// y cada linea completa sale por AXI3 en 8 rafagas de 16 palabras a
//     FB_BASE + slot * SLOT_SIZE + (y0 + linea) * STRIDE + 2 * x0
// donde `slot` es el slot que esta escribiendo el V9990 en ese momento (w_slot): ese slot se publica al acabar el frame del V9990.
// B y el V9990 no estan enganchados: el rectangulo de un slot junta lineas de dos cuadros de B (una costura que rueda despacio).
//
// POSICION FINA (2/11/2026, escritorio de dos columnas con las ventanas arrastrables): x0 puede ser CUALQUIER punto (no solo multiplo de
// 32) y y0 cualquier fila. Las rafagas siguen alineadas a 64 B (empiezan en x0 & ~31, sin cruzar los 4 KB) y son 9 por linea (288 puntos:
// hasta 31 de margen + 256 de B); lo que cae fuera de B sale con WSTRB = 0. El desplazamiento fino (x0 & 31) se hace al sacar las palabras,
// sin ampliar el buffer de linea: la palabra de salida `wo` lleva los puntos 2wo y 2wo+1 de la rafaga, que son los puntos 2wo-f y 2wo+1-f
// de B (f = x0 & 31 = 2m + f0): con f par es la palabra wo-m del buffer tal cual y con f impar {palabra(wo-m)[15:0], palabra(wo-m-1)[31:16]}
// (la mitad alta de la palabra anterior se guarda en `prev_h`). El puntero de lectura `rp` = wo - m cuenta con signo (-15 .. 143); el byte
// enable de cada mitad sale de si su punto de B esta entre 0 y 255. Con x0 impar la palabra de cada borde la comparte con el escritor del
// V9990 (v9990_fb pone WSTRB = 0011 o 1100 en la suya: skip_odd).
//
// Solo escribe (ARVALID = 0 siempre). Sin BRAM.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module bwin_fb #(
    parameter [31:0] FB_BASE   = 32'h1040_0000,
    parameter [31:0] SLOT_SIZE = 32'h0011_0000,
    parameter [31:0] STRIDE    = 32'd2304,     // fijo en 2304 (= 2048 + 256) en la cuenta de la direccion
    parameter [5:0]  AWID      = 6'd10,        // bits 1 y 3 a 1: el arbitro interior (ID_BIT 3) lo manda a su B y el exterior (ID_BIT 1) tambien
    parameter integer SRC_Y0   = 14,           // primera linea con imagen de B que entra (el recorte SRCY = 14 de la ventana de A)
    parameter integer NLINES   = 212           // lineas de la ventana
)(
    input  wire        clk,            // clk_86
    input  wire        resetn,
    input  wire        aresetn,

    // ---- video de B (clk, cualificado por ce) ----
    input  wire        ce,
    input  wire [4:0]  r,
    input  wire [4:0]  g,
    input  wire [4:0]  b,
    input  wire        hs,
    input  wire        vs,
    input  wire        de,

    // ---- colocacion ----
    input  wire        en,             // 1 = capturar y escribir
    input  wire [10:0] x0,             // primera columna del rectangulo en el frame buffer (cualquier punto; <= 896)
    input  wire [9:0]  y0,             // primera fila (cualquiera; <= 268)
    input  wire [1:0]  w_slot,         // slot que esta escribiendo el V9990

    // ---- AXI3 master 32 bits (solo escritura) ----
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

    output reg  [15:0] dbg_lines       // lineas escritas a la DDR en el ultimo frame de B (esperado NLINES)
);
    assign M_AWID = AWID;  assign M_WID = AWID;
    assign M_AWLEN = 4'd15; assign M_AWSIZE = 3'd2; assign M_AWBURST = 2'b01;
    assign M_AWLOCK = 2'b00; assign M_AWCACHE = 4'b0011; assign M_AWPROT = 3'b000; assign M_AWQOS = 4'd0;
    assign M_BREADY = 1'b1;
    assign M_ARID = 6'd0; assign M_ARADDR = 32'd0; assign M_ARLEN = 4'd0; assign M_ARSIZE = 3'd2; assign M_ARBURST = 2'b01;
    assign M_ARLOCK = 2'b00; assign M_ARCACHE = 4'b0011; assign M_ARPROT = 3'b000; assign M_ARQOS = 4'd0;
    assign M_ARVALID = 1'b0; assign M_RREADY = 1'b1;

    // ------------------------------------------------------------------ captura (clk, ce)
    reg hs_q = 1'b0, vs_q = 1'b0, vs_qq = 1'b0, de_q = 1'b0, de_qq = 1'b0;
    reg [4:0] r_q = 5'd0, g_q = 5'd0, b_q = 5'd0;
    always @(posedge clk) begin
        if (!resetn) begin
            vs_q <= 1'b0; vs_qq <= 1'b0; de_q <= 1'b0; de_qq <= 1'b0;
        end else if (ce) begin
            vs_q <= vs; vs_qq <= vs_q; de_q <= de; de_qq <= de_q;
            r_q <= r; g_q <= g; b_q <= b;
        end
    end
    wire vs_lead  = vs_q & ~vs_qq;
    wire de_lead  = de_q & ~de_qq;         // primer pixel de una linea con imagen (r_q/g_q/b_q ya son ese pixel)
    wire de_trail = ~de_q & de_qq;         // acaba la linea con imagen

    (* ram_style = "distributed" *) reg [31:0] lb [0:255];     // dos buffers de 128 palabras (256 puntos)
    reg [7:0]  lnum [0:1];                  // numero de linea (0 .. NLINES - 1) de cada buffer
    reg [8:0]  dl = 9'd0;                   // lineas con imagen vistas en este frame (0-based: la que empieza es dl)
    reg        started = 1'b0;
    reg [1:0]  fc = 2'd0;                   // buffers llenados (mod 4); el buffer que se llena es fc[0]
    wire [1:0] dc_w;                        // buffers volcados (mod 4); el que se vuelca es dc_w[0]
    wire [1:0] pending = fc - dc_w;         // 0 .. 2
    reg        cap_line = 1'b0;             // se esta capturando la linea en curso
    reg [7:0]  lnum_cur = 8'd0;
    reg [2:0]  acc = 3'd3;                  // decimacion 2,5:1: acc + 2 >= 5 -> sale pixel
    reg [8:0]  nout = 9'd0;                 // pixeles que han salido en la linea (0 .. 256)
    reg [15:0] px_lo = 16'd0;
    wire       n_ok     = started && (dl >= SRC_Y0) && (dl < SRC_Y0 + NLINES);
    wire       cap_new  = en && n_ok && (pending != 2'd2);
    wire       cap_now  = de_lead ? cap_new : cap_line;
    wire [2:0] acc_cur  = de_lead ? 3'd3 : acc;
    wire [8:0] nout_cur = de_lead ? 9'd0 : nout;
    wire [2:0] acc_n    = acc_cur + 3'd2;
    wire       emit     = (acc_n >= 3'd5);
    wire [15:0] px      = {1'b0, r_q, g_q, b_q};
    always @(posedge clk) begin
        if (!resetn) begin
            dl <= 9'd0; started <= 1'b0; fc <= 2'd0; cap_line <= 1'b0; acc <= 3'd3; nout <= 9'd0; lnum_cur <= 8'd0;
        end else if (ce) begin
            if (vs_lead) begin dl <= 9'd0; started <= 1'b1; end
            else if (de_lead && started) dl <= dl + 9'd1;
            if (de_lead) begin cap_line <= cap_new; lnum_cur <= dl - SRC_Y0; end
            if (de_q && cap_now) begin
                acc <= emit ? (acc_n - 3'd5) : acc_n;
                if (emit && nout_cur < 9'd256) begin
                    nout <= nout_cur + 9'd1;
                    if (!nout_cur[0]) px_lo <= px;
                    else lb[{fc[0], nout_cur[7:1]}] <= {px, px_lo};
                end else nout <= nout_cur;
            end
            if (de_trail && cap_line) begin
                cap_line <= 1'b0;
                lnum[fc[0]] <= lnum_cur; fc <= fc + 2'd1;
            end
        end
    end

    // ------------------------------------------------------------------ escritura AXI
    localparam [2:0] S_IDLE = 3'd0, S_A1 = 3'd1, S_A2 = 3'd2, S_AW0 = 3'd3, S_AW1 = 3'd4, S_W = 3'd5;
    reg [2:0]  st;
    reg [1:0]  dc;
    assign dc_w = dc;
    reg [3:0]  burst;                       // 0 .. 8: nueve rafagas de 16 palabras desde la columna x0 & ~31
    reg [3:0]  beat;
    reg [31:0] a_row;
    reg [9:0]  yrow;
    reg [31:0] slot_off;
    reg [15:0] wr_lines;
    reg [5:0]  xb;                          // x0 >> 5 (la rafaga 0 empieza en el punto 32 * xb)
    reg        fodd;                        // x0 impar
    reg [3:0]  fm;                          // (x0 & 31) >> 1
    reg [8:0]  rp;                          // palabra de origen que toca (palabra de salida - fm), con signo
    reg [15:0] prev_h;                      // mitad alta de la palabra de origen anterior (con x0 impar)
    wire       aw_acc = M_AWVALID && M_AWREADY;
    wire       w_acc  = M_WVALID  && M_WREADY;
    wire [31:0] cur    = lb[{dc[0], rp[6:0]}];
    wire        in_rng = ~rp[8] & ~rp[7];                                             // 0 .. 127: los dos puntos de la palabra son de B
    wire        lo_ok  = fodd ? (~rp[8] & (rp[7:0] != 8'd0) & (~rp[7] | (rp[7:0] == 8'd128))) : in_rng;   // impar: 1 .. 128
    assign M_WDATA = fodd ? {cur[15:0], prev_h} : cur;
    assign M_WSTRB = {in_rng, in_rng, lo_ok, lo_ok};
    assign M_WLAST = (beat == 4'd15);
    always @(posedge clk) begin
        if (!aresetn) begin
            st <= S_IDLE; dc <= 2'd0; burst <= 4'd0; beat <= 4'd0; M_AWVALID <= 1'b0; M_WVALID <= 1'b0;
            M_AWADDR <= 32'd0; a_row <= 32'd0; yrow <= 10'd0; slot_off <= 32'd0; wr_lines <= 16'd0;
            xb <= 6'd0; fodd <= 1'b0; fm <= 4'd0; rp <= 9'd0; prev_h <= 16'd0;
        end else begin
            case (st)
            S_IDLE: if (pending != 2'd0) begin
                yrow <= y0 + {2'b00, lnum[dc[0]]};
                slot_off <= (w_slot == 2'd0) ? 32'd0 : (w_slot == 2'd1) ? SLOT_SIZE : {SLOT_SIZE[30:0], 1'b0};
                xb <= x0[10:5]; fodd <= x0[0]; fm <= x0[4:1];
                burst <= 4'd0; st <= S_A1;
            end
            S_A1: begin a_row <= ({22'd0, yrow} << 11) + ({22'd0, yrow} << 8); rp <= 9'd0 - {5'd0, fm}; st <= S_A2; end   // yrow * 2304
            S_A2: begin a_row <= a_row + slot_off + FB_BASE + {20'd0, xb, 6'd0}; st <= S_AW0; end
            S_AW0: begin M_AWADDR <= a_row + {22'd0, burst, 6'd0}; M_AWVALID <= 1'b1; beat <= 4'd0; st <= S_AW1; end
            S_AW1: if (aw_acc) begin M_AWVALID <= 1'b0; M_WVALID <= 1'b1; st <= S_W; end
            S_W: if (w_acc) begin
                beat <= beat + 4'd1;
                rp <= rp + 9'd1;
                prev_h <= cur[31:16];
                if (beat == 4'd15) begin
                    M_WVALID <= 1'b0;
                    if (burst == 4'd8) begin dc <= dc + 2'd1; wr_lines <= wr_lines + 16'd1; st <= S_IDLE; end
                    else begin burst <= burst + 4'd1; st <= S_AW0; end
                end
            end
            default: st <= S_IDLE;
            endcase
            if (vs_lead_a) begin dbg_lines <= wr_lines; wr_lines <= 16'd0; end
        end
    end
    reg  vs_a_d = 1'b0;
    wire vs_lead_a = vs_q & ~vs_a_d;
    always @(posedge clk) vs_a_d <= vs_q;
    initial dbg_lines = 16'd0;
endmodule
