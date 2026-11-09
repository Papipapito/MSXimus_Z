//
//  opll_ikaopll.v — el YM2413 (MSX-MUSIC) con IKAOPLL detras de la MISMA interfaz que jt2413
//  (jtopl/jt2413.v), para cambiar de OPLL cambiando solo el nombre del modulo instanciado.
//
//  IKAOPLL: Raki (Sehyeon Kim), https://github.com/ika-musume/IKAOPLL (BSD-2, LICENSE en esta carpeta),
//  commit 4d39323 del 04/01/2025. Nucleo reconstruido de las fotos del dado del YM2413, exacto ciclo a
//  ciclo y con TODOS los bits del registro de test (0Fh): el PCM por el F-number de kokoro.rom solo
//  suena con el (jt2413 ignora el 0Fh). Envoltorio y arreglo de IKAOPLL_pg.v: Javier Abadia (proyecto
//  MSXasgard_tn20k, 18/08/2026). Adaptado al MSXimus Z el 23/09/2026.
//  14/10/2026 (Z1.2.8): mas los dos arreglos de upstream del 08/10/2026, a mano: 15b373b (IKAOPLL_eg.v, factor KSR del peso de
//  paso de la envolvente) y 56a582c (IKAOPLL_reg.v, SUSEN enmascarado en los moduladores apagados).
//
//   Interfaz jt2413  ->  IKAOPLL
//     rst  (activo alto) -> i_IC_n = ~rst
//     clk               -> i_XIN_EMUCLK         (reloj del sistema; en la Zynq, clk_54m)
//     cen  (3,58 MHz)   -> i_phiM_PCEN_n = ~cen (enable de phiM, logica negativa)
//     din/addr/cs_n/wr_n -> i_D/i_A0/i_CS_n/i_WR_n
//     snd  (con signo, 16 b) <- o_ACC_SIGNED    (acumulador y mezclador internos)
//     sample             <- o_ACC_SIGNED_STRB
//
//   Volumenes del mezclador interno (5 b con signo, maximo +15): cada canal vale +-255 y se multiplica por
//   ellos (IKAOPLL_dac.v). Los del README (+2 melodia, +3 ritmo) dejan el OPLL muy bajo; aqui van
//   calibrados contra jt2413 en simulacion para que el mezclador del MSXimus (medido contra openMSX) no
//   cambie de nivel.
//
module opll_ikaopll #(
    parameter signed [4:0] MOVOL = 5'sd15,          // volumen de la melodia
    parameter signed [4:0] ROVOL = 5'sd15,          // volumen del ritmo
    parameter              PIPELINED_MULT = 1       // 1 = multiplicador segmentado (Vivado); en Gowin, 0
)(
    input                rst,
    input                clk,
    input                cen,
    input         [ 7:0] din,
    input                addr,
    input                cs_n,
    input                wr_n,
    output signed [15:0] snd,
    output               sample,
    // estereo por canales (MSXimus Z, 23/09/2026; reparto en IKAOPLL_dac.v): snd_l + snd_r = snd
    output signed [15:0] snd_l,
    output signed [15:0] snd_r
);

    IKAOPLL #(
        .FULLY_SYNCHRONOUS        (1),              // solo biestables D
        .FAST_RESET               (1),              // el reset corre a ritmo de emuclk (18 ciclos de phiM)
        .ALTPATCH_CONFIG_MODE     (0),              // instrumentos del YM2413 (no los del VRC7)
        .USE_PIPELINED_MULTIPLIER (PIPELINED_MULT)
    ) u_ikaopll (
        .i_XIN_EMUCLK             (clk),
        .o_XOUT                   (),
        .i_phiM_PCEN_n            (~cen),
        .i_IC_n                   (~rst),
        .i_ALTPATCH_EN            (1'b0),
        .i_CS_n                   (cs_n),
        .i_WR_n                   (wr_n),
        .i_A0                     (addr),
        .i_D                      (din),
        .o_D                      (),               // el YM2413 no se lee en el MSX
        .o_D_OE                   (),
        .o_DAC_EN_MO              (),
        .o_DAC_EN_RO              (),
        .o_IMP_NOFLUC_SIGN        (),
        .o_IMP_NOFLUC_MAG         (),
        .o_IMP_FLUC_SIGNED_MO     (),
        .o_IMP_FLUC_SIGNED_RO     (),
        .i_ACC_SIGNED_MOVOL       (MOVOL),
        .i_ACC_SIGNED_ROVOL       (ROVOL),
        .o_ACC_SIGNED_STRB        (sample),
        .o_ACC_SIGNED             (snd),
        .o_ACC_SIGNED_L           (snd_l),
        .o_ACC_SIGNED_R           (snd_r)
    );

endmodule
