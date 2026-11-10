/* bootsd.h — leer el BOOT.bin de la raiz de la FAT32 o FAT16 de la TF1 (10/11/2026).
 * Sirve para grabar la ranura A de la QSPI desde la propia SD con la que arranca la placa (ota.c, tecla A con SW1 en SD): sin Vivado.
 * Lee solo (nunca escribe en la tarjeta). Acepta una FAT32 o FAT16 (lo que lee el BootROM; FAT12 no) con o sin tabla de particiones (la
 * primera particion que tenga una, sea cual sea su tipo en el MBR), de cualquier tamano de cluster; la FAT32 con cualquier numero de
 * clusters (se reconoce por la estructura, como Windows), y el nombre "BOOT.bin" en cualquier combinacion de mayusculas (el nombre corto es BOOT    BIN). El fichero puede estar
 * fragmentado. Va por trozos para no bloquear el bucle del companion: bootsd_abre() y luego bootsd_sig() hasta que n sea 0. */
#ifndef BOOTSD_H
#define BOOTSD_H
#include "xil_types.h"

enum { BSD_OK = 0, BSD_SIN_TARJETA, BSD_SIN_FAT32, BSD_SIN_BOOT, BSD_TAM, BSD_IO, BSD_CADENA };   /* SIN_FAT32 = ni FAT32 ni FAT16 */

#define BSD_TROZO   (32U * 1024U)                 /* bytes por llamada a bootsd_sig (64 sectores) */
#define BSD_MAX     0x00800000U                   /* la ranura A mide hasta 8 MB (la B empieza en 0x800000) */
#define BSD_MIN     0x00001000U                   /* menos que esto no es un BOOT.bin */

/* Localiza BOOT.bin en la raiz. 0 = bien y *tam = su tamano en bytes (entre BSD_MIN y BSD_MAX); si no, BSD_* */
int bootsd_abre(u32 *tam);

/* Lee el siguiente trozo (hasta BSD_TROZO bytes) a dst (memoria normal, con o sin cache). 0 = bien y *n = bytes leidos (0 = fin del
 * fichero); si no, BSD_IO o BSD_CADENA. */
int bootsd_sig(u8 *dst, u32 *n);

/* Tras un BSD_SIN_FAT32: lo que se ha visto en la tarjeta, en una linea de hasta BSD_DIAG caracteres ASCII para el OSD y el log
 * ("MBR 0E 00 00 00 P1:FAT12", "Sin MBR: exFAT", "Sector 0 sin 55AA"...). Vacio si no hay nada que contar. */
#define BSD_DIAG    27U
const char *bootsd_diag(void);

#endif
