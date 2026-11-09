/* fdd.h — DISQUETERA USB del MSXimus Z vista desde el proxy de SD (main.c).
 *
 * El PL y Nextor no cambian: el companion presenta el disquete como una VENTANA DE LBA MAGICA del mismo
 * "dispositivo SD": los sectores [FDD_LBA_BASE, FDD_LBA_BASE + FDD_MAX_SECS) son el disquete (0..2879) y
 * el menu del MSX monta esa ventana como si fuera un .dsk (fichero de emulacion de Nextor apuntando a
 * FDD_LBA_BASE). Todo lo demas de la SD sigue igual. Ver fdd.c para los backends y el SDBOX.          */
#ifndef FDD_H
#define FDD_H
#include "xil_types.h"

#define FDD_LBA_BASE   0xFFFE0000U     /* mismo valor en bios/src/menu_main.asm (FLOPPY_LBA) */
#define FDD_MAX_SECS   2880U           /* 1,44 MB (2880) o 720 KB (1440) de 512 B */

/* resultado de fdd_read/fdd_write = ACK_STATUS que ve el PL (todo != 0 acaba en bit1 "timeout" del MSX) */
enum { FDD_OK = 0, FDD_NO_MEDIUM = 1, FDD_ERROR = 2 };

static inline int fdd_in_window(u32 sec) { return sec >= FDD_LBA_BASE && (sec - FDD_LBA_BASE) < FDD_MAX_SECS; }

void fdd_init(void);                    /* antes del bucle: campos del SDBOX a cero (boot.tcl no los limpia) */
void fdd_poll(void);                    /* cada vuelta del bucle: deteccion de medio (~1 s), disquete falso, publicar */
int  fdd_present(void);                 /* 1 = hay medio listo */
u32  fdd_sectors(void);                 /* sectores del medio (1440/2880; 0 sin medio) */
int  fdd_write_protected(void);
/* lba RELATIVA a la ventana (0..2879); buf alineado a 32 y en DDR (SDBUF). Bloquea el bucle hasta ~1,8 s. */
int  fdd_read(u32 lba, u32 cnt, u8 *buf);
int  fdd_write(u32 lba, u32 cnt, const u8 *buf);

/* desde usb_host.c (callbacks de TinyUSB, dentro de tuh_task_ext: solo toman nota) */
void fdd_ufi_mount(uint8_t daddr);
void fdd_ufi_umount(uint8_t daddr);
void fdd_msc_mount(uint8_t daddr);
void fdd_msc_umount(uint8_t daddr);

#endif
