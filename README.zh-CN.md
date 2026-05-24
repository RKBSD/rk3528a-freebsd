# FreeBSD on RK3528A (Rock 2F)

Rockchip RK3528A (Radxa Rock 2F) 的 FreeBSD 移植 —— 引导固件与完整系统镜像。

[English](README.md)

## 目录结构

```
rk3528a-freebsd/
├── u-boot/              # U-Boot 引导固件（含 RK3528 支持）
├── rkbin/               # Rockchip 闭源固件 (DDR 初始化, BL31, BL32)
│   └── bin/rk35/        # RK3528 固件二进制文件
├── freebsd-src/         # FreeBSD 内核 + world 源码
├── freebsd-objs/        # FreeBSD 编译输出目录 (MAKEOBJDIRPREFIX)
├── rk3528-rock-2f.dts   # FreeBSD 设备树源文件
├── build_uboot.sh       # U-Boot 编译脚本
└── build_tfcard_image.sh# TF 卡完整镜像制作脚本
```

## 依赖

| 工具 | 说明 |
|------|------|
| `gmake` | GNU Make (`pkg install gmake`) |
| `aarch64-none-elf-gcc` | ARM64 交叉编译器 (`pkg install aarch64-none-elf-gcc`) |
| `bison` | 语法分析器生成器 (`pkg install bison`) |
| `dtc` | 设备树编译器 (FreeBSD base 自带) |
| `bash` | GNU Bash (`pkg install bash`) |
| `python3` | Python 3 (FreeBSD base 自带) |

## 快速开始

### 1. 编译 U-Boot

```bash
./build_uboot.sh
```

产物：

| 文件 | 说明 |
|------|------|
| `idbloader.img` | DDR 初始化 + SPL |
| `u-boot/u-boot.itb` | U-Boot + ATF BL31 + DTB (FIT 镜像) |
| `rk3528_uboot_only.img` | 仅含 U-Boot 的原始镜像 (调试用，32MB) |

### 2. 生成 TF 卡镜像

```bash
./build_tfcard_image.sh
```

脚本内部会自动编译 FreeBSD world 和内核，无需提前单独编译。
生成 `rk3528_tfcard.img` (16GB)：

| 步骤 | 说明 |
|------|------|
| 分区 | GPT 分区表：ESP (256MB FAT16) + rootfs (UFS) |
| 引导 | 安装 `BOOTAA64.EFI` 到 ESP |
| 系统 | 安装 FreeBSD kernel、world、/etc 骨架到 rootfs |
| DTB | 编译 `rk3528-rock-2f.dts` → `/boot/dtb/rockchip/` 并配置 loader.conf |
| 固件 | 写入 idbloader (LBA 64) + u-boot.itb (LBA 16384) |

### 3. 烧录到 TF 卡

```bash
sudo dd if=rk3528_tfcard.img of=/dev/da0 bs=1M conv=fsync
```

> 用 `camcontrol devlist` 查看 TF 卡设备名。

## 镜像布局

```
LBA         偏移         内容
──────────────────────────────────────────
0 - 63      0 - 32KB     保留
64          32KB         idbloader.img (DDR 初始化 + SPL)
16384       8MB          u-boot.itb (U-Boot + BL31 + DTB)
32768       16MB         GPT 分区表 + ESP (FAT16, /boot/efi)
557056      272MB        rootfs (UFS, /)
```

## 增量调试

修改内核源码后，仅重编变化的部分：

```bash
MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildkernel \
  KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 \
  -DKERNFAST -DNO_CLEAN -j$(sysctl -n hw.ncpu)

./build_tfcard_image.sh
```

## 固件版本

| 固件 | 文件 | 版本 |
|------|------|------|
| DDR 初始化 | `rk3528_ddr_1056MHz_v1.11.bin` | v1.11 |
| ATF BL31 | `rk3528_bl31_v1.20.elf` | v1.20 |
| OP-TEE BL32 | `rk3528_bl32_v1.06.bin` | v1.06 (未启用) |

## USB Mass Storage 调试

`boot2ums.exp` 通过串口自动将开发板的 eMMC 暴露为 USB 大容量存储设备，
方便在主机上直接读写 eMMC 内容（烧录镜像、备份等）。

```bash
./boot2ums.exp
```

工作流程：
1. 通过 picocom 连接开发板串口 (`/dev/ttyU0`, 1500000 baud)
2. 连接外部 GPIO 控制器 (`192.168.133.180:2323`)，发送脉冲信号触发电源/复位
3. 在 U-Boot 自动启动倒计时时发送 Ctrl-C 中断
4. 执行 `ums 0 mmc 1` 将 eMMC 导出为 USB 设备

之后开发板的 eMMC 会作为 `/dev/daX` 出现在主机上，可直接 `dd` 烧录镜像。

## 硬件信息

![RK3528A 硬件拓扑](assets/rk3528a_topology.png)

- **SoC**: Rockchip RK3528A (4×Cortex-A53, ARMv8-A)
- **内存映射**: 0x00000000 - 0xFC000000 (最大 4GB)
- **调试串口**: UART0, 1500000-8-N-1
- **MMIO 起始**: 0xFC000000
