// ============================================================================
//  tr_cpu.v — las dos CPUs del perfil TR (Z80 y R800) sobre el mismo bus
//
//  El Z80 es el G80a de siempre (lo instancia top_zynq.v; aqui entran sus senales
//  de bus). El R800 es el nucleo de rampa069 (r800_cpu.v) con su bus (r800_bus.v) y su
//  regulador de tiempo (r800_timing.v), todo en clk (54 MHz) con el habilitador
//  ce21 de 21,477 MHz (35/88). Este modulo elige cual de las dos manda en el bus
//  y hace el cambio de CPU de la S1990 (R#6 bit 5).
//
//  EL CAMBIO DE CPU (como el del MSX turbo R de verdad, medido en openMSX con la BIOS del FS-A1ST)
//  --------------------------------------------------------------------------
//  Las dos CPUs son INDEPENDIENTES: cada una tiene sus registros y su PC, y el cambio solo
//  PARA a una en un limite de instruccion y SUELTA a la otra, que sigue exactamente donde la
//  dejo (la primera vez que se suelta el R800 arranca en 0000, como tras un reset). Por eso
//  CHGCPU de la BIOS apila todos los registros, guarda SP en FFFDh y los restaura al volver: es
//  la unica forma de "conservarlos". Ejemplo del arranque (openMSX): el Z80 escribe E5h = 40h
//  (R800) dentro de un OTIR de 2 bytes; el R800 arranca en 0000, lee F4h, y mas tarde pide el
//  Z80, que reanuda el OTIR y escribe su segundo byte (E5h = 60h).
//   * RUN: manda cur_r. Si la S1990 pide la otra (want_r800 != cur_r) pasa a FWAIT.
//   * FWAIT: la CPU vieja sigue hasta el siguiente limite de instruccion (el T1 de un M1 que no
//     sigue a un prefijo CB/DD/ED/FD, o un HALT) y se queda parada ahi con las senales fijas;
//     entonces manda la otra, que estaba parada en su T1.
//  La CPU que no manda esta PARADA (R800: CEN a 0; Z80: z_run a 0, que top_zynq.v mete en los
//  clk_enable/clk_falling del G80a) y sin interrupciones. Tras el reset manda el Z80 (como la
//  S1990 real) y el R800 se para en su primer M1 (direccion 0000).
// ============================================================================
`default_nettype none

module tr_cpu (
    input  wire        clk,             // 54 MHz
    input  wire        reset_n,         // reset de CPU (el mismo del Z80)
    input  wire        ce21,            // habilitador de 21,477 MHz
    // S1990
    input  wire        want_r800,       // CPU pedida (R#6 bit 5 = 0): 1 = R800
    input  wire        dram_mode,       // R#6 bit 6 = 0
    output wire        r800_cur,        // la CPU que manda es el R800
    // sistema
    input  wire [7:0]  cpu_din,         // lo que lee la CPU (ya multiplexado por el top)
    input  wire        r_wait_sys_n,    // esperas del sistema para el R800 (memoria, VDP, UART...)
    input  wire        int_n,
    input  wire        frz,             // DMA de la SD en curso (dma_frz): parar el R800 YA (la DMA ya manda en el puerto de RAM)
    input  wire        frz_soft,        // DMA pedida (dma_active) u OSD (iosys_frz): parar el R800 SOLO entre accesos de bus (ver mas abajo)
    input  wire [7:0]  ppi_a,
    input  wire [7:0]  exp0,
    input  wire [7:0]  exp3,
    output wire [15:0] bus_a,
    output wire [7:0]  bus_do,
    output wire        bus_m1_n, bus_mreq_n, bus_iorq_n, bus_rd_n, bus_wr_n, bus_rfsh_n,
    // lado Z80 (G80a)
    input  wire        z_m1_n, z_mreq_n, z_iorq_n, z_rd_n, z_wr_n, z_rfsh_n,
    input  wire [15:0] z_a,
    input  wire [7:0]  z_do,
    output wire [7:0]  z_di,
    input  wire        z_en_pre,        // el clk_enable del Z80 ANTES de aplicarle z_run (para reanudarlo sin perder la pareja enable/falling)
    output wire        z_run,           // 0 = el Z80 se para (clk_enable y clk_falling a 0)
    output wire        z_wait_ovr,      // sin uso en la version actual (0): WAIT_n del Z80 sin forzar
    output wire        z_int_mask,      // 1 = INT_n del Z80 forzado a 1 (el Z80 parado no ve interrupciones)
    output wire [7:0]  dbg,
    // telemetria (depuracion en placa por el buzon): ultimo M1 de cada CPU, ultimo acceso de E/S, estado vivo
    input  wire [4:0]  slot_dbg,        // {la memoria fue servida (any_ram_req), ppi_a[7:6], exp_slotx[7:6]} para el trazador
    input  wire [7:0]  ext_flags,       // senales de espera del sistema (las pone el top, solo para mirar)
    output wire [31:0] tel_a,           // {PC de la ultima M1 del R800, PC de la ultima M1 del Z80}
    output wire [31:0] tel_b,           // {direccion de la ultima E/S, direccion viva del bus}
    output wire [31:0] tel_c,           // {dato de la ultima E/S, ext_flags, M1 del R800 mod 65536}
    output wire [31:0] tel_d,           // {congelado, puntero del anillo[4:0], M1 del Z80 mod 1024, io_wr, cambios de CPU mod 128, banderas}
    input  wire        trc_clr,         // MBOX+0x2C bit 6: flanco de subida = descongelar el trazador y borrar los disparos
    input  wire        io_only,         // el trazador solo anota accesos de E/S (MBOX+0x2C bit 2)
    input  wire        frz_req,         // MBOX+0x1C bit 1: congelar el trazador ahora (flanco de subida)
    output wire        tr_full,         // trazador de 1024 eventos de bus congelado (se vuelca por el buzon)
    input  wire [9:0]  tr_rd_addr,
    output reg  [31:0] tr_rd_data,
    output wire [511:0] tel_ring        // anillo de 32 x 16 bits: 0..27 destinos de saltos (se congela al ejecutar en C000-DFFF), 28..31 ultimas escrituras a FFFD/FFFE
);
    reg        cur_r;                     // 1 = el R800 es la CPU del bus
    reg        fwait;                     // esperando a que la CPU vieja llegue a un limite de instruccion

    assign r800_cur = cur_r;

    // ---- R800 ---------------------------------------------------------------
    wire [15:0] r_a;
    wire [7:0]  r_do;
    wire        r_m1_n, r_mreq_n, r_iorq_n, r_rd_n, r_wr_n, r_rfsh_n, r_halt_n, r_done;
    wire        t_stall, t_io_hold, t_io_go;
    wire        r_int_n  = (cur_r & ~fwait) ? int_n : 1'b1;
    wire        r_active = cur_r & ~fwait;

    r800_timing u_t (
        .clk(clk), .ce21(ce21), .reset(!reset_n), .active(r_active),
        .m1_n(r_m1_n), .merq_n(r_mreq_n), .iorq_n(r_iorq_n), .rd_n(r_rd_n), .wr_n(r_wr_n), .rfsh_n(r_rfsh_n),
        .wait_n(r_wait_sys_n), .adr(r_a), .di(cpu_din), .ppi_a(ppi_a), .exp0(exp0), .exp3(exp3),
        .dram_mode(dram_mode), .stall(t_stall), .io_hold(t_io_hold), .io_go(t_io_go)
    );

    // ---- limites de instruccion ------------------------------------------------
    // Un seguidor de prefijos POR CPU (cada una mira solo sus senales: el camino G80a -> z_run no puede depender del R800, que va a 2 ciclos)
    // fin de un M1: prefijos (CB/ED: 2 bytes; DD/FD: el siguiente puede ser otro prefijo; DD CB d op: el cuarto byte no es M1)
    function [1:0] pnext(input [1:0] p, input [7:0] b);
        case (p)
        2'd0:    pnext = (b == 8'hCB || b == 8'hED) ? 2'd1 : (b == 8'hDD || b == 8'hFD) ? 2'd2 : 2'd0;
        2'd1:    pnext = 2'd0;
        default: pnext = (b == 8'hDD || b == 8'hFD) ? 2'd2 : (b == 8'hED) ? 2'd1 : 2'd0;
        endcase
    endfunction
    reg [1:0] pst_z, pst_r;
    reg [7:0] mb_z, mb_r;
    reg       md_z, md_r;
    wire m1rd_z = ~z_m1_n & ~z_mreq_n & ~z_rd_n;
    wire m1rd_r = ~r_m1_n & ~r_mreq_n & ~r_rd_n;
    wire [1:0] pe_z = (md_z & ~m1rd_z) ? pnext(pst_z, mb_z) : pst_z;     // ya con el M1 que acaba de terminar
    wire [1:0] pe_r = (md_r & ~m1rd_r) ? pnext(pst_r, mb_r) : pst_r;
    wire bnd_z = (pe_z == 2'd0);
    wire bnd_r = (pe_r == 2'd0);
    always @(posedge clk) begin
        if (!reset_n) begin pst_z <= 2'd0; pst_r <= 2'd0; mb_z <= 8'h00; mb_r <= 8'h00; md_z <= 1'b0; md_r <= 1'b0; end
        else begin
            md_z <= m1rd_z;  md_r <= m1rd_r;
            if (m1rd_z) mb_z <= cpu_din;
            if (m1rd_r) mb_r <= cpu_din;
            pst_z <= pe_z;  pst_r <= pe_r;
        end
    end

    wire r_t1 = ~r_m1_n & r_mreq_n & r_iorq_n;
    wire z_t1 = ~z_m1_n & z_mreq_n & z_iorq_n;

    // quien debe correr: la que manda, salvo mientras espera el cambio (entonces se para en su proximo limite)
    wire run_r = cur_r & ~fwait;
    wire run_z = ~cur_r & ~fwait;
    // parada: en el T1 de un M1 que es limite de instruccion (la CPU que no manda lleva su propio estado y no se mira)
    wire park_r = ~run_r & ((r_t1 & bnd_r) | ~r_halt_n);
    wire park_z = ~run_z & z_t1 & bnd_z;
    // El G80a avanza con parejas enable (flanco de subida: empieza el T-estado) / falling (mitad del T-estado). Se para entre las dos del T1 del M1 (z_hold),
    // y al reanudarlo se descarta el siguiente enable y se suelta: el siguiente pulso que ve es el falling que le faltaba.
    reg z_hold;
    always @(posedge clk) begin
        if (!reset_n) z_hold <= 1'b0;
        else if (park_z) z_hold <= 1'b1;
        else if (run_z && z_hold && z_en_pre) z_hold <= 1'b0;
    end
    assign z_run = ~(park_z | z_hold);

    // Una parada (DMA de la SD, OSD) NO puede pillar al R800 con un acceso de bus a medias: el dato que estaba a punto de tomar (ram_dout) lo
    // pisa la DMA (que pasa a mandar en el puerto de RAM) y al reanudarse lee basura (opcodes y operandos erroneos, bytes duplicados o perdidos).
    // El Z80 no lo sufre porque la DMA espera a que acabe su OUT y su proximo M1 tarda un T-state. El R800 empieza el siguiente acceso 2 ciclos
    // de clk despues, asi que se le deja acabar el acceso en curso y solo se le para con los strobes sueltos (fpga/r800/sim/run_mem.sh lo prueba).
    wire r_idle = r_mreq_n & r_iorq_n;
    // 04/11 (kanji con INIR): varios dispositivos del top registran el strobe de E/S a clk_27m (kanji D8h-DBh, PSG, RTC...) y su peticion
    // (p. ej. kanji_data_ram_req -> el mux de ram_addr) sigue viva 1-2 ciclos de clk_54m despues de que el R800 suelte IORQ; el R800 empezaba su
    // siguiente acceso de memoria (el INI escribe en (HL) justo despues del IN) con esa peticion aun en el mux y leia/escribia donde no era
    // (32 bytes del kanji por INIR: con el Z80 bien, con el R800 bytes de otro caracter). Tras cada E/S se retiene el reloj del R800 8 ciclos.
    reg  [3:0] r_pio = 4'd0;
    wire       r_io_any = ~r_iorq_n;
    always @(posedge clk) begin
        if (r_io_any) r_pio <= 4'd8;
        else if (r_pio != 4'd0) r_pio <= r_pio - 4'd1;
    end
    wire r_cen = ~t_stall & ~park_r & ~frz & ~(frz_soft & r_idle) & ~(r_pio != 4'd0 && !r_io_any);

    // acceso de E/S del R800 cuya hora aun no ha llegado (r800_timing la retiene): el sistema NO ve sus strobes y el R800 espera (WAIT) hasta que se los ve
    wire r_io_acc  = ~r_iorq_n & r_m1_n;                 // acceso de E/S (no el ack de interrupcion)
    wire r_io_mask = r_io_acc & ~t_io_go;
    r800_bus u_b (
        .clk(clk), .ce21(ce21), .RESET_n(reset_n), .CEN(r_cen),
        .WAIT_n(r_wait_sys_n & ~t_io_hold & ~r_io_mask),
        .INT_n(r_int_n), .NMI_n(1'b1),
        .M1_n(r_m1_n), .MREQ_n(r_mreq_n), .IORQ_n(r_iorq_n), .RD_n(r_rd_n), .WR_n(r_wr_n), .RFSH_n(r_rfsh_n),
        .HALT_n(r_halt_n), .done(r_done), .A(r_a), .DI(cpu_din), .DO(r_do)
    );

    assign z_di       = cpu_din;
    assign z_wait_ovr = 1'b0;
    assign z_int_mask = cur_r | fwait;

    wire park_cur = cur_r ? park_r : park_z;         // la vieja ya esta parada

    always @(posedge clk) begin
        if (!reset_n) begin
            cur_r <= 1'b0; fwait <= 1'b0;
        end else begin
            if (!fwait) begin
                if (want_r800 != cur_r) fwait <= 1'b1;
            end else begin
                if (want_r800 == cur_r) fwait <= 1'b0;                 // pedido anulado
                else if (park_cur) begin cur_r <= ~cur_r; fwait <= 1'b0; end
            end
        end
    end

    // ---- salida al bus del sistema -----------------------------------------------
    assign bus_a  = cur_r ? r_a  : z_a;
    // El dato de escritura se MANTIENE despues del strobe de WR: varios registros del top (los de subslot FFFFh, los de slot, etc.) toman cpu_dout
    // en clk_27m con un request registrado que sigue activo 1-2 ciclos DESPUES de que acabe el strobe; el T80 mantiene DO hasta el ciclo siguiente,
    // pero el R800 cambia DO nada mas acabar el acceso (p. ej. LD (FFFF),A seguido de LD A,B) y el registro tomaba el dato nuevo.
    reg [7:0] do_h = 8'd0;
    always @(posedge clk) if (!r_wr_n) do_h <= r_do;
    assign bus_do = cur_r ? (r_wr_n ? do_h : r_do) : z_do;
    assign bus_m1_n   = cur_r ? r_m1_n   : z_m1_n;
    assign bus_mreq_n = cur_r ? r_mreq_n : z_mreq_n;
    // E/S del R800: el sistema solo ve el acceso cuando llega su hora (r800_timing retiene la E/S hasta su instante exacto: 62 ciclos entre accesos al
    // VDP, ciclos pares...). Sin esto el periferico atendia la E/S al CAIDA del strobe y el R800 la retenia hasta 8 us mas: dos IN (98h) seguidos
    // llegaban al VDP con 0,3 us de separacion en vez de 8,7 us, el VDP devolvia el byte anterior (rancio) y el texto salia repetido o perdido.
    assign bus_iorq_n = cur_r ? (r_iorq_n | r_io_mask) : z_iorq_n;
    assign bus_rd_n   = cur_r ? (r_rd_n   | r_io_mask) : z_rd_n;
    assign bus_wr_n   = cur_r ? (r_wr_n   | r_io_mask) : z_wr_n;
    // el R800 no saca su "peticion de refresco" (r_rfsh_n, que solo mira r800_timing) al sistema: la DDR se refresca sola y esa
    // senal baja en mitad de los accesos
    assign bus_rfsh_n = cur_r ? 1'b1 : z_rfsh_n;

    assign dbg = {3'b0, fwait, cur_r, pst_z, r_halt_n};

    // ---- telemetria y trazador de bus: solo con TR_DEBUG (build.tcl: variable de entorno TR_DEBUG=1). En produccion las salidas son 0 ----
`ifdef TR_DEBUG
    // ---- telemetria ----
    wire        tm_m1  = ~bus_m1_n & ~bus_mreq_n & ~bus_rd_n;
    wire        tm_io  = ~bus_iorq_n & bus_m1_n & (~bus_rd_n | ~bus_wr_n);
    reg         tm_m1_q = 1'b0, tm_io_q = 1'b0, io_wr = 1'b0;
    reg  [15:0] pc_r = 16'd0, pc_z = 16'd0, io_a = 16'd0, cnt_r = 16'd0, cnt_z = 16'd0;
    reg  [7:0]  io_d = 8'd0;
    reg  [6:0]  sw_cnt = 7'd0;
    reg         cur_q = 1'b0;
    always @(posedge clk) begin
        tm_m1_q <= tm_m1;  tm_io_q <= tm_io;  cur_q <= cur_r;
        if (cur_q != cur_r) sw_cnt <= sw_cnt + 7'd1;
        if (tm_m1 & ~tm_m1_q) begin
            if (cur_r) begin pc_r <= bus_a; cnt_r <= cnt_r + 16'd1; end
            else       begin pc_z <= bus_a; cnt_z <= cnt_z + 16'd1; end
        end
        if (tm_io & ~tm_io_q) begin io_a <= bus_a; io_d <= bus_do; io_wr <= ~bus_wr_n; end
        // 04/11: en un IN, io_d guarda el dato LEIDO (cpu_din del ultimo ciclo del strobe, el que toma la CPU), no el ultimo escrito (do_h)
        if (tm_io & bus_wr_n) io_d <= cpu_din;
    end
    // anillo de saltos: destino de cada M1 que no sigue al anterior (sin repetir el ultimo). Se congela (rfrz) 64 M1 del R800 despues del
    // 5.o cambio de CPU (el que lo suelta tras la inicializacion de las extensiones). Aparte: ultimas 4 escrituras a FCh-FFh (mapper) y lo que se
    // escribio y se leyo en FFFD/FFFE (el SP que guarda y recupera CHGCPU).
    reg [15:0] ring [0:23];
    reg [15:0] rtgt = 16'd0;
    reg [15:0] mw0 = 16'd0, mw1 = 16'd0, mw2 = 16'd0, mw3 = 16'd0;   // {cpu, puerto[1:0], dato[7:0]}
    reg [4:0]  rwp = 5'd0;
    reg        rfrz = 1'b0;
    reg [15:0] last_pc = 16'd0;
    reg [15:0] a_live = 16'd0;
    reg [7:0]  flags_q = 8'd0;
    reg        frq_q = 1'b0;
    reg        clr_q = 1'b0;
    wire       trc_clr_p = trc_clr & ~clr_q;
    reg [7:0]  postc = 8'd0;
    reg [7:0]  sp_lo = 8'd0, sp_hi = 8'd0, rd_lo = 8'd0, rd_hi = 8'd0;
    reg [15:0] w_pc = 16'd0, r_pc = 16'd0;
    wire       tm_wr = ~bus_mreq_n & ~bus_wr_n;
    wire       tm_rd = ~bus_mreq_n & ~bus_rd_n & bus_m1_n;
    reg        tm_wr_q = 1'b0;
    wire [15:0] pc_now = cur_r ? pc_r : pc_z;
    wire       wnew = tm_wr & ~tm_wr_q;
    integer ri;
    initial for (ri = 0; ri < 24; ri = ri + 1) ring[ri] = 16'd0;
    always @(posedge clk) begin
        a_live <= bus_a;
        frq_q <= frz_req;  clr_q <= trc_clr;
        if (frz_req & ~frq_q) rfrz <= 1'b1;
        flags_q <= {cur_r, fwait, r_halt_n, t_stall, t_io_hold, r_wait_sys_n, want_r800, dram_mode};
        tm_wr_q <= tm_wr;
        if (tm_m1 & ~tm_m1_q & ~rfrz) begin
            last_pc <= bus_a;
            if (bus_a != last_pc + 16'd1 && bus_a != last_pc + 16'd2 && bus_a != last_pc + 16'd3 && bus_a != last_pc + 16'd4 && bus_a != rtgt) begin
                ring[rwp] <= bus_a;  rtgt <= bus_a;
                rwp <= (rwp == 5'd23) ? 5'd0 : rwp + 5'd1;
            end
            if (cur_r && sw_cnt == 7'd5) begin
                if (postc != 8'd255) postc <= postc + 8'd1;
                if (postc >= 8'd64 && bus_a == 16'hFFFF) rfrz <= 1'b1;   // el R800 ejecuta en FFFF (se ha ido por las ramas) tras el 5.o cambio
            end
        end
        if (tm_io & ~tm_io_q & ~bus_wr_n & ~rfrz & (bus_a[7:2] == 6'b111111)) begin
            mw0 <= {5'd0, cur_r, bus_a[1:0], bus_do}; mw1 <= mw0; mw2 <= mw1; mw3 <= mw2;
        end
        if (wnew & ~rfrz) begin
            if (bus_a == 16'hFFFD) begin sp_lo <= bus_do; w_pc <= pc_now; end
            if (bus_a == 16'hFFFE) sp_hi <= bus_do;
        end
        if (tm_rd & ~rfrz) begin
            if (bus_a == 16'hFFFD) begin rd_lo <= cpu_din; r_pc <= pc_now; end
            if (bus_a == 16'hFFFE) rd_hi <= cpu_din;
        end
        if (trc_clr_p) rfrz <= 1'b0;
    end
    // ---- trazador de bus: 1024 eventos {tipo[31:30] (0 M1, 1 lectura de memoria, 2 escritura, 3 E/S), cpu[29], 0, direccion[27:12], dato[11:4], seq[3:0]} ----
    // El anillo se congela con rfrz y el buzon lo vuelca a MBOX+0x1000 (la posicion de escritura sale en tel_d[25:16]).
    reg [31:0] tmem [0:1023];
    reg [9:0]  twp = 10'd0;
    reg [3:0]  tseq = 4'd0;
    reg        tarm = 1'b0, tfrz = 1'b0;
    reg [4:0]  tcnt = 5'd0;
    reg [4:0]  nopc = 5'd0;
    reg        tarm3 = 1'b0, iow_q = 1'b0;
    reg [5:0]  tcnt3 = 6'd0;
    reg [7:0]  last98 = 8'd0;
    reg [5:0]  c99 = 6'd0;
    reg        tarm2 = 1'b0;
    reg [5:0]  tcnt2 = 6'd0;
    reg [1:0]  k_q = 2'd0;  reg act_q = 1'b0;
    reg [15:0] ta_q = 16'd0; reg [7:0] td_q = 8'd0; reg cpu_qq = 1'b0; reg [4:0] sd_q = 5'd0;
    wire       a_rd  = ~bus_mreq_n & ~bus_rd_n & bus_m1_n;
    wire       a_wr  = ~bus_mreq_n & ~bus_wr_n;
    wire       a_io  = tm_io;
    wire       a_any = tm_m1 | a_rd | a_wr | a_io;
    wire [1:0] a_k   = tm_m1 ? 2'd0 : a_io ? 2'd3 : a_wr ? 2'd2 : 2'd1;
    always @(posedge clk) begin
        act_q <= a_any;
        if (a_any) begin iow_q <= a_io & ~bus_wr_n; k_q <= a_k; ta_q <= bus_a; td_q <= (a_wr | (a_io & ~bus_wr_n)) ? bus_do : cpu_din; cpu_qq <= cur_r; sd_q <= slot_dbg; end
        if (act_q & ~a_any & ~rfrz & ~tfrz & (~io_only | (k_q == 2'd3))) begin
            tmem[twp] <= {k_q, cpu_qq, sd_q[4], ta_q, td_q, sd_q[3:0]};
            twp <= twp + 10'd1;  tseq <= tseq + 4'd1;
            // disparo: un M1 en 0038 que lee FF (RST 38 en bucle: la BIOS no esta visible en la pagina 0); se congela 24 eventos despues
            if (k_q == 2'd0 && ta_q == 16'h0038 && td_q == 8'hFF && !tarm) tarm <= 1'b1;
            // disparo 2: 24 NOP seguidos (el R800 se ha ido a un hueco de relleno de una ROM)
            if (k_q == 2'd0) begin
                if (td_q == 8'h00) begin nopc <= nopc + 5'd1; if (nopc == 5'd23) tfrz <= 1'b1; end
                else nopc <= 5'd0;
            end
            // disparo 3: lectura de memoria de la direccion 002Dh (PEEK(&H2D)): se congela 40 eventos despues
            if (k_q == 2'd1 && ta_q == 16'h002D && cpu_qq && postc == 8'd255 && !tarm2) tarm2 <= 1'b1;
            if (tarm2) begin tcnt2 <= tcnt2 + 6'd1; if (tcnt2 == 6'd40) tfrz <= 1'b1; end
            // disparo 4: dos escrituras seguidas al 98h con el mismo dato (que no sea 20h/00h/FFh): caracter repetido en pantalla
            if (k_q == 2'd3 && iow_q && ta_q[7:0] == 8'h98) begin
                last98 <= td_q;
                if (td_q == last98 && td_q != 8'h20 && td_q != 8'h00 && td_q != 8'hFF && !tarm3 && 1'b0) tarm3 <= 1'b1;   // desactivado (el relleno 55h del test de VRAM lo dispara)
            end
            // disparo 5: 40 lecturas seguidas del puerto 99h (bucle de espera del estado del VDP): se congela con el principio del bucle y lo anterior en el anillo
            if (k_q == 2'd3) begin
                if (ta_q[7:0] == 8'h99 && !iow_q) begin c99 <= c99 + 6'd1; if (c99 == 6'd39) tfrz <= 1'b1; end
                else c99 <= 6'd0;
            end
            if (tarm3) begin tcnt3 <= tcnt3 + 6'd1; if (tcnt3 == 6'd40) tfrz <= 1'b1; end
            if (tarm) begin tcnt <= tcnt + 5'd1; if (tcnt == 5'd24) tfrz <= 1'b1; end
        end
        if (trc_clr_p) begin tfrz <= 1'b0; tarm <= 1'b0; tarm2 <= 1'b0; tarm3 <= 1'b0; tcnt <= 5'd0; tcnt2 <= 6'd0; tcnt3 <= 6'd0; nopc <= 5'd0; c99 <= 6'd0; end
        tr_rd_data <= tmem[tr_rd_addr];
    end
    assign tr_full = rfrz | tfrz;
    assign tel_a = {pc_r, pc_z};
    assign tel_b = {io_a, a_live};
    assign tel_c = {io_d, ext_flags, cnt_r};
    assign tel_d = {rfrz | tfrz, 5'd0, twp, io_wr, sw_cnt, flags_q};
    genvar gi;
    generate for (gi = 0; gi < 24; gi = gi + 1) begin : g_ring
        assign tel_ring[16*gi +: 16] = ring[gi];
    end endgenerate
    assign tel_ring[16*24 +: 16] = mw0;
    assign tel_ring[16*25 +: 16] = mw1;
    assign tel_ring[16*26 +: 16] = mw2;
    assign tel_ring[16*27 +: 16] = mw3;
    assign tel_ring[16*28 +: 16] = {rd_hi, rd_lo};                    // ultimo SP leido de FFFD/FFFE (LD SP,(FFFD) de CHGCPU)
    assign tel_ring[16*29 +: 16] = r_pc;                              // PC de esa lectura
    assign tel_ring[16*30 +: 16] = {sp_hi, sp_lo};                    // ultimo SP guardado en FFFD/FFFE
    assign tel_ring[16*31 +: 16] = w_pc;                              // PC de esa escritura
`else
    assign tel_a = 32'd0;  assign tel_b = 32'd0;  assign tel_c = 32'd0;  assign tel_d = 32'd0;
    assign tel_ring = 512'd0;  assign tr_full = 1'b0;
    always @* tr_rd_data = 32'd0;
`endif
endmodule

`default_nettype wire
