# 11. Cinta virtual: cargar TSX y CAS

El MSXimus Z tiene casete: un fichero `.tsx` o `.cas` en la SD de TF2 se lanza desde el menú como una ROM y el MSX lo carga como si fuera una cinta de verdad, con su tiempo de carga y su sonido.

## 1. Qué ficheros

- **TSX**: el formato de preservación de cintas de MSX (una extensión del TZX del Spectrum). Hay más de 2500 en el repositorio [tsx.eslamejor.com](https://tsx.eslamejor.com/); se descargan del navegador del PC y se copian a la tarjeta. Sirven todos los bloques que usan las cintas de MSX, incluidos los cargadores propios de algunos juegos (bloques al estilo Spectrum): el MSXimus Z no decodifica bytes, reproduce los pulsos.
- **CAS**: el formato clásico de las colecciones de MSX (los ficheros que empiezan por `1F A6 DE BA CC 13 7D 74`). Se reproducen a 1200 baudios, el estándar de la BIOS.

El fichero entero se carga en memoria antes de reproducirlo, y el límite es **1 MB** por cinta.

Los nombres largos valen; el menú los muestra con su tamaño y aparecen en la pestaña ROM y en ALL.

## 2. Cómo se carga

1. En el menú, RETURN sobre el fichero.
2. El MSX arranca **en BASIC limpio**: mientras hay una cinta cargada el slot de Nextor desaparece (lo pide el companion al core), así que Nextor no se instala y el juego tiene toda la RAM, como en un MSX sin disco: "MSX BASIC version 3.0 / 28815 Bytes free / Ok". El slot de Nextor solo vuelve cuando se reinicia la placa entera (el reset de la placa, PS_SRST) o se apaga y enciende: el botón de reset del MSX (K2) no lo devuelve, y la cinta sigue "puesta". Mientras tanto tampoco está la unidad de la microSD de TF1, que cuelga de Nextor.
3. Al aparecer el `Ok` del BASIC, la orden de carga se teclea sola según la primera cabecera de la cinta: `RUN"CAS:"` (programa ASCII), `BLOAD"CAS:",R` (binario) o `CLOAD` y después `RUN` (BASIC tokenizado). Si la cinta no empieza por una cabecera reconocible se teclea `RUN"CAS:"`; si el juego pide otra cosa (los TSX de tsx.eslamejor lo dicen en su ficha), tecléala tú.
4. `Found: NOMBRE` y a esperar: la cinta corre solo mientras el MSX tiene el motor en marcha, exactamente como la de verdad, así que las pausas entre bloques y los juegos que cargan por fases van bien. Se oye la carga bajita por los altavoces (el "monitor" de la cinta, canal WaveGame del mezclador).

Mientras el motor del casete está en marcha el turbo se desactiva (las rutinas de casete de la BIOS cuentan ciclos a 3,58 MHz) y vuelve solo en cuanto el motor para.

## 3. Consejos

- Un juego que se queda en `Found:` sin avanzar suele necesitar otra orden de carga: prueba `BLOAD"CAS:",R`.
- Las cintas de varias caras vienen como ficheros separados (`Side A`, `Side B`); el juego pide la siguiente cuando la necesite: vuelve al menú (botón de reset del MSX (K2)), lánzala y teclea lo que pida.
- Para parar una cinta a medias, el botón de reset del MSX (K2); Nextor sigue oculto hasta el reset de la placa.
- Una cinta larga tarda lo que tardaba: a 1200 baudios son unos 9 segundos por KB (A.R.C.O.S., 16 KB, carga en 3 minutos y medio; una cara de 178 KB, media hora).
- Desarrollo: `tools/tape.tcl` enseña el estado del reproductor (posición, FIFO, motor, nivel) y `tools/armlog.tcl` el registro del companion (`tp: TSX 17051 bytes, orden RUN"CAS:"`, `tp: cinta convertida: 63 bloques, 990624 pulsos`, `tp: fin`).

## 4. Cinta web: bajar cintas desde el menú

La tecla **F** del menú (el File-Hunter) busca también cintas:

- **CAS de File-Hunter**: la colección de casetes de file-hunter.com, por el mismo API que las ROM y los DSK.
- **TSX de tsx.eslamejor.com**: la máquina lleva dentro el catálogo completo (2565 cintas, con su tamaño, su CRC y su orden de carga) y busca en él sin tocar la web; solo la descarga va a la web, por https.

Teclea parte del nombre (mínimo 2 letras), RETURN, y la lista mezcla ROM, DSK, CAS y TSX. Las cintas llevan su etiqueta delante del tamaño en la columna de la derecha: `CAS 86K` viene de File-Hunter y `TSX 86K` de tsx.eslamejor (en la SD, `.cas` y `.tsx` llevan la misma etiqueta). RETURN sobre una cinta la baja a la carpeta `FHUNT` de la tarjeta (con barra de progreso y comprobación de CRC, como las ROM) y la lanza como cinta virtual. Si ya estaba bajada, arranca directamente.

La orden de carga no se adivina: los TSX de tsx.eslamejor llevan dentro (bloque `TSX.LOAD`) la misma orden que muestra su ficha —`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD` y `RUN`— y las "manos" teclean esa. Los CAS y los TSX sin esa ficha siguen usando la primera cabecera.

Requisitos: red ([capítulo 07](07-wifi-file-hunter.md)) y la tarjeta de TF2 en FAT16, como para cualquier descarga del File-Hunter ([capítulo 03](03-tarjeta-sd.md)). Con el cable Ethernet del procesador el catálogo y la descarga de los TSX los lleva la propia máquina; con el módulo ESP32 de WiFi, el módulo, con su firmware del repositorio [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`).

## 5. Lo que no hay todavía

- Grabar a cinta (`CSAVE`, `BSAVE"CAS:"`).
