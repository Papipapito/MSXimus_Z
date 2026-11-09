# 07. La red: Ethernet, WiFi y File-Hunter

El MSXimus Z tiene red por dos caminos, y los dos le dan al MSX lo mismo: una pila TCP/IP **UNAPI** como la de cualquier cartucho de red. Con ella funcionan el driver del pack, la tecla **W**, el **File-Hunter** del menú (buscar y bajar ROMs, discos y cintas sin pasar por el PC), `hget` y cualquier programa de red de MSX que hable UNAPI. La misma red sirve para [actualizar la placa](12-actualizar.md).

| Camino | Qué hace falta | Cómo se configura |
|---|---|---|
| **Ethernet** | Un cable en el conector **J3** de la ZYNQ MINI | Nada: la IP la da el router por DHCP |
| **WiFi** | Una **Waveshare ESP32-S3-LCD-1.69** en el header **CAM1** | La tecla **W** del menú: red y contraseña |

Con los dos puestos, **manda el cable mientras tenga enlace**; al quitarlo, la WiFi vuelve a mandar. Sin ninguno, el MSX arranca igual: el driver de red sigue en su slot (0-2) sin molestar, y los programas de red dicen que no hay red.

## 1. Ethernet (J3)

La ZYNQ MINI trae dos conectores Ethernet y el MSXimus Z usa el del procesador, **J3**; el de al lado, J2, es de la lógica y no se usa. No hace falta ningún módulo: el *companion* del ARM habla al MSX el protocolo del [ESP32-UNAPI-Firmware de ducasp](https://github.com/ducasp/ESP32-UNAPI-Firmware), y el MSX ve un ESP32 normal.

- **Una sola red, "Ethernet".** La tecla **W** enseña esa red, abierta y conectada mientras haya cable con IP. No hay nada que escanear ni contraseña que poner.
- **IP por DHCP**, con el nombre de equipo `msximus`. La IP sale en el panel F12 (fila *Red*, [capítulo 04, §10](04-menu.md)) y en la OLED; sin cable o sin IP dice *sin cable o sin IP*.
- **TLS (https)** desde el companion: `hget` y las cintas del catálogo TSX bajan de servidores https. Lo que no hace es **verificar el certificado** del servidor: cifra, pero no comprueba con quién habla.
- **Los ajustes de la tecla W** (Nagle, tiempo de la radio, reloj y huso horario) valen mientras la placa esté encendida; al apagar vuelven a sus valores de partida.

## 2. WiFi (CAM1): la ESP32-S3

La WiFi la pone un módulo externo, la **Waveshare ESP32-S3-LCD-1.69** (un ESP32-S3 con pantalla de 1,69" y 240×280), con el firmware de [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`). Se une a la ZYNQ MINI con el **cable SH1.0 de 12 hilos** que trae la placa, a tres pines del CAM1, más la masa.

### El cableado

El cable se numera desde el extremo del conector que queda **lejos del USB-C** de la S3 (posición 1):

| Posición del cable | Color | Señal en la S3 | Pin del CAM1 | Señal en la placa |
|---|---|---|---|---|
| 1 | negro | GPIO18, indicador de turbo | **30** | `esp_turbo_o` (pin P19) |
| 2 | rojo | GPIO17, RX de la S3 | **28** | `esp_tx_o` (R18) |
| 3 | verde | GPIO16, TX de la S3 | **26** | `esp_rx_i` (W16) |
| 11 | morado | GND | **38** | masa |

El azul (3,3 V) y el gris (5 V) **se quedan sin conectar**.

Localizar CAM1 en la placa: es el 2×20 con los pines 1 y 2 en el extremo izquierdo, los impares en la fila exterior y los pares en la interior. Los tres de señal (26, 28 y 30) son tres pares consecutivos de la fila interior, y la masa (38) está en esa misma fila, cuatro pares más allá.

Avisos, por orden de importancia:

- **La masa es obligatoria.** La S3 se alimenta por su propio USB-C, aparte de la placa: sin el hilo de GND no hay referencia y el enlace no va, o va a ratos.
- **Alimentación de la S3 por su USB-C**, desde el PC o desde una fuente USB. No la alimentes desde el CAM1 (su pin 2 es el 5 V del USB-C de la placa) ni unas los 3V3 de los dos lados: son reguladores distintos.
- RX y TX **van cruzados** respecto a los nombres de la S3: el CAM1-26 recibe del TX de la S3 (verde) y el CAM1-28 manda al RX de la S3 (rojo).
- El indicador de turbo (CAM1-30) es opcional: sin él la red funciona igual y la pantalla de la S3 siempre dice *Normal*.

### Grabar el firmware de la S3

El firmware no se publica ya compilado: se compila desde [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`) con `arduino-cli`, como cuenta su README (placa `-DESP32_S3 -DESP32_S3_LCD169`; el esquema de partición `app3M_fat9M_16MB` no es opcional), y se sube por el USB-C de la S3 conectado al PC (sale como *Dispositivo serie USB*), sin soltar los hilos del CAM1. Las órdenes exactas están en el [capítulo 02](02-instalacion.md), sección 8.

El firmware lleva 16 autoridades de certificación de Mozilla, que son las que le permiten a la placa validar el certificado de msx.barcelona al [actualizarse por WiFi](12-actualizar.md).

### La pantalla de la S3

Al encender, el logo MSX; después, el estado:

```
 ┌────────────────────────────────┐
 │ MSX                          ● │  título + punto de actividad del enlace
 ├────────────────────────────────┤
 │ Conectado                      │  o "Sin WiFi" en rojo y
 │ SSID:mired                     │  "Pulsa W en el menu"
 │ RSSI:-58dBm                    │
 ├────────────────────────────────┤
 │ ████ TURBO 5.37MHz ████        │  naranja en turbo,
 │                                │  gris "Normal 3.58MHz" si no
 ├────────────────────────────────┤
 │ Uptime 0:12:34   Temp 41 C     │  la temperatura es la del propio ESP
 │ 18:42  17/09/26                │  hora local por SNTP
 └────────────────────────────────┘
```

| Zona | Qué muestra | Se refresca |
|---|---|---|
| Punto arriba a la derecha | Verde si ha habido tráfico con el MSX en el último cuarto de segundo, gris si no. Es el primer diagnóstico | cada 150 ms |
| Bloque WiFi | *Conectado* con el SSID y la señal en dBm, o *Sin WiFi* con el aviso de pulsar **W** en el menú | cada 1 s |
| Barra de turbo | *TURBO 5.37MHz* en naranja cuando el MSX va en turbo (F11); *Normal 3.58MHz* en gris si no | cada 400 ms |
| Barra inferior | Tiempo encendido, temperatura del chip y hora local. Hasta que el reloj sincroniza dice *Sincronizando*, o *Sin WiFi* | cada 3 s |

El reloj de la S3 se pone en hora por SNTP en cuanto hay red; la opción de reloj del setup de la tecla **W** pone en hora también el del MSX.

Regla del firmware: nunca se imprime texto por la UART del enlace, porque cualquier byte suelto corrompe el protocolo UNAPI.

## 3. Configurar la red: tecla W

En el navegador del menú, o durante el logo de arranque, la tecla **W** abre el **Wi-Fi Setup** del driver UNAPI de ducasp:

| Opción | Qué es |
|---|---|
| Set Nagle | Ajuste del protocolo TCP; se deja como está |
| Wi-Fi On Period | Cuánto tiempo mantiene la radio encendida sin uso |
| Scan/Join Access Points | Buscar redes y unirse a una, con su contraseña. Por cable solo sale "Ethernet" |
| Wi-Fi and Clock Settings | Huso horario y reloj automático |
| ESC | Volver al navegador |

Con la S3, la red y la contraseña se guardan **en la S3**, no en el MSX: una vez configuradas, se conecta sola al encender, y su pantalla pasa de *Sin WiFi* a *Conectado* con el nombre de la red. El cambio de modo de pantalla al entrar y al salir es normal. Más sobre la tecla W en el [capítulo 04, §6](04-menu.md).

La configuración WiFi hay que hacerla **sin cable** en J3: con cable puesto la W solo ve la red "Ethernet".

## 4. File-Hunter: tecla F

[File-Hunter](https://www.file-hunter.com/) es la base de datos de ROMs y discos de MSX. Con la red funcionando y una carpeta `FHUNT` en la raíz de la tarjeta del MSX, la tecla **F** del navegador busca en ella y descarga a la tarjeta.

La tarjeta del MSX es la de **TF2**, la que sirve el companion; TF1 es la de los perfiles (y la de arranque del procesador): ni el menú ni Nextor la ven. `FHUNT` es la misma carpeta donde el menú guarda las SRAM de los juegos (`<rom>.SRM`) y donde busca `GM2.ROM` para el Game Master 2 ([capítulo 05](05-roms-mappers.md)).

1. **F** abre el campo *"File-Hunter Buscar:"*. Se escribe un trozo del nombre, de 2 a 20 caracteres, y RETURN. ESC cancela.
2. El menú consulta `api.file-hunter.com` (ROMs y discos) y, además, el catálogo de **cintas TSX** de tsx.eslamejor.com. Muestra los resultados juntos en la lista del navegador (hasta 112), con *Conectando*, *DNS*, *Abriendo* y *Enviando GET* mientras trabaja. La lista se maneja como la de la tarjeta: scroll, marquee y búsqueda con `/`.
3. Sobre un resultado: **RETURN** lo descarga, **F** hace otra búsqueda, **ESC** o **BACKSPACE** vuelven al navegador normal (el menú vuelve a leer la tarjeta).
4. La descarga va a `FHUNT` sector a sector, con el nombre completo de File-Hunter como nombre largo (VFAT) y un nombre corto único `BASE~N` en 8.3; el nombre largo conserva la etiqueta del mapper que File-Hunter conoce, por ejemplo `[SCC].rom`. Se comprueba el CRC al terminar. Si el fichero ya está en `FHUNT` con el mismo tamaño no se vuelve a bajar: la carpeta hace de caché.
5. Al terminar, se lanza solo, como cualquier ROM o disco de la tarjeta. Las **cintas** se lanzan con la cinta virtual ([capítulo 11](11-cinta.md)).

Se admiten **ROMs de hasta 8 MB** (megaram de la máquina, [capítulo 05](05-roms-mappers.md)). Un fichero descargado se queda en `FHUNT` para siempre: la siguiente vez está en el navegador como uno más.

La carpeta `WIFI` del contenido base de la tarjeta (`base/WIFI/` del contenido de [MSX SD Maker](https://github.com/Papipapito/SD_Maker)) trae las utilidades de red para MSX-DOS: HGET, GETURL, TCPIP, TELNET, TCPCON, SNTP, FTP, SFTP, TFTP y `FH.COM`, el cliente de File-Hunter para DOS.

### Límites

- La partición tiene que ser **FAT16**. Con FAT32 el menú lo dice y no descarga (el navegador sí lee FAT32; el escritor de File-Hunter, no).
- La carpeta `FHUNT` tiene que existir; se crea desde MSX-DOS con `MKDIR FHUNT`. El menú no la crea.
- `FHUNT` ocupa un solo cluster, y cada fichero gasta una entrada corta más las del nombre largo (13 caracteres por entrada, hasta 195 caracteres). Cuando no cabe, el menú da un error limpio: hacer sitio o borrar desde DOS.
- Si se vuelve a descargar un nombre que ya existe con distinto tamaño, la cadena de clusters vieja queda huérfana; se recupera con una comprobación del sistema de ficheros desde el PC.

### Mensajes

| Mensaje | Qué pasa |
|---|---|
| FH: sin UNAPI | El MSX no ve el driver de red. Con la S3: no está, no arrancó antes que el MSX, o los hilos del CAM1 están mal |
| FH: sin red (tecla W) | No hay red: sin cable y con la S3 sin conectar a ninguna WiFi |
| FH: fallo DNS / sin conexion | La red está, internet no, o File-Hunter no responde |
| FH: sin resultados | Ningún fichero con ese texto |
| FH: preparando... / FH: bajando | Estados normales de la descarga |
| FH: timeout de descarga / respuesta API rara | La descarga se cortó. Reintentar |
| FH: error SD / SD llena / CRC MAL / E0 / E1 | Problema al escribir en la tarjeta de TF2. Comprobar la tarjeta, [capítulo 03](03-tarjeta-sd.md) |
| Falta FHUNT (MKDIR en DOS) | No existe la carpeta |
| FH: FHUNT rara | La carpeta existe pero su directorio no es como el menú espera (o está llena) |
| FH: la SD es FAT32 (v1 solo FAT16) | La partición no es FAT16 |

## 5. Diagnóstico rápido

Si algo no va, en este orden:

1. **¿Hay IP?** Abre el panel **F12** y mira la fila *Red*, o la OLED. Con cable debe salir una IP; si dice *sin cable o sin IP*, el cable no tiene enlace o el router no da DHCP. Por WiFi, la IP de la S3 la enseña la página de [actualización](12-actualizar.md) tras una búsqueda.
2. **Con la S3, su pantalla.** *Sin WiFi*: la red no está configurada o no llega; tecla **W** (con el cable de J3 quitado). *Conectado*: la red está bien.
3. **El punto de actividad** de la pantalla de la S3. Si no parpadea cuando el MSX usa la red, el problema está en los hilos o en el cable, no en la WiFi.
4. **Los hilos TX y RX cruzados.** Es el error más común al montar: CAM1-26 recibe del TX de la S3 (verde, GPIO16) y CAM1-28 manda al RX de la S3 (rojo, GPIO17).
5. **La masa.** S3 alimentada por su USB-C y sin el GND (CAM1-38): el enlace no va, o va a ratos.
6. **El orden de encendido.** El driver del ESP se inicializa al arrancar el MSX; si la S3 se enchufa después, `FH: sin UNAPI`. Encender la S3 antes, o reiniciar el MSX con el botón de reset del MSX (K2).
7. **La barra de turbo.** Si con F11 la pantalla de la S3 sigue en *Normal*, falta el hilo de CAM1-30; la red funciona igual sin él.
8. **Durante una actualización por WiFi** el MSX no tiene red: el companion usa la S3 y la suelta al acabar.

Otros síntomas, en el [capítulo 10](10-problemas.md).
