# 03. Las tarjetas SD: TF1 y TF2

La ZYNQ MINI tiene dos ranuras microSD y cada una hace un papel distinto. **TF2 es la tarjeta del MSX**: ROMs, discos, carpetas WaveGame, MSX-DOS. **TF1 es la tarjeta de los perfiles del sistema** (el MSX no la ve) y, si se quiere, la que arranca la placa desde una SD. Este capítulo cuenta cómo preparar las dos y qué poner en TF2. Todo lo que dice sale del código del menú, del driver de disco y del companion.

## 1. Dos ranuras, dos papeles

| Ranura | Quién la lee | Qué lleva |
|---|---|---|
| **TF1** (SD0 del procesador) | El companion (perfiles) y, solo si SW1 está en SD (OFF-OFF), el bootloader del PS | Los perfiles, en una partición propia que la placa prepara sola (sección 2). Para arrancar: `BOOT.bin` en la raíz de la primera partición, **FAT32**. Con SW1 en QSPI (ON-OFF) y sin perfiles no hace falta nada aquí |
| **TF2** (SD1 del procesador) | El companion, que la sirve al MSX | La tarjeta del MSX: **FAT16 o FAT32**, con las ROMs, los `.dsk`, las carpetas WaveGame y los ficheros de MSX-DOS o Nextor |

El bootloader carga desde TF1 el `BOOT.bin` (FSBL, bitstream, companion, pack de BIOS y tabla de ondas) y a partir de ahí esa parte de la tarjeta no se vuelve a tocar; el MSX no ve TF1 de ninguna manera (sección 2). El menú, WaveGame y Nextor no la leen. Y la placa arranca sin nada en TF2: el menú dice *"No se detecta la tarjeta SD."* y ofrece arrancar el MSX (RETURN), los Ajustes (S) y la WiFi (W).

Cómo llega la tarjeta de TF2 al MSX: el core no tiene un controlador de SD propio, tiene un **proxy de sectores**. Cada lectura o escritura del MSX se deja en un buzón de la DDR, el companion hace el acceso real a la tarjeta con el controlador SD del procesador y devuelve los datos. Para el menú y para Nextor es una SD normal, con la misma interfaz que siempre; lo que cambia es la velocidad (sección 10). Los ajustes del menú no se guardan en la tarjeta: van al último sector de la QSPI ([capítulo 04](04-menu.md)).

## 2. TF1: los perfiles y, si se quiere, el arranque desde la SD

Hay dos formas de arrancar la placa y el bootloader solo usa TF1 en una:

- **Desde la QSPI** (SW1 en ON-OFF): el `BOOT.bin` está grabado en la memoria QSPI de la placa y TF1 puede estar vacía o ni siquiera puesta. Es lo normal una vez grabada la placa.
- **Desde la SD** (SW1 en OFF-OFF): el bootloader busca `BOOT.bin` en la raíz de la tarjeta de TF1, formateada en **FAT32**. Sirve para probar una versión sin regrabar la QSPI, o para una placa que aún no la tiene grabada.

Dos cosas que conviene tener claras:

1. **SW1 se lee solo al quitar y dar la corriente.** El reset de la placa (PS_SRST) no lo relee: si se cambia el interruptor hay que apagar y encender.
2. Hay un `BOOT.bin` por cada combinación de Nextor (2 o 3) e idioma (castellano o inglés): los cuatro `BOOT_Z1.3.0_*.bin` están en la release de GitHub. También se construye desde el repositorio con `fpga/zynq/arm/boot/make_boot.sh`. El [capítulo 02](02-instalacion.md) explica cómo.

### Preparar la tarjeta de TF1 (perfiles)

Los **perfiles** son versiones del sistema con otros chips (Música, Dual, Turbo R...; [capítulo 04](04-menu.md), apartado 10). Se guardan en TF1, en una partición propia sin sistema de ficheros que **Windows no muestra** y que Nextor no ve. La tarjeta tiene que ser de **1 GB o más**. Una vez preparada la tarjeta queda así (la prepara la propia placa; no hace falta ningún programa en el PC):

| Partición | Qué es |
|---|---|
| 1 | **FAT32** de 128 MiB, etiqueta `MSXIMUS-Z`, con un `LEEME.TXT`. Es la que lee el bootloader: ahí puede ir el `BOOT.bin` si se arranca desde SD |
| 2 | Tipo `DA` de 512 MiB: los perfiles (seis huecos de 4 MiB). Nadie más la toca |
| (el resto) | Sin usar |

**Cómo se prepara.** Meter la tarjeta, **F12 → P** (página de perfiles). Con una tarjeta nueva la placa avisa sola: una línea naranja en la página de información del F12 y un aviso en la OLED. Lo que pasa depende de lo que lleve la tarjeta:

| La tarjeta | Qué hace la placa |
|---|---|
| **Vacía** (el primer MiB entero a cero o a FF) | **T** e Intro: la prepara, sin borrar nada |
| **Ya preparada** | Nada: es la buena |
| **De las betas** (partición de perfiles compartida con una FAT) | Sigue funcionando tal cual. **B** («Convertir») la deja como una nueva y pierde los perfiles instalados, que se vuelven a bajar |
| **A medias** (se fue la luz preparándola) | **T** e Intro la terminan |
| **Con los directorios de perfiles rotos** | **T** e Intro los rehacen, sin borrar nada |
| **Cualquier otra** (FAT32 de fábrica, exFAT, NTFS, GPT, la FAT16 de la antigua unidad B: de Nextor...) | La página dice *«no es del MSXimus Z»*, el formato y las particiones. Para guardar perfiles hay que **borrarla entera**: **B** («Borrar y preparar») pregunta *¿Seguro?* y solo **Intro** lo hace; cualquier otra tecla o 10 s sin tocar cancelan. Si tiene una FAT16 avisa de que son **datos de MSX-DOS** |

Salvaguardas: **si la placa arrancó desde la SD** (SW1 en SD) la TF1 es la tarjeta de arranque y la placa **no la prepara ni la borra**, aunque se confirme (*«Has arrancado desde esta tarjeta. Pon SW1 en QSPI para prepararla»*); no toca nada más que las particiones, el principio de las viejas y, si era GPT, sus cabeceras; antes de escribir comprueba que la tarjeta **guarda lo que se le escribe** (una tarjeta falsa, de capacidad inventada, se rechaza); y el MBR se escribe siempre el último, así que si se va la luz la tarjeta queda como estaba o a medias (y se termina con **T**). Esto no sustituye a H2testw: solo prueba unos cuantos sectores.

**Después de preparar.** Con cable de red la placa busca sola en el servidor y baja los perfiles. Sin cable, o por WiFi, pulsa **S** (el servidor), y **A** baja todos; por WiFi el MSX se queda sin ESP mientras baja. También vale un `.MXP` desde el navegador del menú (RETURN). La tarjeta preparada sin perfiles dice *«Sin perfiles»*.

**La TF1 ya no es una unidad de Nextor.** Hasta la Z1.4.2 una microSD en TF1 aparecía en MS-DOS como «MSXimus uSD TF1», la segunda unidad (B:). Quien tuviera datos en esa tarjeta como unidad B: (desde la Z1.2.13) deja de verlos con la Z1.4.3: la placa ya no la presenta al MSX. Hay que copiarlos antes a TF2 o a un PC; al preparar la tarjeta la placa avisa de que tiene datos de MSX-DOS y la borra entera.

## 3. TF2: qué tarjeta

**De marca**: Samsung, SanDisk, Kingston. Una tarjeta sin marca puede rechazar escrituras en ráfagas largas, que es justo lo que hacen las descargas y los guardados. Si las descargas o los guardados hacen cosas raras, la primera sospechosa es la tarjeta.

El tamaño da igual dentro de lo razonable: el controlador del procesador admite tarjetas SD y SDHC, y el companion publica su tamaño en MB. Las tarjetas SDXC (más de 32 GB) no están probadas; en cualquier caso vienen en exFAT y habría que reparticionarlas en FAT16 o FAT32. Dos sitios dicen qué tarjeta hay puesta: el **panel F12** (en su sección *Tarjeta SD*, *"NNNN MB"* o *"sin tarjeta"*) y la **pantalla OLED** de la placa (*"SD NNNNMB"* o *"SD --"*). El menú de pruebas (tecla **T**) no vale para eso: el proxy le presenta al MSX siempre una SDHC v2 con un CSD sintético, sea cual sea la tarjeta real.

## 4. Formato de TF2

La tarjeta tiene que llevar **tabla de particiones** (MBR): el menú enumera las cuatro primarias y las lógicas de la cadena extendida, y se queda con las que sean FAT12/16/32 (tipos 01, 04, 06, 0E, 0B y 0C). Una tarjeta formateada como "superfloppy", sin MBR, no se detecta.

**FAT16 en la primera partición** es lo que funciona entero. Con FAT32 el navegador y el lanzador de discos van igual, pero no las dos funciones que escriben en la tarjeta:

| Función | FAT16 | FAT32 |
|---|---|---|
| Navegar y lanzar ROMs | sí | sí |
| Lanzar discos `.dsk` | sí | sí |
| Música WaveGame | sí | sí |
| Descargar con File-Hunter | sí | no: *"FH: la SD es FAT32 (v1 solo FAT16)"* |
| Guardar la SRAM de cartucho y el Game Master 2 | sí | no |
| Nextor desde MSX-DOS | sí | no: Nextor no monta FAT32 (ni la 2.1.4 ni la 3.0) |

La forma recomendada de dejarla lista es **[MSX SD Maker](https://github.com/Papipapito/SD_Maker) 1.4** (repositorio Papipapito/SD_Maker), un programa para Windows, con sus instrucciones en su repositorio, que trae el contenido de la tarjeta (sección 5) y la prepara: parte la tarjeta en particiones FAT16 de 2 o 4 GB como lo hace el FDISK de Nextor (o en una sola FAT32), copia Nextor o MSX-DOS, SofaRun, Multi Mente y el resto de programas, y escribe el `AUTOEXEC.BAT`. Hay que elegir en él el mismo Nextor que lleva la máquina. Sin él: una tarjeta de 2 GB o menos se formatea en FAT16 desde cualquier sistema, y con tarjetas mayores hay que crear una partición de hasta 2 GB en FAT16 con una herramienta de particiones o con `CALL FDISK` desde el propio MSX. El menú admite **varias particiones** y la tecla **TAB** cambia de una a otra, así que una tarjeta grande puede llevar una FAT16 para el menú y otras para MSX-DOS. El `AUTOEXEC.BAT` del contenido base (sección 5) cuenta con eso: monta la partición 2 como `C:` y la 3 como `D:`.

Nombres largos: el navegador los **muestra**, pero todo lo que el menú **escribe** va en formato 8.3. Un fichero que crea el menú, como una descarga o un guardado, se verá con nombre corto en el PC.

## 5. Qué poner y dónde

### El contenido base

El contenido de la tarjeta lo trae MSX SD Maker (carpeta `sd/` del repositorio [Papipapito/SD_Maker](https://github.com/Papipapito/SD_Maker)). Lo que va en la raíz es: **todo `base/`** más **la carpeta de la versión de Nextor que lleve el pack** grabado en la placa, y solo una de las dos:

```
sd/
├── base/                    común a todo, va siempre
│   ├── AUTOEXEC.BAT         PATH, TEMP, hora por sntp, mapdrv de C: y D:
│   ├── UTIL/                utilidades genéricas de DOS (en el PATH)
│   ├── WIFI/                cliente WiFi/UNAPI y FH.COM, el File-Hunter de DOS
│   ├── MM/, musica/, FONTS/ Multi Mente, reproductores, fuentes
│   ├── FHUNT/               VACÍA a propósito: descargas y guardados del menú
│   └── TMP/                 VACÍA a propósito: temporales de DOS
├── nextor-2.1.4/            NEXTOR.SYS, COMMAND2.COM, MSXDOS2.SYS y sus herramientas
└── nextor-3.0.0-beta2/      NEXTOR.SYS, COMMAND3.COM y las herramientas de Nextor 3
```

Las herramientas de `nextor-2.1.4/` y las de `nextor-3.0.0-beta2/` no se mezclan en la misma tarjeta: son versiones distintas de los mismos programas (`MAPDRV`, `DEVINFO`, `CHKDSK`...) emparejadas con su kernel. **Cambiar de Nextor (otro `BOOT.bin`) pide también el `NEXTOR.SYS` de ese Nextor en la tarjeta**: con el de la otra versión el MSX no llega a DOS. El [capítulo 06](06-msxdos-nextor.md) entra en Nextor.

Si `FHUNT` o `TMP` se pierden al copiar (los sistemas de control de versiones no guardan carpetas vacías), se crean a mano. **El menú no crea carpetas.** Sin `FHUNT` no hay descargas ni guardados, y el menú lo dice en la fila de estado (*"GM2: sin FHUNT (MKDIR en DOS)"*, *"SRAM: sin FHUNT, no se guarda"*).

### Las ROMs y los discos

El navegador lista carpetas, ROMs (`.ROM`), discos (`.DSK`), cintas (`.TSX` y `.CAS`, [capítulo 11](11-cinta.md)) y música (`.WAV` y `.MP3`, [capítulo 08](08-audio.md)). Lo demás no se ve, aunque esté. Pueden ir en cualquier carpeta, hasta ocho niveles de profundidad, y el orden es el del directorio.

| Carpeta | Para qué |
|---|---|
| Cualquiera | ROMs y discos, organizados como se quiera. Una ROM WaveGame va con sus `.wav` en la misma carpeta (sección 6) |
| **`FHUNT`** en la raíz | La crea el usuario desde MSX-DOS con `MKDIR FHUNT` o viene del contenido base. Ahí van las descargas de File-Hunter, los guardados `.SRM` y la ROM del Game Master 2 |
| Raíz | Nextor busca aquí `NEXTOR.EMU` para montar discos en tarjetas FAT16; lo crea el menú solo, oculto |
| Raíz | Los ficheros de arranque de MSX-DOS o Nextor si se quiere arrancar en DOS: `MSXDOS2.SYS`, `NEXTOR.SYS`, `COMMAND2.COM` (o `COMMAND3.COM` con Nextor 3), `AUTOEXEC.BAT` |

### Ficheros con nombre especial

| Fichero | Qué es |
|---|---|
| `FHUNT\GM2.ROM` | La ROM del cartucho Game Master 2 de Konami (RC-755), 128 KB justos. La pone el usuario, con ese nombre corto. Necesaria para el guardado de partidas de los juegos Konami con *Slot 1 = Game Master 2* en Ajustes |
| `FHUNT\GM2.SRM` | Los 8 KB de SRAM del Game Master 2. Lo crea el menú la primera vez |
| `FHUNT\<nombre>.SRM` | Los 32 KB de SRAM de cada cartucho ASCII8 o ASCII16 con SRAM, con el mismo nombre que la ROM. Lo crea el menú la primera vez. Un `.SRM` copiado a mano solo con nombre corto no se reconoce |
| `NEXTOR.EMU` | Descriptor de emulación de disco, oculto, en la raíz. Solo en FAT16: en FAT32 el menú usa un sector reservado de la partición y no crea ningún fichero |
| `NN.wav`, `NN.cfg`, `pause.wav` | La música WaveGame de la ROM que está en su misma carpeta (sección 6) |

Cómo se guardan la SRAM y el Game Master 2: el menú carga el `.SRM` en la megaram al lanzar y lo reescribe en su sitio de la tarjeta (misma cadena de clústeres, ni FAT ni directorio cambian) **al volver al navegador tras el reset que sigue a la partida**, si el contenido ha cambiado. En un apagado se pierde lo no guardado: reset, no apagar. La megaram vive en la DDR3 del procesador, que el reset del MSX no toca; el reset que hay que usar para guardar es el botón de reset del MSX (K2), no el reset de la placa (PS_SRST).

> **Con el perfil Dual** (la D sola del menú deja la SD en B): A sigue guardando su `.SRM` —y el de la Game Master 2— porque el companion le deja escribir en esos ficheros aunque la dueña sea B. Hace falta que la carpeta `FHUNT` y el `.SRM` existan (el menú los crea al lanzar, antes de pasar la SD a B). Todo lo demás que A escriba se rechaza mientras B tenga la SD ([capítulo técnico 14](../tecnica/14-perfil-dual.md)).

## 6. Carpetas WaveGame

**WaveGame** es el protocolo de Jeroen Taverne (el del MSX Pico, el PicoVerse y openMSX) con el que un juego parcheado manda tocar música en WAV mientras corre: el juego escribe una orden de un byte en el puerto 92h y el companion sirve el fichero desde TF2 a una voz de audio del core. El [capítulo 08](08-audio.md) describe el protocolo y el mezclador; aquí va lo que tiene que haber en la tarjeta.

**Se copia la carpeta del juego tal cual**, ROM y ficheros de audio juntos, a cualquier sitio de TF2 (la raíz también vale):

| Fichero | Qué es |
|---|---|
| `NN.wav` | La canción `NN`, con **dos cifras exactas**, de `00` a `63`. `01.wav` sí; `1.wav` o `song01.wav` no |
| `NN.cfg` | Opcional. Texto: línea 1 = muestra donde empieza el bucle, línea 2 = muestra de inicio |
| `pause.wav` | Opcional. Lo que suena cuando el juego pide la pausa |

Cómo llega la carpeta al companion: al lanzar la ROM, el menú le manda por el puerto 93h la partición, el clúster de la carpeta y el clúster del fichero. Con eso el companion monta la FAT de la tarjeta (16 o 32), busca ahí los `NN.wav` y queda a la espera de las órdenes del 92h. **Solo funciona al lanzar la ROM desde el menú**: cargada de otra forma, el companion no sabe en qué carpeta mirar.

Formato de los WAV: el estándar del protocolo es **48 kHz, mono, 16 bits**, y así vienen los packs publicados. El companion lee la cabecera RIFF (`fmt` + `data`) y acepta mono o estéreo (lo pasa a mono), 8 o 16 bits y cualquier frecuencia: todo se remuestrea a 44,1 kHz por el camino. Los ficheros se leen en streaming desde la tarjeta, no se cargan en memoria, así que el tamaño no importa. Hasta 64 canciones por carpeta.

Tres detalles prácticos:

- Las ROMs WaveGame de Konami (Castlevania, F1-Spirit...) son **Konami-SCC**. Si el detector del menú dice *Konami*, pulsa **M** hasta *Konami-SCC* antes de lanzar ([capítulo 05](05-roms-mappers.md)).
- El volumen del WaveGame es el canal 7 del mezclador de Ajustes; entra a ganancia x1 porque los WAV vienen a fondo de escala y más alto distorsionaba.
- Validado en placa con *F1-Spirit [MSX Pico WaveGame v1.1]*.

## 7. Etiquetas en el nombre de las ROMs

El menú decide el mapper de una ROM mirando su contenido, pero si el nombre lleva una etiqueta, la etiqueta manda. File-Hunter las pone al descargar, y uno mismo puede ponerlas al renombrar:

| Etiqueta en el nombre | Mapper |
|---|---|
| `[ASCII16]` | ASCII16 |
| `[ASCII8]` | ASCII8 |
| `[SCC]` o `[KonamiSCC]` | Konami-SCC |
| `[KONAMI]` | Konami |
| `NEO16` o `NEO-16` | NEO-16 |
| `NEO8` o `NEO-8` | NEO-8 |
| `KOEI` o `SRAM` | Además del mapper, activa la SRAM de cartucho por defecto |

Las mayúsculas no importan. Una ROM sin etiqueta y cuyo análisis no dé resultado sale como mapper desconocido, y se elige a mano con la tecla **M** en la pantalla de lanzar. El [capítulo 05](05-roms-mappers.md) va al detalle.

## 8. Discos `.dsk`

Un `.dsk` tiene que estar **en clústeres consecutivos** de la tarjeta, porque Nextor lo monta como un rango lineal de sectores. Los ficheros recién copiados a una tarjeta poco usada lo están; en una tarjeta con muchas borradas y escrituras puede que no, y entonces el menú avisa con *"DSK fragmentado: recopialo"*. Basta con copiarlo de nuevo desde el PC.

El montaje no asigna clústeres ni crea entradas de directorio, salvo la primera vez en FAT16, cuando crea el `NEXTOR.EMU` de la raíz; después lo reescribe en su sitio. En FAT32 escribe un sector reservado de la partición que ni el PC ni DOS usan y no crea nada. Por eso lanzar discos funciona en los dos formatos aunque las descargas y los guardados no.

## 9. Cambiar de tarjeta

El companion vigila la ranura: sin tarjeta reintenta la inicialización cada medio segundo, con tarjeta le pregunta su estado cada dos, y si un acceso falla la reinicializa y reintenta una vez. Físicamente, sacar y meter una tarjeta con la placa encendida no rompe nada.

Pero lo que hay encima no se entera: el menú monta la tarjeta una vez y guarda su geometría y su listado en RAM, y Nextor tampoco remonta. Cambiar de tarjeta con la máquina en marcha deja al menú con el listado de la anterior y a DOS escribiendo donde no debe. **Se cambia con la placa apagada o se pulsa el botón de reset del MSX (K2) después.**

## 10. Velocidad

Lo que da el menú de pruebas (tecla **T**, 128 KB por ruta):

| Ruta | KB/s |
|---|---|
| Ventana en la página 1 | 100 |
| Puertos, un sector | 114 |
| Puertos, multibloque | 125 |
| **Puertos, DMA a RAM** | **1600** |

El menú carga las ROMs por DMA clúster a clúster y Nextor lee por DMA en modo lógico, así que las cargas de ROM y los accesos de DOS van por la fila rápida. Las otras tres son el camino clásico byte a byte del Z80, y ahí manda el LDIR, no la tarjeta.

## 11. Editar ficheros de la tarjeta desde el PC

Los ficheros de texto del MSX, como `AUTOEXEC.BAT`, llevan fin de línea CR+LF y barras invertidas en las rutas. Un editor que los convierta a fin de línea Unix o toque las barras los deja inservibles para MSX-DOS. Si se editan desde el PC, con un editor que respete el formato. Los `.cfg` del WaveGame, en cambio, solo llevan números y el companion los lee igual con CR+LF que con LF.

## 12. Preparar las tarjetas desde cero, resumido

**TF2**, la del MSX:

1. Formatear en FAT16 (con MBR). Si la tarjeta es grande, una partición FAT16 de hasta 2 GB y el resto para DOS.
2. Copiar a la raíz (o dejar que lo haga MSX SD Maker) el contenido de `base/` y el de la carpeta de Nextor que lleve el pack de la placa (`nextor-2.1.4/` o `nextor-3.0.0-beta2/`), incluidos `NEXTOR.SYS`, `COMMAND2.COM` o `COMMAND3.COM` y `AUTOEXEC.BAT`.
3. Comprobar que existen `FHUNT` y `TMP` en la raíz, en mayúsculas. Si no, `MKDIR FHUNT` desde MSX-DOS o crearlas desde el PC.
4. Copiar `GM2.ROM` dentro de `FHUNT` si se van a usar los guardados del Game Master 2.
5. Copiar las ROMs y los discos en las carpetas que se quiera; los juegos WaveGame, con su carpeta entera.
6. Meterla en **TF2** y encender.

**TF1** (perfiles; sección 2): meter la tarjeta (1 GB o más), encender con SW1 en ON-OFF y preparar la tarjeta con F12 → P. Si además se quiere arrancar desde la SD:

1. Con la tarjeta ya preparada, copiar `BOOT.bin` a la raíz de su primera partición (FAT32, `MSXIMUS-Z`) desde el PC.
2. SW1 en OFF-OFF, meterla en **TF1**, apagar y encender. (Arrancando desde la SD la placa no prepara ni borra esa tarjeta.)

Con el sistema grabado en la QSPI y sin perfiles, TF1 se queda vacía y sobra esta lista.
