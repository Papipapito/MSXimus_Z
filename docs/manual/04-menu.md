# 04. El menú de arranque

El MSXimus Z lleva un menú dentro de la BIOS. No es un programa que se cargue de la tarjeta: va en el pack de BIOS, en la ROM del cartucho interno (slot 3-1), y arranca antes que MSX-DOS. Desde él se navega por la tarjeta SD, se lanzan ROMs y discos, se cambian los ajustes de la máquina, se regula el mezclador de audio, se configura la WiFi y se descargan ficheros.

El código del menú (`bios/src/`) no se publica. Por debajo, el pack de BIOS vive en la DDR3 del procesador, la tarjeta la sirve el *companion* (el programa que corre en el ARM), los ajustes se guardan en la QSPI de la placa y el teclado, el mando y el ratón llegan por el USB host.

**Idioma.** El menú, Ajustes y todos los mensajes salen en castellano o en inglés según el pack de BIOS: las cuatro variantes de la Z1.3.0 son Nextor 2.1.4 y Nextor 3.0 beta 2, cada una en castellano y en inglés. No hay una opción de idioma en Ajustes; para cambiarlo se pone el pack de la otra variante. En este capítulo se citan los textos en castellano; los de la variante inglesa son su traducción (*Settings*, *Menu at boot*, *Audio mixer*, *Launch ROM*, etc.). El panel F12 (apartado 10) habla el idioma del menú de la imagen que está en marcha.

Todo lo que hay en este capítulo está sacado del código del menú, que no se publica (`bios/src/menu_main.asm`, `gm2.asm`, `srm_saves.asm`, `sort_list.asm`, `test_menu.asm` y `e7_rutinas.asm`) y del *companion* (`fpga/zynq/arm/companion/`).

**Cuál es "la tarjeta".** La placa tiene dos ranuras microSD. En todo este capítulo, "la tarjeta" o "la SD" es la de **TF2**: la del MSX, con las ROMs, los discos y la carpeta `FHUNT`. La de TF1 guarda los perfiles del sistema (y arranca el procesador con un `BOOT.bin` cuando no se arranca desde la QSPI): ni el menú ni Nextor la ven. Está explicado en el capítulo de instalación y en el de la tarjeta SD.

## 1. Qué pasa al encender

1. El procesador arranca (desde la QSPI o desde TF1), carga el bitstream, el pack de BIOS y la tabla de ondas del OPL4 en la DDR3 y arranca el *companion*.
2. El *companion* prueba la tarjeta de TF2, limpia la VRAM, lee el bloque de ajustes que hay en la QSPI y lo siembra en el core. Solo entonces suelta el MSX. Hasta ahí el MSX está en reset y la pantalla no muestra nada.
3. Sale el logo del MSXimus. Dura unos tres segundos.
4. Durante el logo, el menú mira el teclado (la matriz, no la BIOS, así que no depende de que el teclado USB haya enumerado). Tres teclas hacen algo:

| Tecla | Adónde va |
|---|---|
| **S** | Ajustes |
| **W** | Configuración WiFi del ESP32 |
| **T** | Menú de pruebas |

5. Si no se pulsa nada, manda el ajuste **Menú al arrancar**:
   - **On** (el valor por defecto): aparece el navegador de la SD, la pantalla principal de este capítulo.
   - **Off**: la máquina arranca directamente MSX-DOS o Nextor desde la tarjeta, como un MSX normal. El navegador no aparece.

Con el menú desactivado, la forma de volver a activarlo es **mantener S durante el logo**: se entra en Ajustes aunque *Menú al arrancar* esté en Off, y desde ahí se pone en On y se hace **Save & Restart**. No hay que tocar nada en la placa ni reprogramar nada.

Si no hay tarjeta en TF2 o no se puede leer, sale una pantalla con el aviso *"No se detecta la tarjeta SD."* y la línea *"RETURN=Boot MSX   S=Settings   W=WiFi"* (esta línea sale en inglés en las dos variantes). RETURN o ESC arrancan el sistema igualmente, S abre Ajustes, W la WiFi y T las pruebas. El *companion* vuelve a buscar la tarjeta cada medio segundo, así que se puede meter con la placa encendida, pero el menú solo la mira al arrancar: tras meterla hay que reiniciar con el botón de reset del MSX (K2) para que la encuentre.

## 2. El navegador de la SD

Es la pantalla principal. Texto de 80 columnas, con este reparto:

- **Fila 1**: el título, *MSXimus*.
- **Fila 2**: las tres pestañas de filtro, `[R]OM  [D]SK  [A]LL`. La activa se ve en vídeo inverso. Al entrar está en ALL.
- **Filas 4 a 21**: la lista, 18 entradas por página. La fila seleccionada va marcada con `>` y en vídeo inverso a todo lo ancho. Se ven los nombres largos; si el seleccionado no cabe en la ventana de 59 columnas, se desplaza solo como una marquesina. En la columna de la derecha, las carpetas llevan `[DIR]` y los ficheros su tamaño en KB (`86K`); las cintas, la música y los perfiles llevan delante su tipo: `CAS`, `TSX`, `WAV`, `MP3` o `MXP`.
- **Fila 22**: el separador, con el contador `seleccionado/total` en el centro (`3/112`). Si la carpeta tiene más entradas de las que caben, el total lleva un **`+`** detrás (`112/112+`).
- **Fila 23**: el pie con las teclas, `R/D/A=Filtro ESC=MSX S=Set W=WiFi U=USB TAB=Part H=Ayuda`.

Se listan carpetas, ROMs (`.ROM`), discos (`.DSK`), cintas (`.TSX` y `.CAS`, [capítulo 11](11-cinta.md)), música (`.WAV` y `.MP3`, [capítulo 08](08-audio.md)) y perfiles del PL (`.MXP`, apartado 10). El resto de la tarjeta no aparece. Los `.wav` de un juego WaveGame sí salen si están en la misma carpeta que la ROM: RETURN sobre uno lo toca como música del menú, no tiene más efecto. Se puede bajar hasta ocho niveles de carpetas.

**Orden y límites del listado.** El listado sale ordenado: primero las carpetas y después los ficheros (ROMs, discos, cintas y música juntos), y dentro de cada grupo por orden alfabético sin distinguir mayúsculas, sobre el nombre que se ve (el largo si lo hay). No se listan los ficheros ocultos, de sistema ni las etiquetas de volumen, así que desaparecen cosas como `System Volume Information`, `.Trashes`, `.fseventsd` o los `._nombre.rom` que deja macOS. El navegador guarda como máximo **112 entradas por carpeta**, las primeras que encuentra en la tarjeta; si hay más, el contador lo avisa con el `+` y las que sobran no se ven (se reparten en subcarpetas o se usa el filtro R/D/A para que quepan las que interesan). Los resultados de File-Hunter (apartado 7) no se ordenan: salen como los da la base de datos.

### Teclas del navegador

| Tecla | Qué hace |
|---|---|
| **Arriba / Abajo** | Mover la selección |
| **Izquierda / Derecha** | Saltar una página entera (18 entradas) atrás o adelante. Arriba en la primera entrada da la vuelta a la última, y Abajo en la última a la primera |
| **RETURN** | Entrar en la carpeta, o abrir la pantalla de lanzar si es una ROM o un disco |
| **BACKSPACE** | Volver a la carpeta anterior |
| **/** | Buscar por nombre. Abre un campo (*Buscar:*) arriba: se escribe un trozo del nombre (hasta 12 caracteres, sin distinguir mayúsculas), RETURN salta a la siguiente coincidencia desde la selección actual y da la vuelta al final, ESC cancela |
| **TAB** | Cambiar de partición, si la tarjeta tiene más de una |
| **R**, **D**, **A** | Filtrar: solo ROMs, solo discos, o todo |
| **S** | Ajustes |
| **W** | Configuración WiFi |
| **T** | Menú de pruebas |
| **F** | File-Hunter: buscar y descargar de internet (apartado 7) |
| **U** | Disquetera USB: montar el disquete como unidad A: (apartado 4.1) |
| **P** | Música: toca la carpeta desde el primer `.wav`/`.mp3`; otra vez, pausa; otra, sigue ([capítulo 08](08-audio.md)) |
| **N** | Música: pista siguiente |
| **H** | Ayuda: una pantalla con esta misma lista de teclas |
| **ESC** | Arrancar el sistema (MSX-DOS o Nextor de la tarjeta) |

El teclado es un teclado USB enchufado al puerto USB host de la placa; el *companion* lo pasa al core como si fuera el teclado del MSX. Un mando USB genérico (HID, del tipo "SNES USB") hace de mando del puerto 1 y también sirve en el navegador: las cuatro direcciones mueven igual que los cursores, el botón A es RETURN y el botón B es BACKSPACE. Los mandos XInput (Xbox 360 y receptores que se presentan como tal) también funcionan, con el mismo mapa. Se puede poner un hub para tener teclado, mando y ratón a la vez.

## 3. Lanzar una ROM

Al pulsar RETURN sobre una `[ROM]` se abre la pantalla **Lanzar ROM**. Tiene un formato fijo:

- **Fichero**: el nombre completo.
- **Tamaño**: en KB.
- **Mapper**: el tipo de cartucho con el que se va a emular.
- **SRAM: On/Off**: solo aparece con mappers ASCII8 y ASCII16, que son los que llevan SRAM de cartucho.
- **GM2: On/Off**: solo aparece con mappers Konami y Konami-SCC, que son los que usan el Game Master 2.
- Una **barra de progreso** de 64 celdas para la carga.
- Una **línea de estado** con lo que está pasando.
- El **pie** con las teclas disponibles.

Nada más entrar, la línea de estado dice *"Analizando ROM..."* con un indicador girando mientras el menú decide el mapper.

### Cómo se decide el mapper

1. Si la ROM ocupa 32 KB o menos, es **Plain** (lineal, sin mapper), salvo que el nombre lleve una etiqueta.
2. Si es mayor, manda la **etiqueta del nombre** si la hay: `[ASCII16]`, `[ASCII8]`, `[SCC]`, `[KONAMI]`, `NEO16` o `NEO-16`, `NEO8` o `NEO-8`. Son las etiquetas que pone File-Hunter al descargar, y las que puede poner uno mismo al renombrar un fichero.
3. Sin etiqueta, se **analiza el contenido** de la ROM buscando las instrucciones con que cada mapper cambia de banco, al estilo de openMSX. La carga va por DMA (el *companion* sirve los sectores a unos 1600 KB/s) y el análisis lo hace el propio hardware mientras carga.
4. Una ROM que el análisis da como Konami pero mide 320 KB o más se promociona a **Konami-SCC**: el Konami original nunca pasa de 256 KB.
5. Al acabar de cargar, el menú mira la **firma del propio fichero**, que manda sobre la etiqueta y sobre el análisis: la firma de tipo de ROM de MSXgl (ocho letras detrás de la cabecera `AB`, en el offset 10h o en el 4010h) con `ROM_ASC8` (ASCII8), `ROM_AS16` (ASCII16), `ROM_KON4` (Konami), `ROM_KON5` (Konami-SCC), `ROM_NEO8` (NEO-8) o `ROM_NE16` (NEO-16), y la firma `ASCII16X` del ASCII16-X. Una ROM de más de 4 MB sin ninguna firma ni etiqueta NEO es ASCII16-X, el único mapper que llega tan lejos. Y una imagen de 16 a 48 KB con la cabecera en 4000h en vez de en 0 pasa a **Plain 0000h** (capítulo 05).

Si el análisis no ve nada, el mapper queda como *"? (desconocido)"* y hay que elegirlo a mano con la tecla M.

Los mappers disponibles son: Plain, Konami, Konami-SCC, ASCII8, ASCII16, NEO-8, NEO-16, Plain 0000h y ASCII16-X. La megaram, que en la Zynq vive en la DDR3 del procesador, es de **8 MB**: el ASCII16-X llega hasta ahí; ASCII16, NEO-8 y NEO-16 hasta 4 MB; Konami-SCC y ASCII8 hasta 2 MB; Konami, 256 KB; y Plain, 32 KB (Plain 0000h, 48 KB). La tabla completa está en el [capítulo 05](05-roms-mappers.md).

### Teclas de la pantalla de lanzar ROM

| Tecla | Qué hace |
|---|---|
| **RETURN** | Cargar la ROM en la megaram y lanzarla. La barra avanza durante la carga, el estado dice *"Cargando ROM en megaram..."* y luego *"ROM cargada."*; después el menú arranca la ROM directamente, como si fuera un cartucho |
| **M** | Cambiar el mapper. Cicla Plain, Konami, Konami-SCC, ASCII8, ASCII16, NEO-8, NEO-16, Plain 0000h, ASCII16-X y vuelta a Plain. Al cambiar, la SRAM y el GM2 vuelven a su valor por defecto |
| **S** | Conmutar la SRAM de cartucho para este lanzamiento. Solo actúa en ASCII8 y ASCII16. Por defecto está Off, salvo que el nombre lleve `KOEI` o `SRAM`, en cuyo caso arranca On |
| **G** | Conmutar el Game Master 2 para este lanzamiento. Solo actúa en Konami y Konami-SCC. Por defecto toma el valor del ajuste **Slot 1** |
| **V** | Lanzar la ROM **dentro de una ventana del V9990** (solo Zynq): antes de arrancarla pinta el escritorio en el V9990 y programa la ventana del V9968. Como lanzar no reinicia la máquina, el escritorio se queda y el juego corre dentro del marco, con su nombre en la barra de título. Se ve entero, con el escritorio en B5 (640 × 400) y el juego a escala ×0,75 (912 × 477 px de la HDMI con los 8 puntos de margen a cada lado), pegado a la derecha. La ventana se puede arrastrar con el ratón. **Pausa** vuelve al V9968 entero; el reset del MSX borra el escritorio |
| **B** | Como **V**, pero con el escritorio del V9990 en **B7** (1024 × 212, un punto por píxel de la HDMI) y el juego **entero** a escala ×0,5 en una ventana de 512 × 318 px. **Pausa** pasa al V9968 a pantalla completa y otra vez Pausa vuelve a la ventana |
| **D** | Lanzar la ROM en **A** con el **escritorio de dos columnas** del perfil Dual, y arrancar en **B** **MSX-DOS** (Nextor 2.1.4) como segunda máquina, con la **SD en B**: B escribe en la tarjeta y A solo lee, salvo los ficheros `.SRM` de la partida de la ROM que se lanza, que A sigue guardando (si la ROM lleva SRAM, el menú la crea o la carga antes de pintar el escritorio). B se reinicia al ganar la SD, salvo que ya corriera MSX-DOS y ya fuera la dueña. **Solo existe con el perfil `DUAL` cargado**: con cualquier otro (estándar, Música) el pie no la anuncia y la tecla no hace nada. La ROM se lanza como con RETURN (mismo mapper, SRAM y Game Master 2), con el escritorio del apartado siguiente: A (el juego) a la izquierda, B a la derecha |
| **Shift + D** | Lo que hacía la D hasta la Z1.3.2b7: mandar la ROM a la **máquina B** en vez de lanzarla en A. Carga la ROM igual que RETURN, pero la copia al cartucho de B, que la arranca, y vuelve al navegador: **A no se reinicia**. La SD vuelve a **A** (el MSX-DOS de B, si lo había, muere con el cartucho nuevo; A está en el menú, sin DOS que reiniciar). El pie no lo anuncia (no cabe en la fila); también se puede cargar un juego en B con el panel F12 → B (tecla **C** para quitarlo) o con `tools/dual_rom.tcl` |
| **ESC** | Volver al navegador sin lanzar |

Hay un caso en que RETURN no hace nada: cuando el estado dice *"INIT pag.0/BASIC: no lanzable"*. Es una ROM plana cuyo punto de entrada cae fuera de la ventana del cartucho, normalmente un programa BASIC empaquetado como ROM. Lanzarla reiniciaría la máquina, así que el menú lo impide. Cambiar el mapper con M vuelve a evaluar ese veto.

### El escritorio de la ventana

Con V o B (en una ROM y también en un disco) el V9990 enseña un escritorio que se mantiene vivo mientras corre el juego:

- Una barra superior con el nombre de la máquina, la versión y la **hora**.
- La tarjeta **NOW PLAYING**, con el nombre del juego.
- La tarjeta **SYSTEM**, con la IP (la del cable o la de la WiFi de la ESP32-S3), la temperatura, el tiempo encendido, el turbo de la CPU y los dispositivos USB.

La hora viene de la red: SNTP por cable o NTP por la WiFi de la ESP32-S3, con el horario de verano europeo. Si no hay red, se ve el reloj del gestor de ventanas, que sale del reloj del MSX.

### El perfil Turbo R

El perfil **Turbo R** (página Perfiles del panel F12; [capítulo técnico 15](../tecnica/15-perfil-tr.md)) convierte la placa en un turbo R con R800, PCM, OPL4 y 2 MB de mapper.

- **SD:** usa Nextor 3, así que necesita una SD con el `NEXTOR.SYS` de Nextor 3.
- **R800:** el menú lanza las ROM en Z80. Para lanzar una en R800, añade `[R800]` al nombre largo del fichero desde el PC. En el DOS, `CHGCPU` cambia de CPU.
- **Mezclador:** el PCM usa el canal `AUDIO/PCM`.
- **SofaRun:** tras apagar la placa, borra la carpeta `SETTINGS` antes de lanzarlo. Se vuelve a crear sola.

### El perfil Turbo R V9990

El perfil **Turbo R V9990** (id `TRV`) es el Turbo R con V9990, y la tecla Pausa, las teclas V y B del menú y la ventana funcionan como en el sistema estándar. Admite ROM **NEO-16 de hasta 16 MB**, como Monkey Island 2 de Maggoo. No lleva MSX-Audio.

### La máquina B (perfil Dual)

El perfil **Dual** (página Perfiles del panel F12; [capítulo técnico 14](../tecnica/14-perfil-dual.md)) añade una segunda máquina MSX2+, la **B**, con su Z80, su V9968, su PSG y su cartucho, que corre a la vez que A. Sin disco ni menú: arranca el MSX BASIC o el juego que se le manda.

- **Lanzar un juego con B de segunda máquina**: en la pantalla *Lanzar ROM* pulsa **D** (el pie lo dice: `D = Dual`, y solo con este perfil). El juego se lanza en A y el menú pinta el **escritorio de dos columnas**: A a la izquierda a escala ×0,5 (608 × 318 px) y B a la derecha (su imagen de 256 × 212 puntos, 512 × 318 px), las dos enteras y sin taparse, con la barra de la hora arriba y las tarjetas *JUGANDO* (el juego de A) y *SISTEMA* en la franja de abajo. B arranca **MSX-DOS** (su barra dice *MSX - B  MSX-DOS*): un MSX-DOS 2 con la misma tarjeta de TF2 que usa A (ver el apartado siguiente: quién escribe en ella). El teclado empieza en A: para usar el MSX-DOS de B, un clic en su ventana (o Insert) le da el teclado. La **Pausa** enseña el V9990 a pantalla completa.
- **Mandar un juego a B**: con **Shift + D** la ROM va a B y A no se lanza (la tarjeta dice *JUGANDO EN B*, y la barra de B lleva el nombre del juego); el navegador sigue donde estaba, con A en su ventana, y se puede mandar otro juego a B cuando se quiera.
- **Las dos ventanas se mueven con el ratón**: arrastra la barra de título de A (*MSX - V9968*) o la de B (*MSX - B* y el nombre del juego); B se mueve punto a punto. A siempre queda por encima de B si se tocan. Si B pasa por encima de las tarjetas, estas se repintan al soltarla.
- **Teclado y foco**: lo recibe una máquina cada vez, la de la ventana que tiene el **foco**: la barra de título de la ventana con el foco es azul, la de la otra se apaga. Un **clic** dentro de una ventana (en A o en B) le da el foco; **Insert** lo alterna entre A y B (con B parada, siempre es A). *Teclado en A/B (Insert)* se ve también en la tarjeta de abajo. Con la tecla **T** del panel de B el teclado queda forzado a B y el clic en A no lo cambia.
- **Silenciar una máquina**: el **cuadradito cian** de la barra de título de cada ventana (el de la izquierda de los dos de la derecha) silencia o activa el sonido **de esa máquina** con un clic: el de A (*MSX - V9968*) apaga el PSG, el SCC, el FM, el MSX-AUDIO, la música del menú y el monitor de la cinta de A; el de B apaga su PSG. En la barra de B el cuadradito se queda **gris y hueco** mientras está en silencio, y la tarjeta *JUGANDO* lleva una línea *Sonido  A: si  B: no* (en naranja si algo está en silencio). El clic en el cuadradito no cambia el foco del teclado (con el ratón quieto: si se mueve mientras se pulsa, la ventana de A se arrastra esos puntos). El silencio solo vale con B corriendo y **se quita solo** al parar B, al reiniciar A (S1, F12) y al volver a pulsar D, V o B en el menú: nunca queda una máquina muda por sorpresa. También se puede hacer desde el panel de B (teclas **A** y **B**).
- **Panel de B**: con el perfil Dual, **F12 → B** abre la página *Máquina B*: si B corre, el teclado, la ventana, el sonido de cada máquina y el cartucho, y las teclas **S** soltar, **P** parar (si B tenía la SD, vuelve a A), **R** reiniciar, **C** quitar el cartucho (B vuelve al BASIC y la SD a A), **D** pasar la SD de A a B o de B a A (solo con MSX-DOS en B), **M** MSX-DOS en B, **T** teclado a B / libre, **V** ventana de B visible u oculta y **A** / **B** silenciar o activar el sonido de A / de B (solo con el escritorio de dos columnas y B corriendo). La fila *SD* dice quién escribe. Mientras el panel está abierto A está en pausa y B sigue.
- **MSX-DOS en B y la tarjeta compartida**: B ve la **misma tarjeta de TF2 que A** (entera: su primera partición FAT12/FAT16 es `A:` —las demás se mapean con `MAPDRV`, como en cualquier Nextor— y el MSX-DOS arranca de `NEXTOR.SYS` y `COMMAND2.COM`, los de la raíz de la tarjeta). Pero en cada momento **solo una máquina escribe** en ella —la *dueña de la SD*— y la otra **solo lee**: dos MSX-DOS escribiendo a la vez estropearían el sistema de ficheros. La D sola deja la SD en **B**; Shift + D la devuelve a **A**; arrancar o recargar el perfil la deja en A. Quién la tiene lo dicen la línea *SD: escribe B* / *SD: escribe A* de la tarjeta de abajo del escritorio y la fila *SD* del panel de B.
- **Qué pasa con la que no escribe**: si intenta escribir, ve *Disk write protected* (en MSX-DOS 2, `Abort, Retry or Ignore`). Con la SD en B, lo que A intente escribir fuera de los `.SRM` de su partida se rechaza: las **descargas de File-Hunter** desde el menú de A dan error de SD, y el MSX-DOS o el Disk BASIC de A, *Disk write protected*. Para que A vuelva a escribir hay que pasarle la SD (F12 → B → **D**) o parar B (**P**). La SD vuelve **sola** a A cuando B deja de correr MSX-DOS: la paras, la reinicias al BASIC, le quitas el cartucho (**C**) o le mandas una ROM (Shift + D).
- **Datos viejos y reinicios**: la máquina que no escribe **no se entera** de lo que escribe la otra: su MSX-DOS puede enseñar datos viejos (una carpeta ya leída, un fichero abierto) hasta que se reinicie (un `DIR` nuevo suele bastar). Por eso la máquina que **gana** la escritura se reinicia (B) o te avisa (A): al pasar la SD a B, **B se reinicia** con el MSX-DOS limpio; al pasarla a A, si B escribió, el panel dice *«Reinicia A si usa MSX-DOS»*. La excepción es la D sola con B ya corriendo MSX-DOS y ya dueña de la SD: no se toca (puede estar copiando ficheros).
- **Cambiar la dueña a mano**: en el panel de B, la tecla **D** pasa la SD de una máquina a la otra (solo si B corre MSX-DOS; si no, el panel dice que la SD es de A y que **M** lo pone). **Antes sal de lo que se esté escribiendo** en la máquina que la tiene (cierra el programa, vuelve al `A:\>` y espera a que acabe): lo que tuviera a medias en memoria no llega a la tarjeta. Con la D sola y con Shift + D no hay riesgo: el MSX-DOS de la máquina que pierde la escritura muere con el lanzamiento. La tecla **M** del panel arranca el MSX-DOS en B (o lo reinicia) sin tocar quién es la dueña. Si cambias la **tarjeta** de TF2 con MSX-DOS en B, B contesta *sin tarjeta* hasta que la reinicies con **M**.
- **Qué no hay en B**: mappers NEO-8, NEO-16 ni ASCII16-X, ni ROM de más de 2 MB, ni SRAM ni Game Master 2 (el panel lo avisa); tampoco WiFi, turbo ni joystick. Con cualquier otro perfil la tecla D no existe (ni se anuncia en el pie) y el panel dice *«B solo existe en el perfil Dual»*.

### ROM con un disco dentro

Algunas ROM llevan un disco entero con su propio driver (DSK2ROM, como *Sonyc* de Analogy). Al lanzarlas, el menú reinicia la BIOS con la ROM puesta en el cartucho y **sin Nextor**: no caben juntos. El juego arranca desde su disco.

### Juegos con música WaveGame

Al lanzar cualquier ROM, el menú avisa al *companion* (por el puerto 93h) de qué fichero se lanza y en qué carpeta está. Con eso el *companion* busca en esa misma carpeta los ficheros `NN.wav`, `NN.cfg` y `pause.wav` del protocolo WaveGame (el de Jeroen Taverne, el mismo del MSX Pico, el PicoVerse y openMSX) y, si los hay, sirve la música al core cuando el juego la pide. No hay nada que activar en el menú: basta con que la ROM y sus WAV estén juntos en la tarjeta.

Dos cosas a tener en cuenta:

- Las ROMs WaveGame de Konami son **Konami-SCC**. Si el detector dice *Konami*, pulsa **M** hasta Konami-SCC antes de lanzar.
- El nivel del canal WaveGame se regula en el mezclador de Ajustes (sección 5). Arranca a 8/8.

Los detalles del protocolo y del formato de los ficheros están en el capítulo de audio.

### ROM que pide un perfil: `[P:ID]`

Si el nombre de la ROM lleva `[P:ID]` (por ejemplo `Juego [P:SONIDO].rom`: hasta 8 letras, cifras, `_` o `-`, en mayúsculas o minúsculas) el juego necesita ese perfil del PL (apartado 10). Al dar RETURN sobre la ROM, si el perfil que corre no es ese, la placa lo carga de la tarjeta de TF1 (el MSX se reinicia y la imagen tarda unos segundos en volver) y el panel F12 se abre con *«ID» cargado. Vuelve a lanzar el juego*: hay que elegir la ROM otra vez y darle RETURN, y ahora, con el perfil ya puesto, se lanza como cualquier otra (el lanzamiento no continúa solo tras el reinicio). Si el perfil no está instalado, es de otra versión del sistema o no hay tarjeta, el panel dice por qué y el MSX se reinicia: el juego no se lanza. El perfil cargado se queda hasta que se cargue otro, se vuelva al perfil 1 (apartado 10) o se apague.

### La SRAM y las partidas guardadas

Al lanzar un ASCII8 o ASCII16 con **SRAM On**, el menú busca en la carpeta `FHUNT` de la raíz de la tarjeta un fichero con el mismo nombre que la ROM y extensión `.SRM` (32 KB). Si existe, lo carga como SRAM del cartucho; si no, lo crea vacío. La partida se guarda en la SRAM emulada mientras se juega, y se escribe de vuelta a ese `.SRM` **en el siguiente arranque del navegador**, que es cuando el menú vuelve a tener la tarjeta montada.

Por eso, para conservar la partida hay que **reiniciar el MSX, no apagar**: la megaram (y con ella la SRAM emulada) está en la DDR3 del procesador, que aguanta un reset del MSX. El reset del MSX es el botón de reset del MSX (K2, tabla de botones del [capítulo 02](02-instalacion.md)); el reset de la placa (PS_SRST) reinicia en cambio todo el procesador. En un apagado se pierde lo que no se haya escrito, seguro.

Los mensajes que se ven: *"SRAM: cargando ..."*, *"SRAM: nueva (FF) -> FHUNT"*, *"SRAM cambiada: guardando FHUNT/..."* con *"OK"*. Si no existe la carpeta FHUNT, *"SRAM: sin FHUNT, no se guarda"*: la SRAM funciona pero se pierde. Las ROMs de 4 MB no dejan sitio para la SRAM y tampoco se guardan.

### El Game Master 2

El Game Master 2 es el cartucho de Konami que añadía partidas guardadas a sus juegos. El MSXimus Z lo emula en el slot 1 cuando se lanza un juego Konami con **GM2 On**. Necesita dos ficheros en `FHUNT`: `GM2.ROM` (la ROM original del cartucho, 128 KB, la pone el usuario) y `GM2.SRM` (8 KB, se crea solo la primera vez). La escritura a la tarjeta funciona igual que la de la SRAM: en el siguiente arranque del navegador, tras un reinicio del MSX y no tras un apagado.

Si falta algo, el juego se lanza sin GM2 y la línea de estado dice por qué: *"GM2: falta FHUNT/GM2.ROM"*, *"GM2: GM2.ROM no mide 128 KB"* o *"GM2: sin FHUNT"*. Las ROMs de 3840 KB o más pisan la mitad alta y con ellas no se arma.

## 4. Lanzar un disco

Al pulsar RETURN sobre un `[DSK]` se abre **Lanzar disco**, con el nombre del fichero, *"Tipo: Disco"* (*"Multidisco"* si el fichero tiene varios discos de 720 KB) y el estado *"Listo para montar."*.

| Tecla | Qué hace |
|---|---|
| **RETURN** | Montar y lanzar |
| **V** | Montar y lanzar dentro de una ventana del V9990, como en las ROM |
| **B** | Lo mismo con el escritorio en B7, como en las ROM |
| **ESC** | Volver |

El disco se monta con la emulación de disco de Nextor: al seguir el arranque, Nextor lo ve como la unidad A: en modo MSX-DOS 1 y ejecuta su sector de arranque. Dura hasta el siguiente reinicio. Para que funcione, el fichero `.dsk` tiene que estar **en clusters consecutivos** de la tarjeta; si no, el menú avisa con *"DSK fragmentado: recopialo"* y basta con copiarlo de nuevo a la tarjeta desde el PC.

En tarjetas FAT16 el menú necesita un fichero oculto `NEXTOR.EMU` en la raíz, que crea él solo la primera vez. Si no puede crearlo dice *"Falta NEXTOR.EMU en la raiz"*. En FAT32 no hace falta: usa un sector reservado de la partición.

### 4.1. Disquetera USB (tecla U)

Con una disquetera USB de 3,5" enchufada, **U** en el navegador abre la pantalla **Disquetera USB**: el menú lee el disquete que haya (1,44 MB o 720 KB), enseña su tamaño y, con RETURN, lo monta como unidad A: igual que un `.dsk` (Nextor en modo MSX-DOS 1, hasta el siguiente reinicio). Sin disquete dice *"Disquetera USB: sin disco"*. El detalle, y qué disquetes valen, está en el [capítulo 06](06-msxdos-nextor.md).

## 5. Ajustes (tecla S)

La pantalla **MSXimus - Ajustes** tiene estas opciones, en este orden:

| Opción | Valores | Qué es |
|---|---|---|
| **Slot 1** | Nada / 2o SCC / Game Master 2 | Qué hay en el slot 1 del MSX. *2o SCC* pone un segundo chip SCC para los juegos que lo buscan como cartucho aparte. *Game Master 2* deja el GM2 activado por defecto para los juegos Konami |
| **Enable Scanlines** | On / Off | Líneas de barrido en la salida HDMI |
| **Stereo Sound** | On / Off | Sonido en estéreo |
| **Boot Turbo** | On / Off | Arrancar siempre con la CPU a 5,37 MHz. En la misma fila hay una nota, *"(reiniciar fisicamente)"*: ver más abajo |
| **Menú al arrancar** | On / Off | Si aparece el navegador de la SD al encender o se arranca MSX-DOS directamente |
| **Mezclador de audio** | | Abre la página del mezclador (sección 5.1) |
| **Save & Restart** | | Guardar los ajustes en la QSPI y reiniciar el MSX |

Debajo se muestra *"Version FPGA (.fs):"* con la versión del core que hay cargado (el «.fs» de la etiqueta no significa nada en la Zynq). Un core sin versión diría *"desconocida"*. La versión sale del puerto 2Fh (versión: `Z1.3` es A3h) y del 29h (revisión de arreglos, que se añade detrás en decimal si no es 0): con la Z1.3.1 la pantalla enseña «Z1.3.1». La cabecera del panel F12 (apartado 10) enseña la misma versión.

En la última fila de la pantalla hay una leyenda con las teclas de Ajustes.

| Tecla | Qué hace |
|---|---|
| **Arriba / Abajo** | Mover entre opciones |
| **ESPACIO** | Cambiar el valor de la opción seleccionada. En *Slot 1* va ciclando los tres estados. Sobre *Mezclador de audio* abre su página. Sobre *Save & Restart* guarda y reinicia |
| **ESC** | Salir al navegador **sin guardar** |

Los cambios solo se escriben con *Save & Restart*. Si se sale con ESC, o se reinicia la máquina por otro camino, se pierden.

### Qué hace Save & Restart en la Zynq

El core no tiene ninguna memoria no volátil propia: los ajustes los guarda el *companion*. Al pulsar Save & Restart, el menú entrega al core los bytes de configuración y le pide guardar y reiniciar; el core saca el bloque vigente (los ajustes de arriba, la ganancia y los niveles del mezclador) por el buzón que comparte con el ARM, y el *companion* lo graba en el último sector de la QSPI de la placa (el bloque "MSXC", en 0xFFF000). En el siguiente encendido lo lee de ahí y lo siembra en el core antes de soltar el MSX, así que la máquina arranca ya con esos ajustes.

Si en la QSPI no hay un bloque válido (placa recién grabada, o un bloque que no pasa su suma de comprobación), el core arranca con los valores por defecto: Slot 1 = Nada, scanlines Off, estéreo On, Boot Turbo Off, Menú al arrancar On, ganancia x5 y los siete canales del mezclador a 8/8.

### Sobre Boot Turbo

La nota *"(reiniciar fisicamente)"* viene del menú común: el turbo de arranque solo entra en un arranque en frío. En la Zynq el ajuste se siembra en el core una sola vez, cuando el *companion* suelta el MSX, y el reinicio de Save & Restart no pasa por ahí. Para que entre hay que guardar y apagar y encender: el reinicio de Save & Restart no basta. Mantener el botón K3 al soltar el MSX en el arranque lo inhibe.

El turbo también se conmuta en caliente con **F11**, en cualquier momento; ese cambio no se guarda.

### 5.1. La página Mezclador de audio

La pantalla **MSXimus - Mezclador de audio** lista ocho filas, una por canal:

| Fila | Qué regula | Valores |
|---|---|---|
| **Ganancia maestra** | La ganancia de siempre del MSXimus, sobre el grupo clásico (PSG, SCC, OPLL y MSX-AUDIO) | x1, x1.5, x2, x3, x4, x5, x6, x8. Por defecto x5 |
| **PSG** | El PSG (los dos, en estéreo) | 0/8 a 8/8 |
| **SCC** | El SCC de la megaram y el 2o SCC del slot 1 | 0/8 a 8/8 |
| **OPLL (FM-PAC)** | MSX-MUSIC | 0/8 a 8/8 |
| **MSX-AUDIO** | El Y8950, con su ADPCM | 0/8 a 8/8 |
| **OPL4 FM (OPL3)** | La parte FM del MoonSound | 0/8 a 8/8 |
| **OPL4 wave** | La tabla de ondas del MoonSound | 0/8 a 8/8 |
| **WaveGame** | La música WAV de los juegos WaveGame | 0/8 a 8/8 |

Los niveles k/8 atenúan cada fuente antes de la suma: 8/8 es el sonido tal cual (x1, el valor por defecto) y 0/8 lo silencia. El OPL4 y el WaveGame entran a x1 y no pasan por la ganancia maestra. Cómo se mezcla todo, y el limitador que evita la saturación, está en el capítulo de audio.

| Tecla | Qué hace |
|---|---|
| **Arriba / Abajo** | Elegir el canal (la marca `>` a la izquierda) |
| **Izquierda / Derecha** | Bajar o subir el nivel del canal elegido. Cada cambio se aplica al momento y **toca una nota** de unos 250 ms (un La de 440 Hz) en ese mismo chip, para oír el nivel sin salir del menú |
| **ESPACIO** | Volver a oír la nota del canal elegido sin cambiar nada |
| **ESC** (o RETURN) | Volver a Ajustes |

La nota de prueba sale por el propio chip del canal: el PSG por su canal A, el SCC por un pequeño programa que el menú carga en la megaram, el OPLL, el Y8950 y el OPL3 con un tono de dos operadores, el OPL4 wave con la onda 0 de la tabla YRW801, y en el canal WaveGame el menú pide al *companion* que sintetice el tono. En la fila de la ganancia maestra la nota va por el PSG.

Los niveles que se dejan en esta página se conservan al volver a Ajustes, pero **no se guardan hasta pulsar Save & Restart**: van al mismo bloque de la QSPI que el resto de ajustes. Si se reinicia por otro camino, se pierden.

El menú comprueba al entrar si el core tiene mezclador y si es de la línea Zynq (la fila WaveGame solo se ofrece con un core Z). En la Zynq están las ocho filas.

Para programas propios, el mezclador se maneja por el puerto #44 del dispositivo goauld: está en la referencia técnica de los puertos de E/S.

## 6. Configuración WiFi (tecla W)

La tecla W no abre una pantalla del menú, sino el menú de configuración que trae el propio firmware del ESP32, el **Wi-Fi Setup** del driver TCP/IP UNAPI de ducasp. Sus opciones son *Set Nagle*, *Wi-Fi On Period*, *Scan/Join Access Points* y *Wi-Fi and Clock Settings*; con ESC se vuelve al navegador. Es ahí donde se elige la red y se pone la contraseña. La opción de reloj pone en hora el MSX por internet.

Necesita el módulo ESP32-S3 cableado al header CAM1 de la placa y con su firmware (repositorio [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`)), como se explica en el [capítulo 07](07-wifi-file-hunter.md). Sin él, esa pantalla muestra caracteres sin sentido, porque lee de una línea serie a la que no responde nadie.

## 7. File-Hunter (tecla F)

Busca ROMs y discos en la base de datos de File-Hunter y los descarga a la tarjeta. Hace falta la WiFi configurada y una carpeta `FHUNT` en la raíz de la tarjeta, creada desde MSX-DOS con `MKDIR FHUNT`.

1. **F** abre el campo *"File-Hunter Buscar:"* en la fila 0. Se escribe el texto (hasta 20 caracteres), RETURN busca y ESC cancela.
2. Se ven los pasos: *"Conectando..."*, *"DNS..."*, *"Abriendo..."*, *"Enviando GET..."*. Se hacen dos consultas seguidas, una de ROMs y otra de discos, y los resultados salen juntos en la lista del navegador.
3. En la lista de resultados: **RETURN** descarga el seleccionado, **F** hace otra búsqueda, **ESC** o **BACKSPACE** salen de File-Hunter. Los filtros y el resto de teclas del navegador no actúan aquí.
4. La descarga va a `FHUNT` con el nombre original en formato 8.3 y la etiqueta de mapper que dé la API, por ejemplo `[SCC].rom`. Se ve *"FH: bajando ..."* y al acabar se comprueba el CRC (*"CRC OK"*). Si ya existe un fichero con ese nombre y el mismo tamaño no se vuelve a bajar: la carpeta hace de caché. Si existe con otro tamaño pregunta *"Ya existe. Sobreescribir? (S/N)"* (*Y/N* en la variante inglesa). Se admiten ROMs de **hasta 8 MB**, el tamaño de la megaram.
5. Al terminar, el fichero se **lanza solo** por el mismo camino que cualquier ROM o disco de la tarjeta.

Límites: la tarjeta tiene que ser **FAT16** (con FAT32 dice *"FH: la SD es FAT32 (v1 solo FAT16)"*), la carpeta FHUNT tiene que existir (*"Falta FHUNT (MKDIR en DOS)"*) y los nombres se escriben en 8.3.

Mensajes de error: *"FH: sin UNAPI"* (no se ve el driver del ESP), *"FH: sin red (tecla W)"*, *"FH: fallo DNS"*, *"FH: sin conexion"*, *"FH: sin resultados"*, *"FH: timeout de descarga"*, *"FH: respuesta API rara"*, *"FH: error SD"*, *"FH: SD llena"*, *"FH: CRC MAL"*.

Cómo se cablea el módulo y qué firmware lleva está en el [capítulo 07](07-wifi-file-hunter.md).

## 8. Menú de pruebas (tecla T)

La pantalla **MSXimus - Pruebas** sirve para comprobar que la máquina va bien y para medir. Arriba muestra la versión del core, si el core trae cronómetro propio, el tipo de tarjeta y los bytes de configuración del core (`#41`, `#42` y `#46`, con el estado del menú al arrancar).

Dos avisos para la Zynq:

- La línea *"Core FPGA:"* de esta pantalla no conoce la codificación de la línea Zynq y escribe los dos dígitos del puerto 2Fh tal cual, sin la «Z». La versión fiable es la cabecera del panel F12.
- *"Tarjeta SD:"* dice siempre *SDHC*: el proxy de la SD del core presenta cualquier tarjeta de TF2 como una SDHC, sea la que sea.

| Tecla | Prueba |
|---|---|
| **1** | Velocidad de lectura de la SD. Lee los mismos 128 KB por cada uno de los cuatro caminos posibles (ventana, puertos sector a sector, puertos en multibloque y DMA a RAM) y da los KB/s de cada uno. No escribe nada en la tarjeta. En la Zynq los cuatro caminos pasan por el *companion*, que sirve los sectores desde la tarjeta de TF2 |
| **2** | Sonido: una nota por el PSG y otra por el OPLL (MSX-MUSIC) |
| **3** | Game Master 2 en el slot 1: vuelca lo que ve en el slot 1 con la ROM y la SRAM del último lanzamiento, para comprobar que el mapeo es correcto |
| **4** | VDP: cuenta cuántas veces se ven los bits HR y VR del registro de estado S#2 en 20000 lecturas, y da la referencia de un V9938 real |
| **ESC** | Seguir arrancando |

Lo que se ha medido de cada camino está en la [referencia técnica de la SD](../tecnica/06-sd-dma.md) (la DMA del *companion* llega a unos 1600 KB/s).

## 9. Ayuda (tecla H)

Una pantalla con la lista de teclas del navegador. Cualquier tecla vuelve.

## 10. El panel F12 (OSD del *companion*)

No es parte del menú de la BIOS, pero se usa con el mismo teclado y conviene saber que existe. **F12** en el teclado USB enciende y apaga un panel de texto en color sobre la imagen, que dibuja el *companion*. Mientras está abierto, **el Z80 se queda congelado** (es una pausa con datos) y el panel lo recuerda en su última línea. La página de información se refresca cada segundo (la de actualización, hasta cuatro veces por segundo) y tiene cinco secciones:

- **Sistema**: temperatura del chip (con su máximo) y tensiones internas, y el tiempo encendido.
- **Tarjeta SD**: si hay tarjeta en TF2 y de cuántos MB, y los errores.
- **USB**: cuántos dispositivos hay y de qué tipo (teclados, ratones, mandos, discos, hubs).
- **MSX**: la velocidad del Z80 (3,58 o 5,37 MHz; se conmuta con F11), el SCREEN actual, qué vídeo está en pantalla (V9968 o V9990) y si la ROM de ondas del OPL4 (YRW801) es válida.
- **Red**: la dirección IP de la Ethernet de la placa, o *sin cable o sin IP*.

Al pie hay tres botones: **U** abre la página de **actualización por red** (ESC vuelve a la de información), **P** abre la de **perfiles** y **F12** cierra el panel. Cómo se actualiza la máquina está en el [capítulo 12](12-actualizar.md); el panel F12 completo, con sus datos y su relación con el puente de vídeo, está en el [capítulo 09](09-video.md).

La página de **perfiles** (P) es para los perfiles del PL guardados en la microSD de TF1: enseña el estado de la tarjeta, el perfil que corre, el que se carga al encender (con una estrella) y la lista, cuya primera fila es siempre el perfil 1 (el del `BOOT.bin`). Cada perfil sale con su **nombre**: *Música* (*Music* en inglés) y *Dual*; el identificador interno no cambia (los perfiles ya instalados, la actualización por red y las etiquetas `[P:ID]` de las ROM siguen igual: `[P:MUSICA]`, y también vale `[P:MUSIC]`). Las flechas eligen, **Intro** carga el elegido (el MSX se reinicia y la imagen tarda unos segundos en volver; sobre el perfil 1 reinicia la placa) y **D** lo borra. **A** marca el elegido como el perfil **al encender**: la placa lo carga antes de arrancar el MSX (medio segundo más); sobre el perfil 1 lo quita. Si ese perfil falta o es de otra versión del sistema, arranca el 1. Volver al perfil 1 con Intro (dos veces) reinicia la placa y arranca el 1 esa vez, aunque haya perfil al encender. Si un perfil deja la placa sin imagen, se quita la microSD de TF1 y se enciende: arranca el 1. **S** abre la vista del servidor ([capítulo 12](12-actualizar.md), apartado 9). Si la tarjeta de TF1 es nueva, la página lo dice y la prepara ella ([capítulo 03](03-tarjeta-sd.md), sección 2): **T** e Intro si está vacía, a medias o con los directorios rotos (no borra nada); **B** («Borrar y preparar» / «Convertir») si tiene otros datos o es de las betas: la primera pulsación avisa de que se borra la tarjeta **entera** (con *datos de MSX-DOS* si tiene una FAT16), Intro lo hace y cualquier otra tecla o 10 s sin tocar cancelan. Con la placa arrancada desde SD no se puede (*«Pon SW1 en QSPI para prepararla»*). Hace falta una tarjeta de 1 GB o más. Nextor no ve esa tarjeta.

**Instalar un perfil desde un fichero.** Copia el `.mxp` a la tarjeta de TF2, elígelo en el navegador (sale con el tipo `MXP`) y pulsa RETURN: el panel F12 se abre solo y dice *«ID» instalado desde la TF2* o por qué no (sin tarjeta o sin partición de perfiles, perfil dañado, tarjeta llena). Se cierra con ESC o F12; después, Intro sobre ese perfil lo carga.

Desde la Z1.3 el V9968 y el V9990 salen por una sola HDMI y el panel F12 se dibuja encima de esa salida, también con el V9990 en pantalla. Si alguna vez no se viera, Pausa vuelve al V9968.

La misma información resumida sale por la pequeña OLED de la placa (conector J4), si está puesta.

## 11. Resumen de todas las teclas

| Dónde | Teclas |
|---|---|
| Logo | S (mantenerla entra en Ajustes aunque el menú esté en Off), W, T |
| Sin tarjeta | RETURN, ESC, S, W, T |
| Navegador | cursores, RETURN, BACKSPACE, /, TAB, R, D, A, S, W, T, F, U, P, N, H, ESC, mando USB (direcciones, A, B) |
| Búsqueda por nombre | texto, RETURN, BACKSPACE, ESC |
| Lanzar ROM | RETURN, M, S, G, V, B, ESC |
| Lanzar disco | RETURN, V, B, ESC |
| Ajustes | Arriba, Abajo, ESPACIO, ESC (salir sin guardar) |
| Mezclador de audio | Arriba, Abajo, Izquierda, Derecha, ESPACIO, ESC |
| File-Hunter | texto, RETURN, BACKSPACE, F, ESC |
| Pruebas | 1, 2, 3, 4, ESC |
| Ayuda | cualquiera |
| Panel F12 | U (página de actualización), P (perfiles), ESC (vuelve a la página de información), F12 (cerrar) |
| Página de perfiles | cursores, Intro, D, A, S, T, R, ESC. En la vista del servidor: cursores, Intro, A, U, B, T, S, ESC |
| Página de la máquina B (perfil Dual) | S, P, R, C, D (la SD), M (MSX-DOS), T, V, A (sonido de A), B (sonido de B), ESC |
| En cualquier momento | F11 (turbo), F12 (panel del *companion*), el reset de la placa (PS_SRST, reinicio de todo el procesador); el botón de reset del MSX (K2) reinicia solo el MSX |
