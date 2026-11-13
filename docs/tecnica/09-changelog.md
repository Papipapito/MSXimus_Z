# 09. Changelog

Qué trae cada versión del MSXimus Z, de la más nueva a la más antigua. Las versiones grandes salen en la
[release de GitHub](https://github.com/Papipapito/MSXimus_Z/releases); todas, por la actualización por red (F12 → U).

## Z1.4.9 — 13/11/2026 · oficial (GitHub y la red) · El R800 ya no se duerme tras un HALT, y Ajustes, GM2 y V/B en el menú

**Oficial el 13/11** (serie 2026111301): los mismos binarios de la beta del 12/11 salvo el `ota_info` (serie, fecha y `canal=oficial`); en GitHub con los cuatro `BOOT.bin` y **MSXimusZboot** (Windows y macOS), sin `.elf` ni `.bit`. Reúne las betas Z1.4.5 a Z1.4.8 (abajo). La beta fue la serie 2026111109.

El PL del estándar, Música y Dual es el de la Z1.4.7 (`FPGA_PATCH` = 7). Los perfiles **TR y TRV se recompilan** con los dos primeros arreglos. Todo sale de lo que se vio en placa con la Z1.4.4 y la Z1.4.8.

- **TR/TRV: el R800 tras un HALT largo** (`fpga/r800/r800_timing.v`):
  - **Síntoma:** en *Ghosts'n Goblins* V9990 el scroll del mapa que sale al morir iba a saltos en el perfil TRV y no en el normal.
  - **Por qué solo en TR:** el juego pasa él solo al R800 cuando ve un turbo R (`CHGCPU(81h)` desde su INIT), así que mantener pulsado el 1 no cambiaba nada. Espera cada cuadro con `EI/HALT`.
  - **El fallo:** en el HALT el regulador del R800 dejaba de contar el tiempo «de R800», y a los 4,6 ms su resta de 16 bits daba la vuelta. El R800 parecía adelantado y la interrupción que lo despierta entraba hasta 4,4 ms tarde, distinto en cada cuadro: el scroll se escribía con la pantalla a medio pintar.
  - **Arreglo:** pasados 8.192 ciclos de espera, el retraso se acota como al arrancar el R800. Por debajo de ese umbral la temporización no cambia: los bancos de antes del R800 dan la misma salida.
  - **Banco nuevo:** `fpga/r800/sim/run_trv_isr.sh`, el R800 contra el V9990 entero con el patrón del juego. La latencia pasa de 1,0-4,4 ms a 111-148 ns.
  - El mismo arreglo vale para cualquier programa en R800 que espere con HALT más de 4,6 ms, y para el R800 tras el OSD abierto o una DMA larga de la SD.
- **TR/TRV: el panel F12 dice qué CPU manda.** En la sección MSX pone «CPU R800 ROM», «CPU R800 DRAM» o, como siempre, «Z80 3,58 MHz». Lo saca de dos bits nuevos del buzón (`+0x68` bits 15:14). Antes no había forma de saberlo sin la telemetría de depuración.
- **Ajustes enseña la versión del sistema** (la de `ota_info`) y no la del PL: la Z1.4.4 decía «Z1.4.1» y la Z1.4.8, «Z1.4.7». El companion cambia en el pack, antes de soltar el MSX, las dos lecturas de los puertos 2Fh y 29h de Ajustes por `LD A,n` (`ota_menu_version` en `ota.c`). Cambia las dos o ninguna.
- **Lanzar ROM: «GM2: On/Off» y la tecla G solo si Ajustes tiene Slot 1 = Game Master 2.** Antes bastaba un mapper Konami o Konami-SCC: salía con el GM2 apagado en Ajustes.
- **Lanzar ROM: «V/B = V9991» y las teclas V y B solo si el core tiene V9990.** En el perfil TR se anunciaban, y V o B colgaban.
- **Bancos:**
  - `run_trv_isr.sh` (nuevo);
  - `ota_host`: casos 0 (versión de Ajustes) y 0b (la fila de la CPU del F12);
  - `emu_menu_dual.py` con V9990 y GM2 (1194 comprobaciones);
  - `perfil_ota_host`, `mxpf_host`, `tf2_host` y `dual_host` sin fallos.
- **Probada en placa (12/11):** *Ghosts'n Goblins* V9990 en TRV ya no da saltos; con el GM2 apagado en Ajustes, Lanzar ROM ya no lo ofrece; lo demás, bien. Fue la beta de la serie 2026111109; un día después pasó a oficial sin más cambios.

## Z1.4.8 — 11/11/2026 · beta (canal beta de la red) · Los perfiles del servidor ya no se quedan «buscando»

Serie 2026111108. El PL es el de la Z1.4.7 (los mismos `.bit`, `FPGA_PATCH` = 7: Ajustes sigue enseñando «Z1.4.7»; la página de la actualización dice Z1.4.8); los cuatro perfiles se reempaquetan con la serie nueva (F12 → P → S tras actualizar). Cambia solo el programa del ARM, por lo que se vio en placa con la Z1.4.7: en Perfiles → servidor, B no hacía nada y U se quedaba «buscando».

- **U/R y B mandan aunque haya una búsqueda en marcha** (`ota_busca` en `ota.c`): la cortan sin dejar nada abierto (la conexión HTTP, la difusión UDP y la WiFi de la S3, que se suelta y se vuelve a tomar) y buscan otra vez; B, en el otro canal. Antes `ota_tecla` las ignoraba hasta que la búsqueda acabara, y por la WiFi de la S3 son segundos.
- **La búsqueda nunca gira más de 2 minutos**: cada paso ya tenía su plazo (el peor caso por la S3 ronda 95 s), y esto es la red de seguridad por si algo se queda colgado.
- **Arrancada desde la SD, la vista del servidor también busca.** Ahí `ota_tecla` solo atiende la A (grabar la ranura A con el `BOOT.bin` de la TF1), y la vista se quedaba en «Pulsa U para buscar» sin hacer nada. La página de la actualización sigue igual (en SD, U, I y B no hacen nada allí).
- **El perfil 1 se llama «Normal»** («Standard» en inglés): en la lista de Perfiles salía como «BOOT.bin», y en los avisos como «perfil 1». El id interno y la etiqueta `[P:1]` de las ROM no cambian.
- Banco `perfil_ota_host`: tres casos nuevos (B y U a mitad de la búsqueda con cable y con la S3, y la vista del servidor arrancando desde SD), que fallan con el programa de la Z1.4.7. Siguen bien `ota_host`, `mxpf_host` y `tf2_host`.
- Salió como beta sin probar en placa; va dentro de la Z1.4.9.

## Z1.4.7 — 11/11/2026 · beta (canal beta de la red) · El V9990 con los arreglos de openMSX de noviembre

Serie 2026111107; Ajustes enseña «Z1.4.7» (`FPGA_PATCH` = 7) y los cuatro perfiles se recompilan con ella (F12 → P → S tras actualizar).

- **V9990: el motor de comandos, al día con openMSX** (sus arreglos del 5 al 9/11, medidos en un V9990 de verdad; el detalle de cada uno, en el commit `6980173`):
  - **LINE**: el término de error empieza en `max(MJ,2)/2 − 1`, se dibujan MJ+1 puntos y MJ = 0 dibuja uno. Antes toda línea inclinada daba su paso menor tarde y le faltaba un punto (y MJ = 0 dibujaba 4096).
  - **NX de 12 bits**: R#41 bit 3 cuenta y NX = 0 son 4096 píxeles (antes 2048).
  - **BD y BX**: escribir el color (R#48/R#49) borra BD; un SRCH que no encuentra deja en BX el ancho de la imagen (hacia la derecha) o 7FFh (hacia la izquierda), y BD/BX arrancan a 0 con el reset.
  - **P1, LMMV**: rellena las dos capas con R#48; R#49 ya no se cuela en la mitad de los puntos.
  - **SY y DY se escriben de vuelta al acabar cada orden**, como hace el chip (y openMSX desde siempre en los rectángulos): DY avanza NY en LMMC, LMMV, LMMM, CMMC, CMMM…, SY en LMMM, LMCM y LMMV, POINT sube SY en 1, y PSET/ADVN mueven DY según AYE/AYM. Si la CPU escribe ese registro en el mismo ciclo, gana la CPU. No se porta lo que solo hace el chip y no las versiones publicadas de openMSX (NY = FFFh al acabar, SX/DX = 0, BX = SX). El escritorio del ARM y el del menú escriben todos los registros en cada orden: no les afecta.
  - Banco nuevo: `tb_t9990_timing.sv +OMSX=1` (LINE en 445 casos contra un modelo de `executeLINE`, SRCH, BD/FC, NX = 0 y 2049, P1 y la escritura de vuelta en 10 órdenes). Con la Z1.4.6 da 478 fallos.
- **Shim del V9968**: el mux de lectura del victim buffer pasa de prioridad (una cadena de 16) a AND-OR (3 niveles), y el 2:1 de la caché de sprites lo elige `spc_hit1`. Es la misma función (A/B con `tb_manbow`: la misma imagen y las mismas lecturas tardías). Es el mismo fichero que lleva ahora el 138K, al que le hacía falta para el timing.
- **USB**: dos arreglos de host de TinyUSB (`tinyusb-upstream-host.patch`, sin subir el pin): al quitar un teclado o un ratón ya no se descuenta otro que no se llegó a montar, y una memoria que anuncie muchas unidades lógicas ya no se sale de la tabla.
- **Sin probar en placa.** Para probar: demos y juegos del V9990 (Gfx9000) que dibujen con LINE o con órdenes encadenadas, el escritorio del V9990 y quitar y poner teclados y memorias USB.
## Z1.4.6 — 10/11/2026 · beta (canal beta de la red) · Space Manbow sin rayitas y lo que quedaba del V9968 de HRA!

Serie 2026111006; Ajustes enseña «Z1.4.6» (`FPGA_PATCH` = 6) y los cuatro perfiles se recompilan con ella (F12 → P → S tras actualizar). **Probada en placa el 10/11**: *Space Manbow* ya no saca rayitas junto a los sprites.

- **Las rayitas de *Space Manbow*** (ruido de una línea alrededor de la nave y de los enemigos, visto en placa el 10/11 y presente desde al menos la Z1.2.6): el motor de sprites del V9968 lee el dato 14-15 ciclos después de pedirlo, sin esperar, y la VRAM de la Zynq está en la DDR detrás de una caché (el *shim*). En el SCREEN 4 de Konami las tablas de sprites (C800h, F000-FFFFh) caían en las mismas entradas de la caché que las del fondo (0000-3FFFh), el fondo las desalojaba en cada línea y la lectura del sprite iba a la DDR y llegaba tarde: el sprite se pintaba una línea con la X, el color o el patrón de otro. Arreglo: una **caché solo de sprites** de 8 KB en el shim (`v9968_vram_shim.v`, bloque _M1, parámetro `SPC`), que el fondo no puede desalojar y que se sirve en el mismo ciclo que la caché grande. Encontrado con un banco nuevo, `tb_manbow.sv`, que mete en el VDP la VRAM y las interrupciones reales del juego sacadas de openMSX (`manbow_cuadro.tcl`): con VRAM perfecta el cuadro sale idéntico al de openMSX; por el shim, 188 píxeles en rayas; con la caché de sprites, 0 lecturas de sprite equivocadas desde el segundo cuadro. Solo en la Zynq (el Tang usa el mismo shim con `SPC = 0`).

- **Sprites y R#23** (HRA! `c71bc9d`, la otra mitad): la línea de los sprites (con el scroll vertical de R#23) se fija al empezarla. Si el programa cambia R#23 a mitad del barrido de planos, ya no se mezclan dos líneas: la portada de *Dragon Quest II* llegaba a ver 10 sprites en una línea y marcaba un 9.º sprite falso. La Y de la colisión (S#5/S#6) sale de la misma línea.
- **LMCM** (HRA! `419d1ff`, `6094db2`): el comando que pasa la VRAM a la CPU por S#7 leía las coordenadas de destino (DX, DY) en vez de las de origen (SX, SY); ahora lee el origen, como el V9938, y espera a que avancen los contadores entre píxel y píxel. Escribir R#44 carga el color que se lee en S#7 y, con LMCM en marcha, no baja TR.
- Bancos nuevos: `tb_svp_hra.sv` (el banco de HRA! de la selección de sprites, adaptado; su prueba de R#23 falla con la Z1.4.5 y pasa ahora) y `tb_lmcm.sv` (LMCM leído por S#7 con el VDP completo: con la Z1.4.5 fallan los 7 casos, ahora pasan los 14 en modo normal y rápido). Con R#23 fijo la pantalla sale idéntica byte a byte.

## Z1.4.5 — 10/11/2026 · beta (canal beta de la red) · El V9968 de HRA! v0.96-v0.98

Tres arreglos del V9968 de HRA! (sus versiones v0.96 a v0.98, del 6 al 8/11), portados a mano sobre nuestros ficheros:

- **S#0: el 5S se lee a 0 mientras F = 1** (HRA! `c71bc9d`). La rutina de la interrupción de VSYNC ya no ve el 5.º sprite que se marcó durante la imagen. *Dragon Quest II* lo usaba para esconder el logo de su portada. openMSX hace lo mismo («Dragon Quest 2 needs this»). Leído fuera de la interrupción (con F = 0), el 5S se ve como antes.
- **Sprites con CC = 1 y plano 15** (HRA! `1df063f`). La mezcla de los planos empezaba una fase antes de tiempo: un sprite con CC = 1 sin otro con CC = 0 delante se veía (basura en la demo de *AshGuine III*) y, con 16 sprites por línea, el último salía un píxel a la derecha. La colisión cuenta también el plano 13.
- **Comandos del VDP en la franja B** (HRA! `a849a2c`). El motor de comandos podía dar por aceptado un acceso a la VRAM que se llevaba un sprite (*Dragon Slayer* se colgaba en el calabozo). En nuestro RTL ese caso no se da en ningún modo medido; queda cerrado igualmente.
- **Ajustes enseña «Z1.4.5»** (el PL cambia: `FPGA_PATCH` = 5). Los cuatro perfiles (Música, Dual, TR, TRV) se recompilan con el mismo V9968; con la serie nueva (2026111005) hay que volver a bajarlos (F12 → P → S).
- Bancos nuevos en `tools/v9968_sim`: `tb_sprite_cc.sv` (CC = 1, prioridad, 16 sprites por línea: con el RTL anterior falla el CC = 1 y el plano 15), `tb_slotb.sv` (la franja B en 19 modos y configuraciones, y HMMV/LMMM con la pantalla encendida) y fases nuevas en `tb_spcol.sv` (el 5S con F = 0 y F = 1). Detalle en `fpga/v9968/ORIGEN.txt`.
- **Sin probar en placa.** Para probar: la portada de *Dragon Quest II*, la demo de *AshGuine III*, *ZANAC A.I.* (MSX1: OCM-PLD no aplica el 5S AND NOT F en sprites modo 1 por este juego; HRA! y nosotros sí) y *ZANAC EX* / *Space Manbow*.

## Z1.4.4 — 10/11/2026 · GitHub y red · La ranura A desde la SD (sin Vivado)

**Una placa nueva ya no necesita Vivado.** Con SW1 en SD y el `BOOT.bin` de la versión en una microSD FAT32 o FAT16 en TF1, **F12 → U** enseña *BOOT.bin de la SD* y la tecla **A** lo lee y **A, A** lo graba en la ranura A (la de fábrica) de la QSPI. Después, SW1 en QSPI y todo lo demás (preparar la tarjeta de perfiles con F12 → P, bajar los perfiles, actualizar por la red a la ranura B) es el uso de siempre.

- **`bootsd.c`**: lector de solo lectura de la FAT32 o FAT16 de TF1, lo mismo que lee el BootROM para arrancar (con o sin MBR, cualquier tamaño de cluster, fichero fragmentado, nombres largos); entre 4 KB y 8 MB. Reconoce la FAT32 como Windows, por su estructura y no por el número de clusters: la primera prueba en placa rechazaba la tarjeta de los perfiles reformateada en Windows, y la segunda una tarjeta en FAT16 con la que la placa arrancaba. Si no encuentra ninguna, debajo del error dice lo que vio (`MBR 0E 00 00 00 P1:FAT12`, `Sin MBR: exFAT`...).
- **Se comprueba antes de grabar**: cabecera de arranque, `ota_info` y que sea de esta placa. La relectura se compara byte a byte con lo leído. Se borra también el registro de la B, para que el FSBL no salte a una B vieja.
- **Sin riesgo de bloquear la placa**: si se va la luz a mitad, la QSPI no arranca pero la SD sí, y se repite.
- En SD la página no busca por la red (la actualización por red graba la B y desde SD no arranca).
- **Documentación**: lo que hace falta y la puesta en funcionamiento paso a paso, en el README y al principio del capítulo 02 del manual, con una foto de la ranura TF1.
- Serie 2026111004: los perfiles se vuelven a publicar con ella (el mismo contenido que los de la Z1.4.3); un perfil solo se carga con el sistema de su serie, así que tras actualizar hay que volver a bajarlos (F12 → P → S).
- Comprobado en los bancos de PC (`tests/bootsd_host`, casos 25 a 28 de `tests/ota_host`) y **en placa** el 10/11: lee el `BOOT.bin` de una tarjeta FAT16, graba la ranura A y la placa arranca de ella con SW1 en QSPI. Falta probar un apagón a mitad de la grabación. El PL no cambia.

Detalle en el [manual](../manual/02-instalacion.md) (*Puesta en funcionamiento*, y 4.1) y en el [capítulo 11](11-actualizacion.md), sección 11.

## Z1.4.3 — 09/11/2026 · GitHub y red

Reúne la Z1.4.1 y la Z1.4.2 (que no llegaron a publicarse por separado) con la TF1 solo para perfiles: es la primera versión oficial después de la Z1.4.0.

**La microSD de TF1 deja de ser la unidad B: de Nextor y pasa a ser solo la tarjeta de los perfiles.** El MSX ya no la ve de ninguna manera.

- **Quien tenga datos en B: (la TF1 como segunda unidad, desde la Z1.2.13) deja de verlos con esta versión.** Hay que copiarlos antes a TF2 o a un PC. Al preparar la tarjeta la placa avisa de que tiene datos de MSX-DOS (*la antigua B:*) y la borra entera.
- **La placa prepara la tarjeta sola** (F12 → P): una vacía se prepara sin borrar nada; una con otros datos (FAT32 de fábrica, exFAT, la FAT16 de la antigua B:...) pide dos confirmaciones (**B**, y luego Intro; otra tecla o 10 s sin tocar cancelan) y se borra **entera**. La deja con una partición FAT32 de 128 MiB (`MSXIMUS-Z`, con un `LEEME.TXT`; ahí puede ir el `BOOT.bin`) y otra de 512 MiB para los perfiles que Windows no muestra ni ofrece formatear. Hace falta una tarjeta de 1 GB o más.
- **Salvaguardas**: con la placa arrancada desde SD no se prepara ni se borra, aunque se confirme (*«Pon SW1 en QSPI para prepararla»*); se comprueba que la tarjeta guarda lo que se le escribe antes de tocar nada; el MBR se escribe el último, así que si se va la luz la tarjeta queda como estaba o a medias (**T** la termina).
- **Las tarjetas de las betas siguen funcionando tal cual** (la partición de perfiles compartida con una FAT). **B → Convertir** las deja como una nueva y pierde los perfiles instalados, que se vuelven a bajar.
- **Aviso de tarjeta nueva** en la página de información del F12 y en la OLED, sin bloquear nada.
- **Tras preparar con cable**, la placa busca en el servidor y baja los perfiles sola; por WiFi hay que pulsar S y A (el MSX se queda sin ESP mientras baja).
- Los drivers de Nextor no se han tocado: el companion contesta que no hay dispositivo 2. El PL no cambia.
- **El firmware del ESP32-S3 ya no vive en este repositorio**: sale de `esp32/` y se mantiene en [Papipapito/ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`). Solo queda aquí `tsxcat.h`, que el companion usa (ahora en `fpga/zynq/arm/companion/`). El sistema no cambia.
- Imágenes con el PL de la Z1.4.1/Z1.4.2 (no se recompila): Ajustes sigue enseñando «Z1.4.1»; la versión del sistema, «Z1.4.3», se ve en la cabecera del panel F12 y en la OLED. Serie de la OTA 2026110801.

Detalle en el [manual](../manual/03-tarjeta-sd.md) y en el [capítulo 12](12-companion.md), apartado 5.9.

## Z1.4.2 — 06/11/2026 · sin publicar por separado (va en la Z1.4.3) · Multidisco

- **Juegos de varios discos en un `.dsk`**: un fichero de N × 720 KB se monta como N discos de Nextor. Se cambia con el número del disco mantenido y la tecla que pida el juego. Detalle en el [manual](../manual/06-msxdos-nextor.md).
- **Tipo «Multidisco»**: en la ficha del menú, un `.dsk` de varios discos sale como «Multidisco»; uno de 720 KB, como «Disco».
- **Espacio perdido en particiones FAT16**: cada montaje de un `.dsk` creaba de nuevo `NEXTOR.EMU` y perdía un cluster. Ahora se reutiliza. Lo ya perdido se recupera con `chkdsk /f` en el PC.

## Z1.4.1 — 05/11/2026 · sin publicar por separado (va en la Z1.4.3)

Perfil nuevo **Turbo R V9990** y dos arreglos. Los perfiles se bajan desde el panel: F12 → P → S.

- **Perfil Turbo R V9990** (`TRV`): el Turbo R con V9990, OPL4, MSX-Music, tecla Pausa y ventana como en el sistema estándar, y **ROM NEO-16 de hasta 16 MB**. Sin Y8950. Con él corre Monkey Island 2 de Maggoo.
- **Perfil Turbo R**: las ROM de 4 MB o más lanzadas desde el menú salían a MSX-DOS sin arrancar. Arreglado.
- **Nextor 3.0 final** en lugar de la beta 2, con el mismo driver. Las unidades se asignan en orden de dispositivo: A: es la tarjeta de TF2 aunque la de TF1 tenga una partición activa.
- **Nextor 3, modo DOS 1**: deja 640h bytes más por unidad. Illusion City en `.DSK` arranca desde el menú en los perfiles Turbo R y Turbo R V9990.

Detalle técnico en el [capítulo 15](15-perfil-tr.md).

## Z1.4.0 — 04/11/2026 · GitHub y red

Reúne las betas Z1.3.2b1 a b10 (más abajo) y estrena el perfil **Turbo R**. **Los perfiles Música, Dual y Turbo R se bajan desde el panel: F12 → P → S**, después de actualizar a esta versión. Los de una versión anterior hay que volver a bajarlos (**A** los baja todos).

Perfil **Turbo R** (F12 → P):

- **R800 y Z80 con cambio en caliente**, BIOS y BASIC 4.0 del turbo R, modo ROM y modo DRAM, MSX-MUSIC, kanji. La memoria va al ritmo de un turbo R real (Z80BENCH 1.5.1, Mem 8bit: 1261 kB/s; real 1255). La frecuencia equivalente de CPU es 19,7 MHz (openMSX 20,59).
- **PCM del turbo R** (A4h/A5h), en el canal 4 del mezclador. `CALL PCMPLAY` y `PCMPLAY.COM`.
- **OPL4 completo** (FM y wave, con la YRW801), **2 MB de mapper**, ROM del ESP en el slot 3-3 (FileHunter, W y UNAPI) y **Nextor 3**, que va dentro del perfil y necesita una SD de Nextor 3.
- **El menú lanza ROM en el R800** con `[R800]` en el nombre largo del fichero; por defecto, en Z80.
- **Sin** Y8950, V9990, geo3d ni las aplicaciones del FS-A1ST.
- **SofaRun carga ROM** como ESE SCC. Tras apagar la placa, borra la carpeta `SETTINGS` antes de lanzarlo: la vuelve a crear sola.
- **Mezclador:** el canal 4 pasa a llamarse `AUDIO/PCM` en todos los perfiles.
- **Perfiles:** un `.mxp` puede llevar datos además del bitstream.

Detalle técnico en el [capítulo 15](15-perfil-tr.md).

## Z1.3.2b10 — 02/11/2026 · beta

Cambios en el PL (V9968: sprites en YJK) y, solo para el perfil Dual, en el companion, el menú y el driver de Nextor de A (MSX-DOS en B).

- **SCREEN 10, 11 y 12: los sprites se ven y caen donde deben.** Hasta ahora un sprite sobre un píxel YJK quedaba tapado por el
  color YJK (en SCREEN 12 no se veía nunca) y, sobre los puntos con A = 1 de SCREEN 10/11, salía 4 píxeles antes que el fondo. Ahora
  se dibuja sobre cualquier píxel (YJK, A = 0 o A = 1) con su color de la paleta de 16 colores y en el píxel del fondo que le toca,
  como en el V9958 real y en openMSX. Los sprites con mezcla (modo 3, TP) se mezclan con el color YJK del fondo. SCREEN 8 (sprites con
  su tabla fija de 256 colores), SCREEN 5-7 y SCREEN 10-12 sin sprites salen igual que antes, ciclo a ciclo en simulación.
- Sigue igual: la imagen de SCREEN 10, 11 y 12 entera (fondo, borde y ahora los sprites) sale 4 píxeles a la derecha que en SCREEN 8
  (el decodificador YJK retrasa el fondo 4 celdas; en el V9958 real no hay desplazamiento).
- **Perfil Dual: MSX-DOS en la máquina B.** B corre **Nextor 2.1.4** propio y ve la **misma tarjeta de TF2 que A** (entera, su primera
  partición FAT es `A:`). Sin PL nuevo (el bitstream es el de la b8): el cartucho de B es su megaram Konami SCC en modo RAM; el driver
  de Nextor-B habla con el companion por un buzón de 512 + 64 bytes en la DDR, con DI mínimo en las escrituras, una expulsión de la caché
  de B por conflicto de índice (lectura de `6xxxh` antes de `7xxxh`) para ver lo que escribe el ARM, una etiqueta de secuencia (SEQ/ACK) y la
  cancelación de la orden si el ARM no contesta en ~3 s. El companion lleva el Nextor de B comprimido (59 KB) y lo compone al lanzar.
  Capítulo técnico 14, apartado 14.
- **Una sola máquina escribe en la SD: la *dueña*.** La otra solo lee y su escritura da *Disk write protected*. La **D sola** del menú
  lanza el juego en A, arranca MSX-DOS en B y deja la SD en **B**; **Shift + D** manda el juego a B y devuelve la SD a **A**. En el panel
  F12 → Máquina B: tecla **D** = cambiar la dueña (solo con MSX-DOS en B), tecla **M** = MSX-DOS en B. La barra de B dice *MSX - B  MSX-DOS*
  y la tarjeta de abajo, *SD: escribe B / A*. **La que gana la escritura se reinicia** (B: Nextor-B se recompone; A: aviso en el panel
  «Reinicia A si usa MSX-DOS» si B escribió), salvo la D sola con B ya corriendo MSX-DOS y ya dueña. **La SD vuelve sola a A** cuando B deja de
  correr MSX-DOS (P, reinicio al BASIC, C, Shift + D, un cartucho cambiado por JTAG). **No hay «cambiado»** (`DEV_STATUS = 2` hace que Nextor
  desmapee todas las unidades de una tarjeta con varias particiones): los dos LUN son fijos, y la que lee sin ser dueña puede ver datos viejos hasta
  que se reinicie.
- **A sigue guardando la SRAM de la partida con la SD en B.** El menú (`launch_rom`) pinta el escritorio y manda `"V","A"` **después** de
  `srm_launch` y `gm2_launch`, así que A crea o carga el `.SRM` mientras aún escribe; el companion saca de los descriptores del menú
  (`SRM1`, `GM2S`) y de la cadena de clusters de la FAT los rangos de sectores donde A conserva la escritura (el `.SRM` partido en clusters
  da varios). Libres en el menú (castellano / inglés): página 1 18 → 10 B / 227 → 219 B, código en `#A000` 83 → 70 B / 85 → 72 B.
- **Driver de Nextor 2.1.4 de A** (`bios/nextor214/driver.mac`): con el perfil Dual (detectado por el bit 7 del puerto `#45`) una escritura
  rechazada se devuelve como `.WPROT` (pregunta el motivo al companion con el sector mágico `7FFFFFFDh`). `DEV_STATUS` de la TF2 deja de leer
  `(IX+0..3)` sin cargar IX. Sin Dual el driver hace exactamente lo mismo que antes (`tb/test_driver_a.py`, comparado con la ROM anterior,
  incluido el tráfico por los puertos). Los packs de la Zynq hay que regenerarlos con la ROM y el menú nuevos. Nextor 3: pendiente de Nextor 3.0.
- Otros arreglos de la revisión: la tarjeta de TF2 cambiada con Nextor-B puesto (B contesta «sin tarjeta» hasta recomponerlo con M),
  `sd_ceder` atiende también el buzón de B, la escritura de A en la imagen IMG2 pasa por la comprobación de la dueña, los textos de Nextor-B en inglés.
- Herramientas: `make b` en `bios/nextor214` (`Nextor-2.1.4.MSXimusB.ROM`), `tools/gen_nextor_b_h.py` (la ROM comprimida del companion),
  `tb/run_msx_b.sh --scc [--slowb n | --serialb n]` (el RTL real de B), `tb/run_emu_nextor_b.sh` (Nextor-B en el emulador Z80 con un ARM falso:
  Disk BASIC, **MSX-DOS 2 hasta el `A:\>`**, una tarjeta de dos particiones, timeout, respuesta tardía, `mode_a` bloqueado y los negativos),
  `tb/test_driver_a.py` (36), `tb/emu_menu_dual.py` (660) y `tests/dual_host` (569). El `A:\>` de MSX-DOS 2 solo se ha visto en el emulador de juguete:
  falta verlo en placa.
- Pendiente (fase 2): «D con un `.DSK`» (el mecanismo de rangos de A está; falta la tecla en la pantalla del `.DSK` y sacar el rango del disco), la TF1
  para B, Nextor 3.0, la escritura directa del ARM en la RAM de B.
- Beta construida para los tres perfiles (estándar, Música y Dual). El MSX-DOS de B no necesita PL nuevo. Nada de esto está probado en placa.

## Z1.3.2b9 — 01/11/2026 · beta

Cambios en el PL (V9968 y gestor de ventanas); el companion no cambia.

- **geo3d: las caras planas se rellenan más deprisa en SCREEN 8.** Una fila rellena de una cara sin textura (LINE horizontal con
  LOP = IMP, desde X < 256) se ejecuta como HMMV de una fila: el mismo resultado en la VRAM y en los registros del VDP (también si el Z80
  aborta la fila con otro comando o reescribe NX/NY a mitad de ella), con menos de la mitad de ciclos por fila (100 píxeles: de 992 a 414 ciclos en simulación). Sin ajuste de software. Solo SCREEN 8: SCREEN 5-7,
  SCREEN 10-12, las líneas de alambre, las texturas y las LINE del Z80 siguen como antes. HRA! mide en su cartucho 17,1 → 9,2 ms por
  cuadro (idea de **muhanpong**, issue #9 de HRA!).
- **SCREEN 10 y 11: los puntos con A = 1** (los 4 bits altos del byte son el número de paleta) salían con un color de 256 y una
  celda adelantados; ahora salen con su color de paleta y en su sitio. SCREEN 8 y 12 no cambian. (HRA!, v0.93.)
- **Gestor de ventanas del V9990 (PL):** un clic en el cuadradito cian de la barra de título ya no arrastra la ventana (la zona
  es el cuadradito y 2 px a cada lado, la misma en que el companion detecta el clic del silencio en el perfil Dual; en el estándar
  el cuadradito es de adorno). Perfil Dual: con A en silencio, el cuadradito de su barra sale hueco y gris, como el de B.
- Esta beta está construida para el perfil estándar. El **Música** y el **Dual** llevan el cambio de paleta y el del gestor de
  ventanas (el cuadradito gris de A es solo del Dual) cuando se reconstruyen; ninguno de los dos lleva geo3d. Nada de esto está
  probado en placa.

## Z1.3.2b8 — 01/11/2026 · beta (perfil Dual)

- **Perfil Dual: la tecla D lanza la ROM en A.** Con el perfil Dual cargado, D en «Lanzar ROM» lanza la ROM en la máquina A
  (como RETURN y V: mismo mapper, SRAM y Game Master 2) con el escritorio de dos columnas, y deja a B corriendo **sin
  cartucho** (MSX BASIC) como segunda máquina; si B ya corría, se queda como estaba. La tarjeta dice *JUGANDO* con la ROM de A
  y la barra de B, *MSX - B  BASIC*. Lo de antes (la ROM a B) pasa a **Shift + D**; el pie del menú no lo anuncia (no cabe).
  Sin el perfil Dual nada cambia. A a ×0,75 con B al lado no cabe en 1280 px: las ventanas se quedan como estaban.
- **Perfil Dual: sonido por máquina.** El cuadradito cian de la barra de cada ventana (clic) o las teclas A y B del panel F12 →
  Máquina B silencian o activan el sonido de A (PSG, SCC, FM, MSX-AUDIO, música del menú y monitor de la cinta) o de B (su PSG).
  En la barra de B el cuadradito se queda gris y hueco; la tarjeta *JUGANDO* lleva la línea *Sonido  A: si  B: no*; el panel
  la repite. Los silencios se quitan solos al parar B y al reiniciar A, y cada escritorio nuevo empieza con todo sonando.
  Cambio en el PL del Dual (`dual_mute.v`, bits 22-25 de la segunda palabra de control, bits 47-48 de la telemetría `+0xD0`; la
  cuenta de muestras de la telemetría pasa a 15 bits); el estándar y la Música no cambian.
- **Los perfiles salen con su nombre**: *Música* (en inglés *Music*) y *Dual*, en la página de perfiles del F12 y en sus avisos.
  El id interno no cambia (perfiles instalados, actualización por red, etiquetas `[P:MUSICA]`); la etiqueta `[P:MUSIC]` también vale.

## Z1.3.2b7 — 01/11/2026 · beta

- El USB host (teclados, ratones y mandos) ya no se queda mudo tras horas encendida. Tres arreglos en el driver USB del ARM
  ([capítulo 12](12-companion.md), apartado 5.2):
  - El EHCI de TinyUSB daba una transferencia por terminada antes de que el controlador la hiciera (con 0 bytes) y dejaba
    un mismo qTD en dos endpoints; el endpoint de estado del hub dejaba de avisar de los cambios de puerto. Ahora una
    transferencia termina cuando el controlador retira su qTD y el overlay del QH ya está inactivo.
  - El aviso de transferencia terminada (USBINT) se borraba después de repasar las colas: una transferencia que acababa
    durante el repaso se quedaba sin procesar hasta el siguiente aviso, y sin más tráfico (enumeración tras un reinicio,
    hub ocioso) para siempre. Ahora se borra antes, y el bucle del companion repasa las colas cada 8 ms aunque no haya aviso.
  - Vigilante del EHCI: cada ~0,5 s mira que el motor periódico avance; si lleva 1,5 s parado (con dispositivos de
    velocidad completa o baja detrás del hub) reinicia el USB solo —suelta las teclas, resetea USB0 y el PHY y vuelve a
    enumerar el hub—, como mucho una vez cada 5 s. Los dispositivos tardan unos segundos en volver. F12 enseña «USB
    reiniciado: n» si ha ocurrido (cuenta desde que enciende la placa).
- `tools/usbreset.tcl` fuerza ese reinicio por JTAG, y `usbdiag.tcl`, `usbqh.tcl`, `usbsplit.tcl`, `usblinks.tcl` y
  `usbwatch.tcl` miran el estado del EHCI sin tocarlo.

## Z1.3.4 — 31/10/2026 · solo red

- **geo3d también en 8Dh/8Fh**, los espejos de su cartucho externo, igual que el V9968 contesta en 88h-8Ch. Las demos
  *geo3d motion stage* de renatus (`MOT2N`, `MOT8N`) buscan primero un V9968 externo: lo encontraban en el espejo 88h,
  pedían el geo3d en 8Dh/8Fh y, sin él, se paraban con el borde amarillo («falta geo3d»).
- **Los registros 0-13 del PSG interno se leen por A2h** (antes solo el 14 y el 15; el resto daba FFh), como en un AY real.
  VGMPlay comprueba así que hay PSG interno: sin él, en los VGM con dos AY (1942) solo sonaba uno, por el PSG externo.
- Ajustes enseña Z1.3.4 (`FPGA_VERSION` A3h, `FPGA_PATCH` 4). PL: 99,86 % de slices, BRAM 131/140, WNS +0,994 ns. La serie de la OTA es la 2026103104 (por encima de las
  betas Z1.3.2bN, que llevan además los perfiles del PL y serán la Z1.4).

## Z1.3.1 — 30/10/2026 · solo red

Un arreglo de la Z1.3: se publica solo por la actualización por red, sin etiqueta ni release en GitHub (la release sigue siendo la Z1.3.0).

- Escritorio vivo en el V9990 con el juego en la ventana (teclas V y B del menú al lanzar una ROM o un `.dsk`): barra
  superior con la hora, tarjeta «NOW PLAYING» con el nombre del juego y tarjeta «SYSTEM» con la IP (cable o WiFi de la
  ESP32-S3), la temperatura, el tiempo encendido, el turbo de la CPU y el USB. Lo pinta el ARM por un canal de la DDR
  hacia los puertos del V9990 (el Z80 tiene prioridad; [capítulo 13](13-v9990-geo3d.md)).
- Hora de red: SNTP por cable o NTP por la WiFi de la ESP32-S3, con el horario de verano europeo. Sin red, el reloj en
  hardware del gestor de ventanas (sale del RTC del MSX; R#55 bit 0 lo quita).
- Las ROM con un disco dentro (DSK2ROM, como *Sonyc* de Analogy) arrancan: el menú reinicia la BIOS con la ROM puesta y
  sin Nextor, que no cabe con ella.
- La ventana lleva 8 puntos de margen a cada lado: los juegos que mueven la imagen con el ajuste horizontal R#18
  (*Sonyc*) ya no salen cortados.
- Pantalla completa del V9968 en 4:3 con Scale3x: F12, la tecla V alterna 16:9 y 4:3 y se guarda en la flash. Cada
  punto ocupa 3 × 3 píxeles, con barras negras a los lados. Los modos de 512 puntos (SCREEN 6, 7 y texto de 80
  columnas) salen sin filtro, a 1,5 píxeles por punto. Solo a pantalla completa ([capítulo 05](05-v9968.md)).
- La máquina ya no se identifica como turbo R. Del S1990 solo queda el temporizador del sistema (E6h/E7h), que usan
  las demos de geo3d de kanon-ai; E4h y E5h contestan FFh y no hay firma ni CHGCPU. El turbo de 5,37 MHz (F11) sigue
  igual.
- En Ajustes, RETURN cambia la opción igual que ESPACIO (lo que ya decía la leyenda).
- La pantalla de pruebas (T) enseña bien la versión del core (antes salía «:.3»).
- La ventana V cabe en pantalla (WX 180): las tarjetas del escritorio en modo V son más estrechas, de 19 caracteres, y WiFi/LAN va en la cabecera de SYSTEM.
- Ajustes enseña Z1.3.1 (`FPGA_VERSION` A3h, `FPGA_PATCH` 1). El PL está al 99,80 % de slices (BRAM 130,5/140, WNS +0,288 ns).

## Z1.3.0 — 30/10/2026 · GitHub y red

- Una sola salida HDMI para el V9968 y el V9990, compuestos píxel a píxel (compositor V9991) y a 60,000 Hz en todos los
  modos: se acaba el parpadeo de los monitores que rechazaban los 59,92 Hz.
- La ventana del V9968 dentro del escritorio del V9990: teclas V y B al lanzar una ROM, con el gestor de ventanas por
  hardware (marco, puntero y arrastre con el ratón USB). B5 (640 × 400) y B7 (1024 × 212/424) en el V9990.
- Canal beta en la actualización por red: la tecla B de F12 → U alterna *Oficial* y *Beta*.
- La OLED y el panel F12 dicen «V9991» con la ventana o el Video9000 (antes decían «V9968»).
- Los registros de la ventana (R#55-R#62) se aplican enteros: un WX o un WY escrito en dos OUT ya no se ve a medias
  durante un cuadro.
- Ajustes enseña el tercer número de la versión en decimal.

## Z1.2.13 — 28/10/2026 · GitHub y red

- File-Hunter acepta ROMs de hasta 8 MB.
- La microSD de TF1 es el dispositivo 2 de Nextor (FAT12/FAT16 de hasta 4 GB, se detecta al encender o reiniciar el MSX).
- Drivers de Nextor 3.5.4 en Nextor 2.1.4 y en Nextor 3.
- V9990: los modos entrelazados son estables, sin líneas sueltas arriba ni píxeles de la línea siguiente en color directo.
- Problema conocido: el panel F12 no se ve mientras el HDMI muestra el V9990 (Pausa vuelve al V9968).

## Z1.2.12 — 27/10/2026 · red

- V9990 en PAL a 50 Hz; CMMC y CMMM (*Chase H.Q.*), 16 bpp, YJK/YUV y P#2 como el chip.
- OPL4: el wave se interpola entre muestras y los temporizadores del FM son exactos.
- Reloj con el RTC nuevo de OCM (fecha válida tras un arranque en frío).
- geo3d v2.0: hasta 1.023 vértices y caras.
- El menú detecta el mapper de *Xybots* sin etiqueta.

## Z1.2.11 — 21/10/2026 · red

- V9990: el scroll se reinicia con R#17/R#21 a mitad de pantalla (*Xybots*), y la componente G de la paleta se lee bien.
- El menú deja el slot 3 como tras un arranque en frío al lanzar una ROM (*Sol Negro*).

## Z1.2.10 — 16/10/2026 · red

- OPL4 wave: la envolvente para en −60 dB como el chip, LFO exacto, el registro F8h ajusta cada lado del FM.
- Z80: `LD A,I` y `LD A,R` ponen todos los flags como la CPU real.

## Z1.2.9 — 15/10/2026 · red

- OPL4: sin el ruido fuerte en los fundidos de MoonBlaster Wave; las lecturas de registros no perturban las notas.

## Z1.2.8 — 15/10/2026 · red

- OPL4 wave con DAMP y pseudo-reverb como el chip; OPLL (IKAOPLL) al día con su upstream.

## Z1.2.7 — 14/10/2026 · red

- Motor wave del OPL4 como el YMF278B: margen para 24 voces, fundidos de TL, tasas de la envolvente y pan a −3 dB por paso.

## Z1.2.6 — 13/10/2026 · red

- OPL4: la activación NEW2 también por el puerto C5h (los discos del MoonBlaster Wave BASIC driver vuelven a sonar).

## Z1.2.5 — 13/10/2026 · red

- OPL4 como el chip real: F8h arranca en 1Bh, vibrato y trémolo del FM como el YMF262; el panel F12 comprueba la ROM de ondas.

## Z1.2.4 — 05/10/2026 · red

- Los registros de slot del wave del OPL4 se releen bien a la primera.

## Z1.2.3b6 — 03/10/2026

- Nextor 3.0 beta 2 en las variantes de Nextor 3, con sus herramientas.

## Z1.2.3b5 — 02/10/2026

- El menú lee el mapper de la firma de tipo de ROM de MSXgl.

## Z1.2.3b4 — 02/10/2026

- Actualización por red sin cable, por la WiFi de la ESP32-S3; actualizaciones desde msx.barcelona con TLS.

## Z1.2.3 — 01/10/2026

- Menús, Ajustes y panel en castellano o en inglés: cuatro variantes.

## Z1.2.2 — 01/10/2026

- Actualización por red: ranuras A/B en la QSPI, FSBL propio y manifiesto firmado. Panel F12 en color.

## Z1.2.1 — 30/09/2026

- Tres arreglos del V9968 de HRA! (puerto 99h, DIY, paso de píxel).

## Z1.2 — 18/09 a 29/09/2026

- V9990 en los puertos 60h-6Fh con su propia imagen (Pausa conmuta).
- geo3d de Alex Moncks en 9Dh/9Fh.
- Megaram de 8 MB con ASCII16-X; IKAOPLL; estéreo canal a canal en todos los chips.
- Ethernet con TLS; cinta web (TSX/CAS desde File-Hunter); disquetera USB de 3,5"; música WAV y MP3 en el menú.
- Navegador ordenado; las rayas de arranque del V9968 desaparecen.

## Z1.1 — 18/09/2026

- Cinta virtual: TSX y CAS desde la SD.

## Z1.0 — 17/09/2026

- Primera versión de la línea Zynq: el MSX2+ con V9968 en la ZYNQ MINI, la SD por el companion, USB, OLED,
  ajustes en la QSPI, WaveGame y el mezclador por fuente.

## Pendiente

- Con el V9968 por frame buffer sobra el búfer de línea del escalador de su `video_out` (dato de HRA!), que libera
  memoria. Un ajuste «baja latencia» (el V9968 enganchado, sin el cuadro de más del frame buffer), aparcado.
- **Siguiente**: la microSD de TF1 desde el menú (navegar y lanzar también desde TF1). La página 2 del menú ya tiene
  155 bytes libres para ello (la ayuda pasó a la página 1).
- **Después de la Z1.3.1**
  - Perfiles de bitstream como cartuchos (en estudio).
  - USB2SLOT (placa de MSXRetroThings): volcar cartuchos reales desde el menú y slot en vivo. La PCB está en camino.
- **V9990**: faltan B0 y B6, LINE en dos casos, PSET/ADVN, kanji CMMK y el EOR del cursor; *LIFEARTH* por la cadena de
  la BIOS; la fuente kanji en la DDR.
- **Ethernet**: se queda como está. Si falta espacio en el FPGA, es lo primero que sale (la red va por la ESP32-S3).
- **Disquetera USB**: sin probar con una unidad sana.
- **Hilos abiertos**: HRA! #7 (FIFO del LMMC); avisar a buppu3 del reinicio del scroll con R#17/R#21 y a DiHalt
  de la espera de *Shao-lin's Road*; rampa069/v9990 #2 (LICENSE).
- Guiones de 8 px en *Xevious* (compartido con el núcleo original): aparcado.
