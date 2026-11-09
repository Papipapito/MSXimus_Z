//
// tr_pcm.v
//   PCM del turbo R (puertos A4h/A5h), con el comportamiento que modela openMSX (MSXTurboRPCM):
//     A4h lectura : bits 1-0 = contador de 15,7 kHz (3.579.545 / 228)
//     A4h escritura: muestra (reproducir) o valor de comparacion (grabar); pone el contador a 0, sin mover la fase de los 15,7 kHz
//     A5h lectura : bit 7 COMP, bits 4-0 los de la ultima escritura
//     A5h escritura: bit 0 BUFF, bit 1 MUTE (0 = TODO el sonido en silencio), bit 2 FILT, bit 3 SEL, bit 4 SMPL
//   El DAC toma la muestra al escribirla o, con BUFF = 1, en el siguiente tick; con MUTE = 0 no la toma. Al bajar BUFF toma la ultima.
//   No hay microfono: la entrada vale siempre 80h, asi que COMP = (80h >= valor escrito). El reset no silencia: lo hace la primera escritura a A5h.
//
`default_nettype none

module tr_pcm (
    input  wire        clk,         // 54 MHz
    input  wire        rst_n,
    input  wire        cen_3m58,    // habilitador de 3,58 MHz
    input  wire        wr_a4,       // escritura a A4h: nivel mientras dura el ciclo de bus
    input  wire        wr_a5,       // escritura a A5h: idem
    input  wire [7:0]  din,
    input  wire        a0,          // puerto: 0 = A4h, 1 = A5h
    output wire [7:0]  dout,
    output reg  [7:0]  dac,         // sin signo, 80h = silencio
    output reg         mute         // silencio de todo el sonido
);
    reg [7:0] pre = 8'd0;
    reg [1:0] cnt = 2'd0;
    reg [4:0] status = 5'd0;
    reg [7:0] dval = 8'h80;
    reg       pend = 1'b0;
    reg       wr_a4_q = 1'b0, wr_a5_q = 1'b0;

    initial begin dac = 8'h80; mute = 1'b0; end

    wire tick = cen_3m58 && (pre == 8'd227);
    wire comp = (8'h80 >= dval);

    assign dout = a0 ? {comp, 2'b00, status} : {6'd0, cnt};

    always @(posedge clk) begin
        wr_a4_q <= wr_a4;
        wr_a5_q <= wr_a5;
        if (cen_3m58) pre <= (pre == 8'd227) ? 8'd0 : pre + 8'd1;
        if (!rst_n) begin
            cnt <= 2'd0;  status <= 5'd0;  dval <= 8'h80;  dac <= 8'h80;  pend <= 1'b0;  mute <= 1'b0;
        end else begin
            if (tick) begin
                cnt <= cnt + 2'd1;
                if (pend) begin dac <= dval; pend <= 1'b0; end
            end
            if (wr_a4 && !wr_a4_q) begin
                dval <= din;
                cnt  <= 2'd0;
                if (status[1]) begin
                    if (status[0]) pend <= 1'b1;
                    else           dac  <= din;
                end
            end
            if (wr_a5 && !wr_a5_q) begin
                status <= din[4:0];
                mute   <= ~din[1];
                if (status[0] && !din[0]) begin dac <= dval; pend <= 1'b0; end
            end
        end
    end
endmodule

`default_nettype wire
