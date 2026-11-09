// ============================================================================
// v9990_arm_port.v — Inyector de accesos del ARM a los puertos 60h-6Fh del V9990
// (clk_54m). Se intercala entre el decode del T80 (top_zynq.v) y el v9990_cpu_glue:
// el companion deja entradas de 16 bits en un anillo de la DDR (dbg_mailbox_axi.v las
// pasa por una FIFO) y este modulo las convierte en ciclos de chip-select iguales a los
// del Z80, para que el companion maneje el V9990 mientras el Z80 juega en el V9968
// (modos de ventana del compositor).
//
// Entrada (16 bits): [15:14] tipo, [11:8] puerto P#0..P#15 (= direccion 60h+puerto), [7:0] dato
//   tipo 0 = escribir dato en el puerto
//   tipo 1 = NOP (relleno)
//   tipo 2 = esperar hasta que (leer puerto) & dato == 0   (p. ej. P#5, 01h: motor libre, CE = 0)
//   tipo 3 = esperar hasta que (leer puerto) & dato != 0   (p. ej. P#5, 80h: TR)
//   Las esperas tienen tope TMO (~19,4 ms): al vencer se sigue y se cuenta en `tmo` (satura en 15).
//
// Propiedad `own` (0 = Z80, 1 = ARM):
//  - pasa a 1 solo con `en` y `allow`, una entrada disponible, el Z80 sin ciclo 60h-6Fh (IDLEN
//    ciclos seguidos), el WAIT del glue en reposo y fuera de la ventana POST de un traspaso;
//  - vuelve a 0 al acabar la entrada en curso si el Z80 pide, si allow o en bajan, o si no llega
//    otra entrada en LINGER ciclos. allow = 0 NO vacia la FIFO: las entradas esperan;
//  - el Z80 tiene prioridad: si pide con own = 1 se le retiene con su WAIT (wait_z_n) hasta que
//    own = 0 y, tras devolverle el bus, POST ciclos mas, para que el glue vea su chip-select y
//    suba su propio WAIT antes de que el T80 muestree (ni un OUT/IN del Z80 se pierde);
//  - mientras own = 1 el WAIT del glue (ciclos del ARM) no llega al Z80.
//
// Ciclo del ARM: chip-select bajo con mode/cdo estables al menos MINC ciclos y hasta que el WAIT
// del glue (wait_n, ya en 54 M) este alto; las lecturas toman `cdi` (cdi_r del glue) al final;
// luego chip-select alto al menos GAP ciclos antes del siguiente (el glue rearma `served` con 3
// muestras inactivas a 86 MHz tras el 2FF).
// La mezcla Z80/ARM esta REGISTRADA aqui (un FF por senal, como antes los v99_*_r del top): hacia
// clk_86 no cruza logica combinacional.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9990_arm_port #(
    parameter [20:0] TMO    = 21'd1048575,   // tope de una espera (ciclos de 54 M, ~19,4 ms)
    parameter [4:0]  IDLEN  = 5'd8,          // ciclos de Z80 quieto antes de tomar el bus
    parameter [4:0]  POST   = 5'd8,          // ciclos de retencion del Z80 tras devolverle el bus
    parameter [5:0]  LINGER = 6'd24,         // ciclos esperando otra entrada antes de soltar el bus
    parameter [5:0]  MINC   = 6'd14,         // minimo de ciclos de un acceso con el chip-select bajo
    parameter [3:0]  GAP    = 4'd6           // minimo con el chip-select alto entre accesos
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,                   // control del ARM (V9_BASE bit 31)
    input  wire        allow,                // 0 = el ARM no puede tomar el bus (la FIFO espera); sincronizada por el que la conecte
    // FIFO del mailbox
    input  wire [15:0] ent,
    input  wire        ent_v,
    output wire        pop,                  // consume `ent` (combinacional, un ciclo)
    // lado Z80 (decode del top, combinacional) y senales del bus
    input  wire        z_csw_n,
    input  wire        z_csr_n,
    input  wire [3:0]  z_mode,
    input  wire [7:0]  z_cdo,
    // lado glue/V9990 (registradas)
    output reg         o_csw_n,
    output reg         o_csr_n,
    output reg  [3:0]  o_mode,
    output reg  [7:0]  o_cdo,
    input  wire        wait_n,               // WAIT del glue ya en 54 M
    input  wire [7:0]  cdi,                  // dato de lectura del glue
    output wire        wait_z_n,             // WAIT hacia el T80 (sustituye a wait_n)
    // telemetria
    output wire        own,
    output wire        busy,
    output wire [3:0]  tmo
);
    localparam [2:0] S_IDLE = 3'd0, S_LOAD = 3'd1, S_EXEC = 3'd2, S_CYC = 3'd3, S_GAP = 3'd4;
    reg [2:0]  st = S_IDLE;
    reg        own_r = 1'b0;
    reg [15:0] cur = 16'd0;
    reg        a_csw_n = 1'b1, a_csr_n = 1'b1;
    reg [3:0]  a_mode = 4'd0;
    reg [7:0]  a_cdo = 8'd0;
    reg [7:0]  rdv = 8'd0;
    reg [12:0] cnt = 13'd0;
    reg [20:0] tcnt = 21'd0;
    reg [4:0]  idle_cnt = 5'd0;
    reg [4:0]  post_cnt = 5'd0;
    reg [5:0]  lng = 6'd0;
    reg [3:0]  tmo_c = 4'd0;

    wire z_any = !z_csw_n || !z_csr_n;
    wire [1:0] typ = cur[15:14];
    wire is_rd = typ[1];
    wire cond = (typ == 2'd2) ? ((rdv & cur[7:0]) == 8'd0) : ((rdv & cur[7:0]) != 8'd0);

    assign own  = own_r;
    assign busy = (st == S_EXEC) || (st == S_CYC) || (st == S_GAP);
    assign tmo  = tmo_c;
    assign pop  = (st == S_LOAD) && en && allow && !z_any && ent_v;
    // al Z80 se le retiene mientras el ARM tiene el bus o en la ventana POST; el WAIT del glue solo le llega con own = 0
    assign wait_z_n = ~(z_any && (own_r || post_cnt != 5'd0)) && (own_r || wait_n);

    always @(posedge clk) begin
        // mezcla registrada hacia el glue
        o_csw_n <= own_r ? a_csw_n : z_csw_n;
        o_csr_n <= own_r ? a_csr_n : z_csr_n;
        o_mode  <= own_r ? a_mode  : z_mode;
        o_cdo   <= own_r ? a_cdo   : z_cdo;
        if (!rst_n) begin
            st <= S_IDLE; own_r <= 1'b0; a_csw_n <= 1'b1; a_csr_n <= 1'b1; idle_cnt <= 5'd0; post_cnt <= 5'd0;
            tmo_c <= 4'd0; cnt <= 13'd0; tcnt <= 21'd0; lng <= 6'd0;
        end else begin
            if (z_any || !wait_n) idle_cnt <= 5'd0;
            else if (idle_cnt != 5'd31) idle_cnt <= idle_cnt + 5'd1;
            if (post_cnt != 5'd0) post_cnt <= post_cnt - 5'd1;
            case (st)
            S_IDLE: begin
                if (en && allow && ent_v && !z_any && wait_n && idle_cnt >= IDLEN && post_cnt == 5'd0) begin
                    own_r <= 1'b1; st <= S_LOAD; lng <= 6'd0;
                end
            end
            S_LOAD: begin
                if (z_any || !allow || !en) begin
                    own_r <= 1'b0; post_cnt <= POST; st <= S_IDLE;
                end else if (ent_v) begin                  // pop (combinacional)
                    cur <= ent; tcnt <= 21'd0; lng <= 6'd0; st <= S_EXEC;
                end else if (lng == LINGER) begin
                    own_r <= 1'b0; post_cnt <= POST; st <= S_IDLE;
                end else lng <= lng + 6'd1;
            end
            S_EXEC: begin
                if (typ == 2'd1) st <= S_LOAD;                // NOP
                else begin
                    a_mode <= cur[11:8]; a_cdo <= cur[7:0];
                    a_csw_n <= (typ != 2'd0); a_csr_n <= (typ == 2'd0);
                    cnt <= 13'd0; st <= S_CYC;
                end
            end
            S_CYC: begin
                cnt <= cnt + 13'd1;
                if (tcnt != TMO) tcnt <= tcnt + 21'd1;
                if ((cnt >= {7'd0, MINC} && wait_n) || cnt[12]) begin    // cnt[12]: el glue no solto el WAIT (fail-open del glue ya vencio)
                    rdv <= cdi;
                    a_csw_n <= 1'b1; a_csr_n <= 1'b1;
                    cnt <= 13'd0; st <= S_GAP;
                end
            end
            S_GAP: begin
                cnt <= cnt + 13'd1;
                if (tcnt != TMO) tcnt <= tcnt + 21'd1;
                if (cnt >= {9'd0, GAP} - 13'd1) begin
                    if (!is_rd || cond) begin lng <= 6'd0; st <= S_LOAD; end
                    else if (tcnt == TMO) begin
                        if (tmo_c != 4'd15) tmo_c <= tmo_c + 4'd1;
                        lng <= 6'd0; st <= S_LOAD;
                    end else begin
                        a_csr_n <= 1'b0; cnt <= 13'd0; st <= S_CYC;       // otra lectura
                    end
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
