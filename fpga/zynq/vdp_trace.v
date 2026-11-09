// ============================================================================
//  vdp_trace.v — trazador de I/O del V9968 para la ZYNQ (caza del marcador de
//  Xevious, 15/09): anillo de 1024 eventos en BRAM con lo que el Z80 escribe y
//  LEE en los puertos de control del VDP, los flancos de la INT y el VS, cada uno
//  con la linea de pantalla y la posicion horizontal. El buzon (dbg_mailbox_axi)
//  lo vuelca a la DDR cuando la captura ha terminado; tools/vdptrace.tcl lo arma
//  y lo decodifica.
//
//  Evento (32 bits): {evt[2:0], line[8:0], data[7:0], hpos[11:0]}
//    evt 0 = escritura puerto 1 (99h)      data = byte escrito
//        1 = lectura  puerto 1 (99h)      data = byte DEVUELTO al Z80 (S#n)
//        2 = escritura puerto 3 (9Bh)     data = byte escrito (registro indirecto)
//        3 = INT activada (int_n baja)    data = 0
//        4 = INT desactivada (int_n sube) data = 0
//        5 = VS: arranque de cuadro       data = 0   (line vuelve a 0 aqui)
//        6 = escritura puerto 0 (98h)     data = byte  (solo si TRACE_VRAM=1)
//        7 = evento auxiliar (aux_tgl)    data = aux_data (17/09: byte leido por el Z80 del UART del ESP, puerto 06h)
//    line = lineas HS contadas desde el VS (0..511); hpos = ciclos clk/2 desde el HS.
//  Dominio: clk = reloj del VDP (clk_86). La lectura del anillo (puerto B de la
//  BRAM) va en el reloj del buzon; arm/full cruzan con 2 FF.
// ============================================================================
module vdp_trace #(
    parameter TRACE_VRAM = 0,
    parameter CIRC       = 0,         // 1 = anillo circular que solo se para con frz_in (TR, depuracion)
    parameter R2TRIG     = 0,         // 1 = (con CIRC) tambien se para al escribir R#2 con un valor inesperado
    parameter R2LATE     = 0          // 1 = (con CIRC) se para 300 eventos despues de una escritura de R#2 fuera de su ventana (lineas 80..430: Aleste
                                      //     solo lo escribe en la interrupcion de linea ~58 y en la de cuadro >= 463): fotograma roto por ISR retrasada
)(
    input  wire        clk,             // clk_86 (dominio del V9968 y del glue)
    input  wire        rst_n,
    // bus CPU -> V9968 (el mismo que ve el core)
    input  wire [2:0]  bus_address,
    input  wire        bus_write,
    input  wire        bus_valid,
    input  wire        bus_ready,
    input  wire [7:0]  bus_wdata,
    input  wire [7:0]  bus_rdata,
    input  wire        bus_rdata_en,
    input  wire        int_n,
    input  wire        hs,              // activo alto (convencion V9968)
    input  wire        vs,
    // evento auxiliar de otro dominio: cada cambio de aux_tgl registra {7, aux_data} (aux_data estable antes del toggle)
    input  wire        aux_tgl,
    input  wire [7:0]  aux_data,
    // control / volcado (dominio del buzon)
    input  wire        rd_clk,
    input  wire        arm,             // 0->1 = vaciar y capturar hasta llenar
    input  wire        frz_in,          // CIRC: congelar el anillo
    output wire [9:0]  wp_o,            // CIRC: posicion de escritura (estable con el anillo congelado)
    input  wire        aux_only,        // 1 = solo eventos auxiliares (UART): ignora el VDP (17/09)
    input  wire        no_vram,         // 1 = no anotar las escrituras/lecturas del puerto 0 (98h) aunque TRACE_VRAM = 1 (TR, 04/11: 1024 eventos = decenas de cuadros)
    output wire        full,            // captura terminada (1024 eventos)
    input  wire [9:0]  rd_addr,
    output reg  [31:0] rd_data
);
    // ---- arm: cruce al dominio del VDP + deteccion de flanco ----
    reg [2:0] arm_s = 3'd0;
    always @(posedge clk) arm_s <= {arm_s[1:0], arm};
    reg [1:0] auxo_s = 2'd0;
    always @(posedge clk) auxo_s <= {auxo_s[0], aux_only};
    reg [1:0] novr_s = 2'd0;
    always @(posedge clk) novr_s <= {novr_s[0], no_vram};
    wire arm_edge = arm_s[1] && !arm_s[2];

    // ---- linea y posicion horizontal ----
    reg        hs_d = 1'b0, vs_d = 1'b0, int_d = 1'b1;
    reg [8:0]  line = 9'd0;
    reg [12:0] hcnt = 13'd0;
    wire hs_edge = hs && !hs_d;
    wire vs_edge = vs && !vs_d;
    always @(posedge clk) begin
        hs_d  <= hs;
        vs_d  <= vs;
        int_d <= int_n;
        if (vs_edge)      begin line <= 9'd0; end
        else if (hs_edge) begin line <= line + 9'd1; end
        if (hs_edge) hcnt <= 13'd0; else hcnt <= hcnt + 13'd1;
    end

    // ---- eventos ----
    wire acc     = bus_valid && bus_ready;
    wire ev_w1   = acc && bus_write && bus_address == 3'd1;
    wire ev_w3   = acc && bus_write && bus_address == 3'd3;
    wire ev_w0   = TRACE_VRAM && !novr_s[1] && acc && bus_write && bus_address == 3'd0;
    // la lectura de puerto 1 entrega el dato el mismo ciclo (ff_bus_rdata_en); lo capturamos
    // en el pulso de rdata_en que sigue a una lectura de puerto 1
    reg        rd1_pend = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) rd1_pend <= 1'b0;
        else if (acc && !bus_write && bus_address == 3'd1) rd1_pend <= 1'b1;
        else if (bus_rdata_en) rd1_pend <= 1'b0;
    end
    // TR (depuracion): lectura del puerto 0 (98h): se registra como evt 7 el byte que el VDP devuelve (solo si TRACE_VRAM)
    reg        rd0_pend = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) rd0_pend <= 1'b0;
        else if (acc && !bus_write && bus_address == 3'd0) rd0_pend <= 1'b1;
        else if (bus_rdata_en) rd0_pend <= 1'b0;
    end
    wire ev_r0   = TRACE_VRAM && !novr_s[1] && bus_rdata_en && rd0_pend;
    wire ev_r1   = bus_rdata_en && rd1_pend;
    wire ev_int0 = !int_n && int_d;
    wire ev_int1 = int_n && !int_d;
    reg [2:0] aux_s = 3'd0;
    always @(posedge clk) aux_s <= {aux_s[1:0], aux_tgl};
    wire ev_aux = aux_s[2] ^ aux_s[1];

    reg [2:0]  evt;
    reg [7:0]  dat;
    reg        hit;
    always @(*) begin
        hit = 1'b1; evt = 3'd7; dat = 8'd0;
        if      (ev_aux)  begin evt = 3'd7; dat = aux_data; end       // prioridad: un byte del UART no se puede perder
        else if (auxo_s[1]) hit = 1'b0;                                      // solo UART
        else if (ev_w1)   begin evt = 3'd0; dat = bus_wdata; end
        else if (ev_r1)   begin evt = 3'd1; dat = bus_rdata; end
        else if (ev_w3)   begin evt = 3'd2; dat = bus_wdata; end
        else if (ev_int0) begin evt = 3'd3; end
        else if (ev_int1) begin evt = 3'd4; end
        else if (vs_edge) begin evt = 3'd5; end
        else if (ev_w0)   begin evt = 3'd6; dat = bus_wdata; end
        else if (ev_r0)   begin evt = 3'd7; dat = bus_rdata; end
        else hit = 1'b0;
    end

    // ---- anillo ----
    reg [31:0] mem [0:1023];
    // TR (Aleste): congelar al escribir R#2 (pareja X,82h) con un valor distinto de los que usa el juego (1Fh de la interrupcion de linea, 3Fh de la de cuadro)
    reg [7:0]  last_w1 = 8'd0;
    always @(posedge clk) if (!rst_n || arm_edge) last_w1 <= 8'd0; else if (ev_w1) last_w1 <= bus_wdata;
    wire       r2_bad = ev_w1 && (bus_wdata == 8'h82) && (last_w1 != 8'h1F) && (last_w1 != 8'h3F) && (R2TRIG != 0);
    // TR (Aleste, 04/11): escritura de R#2 fuera de su ventana -> se para 300 eventos despues (para ver el resto del cuadro)
    wire       r2_late_hit = ev_w1 && (bus_wdata == 8'h82) && (line > 9'd80) && (line < 9'd430) && (R2LATE != 0);
    reg        r2l_arm = 1'b0;
    reg [8:0]  r2l_cnt = 9'd0;
    wire       r2_late = r2l_arm && (r2l_cnt == 9'd300);
    reg [6:0]  r1c = 7'd0;                // lecturas seguidas del puerto 1 (las INT/VS no cuentan ni cortan)
    wire       r1_run = (r1c == 7'd60);
    always @(posedge clk) begin
        if (arm_edge) r1c <= 7'd0;
        else if (hit && !(ev_int0 || ev_int1 || vs_edge)) begin if (ev_r1) begin if (r1c != 7'd127) r1c <= r1c + 7'd1; end else r1c <= 7'd0; end
    end
    reg [10:0] wp = 11'd0;              // bit 10 = lleno / parado (nace VACIO: sin armar no hay volcado)
    reg        run = 1'b0;
    reg [1:0] frz_s = 2'd0;
    always @(posedge clk) frz_s <= {frz_s[0], frz_in};
    assign wp_o = wp[9:0];
    always @(posedge clk) begin
        if (arm_edge) begin r2l_arm <= 1'b0; r2l_cnt <= 9'd0; end
        else if (run && r2_late_hit && !r2l_arm) r2l_arm <= 1'b1;
        else if (run && r2l_arm && hit && r2l_cnt != 9'd300) r2l_cnt <= r2l_cnt + 9'd1;
    end
    always @(posedge clk) begin
        if (arm_edge) begin wp <= 11'd0; run <= 1'b1; end
        else if (CIRC && run && (frz_s[1] || r1_run || r2_bad || r2_late)) begin run <= 1'b0; wp[10] <= 1'b1; end   // + disparo: 60 lecturas seguidas del puerto 99h (bucle de espera del estado)
        else if (run && hit) begin
            mem[wp[9:0]] <= {evt, line, dat, hcnt[12:1]};
            if (CIRC) wp[9:0] <= wp[9:0] + 10'd1;
            else begin
                wp <= wp + 11'd1;
                if (wp == 11'd1023) run <= 1'b0;
            end
        end
    end
    // ---- lado del buzon ----
    reg [2:0] full_s = 3'd0;
    always @(posedge rd_clk) full_s <= {full_s[1:0], wp[10]};
    assign full = full_s[2];
    always @(posedge rd_clk) rd_data <= mem[rd_addr];
endmodule
