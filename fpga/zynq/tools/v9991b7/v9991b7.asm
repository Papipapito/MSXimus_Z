; ===========================================================================
;  v9991b7.asm - V9991B7.ROM: el escritorio B7 del V9990 con la ventana del
;  V9968 dentro, para lanzarlo desde el menu del MSXimus Z (28/10/2026).
;
;  Cartucho de 16 KB. Su INIT pinta en el V9990 un escritorio en B7 (1024 x 212
;  a 4 bpp; con ILMODE = 1, 1024 x 424 entrelazado): fondo azul, marco de 1
;  punto en el borde de la imagen, marcas de columna cada 128 (verde, con su
;  numero), la ventana "Info" (gris con marco naranja y texto con la fuente de
;  la BIOS) y la ventana del V9968: el hueco de 512 x 106 en (256,53) relleno
;  del color 5, que es TRANSPARENTE (bit YS de paleta + YSE). Programa R#55-R#62
;  (ventana en WX = 256, WY = 53, escala x0,5: el MSX ENTERO, 256 x 212, en
;  512 x 318 px = 512 x 106 lineas de B7, lo que pinta Nishi), pone el V9968 en
;  SCREEN 0 con un mensaje y se queda en un bucle (lanzada desde el menu no hay
;  BASIC detras del INIT). A x1 el V9968 mediria 1024 puntos, todo el ancho de B7.
;  Para JUGAR dentro de la ventana: la tecla B del menu (bios/src/v9991.asm),
;  que pinta este mismo escritorio y lanza la ROM elegida.
;
;  29/10/2026 (V9991c): la ventana tiene un marco de escritorio (contorno negro,
;  biselado blanco/gris, cuerpo gris claro, barra de titulo azul marino con su
;  titulo y dos botones) y se ARRASTRA CON EL RATON: el raton MSX del puerto 2
;  (el raton USB del MSXimus) mueve un puntero en forma de flecha, que son los
;  dos cursores por hardware del V9990 (el 0 pinta el contorno negro, el 1 el
;  relleno blanco; paleta 13 y 14 con R#28 = 3). Con el boton izquierdo
;  pulsado sobre la barra de titulo la ventana sigue al puntero: el bucle
;  principal borra las franjas que deja al descubierto, pinta el marco y el
;  hueco en el sitio nuevo y reescribe R#56-R#59. Al soltar se repinta el resto
;  del escritorio (la ventana Info, las marcas y el borde que el arrastre pudo
;  pisar). La ventana no puede salir de la pantalla. DEMOMOVE = 1 (solo para
;  la traza de openMSX) arrastra la ventana sola sin raton.
;
;  Como lanzar una ROM desde el menu no reinicia la maquina, el escritorio se
;  queda. Desde el BASIC se mueve la ventana con OUT: OUT &H64,56:OUT &H63,x
;  (WX bajo), OUT &H64,57:OUT &H63,x>>8, OUT &H64,58:OUT &H63,y (WY); x1 con
;  OUT &H64,55:OUT &H63,&HA0 (x2 &HA8, x0,5 &HA4); apagar el V9990 con
;  OUT &H64,8:OUT &H63,0 (y Pausa vuelve al V9968). Solo usa los puertos
;  60h-67h y el PSG: en un MSXimus sin V9990 no pasa nada.
;
;  Con B5MODE = 1 (29/10/2026, V9991 paso 5) es V9991B5.ROM: el mismo escritorio en
;  B5 (640 x 400 a 4 bpp, HSCN; XIMM 1024, asi que la direccion de VRAM es la misma
;  y * 512 + x / 2), marcas de columna cada 80, y el hueco de 256 x 212 en (192,94): a
;  x2 / x1,5 en la HDMI son los mismos 512 x 318 px (384..896 x 201..519) que en B7, y
;  cada punto del V9968 a x0,5 cae en UN punto de B5.
;  Ensamblar: bios/bin/asmsx -z v9991b7.asm (ver build.sh al lado: saca las
;  ROM cambiando ILMODE / B5MODE / DEMOMOVE; los IF de asmsx son IF simbolo / ELSE / ENDIF, y se anidan).
; ===========================================================================

ILMODE=0						; 0 = 1024 x 212 progresivo · 1 = 1024 x 424 entrelazado (IL + EO)
B5MODE=0						; 1 = B5, 640 x 400 (HSCN), con ILMODE = 0
DEMOMOVE=0						; 1 = arrastre automatico (traza de openMSX, sin raton)

V9K_P0		equ	#60				; VRAM
V9K_P1		equ	#61				; paleta
V9K_P3		equ	#63				; dato de registro
V9K_P4		equ	#64				; numero de registro
V9K_P5		equ	#65				; estado (bit 0 = CE)
V9K_P7		equ	#67				; control del sistema
CGTABL		equ	#0004			; fuente de la BIOS (pag.0)
INITXT		equ	#006C			; BIOS: SCREEN 0
CHPUT		equ	#00A2			; BIOS: un caracter

; ---- geometria (en puntos y lineas del V9990; B7 en lineas de 212 tambien con ILMODE) ----
	IF B5MODE
SW		equ	640					; pantalla
SH		equ	400
HW		equ	256					; hueco (el V9968 a x0,5)
HH		equ	212
LE		equ	4					; el marco sobresale del hueco: izquierda, derecha, arriba, abajo
RE		equ	4
TE		equ	17
BE		equ	4
WX0		equ	192					; posicion inicial del hueco
WY0		equ	94
TXO		equ	6					; titulo respecto del hueco
TYO		equ	65524				; -12
SXSH	equ	1					; el raton va a medio punto en X (B5: un punto = 2 px)
YOFF	equ	404					; linea de la copia de la ventana, fuera de pantalla
MXFMAX	equ	1279
MYFMAX	equ	399
	ELSE
SW		equ	1024
SH		equ	212
HW		equ	512
HH		equ	106
LE		equ	7
RE		equ	7
TE		equ	12
BE		equ	3
WX0		equ	256
WY0		equ	53
TXO		equ	8
TYO		equ	65526				; -10
SXSH	equ	0
YOFF	equ	216					; linea de la copia de la ventana, fuera de pantalla (x2 con ILMODE)
MXFMAX	equ	1023
MYFMAX	equ	423					; Y a media linea (B7: una linea = 3 px)
	ENDIF
OW		equ	HW+LE+RE			; caja exterior de la ventana
OH		equ	HH+TE+BE
XMIN	equ	LE
XMAX	equ	SW-HW-RE
YMIN	equ	TE
YMAX	equ	SH-HH-BE
NLE		equ	65536-LE			; -LE y -TE para sumar
NTE		equ	65536-TE

; variables en RAM (pag.3)
VAR_X		equ	#C000			; x del texto (16 bits)
VAR_Y		equ	#C002			; y del texto (16 bits, ya doblada si IL)
VAR_COL		equ	#C004			; {fg, bg}
VAR_AL		equ	#C005			; direccion de VRAM del glifo: baja
VAR_AM		equ	#C006			;   media
VAR_AH		equ	#C007			;   alta
MXF			equ	#C010			; puntero en unidades finas (X << SXSH; Y << 1 en B7)
MYF			equ	#C012
MX			equ	#C014			; puntero en puntos / lineas
MY			equ	#C016
WXP			equ	#C018			; esquina del hueco
WYP			equ	#C01A
NWX			equ	#C01C			; esquina pedida por el arrastre
NWY			equ	#C01E
OFFX		equ	#C020			; puntero - hueco al empezar a arrastrar
OFFY		equ	#C022
DRAG		equ	#C024			; arrastrando
MOVED		equ	#C025			; la ventana se movio durante el arrastre
MBTN		equ	#C026			; R#14 del PSG tras leer el raton (bit 4 = boton izquierdo, activo bajo)
FRM			equ	#C027			; cuadros (DEMOMOVE)
BUF			equ	#C030			; rectangulo para fill16: x, y, w, h (16 bits), color

	.org #4000
	db   "AB"					; cabecera del cartucho
	dw   init
	dw   0, 0, 0, 0, 0, 0

init:
	xor  a
	out  (V9K_P7), a			; SRS = 0, MCS = 0 (maestro de 21 MHz)
	ld   hl, regs				; modo, pantalla apagada mientras se pinta
	call regtab
	ld   hl, pal				; paleta: 16 entradas x 3 bytes desde la 0
	ld   b, 48
.pl:
	ld   a, (hl)
	out  (V9K_P1), a
	inc  hl
	djnz .pl
	ld   de, #FF00				; patrones de los dos cursores (2 x 128 bytes en 7FF00h)
	ld   a, #07
	call vaddr
	ld   hl, curpat
	ld   bc, 256
.cp:
	ld   a, (hl)
	out  (V9K_P0), a
	inc  hl
	dec  bc
	ld   a, b
	or   c
	jr   nz, .cp
	ld   hl, bgrect				; el fondo
	call fill16
	ld   hl, LE					; la ventana entera, una vez, fuera de pantalla (0, YOFF): copywin la copia al moverla
	ld   (WXP), hl
	ld   hl, YOFF + TE
	ld   (WYP), hl
	call drawwin
	ld   hl, WX0
	ld   (WXP), hl
	ld   hl, WY0
	ld   (WYP), hl
	call redraw					; marcas, Info, textos y la ventana
	IF DEMOMOVE
	ld   hl, (WXP)				; el puntero sobre la barra de titulo
	ld   de, 40
	add  hl, de
	IF SXSH
	add  hl, hl
	ENDIF
	ld   (MXF), hl
	ld   hl, (WYP)
	ld   de, 65531				; -5
	add  hl, de
	IF B5MODE
	ELSE
	add  hl, hl
	ENDIF
	ld   (MYF), hl
	ELSE
	ld   hl, MXFMAX / 2			; el puntero en el centro
	ld   (MXF), hl
	ld   hl, MYFMAX / 2
	ld   (MYF), hl
	ENDIF
	xor  a
	ld   (DRAG), a
	ld   (MOVED), a
	ld   (FRM), a
	ld   a, #FF
	ld   (MBTN), a
	call ptrupd					; MX/MY y los atributos de los cursores
	ld   hl, wregs				; R#55-R#62: la ventana del V9968
	call regtab
	call setwregs
	ld   a, 28					; R#28 = 3: los cursores usan la paleta 12-15
	out  (V9K_P4), a
	ld   a, 3
	out  (V9K_P3), a
	ld   a, 8					; R#8 = DISP + YSE (SPD = 0: los cursores se ven)
	out  (V9K_P4), a
	ld   a, #A0
	out  (V9K_P3), a
	; lanzada desde el menu no hay BASIC detras del INIT (el menu salta al INIT como a un juego), asi que
	; la propia ROM pone el V9968 en SCREEN 0, escribe un mensaje y se queda moviendo la ventana
	call INITXT
	ld   hl, msg
.msg:
	ld   a, (hl)
	or   a
	jr   z, mainlp
	call CHPUT
	inc  hl
	jr   .msg

mainlp:
	ei
	halt
	IF DEMOMOVE
	call demomouse
	ELSE
	di							; la ISR de la BIOS tambien toca R#15 del PSG
	call rdmouse
	ei
	ENDIF
	ld   a, c
	ld   (MBTN), a
	push hl
	ld   a, h					; dx (el raton MSX lo da NEGADO: a la derecha es negativo)
	call sext
	ld   hl, (MXF)
	or   a
	sbc  hl, de
	ld   bc, MXFMAX
	call clampu
	ld   (MXF), hl
	pop  hl
	ld   a, l					; dy (negado tambien)
	call sext
	ld   hl, (MYF)
	or   a
	sbc  hl, de
	ld   bc, MYFMAX
	call clampu
	ld   (MYF), hl
	call ptrupd
	call dodrag
	jr   mainlp

; ---- dodrag: el arrastre de la ventana por su barra de titulo
dodrag:
	ld   a, (DRAG)
	or   a
	jr   nz, .on
	ld   a, (MBTN)
	bit  4, a
	ret  nz						; boton suelto
	ld   hl, (MX)				; dentro de la caja de arriba (la barra): MX - WXP + LE en [0, OW)
	ld   de, (WXP)
	or   a
	sbc  hl, de
	ld   de, LE
	add  hl, de
	ld   de, OW
	or   a
	sbc  hl, de
	ret  nc
	ld   hl, (MY)				; MY - WYP + TE en [0, TE)
	ld   de, (WYP)
	or   a
	sbc  hl, de
	ld   de, TE
	add  hl, de
	ld   de, TE
	or   a
	sbc  hl, de
	ret  nc
	ld   hl, (MX)
	ld   de, (WXP)
	or   a
	sbc  hl, de
	ld   (OFFX), hl
	ld   hl, (MY)
	ld   de, (WYP)
	or   a
	sbc  hl, de
	ld   (OFFY), hl
	ld   a, 1
	ld   (DRAG), a
	ret
.on:
	ld   a, (MBTN)
	bit  4, a
	jr   z, .mv
	xor  a						; soltado: fin del arrastre
	ld   (DRAG), a
	ld   a, (MOVED)
	or   a
	ret  z
	xor  a
	ld   (MOVED), a
	jp   redraw					; el resto del escritorio que el arrastre pudo pisar
.mv:
	ld   hl, (MX)
	ld   de, (OFFX)
	or   a
	sbc  hl, de
	ld   de, XMIN
	ld   bc, XMAX
	call clampr
	ld   (NWX), hl
	ld   hl, (MY)
	ld   de, (OFFY)
	or   a
	sbc  hl, de
	ld   de, YMIN
	ld   bc, YMAX
	call clampr
	ld   (NWY), hl
	ld   de, (WYP)
	or   a
	sbc  hl, de
	jr   nz, .go
	ld   hl, (NWX)
	ld   de, (WXP)
	or   a
	sbc  hl, de
	ret  z
.go:
	ld   a, 1
	ld   (MOVED), a
	jp   movewin

; ---- movewin: la ventana de (WXP, WYP) a (NWX, NWY). Borra (fondo azul) las franjas de la caja vieja que la
;      nueva no tapa, pinta el marco y el hueco en el sitio nuevo y reescribe R#56-R#59.
movewin:
	ld   a, #22
	ld   (BUF+8), a
	ld   hl, (NWX)				; franja vertical: d = NWX - WXP
	ld   de, (WXP)
	or   a
	sbc  hl, de
	jr   z, .ny
	jp   m, .xneg
	ld   bc, OW					; d > 0: [OX, OX + min(d, OW))
	call minbc
	ld   (BUF+4), hl
	ld   hl, (WXP)
	ld   de, NLE
	add  hl, de
	ld   (BUF), hl
	jr   .xs
.xneg:
	call neghl					; d < 0: [OX + OW - w, OX + OW) con w = min(-d, OW)
	ld   bc, OW
	call minbc
	ld   (BUF+4), hl
	ex   de, hl
	ld   hl, (WXP)
	ld   bc, OW - LE
	add  hl, bc
	or   a
	sbc  hl, de
	ld   (BUF), hl
.xs:
	ld   hl, (WYP)
	ld   de, NTE
	add  hl, de
	ld   (BUF+2), hl
	ld   hl, OH
	ld   (BUF+6), hl
	ld   hl, BUF
	call fill16
.ny:
	ld   hl, (NWY)				; franja horizontal: d = NWY - WYP
	ld   de, (WYP)
	or   a
	sbc  hl, de
	jr   z, .done
	jp   m, .yneg
	ld   bc, OH
	call minbc
	ld   (BUF+6), hl
	ld   hl, (WYP)
	ld   de, NTE
	add  hl, de
	ld   (BUF+2), hl
	jr   .ys
.yneg:
	call neghl
	ld   bc, OH
	call minbc
	ld   (BUF+6), hl
	ex   de, hl
	ld   hl, (WYP)
	ld   bc, OH - TE
	add  hl, bc
	or   a
	sbc  hl, de
	ld   (BUF+2), hl
.ys:
	ld   hl, (WXP)
	ld   de, NLE
	add  hl, de
	ld   (BUF), hl
	ld   hl, OW
	ld   (BUF+4), hl
	ld   hl, BUF
	call fill16
.done:
	call copywin				; la ventana entera (marco, titulo y hueco) desde su copia fuera de pantalla
	ld   hl, (NWX)
	ld   (WXP), hl
	ld   hl, (NWY)
	ld   (WYP), hl
	jp   setwregs

; ---- copywin: LMMM de la caja de la ventana (OW x OH) desde su copia fuera de pantalla (0, YOFF) a
;      (NWX - LE, NWY - TE). Pintar el marco y el titulo con la CPU en cada paso costaba unos 30 ms (dos cuadros).
copywin:
	ld   hl, 0
	ld   c, 32					; SX
	call wr16
	ld   hl, YOFF
	ld   c, 34					; SY
	call wr16y
	ld   hl, (NWX)
	ld   de, NLE
	add  hl, de
	ld   c, 36					; DX
	call wr16
	ld   hl, (NWY)
	ld   de, NTE
	add  hl, de
	ld   c, 38					; DY
	call wr16y
	ld   hl, OW
	ld   c, 40					; NX
	call wr16
	ld   hl, OH
	ld   c, 42					; NY
	call wr16y
	ld   hl, cpregs
	call regtab
.wt:
	in   a, (V9K_P5)
	rrca						; bit 0 = CE
	jr   c, .wt
	ret

; ---- wr16: R#C, R#C+1 = HL; wr16y: lo mismo con las lineas dobladas si ILMODE
wr16y:
	IF ILMODE
	add  hl, hl
	ENDIF
wr16:
	ld   a, c
	out  (V9K_P4), a
	ld   a, l
	out  (V9K_P3), a
	inc  c
	ld   a, c
	out  (V9K_P4), a
	ld   a, h
	out  (V9K_P3), a
	ret

; ---- redraw: marcas, borde, Info, textos y la ventana encima
redraw:
	ld   hl, srects
	ld   b, (hl)
	inc  hl
.rc:
	push bc
	call fill16
	pop  bc
	djnz .rc
	ld   hl, texts
	ld   b, (hl)
	inc  hl
.tt:
	push bc
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
	ld   (VAR_X), de
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
	IF ILMODE
	ex   de, hl
	add  hl, hl					; y * 2 en el cuadro de 424
	ex   de, hl
	ENDIF
	ld   (VAR_Y), de
	ld   a, (hl)
	inc  hl
	ld   (VAR_COL), a
	call prtxt					; deja HL tras el 0 final
	pop  bc
	djnz .tt
	; sigue en drawwin

; ---- drawwin: el marco (tabla chrome, relativa al hueco), el hueco y el titulo en (WXP, WYP)
drawwin:
	ld   hl, chrome
	ld   b, (hl)
	inc  hl
.e:
	push bc
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
	push hl
	ld   hl, (WXP)
	add  hl, de
	ld   (BUF), hl
	pop  hl
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
	push hl
	ld   hl, (WYP)
	add  hl, de
	ld   (BUF+2), hl
	pop  hl
	ld   de, BUF+4				; ancho, alto y color tal cual
	ld   bc, 5
	ldir
	push hl
	ld   hl, BUF
	call fill16
	pop  hl
	pop  bc
	djnz .e
	ld   hl, (WXP)
	ld   de, TXO
	add  hl, de
	ld   (VAR_X), hl
	ld   hl, (WYP)
	ld   de, TYO
	add  hl, de
	IF ILMODE
	add  hl, hl
	ENDIF
	ld   (VAR_Y), hl
	ld   a, #3A					; blanco sobre azul marino
	ld   (VAR_COL), a
	ld   hl, title
	jp   prtxt

; ---- setwregs: R#56-R#59 = la esquina del hueco
setwregs:
	ld   a, 56
	out  (V9K_P4), a
	ld   hl, (WXP)
	ld   a, l
	out  (V9K_P3), a
	ld   a, 57
	out  (V9K_P4), a
	ld   a, h
	and  7
	out  (V9K_P3), a
	ld   hl, (WYP)
	IF ILMODE
	add  hl, hl					; WY en lineas de 424
	ENDIF
	ld   a, 58
	out  (V9K_P4), a
	ld   a, l
	out  (V9K_P3), a
	ld   a, 59
	out  (V9K_P4), a
	ld   a, h
	and  7
	out  (V9K_P3), a
	ret

; ---- ptrupd: MX = MXF >> SXSH, MY = MYF (>> 1 en B7) y los atributos de los dos cursores (7FE00h, 8 bytes
;      cada uno, solo los pares: Y bajo, Y alto, X bajo, {C1 C0 EOR D 0 0 X9 X8})
ptrupd:
	ld   hl, (MXF)
	IF SXSH
	sra  h
	rr   l
	ENDIF
	ld   (MX), hl
	ld   hl, (MYF)
	IF B5MODE
	ELSE
	sra  h
	rr   l
	ENDIF
	ld   (MY), hl
	ld   de, #FE00
	ld   a, #07
	call vaddr
	ld   c, #40					; cursor 0: color 1 (paleta 13, negro): el contorno
	call .one
	ld   c, #80					; cursor 1: color 2 (paleta 14, blanco): el relleno
.one:
	ld   hl, (MY)					; tambien con ILMODE: el cursor del core cuenta en lineas de campo (212)
	ld   a, l
	out  (V9K_P0), a
	xor  a
	out  (V9K_P0), a
	ld   a, h
	and  1
	out  (V9K_P0), a
	xor  a
	out  (V9K_P0), a
	ld   hl, (MX)
	ld   a, l
	out  (V9K_P0), a
	xor  a
	out  (V9K_P0), a
	ld   a, h
	and  3
	or   c
	out  (V9K_P0), a
	xor  a
	out  (V9K_P0), a
	ret

; ---- vaddr: direccion de escritura de VRAM = A:D:E (19 bits), con autoincremento
vaddr:
	push af
	xor  a
	out  (V9K_P4), a
	ld   a, e
	out  (V9K_P3), a
	ld   a, 1
	out  (V9K_P4), a
	ld   a, d
	out  (V9K_P3), a
	ld   a, 2
	out  (V9K_P4), a
	pop  af
	and  7
	out  (V9K_P3), a
	ret

; ---- rdmouse: el raton MSX del puerto 2 (protocolo de 4 nibbles por el pin 8; ver fpga/src/msx_mouse.v).
;      Sale con H = dx, L = dy (con signo, negados como en un raton MSX) y C = R#14 (bit 4/5 = botones, bajo).
rdmouse:
	ld   a, 15
	out  (#A0), a
	in   a, (#A2)
	and  #80					; el LED de kana tal cual
	or   #6C					; puerto 2, pin 8 del puerto 2 alto, pines 6/7 altos
	ld   d, a
	ld   e, #20					; el pin 8 del puerto 2 cambia en cada lectura
	ld   b, 30
	call .rd0					; X alto
	add  a, a
	add  a, a
	add  a, a
	add  a, a
	ld   c, a
	call .rd					; X bajo
	and  #0F
	or   c
	ld   h, a
	call .rd					; Y alto
	add  a, a
	add  a, a
	add  a, a
	add  a, a
	ld   c, a
	call .rd					; Y bajo
	push af
	and  #0F
	or   c
	ld   l, a
	pop  af
	ld   c, a
	ld   a, h					; dx = dy = #FF: no hay raton (el joystick en reposo lee todo a 1), quieto
	and  l
	inc  a
	ret  nz
	ld   hl, 0
	ret
.rd:
	ld   b, 10
.rd0:
	ld   a, 15
	out  (#A0), a
	ld   a, d
	out  (#A1), a
	xor  e
	ld   d, a
	ld   a, 14
	out  (#A0), a
.w:
	djnz .w
	in   a, (#A2)
	ret

	IF DEMOMOVE
; ---- demomouse: sin raton (traza de openMSX): 20 cuadros quieto, 40 arrastrando hacia abajo a la derecha, suelta
demomouse:
	ld   a, (FRM)
	inc  a
	jr   z, .sat
	ld   (FRM), a
.sat:
	ld   hl, 0
	ld   c, #FF
	cp   20
	ret  c
	cp   60
	ret  nc
	ld   hl, #FDFF				; dx = -3 (derecha), dy = -1 (abajo)
	ld   c, #EF					; boton izquierdo pulsado
	ret
	ENDIF

; ---- sext: DE = A con signo
sext:
	ld   e, a
	add  a, a
	sbc  a, a
	ld   d, a
	ret

; ---- neghl: HL = -HL
neghl:
	ld   a, l
	cpl
	ld   l, a
	ld   a, h
	cpl
	ld   h, a
	inc  hl
	ret

; ---- minbc: HL = min(HL, BC) sin signo
minbc:
	push hl
	or   a
	sbc  hl, bc
	pop  hl
	ret  c
	ld   h, b
	ld   l, c
	ret

; ---- clampu: HL con signo a [0, BC]
clampu:
	bit  7, h
	jr   z, minbc
	ld   hl, 0
	ret

; ---- clampr: HL con signo a [DE, BC] (DE y BC positivos)
clampr:
	push hl
	or   a
	sbc  hl, de
	pop  hl
	jp   p, .ge
	ex   de, hl
	ret
.ge:
	push hl
	or   a
	sbc  hl, bc
	pop  hl
	ret  m
	ld   h, b
	ld   l, c
	ret

; ---- regtab: tabla {reg, valor} terminada en #FF
regtab:
	ld   a, (hl)
	cp   #FF
	ret  z
	out  (V9K_P4), a
	inc  hl
	ld   a, (hl)
	out  (V9K_P3), a
	inc  hl
	jr   regtab

; ---- fill16: LMMV del rectangulo {dx, dy, nx, ny (16 bits cada uno), color}
;      al que apunta HL. DY y NY se doblan con ILMODE. Sale con HL += 9.
fill16:
	ld   c, 36
	call .pair					; DX
	ld   c, 38
	call .pairy					; DY
	ld   c, 40
	call .pair					; NX
	ld   c, 42
	call .pairy					; NY
	ld   a, 45
	out  (V9K_P4), a
	ld   a, #0C					; LOP = IMP
	out  (V9K_P3), a
	ld   a, 46
	out  (V9K_P4), a
	ld   a, #FF					; mascara de escritura
	out  (V9K_P3), a
	ld   a, 47
	out  (V9K_P4), a
	ld   a, #FF
	out  (V9K_P3), a
	ld   a, 48
	out  (V9K_P4), a
	ld   a, (hl)				; color (dos pixeles de 4 bits)
	out  (V9K_P3), a
	ld   a, 49
	out  (V9K_P4), a
	ld   a, (hl)
	out  (V9K_P3), a
	inc  hl
	ld   a, 52
	out  (V9K_P4), a
	ld   a, #20					; LMMV
	out  (V9K_P3), a
.wait:
	in   a, (V9K_P5)
	rrca						; bit 0 = CE
	jr   c, .wait
	ret
.pairy:
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
	IF ILMODE
	ex   de, hl
	add  hl, hl					; lineas x 2
	ex   de, hl
	ENDIF
	jr   .pw
.pair:
	ld   e, (hl)
	inc  hl
	ld   d, (hl)
	inc  hl
.pw:
	ld   a, c
	out  (V9K_P4), a
	ld   a, e
	out  (V9K_P3), a
	inc  c
	ld   a, c
	out  (V9K_P4), a
	ld   a, d
	out  (V9K_P3), a
	ret

; ---- prtxt: cadena ASCIIZ en HL en (VAR_X, VAR_Y) con VAR_COL. Sale con HL
;      tras el 0 final. x += 8 por caracter.
prtxt:
	ld   a, (hl)
	inc  hl
	or   a
	ret  z
	push hl
	call prchar
	ld   hl, (VAR_X)
	ld   bc, 8
	add  hl, bc
	ld   (VAR_X), hl
	pop  hl
	jr   prtxt

; ---- prchar: el caracter A en (VAR_X, VAR_Y). B7 a 4 bpp: 512 bytes por linea,
;      direccion = y * 512 + x / 2 (18 bits: baja = x/2, media = y*2 | x>>9,
;      alta = y>>7). Cada bit del glifo es un nibble: 1 = fg, 0 = bg. Con
;      ILMODE cada fila del glifo se pinta dos veces (8 x 16 en las 424).
prchar:
	ld   l, a
	ld   h, 0
	add  hl, hl
	add  hl, hl
	add  hl, hl					; * 8
	ld   bc, (CGTABL)
	add  hl, bc
	push hl
	pop  ix						; IX -> glifo
	ld   hl, (VAR_Y)
	add  hl, hl					; HL = y * 2
	ld   de, (VAR_X)
	srl  d
	rr   e						; DE = x / 2 (D = bit 8)
	ld   a, l
	or   d
	ld   (VAR_AM), a			; media
	ld   a, h
	ld   (VAR_AH), a			; alta
	ld   a, e
	ld   (VAR_AL), a			; baja
	ld   b, 8
.rw:
	push bc
	ld   e, (ix+0)				; la fila del glifo
	inc  ix
	IF ILMODE
	ld   d, e
	call .ln
	ld   e, d
	ENDIF
	call .ln
	pop  bc
	djnz .rw
	ret
.ln:							; pinta la fila E (4 bytes) y baja una linea de VRAM
	push de
	ld   a, 0					; R#0 = direccion baja
	out  (V9K_P4), a
	ld   a, (VAR_AL)
	out  (V9K_P3), a
	ld   a, 1					; R#1 = media
	out  (V9K_P4), a
	ld   a, (VAR_AM)
	out  (V9K_P3), a
	ld   a, 2					; R#2 = alta (bit 7 = 0: autoincremento)
	out  (V9K_P4), a
	ld   a, (VAR_AH)
	and  7
	out  (V9K_P3), a
	ld   a, (VAR_COL)
	ld   c, a
	ld   b, 4
.nib:
	rl   e						; CF = bit mas alto: nibble ALTO
	ld   a, c					; A = {fg, bg}
	jr   c, .hi
	rrca
	rrca
	rrca
	rrca						; A = {bg, fg}
.hi:
	and  #F0
	ld   d, a
	rl   e						; siguiente bit: nibble BAJO
	ld   a, c					; A = {fg, bg}: bajo = bg si el bit es 0
	jr   nc, .lo
	rrca
	rrca
	rrca
	rrca						; A = {bg, fg}: bajo = fg
.lo:
	and  #0F
	or   d
	out  (V9K_P0), a
	djnz .nib
	ld   hl, (VAR_AM)			; L = media, H = alta: + 512 bytes = media + 2
	ld   bc, 2
	add  hl, bc
	ld   (VAR_AM), hl
	pop  de
	ret

; ---- tablas ----
regs:
	db   8, #00					; pantalla apagada
	db   6, #A9					; bitmap, DCKM 1/1, XIMM 1024, 4 bpp = B7 (B5: 640 puntos en lineas de 1024)
	IF B5MODE
	db   7, #01					; HSCN: B5, 640 x 400
	ELSE
	IF ILMODE
	db   7, #06					; EO + IL: 424 lineas
	ELSE
	db   7, #00
	ENDIF
	ENDIF
	db   13, #00				; paleta: R, G, B, sin YUV
	db   14, #00				; puntero de paleta
	db   15, #02				; BDC = 2 (azul, como el fondo)
	db   #FF

pal:							; R (bit 7 = YS), G, B
	db   #80, #00, #00			; 0 negro transparente
	db   #1F, #10, #00			; 1 naranja
	db   #08, #08, #1F			; 2 azul (el fondo)
	db   #1F, #1F, #1F			; 3 blanco
	db   #08, #08, #08			; 4 gris
	db   #80, #00, #00			; 5 negro TRANSPARENTE (el hueco)
	db   #00, #1F, #00			; 6 verde
	db   #1C, #04, #04			; 7 rojo
	db   #07, #07, #09			; 8 gris oscuro (biselado)
	db   #15, #15, #17			; 9 gris claro (el marco)
	db   #02, #04, #10			; 10 azul marino (la barra de titulo)
	db   #0C, #10, #1C			; 11 azul claro
	db   #00, #00, #00			; 12 negro
	db   #00, #00, #00			; 13 cursor: contorno de la flecha (R#28 = 3, color 1)
	db   #1F, #1F, #1F			; 14 cursor: relleno de la flecha (color 2)
	db   #10, #10, #10			; 15 gris medio

bgrect:
	IF B5MODE
	dw   0, 0, 640, 400
	ELSE
	dw   0, 0, 1024, 212
	ENDIF
	db   #22					; fondo azul

srects:							; cuenta, {dx, dy, nx, ny (16 bits), color}; dy/ny en lineas de 212
	IF B5MODE
	db   13
	dw   0, 0, 640, 1
	db   #33					; marco de 1 punto (blanco)
	dw   0, 399, 640, 1
	db   #33					; 
	dw   0, 0, 1, 400
	db   #33					; 
	dw   639, 0, 1, 400
	db   #33					; 
	dw   80, 0, 1, 8
	db   #66					; marcas de columna (verde) cada 80
	dw   160, 0, 1, 8
	db   #66					; 
	dw   240, 0, 1, 8
	db   #66					; 
	dw   320, 0, 1, 8
	db   #66					; 
	dw   400, 0, 1, 8
	db   #66					; 
	dw   480, 0, 1, 8
	db   #66					; 
	dw   560, 0, 1, 8
	db   #66					; 
	dw   8, 16, 232, 48
	db   #11					; ventana Info: marco naranja
	dw   10, 18, 228, 44
	db   #44					;   cuerpo gris
	ELSE
	db   13
	dw   0, 0, 1024, 1
	db   #33					; marco de 1 punto (blanco)
	dw   0, 211, 1024, 1
	db   #33					; 
	dw   0, 0, 1, 212
	db   #33					; 
	dw   1023, 0, 1, 212
	db   #33					; 
	dw   128, 0, 1, 8
	db   #66					; marcas de columna (verde)
	dw   256, 0, 1, 8
	db   #66					; 
	dw   384, 0, 1, 8
	db   #66					; 
	dw   512, 0, 1, 8
	db   #66					; 
	dw   640, 0, 1, 8
	db   #66					; 
	dw   768, 0, 1, 8
	db   #66					; 
	dw   896, 0, 1, 8
	db   #66					; 
	dw   8, 16, 232, 48
	db   #11					; ventana Info: marco naranja
	dw   10, 18, 228, 44
	db   #44					;   cuerpo gris
	ENDIF

chrome:							; el marco de la ventana: cuenta, {dx, dy (con signo, respecto del hueco), nx, ny, color}, en orden
	IF B5MODE
	db   17
	dw   65532, 65519, 264, 1
	db   #CC					; contorno negro: arriba
	dw   65532, 215, 264, 1
	db   #CC					; abajo
	dw   65532, 65519, 1, 233
	db   #CC					; izquierda
	dw   259, 65519, 1, 233
	db   #CC					; derecha
	dw   65533, 65520, 262, 1
	db   #33					; biselado claro: arriba
	dw   65533, 65520, 1, 231
	db   #33					; izquierda
	dw   65533, 214, 262, 1
	db   #88					; biselado oscuro: abajo
	dw   258, 65520, 1, 231
	db   #88					; derecha
	dw   65534, 65521, 2, 229
	db   #99					; cuerpo gris: izquierda
	dw   256, 65521, 2, 229
	db   #99					; derecha
	dw   0, 65521, 256, 1
	db   #99					; sobre la barra
	dw   0, 65534, 256, 2
	db   #99					; bajo la barra
	dw   0, 212, 256, 2
	db   #99					; bajo el hueco
	dw   0, 65522, 256, 12
	db   #AA					; barra de titulo (azul marino)
	dw   244, 65524, 9, 8
	db   #77					; boton rojo
	dw   232, 65524, 9, 8
	db   #99					; boton gris
	dw   0, 0, 256, 212
	db   #55					; el hueco TRANSPARENTE: 256 x 212 puntos de B5 = el MSX a x0,5, punto a punto
	ELSE
	db   16
	dw   65529, 65524, 526, 1
	db   #CC					; contorno negro: arriba
	dw   65529, 108, 526, 1
	db   #CC					; abajo
	dw   65529, 65524, 1, 121
	db   #CC					; izquierda
	dw   518, 65524, 1, 121
	db   #CC					; derecha
	dw   65530, 65525, 524, 1
	db   #33					; biselado claro: arriba
	dw   65530, 65525, 1, 119
	db   #33					; izquierda
	dw   65530, 107, 524, 1
	db   #88					; biselado oscuro: abajo
	dw   517, 65525, 1, 119
	db   #88					; derecha
	dw   65531, 65526, 5, 117
	db   #99					; cuerpo gris: izquierda
	dw   512, 65526, 5, 117
	db   #99					; derecha
	dw   0, 65535, 512, 1
	db   #99					; bajo la barra
	dw   0, 106, 512, 1
	db   #99					; bajo el hueco
	dw   0, 65526, 512, 9
	db   #AA					; barra de titulo (azul marino)
	dw   498, 65527, 10, 7
	db   #77					; boton rojo
	dw   484, 65527, 10, 7
	db   #99					; boton gris
	dw   0, 0, 512, 106
	db   #55					; el hueco TRANSPARENTE: 512 x 106 = el MSX a x0,5
	ENDIF

texts:							; cuenta, {x, y (16 bits, y en lineas de 212), col, cadena, 0}
	IF B5MODE
	db   11
	dw   14, 20
	db   #34, "MSXimus Z  V9991", 0
	dw   14, 30
	db   #34, "B5 640x400 4bpp", 0
	dw   14, 40
	db   #34, "Arrastra la barra", 0
	dw   82, 2
	db   #32, "80", 0
	dw   162, 2
	db   #32, "160", 0
	dw   242, 2
	db   #32, "240", 0
	dw   322, 2
	db   #32, "320", 0
	dw   402, 2
	db   #32, "400", 0
	dw   482, 2
	db   #32, "480", 0
	dw   562, 2
	db   #32, "560", 0
	dw   603, 2
	db   #32, "639", 0
	ELSE
	db   11
	dw   14, 20
	db   #34, "MSXimus Z  V9991", 0
	dw   14, 30
	IF ILMODE
	db   #34, "B7 1024x424 IL 4bpp", 0
	ELSE
	db   #34, "B7 1024x212 4bpp", 0
	ENDIF
	dw   14, 40
	db   #34, "Arrastra la barra", 0
	dw   130, 2
	db   #32, "128", 0
	dw   258, 2
	db   #32, "256", 0
	dw   386, 2
	db   #32, "384", 0
	dw   514, 2
	db   #32, "512", 0
	dw   642, 2
	db   #32, "640", 0
	dw   770, 2
	db   #32, "768", 0
	dw   898, 2
	db   #32, "896", 0
	dw   987, 2
	db   #32, "1023", 0
	ENDIF

title:
	db   "MSX  -  V9968", 0

msg:
	IF B5MODE
	db   "V9991 B5: este V9968 a x0,5 en la ventana", 13, 10
	db   "del escritorio B5 (640x400) del V9990:", 13, 10
	db   "256x212 puntos, uno por punto del MSX.", 13, 10, 13, 10
	ELSE
	db   "V9991 B7: este V9968 a x0,5 en la ventana", 13, 10
	db   "del escritorio B7 del V9990 (512x318 px).", 13, 10, 13, 10
	ENDIF
	db   "Raton en el puerto 2: arrastra la ventana", 13, 10
	db   "cogiendola por su barra de titulo.", 13, 10, 13, 10
	db   "Pausa: V9968 entero / ventana.", 13, 10
	db   "Reset para salir.", 13, 10, 0

cpregs:							; LMMM: ARG 0, LOP = IMP, mascara entera, orden
	db   44, #00
	db   45, #0C
	db   46, #FF
	db   47, #FF
	db   52, #40
	db   #FF

wregs:							; R#55 y R#60-R#62 (WX/WY los pone setwregs): la ventana del V9968, origen 0, todo, x0,5
	db   55, #A4				; WEN, MODE 01 (ventana), sin bordes, x0,5 (bit 2)
	db   60, 0					; SRCX
	db   61, 0					; SRCY
	db   62, 0					; SRCH = todo
	db   #FF

curpat:							; los dos cursores (32 x 32 a 1 bpp, 4 bytes por linea): el 0 es el contorno de la flecha, el 1 el relleno
	IF B5MODE					; B5: un punto = 2 x 1,5 px
	db   #80, #00, #00, #00, #C0, #00, #00, #00, #A0, #00, #00, #00, #90, #00, #00, #00
	db   #88, #00, #00, #00, #84, #00, #00, #00, #82, #00, #00, #00, #81, #00, #00, #00
	db   #80, #80, #00, #00, #87, #C0, #00, #00, #B2, #00, #00, #00, #D2, #00, #00, #00
	db   #89, #00, #00, #00, #04, #80, #00, #00, #06, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #40, #00, #00, #00, #60, #00, #00, #00
	db   #70, #00, #00, #00, #78, #00, #00, #00, #7C, #00, #00, #00, #7E, #00, #00, #00
	db   #7F, #00, #00, #00, #78, #00, #00, #00, #4C, #00, #00, #00, #0C, #00, #00, #00
	db   #06, #00, #00, #00, #03, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	ELSE						; B7: un punto = 1 x 3 px (flecha aplastada en vertical)
	db   #80, #00, #00, #00, #A0, #00, #00, #00, #88, #00, #00, #00, #82, #00, #00, #00
	db   #80, #80, #00, #00, #80, #20, #00, #00, #8F, #E0, #00, #00, #B2, #00, #00, #00
	db   #C9, #00, #00, #00, #06, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #40, #00, #00, #00, #70, #00, #00, #00, #7C, #00, #00, #00
	db   #7F, #00, #00, #00, #7F, #C0, #00, #00, #70, #00, #00, #00, #4C, #00, #00, #00
	db   #06, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	db   #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
	ENDIF

	; (build.sh rellena hasta 16 KB; asmsx recorta los ceros finales)
