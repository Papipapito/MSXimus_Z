// ============================================================================
// v9991_compose.sv — El compositor "V9991": una sola HDMI para el V9968 y el
// V9990, mezclados POR PIXEL en el dominio 720p (74,25 MHz) en vez de conmutar
// dos flujos TMDS (hdmi_tmds_switch, 21/09-28/10/2026).
//
// Los dos puentes leen con el MISMO raster (cx/cy del hdmi de msx2hdmi_v9968;
// msx2hdmi_v9990 lee su frame buffer de la DDR con ese raster, parametro
// EXT_TIMING) y entregan cada uno el pixel de (cx,cy) con la misma alineacion
// que llevaban a su codificador. Aqui se elige uno por pixel y el resultado
// vuelve a msx2hdmi_v9968 (rgb_ext), que lo pasa por el overlay del F12 y por
// su unico codificador HDMI.
//
// Modos (se aplican en el vblank):
//   0  V9968 a pantalla completa                   (lo de hoy con Pausa = V9968)
//      Desde el 29/10/2026 (noche) tambien por el frame buffer del V9968: una ventana de pantalla
//      completa (x0 = y0 = 0, x1, origen 0/0, que es la columna cx/2 y la linea cy/3 del camino
//      enganchado de siempre), asi el hdmi corre LIBRE a 60,000 Hz en todos los modos (V9991f).
//   1  V9990 a pantalla completa                   (lo de hoy con Pausa = V9990)
//   2  LA VENTANA (Nishi, 21/10/2026): el V9990 es el escritorio y el V9968 se ve
//      dentro de un rectangulo, donde el V9990 es transparente (YSE = 1 y bit YS
//      de paleta). Fuera del rectangulo el pixel transparente se pinta con su
//      color. El V9968 llega por su frame buffer en la DDR (msx2hdmi_v9968 con
//      WINDOW): origen y escala programables. Lo gobiernan los registros R#55-R#62
//      del V9990 (los del MSXimus Z, el chip no los tiene), via winreg:
//        R#55 WINCTL  [7] WEN ventana activa · [6:5] MODE: 00 el modo lo pone el top
//                     (Pausa/buzon), 01 ventana (WEN = 0 -> modo 1), 10 Video9000
//                     (01 y 10 solo cuando el top esta en el V9990: con Pausa en el
//                     V9968 sale el V9968 entero, siempre; 29/10/2026),
//                     11 reservado · [4] BORD: la imagen del V9968 con sus bordes
//                     (640 x 240; con SRCX, SRCX puntos menos a cada lado: rama beta) o solo el contenido (512 x 212) · [3] x2 · [2] x0,5
//                     (29/10/2026; los dos a la vez: x0,75, el MSX entero en 768 x 477) · [1] WM (29/10/2026): el gestor de
//                     ventanas por hardware (v9991_wm.sv): marco, puntero y arrastre con el raton,
//                     ventana opaca; WX/WY solo dan la posicion inicial · [0] NOCLK (rama beta, 30/10/2026): sin el
//                     reloj del gestor (con WM = 1 sale salvo que este bit lo quite)
//        R#56/57 WX   esquina izquierda de la ventana en pixeles del V9990 (11 bits
//                     con signo: puede quedar fuera de la pantalla)
//        R#58/59 WY   esquina superior, en lineas del V9990 (11 bits con signo)
//        R#60 SRCX    origen dentro de la imagen del V9968, en pixeles de 256 (0..255)
//        R#61 SRCY    origen, en lineas (0..239)
//        R#62 SRCH    alto en lineas (0 = hasta el final de la imagen)
//      La escala x1 es el tamano NATIVO del V9968 en pantalla (igual que solo), sea
//      cual sea el modo del V9990: en B1/B3 coincide pixel a pixel con su rejilla.
//   3  "Video9000": V9990 encima del V9968 a pantalla completa, transparente donde
//      YSE = 1 y el bit YS de paleta (fuera de su ventana de 1136 px tambien).
//
// Geometria (en el vblank, para el frame siguiente): X0 = xstart(reso) + WX * k
// con k = 4 (B1), 3 (B2), 2 (B3 y B5), 1,5 (B4), 1 (B7) y xstart = 128 en B1/B3/B7 (72 del
// escalador del puente del V9990 + el borde izquierdo de 14/28 px del contenido),
// 64 en B2/B4 (overscan, sin bordes) y 0 en B5 (640 x2 = los 1280); Y0 = 42 + WY * 3 en
// B1/B3 (14 lineas de borde), WY * 3 en B2/B4, y 60 + WY * 1,5 en B5 (29/10/2026: 400
// lineas a x1,5 = 600 centradas; entrelazado: WY * 1,5, el cuadro tiene 424/480 lineas);
// ancho = columnas * (2, 4, 1 o 1,5 a x1, x2, x0,5, x0,75) con columnas = (BORD ? 640
// : 512) - 2 * SRCX; alto = lineas * (3, 6, 1,5 o 9/4). A x0,5 el MSX entero son 512 x 318 px:
// una ventana de 512 x 106 lineas de B7 (o 212 entrelazadas), lo que pinta Nishi; en B5
// son EXACTAMENTE 256 x 212 puntos (x2 y x1,5): un punto del V9968 por punto del B5.
//
// Sin registro en el camino del pixel: el mux es combinacional sobre los dos
// rgb ya registrados (el hdmi registra su entrada). Parte del MSXimus Z.
// Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9991_compose (
    input  wire        clk_pixel,     // 74,25 MHz
    input  wire [10:0] cx,            // raster comun (frame 1650 x 750)
    input  wire [9:0]  cy,
    input  wire [23:0] rgb68,         // pixel del V9968 en (cx,cy)
    input  wire [23:0] rgb99,         // pixel del V9990 en (cx,cy)
    input  wire        ys99,          // 1 = el pixel del V9990 es transparente (alineado con rgb99)
    input  wire        in99,          // 1 = el pixel esta dentro de la imagen del V9990 (fuera ys99 = 1)
    input  wire [1:0]  mode,          // modo pedido por el top (Pausa / buzon): 0, 1 o 3; cuasi-estatico
    input  wire [63:0] winreg,        // R#55..R#62 del V9990 ({R#62, ..., R#55}), clk_86, cuasi-estatico
    input  wire [2:0]  reso99,        // T9990_RESO del frame del V9990 que se muestra (clk_pixel)
    input  wire        il99,          // ese frame es entrelazado (480 lineas tejidas, x1,5): WY va x1,5 (28/10/2026)
    output wire [23:0] rgb,           // al codificador (misma alineacion que rgb68)
    output reg  [1:0]  mode_active,   // clk_pixel: modo que sale ahora
    output reg         desk_free,     // clk_pixel (rama beta): la ventana con el gestor (teclas V y B): el juego es del
                                      // V9968 y el V9990 es del companion (v9990_arm_port.allow)
    // ---- hacia msx2hdmi_v9968 (WINDOW): la ventana aplicada; cambia en el vblank ----
    output reg         win_en,        // el V9968 por su frame buffer: en todos los modos (V9991f)
    output reg signed [11:0] win_x0,  // esquina de la ventana en pantalla (px 720p)
    output reg signed [10:0] win_y0,
    output reg  [1:0]  win_scl,       // 00 x1, 10 x2, 01 x0,5, 11 x0,75
    output reg  [9:0]  win_sx0,       // origen en el frame del V9968: columna del anillo (0..639)
    output reg  [7:0]  win_sy0,       // linea nativa (0..239)
    // ---- raton para el gestor de ventanas (R#55 bit 1), dominio clk_m ----
    input  wire        clk_m,
    input  wire        m_rep,         // 1 ciclo por informe
    input  wire signed [7:0] m_dx,
    input  wire signed [7:0] m_dy,
    input  wire        m_btn,         // boton izquierdo, nivel
    input  wire [38:0] tod            // RTC en BCD (rtc.v), para el reloj del gestor de ventanas
`ifdef PERFIL_DUAL
    ,
    // Dual (2/11/2026): la ventana de A tiene el foco (cuasi-estatica, otro dominio) y, para el ARM, el puntero y la ventana de A. Los
    // valores salen tal cual de los registros del gestor, que solo cambian una vez por cuadro (junto a la linea 721); t_tgl conmuta en la
    // linea 300, bien lejos: el top los captura en clk_54m cuando ve el cambio (dato quieto, sin mas sincronizacion)
    input  wire        a_focus,
    input  wire        mute_a,        // A en silencio (clk_54m, dual_mute.v): cuasi-estatica, el gestor pinta hueco y gris el cuadradito de su barra
    output wire [10:0] t_px,
    output wire [9:0]  t_py,
    output wire        t_btn,
    output wire        t_drag,
    output wire        t_act,         // el gestor esta activo en el cuadro que sale
    output wire [10:0] t_wx,          // esquina de la ventana de A (px 720p)
    output wire [9:0]  t_wy,
    output reg         t_tgl = 1'b0
`endif
);
    // ---- entradas cuasi-estaticas a clk_pixel (dos etapas; se consumen solo en el vblank) ----
    reg [1:0]  mode_s0 = 2'd0, mode_s1 = 2'd0;
    reg [63:0] wr_s0 = 64'd0, wr_s1 = 64'd0;
    always @(posedge clk_pixel) begin
        mode_s0 <= mode;   mode_s1 <= mode_s0;
        wr_s0   <= winreg; wr_s1   <= wr_s0;
    end
    // ---- R#55..R#62 atomicos (30/10/2026, Z1.3): cada bit cruza por su 2FF y un WX o WY se escribe con dos OUT
    // (R#56 y luego R#57), asi que el vblank podia tomar un valor a medias. Solo se acepta un juego de registros
    // que lleva 2^15 ciclos (441 us) sin cambiar, y no en las lineas 718-720, donde el compositor lo esta usando:
    // un cambio aplica en el vblank siguiente o un cuadro mas tarde, pero siempre entero.
    reg [63:0] wr_p = 64'd0, wr_ok = 64'd0;
    reg [14:0] wr_stab = 15'd0;
    always @(posedge clk_pixel) begin
        wr_p <= wr_s1;
        if (wr_s1 != wr_p)  wr_stab <= 15'd0;
        else if (~&wr_stab) wr_stab <= wr_stab + 1'b1;
        if (&wr_stab && cy < 10'd718) wr_ok <= wr_p;
    end
    wire        r_wen  = wr_ok[7];
    wire [1:0]  r_mode = wr_ok[6:5];
    wire        r_bord = wr_ok[4];
    wire        r_x2   = wr_ok[3] & ~wr_ok[2];
    wire        r_half = wr_ok[2] & ~wr_ok[3];                 // x0,5 (29/10/2026): el MSX entero en 512 x 318
    wire        r_q75  = wr_ok[2] &  wr_ok[3];                 // x0,75 (29/10/2026): el MSX entero en 768 x 477 (tecla V, B5)
    wire        r_wm   = wr_ok[1];                             // gestor de ventanas por hardware (29/10/2026)
    wire        r_nock = wr_ok[0];                             // sin el reloj del gestor (rama beta, 30/10/2026)
    wire signed [10:0] r_wx = {wr_ok[18:16], wr_ok[15:8]};     // R#57[2:0] : R#56
    wire signed [10:0] r_wy = {wr_ok[34:32], wr_ok[31:24]};    // R#59[2:0] : R#58
    wire [7:0]  r_srcx = wr_ok[47:40];                         // R#60
    wire [7:0]  r_srcy = wr_ok[55:48];                         // R#61
    wire [7:0]  r_srch = wr_ok[63:56];                         // R#62

    // ---- geometria (combinacional sobre los registros; se latchea en el vblank) ----
    // Pausa manda (29/10/2026): con el top en el V9968 (modo 0) los registros no cuentan, asi siempre se puede salir de la
    // ventana; con el top en el V9990 (1, o 3 por el buzon) deciden R#55: MODE 01 -> ventana (o 1 sin WEN), 10 -> Video9000.
    // Antes MODE 01 se imponia al top y Pausa no hacia nada con la demo B7 en placa.
    wire [1:0] mode_req = (mode_s1 == 2'd0) ? 2'd0 :
                          (r_mode == 2'b01) ? (r_wen ? 2'd2 : 2'd1) :
                          (r_mode == 2'b10) ? 2'd3 : mode_s1;
    wire signed [12:0] wx13 = {{2{r_wx[10]}}, r_wx};
    wire signed [12:0] wxk  = (reso99 == 3'd1) ? (wx13 << 1) + wx13 :            // B2 x3
                              (reso99 == 3'd2 || reso99 == 3'd4) ? (wx13 << 1) : // B3 y B5 x2 (B5: 29/10/2026)
                              (reso99 == 3'd3) ? wx13 + (wx13 >>> 1) :           // B4 x1,5
                              (reso99 == 3'd6) ? wx13 :                          // B7 x1 (28/10/2026)
                                                 (wx13 << 2);                    // B1 x4
    // WX/WY son coordenadas del CONTENIDO del V9990, y el puente captura con bordes: en B1 y B3 el
    // contenido empieza en la columna 14 / 28 de la captura (x4 / x2 = 56 px de pantalla tras el
    // xstart 72 -> 128) y en la linea 14 (x3 = 42); en B2 y B4 (overscan) no hay bordes. Medido con
    // la demo del menu en la cadena del V9990 (28/10): sin esto la ventana caia 14 px a la izquierda. El core pintaba
    // ademas el contenido un punto antes que su ventana DA (B1: 13 puntos de borde, no 14): arreglado en el tiny9990
    // (COLOR_DECODE_DELAY 4, V9991 paso 3), asi que estos xstart son exactos punto a punto (B7: 72 + 56 = 128, k = 1).
    wire signed [12:0] xs13 = (reso99 == 3'd4) ? 13'sd0 : (reso99 == 3'd1 || reso99 == 3'd3) ? 13'sd64 : 13'sd128;   // B5: los 1280 enteros
    wire signed [12:0] x0_n = xs13 + wxk;
    wire signed [12:0] wy13 = {{2{r_wy[10]}}, r_wy};
    wire signed [12:0] ys13 = (reso99 == 3'd4) ? 13'sd60 : (reso99 == 3'd1 || reso99 == 3'd3) ? 13'sd0 : 13'sd42;   // B5: 600 lineas centradas
    wire signed [12:0] wyk  = (il99 || reso99 == 3'd4) ? (wy13 + (wy13 >>> 1)) : ((wy13 << 1) + wy13);   // x1,5 entrelazado (424 lineas) y B5 (400), x3 si no
    wire signed [12:0] y0_n = ys13 + wyk;
    wire [9:0]  sx0_n  = (r_bord ? 10'd0 : 10'd64) + {1'b0, r_srcx, 1'b0};
    wire [8:0]  sy0_s  = (r_bord ? 9'd0 : 9'd14) + {1'b0, r_srcy};
    wire [7:0]  sy0_n  = (sy0_s > 9'd239) ? 8'd239 : sy0_s[7:0];
    // rama beta (30/10/2026): con bordes el recorte de SRCX es SIMETRICO (SRCX puntos a cada lado): el menu deja 8 de
    // margen, el rango del ajuste horizontal R#18 (-7..+8): Sonyc pone R#18 = 08h y sin bordes la ventana cortaba 8
    // puntos por la derecha y enseñaba el borde por la izquierda. Sin bordes, como siempre (solo por la izquierda).
    wire [9:0]  cols_c = r_bord ? (10'd640 - {r_srcx, 2'b00}) : (10'd512 - {1'b0, r_srcx, 1'b0});
    wire [8:0]  ln_req = (r_srch == 8'd0) ? (r_bord ? 9'd240 : 9'd212) : {1'b0, r_srch};
    wire [8:0]  ln_max = 9'd240 - {1'b0, sy0_n};
    wire [8:0]  ln_c   = (ln_req > ln_max) ? ln_max : ln_req;
    wire signed [12:0] w_n = r_x2 ? {1'b0, cols_c, 2'b00} : r_half ? {3'b000, cols_c} :
                             r_q75 ? {3'b000, cols_c} + {4'b0000, cols_c[9:1]} : {2'b00, cols_c, 1'b0};    // cols * 4 / 1 / 1,5 / 2
    wire [11:0]        ln3 = {2'b00, ln_c, 1'b0} + {3'b000, ln_c};                                               // ln * 3
    wire [13:0]        ln9 = {1'b0, ln3, 1'b0} + {2'b00, ln3};                                                    // ln * 9
    wire signed [12:0] h_n = r_x2 ? {ln3, 1'b0} : r_half ? {2'b00, ln3[11:1]} :
                             r_q75 ? {1'b0, ln9[13:2]} : {1'b0, ln3};                                            // ln * 6 / 1,5 / 2,25 / 3
    // registrada (30/10/2026, Z1.3): la geometria solo cambia con wr_ok, reso99 o il99, nunca en las lineas 718-720, y
    // la cadena combinacional entera (h_c -> yhi -> clamp del gestor) era el peor camino del V9991f (23 niveles, 13 ns)
    reg signed [12:0] x0_c = 13'sd0, y0_c = 13'sd0, w_c = 13'sd0, h_c = 13'sd0;
    reg [9:0]  sx0_c = 10'd0;
    reg [7:0]  sy0_c = 8'd0;
    always @(posedge clk_pixel) begin
        x0_c <= x0_n; y0_c <= y0_n; w_c <= w_n; h_c <= h_n; sx0_c <= sx0_n; sy0_c <= sy0_n;
    end

    // ---- gestor de ventanas (R#55 bit 1): la posicion la lleva el raton; WX/WY solo la inicial ----
    reg  wm_act = 1'b0;                                        // gestor activo en el cuadro que sale
    reg  ck_act = 1'b0;                                        // y su reloj
    wire wm_req = (mode_req == 2'd2) && r_wm;
    wire signed [12:0] wm_x, wm_y;
`ifdef PERFIL_DUAL
    wire signed [12:0] wm_px, wm_py;
    wire        wm_drag, wm_btn;
    reg  [1:0]  af_s = 2'b11;
    reg  [1:0]  am_s = 2'b00;
    always @(posedge clk_pixel) begin
        af_s <= {af_s[0], a_focus};
        am_s <= {am_s[0], mute_a};
        if (cy == 10'd300 && cx == 11'd0) t_tgl <= ~t_tgl;
    end
    assign t_px = wm_px[10:0];  assign t_py = wm_py[9:0];  assign t_btn = wm_btn;  assign t_drag = wm_drag;  assign t_act = wm_act;
    assign t_wx = wm_x[10:0];   assign t_wy = wm_y[9:0];
`endif
    wire [1:0]  wm_ov;
    wire [23:0] wm_rgb;
    reg signed [12:0] x0_r = 13'sd0, x1_r = 13'sd0, y0_r = 13'sd0, y1_r = 13'sd0;
    v9991_wm u_wm (
        .clk_m(clk_m), .m_rep(m_rep), .m_dx(m_dx), .m_dy(m_dy), .m_btn(m_btn),
        .clk_pixel(clk_pixel), .cx(cx), .cy(cy), .on(wm_act), .clk_on(ck_act), .reso(reso99), .tod(tod),
        .init_x(x0_c), .init_y(y0_c), .ww(w_c), .wh(h_c),
        .x0(x0_r), .y0(y0_r), .x1(x1_r), .y1(y1_r),
        .wm_x(wm_x), .wm_y(wm_y), .ov(wm_ov), .ov_rgb(wm_rgb),
`ifdef PERFIL_DUAL
        .a_focus(af_s[1]), .mute_a(am_s[1]), .btn_o(wm_btn),
        .px(wm_px), .py(wm_py), .drag(wm_drag)
`else
        .px(), .py(), .drag()
`endif
    );
    // el primer cuadro con el gestor sale donde dicen los registros (el gestor se inicia con esa misma posicion)
    wire signed [12:0] x0_s = (wm_req && wm_act) ? wm_x : x0_c;
    wire signed [12:0] y0_s = (wm_req && wm_act) ? wm_y : y0_c;
    initial begin desk_free = 1'b0; mode_active = 2'd0; win_en = 1'b1; win_x0 = 12'sd0; win_y0 = 11'sd0; win_scl = 2'b00; win_sx0 = 10'd0; win_sy0 = 8'd0; end
    always @(posedge clk_pixel) begin
        if (cy == 10'd720 && cx == 11'd0) begin           // cambio entre frames
            mode_active <= mode_req;
            win_en  <= 1'b1;   // siempre (29/10/2026): en el modo 1 tambien, o Pausa del 1 al 0/2 sacaba un cuadro viejo del V9968
            wm_act  <= wm_req;
            ck_act  <= wm_req && !r_nock;
            desk_free <= wm_req;                         // wm_req ya implica el modo 2
            // modos 0 y 3: la ventana de pantalla completa (el V9968 entero, como el camino enganchado)
            win_x0  <= (mode_req == 2'd2) ? x0_s[11:0] : 12'sd0;
            win_y0  <= (mode_req == 2'd2) ? y0_s[10:0] : 11'sd0;
            win_scl <= (mode_req == 2'd2) ? {r_x2 | r_q75, r_half | r_q75} : 2'b00;
            win_sx0 <= (mode_req == 2'd2) ? sx0_c : 10'd0;
            win_sy0 <= (mode_req == 2'd2) ? sy0_c : 8'd0;
            x0_r <= x0_s; x1_r <= x0_s + w_c;
            y0_r <= y0_s; y1_r <= y0_s + h_c;
        end
    end

    wire signed [12:0] cx13 = {2'b00, cx};
    wire signed [12:0] cy13 = {3'b000, cy};
    wire in_window = (cx13 >= x0_r) && (cx13 < x1_r) && (cy13 >= y0_r) && (cy13 < y1_r);

    assign rgb = (mode_active == 2'd0) ? rgb68 :
                 (mode_active == 2'd1) ? rgb99 :
                 (mode_active == 2'd2 && wm_act) ? ((wm_ov == 2'd2) ? wm_rgb : in_window ? rgb68 :     // gestor: puntero, ventana
                                                    (wm_ov == 2'd1) ? wm_rgb : rgb99) :                  // opaca, marco, escritorio
                 // ventana sin gestor (tecla V): el hueco lo marca el color transparente del escritorio. Fuera de la imagen
                 // del V9990 ys99 tambien es 1, y la ventana llega hasta el borde derecho del MSX (x1 = 1276 en B1):
                 // sin in99 el juego asomaba a la derecha del escritorio (en placa, 29/10/2026)
                 (mode_active == 2'd2) ? ((in_window && ys99 && in99) ? rgb68 : rgb99) :
                                         (ys99 ? rgb68 : rgb99);
endmodule
