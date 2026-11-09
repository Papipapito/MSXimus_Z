//
// r800_timing.v
//   Regulador de velocidad del R800 (MSXtR). Traduccion a Verilog, con reloj de
//   54 MHz y habilitador de 21,48 MHz (ce21), de r800_timing.vhd de Ramon Martinez
//   (rampa069/R800, 2026, LGPL 2.1), que a su vez va escrito para el T80s de la
//   U01_R8 del ZEMMIX. Cabecera del original:
//
// The CPU runs on clk21m with Z80 like bus cycles, so most instructions take
// a different time than on a real R800. This block keeps the time a real
// R800 would have reached (in R800 cycles, 1 cycle = 3 x clk21m) with the
// openMSX R800 rules and holds the CPU when it goes ahead of it:
//  * opcode/operand fetch : 1 cycle, +1 on a DRAM page break (256 bytes)
//  * data access          : 1 cycle + page break (not on the 2nd byte of a word)
//  * internal ROM / external slot : +1 / +2 per access (ROM: no page mode)
//  * I/O                  : 1 cycle, wait for an even cycle, 6 cycles,
//                           VDP ports at least 62 cycles apart
//  * refresh              : 25 cycles every 210 (on an even cycle), as openMSX. The original here
//                           had 18 every 223; a real turbo R gives 1255 kB/s in Z80BENCH Mem 8bit,
//                           which fits 25/210 (docs/tecnica/15-perfil-tr.md)
//  * a few instructions have internal cycles (table), a taken jump +1 and a page break
// The CPU is held at the T1 of an M1 while it is early, and an I/O access
// is held until its exact time. When it is late, the delay is kept, up to
// c_lim cycles, so that the next fast instructions catch up.
//
// Cambios respecto al VHDL: todo el estado avanza solo en los ciclos de clk
// con ce21 = 1 (el "clk21m" del original); reset sincrono; 'resize' y los
// aritmeticos sin signo/con signo a mano. La logica es la misma.
//
`default_nettype none

module r800_timing #(
    parameter integer C_LIM = 32            // late cycles that can be caught up
) (
    input  wire        clk,                 // 54 MHz
    input  wire        ce21,                // habilitador de 21,477 MHz (el clk21m)
    input  wire        reset,
    input  wire        active,              // the R800 is the running CPU
    input  wire        m1_n,
    input  wire        merq_n,
    input  wire        iorq_n,
    input  wire        rd_n,
    input  wire        wr_n,
    input  wire        rfsh_n,
    input  wire        wait_n,
    input  wire [15:0] adr,
    input  wire [7:0]  di,                  // data read by the R800 (opcodes)
    input  wire [7:0]  ppi_a,               // primary slots
    input  wire [7:0]  exp0,                // secondary slots of slot 0
    input  wire [7:0]  exp3,                // secondary slots of slot 3
    input  wire        dram_mode,           // S1990 R#6 bit6 = 0
    output wire        stall,               // hold the R800 (clock enable off)
    output wire        io_hold,             // hold the I/O request
    output wire        io_go                // the I/O access has reached its time: the system may see its strobes (ff_io_done)
);

    localparam [15:0] CL = C_LIM;
    reg [15:0] ff_e;                        // R800 cycles elapsed
    reg [1:0]  ff_ph;
    reg [15:0] ff_v;                        // R800 cycles a real R800 would have used
    reg [15:0] ff_lref;                     // last refresh
    // 04/11 (Aleste): edad del ultimo acceso al VDP en ciclos de R800, SATURADA en 127. Antes era la marca de tiempo ff_lvdp (16 bits) y la regla
    // de los 62 ciclos la comparaba con signo: con un hueco de 32.830 a 65.598 ciclos sin tocar el VDP la diferencia daba la vuelta y el siguiente
    // acceso (el IN (99h) de la ISR de cuadro, tras la logica de RAM de cada cuadro del juego) quedaba retenido hasta 32.768 ciclos (4,6 ms): la ISR escribia
    // R#2 en plena zona visible (fotogramas rotos con el R800 y no con el Z80).
    reg [6:0]  ff_vage;                     // cycles since the last VDP access (saturating)
    reg        ff_act;
    reg [7:0]  ff_page;
    reg        ff_page_ok;
    reg [15:0] ff_exp_pc;
    reg        ff_data;                     // this instruction did a data access
    reg        ff_last_data;                // the last access was a data access
    reg [15:0] ff_last_adr;
    reg [7:0]  ff_op;
    reg [1:0]  ff_pfx;                      // 00: none, 01: CB, 10: ED, 11: DD/FD
    reg        ff_acc_d;
    reg        ff_bnd_done;
    reg        ff_io_done;
    reg        ff_io_hold;

    wire w_mem_rd = (merq_n == 1'b0) && (rd_n == 1'b0) && (rfsh_n == 1'b1);
    wire w_mem_wr = (merq_n == 1'b0) && (wr_n == 1'b0);
    wire w_io     = (iorq_n == 1'b0) && (m1_n == 1'b1) && (rd_n == 1'b0 || wr_n == 1'b0);
    wire w_inta   = (iorq_n == 1'b0) && (m1_n == 1'b0);
    wire w_acc    = w_mem_rd | w_mem_wr | w_inta;
    wire w_t1     = (m1_n == 1'b0) && (merq_n == 1'b1) && (iorq_n == 1'b1);

    function [15:0] even16(input [15:0] v);
        even16 = v[0] ? v + 16'd1 : v;
    endfunction

    // extra delay of the accessed slot: 0 = RAM (3-0), 1 = internal ROM, 2 = external slot
    reg [1:0] w_dly;
    reg [1:0] prim, sec;
    always @* begin
        prim = ppi_a[{adr[15:14], 1'b0} +: 2];
        if (prim == 2'b00)      sec = exp0[{adr[15:14], 1'b0} +: 2];
        else if (prim == 2'b11) sec = exp3[{adr[15:14], 1'b0} +: 2];
        else                    sec = 2'b00;
        if (prim == 2'b01 || prim == 2'b10)
            w_dly = 2'b10;
        else if (prim == 2'b11 && sec == 2'b00)
            w_dly = 2'b00;
        else if (dram_mode && adr[15] == 1'b0 &&
                 ((prim == 2'b00 && sec == 2'b00) || (prim == 2'b11 && sec == 2'b01)))
            w_dly = 2'b00;                  // BIOS / SUB-ROM copied to DRAM
        else
            w_dly = 2'b01;
    end

    // the last M1 opcode is a prefix: the instruction goes on
    wire w_prefix = (ff_op == 8'hCB || ff_op == 8'hED || ff_op == 8'hDD || ff_op == 8'hFD) &&
                    !(ff_pfx == 2'b11 && ff_op == 8'hCB);

    // internal cycles of the instruction that ends at this M1
    reg [5:0] w_extra;
    reg [5:0] x;
    reg [7:0] o;
    always @* begin
        o = ff_op;
        x = 6'd0;
        case (ff_pfx)
        2'b00: begin
            if (o == 8'hC5 || o == 8'hD5 || o == 8'hE5 || o == 8'hF5)               // PUSH
                x = 6'd1;
            else if (o[7:6] == 2'b11 && o[2:0] == 3'b111)                           // RST
                x = 6'd1;
            else if (o == 8'hF3 || o == 8'h34 || o == 8'h35)                        // DI, INC/DEC (HL)
                x = 6'd1;
        end
        2'b01: begin
            if (o[2:0] == 3'b110 && o[7:6] != 2'b01)                                // rotate/SET/RES (HL)
                x = 6'd1;
        end
        2'b10: begin
            if (o == 8'hC1 || o == 8'hC9 || o == 8'hD1 || o == 8'hD9)               // MULUB: 14
                x = 6'd12;
            else if (o == 8'hC3 || o == 8'hF3)                                      // MULUW: 36
                x = 6'd34;
            else if ((o[7:6] == 2'b01 && o[2:0] == 3'b110) ||                       // IM
                     o == 8'h67 || o == 8'h6F ||                                    // RRD, RLD
                     o == 8'hA1 || o == 8'hA9 || o == 8'hB1 || o == 8'hB9)          // CPI, CPD, CPIR, CPDR
                x = 6'd1;
        end
        default: begin
            if (o == 8'h34 || o == 8'h35)                                           // INC/DEC (IX+d)
                x = 6'd2;
            else if (o == 8'hE5 || o == 8'h36 || o == 8'hCB ||                      // PUSH IX, LD (IX+d),n, DD CB
                     (o[7:6] == 2'b01 && o[2:0] == 3'b110 && o != 8'h76) ||
                     (o[7:3] == 5'b01110 && o != 8'h76) ||
                     (o[7:6] == 2'b10 && o[2:0] == 3'b110))
                x = 6'd1;
        end
        endcase
        // a jump taken without data access (JP, JR, DJNZ, JP (HL))
        if (ff_data == 1'b0 && adr != ff_exp_pc)
            x = x + 6'd1;
        w_extra = x;
    end

    // time at this M1: internal cycles, refresh, limit of the late cycles
    wire [15:0] w_v1      = w_prefix ? ff_v : ff_v + {10'd0, w_extra};
    wire        w_refresh = !w_prefix && ((w_v1 - ff_lref) >= 16'd210);
    wire [15:0] w_v2      = w_refresh ? even16(w_v1) + 16'd25 : w_v1;
    wire [15:0] w_v3      = ($signed(ff_e - w_v2) > $signed(CL)) ? ff_e - CL : w_v2;

    wire w_stall = active && ff_act && w_t1 && !ff_bnd_done && ($signed(w_v3 - ff_e) > 0);

    // time of an I/O access: 1 cycle, next even cycle, VDP 62 cycles after the last one
    wire        w_vdp    = (adr[7:2] == 6'b100110);
    wire [15:0] w_t_io0  = even16(ff_v + 16'd1);
    wire [15:0] w_lvdp62 = ff_e + 16'd62 - {9'd0, ff_vage};          // last VDP access + 62 (only meaningful while ff_vage < 62)
    wire [15:0] w_t_io   = (w_vdp && (ff_vage < 7'd62) && ($signed(w_lvdp62 - w_t_io0) > 0)) ? w_lvdp62 : w_t_io0;
    wire        w_io_hold = active && ff_act && w_io && !ff_io_done && ($signed(w_t_io - ff_e) > 0);

    assign stall   = w_stall;
    // registered: req comes from the internal bus registers, one clock after the R800 signals
    assign io_hold = ff_io_hold;
    assign io_go   = ff_io_done;

    reg [2:0] c;
    always @(posedge clk) begin
        if (reset) begin
            ff_e <= 16'd0;  ff_ph <= 2'd0;  ff_v <= 16'd0;  ff_lref <= 16'd0;  ff_vage <= 7'd127;
            ff_act <= 1'b0;  ff_page_ok <= 1'b0;  ff_data <= 1'b0;  ff_last_data <= 1'b0;
            ff_op <= 8'd0;  ff_pfx <= 2'b00;  ff_acc_d <= 1'b0;  ff_bnd_done <= 1'b0;
            ff_io_done <= 1'b0;  ff_io_hold <= 1'b0;
            ff_page <= 8'd0;  ff_exp_pc <= 16'd0;  ff_last_adr <= 16'd0;
        end else if (ce21) begin
            ff_io_hold <= w_io_hold;
            // R800 time
            if (active) begin
                if (ff_ph == 2'd2) begin
                    ff_ph <= 2'd0;
                    ff_e  <= ff_e + 16'd1;
                    if (ff_vage != 7'd127) ff_vage <= ff_vage + 7'd1;
                end else
                    ff_ph <= ff_ph + 2'd1;
            end

            ff_act <= active;
            if (active && !ff_act) begin
                // the R800 starts running: it is on time
                ff_v       <= ff_e;
                ff_lref    <= ff_e;
                ff_vage    <= 7'd127;
                ff_page_ok <= 1'b0;
            end else if (active) begin
                // M1: end of the last instruction
                if (w_t1 && !ff_bnd_done && !w_stall) begin
                    ff_bnd_done <= 1'b1;
                    ff_v <= w_v3;
                    if (ff_data == 1'b0 && adr != ff_exp_pc)  // taken jump: the next fetch has a page break
                        ff_page_ok <= 1'b0;
                    if (w_refresh) begin
                        ff_lref    <= ff_lref + 16'd210;
                        ff_page_ok <= 1'b0;
                    end
                    if (!w_prefix) begin
                        ff_data      <= 1'b0;
                        ff_last_data <= 1'b0;
                        if (ff_op == 8'hDD || ff_op == 8'hFD) ff_pfx <= 2'b11;
                        else                                  ff_pfx <= 2'b00;
                    end else if (ff_op == 8'hCB) ff_pfx <= 2'b01;
                    else if (ff_op == 8'hED)     ff_pfx <= 2'b10;
                    else                         ff_pfx <= 2'b11;
                end else if (m1_n == 1'b1 || w_mem_rd) begin
                    // armed again once this M1 reads (its T2): back to back M1 cycles
                    // with M1_n low all along (the R800 core of misc/r800) count too
                    ff_bnd_done <= 1'b0;
                end

                // opcode of the M1
                if (m1_n == 1'b0 && w_mem_rd && wait_n == 1'b1)
                    ff_op <= di;

                // cost of a memory access, at its start
                ff_acc_d <= w_acc;
                if (w_acc && !ff_acc_d) begin
                    if (w_inta) begin
                        ff_v         <= ff_v + 16'd1;
                        ff_data      <= 1'b1;
                        ff_last_data <= 1'b0;
                    end else if (w_mem_rd && (m1_n == 1'b0 || (adr == ff_exp_pc && !ff_data))) begin
                        // opcode / operand fetch
                        c = 3'b001 + {1'b0, w_dly};
                        if (!ff_page_ok || adr[15:8] != ff_page || w_dly != 2'b00)
                            c = c + 3'd1;
                        ff_v         <= ff_v + {13'd0, c};
                        ff_page      <= adr[15:8];
                        ff_page_ok   <= 1'b1;
                        ff_exp_pc    <= adr + 16'd1;
                        ff_last_data <= 1'b0;
                    end else begin
                        // data access
                        c = 3'b001 + {1'b0, w_dly};
                        if (!(ff_last_data && (adr == ff_last_adr + 16'd1 || adr == ff_last_adr - 16'd1)))
                            c = c + 3'd1;
                        ff_v         <= ff_v + {13'd0, c};
                        ff_page_ok   <= 1'b0;
                        ff_data      <= 1'b1;
                        ff_last_data <= 1'b1;
                        ff_last_adr  <= adr;
                    end
                end

                // I/O access: at its time
                if (w_io && !ff_io_done && !w_io_hold) begin
                    ff_io_done   <= 1'b1;
                    ff_v         <= w_t_io + 16'd6;
                    ff_data      <= 1'b1;
                    ff_last_data <= 1'b0;
                    if (w_vdp) ff_vage <= ff_e[6:0] - w_t_io[6:0];   // normally 0 (the access happens when ff_e reaches w_t_io)
                end else if (!w_io) begin
                    ff_io_done <= 1'b0;
                end
            end
        end
    end
endmodule


// ============================================================================
// tr_opll_gate — separacion minima entre escrituras del R800 al YM2413 (7Ch/7Dh) y strobe estable para el reloj de 3,58 MHz.
// El chip recibe cada escritura por un sincronizador de varios pulsos de phiM (~1 us) y el dato queda en un latch que la escritura SIGUIENTE pisa si llega antes:
// un Z80 las separa >= 3 us, el R800 a 7,16 MHz con los OUT seguidos de los drivers las emite a < 1 us. Se retiene el WAIT del R800 y se oculta el strobe al chip
// hasta cumplir la separacion del YM2413 (12 ciclos de phiM tras la direccion, 84 tras el dato; 1 ciclo de phiM = 15,09 de clk_54m), y despues se mantiene el strobe `HOLD` ciclos.
// ============================================================================
module tr_opll_gate #(parameter GAP_A = 11'd192, parameter GAP_D = 11'd1294, parameter HOLD = 6'd36) (
    input  wire clk,
    input  wire rst_n,
    input  wire sel_wr,     // ciclo de escritura de E/S a 7Ch/7Dh (strobe ya visible)
    input  wire a0,         // 0 = direccion (7Ch), 1 = dato (7Dh)
    output wire wait_o,     // retener al R800
    output wire allow       // el chip puede ver el strobe
);
    reg [10:0] gap = 11'd0;
    reg [5:0]  hold = 6'd0;
    reg        sel_q = 1'b0, a0_q = 1'b0;
    wire gap_busy = (gap != 11'd0);
    always @(posedge clk) begin
        if (!rst_n) begin gap <= 11'd0; hold <= 6'd0; sel_q <= 1'b0; a0_q <= 1'b0; end
        else begin
            sel_q <= sel_wr;
            if (sel_wr) a0_q <= a0;
            if (gap_busy) gap <= gap - 11'd1;
            if (sel_wr && !gap_busy) begin if (hold != HOLD) hold <= hold + 6'd1; end
            else if (!sel_wr) hold <= 6'd0;
            if (!sel_wr && sel_q) gap <= a0_q ? GAP_D : GAP_A;
        end
    end
    assign allow  = sel_wr & ~gap_busy;
    assign wait_o = sel_wr & (gap_busy | (hold != HOLD));
endmodule

`default_nettype wire
