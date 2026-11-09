/* This file is part of JTOPL.

 
    JTOPL program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTOPL program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTOPL.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 20-6-2020 

*/

module jtopl_acc(
    input                rst,
    input                clk,
    input                cenop,
    input         [17:0] slot,
    input                rhy_en,
    input  signed [12:0] op_result,
    input                zero,
    input                op,  // 0 for modulator operators
    input                con, // 0 for modulated connection
    output signed [15:0] snd,
    // MSXimus Z (23/09/2026): estereo por canales, snd_l + snd_r = snd (/4 con redondeo). Sin conectar (jt2413),
    // la sintesis los quita.
    output signed [15:0] snd_l,
    output signed [15:0] snd_r
);

wire               sum_en;
wire signed [12:0] op2x;
wire               rhy2x;

// all rhythm channels are amplified by two
// given the data path latency, slot 16(-1) data enters at slot 6(-1) and so on
// slots 13~18 (counting from 1 to 18) will enter when bits slot[7:2] are set
assign rhy2x  = rhy_en && |slot[7:2];
assign sum_en = op | con;
assign op2x   = rhy2x ? op_result<<1 : op_result;

// Continuous output
jtopl_single_acc  u_acc(
    .clk        ( clk       ),
    .cenop      ( cenop     ),
    .op_result  ( op2x      ),
    .sum_en     ( sum_en    ),
    .zero       ( zero      ),
    .snd        ( snd       )
);

// MSXimus Z (23/09/2026): ESTEREO POR CANALES. Mapa medido en simulacion (un canal cada vez): los canales 1-3
// suman en las ranuras 9,10,11, los 4-6 en 15,16,17 y los 7-9 en 3,4,5 (los moduladores, 3 ranuras antes), asi
// que la ranura mod 3 da el grupo: 0 = canales 1/4/7 (3/4 izq), 1 = 2/5/8 (3/4 der), 2 = 3/6/9 (centro). En
// modo ritmo (canales 7-9): charles (ranura 1) der, platillo (5) izq, bombo, caja y tom al centro. Pesos en
// cuartos, izq = w y der = 4 - w: la suma de los dos lados es el acumulado de siempre.
wire g0 = slot[0] | slot[3] | slot[6] | slot[9]  | slot[12] | slot[15];
wire g1 = slot[1] | slot[4] | slot[7] | slot[10] | slot[13] | slot[16];
reg  [1:0] pan_w;
always @(*) begin
    if( rhy_en && (slot[0] | slot[1] | slot[2] | slot[3] | slot[4] | slot[5]) )
        pan_w = slot[1] ? 2'd1 : slot[5] ? 2'd3 : 2'd2;     // HH der, CYM izq, BD/SD/TOM centro
    else
        pan_w = g0 ? 2'd3 : g1 ? 2'd1 : 2'd2;
end
wire signed [14:0] op_x1 = {{2{op2x[12]}}, op2x};
wire signed [14:0] op_x2 = {op2x[12], op2x, 1'b0};
wire signed [14:0] op_x3 = op_x1 + op_x2;
wire signed [14:0] op_pl = pan_w == 2'd3 ? op_x3 : pan_w == 2'd2 ? op_x2 : op_x1;
wire signed [14:0] op_pr = pan_w == 2'd1 ? op_x3 : pan_w == 2'd2 ? op_x2 : op_x1;
wire        [17:0] snd_l4, snd_r4;      // x4
jtopl_single_acc #(.INW(15), .OUTW(18)) u_acc_l(
    .clk        ( clk       ),
    .cenop      ( cenop     ),
    .op_result  ( op_pl     ),
    .sum_en     ( sum_en    ),
    .zero       ( zero      ),
    .snd        ( snd_l4    )
);
jtopl_single_acc #(.INW(15), .OUTW(18)) u_acc_r(
    .clk        ( clk       ),
    .cenop      ( cenop     ),
    .op_result  ( op_pr     ),
    .sum_en     ( sum_en    ),
    .zero       ( zero      ),
    .snd        ( snd_r4    )
);
assign snd_l = snd_l4[17:2];
assign snd_r = snd_r4[17:2];

endmodule
