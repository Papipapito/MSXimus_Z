// ============================================================================
//  msx_s1990.v — interfaz del S1990 del MSX turboR (puertos E4h-E7h)
//
//  QUE HACE Y QUE NO
//  --------------------------------------------------------------------------
//  Hace que la maquina se IDENTIFIQUE como turboR y da su temporizador de
//  sistema. NO hay R800 ni cambio de velocidad: peticion explicita de Albert
//  (25/08) -- *"solo son registros para identificarse y subida de Mhz"*, y la
//  velocidad se descarto aparte porque el techo real del MSXimus son ~4,3 MHz
//  efectivos (lo limita la SDRAM, no la CPU; ver el FSM de esperas de top.v).
//
//  DE DONDE SALEN LOS DATOS
//  --------------------------------------------------------------------------
//  El S1990 es un chip REAL de Panasonic con interfaz publicado. El mapa de
//  registros se ha contrastado con la implementacion de HRA! (hra1129/
//  FPGA_MSXtR, s2026a.v, MIT). Aqui no se copia su codigo: se implementa el
//  mismo interfaz, que es un hecho sobre el hardware, no una obra suya.
//
//  ID = 0 (Z1.4 de la Zynq, 30/10/2026, orden de Albert): SOLO el temporizador
//  (E6h/E7h). E4h/E5h no se contestan (FFh) y no hay firma ni CHGCPU: la maquina
//  no dice ser turboR hasta que haya un R800 de verdad. El temporizador se queda
//  porque las demos geo3d de kanon-ai miden con el sus cuadros. ID = 1, como antes.
//
//  MAPA
//  --------------------------------------------------------------------------
//    E4h  escribir = indice de registro (4 bits) · leer = {4'd0, indice}
//    E5h  escribir = valor del registro  · leer = valor del registro
//    E6h  escribir = pone a cero el contador · leer = contador[7:0]
//    E7h  leer = contador[15:8]
//
//  REGISTROS (lectura)
//    5   {0, boton_pausa, 6'd0}
//    6   {0, modo_rom, modo_cpu, 5'd0}     modo_cpu: 1 = Z80, 0 = R800
//    13  0x03   14  0x2F   15  0x8B        <- la firma que busca el software
//    resto  0xFF
//
//  🚨 EL BIT DE CPU VA ATADO AL TURBO (idea de Albert, 25/08)
//  --------------------------------------------------------------------------
//  El "modo R800" del turboR significa, para el software, *modo rapido*. Aqui el
//  modo rapido es el turbo Panasonic (5,37 MHz). Asi que se mapea uno sobre otro,
//  en LOS DOS SENTIDOS:
//
//    leer registro 6  -> bit5 = 0 (R800) si el turbo esta puesto, 1 (Z80) si no
//    escribir bit5=0  -> PIDE encender el turbo   (CHGCPU a R800)
//    escribir bit5=1  -> PIDE apagarlo            (CHGCPU a Z80)
//
//  Asi `CHGCPU` y `GETCPU` hacen algo de verdad y son coherentes entre si, en vez
//  de ser un adorno.
//
//  ⚠️ LO QUE ESTO CUESTA, Y HAY QUE SABERLO: al decir "estas en R800", un
//  programa puede creerse libre de usar MULUB/MULUW y demas instrucciones que
//  este procesador NO tiene, y estrellarse. Es una decision consciente: se gana
//  que el software que solo quiere "modo rapido" funcione, y se pierde el que
//  de verdad use el juego de instrucciones del R800. La alternativa (decir
//  siempre Z80) es mas segura pero deja CHGCPU sin efecto.
//
//  ⚠️ Y ESTO SOLO NO BASTA: el software mira ANTES el byte de version de la
//  BIOS ($002D del ROM principal, 3 = turboR). Ese byte vive en el pack, no
//  aqui. Sin el, nadie llega siquiera a preguntar por estos puertos.
// ============================================================================
`default_nettype none

module msx_s1990 #(
    parameter integer CLK_HZ = 27_000_000,
    parameter         ID     = 1            // 0 = solo el temporizador (E6h/E7h)
) (
    input  wire        clk,
    input  wire        reset_n,

    // Bus de E/S del MSX, ya registrado (patron _91/_95 del resto del top)
    input  wire        iorq_n,
    input  wire        rd_n,
    input  wire        wr_n,
    input  wire        m1_n,
    input  wire [7:0]  addr,
    input  wire [7:0]  din,

    output wire [7:0]  dout,
    output wire        req,        // 1 = la direccion es nuestra (para el mux del top)

    input  wire        pause_sw,   // boton PAUSE del turboR: no existe en la Console -> 0
    output wire        rom_mode,   // expuesto por si alguna vez se usa

    // Enlace con el turbo del MSXimus
    input  wire        turbo_on,   // estado ACTUAL (turbo_eff del top)
    output reg         turbo_set,  // pulso de 1 ciclo: hay peticion
    output reg         turbo_val,  // ...y esto es lo que se pide

    // ID = 2 (perfil TR, fase 2, 02/11/2026): S1990 de un turbo R de verdad con R800. R#6 bit 5 elige la CPU
    // (0 = R800; nivel, no pulso), el bit 6 es el modo ROM/DRAM, y se contestan ademas F4h (el registro de
    // estado de reset; desde el 04/11/2026 se borra con el reset, ver mas abajo) y A7h (pausa/LED). Con ID 0/1 estos puertos no se usan.
    output reg         cpu_r800,   // CPU pedida: 1 = R800
    input  wire        cpu_is_r800 // CPU que manda ahora (la de tr_cpu); es lo que lee el R#6
);

    // ---- el bus se REGISTRA antes de mirarlo -------------------------------
    // Leccion de la _95: un modulo en clk_27m que decodifica el bus del T80
    // (lanzado en el flanco de bajada de 54M) directamente crea un camino de
    // medio ciclo, y eso perdio la loteria de placement una vez. Un flop aqui
    // deja un cono trivial. El coste es ver el bus 1 ciclo de 27 MHz tarde
    // (37 ns) frente a los ~560 ns de un ciclo de E/S en turbo: irrelevante.
    reg        r_iorq_n = 1'b1, r_rd_n = 1'b1, r_wr_n = 1'b1, r_m1_n = 1'b1;
    reg [7:0]  r_addr = 8'd0, r_din = 8'd0;
    always @(posedge clk) begin
        r_iorq_n <= iorq_n;  r_rd_n <= rd_n;  r_wr_n <= wr_n;  r_m1_n <= m1_n;
        r_addr   <= addr;    r_din  <= din;
    end

    // ---- decodificacion: E4h..E7h, solo E/S y nunca en ciclo M1 -------------
    wire sel_e   = (r_addr[7:2] == 6'b111001) && (ID != 0 || r_addr[1]);
    wire sel_f4  = (ID == 2) && (r_addr == 8'hF4);       // estado de reset: un cerrojo de 8 bits que no se borra con el reset
    wire sel_a7  = (ID == 2) && (r_addr == 8'hA7);       // pausa / LED del R800
    wire nuestro = (sel_e | sel_f4 | sel_a7) && (r_iorq_n == 1'b0) && (r_m1_n == 1'b1);
    wire leer    = nuestro && (r_rd_n == 1'b0);
    wire escribir= nuestro && (r_wr_n == 1'b0);
    assign req   = leer;

    reg [3:0] indice   = 4'd0;
    reg       ff_rom   = 1'b1;      // el turboR arranca en modo ROM
    assign    rom_mode = ff_rom;
    reg [7:0] f4_reg   = 8'h00;     // ID 2: estado de reset (la BIOS distingue con el bit 7 arranque frio/caliente); se borra con el reset (ver abajo)
    reg [7:0] a7_reg   = 8'h00;     // ID 2: ultimo valor escrito en A7h (LED); la lectura da solo el boton de pausa
    initial   cpu_r800 = 1'b0;

    // ---- temporizador del sistema: un tick cada 3,911 us -------------------
    // Ese periodo es 3,579545 MHz / 14 = 255.682 Hz, o sea 105,6 ciclos de
    // nuestros 27 MHz: ni entero ni cerca de serlo. Un divisor a 106 daria un
    // 0,4% de error acumulandose para siempre, asi que se usa un acumulador
    // fraccionario en 1/64: sumar 64 por ciclo y descontar 6759 (= 105,6*64)
    // al desbordar deja el error en 0,009%.
    localparam [12:0] PASO   = 13'd64;
    localparam [12:0] UMBRAL = 13'd6759;

    reg  [12:0] acc = 13'd0;
    wire [12:0] acc_sig = acc + PASO;
    wire        tick    = (acc_sig >= UMBRAL);

    reg [15:0] contador = 16'd0;

    always @(posedge clk) begin
        if (!reset_n) begin
            acc      <= 13'd0;
            contador <= 16'd0;
            indice    <= 4'd0;
            ff_rom    <= 1'b1;
            turbo_set <= 1'b0;
            turbo_val <= 1'b0;
            cpu_r800  <= 1'b0;          // tras el reset manda el Z80
        end else begin
            acc <= tick ? (acc_sig - UMBRAL) : acc_sig;

            // La puesta a cero MANDA sobre el tick: si coinciden en el mismo
            // ciclo, el contador tiene que quedarse en 0 y no en 1.
            if (escribir && r_addr[1:0] == 2'd2) contador <= 16'd0;
            else if (tick)                     contador <= contador + 16'd1;

            if (escribir && r_addr[1:0] == 2'd0) indice <= r_din[3:0];
            // El registro 6 lleva DOS cosas: el modo ROM (bit 6) y la peticion
            // de cambio de CPU (bit 5). Contrastado con la implementacion de
            // HRA: cpu_change_target = wdata[5], y 1 = Z80, 0 = R800.
            turbo_set <= 1'b0;
            if (escribir && r_addr[1:0] == 2'd1 && indice == 4'd6) begin
                ff_rom    <= r_din[6];
                if (ID == 2) cpu_r800 <= ~r_din[5];
                else begin
                    turbo_set <= 1'b1;
                    turbo_val <= ~r_din[5];     // piden R800 (0) -> turbo ON
                end
            end
        end
    end
    // F4h y A7h (ID 2). El cerrojo de F4h SI se pone a 0 con el reset del MSX (04/11/2026, perfil TR): la BIOS del FS-A1ST, si ve
    // el bit 7 (arranque caliente), llama a CHGCPU(80h) ANTES de seleccionar la RAM en la pagina 3 (PPI A8h = 0 tras el reset),
    // asi que sus PUSH y LD (FFFD),SP se pierden, POP AF devuelve FFh, elige la entrada 04E9h de su tabla (E5h = 00h: R800 + DRAM)
    // y el R800, al arrancar en 0000 y repetir el mismo camino, acaba en LD SP,(FFFD) = FFFF, EI, RET a FFFF -> RST 38h en bucle
    // (CALL FD9A lee FFh): pantalla negra. Medido con el trazador de bus en la placa. openMSX tambien pone F4h a 0 en su reset
    // y arranca por el camino frio; con el bit 7 vivo solo valdria si la pagina 3 siguiera siendo RAM tras el reset (no lo es).
    always @(posedge clk) begin
        if (!reset_n) f4_reg <= 8'h00;
        else if (escribir && sel_f4) f4_reg <= r_din;
        if (!reset_n) a7_reg <= 8'h00;
        else if (escribir && sel_a7) a7_reg <= r_din;
    end

    // ---- lectura -----------------------------------------------------------
    function [7:0] leer_registro(input [3:0] idx, input pausa, input rom, input z80);
        case (idx)
            4'd5:    leer_registro = {1'b0, pausa, 6'd0};
            4'd6:    leer_registro = {1'b0, rom, z80, 5'd0};    // bit5: 1 = Z80, 0 = R800
            4'd13:   leer_registro = 8'h03;
            4'd14:   leer_registro = 8'h2F;
            4'd15:   leer_registro = 8'h8B;
            default: leer_registro = 8'hFF;
        endcase
    endfunction

    assign dout = sel_f4                    ? f4_reg
                : sel_a7                    ? {7'd0, pause_sw}   // bit 0 = boton de pausa (el BIOS espera a que se suelte)
                : (r_addr[1:0] == 2'd0) ? {4'd0, indice}
                : (r_addr[1:0] == 2'd1) ? leer_registro(indice, pause_sw, ff_rom, (ID == 2) ? ~cpu_is_r800 : ~turbo_on)
                : (r_addr[1:0] == 2'd2) ? contador[7:0]
                :                        contador[15:8];

endmodule

`default_nettype wire
