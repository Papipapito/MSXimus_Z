// ============================================================================
//  dbg_mailbox_axi.v — buzon de depuracion en la DDR del PS (Zynq), via HP
// ----------------------------------------------------------------------------
//  "Manos y ojos" para xsdb sin hardware extra:
//    * ENTRADA  (MBOX+0x00, 16 B): bitmap de teclado de 128 bits indexado por
//      keycode HID (el mismo formato que usb_kbd_decode). El PL lo lee cada
//      ~1 ms; el top hace OR con el del USB. xsdb "pulsa" una tecla poniendo su
//      bit y quitandolo ~100 ms despues (tools/key.tcl).
//    * SALIDA (MBOX+0x40, 32 B): telemetria escrita cada ~1 ms:
//        +0x40 {seq[31:0], 32'h4D424F58 'MBOX'}  +0x48 {mem_dbg_miss, mem_dbg_hits}
//        +0x50 {status[31:0], kbd_echo[31:0]}    +0x58 {dbg, dbg2}  +0x60 {dbg3, dbg4}
//        +0x68 {shim_miss, shim_drops}: fallos de fondo/sprites y drops del shim de VRAM
//    * TRAZA (MBOX+0x1000, 4 KB): cuando vdp_trace.v ha llenado su anillo (trace_full),
//      cada ronda vuelca los 1024 eventos (512 palabras de 64 bits, evento par en la
//      mitad baja). Se arma con el bit 1 de la palabra de control (+0x1C): tools/vdptrace.tcl.
//    * Z80 -> ARM (16/09): anillo de 32 entradas {tag, dato} con lo que el Z80 escribe en
//      el puerto 92h (WaveGame, tag 92) y en el 93h (mensajes del menu, tag 93; el 47h es del SD); se vuelca
//      entero cada ronda en +0x78..+0xB7 y el indice de escritura va en +0xB8 [63:56].
//    * WaveGame (16/09): voz PCM mono 16 bits a 44,1 kHz. El companion deja las muestras en
//      un anillo de 32768 muestras en la DDR (WG_BASE) y publica {play[31], wr[15:0]} en
//      +0x20; cada ronda, si hay >= 64 muestras pendientes y sitio en la FIFO (128 x 4
//      muestras), se traen 64 con una rafaga de 16 beats. +0xB8 lleva rd[47:32], el nivel de
//      la FIFO [31:16] y play/fetches [15:0]. Con play=0 la FIFO se vacia y rd sigue a wr.
//      23/09/2026: ESTEREO con el bit 30 de +0x20: el anillo lleva pares {L, R} intercalados y cada tic
//      saca los dos (wg_smp = izquierda, wg_smp_r = derecha); en mono wg_smp_r repite wg_smp. Y las
//      rafagas del anillo ya no esperan al final de la ronda: se piden en cuanto la FIFO tiene sitio
//      (una por ronda de 1 ms eran 64 muestras/ms: de sobra en mono, 44,1; corto en estereo, 88,2).
//    * V9990 por el ARM (30/10/2026, rama beta): el companion escribe en los puertos 60h-6Fh del V9990
//      mientras el Z80 juega en el V9968 (v9990_arm_port.v los inyecta). Control en V9_BASE+0 (32 bits):
//      {en[31], 15'b0, wr[15:0]} (wr = entradas escritas mod 65536). Anillo de 16384 entradas de 16 bits en
//      V9_BASE+0x8000 (entrada i en V9_BASE + 0x8000 + {i[13:0],1'b0}): [15:14] tipo (0 escribir, 1 NOP,
//      2 esperar (leer & dato) == 0, 3 esperar (leer & dato) != 0), [11:8] puerto P#n (60h+n), [7:0] dato.
//      Cada ronda lee ese control (1 beat, despues de la lectura +0x00..+0x2F). Con en = 1 y >= 64 entradas
//      pendientes y sitio en la FIFO (32 x 64 bits, 4 entradas por palabra, la 0 en [15:0]) trae 64 con una
//      rafaga de 16 beats; el ARM rellena siempre hasta multiplos de 64 con NOP. Con en = 0: FIFO vacia y rd
//      sigue a wr. TELEMETRIA +0xC4 (32 bits): {rd[31:16], nivel de la FIFO en entradas[15:8],
//      esperas vencidas (satura en 15)[7:4], en[3], 0[2], busy[1], own[0]}; busy = entrada en ejecucion,
//      own = el ARM tiene el bus del V9990.
//  AXI3 master minimo a clk_54m (sin CDC con el nucleo): una transaccion en
//  vuelo, lecturas de 5 beats (control) o 16 (WaveGame), escrituras single-beat. Drena B/R en reset (el HP
//  del PS no se resetea al reprogramar el PL — medido en 05_hp_bench).
// ============================================================================
module dbg_mailbox_axi #(
    parameter [31:0] MBOX    = 32'h1FF0_0000,
    parameter        PERIOD  = 54000,           // ciclos entre rondas (~1 ms a 54 MHz)
    parameter        ENABLE  = 1,               // 0 = instanciado pero sin trafico (biseccion)
    parameter [31:0] WG_BASE = 32'h1FF8_0000,    // anillo WaveGame (64 KB = 32768 muestras int16); +0x10000 es el SDBUF del proxy
    parameter [31:0] TP_BASE = 32'h1FFA_0000,   // Z1.1: anillo de pulsos de la cinta (64 KB = 16384 entradas de 32 bits)
    parameter [31:0] V9_BASE = 32'h1FFB_0000    // V9990 por el ARM: control +0x0000, anillo de 16384 entradas de 16 bits en +0x8000
)(
    input  wire         clk,
    input  wire         aresetn,

    output reg  [127:0] kbd_mbox,               // bitmap HID leido del buzon
    // +0x10..+0x1F (companion ARM, USB host): joysticks en formato SNES del BL616 y
    // raton como acumulados int16 (ax, ay) + botones -> aqui se saca el delta entre
    // dos lecturas (clamp a +-127, el resto queda para la siguiente) y un pulso.
    output reg  [15:0]  joy1,
    output reg  [15:0]  joy2,
    output reg  [7:0]   mouse_btn,
    output reg  [7:0]   mouse_dx,
    output reg  [7:0]   mouse_dy,
    output reg          mouse_rep,              // pulso de un ciclo: nuevo informe de raton
    // +0x1C: palabra de control del sistema (la escribe boot.tcl o el companion):
    //   bit 0 = MSX_RUN: mientras sea 0 el MSX queda en reset (el pack aun no esta en la DDR).
    //   Con BOOT.bin el FSBL carga un bloque de ceros en el buzon -> el MSX espera al companion.
    output reg          msx_run,
    output reg  [20:0]  cfg_in,                 // +0x1C bits [28:8]: {valid, gain[2:0], turbo, config2[7:0], config1[7:0]}
                                                //   = bloque de config guardado en la QSPI que el companion pone ANTES de MSX_RUN
    output reg  [31:0]  mix_in,                 // +0x24 {valid[31], 3'b0, niveles del mezclador[27:0]} (V3.7), mismas reglas
    output reg  [31:0]  vid_ctl,                // +0x2C control de video (ARM/OSD): {seq[15:8], 6'b0, auto_off[1], sel[0]}: al cambiar
                                                //   seq, la HDMI pasa a sel (0 = V9968, 1 = V9990); auto_off = 1 apaga la conmutacion
                                                //   automatica por DISP del V9990; la tecla Pausa sigue conmutando (tools/vsel.tcl)
    output reg          trace_arm,              // +0x1C bit 1: armar el trazador del VDP (vdp_trace.v)
    output reg          trace_auxonly,          // +0x1C bit 2: el trazador solo registra los eventos auxiliares (UART del ESP)
    output reg          net_ps,                 // +0x1C bit 3 (25/09): la UART del ESP (wifi_lite) va a la UART1 del PS: el companion
                                                //   hace de "ESP32" por Ethernet. A 0, el ESP32 externo del CAM1 como siempre.
    output reg          s3_ps,                  // +0x1C bit 4 (02/10): el ESP32 del CAM1 (la S3) habla con la UART1 del PS y el MSX
                                                //   queda aparte: la actualizacion por red sale por su WiFi cuando no hay cable.
    input  wire         trace_full,             // el anillo esta lleno: se vuelca cada ronda
    output reg  [9:0]   trace_rd_addr,
    input  wire [31:0]  trace_rd_data,          // dato del anillo, 1 ciclo tras trace_rd_addr
    input  wire [319:0] tel_lat,                // perfil TR fase 0: +0xD8..+0xFF, 5 palabras de 64 bits (memory_axi.lat_tel)
    output reg          lat_clr,                // +0x1C bit 5: flanco de subida = puesta a cero de esa telemetria
`ifdef PERFIL_TR
    output reg          tr_bios,                // +0x1C bit 6 (perfil TR, fase 2): la BIOS del turbo R esta en la DDR (0x0E400000, 4 MB; kanji en el pack): mapa de slots FS-A1ST
`endif
    input  wire [31:0]  tel_hits,
    input  wire [31:0]  tel_miss,
    input  wire [31:0]  tel_status,
    input  wire [31:0]  tel_dbg,
    input  wire [31:0]  tel_dbg2,
    input  wire [31:0]  tel_dbg3,               // +0x60 {tel_dbg3, tel_dbg4}
    input  wire [31:0]  tel_dbg4,
    input  wire [31:0]  tel_vmiss,              // +0x6C {spmiss[15:0], bgmiss[15:0]} (v9968_vram_shim dbg_miss)
    input  wire [31:0]  tel_vdrops,              // +0x68 {s1_pfq[15:0], wq_full[15:0]} (dbg_drops)
    input  wire [31:0]  tel_cfg,                 // +0x70 {toggle[31], ..., gain[19:17], turbo[16], config2[15:8], config1[7:0]}: bloque vigente al pulsar "guardar"
    input  wire [31:0]  tel_wifi,                // +0x74 {wifi_unr_cnt, wifi_ovf_cnt}: FIFO del UART del ESP (bytes tirados / lecturas en vacio)
    input  wire [31:0]  tel_mix,                 // +0xC0 {toggle[31], 3'b0, niveles del mezclador[27:0]} al pulsar "guardar" (V3.7)
    // ---- Z80 -> ARM: anillo de 32 entradas {tag[7:0], data[7:0]} (puerto 92h = WaveGame, 93h = menu) ----
    input  wire [511:0] z2a_ring,                // entrada k en [16k +: 16]; se vuelca en +0x78..+0xB7 (palabras 7..14)
    input  wire [7:0]   z2a_wi,                  // indice de escritura libre (mod 256); +0xB8 [63:56]
    // ---- WaveGame: muestra PCM actual (clk), 0 en silencio ----
    output reg  signed [18:0] wg_smp,          // muestra x (1 << ganancia), ganancia = +0x20 bits [29:28]
    output reg  signed [18:0] wg_smp_r,        // 23/09: canal derecho en estereo (bit 30 de +0x20); en mono = wg_smp
    // ---- CINTA VIRTUAL (Z1.1, 18/09): anillo de pulsos {nivel[31], duracion[30:0] en ciclos de clk} en TP_BASE,
    //      control +0x28 {play[31], monitor[30], sin_motor[29], 13'b0, wr[15:0]} (wr = entradas escritas mod 65536).
    //      El nivel sale por tape_in (1 en reposo = lo que leia el PSG hasta hoy) y solo avanza con el motor del
    //      casete en marcha (PPI PC4 = 0) salvo sin_motor. +0xC8 lleva rd, nivel de la FIFO y underruns; +0xCC estado.
    output reg          tape_in,
    output wire         tape_play,
    output wire         tape_mon,
    output wire         tape_nonextor,          // +0x28 bit 28: sin Nextor (el slot 3-2 desaparece: BASIC limpio para la cinta)
    input  wire         tape_motor,             // 1 = motor en marcha (~ppi_port_c[4])
    // ---- V9990 por el ARM: entradas al inyector (v9990_arm_port.v, mismo reloj) ----
    output wire         v9_en,                  // V9_BASE+0 bit 31
    output reg  [15:0]  v9_ent,                 // entrada en cabeza de la FIFO
    output reg          v9_ent_v,               // v9_ent valida (se consume con v9_pop, pulso de un ciclo)
    input  wire         v9_pop,
    // Perfil Dual (31/10/2026): la mitad alta del beat de control del V9990 (V9_BASE+4, que el companion no toca: escribe V9_CTL de 32
    // bits en V9_BASE+0) es la palabra de control de la maquina B. Solo existe con PERFIL_DUAL: con el estandar el modulo es el de siempre
    // (un puerto sin carga quitaba la sintesis, pero dejaba +1 LUT y +1 FF de diferencia).
`ifdef PERFIL_DUAL
    output reg  [31:0]  b_ctl,
    // 2/11/2026 (escritorio de dos columnas): la segunda palabra del mismo control (V9_BASE+8, otro beat de 64 bits que se lee a continuacion:
    // posicion fina de B y peticion de foco) y una palabra de telemetria mas (+0xD0): el puntero del raton, la ventana de A y el foco
    output reg  [31:0]  b_ctl2,
    input  wire [63:0]  tel_wm,
`endif
    input  wire         v9_own,                 // telemetria +0xC4
    input  wire         v9_busy,
    input  wire [3:0]   v9_tmo,

    output reg  [5:0]   M_AWID,
    output reg  [31:0]  M_AWADDR,
    output wire [3:0]   M_AWLEN,
    output wire [2:0]   M_AWSIZE,
    output wire [1:0]   M_AWBURST,
    output wire [1:0]   M_AWLOCK,
    output wire [3:0]   M_AWCACHE,
    output wire [2:0]   M_AWPROT,
    output wire [3:0]   M_AWQOS,
    output reg          M_AWVALID,
    input  wire         M_AWREADY,
    output reg  [5:0]   M_WID,
    output reg  [63:0]  M_WDATA,
    output wire [7:0]   M_WSTRB,
    output wire         M_WLAST,
    output reg          M_WVALID,
    input  wire         M_WREADY,
    input  wire [5:0]   M_BID,
    input  wire [1:0]   M_BRESP,
    input  wire         M_BVALID,
    output reg          M_BREADY,
    output reg  [5:0]   M_ARID,
    output reg  [31:0]  M_ARADDR,
    output reg  [3:0]   M_ARLEN,
    output wire [2:0]   M_ARSIZE,
    output wire [1:0]   M_ARBURST,
    output wire [1:0]   M_ARLOCK,
    output wire [3:0]   M_ARCACHE,
    output wire [2:0]   M_ARPROT,
    output wire [3:0]   M_ARQOS,
    output reg          M_ARVALID,
    input  wire         M_ARREADY,
    input  wire [5:0]   M_RID,
    input  wire [63:0]  M_RDATA,
    input  wire [1:0]   M_RRESP,
    input  wire         M_RLAST,
    input  wire         M_RVALID,
    output reg          M_RREADY
);
    assign M_AWLEN = 4'd0;  assign M_AWSIZE = 3'b011; assign M_AWBURST = 2'b01;
    assign M_AWLOCK = 2'b00; assign M_AWCACHE = 4'b0011; assign M_AWPROT = 3'b000; assign M_AWQOS = 4'd0;
    assign M_WSTRB = 8'hFF; assign M_WLAST = 1'b1;
    assign M_ARSIZE = 3'b011; assign M_ARBURST = 2'b01;   // M_ARLEN: 5 = 6 beats de control (+0x00..+0x2F), 15 = rafaga WaveGame/cinta
    assign M_ARLOCK = 2'b00; assign M_ARCACHE = 4'b0011; assign M_ARPROT = 3'b000; assign M_ARQOS = 4'd0;

    localparam [3:0] S_WAIT = 4'd0, S_RD = 4'd1, S_RDATA = 4'd2, S_WR = 4'd3, S_WRESP = 4'd4,
                     S_TA = 4'd5, S_TB = 4'd6, S_TC = 4'd7, S_TRESP = 4'd8,
                     S_WGA = 4'd9, S_WGD = 4'd10, S_TPA = 4'd11, S_TPD = 4'd12;
    localparam [4:0] S_V9A = 5'd13, S_V9D = 5'd14, S_V9CA = 5'd15, S_V9CD = 5'd16, S_V9CE = 5'd17;
    reg [4:0]  st;
    // ---- V9990 por el ARM: control (V9_BASE+0), FIFO de 32 x 4 entradas ----
    reg [31:0] v9_ctl;
    assign v9_en = v9_ctl[31];
    wire [15:0] v9_wr = v9_ctl[15:0];
    reg [15:0] v9_rd;                // entradas ya traidas (mod 65536; direccion = rd[13:0]*2)
    reg [63:0] v9_fifo [0:31];
    reg [5:0]  v9_fwr, v9_frd;       // punteros libres (mod 64): nivel = fwr - frd (0..32 palabras)
    wire [5:0] v9_flevel = v9_fwr - v9_frd;
    reg [63:0] v9_head;
    reg [2:0]  v9_hcnt;              // entradas que quedan en v9_head
    reg [3:0]  v9_beat;
    wire [15:0] v9_avail = v9_wr - v9_rd;
    wire       v9_fetch_ok = v9_en && (v9_avail >= 16'd64) && (v9_flevel <= 6'd16);
    wire [7:0] v9_lvl = {v9_flevel, 2'b00} + {5'd0, v9_hcnt} + {7'd0, v9_ent_v};
`ifdef PERFIL_TR
    // Perfil TR (02/11/2026): bit 2 = 1 -> "este PL es el perfil TR" (sin V9990 ni OPL4). Lo lee el companion (tr_activo): vale tambien con el perfil
    // cargado por JTAG, donde mxpf_id_activo() no lo sabe. En los demas perfiles es el 0 de siempre.
    `ifdef TR_V9990
    wire [31:0] v9_tel = {v9_rd, v9_lvl[7:1], 1'b1, v9_tmo, v9_en, 1'b1, v9_busy, v9_own};   // perfil TRV: bit 8 = 1, este TR si tiene V9990 (v99desk.c, osd.c)
`else
    wire [31:0] v9_tel = {v9_rd, v9_lvl, v9_tmo, v9_en, 1'b1, v9_busy, v9_own};
`endif
`else
    wire [31:0] v9_tel = {v9_rd, v9_lvl, v9_tmo, v9_en, 1'b0, v9_busy, v9_own};
`endif
    // ---- WaveGame: control del ARM (+0x20), FIFO de 128 x 4 muestras y voz a 44,1 kHz ----
    reg [31:0] wg_ctl;               // {play[31], 1'b0, gain[29:28], 12'b0, wr[15:0]} tal como lo deja el companion
    wire       wg_play = wg_ctl[31];
    wire [1:0] wg_gain = wg_ctl[29:28];   // desplazamiento: x1, x2, x4, x8 (el grupo PSG/SCC entra x5)
    reg  signed [15:0] wg_raw;
    reg  signed [15:0] wg_raw_r;     // 23/09: canal derecho (en mono, copia de wg_raw)
    wire       wg_stereo = wg_ctl[30];   // 23/09: pares {L, R} en el anillo
    wire [15:0] wg_wr  = wg_ctl[15:0];
    reg [15:0] wg_rd;                // muestras ya traidas del anillo de la DDR (mod 65536; direccion = rd[14:0]*2)
    reg [63:0] wg_fifo [0:127];
    reg [7:0]  wg_fwr, wg_frd;       // punteros libres (mod 256): nivel = fwr - frd (0..128)
    wire [7:0] wg_flevel = wg_fwr - wg_frd;
    reg [1:0]  wg_sub;               // muestra dentro de la palabra de 64 bits en curso
    reg [63:0] wg_head;
    reg        wg_head_ok;
    reg [3:0]  wg_beat;
    reg [7:0]  wg_fetches;
    reg [25:0] wg_acc;               // 44100/54e6: tick exacto de media
    reg        wg_tick;
    wire [15:0] wg_avail = wg_wr - wg_rd;
    wire       wg_fetch_ok = wg_play && (wg_avail >= 16'd64) && (wg_flevel <= 8'd112);
    // ---- cinta: control +0x28, FIFO de 32 x 2 entradas y contador de pulsos ----
    reg [31:0] tp_ctl;
    assign tape_play = tp_ctl[31];
    assign tape_mon  = tp_ctl[30];
    assign tape_nonextor = tp_ctl[28];
    wire       tp_nomotor = tp_ctl[29];
    wire [15:0] tp_wr = tp_ctl[15:0];
    reg [15:0] tp_rd;                // entradas ya traidas del anillo (mod 65536; direccion = rd[13:0]*4)
    reg [63:0] tp_fifo [0:31];
    reg [5:0]  tp_fwr, tp_frd;       // punteros libres (mod 64): nivel = fwr - frd (0..32)
    wire [5:0] tp_flevel = tp_fwr - tp_frd;
    reg [63:0] tp_head;
    reg        tp_head_ok, tp_sub;
    reg [30:0] tp_cnt;               // ciclos que quedan del pulso en curso
    reg [3:0]  tp_beat;
    reg [7:0]  tp_fetches, tp_unr;
    wire [15:0] tp_avail = tp_wr - tp_rd;
    wire       tp_fetch_ok = tape_play && (tp_avail >= 16'd32) && (tp_flevel <= 6'd16);
    wire       tp_run = tape_play && (tape_motor || tp_nomotor);
    wire [30:0] tp_d0 = tp_fifo[tp_frd[4:0]][30:0];   // duracion de la entrada baja de la palabra en cabeza
    wire [30:0] tp_d1 = tp_head[62:32];               // y de la alta (ya en tp_head)
    reg [8:0]  tidx;                 // palabra de la traza en curso (0..511)
    reg [31:0] tlo;
    reg        tf_d, trace_pend;     // flanco de subida de trace_full = una captura nueva pendiente de volcar
    reg [15:0] tick;
    reg [2:0]  r_beat;
    reg [63:0] r_lo, r_hi;
    reg [15:0] ax_p, ay_p;                                 // acumulados ya entregados
    reg [7:0]  btn_p;
    wire [15:0] ax_n = M_RDATA[15:0], ay_n = M_RDATA[31:16];   // beat 3
    wire signed [16:0] ddx = $signed({ax_n[15], ax_n}) - $signed({ax_p[15], ax_p});
    wire signed [16:0] ddy = $signed({ay_n[15], ay_n}) - $signed({ay_p[15], ay_p});
    wire signed [7:0]  cdx = (ddx > 17'sd127) ? 8'sd127 : (ddx < -17'sd127) ? -8'sd127 : ddx[7:0];
    wire signed [7:0]  cdy = (ddy > 17'sd127) ? 8'sd127 : (ddy < -17'sd127) ? -8'sd127 : ddy[7:0];
    reg [4:0]  widx;                 // palabra de telemetria en curso (0..16)
    reg [31:0] seq;
    reg        aw_done, w_done;

    wire aw_acc = M_AWVALID && M_AWREADY;
    wire w_acc  = M_WVALID  && M_WREADY;
    wire b_acc  = M_BVALID  && M_BREADY;
    wire ar_acc = M_ARVALID && M_ARREADY;
    wire r_acc  = M_RVALID  && M_RREADY;

    reg [63:0] wword;
    always @(*) begin
        case (widx)
        4'd0: wword = {seq, 32'h4D42_4F58};
        4'd1: wword = {tel_miss, tel_hits};
        4'd2: wword = {tel_status, kbd_mbox[31:0]};
        4'd3: wword = {tel_dbg, tel_dbg2};
        4'd4: wword = {tel_dbg3, tel_dbg4};
        4'd5: wword = {tel_vmiss, tel_vdrops};
        4'd6: wword = {tel_wifi, tel_cfg};      // +0x74 {wifi_unr_cnt[31:16], wifi_ovf_cnt[15:0]} (UART del ESP)
        4'd7:  wword = z2a_ring[ 63:  0];   // +0x78 entradas 0..3
        4'd8:  wword = z2a_ring[127: 64];   // +0x80 4..7
        4'd9:  wword = z2a_ring[191:128];   // +0x88 8..11
        4'd10: wword = z2a_ring[255:192];   // +0x90 12..15
        4'd11: wword = z2a_ring[319:256];   // +0x98 16..19
        4'd12: wword = z2a_ring[383:320];   // +0xA0 20..23
        4'd13: wword = z2a_ring[447:384];   // +0xA8 24..27
        4'd14: wword = z2a_ring[511:448];   // +0xB0 28..31
        4'd15: wword = {z2a_wi, 8'd0, wg_rd, 8'd0, wg_flevel, wg_fetches, 7'd0, wg_play};   // +0xB8
        5'd16: wword = {v9_tel, tel_mix};       // +0xC0 niveles del mezclador + toggle (V3.7); +0xC4 telemetria del V9990 por el ARM
        5'd17: wword = {tp_fetches, 20'd0, tp_nomotor, tape_motor, tape_in, tape_play,   // +0xCC estado de la cinta
                        tp_rd, 2'b00, tp_flevel, tp_unr};                                 // +0xC8 rd, nivel FIFO, underruns
`ifdef PERFIL_DUAL
        5'd18: wword = tel_wm;                  // +0xD0 (Dual): puntero, ventana de A y foco (la captura del top)
`endif
`ifdef TR_DEBUG
        5'd19: wword = tel_lat[ 63:  0];        // +0xD8 {suma de ciclos totales de los fallos, max, min} (ver memory_axi.v)
        5'd20: wword = tel_lat[127: 64];        // +0xE0 {suma AR->linea, max, min}
        5'd21: wword = tel_lat[191:128];        // +0xE8 {suma de espera hasta el AR, max, max de un acierto}
        5'd22: wword = tel_lat[255:192];        // +0xF0 histograma, cajones 0..3 (16 bits cada uno, el 0 abajo)
        5'd23: wword = tel_lat[319:256];        // +0xF8 histograma, cajones 4..7
`endif
        default: wword = 64'd0;
        endcase
    end

    always @(posedge clk) begin
        if (!aresetn) begin
            st <= S_WAIT; tick <= 16'd0; r_beat <= 3'd0; r_lo <= 64'd0; r_hi <= 64'd0; widx <= 5'd0; seq <= 32'd0;
            mix_in <= 32'd0;
            wg_ctl <= 32'd0; wg_rd <= 16'd0; wg_fwr <= 8'd0; wg_frd <= 8'd0; wg_sub <= 2'd0; wg_head <= 64'd0;
            wg_head_ok <= 1'b0; wg_beat <= 4'd0; wg_fetches <= 8'd0; wg_acc <= 26'd0; wg_tick <= 1'b0; wg_smp <= 19'sd0; wg_raw <= 16'sd0;
            wg_smp_r <= 19'sd0; wg_raw_r <= 16'sd0;
            tp_ctl <= 32'd0; vid_ctl <= 32'd0; tp_rd <= 16'd0; tp_fwr <= 6'd0; tp_frd <= 6'd0; tp_head <= 64'd0; tp_head_ok <= 1'b0; tp_sub <= 1'b0;
            tp_cnt <= 31'd0; tp_beat <= 4'd0; tp_fetches <= 8'd0; tp_unr <= 8'd0; tape_in <= 1'b1;
            M_ARLEN <= 4'd5;
            aw_done <= 1'b0; w_done <= 1'b0; kbd_mbox <= 128'd0;
            joy1 <= 16'd0; joy2 <= 16'd0; mouse_btn <= 8'd0; mouse_dx <= 8'd0; mouse_dy <= 8'd0; mouse_rep <= 1'b0;
            msx_run <= 1'b0; lat_clr <= 1'b0; trace_arm <= 1'b0; trace_auxonly <= 1'b0; net_ps <= 1'b0; s3_ps <= 1'b0; trace_rd_addr <= 10'd0; tidx <= 9'd0; tlo <= 32'd0; cfg_in <= 21'd0;
            tf_d <= 1'b0; trace_pend <= 1'b0;
`ifdef PERFIL_TR
            tr_bios <= 1'b0;
`endif
            v9_ctl <= 32'd0; v9_rd <= 16'd0;
`ifdef PERFIL_DUAL
            b_ctl <= 32'd0; b_ctl2 <= 32'd0;
`endif v9_fwr <= 6'd0; v9_frd <= 6'd0; v9_head <= 64'd0; v9_hcnt <= 3'd0; v9_beat <= 4'd0;
            v9_ent <= 16'd0; v9_ent_v <= 1'b0;
            ax_p <= 16'd0; ay_p <= 16'd0; btn_p <= 8'd0;
            M_AWVALID <= 1'b0; M_WVALID <= 1'b0; M_ARVALID <= 1'b0;
            M_AWID <= 6'd0; M_WID <= 6'd0; M_ARID <= 6'd0;
            M_AWADDR <= 32'd0; M_ARADDR <= 32'd0; M_WDATA <= 64'd0;
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;            // drenar herencias del HP
        end else begin
            M_BREADY <= 1'b1; M_RREADY <= 1'b1;
            mouse_rep <= 1'b0;
            tf_d <= trace_full;
            if (trace_full && !tf_d) trace_pend <= 1'b1;
            if (aw_acc) begin M_AWVALID <= 1'b0; aw_done <= 1'b1; end
            if (w_acc)  begin M_WVALID  <= 1'b0; w_done  <= 1'b1; end
            if (ar_acc) M_ARVALID <= 1'b0;

            case (st)
            S_WAIT: begin
                tick <= tick + 1'b1;
                if (ENABLE && tick == PERIOD[15:0]) begin
                    tick <= 16'd0;
                    M_ARADDR <= MBOX; M_ARID <= 6'd0; M_ARLEN <= 4'd5; M_ARVALID <= 1'b1; r_beat <= 3'd0;
                    st <= S_RD;
                end
                else if (ENABLE && wg_fetch_ok) st <= S_WGA;     // 23/09: rafagas entre rondas (estereo)
                else if (ENABLE && tp_fetch_ok) st <= S_TPA;
                else if (ENABLE && v9_fetch_ok) st <= S_V9A;
            end
            S_RD: if (ar_acc || !M_ARVALID) st <= S_RDATA;
            S_RDATA: begin
                if (r_acc) begin
                    r_beat <= r_beat + 3'd1;
                    case (r_beat)
                    3'd0: r_lo <= M_RDATA;
                    3'd1: begin r_hi <= M_RDATA; kbd_mbox <= {M_RDATA, r_lo}; end
                    3'd2: begin joy1 <= M_RDATA[15:0]; joy2 <= M_RDATA[31:16]; btn_p <= M_RDATA[39:32]; end   // +0x10 joy, +0x14 btn|seq
                    3'd3: begin                                                                             // +0x18 {ay, ax}, +0x1C control
                        msx_run <= M_RDATA[32];
                        trace_arm <= M_RDATA[33];
                        trace_auxonly <= M_RDATA[34];
                        net_ps <= M_RDATA[35];
                        s3_ps <= M_RDATA[36];
`ifdef TR_DEBUG
                        lat_clr <= M_RDATA[37];
`endif
`ifdef PERFIL_TR
                        tr_bios <= M_RDATA[38];
`endif
                        cfg_in <= M_RDATA[60:40];
                        if (ax_n != ax_p || ay_n != ay_p || btn_p != mouse_btn) begin
                            mouse_dx <= cdx; mouse_dy <= cdy; mouse_btn <= btn_p; mouse_rep <= 1'b1;
                            ax_p <= ax_p + {{8{cdx[7]}}, cdx}; ay_p <= ay_p + {{8{cdy[7]}}, cdy};
                        end
                    end
                    3'd4: begin                                                                             // +0x20 control WaveGame, +0x24 mezclador
                        wg_ctl <= M_RDATA[31:0];
                        mix_in <= M_RDATA[63:32];
                    end
                    default: begin                                                                          // +0x28 control de la cinta, +0x2C control de video
                        tp_ctl <= M_RDATA[31:0];
                        vid_ctl <= M_RDATA[63:32];
                        widx <= 5'd0;
                        st <= S_V9CA;                                                                       // luego, 1 beat de V9_BASE (control del V9990)
                    end
                    endcase
                end
            end
            S_V9CA: begin
`ifdef PERFIL_DUAL
                M_ARADDR <= V9_BASE; M_ARID <= 6'd3; M_ARLEN <= 4'd1; M_ARVALID <= 1'b1;     // dos beats: V9_BASE+0 (control del V9990 y de B) y +8 (B)
`else
                M_ARADDR <= V9_BASE; M_ARID <= 6'd3; M_ARLEN <= 4'd0; M_ARVALID <= 1'b1;
`endif
                st <= S_V9CD;
            end
            S_V9CD: if (r_acc) begin
                v9_ctl <= M_RDATA[31:0];
`ifdef PERFIL_DUAL
                b_ctl <= M_RDATA[63:32];
                st <= S_V9CE;
`else
                st <= S_WR;
`endif
            end
`ifdef PERFIL_DUAL
            S_V9CE: if (r_acc) begin
                b_ctl2 <= M_RDATA[31:0];
                st <= S_WR;
            end
`endif
            S_WR: begin
                M_AWADDR <= MBOX + 32'h40 + {widx, 3'b000}; M_AWID <= 6'd0; M_WID <= 6'd0;
                M_WDATA  <= wword;
                M_AWVALID <= 1'b1; M_WVALID <= 1'b1;
                aw_done <= 1'b0; w_done <= 1'b0;
                st <= S_WRESP;
            end
            S_WRESP: begin
                if ((aw_done || aw_acc) && (w_done || w_acc) && b_acc) begin
`ifdef TR_DEBUG
                    if (widx == 5'd23) begin   // ultima palabra: +0xF8 (perfil TR fase 0: telemetria de latencia)
`elsif PERFIL_DUAL
                    if (widx == 5'd18) begin
`else
                    if (widx == 5'd17) begin
`endif
                        seq <= seq + 1'b1;
                        // el volcado es de UN DISPARO por captura (flanco de trace_full): antes se
                        // repetia cada ronda mientras el anillo estuviera lleno = 4 KB/ms a la DDR
                        if (trace_pend) begin tidx <= 9'd0; trace_rd_addr <= 10'd0; trace_pend <= 1'b0; st <= S_TA; end
                        else if (wg_fetch_ok) st <= S_WGA;
                        else if (tp_fetch_ok) st <= S_TPA;
                        else if (v9_fetch_ok) st <= S_V9A;
                        else st <= S_WAIT;
                    end
                    else begin widx <= widx + 1'b1; st <= S_WR; end
                end
            end
            // ---- volcado de la traza del VDP: 512 palabras de {evento impar, evento par} ----
            S_TA: begin trace_rd_addr <= {tidx, 1'b1}; st <= S_TB; end          // (dato del par en el ciclo siguiente)
            S_TB: begin tlo <= trace_rd_data; st <= S_TC; end
            S_TC: begin
                M_AWADDR <= MBOX + 32'h1000 + {tidx, 3'b000}; M_AWID <= 6'd0; M_WID <= 6'd0;
                M_WDATA  <= {trace_rd_data, tlo};
                M_AWVALID <= 1'b1; M_WVALID <= 1'b1;
                aw_done <= 1'b0; w_done <= 1'b0;
                st <= S_TRESP;
            end
            S_TRESP: begin
                if ((aw_done || aw_acc) && (w_done || w_acc) && b_acc) begin
                    if (tidx == 9'd511) st <= (wg_fetch_ok ? S_WGA : (tp_fetch_ok ? S_TPA : (v9_fetch_ok ? S_V9A : S_WAIT)));
                    else begin tidx <= tidx + 1'b1; trace_rd_addr <= {tidx + 9'd1, 1'b0}; st <= S_TA; end
                end
            end
            // ---- WaveGame: rafaga de 16 beats (64 muestras) del anillo de la DDR a la FIFO ----
            S_WGA: begin
                M_ARADDR <= WG_BASE + {16'd0, wg_rd[14:0], 1'b0}; M_ARID <= 6'd1; M_ARLEN <= 4'd15;
                M_ARVALID <= 1'b1; wg_beat <= 4'd0;
                st <= S_WGD;
            end
            S_WGD: begin
                if (r_acc) begin
                    wg_fifo[wg_fwr[6:0]] <= M_RDATA;
                    wg_fwr <= wg_fwr + 8'd1;
                    wg_beat <= wg_beat + 4'd1;
                    if (wg_beat == 4'd15) begin
                        wg_rd <= wg_rd + 16'd64; wg_fetches <= wg_fetches + 8'd1;
                        st <= tp_fetch_ok ? S_TPA : S_WAIT;
                    end
                end
            end
            // ---- cinta: rafaga de 16 beats (32 entradas de 32 bits) del anillo de la DDR a la FIFO ----
            S_TPA: begin
                M_ARADDR <= TP_BASE + {16'd0, tp_rd[13:0], 2'b00}; M_ARID <= 6'd2; M_ARLEN <= 4'd15;
                M_ARVALID <= 1'b1; tp_beat <= 4'd0;
                st <= S_TPD;
            end
            S_TPD: begin
                if (r_acc) begin
                    tp_fifo[tp_fwr[4:0]] <= M_RDATA;
                    tp_fwr <= tp_fwr + 6'd1;
                    tp_beat <= tp_beat + 4'd1;
                    if (tp_beat == 4'd15) begin
                        tp_rd <= tp_rd + 16'd32; tp_fetches <= tp_fetches + 8'd1;
                        st <= S_WAIT;
                    end
                end
            end
            // ---- V9990 por el ARM: rafaga de 16 beats (64 entradas de 16 bits) del anillo de la DDR a la FIFO ----
            S_V9A: begin
                M_ARADDR <= V9_BASE + 32'h8000 + {17'd0, v9_rd[13:0], 1'b0}; M_ARID <= 6'd4; M_ARLEN <= 4'd15;
                M_ARVALID <= 1'b1; v9_beat <= 4'd0;
                st <= S_V9D;
            end
            S_V9D: begin
                if (r_acc) begin
                    v9_fifo[v9_fwr[4:0]] <= M_RDATA;
                    v9_fwr <= v9_fwr + 6'd1;
                    v9_beat <= v9_beat + 4'd1;
                    if (v9_beat == 4'd15) begin
                        v9_rd <= v9_rd + 16'd64;
                        st <= S_WAIT;
                    end
                end
            end
            default: st <= S_WAIT;
            endcase

            // ---- V9990: en = 0 -> FIFO vacia y rd sigue a wr. Si no, se saca una entrada cada vez que el inyector la consume ----
            if (!v9_en) begin
                v9_frd <= v9_fwr; v9_hcnt <= 3'd0; v9_ent_v <= 1'b0;
                if (st != S_V9D) v9_rd <= v9_wr;
            end else if (v9_pop) v9_ent_v <= 1'b0;
            else if (!v9_ent_v) begin
                if (v9_hcnt != 3'd0) begin
                    v9_ent <= v9_head[15:0]; v9_head <= {16'd0, v9_head[63:16]}; v9_hcnt <= v9_hcnt - 3'd1; v9_ent_v <= 1'b1;
                end else if (v9_flevel != 6'd0) begin
                    v9_head <= v9_fifo[v9_frd[4:0]]; v9_frd <= v9_frd + 6'd1; v9_hcnt <= 3'd4;
                end
            end

            // ---- cinta: contador de pulsos. play=0 -> FIFO vacia, nivel en reposo y rd sigue a wr ----
            if (!tape_play) begin
                tp_frd <= tp_fwr; tp_head_ok <= 1'b0; tp_sub <= 1'b0; tp_cnt <= 31'd0; tape_in <= 1'b1;
                if (st != S_TPD) tp_rd <= tp_wr;
            end else if (tp_run) begin
                if (tp_cnt != 31'd0) tp_cnt <= tp_cnt - 31'd1;
                else if (!tp_head_ok) begin
                    if (tp_flevel != 6'd0) begin                              // primera entrada de la palabra
                        tp_head <= tp_fifo[tp_frd[4:0]]; tp_frd <= tp_frd + 6'd1; tp_head_ok <= 1'b1; tp_sub <= 1'b1;
                        tape_in <= tp_fifo[tp_frd[4:0]][31]; tp_cnt <= (tp_d0 == 31'd0) ? 31'd0 : tp_d0 - 31'd1;   // dura exactamente d ciclos
                    end else if (tp_unr != 8'hFF) tp_unr <= tp_unr + 8'd1;    // vacia: se mantiene el nivel
                end else begin                                                // segunda entrada de la palabra
                    tape_in <= tp_head[63]; tp_cnt <= (tp_d1 == 31'd0) ? 31'd0 : tp_d1 - 31'd1;
                    tp_head_ok <= 1'b0; tp_sub <= 1'b0;
                end
            end

            // ---- WaveGame: voz. play=0 -> FIFO vacia y rd sigue a wr (arranque limpio de la proxima cancion) ----
            if (!wg_play) begin
                wg_frd <= wg_fwr; wg_sub <= 2'd0; wg_head_ok <= 1'b0; wg_raw <= 16'sd0; wg_raw_r <= 16'sd0;
                if (st != S_WGD) wg_rd <= wg_wr;
            end
            wg_acc <= (wg_acc + 26'd44100 >= 26'd54000000) ? (wg_acc + 26'd44100 - 26'd54000000) : (wg_acc + 26'd44100);
            wg_tick <= (wg_acc + 26'd44100 >= 26'd54000000);
            case (wg_gain)                       // ganancia de la voz (registrada aparte: fuera del cono de la FIFO)
            2'd0: begin wg_smp <= {{3{wg_raw[15]}}, wg_raw};     wg_smp_r <= {{3{wg_raw_r[15]}}, wg_raw_r};     end
            2'd1: begin wg_smp <= {{2{wg_raw[15]}}, wg_raw, 1'b0}; wg_smp_r <= {{2{wg_raw_r[15]}}, wg_raw_r, 1'b0}; end
            2'd2: begin wg_smp <= {wg_raw[15], wg_raw, 2'b00};     wg_smp_r <= {wg_raw_r[15], wg_raw_r, 2'b00};     end
            default: begin wg_smp <= {wg_raw, 3'b000};              wg_smp_r <= {wg_raw_r, 3'b000};              end
            endcase
            if (wg_tick && wg_play) begin
                if (!wg_head_ok) begin
                    if (wg_flevel != 8'd0) begin
                        wg_head <= wg_fifo[wg_frd[6:0]]; wg_frd <= wg_frd + 8'd1; wg_head_ok <= 1'b1;
                        wg_raw   <= wg_fifo[wg_frd[6:0]][15:0];
                        wg_raw_r <= wg_stereo ? wg_fifo[wg_frd[6:0]][31:16] : wg_fifo[wg_frd[6:0]][15:0];
                        wg_sub   <= wg_stereo ? 2'd2 : 2'd1;                   // estereo: 1er par = [15:0],[31:16]
                    end else begin wg_raw <= 16'sd0; wg_raw_r <= 16'sd0; end    // vacia: silencio
                end else if (wg_stereo) begin                                  // 2o par de la palabra
                    wg_raw <= wg_head[47:32]; wg_raw_r <= wg_head[63:48];
                    wg_head_ok <= 1'b0;
                end else begin
                    case (wg_sub)
                    2'd1: begin wg_raw <= wg_head[31:16]; wg_raw_r <= wg_head[31:16]; end
                    2'd2: begin wg_raw <= wg_head[47:32]; wg_raw_r <= wg_head[47:32]; end
                    default: begin wg_raw <= wg_head[63:48]; wg_raw_r <= wg_head[63:48]; end
                    endcase
                    wg_sub <= wg_sub + 2'd1;
                    if (wg_sub == 2'd3) wg_head_ok <= 1'b0;
                end
            end
        end
    end
endmodule
