# 08. Audio

Todo el sonido del MSXimus Z sale por el HDMI, mezclado dentro de la lógica programable (PL). El procesador ARM (el *companion*) no toca el audio salvo en dos cosas: sirve la música WaveGame y guarda los ajustes en la QSPI. Este capítulo dice qué chips hay, qué ve el software, cómo se reparte el estéreo, cómo se ajusta el volumen chip a chip con el mezclador y cómo se usa el WaveGame.

## 1. Los chips

| Chip | Qué es | Dónde lo ve el software |
|---|---|---|
| **PSG** | El sonido básico de todo MSX, tres voces y ruido | Puertos A0-A2, como siempre |
| **Segundo PSG** | Otro PSG completo | Puertos 10-12, para el software que lo busca ahí |
| **SCC y SCC+** | El chip de ondas de Konami, cinco voces | Dentro del cartucho emulado, en el slot 2. Cualquier juego con mapper Konami-SCC lo tiene, y los que usan el SCC+ también |
| **Segundo SCC** | Otro SCC en el slot 1 | Para trackers y reproductores que buscan un SCC como cartucho aparte. Se activa en Ajustes, **Slot 1 = 2o SCC**, y es incompatible con el Game Master 2, que va en el mismo slot |
| **OPLL** | MSX-MUSIC: el YM2413 de nueve voces, como el integrado de los MSX2+ (no el cartucho FM-PAC: no hay sus registros en 7FF4h-7FF6h ni su SRAM). Es **IKAOPLL**, un núcleo reconstruido de las fotos del dado del YM2413, con el registro de test: suena también el software que hace PCM con él, como la demo *kokoro* | Puertos 7C-7D. La firma `APRLOPLL` y la tabla de llamadas de la FM-BIOS están en la ROM del menú (slot 3-1), pero no su extensión de BASIC: `CALL MUSIC` da *Syntax error* |
| **MSX-Audio** | El Y8950 del Music Module de Philips: FM de nueve voces más un canal ADPCM de muestras | Puertos C0-C1, con 32 KB de memoria de muestras. Las interrupciones del chip funcionan |
| **MoonSound** | El OPL4 completo: FM de 18 voces (OPL3) y 24 voces de tabla de ondas con la ROM YRW801 de 2 MB | Puertos C4-C7 el FM, 7E-7F las ondas. Ver la sección siguiente |
| **WaveGame** | Una voz PCM que reproduce ficheros WAV desde la tarjeta, gobernada por el juego | Puerto 92h (una orden por byte). Sección 5 |

Todo esto está a la vez y sin conflictos: un juego puede usar PSG y SCC, un reproductor puede tocar el MoonSound mientras el PSG hace los efectos, y un juego WaveGame tiene su música en WAV y sus efectos en el PSG.

### El MoonSound

El OPL4 es el del MoonSound de verdad: FM de 18 voces en modo OPL3 (o 9 en modo OPL2, según el bit NEW del registro 105h), y 24 voces de ondas con sus 2 MB de instrumentos de la YRW801. El motor de ondas interpola entre muestras y el FM lleva los temporizadores del chip (80,78 y 323,1 µs).

El nivel de cada parte se ajusta con los registros **F8h** (FM) y **F9h** (ondas) del bloque de ondas (puertos 7Eh y 7Fh, con el bit NEW2 puesto), como en un MoonSound. F8h arranca en 1Bh (el FM a −9 dB por lado) y ajusta cada lado por separado. Quien no quiera tocar registros tiene **MTVOL.COM**, que fija el volumen del FM y del wave de cualquier OPL4 (`MTVOL FM <n>`, `MTVOL WAVE <n>`); el SD Maker lo copia a la carpeta `FPGA` de la tarjeta. Aparte de esto, el nivel de cada parte frente al resto de chips se pone en el mezclador (sección 4).

### La ROM de ondas del MoonSound

La YRW801 no se graba en ninguna memoria del core: **va dentro del `BOOT.bin`** y al arrancar queda cargada en la DDR3 del PS (a partir de 0x0F000000). El OPL4 la lee desde ahí por un puerto AXI propio (`fpga/zynq/wave_axi.v`, por el GP0 del PS7), y los 2 MB siguientes de la DDR son la RAM de muestras del OPL4, la que escribe el software que carga sus propios instrumentos. Con el `BOOT.bin` de la entrega no hay que hacer nada.

Quien se construya el `BOOT.bin` necesita `yrw801.rom`: `make_boot.sh [pack] [yrw801.rom]` la toma por defecto de `packs/zynq/roms/` del repositorio privado de BIOS (`MSXIMUS_BIOS_PRIV`, véase el [capítulo 02](02-instalacion.md)), y en un arranque por JTAG `boot.tcl` la carga él de ahí (variable `WAVE_ROM` para usar otra ruta). Sin ella el OPL4 tiene FM pero no ondas: el software que use instrumentos de la ROM sonará incompleto. Para no tener que adivinarlo, el companion suma los bytes de los 2 MB una vez arrancado el MSX y los compara con los de la YRW801 de verdad (suma 101FDA0Eh, md5 42af9361...): el panel F12 lo dice en la fila *OPL4* (`YRW801 OK` / `YRW801 no válida`) y, si no cuadra, la OLED avisa en lugar de la fila del VDP. Solo avisa; el OPL4 sigue funcionando.

## 2. Mono y estéreo

En Ajustes, **Stereo Sound** (de fábrica, On):

| | Izquierda | Centro | Derecha |
|---|---|---|---|
| **Off** | Todo mezclado | | Todo mezclado |
| **On** | Canal A de cada PSG; canales 1 y 4 del SCC; canales 1, 4 y 7 del OPLL y del MSX-Audio, y su platillo | Canal B de cada PSG; canal 3 del SCC; canales 3, 6 y 9 del OPLL y del MSX-Audio, y su bombo, caja y tom; ADPCM; WaveGame de los juegos | Canal C de cada PSG; canales 2 y 5 del SCC; canales 2, 5 y 8 del OPLL y del MSX-Audio, y su charles |

El estéreo reparte **los tres canales de cada PSG** como las modificaciones "PSG estéreo" de siempre: el A a la izquierda, el B en el centro y el C a la derecha (izquierda = (2A+B)/4, derecha = (2C+B)/4, así que al sumar los dos lados sale exactamente la mezcla mono).

**El SCC, el OPLL y el MSX-Audio también van por canales**, con un reparto más suave, que en música suena más natural que el todo o nada: los canales de la columna izquierda de la tabla van 3/4 a la izquierda y 1/4 a la derecha, los de la derecha al revés, y los del centro, mitad y mitad. En el modo ritmo del OPLL y del MSX-Audio, el charles va a la derecha y el platillo a la izquierda (como una batería vista desde delante); bombo, caja y tom, al centro. El ADPCM del MSX-Audio va al centro. El **segundo SCC** reparte **en espejo** (1 y 4 a la derecha, 2 y 5 a la izquierda), para que un tracker que use los diez canales separe los dos chips. Igual que en el PSG, izquierda + derecha es exactamente la mezcla mono de cada chip: el modo mono no cambia.

El **MoonSound** hace lo que hace el chip de verdad: la parte PCM, con el panorama de cada voz, y la FM, con los bits de salida de cada canal (registros C0h-C8h, bit 4 = izquierda, bit 5 = derecha) cuando está en modo OPL3 (bit NEW del registro 105h); en modo OPL2 la FM sale por los dos lados.

El WaveGame de los juegos entra igual por los dos lados, en el centro. La **música del menú** (WAV y MP3) sí va en estéreo de verdad si el fichero es estéreo; los ficheros mono suenan en el centro.

## 3. El volumen: la ganancia maestra

Cada chip entra al mezclador a su nivel real, medido contra openMSX, y el grupo clásico (PSG, SCC, OPLL, MSX-Audio) lleva una **ganancia maestra** que sirve para ponerlo a la altura del MoonSound, que suena más fuerte de origen. El OPL4 y el WaveGame no pasan por ella: entran a x1.

| Valor | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| Ganancia | x1 | x1,5 | x2 | x3 | x4 | **x5** (fábrica) | x6 | x8 |

Al final de la cadena hay un limitador de rodilla suave: por debajo de 0,75 del fondo de escala no toca nada y por encima comprime 2:1. Con la ganancia alta y muchos chips a la vez se comprime, no distorsiona a saco.

La ganancia maestra es la primera fila del mezclador de audio (sección 4) y se guarda en la QSPI con el resto de ajustes. Desde software sigue siendo el puerto 44h del dispositivo de configuración, con el mismo significado de siempre: `OUT #44,0..7`.

## 4. El mezclador de audio

Es una página de Ajustes desde la que se pone el nivel de cada fuente de sonido por separado, oyéndola, y se guarda con lo demás.

### Cómo se entra

En **Ajustes** (tecla S en el menú) hay una fila **Mezclador de audio**, entre *Menú al arrancar* y *Save & Restart*. Con ESPACIO sobre ella se abre la pantalla **MSXimus - Mezclador de audio**. Al abrirse lee los niveles que tiene el core en ese momento, así que lo que se ve es lo que está sonando, incluido lo que el companion sembró desde la QSPI al arrancar.

### La pantalla

Ocho filas, una por canal:

| Canal | Fila | Qué regula | Valores |
|---|---|---|---|
| 0 | **Ganancia maestra** | El grupo clásico entero (PSG, SCC, OPLL, MSX-Audio), lo de la sección 3 | x1, x1,5, x2, x3, x4, x5, x6, x8 |
| 1 | **PSG** | Los dos PSG | 0/8 a 8/8 |
| 2 | **SCC** | El SCC del cartucho y el segundo SCC del slot 1 | 0/8 a 8/8 |
| 3 | **OPLL (FM-PAC)** | El MSX-MUSIC | 0/8 a 8/8 |
| 4 | **MSX-AUDIO** | El Y8950, FM y ADPCM juntos | 0/8 a 8/8 |
| 5 | **OPL4 FM (OPL3)** | La parte FM del MoonSound | 0/8 a 8/8 |
| 6 | **OPL4 wave** | La tabla de ondas del MoonSound | 0/8 a 8/8 |
| 7 | **WaveGame** | La voz WAV del WaveGame | 0/8 a 8/8 |

Los canales 1 a 7 son atenuadores: el nivel *n* multiplica la fuente por *n*/8 **antes** de la suma. 8/8 es x1 y es el valor de fábrica de todos; 0/8 deja el chip mudo. Cada fila se pinta como una barra de ocho posiciones y el número. La ganancia maestra actúa después, sobre la suma del grupo clásico, así que las dos cosas se combinan: PSG a 4/8 con maestra x5 es PSG a x2,5 respecto al MoonSound.

### Las teclas

| Tecla | Qué hace |
|---|---|
| **Arriba / Abajo** | Elegir el canal |
| **Izquierda / Derecha** | Bajar o subir el nivel del canal elegido. Cambia en el acto |
| **ESPACIO** | Volver a oír la nota de prueba del canal elegido |
| **ESC** (o RETURN) | Volver a Ajustes |

Se sale con ESC o con RETURN (Ajustes también tiene ESC). Los cambios ya están sonando al salir; lo que no se guarda vive hasta que se apaga la placa o se pulsa el reset de la placa (PS_SRST).

### La nota de prueba

Cada vez que se cambia un nivel (o se pulsa ESPACIO) el chip de ese canal toca unos 250 ms de un La (440 Hz) y se calla, para oír el nivel sin salir del menú y sin necesitar un juego que use ese chip. La toca el propio chip por sus puertos normales, o sea que también sirve para comprobar que el chip responde:

| Canal | Cómo suena la nota |
|---|---|
| Ganancia maestra | Con el PSG |
| PSG | Canal A por A0/A1 |
| SCC | Una onda cargada en el SCC desde un pequeño programa en RAM (megaram en modo SCC) |
| OPLL | Piano en el canal 0 por 7C/7D |
| MSX-AUDIO | Canal 0 del Y8950 por C0/C1 |
| OPL4 FM | Canal 0 por C4/C5, en modo OPL2 |
| OPL4 wave | La onda 0 de la YRW801 por 7E/7F, con el chip en modo NEW2. Sin la ROM de ondas no suena |
| WaveGame | El menú pide la nota al companion (`'W','T'` por el puerto 93h) y este sintetiza 300 ms a 440 Hz sin leer ningún fichero |

### Guardar

Los niveles se guardan con **Save & Restart** de Ajustes, junto con todo lo demás: al pulsarlo el core saca el bloque de configuración y los siete niveles por el buzón de la DDR, el companion los graba en el bloque `MSXC` de la QSPI (0xFFF000, formato v2 con los niveles) y en el siguiente arranque los siembra en el core antes de soltar el MSX. Nada que hacer con tarjetas ni ficheros.

Un reset del MSX no borra los niveles, que no forman parte del reset del core. Un apagado o el reset de la placa (PS_SRST) sí, y vuelven los de la QSPI.

### Desde software: el puerto 44h extendido

El puerto 44h del dispositivo de configuración (el `#48` del goauld, seleccionado con `OUT #40,#48`) da acceso a todo el mezclador y conserva el uso antiguo:

| Operación | Formato |
|---|---|
| `OUT #44, valor` | `valor` = {bit 7: solo seleccionar, bits 6-4: canal 0-7, bits 3-0: nivel}. Canal 0 = ganancia maestra (nivel 0-7, la tabla de la sección 3); canales 1-7 = nivel 0-8, los mayores de 8 se recortan a 8. Con el bit 7 a 1 no escribe nada, solo deja el canal elegido para la lectura |
| `IN #44` | {0, canal elegido, su nivel}. Con el canal 0 devuelve la ganancia maestra en los bits 2-0, como siempre |
| Sonda | `OUT #44,#F0` y luego `IN #44`: un core con mezclador devuelve `#7n`; uno sin él, la ganancia maestra |

Como los valores 0 a 7 llevan el canal 0 en los bits 6-4, el `OUT #44,0..7` de toda la vida sigue queriendo decir *ganancia maestra*. Desde BASIC, para dejar el SCC a la mitad:

```basic
OUT &H40,&H48 : OUT &H44,&H24
```

y para guardar y reiniciar por el mismo camino que Save & Restart:

```basic
OUT &H40,&H48 : A=INP(&H41) : B=INP(&H42) : OUT &H41,A : OUT &H42,B OR &HC0
```

(bit 6 = guardar, bit 7 = reiniciar). Es la misma secuencia que usa el menú: leer los dos registros **antes** de escribir y escribir los dos, primero `#41` y luego `#42`. Cada puerto confirma solo su registro, así que bastaría con el `#42`; la secuencia completa es la que usa el menú. La línea de BASIC de arriba no se ha probado expresamente en la Z1.2.13; la secuencia es la del menú.

Para desarrollo, `fpga/zynq/tools/cfg.tcl show` enseña el bloque vigente y la siembra del mezclador, y `cfg.tcl mix <7 niveles>` los cambia por JTAG.

## 5. WaveGame

WaveGame es un protocolo de **Jeroen Taverne** para que un juego de MSX tenga banda sonora en WAV: el mismo que usan el MSX Pico, el PicoVerse y openMSX. El juego escribe un byte en el puerto 92h para decir "toca la canción 3 en bucle" o "fundido en 2 segundos", y otro sistema, aquí el companion, se encarga de leer los ficheros y reproducirlos. Hay juegos conocidos (F1-Spirit, Castlevania y otros de Konami) publicados en versión WaveGame con sus WAV.

### Cómo se usa

1. Copiar la carpeta del juego **tal cual** a la tarjeta de TF2 (la "SD" del MSX): la ROM, los `NN.wav`, los `NN.cfg` y el `pause.wav` tienen que estar en la **misma carpeta** que la ROM. La tarjeta puede ser FAT16 o FAT32.
2. Lanzar la ROM desde el menú como cualquier otra. No hay nada que activar: al lanzar una ROM el menú le dice al companion en qué carpeta está, el companion mira si hay `NN.wav` y, si los hay, queda a la escucha del puerto 92h. Si no los hay, no pasa nada.
3. Las ROMs WaveGame de Konami son **Konami-SCC** (17 bancos): si el detector de mappers dice *Konami* (le pasa a Castlevania), pulsar **M** hasta *Konami-SCC* antes de lanzar ([capítulo 05](05-roms-mappers.md)).

Solo funciona con ROMs lanzadas desde el menú, que es cuando se manda la carpeta al companion; con discos no hay WaveGame.

### Los ficheros

| Fichero | Qué es |
|---|---|
| `NN.wav` | La canción NN, de `00` a `63`. El protocolo las define a 48 kHz, mono, 16 bits. El companion acepta cualquier WAV PCM: mono o estéreo (lo pasa a mono), 8 o 16 bits, a cualquier frecuencia, porque lo remuestrea a 44,1 kHz |
| `NN.cfg` | Opcional. Texto: primera línea, posición del bucle en muestras (a dónde vuelve la canción al acabar cuando suena en bucle); segunda línea, posición de inicio. Sin él, el bucle vuelve al principio |
| `pause.wav` | La música de pausa, la que pide la orden F0 |

### Las órdenes del puerto 92h

Para quien haga o adapte software. Un byte por orden, sin respuesta:

| Byte | Orden |
|---|---|
| `01xxxxxx` | Tocar la canción xx una vez |
| `10xxxxxx` | Tocar la canción xx en bucle |
| `0000xxxx` | Fundido de salida de x segundos (0 = 1 s); al llegar a cero se para |
| `C0` | Pausa; otra vez, continúa donde estaba |
| `D0` | Diferir: la siguiente orden espera a que acabe la canción actual (solo si no está en bucle) |
| `E0` | Retomar la canción anterior con fundido de entrada de 1 s |
| `F0` | Tocar `pause.wav` |

### El volumen del WaveGame

La voz entra al mezclador a **x1**, fuera de la ganancia maestra, porque los WAV vienen a fondo de escala. Para bajarla respecto al resto está el canal 7 del mezclador (sección 4). Si aun así se quiere más, el companion admite una ganancia x1/x2/x4/x8 y un volumen fino de 0 a 255 por el buzón (`fpga/zynq/tools/wg.tcl gain` y `vol`), pero por encima de x1 el limitador ya recorta con los WAV a tope.

### Cómo funciona por dentro

Al lanzar la ROM, el menú manda por el puerto 93h `'W','G'` más el LBA de la partición y los clusters de la carpeta y del fichero. El companion monta la FAT de TF2 con eso, busca los `NN.wav` de la carpeta y anota dónde están. Cada orden que el juego escribe en el 92h entra en un anillo del PL que el buzón vuelca a la DDR; el companion la lee, abre el WAV, lo remuestrea a 44,1 kHz con la ganancia y el fundido ya aplicados y va escribiendo muestras en un anillo de 32768 en la DDR, unos 93 ms por delante. El PL las trae en bloques de 64 y las mezcla con el resto del audio. Un cambio de canción es instantáneo: el companion vacía el anillo y el PL su FIFO.

El log del companion (`tools/armlog.tcl`) cuenta lo que hace con líneas `wg: ...` (cuántos WAV ha encontrado, qué orden ha recibido, si falta un fichero), y `tools/wg.tcl` enseña el estado y permite inyectar órdenes sin juego.

## 6. Música en el menú (WAV y MP3)

El navegador de la SD toca música mientras se busca un juego. Usa la misma voz que el WaveGame, así que su volumen es el canal **WaveGame** del mezclador.

- Los ficheros `.wav` y `.mp3` salen en la lista (pestañas ALL y ROM) con su etiqueta y tamaño a la derecha, por ejemplo `WAV 2584K` o `MP3 586K`.
- **RETURN** sobre uno toca la carpeta **empezando por ese fichero** y sigue sola con los siguientes.
- **P** toca la carpeta desde el primero; **P** otra vez **pausa**, y otra más **sigue** donde se quedó.
- **N** pasa a la pista siguiente.
- Mientras suena, bajo las pestañas de filtro se lee *"Musica: P pausa, N siguiente"*.
- Salir del menú (ESC, lanzar una ROM, un disco, la disquetera o una cinta) para la música.

Formatos: WAV PCM de 8 o 16 bits y MP3 (MPEG-1 y MPEG-2 capa III, también de tasa variable; las etiquetas ID3 se saltan), mono o estéreo y a cualquier frecuencia, porque se remuestrea a 44,1 kHz. Los ficheros se leen en streaming desde la tarjeta, así que el tamaño no importa. Con **Stereo Sound** encendido, los ficheros estéreo suenan en estéreo; los mono, en el centro.

El MP3 lo descodifica el companion (minimp3, con la FPU del ARM) a menos del 2 % de su tiempo por trama; el WAV y el MP3 llegan al core por el mismo anillo que el WaveGame, que en estéreo lleva las muestras por pares izquierda/derecha.

## 7. Casos conocidos

- **VGMPlay** con VGMs de OPL3 se cuelga bajo Nextor 3, no bajo Nextor 2.1.4 ([capítulo 06](06-msxdos-nextor.md)). Es del reproductor, no del core.
- El **MoonSound** necesita la YRW801 en la DDR: sin ella solo suena el FM (sección 1).

## 8. Lo que no hay

- Salida analógica: la placa no trae ninguna; todo va por el HDMI, así que hace falta un televisor o un extractor de audio HDMI.
- Volumen en el panel F12: el panel del companion enseña estado, temperatura y tensiones, no toca el sonido. El volumen se gobierna con el mezclador o con el televisor.
- Chips fuera de la lista: no hay Darky ni SFG-01.
