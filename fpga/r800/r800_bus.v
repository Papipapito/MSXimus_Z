//
// r800_bus.v
//   Bus del nucleo R800 (r800_cpu.v, derivado de NextZ80 de Nicolae Dumitrache,
//   LGPL) con los puertos de un T80s. Traduccion a Verilog, con reloj de 54 MHz y
//   habilitador de 21,48 MHz (ce21), de r800_bus.vhd de Ramon Martinez (rampa069/
//   R800, 2026, LGPL 2.1). Cabecera del original:
//
// The R800 core does one bus access per clock with the data read in that clock,
// about one clock per opcode byte plus one per access: the timing model of
// the R800.  Here every access of the core becomes a T80 like bus cycle
// on clk21m while the core is held (its WAIT):
//   T1   the clock the core shows the access: address, M1_n low for an
//        opcode fetch, strobes high (r800_timing and the CPU switch stop the
//        R800 at the T1 of an M1 with CEN)
//   T2   MREQ_n / IORQ_n with RD_n or WR_n (M1_n + IORQ_n for INTA) until
//        WAIT_n is high
//   T3   strobes kept; the data of the bus is there one clock after the wait
//        ends (as for the T80s): the core takes DI and goes on at its end
// so an access lasts at least 3 clk21m, one R800 cycle, and r800_timing
// holds the R800 to the real R800 time.  CEN low freezes it all.  RFSH_n is a
// refresh request (low 4 clocks every 128), whatever the core does.
//
// Aqui "clk21m" son los ciclos de clk con ce21 = 1; CEN actua dentro de ellos.
// Todo lo que se congela (el nucleo, T2/T3) avanza solo con ce = ce21 & CEN.
//
`default_nettype none

module r800_bus (
    input  wire        clk,
    input  wire        ce21,
    input  wire        RESET_n,
    input  wire        CEN,
    input  wire        WAIT_n,
    input  wire        INT_n,
    input  wire        NMI_n,
    output wire        M1_n,
    output wire        MREQ_n,
    output wire        IORQ_n,
    output wire        RD_n,
    output wire        WR_n,
    output wire        RFSH_n,
    output wire        HALT_n,
    output wire        done,           // 1 ciclo de clk: fin de T3 (el nucleo toma DI y sigue); lo usa tr_cpu
    output wire [15:0] A,
    input  wire [7:0]  DI,
    output wire [7:0]  DO
);
    wire [7:0]  c_do;
    wire [15:0] c_adr;
    wire        c_wr, c_mreq, c_iorq, c_halt, c_m1;
    reg  [6:0]  rfsh_cnt = 7'd0;
    reg         t2 = 1'b0;                  // T2 (wait for WAIT_n)
    reg         t3 = 1'b0;                  // T3 (data)

    wire ce      = ce21 & CEN;
    wire w_acc   = c_mreq | c_iorq;
    wire w_inta  = c_iorq & c_m1;
    // held while frozen, and during an access until the bus is done (WAIT_n in T2);
    // the core takes the reset even when frozen: it starts again at 0
    wire c_wait  = (!RESET_n) ? 1'b0 :
                   (!ce)      ? 1'b1 :
                   (w_acc && !t3) ? 1'b1 : 1'b0;

    R800 u_cpu (
        .DI(DI), .DO(c_do), .ADDR(c_adr), .WR(c_wr), .MREQ(c_mreq), .IORQ(c_iorq),
        .HALT(c_halt), .M1(c_m1), .CLK(clk), .RESET(!RESET_n), .INT(!INT_n), .NMI(!NMI_n),
        .WAIT_I(c_wait)
    );

    always @(posedge clk) begin
        if (!RESET_n) begin
            t2 <= 1'b0;
            t3 <= 1'b0;
        end else if (ce) begin
            if (t3)
                t3 <= 1'b0;                 // done: the core goes on now
            else if (t2) begin
                if (WAIT_n) begin
                    t2 <= 1'b0;
                    t3 <= 1'b1;
                end
            end else if (w_acc)
                t2 <= 1'b1;
        end
    end

    // refresh request
    always @(posedge clk) begin
        if (!RESET_n)      rfsh_cnt <= 7'd0;
        else if (ce21)     rfsh_cnt <= rfsh_cnt + 7'd1;
    end

    wire act = t2 | t3;
    assign done   = ce & t3;
    assign A      = c_adr;
    assign DO     = c_do;
    assign M1_n   = (w_acc && c_m1 && RESET_n) ? 1'b0 : 1'b1;
    assign MREQ_n = (act && c_mreq) ? 1'b0 : 1'b1;
    assign IORQ_n = (act && c_iorq) ? 1'b0 : 1'b1;
    assign RD_n   = (act && !c_wr && !w_inta) ? 1'b0 : 1'b1;
    assign WR_n   = (act && c_wr) ? 1'b0 : 1'b1;
    assign RFSH_n = (rfsh_cnt[6:2] == 5'b11111) ? 1'b0 : 1'b1;
    assign HALT_n = !c_halt;
endmodule

`default_nettype wire
