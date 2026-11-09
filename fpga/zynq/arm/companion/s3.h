/* s3.h — la S3 (el ESP32 del CAM1) como red del companion cuando no hay cable (02/10/2026, s3_link.c). */
#ifndef S3_H
#define S3_H
#include "xil_types.h"

#define S3_MAX  2060U                           /* datos de una respuesta: TCP_RCV = 2 + 2048 */

typedef struct { u8 cmd, err; u16 n; u8 d[S3_MAX]; } s3_resp_t;
extern s3_resp_t s3r;                           /* la ultima respuesta */

/* la UART del ESP del CAM1 para el companion (y el MSX aparte) */
void s3_toma(void);
void s3_suelta(void);
int  s3_tomada(void);
int  s3_lista(void);                            /* tomada y pasados los 300 ms de silencio */

/* una orden: s3_pide la manda y s3_resp la espera sin bloquear (solo para respuestas cortas: DNS, TCP_OPEN, estado);
 * s3_orden manda y espera sin soltar (TCP_RCV, UDP_RCV...: la FIFO de la UART es de 64 B y no hay control de flujo) */
int  s3_pide(u8 cmd, const u8 *d, u32 n, u32 plazo_ms);   /* 1 enviada, 0 ya hay una pendiente */
int  s3_resp(void);                                       /* 1 hecha (en s3r), 0 aun no, -1 sin respuesta o mal */
int  s3_orden(u8 cmd, const u8 *d, u32 n, u32 plazo_ms);  /* 1 hecha (en s3r), -1 sin respuesta o mal */

/* lo que usa la actualizacion (todas bloquean lo que tarda la S3 en contestar: pocos ms) */
int  s3_ip(u8 ip[4]);                           /* la IP de la S3 en su WiFi (la ultima leida); 0 si no hay */
void s3_ip_lee(void);
int  s3_difusion(u8 d[4]);                      /* difusion dirigida de su red (IP | ~mascara); 0 si no se sabe */
u8   s3_udp_abre(void);                         /* conexion UDP (puerto al azar), 0 si no */
int  s3_udp_manda(u8 c, const u8 ip[4], u16 puerto, const u8 *d, u32 n);
int  s3_udp_lee(u8 c, u8 *d, u32 cap, u8 ip[4]);/* bytes del datagrama, 0 si no hay, -1 mal */
void s3_udp_cierra(u8 c);
int  s3_tcp_manda(u8 c, const u8 *d, u32 n);    /* 1 bien, -1 mal */
int  s3_tcp_lee(u8 c, u8 *d, u32 cap);          /* bytes (0 si aun nada), -1 la conexion ya no esta */
int  s3_tcp_estado(u8 c);                       /* 1 abierta o con datos, 0 cerrada, -1 sin respuesta */
void s3_tcp_cierra(u8 c);
#endif
