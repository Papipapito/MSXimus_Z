# 06. MSX-DOS y Nextor

El disco del MSXimus Z es la tarjeta microSD de la ranura **TF2**, y quien la sirve al MSX es **Nextor**, el sistema de disco de Nestor Soto que sustituye al MSX-DOS 2 y sabe de particiones grandes y FAT16. Nextor, el menú de arranque y el driver de la tarjeta son los heredados del MSXimus; lo que cambia en esta placa es quién mueve los sectores: la tarjeta cuelga del procesador ARM (el *companion*), no de la lógica del MSX, y los sectores viajan por la DDR3. Para Nextor es transparente. Este capítulo cuenta qué ranura es cada dispositivo, qué versión de Nextor hay, cómo se arranca en DOS, cómo se lanza un disco de imagen y qué esperar del rendimiento.

## 1. Dos ranuras, dos dispositivos

La ZYNQ MINI tiene dos ranuras microSD y no hacen lo mismo:

| Ranura | Para qué | Qué lleva |
|---|---|---|
| **TF1** | Los perfiles del sistema y, solo si SW1 está en SD (OFF-OFF), el arranque del procesador. **El MSX no la ve** | La prepara la placa ([capítulo 03](03-tarjeta-sd.md), sección 2) |
| **TF2** | **El disco del MSX**, dispositivo 1 de Nextor («microSD card slot») | ROMs, `.dsk`, carpetas WaveGame y, si se quiere arrancar en DOS, los ficheros de sistema de Nextor |

Salvo que se diga otra cosa, lo que dice este capítulo y el [capítulo 03](03-tarjeta-sd.md) sobre "la tarjeta" se refiere a **TF2**: es la que arranca DOS, la que lee el menú y la que usan el File-Hunter y WaveGame. La microSD de TF1 no aparece en Nextor (sección 2).

Cómo llega un sector al MSX: el core pide "sector N, tantos bloques" por el mismo controlador de siempre; la petición cae en un buzón de la DDR3, el companion la atiende con el controlador SD del procesador (bus de 4 bits a 50 MHz), deja los datos en la DDR3 y acusa; el core los recoge de ahí. Las escrituras van al revés y se aplican en la tarjeta en el momento, sin caché intermedia. Nextor, el menú y cualquier programa que use el driver ven el controlador de siempre, con los mismos registros y los mismos puertos.

Tres consecuencias prácticas:

- **Sin tarjeta en TF2 el MSX arranca igual**: el menú dice *"No se detecta la tarjeta SD."* y con RETURN sigue a BASIC sin disco (sin menú, cae en BASIC directamente). El companion reintenta cada medio segundo, así que si se mete la tarjeta después la encuentra, pero Nextor no la monta: hay que reiniciar con el botón de reset del MSX (K2).
- **No se cambia la tarjeta en caliente.** El companion se da cuenta de que la tarjeta se ha ido (la sondea cada dos segundos) y reinicializa la nueva, pero el driver de Nextor responde siempre "disponible, sin cambios" y seguiría usando la FAT de la anterior. Para cambiarla: sacar, meter y el botón de reset del MSX (K2).
- El **panel F12** congela el Z80 mientras está abierto, también en mitad de una transferencia de disco. Al cerrarlo sigue donde estaba. Ese panel enseña la tarjeta tal como la ve el companion: tamaño real en MB y errores.

## 2. Las dos versiones

El pack de BIOS lleva Nextor dentro, en el slot 3-2 de la máquina, y hay dos packs que solo difieren en eso:

| Pack (`packs/zynq/msximus/`) | Nextor | Cuándo |
|---|---|---|
| `pack_bios_msximus.bin` | **2.1.4** | El de uso diario. Estable, con años de software probado encima. Es el que se recomienda |
| `pack_bios_msximus_nextor3.bin` | **3.0** | La versión final de Konamiman. Hay software que todavía no la lleva bien |

En esta placa el pack no se graba aparte: va **dentro del `BOOT.bin`** (junto al bitstream, el companion y la tabla de ondas del OPL4), y al arrancar el companion lo deja en la DDR3, de donde el core lo lee. Por eso hay un `BOOT.bin` por versión de Nextor y de idioma (los cuatro `BOOT_<versión>_*.bin` de la release), y cambiar de Nextor es cambiar de `BOOT.bin`: grabarlo en la QSPI o copiarlo a TF1, como cuenta el [capítulo 02](02-instalacion.md). Los ajustes no se pierden al cambiar: viven en un sector propio de la QSPI, no en el pack. **Hay que cambiar también el sistema de la tarjeta de TF2**: el `NEXTOR.SYS` (y `COMMAND2.COM` o `COMMAND3.COM`) tiene que ser el de ese Nextor, y con el de la otra versión el MSX no llega a DOS. [MSX SD Maker](03-tarjeta-sd.md) lo copia al preparar la tarjeta; hay que elegir en él el mismo Nextor que lleva la máquina.

El driver de la tarjeta es el mismo en los dos packs, hecho para este core, y declara la versión **3.5.4** en las dos versiones de Nextor. Al arrancar sondea qué tiene delante y usa lo más rápido que encuentre: los puertos de E/S del controlador en vez de la ventana de memoria, órdenes multibloque en vez de un mandato por sector y, para leer, la **DMA en modo lógico**: el driver le da al core la dirección del búfer de Nextor y el core copia los sectores a la RAM del MSX sin que el Z80 mueva un byte. Esa última ruta solo entra cuando el búfer está en la RAM del mapper (slot 3-0) y fuera de la página 1; si no, el driver lee por puertos como siempre. Nada de esto se configura: lo decide el driver en cada petición.

**La TF1 ya no es una unidad de Nextor.** Hasta la Z1.4.2 el driver ofrecía la microSD de TF1 como dispositivo 2 («MSXimus uSD TF1»), con letra detrás de las de TF2. Desde la Z1.4.3 la TF1 es solo de los perfiles: el driver no ha cambiado, pero el companion contesta que no hay dispositivo 2 y Nextor no enseña ninguna unidad más. Quien tuviera datos en esa tarjeta como unidad B: (desde la Z1.2.13) deja de verlos con la Z1.4.3: la placa ya no la presenta al MSX. Hay que copiarlos antes a TF2 o a un PC; al preparar la tarjeta la placa avisa de que tiene datos de MSX-DOS y la borra entera. Ver el [capítulo 03](03-tarjeta-sd.md), sección 2.

Estado:

- **Nextor 2.1.4** está comprobado en la placa: arranque en DOS por DMA, `AUTOEXEC.BAT`, `DIR` de una segunda partición, Multi Mente cargado y funcionando, y crear, leer, listar y borrar ficheros desde DOS sobre la tarjeta real.
- **Nextor 3.0** lleva el mismo driver que la 2.1.4, así que se comporta igual con la tarjeta.
- Un caso conocido con Nextor 3 y este mismo driver: **VGMPlay** se cuelga al reproducir un VGM de OPL3, mientras que con Nextor 2.1.4 reproduce bien y MoonBlaster con OPL4 funciona bajo Nextor 3. Es del reproductor, no del core ni del driver; conviene reportarlo a sus autores citando la versión de Nextor 3 que se use.

## 3. Arrancar en DOS

Con el ajuste **Menú al arrancar** en Off, la máquina arranca directamente en Nextor desde la tarjeta, como un MSX con su interfaz de disco. Con el menú activo, **ESC** en el navegador hace lo mismo. El ajuste lo guarda el companion en la QSPI y sobrevive al apagado; si se deja el menú en Off y se quiere volver a Ajustes, se mantiene pulsada **S** durante el logo.

En cualquier caso, la tarjeta de TF2 necesita en la raíz de su primera partición los ficheros de sistema: `NEXTOR.SYS` y `COMMAND2.COM` para Nextor 2, o `NEXTOR.SYS` y `COMMAND3.COM` para Nextor 3, y opcionalmente un `AUTOEXEC.BAT`. Sin ellos se arranca en BASIC, con el disco accesible desde ahí.

[MSX SD Maker](https://github.com/Papipapito/SD_Maker) trae el contenido de partida de la tarjeta y lo copia él; a mano, a la raíz va **`base/`** (un `AUTOEXEC.BAT` que monta C: y D: con `MAPDRV` y arma el `PATH`; `UTIL/` con las utilidades genéricas; `WIFI/` con el cliente UNAPI y el File-Hunter de DOS; y las carpetas `FHUNT/` y `TMP/`, vacías a propósito) más **la carpeta de la versión de Nextor que lleve el pack**: `nextor-2.1.4/` o `nextor-3.0.0/`. No hay que mezclar las herramientas de una versión con el kernel de la otra: `MAPDRV`, por ejemplo, cambió de sintaxis entre las dos.

Desde DOS todo es lo de siempre: `DIR`, `COPY`, ejecutar `.COM`, Nextor con sus utilidades. Las particiones que Nextor vea son unidades A:, B:, etc.

Detalles de esta máquina:

- El disco está en el **slot 3-2**, expandido. Las utilidades que piden el slot del driver, como `DRVTEST`, lo quieren así: `DRVTEST 3-2`, no `DRVTEST 3`. El resto del slot 3: 3-0 es el mapper de RAM, 3-1 la sub-ROM con el logo y el menú, 3-3 la megaram. La ROM del ESP32 (UNAPI) está en el 0-2.
- Nextor **no puede escribir en la tarjeta mientras el propio driver está en la página 1**, y `DRVTEST` lo llama directamente. Redirigir su salida a la SD da "Disk error writing drive A". No es un fallo: se redirige a un disco RAM (`RAMDISK 256`; la letra la dice él al crearlo) y luego se copia.
- No hay ranura de cartucho, así que el aviso de Nextor 3 de que desactiva cualquier kernel Nextor 2 que encuentre en la máquina aquí no tiene a quién afectar.

## 4. Lanzar un disco de imagen

Desde el navegador del menú, RETURN sobre un `.dsk` y RETURN otra vez para **montar y lanzar**. El menú deja a Nextor un descriptor de emulación y sigue el arranque: Nextor ve la imagen como unidad A: en modo MSX-DOS 1 y ejecuta su sector de arranque, como si el disquete estuviera en una disquetera. Dura hasta el siguiente arranque (botón de reset del MSX (K2) o apagar y encender); después la unidad A: vuelve a ser la tarjeta.

Requisitos: el `.dsk` en clusters consecutivos (capítulo 03; si no lo está, el menú avisa y basta con copiarlo de nuevo desde el PC). El descriptor va a un sitio distinto según el formato de la partición: en **FAT32** a un sector reservado de la propia partición, invisible desde el PC y sin crear ningún fichero; en **FAT16** al fichero oculto `NEXTOR.EMU` de la raíz, que el menú crea la primera vez (512 bytes, un cluster) y a partir de ahí solo reescribe. Es la única cosa que el menú crea en la tarjeta: todo lo demás, incluido el propio `.dsk`, se queda como está.

Los juegos de disco que usan MSX-DOS y música FM, como Aleste, funcionan así con las dos versiones de Nextor. Los que necesitan cambiar de disco se montan como un solo `.dsk` con todos sus discos seguidos (apartado *Juegos de varios discos en un solo `.dsk`*, al final).

## 5. Rendimiento

La tarjeta se lee por DMA y los sectores ya están en la DDR3 cuando el core los pide: el core congela el Z80, vacía cada bloque en la memoria del MSX (que también vive en la DDR3, con una caché que acepta cada escritura en un ciclo) y lo suelta al acabar la orden. El resultado son **1600 KB/s** sostenidos, unas dieciséis veces la ruta clásica por la ventana de memoria. El arranque de DOS y la carga de programas grandes se notan; una orden puede pedir hasta 255 sectores de golpe.

El menú de pruebas (tecla **T** al arrancar, opción 1) mide los cuatro caminos de lectura sobre los mismos 128 KB con el cronómetro del core, y sirve para ver que la tarjeta y el core están bien:

| Camino | KB/s |
|---|---|
| Ventana de memoria (página 1) | 100 |
| Puertos, un sector por orden | 114 |
| Puertos, multibloque | 125 |
| Puertos, DMA a RAM | **1600** |

Los tres primeros los limita el Z80 moviendo bytes; el cuarto, la DDR3. Los números apenas dependen de la tarjeta: quien la lee es el controlador del procesador, a 50 MHz y 4 bits, y el MSX solo ve la DDR3.

Dos avisos sobre lo que enseña ese menú:

- En "Tarjeta SD:" dirá siempre **SDHC**. El core no habla con la tarjeta real: el proxy le presenta una tarjeta sintética de ese tipo sea cual sea la que haya en TF2. El tipo y el tamaño reales están en el panel F12.
- La escritura no va por DMA: sale por los puertos, un byte del Z80 cada vez, y el companion la aplica en la tarjeta antes de acusar. Es más lenta que la lectura, como en cualquier MSX. La velocidad de escritura está pendiente de medir.

Para desarrollo existe además un modo sin tarjeta ni companion: una imagen de disco cargada en la DDR3 por JTAG (`tools/boot.tcl <pack> <bit> <imagen>`, con `tools/mkfat16.py` para fabricarla). Es cosa de la referencia técnica; el usuario no lo ve.

## 6. Otros sistemas

**SymbOS 4.0** tiene una imagen de tarjeta preparada para este controlador, con el driver de disco `-WNDTNG.DRV` (el de la interfaz SD de Luis Antoniosi, con la que este controlador es compatible registro a registro); está en su propio repositorio. Está pendiente de probar. Y todo lo que corra sobre Nextor, como MSX-DOS 2 con sus herramientas, corre igual.

## 7. Disquetera USB de 3,5"

La máquina no tiene controladora de disquetes, pero el companion sabe hablar con una **disquetera USB de 3,5"** y presentársela al MSX como si fuera un `.dsk` más. Está **pendiente de probar con una disquetera real**: se ha validado con un disquete falso cargado en la DDR3 por JTAG (referencia técnica), no con hardware.

**Qué disqueteras.** Las externas USB de 3,5", las que se vendían para portátiles sin disquetera (Teac, NEC, Mitsumi, Y-E Data, Sony y las genéricas). Todas son *USB Mass Storage*, en una de dos variantes, y el companion lleva las dos: las clásicas hablan **UFI** (subclase 04, transporte CBI o CB) y las más modernas y baratas se presentan como disco SCSI con **BOT** (subclase 06). Un pendrive es también BOT, pero el companion solo acepta como disquete un medio de 2880 sectores o menos: a un pendrive no le escribe nunca.

**Qué discos.** Los de doble densidad de **720 KB** (80 pistas, dos caras, 9 sectores de 512 bytes por pista), que son los del MSX, y los de alta densidad de **1,44 MB**. Las disqueteras USB los leen y escriben los dos. El tamaño lo toma el menú del sector de arranque del propio disco; si no lo trae o no es creíble, supone 720 KB.

**Cómo se usa.** Conectar la disquetera al hub USB (o directamente al puerto USB del companion), meter el disco y, en el navegador del menú, pulsar **U**. El menú lee el sector de arranque; si no hay disquetera, no hay disco o el disco no se lee, dice *"Disquetera USB: sin disco"* y con una tecla vuelve al navegador. Si lo lee, monta el disquete como **unidad A:** y arranca, exactamente como con un `.dsk` (sección 4): Nextor ve un disco en modo MSX-DOS 1 y ejecuta su sector de arranque; desde DOS se lee y se escribe en el disquete real. Dura hasta el siguiente arranque, como los `.dsk`.

**Límites.**

- Solo formatos estándar de 512 bytes por sector. Ni protecciones anticopia, ni pistas raras, ni discos de 8 pulgadas o de 5,25": lo que la disquetera USB no sepa leer, el MSX tampoco. Un disco **protegido contra escritura** se lee bien y las escrituras fallan con *"Not ready"* (el driver no tiene forma de decir "protegido").
- **Sin cambio de disco en caliente** dentro de una sesión de DOS: Nextor no ve la palanca de cambio y seguiría usando la FAT del disco anterior. Para cambiar de disquete, volver al menú (botón de reset del MSX (K2)) y pulsar U otra vez. Los juegos de varios discos, por tanto, no.
- **Velocidad**: la de un disquete de verdad, unos 30-60 KB/s, más el arranque del motor (medio segundo o uno). El core da dos segundos a cada orden: si la primera lectura tras un rato parado no llega a tiempo, el menú reintenta solo y desde DOS aparece el *Abort, Retry, Ignore* de siempre; con *Retry* sigue.
- Un solo disquete y una sola disquetera: la ventana del disquete es fija (2880 sectores) y no hay unidad B:.
- Hace falta la tarjeta de TF2 de todos modos: el descriptor de emulación que el menú le deja a Nextor se escribe en la tarjeta (sección 4), y Nextor arranca desde ella. Sin tarjeta no hay tecla U que valga.

El panel de telemetría de desarrollo (`tools/tel.tcl`, capítulo técnico) enseña si el companion ve la disquetera, si el disco está protegido, con qué variante USB habla, cuántos sectores ha servido y los errores.

## 8. Lo que no hay

- No hay MSX-DOS 2 en ROM aparte de Nextor. No hace falta: Nextor es compatible con él.
- No hay controladora de disquetes clásica (conector de 34 pines ni WD2793): la única disquetera posible es la USB de la sección 7, que está pendiente de probar con hardware real.
- No hay cambio de disco en caliente con los disquetes de verdad. Los juegos de varios discos en imagen sí van, unidos en un solo `.dsk` (apartado siguiente).
- No hay cambio de tarjeta en caliente: sacar, meter y el botón de reset del MSX (K2).
- No hay ranura de cartucho, así que Nextor es la única interfaz de disco de la máquina.

## Juegos de varios discos en un solo `.dsk`

El menú monta como varios discos un `.dsk` que sea la **concatenación de discos de 720 KB**: si el fichero mide N × 720 KB (de 2 a 32 discos), Nextor ve N discos y arranca con el primero. Un `.dsk` de otro tamaño se monta como un solo disco. No hay cabecera ni nada que marcar: cuenta solo el tamaño.

**Unir los discos en el PC**, en el orden del juego. En Windows, desde `cmd`:

```
copy /b disco1.dsk + disco2.dsk + disco3.dsk juego.dsk
```

En Linux o macOS: `cat disco1.dsk disco2.dsk disco3.dsk > juego.dsk`.

**Copiarlo a la tarjeta.** El fichero tiene que quedar en sectores seguidos; si no, el menú dice «DSK fragmentado». Cuanto más grande, más fácil es que pase. Para evitarlo:

- Cópialo a una tarjeta o partición con espacio libre seguido, por ejemplo recién formateada, y antes de copiar otros ficheros.
- Compruébalo desde MSX-DOS: `CONCLUS JUEGO.DSK` dice si está en clusters consecutivos.
- Si sale fragmentado, borrarlo y volverlo a copiar suele dejarlo en el mismo sitio. Copia antes otro fichero grande, luego el `.dsk`, y borra el otro.

**Cambiar de disco.** Cuando el juego pida otro disco, **mantén pulsado el número del disco y pulsa la tecla que pida el juego**, por ejemplo 2 + RETURN. Nextor mira el teclado justo antes de cada lectura: hay que seguir pulsando hasta que el juego lea. Los discos 1 a 9 van con los números, y del 10 en adelante con las letras A a W.

Si la tecla molesta, por ejemplo porque el juego la toma como otra orden, mantén **GRAPH** mientras lee: se enciende el LED de CAPS y el ordenador espera. Suelta GRAPH y pulsa el número del disco; GRAPH otra vez cancela.

Cada disco se comporta como el suyo: lo que el juego grabe en un disco se queda en sus 720 KB. Los juegos que hablan directamente con la disquetera real no funcionan, igual que con un solo disco.
