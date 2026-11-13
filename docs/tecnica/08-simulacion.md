# 08. Verificación: bancos de pruebas y la placa por xsdb

En el MSXimus Z buena parte de lo que en otro proyecto se simularía se comprueba directamente en la placa: el PS tiene la memoria del MSX en la DDR y el buzón permite pulsar teclas, leer la pantalla y la telemetría desde el PC sin tocar nada. Los bancos siguen siendo obligatorios para los módulos nuevos del PL antes de gastar 15 minutos de Vivado, y para todo el código del companion que se puede ejecutar en el PC.

Los bancos corren con Icarus Verilog o Verilator **en WSL Ubuntu-24.04** (no en la distribución por defecto: `wsl -d Ubuntu-24.04`). Casi todos los `run_*.sh` se relanzan solos dentro de WSL, así que se lanzan desde Git Bash. Los que usan Verilator compilan una vez en `/tmp` y ejecutan todos los casos en la misma llamada.

> **En esta copia pública no están los bancos.** Las carpetas de pruebas de las secciones 1 a 4 (`fpga/zynq/tb/`, los bancos de `tools/`, `fpga/zynq/arm/companion/tests/` y `bios/`) son del repositorio de desarrollo y no se publican: el capítulo queda como relación de qué se comprueba antes de cada versión. Sí están aquí `tools/lint.sh` y las herramientas de xsdb de la sección 5 (`fpga/zynq/tools/`).

## 1. Bancos del PL de la Zynq (`fpga/zynq/tb/`)

| Banco | Qué cubre | Resultado |
|---|---|---|
| `run.sh` → `tb_memory_axi.v` (Icarus) | `memory_axi` con un esclavo AXI3 de 64 bits de RAM de 64 KB y latencia configurable: aceptación y entrega inmediatas del puerto `ram_*` del Z80, datos correctos en fallo, acierto y escritura, y que `ram_slow` solo se arma en fallos | `TB_OK` |
| `run_mbox_wg.sh` → `tb_mbox_wg.v` (Icarus) | El buzón (`dbg_mailbox_axi`): ráfaga de control de 6 beats, siembra de configuración y del mezclador (+0x24), telemetría (+0xC0), anillo Z80 → ARM, y la voz del WaveGame: fetch de 16 beats, FIFO, tick de 44,1 kHz exacto, silencio cuando se acaban los datos, salto de canción | `TB_OK` |
| `run_mbox_tape.sh` → `tb_mbox_tape.v` (Icarus) | El reproductor de pulsos de la cinta virtual (capítulo [10](10-cinta.md)): cada pulso dura exactamente sus ciclos, sin motor la cinta no corre, `play` a 0 la vacía, y la telemetría +0xC8/+0xCC | `TB_OK` |
| `run_rtc.sh` → `tb_rtc.v` (Icarus) | El RTC (`fpga/src/ocm/rtc.v`) frente a la versión anterior de referencia (`rtc_old.v`): 56 comprobaciones (fecha de arranque en frío, paso 11 AM → 12 PM, modo 12/24 h, Timer EN, LFSR del preescalador) | `RESULT PASS` |
| `run_textdisp_z.sh` → `tb_textdisp_z.sv` (Icarus) | El OSD con color (`textdisp_z.v`): una página de prueba con los 256 glifos y las 256 combinaciones de color, un cuadro entero simulado y comparado píxel a píxel con `fpga/zynq/tools/osd_render.py` (`textdisp_z_check.py`) | Comparación sin diferencias |
| `run_v9990_vram.sh` → `tb_v9990_vram.v` (Icarus) | El cliente de VRAM del V9990 (`v9990_vram_axi`) con un esclavo AXI3 de 32 bits de 512 KB: lecturas 8/32/32E/32O, escrituras de todos los tamaños, coherencia lectura tras escritura, prefetch secuencial y ausencia de bloqueos, contra un modelo byte a byte | Sin errores |
| `run_musica.sh` → `tb_musica.sv` (Verilator) | El perfil Música (`musica_sound.v` con `jt51` y `jt89`): ROM del SFG y sus espejos, bit de ocupado (~18 µs), tono del YM2151 (442,5 Hz) y reparto izquierda/derecha, IRQ del temporizador al `/INT`, el SN76489 por Franky y por PlaySoniq (442,9 Hz), las detecciones de VGMPlay de ambos, ninguna escritura perdida ni duplicada en ráfagas a 3,6 y 5,37 MHz y el reinicio. `run_musica.sh +LEVEL`: niveles del YM2151. `run_musica.sh <eventos> <ms> [salida]` reproduce un VGM convertido con `tb/vgm2ev.py` y `tb/analiza_out.py` resume (o pasa a WAV) lo que sale. La primera compilación tarda unos 4 minutos; el directorio de objetos queda en `~/obj_musica` y las siguientes, segundos | `TB_OK` |
| `run_msx_b.sh [--sub] [--cart] [--plain] [--irq]` → `tb_msx_b.sv` (**xsim de Vivado**, desde Git Bash: el Z80 `G80a` es VHDL) | La máquina B del perfil Dual (`msx_b.v`, capítulo [14](14-perfil-dual.md)) con su Z80: arranca de una «BIOS» en una DDR de mentira, prueba slot 0, RAM, mapper, PSG, V9968 con su VRAM por AXI y RTC; `--sub` la SUB-ROM, `--cart` el cartucho Konami 4, `--plain` el cartucho plano de `dual_rom.tcl` (lineal con una imagen de 64 KB y una ROM de página 2), `--irq` la interrupción del V9968 (con una rutina como la de la BIOS: lee S#0, cuenta solo si F estaba a 1 y falla si hay INT espurias) y 240 líneas de 640 px por fotograma hacia el puente. `b_prog.py` ensambla el programa. Sin opciones unos 40 s; con `--irq`, unos 6 min. `--bios <pack.bin> [ms]` cambia el programa de prueba por la BIOS y la SUB-ROM de un pack de verdad (unos 13 ms simulados por minuto de pared) y cuenta PC, E/S y escrituras al VDP; `--fast [n]` sube el Z80 a 13,5 MHz (n = 3) para llegar antes | `TB_OK` |
| `emu_b.py <pack.bin>` (Python con `pip install z80`, en WSL) | El mapa de memoria y de E/S de B (`msx_b.v`) en un emulador Z80 con un V9968 de juguete: ejecuta la BIOS de un pack de verdad en segundos y dice si llega a escribir «MSX BASIC» al VDP. Con `--vacio` reproduce el fallo que se vio con `tb_msx_b.sv --bios` (la página 1 del slot 3-1 vacía: RST 38h desde `7A00h`). Con `--cart=<imagen>` pone un cartucho lineal en el slot 1 (la imagen que compone `dual_rom.tcl cargar`; `tb/run_emu_cart.sh <pack> <rom>` lo hace de punta a punta con `tb/xsdb_stub.tcl`) y `--png=` dibuja la pantalla; `tb/check_dual_rom.py` comprueba la elección automática de `cargar`. No mide tiempos ni sustituye a `tb_msx_b.sv`: avisa de dónde se atasca la BIOS antes de gastar ~45 min de xsim | Escribe «MSX BASIC version 3.0 … 28815 Bytes free» |
| `run_bwin.sh` → `tb_bwin.v` (Icarus) | La imagen de la máquina B dentro del frame buffer del V9990 (perfil Dual): `bwin_fb` y un `v9990_fb` con `SKIP = 1` (frames de 640 × 400) escribiendo a la vez por `axi_arb2` (ID_BIT 3) en una DDR de mentira de 3 slots; fuera del rectángulo, los píxeles del V9990; dentro (256 × 212), los de B decimados 2,5:1 y recortados; el escritor del V9990 marca con `WSTRB = 0` las palabras del rectángulo. Con la posición fina (`run_bwin.sh X0,Y0 ...`: por defecto 192/188 y cuatro más; nueve en la revisión) la imagen de B va en cualquier punto, con las palabras de los bordes compartidas si es impar | `TB_OK` en cada posición |
| `run_mbox_dual.sh` → `tb_mbox_dual.v` y `run_v9991_wm_dual.sh` → `tb_v9991_wm_dual.sv` (Icarus, `-DPERFIL_DUAL`) | Lo que el escritorio de dos columnas añade al buzón (control de B en dos beats, telemetría `+0xD0`) y al gestor de ventanas (barra de A según el foco, puntero y ventana de A para el ARM; Z1.3.2b9: el cuadradito cian de A hueco y gris con `mute_a`, y los clics dentro y justo fuera de su zona). Capítulo [14](14-perfil-dual.md), apartados 3.2, 8 y 13 | `TB_OK` |
| `run_v9991_tr.sh` → `tb_v9991_tr.sv` y `run_mbox_tr.sh` → `tb_mbox_tr.v` (Icarus) | Perfil TR (capítulo [15](15-perfil-tr.md)): el compositor sin V9990 (modo 0 fijo: `rgb == rgb68`, ventana de pantalla completa, 4 cuadros) y el bit 2 de `MBOX+0xC4` del buzón con y sin `-DPERFIL_TR` |
| `fpga/r800/sim/run_r800.sh` (Verilator + pasmo, en WSL), `run_tr_xsim.sh` y `run_tr_stress.sh` (xsim de Vivado, mixto VHDL/Verilog con el G80a real) | Perfil TR, fase 2 (capítulo [15](15-perfil-tr.md), apartado 17): las pruebas de rampa069/R800 (multest, pfxtest, blktest, iotest, inttest, halttest, io2test) con nuestro bus y regulador de tiempo, tiempos de MULUB/MULUW, el cambio de CPU (cada CPU conserva sus registros) con un R800 haciendo de Z80 y con el G80a real, la prueba de esfuerzo (1823 cambios al azar), el modo DRAM y el mapa de slots con un firmware sintético (`run_msx.sh` con `dramtest`/`slottest`) el arranque de la BIOS del FS-A1ST (`run_msx.sh`, que pide el firmware del usuario) y el mapper Panasonic del 3-3 (`run_panasonic.sh` con Icarus y `run_panasonic_msx.sh` con Z80 y R800 de verdad; apartado 19 del capítulo 15) |
| `run_arb2w.sh [semillas]` → `tb_arb2w.v`, `check_ids.py` y `run_arb2w_rnd.sh` (Icarus) | `axi_arb2w` (perfil Dual): con un `v9968_axi_backend` y un `memory_axi` reales detrás, y con dos maestros sintéticos de varias lecturas en vuelo contra un esclavo que responde fuera de orden; incluye los fallos de la primera placa (A con 6 bits de etiqueta; el reset de B a mitad de una ráfaga, de golpe y drenado), que deben dar `TB_FAIL` o `TB_OK` según el caso. Capítulo [14](14-perfil-dual.md), apartado 8.1 | `TB_OK (todo como se espera)` |
| `tb_vdp_trace.v` (Icarus) | El trazador de E/S del V9968 (`vdp_trace.v`): arma, genera VS/HS, tres accesos al puerto 1 e INT, y comprueba los eventos leídos. No tiene script: se compila a mano con `iverilog -g2012` | Sin errores |

### El V9990 (Verilator)

Los bancos del tiny9990 usan los mismos enables que `v9990_zynq.v`. Detalle del chip y del puente en el capítulo [13](13-v9990-geo3d.md).

| Script | Qué cubre |
|---|---|
| `run_t9990_timing.sh` (`tb_t9990_timing.sv`) | Geometría y temporización de P1, B1 y B3 con y sin paradas de la caché. Plusargs por `EXTRA`: `+BLIT=1` (motor de comandos, con `+AXI=1` por AXI; variantes `+BLIT4`, `+CMMC`, `+CMMM`, `+ORDEN`, `+P2NOTR`, `+YCC`), `+VTIM=1` con `+R7=8` (PAL: 313 líneas, DE 45..284, un VI cada 1.712.736 ciclos = 50,16 Hz; con `+MCS=1`, 290 líneas visibles) y `+REPLAY=` una traza de E/S de openMSX (`tools/v9990_trace/`) |
| `run_t9990_palette.sh` | R/G/B de las 64 entradas por P#1, en autoincremento y apuntando a cada componente: `PAL_OK` |
| `run_t9990_vscroll.sh` (`tb_t9990_vscroll.sv`) | R#17/R#21 escritos a mitad de pantalla reinician la cuenta de líneas del plano como en openMSX (el split de Xybots): qué línea de VRAM pide cada línea de pantalla en B1 y en los dos planos de P1, con la escritura en varios puntos de la línea, paradas de la caché y R#18 a mitad de cuadro; 14 casos, tres en PAL: `VSCROLL_OK` |
| `run_v9990_glue.sh` (`tb_v9990_glue.sv`) | El paso del bus del T80 al V9990, con el decode registrado y rebotes del chip-select: `GLUE_OK` |
| `run_msx2hdmi_v9990.sh` (`tb_msx2hdmi_v9990.v`, Icarus) | El puente V9990 → 720p con frame buffer, un modo por proceso: `run_msx2hdmi_v9990.sh [NFRAMES] [RESO ...]` con RESO 0..3 = B1..B4, 4 = B5 (640 × 400: ×2 desde cx 0 y ×1,5 en las líneas 60..659), 6 = B7 (1.136 px a ×1); sin lista, los seis de siempre. `EXTRA=-DIL=1` = fuente entrelazada (campos alternos tejidos en 480 líneas, ×1,5). Termina en `TB_OK` o `TB_FAIL` |
| `run_v9990_chain.sh` (`tb_v9990_chain.sv`) | La cadena entera hasta el frame buffer de la HDMI reproduciendo una traza de openMSX; `+LAT=`, `TOPBAND` y `TOPBORDER` para el lector del frame buffer y el borde superior |
| `run_v9990_edge.sh` | Bordes derecho e izquierdo del bitmap por la cadena entera (`+EDGE=1`, con `tools/v9990_trace/mk_edge.py`): BD16, BD8 y paleta, en B3 y B1, con y sin IL: `EDGE OK` |

### El V9991: el compositor y la ventana (Icarus)

Una sola HDMI para el V9968 y el V9990, mezclados por píxel (`fpga/video720/v9991_compose.sv`), la ventana del V9968 dentro del escritorio del V9990 y el gestor de ventanas por hardware.

| Script | Qué cubre |
|---|---|
| `run_v9991_compose.sh` (`tb_v9991_compose.sv`) | El compositor a solas: la salida es siempre la del modo activo (0 V9968, 1 V9990, 2 ventana, 3 Video9000) y el modo solo cambia en (0,720). La ventana por R#55-R#62 en B1..B5 y B7, con y sin entrelazado, ×1, ×2, ×0,5 y ×0,75, esquinas fuera y recortes, contra una geometría calculada aparte; `win_en` y la ventana de pantalla completa de los modos 0 y 3 (el V9968 por su frame buffer); fuera de la imagen del V9990 (`in99`) sale el escritorio. `TB_OK` |
| `run_v9991_wm.sh` (`tb_v9991_wm.sv`) | El gestor de ventanas por hardware (R#55 bit 1, `v9991_wm.sv`): el marco, la barra de título, la flecha, el arrastre con informes de ratón a 54 MHz, el tope de la pantalla, pulsar fuera de la barra y volver a la posición de los registros sin el bit; desde la Z1.3.2b9, que un clic en el cuadradito cian de la barra (y 2 px a cada lado) no arrastra y uno justo fuera sí. `+PPM=` vuelca el cuadro. `TB_OK` |
| `run_msx2hdmi_v9968_win.sh` (`tb_msx2hdmi_v9968_win.v`) | El puente del V9968 con `WINDOW`: fuente sintética de 858 × 525 y DDR de mentira; el modo enganchado de siempre, la ventana a ×1, ×2, ×0,5 y ×0,75 dentro y con la esquina fuera (×0,75 en las tres fases de columna) y la pantalla completa por el frame buffer (fase W). Cero píxeles malos, cero underruns y una petición por frame. `TB_OK` |
| `run_gp1_chain.sh` (`tb_gp1_chain.v`) | Los dos frame buffers a la vez por los dos árbitros AXI del GP1 hasta el compositor, con `-DAR_STALL=3` (el AR que se perdía con el árbitro bloqueado). `TB_OK` |
| `run_t9990_ys.sh`, `run_t9990_winreg.sh` | La salida Ys del core (`YS_OK`) y los registros R#55-R#62 del MSXimus Z en el tiny9990 (`WINREG_OK`) |
| `run_v9990_chain.sh` con `+FRAMEFULL=1` | El cuadro de 1280 × 720 entero (B5, B7): así se validan las ROM de demo (`tools/v9991b7/`) y el escritorio del menú (`build_menu_test.sh`: `MENUV.ROM` y `MENUB.ROM`) con `mk_trace.py` + `mk_replay.py` |

## 2. Bancos compartidos con el núcleo (`tools/`)

| Directorio | Qué cubre |
|---|---|
| `tools/v9968_sim/` (no incluido en esta copia) | El V9968 con escenas de referencia (pantallas, sprites, geometría de 80 columnas) comparadas cuadro a cuadro; `run_battery.sh`, `run_smoke.sh`, `check_all.sh`. `tb_t2drop.sv` (`run_t2drop_vl.sh`, **Verilator**, 30 s): TEXT2 con VPOKE y sondas por celda contra la VRAM perfecta, con `+CPUALL=1` (tablas por el puerto de CPU, como la BIOS) y `+TRACE=1`. `tb_t2zynq.sv` (`run_t2zynq_vl.sh`): la misma escena con la pila de memoria real de la Zynq (los dos bridges CDC, `v9968_axi_backend` y un esclavo AXI3 de 64 bits a 150 MHz asíncrono con latencia 20+rnd20). Los bancos de la pila completa (`tb_sprite3`, `tb_sprite3r`) también corren bajo Verilator: las tareas de bus usan asignaciones bloqueantes tras el flanco. `tb_g2cmd.sv` + `g2cmd_check.py`: HMMV/HMMM/YMMM en SCREEN 2. `tb_geo3d_int.sv` (`run_geo3d_int_vl.sh`): geo3d con el glue y el VDP completo por los puertos 9Dh/9Fh, contra el modelo del autor; con `+sc8 +vdump=` pone SCREEN 8 y vuelca la VRAM entera para compararla con otro RTL. `run_geo3d_hmmv.sh` (**Verilator**, ~1 min): los bancos de HRA del HMMV rápido de geo3d (`tb_geo3d_hmmv.sv`, `tb_geo3d_vdp_modes.sv`: una fila de geo3d frente a la misma LINE de la CPU, SCREEN 5-8, YJK, LOP, cambios de modo a mitad de fila y las caras del motor), adaptados a nuestros puertos. `tb_palette_yjk.sv` (`run_palette_yjk.sh`, Icarus): `vdp_color_palette.v` a solas en SCREEN 8, 10/11 y 12 contra un modelo del libro del V9958 (el píxel con A = 1 sale con su color de paleta, en su celda; con sprites desde la b10). `run_palette_yjk_ab.sh`: esa paleta frente a la de la b9 con estímulo aleatorio. `run_sprite_yjk.sh` (**Verilator**, ~1,5 min): el VDP completo, sprites frente a fondo en SCREEN 8, 10/11 y 12 |
| `tools/sd_tb/` | La DMA de la SD del núcleo (`sd_dma.sv`, capítulo [06](06-sd-dma.md)): `tb_sddma.sv` y compañía con un modelo de tarjeta; `run.sh` |
| `tools/megaram_tb/` | La megaram |
| `tools/opl3_sim/` | El FM del OPL3/OPL4. `run_shadow.sh`: el shadow de lectura sigue al latch de dirección. `run_timer_stop.sh` (**Verilator**): el timer parado en el ciclo exacto en que su preescalador da la vuelta (con 00h, 78h, 40h con el timer en FF y con /RESET): no se queda contando, el ack y el /RESET lo dejan limpio y los periodos son los del chip (T1 = 80,78 µs × n, T2 = 323,1 µs × n); `tb_timer.cpp` mide los periodos |
| `tools/opl4wave_sim/` | El motor wave del OPL4. Ver abajo |

### El motor wave del OPL4 (`tools/opl4wave_sim/`)

Los scripts con la YRW801 real necesitan `yrw801_2m.hex`, que no va en el repositorio; el resto usa una onda sintética. Las cifras son las que verifica cada banco.

| Script | Qué comprueba |
|---|---|
| `run_sim.sh` | Detección, memoria de ondas, carga de cabecera y nota |
| `tb_regrd.sv`, `run_rdmux.sh`, `run_rdnoise.sh` | Relectura de registros con el motor a solas; las colas con PRVB con la CPU releyendo registros por 7Fh sin parar (199 en todas); una nota sonando no cambia porque la CPU lea un registro (bit a bit idéntico) |
| `run_slotrd.sh` (`tb_slotrd.v`) | Un registro de slot del wavetable se relee bien **a la primera** por 7Fh, a través de `opl4_pcm.v` y con un Z80 que respeta /WAIT: los diez grupos (08h-F7h) × 24 slots con la fase del acceso barrida por semilla, en reposo y con seis slots sonando; mide cuánto dura /WAIT en cada IN 7Fh. Tres semillas, unas 12.700 lecturas |
| `run_pitch.sh`, `run_pan.sh` | Afinación y panorama (polaridad y ley de −3 dB por paso: pan 3 da L/R = 0,375) con la YRW801 |
| `run_tl.sh` (`tb_tl.v`) | El TL con LD=0 llega en ~15 ms al bajar 24 pasos y en ~7 ms al subir, sin patrón de 3 muestras, y TL=7Fh calla (tres fases en paralelo, ~40 s) |
| `run_env.sh` (`tb_envfn.v` + `tb_env.v`) | La envolvente: `EffRateCalc`, `EnvStep` y `EnvInc` contra openMSX/libvgm para todas las combinaciones y 2 M de pares tasa-contador, la nota con OCT=-4/RC=0/D2R=1 que no se apaga y el ataque con AR=9 de ~24 ms (~50 s) |
| `run_damp.sh` (`tb_damp.v`) | DAMP y PRVB: tras KEY OFF+DAMP la envolvente pasa −12/−48/−96 dB a 5,8/8,0/10,9 ms sea cual sea RC/OCT, PRVB baja a tasa 20 desde −18 dB, el ataque no se toca (12 fases en paralelo, ~110 s) |
| `run_lforst.sh` | El reset del LFO de 68h cae en su slot (`ALL=1` barre los 24) |
| `run_lforate.sh` (`tb_lforate.v`) | El acumulador de 18 bits del LFO avanza por muestra los pasos de openMSX 1/12/19/25/31/35/37/42 (de 0,168 a 7,066 Hz); un cambio de velocidad entra en ≤ 2 muestras; el reset por 68h bit 5 deja el contador a 0; con DL=0 el ataque pasa directo a DECAY2 (seis fases, ~2,5 min) |
| `run_idlefetch.sh` (`tb_idlefetch.v`) | Motor + `opl4_pcm` + una DDR3 simulada de 20-24 ciclos: en reposo no se lee memoria y la muestra dura 22,675 µs; con 24 voces agudas sonando informa del frenado conocido (octavas 3 y 7, ~8 min) |
| `run_amwrap.sh` (`tb_amwrap.v`) | La suma LEVEL+TL+ALFO: un slot ocioso con AM y TL=7Fh calla del todo; `LevelAddTLALFO` exhaustiva contra min(LEVEL+TL+ALFO, 3FFh); la nota normal con y sin AM conserva el trémolo (cuatro fases, ~4 min) |
| `run_memmode.sh` (`tb_memmode.v`) | El modo de acceso a memoria (reg 02h bit 0): durante la carga por 03h-06h `pcm_l` vale 0 exacto, y muestra a muestra cada salida es 0 o la del control sin modo memoria; el FIFO del pegamento retrasa la salida ~9 muestras (tres pasadas en paralelo, ~90 s) |
| `run_interp.sh` (`interp_medida.py`) | La interpolación lineal entre muestras: SNR de una senoide a seis pitches (50,2-50,8 dB en los fraccionarios, 48,8 a pitch entero) y mayor salto entre muestras ≤ 1,11 de la pendiente teórica |

Modelo de bus: los bancos del buzón llevan un esclavo AXI3 de 64 bits con memoria en un array, suficiente para el protocolo (ID, ráfagas, respuestas); la latencia real de la DDR se midió en placa (capítulo [01](01-arquitectura.md)). Funciones aisladas se prueban con bancos de un fichero que no se versionan (el atenuador del mezclador `mixk(v, k) = (v·k) >>> 3` se validó así, exacto para todos los k).

## 3. El companion en el PC (`fpga/zynq/arm/companion/tests/`)

Código real del companion compilado con `gcc` en WSL, con el hardware sustituido por imitaciones. Desde Git Bash los `/mnt/...` se estropean: lanzarlos desde PowerShell o con `wsl -d Ubuntu-24.04 -- bash …`.

| Banco | Qué cubre |
|---|---|
| `run.sh` (`test_hid_pad.c`) | El parser de mandos (`hid_pad.c`) con descriptores HID reales |
| `run_host_tape.sh <cintas…>` (`host_tape_test.c`, `compare_tape.py`) | `tape.c` tal cual con `TAPE_HOST`: convierte cada `.tsx` o `.cas`, decodifica los pulsos como la BIOS (piloto, arranque, 8 bits, paradas) y compara los bytes con el parser de Python. Imprime la orden de carga detectada (`TSX.LOAD`). Capítulo [10](10-cinta.md) |
| `run_host_yrw801.sh [rom]` (`host_yrw801_test.c`) | `yrw801.c` y su fila en la página de información: la ROM real da OK en 64 tramos de 32 KB; un byte cambiado, la flash en blanco y la ROM a cero dan MAL; sin acabar, «comprobando» |
| `ota_host/run_ota_host.sh <BOOT_A.bin> <carpeta del servidor>` (`ota_banco.c`) | La actualización por red entera: `ota.c` y `fsbl/fsbl_hooks.c` tal cual, con Mbed TLS de verdad (la firma) y de imitación la QSPI (semántica de una NOR, avisa si se toca fuera de la ranura B), la DDR, la red (servidor HTTP falso con los ficheros de `ota_publicar.py`, descubrimiento UDP) y el arranque (BootROM → hook del FSBL → companion en un proceso hijo; un reinicio del PS es un `longjmp`). Cada pantalla del OSD se vuelca a `$OTA_VOLCADO/NN_nombre.txt` para pintarla con `fpga/zynq/tools/osd_render.py`. Los casos 25 a 28 son la ranura A desde la SD (`bootsd_abre` y `bootsd_sig` de imitación, `BOOT_MODE` = SD). Capítulo [11](11-actualizacion.md) |
| `bootsd_host/run_host_bootsd.sh` (`gen_fat32.py`, `test_bootsd.c`) | `bootsd.c` tal cual (leer el `BOOT.bin` de la raíz de la FAT32 o FAT16 de TF1, para grabar la ranura A desde la SD) contra 27 imágenes dispersas (FAT32 y FAT16): sin tabla y con MBR, clusters de 512 B a 32 KB, fichero fragmentado y con tamaño que no es múltiplo de 512, nombres largos, borrados y etiquetas delante, raíz de varios clusters, justo 8 MB, tamaños fuera de rango, cadena de clusters rota, la tarjeta de perfiles con la P1 formateada en Windows (menos de 65 525 clusters, lo que falló en placa), FAT32 en una partición de tipo 83 o en la segunda entrada, un volumen pequeño, la FAT16 de tipo 0E de la segunda prueba en placa, FAT16 sin tabla con la raíz fija llena, FAT16 con la cadena rota, FAT16 vacías con y sin MBR, FAT12, exFAT, NTFS, GPT y sin tarjeta, con el texto de `bootsd_diag()` de cada rechazo; contenido comparado con un patrón y guarda de 0xAA tras el último byte, con AddressSanitizer y UBSan. Capítulo [11](11-actualizacion.md), sección 11 |

## 4. El menú, los drivers de Nextor y los packs

- `bios/build.sh` falla si una sección del menú se sale de su sitio, y `bios/tools/hacer_packs.py` comprueba byte a byte que solo cambian las ventanas previstas (capítulo [07](07-construccion.md)).
- `bios/tests/test_tf1_nextor.py` (Python, `pip install z80`): los drivers de Nextor 2.1.4 y 3 con un emulador Z80 y un «core» falso con los puertos #47-#4F, el #2F y el companion contestando el bloque de información de TF1; con y sin tarjeta, otro core, firma errónea, el bit 31 en lecturas y escrituras de 1 y 2 bloques, SP y SWIO restaurados y los códigos de error. Termina sin fallos.
- `tools/lint.sh`: lint estático del RTL con Verilator (`--lint-only -Wall`): señales muertas, redes implícitas, anchos, latches y dobles drivers.
- En la máquina, el menú de pruebas (tecla **T**, véase el manual) mide las cuatro rutas de lectura de la SD, el sonido, el Game Master 2 y el VDP; las rutas de DMA y de TF1 se contrastan con la telemetría de la sección 5.
- Los programas de prueba del V9968 (`tools/v9968_tests/*.COM`, `tools/msxtest/`) se ejecutan en la placa o en openMSX.

## 5. La placa desde xsdb

Con `hw_server` corriendo y SW1 en JTAG, `xsdb.bat tools/<script>.tcl` (desde `fpga/zynq`). Los que leen la DDR paran el core 1 del ARM (o el APU) y no tocan el MSX.

| Herramienta | Para qué |
|---|---|
| `boot.tcl` | Arranque completo por JTAG (capítulo [07](07-construccion.md)); `BOOT_PROXY`, `BOOT_IMG`, `FDD_IMG`, `WAVE_ROM`, `BOOT_ELF` |
| `program.tcl`, `detect.tcl`, `qspi_program.tcl` | Cargar un bitstream por JTAG, detectar la placa y grabar o leer la QSPI (en Vivado, no en xsdb) |
| `key.tcl RETURN ESC F11 …` / `key.tcl -type "texto"` | Pulsa teclas por el bitmap HID del buzón: el MSX las ve como el teclado USB |
| `screen.tcl [80]` | Vuelca la pantalla de texto leyendo la VRAM de la DDR: la forma de «ver» el menú sin monitor |
| `tel.tcl [n] [ms]` | Telemetría: caché, VDP, SD (proxy y disquetera), ratón, OPL4, V9990, UART del ESP, configuración, mezclador |
| `armlog.tcl` | El registro del companion, el SDBOX (W0-W14), el USB, el OSD y el buzón HID |
| `armpc.tcl [-hold]` | Dónde está el core 0: PC, LR, SP y pila (con `arm-none-eabi-addr2line -e companion.elf <pc>`) |
| `cfg.tcl show\|set\|mix` | El bloque de configuración y la siembra del mezclador |
| `wg.tcl status\|cmd\|msg\|vol\|gain\|ring` | WaveGame: estado, órdenes 92h, mensajes 93h, volumen |
| `tape.tcl status\|msg\|stop\|watch` | El reproductor de la cinta virtual (capítulo [10](10-cinta.md)) |
| `ota.tcl U\|I\|R\|F\|log` | La actualización por red sin teclado: manda la tecla al companion y enseña el final del log |
| `osd.tcl on\|off\|show`, `vsel.tcl`, `temp.tcl` | Panel F12 (congela el Z80), fuente de la HDMI (V9968 o V9990), temperatura y tensiones del die por el XADC |
| `vdptrace.tcl` | Arma el trazador del VDP (o solo los bytes del UART del ESP) y descifra el volcado |
| `vram.tcl`, `vramfill.tcl`, `alive.tcl` | Volcar o rellenar la VRAM de la DDR; comprobar que el MSX está vivo (JIFFY y VRAM) |
| `hid.tcl`, `pkttrace.tcl` | Escribir a mano el buzón HID (joysticks y ratón sin USB); trazas de segmentos TCP del companion |
| `psreset.tcl`, `msxreset.tcl [-cold]`, `packswap.tcl`, `clear_megaram.tcl`, `disk_save.tcl` | Reset del PS; reset del MSX solo (con `-cold` pone a cero los 64 KB de RAM); cambio de pack en caliente; borrar la megaram; volcar la imagen de disco de la DDR (modo imagen) |

Con esto se hacen pruebas de regresión repetibles sin manos: arrancar, pulsar S, entrar en el mezclador, cambiar niveles, guardar, rearrancar tres veces y comprobar con `screen.tcl` que los niveles vuelven. La entrega de una versión (capítulo [07](07-construccion.md), sección 9) pasa por una lista de este estilo, escrita en su `LEEME.txt`.

## 6. Referencias

Para el software estándar de MSX la referencia es openMSX (el fork de buppu3 para el V9968 de generación A). No hay emulador de la Zynq: el companion, el buzón y los backends AXI se verifican en los bancos y en placa.
