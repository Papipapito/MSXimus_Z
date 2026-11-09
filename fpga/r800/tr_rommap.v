// tr_rommap.v — lecturas de ROM / DRAM del mapa de slots del FS-A1ST (perfil TR, fase 2)
//
// El firmware del turbo R (fs-a1st_firmware.rom, 4 MB, lo pone el usuario) esta en la DDR en 0x0E400000, es decir en
// ram_addr C00000-FFFFFF (bit 23 = zona EXT de memory_axi). La RAM del perfil son 2 MB (mapper 000000-1FFFFF; el FS-A1ST lleva 256 KB) y sus
// ULTIMOS 64 KB (1F0000-1FFFFF) son la "DRAM" donde el BIOS se copia a si mismo: con el modo DRAM de la S1990 (R#6 bit 6 = 0)
// las lecturas de la BIOS y la SUB-ROM salen de ahi en lugar de la ROM (y esa zona de la RAM pasa a solo lectura: lo hace el top).
//
//   slot  paginas      contenido                         firmware     modo DRAM
//   0-0   0000-7FFF    BIOS + BASIC 4.0 (bloques 40-43)  050000       RAM 030000
//   0-2   4000-7FFF    MSX-MUSIC (bloques 62-63)         07C000
//   0-3   4000-7FFF    apertura "turbo R" (bloques 36-37) 048000
//   3-1   0000-3FFF    SUB-ROM (bloques 56-57)           070000       RAM 038000
//   3-1   4000-7FFF    driver kanji + BASIC 1 (58-59)    074000       RAM 03C000
//   3-1   8000-BFFF    driver kanji + BASIC 1 (60-61)    078000
//
// (los "bloques" son de 8 KB, como en la maquina FS-A1ST de openMSX). El resto (3-0 RAM, 3-2 disco = Nextor, 3-3) lo sirve el top.
// Registrado en clk como el resto de decodificadores de slot del top: req/addr llegan 1 ciclo despues del strobe.
`default_nettype none
module tr_rommap (
    input  wire        clk,
    input  wire        tr_map,
    input  wire        dram_mode,
    input  wire        mreq_n,
    input  wire        rd_n,
    input  wire        rfsh_n,
    input  wire [15:0] a,
    input  wire        s0,             // slot primario 0 seleccionado para esta pagina
    input  wire        s3,             // slot primario 3 (el expandido de la RAM)
    input  wire [3:0]  e0,             // subslot activo del slot 0 (one-hot)
    input  wire [3:0]  e3,             // subslot activo del slot 3 (one-hot)
    output reg         req,
    output reg  [23:0] addr,
    output reg         ovr,            // 04/11: con req, la lectura devuelve ovd en vez del dato de la DDR
    output reg  [7:0]  ovd
);
    wire [1:0] pg = a[15:14];
    initial begin req = 1'b0; addr = 24'd0; ovr = 1'b0; ovd = 8'h00; end
    always @(posedge clk) begin
        req <= 1'b0;
        // la ventana del menu lleva en 4018h-401Fh la firma "APRLOPLL" del FM-BIOS: en el 0-1 se lee 00h para que quien la busque encuentre el MSX-MUSIC del 0-2
        ovr <= 1'b0;  ovd <= 8'h00;
        if (tr_map && s0 && e0[1] && pg == 2'b01 && a[13:3] == 11'd3) ovr <= 1'b1;   // 00h
        // La ROM del ESP espera cuadros con HALT en su INIT (49B5h). En el 3-3 la BIOS la llama despues del INIT de Nextor, con DI: el HALT no acababa nunca.
        // Su INIT (4002h) se desvia a un stub en el relleno de la ROM (C9h de 6850h a 7FDFh): 7000h EI / 7001h JP 4010h. Solo en TR: el pack y el estandar no cambian.
        if (tr_map && s3 && e3[3] && pg == 2'b01) begin
            case (a[13:0])
            // Y dentro del INIT, 4034h: RST 30h + CHGMOD (slot 0) deja DI (como todo CALLF) y a continuacion viene el HALT. Mismos 4 bytes: CALL 005Fh + EI (medido: M1 49B8h fijo)
            14'h0034: begin ovr <= 1'b1; ovd <= 8'hCD; end
            14'h0035: begin ovr <= 1'b1; ovd <= 8'h5F; end
            14'h0036: begin ovr <= 1'b1; ovd <= 8'h00; end
            14'h0037: begin ovr <= 1'b1; ovd <= 8'hFB; end
            14'h0002: begin ovr <= 1'b1; ovd <= 8'h00; end
            14'h0003: begin ovr <= 1'b1; ovd <= 8'h70; end
            14'h3000: begin ovr <= 1'b1; ovd <= 8'hFB; end
            14'h3001: begin ovr <= 1'b1; ovd <= 8'hC3; end
            14'h3002: begin ovr <= 1'b1; ovd <= 8'h10; end
            14'h3003: begin ovr <= 1'b1; ovd <= 8'h40; end
            default: ;
            endcase
        end
        if (tr_map && mreq_n == 1'b0 && rd_n == 1'b0 && rfsh_n == 1'b1) begin
            if (s0 && e0[0] && !a[15]) begin
                req  <= 1'b1;
                addr <= dram_mode ? (24'h1F0000 | {9'd0, a[14:0]}) : (24'hC50000 | {9'd0, a[14:0]});
            end else if (s0 && e0[1] && (pg == 2'b01 || pg == 2'b10)) begin
                // 04/11 (menu del MSXimus con la BIOS del tR, doc 21): el 0-1 (vacio en el FS-A1ST) es el menu del pack, como cartucho "AB":
                // pagina 1 = ventana "fm + logo + boot menu" (pack 0x6C000, DDR 0x76C000), pagina 2 = 2a pagina del menu (pack 0x70000, DDR 0x770000)
                req  <= 1'b1;  addr <= (pg == 2'b01) ? (24'h76C000 | {10'd0, a[13:0]}) : (24'h770000 | {10'd0, a[13:0]});
            end else if (s0 && e0[2] && pg == 2'b01) begin
                req  <= 1'b1;  addr <= 24'hC7C000 | {10'd0, a[13:0]};
            end else if (s0 && e0[3] && pg == 2'b01) begin
                req  <= 1'b1;  addr <= 24'hC48000 | {10'd0, a[13:0]};
            end else if (s3 && e3[3] && pg == 2'b01) begin
                // 04/11 (doc 19): el 3-3 es la ROM del ESP (pack 0x78000, DDR 0x778000); FileHunter, WiFi y UNAPI. Antes, el firmware Panasonic
                req  <= 1'b1;  addr <= 24'h778000 | {10'd0, a[13:0]};
            end else if (s3 && e3[1] && pg != 2'b11) begin
                req  <= 1'b1;
                case (pg)
                2'b00:   addr <= dram_mode ? (24'h1F8000 | {10'd0, a[13:0]}) : (24'hC70000 | {10'd0, a[13:0]});
                2'b01:   addr <= dram_mode ? (24'h1FC000 | {10'd0, a[13:0]}) : (24'hC74000 | {10'd0, a[13:0]});
                default: addr <= 24'hC78000 | {10'd0, a[13:0]};
                endcase
            end
        end
    end
endmodule
`default_nettype wire
