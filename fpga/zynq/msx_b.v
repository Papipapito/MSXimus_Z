// ============================================================================
//  msx_b.v - La MAQUINA B del perfil "Dual" del MSXimus Z (31/10/2026, prueba de concepto)
// ----------------------------------------------------------------------------
//  Un MSX2+ minimo, entero, sin compartir estado con la maquina A (top_zynq.v): su Z80 (G80a), su V9968 con su cache de VRAM, su
//  PSG, su PPI con la matriz del teclado, su mapper de RAM, su cartucho (megaram_scc) y su RTC. Lo unico que comparten las dos
//  maquinas es lo que es de solo lectura (la BIOS y la SUB-ROM del pack, en la DDR), la cadencia de 3,58 MHz (los pulsos de
//  habilitacion del reloj), el teclado USB (con foco: solo lo ve la maquina enfocada) y la salida HDMI.
//
//  Mapa de B (el mismo orden que A, sin menu ni Nextor ni WiFi ni disco):
//    slot 0     BIOS de 32 KB (BIOS + BASIC), del pack de A (DDR 0x10F60000, solo lectura)
//    slot 1     el cartucho: megaram_scc con el mapper que diga map_sel (Konami 4/SCC/ASCII8/ASCII16) o lineal; su memoria esta
//               en la zona de B de la DDR (RAM_BASE + 0x400000 con A21 = 0, + 0x200000 con A21 = 1: hasta 4 MB). Con cart_en = 0 el
//               slot esta vacio (la DDR arranca con basura y la BIOS la tomaria por un cartucho). Una ROM PLANA (hasta 32 KB, sin mapper)
//               es el modo lineal con una imagen de 64 KB que compone dual_rom.tcl cargar (FF, la ROM en su pagina, FF): no hay otro modo
//    slot 3-0   mapper de RAM de 2 MB (registros FCh-FFh), en la zona de B de la DDR (RAM_BASE + 0x000000)
//    slot 3-1   SUB-ROM de 16 KB, pagina 0 (pack de A, DDR 0x10F68000). Su pagina 1 (en A, el menu y el logo) lee C9h (RET) en todo el
//               rango: la SUB-ROM llama por el NMI (hook FDD6h) al menu de A en 3-1:7A00h; en B vuelve en el acto y la BIOS arranca
//               directa al BASIC, sin menu ni logo
//    slot 2     vacio
//  Puertos: A0h-A2h PSG, A8h-ABh PPI, 98h-9Bh V9968, B4h-B5h RTC, FCh-FFh mapper. El joystick de B no existe (el registro 14 del
//  PSG lee FFh). Sin SCC, sin FM, sin OPL4: el sonido de B es su PSG.
//
//  Memoria: memory_axi (la misma de A) con una cache pequena (LINES_LOG, 4 KB por defecto) en una zona propia (RAM_BASE, 8 MB;
//  bit 23 de ram_addr = 0) y la ventana de A (EXT_BASE, bit 23 = 1) para la BIOS. Sale por un maestro AXI3 de 64 bits a clk_54m
//  (HP2, detras de axi_arb2w). La VRAM de B: v9968_axi_backend (HP0, a fclk0, detras de axi_arb2w) en VRAM_BASE + VRAM_OFF.
//
//  Video: el V9968 de B saca 480 lineas dobladas; aqui se queda con UNA de cada dos (la cuenta de lineas por VS) y la entrega al
//  puente del V9990 (msx2hdmi_v9990, que escribe el frame buffer de B en la DDR y lo lee con el raster de la HDMI) con 5 bits por
//  color, HS/VS/DE activos altos y un pixel por `ce` (el ce86 de A: 1 de cada 2 ciclos de clk_86).
//
//  Reset: rstb_n = reset de A (sys_rst_n: MSX_RUN, S1, reset de la configuracion) y run. Con run = 0 B esta parada, su cache
//  invalidada y su video en reset: la DDR se puede escribir por JTAG sin que nadie la lea.
//
//  Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module msx_b #(
    parameter [31:0] RAM_BASE  = 32'h0C00_0000,   // zona propia de B en la DDR (ventana de 8 MB)
    parameter [31:0] EXT_BASE  = 32'h1080_0000,   // ventana de A (bit 23 de ram_addr = 1): el pack de BIOS, solo lectura
    parameter [31:0] VRAM_BASE = 32'h1000_0000,   // base del backend de VRAM (como A)
    parameter [21:0] VRAM_OFF  = 22'h380000,      // VRAM de B: 0x10380000 (256 KB; justo detras de la del V9990, 0x10300000, y delante de su frame buffer, 0x10400000)
    parameter        LINES_LOG = 8                // cache de la RAM de B: 2^LINES_LOG lineas de 16 B
)(
    input  wire         clk_54m,
    input  wire         clk_27m,
    input  wire         clk_86,
    input  wire         fclk0,
    input  wire         fclk_aresetn,             // reset AXI de HP0 (fclk0)
    input  wire         rst54_n,                  // reset AXI de HP2 (clk_54m)
    input  wire         sys_rst_n,                // reset de A (bus_reset_n), clk_54m
    input  wire         pll86_lock,
    input  wire         run,                      // 1 = B corre (B_CTL[0]), clk_54m
    input  wire         cart_en,                  // 1 = el slot 1 tiene cartucho (B_CTL[1])
    input  wire [1:0]   map_sel,                  // mapper del cartucho (B_CTL[4:3]): 0 Konami4, 1 ASCII8, 2 Konami SCC, 3 ASCII16
    input  wire         map_linear,               // cartucho lineal desde 0000h (B_CTL[5]); con una imagen de 64 KB = cartucho plano
    input  wire         cen_3m6_54,               // los pulsos de 3,58 MHz de A (clk_54m)
    input  wire         cfall_3m6_54,
    input  wire         cen_3m6_27,               // y el de clk_27m (RTC y filtro del PSG)
    input  wire [127:0] keyboard,                 // bitmap HID para B (ya filtrado por el foco), clk_27m
    input  wire         ce86,                     // 1 pixel de cada 2 ciclos de clk_86

    // ---- video hacia msx2hdmi_v9990 (clk_86) ----
    output wire         vid_ce,
    output wire [4:0]   vid_r,
    output wire [4:0]   vid_g,
    output wire [4:0]   vid_b,
    output wire         vid_hs,
    output wire         vid_vs,
    output wire         vid_de,

    // ---- sonido: el PSG de B, mono, ya sin continua (clk_27m) ----
    output wire signed [16:0] psg_ac,

    // ---- estado y telemetria ----
    output wire         running,                  // B fuera de reset
    output wire [31:0]  tel_a,                    // {PC de la ultima M1[31:16], escrituras al VDP[15:0]}
    output wire [31:0]  tel_b,                    // {fotogramas del VDP[31:16], A8h[15:8], lecturas de RAM con fallo[7:0]}

    // ---- AXI3 maestro 64 bits de la RAM de B (clk_54m) ----
    output wire [5:0]   M2_AWID,
    output wire [31:0]  M2_AWADDR,
    output wire [3:0]   M2_AWLEN,
    output wire [2:0]   M2_AWSIZE,
    output wire [1:0]   M2_AWBURST,
    output wire [1:0]   M2_AWLOCK,
    output wire [3:0]   M2_AWCACHE,
    output wire [2:0]   M2_AWPROT,
    output wire [3:0]   M2_AWQOS,
    output wire         M2_AWVALID,
    input  wire         M2_AWREADY,
    output wire [5:0]   M2_WID,
    output wire [63:0]  M2_WDATA,
    output wire [7:0]   M2_WSTRB,
    output wire         M2_WLAST,
    output wire         M2_WVALID,
    input  wire         M2_WREADY,
    input  wire [5:0]   M2_BID,
    input  wire [1:0]   M2_BRESP,
    input  wire         M2_BVALID,
    output wire         M2_BREADY,
    output wire [5:0]   M2_ARID,
    output wire [31:0]  M2_ARADDR,
    output wire [3:0]   M2_ARLEN,
    output wire [2:0]   M2_ARSIZE,
    output wire [1:0]   M2_ARBURST,
    output wire [1:0]   M2_ARLOCK,
    output wire [3:0]   M2_ARCACHE,
    output wire [2:0]   M2_ARPROT,
    output wire [3:0]   M2_ARQOS,
    output wire         M2_ARVALID,
    input  wire         M2_ARREADY,
    input  wire [5:0]   M2_RID,
    input  wire [63:0]  M2_RDATA,
    input  wire [1:0]   M2_RRESP,
    input  wire         M2_RLAST,
    input  wire         M2_RVALID,
    output wire         M2_RREADY,

    // ---- AXI3 maestro 64 bits de la VRAM de B (fclk0) ----
    output wire [5:0]   M0_AWID,
    output wire [31:0]  M0_AWADDR,
    output wire [3:0]   M0_AWLEN,
    output wire [2:0]   M0_AWSIZE,
    output wire [1:0]   M0_AWBURST,
    output wire [1:0]   M0_AWLOCK,
    output wire [3:0]   M0_AWCACHE,
    output wire [2:0]   M0_AWPROT,
    output wire [3:0]   M0_AWQOS,
    output wire         M0_AWVALID,
    input  wire         M0_AWREADY,
    output wire [5:0]   M0_WID,
    output wire [63:0]  M0_WDATA,
    output wire [7:0]   M0_WSTRB,
    output wire         M0_WLAST,
    output wire         M0_WVALID,
    input  wire         M0_WREADY,
    input  wire [5:0]   M0_BID,
    input  wire [1:0]   M0_BRESP,
    input  wire         M0_BVALID,
    output wire         M0_BREADY,
    output wire [5:0]   M0_ARID,
    output wire [31:0]  M0_ARADDR,
    output wire [3:0]   M0_ARLEN,
    output wire [2:0]   M0_ARSIZE,
    output wire [1:0]   M0_ARBURST,
    output wire [1:0]   M0_ARLOCK,
    output wire [3:0]   M0_ARCACHE,
    output wire [2:0]   M0_ARPROT,
    output wire [3:0]   M0_ARQOS,
    output wire         M0_ARVALID,
    input  wire         M0_ARREADY,
    input  wire [5:0]   M0_RID,
    input  wire [63:0]  M0_RDATA,
    input  wire [1:0]   M0_RRESP,
    input  wire         M0_RLAST,
    input  wire         M0_RVALID,
    output wire         M0_RREADY
);
    // ------------------------------------------------------------------ reset
    reg rstb_n = 1'b0;
    always @(posedge clk_54m) rstb_n <= sys_rst_n & run;
    assign running = rstb_n;
    // el Z80 sale de reset ~0,6 ms despues del resto (A tarda ~116 ms por sus reset1..3): el V9968 y la cache de memory_axi
    // (que barre sus tags tras el reset) ya estan listos cuando la BIOS escribe el primer puerto
    reg [15:0] rstc = 16'd0;
    always @(posedge clk_54m) begin
        if (~rstb_n)       rstc <= 16'd0;
        else if (!rstc[15]) rstc <= rstc + 16'd1;
    end
    wire cpu_rst_n = rstb_n & rstc[15];

    // ------------------------------------------------------------------ el Z80
    wire        bus_m1_n, bus_mreq_n, bus_iorq_n, bus_rd_n, bus_wr_n, bus_rfsh_n;
    wire [15:0] bus_addr;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din;
    wire        vdp_wait_n;                   // /WAIT del glue del VDP, ya en clk_54m
    wire        vdp_int_n;                    // /INT del V9968, ya en clk_54m
    wire        ram_busy, ram_slow;
    wire        ram_write;
    wire        vdp_csw_n, vdp_csr_n;

    // ---- esperas: la FSM de A (ZYNQ, sin turbo): una espera en cada escritura de RAM, cada fallo de cache y cada ciclo de E/S
    //      que no sea del VDP (el VDP pone su propio /WAIT); mas la espera de la M1 (el freno del MSX real) ----
    wire ex_iorq_n = bus_iorq_n | (vdp_csr_n == 1'b0) | (vdp_csw_n == 1'b0);
    localparam [2:0] WAIT_IDLE = 3'd0, WAIT_STATE1 = 3'd1, WAIT_STATE2 = 3'd3, WAIT_STATE3 = 3'd2;
    reg [2:0] state_wait = WAIT_IDLE;
    reg       wait_io = 1'b1;
    always @(posedge clk_54m) begin
        if (~rstb_n) begin
            state_wait <= WAIT_IDLE;
            wait_io    <= 1'b1;
        end else begin
            case (state_wait)
            WAIT_IDLE:   if (ram_write == 1 || (bus_mreq_n == 0 && bus_rd_n == 0 && ram_slow == 1) ||
                             (ex_iorq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0))) begin
                             wait_io <= 1'b0; state_wait <= WAIT_STATE1;
                         end
            WAIT_STATE1: if (cen_3m6_54 == 1) state_wait <= WAIT_STATE2;
            WAIT_STATE2: if (cfall_3m6_54 == 1 && ram_busy == 0) begin wait_io <= 1'b1; state_wait <= WAIT_STATE3; end
            WAIT_STATE3: if (bus_rd_n == 1 && bus_wr_n == 1) state_wait <= WAIT_IDLE;
            default:     state_wait <= WAIT_IDLE;
            endcase
        end
    end

    reg  wait_m1 = 1'b1;
    reg  bus_m1_n_prev = 1'b1;
    reg  m1_active = 1'b0, m1_masked_en = 1'b0, m1_masked_fall = 1'b0;
    always @(posedge clk_54m) begin
        if (~rstb_n) begin
            wait_m1 <= 1'b1; bus_m1_n_prev <= 1'b1; m1_active <= 1'b0; m1_masked_en <= 1'b0; m1_masked_fall <= 1'b0;
        end else begin
            bus_m1_n_prev <= bus_m1_n;
            if (!m1_active) begin
                if (bus_m1_n_prev == 1'b1 && bus_m1_n == 1'b0) begin
                    m1_active <= 1'b1; wait_m1 <= 1'b0; m1_masked_en <= 1'b0; m1_masked_fall <= 1'b0;
                end
            end else begin
                if (cen_3m6_54)   m1_masked_en   <= 1'b1;
                if (cfall_3m6_54) m1_masked_fall <= 1'b1;
                if ((m1_masked_en || cen_3m6_54) && (m1_masked_fall || cfall_3m6_54)) begin
                    wait_m1 <= 1'b1; m1_active <= 1'b0;
                end
            end
        end
    end

    // /INT del V9968: nivel de clk_86 a clk_54m con dos flip-flops
    wire vdp_int_n_86;
    reg  [1:0] int_s = 2'b11;
    always @(posedge clk_54m) int_s <= {int_s[0], vdp_int_n_86};
    assign vdp_int_n = int_s[1];

    G80a #(
        .Mode    (0),
        .IOWait  (1)
    ) cpu (
        .RESET_n   (cpu_rst_n),
        .CLK_n     (clk_54m),
        .clk_enable (cen_3m6_54   & wait_io & wait_m1),
        .clk_falling(cfall_3m6_54 & wait_io & wait_m1),
        .WAIT_n    (vdp_wait_n),
        .INT_n     (vdp_int_n),
        .NMI_n     (1'b1),
        .BUSRQ_n   (1'b1),
        .M1_n      (bus_m1_n),
        .MREQ_n    (bus_mreq_n),
        .IORQ_n    (bus_iorq_n),
        .RD_n      (bus_rd_n),
        .WR_n      (bus_wr_n),
        .RFSH_n    (bus_rfsh_n),
        .HALT_n    ( ),
        .BUSAK_n   ( ),
        .A         (bus_addr),
        .update_addr( ),
        .DI        (cpu_din),
        .DO        (cpu_dout),
        .Data_Reverse( )
    );

    // ------------------------------------------------------------------ decodificacion de E/S
    wire io_rd = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0);
    wire io_wr = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_wr_n == 1'b0);
    wire vdp_io_hit = (bus_addr[7:2] == 6'b100110);                       // 98h-9Bh
    assign vdp_csw_n = (vdp_io_hit && io_wr) ? 1'b0 : 1'b1;
    assign vdp_csr_n = (vdp_io_hit && io_rd) ? 1'b0 : 1'b1;
    wire ppi_a_wr = io_wr && bus_addr[7:0] == 8'hA8;
    wire ppi_a_rd = io_rd && bus_addr[7:0] == 8'hA8;
    wire ppi_b_rd = io_rd && bus_addr[7:0] == 8'hA9;
    wire ppi_c_wr = io_wr && bus_addr[7:0] == 8'hAA;
    wire ppi_c_rd = io_rd && bus_addr[7:0] == 8'hAA;
    wire ppi_k_wr = io_wr && bus_addr[7:0] == 8'hAB;
    wire psg_rd   = io_rd && bus_addr[7:0] == 8'hA2;
    wire rtc_wr   = io_wr && bus_addr[7:1] == 7'b1011010;                 // B4h-B5h
    wire rtc_rd   = io_rd && bus_addr[7:1] == 7'b1011010;
    wire map_wr   = io_wr && bus_addr[7:2] == 6'b111111;                  // FCh-FFh

    // ------------------------------------------------------------------ PPI: A8h (slots), AAh (fila del teclado) y AB (bit set/reset)
    reg [7:0] ppi_a = 8'h00;
    always @(posedge clk_54m) begin
        if (~rstb_n)       ppi_a <= 8'h00;
        else if (ppi_a_wr) ppi_a <= cpu_dout;
    end
    reg [7:0] ppi_c = 8'h00;
    reg       ab_req_d = 1'b0;
    reg [7:0] ab_dat   = 8'd0;
    wire      ab_fin   = ab_req_d & ~ppi_k_wr;
    always @(posedge clk_54m) begin
        if (~rstb_n) begin
            ppi_c <= 8'h00; ab_req_d <= 1'b0; ab_dat <= 8'd0;
        end else begin
            ab_req_d <= ppi_k_wr;
            if (ppi_k_wr) ab_dat <= cpu_dout;
            if (ppi_c_wr)                          ppi_c <= cpu_dout;
            else if (ab_fin && ab_dat[7] == 1'b0)  ppi_c[ab_dat[3:1]] <= ab_dat[0];
        end
    end
    wire [7:0] kbd_data;
    usb_keyboard_msx kbd (
        .CLK      (clk_27m),
        .RESET    (~rstb_n),
        .keyboard (keyboard),
        .A        (ppi_c[3:0]),
        .DO       (kbd_data),
        .FN       ( )
    );

    // ------------------------------------------------------------------ slots
    wire [1:0] pri_slot = (bus_addr[15:14] == 2'b00) ? ppi_a[1:0] :
                          (bus_addr[15:14] == 2'b01) ? ppi_a[3:2] :
                          (bus_addr[15:14] == 2'b10) ? ppi_a[5:4] : ppi_a[7:6];
    wire [3:0] pri_slot_num = (pri_slot == 2'b00) ? 4'b0001 : (pri_slot == 2'b01) ? 4'b0010 :
                              (pri_slot == 2'b10) ? 4'b0100 : 4'b1000;
    wire [3:0] page_num = (bus_addr[15:14] == 2'b00) ? 4'b0001 : (bus_addr[15:14] == 2'b01) ? 4'b0010 :
                          (bus_addr[15:14] == 2'b10) ? 4'b0100 : 4'b1000;
    // slot 3 expandido (registro en FFFFh)
    reg [7:0] exp3 = 8'h00;
    reg       xffh = 1'b0, xffl = 1'b0, exp3_req_w = 1'b0, exp3_req_r = 1'b0;
    wire      xffff = xffh & xffl;
    wire [1:0] exp3_page = (bus_addr[15:14] == 2'b00) ? exp3[1:0] : (bus_addr[15:14] == 2'b01) ? exp3[3:2] :
                           (bus_addr[15:14] == 2'b10) ? exp3[5:4] : exp3[7:6];
    wire [3:0] exp3_num  = (exp3_page == 2'b00) ? 4'b0001 : (exp3_page == 2'b01) ? 4'b0010 :
                           (exp3_page == 2'b10) ? 4'b0100 : 4'b1000;
    always @(posedge clk_54m) begin
        xffh <= bus_addr[15:8] == 8'hff;
        xffl <= bus_addr[7:0] == 8'hff;
        exp3_req_w <= (bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[3] == 1) ? 1'b1 : 1'b0;
        exp3_req_r <= (bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[3] == 1) ? 1'b1 : 1'b0;
        if (~rstb_n)          exp3 <= 8'h00;
        else if (exp3_req_w)  exp3 <= cpu_dout;
    end

    // peticiones de memoria, registradas a clk_54m (la direccion ya es estable cuando suben, como en A)
    reg bios_req = 1'b0, subrom_req = 1'b0, subrom_p1_req = 1'b0, mapper_req = 1'b0, cart_req = 1'b0;
    always @(posedge clk_54m) begin
        bios_req   <= (bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1) ? 1'b1 : 1'b0;
        subrom_req <= (bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[3] == 1 && page_num[0] == 1 && exp3_num[1] == 1) ? 1'b1 : 1'b0;
        subrom_p1_req <= (bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[3] == 1 && page_num[1] == 1 && exp3_num[1] == 1) ? 1'b1 : 1'b0;
        mapper_req <= (bus_rfsh_n == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0) &&
                       pri_slot_num[3] == 1 && exp3_num[0] == 1 && xffff == 0) ? 1'b1 : 1'b0;
        cart_req   <= (cart_en == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0) && pri_slot == 2'b01) ? 1'b1 : 1'b0;
    end
    wire mapper_read  = mapper_req & ~bus_rd_n;
    wire mapper_write = mapper_req & ~bus_wr_n;

    // mapper de RAM (FCh-FFh): 16 KB por pagina, 2 MB
    reg [7:0] mapper_reg0 = 8'd3, mapper_reg1 = 8'd2, mapper_reg2 = 8'd1, mapper_reg3 = 8'd0;
    always @(posedge clk_54m) begin
        if (~rstb_n) begin
            mapper_reg0 <= 8'd3; mapper_reg1 <= 8'd2; mapper_reg2 <= 8'd1; mapper_reg3 <= 8'd0;
        end else if (map_wr) begin
            case (bus_addr[1:0])
            2'b00: mapper_reg0 <= cpu_dout;
            2'b01: mapper_reg1 <= cpu_dout;
            2'b10: mapper_reg2 <= cpu_dout;
            2'b11: mapper_reg3 <= cpu_dout;
            endcase
        end
    end
    wire [21:0] mapper_addr = (bus_addr[15:14] == 2'b00) ? {mapper_reg0, bus_addr[13:0]} :
                              (bus_addr[15:14] == 2'b01) ? {mapper_reg1, bus_addr[13:0]} :
                              (bus_addr[15:14] == 2'b10) ? {mapper_reg2, bus_addr[13:0]} : {mapper_reg3, bus_addr[13:0]};

    // el cartucho (slot 1)
    wire        megaram_req, megaram_wrt;
    wire [22:0] megaram_addr;
    wire        cart_wrt = (cart_req == 1 && bus_wr_n == 0) ? 1'b1 : 1'b0;
    megaram_scc megaram_b (
        .clk_27m      (clk_54m),
        .bus_reset_n  (rstb_n),
        .bus_addr     (bus_addr),
        .cpu_dout     (cpu_dout),
        .bus_rd_n     (bus_rd_n),
        .bus_wr_n     (bus_wr_n),
        .scc_req      (cart_req),
        .scc_wrt      (cart_wrt),
        .map_sel      (map_sel),
        .map_linear   (map_linear),
        .sram_cfg     (8'h00),
        .map_ext      (8'h00),
        .megaram_req  (megaram_req),
        .megaram_wrt  (megaram_wrt),
        .megaram_addr (megaram_addr),
        .scc_sound_disable ( ),
        .scc_mode_plus ( ),
        .sccplus_win_en ( )
    );

    // ------------------------------------------------------------------ RAM de B en la DDR (memory_axi)
    // ram_addr de 24 bits: bit 23 = 0 la zona de B (RAM_BASE: mapper en 000000-1FFFFF, cartucho con A21 = 1 en 200000-3FFFFF y con
    // A21 = 0 en 400000-5FFFFF); bit 23 = 1 la ventana de A (EXT_BASE): BIOS en F60000-F67FFF, SUB-ROM en F68000-F6BFFF
    wire [23:0] ram_addr = (mapper_req == 1) ? {3'b000, mapper_addr[20:0]} :
                           (bios_req   == 1) ? {9'b111101100, bus_addr[14:0]} :
                           (subrom_req == 1) ? {10'b1111011010, bus_addr[13:0]} :
                           (megaram_req == 1) ? {1'b0, ~megaram_addr[21], megaram_addr[21], megaram_addr[20:0]} :
                           24'h7fffff;
    wire any_ram_rd = mapper_read | bios_req | subrom_req | megaram_req;
    wire any_ram_rq = mapper_req  | bios_req | subrom_req | megaram_req;
    wire any_ram_wr = mapper_write | megaram_wrt;
    wire ram_req    = any_ram_rq;
    assign ram_write = any_ram_wr & ~bus_wr_n;
    wire [7:0] ram_dout;
    wire [31:0] mem_hits, mem_miss, mem_state;
    // Parada ordenada (31/10/2026): al bajar run / sys_rst_n el Z80 y el VDP de B se paran YA (rstb_n), pero el reset de memory_axi,
    // que suelta AWVALID/WVALID/ARVALID, espera a que no tenga nada a medias en el HP2 (si no, axi_arb2w se queda esperando el
    // resto de la rafaga de B y el buzon del ARM, que comparte el puerto, no vuelve a escribir: el sistema se cuelga)
    wire mem_idle, mem_rst_n;
    axi_rst_drain u_memrst (.clk(clk_54m), .want_n(rstb_n), .idle(mem_idle), .rst_n(mem_rst_n));
    memory_axi #(.RAM_BASE(RAM_BASE), .EXT_BASE(EXT_BASE), .LINES_LOG(LINES_LOG), .TAG_BITS(5), .ID_PFX(6'd32), .IDLE_OUT(1)) mem_b (
        .lat_clr(1'b0), .lat_tel(),
        .clk_54m(clk_54m), .bus_reset_n(mem_rst_n), .idle(mem_idle),
        .video_dhclk(1'b0), .video_dlclk(1'b0), .cpu_run(rstb_n),
        .ram_din(cpu_dout), .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr),
        .ram_dout(ram_dout), .ram_busy(ram_busy), .ram_slow(ram_slow),
        .dbg_hits(mem_hits), .dbg_miss(mem_miss), .dbg_state(mem_state), .ready(),
        .aresetn(rst54_n),
        .M_AWID(M2_AWID), .M_AWADDR(M2_AWADDR), .M_AWLEN(M2_AWLEN), .M_AWSIZE(M2_AWSIZE),
        .M_AWBURST(M2_AWBURST), .M_AWLOCK(M2_AWLOCK), .M_AWCACHE(M2_AWCACHE), .M_AWPROT(M2_AWPROT),
        .M_AWQOS(M2_AWQOS), .M_AWVALID(M2_AWVALID), .M_AWREADY(M2_AWREADY),
        .M_WID(M2_WID), .M_WDATA(M2_WDATA), .M_WSTRB(M2_WSTRB), .M_WLAST(M2_WLAST),
        .M_WVALID(M2_WVALID), .M_WREADY(M2_WREADY),
        .M_BID(M2_BID), .M_BRESP(M2_BRESP), .M_BVALID(M2_BVALID), .M_BREADY(M2_BREADY),
        .M_ARID(M2_ARID), .M_ARADDR(M2_ARADDR), .M_ARLEN(M2_ARLEN), .M_ARSIZE(M2_ARSIZE),
        .M_ARBURST(M2_ARBURST), .M_ARLOCK(M2_ARLOCK), .M_ARCACHE(M2_ARCACHE), .M_ARPROT(M2_ARPROT),
        .M_ARQOS(M2_ARQOS), .M_ARVALID(M2_ARVALID), .M_ARREADY(M2_ARREADY),
        .M_RID(M2_RID), .M_RDATA(M2_RDATA), .M_RRESP(M2_RRESP), .M_RLAST(M2_RLAST),
        .M_RVALID(M2_RVALID), .M_RREADY(M2_RREADY)
    );

    // ------------------------------------------------------------------ PSG (A0h-A2h)
    wire        psgBdir = ( bus_addr[7:3] == 5'b10100 && (bus_iorq_n | bus_wr_n) == 0 && bus_addr[1] == 0 ) ? 1'b1 : 1'b0;
    wire        psgBc1  = ( bus_addr[7:3] == 5'b10100 && (((bus_iorq_n | bus_rd_n) == 0 && bus_addr[1] == 1) ||
                            (bus_addr[1] == 0 && (bus_iorq_n | bus_wr_n) == 0 && bus_addr[0] == 0)) ) ? 1'b1 : 1'b0;
    wire [7:0]  psg_dout;
    wire [7:0]  psgPB;
    wire [7:0]  psg_a, psg_b, psg_c;
    reg  [3:0]  psg_addr_latch = 4'd0;
    always @(posedge clk_54m) begin
        if (~rstb_n) psg_addr_latch <= 4'd0;
        else if (bus_addr[7:0] == 8'hA0 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1) psg_addr_latch <= cpu_dout[3:0];
    end
    reg  clk_1m8 = 1'b0;
    always @(posedge clk_54m) if (cen_3m6_54) clk_1m8 <= ~clk_1m8;
    wire ena_1m8 = cen_3m6_54 & clk_1m8;
    YM2149 psg (
        .I_DA(cpu_dout), .O_DA(psg_dout), .O_DA_OE_L(),
        .I_A9_L(1'b0), .I_A8(1'b1),
        .I_BDIR(psgBdir), .I_BC2(1'b1), .I_BC1(psgBc1), .I_SEL_L(1'b1),
        .O_AUDIO(), .O_AUDIO_A(psg_a), .O_AUDIO_B(psg_b), .O_AUDIO_C(psg_c),
        .I_IOA(8'h00), .O_IOA(), .O_IOA_OE_L(),
        .I_IOB(psgPB), .O_IOB(psgPB), .O_IOB_OE_L(),
        .ENA(ena_1m8), .RESET_L(rstb_n), .CLK(clk_54m), .clkHigh(clk_54m), .debug()
    );
    // sonido: a+b+c (0..765) x16 = el nivel de un lado del PSG de A a tope; mono; sin continua (la receta del bloqueador de A)
    wire [9:0]  psg_sum = {2'b00, psg_a} + {2'b00, psg_b} + {2'b00, psg_c};
    wire signed [16:0] psg_x = $signed({3'b000, psg_sum, 4'b0000});
    reg  signed [31:0] psg_dcacc = 32'sd0;
    assign psg_ac = psg_x - psg_dcacc[31:16];
    always @(posedge clk_27m) begin
        if (~rstb_n)          psg_dcacc <= 32'sd0;
        else if (cen_3m6_27)  psg_dcacc <= psg_dcacc + {{15{psg_ac[16]}}, psg_ac};
    end

    // ------------------------------------------------------------------ RTC (B4h-B5h)
    wire [7:0] rtc_dout;
    rtc rtc_b (
        .clk21m(clk_27m), .reset(1'b0), .clkena(cen_3m6_27),
        .req(rtc_wr | rtc_rd), .ack(), .wrt(rtc_wr), .adr(bus_addr),
        .dbi(rtc_dout), .dbo(cpu_dout), .tod()
    );

    // ------------------------------------------------------------------ el V9968 de B
    wire [7:0] vdp_dout;
    (* syn_maxfan = 16 *) reg [3:0] rst86_sync = 4'd0;
    always @(posedge clk_86) rst86_sync <= {rst86_sync[2:0], rstb_n & pll86_lock};
    wire rst86_n = rst86_sync[3];

    wire [2:0] v68_bus_address;
    wire       v68_ioreq, v68_write, v68_valid, v68_ready;
    wire [7:0] v68_wdata, v68_rdata;
    wire       v68_rdata_en;
    wire       v68_wait86_n;
    v9968_cpu_glue u_glue (
        .clk_86(clk_86), .rst_n(rst86_n),
        .csw_n(vdp_csw_n), .csr_n(vdp_csr_n),
        .mode({1'b0, bus_addr[1:0]}), .cdo(cpu_dout), .cdi_r(vdp_dout),
        .wait_n(v68_wait86_n),
        .bus_address(v68_bus_address), .bus_ioreq(v68_ioreq),
        .bus_write(v68_write), .bus_valid(v68_valid), .bus_ready(v68_ready),
        .bus_wdata(v68_wdata), .bus_rdata(v68_rdata), .bus_rdata_en(v68_rdata_en)
    );
    reg [1:0] v68_wait_s = 2'b11;
    always @(posedge clk_54m) v68_wait_s <= {v68_wait_s[0], v68_wait86_n};
    assign vdp_wait_n = v68_wait_s[1];

    wire [17:2] v68_vram_address;
    wire        v68_vram_write, v68_vram_valid, v68_vram_refresh;
    wire [31:0] v68_vram_wdata, v68_vram_rdata;
    wire [3:0]  v68_vram_mask;
    wire [4:0]  v68_vram_tag, v68_vram_rtag;
    wire        v68_vram_rdata_en, v68_vram_stall;
    wire        v68_hs, v68_vs, v68_de, v68_hires512;
    wire [7:0]  v68_r8, v68_g8, v68_b8;
    vdp u_vdp (
        .reset_n(rst86_n), .clk(clk_86), .initial_busy(1'b0),
        .bus_address(v68_bus_address), .bus_ioreq(v68_ioreq), .bus_write(v68_write),
        .bus_valid(v68_valid), .bus_ready(v68_ready),
        .bus_wdata(v68_wdata), .bus_rdata(v68_rdata), .bus_rdata_en(v68_rdata_en),
        .int_n(vdp_int_n_86),
        .vram_address(v68_vram_address), .vram_write(v68_vram_write),
        .vram_valid(v68_vram_valid), .vram_wdata(v68_vram_wdata),
        .vram_wdata_mask(v68_vram_mask),
        .vram_rdata(v68_vram_rdata), .vram_rdata_en(v68_vram_rdata_en),
        .vram_tag(v68_vram_tag), .vram_rtag(v68_vram_rtag),
        .vram_stall(v68_vram_stall),
        .vram_refresh(v68_vram_refresh),
        .display_hs(v68_hs), .display_vs(v68_vs), .display_en(v68_de),
        .display_r(v68_r8), .display_g(v68_g8), .display_b(v68_b8),
        .hires512(v68_hires512),
        .force_highspeed(1'b0), .button(2'b00),
        .ext_cmd_wr(1'b0), .ext_cmd_num(6'd0), .ext_cmd_data(8'd0), .ext_cmd_fill_span(1'b0), .ext_cmd_ce(),
        .pulse0(), .pulse1(), .pulse2(), .pulse3(),
        .pulse4(), .pulse5(), .pulse6(), .pulse7()
    );

    wire        v68bk_req, v68bk_we, v68bk_done_t;
    wire [21:0] v68bk_addr;
    wire [31:0] v68bk_wdata;
    wire [3:0]  v68bk_wmask;
    wire [15:0] v68bk_rword;
    wire        v68bk2_req, v68bk2_done_t;
    wire [21:0] v68bk2_addr;
    wire [15:0] v68bk2_rword;
    v9968_vram_shim #(.VRAM_BASE(VRAM_OFF), .SPC(1)) u_shim (     // SPC: cache de sprites aparte (como la maquina A)
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .vram_address(v68_vram_address), .vram_write(v68_vram_write),
        .vram_valid(v68_vram_valid), .vram_wdata(v68_vram_wdata),
        .vram_wdata_mask(v68_vram_mask), .vram_tag(v68_vram_tag),
        .vram_rdata(v68_vram_rdata), .vram_rdata_en(v68_vram_rdata_en),
        .vram_rtag(v68_vram_rtag),
        .bk_req(v68bk_req), .bk_we(v68bk_we), .bk_addr(v68bk_addr),
        .bk_wdata(v68bk_wdata), .bk_wmask(v68bk_wmask),
        .bk_rword(v68bk_rword), .bk_done_t(v68bk_done_t),
        .bk2_req(v68bk2_req), .bk2_addr(v68bk2_addr),
        .bk2_rword(v68bk2_rword), .bk2_done_t(v68bk2_done_t),
        .vram_stall(v68_vram_stall),
        .diag(),
        .dbg_miss(), .dbg_bka(), .dbg_bkb(), .dbg_park(), .dbg_drops()
    );
    wire        vddr_clk_x1, vddr_a_req, vddr_a_we, vddr_b_req;
    wire [21:0] vddr_a_addr, vddr_b_addr;
    wire [31:0] vddr_a_wdata;
    wire [3:0]  vddr_a_wmask;
    wire [15:0] vddr_a_dout, vddr_b_dout;
    wire        vddr_a_done, vddr_b_done, vddr_ready;
    v9968_sdram_bridge u_br1 (
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .bk_req(v68bk_req), .bk_we(v68bk_we), .bk_addr(v68bk_addr),
        .bk_wdata(v68bk_wdata), .bk_wmask(v68bk_wmask),
        .bk_rword(v68bk_rword), .bk_done_t(v68bk_done_t),
        .clk_108m(vddr_clk_x1),
        .wv2_req(vddr_a_req), .wv2_we(vddr_a_we), .wv2_addr(vddr_a_addr),
        .wv2_wdata(vddr_a_wdata), .wv2_wmask(vddr_a_wmask),
        .wv2_dout(vddr_a_dout), .wv2_done(vddr_a_done)
    );
    v9968_sdram_bridge u_br2 (
        .clk_vdp(clk_86), .rst_n(rst86_n),
        .bk_req(v68bk2_req), .bk_we(1'b0), .bk_addr(v68bk2_addr),
        .bk_wdata(32'd0), .bk_wmask(4'd0),
        .bk_rword(v68bk2_rword), .bk_done_t(v68bk2_done_t),
        .clk_108m(vddr_clk_x1),
        .wv2_req(vddr_b_req), .wv2_we(), .wv2_addr(vddr_b_addr),
        .wv2_wdata(), .wv2_wmask(), .wv2_dout(vddr_b_dout), .wv2_done(vddr_b_done)
    );
    v9968_axi_backend #(.VRAM_BASE(VRAM_BASE), .TAG_BITS(5), .ID_PFX(6'd32)) u_vram (
        .a_req(vddr_a_req), .a_we(vddr_a_we), .a_addr(vddr_a_addr),
        .a_wdata(vddr_a_wdata), .a_wmask(vddr_a_wmask),
        .a_dout(vddr_a_dout), .a_done(vddr_a_done),
        .b_req(vddr_b_req), .b_addr(vddr_b_addr),
        .b_dout(vddr_b_dout), .b_done(vddr_b_done),
        .clk_x1_out(vddr_clk_x1), .ready(vddr_ready), .diag(),
        .dbg_ops(),
        .recal_req(1'b0),
        .aclk(fclk0), .aresetn(fclk_aresetn),
        .M_AWID(M0_AWID), .M_AWADDR(M0_AWADDR), .M_AWLEN(M0_AWLEN), .M_AWSIZE(M0_AWSIZE),
        .M_AWBURST(M0_AWBURST), .M_AWLOCK(M0_AWLOCK), .M_AWCACHE(M0_AWCACHE), .M_AWPROT(M0_AWPROT),
        .M_AWQOS(M0_AWQOS), .M_AWVALID(M0_AWVALID), .M_AWREADY(M0_AWREADY),
        .M_WID(M0_WID), .M_WDATA(M0_WDATA), .M_WSTRB(M0_WSTRB), .M_WLAST(M0_WLAST),
        .M_WVALID(M0_WVALID), .M_WREADY(M0_WREADY),
        .M_BID(M0_BID), .M_BRESP(M0_BRESP), .M_BVALID(M0_BVALID), .M_BREADY(M0_BREADY),
        .M_ARID(M0_ARID), .M_ARADDR(M0_ARADDR), .M_ARLEN(M0_ARLEN), .M_ARSIZE(M0_ARSIZE),
        .M_ARBURST(M0_ARBURST), .M_ARLOCK(M0_ARLOCK), .M_ARCACHE(M0_ARCACHE), .M_ARPROT(M0_ARPROT),
        .M_ARQOS(M0_ARQOS), .M_ARVALID(M0_ARVALID), .M_ARREADY(M0_ARREADY),
        .M_RID(M0_RID), .M_RDATA(M0_RDATA), .M_RRESP(M0_RRESP), .M_RLAST(M0_RLAST),
        .M_RVALID(M0_RVALID), .M_RREADY(M0_RREADY)
    );

    // ------------------------------------------------------------------ video: 480 lineas dobladas -> 240 + formato del puente del V9990
    // Se quedan las lineas de una paridad (la cuenta se pone a 0 en el VS y salta en cada HS): cada linea nativa sale dos veces
    // seguidas del doblador del V9968, asi que cualquiera de las dos paridades da la imagen entera. El puente cuenta una linea
    // por HS que recibe: con una de cada dos, un frame son 240 lineas.
    reg  hs_d = 1'b0, vs_d = 1'b0, lpar = 1'b0;
    reg  o_hs = 1'b0, o_vs = 1'b0, o_de = 1'b0;
    reg  [4:0] o_r = 5'd0, o_g = 5'd0, o_b = 5'd0;
    wire hs_rise = v68_hs & ~hs_d;
    wire vs_rise = v68_vs & ~vs_d;
    wire lpar_n  = vs_rise ? 1'b0 : (hs_rise ? ~lpar : lpar);
    always @(posedge clk_86) begin
        if (ce86) begin
            hs_d <= v68_hs; vs_d <= v68_vs; lpar <= lpar_n;
            o_hs <= v68_hs & ~lpar_n;
            o_vs <= v68_vs;
            o_de <= v68_de & ~lpar_n;
            o_r  <= v68_r8[7:3]; o_g <= v68_g8[7:3]; o_b <= v68_b8[7:3];
        end
    end
    assign vid_ce = ce86;
    assign vid_r = o_r;  assign vid_g = o_g;  assign vid_b = o_b;
    assign vid_hs = o_hs; assign vid_vs = o_vs; assign vid_de = o_de;

    // ------------------------------------------------------------------ bus de datos al Z80
    wire [7:0] psg_rdata = (psg_addr_latch == 4'd14) ? 8'hFF :           // sin joystick
                           (psg_addr_latch == 4'd15) ? psgPB : psg_dout;
    always @(posedge clk_54m) begin
        cpu_din <=
            ( psg_rd == 1 )         ? psg_rdata :
            ( ppi_b_rd == 1 )       ? kbd_data :
            ( vdp_csr_n == 0 )      ? vdp_dout :
            ( mapper_read == 1 )    ? ram_dout :
            ( exp3_req_r == 1 )     ? ~exp3 :
            ( bios_req == 1 )       ? ram_dout :
            ( subrom_req == 1 )     ? ram_dout :
            ( subrom_p1_req == 1 )  ? 8'hC9 :
            ( megaram_req == 1 )    ? ram_dout :
            ( rtc_rd == 1 )         ? rtc_dout :
            ( ppi_c_rd == 1 )       ? ppi_c :
            ( ppi_a_rd == 1 )       ? ppi_a :
                                      8'hFF;
    end

    // ------------------------------------------------------------------ telemetria
    reg [15:0] b_pc = 16'd0, b_vdpw = 16'd0, b_frames = 16'd0;
    reg        vdpw_d = 1'b0;
    always @(posedge clk_54m) begin
        if (bus_m1_n == 1'b0 && bus_mreq_n == 1'b0) b_pc <= bus_addr;
        vdpw_d <= (vdp_csw_n == 1'b0);
        if (vdp_csw_n == 1'b0 && !vdpw_d) b_vdpw <= b_vdpw + 16'd1;
    end
    reg vs86_d = 1'b0;
    always @(posedge clk_86) begin
        vs86_d <= v68_vs;
        if (v68_vs & ~vs86_d) b_frames <= b_frames + 16'd1;
    end
    assign tel_a = {b_pc, b_vdpw};
    assign tel_b = {b_frames, ppi_a, mem_miss[7:0]};
endmodule
