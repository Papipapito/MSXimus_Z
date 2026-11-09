// musica_sound.v -- perfil "Musica" del MSXimus Z (Zynq): YM2151 (Yamaha SFG-01/05) y SN76489 (Franky, PlaySoniq).
//
// Solo se compila con el perfil Musica (build.tcl ... musica -> `define PERFIL_MUSICA en top_zynq.v). Todo en clk_54m
// con el habilitador de 3,6 MHz del bus (clk_enable_3m6_54), igual que el OPLL y el Y8950; el bus del Z80 llega crudo y
// aqui se registra. Nucleos: jt51 (YM2151) y jt89 (SN76489), de Jotego, GPLv3 (fpga/jt51, fpga/jt89).
//
// ---- Yamaha SFG-01/05 (ranura 0-1) ----
// Cartucho de ROM de 16 KB repetido en las cuatro paginas del slot (openMSX, MSXYamahaSFG.cc). El chip esta en los ultimos
// bytes de cada 16 KB: 3FF0h = registro del OPM (escritura; la lectura da FFh), 3FF1h = dato (escritura) / estado
// (lectura: bit 7 ocupado, bits 1-0 banderas de los temporizadores). 3FF2h-3FF7h (teclado y MIDI del YM2148) no estan:
// se leen como FFh y se ignoran. La ROM es PROPIA y minima (la de Yamaha tiene copyright): solo lleva la cadena "MCHFM0"
// en 0080h con la que VGMPlay detecta el cartucho (SFG_ID_ADDRESS = 80h) y el byte de 0088h con el nibble alto a 0
// (= SFG-01); no tiene cabecera "AB", asi que la BIOS no la inicia. 256 bytes en LUT: sin BRAM ni dependencia del pack.
// La interrupcion de los temporizadores va al /INT del Z80 (en openMSX el YM2151 tiene su IRQHelper); el YM2148 (MIDI) no.
//
// ---- SN76489 ----
// Franky: escritura en 48h y 49h (el contador vertical se lee en 48h y el horizontal en 49h; la deteccion de VGMPlay
// comprueba que el vertical sube de uno en uno). Solo responde si la E/S conmutada no tiene elegido otro dispositivo:
// 48h es de la SD por puertos con el dispositivo 48h (OUT 40h,48h) y VGMPlay hace OUT 40h,0 antes de detectar.
// PlaySoniq: indice en 2Ah y dato en 2Bh. Registro 1Eh = base del SN76489 (bit 0 = "inhibir lectura": se guarda y no
// hace nada, el SN no se lee); el chip responde a las dos direcciones base&FEh y base|1. Registro 1Dh = base del VDP
// (solo se guarda: VGMPlay comprueba que no valga 01h). Reset: ambos a 00h y el SN de PlaySoniq apagado hasta que la
// base sea distinta de 00h/01h. El Musical Memory Mapper (3Ch-3Fh) no esta: su puerto de sonido solo se habilita con un
// bit del registro de control que unicamente se escribe por memoria (80FCh...), asi que no hay forma de activarlo con
// un OUT y no tiene sentido aqui.
module musica_sound (
    input  wire        clk,          // clk_54m
    input  wire        rst_n,        // bus_reset_n
    input  wire        cen,          // clk_enable_3m6_54: 1 ciclo de cada 15
    // bus del Z80
    input  wire [15:0] addr,
    input  wire [7:0]  din,          // cpu_dout (lo que escribe el Z80)
    input  wire        mreq_n,
    input  wire        iorq_n,
    input  wire        rd_n,
    input  wire        wr_n,
    input  wire        m1_n,
    input  wire        sfg_slot,     // la ranura 0-1 esta elegida en la pagina de addr
    input  wire        io48_wr_ok,   // 48h/49h libres para escribir (el dispositivo 48h de la E/S conmutada no esta elegido)
    input  wire        io48_rd_ok,   // 48h/49h libres para leer (ningun dispositivo de la E/S conmutada esta elegido)
    // respuesta
    output wire [7:0]  dout,
    output wire        dout_sel,     // 1: este modulo contesta la lectura en curso
    output wire        int_n,        // IRQ del YM2151 (activo bajo)
    // audio
    output wire signed [15:0] sfg_l, // YM2151, izquierda
    output wire signed [15:0] sfg_r, // YM2151, derecha
    output wire signed [10:0] sn_snd // SN76489 (mono): 3 tonos + ruido, +-1020
);

    // ------------------------------------------------------------ ROM propia del SFG
    // Offset dentro de los 16 KB; fuera de los primeros 256 bytes todo FFh. Texto en ASCII.
    function [7:0] sfg_rom(input [7:0] a);
        case (a)
            8'h80: sfg_rom = 8'h4D;   // M
            8'h81: sfg_rom = 8'h43;   // C
            8'h82: sfg_rom = 8'h48;   // H
            8'h83: sfg_rom = 8'h46;   // F
            8'h84: sfg_rom = 8'h4D;   // M
            8'h85: sfg_rom = 8'h30;   // 0
            8'h86: sfg_rom = 8'h00;
            8'h87: sfg_rom = 8'h00;
            8'h88: sfg_rom = 8'h00;   // nibble alto 0 = SFG-01 (distinto de 0 = SFG-05)
            8'h90: sfg_rom = 8'h4D;   // "MSXimus z SFG-01"
            8'h91: sfg_rom = 8'h53;
            8'h92: sfg_rom = 8'h58;
            8'h93: sfg_rom = 8'h69;
            8'h94: sfg_rom = 8'h6D;
            8'h95: sfg_rom = 8'h75;
            8'h96: sfg_rom = 8'h73;
            8'h97: sfg_rom = 8'h20;
            8'h98: sfg_rom = 8'h7A;
            8'h99: sfg_rom = 8'h20;
            8'h9A: sfg_rom = 8'h53;
            8'h9B: sfg_rom = 8'h46;
            8'h9C: sfg_rom = 8'h47;
            8'h9D: sfg_rom = 8'h2D;
            8'h9E: sfg_rom = 8'h30;
            8'h9F: sfg_rom = 8'h31;
            default: sfg_rom = 8'hFF;
        endcase
    endfunction

    // ------------------------------------------------------------ decodificacion
    wire mem_wr = ~mreq_n & ~wr_n;
    wire mem_rd = ~mreq_n & ~rd_n;
    wire io_wr  = ~iorq_n & m1_n & ~wr_n;
    wire io_rd  = ~iorq_n & m1_n & ~rd_n;

    wire fk_port    = (addr[7:1] == 7'b0100100);                 // 48h-49h
    wire sfg_regs   = (addr[13:1] == 13'h1FF8);                  // 3FF0h-3FF1h dentro de cada 16 KB
    wire sfg_wr_any = mem_wr & sfg_slot & sfg_regs;
    wire fk_wr_any  = io_wr & io48_wr_ok & fk_port;
    wire pi_wr_any  = io_wr & (addr[7:0] == 8'h2A);              // PlaySoniq: indice
    wire pd_wr_any  = io_wr & (addr[7:0] == 8'h2B);              // PlaySoniq: dato

    // PlaySoniq: registros 1Dh (base del VDP) y 1Eh (base del SN76489)
    reg  [7:0] ps_idx     = 8'd0;
    reg  [7:0] ps_vdpbase = 8'd0;
    reg  [7:0] ps_psgbase = 8'd0;
    wire       ps_psg_en  = (ps_psgbase[7:1] != 7'd0);           // 00h/01h = apagado
    wire       ps_wr_any  = io_wr & ps_psg_en & (addr[7:1] == ps_psgbase[7:1]);

    // Cada escritura se detecta en el flanco de subida de su decodificacion (retrasada un ciclo: el dato ya es estable)
    reg [1:0] d_sfg = 2'b00, d_fk = 2'b00, d_ps = 2'b00, d_pi = 2'b00, d_pd = 2'b00;
    always @(posedge clk) begin
        d_sfg <= {d_sfg[0], sfg_wr_any};
        d_fk  <= {d_fk[0],  fk_wr_any};
        d_ps  <= {d_ps[0],  ps_wr_any};
        d_pi  <= {d_pi[0],  pi_wr_any};
        d_pd  <= {d_pd[0],  pd_wr_any};
    end
    wire sfg_stb = d_sfg[0] & ~d_sfg[1];
    wire fk_stb  = d_fk[0]  & ~d_fk[1];
    wire ps_stb  = d_ps[0]  & ~d_ps[1];
    wire pi_stb  = d_pi[0]  & ~d_pi[1];
    wire pd_stb  = d_pd[0]  & ~d_pd[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            ps_idx <= 8'd0; ps_vdpbase <= 8'd0; ps_psgbase <= 8'd0;
        end else begin
            if (pi_stb) ps_idx <= din;
            if (pd_stb) begin
                if (ps_idx == 8'h1D) ps_vdpbase <= din;
                if (ps_idx == 8'h1E) ps_psgbase <= din;
            end
        end
    end

    // ------------------------------------------------------------ YM2151 (jt51)
    // cen_p1 = la mitad de cen (el nucleo corre sus 32 operadores a 1,8 MHz). La escritura entra como UN ciclo que coincide
    // con cen_p1: jt51 escribe sus registros en cada ciclo de clk con write alto y cuenta el "ocupado" solo en cen_p1.
    reg p1_t = 1'b0;
    always @(posedge clk) if (cen) p1_t <= ~p1_t;
    wire cen_p1 = cen & p1_t;

    reg       sfg_pend = 1'b0;
    reg [7:0] sfg_d    = 8'd0;
    reg       sfg_a0   = 1'b0;
    always @(posedge clk) begin
        if (!rst_n) sfg_pend <= 1'b0;
        else if (sfg_stb) begin sfg_pend <= 1'b1; sfg_d <= din; sfg_a0 <= addr[0]; end
        else if (sfg_pend & cen_p1) sfg_pend <= 1'b0;
    end
    wire sfg_wr = sfg_pend & cen_p1;

    wire [7:0] ym_dout;
    wire       ym_irq_n;
    wire signed [15:0] ym_xl, ym_xr;
    jt51 u_ym2151 (
        .rst   (~rst_n),
        .clk   (clk),
        .cen   (cen),
        .cen_p1(cen_p1),
        .cs_n  (1'b0),
        .wr_n  (~sfg_wr),
        .a0    (sfg_a0),
        .din   (sfg_d),
        .dout  (ym_dout),
        .ct1   (),
        .ct2   (),
        .irq_n (ym_irq_n),
        .sample(),
        .left  (),
        .right (),
        .xleft (ym_xl),
        .xright(ym_xr)
    );
    assign int_n = ym_irq_n;
    assign sfg_l = ym_xl;
    assign sfg_r = ym_xr;

    // ------------------------------------------------------------ SN76489 (jt89)
    // jt89 acepta la escritura en el flanco de subida de ~cs_n & ~wr_n (sin ready): un pulso de un ciclo con el dato
    // ya retenido en sn_d.
    reg [7:0] sn_d    = 8'd0;
    reg       sn_cs_n = 1'b1;
    wire      sn_stb  = fk_stb | ps_stb;
    always @(posedge clk) begin
        sn_cs_n <= ~sn_stb;
        if (sn_stb) sn_d <= din;
    end
    jt89 #(.INTERPOL16(0)) u_sn76489 (
        .rst   (~rst_n),
        .clk   (clk),
        .clk_en(cen),
        .wr_n  (1'b0),
        .cs_n  (sn_cs_n),
        .din   (sn_d),
        .sound (sn_snd),
        .ready ()
    );

    // ------------------------------------------------------------ contadores de Franky (lineas de un VDP de Sega NTSC)
    // 54 MHz / 3432 = 15,734 kHz. El vertical sube de uno en uno (VGMPlay exige diferencia exacta de 1); el horizontal es la
    // posicion en la linea, 0..214.
    reg [11:0] fk_ph = 12'd0;
    reg [7:0]  fk_v  = 8'd0;
    always @(posedge clk) begin
        if (!rst_n) begin fk_ph <= 12'd0; fk_v <= 8'd0; end
        else if (fk_ph == 12'd3431) begin fk_ph <= 12'd0; fk_v <= fk_v + 8'd1; end
        else fk_ph <= fk_ph + 12'd1;
    end

    // ------------------------------------------------------------ lecturas
    wire sfg_rd = mem_rd & sfg_slot;
    wire fk_rd  = io_rd & io48_rd_ok & fk_port;
    wire ps_rd  = io_rd & (addr[7:0] == 8'h2B);

    wire [7:0] sfg_data = (addr[13:0] == 14'h3FF1) ? ym_dout :                       // estado del OPM
                          (addr[13:3] == 11'h7FE)  ? 8'hFF :                         // 3FF0h-3FF7h: sin teclado ni MIDI
                          (addr[13:8] == 6'd0)     ? sfg_rom(addr[7:0]) : 8'hFF;
    wire [7:0] ps_data  = (ps_idx == 8'h1D) ? ps_vdpbase :
                          (ps_idx == 8'h1E) ? ps_psgbase : 8'hFF;

    assign dout_sel = sfg_rd | fk_rd | ps_rd;
    assign dout     = sfg_rd ? sfg_data :
                      fk_rd  ? (addr[0] ? fk_ph[11:4] : fk_v) : ps_data;

endmodule
