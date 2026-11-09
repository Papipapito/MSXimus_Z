# 12. El companion

El programa del procesador de la placa. El XC7Z020 tiene dos mitades: la lógica programable (PL), donde vive el MSX, y el sistema de procesador (PS), con dos núcleos Cortex-A9. El **companion** es un programa bare-metal (sin sistema operativo) que corre en el **core 0** y hace de periferia del MSX: sirve las tarjetas SD, lee el USB, dibuja el panel F12 y la OLED, da red al MSX por Ethernet, reproduce música y cintas y gestiona la actualización por red. Está en `fpga/zynq/arm/companion/`. Este capítulo describe cómo arranca, qué hace su bucle, cómo habla con el PL y qué hace cada módulo. La visión de conjunto está en el [capítulo 01](01-arquitectura.md); la SD, en el [06](06-sd-dma.md); la cinta, en el [10](10-cinta.md); la actualización, en el [11](11-actualizacion.md).

El core 1 no se usa.

## 1. Construcción

```
fpga/zynq/arm/get_tinyusb.sh      # una vez
fpga/zynq/arm/get_minimp3.sh      # una vez
fpga/zynq/arm/get_mbedtls.sh      # una vez
fpga/zynq/arm/companion/build.sh  # -> companion.elf
```

`build.sh` compila con `arm-none-eabi-gcc` 14.2 (`-mcpu=cortex-a9 -marm -mfloat-abi=soft -mno-unaligned-access -O2 -ffreestanding -nostdlib`) y usa los fuentes del BSP standalone y de los drivers `sdps`, `qspips`, `emacps` y `scugic`, y lwIP 2.1.1 con el puerto Xilinx, todo del árbol `data/embeddedsw` de Vivado 2019.2: no hace falta SDK ni Vitis. Solo `mp3.c` se compila con `-mfloat-abi=softfp -mfpu=neon`. La configuración de los drivers y de lwIP está en `bsp/` y la de TinyUSB en `tusb_config.h`. El resultado, `companion.elf`, entra en el `BOOT.bin` (véase el [capítulo 07](07-construccion.md)).

## 2. Arranque y memoria

| Fichero | Qué hace |
|---|---|
| `start.S` | Punto de entrada. Deja la MMU, las cachés y el predictor apagados, instala una tabla de vectores propia (cualquier excepción se queda en un bucle con su número en `r0`: 1 instrucción indefinida, 2 SVC, 3 aborto de captura, 4 aborto de datos, 6 IRQ, 7 FIQ), enciende la FPU/NEON (solo la usa `mp3.c`), pasa a modo SVC, pone la pila, limpia `.bss` y llama a `main`. También trae `dcache_inval_all`, `mmu_enable` y `call_on_stack` (para el MP3) |
| `mmu.c` | Enciende la MMU con la memoria entera como *strongly-ordered*, de modo que el DMA de la SD, el EHCI del USB, el GEM de la red y el buzón se vean sin mantenimiento de caché. Solo se mapean **normales y con caché** el código y las constantes del companion (páginas de 4 KB, hasta `__rw_start`), la zona del MP3, el heap de Mbed TLS y la zona de descarga de la actualización: nadie más que este core las toca. La L2 la apaga `main` antes (`l2_disable`) |
| `lscript.ld` | Regiones de la DDR del companion |

| Región | Dirección | Tamaño | Contenido |
|---|---|---|---|
| `ddr` | 0x00100000 | 4 MB | Código, datos, `.bss` y pila (64 KB) |
| `mp3` | 0x00500000 | 1 MB | Estado de minimp3 (con caché) |
| `net` | 0x00600000 | 4 MB | Pools de lwIP y descriptores del GEM0 |
| `tls` | 0x00A00000 | 4 MB | Heap de Mbed TLS (768 KB usados, con caché) |
| — | 0x01000000 | 9 MB | Descarga de la actualización (con caché; `ota.c`) |

Otras zonas de la DDR que toca: la ROM de ondas YRW801 en 0x0F000000, la VRAM del V9968 en 0x10280000, la RAM del Z80 en 0x10800000, el pack de BIOS en 0x10F00000, el buzón en 0x1FF00000 (con el log en +0x800 y el SDBOX en 0x1FF00100), el búfer de sectores SDBUF en 0x1FF10000, la caché de la disquetera en 0x1F200000, la zona de PCAP y de los perfiles en 0x1F400000 y el fichero de la cinta en 0x1FE00000. El mapa completo está en [01](01-arquitectura.md) y [03](03-mapas-memoria.md).

### Secuencia de `main()`

1. `l2_disable`, `mmu_init`, `log_init`.
2. `ota_arranque()`: lee la `ota_info` de la imagen que corre y el registro de la QSPI; puede reiniciar el PS para probar la ranura B (capítulo 11).
3. Inicializa la SD de TF2 (`XSdPs`) y publica en el SDBOX si hay tarjeta; activa el modo proxy (`W0[0] = 1`), salvo en el modo imagen de pruebas.
4. `fdd_init()`; pone a cero la VRAM (256 KB en la DDR, que arranca con basura).
5. `cfg_load()`: la configuración guardada en la QSPI va al buzón (`MBOX+0x1C` bits 28-8) y, con ella, los niveles del mezclador (`MBOX+0x24`), ambos antes de soltar el MSX.
6. `tape_init()`; si hay **perfil al arrancar** (ajuste de la QSPI, apartado 5.9) se carga ahora por PCAP (`mxpf_arranque`, ~0,6 s); y **`MSX_RUN`** (`MBOX+0x1C` bit 0): el MSX sale de reset.
7. `wake_setup()`: configura el GIC (IRQ del PL `IRQ_F2P[0]` y el temporizador privado del core a 10 ms) para que `WFI` despierte; las interrupciones siguen enmascaradas en la CPU y no hay manejadores.
8. `usb_host_init`, `osd_init`, `net_init`, `tls_init`, `esp_init`.

## 3. El bucle principal

El core duerme en `WFI`; lo despiertan el temporizador (cada 10 ms) o la petición de sector del PL. Cada vuelta llama, por este orden, a:

| Llamada | Módulo | Qué hace |
|---|---|---|
| `usb_host_poll` | `usb_host.c` | `tuh_int_handler` + `tuh_task_ext` de TinyUSB |
| `osd_poll` | `osd.c` | F12, repintado del panel, teclas del OSD |
| `cfg_poll` | `qspi_cfg.c` | «Guardar» del menú → sector de la QSPI |
| `wg_poll` | `wavegame.c` | Órdenes Z80 → ARM y relleno del anillo PCM |
| `pext_poll` | `perfiles_ext.c` | Lo que el menú ha pedido por el 93h sobre perfiles (instalar un `.MXP`, etiqueta `[P:ID]` de una ROM; apartado 5.9). Hace aquí, y no dentro de `wg_poll`, lo que tarda |
| `dual_poll` | `dual.c` | Perfil Dual: la ROM que el menú manda a la máquina B (tecla D de «Lanzar ROM», trama `'W', '0'+MAPPER_ID` del 93h; [capítulo 14](14-perfil-dual.md), apartado 11). Copia la ROM de la megaram de A al cartucho de B (hasta 2 MB) fuera de `wg_poll`. Desde la Z1.3.2b8 esa trama es de **Shift+D**; la D sola lanza la ROM en A (`'V','A'`, sin trama de B) y `dual_escritorio(10)` deja a B corriendo sin cartucho |
| `tape_poll` | `tape.c` | Anillo de pulsos y teclas automáticas de la cinta |
| `fdd_poll` | `fdd.c` | Medio de la disquetera y volcado de su caché |
| `net_poll` | `net.c` | RX/TX del GEM0, temporizadores de lwIP, enlace |
| `esp_poll` | `esp_link.c` | El «ESP32» virtual: bytes del MSX, respuestas |
| `ota_poll` | `ota.c` | Búsqueda, descarga, grabación y confirmación |
| `perfil_poll` | `profile.c` | Mira la zona de la prueba de PCAP (una lectura); si hay petición, recarga el PL (apartado 5.8) |
| `mxpf_poll` | `mxpf.c` | Mira la zona de órdenes de los perfiles (una lectura); si hay orden, la hace en la TF1 (apartado 5.9) |

Después atiende la petición de sector del PL, si la hay (`W_REQ_SEQ` ≠ `W_ACK_SEQ`): una orden de la ventana de la disquetera va a `fdd.c`, el sector 0xFFFFFFFF contesta «sin dispositivo 2» (bloque `"TF1!"` con 0 sectores), el resto va a la TF2 (la TF1 ya no es del MSX); el acuse sube con el estado (0 = bien, 1 = sin tarjeta, 2 = error, 3 = orden desconocida). El PL espera como mucho 2 s. Si no hay petición, hace trabajo de fondo: `yrw801_poll` (un tramo de 32 KB de la suma de la ROM de ondas), el sondeo de TF1 y la vigilancia de la tarjeta (reinicializa sin tarjeta cada 0,5 s; con tarjeta, `SEND_STATUS` cada 2 s). Todo lo que tarda se hace por tramos: ningún módulo bloquea el bucle más allá de lo que tarda una petición de disco.

Con el procesador parado por JTAG (halting-debug), `WFI` es un NOP y el bucle gira cien veces más rápido; por eso las esperas en tiempo real usan el temporizador global (`gt_now`) o `tusb_time_millis_api`, no las vueltas.

## 4. El buzón PL ↔ ARM

El buzón (`MBOX`, 0x1FF00000) es una zona de la DDR que el PL lee y escribe sin ayuda del procesador, con `dbg_mailbox_axi.v` como maestro AXI. Cada ~1 ms el PL lee los primeros 0x30 bytes (una ráfaga de 6 beats de 64 bits: teclado, mandos, ratón, controles) y escribe la telemetría. El ARM solo lo ve como memoria. La tabla completa está en [01](01-arquitectura.md); estos son los registros que toca el companion y quién los usa:

| Offset | Dirección | Lo escribe | Módulo | Contenido |
|---|---|---|---|---|
| +0x00..+0x0F | bitmap HID | ARM | `usb_host.c` | Teclado: 128 bits, uno por *usage* HID (modificadores en 104 + i); el PL lo une con el teclado propio. `kbd_synth_set` mete teclas sintéticas (cinta) con OR |
| +0x10 | mandos | ARM | `usb_host.c` | `joy1[15:0]`, `joy2[31:16]`, palabra SNES (bit 11 R, 10 L, 9 X, 8 A, 7 RT, 6 LT, 5 abajo, 4 arriba, 3 Start, 2 Select, 1 Y, 0 B) |
| +0x14, +0x18 | ratón | ARM | `usb_host.c` | Botones + secuencia; acumulados X e Y de 16 bits (el PL saca el delta) |
| +0x1C | control | ARM | `main.c`, `esp_link.c`, `s3_link.c`, `tape.c`, `qspi_cfg.c` | Bit 0 `MSX_RUN`; bit 3 la UART del ESP va a la UART1 del PS (red por cable); bit 4 el ESP del CAM1 va a la UART1 (actualización sin cable); bits 28-8 siembra de configuración |
| +0x20 | WaveGame | ARM | `wavegame.c` | `{play[31], estéreo[30], ganancia[29:28], escritura[15:0]}` del anillo PCM |
| +0x24 | mezclador | ARM | `qspi_cfg.c` | Siembra de los niveles del mezclador |
| +0x28 | cinta | ARM | `tape.c` | `{play[31], monitor[30], sin_motor[29], sin Nextor[28], escritura[15:0]}` del anillo de pulsos |
| +0x2C | vídeo | JTAG, ARM | `tools/vsel.tcl`, `qspi_cfg.c` | `{seq[15:8], fs43[4], auto_off[1], sel[0]}`: al cambiar `seq`, la HDMI pasa a `sel` (0 = V9968, 1 = V9990); `auto_off` apaga la conmutación automática ([13](13-v9990-geo3d.md)); `fs43` = el V9968 a pantalla completa en 4:3 con Scale3x ([05](05-v9968.md)), que el companion toma de la QSPI |
| +0x30, +0x34 | OSD | ambos | `osd.c` | Petición de OSD desde JTAG; estado y temperatura |
| +0x38 | inyección | JTAG | `wavegame.c` | `{secuencia, etiqueta, dato}`: simula un OUT al 92h o 93h, o ajusta volumen, ganancia y anchura |
| +0x3C | tecla del OSD | JTAG | `osd.c` | Tecla HID para el OSD (`tools/ota.tcl`) |
| +0x40..+0x6F | telemetría | PL | `osd.c`, `oled.c`, `ota.c` | Magia `MBOX`, caché del Z80, estado… |
| +0x70, +0xC0 | «guardar» | PL | `qspi_cfg.c` | Bloque de configuración vigente + *toggle*; niveles del mezclador |
| +0x78..+0xBF | anillo Z80 → ARM | PL | `wavegame.c` | 32 entradas `{puerto, dato}` de los OUT al 92h y 93h; estado del WaveGame |
| +0xC8, +0xCC | telemetría de la cinta | PL | `tape.c` | Lectura del anillo de pulsos y nivel de la FIFO |
| +0x800 | log | ARM | `log.c` | Anillo de texto (apartado 7) |
| +0xFF0 | reinicio del USB | JTAG | `usb_host.c` | Magia `USBR` (0x52425355): el companion reinicia la pila USB y la pone a cero (`tools/usbreset.tcl`, apartado 5.2) |
| +0x80000 | anillo PCM | ARM | `wavegame.c` | 32768 muestras de 16 bits |
| +0xA0000 | anillo de pulsos | ARM | `tape.c` | 16384 entradas de 32 bits |

El SDBOX (0x1FF00100) es la cola de peticiones de sector del proxy de SD; su formato y el de los campos de la disquetera (+0x80 y siguientes) están en [06](06-sd-dma.md).

## 5. Módulos

### 5.1 Tarjetas y disquetera

| Fichero | Función | Habla con |
|---|---|---|
| `main.c` | Proxy de sectores: sirve la TF2 al PL por el SDBOX (`XSdPs` sondeado), el bloque de información `"TF1!"` sin dispositivo 2 (sector `0xFFFFFFFF`), las E/S crudas de TF1 para `mxpf.c` (`tf1_sectores`, `tf1_leer`, `tf1_escribir`, `sd_ceder`), el aviso de tarjeta nueva (`perfiles_aviso_revisa` cuando la TF1 aparece o se va) y los modos imagen de pruebas (`IMG1`/`IMG2`: la «SD» es una imagen de la DDR). Detecta cambio de tarjeta en caliente | PL (`sd_axi_proxy.v`), controladores SDIO0/SDIO1 del PS |
| `fdd.c`, `fdd.h` | Disquetera USB: la presenta como una ventana de sectores (LBA 0xFFFE0000.., 2880 sectores); mantiene una copia del disquete en la DDR (0x1F200000, 1,44 MB) que llena en segundo plano; escrituras *write-back*; detecta medio, capacidad y protección. Tiene un disquete falso en la DDR para pruebas | `main.c`, `ufi_host.c`, SDBOX |
| `ufi_host.c`, `ufi_host.h` | Driver de clase TinyUSB para disqueteras USB: transportes CBI, CB y Bulk-Only; una orden a la vez, con tiempo máximo y recuperación tras fallo | TinyUSB, `fdd.c` |
| `wavegame.c` | Montaje FAT16/FAT32 de la TF2 (lo comparten WaveGame, música del menú y cinta): `fat_mount`, cadenas de clústeres, lectura de ficheros | `sd_read` de `main.c` |

### 5.2 USB, teclado, ratón y mandos

| Fichero | Función | Habla con |
|---|---|---|
| `usb_host.c` | Controlador USB0 + PHY USB3320 por ULPI, con TinyUSB: reset del PHY, VBUS externo, hubs, HID. Teclado y ratón en protocolo *boot*; los mandos genéricos, por descriptor. Deja todo en el buzón; cuenta los dispositivos por tipo para el panel; F12 y las pulsaciones nuevas alimentan al OSD. Registra los drivers de clase propios: XInput y UFI. Lleva el vigilante del EHCI (`usb_host_vigila`, abajo) | Buzón (+0x00..+0x1B y +0xFF0), `hid_pad.c`, `usb_vigila.c`, `xinput/`, `ufi_host.c`, `fdd.c`, `osd.c` |
| `usb_vigila.c`, `usb_vigila.h` | La decisión del vigilante del EHCI, como función pura (sin registros ni TinyUSB): cuándo muestrear, cuándo la firma lleva congelada el tiempo suficiente y cuándo toca reiniciar | `usb_host.c` |
| `hid_pad.c`, `hid_pad.h` | Parser mínimo del descriptor de informe HID (ejes X e Y, *hat*, botones) y conversión a la palabra SNES; hasta 2 mandos | `usb_host.c` |
| `xinput/xinput_host.c` | Driver de clase para mandos Xbox y compatibles (MIT, de Ryzee119/tusb_xinput) | `usb_host.c` |
| `ci_hs_zynq.h` | Adaptación de TinyUSB al USB0 del Zynq (base 0xE0002000, sin interrupciones) | TinyUSB |
| `tusb_config.h` | Configuración de TinyUSB: host de alta velocidad, 1 hub, HID, XInput; el MSC propio de TinyUSB está desactivado | TinyUSB |

El driver de TinyUSB lleva un parche (`arm/tinyusb-zynq7000.patch`, que aplica `get_tinyusb.sh`) que enlaza el controlador del Zynq, corrige `hcd_edpt_abort_xfer` del EHCI (la disquetera lo necesita) y arregla el cuelgue del USB:

- `qhd_xfer_complete_isr` da una transferencia por terminada cuando el controlador **retira su qTD** (token con `Active = 0`, que el EHCI escribe de vuelta al terminar o al parar por error), no cuando el overlay del QH está inactivo. El overlay sigue inactivo tras armar una transferencia hasta que el controlador visita el QH (hasta 8 ms en la lista periódica), y la interrupción de cualquier otro endpoint la completaba antes de tiempo con 0 bytes y liberaba un qTD que seguía enlazado: otro endpoint lo reutilizaba y el controlador acababa ejecutándolo en dos QH (el endpoint de estado del hub dejaba de avisar de los cambios de puerto).
- `qtd_init` deja el qTD inactivo y terminado desde la primera escritura y activa el token (`Active`) lo último, con `pid` y `data_toggle` ya puestos.
- Las esperas de estado de `ehci_disable_schedule`, `ehci_enable_schedule` y `ehci_deinit` tienen tope (un EHCI colgado no atiende `PSE = 0` ni `RS = 0`), y `hcd_edpt_abort_xfer` de un endpoint ya cerrado devuelve falso.
- `ehci_split_signature` resume el FrameTag, la C-prog-mask y el SplitX de los QH periódicos FS/LS activos: lo que mira el vigilante.

**Vigilante del EHCI** (`usb_host_vigila`, llamado desde el bucle de `main.c`). Con el controlador colgado (visto en la placa tras horas encendida) `FRINDEX` sigue contando pero el motor periódico se para: los QH con split de los dispositivos detrás del hub dejan de avanzar, no responde ningún teclado ni ratón, ni reconectándolos, y `PSE = 0` o `RS = 0` no hacen efecto. Solo lo saca el reset de USB0 por el SLCR. Cada ~500 ms (500 y 520 ms alternos, con `tusb_time_millis_api`) mira la firma de `ehci_split_signature`; si no ha cambiado en 1,5 s y `FRINDEX` ha avanzado, reinicia: suelta teclas, botones y mandos del buzón (el ratón conserva sus acumulados), reset de USB0, `tuh_deinit(0)` (cierra los dispositivos con sus *umount*; XInput y UFI no tienen `deinit`, usbh solo llama al de los drivers que lo tienen), `usb_arranca` (reset de USB0 y del PHY, `tusb_rhport_init`) y todo el hub se vuelve a enumerar: los dispositivos tardan unos segundos en volver. El reinicio dura unas décimas de segundo y no se repite antes de 5 s. Deja en el log `USB: EHCI colgado (n), reinicio del controlador` y `USB: reinicio hecho en … ms`, y la página de información de F12 enseña `USB reiniciado: n` (solo si n > 0). **Límite:** sin QH con split activos (nada conectado, o solo dispositivos de alta velocidad) no decide nada, y un `FRINDEX` parado tampoco cuenta como colgado.

Prueba por JTAG: `tools/usbreset.tcl` escribe la magia `USBR` (0x52425355) en `MBOX+0xFF0` (el companion la pone a cero al atenderla) y fuerza el mismo reinicio, con `USB: forzado por JTAG (n), …` en el log. Para ver el estado del EHCI sin tocarlo: `tools/usbdiag.tcl` (registros, buzón, log, PC), `usbqh.tcl` (las listas de QH), `usbsplit.tcl` y `usbwatch.tcl` (FrameTag y token de los QH con split; el segundo avisa cuando llevan 1,5 s congelados) y `usblinks.tcl` (enlaces de los QH y qTD en uso; un qTD en dos QH es el fallo de la carrera). Banco en el PC: `tests/usb_vigila_host/run_host_usb.sh`.

### 5.3 Pantalla: OSD y OLED

| Fichero | Función | Habla con |
|---|---|---|
| `osd.c`, `osd.h` | El panel F12: dibuja en memoria cuatro páginas (la de información, la de la actualización, la de perfiles y, con el perfil Dual, la de la máquina B) de 32 × 28 celdas `{atributo, carácter}` y manda al `iosys` solo las filas que cambian, por la UART0 (EMIO) a 2 Mbaud con el protocolo del overlay; con el overlay encendido el PL congela el Z80. Lee temperatura y tensiones del XADC. Reparte las teclas: U abre la página de la actualización, P la de perfiles, B (con el perfil Dual) la de la máquina B, ESC vuelve | PL (`iosys`, `textdisp_z.v`), `osd_info.c`, `ota.c`, `usb_host.c` |
| `osd_info.c`, `osd_info.h` | Pinta la página de información: versión, temperatura, tensiones, tiempo encendida, SD, USB por tipo, turbo, chip de vídeo, IP, ROM de ondas | `osd.c` |
| `perfiles.c`, `perfiles.h` | La página Perfiles del panel (apartado 5.9) | `osd.c`, `mxpf.c` |
| `osd_dib.c` | Primitivas de dibujo sobre una página (texto UTF-8 con tabla de glifos, marcos, barras, botones, pastillas). No toca hardware | `osd_info.c`, `ota.c` |
| `osd_glifos.h` | Paleta y glifos; lo genera `tools/make_dpb_menu.py` | `osd_dib.c` |
| `oled.c`, `oled.h`, `font8x8.h` | OLED SSD1306 128×64 del conector J4, por SPI de 4 hilos a mano sobre GPIO EMIO (banco 2, bits 0..3): versión, temperatura, SD, USB, IP, chip de vídeo, tiempo encendida y velocidad de la CPU, una vez por segundo | PL (GPIO EMIO) |
| `v99desk.c` | El escritorio vivo del V9990 (teclas V y B del menú, y la D y Shift+D del perfil Dual): pinta por el anillo de la DDR (0x1FFB0000) la barra con la hora, NOW PLAYING y SYSTEM; la hora por SNTP (cable) o NTP (S3). Véase el [capítulo 13](13-v9990-geo3d.md). Con el perfil TR (bit 2 de `MBOX+0xC4`, [capítulo 15](15-perfil-tr.md)) no pinta nada: no hay V9990. Con el perfil Dual y `'V','D'` pinta el **escritorio de dos columnas** (layout 9: las tarjetas abajo y el marco de la ventana de B; [capítulo 14](14-perfil-dual.md), apartado 13) | `s3_link.c`, `ota.c`, `dual.c`, PL (`v9990_arm_port.v`) |
| `yrw801.c`, `yrw801.h` | Suma de comprobación de los 2 MB de la ROM de ondas del OPL4 en la DDR, por tramos de 32 KB; el resultado sale en el panel y en la OLED | `osd_info.c`, `oled.c` |

Los textos de las páginas están en castellano o inglés según el menú de la imagen que corre (`T(es, en)`).

### 5.4 Red

| Fichero | Función | Habla con |
|---|---|---|
| `net.c`, `net_phy.c` | GEM0 del PS con el PHY RTL8211E (MDIO en MIO 52/53) y lwIP en modo sondeo: DHCP (nombre `msximus`), DNS, ARP, ICMP y un eco TCP en el puerto 7. `net_phy.c` sustituye al fichero de PHY del puerto Xilinx, que bloquea hasta 30 s sin cable: aquí solo lee el PHY y devuelve al momento. La máquina de estados del enlace es propia | GEM0, lwIP |
| `esp_link.c` | El «ESP32» virtual: habla con el `wifi_lite` del MSX por la UART1 (EMIO) a 869 565 baud con control de flujo automático, y analiza el protocolo del firmware ESP32-UNAPI de ducasp (comando rápido de 1 byte, o byte + tamaño + datos). Está activo mientras el cable tenga enlace (`MBOX+0x1C` bit 3); sin cable, la UART vuelve al ESP32 del CAM1 | PL (`wifi_lite`), `esp_cmd.c`, `esp_tcp.c` |
| `esp_cmd.c` | Comandos propios del firmware (reset, versión `MSXIMUS-ZYNQ`, estado, ajustes, hora por SNTP) y UNAPI no de conexión. Presenta una sola red, «Ethernet», siempre conectada mientras haya cable e IP | `esp_link.c` |
| `esp_tcp.c` | Cuatro conexiones TCP/UDP y DNS sobre la API raw de lwIP, sin bloquear; TCP con TLS cuando el MSX lo pide | lwIP, `esp_tls.c`, `esp_tsx.c` |
| `esp_tls.c` | Sesiones TLS 1.2 cliente con Mbed TLS sobre un pcb de lwIP, sin verificar certificados; entropía mezclada de varias fuentes (no hay TRNG) y CTR-DRBG; el texto en claro, a un anillo | `esp_tcp.c`, `esp_tsx.c`, `ota.c` |
| `esp_tsx.c`, `esp.h` | El host virtual `tsx.msximus`: el catálogo de cintas TSX de tsx.eslamejor.com servido al menú con el formato del File-Hunter, y la descarga por https de la cinta elegida (CRC-32 al vuelo) | `esp_tcp.c`, `esp_tls.c`, `tsxcat.h` |
| `s3_link.c`, `s3.h` | La red sin cable para la actualización: toma la UART1 para hablar con el ESP32-S3 del CAM1 y su WiFi (DNS, UDP, TCP y TLS los hace el ESP), a 862 069 baud | PL (`MBOX+0x1C` bit 4), `ota.c` |

### 5.5 Audio y cinta

| Fichero | Función | Habla con |
|---|---|---|
| `wavegame.c` | WaveGame (órdenes del Z80 por el puerto 92h: tocar, bucle, fade, pausa…) y música del menú (órdenes `W` por el 93h: pista, siguiente, parar, nota de prueba). Descodifica WAV (1 o 2 canales, 8 o 16 bits, cualquier frecuencia) y MP3, remuestrea a 44,1 kHz con ganancia y fundidos, y escribe un anillo PCM de 32768 muestras (siempre en múltiplos de 64) que el PL trae con ráfagas. Es también quien recoge los mensajes del menú de la cinta (`T`,`S`/`T`,`X`) | PL (anillo en +0x80000, control +0x20), `mp3.c`, `tape.c` |
| `mp3.c`, `mp3.h` | Fuente MP3 sobre minimp3 (NEON), una trama cada vez. Usa memoria normal: sobre *strongly-ordered* el `memcpy` aborta | `wavegame.c` |
| `tape.c` | Cinta virtual: carga el `.tsx` o `.cas` en la DDR, lo convierte bloque a bloque en pulsos `{nivel, ciclos de 54 MHz}` en el anillo de +0xA0000, mantiene el anillo por delante del PL y teclea la orden de carga (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`+`RUN` o la `TSX.LOAD` de la cinta) al ver `Ok` en la pantalla. Véase el [capítulo 10](10-cinta.md) | PL (+0x28, +0xC8, +0xCC), `usb_host.c` (`kbd_synth_set`), VRAM y RAM del Z80 |

### 5.6 QSPI y actualización

| Fichero | Función | Habla con |
|---|---|---|
| `qspi_cfg.c` | Dueño de la QSPI: el sector de ajustes (`cfg_load`, `cfg_poll`, y las opciones de vídeo 4:3) y el acceso de bajo nivel para la actualización. Véase el [capítulo 11](11-actualizacion.md) | QSPI, buzón (+0x1C, +0x24, +0x70, +0xC0) |
| `profile.c`, `profile.h` | Carga de un bitstream del PL por la PCAP con el PS vivo (apartado 5.8) | `devcfg` (`fsbl/devcfg/`), SLCR, buzón, `main.c` (`pl_resembra`) |
| `mxpf.c`, `mxpf.h` | Perfiles del PL en la microSD de TF1: formato MXPF, clasificar la tarjeta y prepararla (dedicada), instalar, cargar, borrar, pedir uno (`mxpf_pide`), el perfil al arrancar (`mxpf_arranque`) y órdenes por la zona de la DDR (apartado 5.9) | `main.c` (E/S de TF1), `profile.c`, `inflate.c`, Mbed TLS (SHA-256), `ota.c` |
| `perfiles.c`, `perfiles.h` | La página Perfiles del panel F12: vista de la tarjeta y vista del servidor (apartado 5.9); `perfil_nombre` es el nombre que se enseña (*Música* / *Music*, *Dual*; el id interno no cambia) | `mxpf.c`, `ota.c`, `qspi_cfg.c`, `osd_dib.c` |
| `dual.c`, `dual.h` | La máquina B del perfil Dual: la ROM que manda el menú (composición del cartucho como `tools/dual_rom.tcl cargar`, palabra de control `0x1FFB0004`), la página «Máquina B» del panel F12 ([capítulo 14](14-perfil-dual.md), apartados 11 y 12) y, en el escritorio de dos columnas, la posición fina de B (`0x1FFB0008`), el foco del teclado y el ratón: lee la telemetría `MBOX+0xD0` (puntero, ventana de A, foco) y mueve la ventana de B (apartado 13). Z1.3.2b8: el silencio por máquina (clic en los cuadraditos cian de las barras y teclas A y B del panel; peticiones en los bits 22-25 de `0x1FFB0008`, estado real en los bits 47-48 de la telemetría) | `wavegame.c` (trama del 93h, FAT de la TF2), `mxpf.c` (`mxpf_id_activo`), `osd.c`, `perfiles.c` |
| `perfiles_ext.c`, `perfiles_ext.h` | Peticiones del menú del MSX sobre perfiles: instalar un `.MXP` de la TF2 y cargar el que pide la etiqueta de una ROM (apartado 5.9) | `wavegame.c` (FAT de la TF2, mensajes del 93h), `mxpf.c`, `perfiles.c`, `osd.c` |
| `inflate.c`, `inflate.h` | Descompresor zlib propio (apartado 5.9) | `mxpf.c` |
| `ota.c`, `ota.h`, `ota_clave.h` | Actualización por red: prueba de la ranura B, cliente HTTP/HTTPS, comprobación de firma y de imagen, grabación y confirmación, y la página del OSD | QSPI, lwIP, `esp_tls.c`, `s3_link.c`, `osd.c` |

### 5.7 Utilidades

| Fichero | Función |
|---|---|
| `log.c`, `log.h` | Log en anillo en la DDR (`log_str`, `log_hex`, `log_dec`, `log_printf`) y `memset`/`memcpy` mínimos (sin libc para el driver) |
| `bsp/support.c` | `usleep`/`sleep` y `gt_now` con el temporizador global del A9 (CPU/2), `tusb_time_millis_api`, la salida de `xil_printf` al log |
| `pgmspace.h` | Define `PROGMEM` vacío para poder incluir `tsxcat.h` (copia del catálogo del repo del ESP), escrito para Arduino |

### 5.8 Carga de un bitstream por PCAP (prueba de los perfiles)

`profile.c` reconfigura el PL con el PS vivo (fase 4 del estudio de perfiles; sin pasar por la TF1: el bitstream llega a la DDR por JTAG con `tools/pcap_prueba.tcl`). `perfil_poll` mira cada vuelta la **zona de la prueba** (0x1F400000, 4 MB, sin caché): `+0x00` magia `PCAP`, `+0x04` tamaño, `+0x08` comprobación (`magia ^ tamaño ^ 0xA5A5A5A5`), `+0x10` estado (1 en curso, 2 OK, 0x80+n rechazado sin tocar el PL), `+0x14` etapa, `+0x18..+0x30` tiempos en µs (parado, aislado, init, DMA, DONE, PL vivo, MSX suelto), `+0x34/+0x38` INT_STS y STATUS del devcfg, `+0x3C` código del error, y el bitstream en `+0x1000`. **Formato**: el `.bin` de `bootgen -arch zynq -image x.bif -process_bitstream bin` (palabras con los bytes girados: el sincronismo `0xAA995566` aparece como `66 55 99 AA`), que es lo que el FSBL carga del `BOOT.bin` y lo que acepta la PCAP; el `.bit` de Vivado y el `.bin` de `write_bitstream -bin_file` (sin girar) se rechazan.

La secuencia es la del gestor de FPGA de Linux (`zynq-fpga.c`): comprobar el bitstream y que no haya actualización por red ni la S3 en la UART1 (hasta aquí un error se devuelve y no se ha tocado nada); parar WaveGame y cinta y `MSX_RUN = 0`; `FPGA_RST_CTRL` a 0xF, 20 ms para que los backends drenen y `LVL_SHFTR_EN` a 0 y luego 0xA (solo PS → PL); PROG_B (INIT sube, baja, sube); `PCAP_PR | PCAP_MODE`; DMA con `XDcfg_Transfer` (origen con el bit 0 = último, destino 0xFFFFFFFF); esperar `D_P_DONE` y `PCFG_DONE`; `LVL_SHFTR_EN` a 0xF y resets fuera; esperar la magia `MBOX` en la telemetría del PL nuevo; sembrar lo que sembraba el arranque (`pl_resembra` en `main.c`: SDBOX sin petición ni acuse —el `REQ_SEQ` del PL nuevo empieza en 0—, modo y tarjeta, VRAM del V9968 a cero, la config de la QSPI con `cfg_load`, `tape_init`, `v99desk_init`); soltar `MSX_RUN`; y por último rearmar la UART0/OLED (`osd_pl_rearma`) y la UART1/ESP (`esp_pl_rearma`). Si algo falla desde el aislamiento (INIT, error de AXI, `DONE` que no llega, PL que no contesta) se anota el informe y se llama a `ota_reinicia_ps`: reinicio del PS en la misma ranura y el BootROM vuelve a cargar el perfil de la QSPI o de la SD (con SW1 en JTAG no hay BootROM que cargue nada y el PS se queda parado; el reinicio también pone a cero el buzón, con el log).

Qué toca el PL desde el companion (auditoría del 30/10): ningún acceso por AXI GP; solo la DDR (buzón, SDBOX/SDBUF, anillos del WaveGame, de la cinta y del V9990), la UART0 (OSD), la UART1 (ESP/S3) y el GPIO (OLED) por EMIO, y `IRQ_F2P[0]` para despertar el `WFI`. El companion es de un solo hilo y con las interrupciones enmascaradas, así que mientras dura la carga no corre ningún `*_poll`; USB0 y GEM0 siguen con su DMA (MIO, no dependen del PL). No hay perro guardián del companion (solo vigila el EHCI del USB, apartado 5.2).

Banco en el PC: `tests/perfil_host/run_host_perfil.sh` (el `profile.c` real y el driver devcfg real contra un modelo del devcfg, el SLCR y el buzón).

### 5.9 Perfiles del PL en la TF1 (MXPF)

Fase 5 del estudio de perfiles (estudio interno, no publicado) (apartados 6.2 a 6.6). `mxpf.c` guarda perfiles (bitstreams del PL) en una **partición propia de la microSD de TF1, sin sistema de ficheros**, y los carga por PCAP con `profile.c`. Nextor solo monta particiones FAT12, FAT16, FAT16 pequeña y FAT16 LBA (`AA_PX_NOEX`, `partit.mac`) y se salta cualquier otro tipo: no ve la partición. Sin TF1, o con una tarjeta sin la partición, solo existe el perfil 1 (el del `BOOT.bin`) y todo sigue como antes. Las dos cosas que se diferencian de lo que propuso el estudio: las entradas del directorio miden 80 B (caben la versión de 16 caracteres y el SHA-256: **6 perfiles por tarjeta**, no 7) y el fichero de intercambio es el `.mxp`.

**Formato** (little-endian, sectores de 512 B; los LBA de los campos son relativos al inicio de la partición):

| Dónde | Contenido |
|---|---|
| MBR de la tarjeta | **Dedicada** (Z1.4.3): P1 tipo `0x0C` en el sector 2048 (262144 sectores) y P2 tipo `0xDA` en el 264192 (1048576 sectores). **Compartida** (las betas, que siguen funcionando): una entrada libre pasa a `0xDA` (CHS `FE FF FF`, sin bandera de arranque), inicio alineado a 1 MB tras la última partición; 17 MB como mínimo, 32 MB si hay sitio |
| sector 0 | Superbloque: `+0` `MXPF`, `+4` versión (1), `+8` sectores de la partición, `+12` primer hueco (2048), `+16` sectores por hueco (8192 = 4 MB), `+20` número de huecos (≤ 6), `+24` sector de la copia del MBR (3), `+28` banderas (bit 0 = «dedicada»; era un campo libre a 0, las betas lo ignoran), `+32` `MSXimus Z`, `+0x1FC` CRC-32 de los 508 primeros bytes |
| sectores 1 y 2 | Directorio A y B: `+0` `MXPD`, `+4` secuencia, `+8` número de entradas (≤ 6), `+16` las entradas de 80 B, `+0x1FC` CRC-32. Manda el más alto con CRC bueno (la comparación es módulo 2^32); se escribe **siempre el que no manda**, con la secuencia + 1 |
| sector 3 | Copia del sector 0 original de la tarjeta (el MBR de antes de preparar), para poder recuperarlo |
| desde el sector 2048 | Huecos de 4 MB; el contenido guardado de cada perfil empieza al principio de su hueco y se rellena a 512 B |

Entrada de 80 B: `+0` id (8, ASCII `A-Z 0-9 _ -`, relleno de ceros), `+8` serie del sistema para el que se construyó, `+12` versión (16, ASCII), `+28` método (0 crudo, 1 zlib), `+29` banderas (bit 0 = usada), `+32` LBA del hueco, `+36` bytes guardados (≤ 3,5 MB), `+40` bytes del `.bin` (el de `bootgen -process_bitstream bin`, múltiplo de 4, ≤ `PF_MAX`), `+44` reservado, `+48` SHA-256 de lo guardado.

**El `.mxp`** (lo hace `tools/mxpf.py empaquetar`; es lo que se instala): sector 0 = `MXP1`, versión (1), 512, CRC-32 de la entrada, la entrada de 80 B con el LBA a 0; desde el byte 512 el contenido guardado, relleno a 512 B. El `.bin` de un perfil mide ~2,65 MB y comprimido con zlib ~1,32 MB.

**Clasificar la tarjeta** (`mxpf_clasifica`, solo lee). `SIN_TARJETA` y `ERROR` no necesitan explicación. **`NUESTRA`**: el MBR es exactamente el dedicado (P1 `0x0C` + P2 `0xDA` en los sitios de arriba), el superbloque de P2 es bueno y lleva el indicador, y P1 empieza por una FAT32. **`NUESTRA_ANTIGUA`**: una `0xDA` con superbloque bueno sin el indicador (las betas): se usa tal cual. **`DANADA`**: superbloque bueno y los dos directorios rotos. **`INTERRUMPIDA`**: un superbloque dedicado en la posición fija de P2 (sector 264192) pero un MBR que no es el dedicado (se fue la luz preparando). **`VACIA`**: el primer MiB entero a 0 (el sector 0 puede llevar la firma 55AA) o entero a FF. **`AJENA`**: cualquier otra cosa (con su formato, número de particiones y si hay una FAT16 = «datos de MSX-DOS»). **`DEFECTUOSA`**: menos de 641 MiB (`MXPF_E_SITIO`) o ya falló la prueba de tarjeta falsa con esa tarjeta (`MXPF_E_FALSA`; se recuerda por tamaño y CRC del sector 0).

**Preparar la tarjeta** (`mxpf_prepara_dedicada`; `mxpf_prepara` es el legado de las betas, que añade la `0xDA` compartida sin borrar nada, y solo lo usan los bancos). Con `DANADA` rehace los directorios (no borra nada); con `VACIA` y `INTERRUMPIDA` no pide más; con **`AJENA` y `NUESTRA_ANTIGUA` (convertir) borra la tarjeta entera**. Salvaguardas, cada una con prueba en `tests/mxpf_host`:

1. **Arranque desde SD** (`BOOT_MODE` 5): la TF1 es la tarjeta de arranque, nunca se prepara ni se borra, ni confirmada (`MXPF_E_ARRANQUE_SD`); tampoco se arma la confirmación.
2. **Dos teclas** (`AJENA`, `NUESTRA_ANTIGUA`): `mxpf_ded_arma()` (la primera, B) y `mxpf_prepara_dedicada(1)` (la segunda, Intro) con la **misma tarjeta** (tamaño y CRC del sector 0) y antes de 12 s (la página cancela a los 10); cualquier otra orden o tecla desarma. `INTERRUMPIDA` pide solo la primera. Sin eso: `MXPF_E_CONFIRMA` y ni un sector escrito.
3. **Prueba de tarjeta falsa** antes de tocar nada útil: sectores con patrones distintos en P2+0, P2+256 MiB, el último de P2, el último de la tarjeta y los sectores 2^20 a 2^31; se escriben todos y luego se leen. Una tarjeta que repite direcciones (dos potencias de 2 por encima de su capacidad real caen en el mismo sitio) o que tira lo que cae fuera no los conserva: `MXPF_E_FALSA`, el sector 0 se deja como estaba. No sustituye a H2testw.
4. **Orden de escritura** contra apagones, releyendo cada sector: P2 entera (copia del sector 0 original en P2+3, directorio B, directorio A y el superbloque **el último**), P1 (FAT32 de 512 B por cluster, `MSXIMUS-Z`, `LEEME.TXT`: reservados, las dos FAT, la raíz y el LEEME, unos 4069 sectores; el resto de P1 no se toca), el primer sector de las particiones viejas que no han quedado tapadas (y las cabeceras GPT: LBA 1 y el último sector), y el **MBR al final**. Hasta el MBR la tarjeta es la de antes (`AJENA`...) o `INTERRUMPIDA`.

`tools/mxpf.py imagen crear|preparar --dedicada` produce **byte a byte** lo mismo (el banco lo compara) y `fsck.fat` acepta la P1. Quien llama pide la confirmación: el panel (B e Intro; T e Intro para las que no borran) y `perfiles.tcl dedicada <MB> PELIGRO` (palabra, tamaño de la tarjeta y dos marcas escritas por separado).

**Instalar** (`mxpf_instala`): comprueba la cabecera y el SHA-256 del `.mxp` y descomprime una vez a memoria (el `.bin` tiene que tener el sincronismo `66 55 99 AA`) **antes de escribir nada**; elige un hueco que no use el directorio vigente (el perfil del mismo id sigue en el suyo hasta el final, así que con la tarjeta llena hay que borrar antes); escribe el contenido en trozos de 128 KB, lo relee y comprueba su SHA-256, y solo entonces escribe el sector de directorio. Un apagón durante los datos no cambia nada visible; durante el sector de directorio deja el estado de antes o el nuevo (un sector a medias falla su CRC). La suposición es que la SD escribe un sector de 512 B de forma atómica; el MBR a medias no está cubierto (de ahí la copia del sector 3).

**Cargar** (`mxpf_carga`): rechaza si hay actualización por red en curso o si la serie del perfil no es la del `BOOT.bin` que corre (`ota_serie()`; sin serie, como en un arranque por JTAG, se permite); lee el contenido a la zona sin caché, lo copia a la zona con caché, comprueba el SHA-256, descomprime y llama a `perfil_cargar` (apartado 5.8). Los tiempos de cada paso quedan en el informe y en el log. **Volver al perfil 1** es `ota_reinicia_ps()` (con SW1 en JTAG no se puede: no hay BootROM).

**Memoria.** `Xil_DCache*` son vacías y la memoria del companion es *strongly-ordered* salvo unas zonas (`mmu.c`), así que el DMA de la SD lee y escribe **solo** en la zona de `PF_ZONA` (0x1F400000, sin caché) y lo que se recorre muchas veces (SHA-256, zlib) se copia antes a la zona con caché de la actualización por red (0x01000000, la de `ota.c`, que no se usa si `ota_ocupada()`). Reparto de `PF_ZONA`: `+0x100` órdenes, `+0x200` informe, `+0x400` texto, `+0x1000` el `.mxp` (o el contenido leído), `+0x3F0000` 64 KB de sectores de trabajo. Con caché: `+0` contenido guardado (3,5 MB), `+0x380000` rebote de 64 KB, `+0x390000` tablas de zlib y SHA, `+0x400000` el `.bin` descomprimido (hasta 4 MB), que es lo que recibe `perfil_cargar` (que limpia la L1 antes del DMA de la PCAP). Un bitstream de la prueba de PCAP no debería pasar de 3,9 MB (los reales miden 2,7 MB). **La pila también es *strongly-ordered***: el SHA-256 de Mbed TLS (324 B de pila y 296 escrituras de byte en cada bloque para borrarla) y zlib hacen miles de accesos a la pila por cada KB y el SHA de 1,3 MB habría tardado 1,2-2 s. Por eso corren con SP en la zona con caché (`en_pila`, 16 KB en +0x392000: una sola hebra, interrupciones enmascaradas) y el SHA va en trozos de 64 KB con `sd_ceder()` entre ellos.

**El MSX y la TF1.** La TF1 ya no es de Nextor, pero el MSX sigue pidiendo sectores de TF2 y de la disquetera mientras `mxpf.c` trabaja. Todo corre en el hilo del bucle principal: no hay dos accesos a la vez a `sd1`. Las operaciones largas llaman a `sd_ceder()` entre trozos de 128 KB: sirve la petición del MSX pendiente (`sd_servir()` en `main.c`, el mismo código del bucle) para que el proxy del PL no dé error a los 2 s sin acuse. `last` (el último `REQ_SEQ` atendido) es de fichero y `pl_resembra()` lo pone a 0 porque el PL nuevo empieza su cuenta en 0. `tf1_sectores()` vuelve a sondear la tarjeta si no la había (la han podido meter). Con el panel abierto el Z80 está congelado.

**Descompresor** (`inflate.c`): zlib (RFC 1950/1951) propio, sin código de terceros; las tablas van en memoria con caché (en la estructura `mz_work`) porque cada acceso a memoria *strongly-ordered* cuesta ~100 ns. Banco: `tests/mxpf_host/run_host_inflate.sh` (contra zlib de Python, con AddressSanitizer y UBSan, flujos rotos incluidos).

**Órdenes por la zona** (`mxpf_poll`, para probar sin teclado ni pantalla con `tools/perfiles.tcl`): en `+0x100` magia `MXOR` (la escribe xsdb la última, el companion la borra), `+0x104` orden (1 estado, 2 preparar (legado), 3 instalar, 4 cargar, 5 borrar, 6 perfil1, 7 tarjeta_vacia, 8 dedicada), `+0x108` y `+0x10C` argumentos (instalar: bytes del `.mxp` y «cortar la luz tras N sectores»; cargar y borrar: número de la lista; tarjeta_vacia y dedicada: MB de la tarjeta), `+0x110` id (16 B), `+0x120` y `+0x124` marcas `CON1` y `CON2` (las piden preparar, dedicada, borrar y tarjeta_vacia), `+0x128` comprobación (XOR de las palabras anteriores ^ `0xA5A5A5A5`). Informe en `+0x200`: secuencia (sube al terminar), orden, estado (1 en curso, 2 OK, `0x80` + código), código, ocho tiempos en µs (lee SD, escribe SD, verifica SD, copia, SHA-256, zlib, PCAP, total), perfil activo, número de perfiles, estado de la tarjeta y longitud del texto ASCII de `+0x400`. **`tarjeta_vacia` deja el MBR a cero salvo la firma; es solo para el banco de placa y no está en el panel.**

**Página Perfiles** (`perfiles.c`, tecla P en la página de información del panel F12 o en la de actualización). **Vista de la tarjeta**: la clase de la TF1 (sin tarjeta, vacía, ajena con su formato, de las betas, a medias, defectuosa, dañada, o la partición con los huecos libres), perfil que corre ahora, **perfil al arrancar** (con una estrella en su fila), lista (la primera fila es el perfil 1, siempre) con id, versión y tamaño; los de otra serie, en naranja. Flechas elegir; **Intro** cargar (el panel avisa y repinta antes de la operación larga; con éxito se cierra solo); **D** borrar; **A** perfil al arrancar; **S** vista del servidor; **T** preparar la tarjeta (vacía, a medias o con los directorios rotos), **B** borrar y preparar / convertir (la primera tecla arma `mxpf_ded_arma` y la página dice «¿Seguro?»; Intro hace `mxpf_prepara_dedicada(1)`); con arranque desde SD ninguna arma y la página lo dice; tras preparar con cable busca en el servidor y baja todos los perfiles solos (por WiFi no); Intro sobre el perfil 1 reinicia la placa; **R** relee la tarjeta; ESC cancela lo armado o vuelve. Borrar, preparar, borrar la tarjeta y volver al perfil 1 piden un segundo Intro y caducan a los 10 s. **Vista del servidor** (31/10): la lista de las líneas `perfil=` del manifiesto firmado con su estado frente a la tarjeta, la descarga y su progreso; teclas y comportamiento en el [capítulo 11, apartado 9](11-actualizacion.md). `perfiles_armado()` vale 1 en esa vista (ESC vuelve a la tarjeta en vez de salir del panel).

**Perfil al arrancar.** Se guarda en el sector de ajustes de la QSPI (bytes 16..24, [capítulo 11](11-actualizacion.md)): `cfg_perfil_fija` lo graba y lo relee, `cfg_perfil_arranque` lo da. `main()` llama a `mxpf_arranque` justo antes de soltar el MSX: carga ese perfil de la TF1 con `mxpf_carga` (que ya exige la serie del `BOOT.bin`; `perfil_cargar` suelta el MSX al acabar), así que el MSX nace con el perfil elegido y el arranque tarda ~0,6 s más. Si no se puede (sin tarjeta, no está instalado, otra serie, el PL lo rechaza antes de tocarlo) se sigue con el perfil 1 y se anota en el log. **Marca anti-bucle**: si el PCAP falla ya con el PL tocado, `perfil_cargar` reinicia el PS y volvería a intentarlo para siempre; una marca de dos palabras en la zona de los perfiles (`+0x80`, la DDR sobrevive al reinicio del PS) se pone antes de cargar y se quita al volver, y si al arrancar sigue puesta se arranca el perfil 1 y se borra. Con SW1 en JTAG no se hace (sin BootROM no se recupera un fallo). **Volver al perfil 1** (Intro dos veces sobre la primera fila) es un reinicio del PS, y con un perfil al arrancar puesto el arranque siguiente lo volvería a cargar: `mxpf_perfil1` deja antes otra marca de dos palabras (`+0x88`, «esta vez no») que `mxpf_arranque` consume, y la placa arranca con el perfil 1 una vez (la DDR sobrevive al `PS_SRST`: es lo mismo que `ota_info` ya aprovecha). Un perfil que carga bien pero deja la placa sin imagen o sin teclado no lo detecta ninguna marca; salida: quitar la microSD de TF1 (sin tarjeta arranca el perfil 1) y encender. El ajuste de la QSPI se graba con `q_read` esperando antes a que la flash esté libre (una lectura con la flash borrando devuelve FF y se habría tomado por un bloque vacío); la tecla A no se acepta mientras la actualización usa la QSPI.

**Instalar desde un fichero de TF2** (`perfiles_ext.c`). El navegador del menú etiqueta los `.MXP` como tipo 7 (`ix_is_media`, `tag_hi_p1`) y RETURN manda por el 93h `'W','I'` + `PART_LBA` + `CUR_CLUS` + `FILE_CLUS` (la trama de 14 bytes de `'W','F'`: el 93h es un anillo de 32 entradas que el companion drena cada ~1 ms y 14 caben). `wg_msg_byte` la recoge y `pext_poll` la atiende en el bucle: `tape_fat_locate` da el tamaño y la extensión del fichero por su primer cluster, `tape_file_read` lo lee en trozos de 64 KB a `PF_DATOS` (con `sd_ceder()` entre trozos; antes se para la música del menú, que guarda su sector en el mismo búfer que usa la FAT) y `mxpf_instala` hace el resto, la misma ruta que la orden 3 de `perfiles.tcl` y que la OTA. El **resultado** sale en el panel F12 (`perfiles_aviso_abre` + `osd_abre_perfiles`: la página Perfiles con el cursor sobre el perfil instalado y el mensaje, o por qué no: sin tarjeta, sin partición, `.MXP` dañado o mayor de 3,9 MB, tarjeta llena, actualización en curso): el 93h es de solo escritura y el menú no tiene cómo leer una respuesta (el único camino companion → Z80 de datos es la SD simulada, y habría pedido más Z80 del que cabe), y el panel congela el Z80 mientras se lee, que es lo que se quiere.

**Etiqueta `[P:ID]` en el nombre de una ROM.** Un nombre como `Juego [P:SONIDO].rom` pide el perfil `SONIDO` (hasta 8 caracteres `A-Z 0-9 _ -`, sin distinguir mayúsculas; el primero que haya). El menú manda `'W','Q'` (la trama de `'W','G'` con otra letra, `wg_query_msg`) al dar RETURN sobre una ROM, **antes de cargarla**, y `'W','G'` ya existía al lanzarla: el companion hace la misma comprobación en las dos (si la primera cambia el perfil la segunda ya no tiene nada que hacer). `fat_nombre` (en `wavegame.c`, junto a la FAT de la TF2) lee el **nombre largo** (con un sector propio y sin dejar montada otra partición: no molesta a la música del menú que esté sonando; se llama con cada ROM): las entradas LFN que preceden a la corta, en orden inverso, 13 caracteres UCS-2 cada una (solo ASCII; el resto sale `?`), con la suma de comprobación de la corta (si no cuadra, una LFN huérfana, se usa el 8.3 y no hay etiqueta); admite los 255 caracteres de un nombre largo. Después `mxpf_pide`: si el perfil ya corre, nada; si no, `mxpf_carga` (el MSX se reinicia, la DDR y la megaram se conservan) y `wg_pl_rearma` (el anillo Z80 → ARM del PL nuevo empieza en 0); el panel dice *«ID» cargado. Vuelve a lanzar el juego*. Si no se puede cargar (no está, otra serie, sin tarjeta, actualización en curso) el panel dice por qué **y se reinicia el MSX** (`MSX_RUN` a 0 y a 1), que cancela el lanzamiento: el juego no corre con el perfil equivocado. `[P:1]` no se puede satisfacer cargando: el perfil 1 solo se recupera reiniciando la placa; con otro perfil corriendo, el panel lo dice y se cancela. La tabla de **alias** (`[SND]` → `SONIDO`...) está preparada en `perfiles_ext.c` y **sin activar** (`PERFIL_ALIAS_ACTIVOS = 0`).

**Por qué el lanzamiento no continúa solo tras cargar el perfil.** Se estudió y no se hizo. Cargar un perfil es un PCAP: el Z80 y todos los registros del PL se pierden y la BIOS arranca de cero. La RAM del MSX es la DDR y sobrevive (el companion no la toca; `BOOT_FLAG` en `#E830` ya sobrevive a un `jp #0000`, que es lo que hace el arranque de una ROM con disco, validado en placa con Sonyc), pero `p1_init` pone a cero `#C000-#E7FF` en cada arranque del menú (mapper de la ROM, `MAP_SWIO`, `SRAM_FLAG`, `MIR16`, `INIT_VEC`, el registro de la ROM...) y el estado de la megaram (modo y mapper por SWIO) es de los registros del PL: reanudar `launch_rom` pediría guardar ~20 variables en `#E8xx`, volver a armar la megaram desde cero y saltar al lanzamiento, en un menú al que le quedan 46 B en la página 1 (con el castellano) y 88 B de código en `#A000`. Por eso el companion decide **antes de cargar la ROM** (`'W','Q'`: no se pierde una carga de varios segundos) y el usuario repite el RETURN, una vez, cuando ya corre el perfil. Para continuar solo hará falta podar el menú (candidatos: la ayuda y los mensajes largos en castellano) o mover rutinas a la página 2.

Bancos y herramientas: `tools/mxpf.py` (empaquetar `.bit`/`.bin` a `.mxp`, `info`, e `imagen` para manejar una imagen de disco en fichero; nunca discos físicos), `tools/perfiles.tcl`, `tests/perfil_ota_host` (la descarga por la OTA), `tests/tf2_host` (instalar desde la TF2 y la etiqueta de una ROM, contra una TF2 FAT16 con nombres largos), `tests/cfg_host` (el sector de ajustes y el perfil al arrancar contra una NOR de imitación) y `tests/mxpf_host/run_host_mxpf.sh` (el `mxpf.c` real, `inflate.c` y Mbed TLS contra un disco de imitación: preparar con y sin sitio, MBR lleno, GPT, instalar, reemplazar, borrar, directorio corrupto, SHA-256 y zlib malos, serie, órdenes por la zona, intercambio de imágenes con `mxpf.py` y el **apagón en cada sector escrito**, con corte limpio y con el sector a medias, también con el bitstream real). El banco de la página vuelca las celdas que `tools/osd_render.py` pinta.

## 6. Dependencias externas

Ninguna se versiona: los scripts `arm/get_*.sh` las bajan a carpetas ignoradas por git, con versión fijada.

| Biblioteca | Versión | Script | Para qué | Licencia |
|---|---|---|---|---|
| TinyUSB | commit `7b787da` + `tinyusb-zynq7000.patch` | `get_tinyusb.sh` | Host USB: hubs, HID, XInput, disquetera | MIT |
| Mbed TLS | 3.6.7 | `get_mbedtls.sh` | TLS del «ESP32» por cable, descarga de cintas, actualización y firma ECDSA/SHA-256 | Apache-2.0 |
| minimp3 | commit `ea99364` | `get_minimp3.sh` | Descodificador MP3 de la música del menú | CC0 |
| lwIP | 2.1.1 (del árbol de Vivado) | — | Pila TCP/IP | BSD |

Mbed TLS se compila con su propia configuración (`bsp/msximus_mbedtls_config.h`): cliente TLS 1.2, ECDHE, AES-GCM y ChaCha20-Poly1305, SNI, ECDSA para la firma de la actualización; sin sistema de ficheros, sin hora y sin verificación de certificados. XInput (`xinput/`) sí está en el repositorio, con su licencia.

## 7. Depuración

**El log.** `log.c` escribe texto en un anillo de 0x700 bytes en `LOG_BASE` = 0x1FF00800: `+0` la firma `ALOG`, `+4` el índice de escritura (bytes escritos, sin límite), `+8` los caracteres. Todos los módulos escriben ahí lo que merece la pena: tarjeta detectada o retirada, errores de sector, dispositivos USB montados, IP, pasos de la actualización. `ESP_TRACE` (`esp.h`), `CFG_TUSB_DEBUG` (`tusb_config.h`) y `XI_TRACE` (`usb_host.c`) activan trazas más ruidosas.

**`tools/armlog.tcl`** (XSDB, `hw_server` corriendo) lee el anillo por el core 1 (o por el APU) y lo imprime, y resume el SDBOX: modo, tarjeta, última petición y acuse, lecturas, escrituras, errores y reinicializaciones.

```
xsdb tools/armlog.tcl [n_caracteres=1500]
```

**`tools/armpc.tcl`** para el core 0, imprime `pc`, `lr`, `sp` y la pila de llamadas, y lo vuelve a arrancar (`-hold` lo deja parado). Con `arm-none-eabi-addr2line -e companion.elf <pc>` se sabe en qué función está; si cae en la tabla de vectores, `r0` indica la excepción (apartado 2).

Otras herramientas de `fpga/zynq/tools/` que ven o tocan el buzón: `tel.tcl` (telemetría), `key.tcl` (pulsa teclas), `hid.tcl`, `osd.tcl` (abre y cierra el OSD), `ota.tcl` (teclas de la actualización), `tape.tcl`, `wg.tcl` (inyecta órdenes del WaveGame), `cfg.tcl`, `vsel.tcl`. Para cargar el companion sin grabar: `BOOT_PROXY=1 xsdb tools/boot.tcl` (apartado 9 del [capítulo 01](01-arquitectura.md)); `BOOT_ELF` elige otro binario.

**Pruebas en el PC** (WSL, `gcc`; `arm/companion/tests/`):

| Prueba | Qué comprueba |
|---|---|
| `run.sh` | El parser de mandos (`hid_pad.c`) |
| `run_host_tape.sh` | `tape.c` tal cual: decodifica los pulsos como la BIOS y los compara con los bloques del fichero |
| `run_host_yrw801.sh` | La suma de la ROM de ondas |
| `usb_vigila_host/run_host_usb.sh` | El `ehci.c` parcheado de TinyUSB contra un EHCI de imitación (el controlador carga y retira los qTD y escribe el token de vuelta; el driver rearma tarde y al azar): ninguna transferencia se completa antes de que el HC la retire, ningún qTD en dos QH, control, `qtd_init`, firma de los QH con split, esperas con tope; y la decisión del vigilante con series de muestras (sano, colgado, sin split, `FRINDEX` parado, bucle parado, reinicios seguidos, vuelta de los contadores). Lo repite con el `ehci.c` original, que tiene que fallar |
| `dual_host/run_host_dual.sh` | `dual.c`, `wavegame.c` y el dibujo del panel contra una TF2 FAT16 y la DDR en sus direcciones reales: las 24 comprobaciones de `tb/check_dual_rom.py` contra el C, cada mapper del menú, lo que B no admite, el panel y sus teclas en los dos idiomas y el ratón del escritorio de dos columnas (foco, arrastre, topes), la D sola y el silencio por máquina (257 comprobaciones; capítulo 14, apartado 8) |
| `perfil_host/run_host_perfil.sh` | `profile.c` y el driver devcfg contra un modelo del devcfg, el SLCR y el buzón: sondeo, rechazos que no tocan nada, secuencia de registros y los fallos que acaban en reinicio del PS |
| `ota_host/run_ota_host.sh` | `ota.c` y el hook del FSBL con QSPI y red de imitación (capítulo 11) |
