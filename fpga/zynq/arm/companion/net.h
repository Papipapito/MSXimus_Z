/* net.h — Ethernet del PS (GEM0 + lwIP por sondeo). P0, 25/09/2026. */
#ifndef NET_H
#define NET_H
void net_init(void);        /* tras osd_init(): configura el GEM0, arranca DHCP y el eco TCP del puerto 7 */
void net_poll(void);        /* cada vuelta del bucle principal (~1 ms): RX/TX, temporizadores, enlace */
#endif
