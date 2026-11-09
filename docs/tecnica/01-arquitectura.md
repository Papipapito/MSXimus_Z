# 01. Arquitectura

Cómo está montado el MSXimus Z por dentro: qué corre en la lógica programable (PL), qué corre en el procesador (PS), por dónde se hablan y con qué relojes. Fuentes: `fpga/zynq/top_zynq.v` (el nivel superior), `fpga/top.v` (el núcleo común), `fpga/zynq/*.v`, `fpga/zynq/build.tcl` y `bd_ps7.tcl`, y `fpga/zynq/arm/companion/`.

## 1. La placa y el chip

La OMDAZZ ZYNQ MINI lleva un **XC7Z020-CLG400**, un Zynq-7000: en el mismo encapsulado hay un **PS** (dos Cortex-A9 a 666,67 MHz, con una DDR3 de **512 MB**: un chip de 4 Gbit y 16 bits a 533 MHz, DDR3-1066; QSPI de 16 MB, dos controladores de SD, USB, Ethernet, UART) y un **PL** (una FPGA de la familia Artix-7, 85 K celdas lógicas, 140 bloques de BRAM de 36 Kb, 220 DSP). Lo que en un MSX de FPGA clásico es «la FPGA y sus periféricos» aquí se reparte:

| Dónde | Qué |
|---|---|
| PL | El MSX entero: Z80, V9968, V9990, geo3d, PSG (dos), SCC (dos), OPLL, Y8950, OPL4, megaram, mappers, PPI, RTC, temporizador del S1990, UART del ESP32, HDMI, el mezclador de audio |
| PS | El **companion** ([capítulo 12](12-companion.md)): proxy de las tarjetas SD, USB host (teclado, mandos, ratón, disquetera), Ethernet (hace de «ESP32» UNAPI para el MSX), OLED, panel OSD (F12), ajustes en la QSPI, WaveGame y cinta, actualización por red |
| DDR3 del PS | La memoria del MSX: RAM del Z80, megaram, las dos VRAM, el frame buffer del V9990, el pack de BIOS, la ROM de ondas del OPL4, los buzones y anillos |

No hay memoria externa en el lado del PL: todo lo que necesita ancho de banda va por los puertos AXI del PS a la DDR3.

Periféricos del PS que usa el diseño (`bd_ps7.tcl`): QSPI (MIO 1-6), SD0 = TF1 (MIO 40-45), SD1 = TF2 (MIO 10-15), Ethernet GEM0 con un RTL8211E (MIO 16-27, MDIO en MIO 52-53), USB0 con PHY ULPI (MIO 28-39, reset en MIO 46), UART0 y UART1 por EMIO (hacia el PL) y 4 GPIO por EMIO para la OLED.

## 2. Diagrama de bloques

```
                        ┌──────────────────────── PS (Zynq) ───────────────────────┐
  teclado/mandos/ratón ─┤ USB0 ──┐                                                   │
  disquetera USB        │        ├─ companion (core 0, bare-metal)                   │
  TF1 / TF2 (SD0/SD1) ──┤ SD ────┤    OSD/F12 · OLED · QSPI · WaveGame · cinta ·     │
  cable de red ─────────┤ GEM0 ──┘    Ethernet→UNAPI · actualización por red         │
  QSPI 16 MB ───────────┤                                                           │
                        │      DDR3 512 MB  ◄── HP0 · HP1 · HP2 · HP3 · GP0 · GP1 ──┼──┐
                        └────────────────────────────────────────────────────────────┘  │
                                                                                         │ AXI
  ┌───────────────────────────────────── PL ───────────────────────────────────────────┴──────┐
  │  Z80 (T80/G80A) ── bus ──┬─ memory_axi ──────────── HP1  RAM del Z80, megaram, pack, kanji │
  │  3,58 / 5,37 MHz         ├─ V9968 (+ geo3d 9Dh/9Fh) ─ v9968_axi_backend ── HP0  VRAM        │
  │                          ├─ V9990 (60h-6Fh) ───────── v9990_vram_axi + v9990_fb ─ GP1       │
  │                          ├─ OPL4 FM + wave ────────── wave_axi ─────────── GP0  ROM de ondas│
  │                          ├─ sd_axi_proxy ───────────── HP3  sectores de las tarjetas        │
  │                          ├─ dbg_mailbox_axi ────────── HP2  buzón PL ↔ ARM                  │
  │                          └─ PSG ×2 · SCC ×2 · OPLL · Y8950 · PPI · RTC · S1990 · wifi_lite  │
  │  msx2hdmi_v9968 ─┐                                                                           │
  │                  ├─ hdmi_tmds_switch ── OSERDESE2 ── HDMI 720p60 (+ audio)                   │
  │  msx2hdmi_v9990 ─┘                                                                           │
  └──────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 3. Relojes

El PL recibe 50 MHz de la placa (`clk50`, K17). Dos MMCM (`MMCME2_BASE`: el principal y el de vídeo) y dos PLL (`PLLE2_BASE`: el de `clk_86` y el de 12 MHz) sacen de ahí los relojes del diseño, todos con divisores exactos:

| Reloj | MHz | Origen | Qué lleva |
|---|---|---|---|
| `clk50` | 50 | pad | Entrada de los PLL |
| `clk_27m` | 27 | MMCM principal (VCO 1350 MHz, ÷50) | El Z80 (habilitaciones de 3,58 MHz sobre este reloj), el audio y el mezclador, el proxy de SD (HP3), la entrada de los demás PLL |
| `clk_54m` | 54 | ÷25 | Bus del Z80 registrado, caché de RAM (HP1), buzón (HP2), lado de bus del OPL4 y del V9990 |
| `clk_108m` | 108 | ÷12,5 | Arbitraje de bus heredado del núcleo |
| `clk_135` | 135 | ÷10 | Heredado del núcleo del Tang |
| `clk_wave375` | 37,5 | ÷36 | Motor PCM del OPL4 y su puerto GP0 |
| `clk_hdmi` / `clk_hdmi5` | 74,25 / 371,25 | MMCM de vídeo (27 × 27,5, ÷10 y ÷2) | Píxel del HDMI 720p y reloj de serialización TMDS |
| `clk_86` | 85,909 | PLLE2 (27 × 35 ÷ 11) | V9968, V9990, bus de geo3d y el puerto GP1 |
| `clk_43` | 42,95 | misma PLLE2, ÷22 | Motor de geo3d (la mitad exacta de `clk_86`, en fase) |
| 12 MHz | 12 | PLLE2 desde `clk50` (× 24 ÷ 100) | Soft-host USB del PL, sin pines asignados en esta placa: el USB lo lleva el PS |
| `FCLK0` | 142,86 | PS | Reloj de HP0 (VRAM del V9968). `build.tcl` pide 150 MHz y el PS lo sintetiza a 1000 MHz ÷ 7; es el valor de `clocks.rpt` |

Los dominios `{clk50, 108, 54, 27, 135, 37,5}`, `{74,25, 371,25}`, `{85,9, 42,95}`, `{12}` y `{FCLK0}` son asíncronos entre sí en las restricciones (`top_zynq.xdc`); los cruces son por toggle o por FIFO. `clk_86`/`clk_43` se analizan como emparentados. El Z80 corre a 3,58 MHz con habilitaciones de reloj sobre los 27 MHz y tiene **turbo real a 5,37 MHz** (F11), conmutado sin glitch por `turbo_eff` cuando el bus está en reposo. El HDMI sale a 720p60 con audio.

## 4. Los puertos AXI

| Puerto | Reloj | Módulo | Función | Medida |
|---|---|---|---|---|
| HP0 | FCLK0 | `v9968_axi_backend.v` + `v9968_vram_shim` | Los 256 KB de VRAM del V9968, con caché de fondo y de sprites | 181 ns por lectura suelta |
| HP1 | `clk_54m` | `memory_axi.v` | La RAM del Z80, la megaram, el pack y la fuente kanji: caché de 64 KB que acepta la petición en el primer ciclo | acierto en ~75 ns |
| HP2 | `clk_54m` | `dbg_mailbox_axi.v` | El buzón PL ↔ ARM: una ronda cada ~1 ms | §6 |
| HP3 | `clk_27m` | `sd_axi_proxy.v` | La «SD» del MSX, servida por el companion | 1600 KB/s con la DMA |
| GP0 | `clk_wave375` | `wave_axi.v` | La ROM de ondas del OPL4 (YRW801, 2 MB) y la RAM de muestras | |
| GP1 | `clk_86` | `v9990_vram_axi.v` y `v9990_fb.v`, por `axi_arb2.v` | La VRAM de 512 KB del V9990 (prioritaria) y el frame buffer de su puente de vídeo | |

HP y GP1 son esclavos AXI3 del PS: el PL es el maestro. Con el V9990 compilado, el GP1 ya no sirve el puerto de depuración del OPL4 (34h-37h), que se queda sin motor. Todos los masters del PL nacen en reset (`FCLK_RESET0_N`) hasta que el FSBL o `boot.tcl` han preparado la DDR: el reentrenamiento del DDRC con un master leyendo deja el puerto HP muerto.

## 5. Mapa resumido de la DDR3

| Dirección | Tamaño | Contenido |
|---|---|---|
| 0x00100000 | 4 MB | El companion (código, datos, pila) |
| 0x00500000 | 1 MB | Zona del MP3 (con caché) |
| 0x00600000 | 4 MB | Pools y descriptores de lwIP y del GEM0 |
| 0x00A00000 | 4 MB | Heap de Mbed TLS (con caché) |
| 0x00E10000 | 256 B | `ota_info`: quién es esta imagen, para la actualización por red |
| 0x01000000 | 9 MB | Zona de descarga de la actualización por red (con caché) |
| 0x0E000000 | 4 MB | Mitad alta de la megaram de 8 MB |
| 0x0F000000 | 4 MB | YRW801 (2 MB) y RAM de muestras del OPL4 (2 MB) |
| 0x10280000 | 256 KB | VRAM del V9968 |
| 0x10300000 | 512 KB | VRAM del V9990 |
| 0x10400000 | 3 × 768 KB | Frame buffer del V9990 (tres slots) |
| 0x10800000 | 2 MB | RAM mapeada del Z80 |
| 0x10A00000 | 4 MB | Megaram, 4 MB bajos (dos mitades de 2 MB) |
| 0x10F00000 | 512 KB | Pack de BIOS (incluye la fuente kanji) |
| 0x11000000 | 224 MB | Imagen de disco (solo en modo imagen, sin companion) |
| 0x1F000000 | hasta 1,44 MB | Imagen de disquete de prueba (la deja `boot.tcl`; la zona llega hasta 0x1F1FFFFF) |
| 0x1F200000 | 1,44 MB | Caché del disquete USB |
| 0x1F400000 | 4 MB | Zona de la prueba de carga de un bitstream por PCAP (`profile.c`) y de los perfiles de la TF1 (`mxpf.c`) |
| 0x1FE00000 | 1 MB | Fichero de cinta cargado |
| 0x1FF00000 | 8 KB | Buzón, registro del companion y volcado del trazador |
| 0x1FF00100 | 256 B | SDBOX: cola de peticiones del proxy de SD |
| 0x1FF10000 | 64 KB | SDBUF: sectores del proxy |
| 0x1FF80000 | 64 KB | Anillo PCM del WaveGame |
| 0x1FFA0000 | 64 KB | Anillo de pulsos de la cinta |
| 0x1FFB0000 | 64 KB | Anillo ARM → V9990 del escritorio (control en +0, entradas de 16 bits desde +0x8000; [capítulo 13](13-v9990-geo3d.md)) |

El detalle por región, con las ventanas del Z80, está en el [capítulo 03](03-mapas-memoria.md). La MMU del companion (`mmu.c`) deja todo strongly-ordered, con caché solo el código y las constantes, la zona del MP3, el heap TLS y la zona de descarga (`mmu.c`); el resto (datos, pila, buzones) no tiene caché, para que la DMA y el PL lo vean tal cual. La L2 está apagada.

## 6. El buzón (MBOX)

`dbg_mailbox_axi.v` lee cada ronda los primeros 0x30 bytes (una ráfaga de 6 beats de 64 bits) y escribe la telemetría en +0x40..+0xCF:

| Palabra | Contenido |
|---|---|
| +0x00..+0x0F | Bitmap HID de 128 bits del teclado (bit = usage HID; modificadores en 104 + i). El PL lo OR-ea con el teclado propio |
| +0x10, +0x14 | Mandos (formato SNES de 16 bits, dos) y botones y secuencia del ratón |
| +0x18 | Ratón: acumuladores X e Y de 16 bits (el PL saca el delta entre dos rondas) |
| +0x1C | Control: bit 0 MSX_RUN (a 0 el MSX está en reset), bit 1 arma el trazador del VDP, bit 2 trazador solo de eventos auxiliares, bit 3 la UART del ESP (`wifi_lite`) va a la UART1 del PS (el companion hace de ESP32 por Ethernet), bit 4 el ESP32 del conector CAM1 (la S3) habla con la UART1 del PS y el MSX queda aparte, bits 28-8 siembra de configuración `{válido, ganancia, turbo, config2, config1}` |
| +0x20 | WaveGame: `{play[31], estéreo[30], ganancia[29:28], escritura[15:0]}` |
| +0x24 | Siembra del mezclador: `{válido[31], 7 canales × 4 bits}` |
| +0x28 | Cinta virtual: `{play[31], monitor[30], sin_motor[29], sin_Nextor[28], …, escritura[15:0]}` |
| +0x2C | Vídeo: `{seq[15:8], 3'b0, fs43[4], 2'b0, auto_off[1], sel[0]}`; al cambiar `seq` la HDMI pasa a `sel` (0 = V9968, 1 = V9990); `auto_off` apaga la conmutación automática ([capítulo 13](13-v9990-geo3d.md)); `fs43` pone el V9968 a pantalla completa en 4:3 con Scale3x ([capítulo 05](05-v9968.md)) |
| +0x30 | OSD pedido desde xsdb: bit 0 abre el panel F12 (`OSD_CTRL` en `osd.c`). Solo lo usa el ARM, el PL no lo lee |
| +0x34 | Estado del OSD que publica el companion: bit 0 panel abierto, bits 31-16 temperatura en décimas de °C (`OSD_STAT`) |
| +0x38 | Inyección desde xsdb: `{secuencia[31:24], etiqueta[15:8], dato[7:0]}` (92h orden WaveGame, 93h mensaje, 3Ch volumen fino, 3Dh ganancia) |
| +0x3C | Tecla de la actualización por red desde xsdb (el OSD la trata como si fuese del teclado; `tools/ota.tcl`) |
| +0x40..+0x6F | Telemetría: magia `MBOX`, secuencia, aciertos y fallos de la caché, estado (DDR, MMCM, SD, CPU), contadores del proxy de SD, ratón y mandos, OPL4, fallos del shim de VRAM |
| +0x70 | Bloque de configuración vigente + toggle al pulsar «guardar» |
| +0x74 | Contadores de la FIFO del UART del ESP32 |
| +0x78..+0xB7 | Anillo Z80 → ARM: 32 entradas `{puerto, dato}` de los OUT a 92h y 93h |
| +0xB8 | Estado del WaveGame (índice del anillo, nivel de la FIFO, ráfagas, play) |
| +0xC0 | Niveles del mezclador + toggle al pulsar «guardar» |
| +0xC8, +0xCC | Cinta: lectura, nivel de la FIFO, subdesbordamientos; estado |
| +0x800 | Registro del companion en anillo (`log.h`; lo lee `tools/armlog.tcl`) |
| +0xFF0 | Reinicio del USB desde xsdb: la magia `USBR` (0x52425355) hace que el companion reinicie la pila USB y la ponga a cero (`tools/usbreset.tcl`) |
| +0x1000 | Volcado del trazador del VDP (4 KB) |

Las herramientas `tools/tel.tcl`, `cfg.tcl`, `wg.tcl`, `key.tcl`, `vsel.tcl` y `ota.tcl` no son más que lectores y escritores de este buzón desde xsdb.

## 7. El companion

Programa bare-metal (sin sistema operativo) en el core 0 del PS, `fpga/zynq/arm/companion/`. Hace el proxy de sectores de TF2 (SDBOX) y las E/S de perfiles de TF1, el USB host con TinyUSB, la red con lwIP y Mbed TLS sobre el GEM0 (presenta al MSX un «ESP32» por la UART1 EMIO, ver el [manual](../manual/07-wifi-file-hunter.md)), el panel F12 por la UART0 EMIO con el protocolo del overlay (mientras está abierto el Z80 se congela), la OLED SSD1306, el bloque de ajustes de la QSPI, WaveGame y la cinta virtual, y la actualización por red. Todo ello está en el [capítulo 12](12-companion.md); la actualización, en el [capítulo 11](11-actualizacion.md).

El FSBL propio (`arm/fsbl/`) hace `ps7_init`, entrena la DDR y, si hay una ranura B confirmada, salta a ella. `arm/boot/make_boot.sh` empaqueta siete particiones en un `BOOT.bin` de unos 6,16 MB: FSBL, bitstream, companion, `zeros.bin` (buzón a cero, en 0x1FF00000), el pack (0x10F00000), la YRW801 (0x0F000000) y `ota_info` (0x00E10000).

## 8. `top_zynq.v` se edita a mano

`fpga/top.v` es el núcleo común del MSXimus. `fpga/zynq/top_zynq.v` parte de él pero **se edita a mano** y es la fuente de verdad: lleva el V9990, el puente de vídeo conmutado, geo3d, el buzón, el proxy, los relojes de Xilinx y la siembra de la configuración. `tools/make_top_zynq.py` quedó desfasado y regenerarlo borraría el V9990: no se usa. Ocupación del bitstream de la Z1.3.0 (`util_impl.rpt`, `timing.rpt`; la Z1.3.1 está al ~99,9 % de slices): 43.764 LUT (82,3 %), 35.992 FF, 99,74 % de slices, 130 de 140 tiles de BRAM, 28 DSP; WNS +0,812 ns, WHS +0,036 ns y todas las restricciones cumplidas (detalle en el [capítulo 07](07-construccion.md)). Los `timing.rpt` y `util_impl.rpt` que haya en una carpeta de trabajo son los de la última implementación que se lanzó allí: compruébese la fecha antes de citarlos.

## 9. Arranque

1. **QSPI** (SW1 ON-OFF): el BootROM carga el FSBL de la ranura A del W25Q128, el FSBL configura el PS, entrena la DDR, programa el PL y copia el resto de particiones; salta al companion, que lee la configuración, prepara TF2 y pone `MSX_RUN`. Si hay una ranura B confirmada, el FSBL reinicia el PS desde ella ([capítulo 11](11-actualizacion.md)).
2. **SD** (SW1 OFF-OFF): igual, con `BOOT.bin` en la raíz de la SD de TF1.
3. **JTAG** (SW1 ON-ON, desarrollo): `BOOT_PROXY=1 xsdb tools/boot.tcl [pack] [bit]` hace lo mismo desde el PC: para el PS, carga pack, ondas y VRAM en la DDR, limpia el buzón, arranca el companion, programa el PL y suelta los resets. El modo de arranque solo se relee al quitar y dar la corriente.
