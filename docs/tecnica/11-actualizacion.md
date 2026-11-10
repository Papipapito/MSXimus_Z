# 11. La actualización por red

Cómo se instala una versión nueva en la placa sin JTAG: dónde se guarda, cómo se comprueba que es legítima, cómo se arranca y qué pasa si falla. Cuatro piezas: la QSPI con dos ranuras (A y B), el FSBL propio que salta de una a otra, el companion (`ota.c`) que busca, descarga, graba y confirma, y las herramientas del PC que preparan y publican cada versión. El uso desde el teclado está en [el manual](../manual/12-actualizar.md).

Todo el código del lado de la placa está en `fpga/zynq/arm/companion/` (`ota.c`, `ota.h`, `ota_clave.h`, `qspi_cfg.c`) y `fpga/zynq/arm/fsbl/fsbl_hooks.c`; el del PC, en `fpga/zynq/ota/`.

## 1. Disposición de la QSPI

La flash es una de 16 MB (clase W25Q128, órdenes de 3 bytes de dirección: `03` leer, `06` WREN, `05` RDSR, `02` programar página de 256 B, `20` borrar 4 KB, `D8` borrar 64 KB). El companion la maneja con el driver `xqspips` en modo IO, con la orden sondeada y el CS forzado, a 25 MHz (200 MHz / 8). `qspi_cfg.c` es el único dueño de la QSPI: `ota.c` la usa a través de `qspi_open`, `qspi_read`, `qspi_busy`, `qspi_erase64k_start`, `qspi_erase4k_start`, `qspi_prog_start` y `qspi_wait`. Las órdenes `_start` no esperan (un borrado de 64 KB tarda hasta unos 2 s) y `ota_poll` mira `qspi_busy()` en cada vuelta del bucle.

| Dirección | Tamaño | Contenido |
|---|---|---|
| 0x000000 | hasta 8 MB | **Ranura A**: el `BOOT.bin` «de fábrica», el que se graba por JTAG (`tools/qspi_program.tcl`). La actualización nunca la toca |
| 0x800000 | hasta 0x7F0000 B (8 323 072) | **Ranura B**: el `BOOT.bin` que baja el companion. Un `BOOT.bin` actual ocupa unos 6,2 MB |
| 0xFFE000 | 4 KB | **Registro de la actualización**: qué hay en la B y si ya arrancó bien (apartado 2) |
| 0xFFF000 | 4 KB | **Sector de ajustes** (`MSXC`): configuración y niveles del mezclador, que guarda el menú del MSX |

El resto del último bloque de 64 KB (0xFF0000..0xFFDFFF) no se usa. La B termina antes de él, así que un borrado de bloques de la B nunca alcanza el registro ni los ajustes.

**Sector de ajustes.** 16 bytes: `"MSXC"` (+0), `config1` (+4), `config2` (+5), turbo 0/1 (+6), ganancia 0..7 (+7), suma de control (+8, XOR de los cuatro bytes anteriores con 0x5A), niveles del mezclador (+9..+12, siete canales de 4 bits, little-endian), suma de los niveles (+13, XOR con 0xA5), opciones de vídeo (+14, bit 0 = el V9968 a pantalla completa en 4:3 con Scale3x), su comprobación (+15 = +14 ^ 0x3C; con 0xFF, 0xFF queda en 16:9), el **perfil al arrancar** (+16..+23: el id del perfil, ASCII con relleno de ceros, todo a cero = ninguno; +24 = XOR de esos 8 bytes con 0x6B; un bloque de antes lleva 0xFF ahí, no pasa la suma y vale «ninguno») y relleno 0xFF. Las tres rutinas que graban el sector (`cfg_poll`, `cfg_video43_cambia` y `cfg_perfil_fija`) escriben los 32 primeros bytes, porque el borrado es de 4 KB. `cfg_load()` lo lee al arrancar y siembra el PL con el MSX aún en reset (`MBOX+0x1C` bits 28-8 y `MBOX+0x24`); `cfg_poll()` lo graba cuando el PL cambia el bit de «guardar» de `MBOX+0x70`. Un bloque con `config1 = 0` o con la suma mal se ignora y la máquina arranca con los valores por defecto. La actualización no lo borra: los ajustes sobreviven a cualquier versión.

## 2. El registro (0xFFE000)

Una página de 256 B que lee el FSBL y el companion. Los enteros son little-endian.

| Offset | Tamaño | Campo |
|---|---|---|
| +0x00 | 4 | Firma `"MOTA"` |
| +0x04 | 1 | Formato (1) |
| +0x08 | 4 | Serie de la imagen grabada en la B |
| +0x0C | 4 | Tamaño de la imagen en bytes (como mucho 0x7F0000) |
| +0x10 | 4 | Desplazamiento de la B (0x800000) |
| +0x14 | 32 | SHA-256 de la imagen |
| +0x34 | 16 | Versión (texto, 0 final) |
| +0x44 | 16 | Variante (`nextor214`, `nextor3`, `nextor214-en`, `nextor3-en`) |
| +0x54 | 4 | CRC-32 (polinomio 0xEDB88320) de los bytes +0x00..+0x53 |
| +0x80..+0x82 | 3 | Intentos de arranque de la B: 0xFF = libre, 0x00 = gastado |
| +0x88 | 1 | Confirmada: 0xFF = no, 0x00 = sí |

Los bytes de intentos y de confirmación se programan una sola vez, de FF a 00, sin borrar el sector (una QSPI permite poner bits a 0 sin borrar). El registro es válido si la firma, el formato y el CRC cuadran, el desplazamiento es 0x800000 y el tamaño no pasa del máximo.

## 3. El arranque: BootROM, FSBL y ranura B

1. El BootROM del Zynq carga **siempre** la ranura A (el registro `MULTIBOOT` del PS vale 0 tras el encendido).
2. El FSBL de la A es el propio de la máquina (`arm/fsbl/`, el `zynq_fsbl` de Xilinx de Vivado 2019.2 tal cual, con `ps7_init` del diseño y consola por la UART1). Solo cambia `fsbl_hooks.c`: en `FsblHookBeforeBitstreamDload`, antes de cargar el bitstream, mira el registro. Si **todo** esto se cumple: arranque desde QSPI, `MULTIBOOT` = 0 (se está en la A), registro válido, byte de confirmación = 0x00 y cabecera de arranque de la B válida (firma `AA995566h` / `584C4E58h` en +0x20/+0x24 y suma de la cabecera, la de UG585 tabla 6-3), entonces pone `MULTIBOOT` = 0x100 (0x800000 / 32 KB) y reinicia el PS. El BootROM carga entonces el FSBL de la B y este, al ver `MULTIBOOT` ≠ 0, carga sus particiones desde 0x800000. El salto cuesta unos 0,1 s. Aquí el FSBL solo lee la QSPI (ventana lineal 0xFC000000).
3. Una B **sin confirmar** no la arranca el FSBL. La prueba la lanza el companion de la A (apartado 7).
4. Con la placa en modo JTAG o en SD no se reinicia nada: no hay BootROM de QSPI que cargue la B. `ota_arranque()` lo sabe por el registro de modo de arranque (`0xF800025C`, bits 2:0 = 1 para QSPI) y el OSD pide SW1 en QSPI para probar.

Si el FSBL no ha saltado a la B estando ya confirmada (un FSBL anterior en la A, por ejemplo), `ota_arranque()` lo hace él mismo desde el companion.

### Qué lleva cada imagen

Cada `BOOT.bin` es completo: FSBL, bitstream, companion, buzón a cero, pack de BIOS, YRW801 y la partición `ota_info` (la hace `arm/boot/make_boot.sh`):

| Partición | Destino en la DDR |
|---|---|
| `fsbl.elf`, `msximus_zynq.bit`, `companion.elf` | (arranque) |
| `zeros.bin` | 0x1FF00000 (buzón y SDBOX a cero) |
| `pack.bin` | 0x10F00000 (pack de BIOS, 512 KB) |
| `yrw801.rom` | 0x0F000000 (ROM de ondas, 2 MB) |
| `ota_info.bin` | 0x00E10000 (256 B) |

`ota_info` es texto: `MOTI1\nversion=…\nserie=…\nvariante=…\nidioma=es|en\nplaca=zynq7020-mini\nfecha=…\ncanal=oficial|beta\n`. `make_boot.sh` toma `OTA_VERSION` (hasta 15 caracteres), `OTA_SERIE` y `OTA_CANAL` (`oficial` por defecto, o `beta`; desde la Z1.3) del entorno y deduce la variante del pack: `nextor3` si contiene `NEXTORv3_DRIVER`, `nextor214` si no, con sufijo `-en` si el menú es el inglés (`MSXimus - Settings`). Es la **última** partición de la imagen. El companion la lee al arrancar (`info_leer`) para saber qué versión, serie y variante corre y a qué idioma habla el OSD, y escribe un 0 en su primer byte: tras un reinicio la DDR conserva la de la imagen anterior y no debe heredarse.

Por eso una actualización cambia **todo** a la vez: el bitstream, el companion, el menú y las ROMs de la variante. Lo único que persiste entre versiones son los ajustes (0xFFF000) y la tarjeta SD.

## 4. El manifiesto y la firma

### 4.1 Formato

`manifiesto.txt` es ASCII con saltos de línea LF:

```
MSXIMUS-OTA 1
placa=zynq7020-mini
version=Z1.2.13
serie=2026102707
fecha=2026-10-28
notas=V9990: entrelazado fijo
notas=microSD TF1 = disco 2
notas=File Hunter 8 MB
imagen=nextor214 BOOT_Z1.2.13_nextor214.bin 6159424 85fc184c…
imagen=nextor3 BOOT_Z1.2.13_nextor3.bin 6159424 b0ee7f6f…
imagen=nextor214-en BOOT_Z1.2.13_nextor214-en.bin 6159424 a680e7d9…
imagen=nextor3-en BOOT_Z1.2.13_nextor3-en.bin 6159424 488f8b0c…
perfil=SONIDO Z1.3.2 PERFIL_SONIDO_Z1.3.2.mxp 1317974 3e1c4d0b… 2664960 2026103091
firma=<128 caracteres hexadecimales>
```

| Campo | Regla |
|---|---|
| Primera línea | Exactamente `MSXIMUS-OTA 1` |
| `placa` | `zynq7020-mini`; si es otra, el companion la rechaza («No es para esta placa») |
| `version` | Texto de 1 a 15 caracteres `A-Za-z0-9._-`. Es lo que ve el usuario |
| `serie` | Entero creciente (convención `AAAAMMDDNN`). **Es lo que decide si hay algo nuevo** |
| `fecha` | `AAAA-MM-DD` |
| `notas` | Hasta 3 líneas de 25 columnas como máximo (caben en la tarjeta del OSD) |
| `imagen` | Hasta 4: `<variante> <fichero> <tamaño> <sha256>`. Variantes: `nextor214`, `nextor3` (castellano) y `nextor214-en`, `nextor3-en` (inglés). El fichero lleva solo `A-Za-z0-9._-`; el tamaño va de 0x1000 a 0x7F0000; el SHA-256 son 64 caracteres hex. El nombre por convención es `BOOT_<version>_<variante>.bin` |
| `perfil` | Hasta 6 (los huecos de la tarjeta): `<ID> <versión> <fichero> <tamaño> <sha256> <tamaño del .bin> <serie>`. `ID`: 1 a 8 caracteres `A-Z 0-9 _ -`; `versión`: la misma regla que `version`; el fichero, el `.mxp` entero (`PERFIL_<ID>_<versión>.mxp` por convención), con su tamaño y SHA-256; tamaño del bitstream descomprimido; y la **serie del sistema** para el que se hizo, que tiene que ser la de la línea `serie` (apartado 9). Las placas con un companion de antes de los perfiles saltan estas líneas, como cualquier otra que no conocen (`manif_leer` solo mira `placa`, `version`, `serie`, `fecha`, `canal`, `notas=` e `imagen=` con una variante conocida; `campo()` está anclada al principio de línea), y la firma cubre el texto entero |
| `firma` | Última línea, sin nada detrás salvo el LF: r‖s de ECDSA P-256 (32 + 32 bytes) en hexadecimal |

Qué ofrece el companion (`decide()`): si el registro tiene ya grabada esa serie y esa variante y se corre desde la A, «lista para arrancar»; si la serie del manifiesto es mayor que la que corre, o la variante elegida es otra, «hay actualización»; si no, «al día». La imagen que se propone es la del manifiesto con la **variante que corre**; con las flechas (o N y L) el usuario cambia de Nextor o de idioma, y eso permite instalar otra variante con la misma serie.

### 4.2 La firma

- Algoritmo: **ECDSA sobre P-256 con SHA-256**. Se firma el texto del manifiesto desde el principio hasta el salto de línea que precede a `firma=`, inclusive.
- La clave pública va **compilada** en el companion como el punto sin comprimir `04‖X‖Y` (65 bytes) en `companion/ota_clave.h`; la misma clave, en formato PEM, está en `fpga/zynq/ota/ota_publica.pem` para comprobar a mano una firma. Las dos las escribe `fpga/zynq/ota/ota_claves.py`.
- La clave **privada** no está en ningún repositorio. Vive fuera de ellos, en una carpeta del usuario del PC de publicación (o donde diga la variable `MSXIMUS_OTA_CLAVE`), y `ota_claves.py` no la sobrescribe si ya existe. Quien la tenga puede firmar un `BOOT.bin` que las placas aceptan; si se pierde, las placas ya instaladas solo aceptan versiones firmadas con ella, así que habría que regrabarlas por JTAG con una clave nueva.
- El companion verifica con Mbed TLS (`mbedtls_ecdsa_verify` sobre `MBEDTLS_ECP_DP_SECP256R1`) antes de mirar ningún otro campo. Una firma mala da «Firma no válida».

### 4.3 Integridad de cada imagen

La firma cubre las líneas `imagen=`, y cada una lleva el tamaño y el **SHA-256** del `BOOT.bin`. Eso hace que la firma proteja también las imágenes, y por eso el transporte no necesita ser de fiar. Al terminar la descarga el companion comprueba, en este orden:

1. Tamaño recibido = tamaño del manifiesto.
2. SHA-256 (calculado al vuelo mientras llegaban los datos) = el del manifiesto.
3. Cabecera de arranque: firma `AA995566h` / `584C4E58h` y suma de la cabecera.
4. Partición `ota_info` al final de la imagen, con la misma `serie` que el manifiesto. Así una imagen no puede pasar por otra versión.

Cualquier fallo se enseña como «Descarga dañada» y no se graba nada.

## 5. El transporte

La búsqueda y la descarga las lleva `ota.c` con un cliente HTTP/HTTPS propio, sin bloquear nunca el bucle del companion (una máquina de estados `DNS → conexión → TLS → petición → cabecera → cuerpo`). Hace `GET` HTTP/1.1 con `Connection: close` y `User-Agent: MSXimus-Z/OTA`, sigue hasta 4 redirecciones (`Location` de hasta 2 KB), exige `Content-Length` (no entiende `chunked`), da por perdida la conexión tras 10 s sin responder al abrir (por cable) o 20 s sin datos, y rechaza una respuesta mayor que el tamaño que espera.

**Por cable** (si `esp_net_ok()`: enlace e IP). lwIP 2.1.1 sobre el GEM0 y, para `https`, **Mbed TLS 3.6** (`esp_tls.c`, TLS 1.2 cliente). Sin verificar el certificado del servidor: la integridad la da la firma del manifiesto, no el canal. El heap de Mbed TLS (768 KB) está en una región con caché; la imagen se descarga a una zona propia de la DDR (0x01000000, 9 MB con caché, solo la toca este core): la imagen desde el principio, y a partir de +0x800000 el manifiesto (8 KB), las cabeceras (8 KB), el búfer de relectura (16 KB), el registro y el contexto de SHA-256.

**Sin cable, por la WiFi del ESP32-S3 del conector CAM1** (`s3_link.c`). El PL une ese ESP con la UART1 del PS (`MBOX+0x1C` bit 4) y deja al MSX sin él mientras dura la búsqueda o la descarga; el companion le habla como lo haría el driver UNAPI del MSX (el mismo protocolo que imita `esp_link.c`, del otro lado) y el ESP hace el DNS, el TCP y el TLS. Ahí sí se pide validar el certificado (el firmware de serie trae las raíces) y, si el ESP no puede, se repite sin validar. La UART va a 862 069 baud. La S3 vuelve al MSX en cuanto no hace falta.

### Dónde mira

1. **Servidor de desarrollo en la red local.** Al pulsar U, la placa manda por difusión UDP al puerto **9474** el texto `MSXIMUS-OTA? zynq7020-mini`. Por cable, a 255.255.255.255 y repetido a los 300 ms, con 800 ms de espera; por la S3, a 255.255.255.255 y a la difusión dirigida de su red, con 1,5 s de espera. Un PC que ejecute `ota_servidor.py` contesta `MSXIMUS-OTA <url>`, con una URL `http://` o `https://` sin espacios que acabe en `/` (por ejemplo `http://192.168.1.20:8000/zynq/`). Es lo que se usa para probar una versión en placa antes de publicarla. La placa muestra en el OSD la IP del PC con la marca «(PC)».
2. **Si nadie contesta**: `https://msx.barcelona/wp-content/ota/zynq/` (constante `OTA_URL` en `ota.c`).

En cualquiera de los dos casos pide `<url>manifiesto.txt` y, si el usuario instala, `<url><fichero de la imagen>`.

## 6. Descarga y grabación

El flujo, en teclas del OSD (la página de la actualización se abre con **U** desde el panel F12; **ESC** vuelve al panel):

| Tecla | Acción |
|---|---|
| U | Buscar: difusión UDP, manifiesto, comprobación de firma, decisión |
| I | Instalar la imagen elegida (solo si hay actualización) |
| ← → o N | Cambiar de Nextor (2.1.4 / 3.0) |
| ↑ ↓ o L | Cambiar de idioma (castellano / inglés) |
| R | Reiniciar: prueba la B (gasta un intento) o, si ya está confirmada, la arranca |
| F (dos veces) | Volver a la de fábrica: borra el registro |

`tools/ota.tcl` manda esas teclas por JTAG (`MBOX+0x3C`) y enseña el final del log del ARM, para probar sin teclado.

**Instalar.** Con **I**, el companion baja el `BOOT.bin` a la DDR calculando el SHA-256 al vuelo y hace las comprobaciones del apartado 4.3. Después graba la B por pasos que avanzan una pequeña tanda cada vuelta del bucle:

1. **Borra el registro** (sector de 4 KB). Desde este instante, un corte de corriente deja la placa arrancando la A: la B ya no está «confirmada».
2. Borra los bloques de 64 KB de la B que ocupa la imagen.
3. Programa páginas de 256 B (16 por vuelta o 3 ms, lo que llegue antes).
4. **Relee** toda la B, la compara byte a byte con lo descargado y recalcula el SHA-256 contra el del manifiesto.
5. Escribe el registro nuevo: serie, tamaño, desplazamiento, SHA-256, versión, variante, CRC, con los bytes de intentos y de confirmación sin gastar.

Si falla la grabación o la relectura, el OSD dice «Error al grabar la QSPI» y el registro sigue borrado (se arranca la A).

## 7. El ciclo de prueba y confirmación de la B

1. Con la B grabada y sin confirmar, **R** (o, la primera vez, el propio arranque siguiente de la A: `reg_usados == 0` hace la primera prueba sola) llama a `probar_b()`: gasta un intento (programa a 00 el byte +0x80 + n), pone `MULTIBOOT` = 0x100 y reinicia. Se permiten **tres intentos** en total.
2. Antes de reiniciar (`reiniciar()`), el companion deja el sistema quieto para que el FSBL reentrene la DDR sin tráfico en vuelo: MSX en reset, USB0 detenido y reseteado, GEM0 apagado, masters del PL en reset (`FCLK_RESET`) y level shifters solo PS→PL. Luego `PSS_RST_CTRL`.
3. El companion de la B arranca y **confirma** (`confirmar_poll`, una comprobación por segundo, solo si está en la B y el registro aún no está confirmado) cuando se cumple una de estas:
   - hay tarjeta en TF2, el MSX ha leído algún sector de ella (`SDBOX` W8 > 0) y han pasado más de 5 s desde el arranque del companion; o
   - no hay tarjeta y el Z80 lleva vivo 20 s seguidos (los contadores de aciertos y fallos de la caché de RAM del Z80 cambian cada segundo).
   Entonces programa a 00 el byte +0x88: la B está confirmada.
4. Desde ese momento el FSBL de la A salta a la B en cada encendido (apartado 3).
5. Si la B **no llega a confirmarse** (se cuelga o el usuario apaga), el siguiente encendido arranca la A. La A, con el registro sin confirmar y al menos un intento ya gastado, no reintenta sola: avisa en el OSD (`<versión> no arrancó`) y deja a **R** probarla otra vez, hasta agotar los tres intentos. Con los tres gastados queda la A hasta que se instale otra imagen (que borra el registro y empieza de nuevo).
6. **F** dos veces borra el registro y R reinicia en la A (`MULTIBOOT` = 0).

La A queda siempre como red de seguridad: ninguna operación de la actualización la escribe.

Lo contrario también vale: **grabar la A por JTAG (`qspi_program.tcl`) no cambia lo que arranca si hay una B confirmada.** El script usa `ADDRESS_RANGE {use_file}`, de modo que ni el registro (0xFFE000) ni la B se tocan, y tanto el hook del FSBL (`fsbl_hooks.c`) como `ota_arranque()` saltan a la B sin comparar series con la A. Para probar lo recién grabado: F12 → U → **F** dos veces (borra el registro) → **R** (reinicia en la A), o arrancar la imagen por SD en TF1, donde el salto no actúa (el hook y el companion exigen arranque QSPI). Los ajustes (0xFFF000) quedan fuera del rango y sobreviven.

## 8. Las herramientas de publicación

Todas en `fpga/zynq/ota/`. Necesitan Python con `cryptography`; `ota_subir.py` además `paramiko` y `keyring`.

| Fichero | Para qué |
|---|---|
| `ota_claves.py` | Crea (una vez) el par ECDSA P-256 y escribe la pública en `ota_clave.h` y `ota_publica.pem`. `--publica` regenera solo la pública a partir de la privada que ya existe. Imprime una huella corta (los 8 primeros bytes de X) |
| `ota_publicar.py` | Prepara una versión: valida cada `BOOT.bin`, escribe el manifiesto y lo firma |
| `ota_servidor.py` | Servidor HTTP para el PC + respuesta al descubrimiento UDP; sirve la carpeta `servidor/` |
| `ota_subir.py` | Sube la versión preparada a msx.barcelona y comprueba que la web la sirve bien. Herramienta del mantenedor: no está en el repositorio público |
| `servidor/` | Carpeta de salida de `ota_publicar.py` (`servidor/zynq/` con el manifiesto y los cuatro `BOOT.bin`). **No se versiona** (está en el `.gitignore` de `fpga/zynq`) |

### ota_publicar.py

```
python ota_publicar.py --version Z1.2.13 --serie 2026102707 \
    --imagen nextor214=<BOOT_nextor214.bin> --imagen nextor3=<BOOT_nextor3.bin> \
    --imagen nextor214-en=<…> --imagen nextor3-en=<…> \
    --notas "linea 1" --notas "linea 2" --notas "linea 3"
```

`--fecha` (por defecto hoy) y `--salida` (por defecto `servidor/zynq`) son opcionales. Con `--perfil <fichero.mxp>` (repetible, hasta 6; los hace `tools/mxpf.py empaquetar`) se anuncian perfiles del PL (apartado 9): cada uno se valida con `mxpf.py` (cabecera, SHA-256 del contenido, zlib y sincronismo del bitstream), se exige que su **serie sea la de `--serie`** (si no, aborta sin escribir nada), se copia a la salida como `PERFIL_<ID>_<versión>.mxp` y se añade su línea `perfil=` dentro de la parte firmada. Con `--canal beta` (Z1.3) la versión va al canal beta: el manifiesto lleva `canal=beta`, la salida por defecto es `servidor/zynq/beta`, cada `BOOT.bin` tiene que estar hecho con `OTA_CANAL=beta`, y se sube con `ota_subir.py zynq/beta` a `…/ota/zynq/beta/`. El companion busca ahí cuando la página está en el canal beta (tecla B) y ofrece un cambio de canal aunque la serie no sea mayor. Antes de nada comprueba cada imagen: que cabe en la B, que lleva cabecera de arranque con la suma buena y que su `ota_info` dice **la misma** versión, serie, variante y placa que se están publicando (si no, aborta: eso obliga a haber construido cada `BOOT.bin` con `OTA_VERSION` y `OTA_SERIE` iguales a los de aquí). Copia las imágenes a la carpeta de salida con el nombre `BOOT_<version>_<variante>.bin`, calcula su SHA-256, escribe el manifiesto en el orden `nextor214`, `nextor3`, `nextor214-en`, `nextor3-en`, lo firma con la privada y verifica la firma con la pública por si acaso.

### ota_servidor.py

```
python ota_servidor.py [--puerto 8000] [--dir servidor] [--ip <interfaz>]
```

Sirve `servidor/` por HTTP y escucha el UDP 9474: a cada `MSXIMUS-OTA?` responde con `http://<IP del PC hacia el cliente>:<puerto>/zynq/`. Para probar una versión en la placa antes de publicarla: se prepara con `ota_publicar.py`, se lanza el servidor y se pulsa U en la placa. Como la placa solo instala lo firmado con la clave de siempre, el servidor no tiene por qué ser de fiar. Windows pregunta la primera vez si deja a Python usar la red: hay que permitirlo en redes privadas.

## 9. Los perfiles del PL por la OTA

Un perfil es una versión del PL (un bitstream) que el companion guarda en la microSD de TF1 y carga por PCAP ([capítulo 12](12-companion.md), apartados 5.8 y 5.9). La OTA los trae sin tocar la QSPI: **la descarga de un perfil no cambia el estado del `BOOT.bin`** (`st`), lleva el suyo (`pst`: 0 reposo, 1 bajando, 2 instalando en la TF1) y las dos cosas se excluyen (`ota_ocupada()` vale 1 con `pst == 1`, y `I`, `U`, `B`, `R` y `F` no hacen nada mientras tanto).

**Manifiesto.** Las líneas `perfil=` (apartado 4.1) van dentro de la parte firmada. `perfil_nuevo()` las lee con `manif_leer`: una línea mal escrita, con otro tamaño imposible o con una serie que no es la del manifiesto se salta con un aviso en el log (no puede dejar sin actualizar el sistema), igual que un id repetido. La serie ata el perfil al sistema: el PL nuevo habla con el companion por el buzón de la DDR y el reparto de sus palabras es el contrato, así que un perfil solo se carga si su serie es la de `ota_info` (`mxpf_carga`). **Consecuencia: cada versión del sistema reconstruye todos sus perfiles**, y tras instalar un `BOOT.bin` nuevo los de la tarjeta quedan «de otra serie».

**Estado frente a la tarjeta** (`ota_perfil_estado`, sobre `mxpf_estado()`): `OPS_NO` (no está o no hay tarjeta/partición), `OPS_AL_DIA` (mismo id, misma serie, misma versión y mismo tamaño de `.bin`), `OPS_OTRA_SERIE` y `OPS_OTRA_VERSION`. `ota_perfiles_viejos()` cuenta los dos últimos; la página de actualización (`aviso_perfiles`) avisa con *Perfiles viejos: tecla P* en `O_LISTA` y `O_AL_DIA`, y osd.c lleva la tecla P a la vista del servidor de la página Perfiles.

**Descarga** (`ota_perfil_baja(i)`; `i < 0` = todos los que no estén `OPS_AL_DIA`). Antes de pedir nada: (1) que los perfiles sean de una serie que el sistema pueda cargar (`ota_perfiles_descargables`): la que corre (o ninguna conocida, con el arranque por JTAG) o la del `BOOT.bin` que ya está grabado en la B; con una versión nueva todavía sin instalar (`O_HAY`) la lista se ve pero no se baja nada («Instala antes la versión nueva del sistema»), porque cada perfil sustituiría al del mismo id de la tarjeta, que el sistema de ahora sí carga, por uno que no carga (`MXPF_E_SERIE`); (2) tarjeta con partición válida (`mxpf_monta`) y un hueco libre. Si no se cumple, se anota el resultado (`MXPF_E_TARJETA`, `MXPF_E_SINPART`, `MXPF_E_DIR`, `MXPF_E_LLENO` o el texto de la serie) y no se baja nada. El camino (cable o S3) se decide al empezar la cola, no en cada perfil. Después, para cada perfil de la cola: `h_get` (**el mismo cliente HTTP(S) y la misma zona de 9 MB** que el `BOOT.bin`; por la S3 si no hay cable) con el SHA-256 al vuelo en `W->sha`, y al llegar:

1. tamaño recibido = el de la línea y SHA-256 = el de la línea (si no, «Descarga dañada»);
2. `perfil_cabecera_ok`: la cabecera `MXP1` (versión 1, 512, CRC-32 de la entrada) dice el mismo id, versión, serie y tamaño del `.bin` que la línea firmada (si no, «Perfil no válido»: así un fichero no puede pasar por otro perfil);
3. copia por palabras a la zona **sin caché** de los perfiles (`PF_DATOS` = 0x1F401000: la SD hace DMA y `Xil_DCache*` son vacías);
4. `osd_abre_servidor()`: se abre el panel F12 en la vista del servidor **ya** (el overlay congela el Z80). La instalación ocupa el bucle ~1 s, y con «Ocultar (sigue)» el MSX seguiría corriendo sin que se atiendan USB, WaveGame ni la red; así la instalación se hace siempre con el Z80 congelado, como las demás operaciones de `mxpf.c`, y el resultado queda a la vista. Si ya se está mirando la página de perfiles se deja como está;
5. `mxpf_instala`: SHA-256 del contenido guardado, prueba de zlib y sincronismo del `.bin` **antes** de escribir, hueco libre, relectura y un solo sector de directorio (los apagones los cubre `mxpf.c`; durante la instalación se llama a `sd_ceder()`, así que Nextor no se queda sin servicio).

Un error en cualquier perfil de la cola la corta. El resultado (`ota_perfil_resultado`) distingue instalado(s) (con el número y el id del último), error de `mxpf` (el código `MXPF_E_*`, que la página traduce) y error de red o de contenido (el texto). Los perfiles son de hasta 3,5 MB de contenido guardado (`MX_MAXPAY`), así que el `.mxp` mide como mucho 3,5 MB + 512 B (`PERF_MAX_MXP`); los reales, ~1,3 MB.

**Página.** `perfiles.c` (vista «Servidor», tecla S o P): [manual, capítulo 12](../manual/12-actualizar.md). Si el OSD se abre con una descarga de perfil en marcha va directo a esa vista (`osd_poll`); ESC la oculta y sigue.

**Banco.** `tests/ota_host/run_ota_sint.sh` corre el banco de siempre con BOOT.bin **sintéticos** (`gen_imagenes.py`: cabecera de arranque con su suma, `ota_info` y 6 MB de relleno; no hace falta una build de Vivado) y un manifiesto con tres líneas `perfil=`; con el árbol de antes de los perfiles (sacado de `git archive`) comprueba que **el analizador viejo ofrece la actualización igual** (78 comprobaciones las dos veces). `tests/perfil_ota_host/run_perfil_ota.sh` (144 comprobaciones): `ota.c`, `mxpf.c`, `inflate.c`, `perfiles.c` y Mbed TLS tal cual contra el servidor, el UDP, la S3 y la tarjeta de imitación, con las zonas de la DDR en sus direcciones de la placa (se prueba también que la descarga y `mxpf.c` no se pisan), y `tools/mxpf.py` lee las tarjetas que deja el código en C: manifiesto con y sin `perfil=`, firma mala, SHA-256 alterado, conexión cortada, 404, serie y tamaño que no cuadran con la cabecera, sin tarjeta, sin partición, tarjeta llena, `BOOT.bin` y perfil a la vez, una versión nueva sin instalar (no se baja), el arranque por JTAG (sí) y «tras instalar un `BOOT.bin` los de la tarjeta son viejos». `tests/ota_host/test_publicar.py` prueba `ota_publicar.py --perfil` y `ota_subir.py` en local (sin red).

## 10. Resumen de constantes

| Constante | Valor | Dónde |
|---|---|---|
| Ranura B | 0x800000, máximo 0x7F0000 B | `ota.c`, `ota_publicar.py`, `fsbl_hooks.c` |
| Registro | 0xFFE000 | `ota.c`, `fsbl_hooks.c` |
| Ajustes | 0xFFF000 | `qspi_cfg.c` |
| `MULTIBOOT` de la B | 0x100 (0x800000 / 32 KB), registro `0xF800702C` | `ota.c`, `fsbl_hooks.c` |
| Intentos de prueba | 3 | `ota.c` (`OTA_INTENTOS`) |
| UDP de descubrimiento | 9474, `MSXIMUS-OTA? zynq7020-mini` | `ota.c`, `ota_servidor.py` |
| URL pública | `https://msx.barcelona/wp-content/ota/zynq/` | `ota.c` (`OTA_URL`) |
| Zona de descarga | 0x01000000, 9 MB con caché (también los `.mxp`) | `mmu.c`, `ota.c` |
| Perfiles | hasta 6 líneas `perfil=`, `.mxp` de hasta 0x380200 B, copia sin caché en `PF_DATOS` = 0x1F401000 | `ota.c`, `ota_publicar.py`, `mxpf.c` |
| Perfil al arrancar | bytes 16..24 del sector de ajustes | `qspi_cfg.c` |
| `ota_info` | 0x00E10000, 256 B | `make_boot.sh`, `ota.c` |
| Cabecera de arranque | `AA995566h` / `584C4E58h` en +0x20/+0x24, suma en +0x48 | `ota.c`, `fsbl_hooks.c`, `ota_publicar.py` |

El banco del PC `arm/companion/tests/ota_host/` (`run_ota_host.sh`, en WSL; `run_ota_sint.sh` lo corre con imágenes sintéticas) compila `ota.c` y `fsbl_hooks.c` tal cual con una QSPI y una red de imitación y Mbed TLS de verdad, y recorre las decisiones del arranque, la descarga y la confirmación; el de los perfiles está en el apartado 9.

## 11. La ranura A desde la SD (Z1.4.4)

La ranura A (0x000000) solo la grababa Vivado por JTAG, así que una placa nueva exigía Vivado. Con SW1 en SD (`BOOT_MODE` = 5; `boot_sd` en `ota_arranque()`) la página de actualización pasa a ser la de instalar la A con el `BOOT.bin` de la TF1:

- **`bootsd.c`** (`bootsd_abre`, `bootsd_sig`): lector de FAT32 y FAT16 **de solo lectura** sobre `tf1_leer`; FAT16 porque el BootROM la lee y la placa arranca de ella (segunda prueba en placa, 10/11: una tarjeta con una partición de tipo 0E en FAT16 arrancaba la Z1.4.4 y la página decía `MBR 0E 00 00 00 P1:FAT12/16`). FAT12 no (menos de 4085 clusters). Acepta el volumen sin tabla de particiones o con MBR (la primera partición que tenga una FAT32 o FAT16, sea cual sea su tipo en la tabla: Linux y algunas utilidades no lo cambian al formatear), con cualquier tamaño de cluster, y busca `BOOT    BIN` en la raíz (se saltan los nombres largos, los borrados, las etiquetas y las carpetas; no entra en subcarpetas). Tamaño entre 4 KB y 8 MB (lo que cabe en la A). Lee por trozos de 32 KB, juntando en una sola lectura los clusters contiguos (un fichero fragmentado vale), con buffers estáticos (la SD hace DMA y el `.bss` del companion es memoria sin caché) y copia por palabras a `IMG` (`OTA_MEM`). La FAT32 se reconoce por su **estructura**, como hace Windows (raíz en clusters, FAT de 32 bits: `RootEntCnt` = 0 y `FATSz16` = 0), y **no por el número de clusters** de la especificación: Windows formatea en FAT32 volúmenes con menos de 65 525 clusters y los monta. Es lo que pasó en la primera prueba en placa (10/11): la tarjeta de los perfiles, con su P1 de 128 MiB formateada en Windows (clusters de 2 KB, unos 65 270), salía *La TF1 no es FAT32*. En FAT16 (raíz fija y FAT de 16 bits) sí manda el número de clusters: menos de 4085 es FAT12. La raíz de la FAT16 son sus sectores fijos entre las FAT y los datos; la de la FAT32, la cadena de clusters. Cuando no hay ninguna de las dos, `bootsd_diag()` resume lo que se vio y el OSD lo pone debajo de *La TF1 no es FAT16 ni FAT32* en vez de «A lo intenta otra vez»: `MBR 0E 00 00 00 P1:FAT12` (los tipos de la tabla y por qué la primera candidata no vale), `Sin MBR: exFAT`, `Sector 0 sin 55AA`; también va al log.
- **Estados `O_SD_LEE`, `O_SD_LISTO` y `O_SD_HECHO`** de `ota.c`. La tecla **A** (HID 0x04) lee (`a_lee_poll`, los trozos que quepan en 3 ms por vuelta del bucle); `a_valida` comprueba la cabecera de arranque (0xAA995566 y «XLNX» en 0x20, y que el complemento de la suma de las palabras de 0x20 a 0x44 sea la de 0x48), que exista la partición `ota_info` y que diga `placa=zynq7020-mini`, y guarda `version` y `variante` para la página. Una **segunda A seguida** (otra tecla de por medio desarma la primera) lanza `graba_poll` con `a_sd` = 1.
- **`graba_poll` es la misma máquina que graba la B**: borra el registro (0xFFE000), borra bloques de 64 KB, programa páginas de 256 B y relee. Con `a_sd` la base es 0 y no 0x800000; la relectura se compara byte a byte con lo leído de la SD (no hay SHA-256 de manifiesto) y el último paso no escribe registro nuevo: el registro queda borrado, así que el FSBL no salta a ninguna B vieja.
- **Seguridad**: el companion corre desde la DDR, no desde la flash, así que puede borrar la A. Si se va la luz con la A a medias, la QSPI no arranca, pero la SD sí: se repite. La B (0x800000 en adelante) no se toca nunca.
- **En SD** las teclas U, I, B, R y F de la página no hacen nada, y el pie dice `SD`. La tarjeta de TF1 no se prepara con la placa arrancada desde SD (`mxpf_arranque_sd`): después de grabar la A se pasa SW1 a QSPI y se hace con **F12 → P**.
- **Comprobado** en los bancos de PC: `tests/bootsd_host` (el lector contra 27 imágenes: FAT32 y FAT16, con y sin MBR, clusters de 512 B a 32 KB, fragmentado, nombres largos, raíz de varios clusters, tamaños límite, cadena rota, la tarjeta de perfiles con la P1 de Windows, FAT32 en una partición de otro tipo o en la segunda entrada, un volumen con pocos clusters, la FAT16 de tipo 0E de la segunda prueba (2 GB, clusters de 32 KB, fichero en dos trozos), FAT16 sin tabla con la raíz fija llena de nombres largos, FAT16 con la cadena rota, FAT12, exFAT, NTFS, GPT y sin tarjeta, con el diagnóstico de cada rechazo y AddressSanitizer) y los casos 25 a 28 de `tests/ota_host` (grabar la A en una QSPI en blanco con una B confirmada de antes, comprobar la A byte a byte, el registro borrado, la B intacta y que arranca la A; BOOT.bin de otra placa, con la cabecera mala, sin fichero, sin FAT32, sin tarjeta y de tamaño raro). **Pruebas en placa (10/11)**: la página y la lectura de TF1 con el arranque por SD funcionan; la primera rechazaba la tarjeta de perfiles reformateada en Windows y la segunda una tarjeta en FAT16 (las dos, corregidas arriba). La tercera (serie 2026111003) lee el `BOOT.bin` de esa FAT16 (6,0 MB), graba la A y, con SW1 en QSPI, la placa arranca de ella: la página de actualización dice «ranura A · de fábrica». **Pendiente**: un apagón a mitad de la grabación.

## User-Agent de los clientes

- **Companion:** `MSXimus-Z/OTA <versión> (<perfil>)`, por ejemplo `MSXimus-Z/OTA 1.4.0 (TR)`. Perfil: `STD`, `MUSICA`, `DUAL` o `TR`. No lleva ningún identificador de la placa.
- **MXUPDATE 1.4 o posterior:** `MXUPDATE/<versión> (<placa>)`, por ejemplo `MXUPDATE/1.4 (console60k)`, en HTTP/1.0. Las versiones anteriores no mandan User-Agent.

**Pendiente: filtrar por User-Agent en el servidor.** Todavía no hay `.htaccess` ni filtro. Cuando se haga, cuando todos los clientes lleven agente, `MXUPDATE.COM` y su manifiesto deben seguir abiertos, porque son como se actualizan los clientes viejos, y `ota_subir.py` necesitará un agente permitido.
