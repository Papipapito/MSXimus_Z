# 02. Mapa de puertos de E/S

Todos los puertos a los que responde el core, sacados del decodificador de E/S de `fpga/zynq/top_zynq.v` y de los módulos que cuelgan de él. Los puertos que no aparecen devuelven FFh en lectura y se ignoran en escritura: no hay bus externo. Todos los accesos de E/S se deciden con `IORQ` y sin `M1`.

## 1. Resumen

| Puertos | Dispositivo | Estándar MSX |
|---|---|---|
| 06-07 | UART del ESP32 (WiFi UNAPI) | no |
| 10-12 | Segundo PSG | no |
| 29 | Tercer dígito de la versión del core (lectura) | no |
| 2A-2B | PlaySoniq: índice y dato del registro de bases. **Solo perfil Música** (apartado 5) | PlaySoniq |
| 2D-2F | Diagnóstico USB, diagnóstico del ratón, versión del core | no |
| 3A-3B | SN76489 de PlaySoniq (la base es programable). **Solo perfil Música** | PlaySoniq |
| 34-37 | Diagnóstico del OPL4 (motor de ondas y DDR) | no |
| 40-4F | E/S conmutada: configuración del core, SD por puertos, OCM, turbo Panasonic | OCM |
| 48-49 | SN76489 de Franky (escritura) y sus contadores de línea (lectura), cuando la E/S conmutada no tiene elegido otro dispositivo. **Solo perfil Música** | Franky |
| 60-6F | V9990 (puertos P#0 a P#7 en 60h-67h) | sí (GFX9000) |
| 7C-7D | OPLL (MSX-MUSIC) | sí |
| 7E-7F | OPL4, parte de ondas (MoonSound) | sí |
| 88-8B | V9968 como cartucho externo (alias del interno) | HRA! |
| 8C | Puerto 4 del V9968 (alias del 9Ch) | HRA! |
| 92-93 | Canal Z80 → companion: 92h órdenes WaveGame, 93h mensajes del menú | no |
| 98-9B | V9968 (el VDP de la máquina) | sí |
| 9C | Puerto 4 del V9968: flags de interrupción y bloqueo de R#20/R#21 | HRA! |
| 9D, 9F | geo3d: coprocesador 3D (índice y estado, datos) | Alex Moncks |
| A0-A2 | PSG (en el perfil TR, A0-A3; A4-A5 quedan libres para el PCM del turbo R) | sí |
| A8-AB | PPI: slots, teclado, casete, click | sí |
| B4-B5 | Reloj de tiempo real | sí |
| C0-C1 | Y8950 (MSX-Audio) | sí |
| C4-C7 | OPL4, parte FM (MoonSound) | sí |
| D8-DB | Fuente kanji JIS1 y JIS2 | sí |
| E6-E7 | Temporizador del sistema del S1990 | sí |
| F2 | Registro libre de 8 bits | no |
| FC-FF | Registros del mapper de RAM | sí |

Los registros internos de algunos chips (por ejemplo el F8h del OPL4 o los R#n del V9990) se explican en la sección del puerto por el que se llega a ellos.

## 2. La E/S conmutada: 40h a 4Fh

Es el mecanismo del OCM. Se escribe en el puerto **40h** el identificador de un dispositivo y a partir de ahí los puertos 41h a 4Fh son de ese dispositivo. Leer 40h devuelve el identificador invertido, que es como el software comprueba que el dispositivo existe. El MSXimus responde a tres identificadores:

| OUT 40h | Lee 40h | Dispositivo |
|---|---|---|
| 48h | B7h | La configuración del core, la del menú de Ajustes. Es el dispositivo "goauld" heredado del MSXnano |
| 08h | F7h | Turbo del T9769 de Panasonic, para el software que lo maneja así |
| D4h | 2Bh | E/S conmutada del OCM: órdenes inteligentes en 41h y DIP virtuales en 42h |

Sin dispositivo seleccionado, o con otro identificador, 41h-4Fh caen en el módulo OCM. En el perfil Música, sin dispositivo elegido, 48h y 49h son además el SN76489 de Franky (apartado 5).

### Dispositivo 48h: la configuración del core

| Puerto | Acceso | Contenido |
|---|---|---|
| 41h | R/W | Config 1. bit 0 mapper activo, bit 1 megaram activa, bit 2 segundo SCC en el slot 1, bit 3 scanlines, bits 5-4 slot del mapper (11 = expandido 3-0), bits 7-6 slot de la megaram (11 = expandido 3-3 al arrancar; el dispositivo OCM la pasa a 10 = slot 2 al lanzar una ROM) |
| 42h | R/W | Config 2. bit 0 SD activa, bits 2-1 slot de la SD (3-2), bit 3 menú al arrancar, bit 4 Game Master 2 en el slot 1, bit 5 estéreo. En escritura, el bit 6 ordena guardar la configuración (el PL la saca por el buzón y el companion la graba en la QSPI) y el bit 7 ordena un reset; solo se almacenan los bits 5-0 |
| 43h | W | Configuración de la SRAM de la megaram, volátil. En ASCII8 el bit de habilitación; en ASCII16 distinto de cero activa el modo "valor 10h"; 0 la apaga |
| 44h | R/W | **Mezclador de audio**. Escritura: `{solo_sel[7], canal[6:4], nivel[3:0]}`. Canal 0 = ganancia maestra de 0 a 7 (x1, x1,5, x2, x3, x4, x5, x6, x8; el `OUT 44h,0..7` de siempre sigue valiendo), canales 1 a 7 = PSG, SCC, OPLL, MSX-Audio, OPL4 FM, OPL4 ondas y WaveGame con nivel 0 a 8 (k/8; 8 = sin atenuar). Bit 7 a 1 solo selecciona el canal para leerlo. Lectura: `{0, canal[6:4], nivel[3:0]}`. Sonda: `OUT 44h,F0h` y leer; un core con mezclador devuelve 7 en los bits 6-4. Se guarda con la orden de 42h (bloque de la QSPI, lo escribe el companion) |
| 45h | R/W | bit 0 = arrancar en turbo. Se guarda con la orden de 42h en el bloque de configuración de la QSPI. Lectura: bit 7 = perfil Dual, bit 6 = perfil TR (capítulos [14](14-perfil-dual.md) y [15](15-perfil-tr.md)) |
| 46h | R/W | Extensión del mapper de la megaram, volátil pero sobrevive al reset del MSX: bit 0 NEO (convierte ASCII8 en NEO-8 y ASCII16 en NEO-16), bit 4 mitad alta de los 4 MB para el cargador, bit 6 Game Master 2 armado. En lectura, el bit 7 a 1 dice que el core trae el Game Master 2 |
| 47h-4Fh | | El controlador de la SD por puertos, en el apartado siguiente |

Los registros 41h y 42h se escriben en una copia temporal y solo pasan a ser efectivos con la orden de guardar de 42h, que también reinicia la máquina. El 46h se pone a cero en cada reset a propósito: si el Game Master 2 quedara armado, el escaneo de slots de la BIOS se toparía con su firma en el slot 1.

### Dispositivo 48h, puertos 47h a 4Fh: la SD por puertos

Es el interfaz que usan el menú y el driver de Nextor. La ventana de memoria clásica sigue existiendo (capítulo 03) y ambos caminos gobiernan el mismo controlador.

| Puerto | Acceso | Contenido |
|---|---|---|
| 47h | W | Orden: bit 0 leer, bit 1 escribir, bit 2 DMA (con el bit 0), bit 3 contar patrones de mapper durante la DMA, bit 4 poner a cero los contadores, bit 7 inicializar la tarjeta. Además rebobina el puntero del búfer |
| 47h | R | Estado: bit 7 ocupado, bit 3 bloque listo, bit 2 error de CRC en lectura, bit 1 timeout, bit 0 error de CRC en escritura. Los bits 6-5 fijos a 0 y el bit 4 fijo a 1 sirven de sonda: un core sin puertos devuelve FFh |
| 48h-4Bh | W | Los cuatro bytes del número de sector, del bajo al alto |
| 48h | R | Tipo de tarjeta: 0 desconocida, 1 SD v1, 2 SD v2, 3 SDHC |
| 4Ch | R/W | Un byte del búfer de sector; el puntero avanza solo, pensado para INIR y OTIR |
| 4Dh | R/W | Número de bloques de la siguiente orden: 0 o 1 un solo sector, N mayor que 1 lectura o escritura multibloque |
| 4Eh | W | Índice del byte de información que devolverá la lectura de 4Eh |
| 4Eh | R | El byte de información elegido, según la tabla de abajo |
| 4Fh | W | 80h arma el registro de destino de la DMA y los tres OUT siguientes son la dirección; cualquier otro valor rebobina el puntero del búfer |
| 4Fh | R | Puntero del búfer, byte bajo, para depurar |

Índices de 4Eh:

| Índice | Devuelve |
|---|---|
| 2 | El mismo estado que 47h |
| 7, 8, 9 | Tamaño de la tarjeta (C_SIZE), tres bytes |
| 10 | C_SIZE_MULT |
| 11 | READ_BL_LEN |
| 12 | Tipo de tarjeta |
| 25, 26, 27 | Cronómetro de milisegundos, tres bytes. Al pedir el 25 se congela la foto de los 24 bits, y 26 y 27 devuelven esa misma foto |
| 28 | 54h ('T'): este core tiene cronómetro |
| 29 | 44h ('D'): este core tiene DMA de lectura |
| 31 | 4Dh ('M'): la DMA tiene modo lógico y contadores de mapper |
| 32-33, 34-35, 36-37, 38-39 | Los cuatro contadores de patrones de la DMA, 16 bits cada uno: Konami-SCC, Konami, ASCII8, ASCII16 |

El cronómetro va con el reloj de 27 MHz y no depende de las interrupciones del MSX; existe para medir la carga sin depender del contador de la BIOS, que se para con las interrupciones inhibidas. Todo el detalle de la DMA está en el capítulo 06.

### Dispositivo 08h: el turbo de Panasonic

| Puerto | Acceso | Contenido |
|---|---|---|
| 41h | W | Solo el bit 0, activo a nivel bajo: 0 pone 5,37 MHz, 1 pone 3,58 MHz |
| 41h | R | bit 0 estado del turbo (0 = activo), bit 2 a 0 (turbo disponible), bit 7 a 1; es decir FAh en turbo y FBh en normal |

Es el protocolo que openMSX describe para el MSXMatsushita, y el que usan los juegos y utilidades que conocen el turbo de la serie FS-A1.

### Dispositivo D4h: la E/S conmutada del OCM

Llega del módulo `swioports` del OCM-PLD. El menú la usa para una sola cosa: la orden inteligente 0Fh en 41h, que pone el slot 2 en modo SCC-I interno, que es como el cargador escribe la megaram. Los DIP virtuales del puerto 42h fijan el modo de ese slot 2.

## 3. El resto de puertos, uno a uno

### 06h-07h: UART del ESP32

Es el puente `wifi_lite` de ducasp, agnóstico al módulo. Un byte por acceso, sin búfer de transmisión, FIFO de recepción de 2080 bytes.

| Puerto | Acceso | Contenido |
|---|---|---|
| 06h | W | Orden de velocidad. La versión "lite" solo reconoce la 20, que vacía el FIFO; la velocidad es fija |
| 06h | R | Saca un byte del FIFO de recepción. Si está vacío, el hardware retiene la lectura hasta 25 ms esperando un byte; si no llega, devuelve FFh y marca underrun |
| 07h | W | Byte a transmitir |
| 07h | R | Estado: bit 0 hay datos, bit 1 transmisión en curso, bit 2 FIFO lleno, bit 3 soporta recepción rápida, bit 4 underrun |

El módulo pone al Z80 en espera durante sus ciclos de E/S.

### 10h-12h: segundo PSG

Un segundo YM2149 completo, con la misma decodificación que el principal desplazada: 10h dirección, 11h escritura, 12h lectura. Para el software que espera un PSG ahí.

### 29h y 2Dh-2Fh: diagnóstico y versión

| Puerto | Devuelve |
|---|---|
| 29h | Tercer dígito de la versión (arreglos), `FPGA_PATCH` del bitstream: 01h en la Z1.3.1 (el 2Fh devuelve A3h) |
| 2Dh | Heredado del decodificador USB del PL: bits 7-6 error de conexión, 5-4 y 3-2 tipo de cada puerto USB, 1-0 cuenta de informes. Sin uso en el MSXimus Z (el USB host lo lleva el PS y entra por el buzón) |
| 2Eh | Estado interno del ratón MSX: bit 7 ratón USB presente, bit 6 puerto 2 elegido, bit 5 nivel del pin 8 del puerto 2, bits 4-2 fase de la máquina del ratón, bits 1-0 cuenta de informes |
| 2Fh | Versión del core: A3h (Z1.3). Nibble alto A o mayor = línea Zynq («Z» + alto − 9), nibble bajo = revisión. La serie 3.x es la del MSXimus original |

Ajustes muestra la versión como «Z» + 2Fh + el tercer dígito de 29h en hexadecimal (0Ch se pinta C). 29h solo se imprime si vale de 1 a 15; 0 o FFh (un core sin ese puerto) no añaden dígito. Los puertos 29h y 2Fh se deciden en un solo término del multiplexor de lectura: 29h devuelve el parche y 2Fh la versión. Un core anterior a que existiera 2Fh devuelve FFh, y el menú dice «desconocida».

### 34h-37h: diagnóstico del OPL4

Cuatro puertos heredados del bring-up del OPL4 del Tang: 34h = diagnóstico del acceso a la DDR (`{error de respuesta, 000, operaciones[3:0]}` de `wave_axi.v`), 35h = diagnóstico del motor PCM, 36h = estado y 37h = byte de la memoria de ondas. La ROM de ondas ya está en la DDR desde el arranque (la carga el FSBL o `boot.tcl`), así que no hay carga en curso. Con el V9990 compilado, el puerto GP1 del PS es de la VRAM del V9990 y el acceso de depuración a la memoria de ondas por 34h-37h no tiene motor: 37h lee FFh y el 36h no refleja accesos reales. Telemetría más útil en MBOX+0x60 (`tools/tel.tcl`).

### 7Ch-7Dh: OPLL

El YM2413 de MSX-MUSIC, solo escritura: 7Ch registro, 7Dh dato.

### 7Eh-7Fh: OPL4, ondas

La parte PCM del MoonSound: 7Eh registro y 7Fh dato del motor de 24 slots (el de srg320). La ROM de ondas es la YRW801 de 2 MB, en la DDR del PS (0x0F000000) por el puerto GP0 (`wave_axi.v`); otros 2 MB a continuación son RAM de muestras. En lectura, 7Eh devuelve el estado `{LD, BUSY}` y 7Fh el dato del registro; la lectura de 7Fh retiene al Z80 con `/WAIT` hasta que el motor contesta.

Dos registros del motor no son de voz:

| Registro | Contenido |
|---|---|
| F8h | Mezcla del FM: atenuación por lado, 3 bits por canal. Vale 1Bh tras el reset (FM a −9 dB, como el chip) |
| F9h | Mezcla del PCM, igual; vale 00h tras el reset |

La parte FM del chip (C4h-C7h) comparte con el wave el reloj de bus (54 MHz) pero no el motor: es el OPL3 (`fpga/opl3`).

### 88h-8Bh y 98h-9Bh: el V9968

Los cuatro puertos clásicos del VDP: 98h datos de VRAM, 99h registros y estado, 9Ah paleta, 9Bh registros indirectos. El rango 88h-8Bh es un alias del mismo chip: el software escrito para el cartucho V9968 de HRA! lo busca ahí como VDP externo, y en el MSXimus el V9968 ya es el interno.

El puerto 4 (9Ch y su espejo 8Ch) y los dos de geo3d (9Dh, 9Fh) se describen más abajo. 9Eh y los espejos 8Dh, 8Eh y 8Fh no se decodifican. El bus del Z80 llega al V9968 por un adaptador (`v9968_cpu_glue.v`) que retiene al Z80 con `/WAIT` hasta que el chip responde. El detalle del chip está en el [capítulo 05](05-v9968.md).

### 60h-6Fh: V9990

El V9990 ocupa 60h-6Fh (`bus_addr[7:4] == 6`); el core recibe `bus_addr[3:0]` como número de puerto. Implementa los ocho del chip:

| Puerto | Acceso | Función |
|---|---|---|
| 60h (P#0) | R/W | Datos de VRAM, con dirección automática. Retiene al Z80 con `/WAIT` mientras el core completa el acceso |
| 61h (P#1) | R/W | Datos de paleta (también con `/WAIT`) |
| 62h (P#2) | R/W | Datos del comando de CPU (LMMC, CMMC…); un P#2 escrito sin TR con un comando en marcha se retiene con `/WAIT` |
| 63h (P#3) | R/W | Datos de registro, con autoincremento según R#n |
| 64h (P#4) | W | Número de registro (bit 7 sin incremento en escritura, bit 6 sin incremento en lectura) |
| 65h (P#5) | R | Estado |
| 66h (P#6) | R/W | Banderas de interrupción: bit 2 comando, bit 1 línea, bit 0 cuadro; se borran escribiendo 1 |
| 67h (P#7) | W | Control del sistema: bit 1 reset del chip, bit 0 selección de reloj |
| 68h-6Fh | | Sin función |

La interrupción del chip va al `INT_n` del Z80 con la del V9968, el Y8950 y el OPL4. Un reset del MSX resetea también el V9990. Los registros R#0 a R#54, los modos, el blitter, la VRAM y el puente a HDMI (la tecla Pausa conmuta la imagen) están en el [capítulo 13](13-v9990-geo3d.md).

### 9Dh y 9Fh: geo3d

El coprocesador 3D de Alex Moncks (v2.0) cuelga del mismo bus que el V9968: **9Dh** es el índice (escritura) y el estado (lectura), **9Fh** los datos, los desplazamientos 5 y 7 del bloque del VDP. El motor escribe él mismo comandos LINE y LRMM en el motor de comandos del V9968. El registro 49h devuelve 20h (geo3d v2.0). Los registros del motor están en la cabecera de `fpga/geo3d/geo3d_engine.v` y la integración, en el [capítulo 13](13-v9990-geo3d.md).

### 92h-93h: canal Z80 → companion

Dos puertos de solo escritura que el PL vuelca en un anillo de 32 entradas del buzón (MBOX+0x78..+0xB7, una entrada por OUT: `{puerto, dato}`) que el companion lee cada ronda. **92h** es el protocolo WaveGame de Jeroen Taverne (el mismo del MSX Pico / PicoVerse / openMSX): `01xxxxxx` toca la pista x una vez, `10xxxxxx` en bucle, `0000xxxx` fundido de x segundos, C0h pausa/continúa, D0h difiere la siguiente, E0h continúa con fundido, F0h la pista `pause.wav`. **93h** son mensajes del menú al companion: al lanzar una ROM manda `'W','G'` + LBA de la partición (4) + clúster de la carpeta (4) + clúster del fichero (4), y `'W','T'` pide la nota de prueba del mezclador. Con la misma trama de 14 bytes: `'W','Q'` (RETURN sobre una ROM, antes de cargarla) y `'W','G'` hacen que el companion cargue el perfil que pida la etiqueta `[P:ID]` del nombre de la ROM, y `'W','I'` (RETURN sobre un `.MXP`) que instale ese fichero como perfil en la TF1 ([capítulo 12](12-companion.md), apartado 5.9). Cualquier lectura devuelve FFh.

### 9Ch y 8Ch: puerto 4 del V9968

Generación C del interfaz de registros. Lectura: `{bloqueo[7], 0000, fin de comando[2], línea[1], cuadro[0]}`, los tres flags de interrupción del chip. Escritura: el bit 7 es el bloqueo de R#20 y R#21 (a 1 tras el reset: se ignoran, de modo que una BIOS que los ponga a cero no encienda el modo nativo sin querer, como pasa con el marcador de Xevious); los bits 0, 1 y 2 a 1 borran los flags de cuadro, línea y fin de comando. El software que quiera el V9968 hace `OUT (9Ch),0` antes de tocar R#20 y R#21. Capítulo 05.

### A0h-A2h: PSG

El YM2149 principal. En A2h con el registro 14 seleccionado se lee el joystick, que viene del mando o del ratón USB; el bit 6 del registro 15 elige el puerto. Los botones 3 y 4 del mando hacen autodisparo sobre los botones 1 y 2. El registro 15 se relee (lo último escrito), porque la BIOS lo lee, modifica y escribe en cada interrupción. Con una cinta virtual en marcha, el bit 7 del registro 14 lee el nivel de la cinta. Los demás registros siguen devolviendo FFh al leerlos: el `O_DA` del YM2149 está sin conectar, aunque el modelo los sirve.

### A8h-ABh: PPI

| Puerto | Contenido |
|---|---|
| A8h | Registro de slots primarios |
| A9h | Lectura de la fila del teclado seleccionada |
| AAh | bits 3-0 fila del teclado, bit 4 motor del casete, bit 5 salida de casete, bit 6 LED de kana, bit 7 click del teclado. Se puede releer |
| ABh | Registro de control: el modo de poner y quitar bits sueltos del puerto C, que usa la BIOS para CAPS, el click y el motor |

### B4h-B5h: reloj de tiempo real

El RP5C01 de un MSX2: B4h selecciona el registro, B5h lo lee o escribe. Su reset está fijo a cero, así que hora y RAM sobreviven a los resets del MSX; no hay pila, al apagar se pierden. Con el ESP32 conectado, el driver de red puede ponerlo en hora por internet.

### C0h-C1h: Y8950

MSX-Audio: C0h registro, C1h dato. En lectura, C0h devuelve el estado con los flags de los temporizadores, el fin de muestra y el búfer del ADPCM. La IRQ va al Z80 en AND cableado, y arranca enmascarada.

### C4h-C7h: OPL4, FM

La parte OPL3 del MoonSound: C4h/C5h primer banco de registros, C6h/C7h segundo banco. En lectura, el estado.

### D8h-DBh: fuente kanji

El interfaz estándar sigue en el core (D8h y D9h fijan la dirección en JIS1, DAh y DBh en JIS2), y la fuente de 256 KB es la parte inicial del pack de BIOS, en la DDR desde el arranque (0x10F00000, capítulo 03). Su contenido depende de que el pack se haya construido con las ROMs de kanji (capítulo 04).

### E6h-E7h: temporizador del S1990

Del controlador del turbo R solo queda el temporizador del sistema, que usan las demos de geo3d de kanon-ai para medir los cuadros. La máquina no se identifica como turbo R: E4h y E5h no contestan (FFh), no hay firma ni CHGCPU, y no hay R800. El turbo de 5,37 MHz (F11, puerto 41h al estilo Panasonic) no cambia.

| Puerto | Acceso | Contenido |
|---|---|---|
| E6h | R/W | Lectura: byte bajo del temporizador del sistema (un tic cada 3,911 µs); escritura: lo pone a cero |
| E7h | R | Byte alto del temporizador |

**Perfil TR (capítulo [15](15-perfil-tr.md), fase 2):** la S1990 es la del turbo R completa (`msx_s1990.v` con `ID = 2`), con el R800 de verdad detrás.

| Puerto | Acceso | Contenido |
|---|---|---|
| E4h | R/W | Índice de registro (4 bits) |
| E5h | R/W | Valor del registro. **R#6**: bit 5 = CPU (0 = R800, 1 = Z80; la escritura la pide y se cumple en el siguiente límite de instrucción; la lectura dice la CPU que manda de verdad), bit 6 = modo ROM (1) o DRAM (0). R#5 = botón de pausa (bit 6, siempre 0), R#13/14/15 = firma 03h/2Fh/8Bh, el resto FFh |
| F4h | R/W | Estado de reset: un cerrojo de 8 bits que **no se borra con el reset** (la BIOS lo usa para distinguir el arranque en frío del caliente) |
| A7h | R/W | Pausa / LED del R800: la lectura da en el bit 0 el botón de pausa (0); lo escrito (LED) no se guarda |
| FCh-FFh | R | Los registros del mapper se pueden **releer** (cinco bits, el resto a 1) |

Tras el reset manda el Z80 y el modo es ROM. El PSG decodifica solo A0h-A3h (A4h/A5h, el PCM del turbo R, siguen sin contestar: FFh).
### F2h: registro libre

Un byte de lectura y escritura sin función en el hardware. Se lee tal como se escribió.

### FCh-FFh: mapper de RAM

Los cuatro registros de segmento del mapper, uno por página de 16 KB. Son de **solo escritura** en el core: leerlos devuelve FFh. El mapper es de 2 MB, así que se usan siete bits y el octavo se ignora, que es como se comporta un mapper real de 8 bits con menos memoria. Por ser de solo escritura, la DMA de la SD tiene un modo lógico que traduce direcciones con estos registros dentro del core (capítulo 06).

## 4. Puertos que existen en un MSX y aquí no

- **Impresora** (90h-91h): no hay.
- **Joystick por PSG**: sí, pero solo desde USB; no hay conectores DE-9.
- **Cinta**: no hay conector; la entrada del casete (bit 7 del registro 14 del PSG) la alimenta la cinta virtual que genera el companion a partir de ficheros .TSX o .CAS ([capítulo 10](10-cinta.md)). El motor y la salida del PPI existen.
- **Mapa de E/S fuera de lista**: 8Dh-8Fh y 9Eh no responden.

## 5. Solo en el perfil Música

El perfil Música (`build.tcl … bit musica`, capítulo [07](07-construccion.md)) es el mismo sistema sin geo3d y con el YM2151 de la Yamaha SFG-01/05 (ranura 0-1, capítulo [03](03-mapas-memoria.md)) y un SN76489. En el perfil estándar estos puertos no existen: FFh en lectura e ignorados en escritura. El código es `fpga/zynq/musica_sound.v`.

### 48h-49h: SN76489 de Franky

| Puerto | Acceso | Contenido |
|---|---|---|
| 48h, 49h | W | Dato del SN76489. Solo con el dispositivo 48h de la E/S conmutada **sin elegir** (con él elegido, 48h-4Bh son el número de sector de la SD por puertos) |
| 48h | R | Contador vertical del VDP de Sega de Franky: 8 bits que suben de uno en uno cada línea (15,734 kHz) y dan la vuelta. VGMPlay lo detecta así: exige que cambie en 1 al menos cuatro veces. Solo si no hay ningún dispositivo de la E/S conmutada elegido (VGMPlay hace `OUT 40h,0` antes) |
| 49h | R | Contador horizontal, posición en la línea de 0 a 214 |

Del Franky real no está el VDP de Sega (88h-89h siguen siendo el alias del V9968): la detección de VGMPlay escribe los registros 0 y 1 por 89h y apagará la pantalla del V9968 hasta que el reproductor la restaure.

### 2Ah-2Bh y 3Ah-3Bh: SN76489 de PlaySoniq

| Puerto | Acceso | Contenido |
|---|---|---|
| 2Ah | W | Índice del registro |
| 2Bh | R/W | Dato del registro elegido. Solo existen 1Dh (base del VDP, se guarda y no hace nada) y 1Eh (base del SN76489); los demás se leen FFh. Reset: los dos a 00h |
| base y base+1 | W | El SN76489, en `base & FEh` y `base \| 1`, cuando `base[7:1]` no es 0. VGMPlay pone 3Bh, que son 3Ah-3Bh. El bit 0 de la base («inhibir lectura») se guarda y no hace nada: el SN no se lee |

El Musical Memory Mapper (SN76489 en 3Fh) no está: su puerto de sonido solo se habilita con un bit del registro de control que únicamente se escribe por memoria (80FCh…), así que un `OUT` no puede activarlo y VGMPlay tampoco lo detecta sin el mapper de 1 MB.

### Mezclador: canales 8 y 9

El YM2151 (estéreo propio) es el canal 8 del mezclador y el SN76489 (mono, al centro) el 9. Entran al grupo clásico, o sea que pasan por la ganancia maestra, igual que el PSG, el OPLL y el Y8950. **Su nivel está fijo a 8/8**: el puerto 44h solo direcciona hasta el canal 7 (campo de 3 bits), `mix_lvl` tiene 28 bits y el buzón solo tiene 28 bits en `MBOX+0x24` y 3 libres. Para dar niveles a los dos canales hay que ampliar a la vez:

1. el protocolo del 44h: el campo del canal pasa a 4 bits (por ejemplo, el nivel solo vale 0 a 8 y el bit 7 «solo seleccionar» se codifica como un nivel de 9 a 15; el canal ocupa los bits 7-4);
2. `mix_lvl` (36 bits) y `mix_sel`/`mix_rd` en `top_zynq.v`, sustituyendo las constantes `MIX_LVL_SFG` y `MIX_LVL_SN`;
3. el buzón: una palabra nueva para la siembra (`MBOX+0x24` no tiene sitio) y para la telemetría (`MBOX+0xC0`);
4. `qspi_cfg.c` (bytes 9-13 del bloque MSXC, sobran bytes en el sector), el menú (`bios/src/e7_rutinas.asm`, `ld b,7` es el último canal; la página 2 está casi llena) y el panel F12 del companion.

Niveles de partida: una portadora del YM2151 con TL = 0 da ±8168 y entra a la mitad (±4084, la de una portadora del Y8950); un tono del SN76489 a volumen 0 da ±255 y entra por 16 (±4080, un canal del PSG a tope en mono; en estéreo la mitad a cada lado). La suma del grupo clásico se hace en 20 bits y se satura a 19.
