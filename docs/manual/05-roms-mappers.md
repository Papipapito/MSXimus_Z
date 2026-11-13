# 05. ROMs y mappers

Cómo lanza el MSXimus Z un cartucho desde un fichero de la tarjeta de TF2: dónde vive la ROM mientras se juega, qué mappers emula, cómo elige uno, qué pasa con la SRAM de los cartuchos que guardan partida, cómo funciona el Game Master 2 y qué es el segundo SCC. Las teclas concretas de la pantalla de lanzar están en el [capítulo 04](04-menu.md).

## 1. La megaram: el cartucho emulado

Al lanzar una ROM, el menú la copia de la tarjeta a una memoria de **8 MB** dentro de la máquina, la megaram, y le dice al core con qué mapper tiene que comportarse. Después pone la ROM en el **slot 2** y llama a su arranque directamente, sin reiniciar la máquina, como haría la BIOS con un cartucho pinchado. Deja además el slot 3 como queda tras un arranque en frío (las páginas 0 a 2 en 3-0, la RAM), para que los juegos que buscan la RAM con números de slot sin expandir, como *Sol Negro* para V9990, la encuentren. Un juego no puede distinguirlo de un cartucho real.

Caben ROMs de hasta 8 MB, y las que baja el File-Hunter también ([capítulo 04](04-menu.md), apartado 7).

En el MSXimus Z la megaram no es un chip aparte: vive en la **DDR3 del procesador (PS)**: los 4 MB bajos dentro de la misma ventana de 8 MB que ocupa la RAM del Z80 y los 4 MB altos en otra zona de la DDR que no usa nadie más. El core llega a ella por el puerto AXI HP1 a través de `memory_axi`, una caché de 64 KB en la lógica programable. Un acierto de caché se sirve en unos 75 ns, que es lo que espera un Z80 a 3,58 MHz y también a 5,37 MHz; un fallo frena la CPU con /WAIT hasta que llega la línea de la DDR. Para el juego es transparente.

### Cómo llega la ROM a la megaram

La tarjeta del MSX (TF2) cuelga del procesador, no de la lógica programable, así que la ROM hace dos viajes por la DDR:

1. El **companion** (el programa del ARM) lee los sectores de la tarjeta y los deja en un búfer de la DDR.
2. El core los copia de ahí a la megaram por **DMA**, cluster a cluster, con el Z80 parado y el bus en reposo. Los registros del mapper no se tocan: la DMA escribe en direcciones físicas.

En el menú de pruebas (tecla T, prueba 1) la ruta "DMA a RAM" da unos **1600 KB/s**. A ese ritmo un megarom de 512 KB carga en menos de un segundo y uno de 4 MB en pocos segundos. La barra de la pantalla de lanzar lo muestra.

Si la DMA falla en un cluster (error de lectura, tarjeta que se va), el menú repite ese cluster por la ruta lenta, sector a sector por el Z80, y sigue.

## 2. Los mappers

| Mapper | ROMs típicas | Tamaño máximo |
|---|---|---|
| **Plain** | Cartuchos de 8, 16 y 32 KB sin mapper | 32 KB |
| **Konami** | Konami sin SCC: Nemesis, Penguin Adventure, Metal Gear 1 | 256 KB, ninguno real es mayor |
| **Konami-SCC** | Konami con SCC: Salamander, Metal Gear 2, Space Manbow, y las conversiones grandes | 2 MB |
| **ASCII8** | La mayoría de los megaroms japoneses de 8 KB por banco: Aleste, Xak, Ys | 2 MB |
| **ASCII16** | Megaroms de 16 KB por banco: R-Type, Fire Hawk, Ys II | 4 MB |
| **NEO-8** | El mapper NEO de 8 KB por banco, para homebrew reciente | 4 MB |
| **NEO-16** | El mapper NEO de 16 KB por banco | 4 MB |
| **Plain 0000h** | ROMs planas que empiezan en 0000h, con su propia página 0 (las demos V9990 de Edd Biddulph) | 48 KB |
| **ASCII16-X** | El ASCII16 ampliado de [grauw.nl](https://www.grauw.nl/projects/ascii-x/ascii16-x/), el de los cartuchos XL: homebrew reciente como Another World para V9990 | 8 MB |

Los registros de banco del core son de 9 bits. En Konami, Konami-SCC y ASCII8 el software escribe 8 bits y su techo natural son 2 MB; ASCII16 usa el bit 7 del valor escrito para llegar a 4 MB, y los NEO llevan registros de 12 bits en dos escrituras. Todo lo que cabe en 2 MB cae en las mismas direcciones de siempre.

El **ASCII16-X** forma el número de banco con los 8 bits escritos y 4 bits de la dirección (A11-A8), acepta los registros en todos sus espejos (2000h, 6000h, A000h y E000h para la página 1; 3000h, 7000h, B000h y F000h para la 2) y ve la página 1 también en C000h y la 2 también en 0000h. El core usa 9 de esos 12 bits: 512 bancos de 16 KB, 8 MB. La **FlashROM** del cartucho XL no se emula: la ROM se trata como ROM, y un juego que guardara en ella no conservaría la partida.

Los cartuchos ASCII8 y ASCII16 con **SRAM** (Koei, Hydlide 3, Royal Blood) están cubiertos: la SRAM se emula y se guarda, apartado 4.

Lo que no hay: mappers exóticos como el R-Type original con su disposición propia, Cross Blaim, Harry Fox, o los cartuchos con hardware extra como el FM-PAC o el Sunrise. Y las ROMs que hacen de cartucho de disco.

## 3. Cómo se decide el mapper

En este orden:

1. **Tamaño.** Hasta 32 KB, Plain.
2. **Etiqueta en el nombre.** `[ASCII16]`, `[ASCII8]`, `[SCC]`, `[KONAMI]`, `NEO8` o `NEO-8`, `NEO16` o `NEO-16` (sin distinguir mayúsculas). Si la hay, manda sobre el análisis del contenido. Las pone File-Hunter al descargar, y uno mismo al renombrar. Es la forma de fijar un mapper de una vez para siempre.
3. **Análisis del contenido.** Sin etiqueta, el core cuenta, mientras carga, las instrucciones con que cada familia de mapper cambia de banco, y gana la familia con más. Lo hace el hardware sobre el flujo de la DMA, así que no cuesta tiempo. Es el mismo criterio que usa openMSX y acierta con casi todo (Xevious, por ejemplo, sale ASCII16, que es lo correcto). El análisis mira los primeros 256 KB. Si ahí sale Konami en una ROM de 320 KB o más, que es sospechoso porque ningún Konami sin SCC pasa de 256 KB, vuelve a mirar el fichero hasta 2 MB y decide otra vez (tarda unos 0,6 s por MB, solo en ese caso): así *Xybots* para V9990 sale ASCII16 y no Konami-SCC. Si sigue saliendo Konami, se promociona a Konami-SCC.
4. **A mano.** Si el análisis no ve nada, el mapper sale como desconocido y se elige con **M**, que va ciclando los nueve (Plain, Konami, Konami-SCC, ASCII8, ASCII16, NEO-8, NEO-16, Plain 0000h y ASCII16-X). Una vez encontrado, lo cómodo es poner la etiqueta en el nombre.

Y al acabar de cargar, el menú hace unas comprobaciones por el **contenido del fichero** que mandan sobre todo lo anterior, la etiqueta incluida, porque las pone el autor de la ROM:

- **Firma de tipo de ROM de MSXgl**: ocho letras sin terminador justo detrás de la cabecera `AB`, en el offset 10h del fichero (o en el 4010h, para un Konami-SCC con la cabecera en el segmento 2; ahí solo se mira si el fichero pasa de 4100h). Las conocidas fijan el mapper: `ROM_ASC8` es ASCII8, `ROM_AS16` es ASCII16, `ROM_KON4` es Konami, `ROM_KON5` es Konami-SCC, `ROM_NEO8` es NEO-8 y `ROM_NE16` es NEO-16. Las demás (ROM plana, Yamanooto, Popolon SCC) no cambian nada. Por eso las ROMs hechas con MSXgl, como las de geo3d, no necesitan etiqueta en el nombre.
- **Firma `ASCII16X`** en el offset 10h (la marca que pide la especificación del mapper, y la que usa openMSX): ASCII16-X.
- **Más de 4 MB sin firma**: ASCII16-X, el único mapper que direcciona tanto, salvo que el nombre lleve una etiqueta NEO, que se respeta.
- **Imagen de 16 a 48 KB** sin cabecera en 0 y con ella en 4000h: Plain 0000h.

Cuando una de estas comprobaciones cambia el mapper, la fila del mapper se repinta en cuanto la carga acaba, con la SRAM apagada (en ASCII8 y ASCII16 la tecla S la enciende).

Un mapper equivocado no rompe nada: el juego no arranca o se cuelga, y se vuelve al menú con reset.

Hay ROMs que engañan al análisis: las que cambian de banco con instrucciones distintas de la habitual, como las demos compiladas con z88dk, o las que llevan dentro código de dos mappers. Para esas, la etiqueta. Un caso concreto: las **ROMs WaveGame de Konami** son Konami-SCC, aunque el detector pueda decir Konami; si pasa, **M** hasta Konami-SCC, o `[SCC]` en el nombre (apartado 7).

## 4. La SRAM de cartucho y el guardado

Los cartuchos ASCII8 y ASCII16 con SRAM guardaban la partida en 8 o 32 KB de memoria con pila. En el MSXimus Z:

- La SRAM se emula en la propia megaram, en los **últimos 32 KB de la mitad baja** (segmentos 252 a 255). En ASCII8 se ven páginas de 8 KB; en ASCII16, 2 KB espejados en la ventana, como en los cartuchos reales. Solo existe en ASCII8 y ASCII16; en Konami y en los NEO no aparece.
- Se activa por defecto si el nombre lleva `KOEI` o `SRAM`, y se puede encender o apagar para cada lanzamiento con la tecla **S**. Un juego sin SRAM activada no la ve.
- Al lanzar, el menú busca en `FHUNT` un fichero con el mismo nombre que la ROM y extensión `.SRM` (32 KB). Si existe, lo carga como contenido de la SRAM; si no, deja la SRAM a FF (cartucho virgen) y crea el fichero con esos FF. Después escribe un descriptor en el segmento 511 de la megaram, fuera del alcance del juego, con el nombre del fichero, sus clusters y un checksum de los 32 KB.
- Al **siguiente arranque del navegador**, una vez por arranque, el menú lee el descriptor, recalcula el checksum y, si la SRAM cambió, reescribe los 64 sectores del `.SRM` en su sitio (misma cadena de clusters: ni la FAT ni el directorio cambian).

La consecuencia práctica: **para conservar la partida hay que hacer RESET, no apagar.** La megaram está en la DDR3, que aguanta un reset del MSX, y el menú guarda al arrancar; un apagado pierde lo que no se haya guardado aún. La línea de estado lo dice al arrancar: *"SRAM cambiada: guardando FHUNT/..."* y *"OK"*.

### Qué reset

En la placa hay dos cosas distintas que se llaman reset:

- **El botón de reset del MSX (K2)**, el que va al reset del core (tabla de botones del [capítulo 02](02-instalacion.md)). Reinicia el Z80 y los chips, vacía la caché y deja intacta la DDR3, megaram incluida. Es el que hay que usar para volver al menú y que se guarde la partida.
- **El reset de la placa (PS_SRST)** reinicia el procesador entero: vuelve a arrancar el companion desde la QSPI o desde TF1 y reprograma la lógica. Para guardar la partida, el reset es el del MSX.

Sin carpeta `FHUNT`, la SRAM funciona pero no se guarda: *"SRAM: sin FHUNT, no se guarda"*. Las ROMs de 4 MB (o más) ocupan los 4 MB bajos enteros, incluido el segmento del descriptor, y no dejan sitio: *"SRAM: ROM de 4 MB, no se guarda"*.

El guardado solo escribe si el `.SRM` sigue en la misma tarjeta y en el mismo sitio (misma `FHUNT`, mismo cluster, 32 KB). Cambiar de tarjeta entre el juego y el arranque siguiente no corrompe nada: el menú lo detecta y dice *"NO ESTA: se descarta"*. Si la tarjeta da error al escribir, *"ERROR SD: se reintenta al proximo arranque"*, y el descriptor se queda armado para la siguiente vez.

Cada lanzamiento pone el descriptor a cero antes de nada, para que una ROM de 2 MB sin SRAM, que deja datos suyos en los segmentos 252 a 255, no acabe "guardándose" en el último `.SRM`.

Límites: la tarjeta tiene que ser FAT16 (el escritor de `FHUNT` es el mismo que el de File-Hunter), y un `.SRM` copiado a mano sin nombre largo (solo 8.3) no se reconoce.

## 5. El Game Master 2

El **Game Master 2** de Konami (RC-755) era un cartucho que, pinchado junto a un juego Konami, le daba guardado de partida, trucos y un mapa. Es la forma de guardar en Metal Gear 2, SD Snatcher, Snatcher, Salamander y los demás Konami con SCC que lo reconocen.

El MSXimus Z lo emula en el **slot 1**, el único libre durante el juego (0 = BIOS, 2 = la megaram con el juego, 3 = expandido con RAM, menú y Nextor). Hace falta:

- `FHUNT\GM2.ROM`: la ROM del cartucho, 128 KB. La pone el usuario, por lo mismo que las ROMs de los juegos.
- `FHUNT\GM2.SRM`: sus 8 KB de SRAM. Los crea el menú la primera vez, a FF.

Y activarlo:

- En Ajustes, **Slot 1 = Game Master 2**, y Save & Restart (se guarda en la QSPI). Vale para todos los lanzamientos.
- Con ese ajuste puesto, la pantalla de lanzar enseña la fila **GM2: On** en los mappers Konami y Konami-SCC, y la tecla **G** lo quita para ese lanzamiento. Sirve para un juego que no es Konami pero usa el mapper Konami-SCC, como Space Manbow 2, que con el Game Master 2 activo no arranca.
- Sin ese ajuste no sale ni la fila ni la tecla (desde la Z1.4.9; antes se podía poner para un solo lanzamiento).

Por dentro, la ROM y la SRAM del Game Master 2 van a la **mitad alta de la megaram** (segmentos 480 a 495 la ROM, 496 la SRAM, 497 su descriptor), que solo tocan los juegos de 4 MB. El menú las carga con la misma rutina que la SRAM del apartado 4, arma el cartucho con un bit volátil del puerto #46 y el core mapea esos segmentos en el slot 1 con el mapper del GM2 (página 0 fija en 4000h, registros en 6000h, 8000h y A000h, SRAM en la ventana de A000h y escritura solo por B000h, como el original y como en openMSX). El core borra el bit de armado en cada reset, para que el escaneo de slots de la BIOS no se encuentre un cartucho en el slot 1 al volver al menú.

El guardado funciona igual que el de la SRAM: se escribe en `GM2.SRM` al siguiente arranque del navegador, tras un reset del MSX (K2), si el checksum de los 8 KB cambió. El propio Game Master 2 tiene su utilidad para formatear la SRAM la primera vez.

Al arrancar el juego con el Game Master 2 armado, sale primero la pantalla del cartucho, como en un MSX real: desde ahí se arranca el juego, o se entra en su menú de trucos y guardado.

Si falta algo, el juego arranca igual, sin Game Master 2, y la línea de estado dice por qué: *"GM2: falta FHUNT/GM2.ROM"*, *"GM2: GM2.ROM no mide 128 KB"*, *"GM2: sin FHUNT (MKDIR en DOS)"*, *"GM2: error SD, sin GM2"*. Las ROMs de 3840 KB o más pisan la mitad alta y con ellas no se arma. Y con la opción **Slot 1 = 2o SCC** el slot está ocupado por el segundo SCC y el Game Master 2 no se ofrece: las dos opciones son excluyentes en Ajustes, y el core además las hace excluyentes por su cuenta.

Para comprobar el mapeo hay una prueba en el menú de pruebas (T, prueba 3): vuelca lo que se ve en el slot 1 con la ROM y la SRAM del último lanzamiento.

Una advertencia con Metal Gear 2: hay una versión española de la ROM, la que circula con el número [9692], cuya rutina de arranque comprueba si hay MSX-DOS y no es compatible con el arranque a través del Game Master 2: pantalla negra. No es del core. Otras versiones, como la [3371] española o la [1489] japonesa, arrancan y guardan sin problema.

## 6. El segundo SCC

La opción **Slot 1 = 2o SCC** de Ajustes pone en el slot 1 un **SCC-I solo de sonido**: un cartucho sin memoria detrás (leer fuera de sus registros devuelve FF) con sus propios registros de banco y de modo, incluido el modo SCC+ y la relectura de la RAM de onda. Vive siempre en el slot opuesto a la megaram, así que los trackers y reproductores que buscan dos SCC en dos slots distintos encuentran los dos. Es el mismo chip que el SCC de la megaram, al mismo nivel; en el mezclador de audio los dos van por el canal SCC.

En estéreo cada SCC reparte sus cinco canales entre los dos lados, el segundo en espejo del primero; el reparto está en el [capítulo 08](08-audio.md). En mono se suman.

Con el segundo SCC puesto no hay Game Master 2, y al revés: el slot 1 es de uno o de otro. Un juego normal, que solo usa el SCC de su propio cartucho, no nota nada con el segundo SCC activado.

## 7. ROMs con música WaveGame

Algunas ROMs de Konami llevan una versión con **WaveGame**: el juego pide al hardware que toque pistas de música en WAV en lugar del PSG/SCC, con el protocolo de Jeroen Taverne que usan el MSX Pico, el PicoVerse y openMSX. El MSXimus Z lo trae de serie: el companion lee los WAV de la tarjeta y los sirve a una voz del core, mezclada con el resto del audio.

Para usarlas, la carpeta de la ROM en TF2 tiene que llevar, junto al `.ROM`, los ficheros `NN.wav` (00 a 63, 48 kHz, mono, 16 bits), los `NN.cfg` opcionales (punto de bucle) y `pause.wav`. Al lanzar la ROM, el menú avisa al companion de qué carpeta es, y este monta la FAT (16 o 32) y busca ahí los WAV. Si no los encuentra, el juego arranca igual, sin música WAV.

Dos cosas a tener en cuenta:

- El mapper: son **Konami-SCC**. Si el detector dice Konami, **M** hasta Konami-SCC o `[SCC]` en el nombre. Renombrar la ROM no afecta a los WAV, que se buscan por carpeta.
- El volumen del WaveGame tiene su propio canal en el mezclador de audio (Ajustes), como cualquier otro chip. El detalle del protocolo y de la voz está en el [capítulo 08](08-audio.md).

Validado con F1-Spirit [MSX Pico WaveGame v1.1].

## 8. ROMs que no lanzan

- **"INIT pag.0/BASIC: no lanzable"**: una ROM plana cuyo punto de entrada cae fuera de la ventana del cartucho. Suelen ser programas BASIC empaquetados como ROM. Lanzarla reiniciaría la máquina, así que el menú lo impide. Cambiar el mapper con M vuelve a evaluar ese veto.
- Una ROM de disco (las que emulan una unidad) no tiene sentido aquí: el disco ya lo pone Nextor.
- Una ROM mayor de 8 MB no cabe. Entre 4 y 8 MB solo tiene sentido con ASCII16-X: los demás mappers no llegan tan lejos.
- Tras un **reset**, la BIOS vuelve a arrancar la ROM que haya en la megaram, como con un cartucho pinchado. El core conserva en el reset la extensión del mapper (NEO, Plain 0000h, ASCII16-X), así que esas ROMs vuelven a arrancar con su mapper. Las ROMs que arrancan en dos fases, como la demo *kokoro*, dejan paso al menú.

## 9. Dónde vive cada cosa en la megaram

Para quien quiera saber qué hay en cada rincón de los 8 MB (segmentos de 8 KB):

| Segmentos | Qué hay |
|---|---|
| 0 a 255 | Mitad baja, 2 MB: la ROM del juego (todos los mappers) |
| 252 a 255 | SRAM de cartucho emulada (32 KB), cuando está activada |
| 256 a 511 | Mitad alta, 2 MB: solo la usan las ROMs de más de 2 MB (ASCII16, NEO y ASCII16-X) |
| 512 a 1023 | Los 4 MB altos, en otra zona de la DDR: solo los ASCII16-X de más de 4 MB |
| 480 a 495 | ROM del Game Master 2 (128 KB) |
| 496 | SRAM del Game Master 2 (8 KB) |
| 497 | Descriptor del guardado del Game Master 2 |
| 511 | Descriptor del guardado de la SRAM de cartucho |

Todo esto está en la DDR3 del procesador. Las herramientas de desarrollo por JTAG (`boot.tcl`, `packswap.tcl`) cargan el pack de BIOS y limpian la RAM principal y la VRAM, pero no tocan la megaram.
