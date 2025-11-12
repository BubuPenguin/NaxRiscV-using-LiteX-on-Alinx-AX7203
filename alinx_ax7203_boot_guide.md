# Booting Linux on Alinx AX7203 with NaxRiscv + OpenSBI

This guide documents the complete process for booting Linux on your Alinx AX7203 board using **OpenSBI** as the second-stage bootloader. The guide is optimized for **WSL2/Ubuntu** environments.

**⚠️ Troubleshooting**: If you encounter issues, see the companion [Troubleshooting Guide](alinx_ax7203_troubleshooting.md).

---

## Table of Contents

1. [Prerequisites & System Requirements](#1-prerequisites--system-requirements)
2. [Understanding the Boot Process](#2-understanding-the-boot-process)
3. [Quick Start Guide](#3-quick-start-guide-for-experienced-users)
4. [Step 1: Build RISC-V Toolchain](#4-step-1-build-risc-v-toolchain)
5. [Step 2: Build Linux Kernel](#5-step-2-build-linux-kernel)
6. [Step 3: Build OpenSBI Firmware](#6-step-3-build-opensbi-firmware)
7. [Step 4: Create Debian Root Filesystem](#7-step-4-create-debian-root-filesystem)
8. [Step 5: Setup SD Card](#8-step-5-setup-sd-card-wsl-focus)
9. [First Boot & Verification](#9-first-boot--verification)
10. [Post-Boot Tasks](#10-post-boot-tasks)
11. [Reference](#11-reference)
12. [Additional Resources](#12-additional-resources)

---

## 1. Prerequisites & System Requirements

### Hardware Requirements

- ✅ **Alinx AX7203 board** with FPGA bitstream flashed to QSPI flash
- ✅ **NaxRiscv CPU** (64-bit) configured at 100 MHz
- ✅ **512 MB DDR3 SDRAM** configured
- ✅ **Ethernet (RGMII)** and SD card support added
- ✅ **Serial console cable** (USB to UART)
- ✅ **64GB SD card** (minimum 8GB, FAT32 + ext4 partitions)

### Software Requirements

- ✅ **WSL2** with Ubuntu installed (or native Linux)
- ✅ **RISC-V toolchain** (will build in Step 1)
- ✅ **Build tools**: git, make, gcc, device-tree-compiler

### Verification

Check if your system is ready:

```bash
# Check WSL version
wsl --version

# Check required tools
which git make gcc dtc
# If dtc (device-tree-compiler) is missing:
sudo apt-get install device-tree-compiler

# Check disk space (need ~20GB for builds)
df -h ~
```

---

## 2. Understanding the Boot Process

### 2.1 Boot Flow Diagram

```
Power On
  ↓
FPGA loads bitstream from QSPI flash
  ↓
CPU resets, starts at 0x0 (ROM)
  ↓
LiteX BIOS runs from ROM
  ↓
BIOS initializes DDR3, timers, Ethernet, SD card
  ↓
BIOS loads boot.json files from SD card to RAM
  ↓
BIOS jumps to OpenSBI at 0x40F00000
  ↓
OpenSBI prints "Liftoff!" and initializes SBI
  ↓
OpenSBI jumps to Linux kernel at 0x40000000
  ↓
Linux kernel boots with SBI console support
  ↓
Kernel mounts root filesystem from SD card
  ↓
Init process starts, login prompt appears
```

### 2.2 Boot Components Explained

Understanding what each component does:

#### 1. **Linux Kernel** (`Image` or `vmlinux`)
- **What it is**: The actual Linux operating system kernel
- **Built in**: Step 2
- **Location after build**: `litex-linux/arch/riscv/boot/Image`
- **Size**: ~19MB
- **What it does**: Manages hardware, runs processes, provides system services

#### 2. **OpenSBI Firmware** (`opensbi.bin`)
- **What it is**: Second-stage bootloader and firmware
- **Built in**: Step 3
- **Location after build**: `opensbi/build/platform/litex/naxriscv/firmware/fw_jump.bin`
- **Size**: ~130KB (274KB for .elf)
- **What it does**: Runs before kernel, provides SBI interface, loads kernel

#### 3. **Device Tree** (`linux.dtb`)
- **What it is**: Hardware description file
- **Location**: `build/alinx_ax7203/linux.dtb` (from LiteX build)
- **Size**: ~3KB
- **What it does**: Tells kernel where hardware is (Ethernet address, UART, memory map, etc.)

#### 4. **Root Filesystem** (`debian-sid-risc-v-root.img`)
- **What it is**: The operating system filesystem (NOT the kernel!)
- **Built in**: Step 4
- **Size**: ~7GB (contains complete Debian system)
- **What it does**: Provides all programs, libraries, config files that run on top of the kernel
- **Contains**: Debian OS files, binaries, libraries, configuration files, user space programs

#### Relationship Analogy
- **Kernel** = Engine of a car
- **Root Filesystem** = Everything else (seats, steering wheel, radio, controls)
- **Device Tree** = Wiring diagram
- **OpenSBI** = Ignition system
- **You need ALL of them** for a working system!

### 2.3 Memory Map

Key memory addresses used during boot:

| Component | Load Address | Purpose |
|-----------|--------------|---------|
| OpenSBI | 0x40F00000 | Firmware (runs first) |
| Linux Kernel | 0x41000000 | Kernel image |
| Device Tree | 0x46000000 | Hardware description |
| DDR3 RAM | 0x40000000-0x5FFFFFFF | 512MB system memory |

---

## 3. Quick Start Guide (For Experienced Users)

If you're familiar with the process, here's the command-only version. For detailed explanations, see the full step-by-step sections.

```bash
# Step 1: Build Toolchain
git clone https://github.com/riscv-collab/riscv-gnu-toolchain.git --recursive
cd riscv-gnu-toolchain
./configure --prefix=$HOME/riscv
make -j4 linux
make install
cd ..

# Step 2: Build Kernel
git clone https://github.com/Dolu1990/litex-linux.git
cd litex-linux
git checkout ae80e67c6b48bbedcd13db753237a25b3dec8301
cp /home/riscv_dev/naxsoftware_config.txt .config
export CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-
make ARCH=riscv olddefconfig
scripts/config --enable CONFIG_MICREL_PHY
scripts/config --disable CONFIG_WERROR
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
unset CROSS_COMPILE
cd ..

# Step 3: Build OpenSBI (~5-10 minutes)
git clone https://github.com/Dolu1990/opensbi.git --branch litex-naxriscv
cd opensbi
make CROSS_COMPILE=riscv-none-embed- PLATFORM=litex/naxriscv
cd ..

# Step 4: Create RootFS (~30-60 minutes) - See Section 7 for full commands

# Step 5: Setup SD Card - See Section 8 for WSL-specific procedure

# Step 6: Boot and verify - See Section 9
```

**Note**: Steps 4 and 5 require interactive configuration and WSL-specific procedures. See detailed sections below.

---

## 4. Step 1: Build RISC-V Toolchain

### Goal
Build a local RISC-V cross-compilation toolchain for building the Linux kernel and other RISC-V software.

### Prerequisites
- WSL2/Ubuntu with build-essential installed
- ~10GB free disk space

### Commands

```bash
# Clone the RISC-V GNU toolchain repository
git clone https://github.com/riscv-collab/riscv-gnu-toolchain.git --recursive
cd riscv-gnu-toolchain

# Configure for local installation (no sudo needed)
./configure --prefix=$HOME/riscv

# Build Linux toolchain (use -j4 or adjust for your CPU cores)
make -j4 linux

# Install to $HOME/riscv
make install

cd ..
```

### Why Local Toolchain?

This setup uses a **local toolchain** installed in `$HOME/riscv` instead of system-wide installation in `/opt/`. Benefits:
- No sudo required for installation
- Multiple toolchain versions can coexist
- Easy to remove or rebuild
- Portable across WSL instances

### Verification

```bash
# Verify toolchain is installed
ls $HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc

# Test compiler
$HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc --version
# Should show: riscv64-unknown-linux-gnu-gcc (GCC) 13.x.x or similar

# Add to PATH (optional, for convenience)
echo 'export PATH=$HOME/riscv/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### Troubleshooting

If build fails, see [Troubleshooting Guide - Build Phase Issues](alinx_ax7203_troubleshooting.md#4-build-phase-issues).

---

## 5. Step 2: Build Linux Kernel

### Goal
Build the Linux kernel with **SBI console support** (critical for serial output) and **Ethernet drivers** (for networking).

### Prerequisites
- Toolchain from Step 1
- NaxSoftware kernel config file at `/home/riscv_dev/naxsoftware_config.txt`

### Commands

```bash
# Clone LiteX-compatible Linux kernel
git clone https://github.com/Dolu1990/litex-linux.git
cd litex-linux

# Checkout specific tested commit
git checkout ae80e67c6b48bbedcd13db753237a25b3dec8301

# Optional: Tweak MMC driver for better SD card performance
sed -i 's/SD_SLEEP_US       5/SD_SLEEP_US       0/g' drivers/mmc/host/litex_mmc.c

# Use the NaxSoftware config as base
cp /home/riscv_dev/naxsoftware_config.txt .config

# Set cross-compiler
export CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-

# Synchronize config with this kernel tree
make ARCH=riscv olddefconfig

# Enable Ethernet PHY driver for Alinx (but generic driver is used)
scripts/config --enable CONFIG_MICREL_PHY

# Disable warnings as errors (avoids build failures)
scripts/config --disable CONFIG_WERROR

# Build kernel (adjust -j4 for your CPU cores)
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all

# Unset CROSS_COMPILE when done
unset CROSS_COMPILE

cd ..
```

### Critical Configuration Requirements

The kernel **must** have these options enabled:

#### SBI Console Support (CRITICAL - enables serial output after OpenSBI)
```
CONFIG_SERIAL_EARLYCON_RISCV_SBI=y
CONFIG_RISCV_SBI_V01=y
CONFIG_RISCV_SBI=y
CONFIG_HVC_RISCV_SBI=y
```

**Why needed**: Without these, you'll see "Liftoff!" from OpenSBI, then complete silence. The kernel boots but has no console output.

#### Ethernet Support (Required for networking)
```
CONFIG_LITEETH=y          # LiteX Ethernet driver
CONFIG_MICREL_PHY=y       # PHY driver for KSZ9031RNX chip (CRITICAL!)
CONFIG_MDIO_BUS=y         # MDIO bus support
CONFIG_MDIO_DEVICE=y      # MDIO device support
CONFIG_MII=y              # MII interface support
CONFIG_PHYLIB=y           # PHY library
```

**Why CONFIG_MICREL_PHY is critical**: The Alinx AX7203 uses a **Micrel KSZ9031RNX PHY chip**. Without this driver:
- `networking.service` fails with "Cannot find device"
- Ethernet interface (eth0) won't appear
- Even though LiteX BIOS can access the network, Linux cannot

### Verification

```bash
# Check kernel images were created
ls -lh litex-linux/vmlinux                    # Should be ~15MB
ls -lh litex-linux/arch/riscv/boot/Image     # Should be ~19MB

# Verify critical kernel config options
cd litex-linux
grep CONFIG_SERIAL_EARLYCON_RISCV_SBI=y .config
grep CONFIG_MICREL_PHY=y .config
grep CONFIG_LITEETH=y .config
cd ..
```

### Troubleshooting

- **Build fails with "Error 2"**: See [Troubleshooting Guide - Kernel Build Issues](alinx_ax7203_troubleshooting.md#41-kernel-build-fails-with-error-2)
- **Missing dependencies**: Install `libncurses-dev`, `bison`, `flex`, `libssl-dev`, `libelf-dev`

---

## 6. Step 3: Build OpenSBI Firmware

### Goal
Build the OpenSBI firmware that acts as the second-stage bootloader and provides the SBI (Supervisor Binary Interface) to the kernel.

### Time Estimate
~5-10 minutes

### Prerequisites
- RISC-V toolchain (can use bare-metal or Linux toolchain)

### Commands

```bash
# Clone OpenSBI (LiteX NaxRiscv branch)
git clone https://github.com/Dolu1990/opensbi.git --branch litex-naxriscv
cd opensbi

# Build for LiteX NaxRiscv platform
# Note: This uses bare-metal toolchain (riscv-none-embed-)
# If you don't have it, use: CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-
make CROSS_COMPILE=riscv-none-embed- PLATFORM=litex/naxriscv

cd ..
```

### Toolchain Note

OpenSBI typically uses the **bare-metal toolchain** (`riscv-none-embed-`), which is different from the Linux toolchain. If you don't have it installed:

```bash
# Alternative: Use your local Linux toolchain
cd opensbi
make CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- PLATFORM=litex/naxriscv
cd ..
```

Both work fine for OpenSBI.

### Verification

```bash
# Check firmware files were created
ls -lh opensbi/build/platform/litex/naxriscv/firmware/fw_jump.bin
# Should be ~130KB

ls -lh opensbi/build/platform/litex/naxriscv/firmware/fw_jump.elf
# Should be ~274KB (with debug symbols)
```

### What is OpenSBI?

OpenSBI is a reference implementation of the RISC-V Supervisor Binary Interface (SBI). It:
- Runs **before** the kernel
- Provides a standardized interface between firmware and OS
- Handles early hardware initialization
- Provides console output services (critical for debugging)
- Loads and jumps to the Linux kernel

You'll see its "Liftoff!" message during boot - this confirms OpenSBI started successfully.

---

## 7. Step 4: Create Debian Root Filesystem

### Goal
Create a complete Debian root filesystem image containing the operating system environment that runs on top of the Linux kernel.

### Time Estimate
~30-60 minutes (depending on network speed)

### Prerequisites
- WSL2/Ubuntu with sudo access
- ~10GB free disk space
- Internet connection for downloading packages

---

### 4.1 Understanding the Root Filesystem

Before we start, let's clarify what we're building:

**What is the Root Filesystem (rootfs)?**
- The **operating system filesystem** (all the files that make up the OS)
- **NOT the kernel** (the kernel is separate, built in Step 2)
- Contains: Programs (bash, ls, apt, etc.), libraries, configuration files, user data
- Gets mounted as `/` (root directory) when Linux boots
- Size: ~7GB (complete Debian installation)

**Why 7GB?**
- Base Debian system: ~1.5GB
- Development tools (gcc, git, make): ~500MB
- Networking tools: ~100MB
- Utilities and extras: ~200MB
- Free space for your applications: ~4-5GB

**Understanding Loop Devices**

We'll use **loop devices** to work with the filesystem image. Key points:

- **What they are**: Special devices that let you mount regular files (like `.img`) as if they were disks
- **Why needed**: Allows treating `debian-sid-risc-v-root.img` as a mountable filesystem
- **Normal behavior**: Loop devices are **temporary** and disappear after:
  - System reboot
  - Manual detach (`losetup -d /dev/loopX`)
- **This is expected**: You'll need to re-run `losetup` each time you reboot (not a problem!)

**Check current loop devices:**
```bash
sudo losetup -a          # List all loop devices
lsblk                    # Show block devices (including loop devices)
```

---

### 4.2 Creating the Image File

```bash
# Set up environment variable for mount point
export MNT=$PWD/mnt

# Create 7GB image file (filled with zeros)
dd if=/dev/zero of=debian-sid-risc-v-root.img bs=1M count=7168

# Set up loop device
# --find: Automatically find available loop device
# --show: Display which device was assigned (e.g., /dev/loop0)
# --partscan: Scan for partitions (creates loop0p1, loop0p2, etc. if partitioned)
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Loop device assigned: $LOOP_DEV"

# Format as ext4 filesystem
sudo mkfs.ext4 $LOOP_DEV

# Set filesystem label
sudo e2label $LOOP_DEV rootfs

# Create mount point and mount
mkdir -p $MNT
sudo mount $LOOP_DEV $MNT
```

**What just happened:**
1. Created a 7GB empty file
2. Associated it with `/dev/loop0` (or similar)
3. Formatted it as ext4
4. Mounted it at `./mnt`

Now you can work with `./mnt` as if it's a real disk partition!

---

### 4.3 Bootstrap Debian Base System

```bash
# Install required tools
sudo apt-get install debootstrap qemu-user-static binfmt-support debian-archive-keyring

# Verify keyring file exists
ls -la /usr/share/keyrings/debian-archive-keyring.gpg

# Bootstrap Debian unstable (sid) for riscv64
# Note: As of July 2023, RISC-V is in main Debian archive (not ports)
# Use --foreign for first stage (cross-architecture)
sudo debootstrap --arch=riscv64 --foreign \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    unstable $MNT http://deb.debian.org/debian

# Copy QEMU emulator (required for second stage in chroot)
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/

# Complete second stage installation
sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    LC_ALL=C LANGUAGE=C LANG=C \
    chroot $MNT /debootstrap/debootstrap --second-stage
```

**Why two stages?**
- **Stage 1 (--foreign)**: Downloads and extracts packages (can run on any architecture)
- **Stage 2**: Configures packages (needs RISC-V emulation via QEMU)

**If "Invalid Release file" error occurs**, see [Troubleshooting Guide - Debootstrap Issues](alinx_ax7203_troubleshooting.md#51-debootstrap-invalid-release-file).

---

### 4.4 Configure Base System

Now we'll enter the chroot environment to configure the system:

```bash
# Enter chroot (you'll get a root shell inside the image)
sudo chroot $MNT /bin/bash
```

**You're now inside the root filesystem!** Your prompt should change. All commands below run **inside the chroot**.

#### Update Package Database

```bash
# Update package lists
apt-get update

# Fix any broken dependencies
apt-get --fix-broken install
```

#### Configure Networking

```bash
# Create network directory if it doesn't exist
mkdir -p /etc/network

# Configure network interfaces
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
```

#### Set Root Password

```bash
# Install passwd package if not already installed
apt-get install -y passwd

# Set root password (will prompt you to enter password)
passwd root
# Enter your desired password twice
```

**Verify root account:**
```bash
# Check root's entry in /etc/passwd
grep "^root:" /etc/passwd
# Should show: root:x:0:0:root:/root:/bin/bash

# Verify bash exists and is executable
test -x /bin/bash && echo "bash OK" || echo "bash missing!"
```

#### Configure Hostname and Filesystem

```bash
# Set hostname (change to your preference)
echo alinx_ax7203 > /etc/hostname

# Create fstab
cat > /etc/fstab <<EOF
# <file system>  <mount point>  <type>  <options>            <dump>  <pass>
/dev/mmcblk0p2   /              ext4    errors=remount-ro    0       1
/dev/mmcblk0p1   /boot          vfat    nodev,noexec,rw      0       2
EOF
```

#### **CRITICAL: Configure Console for RISC-V SBI (Prevents Login Loop!)**

This is **essential** for RISC-V systems with SBI console. Without this, you'll get a login loop!

**Why this is needed:**
- RISC-V with OpenSBI uses **hvc0** console device (not ttyS0)
- Systemd getty service needs to be configured for hvc0
- Without this, login sessions exit immediately

```bash
# Enable getty service for hvc0 (SBI console)
systemctl enable serial-getty@hvc0.service 2>/dev/null || \
  ln -sf /lib/systemd/system/serial-getty@.service \
         /etc/systemd/system/getty.target.wants/serial-getty@hvc0.service

# Create service override to ensure proper TTY configuration
mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/

cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/hvc0
StandardInput=tty
StandardOutput=tty
Restart=always
RestartSec=0
EOF

# Verify it was created
echo "=== Verification ==="
ls -la /etc/systemd/system/getty.target.wants/ | grep hvc0
test -f /etc/systemd/system/serial-getty@hvc0.service.d/override.conf && \
  echo "✅ Override file created" || echo "❌ Override file missing!"
```

**What is hvc0?**
- `hvc0` = **Hypervisor Console 0**
- Used by RISC-V SBI for console I/O
- Different from `ttyS0` (traditional serial port) or `ttyUSB0` (USB serial)

#### Install Networking Tools

```bash
# Install SSH server and networking tools
apt-get -y install openssh-server openntpd net-tools isc-dhcp-client

# Note: isc-dhcp-client is REQUIRED for automatic IP address (DHCP)

# Allow root login via SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
```

#### Install Utilities

```bash
# Install useful utilities
apt-get -y install sl hdparm htop wget psmisc tmux kbd usbutils

# Install build tools (if you plan to compile software on the board)
apt-get -y install gcc git libncursesw5-dev autotools-dev autoconf automake libtool build-essential
```

#### Optional: Install Desktop Environment

If you need graphical interface (adds ~2GB):

```bash
# Minimal X11 (just X server)
apt-get -y install xserver-xorg-core xinit xterm

# Or full desktop environment (XFCE - lightweight)
# apt-get -y install xorg xserver-xorg-core
# apt-get -y install xfce4 xfce4-goodies
```

**Skip this** if you only need command-line access.

#### Clean Up and Exit

```bash
# Clean package cache to save space
apt-get clean

# Exit chroot (back to host system)
exit
```

You're now back on your host system (WSL).

#### Unmount Filesystem

```bash
# Unmount the image
sudo umount $MNT
```

**Loop device note**: The loop device (`/dev/loop0`) stays attached even after unmount. This is normal. It will disappear after reboot or manual detach.

---

### 4.5 Making changes to Rootfs

If you need to make changes to the rootfs after creating it:

```bash
# Navigate to working directory
cd /home/riscv_dev

# Set mount point variable (REQUIRED!)
export MNT=$PWD/mnt

# Check if loop device already exists
sudo losetup -a
# If empty, no loop devices are set up (normal after reboot)

# Set up loop device (this is normal - do this each session after reboot)
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Using loop device: $LOOP_DEV"

# Mount filesystem
mkdir -p $MNT
sudo mount -t ext4 $LOOP_DEV $MNT

# Copy QEMU emulator if you need to chroot
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/

# Enter chroot to make changes
sudo chroot $MNT /bin/bash

# Make your changes inside chroot...
# (install packages, edit configs, etc.)

# Exit chroot when done
exit

# Unmount
sudo umount $MNT

# Optional: Detach loop device
sudo losetup -d $LOOP_DEV
```

**Important**: Don't redo the entire Step 4 just because the loop device disappeared! Just remount as shown above.

---

### 4.6 Verification Before SD Card

Before writing to SD card, verify your rootfs is correct:

```bash
# Remount if not already mounted (see 4.5 above)
cd /home/riscv_dev
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# 1. Check filesystem integrity
sudo fsck -n $LOOP_DEV
# Should show: clean, X files, Y blocks

# 2. Verify essential configuration files
echo "=== /etc/fstab ==="
cat $MNT/etc/fstab

echo -e "\n=== /etc/hostname ==="
cat $MNT/etc/hostname

echo -e "\n=== Root password set? ==="
grep "^root:" $MNT/etc/shadow | cut -d: -f2 | head -c 20 && echo " ✅ (hash present)"

# 3. Check disk usage
echo -e "\n=== Disk usage ==="
du -sh $MNT
echo "Largest directories:"
du -sh $MNT/* 2>/dev/null | sort -h | tail -5

# 4. Verify essential binaries exist
echo -e "\n=== Essential binaries ==="
for bin in sh bash ls cat mount umount; do
    test -f $MNT/bin/$bin && echo "✅ /bin/$bin" || echo "❌ MISSING: /bin/$bin"
done

# 5. Verify root's shell is configured correctly
echo -e "\n=== Root shell configuration ==="
grep "^root:" $MNT/etc/passwd
test -x $MNT/bin/bash && echo "✅ /bin/bash is executable" || echo "❌ bash missing!"

# 6. **CRITICAL** Verify TTY/console configuration for hvc0
echo -e "\n=== TTY/Console configuration (CRITICAL) ==="
if [ -L "$MNT/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service" ]; then
    echo "✅ serial-getty@hvc0.service is enabled"
else
    echo "❌ WARNING: serial-getty@hvc0.service NOT enabled - login may fail!"
fi

if [ -f "$MNT/etc/systemd/system/serial-getty@hvc0.service.d/override.conf" ]; then
    echo "✅ Service override file exists"
else
    echo "❌ WARNING: Service override missing - login may fail!"
fi

# If TTY configuration is missing, fix it now:
if [ ! -L "$MNT/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service" ]; then
    echo -e "\n⚠️  Applying TTY fix..."
    sudo chroot $MNT /bin/bash <<'CHROOT_EOF'
        systemctl enable serial-getty@hvc0.service 2>/dev/null || \
          ln -sf /lib/systemd/system/serial-getty@.service \
                 /etc/systemd/system/getty.target.wants/serial-getty@hvc0.service
        
        mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/
        cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/hvc0
StandardInput=tty
StandardOutput=tty
Restart=always
RestartSec=0
EOF
CHROOT_EOF
    echo "✅ TTY fix applied!"
fi

# 7. Test chroot works
echo -e "\n=== Chroot test ==="
sudo chroot $MNT /bin/bash -c 'echo "Chroot works" && uname -m'
# Should show: Chroot works, riscv64

echo -e "\n=== Verification Complete ==="
echo "If all checks passed, you're ready for Step 5 (SD Card setup)!"

# Unmount when done
sudo umount $MNT
```

**Checklist Summary:**
- ✅ Filesystem is clean (no errors)
- ✅ Essential config files exist (fstab, hostname, shadow)
- ✅ Root password is set
- ✅ Essential binaries present (bash, sh, ls, etc.)
- ✅ Root's shell is /bin/bash
- ✅ **hvc0 console configured** (prevents login loop!)
- ✅ Chroot works, architecture is riscv64

If any check fails, remount and fix before proceeding to Step 5!

---

## 8. Step 5: Setup SD Card (WSL Focus)

### Goal
Prepare a bootable SD card with boot partition (boot files) and root partition (Debian filesystem).

### Prerequisites
- 64GB SD card (minimum 8GB)
- Windows PC with WSL2
- SD card reader
- Built kernel, OpenSBI, DTB from Steps 1-3
- Root filesystem image from Step 4

---

### 5.1 SD Card Layout Overview

The SD card will have two partitions:

```
SD Card Layout:
┌─────────────────────────────────────────┐
│ Partition 1: BOOT (FAT32, 512MB)        │
│ - boot.json                             │
│ - Image (kernel)                        │
│ - linux.dtb (device tree)               │
│ - opensbi.bin (firmware)                │
│ - opensbi.elf (optional)                │
│ - vmlinux (optional)                    │
├─────────────────────────────────────────┤
│ Partition 2: ROOT (ext4, 7GB+)          │
│ - Debian root filesystem                │
│ - /bin, /etc, /usr, /var, etc.          │
│ - All OS files and programs             │
└─────────────────────────────────────────┘
```

**Why FAT32 for boot?**
- LiteX BIOS can read FAT32 filesystems
- Simple, universally compatible
- Easy to access from Windows

**Why ext4 for root?**
- Linux native filesystem
- Supports permissions, links, device files
- Required for proper Debian operation

---

### 5.2 Format SD Card in Windows

**Note for WSL users**: WSL has limited direct access to removable media. We'll use Windows to format, then WSL to copy files.

#### Method 1: Windows Disk Management (Recommended)

**Step-by-step:**

1. **Open Disk Management**
   - Press `Win + X` → Select "Disk Management"
   - Or run: `diskmgmt.msc`

2. **Identify your SD card**
   - Look for your 64GB removable disk
   - **⚠️ CRITICAL**: Verify it's the SD card, not your Windows drive!
   - Check size matches (~64GB) and type shows "Removable"

3. **Delete existing partitions**
   - Right-click each partition on the SD card
   - Select "Delete Volume..."
   - Confirm deletion
   - Repeat until card shows as "Unallocated"

4. **Create Boot Partition (Partition 1)**
   - Right-click "Unallocated" space
   - Select "New Simple Volume..."
   - Click Next
   - **Size**: Enter `512` (MB)
   - Click Next
   - **Drive letter**: Choose `E:` (or any available)
   - Click Next
   - **Format**:
     - File system: **FAT32**
     - Volume label: `boot`
     - Leave "Quick format" checked
   - Click Next → Finish

5. **Create Root Partition (Partition 2)**
   - Right-click remaining "Unallocated" space
   - Select "New Simple Volume..."
   - Click Next
   - **Size**: Leave default (uses all remaining space)
   - Click Next
   - **Drive letter**: Choose `F:` (different from boot)
   - Click Next
   - **Format**:
     - File system: **NTFS** or **exFAT** (temporary - we'll write ext4 image later)
     - Or select "Do not format" (recommended)
   - Click Next → Finish

**Verification:**
- Boot partition (E:) is FAT32, 512MB
- Root partition (F:) is unformatted or NTFS, ~59GB

#### Method 2: PowerShell (Alternative)

```powershell
# Open PowerShell as Administrator
# List disks to identify your SD card
Get-Disk

# ⚠️ IDENTIFY YOUR SD CARD DISK NUMBER (e.g., Disk 3)
$disk = 3  # ⚠️ CHANGE THIS TO YOUR SD CARD!

# Clear the disk
Clear-Disk -Number $disk -RemoveData -Confirm:$false

# Create boot partition (512MB, FAT32)
New-Partition -DiskNumber $disk -Size 512MB -DriveLetter E
Format-Volume -DriveLetter E -FileSystem FAT32 -NewFileSystemLabel "boot"

# Create root partition (remaining space)
New-Partition -DiskNumber $disk -UseMaximumSize -DriveLetter F
# Leave F: unformatted (we'll write ext4 image later)
```

---

### 5.3 Copy Boot Files from WSL

Now that the boot partition is formatted, copy boot files from WSL:

```bash
# Mount E: drive in WSL (boot partition)
sudo umount /mnt/e 2>/dev/null || true
sudo mkdir -p /mnt/e
sudo mount -t drvfs E: /mnt/e

export BOOT=/mnt/e

# Navigate to your working directory
cd /home/riscv_dev

# Copy kernel image
sudo cp litex-linux/arch/riscv/boot/Image $BOOT/

# Copy device tree
sudo cp build/alinx_ax7203/linux.dtb $BOOT/

# Copy OpenSBI firmware (rename to opensbi.bin)
sudo cp opensbi/build/platform/litex/naxriscv/firmware/fw_jump.bin $BOOT/opensbi.bin

# Optional: Copy ELF and vmlinux for debugging
sudo cp opensbi/build/platform/litex/naxriscv/firmware/fw_jump.elf $BOOT/opensbi.elf
sudo cp litex-linux/vmlinux $BOOT/

# **CRITICAL**: Create boot.json (tells BIOS where to load files)
cat > /tmp/boot.json <<'EOF'
{
	"Image":       "0x41000000",
	"linux.dtb":   "0x46000000",
	"opensbi.bin": "0x40f00000"
}
EOF
sudo cp /tmp/boot.json $BOOT/

# Verify boot.json was created
cat $BOOT/boot.json

# CRITICAL: Sync to ensure all data is written
sync

# Verify all files are present
echo "=== Boot Partition Contents ==="
ls -lh $BOOT/
# Should show: boot.json, Image, linux.dtb, opensbi.bin, opensbi.elf, vmlinux
```

**What is boot.json?**

This file tells the LiteX BIOS:
- Which files to load from SD card
- Where in RAM to load each file
- Load addresses must match what OpenSBI and kernel expect

```json
{
	"Image":       "0x41000000",  // Kernel at 1GB + 16MB
	"linux.dtb":   "0x46000000",  // Device tree at 1GB + 96MB
	"opensbi.bin": "0x40f00000"   // OpenSBI at 1GB + 15MB
}
```

**File checklist:**
- ✅ `boot.json` - Boot configuration (REQUIRED!)
- ✅ `Image` - Linux kernel (~19MB)
- ✅ `linux.dtb` - Device tree (~3KB)
- ✅ `opensbi.bin` - Firmware (~130KB)
- ✅ `opensbi.elf` - Optional (~274KB, for debugging)
- ✅ `vmlinux` - Optional (~15MB, for debugging)

---

### 5.4 Write Root Filesystem to Partition 2

**Why use dd for Windows:**
WSL typically cannot directly access removable media devices, so we use a Windows tool to write the ext4 image.

#### Step 1: Download dd for Windows

- Download from: https://www.chrysocome.net/dd
- Get: `dd-0.6beta3.zip`
- Extract `dd.exe` to `C:\tools\` or `C:\Windows\System32\`

#### Step 2: Identify Target Partition

```powershell
# Open PowerShell as Administrator
# List partitions to verify your SD card layout
Get-Partition | Format-Table DriveLetter, Size, Type, PartitionNumber

# You should see:
# E: - 512 MB (FAT32) = Boot partition
# F: - ~59 GB = Root partition (this is where we write)
```

#### Step 3: ⚠️ CRITICAL SAFETY CHECKS

**Before running dd, verify these:**

```powershell
# 1. Verify partition layout
Get-Partition -DriveLetter F | Format-List
# Confirm it's your SD card root partition (~59GB)

# 2. Verify rootfs image exists
Test-Path "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img"
# Should return: True

# 3. Check image size (~7GB)
(Get-Item "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img").Length / 1GB
# Should show ~7GB

# 4. Get Volume GUID for F: drive
$volumeId = (Get-Volume -DriveLetter F).UniqueId
Write-Host "Volume GUID: $volumeId"
# Example: \\?\Volume{f26c848a-b7e8-11f0-a777-e0d4e89fa73a}\
```

**⚠️ SAFETY CHECKLIST - VERIFY ALL BEFORE PROCEEDING:**

- ✅ Drive letter F: is your SD card root partition (~59GB)
- ✅ Drive letter E: is your boot partition (~512MB) - **DO NOT WRITE HERE!**
- ✅ Volume GUID is for F: drive (verify with `Get-Volume`)
- ✅ Image file path is correct and file exists
- ✅ Image file size is ~7GB

**If ANYTHING doesn't match, STOP and verify your setup!**

#### Step 4: Write Root Filesystem Image

```powershell
# Navigate to dd.exe location
cd C:\tools\dd-0.6beta3  # or wherever you extracted dd.exe

# Get Volume GUID for F: drive (rootfs partition)
$volumeId = (Get-Volume -DriveLetter F).UniqueId
# Convert format: \\?\Volume{...}\ → \\.\Volume{...} (no trailing \)
$volumeGuid = $volumeId -replace '\\\\\?\\', '\\.\' -replace '\\$', ''
Write-Host "Writing to: $volumeGuid"

# Write image (use quotes to prevent PowerShell from parsing = as parameter)
.\dd.exe if="\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" of="$volumeGuid" bs=1M

# This will take 5-15 minutes for 7GB image
# You'll see progress: records in/out, bytes transferred
# Wait for "X+0 records in, X+0 records out" completion message
```

**Alternative if WSL path doesn't work:**

```powershell
# Copy image to Windows first
Copy-Item "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" -Destination "C:\temp\rootfs.img"

# Then write from Windows path
.\dd.exe if="C:\temp\rootfs.img" of="$volumeGuid" bs=1M
```

**Manual method (if variable doesn't work):**

```powershell
# Get the GUID manually:
(Get-Volume -DriveLetter F).UniqueId
# Example output: \\?\Volume{f26c848a-b7e8-11f0-a777-e0d4e89fa73a}\

# Use it directly (change \\?\ to \\.\ and remove trailing \):
.\dd.exe if="\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" of="\\.\Volume{f26c848a-b7e8-11f0-a777-e0d4e89fa73a}" bs=1M
```

#### Step 5: Verify Write Completed

```powershell
# Check partition properties
Get-Partition -DriveLetter F | Format-List

# The partition now contains ext4 filesystem
# Windows will show F: as unreadable - this is NORMAL (Windows can't read ext4)
```

**Note**: After writing, Windows may show "You need to format the disk" for F: - **DO NOT FORMAT!** This is normal because Windows cannot read ext4 filesystems.

---

### 5.5 Final Pre-Boot Checklist

Before ejecting SD card and booting:

```bash
# In WSL: Verify boot partition files
ls -lh /mnt/e/
# Should show: boot.json, Image, linux.dtb, opensbi.bin, opensbi.elf, vmlinux
```

**Checklist:**
- ✅ Boot partition (E:) has all required files
- ✅ boot.json exists and has correct addresses
- ✅ Root partition (F:) has rootfs image written (shows as unreadable in Windows - normal!)
- ✅ All files synced (`sync` command ran)
- ✅ No error messages during dd write

**Before ejecting:**
```bash
# In WSL: Unmount boot partition cleanly
sudo umount /mnt/e
```

```powershell
# In Windows: Safely eject SD card
# Right-click SD card in Explorer → Eject
```

**You're ready to boot!** Proceed to Section 9.

---

## 9. First Boot & Verification

### 9.1 Connect Serial Console

Connect to the serial console to see boot messages:

#### On WSL/Linux:

```bash
# Using screen
screen /dev/ttyUSB0 115200

# Or using minicom
minicom -D /dev/ttyUSB0 -b 115200

# To exit screen: Ctrl+A, then K, then Y
```

#### On Windows:

Use **PuTTY** or similar terminal emulator:
- Connection type: Serial
- Port: COM3 (or your port - check Device Manager)
- Speed: 115200
- Data bits: 8
- Stop bits: 1
- Parity: None
- Flow control: None

---

### 9.2 Power On and Expected Boot Sequence

Insert the SD card into the board and power on (or reset). You should see:

#### Phase 1: LiteX BIOS Initialization

```
        __   _ __      _  __
       / /  (_) /____ | |/_/
      / /__/ / __/ -_)>  <
     /____/_/\__/\__/_/|_|
   Build your hardware, easily!

--=============== SoC ==================--
CPU:		NaxRiscv 64-bit @ 100MHz
BUS:		WISHBONE 32-bit @ 4GiB
CSR:		32-bit data
ROM:		128KiB
SRAM:		8KiB
SDRAM:		512MiB 16-bit @ 400MT/s (CL-6 CWL-5)

--========== Initialization ============--
Initializing SDRAM @0x40000000...
SDRAM: 512 MBytes @ 0x40000000
```

#### Phase 2: BIOS Loads Boot Files

```
--============== Boot ==================--
Booting from SD card...

Reading boot.json from SD card...
Loading Image to 0x41000000 (20971520 bytes)...
Loading linux.dtb to 0x46000000 (3076 bytes)...
Loading opensbi.bin to 0x40f00000 (274016 bytes)...

Executing booted program at 0x40f00000
```

**✅ Success indicator**: Files loading with byte counts

**If "boot.json not found"**: See [Troubleshooting - boot.json Issues](alinx_ax7203_troubleshooting.md#62-bootjson-file-not-found-at-boot)

#### Phase 3: OpenSBI Initialization

```
--============= Liftoff! ===============--

OpenSBI v1.3.1
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : LiteX/VexRiscv-SMP
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 100000000Hz
Platform Console Device   : litex-uart
```

**✅ Success indicator**: "Liftoff!" message and OpenSBI banner

**If hangs after "Liftoff!"**: See [Troubleshooting - Hangs After Liftoff](alinx_ax7203_troubleshooting.md#72-hangs-after-liftoff-no-opensbi-banner)

#### Phase 4: Linux Kernel Boot

```
Boot HART ID              : 0
Boot HART Domain          : root
Boot HART Priv Version    : v1.11
Boot HART Base ISA        : rv64imafdcsu
Boot HART ISA Extensions  : time
Boot HART PMP Count       : 0
Boot HART PMP Granularity : 0
Boot HART PMP Address Bits: 0
Boot HART MHPM Count      : 0
Firmware Base             : 0x40f00000
Firmware Size             : 264 KB
Runtime SBI Version       : 1.0

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000040f00000-0x0000000040f3ffff (I)
Domain0 Region01          : 0x0000000000000000-0xffffffffffffffff (R,W,X)
Domain0 Next Address      : 0x0000000041000000
Domain0 Next Arg1         : 0x0000000046000000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes

[    0.000000] Linux version 6.1.0 (riscv64-linux-gnu-gcc) ...
[    0.000000] Machine model: litex,vexriscv
[    0.000000] OF: fdt: Ignoring memory range 0x40000000 - 0x40f00000
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000040f00000-0x000000005fffffff]
[    0.000000]   Normal   empty
[    0.000000] printk: bootconsole [ns16550a0] enabled
[    0.000000] Initmem setup node 0 [mem 0x0000000040f00000-0x000000005fffffff]
[    0.000000] SBI specification v1.0 detected
[    0.000000] SBI implementation ID=0x1 Version=0x10001
[    0.000000] SBI TIME extension detected
[    0.000000] SBI IPI extension detected
[    0.000000] SBI RFENCE extension detected
[    0.000000] riscv: ISA extensions acdfim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 129920
[    0.000000] Kernel command line: earlycon=sbi console=hvc0 root=/dev/mmcblk0p2 rootwait
```

**✅ Success indicators**:
- "Linux version 6.1.0..."
- "bootconsole [ns16550a0] enabled" or "earlycon=sbi"
- Kernel command line shows correct parameters

**If silent after "Liftoff!"**: See [Troubleshooting - No Kernel Output](alinx_ax7203_troubleshooting.md#73-complete-silence-after-liftoff)

#### Phase 5: Hardware Detection & Driver Initialization

```
[    0.180000] litex-uart f0001000.serial: IRQ index 0 not found
[    0.190000] printk: console [litex-uart0] enabled
[    0.200000] printk: bootconsole [ns16550a0] disabled
...
[    1.234000] liteeth f0024000.mac eth0: irq 1 slots: tx 2 rx 2 size 2048
[    2.345000] litex-mmc f0004000.mmc: Requested clk_freq=12500000: set to 12500000 via div=4
[    2.356000] mmc0: new SD card at address 0001
[    2.367000] mmcblk0: mmc0:0001 SD64G 58.2 GiB
[    2.378000]  mmcblk0: p1 p2
```

**✅ Success indicators**:
- Ethernet (liteeth) detected
- MMC/SD card detected (mmcblk0)
- Partitions found (p1, p2)

**If MMC driver panic**: See [Troubleshooting - MMC Driver Panic](alinx_ax7203_troubleshooting.md#74-mmcsd-card-driver-panic)

#### Phase 6: Root Filesystem Mount & Init

```
[    3.456000] EXT4-fs (mmcblk0p2): mounted filesystem with ordered data mode. Opts: (null)
[    3.467000] VFS: Mounted root (ext4 filesystem) readonly on device 179:2.
[    3.478000] devtmpfs: mounted
[    3.489000] Freeing unused kernel memory: 2048K
[    3.500000] Run /sbin/init as init process
...
[  OK  ] Reached target Basic System.
[  OK  ] Started D-Bus System Message Bus.
[  OK  ] Started OpenNTPD Network Time Synchronization.
[  OK  ] Reached target System Initialization.
...
Debian GNU/Linux bookworm/sid alinx_ax7203 hvc0

alinx_ax7203 login: _
```

**✅ Success indicators**:
- "Mounted root (ext4 filesystem)"
- Systemd services starting
- Login prompt appears

#### Phase 7: Login

```
alinx_ax7203 login: root
Password: [enter your password]

Linux alinx_ax7203 6.1.0 #1 SMP ... riscv64

root@alinx_ax7203:~# _
```

**✅ Success!** You now have a working Linux system on your FPGA!

**If login loop occurs**: See [Troubleshooting - Login Loop](alinx_ax7203_troubleshooting.md#81-repeated-login-prompts-login-loop)

---

### 9.3 Quick Diagnostics After Boot

Once logged in, verify hardware:

```bash
# Check system info
uname -a
# Should show: Linux alinx_ax7203 6.1.0 ... riscv64 GNU/Linux

# Check CPU
cat /proc/cpuinfo
# Should show: NaxRiscv processor

# Check memory
free -h
# Should show ~512MB total

# Check storage
lsblk
# Should show:
# mmcblk0     [SD card]
#  ├─mmcblk0p1  [boot partition]
#  └─mmcblk0p2  [root partition, mounted on /]

# Check network interface
ip link show
# Should show: eth0 (may be DOWN if not connected)

# Check Ethernet driver
dmesg | grep -i liteeth
# Should show: liteeth f0024000.mac eth0: ...

# Check if networking is configured
ip addr show eth0
# If no IP address, see Section 10.2
```

---

## 10. Post-Boot Tasks

### 10.1 Verify Hardware

#### Check Ethernet

```bash
# Bring interface up
ip link set eth0 up

# Check if carrier detected (cable plugged in)
ip link show eth0
# Should show: state UP (if cable connected)

# Request IP address via DHCP
dhclient eth0

# Verify IP assigned
ip addr show eth0
# Should show: inet X.X.X.X/24 ...

# Test connectivity
ping -c 3 8.8.8.8
```

**If networking fails**: See [Troubleshooting - Networking Issues](alinx_ax7203_troubleshooting.md#82-networkingservice-failed--cannot-find-device)

#### Check SD Card

```bash
# Verify both partitions mounted/accessible
lsblk
# mmcblk0p1 should be mountable at /boot
# mmcblk0p2 should be mounted at /

# Check disk usage
df -h
# Should show rootfs usage (~1.5-2GB used)

# Test write access
touch /tmp/test.txt
echo "SD card write test" > /tmp/test.txt
cat /tmp/test.txt
rm /tmp/test.txt
```

---

### 10.2 System Configuration

#### Update Package Database

```bash
# Update package lists
apt-get update

# Upgrade installed packages (optional)
apt-get upgrade -y
```

#### Configure Time Zone

```bash
# Set timezone
dpkg-reconfigure tzdata
# Follow prompts to select your region/city
```

#### Configure Networking (If Not Working)

```bash
# Edit network interfaces
nano /etc/network/interfaces

# Ensure it has:
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

# Restart networking
systemctl restart networking

# Or manually request DHCP
dhclient eth0
```

---

### 10.3 Next Steps

Now that you have a working Linux system:

1. **Install your applications**
   ```bash
   apt-get install [your-packages]
   ```

2. **Deploy your software**
   ```bash
   git clone [your-repo]
   cd [your-repo]
   make && make install
   ```

3. **Optimize performance**
   - Adjust CPU clock speeds (if needed)
   - Tune SD card performance
   - Configure swap (if needed)

4. **Enable SSH access**
   ```bash
   # SSH should already be running
   systemctl status sshd
   
   # Find your IP address
   ip addr show eth0
   
   # Connect from another machine:
   # ssh root@[board-ip-address]
   ```

5. **Document your setup**
   - Record any changes made
   - Note hardware configuration
   - Document application-specific settings

---

## 11. Reference

### 11.1 Quick Command Reference

#### Kernel Configuration Check

```bash
cd litex-linux
grep CONFIG_SERIAL_EARLYCON_RISCV_SBI=y .config
grep CONFIG_RISCV_SBI_V01=y .config
grep CONFIG_MICREL_PHY=y .config
grep CONFIG_LITEETH=y .config
```

#### Device Tree Operations

```bash
# Compile DTS to DTB
dtc -I dts -O dtb -o linux.dtb linux.dts

# Decompile DTB to DTS (for inspection)
dtc -I dtb -O dts -o linux.dts linux.dtb

# Check bootargs in DTB
dtc -I dtb -O dts linux.dtb | grep bootargs
```

#### Loop Device Operations

```bash
# List all loop devices
sudo losetup -a

# Set up loop device
sudo losetup --partscan --find --show image.img

# Detach loop device
sudo losetup -d /dev/loop0

# Detach all loop devices
sudo losetup -D
```

#### File Verification

```bash
# Check file sizes
ls -lh Image opensbi.bin linux.dtb vmlinux

# Verify boot files on SD card
ls -lh /mnt/e/

# Check rootfs integrity
sudo fsck -n /dev/loop0
```

---

### 11.2 File Locations & Sizes

| File | Location | Size | Purpose |
|------|----------|------|---------|
| `Image` | `litex-linux/arch/riscv/boot/Image` | ~19MB | Linux kernel binary |
| `vmlinux` | `litex-linux/vmlinux` | ~15MB | Kernel with debug symbols |
| `opensbi.bin` | `opensbi/build/.../fw_jump.bin` | ~130KB | OpenSBI firmware |
| `opensbi.elf` | `opensbi/build/.../fw_jump.elf` | ~274KB | OpenSBI with debug symbols |
| `linux.dtb` | `build/alinx_ax7203/linux.dtb` | ~3KB | Device tree blob |
| `linux.dts` | `build/alinx_ax7203/linux.dts` | ~10KB | Device tree source |
| `boot.json` | Created manually | <1KB | Boot configuration |
| `rootfs.img` | `debian-sid-risc-v-root.img` | 7GB | Root filesystem image |

---

### 11.3 Memory Map

#### Boot-Time Addresses

These addresses are configured in `boot.json`:

| Component | Address | Size | Notes |
|-----------|---------|------|-------|
| OpenSBI | 0x40F00000 | 264KB | Firmware runs first |
| Linux Kernel | 0x41000000 | ~19MB | Loaded by OpenSBI |
| Device Tree | 0x46000000 | ~3KB | Passed to kernel |

#### System Memory

| Region | Address Range | Size | Purpose |
|--------|---------------|------|---------|
| DDR3 RAM | 0x40000000 - 0x5FFFFFFF | 512MB | System memory |
| BIOS ROM | 0x00000000 - 0x0001FFFF | 128KB | LiteX BIOS |
| SRAM | (varies) | 8KB | Scratch RAM |

#### Peripheral Addresses

Check your `build/alinx_ax7203/csr.csv` for actual addresses. Common ones:

| Peripheral | Typical Address | Notes |
|------------|----------------|-------|
| UART | 0xF0001000 | Serial console |
| Ethernet (LiteETH) | 0xF0024000 | Network MAC |
| SD Card (MMC) | 0xF0004000 | SD card controller |
| Timer | 0xF0002000 | System timer |

---

### 11.4 Important Paths

#### On Build System (WSL/Linux)

```
$HOME/riscv/                    - RISC-V toolchain
/home/riscv_dev/                - Working directory
  ├── riscv-gnu-toolchain/      - Toolchain source
  ├── litex-linux/              - Kernel source
  ├── opensbi/                  - OpenSBI source
  ├── build/alinx_ax7203/       - LiteX build outputs
  ├── debian-sid-risc-v-root.img - Root filesystem image
  └── mnt/                      - Mount point for loop device
```

#### On SD Card

```
/dev/mmcblk0                    - SD card device
  ├── /dev/mmcblk0p1            - Boot partition (FAT32)
  │   ├── boot.json
  │   ├── Image
  │   ├── linux.dtb
  │   ├── opensbi.bin
  │   ├── opensbi.elf
  │   └── vmlinux
  └── /dev/mmcblk0p2            - Root partition (ext4)
      └── / (entire Debian rootfs)
```

#### On Running System (FPGA Board)

```
/                               - Root filesystem (mmcblk0p2)
/boot                           - Boot partition (mmcblk0p1) - mount manually
/dev/hvc0                       - SBI console device
/dev/eth0                       - Ethernet interface
```

---

### 11.5 Boot Process Summary Table

| Stage | Component | Location | What Happens |
|-------|-----------|----------|--------------|
| 1 | FPGA Bitstream | QSPI Flash | FPGA loads configuration |
| 2 | LiteX BIOS | ROM (0x0) | Initializes DDR, peripherals |
| 3 | Boot Files | SD Card FAT32 | BIOS reads boot.json, loads files |
| 4 | OpenSBI | RAM (0x40F00000) | Firmware initializes SBI |
| 5 | Linux Kernel | RAM (0x41000000) | Kernel boots with DT at 0x46000000 |
| 6 | Root FS | SD Card ext4 | Kernel mounts /dev/mmcblk0p2 as / |
| 7 | Init System | /sbin/init | Systemd starts services |
| 8 | Login | /dev/hvc0 | Getty provides login prompt |

---

## 12. Additional Resources

### Official Documentation

- **LiteX**: https://github.com/enjoy-digital/litex
- **NaxRiscv**: https://github.com/SpinalHDL/NaxRiscv
- **OpenSBI**: https://github.com/riscv-software-src/opensbi
- **RISC-V GNU Toolchain**: https://github.com/riscv-collab/riscv-gnu-toolchain

### Related Guides

- **LiteX Linux Guide**: https://github.com/litex-hub/linux-on-litex-vexriscv
- **RISC-V SBI Specification**: https://github.com/riscv-non-isa/riscv-sbi-doc
- **Device Tree Specification**: https://www.devicetree.org/

### Community & Support

- **LiteX Discord**: https://discord.gg/litex
- **RISC-V Mailing Lists**: https://lists.riscv.org/
- **Alinx Forums**: https://www.alinx.com/

### Troubleshooting

For detailed troubleshooting information, see the companion guide:
- [Alinx AX7203 Troubleshooting Guide](alinx_ax7203_troubleshooting.md)

---

## Acknowledgments

This guide combines knowledge from:
- LiteX project documentation
- NaxRiscv README and examples
- Community contributions and forum discussions
- Real-world testing on Alinx AX7203 hardware

---

**Last Updated**: 2025-11-09

**Guide Version**: 2.0 (Restructured)

**Tested With**:
- Alinx AX7203 board
- NaxRiscv 64-bit @ 100MHz
- LiteX 2024.xx
- OpenSBI v1.3.1
- Linux 6.1.0
- Debian Unstable (sid) riscv64

---

Good luck with your build! 🚀

If you encounter issues, check the [Troubleshooting Guide](alinx_ax7203_troubleshooting.md) for solutions.

