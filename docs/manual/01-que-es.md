# 01. Qué es el MSXimus Z

Un **MSX2+ completo dentro de una FPGA**, en la placa OMDAZZ ZYNQ MINI. No necesita un MSX: es un MSX. Se conecta a un televisor o a un monitor por HDMI, se le enchufa un teclado USB y arranca en un MSX-DOS o en un menú desde el que se lanzan juegos y discos guardados en una tarjeta microSD.

MSXimus Z es la **línea Zynq del MSXimus**, el MSX2+ con V9968 que nació en la Tang Console 60K. El MSXimus, a su vez, es el hermano mayor del [MSXnano](https://github.com/Papipapito/MSXnano): la misma línea de core (goauld, luego MSXnano), portada a una placa con más recursos y ampliada con lo que en la pequeña no cabía. Nano era el pequeño; Maximus el grande; la Z es el mismo grande en un chip con procesador.

La versión vigente es la **Z1.4.9**: la de la release de GitHub y la que ofrece la actualización por red. Este manual describe solo esta placa. El repositorio contiene el core (`fpga/`) y el programa del procesador (`fpga/zynq/arm/`); el menú de arranque y los packs de BIOS no se publican, y el firmware del ESP32 vive en su propio repositorio, [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`).

## La placa: dos mitades

El XC7Z020 no es una FPGA a secas. Es un Zynq-7000: en el mismo chip hay una FPGA (el **PL**, la lógica programable, del tamaño de un Artix-7 de 85K celdas) y un procesador (el **PS**, dos Cortex-A9 a 666 MHz con 512 MB de DDR3 colgados). El MSXimus Z usa las dos mitades:

- En el **PL** corre el MSX entero: el Z80, el V9968, los chips de sonido, la megaram, los mappers y toda la E/S. Es el mismo núcleo del MSXimus, con los cambios que impone la placa.
- En el **PS** corre un programa pequeño y sin sistema operativo, el **companion**, que hace lo que no tiene sentido hacer en lógica: sirve la tarjeta microSD al MSX, atiende el USB (teclado, mandos, ratón y disquetera), el puerto Ethernet, dibuja el panel F12 y la pantallita OLED, guarda los ajustes en la memoria QSPI, reproduce la música WaveGame y **actualiza la placa por la red**.

Las dos mitades se hablan por buzones en la DDR3. La memoria del MSX también vive ahí: la RAM del Z80, la VRAM, la megaram de 8 MB, el pack de BIOS y la tabla de ondas del OPL4. Sobra sitio: el diseño usa 512 MB.

## Lo que trae

| | |
|---|---|
| **CPU** | Z80 a 3,58 MHz, con turbo real a 5,37 MHz al estilo Panasonic (tecla F11) y el temporizador del sistema del turbo R (puertos E6h/E7h) que usan las demos de geo3d. El **R800** está en los perfiles Turbo R (fila *Perfiles*). La RAM va en la DDR3 detrás de una caché de 64 KB dentro del chip: en los aciertos no hay esperas, y en los fallos se frena al Z80 con `/WAIT` |
| **Vídeo** | El **V9968** de HRA!, un V9958 ampliado con 256 KB de VRAM, comandos rápidos, paleta de 32768 colores y sprites multicolor escalables, en su generación C. Y un **V9990** en los puertos 60h-6Fh con su propia imagen: la tecla **Pausa** conmuta el HDMI entre los dos. La VRAM está en la DDR3. Salida HDMI 720p, con bordes como un monitor de tubo, scanlines opcionales y 50 o 60 Hz; a pantalla completa, 16:9 o 4:3 con Scale3x ([capítulo 09](09-video.md)) |
| **Escritorio** | Con las teclas **V** y **B** del menú, una ROM o un disco corre dentro de una ventana del escritorio del V9990, que muestra la hora, el nombre del juego y una tarjeta del sistema (IP, temperatura, tiempo encendido, turbo y USB). La hora viene de la red ([capítulo 04](04-menu.md)) |
| **3D** | **geo3d**, el coprocesador 3D de Alex Moncks, en los puertos 9Dh y 9Fh: transforma, recorta, sombrea y dibuja las caras él mismo con el motor de comandos del V9968 |
| **Audio** | PSG (dos), SCC y un segundo SCC en el slot 1, OPLL (MSX-MUSIC), MSX-Audio Y8950 con ADPCM, y el MoonSound completo: OPL4 con FM y tabla de ondas, con la YRW801 cargada en la DDR3. Además **WaveGame**, música en WAV que controla el propio juego, y un **mezclador por fuente** en Ajustes: ganancia maestra de x1 a x8 y cada chip de 0/8 a 8/8, con una nota de prueba al cambiar. Mono o estéreo por el HDMI; en estéreo cada chip reparte sus canales entre los dos lados ([capítulo 08](08-audio.md)) |
| **Memoria** | 2 MB de RAM mapeada y una **megaram de 8 MB** para el cartucho emulado, las dos en la DDR3 |
| **Almacenamiento** | Nextor sobre la microSD de la ranura **TF2**, servida por el companion con DMA a 1600 KB/s, y una segunda microSD en **TF1** reservada a los perfiles del sistema (el MSX no la ve). Lanza ROMs de hasta 8 MB con los mappers Konami, Konami-SCC, ASCII8, ASCII16, ASCII16-X, NEO-8 y NEO-16, discos `.dsk`, una **cinta virtual** que carga TSX y CAS ([capítulo 11](11-cinta.md)) y una disquetera USB de 3,5" |
| **Guardado** | La SRAM de los cartuchos ASCII y el Game Master 2 de Konami se guardan en la tarjeta |
| **Entrada** | Teclado, mandos HID genéricos (los "SNES USB" y parecidos), mandos XInput (Xbox 360 y receptores que se presentan como tal) y ratón por el USB host de la placa, a través de un hub si hace falta |
| **Red** | **Ethernet** por el conector **J3** de la placa, sin comprar nada más (el companion hace de ESP32 del MSX: UNAPI, File-Hunter, hget y TLS), o **WiFi** con una Waveshare ESP32-S3-LCD-1.69 en el header CAM1. Descarga de ROMs, discos y cintas con File-Hunter desde el propio menú |
| **Actualizaciones** | **Por la red**, por cable o por WiFi: **F12 → U**. Dos ranuras en la QSPI, un manifiesto firmado y la imagen de fábrica siempre a mano ([capítulo 12](12-actualizar.md)) |
| **Variantes** | Cuatro: Nextor 2 o Nextor 3, con los menús, los Ajustes y el panel en castellano o en inglés. Se elige al grabar y se cambia después desde F12 → U |
| **Ajustes** | Se guardan en la QSPI de la placa con "Save & Restart" y sobreviven al apagado: slot 1 (nada, segundo SCC o Game Master 2), scanlines, estéreo, turbo al arrancar, menú al arrancar y los niveles del mezclador. Manteniendo **S** durante el logo se entra en Ajustes aunque el menú esté apagado |
| **Arranque** | Autónomo, sin PC: desde la QSPI o desde una microSD en la ranura **TF1** con el `BOOT.bin` en la raíz |
| **Panel** | Con **F12**, un panel en color sobre la imagen con la temperatura del chip, las tensiones, la tarjeta, los dispositivos USB, el Z80 y el turbo, el modo de pantalla, el VDP activo y la red; el MSX queda congelado mientras está abierto. Y la **OLED** de la placa como pantallita de estado permanente: versión, temperatura, tarjeta, dispositivos USB, IP, VDP activo, tiempo encendido y velocidad de la CPU |
| **Perfiles** | Otros sistemas para la placa, guardados en la microSD de **TF1** y bajados desde ella (F12 → P → S): **Música** (YM2151 y SN76489), **Dual** (dos MSX2+ a la vez), **Turbo R** (R800 y Z80, PCM, OPL4 y 2 MB de mapper) y **Turbo R V9990**. El de siempre se llama *Normal* ([capítulo 04](04-menu.md)) |
| **Extras** | Logo de arranque, un menú de pruebas para diagnosticar (tecla **T**) y la versión del sistema en Ajustes («Z1.4.9»), la misma de la cabecera del panel F12 y de la OLED |

El menú de arranque es el del MSXimus, de 32 KB en ROM: RETURN lanza, ESC arranca el MSX en DOS, **S** son los Ajustes, **W** la WiFi, **F** File-Hunter, **H** la ayuda. El [capítulo 04](04-menu.md) lo recorre tecla a tecla.

## Lo que hace falta

| | Qué | Notas |
|---|---|---|
| **Obligatorio** | La placa **OMDAZZ ZYNQ MINI** | Con el XC7Z020-CLG400, 512 MB de DDR3, QSPI de 16 MB, dos ranuras microSD, USB host, HDMI, Ethernet y la OLED. Todo lo que usa el MSXimus Z viene soldado; no hay módulos que comprar aparte. Se compra en [AliExpress](https://es.aliexpress.com/item/1005002061806290.html): en el anuncio hay que elegir el modelo **7020** (el core no cabe en el 7010) |
| **Obligatorio** | Una **microSD** en la ranura **TF2** | Es la "SD" del MSX: ROMs, discos y carpetas WaveGame. La primera partición en **FAT16** para que el menú pueda escribir (guardados, descargas); con FAT32 solo lee. El [capítulo 03](03-tarjeta-sd.md) explica cómo prepararla |
| **Obligatorio** | Una segunda **microSD** para **TF1**, de 1 GB o más | Para instalar: con el `BOOT.bin` en la raíz (FAT32 o FAT16) la placa arranca de ella y lo graba en su QSPI ([capítulo 02](02-instalacion.md), *Puesta en funcionamiento*). Después es la tarjeta de los **perfiles** del sistema, que prepara la propia placa ([capítulo 03](03-tarjeta-sd.md)). El interruptor **SW1** elige si se arranca de la QSPI o de TF1 y solo se lee al dar la corriente |
| **Obligatorio** | Cable HDMI y la alimentación (5 V) por el USB-C de la placa | |
| **Obligatorio** | Teclado USB, con un adaptador de USB-C a USB-A (o un hub USB-C) para el conector P3 | La instalación se hace desde el panel F12, y el MSX se usa con él |
| **Obligatorio** | Un PC con lector de microSD | Para preparar TF1 con MSXimusZboot (Windows y macOS, va en la release) y TF2 con MSX SD Maker |
| Opcional | Mando USB HID, ratón USB y disquetera USB | Un hub USB vale para enchufar varios a la vez |
| Recomendado | **Cable Ethernet** en **J3**, con salida a Internet | Para la última versión (F12 → U), los perfiles y File-Hunter. Sin red funciona igual, pero se queda en la versión instalada. J2 es del PL y no se usa |
| Opcional | **Waveshare ESP32-S3-LCD-1.69** | La WiFi, con pantalla de estado, para quien no use el cable. Cuatro hilos al CAM1 (pines 26, 28, 30 y la masa), alimentada por su propio USB-C. El firmware está en su propio repositorio, [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`). Capítulos [02](02-instalacion.md) y [07](07-wifi-file-hunter.md) |
| Ya no hace falta | Vivado 2019.2 y el JTAG de la placa | La primera imagen se graba desde la propia microSD (Z1.4.4 o posterior); las siguientes llegan por la red. Vivado queda para instalar por JTAG, compilar el PL y arrancar por JTAG en desarrollo |

Se recomienda un disipador sobre el chip: con él trabaja a unos 55 °C y sin él a unos 80 (el panel F12 y la OLED enseñan la temperatura).

## Lo que no es

- El sistema normal no es un turbo R: no se identifica como tal y no tiene R800. Para eso están los perfiles Turbo R (F12 → P), que convierten la placa en uno.
- No tiene salida de vídeo ni de audio analógicos. Todo va por el HDMI.
- No tiene conectores de joystick, ni de casete, ni de impresora. Los mandos van por USB.
- No lleva la variante de VDP V9958: el V9968 es el único, y es compatible con todo lo que espera un V9958.
- No es una placa con Linux: el procesador corre solo el companion, sin sistema operativo, y su único trabajo es servir al MSX. No hay consola ni escritorio: la red del ARM solo sirve para hablar con el MSX, que la ve como un ESP32 UNAPI.
- La OLED no enseña la imagen del MSX: es monocroma, de 128x64, y solo sirve de pantallita de estado.
- No arranca sin más el software escrito para la generación B del V9968 (DEVCON, V9968DM, TECH DEMO): tiene que hacer `OUT (9Ch),0` antes de tocar los registros extendidos. V9968DM, que no escribe R#21, necesita además R#21 = 0. Para probarlo sin recompilar está `V9968ON.COM`. El [capítulo 09](09-video.md) lo explica.

## Cómo seguir

El [capítulo 02](02-instalacion.md) explica qué grabar y dónde. El [03](03-tarjeta-sd.md), cómo preparar la tarjeta. El [04](04-menu.md), el menú tecla a tecla. Los siguientes van tema por tema: ROMs, discos, red, audio, vídeo, problemas, cinta y actualizaciones por red ([12](12-actualizar.md)). Quien quiera saber cómo está hecho por dentro tiene la [referencia técnica](../INDICE.md#referencia-técnica-docstecnica).
