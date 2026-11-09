// dual_mute.v - SILENCIO POR MAQUINA del perfil Dual (Z1.3.2b8, 1/11/2026). Solo bajo ENABLE_DUAL (top_zynq.v).
//
// El ARM pide el silencio de A o de B por la segunda palabra de control (MBOX V9_BASE+8 = 0x1FFB0008, b_ctl2), con el mismo protocolo
// que la peticion de foco: un bit que CAMBIA es una peticion y el de al lado lleva el valor.
//   req[0] = b_ctl2[22]: peticion A (cada cambio)      req[1] = b_ctl2[23]: 1 = silenciar A, 0 = dejarla sonar
//   req[2] = b_ctl2[24]: peticion B (cada cambio)      req[3] = b_ctl2[25]: 1 = silenciar B, 0 = dejarla sonar
// Solo valen con la posicion fina encendida (fine = B_CTL[7], con la clave valida): sin ella la palabra puede ser basura de la DDR y solo se
// sigue la cuenta de peticiones (la ultima vista), como b_freq_seen del foco. Los silencios se QUITAN SOLOS con B parada (running = 0:
// la parada de B, un reset de A -rstb_n = sys_rst_n & run-, o un PL recien cargado): "B parada" o "A reiniciada" nunca dejan una maquina
// muda por sorpresa. El estado real (a_mute, b_mute) sale en la telemetria +0xD0 para que el ARM lo vea; a_mute_27 y b_mute_27 son los
// mismos bits registrados en clk_27m (el dominio del mezclador; mA_54 y mA_27 son sincronos entre si: un solo registro).
module dual_mute (
    input  wire       clk_54m,
    input  wire       clk_27m,
    input  wire       fine,
    input  wire       running,
    input  wire [3:0] req,
    output wire       a_mute,
    output wire       b_mute,
    output reg        a_mute_27 = 1'b0,
    output reg        b_mute_27 = 1'b0
);
    reg a_k = 1'b0, b_k = 1'b0, a_seen = 1'b0, b_seen = 1'b0;
    always @(posedge clk_54m) begin
        if (!fine) begin
            a_seen <= req[0];                       // sin la posicion fina la palabra es basura: solo se sigue la cuenta
            b_seen <= req[2];
        end else begin
            if (req[0] != a_seen) begin a_seen <= req[0]; a_k <= req[1]; end
            if (req[2] != b_seen) begin b_seen <= req[2]; b_k <= req[3]; end
        end
        if (!running) begin a_k <= 1'b0; b_k <= 1'b0; end
    end
    assign a_mute = a_k;
    assign b_mute = b_k;
    always @(posedge clk_27m) begin
        a_mute_27 <= a_k;
        b_mute_27 <= b_k;
    end
endmodule
