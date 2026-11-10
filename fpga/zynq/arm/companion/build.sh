#!/bin/bash
# build.sh — compila companion.elf (Cortex-A9, bare-metal): proxy de SD (xsdps) +
# USB host (TinyUSB, ../tinyusb: hub, HID, XInput, MSC) + disquetera USB (ufi_host.c, fdd.c)
# con la toolchain ARM GNU 14.2 y los fuentes de Vivado 2019.2 (sin SDK).
set -e
cd "$(dirname "$0")"
# Rutas de las herramientas: se pueden cambiar con variables de entorno (ARM_TC, XILINX_VIVADO, XILINX_EMBEDDEDSW)
TC="${ARM_TC:-/c/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/14.2 rel1/bin}"
export PATH="$TC:$PATH"
E="${XILINX_EMBEDDEDSW:-${XILINX_VIVADO:-/d/Xilinx/Vivado/2019.2}/data/embeddedsw}"
STD=$E/lib/bsp/standalone_v7_1/src
SDPS=$E/XilinxProcessorIPLib/drivers/sdps_v3_8/src
QSPI=$E/XilinxProcessorIPLib/drivers/qspips_v3_6/src
DCFG=$(cd ../fsbl/devcfg && pwd)          # 30/10: driver devcfg (PCAP) del FSBL, para profile.c (carga de perfiles)
TU=$(cd ../tinyusb && pwd)/src
# 25/09: Ethernet del PS (P0): lwIP 2.1.1 + puerto Xilinx (sin xemacpsif_physpeed.c: lo sustituye net_phy.c,
# sin esperas) + driver emacps; todo por sondeo desde el bucle principal (net.c). Configuracion en bsp/.
LWIP=$E/ThirdParty/sw_services/lwip211_v1_1/src
LWC=$LWIP/lwip-2.1.1/src
LWX=$LWIP/contrib/ports/xilinx
EMAC=$E/XilinxProcessorIPLib/drivers/emacps_v3_10/src
GIC=$E/XilinxProcessorIPLib/drivers/scugic_v4_1/src
# 26/09: Mbed TLS 3.6 (arm/get_mbedtls.sh) con bsp/msximus_mbedtls_config.h: cliente TLS 1.2 para el "ESP32" (esp_tls.c)
MBED=$(cd ../mbedtls && pwd)
[ -f "$MBED/include/mbedtls/ssl.h" ] || { echo "falta Mbed TLS: ejecutar arm/get_mbedtls.sh"; exit 1; }
# -mno-unaligned-access: sin MMU toda la memoria es Strongly-Ordered y un acceso desalineado
# es DATA ABORT (gcc fusionaba strb en strh/str sobre char[] y osd_render abortaba).
CFLAGS="-mcpu=cortex-a9 -marm -mfloat-abi=soft -mno-unaligned-access -O2 -ffreestanding -fno-builtin -nostdlib -Wall -Wno-unused-function
        -DCI_HS_ZYNQ7000 -Ibsp -I. -Ixinput -I$TU -I$STD/common -I$STD/arm/cortexa9 -I$STD/arm/common -I$STD/arm/common/gcc -I$SDPS -I$QSPI -I$DCFG -I$LWC/include -I$LWX/include -I$LWX/netif -I$EMAC -I$GIC
        -I$MBED/include -I$MBED/library -DMBEDTLS_CONFIG_FILE=\"msximus_mbedtls_config.h\""
SRCS="start.S main.c mmu.c log.c profile.c mxpf.c inflate.c perfiles.c perfiles_ext.c dual.c dual_disco.c $DCFG/xdevcfg.c $DCFG/xdevcfg_hw.c $DCFG/xdevcfg_intr.c usb_host.c hid_pad.c usb_vigila.c osd.c oled.c v99desk.c qspi_cfg.c wavegame.c tape.c fdd.c ufi_host.c bsp/xqspips_g.c $QSPI/xqspips.c $QSPI/xqspips_hw.c $QSPI/xqspips_options.c $QSPI/xqspips_sinit.c xinput/xinput_host.c bsp/support.c bsp/xsdps_g.c
      $TU/tusb.c $TU/common/tusb_fifo.c $TU/host/usbh.c $TU/host/hub.c $TU/class/hid/hid_host.c $TU/class/msc/msc_host.c
      $TU/portable/chipidea/ci_hs/hcd_ci_hs.c $TU/portable/ehci/ehci.c
      $SDPS/xsdps.c $SDPS/xsdps_options.c $SDPS/xsdps_sinit.c
      $STD/common/xil_assert.c $STD/common/xil_printf.c $STD/common/xplatform_info.c
      net.c net_phy.c ota.c bootsd.c osd_dib.c osd_info.c yrw801.c tr_bios.c bsp/xtopology_g.c bsp/xemacps_g.c esp_link.c esp_cmd.c esp_tcp.c esp_tsx.c esp_tls.c s3_link.c $LWC/apps/sntp/sntp.c
      $LWX/netif/xadapter.c $LWX/netif/xemacpsif.c $LWX/netif/xemacpsif_dma.c $LWX/netif/xemacpsif_hw.c $LWX/netif/xpqueue.c $LWX/sys_arch_raw.c
      $EMAC/xemacps.c $EMAC/xemacps_bdring.c $EMAC/xemacps_control.c $EMAC/xemacps_hw.c $EMAC/xemacps_intr.c $EMAC/xemacps_sinit.c
      $LWC/core/def.c $LWC/core/dns.c $LWC/core/inet_chksum.c $LWC/core/init.c $LWC/core/ip.c $LWC/core/mem.c $LWC/core/memp.c
      $LWC/core/netif.c $LWC/core/pbuf.c $LWC/core/raw.c $LWC/core/stats.c $LWC/core/sys.c $LWC/core/tcp.c $LWC/core/tcp_in.c
      $LWC/core/tcp_out.c $LWC/core/timeouts.c $LWC/core/udp.c
      $LWC/core/ipv4/dhcp.c $LWC/core/ipv4/etharp.c $LWC/core/ipv4/icmp.c $LWC/core/ipv4/igmp.c $LWC/core/ipv4/ip4.c
      $LWC/core/ipv4/ip4_addr.c $LWC/core/ipv4/ip4_frag.c $LWC/netif/ethernet.c"
# 23/09: el MP3 (mp3.c + minimp3, arm/get_minimp3.sh) con la FPU: softfp mantiene la convencion de llamada de
# soft-float, asi que se enlaza con el resto (soft) y con la newlib de siempre. Solo este objeto usa la VFP/NEON.
MP3DIR=../minimp3
[ -f "$MP3DIR/minimp3.h" ] || { echo "falta minimp3: ejecutar arm/get_minimp3.sh"; exit 1; }
mkdir -p build
objs=""
for src in $SRCS; do
    o=build/$(basename "${src%.*}").o
    arm-none-eabi-gcc $CFLAGS -c "$src" -o "$o"
    objs="$objs $o"
done
for src in $MBED/library/*.c; do                      # Mbed TLS: prefijo mbed_ para no chocar con nombres nuestros
    o=build/mbed_$(basename "${src%.*}").o
    [ -f "$o" ] && [ "$o" -nt "$src" ] && [ "$o" -nt bsp/msximus_mbedtls_config.h ] || arm-none-eabi-gcc $CFLAGS -Wno-unused-variable -c "$src" -o "$o"
    objs="$objs $o"
done
arm-none-eabi-gcc ${CFLAGS/-mfloat-abi=soft/-mfloat-abi=softfp -mfpu=neon} -I$MP3DIR -c mp3.c -o build/mp3.o
objs="$objs build/mp3.o"
arm-none-eabi-gcc $CFLAGS -T lscript.ld -Wl,-Map=build/companion.map -Wl,--no-warn-rwx-segments -o companion.elf $objs -lc -lgcc
arm-none-eabi-size companion.elf
echo "BUILD_OK: $(pwd)/companion.elf"
