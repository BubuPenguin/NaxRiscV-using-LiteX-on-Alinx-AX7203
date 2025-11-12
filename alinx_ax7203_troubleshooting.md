# Troubleshooting Guide - Alinx AX7203 Linux Boot

Comprehensive troubleshooting guide for Linux boot issues on the Alinx AX7203 FPGA board with NaxRiscv + OpenSBI.

**📖 Main Guide**: [Alinx AX7203 Boot Guide](alinx_ax7203_boot_guide.md)

---

## How to Use This Guide

1. **Find your symptom** in the Quick Symptom Lookup table below
2. **Jump to the relevant section** using the links
3. **Follow the diagnostic steps** to identify the root cause
4. **Apply the solution** for your specific issue

If you can't find your issue, check the diagnostic commands in Section 11.

---

## Table of Contents

1. [Quick Symptom Lookup](#1-quick-symptom-lookup)
2. [Build Phase Issues](#2-build-phase-issues)
3. [RootFS Creation Issues](#3-rootfs-creation-issues)
4. [SD Card Setup Issues](#4-sd-card-setup-issues)
5. [Boot Phase Issues](#5-boot-phase-issues)
6. [Post-Boot / Login Issues](#6-post-boot--login-issues)
7. [Hardware-Specific Issues](#7-hardware-specific-issues)
8. [Understanding System Components](#8-understanding-system-components)
9. [Diagnostic Command Reference](#9-diagnostic-command-reference)
10. [When to Ask for Help](#10-when-to-ask-for-help)

---

## 1. Quick Symptom Lookup

Find your issue quickly:

| Symptom | Section | Quick Fix Link |
|---------|---------|----------------|
| Kernel build fails "Error 2" | 2.1 | [Disable CONFIG_WERROR](#21-kernel-build-fails-with-error-2) |
| BTRFS/socket.c compilation errors | 2.1.1 | [Disable WERROR](#method-1-disable-config_werror-recommended) |
| "boot.json not found" on boot | 4.2 | [Create boot.json](#42-boot-json-file-not-found-at-boot) |
| SD card not visible in WSL | 4.1 | [Use Windows hybrid method](#41-sd-card-not-visible-in-wsl) |
| dd for Windows "Access Denied" | 4.3 | [Run PowerShell as Admin](#43-dd-for-windows-access-denied) |
| Hangs after "Liftoff!" | 5.1 | [Enable SBI console](#51-hangs-after-liftoff-no-opensbi-banner) |
| Complete silence after "Liftoff!" | 5.2 | [Fix DTS bootargs](#52-complete-silence-after-liftoff) |
| MMC/SD card driver panic | 5.3 | [Fix DTS addresses](#53-mmcsd-card-driver-panic) |
| "Unable to mount root fs" | 5.4 | [Check rootfs partition](#54-unable-to-mount-root-fs) |
| Login loop (immediate logout) | 6.1 | [Configure hvc0 console](#61-repeated-login-prompts-login-loop) |
| networking.service failed | 6.2 | [Enable CONFIG_MICREL_PHY](#62-networkingservice-failed--cannot-find-device) |
| Kernel Oops in LiteETH driver | 6.3 | [Disable networking service](#63-kernel-oops-in-liteeth-driver-memory-fault) |
| No IP address on eth0 | 6.4 | [Install isc-dhcp-client](#64-networking-works-but-no-ip-address--dhcp-client-missing) |
| Debootstrap "Invalid Release file" | 3.1 | [Use main Debian archive](#31-debootstrap-invalid-release-file) |
| Loop device missing after reboot | 3.3 | [Re-run losetup (normal)](#33-loop-device-missing-after-reboot) |
| "Can't find in /etc/fstab" | 3.4 | [Setup loop device first](#34-cant-find-in-etcfstab-error) |
| No output at all | 5.5 | [Check serial connection](#55-no-output-at-all) |

---

## 2. Build Phase Issues

### 2.1 Kernel Build Fails with "Error 2"

#### Symptom
```
make[1]: *** [scripts/Makefile.build:250: fs/btrfs] Error 2
make: *** [Makefile:1992: fs] Error 2
```

Or similar "Error 2" during kernel compilation.

#### Root Cause

"Error 2" is just make's exit code. The **actual error** appears earlier in the build output. Common causes:
- Compiler warnings being treated as errors (`-Werror`)
- Missing build dependencies
- Configuration conflicts
- Toolchain issues

#### Diagnosis Steps

**1. Find the actual error:**

```bash
cd litex-linux

# Scroll up in your terminal to find the first "error:" message
# Or save build output to file:
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- 2>&1 | tee build.log

# View errors from log:
grep -i error build.log | head -20
```

**2. Identify error type:**

Look for patterns like:
- `error: initializer-string ... truncates NUL terminator` → Compiler warning as error
- `error: array subscript ... is outside array bounds` → Compiler warning as error
- `fatal error: xyz.h: No such file or directory` → Missing dependency
- `riscv64-unknown-linux-gnu-gcc: command not found` → Toolchain issue

---

### 2.1.1 Specific Error: BTRFS print-tree.c / net/socket.c

#### Error Messages

```
fs/btrfs/print-tree.c:26:49: error: initializer-string for array of 'char' is too long [-Werror=unterminated-string-initialization]
```

```
net/socket.c:650:21: error: array subscript -1 is outside array bounds [-Werror=array-bounds]
```

These are GCC warnings being treated as errors due to `-Werror` flag.

#### Solutions

##### Method 1: Disable CONFIG_WERROR (Recommended)

**Simplest and most reliable fix:**

```bash
cd litex-linux

# Disable treating warnings as errors
scripts/config --disable CONFIG_WERROR

# Verify it's disabled
grep CONFIG_WERROR .config
# Should show: # CONFIG_WERROR is not set

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

**Why this works**: Allows compilation to continue despite non-critical warnings. These warnings are often false positives from aggressive compiler checks.

##### Method 2: Per-File Warning Disable (Alternative)

If you want to keep `-Werror` for other files:

```bash
cd litex-linux

# Disable warning for BTRFS file
echo 'CFLAGS_print-tree.o += -Wno-error=stringop-truncation' >> fs/btrfs/Makefile

# Disable warning for socket.c
echo 'CFLAGS_socket.o += -Wno-error=array-bounds' >> net/Makefile

# Verify flags were added
tail -2 fs/btrfs/Makefile
tail -2 net/Makefile

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

##### Method 3: Patch Source Code (Proper Fix)

For BTRFS issue, increase array size:

```bash
cd litex-linux

# Fix BTRFS array size (line 26, increase [16] to [17])
sed -i '26s/\[16\]/[17]/' fs/btrfs/print-tree.c

# For net/socket.c, manual inspection needed - might be false positive
# Check the code context around line 650

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

---

### 2.2 Missing Build Dependencies

#### Symptom

```
fatal error: ncurses.h: No such file or directory
# or
bison: command not found
# or
flex: command not found
```

#### Solution

```bash
# Install all required build dependencies
sudo apt-get install -y \
    libncurses-dev \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    bc

# Retry build
cd litex-linux
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

---

### 2.3 Configuration Conflicts

#### Symptom

```
warning: override: reassigning to symbol ...
# or
Configuration file ".config" is outdated
```

#### Solution

```bash
cd litex-linux

# Regenerate config to resolve conflicts
make ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- oldconfig
# Press Enter for default choices when prompted

# Re-enable your custom options
scripts/config --enable CONFIG_MICREL_PHY
scripts/config --disable CONFIG_WERROR

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

---

### 2.4 Clean Rebuild (Last Resort)

If build continues to fail:

```bash
cd litex-linux

# Clean previous build artifacts
make ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- clean

# Or for deep clean (removes .config too):
make ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- mrproper

# If you did mrproper, reconfigure:
cp /home/riscv_dev/naxsoftware_config.txt .config
make ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- olddefconfig
scripts/config --enable CONFIG_MICREL_PHY
scripts/config --disable CONFIG_WERROR

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

---

### 2.5 Toolchain Issues

#### Symptom

```
riscv64-unknown-linux-gnu-gcc: command not found
```

#### Solution

```bash
# Verify toolchain exists
ls $HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc
# If not found, rebuild toolchain (see Main Guide Step 1)

# Verify toolchain works
$HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc --version
# Should show GCC version

# Ensure CROSS_COMPILE is set correctly
export CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-
echo $CROSS_COMPILE
# Should show: /home/yourusername/riscv/bin/riscv64-unknown-linux-gnu-

# Retry build
cd litex-linux
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

---

### 2.6 OpenSBI Build Issues

#### Symptom

```
make: riscv-none-embed-gcc: Command not found
```

#### Solution

Use your Linux toolchain instead:

```bash
cd opensbi
make CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- PLATFORM=litex/naxriscv

# Verify firmware was created
ls -lh build/platform/litex/naxriscv/firmware/fw_jump.bin
# Should be ~130KB
```

---

## 3. RootFS Creation Issues

### 3.1 Debootstrap: "Invalid Release file"

#### Symptom

```
E: Invalid Release file, no entry for main/binary-riscv64/Packages
```

#### Root Cause

As of **July 2023**, RISC-V 64-bit is an **official Debian architecture** and moved from Debian Ports to the main archive. Old guides reference the ports archive which no longer has riscv64.

#### Solution

Use the **main Debian archive** with proper keyring:

```bash
export MNT=$PWD/mnt

# Install Debian archive keyring (NOT ports keyring)
sudo apt-get update
sudo apt-get install -y debian-archive-keyring

# Verify keyring exists
ls -la /usr/share/keyrings/debian-archive-keyring.gpg

# Bootstrap from main Debian archive
sudo debootstrap --arch=riscv64 --foreign \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    unstable $MNT http://deb.debian.org/debian

# Copy QEMU emulator
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/

# Complete second stage
sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    LC_ALL=C LANGUAGE=C LANG=C \
    chroot $MNT /debootstrap/debootstrap --second-stage
```

#### Alternative Suites

If `unstable` doesn't work, try:

```bash
# Try 'sid' (same as unstable)
sudo debootstrap --arch=riscv64 --foreign \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    sid $MNT http://deb.debian.org/debian

# Or try 'bookworm' (stable)
sudo debootstrap --arch=riscv64 --foreign \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    bookworm $MNT http://deb.debian.org/debian
```

---

### 3.2 Chroot: "Cannot determine your user name"

#### Symptom

Error when running commands in chroot:
```
Cannot determine your user name
```

#### Solution

Set environment variables before chroot:

```bash
# Enter chroot with proper environment
sudo LC_ALL=C LANGUAGE=C LANG=C chroot $MNT /bin/bash

# Or if already in chroot:
export USER=root
export LOGNAME=root
export HOME=/root
```

---

### 3.3 Loop Device Missing After Reboot

#### Symptom

```bash
sudo mount /dev/loop0 $MNT
mount: /home/riscv_dev/mnt: special device /dev/loop0 does not exist.
```

#### Root Cause

**This is NORMAL behavior!** Loop devices are **temporary** and disappear after:
- System reboot
- Manual detach (`losetup -d`)

#### Solution

**Just re-setup the loop device** (this is expected workflow):

```bash
cd /home/riscv_dev

# Set mount point variable
export MNT=$PWD/mnt

# Check current loop devices (probably empty after reboot)
sudo losetup -a

# Re-setup loop device (THIS IS NORMAL - do this each session)
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Loop device: $LOOP_DEV"

# Mount filesystem
mkdir -p $MNT
sudo mount -t ext4 $LOOP_DEV $MNT

# Verify mounted
mount | grep $LOOP_DEV
```

#### Important

**DO NOT redo the entire rootfs creation** just because the loop device is missing! The image file (`debian-sid-risc-v-root.img`) is still there with all your data. Just remount it.

**Only redo rootfs creation if:**
- The image file is deleted or corrupted
- You want to start completely fresh (accepting data loss)

---

### 3.4 "Can't find in /etc/fstab" Error

#### Symptom

```bash
sudo mount $LOOP_DEV $MNT
mount: /home/riscv_dev/mnt: can't find in /etc/fstab.
```

#### Root Cause

Either:
1. Loop device not set up yet, OR
2. Mounting without specifying filesystem type

#### Solution

```bash
# First, verify loop device exists
sudo losetup -a
# If nothing shows, set up loop device:
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Loop device: $LOOP_DEV"

# Then mount with explicit filesystem type
sudo mount -t ext4 $LOOP_DEV $MNT

# Verify mounted
mount | grep $LOOP_DEV
# Should show: /dev/loop0 on /home/riscv_dev/mnt type ext4 ...
```

---

## 4. SD Card Setup Issues

### 4.1 SD Card Not Visible in WSL

#### Symptom

```bash
lsblk
# SD card doesn't appear in the list
```

#### Root Cause

WSL has **limited direct access** to removable media. This is a WSL limitation, not a problem with your setup.

#### Solution

Use the **hybrid approach** (recommended for WSL):

1. **Format SD card in Windows** (Disk Management or PowerShell)
2. **Copy boot files from WSL** (WSL can access Windows drives via `/mnt/e`)
3. **Write rootfs using dd for Windows** (PowerShell tool)

See [Main Guide Section 8 - Setup SD Card](alinx_ax7203_boot_guide.md#8-step-5-setup-sd-card-wsl-focus) for complete procedure.

---

### 4.2 "boot.json file not found" at Boot

#### Symptom

During boot, LiteX BIOS shows:
```
Booting from SD card...
boot.json file not found
# or
boot.bin file not found
```

#### Root Cause

1. `boot.json` file missing from SD card boot partition, OR
2. Files not properly written to SD card, OR
3. SD card not properly ejected (data not flushed)

#### Diagnosis

```bash
# In WSL, remount SD card boot partition
sudo umount /mnt/e 2>/dev/null || true
sudo mount -t drvfs E: /mnt/e

# Check if files exist
ls -lh /mnt/e/
# Should show: boot.json, Image, linux.dtb, opensbi.bin, etc.

# Check boot.json content
cat /mnt/e/boot.json
# Should show JSON with addresses
```

#### Solution

**Create boot.json:**

```bash
# Mount boot partition
sudo umount /mnt/e 2>/dev/null || true
sudo mount -t drvfs E: /mnt/e

# Create boot.json
cat > /tmp/boot.json <<'EOF'
{
	"Image":       "0x41000000",
	"linux.dtb":   "0x46000000",
	"opensbi.bin": "0x40f00000"
}
EOF

# Copy to SD card
sudo cp /tmp/boot.json /mnt/e/

# Verify it was created
cat /mnt/e/boot.json
ls -lh /mnt/e/boot.json

# CRITICAL: Sync to ensure data is written
sync

# Verify persistence (remount and check again)
sudo umount /mnt/e
sudo mount -t drvfs E: /mnt/e
ls -lh /mnt/e/
# Files should still be there
```

**If files still missing after remount:**

1. SD card might be faulty
2. Reformat boot partition (FAT32) and recopy files
3. Try a different SD card

---

### 4.3 dd for Windows: "Access Denied"

#### Symptom

```powershell
.\dd.exe if="..." of="..." bs=1M
# Error: Access denied
```

#### Root Cause

PowerShell not running with Administrator privileges, or drive is in use.

#### Solution

**1. Run PowerShell as Administrator:**

- Right-click PowerShell icon
- Select "Run as Administrator"
- Retry dd command

**2. Unmount drive first:**

```powershell
# Check if drive is mounted
Get-Volume -DriveLetter F

# If mounted, try to dismount (might fail in Windows)
# Instead, use Disk Management:
# - Right-click F: drive
# - Select "Change Drive Letter and Paths..."
# - Remove the drive letter temporarily
# - Run dd.exe
# - Reassign drive letter after
```

**3. Verify Volume GUID:**

```powershell
# Make sure you're using the correct Volume GUID
$volumeId = (Get-Volume -DriveLetter F).UniqueId
Write-Host "Volume GUID: $volumeId"

# Verify it's your SD card root partition, not Windows drive!
Get-Partition -DriveLetter F | Format-List
```

---

### 4.4 Wrote to Wrong Partition (Data Loss)

#### Symptom

Accidentally wrote rootfs image to wrong drive, lost data.

#### Prevention

**ALWAYS verify before running dd:**

```powershell
# ⚠️ SAFETY CHECKLIST - Run BEFORE dd ⚠️

# 1. Verify target partition
Get-Partition -DriveLetter F | Format-List
# Confirm: Size ~59GB, DriveLetter F:, DiskNumber matches SD card

# 2. Verify source image
Test-Path "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img"
# Should return: True

# 3. Check image size
(Get-Item "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img").Length / 1GB
# Should show ~7GB

# 4. Verify Volume GUID matches F: drive
(Get-Volume -DriveLetter F).UniqueId
# Make note of the GUID

# 5. Double-check disk number
Get-Disk
# Verify SD card disk number (e.g., Disk 3)

# ONLY after all checks pass, run dd.exe
```

**If data loss occurred:**
- There's no undo for dd.exe
- Data recovery tools might help (TestDisk, PhotoRec)
- Restore from backup if available

---

## 5. Boot Phase Issues

### 5.1 Hangs After "Liftoff!" (No OpenSBI Banner)

#### Symptom

Boot output shows:
```
--============= Liftoff! ===============--

[complete silence, no further output]
```

No OpenSBI banner appears.

#### Root Cause

Kernel **SBI console not enabled**. The kernel boots but has no console output because it can't use the SBI console interface.

#### Diagnosis

```bash
cd litex-linux

# Check if SBI console is enabled
grep CONFIG_SERIAL_EARLYCON_RISCV_SBI .config
# Must show: CONFIG_SERIAL_EARLYCON_RISCV_SBI=y

grep CONFIG_RISCV_SBI_V01 .config
# Must show: CONFIG_RISCV_SBI_V01=y

grep CONFIG_HVC_RISCV_SBI .config
# Must show: CONFIG_HVC_RISCV_SBI=y
```

#### Solution

**Enable SBI console in kernel config:**

```bash
cd litex-linux

# Enable SBI console support
scripts/config --enable CONFIG_SERIAL_EARLYCON_RISCV_SBI
scripts/config --enable CONFIG_RISCV_SBI_V01
scripts/config --enable CONFIG_RISCV_SBI
scripts/config --enable CONFIG_HVC_RISCV_SBI

# Verify enabled
grep -E "(CONFIG_SERIAL_EARLYCON_RISCV_SBI|CONFIG_RISCV_SBI_V01|CONFIG_HVC_RISCV_SBI)" .config

# Rebuild kernel
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all

# Copy new kernel to SD card
sudo mount -t drvfs E: /mnt/e
sudo cp arch/riscv/boot/Image /mnt/e/
sync
sudo umount /mnt/e

# Reboot board and test
```

---

### 5.2 Complete Silence After "Liftoff!"

#### Symptom

```
--============= Liftoff! ===============--

OpenSBI v1.3.1
   ____                    _____ ____ _____
  ...OpenSBI banner shows...

Boot HART ID              : 0
...

[then complete silence, no Linux messages]
```

#### Root Cause

Device Tree **bootargs missing `earlycon=sbi`**. The kernel starts but doesn't know to use SBI for early console output.

#### Diagnosis

```bash
# Check DTS bootargs
cd build/alinx_ax7203
grep bootargs linux.dts
# Should show: bootargs = "earlycon=sbi console=hvc0 root=/dev/mmcblk0p2 rootwait";

# Or check DTB directly
dtc -I dtb -O dts linux.dtb | grep bootargs
```

#### Solution

**Fix bootargs in DTS:**

```bash
cd build/alinx_ax7203

# Edit linux.dts
nano linux.dts  # or your preferred editor

# Find the chosen node, add/fix bootargs:
# chosen {
#     bootargs = "earlycon=sbi console=hvc0 root=/dev/mmcblk0p2 rootwait";
# };

# Save file, then recompile DTB
dtc -I dts -O dtb -o linux.dtb linux.dts

# Verify bootargs in new DTB
dtc -I dtb -O dts linux.dtb | grep bootargs

# Copy new DTB to SD card
sudo mount -t drvfs E: /mnt/e
sudo cp linux.dtb /mnt/e/
sync
sudo umount /mnt/e

# Reboot board and test
```

**Critical bootargs parameters:**
- `earlycon=sbi` - Enable early console via SBI (REQUIRED for output!)
- `console=hvc0` - Main console device (for SBI console)
- `root=/dev/mmcblk0p2` - Root filesystem device
- `rootwait` - Wait for root device to appear

---

### 5.3 MMC/SD Card Driver Panic

#### Symptom

```
[    2.345000] litex-mmc f0004000.mmc: Requested clk_freq=12500000
[    2.356000] Unable to handle kernel paging request at virtual address ffffffc800405010
[    2.367000] Oops - store (or AMO) access fault [#1]
[    2.378000] epc : litex_mmc_probe+0x20/0x176
[    2.389000] Kernel panic - not syncing: Attempted to kill init!
```

#### Root Cause

**Device Tree address mismatch** with actual hardware. The DTS has MMC at one address (e.g., `0xf0028000`), but LiteX instantiated it at a different address (e.g., `0xf0004000`).

**Why this happens:**
- LiteX auto-generates hardware addresses (see `csr.csv`)
- DTS might be manually created or copied from another board
- Addresses don't match, kernel tries to access wrong address → crash

#### Diagnosis

```bash
# Check actual hardware addresses in csr.csv
cd build/alinx_ax7203
grep sdcard csr.csv
# Shows actual SD card register addresses

# Check DTS addresses
grep -A5 "mmc@" linux.dts
# Shows configured addresses in device tree

# Compare - they probably don't match!
```

#### Solution 1: Fix DTS Addresses (Recommended)

```bash
cd build/alinx_ax7203

# Edit linux.dts
nano linux.dts

# Find mmc0 node (around line 130)
# Change from:
#   mmc0: mmc@f0028000 {
#       reg = <0xf0028000 0x18>,    # Wrong address!
#             ...
#
# To match csr.csv addresses (example - check YOUR csr.csv):
#   mmc0: mmc@f0004000 {
#       reg = <0xf0004000 0x18>,    # Correct address from csr.csv
#             <0xf000401c 0xa8>,
#             <0xf0004048 0x9c>,
#             <0xf0004064 0x9c>,
#             <0xf0004080 0x4>;

# Save file, recompile DTB
dtc -I dts -O dtb -o linux.dtb linux.dts

# Copy to SD card
sudo mount -t drvfs E: /mnt/e
sudo cp linux.dtb /mnt/e/
sync
sudo umount /mnt/e

# Reboot and test
```

#### Solution 2: Temporarily Disable MMC (Quick Test)

To test boot without SD card root:

```bash
cd build/alinx_ax7203

# Edit linux.dts
nano linux.dts

# Find mmc0 node, change status:
#   mmc0: mmc@f0028000 {
#       ...
#       status = "disabled";  # Changed from "okay"
#   };

# Save, recompile
dtc -I dts -O dtb -o linux.dtb linux.dts

# Copy to SD card and test
```

---

### 5.4 "Unable to mount root fs"

#### Symptom

```
[    3.456000] VFS: Cannot open root device "mmcblk0p2" or unknown-block(0,0)
[    3.467000] Please append a correct "root=" boot option
[    3.478000] Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)
```

#### Root Cause

1. Root filesystem partition not written correctly, OR
2. Wrong `root=` parameter in bootargs, OR
3. Missing rootfs (if you haven't created it yet, this is EXPECTED)

#### Diagnosis

```bash
# Check bootargs in DTB
cd build/alinx_ax7203
dtc -I dtb -O dts linux.dtb | grep bootargs
# Should show: root=/dev/mmcblk0p2

# Check if MMC driver loaded successfully (from boot log)
# Look for: mmc0: new SD card at address...
#           mmcblk0: mmc0:0001 SD64G 58.2 GiB
#            mmcblk0: p1 p2
```

#### Solution

**1. Verify rootfs partition was written:**

From Windows PowerShell:
```powershell
# Check partition 2 exists
Get-Partition -DriveLetter F | Format-List
# Should show ~59GB partition

# Verify dd write completed successfully
# If you saved dd output, check for "X+0 records in, X+0 records out"
```

**2. Verify bootargs:**

```bash
cd build/alinx_ax7203

# Check bootargs in DTS
grep bootargs linux.dts
# Should show: root=/dev/mmcblk0p2

# If wrong, fix and recompile DTB
nano linux.dts  # fix bootargs
dtc -I dts -O dtb -o linux.dtb linux.dts
# Copy to SD card
```

**3. If you haven't created rootfs yet:**

This error is **EXPECTED** if you're testing without rootfs. The fact you get this far means:
- ✅ Boot files working
- ✅ OpenSBI → Linux handoff successful
- ✅ Kernel running
- ❌ Just missing rootfs

Create the rootfs (Main Guide Section 7) and write to SD card (Main Guide Section 8).

**4. Rewrite rootfs partition:**

If rootfs write might have failed, redo:

```powershell
# In PowerShell as Administrator
cd C:\tools\dd-0.6beta3
$volumeGuid = (Get-Volume -DriveLetter F).UniqueId -replace '\\\\\?\\', '\\.\' -replace '\\$', ''
.\dd.exe if="\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" of="$volumeGuid" bs=1M
```

---

### 5.5 No Output at All

#### Symptom

Completely silent - no serial output whatsoever.

#### Diagnosis Checklist

```
Physical Connection:
  ☐ Serial cable connected to board and PC
  ☐ Power LED on board is lit
  ☐ Correct COM port selected (check Device Manager on Windows)
  ☐ Baud rate set to 115200
  ☐ Data bits: 8, Stop bits: 1, Parity: None
  ☐ Flow control: None

SD Card:
  ☐ SD card inserted in board
  ☐ SD card has boot files (boot.json, Image, opensbi.bin, linux.dtb)

Software:
  ☐ Terminal emulator running (PuTTY, screen, minicom)
  ☐ Terminal emulator connected to correct port
```

#### Solution

**1. Verify serial connection:**

```bash
# On Linux/WSL, check if serial device exists
ls -l /dev/ttyUSB0
# or
ls -l /dev/ttyS*

# On Windows, check Device Manager:
# - Ports (COM & LPT)
# - Look for USB Serial Port (COM3 or similar)
```

**2. Test serial with different tool:**

Try a different terminal emulator:
- Windows: PuTTY, Tera Term, RealTerm
- Linux: screen, minicom, picocom

**3. Verify board power and FPGA:**

- Check power LED
- Try pressing reset button
- Verify FPGA bitstream is loaded (other LEDs should indicate FPGA activity)

**4. Test with known-working serial connection:**

If you have other serial devices, test your serial cable and software setup with them first.

---

## 6. Post-Boot / Login Issues

### 6.1 Repeated Login Prompts (Login Loop)

#### Symptom

After entering username and password:
```
alinx_ax7203 login: root
Password: [enter password]
[immediately logs out]
alinx_ax7203 login: _
```

Login succeeds but immediately exits back to login prompt.

#### Root Causes (In Order of Likelihood)

1. **TTY/Console misconfiguration** (most common for RISC-V with SBI)
2. Shell doesn't exist or isn't executable
3. Systemd getty restart loop
4. Profile/shell configuration errors

---

#### Solution 1: Configure hvc0 Console (Most Likely Fix)

**Why this is needed:**

RISC-V systems with OpenSBI use **hvc0** (hypervisor console) device, NOT `ttyS0` (traditional serial). Systemd getty must be configured for hvc0, otherwise login sessions exit immediately.

**From host system (before boot or from rescue mode):**

```bash
# Mount rootfs image
cd /home/riscv_dev
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Enter chroot
sudo chroot $MNT /bin/bash

# Inside chroot - Enable getty for hvc0
systemctl enable serial-getty@hvc0.service 2>/dev/null || \
  ln -sf /lib/systemd/system/serial-getty@.service \
         /etc/systemd/system/getty.target.wants/serial-getty@hvc0.service

# Create service override
mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/
cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/hvc0
StandardInput=tty
StandardOutput=tty
Restart=always
RestartSec=0
EOF

# Verify configuration
ls -la /etc/systemd/system/getty.target.wants/ | grep hvc0
cat /etc/systemd/system/serial-getty@hvc0.service.d/override.conf

# Exit chroot
exit

# Unmount
sudo umount $MNT
sudo losetup -d $LOOP_DEV

# Write updated rootfs to SD card (see Main Guide Section 8.4)
```

**Verification checklist:**
- ✅ Symlink exists: `/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service`
- ✅ Override file exists: `/etc/systemd/system/serial-getty@hvc0.service.d/override.conf`
- ✅ Override file has correct content (TTYPath=/dev/hvc0, etc.)

---

#### Solution 2: Fix Shell Configuration

**Check if bash exists and is configured:**

```bash
# From host system, mount and check
cd /home/riscv_dev
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Check root's shell
grep "^root:" $MNT/etc/passwd
# Must show: root:x:0:0:root:/root:/bin/bash
# NOT: /bin/false, /usr/sbin/nologin, or empty

# Verify bash exists and is executable
test -x $MNT/bin/bash && echo "bash OK" || echo "bash MISSING!"

# If shell is wrong, fix it:
sudo chroot $MNT /bin/bash -c 'chsh -s /bin/bash root'

# Verify fix
grep "^root:" $MNT/etc/passwd

# Unmount
sudo umount $MNT
```

**From running system** (if you can get a brief moment):

```bash
# Quickly change root's shell
chsh -s /bin/bash root

# Exit and try logging in again
exit
```

---

#### Solution 3: Disable Auto-Restart (Diagnostic)

To prevent getty from restarting immediately (helps diagnose):

```bash
# In chroot
sudo chroot $MNT /bin/bash

mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/
cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/hvc0
Restart=no
StandardInput=tty
StandardOutput=tty
TTYReset=no
TTYVHangup=no
EOF

exit
```

This prevents automatic restart, allowing you to see error messages.

---

### 6.2 networking.service Failed / "Cannot find device"

#### Symptom

```
[FAILED] Failed to start networking.service - Raise network interfaces.
```

Or:

```bash
systemctl status networking.service
# Shows: Cannot find device "eth0"
```

#### Root Cause

**Missing CONFIG_MICREL_PHY** in kernel configuration. The LiteETH driver is present, but it cannot communicate with the KSZ9031RNX PHY chip without the Micrel PHY driver.

**Why BIOS works but Linux doesn't:**
- LiteX BIOS has its own simple Ethernet driver
- Linux requires proper PHY drivers through the PHYLIB abstraction layer
- BIOS proving hardware works confirms this is a kernel config issue, NOT hardware failure

#### Diagnosis

```bash
cd litex-linux

# Check for Ethernet drivers in kernel config
grep -E "CONFIG_LITEETH|CONFIG_MICREL_PHY|CONFIG_MDIO_BUS|CONFIG_MII" .config

# Must show:
# CONFIG_LITEETH=y
# CONFIG_MICREL_PHY=y          ← Often missing!
# CONFIG_MDIO_BUS=y
# CONFIG_MII=y

# On running system, check if eth0 exists
ip link show
# Should show eth0 (not just lo)

# Check kernel messages
dmesg | grep -i "eth\|phy\|mdio"
# Should show PHY detection and Ethernet initialization
```

#### Solution

**Enable Micrel PHY driver in kernel:**

```bash
cd litex-linux

# Enable required Ethernet drivers
scripts/config --enable CONFIG_LITEETH
scripts/config --enable CONFIG_MICREL_PHY     # Critical!
scripts/config --enable CONFIG_MDIO_BUS
scripts/config --enable CONFIG_MDIO_DEVICE
scripts/config --enable CONFIG_MII
scripts/config --enable CONFIG_PHYLIB

# Verify enabled
grep -E "CONFIG_MICREL_PHY|CONFIG_LITEETH" .config
# Should show:
# CONFIG_LITEETH=y
# CONFIG_MICREL_PHY=y

# Rebuild kernel
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all

# Copy new kernel to SD card
sudo mount -t drvfs E: /mnt/e
sudo cp arch/riscv/boot/Image /mnt/e/
sync
sudo umount /mnt/e

# Reboot board and test
```

**On rebooted system, verify:**

```bash
# Check if eth0 appears
ip link show
# Should show: eth0: <...>

# Check PHY detection
dmesg | grep -i "phy\|micrel\|ksz9031"
# Should show: Micrel KSZ9031 PHY detected

# Check Ethernet driver
dmesg | grep -i liteeth
# Should show: liteeth f0024000.mac eth0: irq 1 slots: tx 2 rx 2

# Bring interface up
ip link set eth0 up

# Request DHCP
dhclient eth0

# Check IP assigned
ip addr show eth0
```

---

### 6.3 Kernel Oops in LiteETH Driver (Memory Fault)

#### Symptom

```
[    3.456000] Unable to handle kernel paging request at virtual address ffffffc800405010
[    3.467000] Oops - store (or AMO) access fault [#1]
[    3.478000] epc : liteeth_open+0x20/0x176
[    3.489000] badaddr: ffffffc800405010
...
[FAILED] Failed to start networking.service
```

Login works initially but system may hang when networking tries to start.

#### Root Cause

LiteETH driver trying to access invalid memory addresses, usually due to:
- Device tree address mismatch
- PHY initialization failure
- MDIO bus configuration issues

#### Quick Fix: Disable Networking (Allows Boot)

**From chroot (before booting):**

```bash
# Mount rootfs
cd /home/riscv_dev
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Enter chroot
sudo chroot $MNT /bin/bash

# Disable networking service
systemctl disable networking.service
systemctl mask networking.service

# Also disable other network services
systemctl disable dhcpcd.service 2>/dev/null || true
systemctl disable NetworkManager.service 2>/dev/null || true
systemctl disable systemd-networkd.service 2>/dev/null || true

# Exit chroot
exit

# Unmount
sudo umount $MNT
```

**From running system (if you can get shell briefly):**

```bash
# Disable networking
systemctl disable networking.service
systemctl mask networking.service
systemctl stop networking.service 2>/dev/null || true

# Reboot
reboot
```

**Alternative: Edit network interfaces to disable eth0:**

```bash
# In chroot
sudo chroot $MNT /bin/bash

cat > /etc/network/interfaces <<'EOF'
# Loopback only - ethernet disabled to prevent crash
auto lo
iface lo inet loopback

# Ethernet disabled (causes kernel oops)
# auto eth0
# iface eth0 inet dhcp
EOF

exit
```

#### Proper Fix: Verify Device Tree Configuration

```bash
cd build/alinx_ax7203

# Check LiteETH address in csr.csv
grep "liteeth\|mac" csr.csv

# Check DTS address
grep -A5 "ethernet@" linux.dts

# Compare - they should match!
# If not, edit linux.dts to match csr.csv addresses

# Also check PHY configuration
grep -A10 "mdio" linux.dts
# PHY node should reference correct MDIO bus and reg address
```

---

### 6.4 Networking Works But No IP Address / DHCP Client Missing

#### Symptom

```bash
ip link show eth0
# Shows: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> (carrier detected)

ip addr show eth0
# Shows: NO inet address (no IPv4)

dhclient eth0
# Shows: -bash: dhclient: command not found
```

#### Root Cause

DHCP client package (`isc-dhcp-client`) not installed during rootfs creation.

#### Solution: Install DHCP Client

**From host system, update rootfs:**

```bash
cd /home/riscv_dev
export MNT=$PWD/mnt

# Mount rootfs image
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Install DHCP client in chroot
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/ 2>/dev/null || true
sudo chroot $MNT apt-get update
sudo chroot $MNT apt-get install -y isc-dhcp-client

# Unmount
sudo umount $MNT
sudo losetup -d $LOOP_DEV

# Write updated rootfs to SD card (see Main Guide Section 8.4)
```

**After rebooting with updated rootfs:**

```bash
# DHCP should work automatically via networking.service
# Or manually request IP:
dhclient eth0
ip addr show eth0
# Should now show: inet X.X.X.X/24
```

#### Alternative: Static IP (Quick Workaround)

If you can't update rootfs immediately:

```bash
# Set static IP manually (adjust to match your network)
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1

# Test connectivity
ping -c 3 192.168.1.1

# To make persistent, edit /etc/network/interfaces:
cat >> /etc/network/interfaces <<'EOF'

auto eth0
iface eth0 inet static
    address 192.168.1.100
    netmask 255.255.255.0
    gateway 192.168.1.1
EOF
```

---

## 7. Hardware-Specific Issues

### 7.1 Ethernet PHY Not Detected

#### Symptom

```bash
dmesg | grep -i phy
# Shows: PHY detection failed
# or no output at all
```

#### Diagnosis

Check device tree PHY configuration:

```bash
cd build/alinx_ax7203

# Check PHY node in DTS
grep -A10 "mdio\|phy@" linux.dts

# Should show something like:
#   mdio {
#       phy0: phy@0 {
#           reg = <0>;  # PHY address on MDIO bus
#           ...
#       };
#   };
```

#### Solution

**1. Verify PHY address:**

The KSZ9031RNX PHY address is typically `0` or `1` (configured by hardware straps). Check your board schematic.

**2. Fix DTS PHY configuration:**

```bash
cd build/alinx_ax7203
nano linux.dts

# Ensure MDIO bus is present and PHY node is correct:
ethernet@f0024000 {
    ...
    mdio {
        #address-cells = <1>;
        #size-cells = <0>;
        
        phy0: ethernet-phy@0 {
            reg = <0>;  # or <1> depending on your board
            compatible = "ethernet-phy-ieee802.3-c22";
        };
    };
    
    phy-handle = <&phy0>;
    phy-mode = "rgmii-id";
};

# Save, recompile DTB
dtc -I dts -O dtb -o linux.dtb linux.dts

# Copy to SD card and test
```

---

### 7.2 SD Card Performance Issues

#### Symptom

Slow SD card read/write performance.

#### Solution

**1. Check SD card class:**

Use Class 10 or UHS-I/UHS-II cards for better performance.

**2. Apply SD_SLEEP_US tweak:**

```bash
cd litex-linux

# Reduce sleep time in MMC driver
sed -i 's/SD_SLEEP_US       5/SD_SLEEP_US       0/g' drivers/mmc/host/litex_mmc.c

# Rebuild kernel
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

**3. Check MMC clock frequency:**

```bash
# From running system
dmesg | grep -i "litex-mmc\|clk_freq"
# Shows: Requested clk_freq=12500000: set to 12500000
```

Higher clock = better performance (if hardware supports it).

---

### 7.3 Serial Console Garbled Output

#### Symptom

Serial output shows garbage characters or is unreadable.

#### Solution

**1. Verify baud rate:**

```bash
# Must be 115200 on both board and terminal
# In terminal emulator, check settings:
# - Baud: 115200
# - Data bits: 8
# - Stop bits: 1
# - Parity: None
# - Flow control: None
```

**2. Check cable quality:**

Poor quality USB-to-UART cables can cause signal integrity issues. Try a different cable.

**3. Check terminal emulator settings:**

Some emulators have encoding issues. Try:
- UTF-8 encoding
- VT100 or ANSI terminal type
- Disable line translation options

---

## 8. Understanding System Components

### 8.1 Boot Component Roles

Quick reference for debugging:

| Component | When It Runs | What It Does | If It Fails |
|-----------|--------------|--------------|-------------|
| FPGA Bitstream | Power-on | Loads FPGA config | No LED activity |
| LiteX BIOS | After FPGA loads | Initializes DDR, loads boot files | No serial output |
| OpenSBI | After BIOS | Firmware, provides SBI | Hangs after "Executing..." |
| Linux Kernel | After OpenSBI | OS kernel | Hangs after "Liftoff!" |
| Root FS | After kernel | User space | "Unable to mount root fs" |

### 8.2 Console Devices on RISC-V

**Understanding console device names:**

| Device | Description | Used By |
|--------|-------------|---------|
| `hvc0` | Hypervisor Console 0 | RISC-V SBI console (OpenSBI systems) |
| `ttyS0` | Serial Port 0 | Traditional UART (x86, ARM) |
| `ttyUSB0` | USB Serial Port 0 | USB-to-serial adapters (host PC side) |

**For RISC-V with OpenSBI, always use `hvc0`!**

```bash
# Correct bootargs:
bootargs = "earlycon=sbi console=hvc0 root=/dev/mmcblk0p2";

# Wrong (will cause issues):
bootargs = "console=ttyS0 root=/dev/mmcblk0p2";  # Missing earlycon=sbi
```

### 8.3 Device Tree Debugging

**Understanding device tree files:**

- **DTS** (Device Tree Source): Human-readable text format
- **DTB** (Device Tree Blob): Binary format used by kernel

**Compile/decompile:**

```bash
# DTS → DTB (compile)
dtc -I dts -O dtb -o output.dtb input.dts

# DTB → DTS (decompile for inspection)
dtc -I dtb -O dts -o output.dts input.dtb

# Check bootargs in DTB
dtc -I dtb -O dts linux.dtb | grep bootargs

# Check a specific node
dtc -I dtb -O dts linux.dtb | grep -A10 "ethernet@"
```

**Common DTS mistakes:**

1. **Wrong addresses**: Must match `csr.csv` from LiteX build
2. **Missing bootargs**: Kernel won't know console device
3. **Wrong reg format**: Check `#address-cells` and `#size-cells`
4. **Missing status = "okay"**: Device won't be enabled

---

## 9. Diagnostic Command Reference

### 9.1 Build System Diagnostics

```bash
# Verify toolchain
$HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc --version
ls -lh $HOME/riscv/bin/riscv64-unknown-linux-gnu-*

# Check kernel config
cd litex-linux
grep CONFIG_SERIAL_EARLYCON_RISCV_SBI .config
grep CONFIG_MICREL_PHY .config
grep CONFIG_LITEETH .config

# Check DTS bootargs
cd build/alinx_ax7203
grep bootargs linux.dts

# Verify DTB content
dtc -I dtb -O dts linux.dtb | grep bootargs

# Check file sizes
ls -lh litex-linux/arch/riscv/boot/Image         # ~19MB
ls -lh opensbi/build/.../fw_jump.bin             # ~130KB
ls -lh build/alinx_ax7203/linux.dtb              # ~3KB
```

### 9.2 RootFS Diagnostics

```bash
# Check loop device status
sudo losetup -a

# Verify filesystem integrity
sudo fsck -n /dev/loop0

# Check critical files in mounted rootfs
export MNT=$PWD/mnt
ls -l $MNT/bin/bash
grep "^root:" $MNT/etc/passwd
cat $MNT/etc/fstab
cat $MNT/etc/hostname

# Check TTY configuration
ls -la $MNT/etc/systemd/system/getty.target.wants/ | grep hvc0
cat $MNT/etc/systemd/system/serial-getty@hvc0.service.d/override.conf

# Check disk usage
du -sh $MNT
du -sh $MNT/* 2>/dev/null | sort -h | tail -5
```

### 9.3 Boot Diagnostics

```bash
# Check boot files on SD card (from WSL)
ls -lh /mnt/e/
cat /mnt/e/boot.json

# Verify boot.json format
cat /mnt/e/boot.json | python3 -m json.tool  # Check valid JSON

# Verify DTB bootargs
dtc -I dtb -O dts /mnt/e/linux.dtb | grep bootargs

# Check file checksums (if you suspect corruption)
sha256sum /mnt/e/Image
sha256sum /mnt/e/opensbi.bin
```

### 9.4 Running System Diagnostics

```bash
# Check kernel version and architecture
uname -a
# Should show: Linux ... riscv64 GNU/Linux

# Check boot command line
cat /proc/cmdline

# Check CPU info
cat /proc/cpuinfo
# Should show: NaxRiscv processor

# Check memory
free -h
cat /proc/meminfo

# Check storage
lsblk
df -h

# Check network interface
ip link show
ip addr show eth0

# Check Ethernet driver
dmesg | grep -i "liteeth\|eth0"
# Should show: liteeth f0024000.mac eth0: ...

# Check PHY
dmesg | grep -i "phy\|micrel\|ksz9031"
# Should show: Micrel KSZ9031 PHY detected

# Check services
systemctl status networking.service
systemctl status serial-getty@hvc0.service
systemctl status sshd.service

# Check system logs
journalctl -b | tail -100
journalctl -u networking.service
journalctl -u serial-getty@hvc0.service

# Check kernel messages
dmesg | tail -50
dmesg | grep -i "error\|fail\|warn"
```

---

## 10. When to Ask for Help

If you've tried the troubleshooting steps and still have issues, gather this information before asking for help:

### Information to Provide

**1. Which step are you at?**
- Step X: [Toolchain / Kernel / OpenSBI / RootFS / SD Card / Boot]

**2. Exact error message:**
```
[Paste complete error output, not just "Error 2"]
```

**3. Diagnostic command outputs:**
```bash
# Run relevant commands from Section 9 and paste output
```

**4. What you've tried:**
- List troubleshooting steps already attempted
- Any changes made to default configuration

**5. Platform information:**
```bash
# WSL version
wsl --version

# Ubuntu version
lsb_release -a

# Toolchain version
$HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc --version

# Kernel config (if relevant)
cd litex-linux
grep -E "(CONFIG_SERIAL_EARLYCON_RISCV_SBI|CONFIG_MICREL_PHY)" .config

# SD card info
# Size, brand, class rating
```

**6. Hardware information:**
- Board model: Alinx AX7203
- FPGA: [model]
- NaxRiscv clock speed: [MHz]
- DDR3 size: [MB]
- SD card: [size, brand, class]

### Where to Ask

**Community Forums:**
- **LiteX Discord**: https://discord.gg/litex
- **RISC-V Forums**: https://forums.riscv.org/
- **Alinx Support**: https://www.alinx.com/

**GitHub Issues:**
- LiteX: https://github.com/enjoy-digital/litex/issues
- NaxRiscv: https://github.com/SpinalHDL/NaxRiscv/issues
- OpenSBI: https://github.com/riscv-software-src/opensbi/issues

**Email Lists:**
- RISC-V SW Dev: sw-dev@lists.riscv.org

### Before Posting

- ✅ Search existing issues/posts for similar problems
- ✅ Include all diagnostic information (see above)
- ✅ Format code/logs in code blocks
- ✅ Be specific about what you expected vs what happened
- ✅ List what you've already tried

---

## Appendix: Common Boot Sequences

### A1: Successful Boot

```
[BIOS initialization]
--=============== SoC ==================--
CPU:		NaxRiscv 64-bit @ 100MHz
...
--============== Boot ==================--
Loading Image to 0x41000000 (20971520 bytes)...
Loading linux.dtb to 0x46000000 (3076 bytes)...
Loading opensbi.bin to 0x40f00000 (274016 bytes)...
Executing booted program at 0x40f00000

[OpenSBI initialization]
--============= Liftoff! ===============--
OpenSBI v1.3.1
Platform Name: LiteX/VexRiscv-SMP
...

[Kernel boot]
[    0.000000] Linux version 6.1.0 ...
[    0.000000] early console: using RISC-V SBI
[    0.000000] printk: console [sbi] enabled
...
[    2.345000] liteeth f0024000.mac eth0: ...
[    2.456000] mmc0: new SD card ...
[    3.567000] EXT4-fs (mmcblk0p2): mounted filesystem ...
...
Debian GNU/Linux bookworm/sid alinx_ax7203 hvc0

alinx_ax7203 login: _
```

### A2: Boot Failure Patterns

**Pattern 1: Hangs after "Executing booted program"**
→ OpenSBI not starting (check OpenSBI file/address)

**Pattern 2: "Liftoff!" then silence**
→ Kernel SBI console not enabled (CONFIG_SERIAL_EARLYCON_RISCV_SBI)

**Pattern 3: OpenSBI banner, then silence**
→ DTS bootargs missing "earlycon=sbi"

**Pattern 4: Kernel panic in MMC driver**
→ DTS address mismatch with hardware

**Pattern 5: "Unable to mount root fs"**
→ Rootfs not written or wrong root= parameter

**Pattern 6: Login loop**
→ hvc0 console not configured in systemd

---

**Last Updated**: 2025-11-09

**Guide Version**: 2.0 (Comprehensive Troubleshooting)

---

**Return to**: [Main Boot Guide](alinx_ax7203_boot_guide.md)

