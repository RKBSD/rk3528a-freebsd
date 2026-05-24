# AGENTS.md — RK3528A FreeBSD/U-Boot Port

## Project Overview

This is a **board support package** for running FreeBSD on Rockchip RK3528-based single-board computers, primarily the **Radxa Rock 2F**. The root directory is a git repo with three submodules:

| Directory | Purpose | Submodule URL (relative) |
|---|---|---|
| `u-boot/` | U-Boot bootloader with RK3528 support | `../../RKBSD/u-boot.git` |
| `rkbin/` | Rockchip closed-source firmware blobs | `../../RKBSD/rkbin.git` |
| `freebsd-src/` | FreeBSD kernel + world source | `../../RKBSD/freebsd-src.git` |

## Hardware Architecture

- **SoC**: Rockchip RK3528A — quad Cortex-A53, ARMv8-A
- **Board**: Radxa Rock 2F (the primary target; single defconfig also covers Rock 2A and E20C)
- **DEBUG_UART base**: `0xFF9F0000`, shift 2, 1500000 baud, UART0
- **SDRAM**: 0x00000000–0xFC000000 (up to 4GB, SDRAM_MAX_SIZE=0xfc000000)

## Boot Chain

```
BootROM → idbloader.img (DDR init blob + U-Boot SPL) → u-boot.itb (U-Boot proper + ATF BL31 + DTB) → FreeBSD loader (BOOTAA64.EFI)
```

- **idbloader.img**: DDR init blob from rkbin + `spl/u-boot-spl.bin`, packaged with `mkimage -n rk3528 -T rksd`
- **u-boot.itb**: FIT image containing U-Boot proper (`u-boot-nodtb.bin`), ATF BL31 (one or more segments from `bl31.elf`), and device tree (`u-boot.dtb`). Generated via `arch/arm/mach-rockchip/make_fit_atf.sh` + `mkimage`.
- FreeBSD is booted via EFI — U-Boot loads `EFI/BOOT/BOOTAA64.EFI` from the ESP.

## Build System

### U-Boot Build

U-Boot uses Kbuild. Use **GNU Make** (`gmake`), not BSD `make`. The cross-compiler is at `/usr/local/bin/aarch64-none-elf-gcc`.

**Automated build** (recommended): Run `./build_uboot.sh` from the repo root. It handles:
1. FreeBSD compatibility fixes (BSD sed `\s`→`[[:space:]]`, python2→python3 in decode_bl31.py)
2. `rock-2-rk3528_defconfig` + full build
3. `u-boot.itb` FIT image packaging via `make_fit_atf.sh`
4. `idbloader.img` packaging via `mkimage -n rk3528 -T rksd`
5. Raw TF card image (`rk3528_uboot_only.img`) with idbloader at sector 64, u-boot.itb at sector 16384

**Manual build** (from `u-boot/`):
```bash
gmake HOSTCC=cc CROSS_COMPILE=/usr/local/bin/aarch64-none-elf- \
  HOSTCFLAGS="-I/usr/local/include" HOSTLDFLAGS="-L/usr/local/lib" \
  CONFIG_SHELL=/usr/local/bin/bash rock-2-rk3528_defconfig

gmake HOSTCC=cc CROSS_COMPILE=/usr/local/bin/aarch64-none-elf- \
  HOSTCFLAGS="-I/usr/local/include" HOSTLDFLAGS="-L/usr/local/lib" \
  CONFIG_SHELL=/usr/local/bin/bash -j$(sysctl -n hw.ncpu)
```

**FIT image packaging** (manual, after build):
```bash
cp /path/to/rk3528_bl31_v1.20.elf bl31.elf
srctree=. bash arch/arm/mach-rockchip/make_fit_atf.sh > u-boot.its
tools/mkimage -f u-boot.its -E u-boot.itb
```
`make_fit_atf.sh` sources `arch/arm/mach-rockchip/fit_nodes.sh` (which sources `fit_args.sh`), then runs `decode_bl31.py` to split `bl31.elf` into load-address-named segments.

**Key build artifacts**:
| File | Description |
|---|---|
| `u-boot/spl/u-boot-spl.bin` | SPL binary |
| `u-boot/idbloader.img` | DDR init + SPL (via `mkimage -T rksd`) |
| `u-boot/u-boot.itb` | FIT image: U-Boot + BL31 + DTB |

### FreeBSD Build

FreeBSD source lives in the `freebsd-src/` submodule. Build output goes to `freebsd-objs/` (created by `MAKEOBJDIRPREFIX`).

**Full build**:
```bash
mkdir -p freebsd-objs
MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildworld \
  TARGET=arm64 TARGET_ARCH=aarch64 -j$(sysctl -n hw.ncpu)

MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildkernel \
  KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 -j$(sysctl -n hw.ncpu)
```

**Incremental kernel rebuild** (after changing kernel code):
```bash
MAKEOBJDIRPREFIX=$(pwd)/freebsd-objs make -C freebsd-src buildkernel \
  KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64 \
  -DKERNFAST -DNO_CLEAN -j$(sysctl -n hw.ncpu)
```
`-DKERNFAST` skips config/depend phases; `-DNO_CLEAN` preserves `.o` files.

**Full TF card image**: Run `./build_tfcard_image.sh` — it creates a GPT-partitioned image with ESP (FAT16) + rootfs (UFS), installs FreeBSD world/kernel, and writes idbloader+u-boot.itb to raw sectors.

### Automation Scripts

| Script | Purpose |
|---|---|
| `build_uboot.sh` | Full U-Boot build + packaging + raw TF image |
| `build_tfcard_image.sh` | Full FreeBSD TF card image (GPT, ESP, rootfs, world install) |
| `boot2ums.exp` | Expect script: connects to board via picocom, triggers USB Mass Storage mode via external GPIO controller at 192.168.133.180:2323 |

`boot2ums.exp` flow: sets GPIO MODE→out, sends "SET 1 1/0" pulse on "Terminal ready", sends Ctrl-C at "Hit key to stop autoboot", then runs `ums 0 mmc 1` at U-Boot prompt.

## Code Organization

### U-Boot (this repo's modified fork)

```
u-boot/
├── board/radxa/rock2/             # Board-specific code
│   ├── rock2.c                   # Minimal stub (includes common.h only)
│   ├── Kconfig                   # TARGET_ROCK2, SYS_BOARD="rock2", SYS_VENDOR="radxa"
│   ├── Makefile                  # obj-y += rock2.o
│   └── MAINTAINERS
├── arch/arm/mach-rockchip/
│   ├── rk3528/
│   │   ├── rk3528.c             # Memory map, debug UART mux, DDR firewall,
│   │   │                          stimer init (SPL only), OTP fdt_fixup
│   │   ├── clk_rk3528.c         # Clock driver stub
│   │   ├── syscon_rk3528.c      # Syscon (GRF) driver
│   │   ├── Kconfig              # SoC config (TARGET_EVB_RK3528)
│   │   └── Makefile
│   ├── make_fit_atf.sh          # Generates u-boot.its (sources fit_nodes.sh)
│   ├── fit_nodes.sh             # FIT node generators (uboot, bl31, bl32, fdt, etc.)
│   ├── fit_args.sh              # FIT argument processing (sourced by fit_nodes.sh)
│   ├── decode_bl31.py           # Splits bl31.elf into bl31_0x*.bin segments
│   └── spl.c                    # board_fit_config_name_match (return 0 — match all)
├── arch/arm/dts/                 # U-Boot DTS files (NOT dts/upstream/)
│   ├── rk3528.dtsi              # SoC-level DTSI
│   ├── rk3528-pinctrl.dtsi      # Pin control
│   ├── rk3528-u-boot.dtsi       # U-Boot SoC additions
│   ├── rk3528-rock-2a.dts       # Rock 2A: includes rk3528.dtsi + rk3528-u-boot.dtsi
│   ├── rk3528-rock-2.dts        # Common rock-2: includes rk3528-rock-2a.dts
│   ├── rk3528-radxa-e20c.dts    # E20C variant
│   ├── rk3528-radxa-e24c-spi.dts# E24C SPI variant
│   ├── rk3528-evb.dts           # EVB reference
│   └── rk3528-rock-2.dtb        # Pre-built DTB
├── include/configs/
│   ├── rk3528_common.h          # Memory layout, env settings, load addresses
│   └── rockchip-common.h        # FDTFILE, partition defaults, boot targets
├── configs/rock-2-rk3528_defconfig  # Single defconfig for all RK3528 boards
```

**Important**: `arch/arm/dts/rk3528-rock-2.dts` is the DEFAULT_DEVICE_TREE. It simply `#include`s `rk3528-rock-2a.dts`. There is **no separate** `rk3528-rock-2f-u-boot.dtsi` — the Rock 2F uses the same DTS as Rock 2A (minus Ethernet which is handled by the FreeBSD DTB).

### Root-level DTS

`rk3528-rock-2f.dts` at the repo root is a **decompiled FreeBSD DTB** (with phandle references like `phandle = <0x85>`), not the U-Boot source DTS. This is the DTB that FreeBSD kernel uses at runtime.

### rkbin (firmware blobs)

```
rkbin/bin/rk35/
├── rk3528_bl31_v1.20.elf              # ATF BL31 (used by build_uboot.sh)
├── rk3528_bl32_v1.06.bin              # OP-TEE BL32
├── rk3528_ddr_1056MHz_2L_PCB_v1.11.bin # DDR init for 2-layer PCB (Rock 2F)
├── rk3528_ddr_1056MHz_v1.11.bin       # DDR init standard
├── rk3528_ddr_1056MHz_4BIT_PCB_v1.11.bin
└── ... (other RK35xx family blobs)
```

Rock 2F uses 2-layer PCB → `rk3528_ddr_1056MHz_2L_PCB_v1.11.bin` as referenced in README.md.

### Key Memory Layout (from `rk3528_common.h`)

```
0x00000000  CONFIG_SPL_TEXT_BASE (SPL)
0x00200000  CONFIG_SYS_TEXT_BASE (U-Boot proper)
0x00c00000  CONFIG_SYS_INIT_SP_ADDR / scriptaddr
0x00280000  kernel_addr_r
0x04080000  kernel_addr_c
0x02000000  CONFIG_SPL_LOAD_FIT_ADDRESS
0x08200000  fdtoverlay_addr_r
0x08300000  fdt_addr_r
0x0a200000  ramdisk_addr_r
0xfc000000  SDRAM top (MMIO starts)
```

### Key MMIO Registers (from `rk3528.c`)

```
0xff9f0000  DEBUG_UART_BASE (UART0)
0xff620000  STIMER_BASE
0xff2e0000  FIREWALL_DDR_BASE
0xff320000  VENC_GRF_BASE
0xff340000  VPU_GRF_BASE
0xff440000  PMU_SGRF_BASE
0xff4b0000  PMU_CRU_BASE
0xff540000  GPIO0_IOC_BASE
0xff560000  GPIO1_IOC_BASE
0xff570000  GPIO2_IOC_BASE
```

### FreeBSD Kernel

- Config: `freebsd-src/sys/arm64/conf/ROCKCHIP`
- KERNCONF=ROCKCHIP, TARGET=arm64, TARGET_ARCH=aarch64
- DTB for Rock 2F is in `sys/modules/dtb/rockchip/rk3528-rock-2f/`

## Defconfig Specifics

Key options in `rock-2-rk3528_defconfig`:

- `CONFIG_TARGET_EVB_RK3528=y` — uses the EVB target (not a separate Radxa target)
- `CONFIG_DEFAULT_DEVICE_TREE="rk3528-rock-2"` — default DTB
- `CONFIG_ROCKCHIP_FIT_IMAGE=y`, `CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y` — Rockchip FIT image mechanism
- `CONFIG_SPL_FIT_GENERATOR="arch/arm/mach-rockchip/make_fit_atf.sh"` — FIT generation script
- `CONFIG_ANDROID_BOOTLOADER=y`, `CONFIG_ANDROID_AVB=y` — Android boot/AVB support enabled
- `CONFIG_FASTBOOT_FLASH=y` — Fastboot flash support
- `CONFIG_DEBUG_UART_BASE=0xff9f0000`, `CONFIG_DEBUG_UART_SHIFT=2`
- `CONFIG_BAUDRATE=1500000`
- `CONFIG_SARADC_ROCKCHIP_V2=y` (not v1)
- `CONFIG_ADC_KEY=y` — ADC-based key detection
- `CONFIG_ROCKCHIP_OTP=y`, `CONFIG_MISC=y` — OTP reading for chip identification
- `CONFIG_ROCKCHIP_BOOTDEV="nvme 0"` — NVMe boot device
- `CONFIG_SPL_FIT_IMAGE_KB=2560` — SPL FIT image size limit

## Critical Gotchas

### U-Boot Port Specifics

1. **board_fit_config_name_match is a no-op**: The Rockchip SPL's `board_fit_config_name_match()` in `arch/arm/mach-rockchip/spl.c:261` simply returns 0 (match all). There is **no ADC-based board detection** at this level. The OTP-based chip identification happens in `rk_board_dm_fdt_fixup()` via `fdt_fixup_modules()` which reads OTP offset 40 to append `rockchip,rk3528` or `rockchip,rk3528a` to the compatible string.

2. **FreeBSD host compilation**: Must use `HOSTCC=cc` (not gcc), `gmake` (not BSD make), and `CONFIG_SHELL=/usr/local/bin/bash`. The `build_uboot.sh` script sets all of these.

3. **BSD sed incompatibility**: The `scripts/check-config.sh` uses `\s` which BSD sed doesn't support. `build_uboot.sh` patches this with `sed -i '' 's/\\s/[[:space:]]/g'`.

4. **Python version**: `decode_bl31.py` defaults to python2; `build_uboot.sh` patches it to python3.

5. **DDR firewall must be configured in SPL**: `arch_cpu_init()` (guarded by `CONFIG_SPL_BUILD`) configures DDR firewall registers to allow eMMC (MST6), SDMMC (MST14), crypto (MST1), FSPI (MST7), and optionally USB (MST16) to access DRAM. This also sets eMMC IO drive strength.

6. **USB3 OTG port not explicitly disabled here**: Unlike some other RK ports, there's no explicit USB3 OTG disable in this `arch_cpu_init()` — the COMBPHY driver handles it.

7. **stimer is only initialized for SPL**: `rockchip_stimer_init()` is guarded by `CONFIG_SPL_BUILD`.

8. **OTP chip identification**: `rk_board_dm_fdt_fixup()` reads OTP offset 40 (CHIP_TYPE_OFF). Value 0x01 → "rockchip,rk3528"; anything else → "rockchip,rk3528a". This appends to the root FDT compatible string.

9. **FDTFILE uses "rockchip/" prefix on ARM64**: The fdtfile env var will be `rockchip/rk3528-rock-2.dtb` (from `rockchip-common.h:134`).

10. **SPL loads u-boot.itb from offset**: `CONFIG_SPL_LOAD_FIT_ADDRESS=0x2000000` — SPL expects to find and load the FIT image at this address.

### FreeBSD Build Specifics

11. **MAKEOBJDIRPREFIX is required**: Must point to `$(pwd)/freebsd-objs` to keep build artifacts isolated from the source tree.

12. **Kernel config file**: `sys/arm64/conf/ROCKCHIP` in freebsd-src.

13. **DQE in DWC_ETH_QOS driver**: If Ethernet corruption occurs, the `snps,en-tx-dqeee` or related DQE properties in the FreeBSD DTS may need tuning — this is a known RK3528 quirk.

### General

14. **No CI/CD**: No GitHub Actions, no CI config files. Manual build workflow.

15. **Submodules use relative URLs**: The `.gitmodules` uses `../../RKBSD/...` paths. Cloning this repo requires access to those relative paths.

16. **Multiple DDR blob variants exist**: `rkbin/bin/rk35/` contains multiple DDR init blobs for different PCB layouts (2-layer, 4-bit PCB, eyescan variants). Rock 2F uses `2L_PCB` (2-layer) version.

## Image Layout (TF Card)

```
LBA         Offset      Content
────────────────────────────────────────
0 - 63      0 - 32KB    Reserved (Rockchip vendor data)
64          32KB        idbloader.img (DDR init + SPL)
16384       8MB         u-boot.itb (U-Boot + BL31 + DTB)
32768       16MB        GPT partition table + ESP (FAT16)
557056      272MB       rootfs (UFS)
```

## Testing & Debugging

- UART0 at 1500000-8-N-1 (`/dev/ttyU0` on FreeBSD host)
- `picocom -b 1500000 /dev/ttyU0` for serial console
- No automated test framework — changes validated by building and booting on real hardware
- TF card device: check with `camcontrol devlist`, then `dd if=image of=/dev/daX bs=1M conv=fsync`
- USB Mass Storage mode via `boot2ums.exp`: exposes eMMC (`mmc 1`) as USB drive on host
