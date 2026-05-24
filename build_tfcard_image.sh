#!/bin/sh
# Rock 2F (RK3528) TF 卡镜像制作脚本
# 参见 docs/rk3528a-tfcard-image-layout.md
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC=$SCRIPT_DIR/freebsd-src
OBJ=$SCRIPT_DIR/freebsd-objs

# ── 1. 创建空镜像并挂载为 memory disk ──────────────────────────
dd if=/dev/zero of=${SCRIPT_DIR}/rk3528_tfcard.img \
   bs=1M count=16384

MD=$(sudo mdconfig -a -t vnode -f ${SCRIPT_DIR}/rk3528_tfcard.img)
echo "Attached as /dev/$MD"

# ── 2. 创建 GPT 分区表 ────────────────────────────────────────
sudo gpart create -s GPT /dev/$MD

# ── 3. 添加分区 ───────────────────────────────────────────────
sudo gpart add -t efi -s 256M -b 32768 /dev/$MD
sudo gpart add -t freebsd-ufs -b 557056 /dev/$MD

# ── 4. 格式化分区 ─────────────────────────────────────────────
sudo newfs_msdos -F 16 -L BOOTFS /dev/${MD}p1
sudo newfs -U -L rootfs /dev/${MD}p2

# ── 5. 安装 BOOTAA64.EFI 到 ESP ───────────────────────────────
MNT=$(mktemp -d)
sudo mount -t msdosfs /dev/${MD}p1 $MNT
sudo mkdir -p $MNT/EFI/BOOT
sudo cp `find $OBJ -name "loader_lua.efi"` \
   $MNT/EFI/BOOT/BOOTAA64.EFI
sudo umount $MNT
rmdir $MNT

# ── 6. 安装 FreeBSD 到 rootfs ─────────────────────────────────

MNT=$(mktemp -d)
sudo mount /dev/${MD}p2 $MNT

cd $SRC

# 6a. 安装内核 + 模块 + DTB → $MNT/boot/kernel/
sudo env MAKEOBJDIRPREFIX=$OBJ \
  make installkernel KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 \
  DESTDIR=$MNT

# 6b. 安装 distributekernel → $MNT/boot/ (device.hints 等)
sudo env MAKEOBJDIRPREFIX=$OBJ \
  make distributekernel KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 \
  DESTDIR=$MNT

# 6c. 安装 userland (bin, lib, sbin, usr, …)
sudo env MAKEOBJDIRPREFIX=$OBJ \
  make installworld TARGET=arm64 TARGET_ARCH=aarch64 \
  DESTDIR=$MNT

# 6d. 安装 /etc, /var, /root 骨架 (不覆盖已有配置)
sudo env MAKEOBJDIRPREFIX=$OBJ \
  make distribution TARGET=arm64 TARGET_ARCH=aarch64 \
  DESTDIR=$MNT

# 6e. /etc/fstab — 让 FreeBSD 挂载 rootfs 和 ESP
sudo tee $MNT/etc/fstab <<'FSTAB'
/dev/gpt/rootfs  /       ufs  rw,noatime  1  1
/dev/gpt/BOOTFS  /boot/efi  msdosfs  rw,noatime  0  0
FSTAB

sudo umount $MNT
rmdir $MNT

# ── 7. 写入 idbloader 和 u-boot 到裸扇区 ──────────────────────
sudo dd if=${SCRIPT_DIR}/idbloader.img \
   of=/dev/$MD bs=512 seek=64 conv=notrunc
sudo dd if=${SCRIPT_DIR}/u-boot/u-boot.itb \
   of=/dev/$MD bs=512 seek=16384 conv=notrunc

# ── 8. 卸载 memory disk ───────────────────────────────────────
sudo mdconfig -d -u ${MD#md}
