#!/bin/bash
# get_tinyusb.sh — clona TinyUSB (commit fijado) en arm/tinyusb y aplica el parche del
# Zynq-7000 (hcd_ci_hs.c: #elif defined(CI_HS_ZYNQ7000) -> ci_hs_zynq.h del companion) y el arreglo de
# hcd_edpt_abort_xfer del EHCI (ehci.c, 22/09/2026: el abort dejaba el overlay del QH con Active=1 y la
# transferencia seguia viva; lo necesita la disquetera USB, ufi_host.c) y, 1/11/2026, los arreglos del EHCI para el cuelgue del
# USB (ehci.c: qhd_xfer_complete_isr decide por el token del qTD y no por el overlay del QH, qtd_init publica el qTD con Active
# el ultimo, esperas con tope, ehci_split_signature para el vigilante de companion/usb_host.c).
# arm/tinyusb/ esta en .gitignore: ejecutar esto antes de companion/build.sh.
set -e
cd "$(dirname "$0")"
REV=7b787da
[ -d tinyusb ] || git clone https://github.com/hathach/tinyusb.git tinyusb
git -C tinyusb checkout -q $REV
if git -C tinyusb apply --check ../tinyusb-zynq7000.patch 2>/dev/null; then git -C tinyusb apply ../tinyusb-zynq7000.patch; echo "parche aplicado"; else echo "parche ya aplicado (o no aplica)"; fi
git -C tinyusb log --oneline -1
