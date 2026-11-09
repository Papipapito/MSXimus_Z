# 03. Mapas de memoria

Tres mapas y cómo se relacionan: lo que ve el Z80 (slots y páginas), dónde vive cada cosa en la DDR3 del PS, y qué hay en la QSPI.

## 1. Lo que ve el Z80: slots y páginas

| Slot | Página 0 (0000-3FFF) | Página 1 (4000-7FFF) | Página 2 (8000-BFFF) | Página 3 (C000-FFFF) |
|---|---|---|---|---|
| 0-0 | BIOS | BASIC | | |
| 0-2 | | ROM UNAPI del ESP32 (WiFi) | | |
| 0-3 | | Logo de arranque | | |
| 1 | | Cartucho: la megaram con el mapper elegido, o el segundo SCC, o el Game Master 2 | | |
| 2 | | Megaram en modo SCC (donde el menú carga las ROMs) | | |
| 3-0 | RAM mapeada de 2 MB (registros FCh-FFh) | | | |
| 3-1 | SUB-ROM (MSX2+) | FM-BIOS (OPLL, 4000h-475Fh) y menú de 32 KB, página 1 (4760h-7050h) | Menú, página 2 | |
| 3-2 | SFG\* | Nextor: kernel de 128 KB en bancos de 16 KB + la ventana de la SD | El mismo banco de 16 KB | |
| 3-3 | | Megaram, cuando el menú la deja expandida en el slot 3 | | |

- \* **Solo en el perfil Música**: la Yamaha SFG-01 (YM2151), en la **página 0 del slot 3-2** (en el slot 0 no puede ir: el RDSLT de la BIOS no lee la página 0 de otro subslot del slot 0, y VGMPlay busca el SFG así). El chip está al final de la página (3FF0h registro del OPM, 3FF1h dato en escritura y estado en lectura con el bit 7 de «ocupado»; 3FF2h-3FF7h, el teclado y el MIDI del YM2148, no están y se leen FFh). Su ROM es **propia y mínima**, de 256 bytes en lógica del PL (no usa BRAM ni el pack): «MCHFM0» en 0080h, que es lo que busca VGMPlay, el nibble alto de 0088h a 0 (SFG-01) y FFh en el resto; no lleva cabecera «AB», así que la BIOS no la inicia. La ROM de Yamaha tiene copyright y no se redistribuye. El software que llama a su BIOS (la extensión de BASIC y los programas de Yamaha del CX5M) no funciona con esta ROM. En el perfil estándar la página 0 del slot 3-2 está vacía.
- **El menú corre desde ROM** como un cartucho de 32 KB en las páginas 1 y 2 del slot 3-1; la página 2 es la ventana 70000h del pack. Por eso el setup WiFi del ESP32, que necesita la página 2 como RAM, se lanza desde un stub en RAM de la página 3 (`bios/src/e7_rutinas.asm`).
- **Nextor** ocupa el slot 3-2: las páginas 1 y 2 ven el mismo banco de 16 KB del kernel de 128 KB, que se elige escribiendo en 6000h (3 bits). En la página 1 lleva además la ventana de la SD: 7C00h-7DFFh es el búfer de sector y 7E00h-7EFFh los registros del controlador (los mismos que la E/S conmutada 47h-4Fh). Al cargar una cinta el companion pide al PL que el slot 3-2 desaparezca (el BASIC arranca limpio, sin disco).
- **La megaram** son **8 MB** (segmentos 0-1023 de 8 KB). El bit 4 del puerto 46h elige para el cargador cuál de las mitades de 4 MB ve; el segmento 511 guarda el descriptor del guardado de SRAM y el 497 el del Game Master 2 ([manual, capítulo 05](../manual/05-roms-mappers.md)).

## 2. La DDR3 del PS

Toda la memoria del MSX vive en la DDR3 de **512 MB** del PS (direcciones 0x00000000 a 0x1FFFFFFF), detrás de los puertos AXI (capítulo 01, §4). El PL no ve la DDR «como memoria»: cada cliente tiene un backend con su caché.

### 2.1. Las regiones del PL

| Dirección | Tamaño | Contenido | Cliente |
|---|---|---|---|
| 0x0E000000 | 4 MB | Megaram, los 4 MB altos (segmentos 512-1023) | `memory_axi.v` (HP1) |
| 0x0F000000 | 2 MB | YRW801, la ROM de ondas del OPL4 | `wave_axi.v` (GP0), solo lectura |
| 0x0F200000 | 2 MB | RAM de muestras del OPL4 | `wave_axi.v` (GP0) |
| 0x10280000 | 256 KB | VRAM del V9968 | `v9968_axi_backend.v` (HP0) con shim y caché |
| 0x10300000 | 512 KB | VRAM del V9990 (el byte A de la VRAM va en la DDR en 2·A[17:0] + A[18]) | `v9990_vram_axi.v` (GP1), con caché |
| 0x10400000 | 3 × 1088 KB | Frame buffer del V9990 (3 slots de 480 líneas × 2304 B: hasta 1136 px por línea, B7, y los dos campos tejidos si hay entrelazado) | `v9990_fb.v` (GP1) |
| 0x0F800000 | 3 × 384 KB | Frame buffer del V9968 (V9991: la ventana del modo 2 y, desde el V9991f, también la pantalla completa de los modos 0 y 3): 3 slots de 240 × 1280 B. Hasta el 28/10 estaba en 0x10600000 | `v9990_fb.v` en `msx2hdmi_v9968.sv` (GP1) |
| 0x10800000 | 2 MB | RAM mapeada del Z80 (la página 3 y los segmentos del mapper) | `memory_axi.v` (HP1), caché de 64 KB |
| 0x10A00000 | 2 MB | Megaram, segmentos 256-511 (A21 = 1; ahí está también el Game Master 2) | `memory_axi.v` (HP1) |
| 0x10C00000 | 2 MB | Megaram, segmentos 0-255 (A21 = 0) | `memory_axi.v` (HP1) |
| 0x10F00000 | 512 KB | Pack de BIOS (capítulo 04); sus primeros 256 KB son la fuente kanji JIS1/JIS2 | `memory_axi.v` (HP1), solo lectura |
| 0x11000000 | 224 MB | Imagen de disco: solo en modo imagen, sin companion | `sd_axi_proxy.v` (HP3) |
| 0x1FF00000 | 8 KB | Buzón MBOX (+ registro del companion en +0x800, la palabra de reinicio del USB en +0xFF0 y volcado del trazador en +0x1000) | `dbg_mailbox_axi.v` (HP2) |
| 0x1FF00100 | 256 B | SDBOX: cola del proxy de SD (y palabras del companion, p. ej. el estado de TF1) | `sd_axi_proxy.v` y el companion |
| 0x1FF10000 | 64 KB | SDBUF: los sectores que sirve el companion | `sd_axi_proxy.v` y el companion |
| 0x1FF80000 | 64 KB | Anillo PCM del WaveGame (32 768 muestras de 16 bits) | `dbg_mailbox_axi.v` y el companion |
| 0x1FFA0000 | 64 KB | Anillo de pulsos de la cinta (16 384 entradas de 32 bits) | `dbg_mailbox_axi.v` y el companion |
| 0x1FFB0000 | 64 KB | Anillo ARM → V9990 del escritorio vivo (control en +0, 16 384 entradas de 16 bits desde +0x8000; capítulo 13) | `dbg_mailbox_axi.v` + `v9990_arm_port.v` y el companion (`v99desk.c`) |

La RAM del Z80 se indexa con un `ram_addr` de 24 bits que `memory_axi.v` traduce: con el bit 23 a 0 va a `RAM_BASE` (0x10800000, ventana de 8 MB) y con el bit 23 a 1 a `EXT_BASE` (0x0E000000). El núcleo reparte así los offsets (`top_zynq.v`):

| `ram_addr` | Contenido |
|---|---|
| 000000-1FFFFF | Mapper (2 MB) |
| 200000-3FFFFF | Megaram con A21 = 1 y Game Master 2 |
| 400000-5FFFFF | Megaram con A21 = 0 |
| 700000-73FFFF | Fuente kanji (pack 00000-3FFFF) |
| 740000-75FFFF | Kernel de Nextor, 128 KB (pack 40000) |
| 760000-76FFFF | BIOS de 32 KB (pack 60000), SUB-ROM de 16 KB (68000), FM-BIOS + logo + menú (6C000) |
| 770000-773FFF | Segunda página del menú (pack 70000) |
| 778000-77BFFF | ROM UNAPI del ESP32 (pack 78000) |
| 77C000-77FFFF | Logo de arranque (pack 7C000) |
| 800000-BFFFFF | Megaram con A22 = 1 (4 MB altos): en `EXT_BASE` |

### 2.2. Las regiones del companion

| Dirección | Tamaño | Contenido |
|---|---|---|
| 0x00100000 | 4 MB | Código, datos y pila del companion (`lscript.ld`) |
| 0x00500000 | 1 MB | Zona del MP3 (con caché) |
| 0x00600000 | 4 MB | Pools de lwIP y descriptores del GEM0 |
| 0x00A00000 | 4 MB | Heap de Mbed TLS (con caché) |
| 0x00E10000 | 256 B | `ota_info`, la identidad de esta imagen (la carga el `BOOT.bin`) |
| 0x01000000 | 9 MB | Zona de descarga de la actualización por red (con caché). Sin descarga en curso la usa `mxpf.c` como memoria de trabajo: contenido guardado en +0, rebote en +0x380000, tablas de zlib y SHA en +0x390000 y el `.bin` descomprimido en +0x400000 |
| 0x1F000000 | | Imagen de disquete de prueba (la deja `boot.tcl`) |
| 0x1F200000 | 1,44 MB | Caché del disquete USB |
| 0x1F400000 | 4 MB | Zona de la prueba de carga de un bitstream por PCAP (`profile.c`) y de los perfiles de la TF1 (`mxpf.c`); sin caché, por el DMA de la SD. Cabecera e informe de la prueba de PCAP en +0; órdenes de los perfiles en +0x100, su informe en +0x200 y su texto en +0x400; el `.bin` de la prueba, o el `.mxp`, en +0x1000; sectores de trabajo en +0x3F0000 (64 KB) |
| 0x1FE00000 | 1 MB | El fichero de cinta cargado |

Notas:

- **La RAM y la megaram son la misma caché**: `memory_axi.v` sirve aciertos en ~75 ns, con líneas de 16 B y 4096 líneas de mapeo directo (64 KB). La DMA de la SD escribe por el mismo camino. Las escrituras son write-through.
- **Las VRAM nacen a cero**: la DDR arranca con basura y todo lo que un juego no escribe se vería como ruido; `boot.tcl` y el companion limpian la del V9968 antes de soltar el MSX.
- **Nada sobrevive al apagado** en la DDR: el guardado de SRAM y del Game Master 2 va a la SD y la configuración a la QSPI.
- El `BOOT.bin` carga en la DDR el buzón a cero (0x1FF00000), el pack (0x10F00000), la YRW801 (0x0F000000) y `ota_info` (0x00E10000) antes de saltar al companion.

## 3. La QSPI: 16 MB (W25Q128)

| Dirección | Contenido |
|---|---|
| 0x000000 | Ranura A: el `BOOT.bin` de fábrica (~6,16 MB, siete particiones: FSBL, bitstream, companion, buzón a cero, pack, YRW801, `ota_info`) |
| 0x800000 | Ranura B: el `BOOT.bin` que baja la actualización por red (hasta 0x7F0000 B) |
| 0xFFE000 | Registro de la actualización (qué hay en la B y si ya arrancó bien) |
| 0xFFF000 | Bloque de ajustes «MSXC» (último sector de 4 KB): config1, config2, turbo de arranque, ganancia, suma, y los niveles del mezclador con su suma; opciones de vídeo en los bytes 14 y 15 |

El detalle de las ranuras y del registro está en el [capítulo 11](11-actualizacion.md). El bloque de ajustes lo lee `qspi_cfg.c` al arrancar y lo pone en MBOX+0x1C y +0x24 con el bit de válido antes de soltar el MSX; el PL siembra los registros de configuración con él. Al pulsar «Save & Restart» el PL saca el bloque vigente por +0x70 y +0xC0 con un toggle y el companion borra y regraba el sector. Un bloque con config1 = 0 (o sin la magia) se rechaza y valen los defectos del core (menú al arrancar, scanlines apagadas, ganancia x5, mezclador a 8/8). `tools/qspi_program.tcl` graba solo el rango del `BOOT.bin`, así que el bloque de ajustes sobrevive a una regrabación.

## 4. Dónde mirar

- Regiones de la DDR y la caché: `fpga/zynq/memory_axi.v` (cabecera), y el mapa de `ram_addr` en `fpga/zynq/top_zynq.v`.
- El buzón, palabra a palabra: `fpga/zynq/dbg_mailbox_axi.v` y el [capítulo 01](01-arquitectura.md).
- Las regiones del companion: `fpga/zynq/arm/companion/lscript.ld` y `mmu.c` ([capítulo 12](12-companion.md)).
- El `BOOT.bin`: `fpga/zynq/arm/boot/make_boot.sh`.
- El bloque de ajustes de la QSPI: `fpga/zynq/arm/companion/qspi_cfg.c`.
