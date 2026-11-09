// ============================================================================
// v9990_cpu_glue.v — Adaptador del bus I/O del T80 (clk_54m, senales estilo
// Z80: csw_n/csr_n activos bajo durante el ciclo I/O de los puertos 60h-6Fh)
// al puerto CPU del tiny9990 (clk_86): CSR_n/CSW_n de NIVEL con detector de
// flanco interno (t9990_port.sv: det_w/det_r = prev && !CS), MODE[3:0],
// CD_IN/CD_OUT y su WAIT_n.
//
// Hereda el diseno de v9968_cpu_glue.v (lecciones _91/_177: todo registrado,
// nada combinacional cruzando dominios, nivel+served en vez de flanco, wait
// gateado al ciclo I/O y timeout fail-open):
//  - csw_n/csr_n se sincronizan con 2FF a clk_86; el NIVEL bajo con `served`
//    limpio presenta UNA vez por ciclo I/O el chip-select al T9990 (que ve el
//    flanco de bajada) con MODE y CD_IN latcheados (cuasi-estaticos en el T80).
//  - Cronologia (ciclos de clk_86 desde la presentacion, `settle`):
//      0: t_cs_n <= 0            1: el T9990 ve det_r/det_w
//      2: CD_OUT valido (P#2/3/5/6, R#n) o WAIT_n bajado (P#0 VRAM, P#1 paleta)
//    Lecturas: cdi_r se captura cuando settle >= 2 y t_wait_n == 1 (para P#0/P#1
//    el T9990 sube WAIT_n en el MISMO flanco en que actualiza CD_OUT, asi que
//    un ciclo despues el dato ya esta). Escrituras P#0/P#1: se retiene al Z80
//    mientras el T9990 tenga WAIT_n bajo (como el chip real).
//  - El chip-select se mantiene bajo hasta que el T80 acaba el ciclo (ambos cs
//    altos): el T9990 solo mira el flanco, y el siguiente ciclo I/O trae otro.
//  - wait_n va gateado al ciclo I/O (fuera de el, alto) y con TIMEOUT fail-open
//    de 2^12 ciclos (~47.7 us): si el T9990 no soltara WAIT_n, se libera al Z80
//    con dato rancio antes que colgar el MSX.
//
// Parte del MSXimus Z. Copyright (C) 2026 Papipapito. GPL-3.0-or-later.
// ============================================================================
module v9990_cpu_glue (
    input  wire       clk_86,        // 85.909 MHz (dominio del T9990)
    input  wire       rst_n,

    // lado T80 (top: decode 60h-6Fh con IORQ/M1/RD/WR, patron vdp_csw_n)
    input  wire       csw_n,         // escritura, activo bajo
    input  wire       csr_n,         // lectura, activo bajo
    input  wire [3:0] mode,          // bus_addr[3:0]: P#0..P#15 del V9990
    input  wire [7:0] cdo,           // dato del T80 (escrituras)
    output reg  [7:0] cdi_r,         // dato al T80 (lecturas, estable)
    output wire       wait_n,        // retener al Z80 (activo bajo)

    // lado T9990
    output reg        t_csr_n,
    output reg        t_csw_n,
    output reg  [3:0] t_mode,
    output reg  [7:0] t_cd_in,
    input  wire [7:0] t_cd_out,
    input  wire       t_wait_n
);
    // sync 2FF de los chip-selects (3 etapas: la 0 absorbe la metaestabilidad)
`ifdef TR_V9990
    (* ASYNC_REG = "TRUE" *) reg [2:0] csw_s = 3'b111;
    (* ASYNC_REG = "TRUE" *) reg [2:0] csr_s = 3'b111;
`else
    reg [2:0] csw_s = 3'b111;
    reg [2:0] csr_s = 3'b111;
`endif
    always @( posedge clk_86 ) begin
        csw_s <= { csw_s[1:0], csw_n };
        csr_s <= { csr_s[1:0], csr_n };
    end
    wire io_wr = (csw_s[1] == 1'b0);
    wire io_rd = (csr_s[1] == 1'b0);
    wire io_any = io_wr || io_rd;

    reg        served  = 1'b0;   // ya presentado al T9990 en este ciclo I/O
    reg        rd_pend = 1'b0;   // lectura en vuelo: cdi_r aun sin el dato
    reg  [1:0] settle  = 2'd0;   // ciclos desde la presentacion (satura en 3)
    reg  [1:0] idle_cnt = 2'd0;  // muestras seguidas sin ciclo I/O (satura en 3)

    // timeout fail-open (como el glue del V9968, _184: 2^12 ciclos)
    reg [12:0] wtmo = 13'd0;
    wire wtmo_hit = wtmo[12];

    always @( posedge clk_86 ) begin
        if( !rst_n ) begin
            t_csr_n <= 1'b1;
            t_csw_n <= 1'b1;
            t_mode  <= 4'd0;
            t_cd_in <= 8'd0;
            served  <= 1'b0;
            rd_pend <= 1'b0;
            settle  <= 2'd0;
            idle_cnt <= 2'd0;
        end
        else begin
            if( io_any && !served ) begin
                // addr/dato llevan >= 2 ciclos de 85.9 estables (viajaron con
                // el propio cs): latch directo y chip-select de nivel
                t_mode  <= mode;
                t_cd_in <= cdo;
                t_csw_n <= ~io_wr;
                t_csr_n <= ~(io_rd && !io_wr);
                served  <= 1'b1;
                rd_pend <= io_rd && !io_wr;
                settle  <= 2'd0;
            end
            else if( served && settle != 2'd3 ) begin
                settle <= settle + 2'd1;
            end
            else if( !served ) begin
                settle <= 2'd0;                      // en reposo, listo para la siguiente presentacion
            end
            // captura del dato de lectura: T9990 sin WAIT y ya procesado el flanco
            if( rd_pend && served && settle >= 2'd2 && t_wait_n ) begin
                cdi_r   <= t_cd_out;
                rd_pend <= 1'b0;
            end
            if( wtmo_hit ) rd_pend <= 1'b0;          // fail-open
            // fin del ciclo I/O del T80: se suelta el chip-select a la primera muestra
            // inactiva, pero `served` solo se rearma tras 3 seguidas (18/10, como el
            // "event guard" del tiny V9990 de GNF): un hueco espurio de 1-2 muestras
            // (rebote del cs) ni presenta otra vez el acceso ni suelta el WAIT
            // (wait_cause, abajo, sigue vivo mientras served = 1).
            if( io_any ) idle_cnt <= 2'd0;
            else if( idle_cnt != 2'd3 ) idle_cnt <= idle_cnt + 2'd1;
            if( !io_any ) begin
                t_csr_n <= 1'b1;
                t_csw_n <= 1'b1;
                if( idle_cnt >= 2'd2 ) served <= 1'b0;   // 3a muestra inactiva seguida
            end
        end
    end

    // wait activo (bajo) SOLO durante un ciclo I/O al V9990 con trabajo
    // pendiente: sin presentar, recien presentado (el T9990 aun no ha podido
    // bajar su WAIT_n), lectura sin dato, o WAIT_n del T9990 bajo (P#0/P#1).
    // 18/10: el ciclo sigue vivo hasta el rearme (io_any || served): un rebote del
    // cs no suelta al Z80 a mitad de acceso. En un ciclo normal el T80 solo suelta
    // RD/WR cuando ya no hay trabajo pendiente, asi que la cola de 3 muestras no
    // retiene nada. wait_n es combinacional y cruza a clk_54m (2FF en top): al
    // presentar cambian served y rd_pend pero io_any = 1 y settle = 0 (se pone a 0
    // en reposo) fijan wait_cause a 1, y el fin de ciclo y los rebotes cambian io_any
    // con served = 1. El rearme SI es un riesgo estatico de 0 (served && !served con
    // 7 entradas, 2 niveles de LUT): un glitch llegaria al WAIT_n del T80 unos
    // 40-125 ns tras subir el cs, y la primera muestra que el T80 usa (TState 2 del
    // M-ciclo siguiente) llega >= 2 T despues (>= 372 ns en turbo): inofensivo. Si
    // algun dia hiciera falta, registrar wait_n aqui (+1 ciclo de 86 de latencia).
    wire wait_cause = ( io_any || served ) && ( !served || settle < 2'd2 || rd_pend || !t_wait_n );
    always @( posedge clk_86 ) begin
        if( !rst_n )           wtmo <= 13'd0;
        else if( !wait_cause ) wtmo <= 13'd0;
        else if( !wtmo_hit )   wtmo <= wtmo + 13'd1;
    end
    assign wait_n = ~( wait_cause && !wtmo_hit );

    initial cdi_r = 8'hFF;
endmodule
