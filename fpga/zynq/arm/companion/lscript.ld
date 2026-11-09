/* lscript.ld — proxy de SD en la DDR baja del PS (0x00100000, 4 MB), lejos de
 * la VRAM (0x10000000), la RAM del Z80 (0x10800000), la imagen (0x11000000)
 * y los buzones (0x1FF00000). */
ENTRY(_start)
MEMORY {
    ddr (rwx) : ORIGIN = 0x00100000, LENGTH = 0x00400000
    mp3 (rw)  : ORIGIN = 0x00500000, LENGTH = 0x00100000   /* 23/09: zona con cache del MP3 (mmu.c) */
    net (rw)  : ORIGIN = 0x00600000, LENGTH = 0x00400000   /* 25/09: lwIP (heap, pools) + descriptores del GEM0 (net.c la pone a cero) */
    tls (rw)  : ORIGIN = 0x00A00000, LENGTH = 0x00400000   /* 26/09: heap de Mbed TLS (esp_tls.c): CON cache (mmu.c), sin DMA */
}
SECTIONS
{
    .vectors : { KEEP(*(.vectors)) } > ddr
    .text    : { *(.text*) *(.rodata*) *(.glue_7) *(.glue_7t) } > ddr
    /* 23/09 (mmu.c): TODO lo que va antes de __rw_start (codigo, constantes, .ARM.exidx) es de solo lectura
     * y tiene cache; .data empieza en una pagina nueva de 4 KB para que ninguna variable caiga en esas paginas. */
    .data    : ALIGN(4096) { __rw_start = .; *(.data*) } > ddr
    .netbss (NOLOAD) : { __net_start = .; */xemacpsif_dma.o(.bss* COMMON) */mem.o(.bss*) */memp.o(.bss*) */xpqueue.o(.bss*) . = ALIGN(4); __net_end = .; } > net
    .bss (NOLOAD) : { __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ddr
    .stack (NOLOAD) : { . = ALIGN(16); . = . + 0x10000; __stack_top = .; } > ddr   /* 26/09: 64 KB (ECDSA/RSA de Mbed TLS) */
    .mp3 (NOLOAD)   : { *(.mp3*) } > mp3                /* mp3.c: sin cargar ni poner a cero (lo inicializa mp3_open) */
    .tls (NOLOAD)   : { *(.tlsheap*) } > tls                /* esp_tls.c: el asignador de Mbed TLS lo gobierna (no hace falta a cero) */
}
