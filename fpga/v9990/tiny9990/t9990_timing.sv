//
// t9990_timing.sv
//
// BSD 3-Clause License
// 
// Copyright (c) 2024, Shinobu Hashimoto
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// 
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
// 
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
// 
// 3. Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

`default_nettype none

/***************************************************************
 * メモリ接続先
 ***************************************************************/
package T9990_MEM_CONNECT;
    localparam [2:0] RAM_XX = 3'h0; // no connect
    localparam [2:0] RAM_VC = 3'h1; // VDP command / CPU
    localparam [2:0] RAM_SP = 3'h2; // sprite
    localparam [2:0] RAM_BP = 3'h3; // bitmap
    localparam [2:0] RAM_PA = 3'h4; // Pattern A
    localparam [2:0] RAM_PB = 3'h5; // Pattern B
    localparam [2:0] RAM_RF = 3'h6; // refresh
endpackage

/***************************************************************
 * メモリタイミング I/F
 ***************************************************************/
interface T9990_MEM_TIMING;
    logic [2:0] STATE;  // モジュールを指定
    logic       PREP;   // 各モジュールにアドレスを教えてもらうタイミング
    logic       EXEC;   // メモリのリード(ライト)開始タイミング

    modport TG ( output PREP, EXEC, STATE );
    modport RAM( input  PREP, EXEC, STATE );
endinterface

    localparam [2:0]    RAM_XX = T9990_MEM_CONNECT::RAM_XX;  // なし
    localparam [2:0]    RAM_VC = T9990_MEM_CONNECT::RAM_VC;  // VDP コマンド or CPU R/W
    localparam [2:0]    RAM_SP = T9990_MEM_CONNECT::RAM_SP;  // スプライト
    localparam [2:0]    RAM_BP = T9990_MEM_CONNECT::RAM_BP;  // ビットマップ
    localparam [2:0]    RAM_PA = T9990_MEM_CONNECT::RAM_PA;  // P1A/P2
    localparam [2:0]    RAM_PB = T9990_MEM_CONNECT::RAM_PB;  // P1B
    localparam [2:0]    RAM_RF = T9990_MEM_CONNECT::RAM_RF;  // リフレッシュ

/***************************************************************
 * タイミングジェネレータモジュール
 ***************************************************************/
module T9990_TIMING (
    input wire              RESET_n,
    input wire              CLK,
    input wire              CLK_MASTER_EN,
    input wire              DCLK_EN,
    input wire              TG_EN,

    T9990_REGISTER_IF.VDP   REG,
    T9990_STATUS_IF.TIM     STATUS,

    output reg              HD,
    output reg              VD,
    output reg              HS,
    output reg              VS,

    output reg              SPR_START,
    output reg [8:0]        SPR_Y,

    output reg              BG_START,
    output reg [10:0]       BG_X,       // 11 bits (B7: 1368 puntos por linea)
    output reg [9:0]        BG_Y,       // MSXimus Z 21/10/2026: 10 bits (PAL B0/B2/B4 entrelazado = 580 lineas)

    output reg              MUX_VDE,    // MUX Vアクティブ期間
    output reg              MUX_HDE,    // MUX Hアクティブ期間
    output reg              MUX_HDE_E,  // MSXimus Z 30/10/2026: MUX_HDE un punto antes (la ventana del PRI, ver abajo)

    // MSXimus Z 21/10/2026: reinicio del scroll vertical (ver el bloque VOFS mas abajo)
    output reg [8:0]        VOFS_A,     // linea de pantalla en la que cayo la ultima escritura de R#17 (0 al empezar el cuadro)
    output reg [8:0]        VOFS_B,     // idem R#21 (plano B de P1)
    output reg [4:0]        SCAY_HI,    // R#18[4:0] congelado durante el area visible
    output reg              SCBY_HI,    // R#22[0]   idem

    input wire              MEM_REQ,

    T9990_MEM_TIMING.TG     MEM
);
    //  HSCN    C25M    MCS     DCKM    width   total   sync    erase   border  border  erase
    //  0       X       0       0       256     342     25      50      14      14      8
    //  0       X       0       1       512     684     50      100     28      28      16
    //  0       X       1       1       384     456     34      62      0       0       10
    //  0       X       1       2       768     912     68      124     0       0       20
    //  1       0       X       X       640     848     64      128     0       0       80      (MSXimus Z 29/10/2026: B5, puntos de 21 MHz 1/1 como B7; 440 lineas)
    //  1       1       X       X       640     800     96      112     0       0       48
    //  0       X       0       2       1024    1368    100     200     56      56      32      (MSXimus Z 28/10/2026: B7)

    localparam  SHIFT_BUFFER_DELAY_LOW = 33;
    localparam  SHIFT_BUFFER_DELAY_HIGH = 65;
    // MSXimus Z 28/10/2026 (V9991 paso 3): era 5 y el contenido salia UN PUNTO ANTES que la ventana DA del selector
    // en todos los modos (B1: 13 puntos de borde a la izquierda y 15 a la derecha, B3: 27/29; el ultimo punto de borde
    // mostraba el punto 0 de la imagen y el ultimo de la ventana DA el backdrop). La cadena real es PRI 1 + PAL 3 +
    // selector 1 = 5, pero el DA (STATUS.HR) va un punto por detras de MUX_HDE + 5: con 4 el bitmap, los sprites y el
    // mux arrancan un punto mas tarde juntos y el punto 0 cae en el primero de la ventana. Medido con +LINEDUMP del
    // tb_v9990_chain en B1, B3 y B7 (antes: 72 + 13 x 4 = 124 en la HDMI; ahora 128, lo que suponia el compositor).
    localparam  COLOR_DECODE_DELAY = 4;    // MUX+PAL / CLR_DEC
    localparam  SPR_DELAY = 1;             // SPRITE DELAY

    localparam  H256_LEFT_ERASE   = 50;
    localparam  H256_LEFT_BORDER  = 14;
    localparam  H256_WIDTH        = 256;
    localparam  H256_RIGHT_BORDER = 14;
    localparam  H256_RIGHT_ERASE  = 8;
    localparam  H256_SYNC         = 25;
    localparam  H256_TOTAL        = (H256_LEFT_ERASE + H256_LEFT_BORDER + H256_WIDTH + H256_RIGHT_BORDER + H256_RIGHT_ERASE);
    localparam  H256_ACTIVE       = (H256_LEFT_ERASE + H256_LEFT_BORDER);
    localparam  H256_INACTIVE     = (H256_LEFT_ERASE + H256_LEFT_BORDER + H256_WIDTH);
    localparam  H256_DISP_ENA     = (H256_LEFT_ERASE);
    localparam  H256_DISP_DIS     = (H256_LEFT_ERASE + H256_LEFT_BORDER + H256_WIDTH + H256_RIGHT_BORDER);
    localparam  H256_BG_ACTIVE    = (H256_ACTIVE - SHIFT_BUFFER_DELAY_LOW - COLOR_DECODE_DELAY);
    localparam  H256_SPR_ACTIVE   = (H256_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H256_MUX_ACTIVE   = (H256_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H256_MUX_INACTIVE = (H256_INACTIVE - COLOR_DECODE_DELAY);

    localparam  H512_LEFT_ERASE   = 100;
    localparam  H512_LEFT_BORDER  = 28;
    localparam  H512_WIDTH        = 512;
    localparam  H512_RIGHT_BORDER = 28;
    localparam  H512_RIGHT_ERASE  = 16;
    localparam  H512_SYNC         = 50;
    localparam  H512_TOTAL        = (H512_LEFT_ERASE + H512_LEFT_BORDER + H512_WIDTH + H512_RIGHT_BORDER + H512_RIGHT_ERASE);
    localparam  H512_ACTIVE       = (H512_LEFT_ERASE + H512_LEFT_BORDER);
    localparam  H512_INACTIVE     = (H512_LEFT_ERASE + H512_LEFT_BORDER + H512_WIDTH);
    localparam  H512_DISP_ENA     = (H512_LEFT_ERASE);
    localparam  H512_DISP_DIS     = (H512_LEFT_ERASE + H512_LEFT_BORDER + H512_WIDTH + H512_RIGHT_BORDER);
    localparam  H512_BG_ACTIVE    = (H512_ACTIVE - SHIFT_BUFFER_DELAY_HIGH - COLOR_DECODE_DELAY);
    localparam  H512_SPR_ACTIVE   = (H512_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H512_MUX_ACTIVE   = (H512_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H512_MUX_INACTIVE = (H512_INACTIVE - COLOR_DECODE_DELAY);

`ifndef T9990_B2_INIT
`define T9990_B2_INIT  3      // tbl_init / BG_START antes de H384_BG_ACTIVE (B2): eran 4/3 y el punto 0 de la imagen caia
`define T9990_B2_START 2      // en el borrado (B2 no tiene borde): con 3/2, como B1/B3, salen los 384 (medido en la cadena, 28/10/2026)
`define T9990_B4_INIT  3      // B4 (768): eran 6/5 y la imagen salia 3 puntos antes (el 0, 1 y 2 en el borrado y tres
`define T9990_B4_START 2      // puntos de backdrop al final); con 5/4 dos puntos antes; con 3/2 exacta (cadena, 28/10/2026)
`endif
    // MSXimus Z 28/10/2026: B7, 1024 puntos a 21,48 MHz (DCKM 1/1 con el maestro de 21 MHz): la linea de B1
    // por 4 (1368 puntos, bordes de 56, sync 100). Mismo esquema de bloques de 32 puntos que 512/768 (DBL).
`ifndef T9990_B7_INIT
`define T9990_B7_INIT  3      // tbl_init / BG_START en puntos antes de H1024_BG_ACTIVE, como en 256/512: con 3/2 el punto 0
`define T9990_B7_START 2      // es el primero que pasa por el mux (medido con +LINEDUMP en la cadena; con 10/9 iba un punto tarde)
`endif
    localparam  H1024_LEFT_ERASE   = 200;
    localparam  H1024_LEFT_BORDER  = 56;
    localparam  H1024_WIDTH        = 1024;
    localparam  H1024_RIGHT_BORDER = 56;
    localparam  H1024_RIGHT_ERASE  = 32;
    localparam  H1024_SYNC         = 100;
    localparam  H1024_TOTAL        = (H1024_LEFT_ERASE + H1024_LEFT_BORDER + H1024_WIDTH + H1024_RIGHT_BORDER + H1024_RIGHT_ERASE);
    localparam  H1024_ACTIVE       = (H1024_LEFT_ERASE + H1024_LEFT_BORDER);
    localparam  H1024_INACTIVE     = (H1024_LEFT_ERASE + H1024_LEFT_BORDER + H1024_WIDTH);
    localparam  H1024_DISP_ENA     = (H1024_LEFT_ERASE);
    localparam  H1024_DISP_DIS     = (H1024_LEFT_ERASE + H1024_LEFT_BORDER + H1024_WIDTH + H1024_RIGHT_BORDER);
    localparam  H1024_BG_ACTIVE    = (H1024_ACTIVE - SHIFT_BUFFER_DELAY_HIGH - COLOR_DECODE_DELAY);
    localparam  H1024_SPR_ACTIVE   = (H1024_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H1024_MUX_ACTIVE   = (H1024_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H1024_MUX_INACTIVE = (H1024_INACTIVE - COLOR_DECODE_DELAY);

    localparam  H384_LEFT_ERASE   = 62;
    localparam  H384_LEFT_BORDER  = 0;
    localparam  H384_WIDTH        = 384;
    localparam  H384_RIGHT_BORDER = 0;
    localparam  H384_RIGHT_ERASE  = 10;
    localparam  H384_SYNC         = 34;
    localparam  H384_TOTAL        = (H384_LEFT_ERASE + H384_LEFT_BORDER + H384_WIDTH + H384_RIGHT_BORDER + H384_RIGHT_ERASE);
    localparam  H384_ACTIVE       = (H384_LEFT_ERASE + H384_LEFT_BORDER);
    localparam  H384_INACTIVE     = (H384_LEFT_ERASE + H384_LEFT_BORDER + H384_WIDTH);
    localparam  H384_DISP_ENA     = (H384_LEFT_ERASE);
    localparam  H384_DISP_DIS     = (H384_LEFT_ERASE + H384_LEFT_BORDER + H384_WIDTH + H384_RIGHT_BORDER);
    localparam  H384_BG_ACTIVE    = (H384_ACTIVE - SHIFT_BUFFER_DELAY_LOW - COLOR_DECODE_DELAY);
    localparam  H384_SPR_ACTIVE   = (H384_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H384_MUX_ACTIVE   = (H384_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H384_MUX_INACTIVE = (H384_INACTIVE - COLOR_DECODE_DELAY);

    localparam  H768_LEFT_ERASE   = 124;
    localparam  H768_LEFT_BORDER  = 0;
    localparam  H768_WIDTH        = 768;
    localparam  H768_RIGHT_BORDER = 0;
    localparam  H768_RIGHT_ERASE  = 20;
    localparam  H768_SYNC         = 68;
    localparam  H768_TOTAL        = (H768_LEFT_ERASE + H768_LEFT_BORDER + H768_WIDTH + H768_RIGHT_BORDER + H768_RIGHT_ERASE);
    localparam  H768_ACTIVE       = (H768_LEFT_ERASE + H768_LEFT_BORDER);
    localparam  H768_INACTIVE     = (H768_LEFT_ERASE + H768_LEFT_BORDER + H768_WIDTH);
    localparam  H768_DISP_ENA     = (H768_LEFT_ERASE);
    localparam  H768_DISP_DIS     = (H768_LEFT_ERASE + H768_LEFT_BORDER + H768_WIDTH + H768_RIGHT_BORDER);
    localparam  H768_BG_ACTIVE    = (H768_ACTIVE - SHIFT_BUFFER_DELAY_HIGH - COLOR_DECODE_DELAY);
    localparam  H768_SPR_ACTIVE   = (H768_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H768_MUX_ACTIVE   = (H768_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H768_MUX_INACTIVE = (H768_INACTIVE - COLOR_DECODE_DELAY);

    localparam  H640_LEFT_ERASE   = 144;
    localparam  H640_LEFT_BORDER  = 0;
    localparam  H640_WIDTH        = 640;
    localparam  H640_RIGHT_BORDER = 0;
    localparam  H640_RIGHT_ERASE  = 64;
    localparam  H640_SYNC         = 64;
    localparam  H640_TOTAL        = (H640_LEFT_ERASE + H640_LEFT_BORDER + H640_WIDTH + H640_RIGHT_BORDER + H640_RIGHT_ERASE);
    localparam  H640_ACTIVE       = (H640_LEFT_ERASE + H640_LEFT_BORDER);
    localparam  H640_INACTIVE     = (H640_LEFT_ERASE + H640_LEFT_BORDER + H640_WIDTH);
    localparam  H640_DISP_ENA     = (H640_LEFT_ERASE);
    localparam  H640_DISP_DIS     = (H640_LEFT_ERASE + H640_LEFT_BORDER + H640_WIDTH + H640_RIGHT_BORDER);
    localparam  H640_BG_ACTIVE    = (H640_ACTIVE - SHIFT_BUFFER_DELAY_HIGH - COLOR_DECODE_DELAY);
    localparam  H640_SPR_ACTIVE   = (H640_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H640_MUX_ACTIVE   = (H640_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H640_MUX_INACTIVE = (H640_INACTIVE - COLOR_DECODE_DELAY);

    localparam  H648_LEFT_ERASE   = 144;
    localparam  H648_LEFT_BORDER  = 0;
    localparam  H648_WIDTH        = 640;
    localparam  H648_RIGHT_BORDER = 0;
    localparam  H648_RIGHT_ERASE  = 16;
    localparam  H648_SYNC         = 96;
    localparam  H648_TOTAL        = (H648_LEFT_ERASE + H648_LEFT_BORDER + H648_WIDTH + H648_RIGHT_BORDER + H648_RIGHT_ERASE);
    localparam  H648_ACTIVE       = (H648_LEFT_ERASE + H648_LEFT_BORDER);
    localparam  H648_INACTIVE     = (H648_LEFT_ERASE + H648_LEFT_BORDER + H648_WIDTH);
    localparam  H648_DISP_ENA     = (H648_LEFT_ERASE);
    localparam  H648_DISP_DIS     = (H648_LEFT_ERASE + H648_LEFT_BORDER + H648_WIDTH + H648_RIGHT_BORDER);
    localparam  H648_BG_ACTIVE    = (H648_ACTIVE - SHIFT_BUFFER_DELAY_HIGH - COLOR_DECODE_DELAY);
    localparam  H648_SPR_ACTIVE   = (H648_ACTIVE - COLOR_DECODE_DELAY - SPR_DELAY);
    localparam  H648_MUX_ACTIVE   = (H648_ACTIVE - COLOR_DECODE_DELAY);
    localparam  H648_MUX_INACTIVE = (H648_INACTIVE - COLOR_DECODE_DELAY);

    //  HSCN    C25M    MCS             height  total   sync    erase   border  border  erase
    //  0       X       0               212     262     3       18      14      14      4
    //  0       X       1               240     262     3       18      0       0       4
    //  1       0       X               400     440     8       33      0       0       7       (B5: 25,3 kHz, 57,6 Hz)
    //  1       1       X               480     525     2       35      0       0       10

    localparam  V212_TOP_ERASE     = 18;
    localparam  V212_TOP_BORDER    = 14;
    localparam  V212_HEIGHT        = 212;
    localparam  V212_BOTTOM_BORDER = 14;
    localparam  V212_BOTTOM_ERASE  = 4;
    localparam  V212_SYNC          = 3;
    localparam  V212_TOTAL         = (V212_TOP_ERASE + V212_TOP_BORDER + V212_HEIGHT + V212_BOTTOM_BORDER + V212_BOTTOM_ERASE);
    localparam  V212_ACTIVE        = (V212_TOP_ERASE + V212_TOP_BORDER);
    localparam  V212_INACTIVE      = (V212_TOP_ERASE + V212_TOP_BORDER + V212_HEIGHT);
    localparam  V212_DISP_ENA      = (V212_TOP_ERASE);
    localparam  V212_DISP_DIS      = (V212_TOP_ERASE + V212_TOP_BORDER + V212_HEIGHT + V212_BOTTOM_BORDER);
    localparam  V212_BG_ACTIVE     = (V212_ACTIVE);
    localparam  V212_SPR_ACTIVE    = (V212_ACTIVE - 1);         // -1 ラインからアトリビュート収集を開始
    localparam  V212_SPR_INACTIVE  = (V212_INACTIVE - 1);
    localparam  V212_DISP_LI_START = (V212_ACTIVE); 

    localparam  V240_TOP_ERASE     = 18;
    localparam  V240_TOP_BORDER    = 0;
    localparam  V240_HEIGHT        = 240;
    localparam  V240_BOTTOM_BORDER = 0;
    localparam  V240_BOTTOM_ERASE  = 4;
    localparam  V240_SYNC          = 3;
    localparam  V240_TOTAL         = (V240_TOP_ERASE + V240_TOP_BORDER + V240_HEIGHT + V240_BOTTOM_BORDER + V240_BOTTOM_ERASE);
    localparam  V240_ACTIVE        = (V240_TOP_ERASE + V240_TOP_BORDER);
    localparam  V240_INACTIVE      = (V240_TOP_ERASE + V240_TOP_BORDER + V240_HEIGHT);
    localparam  V240_DISP_ENA      = (V240_TOP_ERASE);
    localparam  V240_DISP_DIS      = (V240_TOP_ERASE + V240_TOP_BORDER + V240_HEIGHT + V240_BOTTOM_BORDER);
    localparam  V240_BG_ACTIVE     = (V240_ACTIVE);
    localparam  V240_SPR_ACTIVE    = (V240_ACTIVE - 1);
    localparam  V240_SPR_INACTIVE  = (V240_INACTIVE - 1);
    localparam  V240_DISP_LI_START = (V240_ACTIVE); 

    // MSXimus Z 21/10/2026: PAL (R#7 bit 3), 313 lineas por cuadro (50,2 Hz con la misma linea que en
    // NTSC), tablas de openMSX (V9990DisplayTiming.hh: displayPAL_MCLK 15/41/212/37 y displayPAL_XTAL
    // 15/0/290/0, con la sincronia de 3 lineas delante como en las de arriba). En HSCN=1 no cuenta.
    //  HSCN    C25M    MCS     PAL     height  total   sync    erase   border  border  erase
    //  0       X       0       1       212     313     3       18      41      37      5
    //  0       X       1       1       290     313     3       18      0       0       5
    //  El DE (VD) solo abre 240 lineas como en NTSC, porque el puente HDMI guarda 240 por cuadro:
    //  en 212 son 14 + 212 + 14 (el resto del borde, 27 arriba y 23 abajo, no sale); en 290 las 240
    //  centrales (25 arriba y 25 abajo no salen). STATUS.VR, VI, BG_Y, disp_line y el reinicio del
    //  scroll siguen al area visible entera.
    localparam  V212P_TOP_ERASE     = 18;
    localparam  V212P_TOP_BORDER    = 41;
    localparam  V212P_HEIGHT        = 212;
    localparam  V212P_BOTTOM_BORDER = 37;
    localparam  V212P_BOTTOM_ERASE  = 5;
    localparam  V212P_SYNC          = 3;
    localparam  V212P_DE_BORDER     = 14;   // borde que sale por el DE (el de NTSC)
    localparam  V212P_TOTAL         = (V212P_TOP_ERASE + V212P_TOP_BORDER + V212P_HEIGHT + V212P_BOTTOM_BORDER + V212P_BOTTOM_ERASE);
    localparam  V212P_ACTIVE        = (V212P_TOP_ERASE + V212P_TOP_BORDER);
    localparam  V212P_INACTIVE      = (V212P_TOP_ERASE + V212P_TOP_BORDER + V212P_HEIGHT);
    localparam  V212P_DISP_ENA      = (V212P_ACTIVE - V212P_DE_BORDER);
    localparam  V212P_DISP_DIS      = (V212P_INACTIVE + V212P_DE_BORDER);
    localparam  V212P_BG_ACTIVE     = (V212P_ACTIVE);
    localparam  V212P_SPR_ACTIVE    = (V212P_ACTIVE - 1);
    localparam  V212P_SPR_INACTIVE  = (V212P_INACTIVE - 1);
    localparam  V212P_DISP_LI_START = (V212P_ACTIVE);

    localparam  V290P_TOP_ERASE     = 18;
    localparam  V290P_TOP_BORDER    = 0;
    localparam  V290P_HEIGHT        = 290;
    localparam  V290P_BOTTOM_BORDER = 0;
    localparam  V290P_BOTTOM_ERASE  = 5;
    localparam  V290P_SYNC          = 3;
    localparam  V290P_DE_SKIP       = 25;   // lineas visibles de arriba que no salen por el DE
    localparam  V290P_DE_LINES      = 240;
    localparam  V290P_TOTAL         = (V290P_TOP_ERASE + V290P_TOP_BORDER + V290P_HEIGHT + V290P_BOTTOM_BORDER + V290P_BOTTOM_ERASE);
    localparam  V290P_ACTIVE        = (V290P_TOP_ERASE + V290P_TOP_BORDER);
    localparam  V290P_INACTIVE      = (V290P_TOP_ERASE + V290P_TOP_BORDER + V290P_HEIGHT);
    localparam  V290P_DISP_ENA      = (V290P_ACTIVE + V290P_DE_SKIP);
    localparam  V290P_DISP_DIS      = (V290P_ACTIVE + V290P_DE_SKIP + V290P_DE_LINES);
    localparam  V290P_BG_ACTIVE     = (V290P_ACTIVE);
    localparam  V290P_SPR_ACTIVE    = (V290P_ACTIVE - 1);
    localparam  V290P_SPR_INACTIVE  = (V290P_INACTIVE - 1);
    localparam  V290P_DISP_LI_START = (V290P_ACTIVE);

    localparam  V400_TOP_ERASE     = 33;
    localparam  V400_TOP_BORDER    = 0;
    localparam  V400_HEIGHT        = 400;
    localparam  V400_BOTTOM_BORDER = 0;
    localparam  V400_BOTTOM_ERASE  = 7;
    localparam  V400_SYNC          = 8;
    localparam  V400_TOTAL         = (V400_TOP_ERASE + V400_TOP_BORDER + V400_HEIGHT + V400_BOTTOM_BORDER + V400_BOTTOM_ERASE);
    localparam  V400_ACTIVE        = (V400_TOP_ERASE + V400_TOP_BORDER);
    localparam  V400_INACTIVE      = (V400_TOP_ERASE + V400_TOP_BORDER + V400_HEIGHT);
    localparam  V400_DISP_ENA      = (V400_TOP_ERASE);
    localparam  V400_DISP_DIS      = (V400_TOP_ERASE + V400_TOP_BORDER + V400_HEIGHT + V400_BOTTOM_BORDER);
    localparam  V400_BG_ACTIVE     = (V400_ACTIVE);
    localparam  V400_SPR_ACTIVE    = (V400_ACTIVE - 1);
    localparam  V400_SPR_INACTIVE  = (V400_INACTIVE - 1);
    localparam  V400_DISP_LI_START = (V400_ACTIVE); 

    localparam  V480_TOP_ERASE     = 35;
    localparam  V480_TOP_BORDER    = 0;
    localparam  V480_HEIGHT        = 480;
    localparam  V480_BOTTOM_BORDER = 0;
    localparam  V480_BOTTOM_ERASE  = 10;
    localparam  V480_SYNC          = 2;
    localparam  V480_TOTAL         = (V480_TOP_ERASE + V480_TOP_BORDER + V480_HEIGHT + V480_BOTTOM_BORDER + V480_BOTTOM_ERASE);
    localparam  V480_ACTIVE        = (V480_TOP_ERASE + V480_TOP_BORDER);
    localparam  V480_INACTIVE      = (V480_TOP_ERASE + V480_TOP_BORDER + V480_HEIGHT);
    localparam  V480_DISP_ENA      = (V480_TOP_ERASE);
    localparam  V480_DISP_DIS      = (V480_TOP_ERASE + V480_TOP_BORDER + V480_HEIGHT + V480_BOTTOM_BORDER);
    localparam  V480_BG_ACTIVE     = (V480_ACTIVE);
    localparam  V480_SPR_ACTIVE    = (V480_ACTIVE - 1);
    localparam  V480_SPR_INACTIVE  = (V480_INACTIVE - 1);
    localparam  V480_DISP_LI_START = (V480_ACTIVE); 

    // MSXimus Z 29/10/2026 (B5): con HSCN el punto es el maestro de 21 MHz (1/1) diga lo que diga DCKM o MCS, y las
    // ranuras de VRAM son las de 1024 puntos (una cada 4 puntos): 640 + 32 = 168 palabras a 8 bpp en una linea de 212 ranuras
    wire mcs21_eff = REG.HSCN || (REG.MCS == T9990_REG::MCS_21MHZ);

    wire [10:0] H_RESET         = REG.HSCN ? (REG.C25M ? (H648_TOTAL         - 2'd2) : (H640_TOTAL         - 2'd2)) : REG.MCS ? (REG.DCKM[1] ? (H768_TOTAL         - 2'd2) : (H384_TOTAL         - 2'd2)) : (REG.DCKM[1] ? (H1024_TOTAL - 2'd2) : REG.DCKM[0] ? (H512_TOTAL - 2'd2) : (H256_TOTAL - 2'd2));
    wire [10:0] H_HR_ACTIVE     = REG.HSCN ? (REG.C25M ? (H648_ACTIVE        - 1'd1) : (H640_ACTIVE        - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_ACTIVE        - 1'd1) : (H384_ACTIVE        - 1'd1)) : (REG.DCKM[1] ? (H1024_ACTIVE - 1'd1) : REG.DCKM[0] ? (H512_ACTIVE - 1'd1) : (H256_ACTIVE - 1'd1));
    wire [10:0] H_HR_INACTIVE   = REG.HSCN ? (REG.C25M ? (H648_INACTIVE      - 1'd1) : (H640_INACTIVE      - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_INACTIVE      - 1'd1) : (H384_INACTIVE      - 1'd1)) : (REG.DCKM[1] ? (H1024_INACTIVE - 1'd1) : REG.DCKM[0] ? (H512_INACTIVE - 1'd1) : (H256_INACTIVE - 1'd1));
    wire [10:0] H_MUX_ACTIVE    = REG.HSCN ? (REG.C25M ? (H648_MUX_ACTIVE    - 1'd1) : (H640_MUX_ACTIVE    - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_MUX_ACTIVE    - 1'd1) : (H384_MUX_ACTIVE    - 1'd1)) : (REG.DCKM[1] ? (H1024_MUX_ACTIVE - 1'd1) : REG.DCKM[0] ? (H512_MUX_ACTIVE - 1'd1) : (H256_MUX_ACTIVE - 1'd1));
    wire [10:0] H_MUX_INACTIVE  = REG.HSCN ? (REG.C25M ? (H648_MUX_INACTIVE  - 1'd1) : (H640_MUX_INACTIVE  - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_MUX_INACTIVE  - 1'd1) : (H384_MUX_INACTIVE  - 1'd1)) : (REG.DCKM[1] ? (H1024_MUX_INACTIVE - 1'd1) : REG.DCKM[0] ? (H512_MUX_INACTIVE - 1'd1) : (H256_MUX_INACTIVE - 1'd1));
    wire [10:0] H_DISP_ENA      = REG.HSCN ? (REG.C25M ? (H648_DISP_ENA      - 1'd1) : (H640_DISP_ENA      - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_DISP_ENA      - 1'd1) : (H384_DISP_ENA      - 1'd1)) : (REG.DCKM[1] ? (H1024_DISP_ENA - 1'd1) : REG.DCKM[0] ? (H512_DISP_ENA - 1'd1) : (H256_DISP_ENA - 1'd1));
    wire [10:0] H_DISP_DIS      = REG.HSCN ? (REG.C25M ? (H648_DISP_DIS      - 1'd1) : (H640_DISP_DIS      - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_DISP_DIS      - 1'd1) : (H384_DISP_DIS      - 1'd1)) : (REG.DCKM[1] ? (H1024_DISP_DIS - 1'd1) : REG.DCKM[0] ? (H512_DISP_DIS - 1'd1) : (H256_DISP_DIS - 1'd1));
    wire [10:0] H_SYNC_PERIOD   = REG.HSCN ? (REG.C25M ? (H648_SYNC          - 1'd1) : (H640_SYNC          - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_SYNC          - 1'd1) : (H384_SYNC          - 1'd1)) : (REG.DCKM[1] ? (H1024_SYNC - 1'd1) : REG.DCKM[0] ? (H512_SYNC - 1'd1) : (H256_SYNC - 1'd1));    // HSYNC 期間(DCLK タイミング用)

    // MSXimus Z 21/10/2026: PAL tomado al empezar el cuadro (v_rst) y al arrancar el TG, como el
    // palTiming de openMSX (frameStart): asi V_TOTAL no cambia a mitad de cuadro.
    logic       pal_fs;

    wire [9:0]  V_TOTAL         = REG.HSCN ? (REG.C25M ? (V480_TOTAL         - 1'd1) : (V400_TOTAL         - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_TOTAL        - 1'd1) : (V240_TOTAL         - 1'd1)) : (pal_fs ? (V212P_TOTAL        - 1'd1) : (V212_TOTAL         - 1'd1)));   // 縦総ライン数(v_incタイミング用)
    wire [9:0]  V_SYNC_PERIOD   = REG.HSCN ? (REG.C25M ? (V480_SYNC          - 1'd1) : (V400_SYNC          - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_SYNC         - 1'd1) : (V240_SYNC          - 1'd1)) : (pal_fs ? (V212P_SYNC         - 1'd1) : (V212_SYNC          - 1'd1)));   // VSYNC inactive ライン(v_incタイミング用)
    wire [9:0]  V_VR_ACTIVE     = REG.HSCN ? (REG.C25M ? (V480_ACTIVE        - 1'd1) : (V400_ACTIVE        - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_ACTIVE       - 1'd1) : (V240_ACTIVE        - 1'd1)) : (pal_fs ? (V212P_ACTIVE       - 1'd1) : (V212_ACTIVE        - 1'd1)));
    wire [9:0]  V_VR_INACTIVE   = REG.HSCN ? (REG.C25M ? (V480_INACTIVE      - 1'd1) : (V400_INACTIVE      - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_INACTIVE     - 1'd1) : (V240_INACTIVE      - 1'd1)) : (pal_fs ? (V212P_INACTIVE     - 1'd1) : (V212_INACTIVE      - 1'd1)));
    wire [9:0]  V_MUX_ACTIVE    = REG.HSCN ? (REG.C25M ? (V480_ACTIVE        - 1'd1) : (V400_ACTIVE        - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_ACTIVE       - 1'd1) : (V240_ACTIVE        - 1'd1)) : (pal_fs ? (V212P_ACTIVE       - 1'd1) : (V212_ACTIVE        - 1'd1)));
    wire [9:0]  V_MUX_INACTIVE  = REG.HSCN ? (REG.C25M ? (V480_INACTIVE      - 1'd1) : (V400_INACTIVE      - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_INACTIVE     - 1'd1) : (V240_INACTIVE      - 1'd1)) : (pal_fs ? (V212P_INACTIVE     - 1'd1) : (V212_INACTIVE      - 1'd1)));
    wire [9:0]  V_DISP_ENA      = REG.HSCN ? (REG.C25M ? (V480_DISP_ENA      - 1'd1) : (V400_DISP_ENA      - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_DISP_ENA     - 1'd1) : (V240_DISP_ENA      - 1'd1)) : (pal_fs ? (V212P_DISP_ENA     - 1'd1) : (V212_DISP_ENA      - 1'd1)));   // VD active(v_incタイミング用)
    wire [9:0]  V_DISP_DIS      = REG.HSCN ? (REG.C25M ? (V480_DISP_DIS      - 1'd1) : (V400_DISP_DIS      - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_DISP_DIS     - 1'd1) : (V240_DISP_DIS      - 1'd1)) : (pal_fs ? (V212P_DISP_DIS     - 1'd1) : (V212_DISP_DIS      - 1'd1)));   // VD inactive ライン(v_incタイミング用)
    wire [9:0]  V_DISP_LI_START = REG.HSCN ? (REG.C25M ? (V480_DISP_LI_START - 1'd1) : (V400_DISP_LI_START - 1'd1)) : (REG.MCS ? (pal_fs ? (V290P_DISP_LI_START - 1'd1) : (V240_DISP_LI_START - 1'd1)) : (pal_fs ? (V212P_DISP_LI_START - 1'd1) : (V212_DISP_LI_START - 1'd1)));   // ILカウンタ開始ライン(v_inc タイミング用)

    wire [10:0] H_BG_INIT       = REG.HSCN ? (REG.C25M ? (H648_BG_ACTIVE     - 2'd3) : (H640_BG_ACTIVE     - 2'd3)) : REG.MCS ? (REG.DCKM[1] ? (H768_BG_ACTIVE     - `T9990_B4_INIT) : (H384_BG_ACTIVE     - `T9990_B2_INIT)) : (REG.DCKM[1] ? (H1024_BG_ACTIVE - `T9990_B7_INIT) : REG.DCKM[0] ? (H512_BG_ACTIVE - 2'd3) : (H256_BG_ACTIVE - 2'd3));
    wire [10:0] H_BG_START      = REG.HSCN ? (REG.C25M ? (H648_BG_ACTIVE     - 2'd2) : (H640_BG_ACTIVE     - 2'd2)) : REG.MCS ? (REG.DCKM[1] ? (H768_BG_ACTIVE     - `T9990_B4_START) : (H384_BG_ACTIVE     - `T9990_B2_START)) : (REG.DCKM[1] ? (H1024_BG_ACTIVE - `T9990_B7_START) : REG.DCKM[0] ? (H512_BG_ACTIVE - 2'd2) : (H256_BG_ACTIVE - 2'd2));
    wire [10:0] H_BG_ACTIVE     = REG.HSCN ? (REG.C25M ? (H648_BG_ACTIVE     - 1'd1) : (H640_BG_ACTIVE     - 1'd1)) : REG.MCS ? (REG.DCKM[1] ? (H768_BG_ACTIVE     - 1'd1) : (H384_BG_ACTIVE     - 1'd1)) : (REG.DCKM[1] ? (H1024_BG_ACTIVE - 1'd1) : REG.DCKM[0] ? (H512_BG_ACTIVE - 1'd1) : (H256_BG_ACTIVE - 1'd1));
    wire [10:0] H_SPR_OUT_START = REG.HSCN ? (REG.C25M ? (H648_SPR_ACTIVE    - 2'd2) : (H640_SPR_ACTIVE    - 2'd2)) : REG.MCS ? (REG.DCKM[1] ? (H768_SPR_ACTIVE    - 2'd2) : (H384_SPR_ACTIVE    - 2'd2)) : (REG.DCKM[1] ? (H1024_SPR_ACTIVE - 2'd2) : REG.DCKM[0] ? (H512_SPR_ACTIVE - 2'd2) : (H256_SPR_ACTIVE - 2'd2));

    wire [9:0]  V_BG_ACTIVE     = REG.HSCN ? (REG.C25M ? (V480_BG_ACTIVE           ) : (V400_BG_ACTIVE           )) : (REG.MCS ? (pal_fs ? (V290P_BG_ACTIVE          ) : (V240_BG_ACTIVE           )) : (pal_fs ? (V212P_BG_ACTIVE          ) : (V212_BG_ACTIVE           )));   // BG 処理開始ライン
    wire [9:0]  V_SPR_ACTIVE    = REG.HSCN ? (REG.C25M ? (V480_SPR_ACTIVE          ) : (V400_SPR_ACTIVE          )) : (REG.MCS ? (pal_fs ? (V290P_SPR_ACTIVE         ) : (V240_SPR_ACTIVE          )) : (pal_fs ? (V212P_SPR_ACTIVE         ) : (V212_SPR_ACTIVE          )));   // スプライト処理開始ライン
    wire [9:0]  V_SPR_INACTIVE  = REG.HSCN ? (REG.C25M ? (V480_SPR_INACTIVE        ) : (V400_SPR_INACTIVE        )) : (REG.MCS ? (pal_fs ? (V290P_SPR_INACTIVE       ) : (V240_SPR_INACTIVE        )) : (pal_fs ? (V212P_SPR_INACTIVE       ) : (V212_SPR_INACTIVE        )));   // スプライト処理終了ライン

    /***************************************************************
     * h_cnt(HSYNCからのカウント)
     ***************************************************************/
    logic h_rst;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)     h_rst <= 0;
        else if(!TG_EN)  h_rst <= 0;
        else if(DCLK_EN) h_rst <= (h_cnt == H_RESET);
    end

    logic [10:0] h_cnt;    // MSXimus Z 28/10/2026: 11 bits por B7 (H1024_TOTAL = 1368)
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)              h_cnt <= 0;
        else if(!TG_EN)           h_cnt <= 0;
        else if(DCLK_EN && h_rst) h_cnt <= 0;
        else if(DCLK_EN         ) h_cnt <= h_cnt + 1'd1;
    end

    /***************************************************************
     * v_cnt(VSYNCからのカウント)
     ***************************************************************/
    wire v_inc = h_rst;

    logic v_rst;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)     v_rst <= 0;
        else if(!TG_EN)  v_rst <= 0;
        else if(DCLK_EN) v_rst <= (h_cnt == H_RESET) && (v_cnt == V_TOTAL);
    end

    logic [8:0] v_cnt;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)              v_cnt <= 0;
        else if(!TG_EN)           v_cnt <= 0;
        else if(DCLK_EN && v_rst) v_cnt <= 0;
        else if(DCLK_EN && v_inc) v_cnt <= v_cnt + 1'd1;
    end

    // MSXimus Z 21/10/2026: PAL del cuadro (ver V_TOTAL); cambia en el mismo flanco en que v_cnt vuelve a 0
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)              pal_fs <= 0;
        else if(!TG_EN)           pal_fs <= REG.PALM;
        else if(DCLK_EN && v_rst) pal_fs <= REG.PALM;
    end

    /***************************************************************
     * SPR_START
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                 SPR_START <= 0;
        else if(DCLK_EN && h_cnt == H_SPR_OUT_START) SPR_START <= 1;
        else                                         SPR_START <= 0;
    end

    /***************************************************************
     * SPR_Y
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                             SPR_Y <= 0;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE) SPR_Y <= (v_cnt == V_SPR_ACTIVE) ? 9'd0 : (SPR_Y + 1'd1);
    end

    /***************************************************************
     * spr_v_ena
     ***************************************************************/
    logic spr_v_ena;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                                        spr_v_ena <= 0;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE && v_cnt == V_SPR_ACTIVE)   spr_v_ena <= 1;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE && v_cnt == V_SPR_INACTIVE) spr_v_ena <= 0;
    end

    /***************************************************************
     * BG_START
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                            BG_START <= 0;
        else if(DCLK_EN && h_cnt == H_BG_START) BG_START <= 1;
        else                                    BG_START <= 0;
    end

    /***************************************************************
     * BG_X
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                             BG_X <= 0;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE) BG_X <= 0;
        else if(DCLK_EN)                         BG_X <= BG_X + 1'd1;
    end

    /***************************************************************
     * y_cnt
     ***************************************************************/
    logic [8:0] bg_y_cnt;
    wire [8:0] bg_y_cnt_new = bg_y_cnt + 1'd1;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                             bg_y_cnt <= 0;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE) bg_y_cnt <= (v_cnt == V_BG_ACTIVE) ? 0 : bg_y_cnt_new;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                                     BG_Y <= 0;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE && v_cnt == V_BG_ACTIVE) BG_Y <= (REG.ILM && REG.EO && !REG.HSCN) ? {9'd0, STATUS.EO}              : 0;
        else if(DCLK_EN && h_cnt == H_BG_ACTIVE)                         BG_Y <= (REG.ILM && REG.EO && !REG.HSCN) ? {bg_y_cnt_new[8:0], STATUS.EO} : {1'b0, bg_y_cnt_new};
    end

    /***************************************************************
     * STATUS.EO
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                 STATUS.EO <= 0;
        else if(DCLK_EN && !REG.ILM) STATUS.EO <= 0;
        else if(DCLK_EN && v_rst)    STATUS.EO <= !STATUS.EO;
    end

    /***************************************************************
     * HSYNC
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                               HS <= 0;
        else if(DCLK_EN && h_rst)                  HS <= 1;
        else if(DCLK_EN && h_cnt == H_SYNC_PERIOD) HS <= 0;
    end

    /***************************************************************
     * VSYNC
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                        VS <= 0;
        else if(DCLK_EN && v_rst)                           VS <= 1;
        else if(DCLK_EN && v_inc && v_cnt == V_SYNC_PERIOD) VS <= 0;
    end

    /***************************************************************
     * STATUS.HR(ボーダーを含まない表示期間)
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                               STATUS.HR <= 1;
        else if(DCLK_EN && h_cnt == H_HR_ACTIVE)   STATUS.HR <= 0;
        else if(DCLK_EN && h_cnt == H_HR_INACTIVE) STATUS.HR <= 1;
    end

    /***************************************************************
     * MUX HDE
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                MUX_HDE <= 0;
        else if(DCLK_EN && h_cnt == H_MUX_ACTIVE)   MUX_HDE <= 1;
        else if(DCLK_EN && h_cnt == H_MUX_INACTIVE) MUX_HDE <= 0;
    end
    // MSXimus Z 30/10/2026 (fusion de zynq): el PRI de T9990_PRIORITY (el bit 15 de la paleta: el backdrop, por donde
    // se ve el color directo) llega al selector UN PUNTO DESPUES que el color de paleta que sale con el. Con
    // COLOR_DECODE_DELAY = 4 la paleta cae justa en DA (27..538 a la entrada del selector, B3) pero el hueco del PRI
    // queda en 28..539: en BD8/BD16/YJK la ventana visible del color directo era de 511 puntos y se perdia el pixel 0 o
    // el ultimo (run_v9990_edge.sh). El PRI se abre y se cierra con esta copia un punto adelantada.
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                        MUX_HDE_E <= 0;
        else if(DCLK_EN && h_cnt == H_MUX_ACTIVE - 1'd1)    MUX_HDE_E <= 1;
        else if(DCLK_EN && h_cnt == H_MUX_INACTIVE - 1'd1)  MUX_HDE_E <= 0;
    end

    /***************************************************************
     * HD(ボーダーを含む表示期間)
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                            HD <= 0;
        else if(DCLK_EN && h_cnt == H_DISP_ENA) HD <= 1;
        else if(DCLK_EN && h_cnt == H_DISP_DIS) HD <= 0;
    end

    /***************************************************************
     * STATUS.HI
     ***************************************************************/
    logic [10:0] mclk_cnt;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                             mclk_cnt <= 0;
        else if(DCLK_EN && h_cnt == H_HR_ACTIVE) mclk_cnt <= 0;
        else if(CLK_MASTER_EN)                   mclk_cnt <= mclk_cnt + 1'd1;
    end

    logic [9:0] disp_line;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                            disp_line <= 0;
        else if(DCLK_EN && v_inc && (v_cnt == V_DISP_LI_START)) disp_line <= 0;
        else if(DCLK_EN && v_inc)                               disp_line <= disp_line + 1'd1;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                                        STATUS.HI <= 0;
        else if(!CLK_MASTER_EN)                                             STATUS.HI <= 0;
        else if((mclk_cnt == {REG.IX, 6'b000000}) && (disp_line == REG.IL)) STATUS.HI <= 1;
        else                                                                STATUS.HI <= 0;
    end

    /***************************************************************
     * MSXimus Z 21/10/2026: reinicio del scroll vertical y R#18/R#22
     *  Como openMSX (V9990PixelRenderer::updateScrollAYLow/BYLow, "verified" en el chip real):
     *  escribir R#17 (o R#21) con la pantalla encendida y dentro del area visible reinicia la
     *  cuenta de lineas del plano: desde ese punto la linea L muestra la linea 0 del nuevo scroll
     *  y la L+k la k. Fuera del area visible no reinicia nada. R#18/R#22 (parte alta) se toman
     *  una vez por cuadro (openMSX scrollAYHigh en frameStart): aqui siguen al registro fuera
     *  del area visible y se congelan dentro. DISP tambien se toma una vez por cuadro, como el
     *  displayEnabled de openMSX.
     *  La ventana sale de v_cnt (= !STATUS.VR en marcha normal) y no de STATUS.VR: cuando
     *  T9990_CLOCK rearranca el TG (cambio de MCS/DCKM/HSCN/C25M) a mitad de pantalla, v_cnt
     *  vuelve a 0 pero STATUS.VR se queda a 0 hasta el final del area visible siguiente.
     *  disp_line cambia en el v_inc (como el lastY de openMSX) y vuelve a 0 justo al abrirse la
     *  ventana (V_DISP_LI_START = V_VR_ACTIVE); el fetch de la linea de pantalla L se hace dentro
     *  de la linea L con BG_Y = L, asi que el plano usa Y = SCAY + (BG_Y - VOFS). Xybots lo usa
     *  para partir la pantalla (R#17 en la linea 95).
     ***************************************************************/
    wire vofs_win = TG_EN && (v_cnt > V_VR_ACTIVE) && (v_cnt <= V_VR_INACTIVE);
    logic disp_fs;
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            VOFS_A  <= 0;
            VOFS_B  <= 0;
            SCAY_HI <= 0;
            SCBY_HI <= 0;
            disp_fs <= 0;
        end
        else if(!vofs_win) begin
            VOFS_A  <= 0;
            VOFS_B  <= 0;
            SCAY_HI <= REG.SCAY[12:8];
            SCBY_HI <= REG.SCBY[8];
            disp_fs <= REG.DISP;
        end
        else begin
            if(REG.SCAYL_WR && disp_fs) VOFS_A <= disp_line[8:0];
            if(REG.SCBYL_WR && disp_fs) VOFS_B <= disp_line[8:0];
        end
    end

    /***************************************************************
     * STATUS.VR(ボーダーを含まない表示期間)
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                        STATUS.VR <= 1;
        else if(DCLK_EN && v_inc && v_cnt == V_VR_ACTIVE)   STATUS.VR <= 0;
        else if(DCLK_EN && v_inc && v_cnt == V_VR_INACTIVE) STATUS.VR <= 1;
    end

    /***************************************************************
     * MUX VDE
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                         MUX_VDE <= 0;
        else if(DCLK_EN && v_inc && v_cnt == V_MUX_ACTIVE)   MUX_VDE <= 1;
        else if(DCLK_EN && v_inc && v_cnt == V_MUX_INACTIVE) MUX_VDE <= 0;
    end

    /***************************************************************
     * VD(ボーダーを含む表示期間)
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                     VD <= 0;
        else if(DCLK_EN && v_inc && v_cnt == V_DISP_ENA) VD <= 1;
        else if(DCLK_EN && v_inc && v_cnt == V_DISP_DIS) VD <= 0;
    end

    /***************************************************************
     * STATUS.VI
     ***************************************************************/
    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                        STATUS.VI <= 0;
        else if(DCLK_EN && v_inc && v_cnt == V_VR_INACTIVE) STATUS.VI <= 1; // 表示期間完了時に1(ToDo: ボーダーを含むか含まないかを確認)
        else                                                STATUS.VI <= 0;
    end

    /***************************************************************
     * RAM タイミング
     ***************************************************************/
    wire tbl_init = DCLK_EN && (h_cnt == (H_BG_INIT));
    wire cnt_init = DCLK_EN && (h_cnt == (H_BG_INIT));
    wire tbl_send = MEM_REQ && (h_cnt != (H_BG_START));
    logic cnt_dec;

    wire ena_sp = (sp_cnt != 0) && REG.DISP && !REG.SPD && spr_v_ena;
    wire ena_bp = (bp_cnt != 0) && REG.DISP && !STATUS.VR;
    wire ena_pa = (pa_cnt != 0) && REG.DISP && !STATUS.VR;
    wire ena_pb = (pb_cnt != 0) && REG.DISP && !STATUS.VR;

    assign MEM.PREP = MEM_REQ;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) MEM.EXEC <= 0;
        else         MEM.EXEC <= MEM_REQ;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                    MEM.STATE <= RAM_XX;    // なにもしない
        else if(REG.DSPM == T9990_REG::DSPM_STANDBY) 
                                        MEM.STATE <= RAM_XX;    // なにもしない
        else if(tbl_init)               MEM.STATE <= RAM_RF;    // リフレッシュ固定
        else if(tbl_send) begin
            case (curr_tbl)
                default:                MEM.STATE <= RAM_VC;    // 未定義
                RAM_VC:                 MEM.STATE <= RAM_VC;    // VDP/CPU
                RAM_RF:                 MEM.STATE <= RAM_RF;    // リフレッシュ
                RAM_BP: if(ena_bp)      MEM.STATE <= RAM_BP;    // BITMAP データが必要なので BITMAP データを取得する
                        else if(ena_sp) MEM.STATE <= RAM_SP;    // BITMAP データがいらないので CURSOR データを取得する
                        else            MEM.STATE <= RAM_VC;    // BITMAP も CURSOR データもいらないので VDP/CPU に帯域をまわす
                RAM_SP: if(ena_sp)      MEM.STATE <= RAM_SP;    // SPRITE データが必要なので SPRITE データを取得する
                        else            MEM.STATE <= RAM_VC;    // SPRITE データがいらないので VDP/CPU に帯域をまわす
                RAM_PA: if(ena_pa)      MEM.STATE <= RAM_PA;    // PATTERN A データが必要なので PATTERN A データを取得
                        else if(ena_sp) MEM.STATE <= RAM_SP;    // PATTERN A がいらないので SPRITE データを取得
                        else            MEM.STATE <= RAM_VC;    // PATTERN A も SPRITE データもいらないので VDP/CPU に帯域をまわす
                RAM_PB: if(ena_pb)      MEM.STATE <= RAM_PB;    // PATTERN B データが必要なので PATTERN B データを取得
                        else if(ena_sp) MEM.STATE <= RAM_SP;    // PATTERN B データがいらないので SPRITE データを取得
                        else            MEM.STATE <= RAM_VC;    // PATTERN B も SPRITE もいらないので VDP/CPU に帯域をまわす
            endcase
        end
        //else                          MEM.STATE <= MEM.STATE;
    end

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                 cnt_dec <= 0;
        else if(REG.DSPM == T9990_REG::DSPM_STANDBY) cnt_dec <= 0;
        else if(tbl_init)                            cnt_dec <= 0;
        else if(tbl_send)                            cnt_dec <= 1;
        else                                         cnt_dec <= 0;
    end

    // データ残数更新
    logic [7:0] sp_cnt; // スプライトデータ残数
    logic [7:0] pa_cnt; // P1Aデータ残数
    logic [7:0] pb_cnt; // P2Bデータ残数
    logic [8:0] bp_cnt; // BPデータ残数

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            sp_cnt <= 0;
            bp_cnt <= 0;
            pa_cnt <= 0;
            pb_cnt <= 0;
        end
        else if(cnt_init) begin

            // SPRITE / CURSOR
            if(REG.DSPM == T9990_REG::DSPM_P2 || REG.DSPM == T9990_REG::DSPM_P1) begin
                sp_cnt <= 8'd157;       // 125 + 16 * 2
            end
            else begin
                sp_cnt <= 3'd6;         // (2 + 1) * 2
            end

            // PA/PB/BP
            if(REG.DSPM == T9990_REG::DSPM_P1) begin
                pa_cnt <= REG.MCS == T9990_REG::MCS_21MHZ ? 8'd51 : 8'd75;     // (256 / 16 +1) * 3 : (384 / 16 +1) * 3
                pb_cnt <= REG.MCS == T9990_REG::MCS_21MHZ ? 8'd51 : 8'd75;     // (256 / 16 +1) * 3 : (384 / 16 +1) * 3
                bp_cnt <= 0;

            end
            else if(REG.DSPM == T9990_REG::DSPM_P2) begin
                pa_cnt <= REG.MCS == T9990_REG::MCS_21MHZ ? 8'd102 : 8'd150;    // (512 / 32 + 1) * 6 : (768 / 32 + 1) * 6
                pb_cnt <= 0;
                bp_cnt <= 0;
            end
            else if(REG.HSCN) begin
                // MSXimus Z 29/10/2026: B5 (640 puntos a 21 MHz 1/1, HSCN): (640 + 32) * bpp / 32 palabras por linea.
                // 16 bpp no cabe (336 palabras en 212 ranuras); el chip real da 2 y 4 bpp en B5, aqui tambien 8.
                pa_cnt <= 0;
                pb_cnt <= 0;
                case (REG.CLRM)
                    T9990_REG::CLRM_2BPP: bp_cnt <= 9'd42;    // 640dot 2bpp    (640+32)* 2/32
                    T9990_REG::CLRM_4BPP: bp_cnt <= 9'd84;    // 640dot 4bpp    (640+32)* 4/32
                    T9990_REG::CLRM_8BPP: bp_cnt <= 9'd168;   // 640dot 8bpp    (640+32)* 8/32
                    default:              bp_cnt <= 0;
                endcase
            end
            else begin
                pa_cnt <= 0;
                pb_cnt <= 0;
                case ({REG.MCS, REG.DCKM, REG.CLRM})
                    default:                                                              bp_cnt <= 0;       // 未定義
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV4, T9990_REG::CLRM_2BPP }: bp_cnt <= 9'd17;   // 256dot 2bpp    (256+16)* 2/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV4, T9990_REG::CLRM_4BPP }: bp_cnt <= 9'd34;   // 256dot 4bpp    (256+16)* 4/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV4, T9990_REG::CLRM_8BPP }: bp_cnt <= 9'd68;   // 256dot 8bpp    (256+16)* 8/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV4, T9990_REG::CLRM_16BPP}: bp_cnt <= 9'd136;  // 256dot 16bpp   (256+16)*16/32

                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_2BPP }: bp_cnt <= 9'd34;   // 512dot 2bpp    (512+32)* 2/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_4BPP }: bp_cnt <= 9'd68;   // 512dot 4bpp    (512+32)* 4/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_8BPP }: bp_cnt <= 9'd136;  // 512dot 8bpp    (512+32)* 8/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_16BPP}: bp_cnt <= 9'd272;  // 512dot 16bpp   (512+32)*16/32

                    // MSXimus Z 28/10/2026: B7 (1024 puntos a 21 MHz / 1): 2, 4 y 8 bpp. 16 bpp no cabe (528 palabras
                    // por linea, mas de una por ranura de VRAM); el chip real solo da 2 y 4 bpp en B7.
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_2BPP }: bp_cnt <= 9'd66;   // 1024dot 2bpp   (1024+32)* 2/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_4BPP }: bp_cnt <= 9'd132;  // 1024dot 4bpp   (1024+32)* 4/32
                    { T9990_REG::MCS_21MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_8BPP }: bp_cnt <= 9'd264;  // 1024dot 8bpp   (1024+32)* 8/32

                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_2BPP }: bp_cnt <= 9'd25;   // 384dot 2bpp    (384+16)* 2/32
                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_4BPP }: bp_cnt <= 9'd50;   // 384dot 4bpp    (384+16)* 4/32
                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_8BPP }: bp_cnt <= 9'd100;  // 384dot 8bpp    (384+16)* 8/32
                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV2, T9990_REG::CLRM_16BPP}: bp_cnt <= 9'd200;  // 384dot 16bpp   (384+16)*16/32

                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_2BPP }: bp_cnt <= 9'd50;   // 768dot 2bpp    (768+32)* 2/32
                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_4BPP }: bp_cnt <= 9'd100;  // 768dot 4bpp    (768+32)* 4/32
                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_8BPP }: bp_cnt <= 9'd200;  // 768dot 8bpp    (768+32)* 8/32
                    { T9990_REG::MCS_14MHZ, T9990_REG::DCKM_DIV1, T9990_REG::CLRM_16BPP}: bp_cnt <= 9'd400;  // 768dot 16bpp   (768+32)*16/32
                endcase
            end
        end
        else if(cnt_dec) begin
            if(MEM.STATE == RAM_SP) begin
                if(sp_cnt) sp_cnt <= sp_cnt - 1'd1;
            end
            else if(MEM.STATE == RAM_BP) begin
                if(bp_cnt) bp_cnt <= bp_cnt - 1'd1;
            end
            else if(MEM.STATE == RAM_PA) begin
                if(pa_cnt) pa_cnt <= pa_cnt - 1'd1;
            end
            else if(MEM.STATE == RAM_PB) begin
                if(pb_cnt) pb_cnt <= pb_cnt - 1'd1;
            end
        end
    end

    // テーブル更新
    logic [3:0] tbl_addr;
    logic [$bits(RAM_XX)-1:0] curr_tbl;
    T9990_TIMING_TABLE u_tbl (
        .RESET_n,
        .CLK,
        .REG,
        .ADDR(tbl_init ? 4'd0 : tbl_addr),
        .OUT(curr_tbl)
    );

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n)                                         tbl_addr <= 0;
        else if(tbl_init)                                    tbl_addr <= 0;
        else if(tbl_send &&  mcs21_eff)                      tbl_addr <= tbl_addr + 1'd1;                                // 16サイクル (B5 tambien)
        else if(tbl_send && !mcs21_eff)                      tbl_addr <= (tbl_addr == 4'd11) ? 4'd0 : (tbl_addr + 1'd1); // 12サイクル
    end

endmodule 

module T9990_TIMING_TABLE (
    input wire                      RESET_n,
    input wire                      CLK,
    T9990_REGISTER_IF.VDP           REG,
    input wire [3:0]                ADDR,
    output reg [$bits(RAM_XX)-1:0]  OUT
);
    wire [3:0] addr = ADDR;
    // MSXimus Z 29/10/2026 (B5): con HSCN valen las tablas de 1024 puntos (21 MHz 1/1) diga lo que diga DCKM o MCS
    wire       mcs21_eff = REG.HSCN || (REG.MCS == T9990_REG::MCS_21MHZ);
    wire [1:0] dckm_eff  = REG.HSCN ? T9990_REG::DCKM_DIV1 : REG.DCKM;

    always_ff @(posedge CLK or negedge RESET_n) begin
        if(!RESET_n) begin
            OUT <= RAM_XX;
        end

        // P1 256dot
        else if(REG.DSPM == T9990_REG::DSPM_P1 && mcs21_eff) begin
            case (addr)
                4'd 0:  OUT <= RAM_PA;
                4'd 1:  OUT <= RAM_PB;
                4'd 2:  OUT <= RAM_PA;
                4'd 3:  OUT <= RAM_PB;
                4'd 4:  OUT <= RAM_PA;
                4'd 5:  OUT <= RAM_PB;
                4'd 6:  OUT <= RAM_SP;
                4'd 7:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_SP;
                4'd 9:  OUT <= RAM_SP;
                4'd10:  OUT <= RAM_SP;
                4'd11:  OUT <= RAM_SP;
                4'd12:  OUT <= RAM_SP;
                4'd13:  OUT <= RAM_SP;
                4'd14:  OUT <= RAM_SP;
                4'd15:  OUT <= RAM_VC;
            endcase
        end

        // P1 384dot
        else if(REG.DSPM == T9990_REG::DSPM_P1 && !mcs21_eff) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_SP;
                4'd 9:  OUT <= RAM_SP;
                4'd 8:  OUT <= RAM_SP;
                4'd 7:  OUT <= RAM_SP;
                4'd 6:  OUT <= RAM_SP;
                4'd 5:  OUT <= RAM_PB;
                4'd 4:  OUT <= RAM_PA;
                4'd 3:  OUT <= RAM_PB;
                4'd 2:  OUT <= RAM_PA;
                4'd 1:  OUT <= RAM_PB;
                4'd 0:  OUT <= RAM_PA;
            endcase
        end

        // P2 512dot
        else if(REG.DSPM == T9990_REG::DSPM_P2 && mcs21_eff) begin
            case (addr)
                4'd 0:  OUT <= RAM_PA;
                4'd 1:  OUT <= RAM_PA;
                4'd 2:  OUT <= RAM_PA;
                4'd 3:  OUT <= RAM_PA;
                4'd 4:  OUT <= RAM_PA;
                4'd 5:  OUT <= RAM_PA;
                4'd 6:  OUT <= RAM_SP;
                4'd 7:  OUT <= RAM_VC;

                4'd 8:  OUT <= RAM_SP;
                4'd 9:  OUT <= RAM_SP;
                4'd10:  OUT <= RAM_SP;
                4'd11:  OUT <= RAM_SP;
                4'd12:  OUT <= RAM_SP;
                4'd13:  OUT <= RAM_SP;
                4'd14:  OUT <= RAM_SP;
                4'd15:  OUT <= RAM_VC;
            endcase
        end

        // P2 768dot
        else if(REG.DSPM == T9990_REG::DSPM_P2 && !mcs21_eff) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_SP;
                4'd 9:  OUT <= RAM_SP;
                4'd 8:  OUT <= RAM_SP;
                4'd 7:  OUT <= RAM_SP;
                4'd 6:  OUT <= RAM_SP;
                4'd 5:  OUT <= RAM_PA;
                4'd 4:  OUT <= RAM_PA;
                4'd 3:  OUT <= RAM_PA;
                4'd 2:  OUT <= RAM_PA;
                4'd 1:  OUT <= RAM_PA;
                4'd 0:  OUT <= RAM_PA;
            endcase
        end

        // 2bpp 256dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV4 && REG.CLRM == T9990_REG::CLRM_2BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 4bpp 256dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV4 && REG.CLRM == T9990_REG::CLRM_4BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 8bpp 256dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV4 && REG.CLRM == T9990_REG::CLRM_8BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 16bpp 256dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV4 && REG.CLRM == T9990_REG::CLRM_16BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_BP;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_BP;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 2bpp 512dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_2BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 4bpp 512dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_4BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 8bpp 512dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_8BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_BP;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_BP;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 16bpp 512dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_16BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_BP;
                4'd14:  OUT <= RAM_BP;
                4'd13:  OUT <= RAM_BP;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_BP;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_BP;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_BP;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_BP;
                4'd 1:  OUT <= RAM_BP;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // MSXimus Z 28/10/2026: B7 (1024 puntos, 4 ciclos por punto, ranura de VRAM cada 16 ciclos = 4 puntos); B5 (29/10) igual:
        // 2 bpp una palabra cada 16 puntos (1 de cada 4 ranuras), 4 bpp cada 8 (1 de cada 2), 8 bpp cada 4 (todas)
        // 2bpp 1024dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_2BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 4bpp 1024dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_4BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_BP;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_BP;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 8bpp 1024dot
        else if(mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_8BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_BP;
                4'd14:  OUT <= RAM_BP;
                4'd13:  OUT <= RAM_BP;
                4'd12:  OUT <= RAM_BP;
                4'd11:  OUT <= RAM_BP;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_BP;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_BP;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_BP;
                4'd 1:  OUT <= RAM_BP;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 2bpp 384dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_2BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_VC;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 4bpp 384dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_4BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 8bpp 384dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_8BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 16bpp 384dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV2 && REG.CLRM == T9990_REG::CLRM_16BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_BP;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_BP;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 2bpp 768dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_2BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_VC;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_VC;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 4bpp 768dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_4BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_VC;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_VC;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_VC;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_VC;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 8bpp 768dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_8BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_VC;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_VC;
                4'd 7:  OUT <= RAM_BP;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_VC;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_VC;
                4'd 1:  OUT <= RAM_BP;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // 16bpp 768dot
        else if(!mcs21_eff && dckm_eff == T9990_REG::DCKM_DIV1 && REG.CLRM == T9990_REG::CLRM_16BPP) begin
            case (addr)
                4'd15:  OUT <= RAM_BP;
                4'd14:  OUT <= RAM_VC;
                4'd13:  OUT <= RAM_VC;
                4'd12:  OUT <= RAM_VC;
                4'd11:  OUT <= RAM_VC;
                4'd10:  OUT <= RAM_BP;
                4'd 9:  OUT <= RAM_BP;
                4'd 8:  OUT <= RAM_BP;
                4'd 7:  OUT <= RAM_BP;
                4'd 6:  OUT <= RAM_BP;
                4'd 5:  OUT <= RAM_BP;
                4'd 4:  OUT <= RAM_BP;
                4'd 3:  OUT <= RAM_BP;
                4'd 2:  OUT <= RAM_BP;
                4'd 1:  OUT <= RAM_BP;
                4'd 0:  OUT <= RAM_BP;
            endcase
        end

        // default
        else begin
            OUT <= 0;
        end
    end
endmodule

`default_nettype wire
