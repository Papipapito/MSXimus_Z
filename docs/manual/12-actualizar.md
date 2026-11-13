# 12. Actualizar por la red

El MSXimus Z se actualiza solo, por la red: desde el panel **F12**, sin PC, sin cable JTAG y sin sacar la tarjeta. La placa pregunta cuál es la última versión, enseña lo que trae, la baja, la graba en su memoria QSPI y la comprueba. Este capítulo cuenta cómo se usa; cómo funciona por dentro (ranuras, registro, firma, arranque) está en la [referencia técnica](../tecnica/11-actualizacion.md).

## 1. Qué hace falta

- **La instalación en la QSPI.** La actualización escribe en la memoria QSPI de la placa, así que necesita que la máquina arranque de ella (**SW1 en ON-OFF**, [capítulo 02](02-instalacion.md)). Con el sistema arrancado por JTAG, la página se abre y busca, pero no puede reiniciar en la imagen nueva: en la esquina inferior derecha pone `JTAG` en vez de `QSPI`, y **R** contesta *"SW1 en QSPI y apaga"*. Con el sistema arrancado desde la microSD de TF1 la página es otra (sección 10): sirve para instalar la imagen de fábrica en la QSPI, sin Vivado.
- **Red**, de una de las dos maneras del [capítulo 07](07-wifi-file-hunter.md):

| Camino | Qué tarda | Qué pasa con el MSX |
|---|---|---|
| **Cable Ethernet** en J3 | Segundos | Nada: la red del MSX es la misma |
| **WiFi** de la ESP32-S3 del CAM1 (con la red ya configurada con la tecla **W**) | 3-4 minutos por imagen | El *companion* toma prestada la S3 mientras dura la búsqueda o la descarga: **el MSX se queda sin WiFi ese rato** |

Si hay cable con enlace, se usa el cable. Si no, la S3. Sin ninguno de los dos, la página dice *"Sin red: cable o WiFi"*; si la S3 está pero no conecta a la WiFi, *"La WiFi no conecta"*.

## 2. La página de actualización

**F12** abre el panel de estado ([capítulo 04, §10](04-menu.md)) y el MSX queda congelado detrás. En su pie hay tres botones: **U** *Actualizar*, **P** *Perfiles* y **F12** *Salir*. **U** abre la página **Actualizar por red** (*Network update*, en el idioma del menú de la imagen instalada); **ESC** vuelve al panel y **F12** lo cierra.

> Hasta la Z1.2.13 el panel F12 no se veía con el HDMI en el V9990 (Pausa vuelve al V9968); desde la Z1.3 sale en todos los modos ([capítulo 09](09-video.md)).

La página, de arriba abajo:

| Bloque | Qué enseña |
|---|---|
| **Instalada** | La versión que corre y su variante (`N2.1.4 ES`, `N3.0 EN`...), con `beta` en naranja si es del canal beta. Debajo, de dónde arrancó: *ranura A · de fábrica*, *ranura B · actualización* o *ranura B · a prueba* (en amarillo, hasta que se confirma). Si hay una B grabada que todavía no ha arrancado, *B: versión sin probar*; si no llegó a arrancar, *versión no arrancó* |
| **Servidor** | Con la búsqueda hecha, el nombre del servidor y, en el marco: la **versión** disponible y su **fecha**, el **tamaño** de la imagen en MB con *firma* y una marca verde (la firma del manifiesto ha cuadrado), y hasta tres líneas de **notas** |
| **Canal** | *Oficial* o *Beta* (§6): de dónde se busca la versión |
| **Nextor / Idioma** | Las variantes que ofrece esa versión (§5) |
| **Estado** | *Estás al día*, *Hay una versión nueva*, *Lista para instalar*, la barra de progreso o el error |
| **Pie** | Una `IP`, con `WiFi` detrás si va por la S3, o *sin red: cable o WiFi*; y `QSPI` o `JTAG` |

### Teclas de la página

| Tecla | Qué hace |
|---|---|
| **U** | Busca la última versión (*Buscando el servidor…*, *Leyendo la versión…*). Con un error, la vuelve a intentar |
| **I** | Instala la versión que enseña la página. Solo sale cuando hay algo que instalar |
| **R** | Reinicia la placa en la ranura B. Si la B está grabada pero sin probar, es la prueba |
| **F** (dos veces) | Vuelve a la imagen de fábrica (§7). Solo sale cuando hay una B grabada |
| **← →** o **N** | Elegir Nextor 2 o Nextor 3 (§5) |
| **↑ ↓** o **L** | Elegir castellano o inglés (§5) |
| **B** | Cambia de canal, *Oficial* o *Beta*, y busca en el nuevo (§6) |
| **ESC** | Vuelve al panel. Con una descarga en marcha lo dice el botón: *Ocultar (sigue)* |

## 3. Actualizar, paso a paso

1. **F12**, luego **U**. La página busca la versión disponible. Si ya estás en la última, dice *Estás al día* en verde.
2. Si hay una nueva, en amarillo *Hay una versión nueva*, con sus notas, su tamaño y la marca de la firma. Si no te convence, **ESC**.
3. **I**. La barra recorre cuatro pasos: **Bajar**, **Borrar**, **Grabar**, **Verif** (*Get / Erase / Write / Check* en inglés). Al bajar muestra los MB y los KB/s. En los dos últimos pasos pone *No apagues la placa*; si se va la luz a media grabación, al volver a encender arranca la imagen de fábrica.
4. Cuando acaba: *Grabada en la ranura B*. **R** reinicia con ella. Si apagas y enciendes en vez de pulsar **R**, la placa la prueba sola en el siguiente arranque.
5. La imagen nueva arranca. Cuando el MSX lee su tarjeta, la placa la **confirma** y desde entonces es la que arranca siempre. En la página aparece como *ranura B · actualización*.

La descarga no se fía del canal: el manifiesto de la versión va firmado y la imagen se comprueba contra la suma que lleva (tamaño, SHA-256 y cabecera de arranque) antes de grabar y, grabada, se vuelve a leer entera. La clave pública con la que se comprueba está en `fpga/zynq/ota/ota_publica.pem`; la privada no está en ningún repositorio.

## 4. De dónde sale la versión

- **msx.barcelona**, por TLS. Es el servidor de las versiones. Con la S3, el certificado se valida contra las 16 autoridades que lleva su firmware.
- **Antes**, la placa pregunta por UDP (difusión al puerto 9474 de la red local) si hay un **servidor de desarrollo** en algún PC (`fpga/zynq/ota/ota_servidor.py`); si alguien contesta, la actualización sale de ahí y el servidor lo dice en el marco con `(PC)`. Si nadie contesta, msx.barcelona. Para un uso normal no hace falta saberlo.
- **GitHub lleva las versiones grandes** (con los cuatro `BOOT_*.bin` y MSXimusZboot, el programa de la tarjeta de instalación) y **los arreglos salen solo por la red**. Se instala la versión grande de GitHub (o la que ya se tenga) y con **F12 → U** se llega a la última.

## 5. Las cuatro variantes

Cada versión se publica en cuatro imágenes: **Nextor 2** o **Nextor 3**, cada una con los menús en **castellano** o en **inglés**. La página enseña dos filas con una pastilla cian en la elegida: *Nextor* y *Idioma*, y solo aparecen las opciones que esa versión trae.

- **← →** (o **N**) cambia de Nextor; **↑ ↓** (o **L**), de idioma. La elección vale para la instalación que sigue y no es definitiva: se puede volver a cambiar con otra pasada de **U**, **←/→**, **I**.
- Al cambiar el idioma, la página avisa de *Menús en inglés* o *Menús en español*.
- **Cambiar de Nextor pide su `NEXTOR.SYS` en la tarjeta de TF2.** La página lo avisa en naranja (*Cambias a Nextor ... / Sin su NEXTOR.SYS en la SD no arrancará MSX-DOS*). [MSX SD Maker](03-tarjeta-sd.md) prepara la tarjeta con el de cada uno.

## 6. El canal beta

Además de las versiones oficiales hay un **canal beta** con builds de prueba de funciones nuevas. Las betas salen en las mismas cuatro variantes que las oficiales y pueden fallar: son para probar, no para el uso de cada día.

- **B** en la página cambia la fila *Canal* de *Oficial* a *Beta* (o al revés) y busca enseguida la versión de ese canal.
- Si hay una beta, la página dice *Beta: experimental*; **I** la instala como cualquier otra versión, en la ranura B, con la misma firma y las mismas comprobaciones.
- La versión instalada lleva `beta` al lado del número mientras sea una beta.
- **Para volver a la oficial**: **B** hasta *Oficial*; la página dice *Vuelta a la oficial* aunque la oficial sea más antigua que la beta, e **I** la instala. Otra forma es volver a la de fábrica (§7).

## 7. Si algo sale mal: las dos ranuras

La QSPI guarda dos imágenes:

| Ranura | Qué es |
|---|---|
| **A** | La de **fábrica**: la que se grabó al instalar la placa. La actualización **no la toca nunca** |
| **B** | La que baja la actualización |

- Una B recién grabada **se prueba una vez**. Si el MSX llega a leer la tarjeta (o, sin tarjeta, tras unos 20 segundos con el Z80 vivo), la placa la **confirma** y arranca siempre con ella.
- Si **no arranca** (pantalla negra, se queda a medias, el MSX no lee la tarjeta), **apaga y enciende**: vuelve la A, y su página lo dice con *versión no arrancó*. **R** la prueba otra vez; la placa da tres intentos en total.
- Para **volver a la de fábrica** incluso con una B buena: **F12 → U**, **F** (la página pide *F otra vez: a la de fábrica*), **F** de nuevo (*Fábrica elegida: R reinicia*) y **R**. La B se olvida; una nueva actualización la vuelve a grabar.

## 8. Errores que enseña la página

| Mensaje | Qué pasa |
|---|---|
| Sin red: cable o WiFi | No hay cable con IP ni S3 que conteste |
| La WiFi no conecta | La S3 está, pero no tiene WiFi: configúrala con la tecla **W** ([capítulo 07](07-wifi-file-hunter.md)) |
| Sin conexión al servidor | La red está, pero no se llega a msx.barcelona (DNS, TLS o corte). Reintentar con **U** |
| La actualización no está | El servidor no tiene el manifiesto o la imagen |
| Firma no válida | El manifiesto no está firmado con la clave de la placa. No se instala nada |
| No es para esta placa | La versión es de otra placa |
| Descarga dañada | El tamaño, la suma o la cabecera de la imagen no cuadran. Reintentar |
| Datos de versión no válidos / Respuesta no válida | El servidor devolvió algo que la placa no entiende |
| Error al grabar la QSPI | La relectura no coincide con lo bajado. Reintentar |
| SW1 en QSPI y apaga | La placa no arrancó de la QSPI (modo JTAG): no puede reiniciar en la ranura B |
| No se puede reiniciar / No se puede probar la B | Apaga y enciende |

En todos los de red, **U** lo intenta otra vez.

## 9. Perfiles del PL

Una versión puede traer además **perfiles**: versiones del PL con otros chips u otra máquina (Música, Dual, Turbo R y Turbo R V9990), que se guardan en la microSD de TF1 y se cargan desde la página de perfiles ([capítulo 04, §10](04-menu.md)). Cada versión del sistema necesita los suyos: un perfil de una versión anterior no se carga con la nueva. Por eso, al instalar una versión, la página de actualización avisa con *Perfiles viejos: tecla P* si la tarjeta tiene perfiles que el servidor tiene más nuevos, y **P** lleva a la vista del servidor.

**F12 → P → S** (o **P** en la página de actualización) abre la vista **Servidor** de la página de perfiles: busca igual que la actualización, enseña el canal (*Oficial* o *Beta*) y la lista de perfiles de esa versión con su estado frente a la tarjeta:

| Estado | Qué significa |
|---|---|
| **al día** (verde) | Ya está en la tarjeta, de esta versión |
| **nuevo** (cian) | No está en la tarjeta |
| **serie** (naranja) | Hay uno en la tarjeta, de otra versión del sistema: no se cargaría |
| **versión** (naranja) | Hay uno en la tarjeta, de la misma serie pero otra versión |

| Tecla | Qué hace |
|---|---|
| **↑ ↓** | Elegir (debajo salen su tamaño y su serie) |
| **Intro** | Baja el elegido y lo instala en la tarjeta |
| **A** | Baja **todos los que falten o estén viejos**: es lo que hace falta tras cada actualización |
| **U** | Busca otra vez |
| **B** | Cambia de canal y busca en el nuevo |
| **T** | Prepara la tarjeta de TF1 si está vacía, a medias o con los directorios rotos (con otros datos, **B** en la vista de la tarjeta: [capítulo 03](03-tarjeta-sd.md), sección 2) |
| **S** o **ESC** | Vuelve a la vista de la tarjeta. Con una descarga en marcha sigue |

Los perfiles de una versión que **aún no has instalado** se ven pero no se bajan (*Instala antes la versión nueva del sistema*): instala la versión (**I**) y entonces **P**, o se sustituirían los que carga la versión de ahora. Al terminar de bajar, el panel se abre solo en esa vista y deja el MSX en pausa el segundo que tarda en guardar el perfil; ESC o F12 lo cierran. Antes de bajar nada la placa comprueba que haya tarjeta en TF1, partición de perfiles y un hueco libre; si falta algo, lo dice (*No hay tarjeta*, *La tarjeta no tiene partición de perfiles: T la crea*, *No queda hueco: borra un perfil*) y no baja nada. Un perfil lleva su SHA-256 en el manifiesto firmado, igual que las imágenes: si llega alterado sale *Descarga dañada*. Actualizar el sistema y bajar un perfil no se pueden hacer a la vez.

Más problemas, en el [capítulo 10](10-problemas.md).

## 10. Con la placa arrancada desde SD: instalar la imagen de fábrica

Con SW1 en SD (arranque del `BOOT.bin` de la microSD de TF1) **F12 → U** no busca versiones por la red: enseña la tarjeta *BOOT.bin de la SD* y graba la **ranura A** de la QSPI con ese fichero, sin Vivado. Es la primera instalación de una placa nueva ([capítulo 02, §4.1](02-instalacion.md)).

| Tecla | Qué hace |
|---|---|
| **A** | Lee el `BOOT.bin` de la raíz de la FAT32 o FAT16 de TF1 y comprueba que es de esta placa. Enseña su versión y su variante |
| **A, A** | Con el fichero ya leído, dos veces seguidas (otra tecla de por medio la desarma): borra y graba la ranura A (*Leer, Borrar, Grabar, Verif*) y la relee comparándola con lo leído. Al acabar: *Grabada en la ranura A. Apaga y pon SW1 en QSPI* |
| **ESC** | Vuelve |

No hay que apagar mientras graba. Si se va la luz, la ranura A queda a medias y la QSPI no arrancaría, pero la SD sí: se vuelve a arrancar de ella y se repite. La grabación borra también el registro de la ranura B: una B instalada antes no vuelve a arrancar y se baja otra vez por la red cuando haga falta.

Errores de esta página: *No hay tarjeta en la TF1*, *La TF1 no es FAT16 ni FAT32* (hace falta una partición FAT32 o FAT16, con o sin tabla de particiones; la línea de debajo dice lo que hay: `MBR 0E 00 00 00 P1:FAT12` es una tarjeta con tabla cuya primera partición está en FAT12, `Sin MBR: exFAT` una tarjeta entera en exFAT, `Sector 0 sin 55AA` una tarjeta vacía o sin formato), *No hay BOOT.bin en la TF1* (en la raíz, con ese nombre), *BOOT.bin de tamaño raro* (entre 4 KB y 8 MB), *BOOT.bin dañado en la TF1*, *Error leyendo la TF1*, *No es para esta placa* y *BOOT.bin no válido*. **A** lo intenta otra vez.
