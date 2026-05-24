#!/bin/sh
# Build U-Boot, idbloader, and TF card image for RK3528 Rock 2F
# Usage: ./build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UBOOT_DIR="${SCRIPT_DIR}/u-boot"
#UBOOT_DIR="${SCRIPT_DIR}/uboot-next-dev-v2024.10"
RKBIN_DIR="${SCRIPT_DIR}/rkbin"
#RKBIN_DIR="${SCRIPT_DIR}/rkbin-tools"
OUT_DIR="${SCRIPT_DIR}"

# --- Config ---
CROSS_COMPILE="/usr/local/bin/aarch64-none-elf-"
JOBS="$(sysctl -n hw.ncpu)"
BL31="${RKBIN_DIR}/bin/rk35/rk3528_bl31_v1.20.elf"
#BL31="${RKBIN_DIR}/rk35/rk3528_bl31_v1.17.elf"
DDR_BIN="${RKBIN_DIR}/bin/rk35/rk3528_ddr_1056MHz_v1.11.bin"
#DDR_BIN="${RKBIN_DIR}/rk35/rk3528_ddr_1056MHz_v1.09.bin"
HOSTCFLAGS="-I/usr/local/include"
HOSTLDFLAGS="-L/usr/local/lib"

echo "=== Step 1: Build U-Boot ==="
cd "${UBOOT_DIR}"

# Apply FreeBSD compatibility fixes (idempotent)
# - BSD sed does not support \s, use [[:space:]]
sed -i '' 's/\\s/[[:space:]]/g' scripts/check-config.sh 2>/dev/null || true
# - decode_bl31.py needs python3
sed -i '' 's/python2/python3/' arch/arm/mach-rockchip/decode_bl31.py 2>/dev/null || true

gmake HOSTCC=cc \
      CROSS_COMPILE="${CROSS_COMPILE}" \
      HOSTCFLAGS="${HOSTCFLAGS}" \
      HOSTLDFLAGS="${HOSTLDFLAGS}" \
      CONFIG_SHELL=/usr/local/bin/bash \
      rock-2-rk3528_defconfig

gmake HOSTCC=cc \
      CROSS_COMPILE="${CROSS_COMPILE}" \
      HOSTCFLAGS="${HOSTCFLAGS}" \
      HOSTLDFLAGS="${HOSTLDFLAGS}" \
      CONFIG_SHELL=/usr/local/bin/bash \
      -j"${JOBS}"

echo "=== Step 2: Build u-boot.itb ==="
cd "${UBOOT_DIR}"
cp "${BL31}" bl31.elf
srctree=. bash arch/arm/mach-rockchip/make_fit_atf.sh > u-boot.its
tools/mkimage -f u-boot.its -E u-boot.itb

echo "=== Step 3: Build idbloader.img ==="
tools/mkimage -n rk3528 -T rksd \
      -d "${DDR_BIN}:${UBOOT_DIR}/spl/u-boot-spl.bin" \
      "${OUT_DIR}/idbloader.img"

echo "=== Step 4: Build TF card image ==="
TF_IMG="${OUT_DIR}/rk3528_uboot_only.img"
# 16MB image, idbloader at sector 64, u-boot.itb at sector 16384
dd if=/dev/zero of="${TF_IMG}" bs=512 count=65536
dd if="${OUT_DIR}/idbloader.img" of="${TF_IMG}" bs=512 seek=64 conv=notrunc,sync
dd if="${UBOOT_DIR}/u-boot.itb" of="${TF_IMG}" bs=512 seek=16384 conv=notrunc,sync

echo ""
echo "=== Done ==="
echo "idbloader.img : $(ls -lh "${OUT_DIR}/idbloader.img" | awk '{print $5}')"
echo "u-boot.itb    : $(ls -lh "${UBOOT_DIR}/u-boot.itb" | awk '{print $5}')"
echo "tf card image : $(ls -lh "${TF_IMG}" | awk '{print $5}')"
echo ""
echo "Flash: dd if=${TF_IMG} of=/dev/daX bs=1M conv=sync"
