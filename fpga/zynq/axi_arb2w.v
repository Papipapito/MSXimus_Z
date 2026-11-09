// ============================================================================
// axi_arb2w.v - Arbitro AXI3 de DOS maestros sobre UN esclavo, con el ancho de datos parametrizable (64 bits por defecto: los
// puertos S_AXI_HPx del PS). Es axi_arb2.v (el del GP1, 32 bits) sin mas cambios que el ancho: mismas reglas de ruta y de
// bloqueo del AR. Perfil Dual (31/10/2026): lo usan el HP0 (VRAM de A y de B, ID_BIT = 5) y el HP2 (buzon y RAM de B, ID_BIT = 5).
//
//  * Lecturas: AR de cualquiera (A antes que B si coinciden); las dos pueden tener rafagas en vuelo a la vez. Los beats R se
//    rutan por RID[ID_BIT]: los maestros B etiquetan con ese bit a 1 (ID_PFX = 32 en v9968_axi_backend y memory_axi) y los A
//    lo llevan a 0 (el buzon usa IDs < 8, el backend de A con prefijo 0 y 5 bits de etiqueta).
//  * Escrituras: AXI3 sin intercalado de datos -> una transaccion entera (AW y sus W hasta WLAST) de un maestro cada vez. B se
//    rutea por BID[ID_BIT]. Un maestro puede presentar W antes de que le acepten el AW (memory_axi lo hace): el W solo pasa
//    cuando el arbitro esta en la fase de datos de ese maestro.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module axi_arb2w #(
    parameter DW     = 64,
    parameter ID_BIT = 5,
    // 31/10/2026 (placa del Dual): si el maestro dueno de una rafaga de escritura se queda W_TMO ciclos sin presentar WVALID (un
    // reset que le suelta el VALID a medias) el arbitro CIERRA la rafaga con beats de WSTRB = 0 hasta WLAST, para no dejar al otro
    // maestro del puerto (el buzon del ARM, en el HP2) esperando para siempre. 0 = sin vaciado (lo anterior). Un maestro correcto
    // nunca se acerca: memory_axi, los backends de VRAM y el buzon presentan sus beats seguidos.
    parameter W_TMO  = 0
) (
    input  wire        clk,
    input  wire        aresetn,

    // ---- maestro A (prioridad) ----
    input  wire [5:0]  a_awid,   input  wire [31:0] a_awaddr, input  wire [3:0] a_awlen,  input  wire [2:0] a_awsize,
    input  wire [1:0]  a_awburst, input wire [1:0]  a_awlock, input  wire [3:0] a_awcache, input wire [2:0] a_awprot,
    input  wire [3:0]  a_awqos,  input  wire        a_awvalid, output wire       a_awready,
    input  wire [5:0]  a_wid,    input  wire [DW-1:0] a_wdata,  input  wire [DW/8-1:0] a_wstrb,  input  wire       a_wlast,
    input  wire        a_wvalid, output wire        a_wready,
    output wire [5:0]  a_bid,    output wire [1:0]  a_bresp,  output wire       a_bvalid, input  wire       a_bready,
    input  wire [5:0]  a_arid,   input  wire [31:0] a_araddr, input  wire [3:0] a_arlen,  input  wire [2:0] a_arsize,
    input  wire [1:0]  a_arburst, input wire [1:0]  a_arlock, input  wire [3:0] a_arcache, input wire [2:0] a_arprot,
    input  wire [3:0]  a_arqos,  input  wire        a_arvalid, output wire       a_arready,
    output wire [5:0]  a_rid,    output wire [DW-1:0] a_rdata,  output wire [1:0] a_rresp,  output wire       a_rlast,
    output wire        a_rvalid, input  wire        a_rready,

    // ---- maestro B ----
    input  wire [5:0]  b_awid,   input  wire [31:0] b_awaddr, input  wire [3:0] b_awlen,  input  wire [2:0] b_awsize,
    input  wire [1:0]  b_awburst, input wire [1:0]  b_awlock, input  wire [3:0] b_awcache, input wire [2:0] b_awprot,
    input  wire [3:0]  b_awqos,  input  wire        b_awvalid, output wire       b_awready,
    input  wire [5:0]  b_wid,    input  wire [DW-1:0] b_wdata,  input  wire [DW/8-1:0] b_wstrb,  input  wire       b_wlast,
    input  wire        b_wvalid, output wire        b_wready,
    output wire [5:0]  b_bid,    output wire [1:0]  b_bresp,  output wire       b_bvalid, input  wire       b_bready,
    input  wire [5:0]  b_arid,   input  wire [31:0] b_araddr, input  wire [3:0] b_arlen,  input  wire [2:0] b_arsize,
    input  wire [1:0]  b_arburst, input wire [1:0]  b_arlock, input  wire [3:0] b_arcache, input wire [2:0] b_arprot,
    input  wire [3:0]  b_arqos,  input  wire        b_arvalid, output wire       b_arready,
    output wire [5:0]  b_rid,    output wire [DW-1:0] b_rdata,  output wire [1:0] b_rresp,  output wire       b_rlast,
    output wire        b_rvalid, input  wire        b_rready,

    // ---- esclavo (S_AXI_GP1) ----
    output wire [5:0]  s_awid,   output wire [31:0] s_awaddr, output wire [3:0] s_awlen,  output wire [2:0] s_awsize,
    output wire [1:0]  s_awburst, output wire [1:0] s_awlock, output wire [3:0] s_awcache, output wire [2:0] s_awprot,
    output wire [3:0]  s_awqos,  output wire        s_awvalid, input  wire       s_awready,
    output wire [5:0]  s_wid,    output wire [DW-1:0] s_wdata,  output wire [DW/8-1:0] s_wstrb,  output wire       s_wlast,
    output wire        s_wvalid, input  wire        s_wready,
    input  wire [5:0]  s_bid,    input  wire [1:0]  s_bresp,  input  wire       s_bvalid, output wire       s_bready,
    output wire [5:0]  s_arid,   output wire [31:0] s_araddr, output wire [3:0] s_arlen,  output wire [2:0] s_arsize,
    output wire [1:0]  s_arburst, output wire [1:0] s_arlock, output wire [3:0] s_arcache, output wire [2:0] s_arprot,
    output wire [3:0]  s_arqos,  output wire        s_arvalid, input  wire       s_arready,
    input  wire [5:0]  s_rid,    input  wire [DW-1:0] s_rdata,  input  wire [1:0] s_rresp,  input  wire       s_rlast,
    input  wire        s_rvalid, output wire        s_rready
);
    // ------------------------------------------------------------------ lecturas
    // La seleccion del AR queda FIJADA mientras el esclavo no lo acepte (AXI: la carga
    // de un canal no puede cambiar con VALID alto). Sin esto, si A pedia mientras el AR
    // de B esperaba el ARREADY, la direccion/ID presentados al PS cambiaban a mitad del
    // handshake y una de las dos rafagas se perdia (el cliente de VRAM esperaba eternamente
    // sus R con el core parado: pantalla negra en B3 a 16 bpp, 21/09).
    reg  ar_lock = 1'b0, ar_sel_q = 1'b0;
    wire sel_b_ar = ar_lock ? ar_sel_q : (!a_arvalid && b_arvalid);
    assign s_arvalid = a_arvalid | b_arvalid;
    always @(posedge clk) begin
        if (!aresetn) begin ar_lock <= 1'b0; ar_sel_q <= 1'b0; end
        else if (s_arvalid && !s_arready) begin ar_lock <= 1'b1; ar_sel_q <= sel_b_ar; end
        else ar_lock <= 1'b0;
    end
    assign s_arid    = sel_b_ar ? b_arid    : a_arid;
    assign s_araddr  = sel_b_ar ? b_araddr  : a_araddr;
    assign s_arlen   = sel_b_ar ? b_arlen   : a_arlen;
    assign s_arsize  = sel_b_ar ? b_arsize  : a_arsize;
    assign s_arburst = sel_b_ar ? b_arburst : a_arburst;
    assign s_arlock  = sel_b_ar ? b_arlock  : a_arlock;
    assign s_arcache = sel_b_ar ? b_arcache : a_arcache;
    assign s_arprot  = sel_b_ar ? b_arprot  : a_arprot;
    assign s_arqos   = sel_b_ar ? b_arqos   : a_arqos;
    // 29/10/2026 (B5 en placa, V9991 paso 5): A solo ve su AR aceptado si es el SUYO el que va al esclavo. Antes
    // a_arready = s_arready & a_arvalid: con el arbitro BLOQUEADO en un AR de B (el esclavo tardo en aceptarlo) y A pidiendo
    // en ese momento, al llegar el ARREADY el PS aceptaba el AR de B y A creia aceptado el suyo: su rafaga se perdia y A
    // esperaba eternamente sus R. En el arbitro interior A es el lector del frame buffer del V9990 -> lector colgado para
    // siempre (underrun 31, el anillo rancio: una linea repetida en toda la pantalla). B5 lo provocaba en segundos (su
    // patron de cache de VRAM, 336 B por linea y un salto, bloquea el arbitro exterior mucho mas a menudo que B7);
    // en el exterior A es el cliente de VRAM: el mismo fallo paraba el core para siempre.
    assign a_arready = s_arready & a_arvalid & ~sel_b_ar;
    assign b_arready = s_arready & sel_b_ar;

    wire r_to_b = s_rid[ID_BIT];
    assign a_rid = s_rid; assign a_rdata = s_rdata; assign a_rresp = s_rresp; assign a_rlast = s_rlast;
    assign b_rid = s_rid; assign b_rdata = s_rdata; assign b_rresp = s_rresp; assign b_rlast = s_rlast;
    assign a_rvalid = s_rvalid & ~r_to_b;
    assign b_rvalid = s_rvalid &  r_to_b;
    assign s_rready = r_to_b ? b_rready : a_rready;

    // ------------------------------------------------------------------ escrituras
    localparam [1:0] W_IDLE = 2'd0, W_AW = 2'd1, W_DATA = 2'd2;
    reg [1:0] wst;
    reg       own_b;                 // transaccion en curso del maestro B
    wire aw_acc = s_awvalid & s_awready;
    wire w_acc  = s_wvalid  & s_wready;
    reg [3:0]  w_len_q = 4'd0, w_cnt = 4'd0;   // AWLEN de la rafaga en curso y beats ya aceptados por el esclavo
    reg [15:0] w_idle = 16'd0;                 // ciclos seguidos de la fase de datos sin que el dueno presente WVALID
    reg        w_flush = 1'b0;                 // el dueno ha desaparecido: se cierra la rafaga con beats de WSTRB = 0
    wire       own_wvalid = own_b ? b_wvalid : a_wvalid;
    always @(posedge clk) begin
        if (!aresetn) begin wst <= W_IDLE; own_b <= 1'b0; w_flush <= 1'b0; w_idle <= 16'd0; w_cnt <= 4'd0; w_len_q <= 4'd0; end
        else case (wst)
            W_IDLE: if (a_awvalid)      begin own_b <= 1'b0; wst <= W_AW; end
                    else if (b_awvalid) begin own_b <= 1'b1; wst <= W_AW; end
            W_AW:   if (aw_acc) begin wst <= W_DATA; w_len_q <= s_awlen; w_cnt <= 4'd0; w_idle <= 16'd0; w_flush <= 1'b0; end
                    else if (!(own_b ? b_awvalid : a_awvalid)) wst <= W_IDLE;   // el maestro retiro el AW sin que lo aceptaran: se suelta
            W_DATA: begin
                if (w_acc) begin
                    w_cnt <= w_cnt + 4'd1; w_idle <= 16'd0;
                    if (s_wlast) begin wst <= W_IDLE; w_flush <= 1'b0; end
                end
                else if (W_TMO != 0 && !w_flush && !own_wvalid) begin
                    if (w_idle == W_TMO - 1) w_flush <= 1'b1; else w_idle <= w_idle + 16'd1;
                end
                else if (own_wvalid) w_idle <= 16'd0;
            end
            default: wst <= W_IDLE;
        endcase
    end
    wire aw_pass = (wst == W_AW);
    wire w_pass  = (wst == W_DATA);
    assign s_awvalid = aw_pass & (own_b ? b_awvalid : a_awvalid);
    assign s_awid    = own_b ? b_awid    : a_awid;
    assign s_awaddr  = own_b ? b_awaddr  : a_awaddr;
    assign s_awlen   = own_b ? b_awlen   : a_awlen;
    assign s_awsize  = own_b ? b_awsize  : a_awsize;
    assign s_awburst = own_b ? b_awburst : a_awburst;
    assign s_awlock  = own_b ? b_awlock  : a_awlock;
    assign s_awcache = own_b ? b_awcache : a_awcache;
    assign s_awprot  = own_b ? b_awprot  : a_awprot;
    assign s_awqos   = own_b ? b_awqos   : a_awqos;
    assign a_awready = aw_pass & ~own_b & s_awready;
    assign b_awready = aw_pass &  own_b & s_awready;

    assign s_wvalid = w_pass & (w_flush | own_wvalid);
    assign s_wid    = own_b ? b_wid   : a_wid;
    assign s_wdata  = w_flush ? {DW{1'b0}} : (own_b ? b_wdata : a_wdata);
    assign s_wstrb  = w_flush ? {(DW/8){1'b0}} : (own_b ? b_wstrb : a_wstrb);
    assign s_wlast  = w_flush ? (w_cnt == w_len_q) : (own_b ? b_wlast : a_wlast);
    assign a_wready = w_pass & ~own_b & ~w_flush & s_wready;
    assign b_wready = w_pass &  own_b & ~w_flush & s_wready;

    wire b_to_b = s_bid[ID_BIT];
    assign a_bid = s_bid; assign a_bresp = s_bresp;
    assign b_bid = s_bid; assign b_bresp = s_bresp;
    assign a_bvalid = s_bvalid & ~b_to_b;
    assign b_bvalid = s_bvalid &  b_to_b;
    assign s_bready = b_to_b ? b_bready : a_bready;

    // Solo simulacion: el arbitro rutea R y B por el bit ID_BIT del ID. Un maestro A con ese bit a 1 (p. ej. un v9968_axi_backend con 6 bits
    // de etiqueta en vez de 5) recibiria la mitad de sus R en el maestro B, y al reves; se vio en placa como barras blancas en la VRAM de A.
    // synthesis translate_off
    integer id_errors = 0, n_flush = 0;
    reg     w_flush_d = 1'b0;
    always @(posedge clk) begin w_flush_d <= w_flush; if (w_flush && !w_flush_d) n_flush = n_flush + 1; end
    always @(posedge clk) if (aresetn) begin
        if (a_arvalid && a_arid[ID_BIT])  begin id_errors = id_errors + 1; $display("ERROR axi_arb2w: A usa ARID %0d (bit %0d a 1)", a_arid, ID_BIT); end
        if (a_awvalid && a_awid[ID_BIT])  begin id_errors = id_errors + 1; $display("ERROR axi_arb2w: A usa AWID %0d (bit %0d a 1)", a_awid, ID_BIT); end
        if (b_arvalid && !b_arid[ID_BIT]) begin id_errors = id_errors + 1; $display("ERROR axi_arb2w: B usa ARID %0d (bit %0d a 0)", b_arid, ID_BIT); end
        if (b_awvalid && !b_awid[ID_BIT]) begin id_errors = id_errors + 1; $display("ERROR axi_arb2w: B usa AWID %0d (bit %0d a 0)", b_awid, ID_BIT); end
    end
    // synthesis translate_on
endmodule
