// config_pkg.sv — sustituto minimo del paquete CONFIG de tnCart (rtl/src/config.sv)
// para compilar el tiny9990 fuera de tnCart. El core solo consulta
// CONFIG::ENABLE_V9990_CMD (t9990_port.sv: CMD_START <= CONFIG::ENABLE_V9990_CMD),
// que habilita el motor de comandos (blitter). Lo demas del paquete original es
// del cartucho (flash, megarom, sonido) y aqui no pinta nada.
//
// Parte del MSXimus Z. tiny9990 es de Shinobu Hashimoto (BSD-3, LICENSE.tnCart).
`default_nettype none
package CONFIG;
    localparam DISABLE            = 0;
    localparam ENABLE             = 1;
    localparam ENABLE_V9990_CMD   = ENABLE;   // blitter del V9990 activo
endpackage
`default_nettype wire
