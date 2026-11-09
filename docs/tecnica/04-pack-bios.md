# 04. El pack de BIOS

Qué es el fichero de 512 KB que el PS deja en la DDR3 en 0x10F00000 antes de soltar el MSX, qué ROMs lleva y en qué orden, cómo se construye, por qué caminos llega a la placa y por qué en esta línea la configuración ya no viaja con él. Sale de `bios/` (`build.sh`, `tools/hacer_packs.py`, `tools/desmontar_pack.py` y el fuente del menú en `src/`), de `fpga/zynq/arm/boot/make_boot.sh` y de `fpga/zynq/tools/boot.tcl` y `packswap.tcl`.

## 1. Qué es

Una **concatenación pura** de ROMs, sin cabecera ni índice, en diez ventanas fijas. El core sabe qué hay en cada desplazamiento porque está cableado en el RTL común (`fpga/top.v`): el banco D de la ventana de memoria del Z80 es el pack, y cada región es exactamente el pack más su base ([capítulo 03](03-mapas-memoria.md)).

| Desplazamiento | Tamaño | Contenido | Slot donde aparece |
|---|---|---|---|
| 00000 | 128 KB | Fuente kanji JIS1 | Por puertos D8-DB |
| 20000 | 128 KB | Fuente kanji JIS2 | Por puertos D8-DB |
| 40000 | 128 KB | **Nextor**: kernel en los bancos 0 a 6, driver de la SD en el banco 7 | 3-2 |
| 60000 | 32 KB | BIOS principal MSX2+ | 0-0 |
| 68000 | 16 KB | SubROM MSX2+ | 3-1, página 0 |
| 6C000 | 16 KB | BIOS MSX-MUSIC y, desde 4760h, **el menú** | 3-1, página 1 |
| 70000 | 16 KB | **Segunda página del menú** | 3-1, página 2 |
| 74000 | 16 KB | Reserva, a FF | |
| 78000 | 16 KB | ROM UNAPI del driver de red | 0-2, página 1 |
| 7C000 | 16 KB | Logo de arranque | 0-3, página 1 |

El pack nació en el MSXimus original y es el mismo binario: mismo menú, mismo driver, mismas ventanas. Lo que cambia en el MSXimus Z es **dónde vive y quién lo pone ahí**.

En esta línea el pack **no se copia**: no hay flash colgando del PL y no existe el paso de streaming al arrancar. El PS lo escribe directamente en la DDR3, en **0x10F00000** = `RAM_BASE` de `memory_axi` (0x10800000) + 0x700000, que es donde el mux de `top.v` espera el banco D, y el core lo lee en el sitio por el puerto AXI HP1, con la caché de 64 KB de `memory_axi` por delante (la caché se invalida entera mientras `cpu_run` está a 0, que es justo cuando el PS carga). Quien lo pone ahí es el FSBL cuando se arranca desde un BOOT.bin (QSPI o TF1) o `boot.tcl` cuando se arranca por JTAG (sección 5). Mientras el pack no está, el buzón lleva `MSX_RUN` a 0 y el Z80 espera en reset.

Visto desde la DDR:

| Dirección DDR | Tamaño | Contenido | Origen en el pack |
|---|---|---|---|
| 10F00000-10F3FFFF | 256 KB | Fuente kanji JIS1 y JIS2 | 00000 |
| 10F40000-10F5FFFF | 128 KB | Nextor (kernel y driver) | 40000 |
| 10F60000-10F67FFF | 32 KB | BIOS principal | 60000 |
| 10F68000-10F6BFFF | 16 KB | SubROM | 68000 |
| 10F6C000-10F6FFFF | 16 KB | FM-BIOS + menú, primera página | 6C000 |
| 10F70000-10F73FFF | 16 KB | Menú, segunda página | 70000 |
| 10F74000-10F77FFF | 16 KB | Reserva, a FF | 74000 |
| 10F78000-10F7BFFF | 16 KB | ROM UNAPI del ESP | 78000 |
| 10F7C000-10F7FFFF | 16 KB | Logo de arranque | 7C000 |
| 10F80000 | | Fin del pack | |

Mide **512 KB justos**. Los seis bytes de configuración que otras máquinas llevan detrás ('A', 'B', config 1, config 2, turbo, ganancia) no pintan nada aquí: la configuración vive en la QSPI y la administra el companion (sección 6). Si a la DDR llega un pack antiguo con esa cola, es inerte: en `top_zynq.v` la máquina de estados que la leía arranca en `STATE_IDLE` (parche 7 de `make_top_zynq.py`) y `config_init` no se dispara nunca; la siembra de los registros llega por el buzón.

## 2. Las ROMs y su procedencia

| ROM | Fichero | De dónde |
|---|---|---|
| Kanji JIS1 y JIS2 | `a1xxjis1.rom`, `a1xxjis2.rom` | Las de un Panasonic FS-A1FX. Propietarias |
| Nextor 2.1.4 | `bios/nextor214/Nextor-2.1.4.MSXimus.ROM` (no está en el repositorio público: ver la licencia de Nextor en `docs/tecnica/07-construccion.md`) | Kernel de Néstor Soriano (Konamiman) más el driver de la SD, hecho aquí sobre el de Luis Antoniosi (`lfantoniosi`, BSD-2). Se compila en `bios/nextor214/` |
| Nextor 3.0 | `bios/nextor3/Nextor-3*.ROM` (tampoco) | El mismo driver, portado al kernel 3, con `parche_illusion.py`. Se compila en `bios/nextor3/` |
| BIOS principal, internacional | `32k_msx2p_int_fix.bin` | La BIOS japonesa de Panasonic con 49 bytes cambiados: juego de caracteres, teclado y BASIC internacionales, el glifo del yen convertido en barra, el color del borde. Propietaria |
| BIOS principal y SubROM, japonesas | `a1wsxyen.rom`, `2pextrtc.rom` | Las del Panasonic FS-A1WSX. Propietarias |
| SubROM internacional | `16k_msx2p_subrom.bin` | Propietaria |
| FM-BIOS | Dentro de `assets/16k_msx2p_fm_logo_menu.bin` del repositorio privado de BIOS | La BIOS de MSX-MUSIC, propietaria, con el menú detrás |
| Driver de red | `esp8266e.rom` | El driver TCP/IP UNAPI de ducasp, binario |
| Logo | `bios/assets/logo16k_msximus.bin` | Propio, el «MSXimus z» (fuente en `docs/logo/`); empieza por el magic `LG` y el menú lo invoca con `CALLF` a #4002 |

Como lleva ROMs propietarias, los packs sueltos no se publican aparte: viven en el repositorio privado `Papipapito/bios-msxnano-msximus` (`packs/zynq/msximus/`), que se clona como carpeta hermana de este (o donde diga `MSXIMUS_BIOS_PRIV`), y llegan al público dentro de los cuatro `BOOT_<versión>_<variante>.bin` de la release de GitHub y de la actualización por red de msx.barcelona. En `files/<fecha>/` sólo se versionan los LEEME. Quien tenga sus propias ROMs monta el pack con las herramientas de `bios/`.

`bios/tools/desmontar_pack.py` corta un pack por esos desplazamientos y comprueba, reconcatenando, que reproduce el original byte a byte. Ojo: su tabla es todavía la del **pack antiguo** —driver kanji de 32 KB entero en 70000 y los 6 bytes de cola—, y suma 524 294 bytes; como compara el tamaño antes de cortar, con un pack actual de 512 KB justos aborta con «no es este formato» y no deja nada. Sirve tal cual para destripar un pack viejo; poner su tabla al día con la ventana de la segunda página del menú está pendiente.

## 3. El menú: 32 KB en ROM

El menú de la BIOS ([capítulo 04 del manual](../manual/04-menu.md)) es un programa en ensamblador que se ejecuta como cartucho desde el slot 3-1. Corre desde la ROM, con 32 KB repartidos así:

| Dirección Z80 | Qué |
|---|---|
| 4000-475F | La FM-BIOS de siempre, intacta |
| 4760-7050 | **Página 1 del menú**: rutinas que no pueden conmutar la página 1 (guardados, Game Master 2, DMA, pruebas, la página del mezclador, el setup WiFi) y la entrada del cartucho |
| 7051-7FFF | Tablas de la FM-BIOS, intactas. El ensamblado comprueba que no se pisan |
| 8000-9FFF | **Banco de código** del menú, en la página 2 |
| A010-BFFF | **Banco de datos**, con las rutinas que necesitan conmutar la página 1 |
| C000-E7FF | Variables y búferes en RAM; E800 en adelante se conserva entre pases |

Los dos bancos de la página 2 llevan guardas (`ds #A000-$` y `ds #C000-$`) que hacen fallar el ensamblado si el código crece más de la cuenta; `build.sh` imprime lo que queda libre en cada uno. Dos reglas de esa estructura:

- **Nada de lo que se llame durante una sesión de red de File-Hunter puede vivir en la página 1**, porque durante la sesión la página 1 es la ROM del ESP.
- **Nada que conmute la página 2 puede correr desde la página 2.** El setup WiFi (tecla W) conmuta la página 2 para hablar con la ROM del ESP, así que `wifi_setup_p1` (en `e7_rutinas.asm`, página 1) copia un stub a RAM y lo ejecuta desde ahí.

El fuente es único y lleva en `menu_main.asm` una bandera `MSXIMUS` (1 o 0) heredada de cuando servía a dos máquinas; el resto son bloques `IF MSXIMUS`, y `build.sh` la fija reescribiendo esa línea en una copia temporal. El MSXimus Z se ensambla siempre con `MSXIMUS=1`, tal cual; **no hay una bandera de línea en el fuente**. Lo que es distinto se descubre en tiempo de ejecución:

- **El puerto 2Fh** devuelve la versión del core. Con el nibble alto por debajo de A el menú la imprime como "M.m"; con A o más es la línea Zynq y la imprime como "Zn.m" (`ver_pnib`, en `e7_rutinas.asm`: 'Z' + (alto - 9) + '.' + bajo). La línea Zynq devuelve A2h y la línea "Version FPGA" de Ajustes muestra Z1.2; el tercer dígito sale del puerto 29h ([capítulo 02](02-puertos-es.md)). Esa misma comparación (`MIX_ZQ`) es la que añade la fila WaveGame en la página del mezclador.
- **La sonda del mezclador**: con el dispositivo goauld seleccionado (`OUT #40,#48`), `OUT #44,#F0` seguido de `IN #44`; si los bits 6..4 devuelven 7 (`MIX_HAS`), el core lleva mezclador por fuente y la página "Mezclador de audio" ofrece los siete canales; si no, sólo la ganancia maestra. La sonda selecciona con el bit 7 y arrastra los tres bits bajos de la ganancia leída, para que en un core sin mezclador —donde cualquier `OUT #44` es la ganancia— no le cambie el volumen por el camino.
- **El puerto 93h**: al lanzar una ROM, `wg_launch_msg` manda 'W', 'G', el LBA de la partición y los clusters de la carpeta y del fichero, para que el companion encuentre los `NN.wav` del WaveGame. En un core sin el anillo Z80→ARM es un `OUT` que nadie escucha.

## 4. Construir

Todo desde `bios/`, en WSL o Git Bash (los ejecutables externos de `bin/` se bajan aparte: véase `bios/README.md`):

```bash
cd bios
./build.sh msximus msximus_en   # ensambla el menu (castellano e ingles) con asmsx y lo inyecta en la FM-BIOS
python tools/hacer_packs.py     # monta los cuatro packs: Nextor 2.1.4 y Nextor 3, castellano e ingles
```

`build.sh` ensambla `src/menu_main.asm` con `asmsx`, comprueba que la parte de la página 1 no pisa las tablas de la FM-BIOS y que la imagen de la página 2 no empieza por `AB` (la BIOS la tomaría por otro INIT), y deja `out/bios_msximus.bin` (los 16 KB de 6C000) y `out/bios_msximus_p2.bin` (los de 70000); `msximus_en` da lo mismo con el menú, Ajustes y mensajes en inglés (`out/bios_msximus_en.bin` y `out/bios_msximus_en_p2.bin`). `hacer_packs.py` solo monta los packs en inglés si existe `out/bios_msximus_en.bin`.

`hacer_packs.py` trabaja en `packs/zynq/` del repositorio privado de BIOS y parte del pack anterior (`packs/zynq/msximus/nextor-2.1.4/pack_bios_msximus.bin`), reescribe las ventanas que cambian (menú, segunda página con 74000-77FFF a FF, logo desde `assets/`, Nextor desde `nextor214/`) y guarda el anterior en `packs/zynq/historico/bak_<fecha>/`. Cada parche verifica que no cambia ni un byte fuera de su ventana. Si el pack base todavía traía la cola de 6 bytes, la recorta: los packs salen de 512 KB justos. Para la línea de Nextor 3 toma la ROM más nueva que haya en `nextor3/` (comprueba la firma `NEXTORv3_DRIVER`): para actualizar la beta basta con dejar ahí su ROM de 128 KB. Imprime el md5 de cada pack, que es lo que se anota en cada entrega. Solo hace el MSXimus.

Para tocar una sola ventana sin regenerar nada, `tools/insertar_en_pack.py pack.bin out/bios_msximus.bin nuevo.bin [out/bios_msximus_p2.bin]` hace lo mismo con el menú y comprueba lo mismo.

El driver de la SD se compila aparte, con `make` en `nextor214/` y en `nextor3/`, usando los ensambladores de cada kernel; el fichero `sd_rw_ports.inc` es común a los dos.

## 5. Meterlo en la placa: tres caminos

### a) Dentro del BOOT.bin (arranque autónomo)

`fpga/zynq/arm/boot/make_boot.sh [pack.bin] [yrw801.rom]` escribe un `.bif` y llama a `bootgen` (Vivado 2019.2). El orden de las particiones lo fija el FSBL: el bitstream tiene que ir justo detrás del bootloader y el companion tiene que ser la primera partición del PS, porque el FSBL salta a la primera que ve.

```
[bootloader] ../fsbl/fsbl.elf        ps7_init + DDR
../../msximus_zynq.bit               el PL arranca; MSX_RUN lo lee de la DDR
../companion/companion.elf           SD, USB, OSD, OLED, QSPI, WaveGame
[load=0x1FF00000] zeros.bin          64 KB: buzon y SDBOX a cero (MSX_RUN = 0, el MSX espera)
[load=0x10F00000] pack.bin           el pack de BIOS
[load=0x0F000000] yrw801.rom         tabla de ondas del OPL4, 2 MB
[load=0x00E10000] ota_info.bin       quien es esta imagen para la actualizacion por red
```

El `zeros.bin` lo fabrica el propio script (64 KB). El FSBL carga todas las particiones y después salta al companion, que arranca la tarjeta de TF2 y pone `MSX_RUN` a 1. Por defecto el pack es el de Nextor 2.1.4 de `packs/zynq/msximus/` del repositorio privado de BIOS; para Nextor 3 se pasa el de `nextor-3.0.0-beta2/`. La ROM de ondas se copia a este directorio para el `.bif`.

El BOOT.bin resultante se graba en la QSPI desde `fpga/zynq/` con

```
vivado -mode batch -source tools/qspi_program.tcl -tclargs program w25q128fv-qspi-x4-single BOOT.bin
```

que usa nuestro FSBL como ayudante (no hace falta el `program_flash` del SDK) y necesita `hw_server` en marcha y **SW1 en JTAG = ON-ON**: con SW1 en SD el borrado se queda colgado y Vivado acaba contestando "The current boot mode is SD". Después se arranca con SW1 en QSPI (ON-OFF) (si la placa tiene una ranura B confirmada por la actualización por red, el FSBL salta a ella y no arranca lo grabado en la A: F12 → U → F dos veces → R vuelve a la A; el capítulo [11](11-actualizacion.md) lo explica); o se copia el BOOT.bin a la raíz de una SD FAT32 y se mete en TF1 con SW1 en SD (OFF-OFF). SW1 sólo se lee al quitar y dar la corriente. Un pack nuevo implica regenerar y regrabar el BOOT.bin entero.

### b) Por JTAG con `boot.tcl` (desarrollo)

```
BOOT_PROXY=1 xsdb.bat tools/boot.tcl [pack.bin] [bitstream.bit]
```

Con `hw_server` aparte. Para los dos Cortex-A9, deja los masters del PL en reset (`FCLK_RESET0..3_N` a 0 y los level shifters sólo PS→PL, como hace el FSBL: `ps7_init` reentrena la DDR3 y si el PL sigue leyendo por AXI mientras tanto los puertos HP se quedan muertos), ejecuta `ps7_init`, escribe el pack en 0x10F00000 con `mwr -bin -file` e imprime las dos puntas (cabeza y último word) para ver que ha entrado, carga la YRW801 en 0x0F000000, pone la VRAM (0x10280000, 256 KB) y el buzón entero a cero, arranca el companion en el core 0, programa el PL y suelta el MSX. Sin `BOOT_PROXY` la "SD" es una imagen de disco en la DDR (tercer argumento). Con SW1 en SD no funciona.

### c) En caliente con `packswap.tcl`

```
xsdb.bat tools/packswap.tcl pack.bin
```

Sin reprogramar el PL ni tocar el PS: `MSX_RUN` a 0 (el MSX entra en reset y `memory_axi` invalida su caché), el pack nuevo a 0x10F00000, la VRAM y los 64 KB de RAM principal del Z80 a cero, `MSX_RUN` a 1. Los 64 KB a cero no son opcionales: el menú guarda en RAM banderas que sobreviven al reset (`BOOT_FLAG`, `DSK_PEND`, `BOOT_SP`/`BOOT_RET` en E800 en adelante) y con otro pack debajo lo llevaban a un bucle. Es el camino para iterar el menú sin perder el JTAG, que se cae al reprogramar la FPGA; el companion sigue sirviendo la tarjeta.

### Entregas

Cada entrega deja en `files/<fecha>/` el pack, el BOOT.bin y su LEEME con los md5. Los md5 de los packs de cada versión están en el LEEME de su entrega.

## 6. La configuración: en la QSPI, no en el pack

Los ajustes del menú (config 1, config 2, turbo al arrancar, ganancia y los siete niveles del mezclador) viven en un bloque `MSXC` de 16 bytes en el último sector de 4 KB de la QSPI, en **0xFFF000**: config 1, config 2, turbo (0/1), ganancia (0..7), un xor con 5A; la versión 2 añade en los bytes 9..12 los niveles del mezclador (7 x 4 bits) y en el 13 un xor con A5.

- **Al arrancar**, `cfg_load()` del companion lo lee y lo pone en `MBOX+0x1C[28:8]` (`{valid, gain, turbo, config2, config1}`) y en `MBOX+0x24` (niveles) con `valid` a 1 **antes** de `MSX_RUN`. El PL siembra con eso config 1 (puerto 41h), config 2 (42h), el turbo de arranque (45h), la ganancia (44h) y los niveles del mezclador, y sigue sembrando hasta que el MSX corre; el turbo de arranque se siembra un ciclo después de soltar el bus. Los niveles llevan su propia ventana de siembra: `MBOX+0x24` llega un *beat* del buzón después que `MBOX+0x1C`, y arrancando por JTAG (con `MSX_RUN` ya a 1 antes de configurar el PL) la ventana común es de un solo ciclo de 27 MHz.
- **Save & Restart** del menú (`OUT #42` con el bit 6, dos veces): el PL saca el bloque vigente por `MBOX+0x70` y los niveles por `MBOX+0xC0`, cada uno con un toggle; `cfg_poll()` espera a que los dos coincidan y graba. Un bloque con config 1 = 0 se rechaza.
- **Sin bloque válido**: los valores de fábrica, config 1 = F3h, config 2 = 0Fh (SD activa en 3-2 y menú al arrancar), sin turbo, ganancia x5, mezclador a 8 de 8.
- **Rescate**: manteniendo S durante el logo se entra en Ajustes aunque "Menu al arrancar" esté Off.
- **Trampa del JTAG**: `boot.tcl` limpia el buzón **entero** (los 256 bytes), no sólo las teclas. Si se deja la telemetría del PL anterior, el toggle de guardar de `MBOX+0x70`/`+0xC0` llega a 1, el companion recién arrancado lo compara con su 0, cree que se ha pulsado guardar y escribe un bloque de ceros en la QSPI; ese bloque lo rechaza el arranque siguiente (config 1 = 0) y la placa sale con los valores de fábrica.

La consecuencia práctica es la que motivó quitar la cola del pack: grabar un pack o un BOOT.bin nuevo no toca los ajustes, y grabar ajustes no toca el pack. `qspi_program.tcl` graba con `PROGRAM.ADDRESS_RANGE {use_file}`, así que el borrado se ciñe a los sectores que ocupa el BOOT.bin y no llega a 0xFFF000: regrabar la QSPI no debería tirar la configuración (es lo que pide el script; no se ha forzado la prueba en placa). Herramientas: `tools/cfg.tcl show|set|mix` para leer y escribir el bloque desde el PC y `tools/tel.tcl` para ver lo que el PL tiene vigente.

## 7. Lo que no va en el pack

- **La tabla de ondas del OPL4** (`yrw801.rom`, 2 MB, en `packs/zynq/roms/` del repositorio privado de BIOS): partición aparte del BOOT.bin en 0x0F000000, o `boot.tcl` (`WAVE_ROM=fichero` para otra ROM, `WAVE_ROM=none` para no cargarla).
- **El contenido de la tarjeta de TF2**: `NEXTOR.SYS`, `COMMAND`, utilidades, herramientas del WiFi y del File-Hunter. Lo trae [MSX SD Maker](https://github.com/Papipapito/SD_Maker) (`base/`, `nextor-2.1.4/` y `nextor-3.0.0-beta2/`); [capítulo 03 del manual](../manual/03-tarjeta-sd.md).
- **La configuración** (sección 6) y **el companion**, que es una partición del BOOT.bin o un `.elf` que `boot.tcl` descarga por JTAG.

## 8. Un pack para el core

El menú y el driver sondean el core en cada arranque y usan lo que encuentran, con las firmas del [capítulo 06](06-sd-dma.md): puertos de la SD, cronómetro, DMA, modo lógico, contadores de mapper. En el MSXimus Z todo eso está: `sd_axi_proxy.v` sustituye al lector de tarjeta con **la misma interfaz de cliente**, así que `sdc_ioport`, `sd_dma` y el pegamento de `top.v` no se tocan, y el driver de Nextor va por puertos y DMA como en cualquier core con ellos. La diferencia está debajo: los sectores no vienen de una tarjeta colgada del PL sino del companion, que sirve la tarjeta real de TF2 por el buzón SDBOX (modo proxy), o de una imagen de disco en la DDR (modo imagen, sólo por JTAG y sin companion).

Lo que un core tiene que tener para arrancar un pack actual: el menú de 32 KB en ROM exige la ventana de la segunda página en el slot 3-1 (la Zynq la tiene) y el puerto 2Fh con un valor distinto de FFh para que Ajustes muestre la versión. Las funciones propias de la Zynq (mezclador por fuente, WaveGame, versión "Zn.m") las descubre el mismo menú por las sondas de la sección 3, así que una entrega nueva del core no obliga a regenerar el pack, y una entrega nueva del pack no obliga a regenerar el bitstream, salvo que el LEEME de la entrega diga lo contrario. El BOOT.bin, en cambio, lleva las dos cosas: cualquiera de ellas que cambie obliga a rehacerlo.

## 9. El pack de pruebas de escritura

En `packs/zynq/herramientas/` del repositorio privado de BIOS hay packs que en vez del menú llevan la prueba de escritura en crudo de la SD (la tecla C de las versiones antiguas). Sirven para calificar tarjetas: escriben y verifican en un cluster libre sin tocar el sistema de ficheros. Se cargan por cualquiera de los tres caminos de la sección 5. No son para uso normal, y en esta línea no se han pasado todavía: la escritura ya se valida con el menú de pruebas (tecla T) y con el propio Nextor sobre el proxy.
