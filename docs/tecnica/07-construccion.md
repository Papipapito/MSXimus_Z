# 07. Construcción y entrega: del fuente al BOOT.bin y a la placa

El orden es: bitstream, companion y FSBL, menú y packs, `BOOT.bin`. Las secciones 1 a 8 son la construcción; la 9 cuenta cómo se generan las imágenes de BOOT y cómo se prueba la actualización por red.

**Qué se puede compilar desde este repositorio y qué no:**

| Pieza | ¿Desde aquí? |
|---|---|
| Bitstream del PL (Vivado 2019.2) | **Sí** (sección 2) |
| Companion y FSBL (ARM GNU Toolchain, sin SDK) | **Sí** (sección 3) |
| Menú y packs de BIOS | **No**: ensamblar el menú necesita la FM-BIOS base y los packs llevan ROM de sistema del MSX, con copyright, que viven en un repositorio privado (sección 4) |
| `BOOT.bin` propio | **Sí**, con el pack y la tabla de ondas de un `BOOT.bin` publicado (sección 5) |

Quien quiera un `BOOT.bin` propio usa el pack que va dentro de un `BOOT.bin` publicado (`fpga/zynq/arm/boot/extraer_de_boot.py` lo saca) y compila el resto. La YRW801 (la tabla de ondas del OPL4, 2 MB) también se puede sustituir por un fichero de 2 MB a ceros: el OPL4 wave queda mudo, pero nada se bloquea (`fpga/zynq/arm/companion/yrw801.c`).

## 1. Herramientas

| Herramienta | Para qué | Dónde |
|---|---|---|
| Vivado 2019.2 | Bitstream, `bootgen`, grabación de la QSPI, `xsdb` y `hw_server` (JTAG) | Por defecto `D:/Xilinx/Vivado/2019.2`; los scripts `build.sh` y `make_boot.sh` buscan ahí `data/embeddedsw` y `bin/bootgen.bat`. Otra instalación: variable `XILINX_VIVADO` (o `XILINX_EMBEDDEDSW` y `BOOTGEN` por separado) |
| ARM GNU Toolchain 14.2 (`arm-none-eabi`) | Companion y FSBL | Por defecto `C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/14.2 rel1` (los `build.sh` ponen su `bin` en el `PATH`). Otra ruta: variable `ARM_TC` (la carpeta `bin`) |
| Git Bash | Ejecutar los `build.sh` y `make_boot.sh` en Windows | — |
| `asmsx` 1.1.1 | Ensamblar el menú (solo con acceso a los packs privados) | No se versiona: se baja de [Fubukimaru/asMSX](https://github.com/Fubukimaru/asMSX) y se deja en `bios/bin/` (véase `bios/README.md`) |
| Python 3 | `hacer_packs.py`, los scripts de `ota/` (módulo `cryptography`), los generadores de `tools/` | — |
| WSL Ubuntu-24.04 | Bancos de pruebas (Icarus Verilog y Verilator), `gcc` para los bancos del companion, y el driver de Nextor (`N80`, `mknexrom`) | La distribución hay que nombrarla: `wsl -d Ubuntu-24.04` |
| `arduino-cli` | El firmware del ESP32 | — |

Los pasos 2 a 5 salen de Git Bash; las simulaciones, de WSL (capítulo [08](08-simulacion.md)).

## 2. El bitstream del PL

```
cd fpga/zynq
vivado -mode batch -source build.tcl -tclargs bit   # unos 15 min -> msximus_zynq.bit
```

`build.tcl` acepta tres modos: `elab` (solo elaboración RTL, para cazar errores de sintaxis), `synth` (síntesis y utilización) y `bit` (por defecto: además implementación y bitstream). Lo que hace:

- Crea el proyecto `vivado_prj/` para el XC7Z020-CLG400-2 y el PS7 con `bd_ps7.tcl` (DDR3, MIO, QSPI, SD0/SD1, USB, FCLK0 a 150 MHz, cuatro puertos HP y dos GP).
- Añade los fuentes en un orden manual (paquetes SystemVerilog delante de quien los importa; `source_mgmt_mode DisplayOnly`): el RTL común de `fpga/` (núcleo, V9968, V9990, OPL3/OPL4, jtopl, ikaopll, jt10, G80A, geo3d, vídeo 720p…) más lo específico de la Zynq que vive en `fpga/zynq/`: `top_zynq.v`, `memory_axi.v`, `v9968_axi_backend.v`, `dbg_mailbox_axi.v`, `sd_axi_proxy.v`, `wave_axi.v`, `vdp_trace.v`, `iosys_bl616_z.v`, `textdisp_z.v`, `osd_paleta.v`, `gowin_prims.v` y `gowin_dpb_menu.v`. El define `ZYNQ=1` se aplica a todo el fileset.
- Añade las constraints: `top_zynq.xdc` (HDMI, LEDs, botones), `top_zynq_esp.xdc`, `top_zynq_oled.xdc` y `top_zynq_sd.xdc` (CAM1 y el header de microSD).
- Lanza síntesis e implementación con 4 trabajos en paralelo y `write_bitstream`; al acabar deja en `fpga/zynq/` el bitstream (`msximus_zynq.bit`), `ps7_init.tcl` (lo usa `boot.tcl`) y los informes `util_synth.rpt`, `util_synth_hier.rpt`, `util_impl.rpt`, `timing.rpt` y `clocks.rpt`. `ps7_init.c/h`, que usa el FSBL, no los copia `build.tcl`: los toma `fsbl/build.sh` del proyecto de Vivado.

**`top_zynq.v` se edita a mano.** `tools/make_top_zynq.py`, que lo generó al principio a partir de `fpga/top.v`, está desfasado y **no hay que ejecutarlo**: borraría el V9990 y lo posterior. Lo común con el MSXimus de Tang se mantiene a mano en las dos copias.

### Perfiles del PL

`vivado -mode batch -source build.tcl -tclargs bit musica` construye el perfil **Música**: el mismo sistema (mismo companion, mismo buzón, mismo pack) sin geo3d y con el YM2151 de la Yamaha SFG-01/05 y un SN76489 (capítulos [02](02-puertos-es.md), apartado 5, y [03](03-mapas-memoria.md)). El segundo argumento fija el define `PERFIL_MUSICA` y cambia la lista de fuentes (sin `fpga/geo3d`, con `fpga/jt51`, `fpga/jt89` y `fpga/zynq/musica_sound.v`); proyecto y salidas llevan el sufijo `_musica` (`vivado_prj_musica`, `msximus_zynq_musica.bit`, `util_musica.rpt`, `timing_musica.rpt`…) y no pisan nada del estándar. Sin el segundo argumento el script hace exactamente lo de siempre. El `.bit` se empaqueta como perfil de la TF1 con `tools/mxpf.py empaquetar` (`files/musica/LEEME.txt`).

`… bit dual` construye el perfil **Dual** (31/10/2026, prueba de concepto; capítulo [14](14-perfil-dual.md)): sin geo3d ni OPL4 (`ENABLE_OPL4FM` y `ENABLE_OPL4_WAVE` sin definir) y con una segunda máquina MSX2+ (`fpga/zynq/msx_b.v`, `fpga/zynq/axi_arb2w.v`) cuya imagen es un rectángulo del frame buffer del V9990 (`fpga/video720/bwin_fb.v`, por el `S_AXI_GP0`). Fija `PERFIL_DUAL`, quita de la lista de fuentes `fpga/geo3d`, añade esos tres ficheros (y, desde la Z1.3.2b8, `fpga/zynq/dual_mute.v`: el silencio por máquina) y usa sufijo y proyecto `_dual` (`vivado_prj_dual`, `msximus_zynq_dual.bit`, `util_dual.rpt`…). `files/dual/LEEME.txt` trae las cifras, el `.mxp` y cómo probarlo.

`… bit tr` construye el perfil **TR** (Turbo R, publicado desde la Z1.4.0; capítulo [15](15-perfil-tr.md), y `… bit trv` su variante con V9990): sin geo3d, sin V9990 (chip, puente, árbitros del GP1 y puerto del ARM), sin OPL4 (`ENABLE_OPL4FM`, `ENABLE_OPL4_WAVE` y `wave_axi`) y sin Y8950 (`ENABLE_Y8950*`, `jtopl`, `jt10`, `y8950_adpcm`, `adpcm_sdram`). Fija `PERFIL_TR` (el top lo convierte en `ENABLE_TR`), sufijo `_tr` y proyecto `vivado_prj_tr`. Se queda `video720/v9990_fb.v` porque `msx2hdmi_v9968` lo instancia para su frame buffer.

`… bit trv` construye el perfil **TRV** (capítulo [15](15-perfil-tr.md), sección 30): el TR con V9990 y megaram de 16 MB, sin Y8950. Salidas con sufijo `_trv`. `BUILD_TAG` y `PLACE_DIR` en el entorno lanzan varias colocaciones en paralelo (`BUILD_TAG=a` da el proyecto `vivado_prj_trv_a`), y `NEO16M=1` activa los 16 MB en cualquier perfil.

### Qué se mira al acabar

| Informe | Qué mirar | Valores de la Z1.3.1 |
|---|---|---|
| `timing.rpt`, «Design Timing Summary» | **WNS** y **WHS** (peor holgura de *setup* y de *hold*) positivos y la línea «All user specified timing constraints are met». También la holgura del reloj `pD_86` (86 MHz, V9968/V9990), la más ajustada | WNS +0,288 ns, WHS +0,036 ns, todo cumplido |
| `util_impl.rpt` | **BRAM** (el límite duro: 140) y **slices** (sobre el 98 % el enrutado cuesta cerrar), DSP, LUT, FF | BRAM 130,5/140, slices 99,80 %, DSP 29/220, LUT 44.720, FF 36.711 |
| `clocks.rpt` | Que no aparezcan relojes sin restringir | — |

Con tan poco margen de BRAM y de slices, cualquier módulo nuevo del PL se mide antes (síntesis fuera de contexto: `tools/synth_v9990_ooc.tcl` es el ejemplo) y se prueba en banco antes de gastar los 15 minutos. Una holgura de hold de unos pocos picosegundos es normal: lo que importa es que sea positiva y que el informe diga que se cumple todo.

`git` ignora `vivado_prj/`, los `.bit`, los `.log`, los `.rpt`, los `.jou` y `ps7_init*.tcl`.

## 3. El companion y el FSBL

```
fpga/zynq/arm/get_tinyusb.sh        # una vez: clona TinyUSB y aplica tinyusb-zynq7000.patch
fpga/zynq/arm/get_minimp3.sh        # una vez: minimp3 (el MP3 del menú)
fpga/zynq/arm/get_mbedtls.sh        # una vez: Mbed TLS 3.6 (https del «ESP32» por cable)
fpga/zynq/arm/companion/build.sh    # -> companion.elf (bare-metal, -O2)
fpga/zynq/arm/fsbl/build.sh         # -> fsbl.elf
```

Los dos son *bare-metal*, sin SDK ni Vitis: compilan los fuentes del BSP *standalone* y de los drivers (`sdps`, `qspips`, `emacps`, `scugic`, `uartps`, `wdtps`, `xilffs`, lwIP 2.1.1) que trae Vivado en `<Vivado>/data/embeddedsw` (rutas por defecto y variables `XILINX_VIVADO`, `XILINX_EMBEDDEDSW` y `ARM_TC`: sección 1).

- **Companion**: `build.sh` compila la lista de fuentes de `main.c`, `usb_host.c`, `osd*.c`, `wavegame.c`, `tape.c`, `fdd.c`, `ota.c`, `net*.c`, `esp_*.c`, etc., más TinyUSB, lwIP y toda la biblioteca de Mbed TLS (con `bsp/msximus_mbedtls_config.h`); `mp3.c` se compila aparte con la FPU (`softfp`). Termina con `BUILD_OK: …/companion.elf` y la tabla de `arm-none-eabi-size`. La memoria se reparte en `lscript.ld` (el companion, los descriptores y *pools* de red en 0x00600000, el *heap* de TLS de 768 KB en 0x00A00000). Detalles del companion: capítulo [12](12-companion.md).
- **FSBL**: es el `zynq_fsbl` de Xilinx con `fsbl_hooks.c` propio (el salto a la ranura B de la actualización por red) y el `ps7_init.c/h` del proyecto de Vivado (`build.sh` los copia: **hay que haber compilado el bitstream antes** y recompilar el FSBL si cambia `bd_ps7.tcl`). Consola por la UART1 a 115200.
- Tras cambiar el companion no hace falta tocar el bitstream, y al revés. El FSBL casi nunca cambia.

## 4. El menú, el driver de Nextor y los packs

> **Esta sección no se reproduce desde un clon público.** El fuente del menú y de los drivers (`bios/`) no está en esta copia: `build.sh` necesita la FM-BIOS base y `hacer_packs.py` los packs base, que llevan ROM de sistema con copyright y están en un repositorio privado. Queda descrito como referencia de cómo se hace. Quien no tenga ese repositorio parte de los packs de un `BOOT.bin` publicado (sección 5).

```
cd bios
./build.sh                          # desde Git Bash: out/bios_msximus.bin, bios_msximus_p2.bin y los _en
python tools/hacer_packs.py         # los packs de BIOS
```

- `build.sh` sin argumentos compila `msximus`, `msximus_en` (menú, Ajustes y mensajes en inglés, `ENGLISH=1`) y `msxnano`; para la Zynq basta `./build.sh msximus msximus_en`. Imprime el espacio libre de cada sección (página 1 hasta `#7051`, código de la página 2 hasta `#A000`, datos hasta `#C000` y `#E800`) y falla si el menú no cabe o pisa las tablas del FM-BIOS. La FM-BIOS base sobre la que va el menú (`16k_msx2p_fm_logo_menu.bin`) la lee de `assets/` del repositorio privado de BIOS (véase abajo); sin él, `build.sh` se detiene.
- `hacer_packs.py` parte de los packs base de `packs/zynq/` del repositorio **privado** `Papipapito/bios-msxnano-msximus`, que se clona como carpeta hermana de este (`../bios-msxnano-msximus`, o donde diga la variable de entorno `MSXIMUS_BIOS_PRIV`): los packs llevan ROMs con copyright y no están en este repositorio (véase `bios/packs/LEEME.md`). Quien construye sin acceso a él necesita sus propias ROM de sistema y montar su pack con las herramientas de `bios/`, o usar los `BOOT.bin` publicados. El script reescribe **solo** las ventanas del menú, del logo de arranque, de Nextor y de la segunda mitad del menú, comprobando byte a byte que no toca nada más (capítulo [04](04-pack-bios.md)). Para que salgan también los packs en inglés hace falta haber compilado antes `msximus_en`. Solo hace el MSXimus y saca cuatro packs de 512 KB justos:

| Pack | Nextor | Menú |
|---|---|---|
| `packs/zynq/msximus/nextor-2.1.4/pack_bios_msximus.bin` | 2.1.4 | castellano |
| `packs/zynq/msximus/nextor-2.1.4/pack_bios_msximus_en.bin` | 2.1.4 | inglés |
| `packs/zynq/msximus/nextor-3.0.0/pack_bios_msximus_nextor3.bin` | 3.0 | castellano |
| `packs/zynq/msximus/nextor-3.0.0/pack_bios_msximus_en_nextor3.bin` | 3.0 | inglés |

  Imprime el MD5 de cada pack, y deja una copia del estado anterior en `packs/zynq/historico/bak_<fecha>/`. El logo de arranque sale de `bios/assets/logo16k_msximus.bin`.
- **Drivers de Nextor.** Las ROM compiladas (`bios/nextor214/Nextor-2.1.4.MSXimus.ROM`, `bios/nextor3/Nextor-3.0.0.MSXnano.ROM`) y el kernel base (`bios/nextor214/Nextor-2.1.4.base.dat`) **no están en el repositorio público**: la licencia de Nextor (MSX Licensing Corporation) no permite repartir obras derivadas sin permiso. Quien compile parte del kernel oficial de las releases de Konamiman (https://github.com/Konamiman/Nextor/releases) y monta la ROM con el `make` de esta sección; `hacer_packs.py` las trasplanta tal cual. Solo se recompilan si cambia el driver (`bios/nextor214/sd_rw_ports.inc` y `driver.mac`, `bios/nextor3/driver.asm`): en WSL, `bios/nextor3/setup.sh` una vez (baja `N80`, `mknexrom` y el SDK de Nextor) y `make` en `bios/nextor3` y en `bios/nextor214`. El banco `bios/tests/test_tf1_nextor.py` (emulador Z80, `pip install z80`) prueba los dos drivers con y sin tarjeta en TF1.

## 5. El BOOT.bin

```
cd fpga/zynq/arm/boot
OTA_VERSION=Z1.4.9 OTA_SERIE=2026111301 ./make_boot.sh [pack.bin] [yrw801.rom]
```

Sin argumentos usa el pack de Nextor 2.1.4 en castellano y la `yrw801.rom` de `packs/zynq/` del repositorio privado de BIOS (`MSXIMUS_BIOS_PRIV`, por defecto `../../../../../bios-msxnano-msximus`). Sin acceso a él, hay que darle los dos ficheros: se sacan de un `BOOT.bin` publicado con `python extraer_de_boot.py BOOT_<versión>_<variante>.bin <carpeta>` (en una carpeta que no sea la de `make_boot.sh`, que copia aquí el pack y la ROM de ondas con esos mismos nombres) y se pasan como `./make_boot.sh <carpeta>/pack.bin <carpeta>/yrw801.rom`. La ROM de ondas puede ser también un fichero de 2 MB a ceros. Comprueba que existen `fsbl.elf`, `companion.elf`, el bitstream (`fpga/zynq/msximus_zynq.bit`), el pack y la ROM de ondas; genera `boot.bif` y llama a `bootgen`. El orden de las particiones es el del `.bif`, y el bitstream tiene que ir justo detrás del FSBL:

| # | Partición | Destino |
|---|---|---|
| 1 | `fsbl.elf` (bootloader) | — |
| 2 | `msximus_zynq.bit` | PL |
| 3 | `companion.elf` (tiene que ser la primera partición del PS: el FSBL salta a ella) | — |
| 4 | `zeros.bin` (64 KB) | DDR 0x1FF00000: buzón y SDBOX a cero, el MSX espera |
| 5 | `pack.bin` | DDR 0x10F00000 |
| 6 | `yrw801.rom` (2 MB) | DDR 0x0F000000: ondas del OPL4 |
| 7 | `ota_info.bin` | DDR 0x00E10000: quién es esta imagen para la actualización por red |

`OTA_VERSION` y `OTA_SERIE` van a `ota_info.bin` (`MOTI1`, `version=`, `serie=`, `variante=`, `idioma=`, `placa=zynq7020-mini`, `fecha=`). La versión tiene como mucho 15 caracteres; la serie es un entero creciente (`AAAAMMDDNN`); la **variante** y el idioma los deduce el script del propio pack (`nextor214` / `nextor3`, más `-en` si es el menú en inglés). Sin las variables salen «dev» y 0: sirve para pruebas, pero la placa no la tomaría por ninguna versión publicada. Resultado: `BOOT.bin` de 6.159.424 bytes. **Siempre escribe en `BOOT.bin`**: hay que copiarlo con su nombre final antes de generar la siguiente variante.

## 6. Grabar y arrancar

- **QSPI**: con SW1 en JTAG (ON-ON) y `hw_server` corriendo:
  ```
  cd fpga/zynq
  vivado -mode batch -source tools/qspi_program.tcl -tclargs program w25q128fv-qspi-x4-single BOOT.bin
  ```
  Borra, programa y verifica (~1,5 min); usa el `fsbl.elf` como ayudante. Solo toca el rango del fichero (`ADDRESS_RANGE {use_file}`): los ajustes (0xFFF000) sobreviven, pero tampoco se tocan el registro de la actualización por red (0xFFE000) ni la ranura B. **Si la placa tiene una B confirmada, el FSBL (y el companion) saltan a ella en cada arranque desde QSPI y no arranca lo recién grabado en la A**: para volver a la A, F12 → U → **F** dos veces → **R**; o probar la imagen por SD en TF1, donde el salto no actúa (capítulo [11](11-actualizacion.md)). `-tclargs backup <parte> <salida.bin>` lee los 16 MB. El nombre de la parte depende del chip U15 (Winbond W25Q128, Micron MT25QU128, Spansion S25FL128S: véase la cabecera del script). Con SW1 en SD el borrado se cuelga («The current boot mode is SD»); si el *verify* se queda colgado, matar Vivado y repetir. Después, SW1 en QSPI (ON-OFF) y quitar y dar la corriente.
- **SD**: copiar `BOOT.bin` a la raíz de una SD FAT32 en TF1, SW1 en SD (OFF-OFF).
- **JTAG** (desarrollo, no graba nada): `BOOT_PROXY=1 xsdb.bat tools/boot.tcl [pack] [bit]` con SW1 en JTAG. Para el PS, carga pack, ondas y VRAM en la DDR, limpia el buzón, arranca el companion (sirve la TF2 real; `BOOT_ELF` elige otro binario), programa el PL y suelta los resets. Con SW1 en SD falla al bajar el companion. Variables de modo imagen y disquete falso: capítulo [06](06-sd-dma.md).
- **Red**: una placa con una versión anterior se actualiza con la tecla U con el panel F12 abierto (capítulo [11](11-actualizacion.md)).

## 7. El ESP32

Opcional en la Zynq: sin él, el companion hace de «ESP32» por el Ethernet de la placa. El firmware está en su propio repositorio, [`Papipapito/ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA) (rama `c6`), y se compila con `arduino-cli` y el FQBN completo de la placa (véase su README y `ESP32BOARDS.h`): el C6 es la placa por defecto y `-DESP32_S3_LCD169` es la Waveshare ESP32-S3-LCD-1.69, el módulo de la Zynq. Se flashea por su propio USB-C, solo la app a `0x10000` (nunca la imagen fusionada a `0x0`).

## 8. Dónde está el número de versión

| Qué | Dónde | Cómo se ve |
|---|---|---|
| Versión del PL | `FPGA_VERSION` en `fpga/zynq/top_zynq.v` (`A4h` = Z1.4), puerto 2Fh | `INP(&H2F)`; el menú de pruebas |
| Tercer dígito del PL | `FPGA_PATCH` en `top_zynq.v` (hoy 7), puerto 29h | `INP(&H29)`, en decimal (1..99) |
| Versión y serie de la imagen | `OTA_VERSION` y `OTA_SERIE` de `make_boot.sh` → `ota_info` | El panel F12, la OLED, la actualización por red y, desde la Z1.4.9, Ajustes → «Version FPGA» (el companion la pone en el pack: `ota_menu_version`) |

Regla: los lotes de arreglos suben el tercer dígito. **`FPGA_PATCH` es del bitstream**: solo se toca si cambia el PL, y se sube a la vez en la versión que lo lleva. Una versión menor nueva (Z1.3) sube `FPGA_VERSION` (A3h) y vuelve a `FPGA_PATCH` 0. Dos imágenes con el mismo bitstream se distinguen por `OTA_VERSION`/`OTA_SERIE`; el companion decide si hay actualización comparando solo la **serie**.

## 9. Cómo se generan las imágenes de BOOT y la actualización por red

Las cuatro variantes (`nextor214`, `nextor3`, `nextor214-en` y `nextor3-en`) salen de una vuelta de `make_boot.sh` por pack, con los mismos `OTA_VERSION` y `OTA_SERIE` en las cuatro, y cada resultado se guarda con el nombre `BOOT_<versión>_<variante>.bin`. Las cuatro miden lo mismo (6.377.024 bytes las de la Z1.4.9) y comparten FSBL, bitstream, companion, `zeros` y tabla de ondas; cambian el pack y `ota_info`. La serie tiene que crecer siempre: una placa solo ofrece las series mayores que la suya, así que publicar una menor o igual no actualiza a nadie.

La release de GitHub lleva esas cuatro imágenes y **MSXimusZboot** para Windows y macOS, el programa que prepara con ellas la tarjeta de instalación (sale del repositorio [SD_Maker](https://github.com/Papipapito/SD_Maker)); ni el `.bit` ni el `fsbl.elf`: quien graba por JTAG los compila.

La actualización por red se puede probar en local, sin servidor externo:

```
cd fpga/zynq/ota
python ota_publicar.py --version Z1.3.1 --serie 2026103002 \
    --imagen nextor214=BOOT_Z1.3.1_nextor214.bin  --imagen nextor3=BOOT_Z1.3.1_nextor3.bin \
    --imagen nextor214-en=BOOT_Z1.3.1_nextor214-en.bin --imagen nextor3-en=BOOT_Z1.3.1_nextor3-en.bin \
    --notas "primera linea" --notas "segunda" --notas "tercera"
python ota_servidor.py
```

`ota_publicar.py` comprueba cada BOOT (cabecera de arranque, que quepa en la ranura B, que su `ota_info` coincida con `--version`, `--serie` y la variante), las copia a `ota/servidor/zynq/` con el nombre `BOOT_<versión>_<variante>.bin`, calcula su SHA-256 y escribe `manifiesto.txt` firmado con ECDSA P-256 (`--salida` elige otra carpeta; hasta 3 notas de 25 columnas, que es lo que cabe en el panel). La clave privada de firma no está en el repositorio (la lee de donde diga `MSXIMUS_OTA_CLAVE`); la pública, `ota_publica.pem`, es la que lleva compilada el companion (`ota_clave.h`). `ota_servidor.py` sirve `ota/servidor/` por HTTP en el PC y contesta a la difusión UDP de la placa (puerto 9474) al pulsar U en el panel, así que la placa encuentra el PC sin saber su IP. Con la placa en una versión anterior: U (buscar), I (instalar), R (reiniciar a la ranura B). `tools/ota.tcl U|I|R|F|log` manda esas teclas desde xsdb. Cómo funciona todo ello: capítulo [11](11-actualizacion.md).
