# FreeBSD on RK3528A (Rock 2F)

FreeBSD 移植到 Rockchip RK3528A (Radxa Rock 2F) 的引导固件。

## 目录结构

```
rk3528a-freebsd/
├── u-boot/          # U-Boot v2026.07-rc2 (主线，含 RK3528 支持)
├── rkbin/           # Rockchip 闭源固件 (DDR 初始化, BL31, BL32)
│   └── bin/rk35/    # RK3528 固件二进制文件
└── rk3528_uboot.img # 编译输出：可烧录 TF 卡镜像
```

## 依赖

| 工具 | 说明 |
|------|------|
| `gmake` | GNU Make (BSD make 不兼容) |
| `aarch64-none-elf-gcc` | ARM64 交叉编译器 (`pkg install aarch64-none-elf-gcc`) |
| `python3` | binman 打包需要 |

## 快速开始

### 1. 编译 U-Boot

```bash
./build_uboot.sh
```

编译产物：

| 文件 | 说明 |
|------|------|
| `idbloader.img` | DDR 初始化 + SPL |
| `u-boot/u-boot.itb` | U-Boot + ATF BL31 + DTB (FIT 镜像) |
| `rk3528_uboot_only.img` | 仅含 U-Boot 的裸 TF 卡镜像 (用于调试) |

`u-boot.itb` 包含默认 DTB (`rk3528-rock-2.dtb`)，覆盖 Rock 2A / Rock 2F 等板型。

### 2. 编译 FreeBSD (可选)

`build_tfcard_image.sh` 会自动编译 FreeBSD world 和内核，通常无需手动执行。
如需单独编译或增量调试：

```bash
# 首次全量编译
mkdir -p freebsd-objs
MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildworld \
  TARGET=arm64 TARGET_ARCH=aarch64 -j$(sysctl -n hw.ncpu)

MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildkernel \
  KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 -j$(sysctl -n hw.ncpu)
```

> FreeBSD 源码位于 `freebsd-src/` 子模块。`MAKEOBJDIRPREFIX` 将所有编译产物隔离到 `freebsd-objs/` 目录。

#### 增量编译 (快速调试)

```bash
MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildkernel \
  KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 \
  -DKERNFAST -DNO_CLEAN -j$(sysctl -n hw.ncpu)
```

| 选项 | 作用 |
|------|------|
| `-DKERNFAST` | 跳过 config、depend 等重复步骤，只编译变化的源文件 |
| `-DNO_CLEAN` | 不执行 `make clean`，保留已有 `.o`，仅重编修改过的文件 |

### 3. 生成 TF 卡镜像

```bash
# 一键生成完整镜像（包含 U-Boot + FreeBSD kernel + rootfs）
./build_tfcard_image.sh
```

脚本流程：
1. 创建 16GB 空白镜像并挂载为 memory disk
2. 创建 GPT 分区表：ESP（256MB FAT16）+ rootfs（剩余空间 UFS）
3. 安装 `BOOTAA64.EFI` 到 ESP
4. 安装 FreeBSD kernel + world 到 rootfs
5. 写入 `idbloader.img` 到 LBA 64、`u-boot.itb` 到 LBA 16384

### 4. 烧录到 TF 卡

```bash
sudo dd if=rk3528_tfcard.img of=/dev/da0 bs=1M conv=fsync
```

> 用 `camcontrol devlist` 查看 TF 卡设备名，将 `/dev/da0` 替换为实际设备。

## 镜像布局

```
LBA         偏移         内容
──────────────────────────────────────────
0 - 63      0 - 32KB     保留 (Rockchip vendor 数据区)
64          32KB         idbloader.img (DDR 初始化 + SPL)
16384       8MB          u-boot.itb (U-Boot + BL31 + DTB)
32768       16MB         GPT 分区表 + ESP (FAT16, /boot/efi)
557056      272MB        rootfs (UFS, /)
```

## 固件版本

| 固件 | 文件 | 版本 |
|------|------|------|
| DDR 初始化 | `rk3528_ddr_1056MHz_v1.11.bin` | v1.11 |
| ATF BL31 | `rk3528_bl31_v1.20.elf` | v1.20 |
| OP-TEE BL32 | `rk3528_bl32_v1.06.bin` | v1.06 (可选) |


## 硬件信息

![RK3528A 硬件拓扑](assets/rk3528a_topology.png)

- **SoC**: Rockchip RK3528A (4×Cortex-A53, ARMv8-A)
- **内存映射**: 0x00000000 - 0xFC000000 (最大 4GB)
- **调试串口**: UART0, 1500000-8-N-1
- **MMIO 起始**: 0xFC000000
