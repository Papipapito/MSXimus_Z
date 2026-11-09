// ============================================================================
// scc_wave2_ghdl.v -- SCC / SCC-I sound core (GENERADO, no editar a mano).
//
// Verilog producido por GHDL a partir del VHDL original, para esquivar el
// frontend VHDL de la sintesis de Gowin en GW5A (que miscompila este fichero
// en silencio: entity barrida NL0002 + al menos una miscompilacion muda mas).
// Gowin solo ve Verilog; GHDL (que interpreta el VHDL correctamente) hace la
// conversion.
//
// Fuentes:
//   fpga/src/ocm/scc_wave2.vhd            (md5 d9aa3bc2aeadf582812802d4a19b4ef5)
//   fpga/tn_vdp_v3_v9958/src/ram.vhd      (md5 4b07b17365c24cdf624b4cafad86fbeb, solo entity 'ram')
//
// Herramienta:
//   GHDL 6.0.0 (6.0.0.r0.ge589c698c) [Dunoon edition], mcode,
//   binario release ghdl-mcode-6.0.0-ubuntu24.04-x86_64.tar.gz (WSL).
//
// Comandos exactos:
//   ghdl -a       -fsynopsys -fexplicit --std=93c ram.vhd scc_wave2.vhd
//   ghdl --synth  --out=verilog -fsynopsys -fexplicit --std=93c scc_wave2 \
//        > scc_wave2_ghdl.v
//
// Modulos generados:
//   scc_wave2   -- top, MISMO nombre y port map que la entity VHDL, con los
//                  puertos de debug:
//                   _46dbg: dbg_vol_nz / dbg_sel_nz / dbg_freq_nz
//                   _49dbg: dbg_ptr_lsb  = ff_ptr_ch_a(0), togglea en CADA
//                           avance del puntero ch.A (440Hz -> cuadrada
//                           ~7 kHz, duty 50%)
//                   _51dbg: dbg_scan_lsb = ff_ch_num(0), escaneo de canales
//                           a reloj pleno (vivo = cuadrada clk/2 = 13.5 MHz
//                           a 27M, duty ~50%; congelado = nivel fijo)
//                           dbg_mix_nz   = ff_mix /= 0 (con tono ~80% duty;
//                           mixer muerto = 0%)
//                   _52dbg: dbg_wavlatch = togglea en cada CAPTURA real del
//                           latch final ff_wave (vivo = ~4.5M capturas/s a
//                           27M, CON o SIN tono => cuadrada 2.25 MHz duty
//                           50%; muerto = fijo; ligado-a-accesos = kHz
//                           esporadicos solo bajo martilleo CPU)
//                   _53dbg: dbg_capnz   = '1' si la ULTIMA captura fue con
//                           ff_mix /= 0 (beeper sierra vivo ~97% = 31/32;
//                           "captura ceros" = 0% fijo)
//                           dbg_wave_nz = ff_wave (registro interno) /= 0
//                           (~97% con tono; separa "ff_wave==0" de "cono
//                           ff_wave->puerto wave roto")
//                   _54dbg: dbg_mix5_nz = ff_mix /= 0 muestreado en el slot
//                           dl=="101" (ultimo de acumulacion; ~97-100% con
//                           tono). mix5_nz ON + capnz OFF = el valor se
//                           desvanece entre dl==5 y la captura dl==0.
//
// ⚠ CAMBIOS DE RTL (no solo sondas):
//   _52: el proceso ff_wave captura SIN el guard ff_wave_ce_dl='0'.
//   _54 FIX "carga/hold" (sintoma _53dbg: el latch capturaba CEROS): ff_mix
//     ya NO se resetea en dl=="000" (HOLD); en dl=="001" CARGA el primer
//     producto (ch.A) y en dl=="010".."101" acumula. Suma IDENTICA, pero la
//     captura de ff_wave lee un valor estable >=1 ciclo — cero interaccion
//     captura/reset por construccion (mata la carrera que GW5A rompia).
//     El guard ce_dl del mixer se conserva. Ver comentarios en scc_wave2.vhd.
//   23/09/2026 (MSXimus Z): ESTEREO POR CANALES. Puertos nuevos wave_l, wave_r
//     (15 b) y pan_mirror (entrada). Dos acumuladores mas, al mismo ritmo que
//     ff_mix, con un peso en cuartos por canal (A 3/1, B 1/3, C 2/2, D 3/1,
//     E 1/3 izq/der; en espejo con pan_mirror=1): wave_l + wave_r = wave
//     (redondeo aparte). wave no cambia. Regenerado con los mismos comandos;
//     sin el estereo, el netlist del 21/09 salia identico (salvo comentarios).
//   ram_Brtl    -- la wave RAM 256x8 (entity 'ram', arquitectura RTL);
//                  el sufijo _Brtl lo pone GHDL => NO colisiona con la
//                  entity VHDL 'ram' de ram.vhd si esta sigue en el proyecto
//
// INTEGRACION (build.tcl): al añadir este fichero hay que QUITAR
//   src/ocm/scc_wave2.vhd  del proyecto (si no, design unit 'scc_wave2'
//   duplicada VHDL/Verilog). ram.vhd puede quedarse (palette_rb/palette_g).
//
// Validado con Icarus Verilog 12:
//   tools/scc_tb/run_ghdl.sh  -- mismos 21 checks que el TB de scc_wave2v
//   tools/scc_tb/run_cen27.sh -- TB con el camino REAL de clk_enable_3m6_27
//     (div30@108M -> PINFILTER@54M -> cadena 8FF@27M -> edge detect, replica
//     verbatim de top.v:240-328) y chip a clk_27m: 21 checks + checks de
//     avance del puntero (N1), escaneo vivo (N2), acumulador activo (N3),
//     tasa de captura del latch final (N4), contenido de la captura +
//     registro de salida (N5) y suma en el ultimo slot de acumulacion (N6)
//     con las sondas dbg_ptr_lsb / dbg_scan_lsb / dbg_mix_nz / dbg_wavlatch /
//     dbg_capnz / dbg_wave_nz / dbg_mix5_nz calibradas.
//
// Notas de estilo del netlist GHDL (revisadas):
//   - FF: always @(posedge clk21m or posedge reset) con if/else -> DFF con
//     reset asincrono estandar, sin latches.
//   - Combinacional: assign + always @* con case y default en todos los
//     decodificadores; los 5 always @* sin default son copias incondicionales
//     de una sola linea (espejo de las VHDL variables ff_cnt_ch_*).
//   - 5 bloques 'initial <reg> = 12'bX': inicializacion X SOLO de simulacion
//     de esos espejos; la sintesis los ignora (don't care).
//   - 1 multiplicador: assign $signed(a) * $signed(b) // smul (el producto
//     onda x volumen del FIX, ya inline, sin frontera de entity que barrer).
//
// Licencia: derivado de scc_wave.vhd (c)2006 Kazuhiro Tsujikawa (ESE Artists'
// factory), mod. 2007 t.hara. La licencia original (no comercial) aplica.
// ============================================================================

module ram_Brtl
  (input  [7:0] adr,
   input  clk,
   input  we,
   input  [7:0] dbo,
   output [7:0] dbi);
  wire [7:0] iadr;
  reg [7:0] n764;
  wire [7:0] n765; // mem_rd
  assign dbi = n765; //(module output)
  /*# ram.vhd:50:10 */
  assign iadr = n764; // (signal)
  /*# ram.vhd:56:5 */
  always @(posedge clk)
    n764 <= adr;
  reg [7:0] blkram[255:0] ; // memory
  assign n765 = blkram[iadr];
  always @(posedge clk)
    if (we)
      blkram[adr] <= dbo;
  /*# ram.vhd:64:17 */
  /*# ram.vhd:58:16 */
endmodule

module scc_wave2
  (input  clk21m,
   input  reset,
   input  clkena,
   input  req,
   output ack,
   input  wrt,
   input  [7:0] adr,
   output [7:0] dbi,
   input  [7:0] dbo,
   output [14:0] wave,
   output [14:0] wave_l,
   output [14:0] wave_r,
   input  pan_mirror,
   input  sccplus,
   output dbg_vol_nz,
   output dbg_sel_nz,
   output dbg_freq_nz,
   output dbg_ptr_lsb,
   output dbg_scan_lsb,
   output dbg_mix_nz,
   output dbg_wavlatch,
   output dbg_capnz,
   output dbg_wave_nz,
   output dbg_mix5_nz);
  wire w_wave_ce;
  wire w_wave_we;
  wire [7:0] w_wave_adr;
  wire [4:0] w_ch_dec;
  wire w_ch_bit;
  wire [7:0] w_ch_mask;
  wire [3:0] w_ch_vol;
  wire [7:0] w_wave;
  wire [11:0] w_mul;
  wire [12:0] w_mul_s;
  wire [7:0] ram_dbi;
  wire [11:0] reg_freq_ch_a;
  wire [11:0] reg_freq_ch_b;
  wire [11:0] reg_freq_ch_c;
  wire [11:0] reg_freq_ch_d;
  wire [11:0] reg_freq_ch_e;
  wire [3:0] reg_vol_ch_a;
  wire [3:0] reg_vol_ch_b;
  wire [3:0] reg_vol_ch_c;
  wire [3:0] reg_vol_ch_d;
  wire [3:0] reg_vol_ch_e;
  wire [4:0] reg_ch_sel;
  wire [7:0] reg_mode_sel;
  wire ff_rst_ch_a;
  wire ff_rst_ch_b;
  wire ff_rst_ch_c;
  wire ff_rst_ch_d;
  wire ff_rst_ch_e;
  wire [4:0] ff_ptr_ch_a;
  wire [4:0] ff_ptr_ch_b;
  wire [4:0] ff_ptr_ch_c;
  wire [4:0] ff_ptr_ch_d;
  wire [4:0] ff_ptr_ch_e;
  wire [2:0] ff_ch_num;
  wire [2:0] ff_ch_num_dl;
  wire [14:0] ff_mix;
  wire ff_wave_ce;
  wire ff_wave_ce_dl;
  wire ff_req_dl;
  wire [7:0] ff_wave_dat;
  wire [14:0] ff_wave;
  wire ff_wavlatch_tgl;
  wire ff_capnz;
  wire ff_mix5_nz;
  wire [1:0] w_wl_n;
  wire [1:0] w_wl;
  wire [1:0] w_wr;
  wire [13:0] w_m1;
  wire [13:0] w_m2;
  wire [13:0] w_m3;
  wire [13:0] w_pl;
  wire [13:0] w_pr;
  wire [16:0] ff_mix_l;
  wire [16:0] ff_mix_r;
  wire [14:0] ff_wave_l;
  wire [14:0] ff_wave_r;
  wire n18;
  wire n19;
  wire n20;
  wire n21;
  wire [2:0] n22;
  wire n24;
  wire n25;
  wire [2:0] n26;
  wire n28;
  wire n29;
  wire n30;
  wire n31;
  wire [3:0] n32;
  wire n33;
  wire n35;
  wire [3:0] n36;
  wire n37;
  wire n39;
  wire n40;
  wire n42;
  wire [3:0] n43;
  wire n44;
  wire n46;
  wire n47;
  wire n49;
  wire [3:0] n50;
  wire n51;
  wire n53;
  wire n54;
  wire n56;
  wire [3:0] n57;
  wire n58;
  wire n60;
  wire n61;
  wire n63;
  wire [3:0] n64;
  wire n65;
  wire n67;
  wire [3:0] n68;
  wire n70;
  wire [3:0] n71;
  wire n73;
  wire [3:0] n74;
  wire n76;
  wire [3:0] n77;
  wire n79;
  wire [3:0] n80;
  wire n82;
  wire [4:0] n83;
  wire [14:0] n84;
  wire [7:0] n85;
  reg [7:0] n86;
  wire [3:0] n87;
  reg [3:0] n88;
  wire [7:0] n89;
  reg [7:0] n90;
  wire [3:0] n91;
  reg [3:0] n92;
  wire [7:0] n93;
  reg [7:0] n94;
  wire [3:0] n95;
  reg [3:0] n96;
  wire [7:0] n97;
  reg [7:0] n98;
  wire [3:0] n99;
  reg [3:0] n100;
  wire [7:0] n101;
  reg [7:0] n102;
  wire [3:0] n103;
  reg [3:0] n104;
  reg [3:0] n105;
  reg [3:0] n106;
  reg [3:0] n107;
  reg [3:0] n108;
  reg [3:0] n109;
  reg [4:0] n110;
  reg n111;
  reg n112;
  reg n113;
  reg n114;
  reg n115;
  wire n117;
  wire n119;
  wire n121;
  wire n123;
  wire n125;
  wire [11:0] n126;
  wire [11:0] n128;
  wire [11:0] n130;
  wire [11:0] n132;
  wire [11:0] n134;
  wire n142;
  wire n143;
  wire n144;
  wire n145;
  wire n146;
  wire n147;
  wire [2:0] n148;
  wire n150;
  wire n151;
  wire n209;
  wire n210;
  wire n211;
  wire n213;
  wire n214;
  wire n215;
  wire n219;
  wire n220;
  wire n224;
  wire n225;
  wire n229;
  wire n230;
  wire n232;
  wire n233;
  wire n236;
  wire n237;
  reg [11:0] n239_ff_cnt_ch_a;
  reg [11:0] n239_ff_cnt_ch_b;
  reg [11:0] n239_ff_cnt_ch_c;
  reg [11:0] n239_ff_cnt_ch_d;
  reg [11:0] n239_ff_cnt_ch_e;
  wire [8:0] n247;
  wire n249;
  wire n250;
  wire n252;
  wire [4:0] n254;
  wire [11:0] n256;
  wire [4:0] n257;
  wire [11:0] n258;
  wire [4:0] n260;
  wire [11:0] n261;
  wire [8:0] n262;
  wire n264;
  wire n265;
  wire n267;
  wire [4:0] n269;
  wire [11:0] n271;
  wire [4:0] n272;
  wire [11:0] n273;
  wire [4:0] n275;
  wire [11:0] n276;
  wire [8:0] n277;
  wire n279;
  wire n280;
  wire n282;
  wire [4:0] n284;
  wire [11:0] n286;
  wire [4:0] n287;
  wire [11:0] n288;
  wire [4:0] n290;
  wire [11:0] n291;
  wire [8:0] n292;
  wire n294;
  wire n295;
  wire n297;
  wire [4:0] n299;
  wire [11:0] n301;
  wire [4:0] n302;
  wire [11:0] n303;
  wire [4:0] n305;
  wire [11:0] n306;
  wire [8:0] n307;
  wire n309;
  wire n310;
  wire n312;
  wire [4:0] n314;
  wire [11:0] n316;
  wire [4:0] n317;
  wire [11:0] n318;
  wire [4:0] n320;
  wire [11:0] n321;
  wire [7:0] n363;
  wire [7:0] n365;
  wire n367;
  wire [7:0] n368;
  wire [7:0] n370;
  wire n372;
  wire [7:0] n373;
  wire [7:0] n375;
  wire n377;
  wire [7:0] n378;
  wire [7:0] n380;
  wire n382;
  wire [7:0] n383;
  wire [7:0] n385;
  wire [7:0] n386;
  wire [7:0] n388;
  wire [7:0] wavemem_n389;
  wire n418;
  wire n421;
  wire n424;
  wire n427;
  wire n430;
  wire [4:0] n432;
  reg [4:0] n433;
  wire n434;
  wire n435;
  wire n436;
  wire n437;
  wire n438;
  wire n439;
  wire n440;
  wire n441;
  wire n442;
  wire n443;
  wire n444;
  wire n445;
  wire n446;
  wire n447;
  wire n448;
  wire n449;
  wire n450;
  wire n451;
  wire n452;
  wire [7:0] n453;
  wire n455;
  wire n457;
  wire n459;
  wire n461;
  wire n463;
  wire [4:0] n465;
  reg [3:0] n466;
  wire [7:0] n467;
  wire [4:0] n469;
  wire [12:0] n470;
  wire [12:0] n471;
  wire [12:0] n472;
  wire [11:0] n473;
  wire n476;
  wire n479;
  wire n482;
  wire n485;
  wire n488;
  wire [4:0] n490;
  reg [1:0] n491;
  wire n492;
  wire [1:0] n493;
  wire n494;
  wire n495;
  wire n496;
  wire n497;
  wire [1:0] n498;
  wire n499;
  wire n500;
  wire n501;
  wire n502;
  wire [1:0] n503;
  wire n504;
  wire n505;
  wire [1:0] n506;
  wire [13:0] n507;
  wire n508;
  wire [12:0] n509;
  wire [13:0] n511;
  wire [13:0] n512;
  wire n514;
  wire [13:0] n515;
  wire n517;
  wire [13:0] n518;
  wire n520;
  wire [13:0] n521;
  wire n523;
  wire [13:0] n524;
  wire n528;
  wire n530;
  wire [2:0] n532;
  wire [2:0] n534;
  wire n543;
  wire n545;
  wire n546;
  wire n547;
  wire [1:0] n548;
  wire n549;
  wire [2:0] n550;
  wire [14:0] n551;
  wire n553;
  wire n554;
  wire n555;
  wire [1:0] n556;
  wire n557;
  wire [2:0] n558;
  wire [14:0] n559;
  wire [14:0] n560;
  wire [14:0] n561;
  wire [14:0] n562;
  wire n572;
  wire n574;
  wire n577;
  wire n586;
  wire n588;
  wire n589;
  wire n590;
  wire [1:0] n591;
  wire n592;
  wire [2:0] n593;
  wire [16:0] n594;
  wire n595;
  wire n596;
  wire [1:0] n597;
  wire n598;
  wire [2:0] n599;
  wire [16:0] n600;
  wire n602;
  wire n603;
  wire n604;
  wire [1:0] n605;
  wire n606;
  wire [2:0] n607;
  wire [16:0] n608;
  wire [16:0] n609;
  wire n610;
  wire n611;
  wire [1:0] n612;
  wire n613;
  wire [2:0] n614;
  wire [16:0] n615;
  wire [16:0] n616;
  wire [16:0] n617;
  wire [16:0] n618;
  wire [16:0] n619;
  wire [16:0] n620;
  wire n634;
  wire [14:0] n635;
  wire [14:0] n636;
  wire n637;
  wire n639;
  wire n642;
  wire n666;
  wire n667;
  wire [7:0] n672;
  reg [7:0] n673;
  wire [11:0] n674;
  reg [11:0] n675;
  wire [11:0] n676;
  reg [11:0] n677;
  wire [11:0] n678;
  reg [11:0] n679;
  wire [11:0] n680;
  reg [11:0] n681;
  wire [11:0] n682;
  reg [11:0] n683;
  wire [3:0] n684;
  reg [3:0] n685;
  wire [3:0] n686;
  reg [3:0] n687;
  wire [3:0] n688;
  reg [3:0] n689;
  wire [3:0] n690;
  reg [3:0] n691;
  wire [3:0] n692;
  reg [3:0] n693;
  wire [4:0] n694;
  reg [4:0] n695;
  wire [7:0] n696;
  reg [7:0] n697;
  reg n698;
  reg n699;
  reg n700;
  reg n701;
  reg n702;
  wire [4:0] n703;
  reg [4:0] n704;
  wire [4:0] n705;
  reg [4:0] n706;
  wire [4:0] n707;
  reg [4:0] n708;
  wire [4:0] n709;
  reg [4:0] n710;
  wire [4:0] n711;
  reg [4:0] n712;
  wire [2:0] n713;
  reg [2:0] n714;
  reg [2:0] n715;
  wire [14:0] n716;
  reg [14:0] n717;
  reg n718;
  reg n719;
  reg n720;
  reg [7:0] n721;
  wire [14:0] n722;
  reg [14:0] n723;
  wire n724;
  reg n725;
  wire n726;
  reg n727;
  wire n728;
  reg n729;
  wire [16:0] n730;
  reg [16:0] n731;
  wire [16:0] n732;
  reg [16:0] n733;
  wire [14:0] n734;
  reg [14:0] n735;
  wire [14:0] n736;
  reg [14:0] n737;
  wire [11:0] n738;
  reg [11:0] n739;
  wire [11:0] n740;
  reg [11:0] n741;
  wire [11:0] n742;
  reg [11:0] n743;
  wire [11:0] n744;
  reg [11:0] n745;
  wire [11:0] n746;
  reg [11:0] n747;
  assign ack = ff_req_dl; //(module output)
  assign dbi = n673; //(module output)
  assign wave = ff_wave; //(module output)
  assign wave_l = ff_wave_l; //(module output)
  assign wave_r = ff_wave_r; //(module output)
  assign dbg_vol_nz = n220; //(module output)
  assign dbg_sel_nz = n225; //(module output)
  assign dbg_freq_nz = n230; //(module output)
  assign dbg_ptr_lsb = n232; //(module output)
  assign dbg_scan_lsb = n233; //(module output)
  assign dbg_mix_nz = n237; //(module output)
  assign dbg_wavlatch = ff_wavlatch_tgl; //(module output)
  assign dbg_capnz = ff_capnz; //(module output)
  assign dbg_wave_nz = n667; //(module output)
  assign dbg_mix5_nz = ff_mix5_nz; //(module output)
  /*# scc_wave2.vhd:140:12 */
  assign w_wave_ce = n211; // (signal)
  /*# scc_wave2.vhd:141:12 */
  assign w_wave_we = n215; // (signal)
  /*# scc_wave2.vhd:142:12 */
  assign w_wave_adr = n363; // (signal)
  /*# scc_wave2.vhd:143:12 */
  assign w_ch_dec = n433; // (signal)
  /*# scc_wave2.vhd:144:12 */
  assign w_ch_bit = n452; // (signal)
  /*# scc_wave2.vhd:145:12 */
  assign w_ch_mask = n453; // (signal)
  /*# scc_wave2.vhd:146:12 */
  assign w_ch_vol = n466; // (signal)
  /*# scc_wave2.vhd:147:12 */
  assign w_wave = n467; // (signal)
  /*# scc_wave2.vhd:148:12 */
  assign w_mul = n473; // (signal)
  /*# scc_wave2.vhd:149:12 */
  assign w_mul_s = n472; // (signal)
  /*# scc_wave2.vhd:150:12 */
  assign ram_dbi = wavemem_n389; // (signal)
  /*# scc_wave2.vhd:156:12 */
  assign reg_freq_ch_a = n675; // (signal)
  /*# scc_wave2.vhd:157:12 */
  assign reg_freq_ch_b = n677; // (signal)
  /*# scc_wave2.vhd:158:12 */
  assign reg_freq_ch_c = n679; // (signal)
  /*# scc_wave2.vhd:159:12 */
  assign reg_freq_ch_d = n681; // (signal)
  /*# scc_wave2.vhd:160:12 */
  assign reg_freq_ch_e = n683; // (signal)
  /*# scc_wave2.vhd:161:12 */
  assign reg_vol_ch_a = n685; // (signal)
  /*# scc_wave2.vhd:162:12 */
  assign reg_vol_ch_b = n687; // (signal)
  /*# scc_wave2.vhd:163:12 */
  assign reg_vol_ch_c = n689; // (signal)
  /*# scc_wave2.vhd:164:12 */
  assign reg_vol_ch_d = n691; // (signal)
  /*# scc_wave2.vhd:165:12 */
  assign reg_vol_ch_e = n693; // (signal)
  /*# scc_wave2.vhd:166:12 */
  assign reg_ch_sel = n695; // (signal)
  /*# scc_wave2.vhd:167:12 */
  assign reg_mode_sel = n697; // (signal)
  /*# scc_wave2.vhd:170:12 */
  assign ff_rst_ch_a = n698; // (signal)
  /*# scc_wave2.vhd:171:12 */
  assign ff_rst_ch_b = n699; // (signal)
  /*# scc_wave2.vhd:172:12 */
  assign ff_rst_ch_c = n700; // (signal)
  /*# scc_wave2.vhd:173:12 */
  assign ff_rst_ch_d = n701; // (signal)
  /*# scc_wave2.vhd:174:12 */
  assign ff_rst_ch_e = n702; // (signal)
  /*# scc_wave2.vhd:175:12 */
  assign ff_ptr_ch_a = n704; // (signal)
  /*# scc_wave2.vhd:176:12 */
  assign ff_ptr_ch_b = n706; // (signal)
  /*# scc_wave2.vhd:177:12 */
  assign ff_ptr_ch_c = n708; // (signal)
  /*# scc_wave2.vhd:178:12 */
  assign ff_ptr_ch_d = n710; // (signal)
  /*# scc_wave2.vhd:179:12 */
  assign ff_ptr_ch_e = n712; // (signal)
  /*# scc_wave2.vhd:180:12 */
  assign ff_ch_num = n714; // (signal)
  /*# scc_wave2.vhd:181:12 */
  assign ff_ch_num_dl = n715; // (signal)
  /*# scc_wave2.vhd:182:12 */
  assign ff_mix = n717; // (signal)
  /*# scc_wave2.vhd:183:12 */
  assign ff_wave_ce = n718; // (signal)
  /*# scc_wave2.vhd:184:12 */
  assign ff_wave_ce_dl = n719; // (signal)
  /*# scc_wave2.vhd:185:12 */
  assign ff_req_dl = n720; // (signal)
  /*# scc_wave2.vhd:186:12 */
  assign ff_wave_dat = n721; // (signal)
  /*# scc_wave2.vhd:187:12 */
  assign ff_wave = n723; // (signal)
  /*# scc_wave2.vhd:188:12 */
  assign ff_wavlatch_tgl = n725; // (signal)
  /*# scc_wave2.vhd:189:12 */
  assign ff_capnz = n727; // (signal)
  /*# scc_wave2.vhd:190:12 */
  assign ff_mix5_nz = n729; // (signal)
  /*# scc_wave2.vhd:192:12 */
  assign w_wl_n = n491; // (signal)
  /*# scc_wave2.vhd:193:12 */
  assign w_wl = n493; // (signal)
  /*# scc_wave2.vhd:194:12 */
  assign w_wr = n503; // (signal)
  /*# scc_wave2.vhd:195:12 */
  assign w_m1 = n507; // (signal)
  /*# scc_wave2.vhd:196:12 */
  assign w_m2 = n511; // (signal)
  /*# scc_wave2.vhd:197:12 */
  assign w_m3 = n512; // (signal)
  /*# scc_wave2.vhd:198:12 */
  assign w_pl = n515; // (signal)
  /*# scc_wave2.vhd:199:12 */
  assign w_pr = n521; // (signal)
  /*# scc_wave2.vhd:200:12 */
  assign ff_mix_l = n731; // (signal)
  /*# scc_wave2.vhd:201:12 */
  assign ff_mix_r = n733; // (signal)
  /*# scc_wave2.vhd:202:12 */
  assign ff_wave_l = n735; // (signal)
  /*# scc_wave2.vhd:203:12 */
  assign ff_wave_r = n737; // (signal)
  /*# scc_wave2.vhd:237:41 */
  assign n18 = ~ff_req_dl;
  /*# scc_wave2.vhd:237:27 */
  assign n19 = n18 & req;
  /*# scc_wave2.vhd:237:47 */
  assign n20 = wrt & n19;
  /*# scc_wave2.vhd:238:27 */
  assign n21 = ~sccplus;
  /*# scc_wave2.vhd:238:40 */
  assign n22 = adr[7:5]; // extract
  /*# scc_wave2.vhd:238:53 */
  assign n24 = n22 == 3'b100;
  /*# scc_wave2.vhd:238:33 */
  assign n25 = n24 & n21;
  /*# scc_wave2.vhd:239:40 */
  assign n26 = adr[7:5]; // extract
  /*# scc_wave2.vhd:239:53 */
  assign n28 = n26 == 3'b101;
  /*# scc_wave2.vhd:239:33 */
  assign n29 = n28 & sccplus;
  /*# scc_wave2.vhd:238:62 */
  assign n30 = n25 | n29;
  /*# scc_wave2.vhd:237:61 */
  assign n31 = n30 & n20;
  /*# scc_wave2.vhd:240:25 */
  assign n32 = adr[3:0]; // extract
  /*# scc_wave2.vhd:241:114 */
  assign n33 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:241:21 */
  assign n35 = n32 == 4'b0000;
  /*# scc_wave2.vhd:242:71 */
  assign n36 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:242:114 */
  assign n37 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:242:21 */
  assign n39 = n32 == 4'b0001;
  /*# scc_wave2.vhd:243:114 */
  assign n40 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:243:21 */
  assign n42 = n32 == 4'b0010;
  /*# scc_wave2.vhd:244:71 */
  assign n43 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:244:114 */
  assign n44 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:244:21 */
  assign n46 = n32 == 4'b0011;
  /*# scc_wave2.vhd:245:114 */
  assign n47 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:245:21 */
  assign n49 = n32 == 4'b0100;
  /*# scc_wave2.vhd:246:71 */
  assign n50 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:246:114 */
  assign n51 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:246:21 */
  assign n53 = n32 == 4'b0101;
  /*# scc_wave2.vhd:247:114 */
  assign n54 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:247:21 */
  assign n56 = n32 == 4'b0110;
  /*# scc_wave2.vhd:248:71 */
  assign n57 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:248:114 */
  assign n58 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:248:21 */
  assign n60 = n32 == 4'b0111;
  /*# scc_wave2.vhd:249:114 */
  assign n61 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:249:21 */
  assign n63 = n32 == 4'b1000;
  /*# scc_wave2.vhd:250:71 */
  assign n64 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:250:114 */
  assign n65 = reg_mode_sel[5]; // extract
  /*# scc_wave2.vhd:250:21 */
  assign n67 = n32 == 4'b1001;
  /*# scc_wave2.vhd:251:71 */
  assign n68 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:251:21 */
  assign n70 = n32 == 4'b1010;
  /*# scc_wave2.vhd:252:71 */
  assign n71 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:252:21 */
  assign n73 = n32 == 4'b1011;
  /*# scc_wave2.vhd:253:71 */
  assign n74 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:253:21 */
  assign n76 = n32 == 4'b1100;
  /*# scc_wave2.vhd:254:71 */
  assign n77 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:254:21 */
  assign n79 = n32 == 4'b1101;
  /*# scc_wave2.vhd:255:71 */
  assign n80 = dbo[3:0]; // extract
  /*# scc_wave2.vhd:255:21 */
  assign n82 = n32 == 4'b1110;
  /*# scc_wave2.vhd:256:71 */
  assign n83 = dbo[4:0]; // extract
  /*# scc_wave2.vhd:240:17 */
  assign n84 = {n82, n79, n76, n73, n70, n67, n63, n60, n56, n53, n49, n46, n42, n39, n35};
  /*# scc_wave2.vhd:156:12 */
  assign n85 = reg_freq_ch_a[7:0]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n86 = n85;
      15'b010000000000000: n86 = n85;
      15'b001000000000000: n86 = n85;
      15'b000100000000000: n86 = n85;
      15'b000010000000000: n86 = n85;
      15'b000001000000000: n86 = n85;
      15'b000000100000000: n86 = n85;
      15'b000000010000000: n86 = n85;
      15'b000000001000000: n86 = n85;
      15'b000000000100000: n86 = n85;
      15'b000000000010000: n86 = n85;
      15'b000000000001000: n86 = n85;
      15'b000000000000100: n86 = n85;
      15'b000000000000010: n86 = n85;
      15'b000000000000001: n86 = dbo;
      default: n86 = n85;
    endcase
  /*# scc_wave2.vhd:156:12 */
  assign n87 = reg_freq_ch_a[11:8]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n88 = n87;
      15'b010000000000000: n88 = n87;
      15'b001000000000000: n88 = n87;
      15'b000100000000000: n88 = n87;
      15'b000010000000000: n88 = n87;
      15'b000001000000000: n88 = n87;
      15'b000000100000000: n88 = n87;
      15'b000000010000000: n88 = n87;
      15'b000000001000000: n88 = n87;
      15'b000000000100000: n88 = n87;
      15'b000000000010000: n88 = n87;
      15'b000000000001000: n88 = n87;
      15'b000000000000100: n88 = n87;
      15'b000000000000010: n88 = n36;
      15'b000000000000001: n88 = n87;
      default: n88 = n87;
    endcase
  /*# scc_wave2.vhd:157:12 */
  assign n89 = reg_freq_ch_b[7:0]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n90 = n89;
      15'b010000000000000: n90 = n89;
      15'b001000000000000: n90 = n89;
      15'b000100000000000: n90 = n89;
      15'b000010000000000: n90 = n89;
      15'b000001000000000: n90 = n89;
      15'b000000100000000: n90 = n89;
      15'b000000010000000: n90 = n89;
      15'b000000001000000: n90 = n89;
      15'b000000000100000: n90 = n89;
      15'b000000000010000: n90 = n89;
      15'b000000000001000: n90 = n89;
      15'b000000000000100: n90 = dbo;
      15'b000000000000010: n90 = n89;
      15'b000000000000001: n90 = n89;
      default: n90 = n89;
    endcase
  /*# scc_wave2.vhd:157:12 */
  assign n91 = reg_freq_ch_b[11:8]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n92 = n91;
      15'b010000000000000: n92 = n91;
      15'b001000000000000: n92 = n91;
      15'b000100000000000: n92 = n91;
      15'b000010000000000: n92 = n91;
      15'b000001000000000: n92 = n91;
      15'b000000100000000: n92 = n91;
      15'b000000010000000: n92 = n91;
      15'b000000001000000: n92 = n91;
      15'b000000000100000: n92 = n91;
      15'b000000000010000: n92 = n91;
      15'b000000000001000: n92 = n43;
      15'b000000000000100: n92 = n91;
      15'b000000000000010: n92 = n91;
      15'b000000000000001: n92 = n91;
      default: n92 = n91;
    endcase
  /*# scc_wave2.vhd:158:12 */
  assign n93 = reg_freq_ch_c[7:0]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n94 = n93;
      15'b010000000000000: n94 = n93;
      15'b001000000000000: n94 = n93;
      15'b000100000000000: n94 = n93;
      15'b000010000000000: n94 = n93;
      15'b000001000000000: n94 = n93;
      15'b000000100000000: n94 = n93;
      15'b000000010000000: n94 = n93;
      15'b000000001000000: n94 = n93;
      15'b000000000100000: n94 = n93;
      15'b000000000010000: n94 = dbo;
      15'b000000000001000: n94 = n93;
      15'b000000000000100: n94 = n93;
      15'b000000000000010: n94 = n93;
      15'b000000000000001: n94 = n93;
      default: n94 = n93;
    endcase
  /*# scc_wave2.vhd:158:12 */
  assign n95 = reg_freq_ch_c[11:8]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n96 = n95;
      15'b010000000000000: n96 = n95;
      15'b001000000000000: n96 = n95;
      15'b000100000000000: n96 = n95;
      15'b000010000000000: n96 = n95;
      15'b000001000000000: n96 = n95;
      15'b000000100000000: n96 = n95;
      15'b000000010000000: n96 = n95;
      15'b000000001000000: n96 = n95;
      15'b000000000100000: n96 = n50;
      15'b000000000010000: n96 = n95;
      15'b000000000001000: n96 = n95;
      15'b000000000000100: n96 = n95;
      15'b000000000000010: n96 = n95;
      15'b000000000000001: n96 = n95;
      default: n96 = n95;
    endcase
  /*# scc_wave2.vhd:159:12 */
  assign n97 = reg_freq_ch_d[7:0]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n98 = n97;
      15'b010000000000000: n98 = n97;
      15'b001000000000000: n98 = n97;
      15'b000100000000000: n98 = n97;
      15'b000010000000000: n98 = n97;
      15'b000001000000000: n98 = n97;
      15'b000000100000000: n98 = n97;
      15'b000000010000000: n98 = n97;
      15'b000000001000000: n98 = dbo;
      15'b000000000100000: n98 = n97;
      15'b000000000010000: n98 = n97;
      15'b000000000001000: n98 = n97;
      15'b000000000000100: n98 = n97;
      15'b000000000000010: n98 = n97;
      15'b000000000000001: n98 = n97;
      default: n98 = n97;
    endcase
  /*# scc_wave2.vhd:159:12 */
  assign n99 = reg_freq_ch_d[11:8]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n100 = n99;
      15'b010000000000000: n100 = n99;
      15'b001000000000000: n100 = n99;
      15'b000100000000000: n100 = n99;
      15'b000010000000000: n100 = n99;
      15'b000001000000000: n100 = n99;
      15'b000000100000000: n100 = n99;
      15'b000000010000000: n100 = n57;
      15'b000000001000000: n100 = n99;
      15'b000000000100000: n100 = n99;
      15'b000000000010000: n100 = n99;
      15'b000000000001000: n100 = n99;
      15'b000000000000100: n100 = n99;
      15'b000000000000010: n100 = n99;
      15'b000000000000001: n100 = n99;
      default: n100 = n99;
    endcase
  /*# scc_wave2.vhd:160:12 */
  assign n101 = reg_freq_ch_e[7:0]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n102 = n101;
      15'b010000000000000: n102 = n101;
      15'b001000000000000: n102 = n101;
      15'b000100000000000: n102 = n101;
      15'b000010000000000: n102 = n101;
      15'b000001000000000: n102 = n101;
      15'b000000100000000: n102 = dbo;
      15'b000000010000000: n102 = n101;
      15'b000000001000000: n102 = n101;
      15'b000000000100000: n102 = n101;
      15'b000000000010000: n102 = n101;
      15'b000000000001000: n102 = n101;
      15'b000000000000100: n102 = n101;
      15'b000000000000010: n102 = n101;
      15'b000000000000001: n102 = n101;
      default: n102 = n101;
    endcase
  /*# scc_wave2.vhd:160:12 */
  assign n103 = reg_freq_ch_e[11:8]; // extract
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n104 = n103;
      15'b010000000000000: n104 = n103;
      15'b001000000000000: n104 = n103;
      15'b000100000000000: n104 = n103;
      15'b000010000000000: n104 = n103;
      15'b000001000000000: n104 = n64;
      15'b000000100000000: n104 = n103;
      15'b000000010000000: n104 = n103;
      15'b000000001000000: n104 = n103;
      15'b000000000100000: n104 = n103;
      15'b000000000010000: n104 = n103;
      15'b000000000001000: n104 = n103;
      15'b000000000000100: n104 = n103;
      15'b000000000000010: n104 = n103;
      15'b000000000000001: n104 = n103;
      default: n104 = n103;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n105 = reg_vol_ch_a;
      15'b010000000000000: n105 = reg_vol_ch_a;
      15'b001000000000000: n105 = reg_vol_ch_a;
      15'b000100000000000: n105 = reg_vol_ch_a;
      15'b000010000000000: n105 = n68;
      15'b000001000000000: n105 = reg_vol_ch_a;
      15'b000000100000000: n105 = reg_vol_ch_a;
      15'b000000010000000: n105 = reg_vol_ch_a;
      15'b000000001000000: n105 = reg_vol_ch_a;
      15'b000000000100000: n105 = reg_vol_ch_a;
      15'b000000000010000: n105 = reg_vol_ch_a;
      15'b000000000001000: n105 = reg_vol_ch_a;
      15'b000000000000100: n105 = reg_vol_ch_a;
      15'b000000000000010: n105 = reg_vol_ch_a;
      15'b000000000000001: n105 = reg_vol_ch_a;
      default: n105 = reg_vol_ch_a;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n106 = reg_vol_ch_b;
      15'b010000000000000: n106 = reg_vol_ch_b;
      15'b001000000000000: n106 = reg_vol_ch_b;
      15'b000100000000000: n106 = n71;
      15'b000010000000000: n106 = reg_vol_ch_b;
      15'b000001000000000: n106 = reg_vol_ch_b;
      15'b000000100000000: n106 = reg_vol_ch_b;
      15'b000000010000000: n106 = reg_vol_ch_b;
      15'b000000001000000: n106 = reg_vol_ch_b;
      15'b000000000100000: n106 = reg_vol_ch_b;
      15'b000000000010000: n106 = reg_vol_ch_b;
      15'b000000000001000: n106 = reg_vol_ch_b;
      15'b000000000000100: n106 = reg_vol_ch_b;
      15'b000000000000010: n106 = reg_vol_ch_b;
      15'b000000000000001: n106 = reg_vol_ch_b;
      default: n106 = reg_vol_ch_b;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n107 = reg_vol_ch_c;
      15'b010000000000000: n107 = reg_vol_ch_c;
      15'b001000000000000: n107 = n74;
      15'b000100000000000: n107 = reg_vol_ch_c;
      15'b000010000000000: n107 = reg_vol_ch_c;
      15'b000001000000000: n107 = reg_vol_ch_c;
      15'b000000100000000: n107 = reg_vol_ch_c;
      15'b000000010000000: n107 = reg_vol_ch_c;
      15'b000000001000000: n107 = reg_vol_ch_c;
      15'b000000000100000: n107 = reg_vol_ch_c;
      15'b000000000010000: n107 = reg_vol_ch_c;
      15'b000000000001000: n107 = reg_vol_ch_c;
      15'b000000000000100: n107 = reg_vol_ch_c;
      15'b000000000000010: n107 = reg_vol_ch_c;
      15'b000000000000001: n107 = reg_vol_ch_c;
      default: n107 = reg_vol_ch_c;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n108 = reg_vol_ch_d;
      15'b010000000000000: n108 = n77;
      15'b001000000000000: n108 = reg_vol_ch_d;
      15'b000100000000000: n108 = reg_vol_ch_d;
      15'b000010000000000: n108 = reg_vol_ch_d;
      15'b000001000000000: n108 = reg_vol_ch_d;
      15'b000000100000000: n108 = reg_vol_ch_d;
      15'b000000010000000: n108 = reg_vol_ch_d;
      15'b000000001000000: n108 = reg_vol_ch_d;
      15'b000000000100000: n108 = reg_vol_ch_d;
      15'b000000000010000: n108 = reg_vol_ch_d;
      15'b000000000001000: n108 = reg_vol_ch_d;
      15'b000000000000100: n108 = reg_vol_ch_d;
      15'b000000000000010: n108 = reg_vol_ch_d;
      15'b000000000000001: n108 = reg_vol_ch_d;
      default: n108 = reg_vol_ch_d;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n109 = n80;
      15'b010000000000000: n109 = reg_vol_ch_e;
      15'b001000000000000: n109 = reg_vol_ch_e;
      15'b000100000000000: n109 = reg_vol_ch_e;
      15'b000010000000000: n109 = reg_vol_ch_e;
      15'b000001000000000: n109 = reg_vol_ch_e;
      15'b000000100000000: n109 = reg_vol_ch_e;
      15'b000000010000000: n109 = reg_vol_ch_e;
      15'b000000001000000: n109 = reg_vol_ch_e;
      15'b000000000100000: n109 = reg_vol_ch_e;
      15'b000000000010000: n109 = reg_vol_ch_e;
      15'b000000000001000: n109 = reg_vol_ch_e;
      15'b000000000000100: n109 = reg_vol_ch_e;
      15'b000000000000010: n109 = reg_vol_ch_e;
      15'b000000000000001: n109 = reg_vol_ch_e;
      default: n109 = reg_vol_ch_e;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n110 = reg_ch_sel;
      15'b010000000000000: n110 = reg_ch_sel;
      15'b001000000000000: n110 = reg_ch_sel;
      15'b000100000000000: n110 = reg_ch_sel;
      15'b000010000000000: n110 = reg_ch_sel;
      15'b000001000000000: n110 = reg_ch_sel;
      15'b000000100000000: n110 = reg_ch_sel;
      15'b000000010000000: n110 = reg_ch_sel;
      15'b000000001000000: n110 = reg_ch_sel;
      15'b000000000100000: n110 = reg_ch_sel;
      15'b000000000010000: n110 = reg_ch_sel;
      15'b000000000001000: n110 = reg_ch_sel;
      15'b000000000000100: n110 = reg_ch_sel;
      15'b000000000000010: n110 = reg_ch_sel;
      15'b000000000000001: n110 = reg_ch_sel;
      default: n110 = n83;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n111 = ff_rst_ch_a;
      15'b010000000000000: n111 = ff_rst_ch_a;
      15'b001000000000000: n111 = ff_rst_ch_a;
      15'b000100000000000: n111 = ff_rst_ch_a;
      15'b000010000000000: n111 = ff_rst_ch_a;
      15'b000001000000000: n111 = ff_rst_ch_a;
      15'b000000100000000: n111 = ff_rst_ch_a;
      15'b000000010000000: n111 = ff_rst_ch_a;
      15'b000000001000000: n111 = ff_rst_ch_a;
      15'b000000000100000: n111 = ff_rst_ch_a;
      15'b000000000010000: n111 = ff_rst_ch_a;
      15'b000000000001000: n111 = ff_rst_ch_a;
      15'b000000000000100: n111 = ff_rst_ch_a;
      15'b000000000000010: n111 = n37;
      15'b000000000000001: n111 = n33;
      default: n111 = ff_rst_ch_a;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n112 = ff_rst_ch_b;
      15'b010000000000000: n112 = ff_rst_ch_b;
      15'b001000000000000: n112 = ff_rst_ch_b;
      15'b000100000000000: n112 = ff_rst_ch_b;
      15'b000010000000000: n112 = ff_rst_ch_b;
      15'b000001000000000: n112 = ff_rst_ch_b;
      15'b000000100000000: n112 = ff_rst_ch_b;
      15'b000000010000000: n112 = ff_rst_ch_b;
      15'b000000001000000: n112 = ff_rst_ch_b;
      15'b000000000100000: n112 = ff_rst_ch_b;
      15'b000000000010000: n112 = ff_rst_ch_b;
      15'b000000000001000: n112 = n44;
      15'b000000000000100: n112 = n40;
      15'b000000000000010: n112 = ff_rst_ch_b;
      15'b000000000000001: n112 = ff_rst_ch_b;
      default: n112 = ff_rst_ch_b;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n113 = ff_rst_ch_c;
      15'b010000000000000: n113 = ff_rst_ch_c;
      15'b001000000000000: n113 = ff_rst_ch_c;
      15'b000100000000000: n113 = ff_rst_ch_c;
      15'b000010000000000: n113 = ff_rst_ch_c;
      15'b000001000000000: n113 = ff_rst_ch_c;
      15'b000000100000000: n113 = ff_rst_ch_c;
      15'b000000010000000: n113 = ff_rst_ch_c;
      15'b000000001000000: n113 = ff_rst_ch_c;
      15'b000000000100000: n113 = n51;
      15'b000000000010000: n113 = n47;
      15'b000000000001000: n113 = ff_rst_ch_c;
      15'b000000000000100: n113 = ff_rst_ch_c;
      15'b000000000000010: n113 = ff_rst_ch_c;
      15'b000000000000001: n113 = ff_rst_ch_c;
      default: n113 = ff_rst_ch_c;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n114 = ff_rst_ch_d;
      15'b010000000000000: n114 = ff_rst_ch_d;
      15'b001000000000000: n114 = ff_rst_ch_d;
      15'b000100000000000: n114 = ff_rst_ch_d;
      15'b000010000000000: n114 = ff_rst_ch_d;
      15'b000001000000000: n114 = ff_rst_ch_d;
      15'b000000100000000: n114 = ff_rst_ch_d;
      15'b000000010000000: n114 = n58;
      15'b000000001000000: n114 = n54;
      15'b000000000100000: n114 = ff_rst_ch_d;
      15'b000000000010000: n114 = ff_rst_ch_d;
      15'b000000000001000: n114 = ff_rst_ch_d;
      15'b000000000000100: n114 = ff_rst_ch_d;
      15'b000000000000010: n114 = ff_rst_ch_d;
      15'b000000000000001: n114 = ff_rst_ch_d;
      default: n114 = ff_rst_ch_d;
    endcase
  /*# scc_wave2.vhd:240:17 */
  always @*
    case (n84)
      15'b100000000000000: n115 = ff_rst_ch_e;
      15'b010000000000000: n115 = ff_rst_ch_e;
      15'b001000000000000: n115 = ff_rst_ch_e;
      15'b000100000000000: n115 = ff_rst_ch_e;
      15'b000010000000000: n115 = ff_rst_ch_e;
      15'b000001000000000: n115 = n65;
      15'b000000100000000: n115 = n61;
      15'b000000010000000: n115 = ff_rst_ch_e;
      15'b000000001000000: n115 = ff_rst_ch_e;
      15'b000000000100000: n115 = ff_rst_ch_e;
      15'b000000000010000: n115 = ff_rst_ch_e;
      15'b000000000001000: n115 = ff_rst_ch_e;
      15'b000000000000100: n115 = ff_rst_ch_e;
      15'b000000000000010: n115 = ff_rst_ch_e;
      15'b000000000000001: n115 = ff_rst_ch_e;
      default: n115 = ff_rst_ch_e;
    endcase
  /*# scc_wave2.vhd:258:13 */
  assign n117 = clkena ? 1'b0 : ff_rst_ch_a;
  /*# scc_wave2.vhd:258:13 */
  assign n119 = clkena ? 1'b0 : ff_rst_ch_b;
  /*# scc_wave2.vhd:258:13 */
  assign n121 = clkena ? 1'b0 : ff_rst_ch_c;
  /*# scc_wave2.vhd:258:13 */
  assign n123 = clkena ? 1'b0 : ff_rst_ch_d;
  /*# scc_wave2.vhd:258:13 */
  assign n125 = clkena ? 1'b0 : ff_rst_ch_e;
  /*# scc_wave2.vhd:237:13 */
  assign n126 = {n88, n86};
  /*# scc_wave2.vhd:237:13 */
  assign n128 = {n92, n90};
  /*# scc_wave2.vhd:237:13 */
  assign n130 = {n96, n94};
  /*# scc_wave2.vhd:237:13 */
  assign n132 = {n100, n98};
  /*# scc_wave2.vhd:237:13 */
  assign n134 = {n104, n102};
  /*# scc_wave2.vhd:237:13 */
  assign n142 = n31 ? n111 : n117;
  /*# scc_wave2.vhd:237:13 */
  assign n143 = n31 ? n112 : n119;
  /*# scc_wave2.vhd:237:13 */
  assign n144 = n31 ? n113 : n121;
  /*# scc_wave2.vhd:237:13 */
  assign n145 = n31 ? n114 : n123;
  /*# scc_wave2.vhd:237:13 */
  assign n146 = n31 ? n115 : n125;
  /*# scc_wave2.vhd:267:27 */
  assign n147 = wrt & req;
  /*# scc_wave2.vhd:267:48 */
  assign n148 = adr[7:5]; // extract
  /*# scc_wave2.vhd:267:61 */
  assign n150 = n148 == 3'b110;
  /*# scc_wave2.vhd:267:41 */
  assign n151 = n150 & n147;
  /*# scc_wave2.vhd:276:55 */
  assign n209 = ~ff_req_dl;
  /*# scc_wave2.vhd:276:41 */
  assign n210 = n209 & req;
  /*# scc_wave2.vhd:276:25 */
  assign n211 = n210 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:277:55 */
  assign n213 = ~ff_req_dl;
  /*# scc_wave2.vhd:277:41 */
  assign n214 = n213 & req;
  /*# scc_wave2.vhd:277:25 */
  assign n215 = n214 ? wrt : 1'b0;
  /*# scc_wave2.vhd:281:44 */
  assign n219 = reg_vol_ch_a != 4'b0000;
  /*# scc_wave2.vhd:281:24 */
  assign n220 = n219 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:282:42 */
  assign n224 = reg_ch_sel != 5'b00000;
  /*# scc_wave2.vhd:282:24 */
  assign n225 = n224 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:283:45 */
  assign n229 = reg_freq_ch_a != 12'b000000000000;
  /*# scc_wave2.vhd:283:24 */
  assign n230 = n229 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:289:31 */
  assign n232 = ff_ptr_ch_a[0]; // extract
  /*# scc_wave2.vhd:301:30 */
  assign n233 = ff_ch_num[0]; // extract
  /*# scc_wave2.vhd:302:39 */
  assign n236 = ff_mix != 15'b000000000000000;
  /*# scc_wave2.vhd:302:25 */
  assign n237 = n236 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:308:18 */
  always @*
    n239_ff_cnt_ch_a = n739; // (isignal)
  initial
    n239_ff_cnt_ch_a = 12'bX;
  /*# scc_wave2.vhd:309:18 */
  always @*
    n239_ff_cnt_ch_b = n741; // (isignal)
  initial
    n239_ff_cnt_ch_b = 12'bX;
  /*# scc_wave2.vhd:310:18 */
  always @*
    n239_ff_cnt_ch_c = n743; // (isignal)
  initial
    n239_ff_cnt_ch_c = 12'bX;
  /*# scc_wave2.vhd:311:18 */
  always @*
    n239_ff_cnt_ch_d = n745; // (isignal)
  initial
    n239_ff_cnt_ch_d = 12'bX;
  /*# scc_wave2.vhd:312:18 */
  always @*
    n239_ff_cnt_ch_e = n747; // (isignal)
  initial
    n239_ff_cnt_ch_e = 12'bX;
  /*# scc_wave2.vhd:329:34 */
  assign n247 = reg_freq_ch_a[11:3]; // extract
  /*# scc_wave2.vhd:329:48 */
  assign n249 = n247 == 9'b000000000;
  /*# scc_wave2.vhd:329:62 */
  assign n250 = n249 | ff_rst_ch_a;
  /*# scc_wave2.vhd:332:36 */
  assign n252 = n239_ff_cnt_ch_a == 12'b000000000000;
  /*# scc_wave2.vhd:333:48 */
  assign n254 = ff_ptr_ch_a + 5'b00001;
  /*# scc_wave2.vhd:336:48 */
  assign n256 = n239_ff_cnt_ch_a - 12'b000000000001;
  /*# scc_wave2.vhd:332:17 */
  assign n257 = n252 ? n254 : ff_ptr_ch_a;
  /*# scc_wave2.vhd:332:17 */
  assign n258 = n252 ? reg_freq_ch_a : n256;
  /*# scc_wave2.vhd:329:17 */
  assign n260 = n250 ? 5'b00000 : n257;
  /*# scc_wave2.vhd:329:17 */
  assign n261 = n250 ? reg_freq_ch_a : n258;
  /*# scc_wave2.vhd:339:34 */
  assign n262 = reg_freq_ch_b[11:3]; // extract
  /*# scc_wave2.vhd:339:48 */
  assign n264 = n262 == 9'b000000000;
  /*# scc_wave2.vhd:339:62 */
  assign n265 = n264 | ff_rst_ch_b;
  /*# scc_wave2.vhd:342:36 */
  assign n267 = n239_ff_cnt_ch_b == 12'b000000000000;
  /*# scc_wave2.vhd:343:48 */
  assign n269 = ff_ptr_ch_b + 5'b00001;
  /*# scc_wave2.vhd:346:48 */
  assign n271 = n239_ff_cnt_ch_b - 12'b000000000001;
  /*# scc_wave2.vhd:342:17 */
  assign n272 = n267 ? n269 : ff_ptr_ch_b;
  /*# scc_wave2.vhd:342:17 */
  assign n273 = n267 ? reg_freq_ch_b : n271;
  /*# scc_wave2.vhd:339:17 */
  assign n275 = n265 ? 5'b00000 : n272;
  /*# scc_wave2.vhd:339:17 */
  assign n276 = n265 ? reg_freq_ch_b : n273;
  /*# scc_wave2.vhd:349:34 */
  assign n277 = reg_freq_ch_c[11:3]; // extract
  /*# scc_wave2.vhd:349:48 */
  assign n279 = n277 == 9'b000000000;
  /*# scc_wave2.vhd:349:62 */
  assign n280 = n279 | ff_rst_ch_c;
  /*# scc_wave2.vhd:352:36 */
  assign n282 = n239_ff_cnt_ch_c == 12'b000000000000;
  /*# scc_wave2.vhd:353:48 */
  assign n284 = ff_ptr_ch_c + 5'b00001;
  /*# scc_wave2.vhd:356:48 */
  assign n286 = n239_ff_cnt_ch_c - 12'b000000000001;
  /*# scc_wave2.vhd:352:17 */
  assign n287 = n282 ? n284 : ff_ptr_ch_c;
  /*# scc_wave2.vhd:352:17 */
  assign n288 = n282 ? reg_freq_ch_c : n286;
  /*# scc_wave2.vhd:349:17 */
  assign n290 = n280 ? 5'b00000 : n287;
  /*# scc_wave2.vhd:349:17 */
  assign n291 = n280 ? reg_freq_ch_c : n288;
  /*# scc_wave2.vhd:359:34 */
  assign n292 = reg_freq_ch_d[11:3]; // extract
  /*# scc_wave2.vhd:359:48 */
  assign n294 = n292 == 9'b000000000;
  /*# scc_wave2.vhd:359:62 */
  assign n295 = n294 | ff_rst_ch_d;
  /*# scc_wave2.vhd:362:36 */
  assign n297 = n239_ff_cnt_ch_d == 12'b000000000000;
  /*# scc_wave2.vhd:363:48 */
  assign n299 = ff_ptr_ch_d + 5'b00001;
  /*# scc_wave2.vhd:366:48 */
  assign n301 = n239_ff_cnt_ch_d - 12'b000000000001;
  /*# scc_wave2.vhd:362:17 */
  assign n302 = n297 ? n299 : ff_ptr_ch_d;
  /*# scc_wave2.vhd:362:17 */
  assign n303 = n297 ? reg_freq_ch_d : n301;
  /*# scc_wave2.vhd:359:17 */
  assign n305 = n295 ? 5'b00000 : n302;
  /*# scc_wave2.vhd:359:17 */
  assign n306 = n295 ? reg_freq_ch_d : n303;
  /*# scc_wave2.vhd:369:34 */
  assign n307 = reg_freq_ch_e[11:3]; // extract
  /*# scc_wave2.vhd:369:48 */
  assign n309 = n307 == 9'b000000000;
  /*# scc_wave2.vhd:369:62 */
  assign n310 = n309 | ff_rst_ch_e;
  /*# scc_wave2.vhd:372:36 */
  assign n312 = n239_ff_cnt_ch_e == 12'b000000000000;
  /*# scc_wave2.vhd:373:48 */
  assign n314 = ff_ptr_ch_e + 5'b00001;
  /*# scc_wave2.vhd:376:48 */
  assign n316 = n239_ff_cnt_ch_e - 12'b000000000001;
  /*# scc_wave2.vhd:372:17 */
  assign n317 = n312 ? n314 : ff_ptr_ch_e;
  /*# scc_wave2.vhd:372:17 */
  assign n318 = n312 ? reg_freq_ch_e : n316;
  /*# scc_wave2.vhd:369:17 */
  assign n320 = n310 ? 5'b00000 : n317;
  /*# scc_wave2.vhd:369:17 */
  assign n321 = n310 ? reg_freq_ch_e : n318;
  /*# scc_wave2.vhd:386:41 */
  assign n363 = w_wave_ce ? adr : n368;
  /*# scc_wave2.vhd:387:24 */
  assign n365 = {3'b000, ff_ptr_ch_a};
  /*# scc_wave2.vhd:387:57 */
  assign n367 = ff_ch_num == 3'b000;
  /*# scc_wave2.vhd:386:66 */
  assign n368 = n367 ? n365 : n373;
  /*# scc_wave2.vhd:388:24 */
  assign n370 = {3'b001, ff_ptr_ch_b};
  /*# scc_wave2.vhd:388:57 */
  assign n372 = ff_ch_num == 3'b001;
  /*# scc_wave2.vhd:387:66 */
  assign n373 = n372 ? n370 : n378;
  /*# scc_wave2.vhd:389:24 */
  assign n375 = {3'b010, ff_ptr_ch_c};
  /*# scc_wave2.vhd:389:57 */
  assign n377 = ff_ch_num == 3'b010;
  /*# scc_wave2.vhd:388:66 */
  assign n378 = n377 ? n375 : n383;
  /*# scc_wave2.vhd:390:24 */
  assign n380 = {3'b011, ff_ptr_ch_d};
  /*# scc_wave2.vhd:390:57 */
  assign n382 = ff_ch_num == 3'b011;
  /*# scc_wave2.vhd:389:66 */
  assign n383 = n382 ? n380 : n386;
  /*# scc_wave2.vhd:391:24 */
  assign n385 = {3'b100, ff_ptr_ch_e};
  /*# scc_wave2.vhd:390:66 */
  assign n386 = sccplus ? n385 : n388;
  /*# scc_wave2.vhd:392:24 */
  assign n388 = {3'b011, ff_ptr_ch_e};
  /*# scc_wave2.vhd:394:5 */
  ram_Brtl wavemem (
    .adr(w_wave_adr),
    .clk(clk21m),
    .we(w_wave_we),
    .dbo(dbo),
    .dbi(wavemem_n389));
  /*# scc_wave2.vhd:438:17 */
  assign n418 = ff_ch_num_dl == 3'b001;
  /*# scc_wave2.vhd:439:17 */
  assign n421 = ff_ch_num_dl == 3'b010;
  /*# scc_wave2.vhd:440:17 */
  assign n424 = ff_ch_num_dl == 3'b011;
  /*# scc_wave2.vhd:441:17 */
  assign n427 = ff_ch_num_dl == 3'b100;
  /*# scc_wave2.vhd:442:17 */
  assign n430 = ff_ch_num_dl == 3'b101;
  /*# scc_wave2.vhd:437:5 */
  assign n432 = {n430, n427, n424, n421, n418};
  /*# scc_wave2.vhd:437:5 */
  always @*
    case (n432)
      5'b10000: n433 = 5'b10000;
      5'b01000: n433 = 5'b01000;
      5'b00100: n433 = 5'b00100;
      5'b00010: n433 = 5'b00010;
      5'b00001: n433 = 5'b00001;
      default: n433 = 5'b00000;
    endcase
  /*# scc_wave2.vhd:445:30 */
  assign n434 = w_ch_dec[0]; // extract
  /*# scc_wave2.vhd:445:48 */
  assign n435 = reg_ch_sel[0]; // extract
  /*# scc_wave2.vhd:445:34 */
  assign n436 = n434 & n435;
  /*# scc_wave2.vhd:446:30 */
  assign n437 = w_ch_dec[1]; // extract
  /*# scc_wave2.vhd:446:48 */
  assign n438 = reg_ch_sel[1]; // extract
  /*# scc_wave2.vhd:446:34 */
  assign n439 = n437 & n438;
  /*# scc_wave2.vhd:445:53 */
  assign n440 = n436 | n439;
  /*# scc_wave2.vhd:447:30 */
  assign n441 = w_ch_dec[2]; // extract
  /*# scc_wave2.vhd:447:48 */
  assign n442 = reg_ch_sel[2]; // extract
  /*# scc_wave2.vhd:447:34 */
  assign n443 = n441 & n442;
  /*# scc_wave2.vhd:446:53 */
  assign n444 = n440 | n443;
  /*# scc_wave2.vhd:448:30 */
  assign n445 = w_ch_dec[3]; // extract
  /*# scc_wave2.vhd:448:48 */
  assign n446 = reg_ch_sel[3]; // extract
  /*# scc_wave2.vhd:448:34 */
  assign n447 = n445 & n446;
  /*# scc_wave2.vhd:447:53 */
  assign n448 = n444 | n447;
  /*# scc_wave2.vhd:449:30 */
  assign n449 = w_ch_dec[4]; // extract
  /*# scc_wave2.vhd:449:48 */
  assign n450 = reg_ch_sel[4]; // extract
  /*# scc_wave2.vhd:449:34 */
  assign n451 = n449 & n450;
  /*# scc_wave2.vhd:448:53 */
  assign n452 = n448 | n451;
  /*# scc_wave2.vhd:451:21 */
  assign n453 = {w_ch_bit, w_ch_bit, w_ch_bit, w_ch_bit, w_ch_bit, w_ch_bit, w_ch_bit, w_ch_bit};
  /*# scc_wave2.vhd:454:29 */
  assign n455 = ff_ch_num_dl == 3'b001;
  /*# scc_wave2.vhd:455:29 */
  assign n457 = ff_ch_num_dl == 3'b010;
  /*# scc_wave2.vhd:456:29 */
  assign n459 = ff_ch_num_dl == 3'b011;
  /*# scc_wave2.vhd:457:29 */
  assign n461 = ff_ch_num_dl == 3'b100;
  /*# scc_wave2.vhd:458:29 */
  assign n463 = ff_ch_num_dl == 3'b101;
  /*# scc_wave2.vhd:453:5 */
  assign n465 = {n463, n461, n459, n457, n455};
  /*# scc_wave2.vhd:453:5 */
  always @*
    case (n465)
      5'b10000: n466 = reg_vol_ch_e;
      5'b01000: n466 = reg_vol_ch_d;
      5'b00100: n466 = reg_vol_ch_c;
      5'b00010: n466 = reg_vol_ch_b;
      5'b00001: n466 = reg_vol_ch_a;
      default: n466 = 4'b0000;
    endcase
  /*# scc_wave2.vhd:461:28 */
  assign n467 = w_ch_mask & ff_wave_dat;
  /*# scc_wave2.vhd:471:48 */
  assign n469 = {1'b0, w_ch_vol};
  /*# scc_wave2.vhd:471:35 */
  assign n470 = {{5{w_wave[7]}}, w_wave}; // sext
  /*# scc_wave2.vhd:471:35 */
  assign n471 = {{8{n469[4]}}, n469}; // sext
  /*# scc_wave2.vhd:471:35 */
  assign n472 = $signed(n470) * $signed(n471); // smul
  /*# scc_wave2.vhd:472:44 */
  assign n473 = w_mul_s[11:0]; // extract
  /*# scc_wave2.vhd:479:14 */
  assign n476 = ff_ch_num_dl == 3'b001;
  /*# scc_wave2.vhd:480:14 */
  assign n479 = ff_ch_num_dl == 3'b010;
  /*# scc_wave2.vhd:481:14 */
  assign n482 = ff_ch_num_dl == 3'b011;
  /*# scc_wave2.vhd:482:14 */
  assign n485 = ff_ch_num_dl == 3'b100;
  /*# scc_wave2.vhd:483:14 */
  assign n488 = ff_ch_num_dl == 3'b101;
  /*# scc_wave2.vhd:478:5 */
  assign n490 = {n488, n485, n482, n479, n476};
  /*# scc_wave2.vhd:478:5 */
  always @*
    case (n490)
      5'b10000: n491 = 2'b01;
      5'b01000: n491 = 2'b11;
      5'b00100: n491 = 2'b10;
      5'b00010: n491 = 2'b01;
      5'b00001: n491 = 2'b11;
      default: n491 = 2'b10;
    endcase
  /*# scc_wave2.vhd:485:44 */
  assign n492 = ~pan_mirror;
  /*# scc_wave2.vhd:485:27 */
  assign n493 = n492 ? w_wl_n : n498;
  /*# scc_wave2.vhd:485:64 */
  assign n494 = w_wl_n[1]; // extract
  /*# scc_wave2.vhd:485:78 */
  assign n495 = w_wl_n[0]; // extract
  /*# scc_wave2.vhd:485:68 */
  assign n496 = n494 ^ n495;
  /*# scc_wave2.vhd:485:91 */
  assign n497 = w_wl_n[0]; // extract
  /*# scc_wave2.vhd:485:83 */
  assign n498 = {n496, n497};
  /*# scc_wave2.vhd:486:26 */
  assign n499 = w_wl[1]; // extract
  /*# scc_wave2.vhd:486:38 */
  assign n500 = w_wl[0]; // extract
  /*# scc_wave2.vhd:486:30 */
  assign n501 = n499 ^ n500;
  /*# scc_wave2.vhd:486:49 */
  assign n502 = w_wl[0]; // extract
  /*# scc_wave2.vhd:486:43 */
  assign n503 = {n501, n502};
  /*# scc_wave2.vhd:487:25 */
  assign n504 = w_mul[11]; // extract
  /*# scc_wave2.vhd:487:37 */
  assign n505 = w_mul[11]; // extract
  /*# scc_wave2.vhd:487:30 */
  assign n506 = {n504, n505};
  /*# scc_wave2.vhd:487:42 */
  assign n507 = {n506, w_mul};
  /*# scc_wave2.vhd:488:25 */
  assign n508 = w_mul[11]; // extract
  /*# scc_wave2.vhd:488:30 */
  assign n509 = {n508, w_mul};
  /*# scc_wave2.vhd:488:38 */
  assign n511 = {n509, 1'b0};
  /*# scc_wave2.vhd:489:25 */
  assign n512 = w_m1 + w_m2;
  /*# scc_wave2.vhd:490:36 */
  assign n514 = w_wl == 2'b11;
  /*# scc_wave2.vhd:490:25 */
  assign n515 = n514 ? w_m3 : n518;
  /*# scc_wave2.vhd:490:65 */
  assign n517 = w_wl == 2'b10;
  /*# scc_wave2.vhd:490:44 */
  assign n518 = n517 ? w_m2 : w_m1;
  /*# scc_wave2.vhd:491:36 */
  assign n520 = w_wr == 2'b11;
  /*# scc_wave2.vhd:491:25 */
  assign n521 = n520 ? w_m3 : n524;
  /*# scc_wave2.vhd:491:65 */
  assign n523 = w_wr == 2'b10;
  /*# scc_wave2.vhd:491:44 */
  assign n524 = n523 ? w_m2 : w_m1;
  /*# scc_wave2.vhd:534:28 */
  assign n528 = ~ff_wave_ce;
  /*# scc_wave2.vhd:535:31 */
  assign n530 = ff_ch_num == 3'b101;
  /*# scc_wave2.vhd:538:44 */
  assign n532 = ff_ch_num + 3'b001;
  /*# scc_wave2.vhd:535:17 */
  assign n534 = n530 ? 3'b000 : n532;
  /*# scc_wave2.vhd:563:31 */
  assign n543 = ~ff_wave_ce_dl;
  /*# scc_wave2.vhd:564:34 */
  assign n545 = ff_ch_num_dl == 3'b001;
  /*# scc_wave2.vhd:565:39 */
  assign n546 = w_mul[11]; // extract
  /*# scc_wave2.vhd:565:51 */
  assign n547 = w_mul[11]; // extract
  /*# scc_wave2.vhd:565:44 */
  assign n548 = {n546, n547};
  /*# scc_wave2.vhd:565:63 */
  assign n549 = w_mul[11]; // extract
  /*# scc_wave2.vhd:565:56 */
  assign n550 = {n548, n549};
  /*# scc_wave2.vhd:565:68 */
  assign n551 = {n550, w_mul};
  /*# scc_wave2.vhd:566:37 */
  assign n553 = ff_ch_num_dl != 3'b000;
  /*# scc_wave2.vhd:567:39 */
  assign n554 = w_mul[11]; // extract
  /*# scc_wave2.vhd:567:51 */
  assign n555 = w_mul[11]; // extract
  /*# scc_wave2.vhd:567:44 */
  assign n556 = {n554, n555};
  /*# scc_wave2.vhd:567:63 */
  assign n557 = w_mul[11]; // extract
  /*# scc_wave2.vhd:567:56 */
  assign n558 = {n556, n557};
  /*# scc_wave2.vhd:567:68 */
  assign n559 = {n558, w_mul};
  /*# scc_wave2.vhd:567:77 */
  assign n560 = n559 + ff_mix;
  /*# scc_wave2.vhd:566:17 */
  assign n561 = n553 ? n560 : ff_mix;
  /*# scc_wave2.vhd:564:17 */
  assign n562 = n545 ? n551 : n561;
  /*# scc_wave2.vhd:584:30 */
  assign n572 = ff_ch_num_dl == 3'b101;
  /*# scc_wave2.vhd:585:28 */
  assign n574 = ff_mix != 15'b000000000000000;
  /*# scc_wave2.vhd:585:17 */
  assign n577 = n574 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:604:31 */
  assign n586 = ~ff_wave_ce_dl;
  /*# scc_wave2.vhd:605:34 */
  assign n588 = ff_ch_num_dl == 3'b001;
  /*# scc_wave2.vhd:606:38 */
  assign n589 = w_pl[13]; // extract
  /*# scc_wave2.vhd:606:49 */
  assign n590 = w_pl[13]; // extract
  /*# scc_wave2.vhd:606:43 */
  assign n591 = {n589, n590};
  /*# scc_wave2.vhd:606:60 */
  assign n592 = w_pl[13]; // extract
  /*# scc_wave2.vhd:606:54 */
  assign n593 = {n591, n592};
  /*# scc_wave2.vhd:606:65 */
  assign n594 = {n593, w_pl};
  /*# scc_wave2.vhd:607:38 */
  assign n595 = w_pr[13]; // extract
  /*# scc_wave2.vhd:607:49 */
  assign n596 = w_pr[13]; // extract
  /*# scc_wave2.vhd:607:43 */
  assign n597 = {n595, n596};
  /*# scc_wave2.vhd:607:60 */
  assign n598 = w_pr[13]; // extract
  /*# scc_wave2.vhd:607:54 */
  assign n599 = {n597, n598};
  /*# scc_wave2.vhd:607:65 */
  assign n600 = {n599, w_pr};
  /*# scc_wave2.vhd:608:37 */
  assign n602 = ff_ch_num_dl != 3'b000;
  /*# scc_wave2.vhd:609:38 */
  assign n603 = w_pl[13]; // extract
  /*# scc_wave2.vhd:609:49 */
  assign n604 = w_pl[13]; // extract
  /*# scc_wave2.vhd:609:43 */
  assign n605 = {n603, n604};
  /*# scc_wave2.vhd:609:60 */
  assign n606 = w_pl[13]; // extract
  /*# scc_wave2.vhd:609:54 */
  assign n607 = {n605, n606};
  /*# scc_wave2.vhd:609:65 */
  assign n608 = {n607, w_pl};
  /*# scc_wave2.vhd:609:73 */
  assign n609 = n608 + ff_mix_l;
  /*# scc_wave2.vhd:610:38 */
  assign n610 = w_pr[13]; // extract
  /*# scc_wave2.vhd:610:49 */
  assign n611 = w_pr[13]; // extract
  /*# scc_wave2.vhd:610:43 */
  assign n612 = {n610, n611};
  /*# scc_wave2.vhd:610:60 */
  assign n613 = w_pr[13]; // extract
  /*# scc_wave2.vhd:610:54 */
  assign n614 = {n612, n613};
  /*# scc_wave2.vhd:610:65 */
  assign n615 = {n614, w_pr};
  /*# scc_wave2.vhd:610:73 */
  assign n616 = n615 + ff_mix_r;
  /*# scc_wave2.vhd:608:17 */
  assign n617 = n602 ? n609 : ff_mix_l;
  /*# scc_wave2.vhd:608:17 */
  assign n618 = n602 ? n616 : ff_mix_r;
  /*# scc_wave2.vhd:605:17 */
  assign n619 = n588 ? n594 : n617;
  /*# scc_wave2.vhd:605:17 */
  assign n620 = n588 ? n600 : n618;
  /*# scc_wave2.vhd:638:30 */
  assign n634 = ff_ch_num_dl == 3'b000;
  /*# scc_wave2.vhd:640:44 */
  assign n635 = ff_mix_l[16:2]; // extract
  /*# scc_wave2.vhd:641:44 */
  assign n636 = ff_mix_r[16:2]; // extract
  /*# scc_wave2.vhd:642:36 */
  assign n637 = ~ff_wavlatch_tgl;
  /*# scc_wave2.vhd:647:28 */
  assign n639 = ff_mix != 15'b000000000000000;
  /*# scc_wave2.vhd:647:17 */
  assign n642 = n639 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:663:40 */
  assign n666 = ff_wave != 15'b000000000000000;
  /*# scc_wave2.vhd:663:25 */
  assign n667 = n666 ? 1'b1 : 1'b0;
  /*# scc_wave2.vhd:408:9 */
  assign n672 = ff_wave_ce ? ram_dbi : n673;
  /*# scc_wave2.vhd:408:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n673 <= 8'b11111111;
    else
      n673 <= n672;
  /*# scc_wave2.vhd:235:9 */
  assign n674 = n31 ? n126 : reg_freq_ch_a;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n675 <= 12'b000000000000;
    else
      n675 <= n674;
  /*# scc_wave2.vhd:235:9 */
  assign n676 = n31 ? n128 : reg_freq_ch_b;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n677 <= 12'b000000000000;
    else
      n677 <= n676;
  /*# scc_wave2.vhd:235:9 */
  assign n678 = n31 ? n130 : reg_freq_ch_c;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n679 <= 12'b000000000000;
    else
      n679 <= n678;
  /*# scc_wave2.vhd:235:9 */
  assign n680 = n31 ? n132 : reg_freq_ch_d;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n681 <= 12'b000000000000;
    else
      n681 <= n680;
  /*# scc_wave2.vhd:235:9 */
  assign n682 = n31 ? n134 : reg_freq_ch_e;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n683 <= 12'b000000000000;
    else
      n683 <= n682;
  /*# scc_wave2.vhd:235:9 */
  assign n684 = n31 ? n105 : reg_vol_ch_a;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n685 <= 4'b0000;
    else
      n685 <= n684;
  /*# scc_wave2.vhd:235:9 */
  assign n686 = n31 ? n106 : reg_vol_ch_b;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n687 <= 4'b0000;
    else
      n687 <= n686;
  /*# scc_wave2.vhd:235:9 */
  assign n688 = n31 ? n107 : reg_vol_ch_c;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n689 <= 4'b0000;
    else
      n689 <= n688;
  /*# scc_wave2.vhd:235:9 */
  assign n690 = n31 ? n108 : reg_vol_ch_d;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n691 <= 4'b0000;
    else
      n691 <= n690;
  /*# scc_wave2.vhd:235:9 */
  assign n692 = n31 ? n109 : reg_vol_ch_e;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n693 <= 4'b0000;
    else
      n693 <= n692;
  /*# scc_wave2.vhd:235:9 */
  assign n694 = n31 ? n110 : reg_ch_sel;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n695 <= 5'b00000;
    else
      n695 <= n694;
  /*# scc_wave2.vhd:235:9 */
  assign n696 = n151 ? dbo : reg_mode_sel;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n697 <= 8'b00000000;
    else
      n697 <= n696;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n698 <= 1'b0;
    else
      n698 <= n142;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n699 <= 1'b0;
    else
      n699 <= n143;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n700 <= 1'b0;
    else
      n700 <= n144;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n701 <= 1'b0;
    else
      n701 <= n145;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n702 <= 1'b0;
    else
      n702 <= n146;
  /*# scc_wave2.vhd:326:9 */
  assign n703 = clkena ? n260 : ff_ptr_ch_a;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n704 <= 5'b00000;
    else
      n704 <= n703;
  /*# scc_wave2.vhd:326:9 */
  assign n705 = clkena ? n275 : ff_ptr_ch_b;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n706 <= 5'b00000;
    else
      n706 <= n705;
  /*# scc_wave2.vhd:326:9 */
  assign n707 = clkena ? n290 : ff_ptr_ch_c;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n708 <= 5'b00000;
    else
      n708 <= n707;
  /*# scc_wave2.vhd:326:9 */
  assign n709 = clkena ? n305 : ff_ptr_ch_d;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n710 <= 5'b00000;
    else
      n710 <= n709;
  /*# scc_wave2.vhd:326:9 */
  assign n711 = clkena ? n320 : ff_ptr_ch_e;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n712 <= 5'b00000;
    else
      n712 <= n711;
  /*# scc_wave2.vhd:533:9 */
  assign n713 = n528 ? n534 : ff_ch_num;
  /*# scc_wave2.vhd:533:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n714 <= 3'b000;
    else
      n714 <= n713;
  /*# scc_wave2.vhd:426:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n715 <= 3'b000;
    else
      n715 <= ff_ch_num;
  /*# scc_wave2.vhd:562:9 */
  assign n716 = n543 ? n562 : ff_mix;
  /*# scc_wave2.vhd:562:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n717 <= 15'b000000000000000;
    else
      n717 <= n716;
  /*# scc_wave2.vhd:426:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n718 <= 1'b0;
    else
      n718 <= w_wave_ce;
  /*# scc_wave2.vhd:426:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n719 <= 1'b0;
    else
      n719 <= ff_wave_ce;
  /*# scc_wave2.vhd:235:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n720 <= 1'b0;
    else
      n720 <= req;
  /*# scc_wave2.vhd:426:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n721 <= 8'b00000000;
    else
      n721 <= ram_dbi;
  /*# scc_wave2.vhd:637:9 */
  assign n722 = n634 ? ff_mix : ff_wave;
  /*# scc_wave2.vhd:637:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n723 <= 15'b000000000000000;
    else
      n723 <= n722;
  /*# scc_wave2.vhd:637:9 */
  assign n724 = n634 ? n637 : ff_wavlatch_tgl;
  /*# scc_wave2.vhd:637:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n725 <= 1'b0;
    else
      n725 <= n724;
  /*# scc_wave2.vhd:637:9 */
  assign n726 = n634 ? n642 : ff_capnz;
  /*# scc_wave2.vhd:637:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n727 <= 1'b0;
    else
      n727 <= n726;
  /*# scc_wave2.vhd:583:9 */
  assign n728 = n572 ? n577 : ff_mix5_nz;
  /*# scc_wave2.vhd:583:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n729 <= 1'b0;
    else
      n729 <= n728;
  /*# scc_wave2.vhd:603:9 */
  assign n730 = n586 ? n619 : ff_mix_l;
  /*# scc_wave2.vhd:603:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n731 <= 17'b00000000000000000;
    else
      n731 <= n730;
  /*# scc_wave2.vhd:603:9 */
  assign n732 = n586 ? n620 : ff_mix_r;
  /*# scc_wave2.vhd:603:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n733 <= 17'b00000000000000000;
    else
      n733 <= n732;
  /*# scc_wave2.vhd:637:9 */
  assign n734 = n634 ? n635 : ff_wave_l;
  /*# scc_wave2.vhd:637:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n735 <= 15'b000000000000000;
    else
      n735 <= n734;
  /*# scc_wave2.vhd:637:9 */
  assign n736 = n634 ? n636 : ff_wave_r;
  /*# scc_wave2.vhd:637:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n737 <= 15'b000000000000000;
    else
      n737 <= n736;
  /*# scc_wave2.vhd:326:9 */
  assign n738 = clkena ? n261 : n239_ff_cnt_ch_a;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n739 <= 12'b000000000000;
    else
      n739 <= n738;
  /*# scc_wave2.vhd:326:9 */
  assign n740 = clkena ? n276 : n239_ff_cnt_ch_b;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n741 <= 12'b000000000000;
    else
      n741 <= n740;
  /*# scc_wave2.vhd:326:9 */
  assign n742 = clkena ? n291 : n239_ff_cnt_ch_c;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n743 <= 12'b000000000000;
    else
      n743 <= n742;
  /*# scc_wave2.vhd:326:9 */
  assign n744 = clkena ? n306 : n239_ff_cnt_ch_d;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n745 <= 12'b000000000000;
    else
      n745 <= n744;
  /*# scc_wave2.vhd:326:9 */
  assign n746 = clkena ? n321 : n239_ff_cnt_ch_e;
  /*# scc_wave2.vhd:326:9 */
  always @(posedge clk21m or posedge reset)
    if (reset)
      n747 <= 12'b000000000000;
    else
      n747 <= n746;
endmodule

