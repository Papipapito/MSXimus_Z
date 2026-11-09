// ============================================================================
// v9990_vram_axi.v — La VRAM de 512 KB del tiny9990 vive en la DDR3 (S_AXI_GP1,
// 32 bits, AXI3, a clk_86) detras de una cache de 64 KB en BRAM, 2 vias.
//
// Lado T9990 (t9990_ram.sv, protocolo del UMA de tnCart): tras cada RAM_REQ el
// core baja RAM_OE_n / RAM_WE_n / RAM_RFSH_n (nivel, hasta ver el ACK) con
// RAM_ADDR[18:0] (byte), RAM_DIN y RAM_DIN_SIZE; aqui se detecta el flanco H->L,
// se sirve y se contesta con RAM_ACK_n = 0 UN ciclo: el core pasa a WAIT_BUSY y
// captura RAM_DOUT en el ciclo en que ACK_n vuelve a 1 (RAM_DOUT queda estable).
//   DIN_SIZE (ram_pkg.sv): 8 = byte en ADDR (dout a cero por arriba); 32 =
//   palabra alineada (ADDR[1:0] ignorado); 32_E / 32_O = los 4 bytes PARES /
//   IMPARES del grupo de 8 bytes alineado en ADDR[18:3] (los dos chips de VRAM
//   del V9990 real, entrelazados): E -> {b6,b4,b2,b0}, O -> {b7,b5,b3,b1};
//   escrituras simetricas (sdram.sv de tnCart, DQM 1010/0101). 16 no se usa.
//   El core mapea VRAM A -> RAM_ADDR = {A[17:0], A[18]}: en la DDR el byte de
//   VRAM A esta en 2*A[17:0] + A[18] (pares = chip 0, impares = chip 1).
//
// Cache: 2 vias x 2^SET_BITS conjuntos x 64 B (SET_BITS 9 = 64 KB, 10 = 128 KB), indice =
// ADDR[SET_BITS+5:6], tag = el resto de ADDR[18:6], LRU de 1 bit por conjunto; datos en dos bancos de 8192 x 32
// ({via, conjunto, grupo}: pares/impares del grupo de 8 B) para leer el grupo
// entero en un ciclo. 20/09: la directa de 32 KB fallaba el 67 % en modo P1
// (cada tile lee 4 B de una fila de patron distinta y las colisiones de indice
// se comian la localidad de las 8 filas) y el stall estiraba el frame a 42 Hz.
// Lecturas: acierto = 4 ciclos; fallo = STALL (la salida `stall` congela los
// enables del core: el T9990 no sabe esperar y un ACK tardio le haria perder
// ranuras) hasta traer la linea con UNA rafaga INCR de 16 x 32 bits en la via
// LRU. Escrituras: write-through (FIFO de 8 hacia la DDR) + actualizacion de la
// linea si esta en cache; sin asignacion. Barrera lectura-tras-escritura: una
// rafaga de lectura no sale hasta drenar la FIFO y recibir todos los B.
// Prefetch secuencial: tras una lectura de la linea L en patron secuencial se
// trae L+1 si no esta (bitmap, tablas de nombres y de sprites leen en orden).
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9990_vram_axi #(
    parameter [31:0] VRAM_BASE = 32'h1030_0000,
    parameter        SET_BITS  = 9            // conjuntos = 2^SET_BITS (9 = 512 -> 64 KB; 10 = 1024 -> 128 KB)
)(
    input  wire        clk,
    input  wire        rst_n,          // dominio VDP
    input  wire        aresetn,        // FCLK_RESET0_N sincronizado a clk

    // T9990 RAM I/F
    input  wire        ram_oe_n,
    input  wire        ram_we_n,
    input  wire        ram_rfsh_n,
    input  wire [18:0] ram_addr,
    input  wire [31:0] ram_din,
    input  wire [2:0]  ram_din_size,
    output reg  [31:0] ram_dout,
    output reg         ram_ack_n,
    output reg         stall,
    input  wire        pf_en,          // 1 = prefetch secuencial de la linea siguiente (ver nota P1)

    // telemetria
    output reg  [31:0] dbg_reads,      // lecturas servidas
    output reg  [31:0] dbg_miss,       // fallos con stall
    output reg  [31:0] dbg_stall,      // ciclos de stall acumulados
    output reg  [31:0] dbg_writes,     // escrituras a la DDR (entradas de la FIFO)

    // AXI3 master 32 bits (S_AXI_GP1)
    output wire [5:0]  M_AWID,
    output reg  [31:0] M_AWADDR,
    output reg  [3:0]  M_AWLEN,
    output wire [2:0]  M_AWSIZE,
    output wire [1:0]  M_AWBURST,
    output wire [1:0]  M_AWLOCK,
    output wire [3:0]  M_AWCACHE,
    output wire [2:0]  M_AWPROT,
    output wire [3:0]  M_AWQOS,
    output reg         M_AWVALID,
    input  wire        M_AWREADY,
    output wire [5:0]  M_WID,
    output reg  [31:0] M_WDATA,
    output reg  [3:0]  M_WSTRB,
    output reg         M_WLAST,
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
    localparam [2:0] SZ_8 = 3'b000, SZ_16 = 3'b001, SZ_32 = 3'b010, SZ_32E = 3'b011, SZ_32O = 3'b111;
    localparam SB = SET_BITS;                 // bits de indice
    localparam TB = 13 - SET_BITS;            // bits de etiqueta (linea = addr[18:6], 13 bits)
    localparam NSETS = (1 << SET_BITS);
    localparam BB = SET_BITS + 4;             // bits de direccion de los bancos {via, conjunto, grupo}

    assign M_AWID = 6'd0;  assign M_WID = 6'd0;  assign M_ARID = 6'd1;
    assign M_AWSIZE = 3'd2; assign M_ARSIZE = 3'd2;          // 4 bytes por beat
    assign M_AWBURST = 2'b01; assign M_ARBURST = 2'b01;      // INCR
    assign M_AWLOCK = 2'b00; assign M_ARLOCK = 2'b00;
    assign M_AWCACHE = 4'b0011; assign M_ARCACHE = 4'b0011;  // normal, bufferable
    assign M_AWPROT = 3'b000; assign M_ARPROT = 3'b000;
    assign M_AWQOS = 4'd0; assign M_ARQOS = 4'd0;
    assign M_ARLEN = 4'd15;                                  // 16 beats = 64 B
    assign M_BREADY = 1'b1;
    assign M_RREADY = 1'b1;

    // ------------------------------------------------------------------------
    // Cache: tags + validez + LRU (distribuidos) y dos bancos de datos (BRAM)
    // ------------------------------------------------------------------------
    // Metadatos en LUTRAM (memoria distribuida), 20/09 noche: {valido, etiqueta} por via en DOS
    // copias (una por puerto de lectura: la consulta en q_idx y la comprobacion del prefetch en
    // n_line) y el LRU (1 bit por conjunto; 1 = la via 1 fue la ultima usada -> victima = via 0).
    // Un solo puerto de escritura cada uno. Los vectores planos de 1024 bits con indice dinamico
    // costaban 13.500 LUT (build 8: 103 % del chip). Al no tener reset, un BARRIDO (flush) de
    // NSETS ciclos los invalida tras cada reset, con el core congelado (stall) mientras dura.
    (* ram_style = "distributed" *) reg [TB:0] metaq0 [0:NSETS-1];
    (* ram_style = "distributed" *) reg [TB:0] metaq1 [0:NSETS-1];
    (* ram_style = "distributed" *) reg [TB:0] metan0 [0:NSETS-1];
    (* ram_style = "distributed" *) reg [TB:0] metan1 [0:NSETS-1];
    (* ram_style = "distributed" *) reg        lrum   [0:NSETS-1];
    reg           mw_en0, mw_en1;             // escritura de metadatos (por via)
    reg  [SB-1:0] mw_idx;
    reg  [TB:0]   mw_val;
    reg           lw_en;                      // escritura del LRU
    reg  [SB-1:0] lw_idx;
    reg           lw_val;
    always @(posedge clk) begin
        if (mw_en0) begin metaq0[mw_idx] <= mw_val; metan0[mw_idx] <= mw_val; end
        if (mw_en1) begin metaq1[mw_idx] <= mw_val; metan1[mw_idx] <= mw_val; end
        if (lw_en)  lrum[lw_idx] <= lw_val;
    end
    reg           flush = 1'b1;               // barrido de metadatos en curso (tambien al configurar)
    reg  [SB-1:0] flush_idx = {SB{1'b0}};
    (* ram_style = "block" *) reg [31:0] bank0 [0:(1<<BB)-1];   // bytes 0-3 del grupo, {via, conjunto, grupo}
    (* ram_style = "block" *) reg [31:0] bank1 [0:(1<<BB)-1];   // bytes 4-7 del grupo

    // puerto A (core): lectura sincrona + escritura por bytes (write-through)
    reg  [BB-1:0] a_addr;
    reg  [3:0]  a_we0, a_we1;
    reg  [31:0] a_wd0, a_wd1;
    reg  [31:0] a_rd0, a_rd1;
    integer li;
    always @(posedge clk) begin
        for (li = 0; li < 4; li = li + 1)
            if (a_we0[li]) bank0[a_addr][li*8 +: 8] <= a_wd0[li*8 +: 8];
        a_rd0 <= bank0[a_addr];
    end
    always @(posedge clk) begin
        for (li = 0; li < 4; li = li + 1)
            if (a_we1[li]) bank1[a_addr][li*8 +: 8] <= a_wd1[li*8 +: 8];
        a_rd1 <= bank1[a_addr];
    end
    // puerto B (relleno AXI): palabras completas
    reg         b_we0, b_we1;
    reg  [BB-1:0] b_addr;
    reg  [31:0] b_wd;
    always @(posedge clk) if (b_we0) bank0[b_addr] <= b_wd;
    always @(posedge clk) if (b_we1) bank1[b_addr] <= b_wd;

    // ------------------------------------------------------------------------
    // Peticion del core: flanco H->L de OE/WE/RFSH
    // ------------------------------------------------------------------------
    reg oe_q = 1'b1, we_q = 1'b1, rf_q = 1'b1;
    always @(posedge clk) begin oe_q <= ram_oe_n; we_q <= ram_we_n; rf_q <= ram_rfsh_n; end
    wire det_rd = oe_q && !ram_oe_n;
    wire det_wr = we_q && !ram_we_n;
    wire det_rf = rf_q && !ram_rfsh_n;

    reg  [18:0] q_addr;
    reg  [31:0] q_din;
    reg  [2:0]  q_size;
    reg         q_rd, q_wr;
    wire [SB-1:0] q_idx = q_addr[SB+5:6];
    wire [TB-1:0] q_tag = q_addr[18:SB+6];
    wire [12:0] q_line = q_addr[18:6];
    wire [TB:0] mq0 = metaq0[q_idx];
    wire [TB:0] mq1 = metaq1[q_idx];
    wire        q_hit0 = mq0[TB] && (mq0[TB-1:0] == q_tag);
    wire        q_hit1 = mq1[TB] && (mq1[TB-1:0] == q_tag);
    wire        q_hit  = q_hit0 || q_hit1;
    wire        q_way  = q_hit1;           // via del acierto

    // relleno en curso (demanda o prefetch)
    reg         fill_busy;
    reg  [12:0] fill_line;
    reg         fill_way;
    reg         fill_done;                 // pulso: linea completa y tag escrito
    wire        q_in_fill = fill_busy && (fill_line == q_line);
    // linea siguiente (para el prefetch): ya en cache?
    wire [12:0] n_line = q_line + 13'd1;
    wire [TB:0] mn0 = metan0[n_line[SB-1:0]];
    wire [TB:0] mn1 = metan1[n_line[SB-1:0]];
    wire        n_hit  = (mn0[TB] && (mn0[TB-1:0] == n_line[12:SB])) ||
                         (mn1[TB] && (mn1[TB-1:0] == n_line[12:SB]));
    // patron secuencial: esta lectura cae en la misma linea que la anterior o en
    // la siguiente (bitmap, patrones, tablas); los accesos sueltos no prefetchean
    reg  [12:0] last_line;
    wire        seq_ok = (q_line == last_line) || (q_line == last_line + 13'd1);

    // FIFO de escrituras hacia la DDR: {len2, waddr[16:0], d0, s0, d1, s1}
    reg  [89:0] wf [0:7];
    reg  [2:0]  wf_wp = 3'd0, wf_rp = 3'd0;
    reg  [3:0]  wf_cnt = 4'd0;
    wire        wf_full  = wf_cnt[3];
    wire        wf_empty = (wf_cnt == 4'd0);
    reg         wf_push, wf_pop;
    reg  [89:0] wf_din;
    always @(posedge clk) begin
        if (!rst_n) begin
            wf_wp <= 3'd0; wf_rp <= 3'd0; wf_cnt <= 4'd0;
        end else begin
            if (wf_push) begin wf[wf_wp] <= wf_din; wf_wp <= wf_wp + 3'd1; end
            if (wf_pop)  wf_rp <= wf_rp + 3'd1;
            wf_cnt <= wf_cnt + {3'd0, wf_push} - {3'd0, wf_pop};
        end
    end
    wire [89:0] wf_head = wf[wf_rp];

    // ---- descomposicion de una escritura en los dos bancos / beats AXI ----
    // grupo de 8 B: bank0 = bytes 0-3, bank1 = bytes 4-7
    reg [31:0] w_d0, w_d1;
    reg [3:0]  w_s0, w_s1;
    always @(*) begin
        w_d0 = q_din; w_d1 = q_din; w_s0 = 4'd0; w_s1 = 4'd0;
        case (q_size)
            SZ_8: begin
                w_d0 = {4{q_din[7:0]}}; w_d1 = {4{q_din[7:0]}};
                if (q_addr[2]) w_s1 = 4'b0001 << q_addr[1:0]; else w_s0 = 4'b0001 << q_addr[1:0];
            end
            SZ_16: begin
                w_d0 = {2{q_din[15:0]}}; w_d1 = {2{q_din[15:0]}};
                if (q_addr[2]) w_s1 = q_addr[1] ? 4'b1100 : 4'b0011; else w_s0 = q_addr[1] ? 4'b1100 : 4'b0011;
            end
            SZ_32E: begin
                w_d0 = {8'd0, q_din[15:8], 8'd0, q_din[7:0]};   w_s0 = 4'b0101;
                w_d1 = {8'd0, q_din[31:24], 8'd0, q_din[23:16]}; w_s1 = 4'b0101;
            end
            SZ_32O: begin
                w_d0 = {q_din[15:8], 8'd0, q_din[7:0], 8'd0};   w_s0 = 4'b1010;
                w_d1 = {q_din[31:24], 8'd0, q_din[23:16], 8'd0}; w_s1 = 4'b1010;
            end
            default: begin  // SZ_32
                if (q_addr[2]) w_s1 = 4'b1111; else w_s0 = 4'b1111;
            end
        endcase
    end
    wire w_two = (q_size == SZ_32E) || (q_size == SZ_32O);
    // palabra AXI unica (tamanos 8/16/32): la del banco que toca
    wire [31:0] w_one_d = q_addr[2] ? w_d1 : w_d0;
    wire [3:0]  w_one_s = q_addr[2] ? w_s1 : w_s0;

    // ---- ensamblado de la lectura (grupo {a_rd1, a_rd0}) ----
    wire [31:0] r_word = q_addr[2] ? a_rd1 : a_rd0;          // palabra del banco que toca
    wire [7:0]  r_byte = r_word >> (q_addr[1:0] * 8);         // truncado a 8 bits
    wire [15:0] r_half = q_addr[1] ? r_word[31:16] : r_word[15:0];
    reg [31:0] r_asm;
    always @(*) begin
        case (q_size)
            SZ_8:   r_asm = {24'd0, r_byte};
            SZ_16:  r_asm = {16'd0, r_half};
            SZ_32E: r_asm = {a_rd1[23:16], a_rd1[7:0], a_rd0[23:16], a_rd0[7:0]};
            SZ_32O: r_asm = {a_rd1[31:24], a_rd1[15:8], a_rd0[31:24], a_rd0[15:8]};
            default: r_asm = r_word;
        endcase
    end

    // ------------------------------------------------------------------------
    // FSM del lado core
    // ------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0, S_LOOKUP = 3'd1, S_RDATA = 3'd2, S_ACK = 3'd3,
                     S_WAITFILL = 3'd4, S_WAITWF = 3'd5, S_RWAIT = 3'd6;
    reg [2:0]  st;
    reg        demand_req;                 // fallo de demanda pendiente para el motor AXI
    reg [12:0] demand_line;
    reg        pf_req;                     // prefetch pendiente
    reg [12:0] pf_line;
    reg        lru_set;                    // pulso: actualizar lru[q_idx] con lru_val
    reg        lru_val;

    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; ram_ack_n <= 1'b1; ram_dout <= 32'd0; stall <= 1'b0;
            a_we0 <= 4'd0; a_we1 <= 4'd0; a_addr <= {BB{1'b0}};
            q_rd <= 1'b0; q_wr <= 1'b0; q_addr <= 19'd0; q_din <= 32'd0; q_size <= 3'd0;
            demand_req <= 1'b0; demand_line <= 13'd0;
            pf_req <= 1'b0; pf_line <= 13'd0; last_line <= 13'h1FFF;
            wf_push <= 1'b0; wf_din <= 90'd0; lru_set <= 1'b0; lru_val <= 1'b0;
            dbg_reads <= 32'd0; dbg_miss <= 32'd0; dbg_stall <= 32'd0; dbg_writes <= 32'd0;
        end else begin
            a_we0 <= 4'd0; a_we1 <= 4'd0;
            wf_push <= 1'b0; lru_set <= 1'b0;
            if (fill_done && demand_req && fill_line == demand_line) demand_req <= 1'b0;
            if (fill_done && pf_req && fill_line == pf_line) pf_req <= 1'b0;
            if (stall) dbg_stall <= dbg_stall + 32'd1;
            case (st)
            S_IDLE: begin
                ram_ack_n <= 1'b1;
                stall <= flush;                    // barrido de metadatos: core congelado, sin peticiones
                if (!flush && (det_rd || det_wr || det_rf)) begin
                    q_addr <= ram_addr; q_din <= ram_din; q_size <= ram_din_size;
                    q_rd <= det_rd && !det_wr; q_wr <= det_wr;
                    st <= (det_rd || det_wr) ? S_LOOKUP : S_RDATA;   // refresco: ACK sin mas
                end
            end
            S_LOOKUP: begin
                a_addr <= {q_way, q_idx, q_addr[5:3]};
                if (q_in_fill) begin
                    // la linea esta llegando (prefetch): esperar a que acabe
                    stall <= 1'b1; st <= S_WAITFILL;
                end
                else if (q_rd) begin
                    if (q_hit) begin
                        lru_set <= 1'b1; lru_val <= q_way;
                        st <= S_RWAIT;                   // a_addr -> bancos -> a_rd* (2 ciclos)
                    end else begin
                        demand_req <= 1'b1; demand_line <= q_line;
                        stall <= 1'b1; dbg_miss <= dbg_miss + 32'd1;
                        st <= S_WAITFILL;
                    end
                end
                else begin  // escritura: write-through + actualizacion si acierta
                    if (wf_full) begin
                        stall <= 1'b1; st <= S_WAITWF;
                    end else begin
                        if (q_hit) begin a_we0 <= w_s0; a_we1 <= w_s1; a_wd0 <= w_d0; a_wd1 <= w_d1; end
                        wf_push <= 1'b1;
                        wf_din  <= w_two ? {1'b1, q_addr[18:3], 1'b0, w_d0, w_s0, w_d1, w_s1}
                                         : {1'b0, q_addr[18:2],       w_one_d, w_one_s, 32'd0, 4'd0};
                        dbg_writes <= dbg_writes + 32'd1;
                        st <= S_RDATA;
                    end
                end
            end
            S_WAITFILL: begin
                // vuelve a mirar cuando el relleno de ESTA linea (de demanda o
                // el prefetch que la traia) ha terminado
                if (fill_done && fill_line == q_line) begin
                    stall <= 1'b0; st <= S_LOOKUP;
                end
            end
            S_WAITWF: begin
                if (!wf_full) begin stall <= 1'b0; st <= S_LOOKUP; end
            end
            S_RWAIT: st <= S_RDATA;                      // los bancos entregan a_rd*
            S_RDATA: begin
                // lectura: el dato de los bancos ya esta en a_rd*
                if (q_rd) begin
                    ram_dout <= r_asm; dbg_reads <= dbg_reads + 32'd1;
                    last_line <= q_line;
                    // prefetch de la linea siguiente: solo en patron secuencial, si
                    // no esta ya en cache y nadie la esta trayendo
                    if (pf_en && seq_ok && !n_hit && !fill_busy && !pf_req && !demand_req) begin
                        pf_req  <= 1'b1;
                        pf_line <= n_line;
                    end
                end
                ram_ack_n <= 1'b0;
                st <= S_ACK;
            end
            S_ACK: begin
                ram_ack_n <= 1'b1;
                q_rd <= 1'b0; q_wr <= 1'b0;
                st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Motor AXI: escrituras (FIFO -> AW/W, B contadas) y rellenos (AR/R)
    // ------------------------------------------------------------------------
    reg [3:0]  wr_outstanding;             // AW aceptados sin B
    wire       aw_acc = M_AWVALID && M_AWREADY;
    wire       w_acc  = M_WVALID  && M_WREADY;
    wire       b_acc  = M_BVALID  && M_BREADY;
    wire       ar_acc = M_ARVALID && M_ARREADY;
    wire       r_acc  = M_RVALID  && M_RREADY;

    localparam [1:0] W_IDLE = 2'd0, W_AW = 2'd1, W_D0 = 2'd2, W_D1 = 2'd3;
    reg [1:0]  wst;
    reg [89:0] wcur;
    wire       wcur_two = wcur[89];
    always @(posedge clk) begin
        if (!aresetn) begin
            wst <= W_IDLE; M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_WLAST <= 1'b0;
            M_AWADDR <= 32'd0; M_AWLEN <= 4'd0; M_WDATA <= 32'd0; M_WSTRB <= 4'd0;
            wf_pop <= 1'b0; wr_outstanding <= 4'd0; wcur <= 90'd0;
        end else begin
            wf_pop <= 1'b0;
            wr_outstanding <= wr_outstanding + {3'd0, aw_acc} - {3'd0, b_acc};
            case (wst)
            W_IDLE: if (!wf_empty && !wr_outstanding[3]) begin
                wcur <= wf_head; wf_pop <= 1'b1;
                M_AWADDR  <= VRAM_BASE + {13'd0, wf_head[88:72], 2'b00};
                M_AWLEN   <= wf_head[89] ? 4'd1 : 4'd0;
                M_AWVALID <= 1'b1;
                wst <= W_AW;
            end
            W_AW: if (aw_acc) begin
                M_AWVALID <= 1'b0;
                M_WDATA <= wcur[71:40]; M_WSTRB <= wcur[39:36];
                M_WLAST <= !wcur_two; M_WVALID <= 1'b1;
                wst <= W_D0;
            end
            W_D0: if (w_acc) begin
                if (wcur_two) begin
                    M_WDATA <= wcur[35:4]; M_WSTRB <= wcur[3:0]; M_WLAST <= 1'b1;
                    wst <= W_D1;
                end else begin
                    M_WVALID <= 1'b0; M_WLAST <= 1'b0; wst <= W_IDLE;
                end
            end
            W_D1: if (w_acc) begin M_WVALID <= 1'b0; M_WLAST <= 1'b0; wst <= W_IDLE; end
            endcase
        end
    end

    // rellenos: demanda antes que prefetch; barrera de escrituras; via = LRU
    localparam [1:0] R_IDLE = 2'd0, R_AR = 2'd1, R_DATA = 2'd2;
    reg [1:0] rst_st;
    reg [3:0] beat;
    wire wr_quiet = wf_empty && (wr_outstanding == 4'd0) && (wst == W_IDLE);
    wire [12:0] req_line = demand_req ? demand_line : pf_line;
    wire        req_way  = ~lrum[req_line[SB-1:0]];  // victima: la via que NO fue la ultima usada
    always @(posedge clk) begin
        if (!aresetn) begin
            rst_st <= R_IDLE; M_ARVALID <= 1'b0; M_ARADDR <= 32'd0;
            fill_busy <= 1'b0; fill_line <= 13'd0; fill_way <= 1'b0; fill_done <= 1'b0; beat <= 4'd0;
            b_we0 <= 1'b0; b_we1 <= 1'b0; b_addr <= {BB{1'b0}}; b_wd <= 32'd0;
            mw_en0 <= 1'b0; mw_en1 <= 1'b0; mw_idx <= {SB{1'b0}}; mw_val <= {(TB+1){1'b0}};
            lw_en <= 1'b0; lw_idx <= {SB{1'b0}}; lw_val <= 1'b0;
            flush <= 1'b1; flush_idx <= {SB{1'b0}};
        end else begin
            fill_done <= 1'b0; b_we0 <= 1'b0; b_we1 <= 1'b0;
            mw_en0 <= 1'b0; mw_en1 <= 1'b0; lw_en <= 1'b0;
            if (!rst_n) begin flush <= 1'b1; flush_idx <= {SB{1'b0}}; end
            else if (flush) begin
                // barrido: invalida las dos vias y pone el LRU a 0, un conjunto por ciclo
                mw_en0 <= 1'b1; mw_en1 <= 1'b1; mw_idx <= flush_idx; mw_val <= {(TB+1){1'b0}};
                lw_en <= 1'b1; lw_idx <= flush_idx; lw_val <= 1'b0;
                flush_idx <= flush_idx + 1'b1;
                if (&flush_idx) flush <= 1'b0;
            end
            // LRU por acierto (si coincide con el arranque de un relleno, gana el relleno: abajo)
            if (!flush && lru_set) begin lw_en <= 1'b1; lw_idx <= q_idx; lw_val <= lru_val; end
            case (rst_st)
            // !fill_done: el ciclo siguiente a acabar un relleno la peticion que lo
            // pidio aun no se ha borrado (lo hace la FSM del core al ver fill_done);
            // sin esta guarda cada linea se traia DOS veces (banco: 130 rafagas / 64 lineas)
            R_IDLE: if (!flush && (demand_req || pf_req) && wr_quiet && !fill_done) begin
                fill_line <= req_line;
                fill_way  <= req_way;
                fill_busy <= 1'b1;
                // invalidar la victima (su banco se va a sobreescribir) y marcarla como ultima usada
                mw_en0 <= ~req_way; mw_en1 <= req_way; mw_idx <= req_line[SB-1:0]; mw_val <= {(TB+1){1'b0}};
                lw_en <= 1'b1; lw_idx <= req_line[SB-1:0]; lw_val <= req_way;
                M_ARADDR  <= VRAM_BASE + {13'd0, req_line, 6'd0};
                M_ARVALID <= 1'b1;
                beat <= 4'd0;
                rst_st <= R_AR;
            end
            R_AR: if (ar_acc) begin M_ARVALID <= 1'b0; rst_st <= R_DATA; end
            R_DATA: if (r_acc) begin
                b_addr <= {fill_way, fill_line[SB-1:0], beat[3:1]};
                b_wd   <= M_RDATA;
                b_we0  <= ~beat[0];
                b_we1  <=  beat[0];
                beat   <= beat + 4'd1;
                if (M_RLAST) begin
                    // etiqueta + valido de la linea recien traida (el LRU ya se puso al arrancar)
                    mw_en0 <= ~fill_way; mw_en1 <= fill_way; mw_idx <= fill_line[SB-1:0];
                    mw_val <= {1'b1, fill_line[12:SB]};
                    fill_busy <= 1'b0;
                    fill_done <= 1'b1;
                    rst_st <= R_IDLE;
                end
            end
            default: rst_st <= R_IDLE;
            endcase
        end
    end
endmodule
