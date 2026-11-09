/******************************************************************************
*
* Copyright (C) 2012 - 2014 Xilinx, Inc.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
*
******************************************************************************/

/*****************************************************************************
* fsbl_hooks.c del zynq_fsbl de Xilinx (Vivado 2019.2) con UN cambio del MSXimus (30/09/2026): la ranura B de la
* actualizacion por red (companion/ota.c).
*
* La QSPI lleva dos BOOT.bin: la ranura A en 0 (la "de fabrica", la que se graba por JTAG; nunca la toca la
* actualizacion) y la ranura B en 0x800000 (la que baja el companion). Al encender, el BootROM arranca SIEMPRE la A
* (MULTIBOOT = 0) y este FSBL, antes de cargar el bitstream, mira el registro de la actualizacion (sector 0xFFE000):
* si hay una B CONFIRMADA (ya arranco bien una vez en esta placa) con cabecera valida, pone MULTIBOOT = 0x100
* (0x800000 / 32 KB) y reinicia el PS: el BootROM carga entonces el FSBL de la B y ese FSBL (MULTIBOOT != 0) carga
* sus particiones desde 0x800000 (image_mover.c suma el desplazamiento de MULTIBOOT). Cuesta ~0,1 s.
* Una B SIN confirmar no la arranca el FSBL: la prueba la lanza el companion de la A contando intentos (tres como
* mucho), asi que una B que no arranca vuelve sola a la A en el siguiente encendido. Aqui solo se LEE la QSPI
* (ventana lineal 0xFC000000): nada que pueda estropearla.
* Formato del registro: ota.c (la misma disposicion de bytes; CRC-32 de los 0x54 primeros en +0x54).
******************************************************************************/

#include "fsbl.h"
#include "xstatus.h"
#include "fsbl_hooks.h"

#define OTA_QSPI_LIN     0xFC000000U                 /* ventana lineal de la QSPI (el FSBL la deja en modo lineal) */
#define OTA_REG          0x00FFE000U                 /* registro de la actualizacion */
#define OTA_SLOT_B       0x00800000U
#define OTA_MB_B         (OTA_SLOT_B / 0x8000U)      /* MULTIBOOT en unidades de 32 KB */
#define OTA_MULTIBOOT    0xF800702CU                 /* devcfg MULTIBOOT_ADDR */
#define OTA_SLCR_UNLOCK  0xF8000008U

static u32 ota_crc32(const volatile u8 *p, u32 n)
{
	u32 c = 0xFFFFFFFFU, k;
	while (n--) {
		c ^= *p++;
		for (k = 0; k < 8U; k++) c = (c >> 1) ^ (0xEDB88320U & (0U - (c & 1U)));
	}
	return ~c;
}

static u32 ota_rd32(u32 a)
{
	const volatile u8 *p = (const volatile u8 *)(OTA_QSPI_LIN + a);
	return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24);
}

static int ota_b_confirmada(void)
{
	const volatile u8 *r = (const volatile u8 *)(OTA_QSPI_LIN + OTA_REG);
	u32 sum = 0, a;
	if (r[0] != 'M' || r[1] != 'O' || r[2] != 'T' || r[3] != 'A' || r[4] != 1U) return 0;
	if (ota_crc32(r, 0x54U) != ota_rd32(OTA_REG + 0x54U)) return 0;
	if (ota_rd32(OTA_REG + 0x10U) != OTA_SLOT_B) return 0;
	if (r[0x88] != 0x00U) return 0;                       /* sin confirmar: la prueba es cosa del companion */
	if (ota_rd32(OTA_SLOT_B + 0x20U) != 0xAA995566U || ota_rd32(OTA_SLOT_B + 0x24U) != 0x584C4E58U) return 0;
	for (a = 0x20U; a <= 0x44U; a += 4U) sum += ota_rd32(OTA_SLOT_B + a);
	return ~sum == ota_rd32(OTA_SLOT_B + 0x48U);          /* suma de la cabecera de arranque (UG585 tabla 6-3) */
}

/******************************************************************************
* Hook antes del bitstream: la ranura B (ver arriba). Solo con arranque QSPI y desde la A (MULTIBOOT = 0).
****************************************************************************/
u32 FsblHookBeforeBitstreamDload(void)
{
	if ((Xil_In32(BOOT_MODE_REG) & BOOT_MODES_MASK) == QSPI_MODE && (Xil_In32(OTA_MULTIBOOT) & 0x1FFFU) == 0U &&
			ota_b_confirmada()) {
		fsbl_printf(DEBUG_GENERAL, "MSXimus OTA: ranura B confirmada -> MULTIBOOT 0x%x y reinicio\r\n", OTA_MB_B);
		Xil_Out32(OTA_MULTIBOOT, OTA_MB_B);
		Xil_Out32(OTA_SLCR_UNLOCK, 0xDF0DU);
		dsb(); isb();
		Xil_Out32(PS_RST_CTRL_REG, PS_RST_MASK);
		while (1) ;
	}
	return XST_SUCCESS;
}

/******************************************************************************
* This function is the hook which will be called  after the bitstream download.
****************************************************************************/
u32 FsblHookAfterBitstreamDload(void)
{
	fsbl_printf(DEBUG_INFO, "In FsblHookAfterBitstreamDload function \r\n");
	return XST_SUCCESS;
}

/******************************************************************************
* This function is the hook which will be called  before the FSBL does a handoff
* to the application.
****************************************************************************/
u32 FsblHookBeforeHandoff(void)
{
	fsbl_printf(DEBUG_INFO,"In FsblHookBeforeHandoff function \r\n");
	return XST_SUCCESS;
}

/******************************************************************************
* This function is the hook which will be called in case FSBL fall back
****************************************************************************/
void FsblHookFallback(void)
{
	fsbl_printf(DEBUG_INFO,"In FsblHookFallback function \r\n");
	while(1);
}
