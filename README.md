# FreeBSD on RK3528A (Rock 2F)

FreeBSD port for the Rockchip RK3528A SoC (Radxa Rock 2F) — boot firmware and full system image.

[中文版](README.zh-CN.md)

## Directory Structure

```
rk3528a-freebsd/
├── u-boot/              # U-Boot bootloader (RK3528 support)
├── rkbin/               # Rockchip closed-source firmware (DDR init, BL31, BL32)
│   └── bin/rk35/        # RK3528 firmware binaries
├── freebsd-src/         # FreeBSD kernel + world source
├── freebsd-objs/        # FreeBSD build output (MAKEOBJDIRPREFIX)
├── rk3528-rock-2f.dts   # FreeBSD device tree source
├── build_uboot.sh       # U-Boot build script
└── build_tfcard_image.sh# Full TF card image build script
```

## Dependencies

| Tool | Notes |
|------|-------|
| `gmake` | GNU Make (`pkg install gmake`) |
| `aarch64-none-elf-gcc` | ARM64 cross-compiler (`pkg install aarch64-none-elf-gcc`) |
| `bison` | Parser generator (`pkg install bison`) |
| `dtc` | Device tree compiler (included in FreeBSD base) |
| `bash` | GNU Bash (`pkg install bash`) |
| `python3` | Python 3 (included in FreeBSD base) |

## Quick Start

### 1. Build U-Boot

```bash
./build_uboot.sh
```

Outputs:

| File | Description |
|------|-------------|
| `idbloader.img` | DDR init + SPL |
| `u-boot/u-boot.itb` | U-Boot + ATF BL31 + DTB (FIT image) |
| `rk3528_uboot_only.img` | Bare U-Boot image (32MB, for debugging) |

### 2. Build TF Card Image

```bash
./build_tfcard_image.sh
```

The script internally compiles FreeBSD world and kernel — no need to build them separately.
Produces `rk3528_tfcard.img` (16GB):

| Step | Description |
|------|-------------|
| Partition | GPT table: ESP (256MB FAT16) + rootfs (UFS) |
| Boot | Install `BOOTAA64.EFI` to ESP |
| System | Install FreeBSD kernel, world, /etc skeleton to rootfs |
| DTB | Compile `rk3528-rock-2f.dts` → `/boot/dtb/rockchip/`, configure loader.conf |
| Firmware | Write idbloader (LBA 64) + u-boot.itb (LBA 16384) |

### 3. Flash to TF Card

```bash
sudo dd if=rk3528_tfcard.img of=/dev/da0 bs=1M conv=fsync
```

> Use `camcontrol devlist` to find the TF card device.

## Image Layout

```
LBA         Offset      Content
──────────────────────────────────────────
0 - 63      0 - 32KB    Reserved
64          32KB        idbloader.img (DDR init + SPL)
16384       8MB         u-boot.itb (U-Boot + BL31 + DTB)
32768       16MB        GPT table + ESP (FAT16, /boot/efi)
557056      272MB       rootfs (UFS, /)
```

## Incremental Builds

After modifying kernel source, rebuild only what changed:

```bash
MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildkernel \
  KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 \
  -DKERNFAST -DNO_CLEAN -j$(sysctl -n hw.ncpu)

./build_tfcard_image.sh
```

## Firmware Versions

| Firmware | File | Version |
|----------|------|---------|
| DDR init | `rk3528_ddr_1056MHz_v1.11.bin` | v1.11 |
| ATF BL31 | `rk3528_bl31_v1.20.elf` | v1.20 |
| OP-TEE BL32 | `rk3528_bl32_v1.06.bin` | v1.06 (not used) |

## USB Mass Storage Debugging

`boot2ums.exp` automates exposing the board's eMMC as a USB mass storage device
via serial, allowing direct read/write from the host (flashing images, backups, etc.).

```bash
./boot2ums.exp
```

Workflow:
1. Connects to the board's serial console via picocom (`/dev/ttyU0`, 1500000 baud)
2. Sends a pulse to an external GPIO controller (`192.168.133.180:2323`) to trigger power/reset
3. Sends Ctrl-C during U-Boot's autoboot countdown
4. Runs `ums 0 mmc 1` to export eMMC as a USB device

The eMMC then appears as `/dev/daX` on the host — ready for `dd` flashing.

## Hardware Info

![RK3528A Hardware Topology](assets/rk3528a_topology.png)

- **SoC**: Rockchip RK3528A (4×Cortex-A53, ARMv8-A)
- **Memory map**: 0x00000000 - 0xFC000000 (max 4GB)
- **Debug UART**: UART0, 1500000-8-N-1
- **MMIO base**: 0xFC000000
