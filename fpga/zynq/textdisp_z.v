// textdisp_z.v — el textdisp de TangCore (src/iosys/textdisp.v) para la Zynq, CON COLOR (30/09/2026, Z1.2.2).
//
// 32x28 caracteres de 8x8 sobre el overlay de 256x224. Cada celda es una palabra de 16 bits de la BRAM del menu
// (zynq/gowin_dpb_menu.v, ahora 2048 x 16): {atributo[7:0], caracter[7:0]}, atributo = {fondo[3:0], tinta[3:0]} de
// una paleta de 16 colores (zynq/osd_paleta.v). Los caracteres 0..127 son la fuente de siempre y los 128..255 glifos
// nuevos (bloques, marcos, iconos, letras con tilde: tools/osd_fuente.py). El atributo 0 da el aspecto de antes
// (tinta amarilla sobre negro), asi que quien no sepa de colores ve lo mismo que siempre.
// Diferencias con el original: sin el logo de 72x14 (tapaba las filas 25-26: con los glifos ya no hace falta) ni la
// primera columna naranja (el "cursor" del menu de TangCore).
// La escritura trae el atributo en reg_char_di[31:24] (iosys_bl616_z.v: orden 0x10 = fija el atributo de lo que se
// imprime despues). Misma latencia de 2 ciclos y los mismos 3 estados por pixel que el original.

module textdisp(
    input             clk,              // reloj de la logica (escrituras)
    input             hclk,             // reloj del HDMI (lecturas)
    input             resetn,

    input      [7:0]  x,                // 0 - 255
    input      [7:0]  y,                // 0 - 223
    output reg [14:0] color,            // BGR555, 2 ciclos de latencia

    // [31:24] atributo, [20:16] x, [12:8] y, [7:0] caracter
    input      [3:0]  reg_char_we,
    input      [31:0] reg_char_di
);
parameter [14:0] COLOR_LOGO = 15'b00000_10101_00000;    // sin uso (ya no hay logo); se deja por compatibilidad

wire [4:0] text_x = reg_char_di[20:16];
wire [4:0] text_y = reg_char_di[12:8];

reg  [10:0] mem_addr_b;
wire [15:0] mem_do_b;

gowin_dpb_menu menu_mem (
    .clka(clk), .reseta(1'b0), .ocea(1'b1), .cea(1'b1),
    .ada({1'b0, text_y, text_x}), .wrea(reg_char_we[0]),
    .dina({reg_char_di[31:24], reg_char_di[7:0]}), .douta(),

    .clkb(hclk), .resetb(1'b0), .oceb(1'b1), .ceb(1'b1),
    .adb(mem_addr_b), .wreb(1'b0),
    .dinb(16'h0000), .doutb(mem_do_b)
);

// paleta: se consulta con el atributo registrado (fuera del camino BRAM -> pixel)
reg  [7:0]  attr;
reg         alto;               // glifo 128..255: byte alto de la palabra de la fuente
wire [14:0] pal_tinta, pal_fondo;
osd_paleta paleta (.ti(attr[3:0]), .fo(attr[7:4]), .tinta(pal_tinta), .fondo(pal_fondo));

reg [14:0] color_buf;
reg [7:0]  x_r;

reg [1:0] state;
localparam MAIN       = 2'd0;   // leer la celda
localparam FETCH_FONT = 2'd1;   // leer la fila del glifo
localparam OUTPUT     = 2'd3;   // sacar el pixel y leer la celda siguiente

always @* begin
    color = color_buf;
    case (state)
    MAIN:       mem_addr_b = {1'b0, y[7:3], x[7:3]};
    FETCH_FONT: mem_addr_b = {1'b1, mem_do_b[6:0], y[2:0]};         // mem_do_b = la celda
    OUTPUT: begin
        mem_addr_b = {1'b0, y[7:3], x[7:3]};
        color = (alto ? mem_do_b[{1'b1, x[2:0]}] : mem_do_b[{1'b0, x[2:0]}]) ? pal_tinta : pal_fondo;
    end
    default:    mem_addr_b = 11'd0;
    endcase
end

always @(posedge hclk) begin
    x_r <= x;
    case (state)
    MAIN, OUTPUT: begin
        state <= MAIN;
        if (state == OUTPUT) color_buf <= color;
        if (x[0] != x_r[0]) state <= FETCH_FONT;                    // pixel nuevo
    end
    FETCH_FONT: begin                                               // aqui mem_do_b es aun la CELDA
        attr  <= mem_do_b[15:8];
        alto  <= mem_do_b[7];
        state <= OUTPUT;
    end
    default: state <= MAIN;
    endcase
end

endmodule
