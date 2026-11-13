# 09. Vídeo

Qué sale por el HDMI de la ZYNQ MINI, qué opciones tiene, qué son el V9968 y el V9990, qué es el panel F12 y la pantallita OLED.

## 1. La salida

Una sola señal: **HDMI 1280×720 a 60 Hz**, con el audio embebido (44,1 kHz, estéreo o mono según Ajustes). Sale por el conector HDMI de la placa, que va a pines fijos del XC7Z020: no hay que cablear nada. Cualquier televisor o monitor con HDMI la acepta, y los capturadores también.

La salida es siempre 720p60. Es el modo que permite escalar la imagen del MSX con factores enteros.

La imagen del MSX ocupa la pantalla entera. Cada punto del MSX son 4 píxeles de ancho y cada línea 3 de alto, sin fracciones, así que los píxeles salen todos iguales y sin escalones: el V9968 saca 640 columnas nativas (256 de contenido doblado más 32 puntos de borde a cada lado) y el puente HDMI las multiplica exactamente por 2; las 240 líneas nativas se multiplican exactamente por 3. Se ve el **borde** a los cuatro lados, como en un monitor de tubo: 32 puntos a cada lado del área de 256, que es donde los juegos con scroll esconden y sacan cosas.

**16:9 o 4:3.** En el panel F12 (página de información) la tecla **V** alterna la proporción de la pantalla completa del V9968 y se guarda en la flash:

- **16:9** (de fábrica): la imagen llena los 1280 píxeles de ancho, como se ha descrito.
- **4:3 con Scale3x**: la proporción de una tele de tubo, con barras negras a los lados. Cada punto del MSX ocupa 3 × 3 píxeles y el filtro Scale3x redondea las diagonales y los escalones sin emborronar ni inventar colores. No hay scanlines en este modo.
- Los modos de 512 puntos (SCREEN 6, SCREEN 7 y el texto de 80 columnas) salen **sin filtro**, a 1,5 píxeles por punto.

Solo vale a pantalla completa; en la ventana del escritorio no cambia nada.

**Scanlines**: en Ajustes (tecla S en el menú, [capítulo 04](04-menu.md)), *Enable Scanlines* oscurece al 50 % una de cada tres líneas, el aspecto de un monitor de la época. De fábrica está en Off. Se aplica en el momento de cambiarla, sin reiniciar nada; para que sobreviva al apagado hay que pasar por *Save & Restart*, que la guarda con el resto de ajustes en la QSPI de la placa.

**50 Hz**: el software que pone el VDP en 50 Hz funciona. La salida sigue siendo 720p60:

- En el **V9968**, la imagen se convierte a 60 Hz: el V9968 normaliza los dos modos a 240 líneas nativas y el puente hace siempre el mismo ×3, así que las scanlines también salen de una de cada tres en 50 Hz. Es el modo menos probado y su geometría en el V9968 no está medida: si algún juego europeo se ve raro en 50 Hz, es lo primero que mirar.
- En el **V9990**, el PAL (R#7 bit 3) da 313 líneas a 50 Hz, el ritmo de los juegos que lo piden; el puente repite un cuadro de cada seis para llenar los 60 Hz de la salida.

**La VRAM** del V9968 (256 KB) y la del V9990 (512 KB) no están en la lógica programable sino en la DDR3 del procesador. Al usuario no le cambia nada; solo conviene saber que nacen a cero en cada arranque, de modo que no hay "basura" heredada en pantalla tras un reset.

## 2. Dos chips de vídeo, una HDMI

El MSXimus Z lleva dos VDP, cada uno con su propia imagen, y **una sola salida HDMI** que muestra uno u otro:

| Chip | Puertos | VRAM | Para qué |
|---|---|---|---|
| **V9968** | 98h-9Bh (y 88h-8Bh) | 256 KB | Todo el software de MSX, MSX2+ incluido. Es el que se ve al arrancar |
| **V9990** | 60h-6Fh | 512 KB | El software hecho para el GFX9000 / V9990 (Xybots, Sol Negro, Dream Puzzle, Chase H.Q., SymbOS G9K y similares) |

### Cómo se conmuta

- **Automático, de ida**: cuando un programa enciende la pantalla del V9990 (bit 7 del R#8) en un modo que el puente captura, la HDMI pasa al V9990 y **se queda ahí**. Los apagados de pantalla del juego (cambios de fase, cargas) muestran negro, como con un GFX9000 de verdad. El automático actúa con todos los modos salvo B6, el único que el puente no captura.
- **Tecla Pausa** (la del teclado USB): conmuta a mano entre el V9968 y el V9990. Cada conmutación cuesta al monitor un segundo o dos de reenganche, porque las dos señales 720p no van en fase. Al pulsarla se desarma el automático hasta el siguiente reset, para poder mirar el V9968 mientras un programa V9990 sigue encendiendo su pantalla.
- **Reset del MSX**: vuelve siempre al V9968 y rearma el automático.
- Desde el PC, `tools/vsel.tcl` hace lo mismo que la tecla Pausa. El menú apaga la pantalla del V9990 al arrancar.

La fila *MSX* del panel F12 y la línea *VDP* de la OLED dicen qué chip está en la HDMI.

### El V9990

Es el *tiny9990* de buppu3 (BSD-3), en los puertos 60h-6Fh. Lo que ve el software:

- Modos de patrones P1 y P2 y bitmap B1 a B4, con paleta de 2, 4 y 8 bpp y color directo (BD8, BD16 y YJK/YUV), sobre una VRAM de 512 KB.
- Comandos de bloque, incluidos los que pasan datos por la CPU (CMMC y CMMM) a 2, 4, 8 y 16 bpp.
- **Entrelazado** (IL + EO): cada campo trae las filas pares o impares y el puente las teje en un cuadro de 480 líneas que escala a 720, sin que la imagen salte de campo.
- **PAL a 50 Hz** (R#7 bit 3), como se ha dicho arriba.
- Un P#2 escrito sin esperar a TR con un comando en marcha se retiene con WAIT en lugar de perderse.
- El reinicio de la cuenta de líneas del plano al escribir R#17/R#21 a mitad de pantalla, que usan los juegos que parten la pantalla con la interrupción de línea.

En 212 líneas el V9990 tiene un borde negro arriba y abajo (unas 42 líneas de salida arriba y 43 abajo): es el del chip, y no se recorta.

El modo B6 el puente no lo captura; el resto, sí.

### geo3d

Los puertos **9Dh** (índice y estado) y **9Fh** (datos) son de **geo3d**, el coprocesador 3D de Alex Moncks (MIT) que el MSXimus Z lleva como cartucho virtual junto al V9968. El Z80 sube un modelo de vértices, aristas y caras una vez y después manda unos pocos bytes por cuadro (posición y giro); geo3d transforma, recorta, ordena y sombrea, y escribe él mismo las líneas y los bloques en el motor de comandos del V9968. Es la versión 2.0, con hasta 1.023 vértices, aristas y caras. Un software hecho para la versión 1 saca los mismos comandos.

No hay nada que activar: el software 3D (las demos de kanon-ai, por ejemplo) lo busca en esos puertos y lo encuentra. El detalle técnico está en [la referencia técnica](../tecnica/13-v9990-geo3d.md).

## 3. El panel F12

**F12** en el teclado USB congela el MSX y dibuja encima un panel de texto con lo que el sistema dice de sí mismo. F12 otra vez y el juego sigue donde estaba. Lo pinta el **companion**, el programa que corre en el procesador ARM de la Zynq y que va dentro del BOOT.bin ([capítulo 02](02-instalacion.md)), hablando con el overlay de texto del core por una UART interna.

Mientras el panel está abierto el Z80 está parado (es una pausa, pero una pausa con datos); el panel la página de información se refresca cada segundo (la de actualización, hasta cuatro veces por segundo) y se dibuja en color, en 32 columnas de las que se ven 30. Los textos salen en el idioma de la imagen en marcha, castellano o inglés ([capítulo 12](12-actualizar.md)).

El V9968 y el V9990 salen por una sola HDMI y el panel F12 se dibuja encima de esa salida, también con el V9990 en pantalla. Si alguna vez no se viera, Pausa vuelve al V9968.

### La página de información

| Bloque | Qué dice |
|---|---|
| Cabecera | `MSXimus Z` y la versión instalada (por ejemplo `Z1.3.1`) |
| Sistema | **Temperatura** del chip (die) y la máxima registrada, en verde por debajo de 60 °C, en amarillo hasta 75 y en rojo por encima; **tensiones** Vint, Vaux y Vbram (alimentaciones internas, leídas por el XADC del Zynq); y el tiempo **encendida** |
| Tarjeta SD | La de TF2: tamaño en MB y, si los hay, el número de errores; o `sin tarjeta` |
| USB | Cuántos dispositivos hay y de qué tipo (teclados, ratones, mandos, discos, hubs) |
| MSX | `Z80 3,58 MHz` o `5,37 MHz` con `turbo` (el turbo va en **F11**); `SCREEN` actual y el vídeo en la HDMI (`V9968` o `V9990`); y la comprobación de la tabla de ondas del MoonSound: `YRW801 OK`, `YRW801 no válida` o `comprobando` |
| Red | La IP del cable (J3), o `sin cable o sin IP` |
| Pie | Los botones **U** (actualizar), **V** (16:9 o 4:3) y **F12** (salir), y el aviso de que el MSX está en pausa |

La temperatura es el dato que más se mira: el XC7Z020 ronda los **80 °C sin disipador** (su máximo comercial es 85 °C) y unos **55 °C con uno**. Si no lleva disipador, pónselo.

Porque F12 es del panel, el **turbo va en F11**.

En esta página, **V** alterna la pantalla completa del V9968 entre 16:9 y 4:3 con Scale3x ([sección 1](#1-la-salida)); la fila *V9968 completo* dice cuál está activa (`16:9` o `4:3 Scale3x`).

### La página de actualización

Con **U** sobre la página de información se abre la de la actualización por red (buscar la última versión, instalarla, elegir Nextor e idioma). **ESC** vuelve a la información. Se explica en el [capítulo 12](12-actualizar.md).

Desde el PC, con la placa conectada por JTAG, `tools/osd.tcl on|off` (en `fpga/zynq/tools/`) enciende y apaga el mismo panel sin teclado. Y si al arrancar por JTAG aparece un instante un panel con texto de demostración, es el overlay del core antes de que el companion lo apague: es normal y desaparece solo.

## 4. La pantalla OLED

La ZYNQ MINI trae una **OLED monocroma de 128×64** (SSD1306) en el conector J4. El companion la usa como pantallita de estado permanente, encendida siempre, con o sin panel F12, refrescada una vez por segundo. Un ejemplo de lo que se lee en ella (los números varían):

```
MSXimus Z1.3.1
die 55.2 C
SD 14910MB
USB t1 r0 m1
192.168.1.40
VDP V9968
up 00:12:07
CPU 3.58MHz
```

Es decir: la versión, la temperatura del chip, el tamaño de la tarjeta de TF2 (`--` si no hay), los teclados, ratones y mandos USB detectados (`t`, `r`, `m`), la IP del cable (`IP --` si no hay), el chip de vídeo que está en la HDMI (`VDP V9968` o `VDP V9990`), el tiempo encendido y la velocidad de la CPU. Si la comprobación de la tabla de ondas falla, la línea del VDP se sustituye por `YRW801 NO VALIDA`. No admite color ni gráficos del MSX: son ocho filas de texto de 8×8 y nada más. La conduce el ARM por cuatro pines GPIO, así que cambiar lo que muestra es tocar `oled.c` del companion, sin recompilar la FPGA.

## 5. El V9968

El VDP principal del MSXimus Z no es un V9958: es el **V9968** de Takayuki Hara (HRA!). Es un chip imaginario que amplía el V9958 con lo que Yamaha nunca llegó a sacar:

- **Sprites multicolor**: 15 colores más transparencia por sprite, definidos píxel a píxel.
- **16 sprites por línea** en vez de 8: se acabó el parpadeo cuando hay muchos.
- **Sprites escalables**, con aumento, rotación y espejo.
- **Paleta ampliada**: 32768 colores, en conjuntos de 16.
- **256 KB de VRAM**, comandos nuevos (LRMM rota y escala al copiar, LFMM, LFMC) y un modo rápido de comandos que multiplica la velocidad de los bloques.

Todo eso está desactivado hasta que el software lo pide, así que el MSXimus Z es un MSX2+ normal para todo el catálogo. Para el software que sí lo pide, la referencia es la [demo DEVCON de HRA!](https://github.com/hra1129/V9968_Cartridge) y las demos de terceros escritas para él.

### 5.1 La generación C y el desbloqueo

Hay tres versiones del interfaz de registros del chip (A, B y C, explicadas en el [capítulo 05 de la referencia técnica](../tecnica/05-v9968.md)). El MSXimus Z lleva la **generación C**: las escrituras a los registros R#20 y R#21, que son los que activan lo nuevo, **se ignoran mientras el bit 7 del puerto 4 del VDP esté a 1**, y ese es el estado tras cada reset. El puerto 4 es el 9Ch (y su espejo 8Ch en el rango de cartucho), y el MSXimus Z lo decodifica.

Así la BIOS del MSX, que escribe en R#21 durante el arranque, no deja el chip en modo nativo (donde el bit 7 de R#2 es una línea de dirección más), y los juegos de V9958 corrientes ven un V9958 de verdad.

La consecuencia para quien pruebe software de V9968:

- El software de **generación B** (DEVCON con 0x9F, V9968DM, el port ru66 de herraa1, las demos de renatus: TECH DEMO 0.7.0, BENCHMARK, PROBE) **no detecta el V9968** hasta que haga `OUT (9Ch),0` antes de tocar R#20/R#21. Es una instrucción en el programa.
- Hay software de generación B que **tampoco escribe R#21**: da por hecho el R#21 = 0 que la BIOS ponía al arrancar. Aquí esa escritura se ignoró por el bloqueo, así que el chip sigue en modo V9958, sin los comandos nuevos ni los 256 KB. Es el caso de V9968DM: el logo sale, pero no gira, porque su LRMM no hace nada. DEVCON sí escribe R#21 él mismo.
- Para probar ese software sin recompilar hay dos caminos. Los dos valen hasta el siguiente reset, que vuelve a bloquear y a poner el modo V9958:
  - desde MSX-DOS, `V9968ON` (`tools/v9968_tests/V9968ON.COM`), que desbloquea y pone R#21 = 0;
  - desde BASIC, `OUT &H9C,0:VDP(22)=0` antes de lanzarlo (`VDP(22)` es R#21).
- Después hay que reiniciar antes de volver a los juegos normales: en modo V9968, el bit 7 de R#2 vuelve a ser una línea de dirección.
- El software de **generación A**, el hecho contra el emulador de buppu3, necesita además un byte cambiado en R#20 (0xFF pasa a 0x9F). Está explicado en el capítulo técnico.
- El software de **generación C**, el que ya hace el desbloqueo (el bitstream actual del cartucho de HRA! lo exige igual), funciona sin tocar nada.

### 5.2 Cómo se identifica

Bloqueado, que es como arranca, el V9968 responde como V9958 y el MSXimus Z como MSX2+: los programas de diagnóstico dirán "V9958". El chip responde en las dos direcciones estándar, 98h-9Bh y 88h-8Bh, así que el software que sí lo desbloquea puede encontrarlo en las dos. El `CHKVDP.COM` de la suite de HRA! (repositorio [hra1129/V9968_Cartridge](https://github.com/hra1129/V9968_Cartridge)) está pensado para identificar el V9968; con el candado puesto dice V9958. Lo que muestra exactamente tras el `OUT (9Ch),0` en el MSXimus Z no está documentado todavía.

## 6. Lo que no hay

- Salida analógica de ningún tipo: ni compuesto, ni RGB, ni VGA.
- Modo 4:3 con marco.
- Una limitación conocida: en Xevious aparecen guiones de 8 píxeles en las filas 6 y 7 de los tiles copiados con HMMM, por el motor de comandos del V9968.
- Tras un corte de corriente, el HDMI puede quedarse con el logo de arranque mientras el MSX ya está en el menú; se refresca al pulsar una tecla.
