/* lwipopts.h — lwIP 2.1.1 en el companion (bare-metal, NO_SYS, API raw). 25/09/2026, P0 Ethernet.
 * Sale de la plantilla del puerto Xilinx (lwip211_v1_1/contrib/ports/xilinx/include/lwipopts.h)
 * con lo que hace falta para DHCP + DNS + TCP/UDP desde el bucle principal, sin interrupciones. */
#ifndef __LWIPOPTS_H__
#define __LWIPOPTS_H__

#define NO_SYS                          1
#define SYS_LIGHTWEIGHT_PROT            0
#define LWIP_CALLBACK_API               1
#define LWIP_NETCONN                    0
#define LWIP_SOCKET                     0
#define LWIP_COMPAT_SOCKETS             0
#define LWIP_ERRNO_STDINCLUDE           1
#define LWIP_TIMERS                     1

/* memoria: todo en .bss (strongly-ordered con la MMU de mmu.c, asi que la DMA del GEM la ve tal cual) */
#define MEM_ALIGNMENT                   64
#define MEM_SIZE                        (256 * 1024)
#define MEMP_NUM_PBUF                   64
#define MEMP_NUM_UDP_PCB                8
#define MEMP_NUM_TCP_PCB                8
#define MEMP_NUM_TCP_PCB_LISTEN         4
#define MEMP_NUM_TCP_SEG                256
#define MEMP_NUM_NETBUF                 0
#define MEMP_NUM_NETCONN                0
#define MEMP_NUM_TCPIP_MSG_API          0
#define MEMP_NUM_TCPIP_MSG_INPKT        0
/* 26/09: los temporizadores de lwIP salen de un pool que por defecto cuenta los internos (TCP, ARP, reensamblado,
 * DHCP x2, DNS) pero NO el de SNTP. Con SNTP en marcha (comando 'G' del menu) el pool se llenaba, el sys_timeout
 * del TCP fallaba en silencio y como tcp_timer_needed() ya habia marcado el temporizador como activo no se
 * reintentaba: tcp_tmr no corria nunca (tcp_ticks = 0): ni retransmisiones ni ACK diferidos ni TIME_WAIT. */
#define MEMP_NUM_SYS_TIMEOUT            (LWIP_NUM_SYS_TIMEOUT_INTERNAL + 4)
#define PBUF_POOL_SIZE                  128
#define PBUF_POOL_BUFSIZE               1600
#define PBUF_LINK_HLEN                  16

/* TCP */
#define LWIP_TCP                        1
#define TCP_TTL                         255
#define TCP_QUEUE_OOSEQ                 1
#define TCP_MSS                         1460
#define TCP_SND_BUF                     (16 * TCP_MSS)
#define TCP_SND_QUEUELEN                (4 * TCP_SND_BUF / TCP_MSS)
#define TCP_WND                         (8 * TCP_MSS)
#define TCP_MAXRTX                      12
#define TCP_SYNMAXRTX                   4
#define LWIP_TCP_KEEPALIVE              1
#define TCP_TMR_INTERVAL                250

/* ARP / IP / ICMP */
#define ARP_TABLE_SIZE                  10
#define ARP_QUEUEING                    1
#define IP_FORWARD                      0
#define IP_OPTIONS_ALLOWED              1
#define IP_REASSEMBLY                   1
#define IP_FRAG                         1
#define ICMP_TTL                        255
#define LWIP_ICMP                       1
#define LWIP_RAW                        1

/* DHCP / DNS / UDP */
#define LWIP_DHCP                       1
#define DHCP_DOES_ARP_CHECK             1
#define LWIP_DNS                        1
#define DNS_TABLE_SIZE                  4
#define DNS_MAX_NAME_LENGTH             128
#define LWIP_UDP                        1
#define UDP_TTL                         255
#define LWIP_NETIF_STATUS_CALLBACK      1
#define LWIP_NETIF_LINK_CALLBACK        1
#define LWIP_NETIF_HOSTNAME             1

/* checksums por software (el GEM tambien las comprueba, no estorba) */
#define CHECKSUM_GEN_IP                 1
#define CHECKSUM_GEN_UDP                1
#define CHECKSUM_GEN_TCP                1
#define CHECKSUM_GEN_ICMP               1
#define CHECKSUM_CHECK_IP               1
#define CHECKSUM_CHECK_UDP              1
#define CHECKSUM_CHECK_TCP              1
#define CHECKSUM_CHECK_ICMP             1

/* SNTP (esp_cmd.c, comando 'G' del ESP): el servidor por nombre, la hora a esp_time_set() */
#define SNTP_SERVER_DNS                 1
#define SNTP_STARTUP_DELAY              0
#define SNTP_UPDATE_DELAY               3600000
extern void esp_time_set(unsigned long sec);
#define SNTP_SET_SYSTEM_TIME(sec)       esp_time_set((unsigned long)(sec))

#define LWIP_STATS                      0
#define LWIP_IPV6                       0
#define LWIP_IGMP                       0

#endif /* __LWIPOPTS_H__ */
