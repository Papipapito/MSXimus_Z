/* start.S — arranque minimo del Cortex-A9 (core 0) para el proxy de SD.
 * Lo carga xsdb (dow sdproxy.elf; con) con la DDR ya entrenada por ps7_init.
 *   1. SCTLR: MMU, D-cache, I-cache y predictor fuera (la demo de fabrica pudo
 *      dejarlos activos): toda la memoria pasa a ser strongly-ordered, coherente
 *      con el PL (buzon) y con el DMA del SDIO sin mantenimiento de cache.
 *   2. tabla de vectores propia (VBAR): cualquier excepcion se queda en un bucle
 *      con su numero en r0 (leible con xsdb: rrd pc / r0).
 *   3. pila, .bss a cero, main().
 *   23/09: FPU/NEON encendida (CPACR + FPEXC) para el MP3 (mp3.c, softfp): el resto del companion es
 *   soft-float y no la toca. mmu.c enciende luego la MMU SIN cambiar nada de lo anterior: todo lo que
 *   era strongly-ordered lo sigue siendo; solo el codigo y la zona del MP3 pasan a tener cache.       */
    .syntax unified
    .arm
    .fpu neon
    .section .vectors, "ax"
    .global _vector_table
_vector_table:
    b   _start
    b   ex_undef
    b   ex_svc
    b   ex_pabt
    b   ex_dabt
    b   .
    b   ex_irq
    b   ex_fiq
ex_undef: mov r0, #1
          b .
ex_svc:   mov r0, #2
          b .
ex_pabt:  mov r0, #3
          b .
ex_dabt:  mov r0, #4
          b .
ex_irq:   mov r0, #6
          b .
ex_fiq:   mov r0, #7
          b .

    .text
    .global _start
_start:
    cpsid   if                          /* sin interrupciones */
    mrc     p15, 0, r0, c1, c0, 0       /* SCTLR */
    bic     r0, r0, #0x1                /* M: MMU off */
    bic     r0, r0, #0x4                /* C: D-cache off */
    bic     r0, r0, #0x1000             /* I: I-cache off */
    bic     r0, r0, #0x800              /* Z: branch predictor off */
    bic     r0, r0, #0x2000             /* V: vectores en VBAR (no en 0xFFFF0000) */
    mcr     p15, 0, r0, c1, c0, 0
    mov     r0, #0
    mcr     p15, 0, r0, c7, c5, 0       /* invalidar I-cache */
    mcr     p15, 0, r0, c7, c5, 6       /* invalidar predictor */
    dsb
    isb
    ldr     r0, =_vector_table
    mcr     p15, 0, r0, c12, c0, 0      /* VBAR */
    /* FPU/NEON: cp10 y cp11 con acceso completo, FPEXC.EN = 1 (lo usa solo mp3.c) */
    mrc     p15, 0, r0, c1, c0, 2       /* CPACR */
    orr     r0, r0, #(0xF << 20)
    mcr     p15, 0, r0, c1, c0, 2
    isb
    mov     r0, #0x40000000
    vmsr    fpexc, r0
    cps     #0x13                       /* modo SVC */
    ldr     sp, =__stack_top
    /* .bss a cero */
    ldr     r0, =__bss_start
    ldr     r1, =__bss_end
    mov     r2, #0
1:  cmp     r0, r1
    strlo   r2, [r0], #4
    blo     1b
    bl      main
2:  b       2b

/* ---- utilidades para mmu.c y mp3.c (23/09) ---- */
    .global dcache_inval_all
dcache_inval_all:                       /* L1 D del A9: 32 KB, 4 vias, lineas de 32 B = 256 conjuntos */
    mov     r0, #0
3:  mov     r1, #0
4:  lsl     r2, r1, #30
    orr     r2, r2, r0, lsl #5
    mcr     p15, 0, r2, c7, c6, 2       /* DCISW: invalidar por conjunto/via */
    add     r1, r1, #1
    cmp     r1, #4
    blo     4b
    add     r0, r0, #1
    cmp     r0, #256
    blo     3b
    dsb
    bx      lr

    .global mmu_enable                  /* r0 = tabla de primer nivel (16 KB alineada) */
mmu_enable:
    mov     r1, #0
    mcr     p15, 0, r1, c2, c0, 2       /* TTBCR = 0: solo TTBR0 */
    mcr     p15, 0, r0, c2, c0, 0       /* TTBR0 (recorridos de la tabla sin cache) */
    mvn     r1, #0
    mcr     p15, 0, r1, c3, c0, 0       /* DACR: manager en todos los dominios */
    mov     r1, #0
    mcr     p15, 0, r1, c8, c7, 0       /* invalidar TLB */
    mcr     p15, 0, r1, c7, c5, 0       /* invalidar I-cache */
    mcr     p15, 0, r1, c7, c5, 6       /* invalidar predictor */
    dsb
    isb
    mrc     p15, 0, r1, c1, c0, 0
    orr     r1, r1, #0x1                /* M: MMU */
    orr     r1, r1, #0x4                /* C: D-cache (solo actua en las paginas normales) */
    orr     r1, r1, #0x1000             /* I: I-cache */
    orr     r1, r1, #0x800              /* Z: predictor */
    mcr     p15, 0, r1, c1, c0, 0
    dsb
    isb
    bx      lr

/* int call_on_stack(void *arg, int (*fn)(void *), void *sp_top): llama a fn(arg) con otra pila. El
 * descodificador MP3 pone ~16 KB de trabajo en la pila y hace memcpy desalineados: sobre la pila normal
 * del companion (strongly-ordered) eso es DATA ABORT; la suya vive en la zona con cache (.mp3). */
    .global call_on_stack
call_on_stack:
    push    {r4, lr}
    mov     r4, sp
    mov     sp, r2
    blx     r1
    mov     sp, r4
    pop     {r4, pc}
