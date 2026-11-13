<p align="center"><img src="logo/msximus.svg" alt="MSXimus z" width="420"/></p>

# Documentación del MSXimus Z

La documentación del **MSXimus Z**, el MSX2+ en la placa OMDAZZ **ZYNQ MINI** (XC7Z020), al día con la versión **Z1.4.9**. Describe esta placa y solo esta placa: lo que se lee aquí es lo que hace la máquina que se tiene delante.

Son dos documentos distintos y se pueden leer por separado:

- El **manual de usuario** es para quien tiene la placa y quiere usarla: qué grabar, cómo preparar las tarjetas, el menú tecla a tecla, las ROMs, los discos, la red, el audio, el vídeo, la actualización y qué mirar cuando algo no va.
- La **referencia técnica** es para quien quiere entender o modificar el core: los bloques, los puertos, los mapas de memoria, el pack de BIOS, los chips de vídeo, la tarjeta, el companion del ARM, la actualización por red y cómo se construye, se comprueba y se entrega todo esto.

Idioma: castellano en las dos partes. El README de la raíz está también en inglés.

**Sobre esta copia pública.** La referencia técnica es la del repositorio de desarrollo y cita carpetas que aquí no están: `bios/` (el menú de arranque, los drivers de Nextor y las herramientas de los packs, ligados a ROM con copyright), `files/` y `archivo/` (entregas y binarios) y los bancos de pruebas (`fpga/zynq/tb/`, `fpga/zynq/arm/companion/tests/`, `tools/v9968_sim/` y parecidos). Lo que sí se construye desde aquí está en el capítulo [07](tecnica/07-construccion.md).

## Cómo está organizada

| Carpeta | Para quién | Qué contiene |
|---|---|---|
| [`manual/`](manual/) | Quien tiene la placa y quiere usarla | La guía rápida y los doce capítulos del manual |
| [`tecnica/`](tecnica/) | Quien quiere entender o modificar el core | Los quince capítulos de la referencia, con el changelog |
| `img/` | Material de apoyo | Capturas de la salida HDMI (escritorio, perfiles, demos del V9968), fotos del V9968 en marcha y capturas de geo3d |
| `logo/` | Material de apoyo | El logo «MSXimus z»: los dos SVG, la imagen fuente de la pantalla de arranque, su vista previa y el binario de 16 KB que va dentro del pack de BIOS |
| [`geo3d_integration_notes.md`](geo3d_integration_notes.md) | Quien integra geo3d en otro diseño | Notas en inglés de cómo entró geo3d en el MSXimus Z |

## Manual de usuario (`docs/manual/`)

| Nº | Capítulo | Qué cuenta |
|---|---|---|
| 00 | [Guía rápida](manual/00-guia-rapida.md) | Para empezar: qué conectar, las pantallas del menú, el panel F12, los modos de vídeo y todas las teclas, en una sola página |
| 01 | [Qué es el MSXimus Z](manual/01-que-es.md) | La placa y sus dos mitades, lo que trae la máquina, lo que hace falta para montarla y lo que no es |
| 02 | [Instalación](manual/02-instalacion.md) | **Lo que hace falta y la puesta en funcionamiento paso a paso** (sin Vivado). El `BOOT.bin` y sus variantes, el interruptor SW1, grabar la QSPI, arrancar desde TF1, las conexiones, la red, el primer arranque |
| 03 | [Las tarjetas SD: TF1 y TF2](manual/03-tarjeta-sd.md) | Qué hace cada ranura, TF1 para los perfiles (cómo se prepara), qué tarjeta y qué formato pide TF2, qué poner y dónde, WaveGame, etiquetas, discos |
| 04 | [El menú de arranque](manual/04-menu.md) | El navegador, lanzar ROMs y discos, la disquetera USB, Ajustes, WiFi, File-Hunter, el menú de pruebas, la ayuda, el panel F12 y todas las teclas |
| 05 | [ROMs y mappers](manual/05-roms-mappers.md) | La megaram de 8 MB, los mappers y cómo se decide cuál, la SRAM de cartucho, el Game Master 2, el segundo SCC y las ROMs que no lanzan |
| 06 | [MSX-DOS y Nextor](manual/06-msxdos-nextor.md) | Los dos dispositivos, las dos versiones de Nextor, arrancar en DOS, imágenes de disco, rendimiento y la disquetera USB |
| 07 | [La red: Ethernet, WiFi y File-Hunter](manual/07-wifi-file-hunter.md) | Ethernet en J3, la ESP32-S3 en el CAM1, configurar la red con la tecla W, descargar con la tecla F y el diagnóstico rápido |
| 08 | [Audio](manual/08-audio.md) | Los chips, mono y estéreo, la ganancia maestra, el mezclador por fuente, el MoonSound, WaveGame y la música del menú |
| 09 | [Vídeo](manual/09-video.md) | La salida HDMI, el V9968 y el V9990 en una sola pantalla, geo3d, el panel F12 y la OLED |
| 10 | [Problemas frecuentes](manual/10-problemas.md) | Por síntoma, con la causa probable y qué hacer, las herramientas de diagnóstico y cómo reportar un problema |
| 11 | [Cinta virtual](manual/11-cinta.md) | Cargar TSX y CAS desde la SD y bajar cintas desde el menú |
| 12 | [Actualizar por la red](manual/12-actualizar.md) | F12 → U, las cuatro variantes, las ranuras A y B y los errores que enseña la página |

## Referencia técnica (`docs/tecnica/`)

| Nº | Capítulo | Qué cuenta |
|---|---|---|
| 01 | [Arquitectura](tecnica/01-arquitectura.md) | La placa y el chip, el diagrama de bloques, los relojes, los puertos AXI, la DDR3, el buzón PL ↔ ARM y el arranque |
| 02 | [Mapa de puertos de E/S](tecnica/02-puertos-es.md) | Todos los puertos a los que responde el core, la E/S conmutada de 40h a 4Fh y los que existen en un MSX y aquí no |
| 03 | [Mapas de memoria](tecnica/03-mapas-memoria.md) | Slots y páginas del Z80, la DDR3 región a región y la QSPI |
| 04 | [El pack de BIOS](tecnica/04-pack-bios.md) | El fichero de 512 KB, sus ROMs y su procedencia, el menú de 32 KB, cómo se construye y cómo llega a la placa |
| 05 | [El V9968](tecnica/05-v9968.md) | Las generaciones del interfaz, lo que lleva de HRA! y lo añadido, la VRAM en la DDR3 y cómo se comprueba |
| 06 | [La SD: el proxy y la DMA](tecnica/06-sd-dma.md) | El proxy de sectores del companion, la DMA, la TF1 (ya no es de Nextor), el modo imagen y la telemetría |
| 07 | [Construcción y entrega](tecnica/07-construccion.md) | Las herramientas, qué se compila desde el repositorio, cada paso hasta el `BOOT.bin`, dónde está el número de versión y cómo se generan las imágenes y se prueba la actualización por red |
| 08 | [Verificación](tecnica/08-simulacion.md) | Los bancos de pruebas del PL, del companion y del menú, y la placa desde xsdb |
| 09 | [Changelog](tecnica/09-changelog.md) | Qué trae cada versión, en resumen, y lo pendiente |
| 10 | [La cinta virtual por dentro](tecnica/10-cinta.md) | El reproductor de pulsos, el conversor TSX/CAS, el menú, la orden de carga y la cinta web |
| 11 | [La actualización por red](tecnica/11-actualizacion.md) | La QSPI, el registro, el FSBL y la ranura B, el manifiesto firmado, el transporte, la confirmación y las herramientas de publicación |
| 12 | [El companion](tecnica/12-companion.md) | El programa del ARM: construcción, arranque, bucle principal, buzón, cada módulo, dependencias y depuración |
| 13 | [El V9990 y geo3d](tecnica/13-v9990-geo3d.md) | El tiny9990, su VRAM, el puente al HDMI, y el coprocesador 3D de Alex Moncks |
| 14 | [El perfil Dual](tecnica/14-perfil-dual.md) | Dos MSX a la vez (prueba de concepto, V9990 dentro y OPL4 fuera): la máquina B, su control por el buzón, su imagen como rectángulo del frame buffer del V9990, el reparto de la DDR y de los puertos AXI y los bancos |
| 15 | [El perfil TR](tecnica/15-perfil-tr.md) | Los perfiles Turbo R y Turbo R V9990: el R800 y el Z80 con cambio en caliente, el regulador de velocidad del R800, la BIOS del turbo R, el PCM, el mapper de 2 MB, los puertos y el aviso al companion |

## Otros documentos del repositorio

| Documento | Qué cuenta |
|---|---|
| [`README.md`](../README.md) · [`README.es.md`](../README.es.md) | La portada: qué es, qué hace falta, instalación, actualización y construcción |
| [`UPSTREAM.md`](../UPSTREAM.md) | El código de terceros, su procedencia, su commit y su licencia |
| [README del repo del ESP](https://github.com/Papipapito/ESP32-for-FPGA/blob/c6/README.md) | El firmware del módulo WiFi (vive en `Papipapito/ESP32-for-FPGA`, rama `c6`): compilar y grabar |
| [MSX SD Maker](https://github.com/Papipapito/SD_Maker) | El programa para preparar la tarjeta TF2: trae el contenido de la SD y la deja lista (repositorio aparte) |
