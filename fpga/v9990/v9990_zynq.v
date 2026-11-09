// ============================================================================
// v9990_zynq.v — El V9990 (tiny9990) dentro de la Zynq: envoltorio que junta
// el core, el pegamento del bus del T80 (v9990_cpu_glue), la VRAM en la DDR
// (v9990_vram_axi, S_AXI_GP1) y los relojes.
//
// Relojes: el core corre ENTERO a clk_86 (85,909 MHz) con enables:
//   CLK_21M_EN = clk_86/4 = 21,477 MHz  y  CLK_14M_EN = clk_86/6 = 14,318 MHz,
//   los dos EXACTOS (tnCart usa 108/5 = 21,6 y 108/7,5 = 14,4 con error).
//   RAM_REQ = 1 ranura de VRAM cada 16 ciclos = 5,37 MHz, la misma cadencia que
//   el UMA de tnCart (10,74 MHz repartidos entre dos clientes), en la fase +2
//   del enable de 21 M (t9990_clock.sv sincroniza el DCLK con la coincidencia
//   "enable retrasado 2 ciclos && MEM_REQ").
//   CLK_25M_EN = enable fraccionario de 25,175 MHz (solo para que el core siga vivo en
//   B6 con C25M = R#7 bit 6): el puente no captura 640x480. B5 (640x400, HSCN con C25M = 0)
//   va con el maestro de 21 MHz y SI se captura (29/10/2026, V9991 paso 5).
// STALL: cuando la cache de VRAM falla, `stall` congela los tres enables y sus
// contadores de fase (el core entero se para y reanuda con la misma relacion de
// fase); el puerto CPU y el blitter, que van a CLK, esperan solos por el ACK
// de la RAM y el WAIT_n del puerto.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9990_zynq #(
    parameter [31:0] VRAM_BASE = 32'h1030_0000
)(
    input  wire        clk_86,
    input  wire        rst_n,          // rst86_n del dominio VDP (= bus_reset_n & pll86_lock sincronizado: el
                                       // reset del MSX resetea el core, como el /RESET del slot en un GFX9000)
    input  wire        aresetn,        // FCLK_RESET0_N sincronizado a clk_86

    // ---- bus del T80 (decodificado en top: puertos 60h-6Fh) ----
    input  wire        csw_n,
    input  wire        csr_n,
    input  wire [3:0]  mode,           // bus_addr[3:0]
    input  wire [7:0]  cdo,
    output wire [7:0]  cdi,
    output wire        wait_n,         // clk_86; top lo sincroniza a 54 M
    output wire        int_n,          // INT0_n & INT1_n (nivel)

    // ---- video nativo del V9990 (dominio clk_86, pixel = dclk_en) ----
    output wire        v_de,           // periodo visible con bordes
    output wire        v_disp,         // R#8 bit 7 (DISP): pantalla del V9990 encendida (clk_86)
    output wire        v_hs,           // activo ALTO
    output wire        v_vs,           // activo ALTO
    output wire [4:0]  v_r,
    output wire [4:0]  v_g,
    output wire [4:0]  v_b,
    output wire        v_ys,           // 1 = TRANSPARENTE (YSE = 1 y bit YS de la paleta del pixel; bordes y backdrop
                                       // segun la entrada BDC); 0 = opaco. Alineado con v_r/g/b. V9991 (28/10/2026)
    output wire        v_dclk_en,
    output wire [2:0]  v_reso,         // T9990_RESO: 0 B1 .. 3 B4, 6 B7 (1024 puntos; 28/10/2026)
    output wire        v_il,
    output wire        v_eo,
    output wire [63:0] v_win,          // V9991: R#55..R#62 del V9990 ({R#62, ..., R#55}), la ventana del V9968 (clk_86, cuasi-estatico)

    // ---- telemetria ----
    output wire [31:0] dbg_reads,
    output wire [31:0] dbg_miss,
    output wire [31:0] dbg_stall,
    output wire [31:0] dbg_writes,
    output wire        dbg_stalled,

    // ---- AXI3 master 32 bits (S_AXI_GP1 a clk_86) ----
    output wire [5:0]  M_AWID,
    output wire [31:0] M_AWADDR,
    output wire [3:0]  M_AWLEN,
    output wire [2:0]  M_AWSIZE,
    output wire [1:0]  M_AWBURST,
    output wire [1:0]  M_AWLOCK,
    output wire [3:0]  M_AWCACHE,
    output wire [2:0]  M_AWPROT,
    output wire [3:0]  M_AWQOS,
    output wire        M_AWVALID,
    input  wire        M_AWREADY,
    output wire [5:0]  M_WID,
    output wire [31:0] M_WDATA,
    output wire [3:0]  M_WSTRB,
    output wire        M_WLAST,
    output wire        M_WVALID,
    input  wire        M_WREADY,
    input  wire [5:0]  M_BID,
    input  wire [1:0]  M_BRESP,
    input  wire        M_BVALID,
    output wire        M_BREADY,
    output wire [5:0]  M_ARID,
    output wire [31:0] M_ARADDR,
    output wire [3:0]  M_ARLEN,
    output wire [2:0]  M_ARSIZE,
    output wire [1:0]  M_ARBURST,
    output wire [1:0]  M_ARLOCK,
    output wire [3:0]  M_ARCACHE,
    output wire [2:0]  M_ARPROT,
    output wire [3:0]  M_ARQOS,
    output wire        M_ARVALID,
    input  wire        M_ARREADY,
    input  wire [5:0]  M_RID,
    input  wire [31:0] M_RDATA,
    input  wire [1:0]  M_RRESP,
    input  wire        M_RLAST,
    input  wire        M_RVALID,
    output wire        M_RREADY
);
    // ------------------------------------------------------------------------
    // Enables de reloj y ranuras de VRAM (congelados durante el stall)
    // ------------------------------------------------------------------------
    wire stall;
    reg [1:0] c4  = 2'd0;
    reg [2:0] c6  = 3'd0;
    reg [3:0] c16 = 4'd0;
    always @(posedge clk_86) begin
        if (!rst_n) begin
            c4 <= 2'd0; c6 <= 3'd0; c16 <= 4'd0;
        end else if (!stall) begin
            c4  <= c4 + 2'd1;
            c6  <= (c6 == 3'd5) ? 3'd0 : c6 + 3'd1;
            c16 <= c16 + 4'd1;
        end
    end
    wire clk21_en = !stall && (c4 == 2'd0);
    wire clk14_en = !stall && (c6 == 3'd0);
    wire ram_req  = !stall && (c16 == 4'd2);
    assign dbg_stalled = stall;
    // CLK_25M_EN (modo VGA B6, R#7 bit 6 C25M con HSCN): 25,175 MHz como enable fraccionario
    // sobre los 85,909 MHz (25175/85909, jitter de un ciclo). Solo para que el core no se
    // pare si un programa activa C25M: el puente no captura 640x480 (pendiente). B5 (HSCN sin
    // C25M) usa el maestro de 21 MHz, como B7, y se captura (29/10/2026).
    reg  [16:0] c25_acc = 17'd0;
    wire [17:0] c25_sum  = {1'b0, c25_acc} + 18'd25175;
    wire        c25_wrap = (c25_sum >= 18'd85909);
    always @(posedge clk_86) begin
        if (!rst_n) c25_acc <= 17'd0;
        else if (!stall) c25_acc <= c25_wrap ? (c25_sum[16:0] - 17'd85909) : c25_sum[16:0];
    end
    wire clk25_en = !stall && c25_wrap;

    // ------------------------------------------------------------------------
    // Pegamento del bus del T80
    // ------------------------------------------------------------------------
    wire       t_csr_n, t_csw_n, t_wait_n;
    wire [3:0] t_mode;
    wire [7:0] t_cd_in, t_cd_out;
    v9990_cpu_glue u_glue (
        .clk_86(clk_86), .rst_n(rst_n),
        .csw_n(csw_n), .csr_n(csr_n), .mode(mode), .cdo(cdo),
        .cdi_r(cdi), .wait_n(wait_n),
        .t_csr_n(t_csr_n), .t_csw_n(t_csw_n), .t_mode(t_mode), .t_cd_in(t_cd_in),
        .t_cd_out(t_cd_out), .t_wait_n(t_wait_n)
    );

    // ------------------------------------------------------------------------
    // VRAM en la DDR
    // ------------------------------------------------------------------------
    wire        ram_oe_n, ram_we_n, ram_rfsh_n, ram_ack_n;
    wire [18:0] ram_addr;
    wire [31:0] ram_din, ram_dout;
    wire [2:0]  ram_din_size;
    // SET_BITS 10 = 128 KB (20/09 noche): con 64 KB el P1 del msx-samurai perdia el 2,3 % en stall
    // (tb_t9990_timing +TILES=1024 +SPR=64: 3261 fallos/frame con 512 conjuntos, 279 con 1024)
    v9990_vram_axi #(.VRAM_BASE(VRAM_BASE), .SET_BITS(10)) u_vram (
        .clk(clk_86), .rst_n(rst_n), .aresetn(aresetn),
        .ram_oe_n(ram_oe_n), .ram_we_n(ram_we_n), .ram_rfsh_n(ram_rfsh_n),
        .ram_addr(ram_addr), .ram_din(ram_din), .ram_din_size(ram_din_size),
        .ram_dout(ram_dout), .ram_ack_n(ram_ack_n), .stall(stall), .pf_en(1'b1),
        .dbg_reads(dbg_reads), .dbg_miss(dbg_miss), .dbg_stall(dbg_stall), .dbg_writes(dbg_writes),
        .M_AWID(M_AWID), .M_AWADDR(M_AWADDR), .M_AWLEN(M_AWLEN), .M_AWSIZE(M_AWSIZE),
        .M_AWBURST(M_AWBURST), .M_AWLOCK(M_AWLOCK), .M_AWCACHE(M_AWCACHE), .M_AWPROT(M_AWPROT),
        .M_AWQOS(M_AWQOS), .M_AWVALID(M_AWVALID), .M_AWREADY(M_AWREADY),
        .M_WID(M_WID), .M_WDATA(M_WDATA), .M_WSTRB(M_WSTRB), .M_WLAST(M_WLAST),
        .M_WVALID(M_WVALID), .M_WREADY(M_WREADY),
        .M_BID(M_BID), .M_BRESP(M_BRESP), .M_BVALID(M_BVALID), .M_BREADY(M_BREADY),
        .M_ARID(M_ARID), .M_ARADDR(M_ARADDR), .M_ARLEN(M_ARLEN), .M_ARSIZE(M_ARSIZE),
        .M_ARBURST(M_ARBURST), .M_ARLOCK(M_ARLOCK), .M_ARCACHE(M_ARCACHE), .M_ARPROT(M_ARPROT),
        .M_ARQOS(M_ARQOS), .M_ARVALID(M_ARVALID), .M_ARREADY(M_ARREADY),
        .M_RID(M_RID), .M_RDATA(M_RDATA), .M_RRESP(M_RRESP), .M_RLAST(M_RLAST),
        .M_RVALID(M_RVALID), .M_RREADY(M_RREADY)
    );

    // ------------------------------------------------------------------------
    // El core
    // ------------------------------------------------------------------------
    wire int0_n, int1_n, hscn;
    T9990 u_t9990 (
        .RESET_n(rst_n), .CLK(clk_86),
        .CLK_21M_EN(clk21_en), .CLK_14M_EN(clk14_en), .CLK_25M_EN(clk25_en),
        .CSR_n(t_csr_n), .CSW_n(t_csw_n), .MODE(t_mode), .CD_IN(t_cd_in), .CD_OUT(t_cd_out),
        .WAIT_n(t_wait_n), .INT0_n(int0_n), .INT1_n(int1_n), .DREQ_n(), .VMREQ_n(),
        .RAM_REQ(ram_req), .RAM_ACK_n(ram_ack_n),
        .RAM_OE_n(ram_oe_n), .RAM_WE_n(ram_we_n), .RAM_RFSH_n(ram_rfsh_n),
        .RAM_ADDR(ram_addr), .RAM_DIN(ram_din), .RAM_DIN_SIZE(ram_din_size), .RAM_DOUT(ram_dout),
        .HS(v_hs), .VS(v_vs), .R(v_r), .G(v_g), .B(v_b), .Ys(v_ys), .DCLK_EN(v_dclk_en),
        .RESO(v_reso), .HSCN(hscn), .IL(v_il), .EO(v_eo), .DE(v_de), .DISP(v_disp),
        .WINREG(v_win)
    );
    assign int_n = int0_n & int1_n;
endmodule
