// ============================================================================
// v9991_wm.sv — El gestor de ventanas por hardware del V9991 (29/10/2026).
//
// Con la tecla B del menu el juego se queda con el Z80: no queda ningun codigo
// del MSXimus que lea el raton y mueva la ventana. Asi que lo hace el hardware,
// dentro del compositor, cuando R#55 lleva el bit WM (bit 1) en el modo 2:
//   * lee el raton USB (los mismos informes que el raton MSX del puerto 2, que
//     el juego sigue recibiendo) y lleva un puntero en pixeles de 720p;
//   * pinta la flecha del puntero (12 x 19 px, encima de todo);
//   * pinta el marco de la ventana del V9968: contorno negro, biselado, cuerpo
//     gris, barra de titulo azul marino de TT px con "MSX - V9968" (la fuente
//     del OSD a x2) y dos botones de adorno. La ventana es OPACA (sale el V9968
//     entero dentro, sin mirar el YS del V9990): el escritorio no necesita hueco;
//   * con el boton izquierdo pulsado sobre la barra de titulo, la ventana sigue
//     al puntero sin salir de la pantalla. La posicion se aplica, como todo en el
//     compositor, en el vblank (un cuadro de retraso). Un clic en el cuadradito cian de la barra (el
//     sonido de A en el perfil Dual; adorno en el estandar) NO empieza el arrastre (in_sq).
//   * (perfil Dual, 2/11/2026) mute_a: con A en silencio el cuadradito se pinta hueco y gris, como el de B.
// Al encenderse la ventana sale donde dicen WX/WY (init_x/init_y).
//   * (rama beta, 30/10/2026) el RELOJ: un panel arriba a la derecha con la hora (x4) y la fecha (x2) del RTC del
//     MSX (rtc.v, BCD), por encima del escritorio y por debajo de la ventana y del puntero. Sale con el gestor (teclas
//     B y V del menu) salvo que R#55 lleve el bit 0 (clk_on = 0). En la tecla V cabe en la franja negra de arriba del B5.
//
// Cruce de dominios: el raton suma sus deltas en clk_m (54 MHz); una vez por
// cuadro (cy = 721) el lado del pixel pide una foto con un toggle, el lado del
// raton la congela (deltas acumulados y boton) y contesta con otro toggle: la
// foto esta quieta mucho antes de que el lado del pixel la lea (2 FF).
//
// El dibujo se calcula un pixel ADELANTADO (para (cx+1, cy)) y se registra, asi
// el resultado sale alineado con (cx, cy) sin logica combinacional larga en el
// camino del pixel. Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9991_wm #(
    parameter integer BX = 4,       // borde lateral del marco (px)
    parameter integer TT = 24,      // alto del marco de arriba: contorno, biselado, gris, barra de 18 px, gris
    parameter integer BB = 4        // borde de abajo
) (
    // ---- raton (dominio clk_m) ----
    input  wire               clk_m,
    input  wire               m_rep,          // 1 ciclo por informe
    input  wire signed [7:0]  m_dx,           // + = derecha (USB)
    input  wire signed [7:0]  m_dy,           // + = abajo
    input  wire               m_btn,          // boton izquierdo, nivel
    // ---- pixel (74,25 MHz) ----
    input  wire               clk_pixel,
    input  wire [10:0]        cx,
    input  wire [9:0]         cy,
    input  wire               on,             // gestor activo (cambia en el vblank)
    input  wire               clk_on,         // el reloj (con on; cambia en el vblank)
`ifdef PERFIL_DUAL
    input  wire               a_focus,        // Dual: la ventana de A tiene el foco del teclado (barra de titulo azul; si no, apagada)
    input  wire               mute_a,         // Dual: A en silencio (ya en clk_pixel): el cuadradito cian de su barra, hueco y gris
    output wire               btn_o,          // Dual: el boton izquierdo tal como lo vio el ultimo cuadro (telemetria al ARM)
`endif
    input  wire [2:0]         reso,           // modo del V9990 del cuadro (4 = B5): donde va el reloj (b3)
    input  wire [38:0]        tod,            // RTC en BCD (clk_27m, cambia una vez por segundo): {anio desde 1980[38:31],
                                              // mes[30:26], dia[25:20], hora[19:14], minuto[13:7], segundo[6:0]}
    input  wire signed [12:0] init_x,         // posicion de los registros, al encender
    input  wire signed [12:0] init_y,
    input  wire signed [12:0] ww,             // tamano de la ventana (px)
    input  wire signed [12:0] wh,
    input  wire signed [12:0] x0,             // la ventana del cuadro que sale (latcheada por el compositor)
    input  wire signed [12:0] y0,
    input  wire signed [12:0] x1,
    input  wire signed [12:0] y1,
    output reg  signed [12:0] wm_x = 13'sd384,   // posicion pedida para el cuadro siguiente
    output reg  signed [12:0] wm_y = 13'sd201,
    output reg  [1:0]         ov = 2'd0,      // (cx, cy): 0 nada, 1 marco, 2 puntero
    output reg  [23:0]        ov_rgb = 24'd0,
    // diagnostico / bancos
    output reg  signed [12:0] px = 13'sd640,  // el puntero
    output reg  signed [12:0] py = 13'sd360,
    output reg                drag = 1'b0
);

    // "MSX - V9968" con la fuente del OSD (fpga/src/iosys/font.vh), 88 px x 8 lineas; bit 0 = pixel izquierdo (genwm.py)
    localparam integer TITLE_W = 88;
    wire [87:0] title_row [0:7];
    assign title_row[0] = 88'h1E1C1E1E33000000631E63;
    assign title_row[1] = 88'h3306333333000000633377;
    assign title_row[2] = 88'h330333333300000036077F;
    assign title_row[3] = 88'h1E1F3E3E33003F001C0E7F;
    assign title_row[4] = 88'h33333030330000001C386B;
    assign title_row[5] = 88'h333318181E000000363363;
    assign title_row[6] = 88'h1E1E0E0E0C000000631E63;
    assign title_row[7] = 88'h0000000000000000000000;
    // la flecha del puntero, 12 x 19 px: contorno negro (O) y relleno blanco (F); bit 0 = pixel izquierdo
    wire [11:0] ptr_o [0:18];
    wire [11:0] ptr_f [0:18];
    assign ptr_o[0] = 12'h001; assign ptr_f[0] = 12'h000;   // O
    assign ptr_o[1] = 12'h003; assign ptr_f[1] = 12'h000;   // OO
    assign ptr_o[2] = 12'h005; assign ptr_f[2] = 12'h002;   // OFO
    assign ptr_o[3] = 12'h009; assign ptr_f[3] = 12'h006;   // OFFO
    assign ptr_o[4] = 12'h011; assign ptr_f[4] = 12'h00E;   // OFFFO
    assign ptr_o[5] = 12'h021; assign ptr_f[5] = 12'h01E;   // OFFFFO
    assign ptr_o[6] = 12'h041; assign ptr_f[6] = 12'h03E;   // OFFFFFO
    assign ptr_o[7] = 12'h081; assign ptr_f[7] = 12'h07E;   // OFFFFFFO
    assign ptr_o[8] = 12'h101; assign ptr_f[8] = 12'h0FE;   // OFFFFFFFO
    assign ptr_o[9] = 12'h201; assign ptr_f[9] = 12'h1FE;   // OFFFFFFFFO
    assign ptr_o[10] = 12'h401; assign ptr_f[10] = 12'h3FE;   // OFFFFFFFFFO
    assign ptr_o[11] = 12'hF81; assign ptr_f[11] = 12'h07E;   // OFFFFFFOOOOO
    assign ptr_o[12] = 12'h091; assign ptr_f[12] = 12'h06E;   // OFFFOFFO
    assign ptr_o[13] = 12'h099; assign ptr_f[13] = 12'h066;   // OFFOOFFO
    assign ptr_o[14] = 12'h125; assign ptr_f[14] = 12'h0C2;   // OFO  OFFO
    assign ptr_o[15] = 12'h123; assign ptr_f[15] = 12'h0C0;   // OO   OFFO
    assign ptr_o[16] = 12'h241; assign ptr_f[16] = 12'h180;   // O     OFFO
    assign ptr_o[17] = 12'h240; assign ptr_f[17] = 12'h180;   //       OFFO
    assign ptr_o[18] = 12'h180; assign ptr_f[18] = 12'h000;   //        OO

    // ------------------------------------------------------------------ raton (clk_m)
    reg                req_p = 1'b0;                       // clk_pixel: pide una foto (toggle)
    reg  [2:0]         req_s = 3'b000;
    reg                ack_m = 1'b0;                       // clk_m: foto lista (toggle)
    reg  signed [12:0] acc_x = 13'sd0, acc_y = 13'sd0;     // deltas desde la ultima foto (<= 16 informes x 127 por cuadro)
    reg  signed [12:0] snap_x = 13'sd0, snap_y = 13'sd0;
    reg                snap_b = 1'b0, btn_m = 1'b0;
    wire signed [12:0] dx13 = {{5{m_dx[7]}}, m_dx};
    wire signed [12:0] dy13 = {{5{m_dy[7]}}, m_dy};
    wire               req_e = req_s[2] ^ req_s[1];
    always @(posedge clk_m) begin
        req_s <= {req_s[1:0], req_p};
        btn_m <= m_btn;
        if (req_e) begin
            snap_x <= acc_x + (m_rep ? dx13 : 13'sd0);
            snap_y <= acc_y + (m_rep ? dy13 : 13'sd0);
            snap_b <= btn_m;
            acc_x  <= 13'sd0;
            acc_y  <= 13'sd0;
            ack_m  <= ~ack_m;
        end else if (m_rep) begin
            acc_x <= acc_x + dx13;
            acc_y <= acc_y + dy13;
        end
    end

    // ------------------------------------------------------------------ puntero y arrastre (clk_pixel, una vez por cuadro)
    reg  [2:0]         ack_s = 3'b000;
    wire               ack_e = ack_s[2] ^ ack_s[1];
    reg                on_q = 1'b0, btn_q = 1'b0;
    reg                placed = 1'b0;                      // ya se coloco una vez
    reg  signed [12:0] ix_q = 13'sd0, iy_q = 13'sd0;        // WX/WY de esa vez
    reg  signed [12:0] offx = 13'sd0, offy = 13'sd0;

    function automatic signed [12:0] clamp(input signed [12:0] v, input signed [12:0] lo, input signed [12:0] hi);
        clamp = (v < lo) ? lo : (v > hi) ? ((hi < lo) ? lo : hi) : v;
    endfunction
`ifdef PERFIL_DUAL
    assign btn_o = btn_q;
`endif
    wire signed [12:0] npx = clamp(px + snap_x, 13'sd0, 13'sd1279);
    wire signed [12:0] npy = clamp(py + snap_y, 13'sd0, 13'sd719);
    // el cuadradito de la barra (in_btn2, mas abajo: rx de ow-BX-40 a ow-BX-25, ry de 5 a 17) en coordenadas del puntero y con 2 px de
    // margen por lado: la misma zona en la que el companion (dual.c, en_sa) da el clic del silencio de A. Ahi no se arrastra la ventana.
    wire signed [12:0] sq_dx   = npx - wm_x - ww;                 // la esquina derecha de la ventana = 0; el cuadradito, de -40 a -25
    wire signed [12:0] sq_dy   = npy - wm_y;                      // la barra es de -TT a -1; el cuadradito, de 5-TT a 17-TT
    wire               in_sq   = (sq_dx >= -13'sd42) && (sq_dx < -13'sd22) && (sq_dy >= 3 - TT) && (sq_dy < 20 - TT);
    wire               in_bar = (npx >= wm_x - BX) && (npx < wm_x + ww + BX) && (npy >= wm_y - TT) && (npy < wm_y) && !in_sq;
    // limites registrados (30/10/2026, Z1.3): ww/wh son cuasi-estaticos; sin el registro, la resta y el clamp colgaban
    // de la geometria del compositor en el mismo ciclo (el peor camino del V9991f)
    reg  signed [12:0] xhi = 13'sd0, yhi = 13'sd0;
    always @(posedge clk_pixel) begin
        xhi <= 13'sd1280 - BX - ww;
        yhi <= 13'sd720 - BB - wh;
    end

    always @(posedge clk_pixel) begin
        ack_s <= {ack_s[1:0], ack_m};
        if (cy == 10'd721 && cx == 11'd0) req_p <= ~req_p;
        on_q <= on;
        if (on && !on_q) begin                              // al encenderse: la ventana donde dicen los registros, si han cambiado
            // (o la primera vez); si no, donde se dejo arrastrada (Pausa y vuelta, 29/10/2026)
            if (!placed || init_x != ix_q || init_y != iy_q) begin wm_x <= init_x; wm_y <= init_y; end
            placed <= 1'b1; ix_q <= init_x; iy_q <= init_y;
            drag <= 1'b0; btn_q <= 1'b1;                    // un boton ya pulsado no empieza un arrastre
        end else if (ack_e) begin
            px <= npx; py <= npy; btn_q <= snap_b;
            if (!on) drag <= 1'b0;
            else if (!drag) begin
                if (snap_b && !btn_q && in_bar) begin drag <= 1'b1; offx <= npx - wm_x; offy <= npy - wm_y; end
            end else if (!snap_b) drag <= 1'b0;
            else begin
                wm_x <= clamp(npx - offx, BX, xhi);
                wm_y <= clamp(npy - offy, TT, yhi);
            end
        end
    end

    // ------------------------------------------------------------------ dibujo (un pixel adelantado)
    wire signed [12:0] nx = (cx == 11'd1649) ? 13'sd0 : {2'b00, cx} + 13'sd1;
    wire signed [12:0] ny = (cx == 11'd1649) ? ((cy == 10'd749) ? 13'sd0 : {3'b000, cy} + 13'sd1) : {3'b000, cy};
    // caja exterior del marco: [x0 - BX, x1 + BX) x [y0 - TT, y1 + BB)
    wire signed [12:0] rx = nx - (x0 - BX);
    wire signed [12:0] ry = ny - (y0 - TT);
    wire signed [12:0] ow = (x1 - x0) + 2 * BX;
    wire signed [12:0] oh = (y1 - y0) + TT + BB;
    wire in_box  = (rx >= 0) && (rx < ow) && (ry >= 0) && (ry < oh);
    wire in_win  = (nx >= x0) && (nx < x1) && (ny >= y0) && (ny < y1);
    wire outl    = (rx == 0) || (ry == 0) || (rx == ow - 1) || (ry == oh - 1);
    wire bev_d   = (rx == ow - 2) || (ry == oh - 2);
    wire bev_l   = (rx == 1) || (ry == 1);
    wire in_tbar = (ry >= 3) && (ry < TT - 3) && (rx >= BX) && (rx < ow - BX);
    // titulo a x2 desde 8 px dentro de la barra, 16 lineas desde la 4 del marco
    wire signed [12:0] tx = rx - (BX + 8);
    wire signed [12:0] ty = ry - 13'sd4;
    wire in_text = (tx >= 0) && (tx < 2 * TITLE_W) && (ty >= 0) && (ty < 16);
    wire [87:0] trow = title_row[ty[3:1]];
    wire t_on    = in_text && trow[tx[7:1]];
    wire in_btn1 = (ry >= 5) && (ry < 18) && (rx >= ow - BX - 20) && (rx < ow - BX - 4);    // rojo
    wire in_btn2 = (ry >= 5) && (ry < 18) && (rx >= ow - BX - 40) && (rx < ow - BX - 24);   // cian (el sonido de A)
    wire btn2_f  = (ry == 5) || (ry == 17) || (rx == ow - BX - 40) || (rx == ow - BX - 25);  // su marco de 1 px (mute_a: hueco y gris)
    // puntero
    wire signed [12:0] qx = nx - px;
    wire signed [12:0] qy = ny - py;
    wire in_ptr  = (qx >= 0) && (qx < 12) && (qy >= 0) && (qy < 19);
    wire [11:0] po = ptr_o[qy[4:0]];
    wire [11:0] pf = ptr_f[qy[4:0]];
    wire p_o     = in_ptr && po[qx[3:0]];
    wire p_f     = in_ptr && pf[qx[3:0]];

    // ------------------------------------------------------------------ el reloj
    // la hora cruza en una foto por cuadro (cy 719) y solo se acepta si es igual a la del cuadro anterior: los bits del
    // RTC cambian a la vez una vez por segundo y un 2FF por bit podria tomar una hora a medias
    reg  [38:0] tod_s0 = 39'd0, tod_s1 = 39'd0, tod_p = 39'd0, tod_q = 39'd0;
    always @(posedge clk_pixel) begin
        tod_s0 <= tod; tod_s1 <= tod_s0;
        if (cy == 10'd719 && cx == 11'd0) begin tod_p <= tod_s1; if (tod_s1 == tod_p) tod_q <= tod_s1; end
    end
    wire [7:0] t_yea = tod_q[38:31];
    wire [3:0] t_mo1 = {3'b000, tod_q[30]},  t_mo0 = tod_q[29:26];
    wire [3:0] t_da1 = {2'b00, tod_q[25:24]}, t_da0 = tod_q[23:20];
    wire [3:0] t_ho1 = {2'b00, tod_q[19:18]}, t_ho0 = tod_q[17:14];
    wire [3:0] t_mi1 = {1'b0, tod_q[13:11]},  t_mi0 = tod_q[10:7];
    wire [3:0] t_se1 = {1'b0, tod_q[6:4]},    t_se0 = tod_q[3:0];
    // el anio: el RTC cuenta desde 1980 (00..99 = 1980..2079)
    wire       y_19  = (t_yea < 8'h20);
    wire [3:0] t_y1  = y_19 ? t_yea[7:4] + 4'd8 : t_yea[7:4] - 4'd2;
    wire [3:0] t_y0  = t_yea[3:0];
    // el panel: 272 x 57 px en (992, 2); hora "HH:MM:SS" a x4 (8 x 32 px por caracter) desde (8, 3), fecha
    // "DD/MM/AAAA" a x2 (8 x 16) desde (56, 38)
    // b3 (30/10/2026): dentro de la barra de arriba del escritorio del companion (B7: el escritorio va de x 128 a 1152 y
    // empieza en y 42) o en la franja negra de encima del B5; plano, del color de la barra, con una linea de acento abajo
    localparam integer CK_W = 272, CK_H = 57;
    reg  signed [12:0] ck_x0 = 13'sd864, ck_y0 = 13'sd44;
    always @(posedge clk_pixel) begin ck_x0 <= (reso == 3'd4) ? 13'sd992 : 13'sd864; ck_y0 <= (reso == 3'd4) ? 13'sd2 : 13'sd44; end
    wire signed [12:0] kx = nx - ck_x0;
    wire signed [12:0] ky = ny - ck_y0;
    wire in_ck   = clk_on && (kx >= 0) && (kx < CK_W) && (ky >= 0) && (ky < CK_H);
    wire ck_out  = (ky == CK_H - 1) || (ky == CK_H - 2);                  // la linea de acento
    wire ck_bev  = 1'b0;
    wire signed [12:0] hx = kx - 13'sd8;
    wire signed [12:0] hy = ky - 13'sd3;
    wire in_hora = (hx >= 0) && (hx < 256) && (hy >= 0) && (hy < 32);
    wire signed [12:0] fx = kx - 13'sd56;
    wire signed [12:0] fy = ky - 13'sd38;
    wire in_fech = (fx >= 0) && (fx < 160) && (fy >= 0) && (fy < 16);
    reg  [3:0] ch_h, ch_f;
    always @(*) begin
        case (hx[7:5])
            3'd0: ch_h = t_ho1; 3'd1: ch_h = t_ho0; 3'd2: ch_h = 4'd10; 3'd3: ch_h = t_mi1;
            3'd4: ch_h = t_mi0; 3'd5: ch_h = 4'd10; 3'd6: ch_h = t_se1; default: ch_h = t_se0;
        endcase
        case (fx[7:4])
            4'd0: ch_f = t_da1; 4'd1: ch_f = t_da0; 4'd2: ch_f = 4'd11; 4'd3: ch_f = t_mo1; 4'd4: ch_f = t_mo0;
            4'd5: ch_f = 4'd11; 4'd6: ch_f = y_19 ? 4'd1 : 4'd2; 4'd7: ch_f = y_19 ? 4'd9 : 4'd0; 4'd8: ch_f = t_y1;
            default: ch_f = t_y0;
        endcase
    end
    // glifos del reloj: la fuente del OSD (fpga/src/iosys/font.vh), bit 0 = pixel izquierdo; 0-9, 10 ':', 11 '/'
    function automatic [7:0] glifo(input [3:0] c, input [2:0] r);
        case ({c, r})
            7'h00: glifo = 8'h3E; 7'h01: glifo = 8'h63; 7'h02: glifo = 8'h73; 7'h03: glifo = 8'h7B; 7'h04: glifo = 8'h6F; 7'h05: glifo = 8'h67; 7'h06: glifo = 8'h3E; 7'h07: glifo = 8'h00;
            7'h08: glifo = 8'h0C; 7'h09: glifo = 8'h0E; 7'h0A: glifo = 8'h0C; 7'h0B: glifo = 8'h0C; 7'h0C: glifo = 8'h0C; 7'h0D: glifo = 8'h0C; 7'h0E: glifo = 8'h3F; 7'h0F: glifo = 8'h00;
            7'h10: glifo = 8'h1E; 7'h11: glifo = 8'h33; 7'h12: glifo = 8'h30; 7'h13: glifo = 8'h1C; 7'h14: glifo = 8'h06; 7'h15: glifo = 8'h33; 7'h16: glifo = 8'h3F; 7'h17: glifo = 8'h00;
            7'h18: glifo = 8'h1E; 7'h19: glifo = 8'h33; 7'h1A: glifo = 8'h30; 7'h1B: glifo = 8'h1C; 7'h1C: glifo = 8'h30; 7'h1D: glifo = 8'h33; 7'h1E: glifo = 8'h1E; 7'h1F: glifo = 8'h00;
            7'h20: glifo = 8'h38; 7'h21: glifo = 8'h3C; 7'h22: glifo = 8'h36; 7'h23: glifo = 8'h33; 7'h24: glifo = 8'h7F; 7'h25: glifo = 8'h30; 7'h26: glifo = 8'h78; 7'h27: glifo = 8'h00;
            7'h28: glifo = 8'h3F; 7'h29: glifo = 8'h03; 7'h2A: glifo = 8'h1F; 7'h2B: glifo = 8'h30; 7'h2C: glifo = 8'h30; 7'h2D: glifo = 8'h33; 7'h2E: glifo = 8'h1E; 7'h2F: glifo = 8'h00;
            7'h30: glifo = 8'h1C; 7'h31: glifo = 8'h06; 7'h32: glifo = 8'h03; 7'h33: glifo = 8'h1F; 7'h34: glifo = 8'h33; 7'h35: glifo = 8'h33; 7'h36: glifo = 8'h1E; 7'h37: glifo = 8'h00;
            7'h38: glifo = 8'h3F; 7'h39: glifo = 8'h33; 7'h3A: glifo = 8'h30; 7'h3B: glifo = 8'h18; 7'h3C: glifo = 8'h0C; 7'h3D: glifo = 8'h0C; 7'h3E: glifo = 8'h0C; 7'h3F: glifo = 8'h00;
            7'h40: glifo = 8'h1E; 7'h41: glifo = 8'h33; 7'h42: glifo = 8'h33; 7'h43: glifo = 8'h1E; 7'h44: glifo = 8'h33; 7'h45: glifo = 8'h33; 7'h46: glifo = 8'h1E; 7'h47: glifo = 8'h00;
            7'h48: glifo = 8'h1E; 7'h49: glifo = 8'h33; 7'h4A: glifo = 8'h33; 7'h4B: glifo = 8'h3E; 7'h4C: glifo = 8'h30; 7'h4D: glifo = 8'h18; 7'h4E: glifo = 8'h0E; 7'h4F: glifo = 8'h00;
            7'h50: glifo = 8'h00; 7'h51: glifo = 8'h0C; 7'h52: glifo = 8'h0C; 7'h53: glifo = 8'h00; 7'h54: glifo = 8'h00; 7'h55: glifo = 8'h0C; 7'h56: glifo = 8'h0C; 7'h57: glifo = 8'h00;
            7'h58: glifo = 8'h60; 7'h59: glifo = 8'h30; 7'h5A: glifo = 8'h18; 7'h5B: glifo = 8'h0C; 7'h5C: glifo = 8'h06; 7'h5D: glifo = 8'h03; 7'h5E: glifo = 8'h01; 7'h5F: glifo = 8'h00;
            default: glifo = 8'h00;
        endcase
    endfunction
    wire [7:0] g_h = glifo(ch_h, hy[4:2]);
    wire [7:0] g_f = glifo(ch_f, fy[3:1]);
    wire ck_hora = in_hora && g_h[hx[4:2]];
    wire ck_fech = in_fech && g_f[fx[3:1]];

    // b3 (30/10/2026): los colores del escritorio del companion (v99desk.c): oscuro y plano, acento cian
    localparam [23:0] C_BLACK = 24'h000000, C_WHITE = 24'hF8F8F8, C_DARK = 24'h0A1428, C_GRAY = 24'h293A5A,
                      C_NAVY  = 24'h425284, C_TEXT  = 24'hEEF6FF, C_RED  = 24'hE0483C,
                      C_LIGHT = 24'h5A6E9C, C_EDGE  = 24'h050A14, C_BAR  = 24'h081020, C_DIM   = 24'h8C9CBD,
                      C_ACC   = 24'h19B5E6;
    always @(posedge clk_pixel) begin
        if (on && p_o)                 begin ov <= 2'd2; ov_rgb <= C_BLACK; end
        else if (on && p_f)            begin ov <= 2'd2; ov_rgb <= C_WHITE; end
        else if (on && in_box && !in_win) begin
            ov <= 2'd1;
            ov_rgb <= outl    ? C_EDGE  :
                      bev_d   ? C_DARK  :
                      bev_l   ? C_LIGHT :
                      in_btn1 ? C_RED   :
`ifdef PERFIL_DUAL
                      in_btn2 ? (!mute_a ? C_ACC : btn2_f ? C_DIM : a_focus ? C_NAVY : C_GRAY) :   // en silencio: marco gris, dentro el color de la barra
`else
                      in_btn2 ? C_ACC   :
`endif
                      t_on    ? C_TEXT  :
`ifdef PERFIL_DUAL
                      (in_tbar && a_focus) ? C_NAVY  : C_GRAY;     // sin el foco la barra se apaga (del color del cuerpo)
`else
                      in_tbar ? C_NAVY  : C_GRAY;
`endif
        end
        else if (on && in_ck) begin                 // el reloj: debajo del marco y de la ventana (el compositor la pone encima)
            ov <= 2'd1;
            ov_rgb <= ck_out  ? C_ACC   :
                      ck_hora ? C_TEXT  :
                      ck_fech ? C_DIM   : C_BAR;
        end
        else begin ov <= 2'd0; ov_rgb <= 24'd0; end
    end
endmodule
