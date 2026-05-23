# AGENTS.md — RK3528A FreeBSD/U-Boot Port

## Project Overview

This is a **board support package** for running FreeBSD on Rockchip RK3528-based single-board computers, specifically the **Radxa Rock 2F**. The repository contains two submodules:

| Directory | Purpose | Upstream |
|---|---|---|
| `u-boot/` | U-Boot v2026.07-rc2 bootloader for RK3528 | Mainline U-Boot |
| `rkbin/` | Rockchip closed-source firmware blobs (DDR init, BL31, BL32) | Rockchip rkbin repo |

FreeBSD kernel source and build scripts live **outside this repo** at `~/workspace/freebsd/`.

## Hardware Architecture

- **SoC**: Rockchip RK3528A — quad Cortex-A53, ARMv8-A
- **Board**: Radxa Rock 2F (detected at runtime via ADC channel 2)
- **Single defconfig** serves three boards: Rock 2A, Rock 2F, and Radxa E20C
- Board is identified at boot by reading ADC channel 2 from `adc@ffae0000`; the threshold ranges map to DTB filenames
- **Rock 2F** has no Ethernet (no `&gmac1` node in its DTS), unlike **Rock 2A** which has RGMII

## Boot Chain

```
BootROM → idbloader.img (DDR init + TPL/SPL) → u-boot.itb (U-Boot proper + ATF BL31 + DTB) → FreeBSD loader (BOOTAA64.EFI)
```

- **idbloader.img**: DDR init blob from rkbin + U-Boot SPL, packaged with `mkimage -n rk3528 -T rksd`
- **u-boot.itb**: FIT image containing U-Boot proper, ARM Trusted Firmware BL31, and device tree
- FreeBSD is booted via EFI stub — U-Boot loads `EFI/BOOT/BOOTAA64.EFI` from the ESP

## Build System

### U-Boot Build (in this repo)

U-Boot uses Kbuild (Linux-style recursive make). Must use **GNU Make** (`gmake`), not BSD `make`.

```bash
# From u-boot/ directory:
gmake rock-2-rk3528_defconfig
gmake CROSS_COMPILE=/usr/local/bin/aarch64-none-elf- -j$(sysctl -n hw.ncpu)
```

**Key build artifacts** (manual steps — not in U-Boot Makefile targets):
- `spl/u-boot-spl.bin` → combined with DDR blob into `idbloader.img`
- `u-boot.bin` + BL31 → `u-boot.itb` (FIT image)

The `make_fit_atf.sh` and `decode_bl31.py` scripts referenced in the crush skills are **not yet present** in this U-Boot tree — they need to be created or pulled from another rk3528 U-Boot port. The TF card image assembly is separate, documented in `~/workspace/` (see `docs/rk3528a-tfcard-image-layout.md` outside this repo).

### FreeBSD Kernel Build (outside this repo)

See crush skill `build-freebsd-rock2f` for full build commands. Key points:
- Source lives at `/storage/home/virusv/workspace/freebsd`
- Config: `KERNCONF=ROCKCHIP TARGET=arm64 TARGET_ARCH=aarch64`
- Incremental: `-DKERNFAST`
- DTB is auto-built via kernel module (`sys/modules/dtb/rockchip/rk3528-rock-2f`)

## Code Organization

### U-Boot Board Support

```
u-boot/
├── board/radxa/rock-2-rk3528/     # Board-specific code
│   ├── rock-2-rk3528.c           # ADC-based board detection, fit_config_name_match
│   ├── Kconfig                   # Selects ADC, defines SYS_BOARD/SYS_VENDOR
│   └── MAINTAINERS
├── arch/arm/mach-rockchip/rk3528/ # SoC-level code
│   ├── rk3528.c                  # Memory map, debug UART, DDR firewall setup,
│   │                               boot device paths, stimer init, OTP checkboard
│   ├── clk_rk3528.c              # Clock driver stub
│   ├── syscon_rk3528.c           # Syscon (GRF) driver
│   └── Kconfig                   # SoC config including TARGET_RADXA_ROCK_2_RK3528
├── include/configs/rk3528_common.h # Memory layout, env settings, load addresses
├── configs/rock-2-rk3528_defconfig # Single unified defconfig for all three boards
├── dts/upstream/src/arm64/rockchip/ # Upstream DTS from Linux
│   ├── rk3528.dtsi               # SoC-level DTSI
│   ├── rk3528-rock-2.dtsi        # Common board DTSI (both 2A and 2F share this)
│   ├── rk3528-rock-2a.dts        # Rock 2A specifics (Ethernet, OTG power, green LED)
│   ├── rk3528-rock-2f.dts        # Rock 2F — minimal, just includes rock-2.dtsi
│   └── rk3528-rock-2f.dtb        # Pre-built DTB (exists alongside .dts)
└── arch/arm/dts/                  # U-Boot-specific DTSI overlays
    ├── rk3528-u-boot.dtsi         # SoC-level U-Boot additions
    ├── rk3528-rock-2-u-boot.dtsi  # Common board U-Boot additions
    └── rk3528-rock-2f-u-boot.dtsi # Rock 2F U-Boot additions (just includes rock-2)
```

### rkbin (firmware blobs)

```
rkbin/
├── bin/rk35/          # RK35xx family firmware
│   ├── rk3528_bl31_v1.20.elf         # ATF BL31 (EL3 runtime)
│   ├── rk3528_bl32_v1.06.bin         # OP-TEE BL32 (optional)
│   └── rk3528_ddr_1056MHz_*_v1.11.bin # DDR init blob
├── RKBOOT/            # Bootloader configs
├── RKTRUST/           # Trusted firmware configs
└── tools/             # Image signing/unpacking scripts
```

### Key Memory Layout (from `rk3528_common.h`)

```
0x00000000  SDRAM base
0x00c00000  scriptaddr (boot.scr)
0x02000000  kernel_addr_r
0x0a000000  kernel_comp_addr_r (decompression buffer)
0x12000000  fdt_addr_r
0x12100000  fdtoverlay_addr_r
0x12180000  ramdisk_addr_r
0xfc000000  SDRAM top (device MMIO starts)
```

### Key MMIO Registers (from `rk3528.c`)

```
0xff370200  BOOT_MODE_REG
0xff620000  STIMER_BASE
0xff340000  VPU_GRF_BASE
0xff2e0000  FIREWALL_DDR_BASE
0xffae0000  ADC used for board ID
0xffbf0000  eMMC (boot device)
0xffc30000  SD (boot device)
```

## Critical Gotchas

### U-Boot Port Specifics

1. **Board detection is runtime, not compile-time**: One defconfig builds firmware for three different boards. SPL reads ADC channel 2 during `board_fit_config_name_match()` to select the correct DTB. Ranges: Rock 2A [63,278], E20C [291,392], Rock 2F [519,733].

2. **`generated_defconfig-e` is stale**: This file in the u-boot root appears to be a saved environment or partial config dump — it's NOT the active config. Always use `rock-2-rk3528_defconfig`.

3. **make_fit_atf.sh / decode_bl31.py are missing**: These scripts (needed to package `u-boot.itb`) don't exist yet in this tree. The build skills say to use them at `arch/arm/mach-rockchip/make_fit_atf.sh` and `arch/arm/mach-rockchip/decode_bl31.py`.

4. **FreeBSD host compilation**: When building U-Boot on FreeBSD, set `HOSTCC=cc` and use `gmake` (not BSD `make`). The cross-compiler is at `/usr/local/bin/aarch64-none-elf-gcc`.

5. **DDR firewall must be configured in SPL**: The `arch_cpu_init()` function configures DDR firewall registers to allow eMMC, FSPI, SDMMC, and USB to access DRAM. This only runs during `CONFIG_SPL_BUILD`.

6. **USB3 OTG disabled in SPL**: SPL disables the USB3 OTG U3 port (`VPU_GRF_BASE + 0x44`); COMBPHY driver re-enables it later.

7. **stimer is only initialized in XPL builds**: The `rockchip_stimer_init()` function only runs for TPL/SPL builds, not full U-Boot.

8. **OTP-based SoC identification**: `checkboard()` reads OTP at offset 0x02 (cpu_code) and 0x28 (chip_type) to print SoC model like "RK3528A". Requires CONFIG_ROCKCHIP_OTP and CONFIG_MISC.

9. **no-sdio in sdhci (eMMC)**: The eMMC controller DTS has `no-sdio` and `no-sd`, it's exclusively eMMC. SD card is on `sdmmc` (SDHCI vs DW-MMC).

### FreeBSD Build Specifics

10. **Path sensitivity**: FreeBSD kernel build requires source at `/storage/home/virusv/workspace/freebsd` — the Makefile has hardcoded paths.

11. **External rkbin is required**: The rkbin blobs in this repo's `bin/rk35/` subdirectory may differ from the ones expected by the build skills at `~/workspace/rkbin-tools/rk35/`. The skill references `rk3528_ddr_1056MHz_v1.09.bin` and `rk3528_bl31_v1.17.elf` — but this repo has `v1.11` (DDR) and `v1.20` (BL31).

### General

12. **No CI/CD**: No GitHub Actions, no CI config files. This is a manual build workflow.

13. **Two separate git repos**: `u-boot/` and `rkbin/` are independent git submodules (or standalone repos). The root `rk3528a-freebsd/` is NOT itself a git repo.

## File Naming Conventions

- Rockchip binary naming: `[chip]_[module]_[feature]_v[version].[ext]`
- DTS files: `rk3528-[board].dts` (upstream), `rk3528-[board]-u-boot.dtsi` (U-Boot overlay)
- Board code follows U-Boot convention: `board/<vendor>/<board>/<board>.c`
- Config header: `include/configs/<soc>_common.h`

## Testing & Debugging

- U-Boot has `DEBUG_UART` enabled at base `0xFF9F0000`, shift 2, 1500000 baud
- PCB board serial is UART0 (`serial0:1500000n8`)
- There is no `defconfig` change test framework — changes are validated by building and booting on real hardware
- Boot from TF card only (no eMMC or SPI flash boot documented in this port)
