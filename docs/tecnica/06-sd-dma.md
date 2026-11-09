# 06. La SD: el proxy del companion y la DMA

## 1. Dos tarjetas

La ZYNQ MINI tiene dos ranuras microSD y ninguna cuelga del PL:

| Ranura | Controlador | Uso |
|---|---|---|
| TF1 | SD0 del PS | Los **perfiles** del PL (`mxpf.c`, solo desde el bucle principal del companion) y, si SW1 está en SD, el arranque del PS (`BOOT.bin` en la raíz de su primera partición). **El MSX no la ve** (sección 3) |
| TF2 | SD1 del PS | **La "SD" del MSX** (dispositivo 1 de Nextor): ROMs, discos, carpetas WaveGame, saves |

El núcleo del MSXimus sigue hablando con "su" controlador de SD por los puertos 47h-4Fh del dispositivo 48h (capítulo 02) y por la ventana de Nextor; lo que ha cambiado es quién está al otro lado: `fpga/zynq/sd_axi_proxy.v` en vez de un lector SPI.

## 2. El proxy

`sd_axi_proxy.v` (HP3, `clk_27m`, el reloj del lector SPI al que sustituye) traduce cada orden de sector del núcleo en una petición en el **SDBOX** (DDR 0x1FF00100) y espera la respuesta. El PL lo lee y lo escribe en palabras de 64 bits; el companion (`main.c`) lo ve como un array de `u32`, y la tabla usa ese índice (palabra *n* = SDBOX + 4·*n*):

| Palabra | Contenido |
|---|---|
| W0 | `MODE`: bit 0 = 0 imagen (el PL lee los sectores directamente de la imagen en 0x11000000), 1 = proxy (los sirve el companion) |
| W1 | Tarjeta: bit 0 presente, bits 31-16 tamaño de TF2 en MB |
| W2 | Petición: secuencia (`REQ_SEQ`; el PL la incrementa en cada orden y avisa por `IRQ_F2P[0]`) |
| W3 | Petición: opcode (bits 7-0: 1 leer, 2 escribir; bits 15-8: número de bloques) |
| W4 | Petición: sector (LBA de 32 bits, entero; el sector 0xFFFFFFFF es el bloque de información de TF1, sección 3) |
| W6, W7 | Respuesta del companion: secuencia atendida (`ACK_SEQ`) y estado (0 = OK, 1 = sin tarjeta, 2 = error o fuera de la tarjeta, 3 = orden desconocida) |
| W8-W12 | Contadores de TF2: lecturas, escrituras, errores, inicializaciones, vueltas del bucle |
| W13, W14 | Montajes USB e informes HID (los pone el companion; los lee `armlog.tcl`) |
| W15, W16 | TF1: presencia y sectores, solo informativos (sección 3). W17-W19 ya no se usan |
| W30 | `'IMG1'` / `'IMG2'`: modo imagen (sección 4); lo deja `boot.tcl` |
| +0x80.. | La ventana de la disquetera USB (`fdd.c`; `tools/tel.tcl` la imprime) |

Los datos van por el **SDBUF** (0x1FF10000, hasta 255 bloques de 512 B por orden): en lectura el companion deja ahí los sectores y el PL los copia a su búfer o, con la **DMA**, directamente a la RAM del MSX por `memory_axi`; en escritura el PL los deja y el companion los graba. El companion atiende las peticiones en su bucle principal con el driver `xsdps` del PS; la tarjeta se inicializa una vez. Un acceso que falla reinicializa la tarjeta y se reintenta una vez; sin tarjeta, el bucle intenta el `init` cada 0,5 s, y con tarjeta comprueba cada 2 s (`SEND_STATUS`) que sigue ahí. Una orden sin acuse en 2 s la da por perdida el PL y la devuelve al MSX como error de tiempo.

Rendimiento medido: **1600 KB/s** con la DMA de lectura. La DMA es la misma del núcleo (`fpga/src/sd_dma.sv`): modo lógico, contadores de patrones de mapper para el detector del menú, y el driver de Nextor la usa para los bloques grandes (orden `05h` del puerto 47h: leer más DMA).

## 3. TF1: solo perfiles (ya no es un dispositivo de Nextor)

Desde la Z1.2.13 hasta la Z1.4.2 la microSD de TF1 (SD0) era el **dispositivo 2** del driver de Nextor (unidad B:): el driver ponía el bit 31 del sector y el companion lo desviaba a TF1 (`tf1_serve`). **Desde la Z1.4.3 la TF1 es solo de los perfiles y el MSX no tiene ningún camino a ella.** El PL no cambia, los drivers de Nextor tampoco:

- **Orden.** Un sector con el bit 31 ya no es de TF1: cae en la ruta de TF2 y, al estar fuera de la tarjeta, se rechaza con estado 2 sin reinicializar nada. La ventana de la disquetera USB (0xFFFE0000.., lleva el bit 31) y los sectores mágicos del perfil Dual (0x7FFFFFFD y 0x7FFFFFFE, sin bit 31) se atienden **antes**, como siempre.
- **Bloque de información.** Los drivers de Nextor leen en su inicialización el sector 0xFFFFFFFF: el companion contesta `"TF1!"` (+0), **0 sectores** (+4) y presencia 0 (+8), así que ningún driver enseña el dispositivo 2 (`bios/tests/test_tf1_nextor.py`, caso «sin tarjeta»).
- **Presencia.** `W1` bit 0 vale 1 **solo** si hay tarjeta en TF2. La TF1 se sondea al arrancar el bucle y cuando `mxpf.c` la consulta; con tarjeta se vigila cada 2 s para detectar que la retiran, y un cambio de estado hace que `perfiles_aviso_revisa()` vuelva a clasificarla (aviso de tarjeta nueva). Sin tarjeta no hay reintentos de fondo.
- **Telemetría.** W15: bit 0 TF1 presente, bit 1 sondeada. W16: sectores de 512 B de TF1 (ya sin el recorte a 0x7FFFFFFF). W17-W19 quedan sin uso.
- **Quién la toca.** `tf1_sectores`, `tf1_leer` y `tf1_escribir` (`main.c`) son de `mxpf.c`; cada trozo largo llama a `sd_ceder()` (antes `tf1_ceder`) para atender al MSX (TF2, disquetera, Dual).

## 4. Modo imagen

Sin tarjeta, la "SD" puede ser una imagen FAT16 de hasta 224 MB cargada en la DDR (0x11000000) por `boot.tcl`: `xsdb tools/boot.tcl <pack> <bit> <imagen.img>`; `tools/mkfat16.py` fabrica una. Tres variantes:

| Arranque | Quién sirve los sectores |
|---|---|
| `boot.tcl` sin `BOOT_PROXY` | Solo el PL, con `MODE` = 0 y sin companion |
| `BOOT_PROXY=1 BOOT_IMG=1` (marca `'IMG1'` en W30) | El PL (`MODE` = 0); el companion está en marcha y atiende WaveGame y cinta desde la imagen |
| `BOOT_PROXY=1 BOOT_IMG=2` (marca `'IMG2'`) | El companion (`MODE` = 1), con la ventana de la disquetera incluida (`FDD_IMG=<disco.dsk>` carga un disquete falso) |

En los modos de imagen TF1 no se sondea. Sirven para probar sin tarjeta, pero no persisten nada. El uso normal es el proxy.

## 5. Sistemas de ficheros

- El **menú** (`bios/`) entiende FAT16 y FAT32 (particiones 01/04/06/0E y 0B/0C); el File-Hunter escribe en las dos.
- El **companion** (`wavegame.c`) lleva su propio lector FAT16/FAT32 para encontrar los WAV de la carpeta de la ROM lanzada; el menú le manda el LBA de la partición y los clústeres por el puerto 93h.
- La SD de TF2 se puede formatear en el PC como siempre; el contenido base (utilidades, WiFi, File-Hunter) lo trae [MSX SD Maker](https://github.com/Papipapito/SD_Maker).

## 6. Telemetría y diagnóstico

`tools/tel.tcl` imprime, de MBOX+0x54 y +0x58, el estado del proxy (modo, IRQ, ocupado, bloque listo, inicio de lectura/escritura), el tipo y estado de la tarjeta y los contadores de órdenes, `timeout`, `crc` y `rcrc`; `tools/armlog.tcl` enseña el registro del companion (montaje de la tarjeta, MB, errores) y las palabras W0-W14 del SDBOX. Los síntomas están en el capítulo de problemas del manual ([`10-problemas.md`](../manual/10-problemas.md)).
