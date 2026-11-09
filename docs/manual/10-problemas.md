# 10. Problemas frecuentes

Por síntoma, qué mirar en el MSXimus Z (ZYNQ MINI, versión Z1.3.1). La causa probable va en primer lugar.

La placa tiene dos mundos y conviene saber en cuál está el problema: el **PS** (el ARM, que arranca desde la QSPI o desde la tarjeta de TF1 y hace de *companion*: tarjeta, USB, OSD, OLED, ajustes) y el **PL** (el MSX). Una regla rápida: si la OLED escribe y el panel de **F12** responde, el companion está vivo y el fallo está en el lado MSX; si ni la OLED ni F12 dan señales, el problema es de arranque del PS.

## Al encender

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No arranca nada: sin logo, la OLED apagada, los LEDs del PL sin vida | SW1 en un modo que no corresponde a lo que hay grabado. ON-ON = JTAG (se queda esperando al PC), ON-OFF = QSPI, OFF-OFF = tarjeta de TF1 | Poner SW1 donde toca y **quitar y dar la corriente**: el modo solo se lee al encender; el reset de la placa (PS_SRST) no lo relee |
| Con SW1 en SD (OFF-OFF) no arranca | `BOOT.bin` no está en la raíz de la tarjeta de **TF1**, la tarjeta no es FAT32, o se ha metido en TF2, que es la del MSX | TF1 es la ranura del PS. El fichero se llama exactamente `BOOT.bin` y va en la raíz |
| Con SW1 en QSPI (ON-OFF) no arranca, o arranca la demo de fábrica | La QSPI está vacía o **a medio grabar**: un borrado que se queda colgado (pasa si se intenta grabar con SW1 en SD) deja la QSPI inservible hasta regrabarla | Regrabar con `tools/qspi_program.tcl` **con SW1 en JTAG (ON-ON)**, y encender de nuevo con SW1 en QSPI ([capítulo 02](02-instalacion.md)) |
| Pantalla negra, sin señal HDMI, pero la OLED sí escribe | El PL no se ha configurado: `BOOT.bin` mal montado (el bitstream tiene que ir justo detrás del FSBL) o el monitor no acepta la señal | Regenerar el `BOOT.bin` con `make_boot.sh`; probar otra entrada o cable |
| Pantalla negra y la OLED también apagada | El PS no ha llegado al companion: el FSBL no encuentra sus particiones o no ha entrenado la DDR | La consola del FSBL sale por la UART1 del PS (P1, el puerto serie USB de la placa, 115200 baudios). Por JTAG, `tools/armlog.tcl` dirá "sin log del ARM" |
| El HDMI se queda con el logo mientras el MSX ya está en el menú | Tras un apagón puede pasar: el puente de vídeo no refrescó | Pulsar cualquier tecla: se refresca. Si se repite, anotarlo |
| Arranca directo en DOS y no sale el menú | *Menú al arrancar* en Off | Mantener **S** durante el logo: entra en Ajustes igualmente. Marcar *Menú al arrancar* y Save & Restart |
| Arranca pero se reinicia en bucle | Una ROM con el punto de entrada fuera del cartucho | Reset; el menú ya veta las que reconoce |
| Sale el menú del Game Master 2 en vez del juego | El juego no es Konami pero usa el mapper Konami-SCC (Space Manbow 2) con GM2 activo | Tecla **G** en la pantalla de lanzar para ese juego |

### Los resets

- **El reset de la placa (PS_SRST)** reinicia el PS entero: vuelve a pasar por el FSBL, el companion y la configuración del PL. Es el "apagar y encender" sin tocar el cable, con una excepción: **no relee SW1**. Va bien desde SD y desde QSPI.
- **El botón de reset del MSX (K2)**, conectado al pin **M19** del PL, reinicia solo el MSX: solo el Z80 y sus chips; el companion sigue sirviendo la tarjeta y la RAM se conserva, como el botón de reset de un MSX de verdad.
- `tools/msxreset.tcl` por JTAG hace lo mismo que ese botón escribiendo MSX_RUN, pero deja colgado el ESC=Boot del menú: para un reset caliente, mejor el botón de reset del MSX (K2) o el reset de la placa (PS_SRST).

## Los ajustes

En la Zynq los ajustes no viven en la cola del pack sino en un bloque de 16 bytes en el último sector de la QSPI (0xFFF000), que **graba el companion** cuando el menú pulsa *Save & Restart* y que siembra en el core antes de soltar el MSX.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Los ajustes no sobreviven al apagado | Solo se graban con **Save & Restart** de Ajustes. Y solo si el companion está en marcha: en un arranque por JTAG sin `BOOT_PROXY=1` no hay quien los escriba | Guardar desde Ajustes con el sistema arrancado desde QSPI, desde TF1 o por JTAG con `BOOT_PROXY=1` |
| Ajustes sale con todo a cero o a los valores de fábrica | El bloque leído no es válido (un bloque con config1 = 0 se rechaza) y el core arranca con los defectos | Poner lo que se quiera y Save & Restart: el bloque nuevo sustituye al malo |
| El mezclador vuelve a 8/8 en todos los canales | El bloque de config no lleva los niveles o su suma de comprobación no cuadra: el core se queda con los defectos | Ajustar los niveles y Save & Restart; el bloque nuevo ya los lleva |
| *Boot Turbo* marcado pero arranca a 3,58 MHz | El boot turbo solo entra en arranque en frío: tras un Save & Restart (que es un reset caliente) queda para el siguiente encendido. Mantener el botón K3 (pin M20) al soltar el MSX en el arranque también lo inhibe | Apagar y encender |
| *Menú al arrancar* en Off y no hay forma de volver a Ajustes | Es el diseño: el menú no aparece | Mantener **S** durante el logo: entra en Ajustes aunque el menú esté apagado |

Para mirarlo desde el PC: `tools/cfg.tcl show` enseña el bloque sembrado (+0x1C y +0x24 del buzón) y el último que salió al guardar (+0x70 y +0xC0); `tools/tel.tcl` lo repite entre el resto de la telemetría. Regrabar la QSPI con `qspi_program.tcl` no toca el bloque de ajustes: solo graba el rango del fichero y los ajustes están en el último sector.

## La tarjeta (TF2)

La tarjeta del MSX va en **TF2**. La sirve el companion sector a sector (proxy por la DDR); el core no la toca directamente.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| "No se detecta la tarjeta SD" | La tarjeta está en TF1 (la del arranque) en vez de TF2; no inicializa; o se ha metido con el MSX ya arrancado | El companion reintenta cada 0,5 s, pero el menú solo pregunta al arrancar: reset del MSX. **F12** dice si el companion la ve (sección *Tarjeta SD*: "NNNN MB" o "sin tarjeta") |
| Errores de disco tras sacar y meter la tarjeta en caliente | El companion la reinicializa sola, pero lo que el MSX tenía abierto se pierde | Reset |
| Todo se queda parado unos 2 segundos y sale un error de SD | El PL no recibió el acuse del ARM: el companion no está en marcha (arranque por JTAG en modo imagen, sin `BOOT_PROXY`) o se ha colgado | `tools/armlog.tcl`: si dice "sin log del ARM", no hay companion. Arrancar desde QSPI/TF1 o con `BOOT_PROXY=1` |
| Descargas o guardados que fallan de forma aleatoria | Tarjeta sin marca que pierde escrituras | Cambiar a una de marca, clase 10. `armlog.tcl` enseña cada acceso fallido como "ERR op=... st=..." (st=1 sin tarjeta, st=2 fallo de la tarjeta) |
| "FH: la SD es FAT32 (v1 solo FAT16)" o los guardados no se escriben | File-Hunter escribe solo en FAT16 | Partición FAT16 de hasta 2 GB para el menú; el resto de la tarjeta puede ser FAT32 |
| "DSK fragmentado: recopialo" | El `.dsk` no está en clusters consecutivos | Copiarlo de nuevo desde el PC |
| "Falta NEXTOR.EMU en la raiz" | El menú no pudo crear el fichero oculto | Tarjeta llena o protegida; con FAT32 no hace falta |
| "Falta FHUNT (MKDIR en DOS)" o "GM2: sin FHUNT" | No existe la carpeta | Crearla desde MSX-DOS |
| Nextor da "Disk error writing drive A" con DRVTEST | Se ha redirigido la salida a la tarjeta | Redirigir a un disco RAM |
| La tarjeta va lenta | La tecla **T** mide las cuatro rutas; la DMA de lectura en la Zynq ronda los 1600 KB/s | Si sale mucho menos, probar otra tarjeta |

## La tarjeta de TF1 (perfiles)

La microSD de **TF1** guarda los perfiles del sistema y el MSX no la ve ([capítulo 03](03-tarjeta-sd.md), sección 2). Hasta la Z1.4.2 era la segunda unidad de Nextor.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Ya no aparece la unidad B: con la tarjeta de TF1 | Desde la Z1.4.3 la TF1 es solo de perfiles | Es lo esperado. Los datos de esa tarjeta hay que copiarlos antes a TF2 o al PC; la placa avisa de que tiene datos de MSX-DOS antes de borrarla |
| El panel F12 y la OLED dicen «TF1 nueva» o «tarjeta beta» | Hay una tarjeta en TF1 que aún no está preparada para perfiles (o es de las betas) | F12 → P: **T** o **B** según lo que diga la página. Es un aviso, no bloquea nada |
| «Has arrancado desde esta tarjeta. Pon SW1 en QSPI para prepararla» | La placa arrancó desde SD: TF1 es la tarjeta de arranque y no se prepara ni se borra | Poner SW1 en ON-OFF (QSPI), apagar y encender |
| «La tarjeta no guarda lo que se escribe: parece falsa o defectuosa» | La capacidad que dice la tarjeta no es la real, o está estropeada | Otra tarjeta (de marca, 1 GB o más) y, si hay dudas, H2testw en el PC |
| «La tarjeta es demasiado pequeña» | Menos de 1 GB | Una tarjeta de 1 GB o más |
| Sale «Sin perfiles» tras preparar | La tarjeta está lista pero vacía | Con red: **S** y **A** baja todos. Sin red: un `.MXP` desde el navegador del menú |
| El menú, WaveGame o la cinta no ven nada de TF1 | Esas funciones leen solo TF2 | Es lo esperado |

## ROMs

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Mapper "? (desconocido)" | La ROM cambia de banco de una forma que el análisis no ve | Tecla **M** hasta acertar; luego poner la etiqueta en el nombre |
| El juego arranca y se cuelga a los pocos segundos | Mapper equivocado | Probar los otros con M |
| "INIT pag.0/BASIC: no lanzable" | ROM de un programa BASIC | No es lanzable como cartucho |
| La partida no se guardó | Se apagó en vez de hacer reset, o no hay carpeta FHUNT | Reset siempre; crear FHUNT |
| Metal Gear 2 en pantalla negra con el Game Master 2 | La versión [9692] de la ROM, con chequeo de MSX-DOS en el arranque | Usar otra versión, por ejemplo la [3371] o la [1489] |
| Un juego de V9990 se queda en negro tras «V9990 found !» | Mapper equivocado: el juego copia su código cambiando de banco y el menú eligió otro | **M** hasta acertar. *Shao-lin's Road* va con Konami-SCC; *Xybots* y *Sol Negro*, con ASCII16 ([capítulo 05](05-roms-mappers.md)) |

### WaveGame

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La música WAV no suena, solo el PSG/SCC | Los `NN.wav`, `NN.cfg` y `pause.wav` no están en **la misma carpeta que la ROM** de TF2, o el WAV no es 48 kHz mono 16 bits | Copiar la carpeta del juego tal cual |
| El juego WaveGame arranca mal o se cuelga | Las ROMs WaveGame de Konami son Konami-SCC aunque el detector diga "Konami" | **M** hasta Konami-SCC |
| La música distorsiona | Ganancia del WaveGame subida por encima de x1, o canal 7 del mezclador | `tools/wg.tcl gain 0`; nivel del canal WaveGame en el Mezclador de audio |

Para ver qué hace el companion con la música: `tools/wg.tcl status` (estado, anillo, canción) y las líneas "wg: ..." de `tools/armlog.tcl`.

## Vídeo y audio

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El televisor no muestra imagen | Receptor que no acepta 720p60 con audio embebido | Probar otro cable o entrada; es una señal estándar |
| Un juego a 50 Hz se ve con la geometría rara | En el V9968 el modo 50 Hz es el menos probado: su geometría no está medida | Anotar cuál y reportarlo |
| La imagen se va a negro uno o dos segundos al cambiar entre V9968 y V9990 | Las dos señales 720p no van en fase y el monitor se reengancha | Es normal; no pulsar Pausa en ráfaga ([capítulo 09](09-video.md)) |
| Un programa de V9990 no pasa la HDMI al V9990 | El automático salta con todos los modos salvo B6, y Pausa lo desarma hasta el siguiente reset | Pausa para conmutar a mano; o reset del MSX para rearmarlo |
| El V9990 tiene una franja negra arriba y abajo | El borde del propio chip en 212 líneas | Es normal, no se recorta |
| Sin MoonSound, o instrumentos que faltan | La tabla de ondas YRW801 no está en la DDR: el `BOOT.bin` se montó sin `yrw801.rom`, o en un arranque por JTAG no se pasó `WAVE_ROM=` a `boot.tcl` | Regenerar el `BOOT.bin` con `make_boot.sh` (la carga en 0x0F000000). El companion suma los 2 MB al arrancar: el panel F12 (fila *OPL4*) dice `YRW801 OK` o `YRW801 no válida`, y la OLED sustituye la fila del VDP por `YRW801 NO VALIDA`. Con el `BOOT.bin` publicado esto no pasa |
| El FM del MoonSound suena más bajo o más alto de lo esperado respecto al wave | Los registros F8h y F9h del OPL4 (volumen del FM y del wave) | `MTVOL.COM` los fija; el nivel frente a los demás chips, en el Mezclador de audio ([capítulo 08](08-audio.md)) |
| Todo suena bajo o distorsionado | Ganancia maestra o niveles del mezclador tocados | Ajustes, *Mezclador de audio*: maestra x5 y canales a 8/8 ([capítulo 08](08-audio.md)) |
| Un chip concreto no suena | Su canal está a 0/8 (mudo) en el mezclador | Subirlo. Cada cambio toca una nota en ese chip: si no se oye ni la nota, el chip no está sonando |
| VGMPlay se cuelga con OPL3 | Nextor 3 | Usar el pack con Nextor 2.1.4 |
| El SCC no suena en un juego | El juego busca el SCC en otro slot | Ajustes, Slot 1 = 2o SCC |
| DEVCON 0x9F, V9968DM o TECH DEMO 0.7.0 no detectan el V9968 | Generación C: R#20/R#21 se ignoran hasta que el programa escribe el puerto 9Ch con el bit 7 a 0 | Es lo esperado; ese software tiene que hacer `OUT (9Ch),0` antes de tocar R#20/R#21 ([capítulo 09](09-video.md)) |
| Guiones de 8 px en los tiles de Xevious | Defecto conocido del motor de comandos del V9968 | Nada por ahora; si sale en otro juego, anotarlo |
| Bloques de 8 px "rancios" o ruido en zonas de la pantalla | Fallos del shim de la VRAM en la DDR (fondo o sprites) | `tools/tel.tcl 3` enseña los fallos por lectura ("shim VRAM: bgmiss/spmiss"); reportar con esa salida |

## Teclado, mando y ratón

Todo entra por el USB host del PS (el companion, con TinyUSB) y llega al MSX por el buzón de la DDR. El panel de **F12** lleva la cuenta en el bloque USB ("2 dispositivos" y debajo "1 teclado · 1 mando"), y la OLED en su línea `USB t r m`. Si el dispositivo no suma ahí, el MSX no lo verá nunca.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El teclado no responde | No se ha enumerado: un hub con Ethernet (RTL8153) se queda a medias en la enumeración; o el teclado no habla el protocolo *boot* | Conectar directo o por un hub simple sin RJ45; comprobar en F12 que cuenta un teclado |
| Teclado, ratón y mando dejan de responder a la vez tras horas encendida, y reconectarlos no sirve | El controlador USB del PS se ha colgado | Desde la Z1.3.2b7 la placa lo detecta y reinicia el USB sola en unos segundos (F12 dice «USB reiniciado: n»). Si no vuelve, `tools/usbreset.tcl` por JTAG, o apagar y encender |
| El mando no hace nada | No se ha enumerado, o el mando no es ni HID genérico ("SNES USB") ni XInput (Xbox 360 o receptor que se presenta como tal) | Probar sin hub o con otro mando; F12 tiene que contar un mando |
| El ratón no se ve o no se mueve | Receptor inalámbrico compuesto (no todos van) | Ratón con cable; F12 tiene que contar un ratón en el bloque USB |
| F12 no hace nada | El companion no está en marcha (arranque por JTAG sin `BOOT_PROXY`), el teclado no se ha montado, o el HDMI está en el V9990 (fila siguiente) | `tools/osd.tcl on` por JTAG enciende el panel sin teclado. El turbo va en F11 |
| F12 congela el MSX pero no se ve el panel | Hasta la Z1.2.13, con el HDMI en el V9990 el panel no se dibujaba; desde la Z1.3 sale en todos los modos | **F12** otra vez para soltar el MSX, **Pausa** para volver al V9968 y F12 de nuevo; actualizar a la Z1.3. La OLED sigue diciendo el estado |
| El MSX está congelado con un panel de texto encima | El OSD está abierto: mientras está encendido el Z80 se para | F12 otra vez, o `tools/osd.tcl off` |
| La ñ no sale con un teclado español | La distribución del MSX no la tiene en esa tecla | Sin arreglo documentado todavía |

## WiFi (módulo ESP32-S3 en CAM1)

Sin módulo y sin cable el MSX no tiene red; con cable, el companion hace de ESP y no hace falta módulo (sección siguiente).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Con **W** salen caracteres sin sentido y no aparece el menú del ESP | El módulo no está alimentado o no responde | Alimentarlo por **su propio USB-C** (el USB host de la placa no basta para alimentarlo); la LCD tiene que encender |
| La LCD enciende pero el menú W no ve el módulo | Falta la **masa común** (obligatoria si se alimenta aparte), o TX y RX al revés | Pin 26 del CAM1 ← TX del ESP (GPIO16 en la S3-LCD-1.69), 28 → RX (GPIO17), 30 = turbo (GPIO18), GND en 37/38. Nunca el pin 2 (VCC5) ni unir los 3V3 |
| "FH: sin UNAPI" | El MSX no ve el driver: la línea del ESP hacia el PL no llega | Revisar el cruce TX/RX; `tools/tel.tcl` enseña los contadores del UART del ESP (bytes tirados y lecturas en vacío) |
| "FH: sin red (tecla W)" | Red no configurada | Tecla W, Scan/Join |
| "FH: CRC MAL" o descargas corruptas | Bytes perdidos en la FIFO del UART | Con la S3 en CAM1 no debería haberlos; si aparecen, anotar los contadores de `tel.tcl` y reportar |
| Conectado pero nada descarga | Sin internet, o File-Hunter caído | Probar más tarde |
| La LCD dice "Sin WiFi" | Red no configurada, o la red guardada no está al alcance | Tecla W, Scan/Join. La red y la contraseña se guardan en el módulo, no en el MSX |
| El módulo enciende y dice *Conectado* pero el MSX no ve el driver ("FH: sin UNAPI") | El driver del ESP se inicializa al arrancar el MSX y el módulo se enchufó o arrancó después | Encender el módulo antes, o reiniciar el MSX con el botón de reset del MSX (K2) |
| Con un cable Ethernet puesto, el módulo no responde | Mientras el cable tenga enlace, el companion se queda con la UART del ESP | Quitar el cable (ver *Red por cable*) |

## Red por cable (Ethernet de la placa)

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La tecla W dice "Ethernet" pero no conectada | Sin cable o sin enlace | Cable en **J3** (el jack del procesador; J2 es el del PL y no vale); el enlace se mira cada 250 ms y el DHCP arranca solo |
| Hay cable con enlace pero **sin IP**: F12 dice "sin cable o sin IP" y la OLED `IP --` | El DHCP no ha contestado (router sin DHCP, puerto sin red, cable de mala calidad que negocia mal) | Probar otro puerto o cable; el PHY tarda unos segundos en negociar tras enchufar. `tools/armlog.tcl` enseña la IP, la puerta y el DNS cuando llegan; si no hay línea de DHCP, no ha contestado nadie |
| Al bajar una cinta TSX el menú acaba en "FH: timeout de descarga" | La descarga va por https desde el companion: sin salida a internet, DNS caído o el servidor devolvió un error | `tools/armlog.tcl`: las líneas `tls:` y `esp: tsx` dicen en qué paso se quedó (DNS, TLS, HTTP 4xx, CRC) |
| hget https falla con "connection failed" | El handshake TLS no acabó en 25 s (servidor sin TLS 1.2 con ECDHE, o sin red) | En el log del ARM sale el motivo (`tls: handshake fallo -0x...`); el certificado no se verifica, así que no es cosa de CA |
| "FH: fallo DNS" nada más buscar | El router no da DNS, o la red no tiene salida | `tools/armlog.tcl` enseña la IP, la puerta y el DNS que llegaron por DHCP |
| Con un ESP32 en el CAM1 el MSX habla con el cable y no con el módulo | Mientras el cable tenga enlace el companion se queda con la UART del ESP (bit 3 de MBOX+0x1C) | Quitar el cable: en un segundo la UART vuelve al módulo (y al ponerlo, al companion) |
| Quiero ver qué se dicen el MSX y el companion | | Compilar el companion con `ESP_TRACE 1` (`esp.h`): cada comando, su respuesta y los ms salen en el log del ARM |

## Actualización por red

Se hace desde **F12** y luego **U** (explicada en el [capítulo 12](12-actualizar.md)). Para reiniciar en la ranura B la placa tiene que arrancar desde la **QSPI**. Lo que dice la página y qué hacer:

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| "Sin conexión al servidor" | No hay salida a internet: DNS, TCP o TLS fallan, o el servidor no contesta | Comprobar la red (cable en J3 con IP, o WiFi de la S3); probar más tarde. `tools/armlog.tcl` dice en qué paso se quedó (`ota: fallo: ...`) |
| "La WiFi no conecta" | Sin cable, y la S3 del CAM1 no tiene red | Tecla W en el menú para configurarla, o conectar el cable en J3. Mientras dura la búsqueda o la descarga, el companion toma el ESP: el MSX se queda sin red hasta que acaba |
| "sin red: cable o WiFi" al pie de la página | No hay cable con IP ni S3 | Igual que arriba |
| "Firma no válida" | El manifiesto no está firmado con la clave de esta placa: un servidor equivocado, una descarga a medias o una versión manipulada. La placa lleva solo la clave pública (`fpga/zynq/ota/ota_publica.pem`) | No instalar nada. Probar de nuevo; si persiste, avisar |
| "La actualización no está" | El servidor no tiene el fichero que anuncia | Probar más tarde |
| "No es para esta placa" | La imagen es de otra placa | Es un error del servidor; avisar |
| "Descarga dañada" | El tamaño o el SHA-256 no cuadran | **U** para intentarlo otra vez; no se ha tocado la QSPI |
| "Datos de versión no válidos" / "Respuesta no válida" | El manifiesto o la respuesta del servidor no tienen el formato esperado | **U** otra vez; si persiste, avisar |
| "Error al grabar la QSPI" | Falló la grabación o la relectura de la ranura B | **U** y **I** de nuevo. La ranura A (de fábrica) no se toca nunca |
| "SW1 en QSPI y apaga" al pulsar **R** | La placa arrancó desde tarjeta o por JTAG: no hay BootROM de QSPI que cargue la B | SW1 en QSPI (ON-OFF) y quitar y dar la corriente |
| Instalada, pero tras reiniciar vuelve la versión de antes | La ranura B nueva no llegó a confirmarse: se confirma cuando el MSX lee la tarjeta (o tras 20 s de Z80 vivo si no hay), y se prueba como mucho tres veces | Mirar *Instalada* en la página (`ranura A · de fábrica` o `ranura B · actualización`; `a prueba` si aún no está confirmada). **R** la prueba otra vez |
| Quiero volver a la versión de fábrica (**ranura A**) | | En la página de la actualización, **F** dos veces borra el registro de la B ("F otra vez: a la de fábrica") y **R** reinicia en la A. También se vuelve a la A al apagar y encender si la B no se ha confirmado |
| "Sin su NEXTOR.SYS en la SD no arrancará MSX-DOS" | Se ha elegido en la página otro Nextor (2.1.4 o 3) u otro idioma | Cambiar de Nextor exige el `NEXTOR.SYS` correspondiente en la tarjeta (MSX SD Maker lo prepara, [capítulo 03](03-tarjeta-sd.md)) |

## Desarrollo por JTAG

Solo para quien compila o arranca desde el PC.

- **El JTAG no ve la placa** (`tools/detect.tcl` dice SIN_TARGET): SW1 en JTAG (ON-ON) y apagar y encender; `hw_server` en marcha y sin otro Vivado o xsdb abierto contra la misma placa; el adaptador en otro puerto USB, o desenchufarlo y volver, y reiniciar `hw_server`. Vivado 2019.2 solo lo ve con el `FTD2XX.dll` cambiado ([capítulo 02](02-instalacion.md)).
- **Con SW1 en SD no funciona nada por JTAG**: ni `boot.tcl` ni la grabación de la QSPI ("The current boot mode is SD"). JTAG o QSPI, y el modo solo se relee al quitar y dar la corriente.
- **`boot.tcl` no arranca el MSX** (`tel.tcl` da hits=0, miss=1, siempre igual): un puerto HP se quedó atascado al reprogramar el PL en caliente con la imagen anterior leyendo la DDR. `tools/psreset.tcl` y repetir `boot.tcl`; el propio `boot.tcl` ya para el PL antes de tocar el PS para que no vuelva a pasar.
- **La grabación de la QSPI se queda colgada en el borrado o en el verify**: primero comprobar SW1 (lo de arriba). Si se queda colgada con SW1 bien puesto: matar Vivado y repetir.
- **`armlog.tcl` dice "sin log del ARM"**: el companion no está cargado (arranque por JTAG sin `BOOT_PROXY=1`, o el PS no llegó a él).
- **El MSX se cuelga o teclea solo tras `key.tcl`**: los caracteres `\` y `|` ya se mapean; si una línea sale concatenada, revisar las comillas del `-type`.
- **Temperatura**: el chip va a unos **80 °C sin disipador** y a unos 55 °C con él. Poner disipador. Se mira con `tools/temp.tcl`, en F12 o en la OLED (línea "die").
- **El MCP de openMSX no sirve** con esta cadena de herramientas (issue nataliapc/mcp-openmsx#22): openMSX por línea de comandos, con `tools/openmsx_vdplog.tcl` para las trazas del VDP.

## Herramientas para diagnosticar

Desde el MSX, sin PC:

- **Tecla T en el arranque o en el navegador**: el menú de pruebas. Dice la versión del core, el tipo de tarjeta, los bytes de configuración de los puertos 41h/42h/46h, y mide la velocidad de la tarjeta por sus cuatro rutas, el sonido del PSG y del OPLL, el Game Master 2 y el VDP.
- **Tecla H**: la ayuda del navegador.
- **Ajustes**: muestra la versión del core (Z1.3.1), la misma que la cabecera del panel F12.
- **F12**: el panel del companion, sobre la imagen del MSX: versión, temperatura del chip y máxima, tensiones internas, tiempo encendida, tarjeta de TF2 (MB y errores), USB (dispositivos y tipos), velocidad del Z80, SCREEN actual, chip de vídeo en la HDMI, estado de la YRW801 y la IP del cable ([capítulo 09](09-video.md)). Congela el Z80 mientras está abierto, y con el HDMI en el V9990 no se ve (problema conocido). Con **U** pasa a la página de la actualización.
- **La OLED de la placa** (J4): lo esencial en ocho líneas, sin parar nada y también con el HDMI en el V9990: versión, temperatura, MB de la tarjeta, contadores USB (t/r/m), IP, chip de vídeo (o `YRW801 NO VALIDA`), tiempo encendido y CPU a 3,58 o 5,37 MHz.
- **Los LEDs del PL**: el conectado a W13 parpadea lento a 3,58 MHz y rápido con el turbo (es el "estoy vivo" del core); el de V12 se enciende con la actividad de la tarjeta. Los otros dos siguen los disparos del mando 1.
- **La LCD del ESP32**: red, tráfico, turbo, hora.
- **Puertos desde BASIC**: `INP(&H2F)` da la versión del core (&HA3 = línea Zynq Z1.3; el nibble alto A significa línea Zynq) e `INP(&H29)` los arreglos (1 en la Z1.3.1); la versión completa la dice la cabecera del panel F12. El 2Dh describe el estado del USB del núcleo, que en la Zynq no se usa (el USB va por el companion): para el USB, F12 ([capítulo 02 de la referencia técnica](../tecnica/02-puertos-es.md)).

Desde el PC, por JTAG (`xsdb.bat tools/<script>.tcl`, con `hw_server` aparte):

| Script | Qué mira |
|---|---|
| `tel.tcl [n] [ms]` | Telemetría del PL: caché de la RAM, VDP, estado de la tarjeta, ratón, UART del ESP, OPL4, fallos del shim de VRAM, bloque de config y mezclador |
| `armlog.tcl` | Log del companion y estadísticas del proxy de la tarjeta (lecturas, escrituras, errores, reinicios) |
| `screen.tcl` | Vuelca la pantalla de texto del MSX leyendo la VRAM de la DDR |
| `key.tcl` | Pulsa teclas en el MSX (para reproducir un fallo sin teclado) |
| `cfg.tcl show` | Bloque de ajustes sembrado y guardado |
| `osd.tcl on/off/show` | Enciende el panel F12 y da la temperatura que ve el ARM |
| `temp.tcl` | Temperatura del chip y tensiones por el XADC |
| `wg.tcl status` | Estado del WaveGame |
| `vdptrace.tcl` | Traza de los accesos al VDP y los bytes del UART del ESP |
| `psreset.tcl`, `msxreset.tcl` | Reset del PS entero / solo del MSX |

## Cómo reportar un problema

Con la versión del core (la cabecera del panel F12 o `INP(&H2F)`), el pack (2.1.4 o Nextor 3), cómo arrancó la placa (QSPI, tarjeta en TF1 o JTAG) y el `md5` del `BOOT.bin` si se sabe, el nombre exacto de la ROM o disco con su tamaño, y lo que dice la línea de estado del menú o el mensaje de DOS. Una foto de la pantalla vale más que una descripción; si hay JTAG a mano, la salida de `tel.tcl` y de `armlog.tcl` vale más que la foto.
