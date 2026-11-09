// ============================================================================
// gowin_dpb.v — Modelo inferible de la primitiva DPB de Gowin (BSRAM de doble
// puerto de 16 kbit) para compilar el tiny9990 en la Zynq (Vivado infiere un
// RAMB18 por instancia).
//
// Solo cubre lo que usa el tiny9990 (19 instancias, ver `grep defparam`):
//   BIT_WIDTH_0 == BIT_WIDTH_1 in {16, 8}, READ_MODE 0 (bypass: lectura
//   sincrona de 1 ciclo, sin registro de pipeline; OCE no interviene),
//   WRITE_MODE 00 (normal: DO no cambia durante una escritura), RESET_MODE
//   "SYNC" (reset sincrono del registro de salida), BLK_SEL 0 (no se apilan
//   bloques: BLKSEL se ignora).
// RAM_STYLE = "distributed" (parametro propio, no existe en la primitiva Gowin;
// solo para memorias PEQUENAS): el modelo pasa a LUTRAM en vez de RAMB18. Exige
// WREA = 0 (el puerto A solo lee; las instancias del tiny9990 que lo usan lo
// cumplen) y ADDR_BITS = bits de direccion de palabra/byte REALMENTE usados
// (los de arriba van a 0 en la instancia); la lectura sigue siendo sincrona de
// 1 ciclo con el mismo registro de salida, reset y CE que el modelo "block".
// Direccionamiento de Gowin (UG285): x16 -> palabra = AD[13:4] y AD[1:0] son
// los byte-enables de escritura; x8 -> byte = AD[13:3].
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module DPB #(
    parameter READ_MODE0  = 1'b0,
    parameter READ_MODE1  = 1'b0,
    parameter WRITE_MODE0 = 2'b00,
    parameter WRITE_MODE1 = 2'b00,
    parameter BIT_WIDTH_0 = 16,
    parameter BIT_WIDTH_1 = 16,
    parameter BLK_SEL_0   = 3'b000,
    parameter BLK_SEL_1   = 3'b000,
    parameter RESET_MODE  = "SYNC",
    parameter RAM_STYLE   = "block",
    parameter ADDR_BITS   = 0           // solo "distributed": 0 = completo (10 en x16, 11 en x8)
)(
    output reg  [15:0] DOA,
    output reg  [15:0] DOB,
    input  wire        CLKA,
    input  wire        OCEA,
    input  wire        CEA,
    input  wire        RESETA,
    input  wire        WREA,
    input  wire        CLKB,
    input  wire        OCEB,
    input  wire        CEB,
    input  wire        RESETB,
    input  wire        WREB,
    input  wire [2:0]  BLKSELA,
    input  wire [2:0]  BLKSELB,
    input  wire [13:0] ADA,
    input  wire [15:0] DIA,
    input  wire [13:0] ADB,
    input  wire [15:0] DIB
);
    generate
    if (RAM_STYLE == "distributed") begin : g_dist
        localparam AW = ADDR_BITS != 0 ? ADDR_BITS : (BIT_WIDTH_0 == 16 ? 10 : 11);
        // x16: palabra = AD[13:4]; x8: byte = AD[13:3]
        wire [10:0] fa = (BIT_WIDTH_0 == 16) ? {1'b0, ADA[13:4]} : ADA[13:3];
        wire [10:0] fb = (BIT_WIDTH_1 == 16) ? {1'b0, ADB[13:4]} : ADB[13:3];
        wire [AW-1:0] adra = fa[AW-1:0];
        wire [AW-1:0] adrb = fb[AW-1:0];
        (* ram_style = "distributed" *) reg [7:0] mem_lo [0:(1<<AW)-1];
        (* ram_style = "distributed" *) reg [7:0] mem_hi [0:(1<<AW)-1];
        // Un solo puerto de escritura (B), como exige la LUTRAM; A solo lee.
        always @(posedge CLKA) begin
            if (CEA) DOA <= (BIT_WIDTH_0 == 16) ? {mem_hi[adra], mem_lo[adra]} : {8'd0, mem_lo[adra]};
            if (RESETA) DOA <= 16'd0;
        end
        always @(posedge CLKB) begin
            if (CEB) begin
                if (WREB) begin
                    if (BIT_WIDTH_1 == 16) begin
                        if (ADB[0]) mem_lo[adrb] <= DIB[7:0];
                        if (ADB[1]) mem_hi[adrb] <= DIB[15:8];
                    end
                    else mem_lo[adrb] <= DIB[7:0];
                end
                else DOB <= (BIT_WIDTH_1 == 16) ? {mem_hi[adrb], mem_lo[adrb]} : {8'd0, mem_lo[adrb]};
            end
            if (RESETB) DOB <= 16'd0;
        end
        // synthesis translate_off
        always @(posedge CLKA) if (CEA && WREA) $display("DPB distributed: WREA no soportado (%m)");
        // synthesis translate_on
    end
    else if (BIT_WIDTH_0 == 16) begin : g_x16
        // 1024 x 16 con byte-enables (AD[1:0]); las dos mitades como dos
        // bancos de 8 bits para que Vivado infiera un RAMB18 con WE por byte.
        (* ram_style = "block" *) reg [7:0] mem_lo [0:1023];
        (* ram_style = "block" *) reg [7:0] mem_hi [0:1023];
        wire [9:0] adra = ADA[13:4];
        wire [9:0] adrb = ADB[13:4];
        always @(posedge CLKA) begin
            if (CEA) begin
                if (WREA) begin
                    if (ADA[0]) mem_lo[adra] <= DIA[7:0];
                    if (ADA[1]) mem_hi[adra] <= DIA[15:8];
                end
                else DOA <= {mem_hi[adra], mem_lo[adra]};
            end
            if (RESETA) DOA <= 16'd0;
        end
        always @(posedge CLKB) begin
            if (CEB) begin
                if (WREB) begin
                    if (ADB[0]) mem_lo[adrb] <= DIB[7:0];
                    if (ADB[1]) mem_hi[adrb] <= DIB[15:8];
                end
                else DOB <= {mem_hi[adrb], mem_lo[adrb]};
            end
            if (RESETB) DOB <= 16'd0;
        end
    end
    else begin : g_x8
        // 2048 x 8: byte = AD[13:3]
        (* ram_style = "block" *) reg [7:0] mem [0:2047];
        wire [10:0] adra = ADA[13:3];
        wire [10:0] adrb = ADB[13:3];
        always @(posedge CLKA) begin
            if (CEA) begin
                if (WREA) mem[adra] <= DIA[7:0];
                else      DOA <= {8'd0, mem[adra]};
            end
            if (RESETA) DOA <= 16'd0;
        end
        always @(posedge CLKB) begin
            if (CEB) begin
                if (WREB) mem[adrb] <= DIB[7:0];
                else      DOB <= {8'd0, mem[adrb]};
            end
            if (RESETB) DOB <= 16'd0;
        end
    end
    endgenerate
endmodule
