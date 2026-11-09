// ============================================================================
// axi_rst_drain.v - reset ORDENADO de un maestro AXI que comparte puerto del PS con otro (perfil Dual, 31/10/2026).
//
// El reset de memory_axi (y de cualquier maestro de este diseno) suelta AWVALID/WVALID/ARVALID de golpe. En AXI un maestro no puede
// retirar un VALID ni dejar una rafaga de escritura sin su WLAST: axi_arb2w (y el HP del PS) se quedan esperando los datos para
// siempre, y con ellos el otro maestro del mismo puerto (en el HP2, el buzon del ARM: se cuelga todo). Aqui el reset que se pide
// (want_n = 0: B parada, el Z80 y el VDP de B ya en reset y sin pedir nada nuevo) solo se APLICA (rst_n = 0) cuando el maestro lleva
// SETTLE ciclos seguidos sin nada a medias (idle = 1); se suelta (rst_n = 1) en cuanto want_n vuelve a 1.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module axi_rst_drain #(
    parameter SETTLE = 16
)(
    input  wire clk,
    input  wire want_n,      // 0 = se pide el reset de la maquina
    input  wire idle,        // 1 = el maestro AXI no tiene nada a medias
    output reg  rst_n = 1'b0 // reset que se aplica al maestro (arranca en reset)
);
    reg [7:0] cnt = 8'd0;
    always @(posedge clk) begin
        if (want_n) begin
            rst_n <= 1'b1; cnt <= 8'd0;
        end else if (rst_n) begin
            if (!idle) cnt <= 8'd0;
            else if (cnt == SETTLE - 1) rst_n <= 1'b0;
            else cnt <= cnt + 8'd1;
        end
    end
endmodule
