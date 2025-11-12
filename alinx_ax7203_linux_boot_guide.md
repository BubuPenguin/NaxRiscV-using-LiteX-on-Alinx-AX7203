# Booting Linux on Alinx AX7203 with NaxRiscv + OpenSBI

This guide documents the hybrid boot process using **OpenSBI** as the second-stage bootloader on your Alinx AX7203 board.

## Prerequisites

- ✅ FPGA bitstream built and flashed to QSPI flash
- ✅ NaxRiscv CPU (64-bit) configured at 100 MHz
- ✅ Ethernet (RGMII) and SD card support added
- ✅ 512 MB DDR3 SDRAM configured
- ✅ LiteX BIOS built and ready
- ✅ WSL2 with Ubuntu installed
- ✅ RISC-V toolchain installed (`riscv64-linux-gnu-*`)

## Boot Process Overview

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

## Step-by-Step Following README_NaxSoftware.md

### Step 1: Build Linux Toolchain (Lines 106-113)

**Note:** This setup uses a local toolchain installed in `$HOME/riscv` (not `/opt/riscv_rv64gc_linux`).

```bash
git clone https://github.com/riscv-collab/riscv-gnu-toolchain.git --recursive
cd riscv-gnu-toolchain
./configure --prefix=$HOME/riscv
make -j4 linux
make install  # No sudo needed for $HOME installation
cd ..
```

### Step 2: Build Linux Kernel (Lines 117-134)

**Note:** This setup uses a local RISC-V toolchain built with `./configure --prefix=$HOME/riscv`. All kernel build commands use `CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-`.

```bash
git clone https://github.com/Dolu1990/litex-linux.git
cd litex-linux
git checkout ae80e67c6b48bbedcd13db753237a25b3dec8301

# Optional MMC tweak
sed -i 's/SD_SLEEP_US       5/SD_SLEEP_US       0/g' drivers/mmc/host/litex_mmc.c

# Use the NaxSoftware config as-is
cp /home/riscv_dev/naxsoftware_config.txt .config

export CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-
make ARCH=riscv olddefconfig      # sync symbols with this tree
scripts/config --enable CONFIG_MICREL_PHY
scripts/config --disable CONFIG_WERROR

make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all   
# builds vmlinux + Image

ls vmlinux
ls arch/riscv/boot/Image

cd ..
unset CROSS_COMPILE
```

**Config requirements (lines 138-142):**
- CONFIG_SIFIVE_PLIC
- CONFIG_RISCV_SBI_V01
- CONFIG_RISCV_SBI
- CONFIG_HVC_RISCV_SBI

**Ethernet Configuration (for networking.service):**
- CONFIG_LITEETH=y (LiteX Ethernet driver - should be enabled by defconfig)
- CONFIG_MICREL_PHY=y (Required for KSZ9031RNX PHY chip)
- CONFIG_MDIO_BUS=y (MDIO bus support for PHY communication)
- CONFIG_MDIO_DEVICE=y (MDIO device support)
- CONFIG_MII=y (MII interface support)
- CONFIG_PHYLIB=y (PHY library - should be enabled by defconfig)

**Note:** Without CONFIG_MICREL_PHY, the Ethernet interface will not be detected, causing `networking.service` to fail with "Cannot find device" error.

### Step 3: Build OpenSBI (Lines 146-155)

**Note:** OpenSBI uses `riscv-none-embed-` toolchain (different from the Linux toolchain). If you need to use the local RISC-V toolchain, use `CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-`.

```bash
git clone https://github.com/Dolu1990/opensbi.git --branch litex-naxriscv
cd opensbi
make CROSS_COMPILE=riscv-none-embed- PLATFORM=litex/naxriscv

ls build/platform/litex/naxriscv/firmware/fw_jump.bin 
ls build/platform/litex/naxriscv/firmware/fw_jump.elf

cd ..
```

### Step 4: Create Debian RootFS (Lines 12-98)

**What is `debian-sid-risc-v-root.img`?**
- This is the **root filesystem image** (the operating system filesystem), NOT the kernel
- Contains: Debian operating system files, binaries, libraries, configuration files, user space programs
- The kernel boots and then mounts this as the root filesystem (`/`)
- Size: ~7GB (7,168 MB) - contains complete Debian system

**Boot Components Overview:**
1. **Kernel** (`Image` or `vmlinux`) - Built in Step 2, the actual Linux kernel
   - Location after build: `litex-linux/arch/riscv/boot/Image`
   - What it does: Manages hardware, runs processes, provides system services
2. **OpenSBI** (`opensbi.bin`) - Built in Step 3, firmware that boots the kernel
   - Location after build: `opensbi/build/platform/litex/naxriscv/firmware/fw_jump.bin`
   - What it does: Runs before kernel, provides SBI interface, loads kernel
3. **Device Tree** (`linux.dtb`) - Hardware description (from LiteX build)
   - Location: `build/alinx_ax7203/linux.dtb`
   - What it does: Tells kernel where hardware is (Ethernet address, UART, etc.)
4. **Root Filesystem** (`debian-sid-risc-v-root.img`) - The OS filesystem you're creating here
   - Contains: All the programs, libraries, config files that run on top of the kernel
   - What it does: Provides the actual OS environment (bash, systemd, programs, etc.)

**Relationship:**
```
Boot Process:
FPGA → LiteX BIOS → OpenSBI → Linux Kernel → Mounts RootFS → System Ready
                    (Step 3)    (Step 2)      (Step 4)
```

**Analogy:**
- **Kernel** = Engine of a car
- **Root Filesystem** = Everything else (seats, steering wheel, radio, etc.)
- You need BOTH to have a working system!

```bash
export MNT=$PWD/mnt

# create image file
dd if=/dev/zero of=debian-sid-risc-v-root.img bs=1M count=7168
       
# Mount image in loop device
# Loop devices (/dev/loop0, /dev/loop1, etc.) allow you to mount files as if they were block devices
# This lets you treat an image file (like debian-sid-risc-v-root.img) as a disk
# 
# --find: Find the first available loop device automatically
# --show: Display which loop device was assigned (e.g., /dev/loop0)
# --partscan: Scan for partitions automatically (creates /dev/loop0p1, /dev/loop0p2, etc.)
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Loop device assigned: $LOOP_DEV"  # Will show something like /dev/loop0

# format partitions
# Note: After losetup with --partscan, partitions appear as loop0p1, loop0p2, etc.
# But since this is a single partition image, we format the loop device directly
sudo mkfs.ext4 $LOOP_DEV
sudo e2label $LOOP_DEV rootfs

# mount root partition
mkdir -p $MNT
# Use the loop device we captured earlier
sudo mount $LOOP_DEV $MNT

# install base files
# Note: RISC-V 64-bit became an official Debian architecture in July 2023,
# so we use the main Debian archive, not Debian Ports
sudo apt-get install debootstrap qemu-user-static binfmt-support debian-archive-keyring

# Verify keyring file exists
ls -la /usr/share/keyrings/debian-archive-keyring.gpg

# Bootstrap Debian unstable (sid) for riscv64 using main Debian archive
# Use foreign stage first (recommended for cross-arch)
sudo debootstrap --arch=riscv64 --foreign --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    unstable $MNT http://deb.debian.org/debian

# Copy QEMU emulator (required for cross-architecture chroot)
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/

# Complete the second stage installation
sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    LC_ALL=C LANGUAGE=C LANG=C chroot $MNT /debootstrap/debootstrap --second-stage

# Alternative: If unstable doesn't work, try sid (same as unstable) or bookworm (stable):
# sudo debootstrap --arch=riscv64 --foreign sid $MNT http://deb.debian.org/debian
# sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/
# sudo DEBIAN_FRONTEND=noninteractive chroot $MNT /debootstrap/debootstrap --second-stage

# chroot into base filesystem and made basic configuration
# Note: Set environment variables to avoid "Cannot determine your user name" errors
sudo chroot $MNT /bin/bash

# Update package information
apt-get update
apt-get --fix-broken install

# Set up basic networking
# Create network directory if it doesn't exist (newer Debian versions may not have it)
mkdir -p /etc/network
cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Fix "I have no name!" issue and set root password
# First, install passwd if not already installed
apt-get install -y passwd

# Set root password (use one of these methods)
# Method 1: Interactive (will prompt for password) - Recommended
passwd root

# Method 2: Non-interactive (if Method 1 fails, manually edit /etc/shadow)
# The chpasswd method may fail due to PAM configuration. If needed:
# perl -e 'print crypt("root", "salt"), "\n"'  # Generate hash manually if needed
# Or use: echo 'root:$6$salt...' | chpasswd -e  # Requires hash generation

# IMPORTANT: Verify root's shell is set correctly
grep "^root:" /etc/passwd
# Should show: root:x:0:0:root:/root:/bin/bash
# If shell is wrong or missing (/bin/false, /bin/sh missing, etc.), fix it:
chsh -s /bin/bash root
# Or manually edit /etc/passwd if needed

# Verify bash exists and is executable
test -x /bin/bash && echo "bash OK" || echo "bash missing!"

# Change hostname (change to your board name)
echo alinx_ax7203 > /etc/hostname

# Set up fstab
cat > /etc/fstab <<EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>

/dev/mmcblk0p2 /               ext4    errors=remount-ro 0       1
/dev/mmcblk0p1 /boot           vfat    nodev,noexec,rw   0       2
EOF

# Install networking stuff
# Note: ntpdate may not be available in newer Debian - use ntpsec-ntpdate or skip it
apt-get -y install openssh-server openntpd net-tools isc-dhcp-client
# If ntpdate is needed, use: apt-get -y install ntpsec-ntpdate
# isc-dhcp-client is required for DHCP networking (automatically getting IP address)
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

# Install utilities
apt-get -y install sl hdparm htop wget psmisc tmux kbd usbutils

# Install build tools
apt-get -y install gcc git libncursesw5-dev autotools-dev autoconf automake libtool build-essential

# Optional: Install X11 and desktop environment (if graphical interface is needed)
# This adds significant size but enables GUI applications
# Uncomment the following lines if you need X11 support:
# apt-get -y install xorg xserver-xorg-core
# apt-get -y install xfce4 xfce4-goodies  # Lightweight desktop environment
# Or for minimal X11 (just X server):
# apt-get -y install xserver-xorg-core xinit xterm

apt-get clean

# exit chroot
exit

sudo umount $MNT
```

**Understanding Loop Devices:**

Loop devices (`/dev/loop0`, `/dev/loop1`, etc.) are special device files that allow you to mount regular files (like image files) as if they were physical block devices (like disks). This is essential for working with filesystem images.

**Important: Loop devices are temporary and disappear:**
- ❌ After system reboot
- ❌ After running `losetup -d /dev/loopX` (manual detach)
- ❌ After unmounting, the loop device stays attached unless explicitly detached
- ✅ They persist during your current session (until reboot or manual detach)

**This is normal behavior** - you need to re-run `losetup` each time you reboot or if you manually detached it. This is why we capture the loop device in a variable (`$LOOP_DEV`) - so you can easily recreate it.

**How to check what loop devices are set up:**
```bash
# List all loop devices and what files they're associated with
sudo losetup -a
# Example output:
# /dev/loop0: [0035]:1234567 (/home/riscv_dev/debian-sid-risc-v-root.img)
# If empty, no loop devices are currently set up

# Or use lsblk to see loop devices
lsblk
# Shows loop0, loop0p1, etc. with their mount points
# If you don't see your image file, the loop device isn't set up
```

**Workflow when loop device is missing (normal situation):**

Since loop devices disappear after reboot, this is the normal workflow:

```bash
# 1. Set up environment variable for mount point (REQUIRED FIRST!)
export MNT=$PWD/mnt
# Or explicitly:
# export MNT=/home/riscv_dev/mnt

# 2. Check if already set up (probably empty after reboot)
sudo losetup -a

# 3. Set up loop device again (this is normal - do this each session)
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Loop device: $LOOP_DEV"

# 4. Check if filesystem is already mounted
mount | grep $LOOP_DEV
# If mounted, you can skip step 5

# 5. Mount it
mkdir -p $MNT
sudo mount -t ext4 $LOOP_DEV $MNT

# 6. Verify it's mounted
mount | grep $LOOP_DEV
# Should show: /dev/loop0 on /home/riscv_dev/mnt type ext4 ...
```

**Note:** Don't worry if the loop device is gone - this is expected after reboot. Just run `losetup` again to recreate it.

**⚠️ IMPORTANT: Do NOT redo Step 4 just because the loop device is missing!**

If you've already created `debian-sid-risc-v-root.img` and made changes to it, you should:
- ✅ **Just remount the existing image** (follow the workflow above)
- ❌ **DO NOT** re-run the entire Step 4 (you'll lose all your work!)

**Only redo Step 4 if:**
- The image file doesn't exist or was deleted
- The image file is corrupted
- You want to start completely fresh (accepting data loss)

**If you get "can't find in /etc/fstab" error when mounting:**

This error means:
1. The loop device might not be set up yet, OR
2. You're trying to mount without specifying the filesystem type

**Fix:**
```bash
# First, check if loop device exists and is set up
sudo losetup -a
# If nothing shows up, set up the loop device:
sudo losetup --partscan --find --show debian-sid-risc-v-root.img
# This will output something like: /dev/loop0

# Then mount with explicit filesystem type:
sudo mount -t ext4 /dev/loop0 $MNT
# Or if it's a single partition image:
sudo mount -t ext4 /dev/loop0 $MNT
```

**Common loop device usage:**
```bash
# Set up loop device (associates file with /dev/loopX)
sudo losetup --partscan --find --show image.img
# Output: /dev/loop0 (for example)

# Mount it
sudo mount /dev/loop0 /mnt

# When done, unmount and detach:
sudo umount /mnt
sudo losetup -d /dev/loop0  # Detach the loop device

# Or detach all:
sudo losetup -D
```

**To remove packages after unmounting:**

If you need to remove packages you've already installed (e.g., multimedia packages), remount and enter chroot:

```bash
# Navigate to working directory
cd /home/riscv_dev

# Set mount point
export MNT=$PWD/mnt

# Set up loop device (capture which one was assigned)
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Using loop device: $LOOP_DEV"

# Mount filesystem
mkdir -p $MNT
sudo mount -t ext4 $LOOP_DEV $MNT

# Copy QEMU emulator if needed
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/

# Enter chroot
sudo chroot $MNT /bin/bash

apt-get install build-essential
git clone -b dev-pureminima --single-branch https://github.com/minima-global/Minima.git

# Remove packages (example - adjust to your needs)
apt-get remove --purge mpg123 ffmpeg chocolate-doom openttd xscreensaver xscreensaver-data xscreensaver-data-extra

# Before autoremove: Check if you have X11 installed
# If you have X11, some packages (like GTK libraries) might be needed
# Check what packages are installed:
dpkg -l | grep -E '(xorg|xfce|openbox|gtk|libgtk)'

# If you DON'T have X11, autoremove is safe
# If you DO have X11, be more careful:
# Option 1: Safe autoremove (apt will keep packages still needed)
apt-get autoremove

# Option 2: If you want to see what depends on a package first:
# apt-cache rdepends <package-name>

apt-get autoclean

# Exit chroot
exit

# Unmount
sudo umount $MNT
```

**Verification Checks Before Proceeding to SD Card Setup:**

Before writing the rootfs to SD card, verify it's correct. Run these from **outside the chroot** (on your host system):

```bash
# Remount if not already mounted
cd /home/riscv_dev
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
echo "Loop device: $LOOP_DEV"
sudo mount -t ext4 $LOOP_DEV $MNT

# 1. Check filesystem integrity
sudo fsck -n $LOOP_DEV
# Should show no errors

# 2. Verify essential configuration files
echo "=== /etc/fstab ==="
cat $MNT/etc/fstab
echo ""
echo "=== /etc/hostname ==="
cat $MNT/etc/hostname
echo ""
echo "=== Root password hash exists ==="
grep "^root:" $MNT/etc/shadow | cut -d: -f2 | head -c 20 && echo " (hash present)"
echo ""

# 3. Check disk space usage
du -sh $MNT
du -sh $MNT/* | sort -h | tail -5
# Shows total size and largest directories

# 4. Test chroot and verify architecture
sudo chroot $MNT /bin/bash -c 'echo "Chroot works" && uname -m'
# Should show: Chroot works and riscv64

# 5. Verify essential binaries exist
echo "=== Essential binaries ==="
for bin in sh bash ls cat mount umount; do
    test -f $MNT/bin/$bin && echo "OK: /bin/$bin" || echo "MISSING: /bin/$bin"
done

# 6. Verify package database is intact
sudo chroot $MNT /bin/bash -c 'dpkg --print-architecture'
# Should show: riscv64

# 7. Verify root's shell is configured correctly
echo "=== Root shell configuration ==="
grep "^root:" $MNT/etc/passwd
# Should show: root:x:0:0:root:/root:/bin/bash
test -x $MNT/bin/bash && echo "OK: /bin/bash is executable" || echo "ERROR: /bin/bash missing or not executable"

# 8. Verify TTY/console configuration for RISC-V SBI (hvc0)
echo "=== TTY/Console configuration ==="
# Check if getty service is enabled for hvc0
if [ -L "$MNT/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service" ]; then
    echo "OK: serial-getty@hvc0.service is enabled"
    ls -l $MNT/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service
else
    echo "WARNING: serial-getty@hvc0.service is NOT enabled - login may fail!"
    echo "Fix: Enter chroot and enable it (see Step 4 troubleshooting section)"
fi

# Check if service override exists
if [ -f "$MNT/etc/systemd/system/serial-getty@hvc0.service.d/override.conf" ]; then
    echo "OK: Service override file exists"
    cat $MNT/etc/systemd/system/serial-getty@hvc0.service.d/override.conf
else
    echo "WARNING: Service override file missing - login may fail!"
    echo "Fix: Enter chroot and create it (see Step 4 troubleshooting section)"
fi

# If TTY fix is missing, apply it now:
if [ ! -L "$MNT/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service" ] || \
   [ ! -f "$MNT/etc/systemd/system/serial-getty@hvc0.service.d/override.conf" ]; then
    echo ""
    echo "=== Applying TTY fix for RISC-V SBI console ==="
    sudo chroot $MNT /bin/bash <<'CHROOT_EOF'
        # Enable getty for hvc0 (SBI console)
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
        
        # Verify it was created
        echo "Verification:"
        ls -la /etc/systemd/system/getty.target.wants/ | grep hvc0 || echo "ERROR: Symlink not created!"
        test -f /etc/systemd/system/serial-getty@hvc0.service.d/override.conf && \
          echo "OK: Override file created" || echo "ERROR: Override file not created!"
CHROOT_EOF
    echo "TTY fix applied!"
fi
```

**From inside chroot** (if you're already in chroot, use these - NO sudo needed):

```bash
# Check configuration files
cat /etc/fstab
cat /etc/hostname
test -s /etc/shadow && grep "^root:" /etc/shadow | cut -d: -f2 | head -c 20 && echo " (password set)"

# Verify architecture
dpkg --print-architecture
# Should show: riscv64

# Check essential binaries
for bin in sh bash ls cat mount umount; do
    test -f /bin/$bin && echo "OK: /bin/$bin" || echo "MISSING: /bin/$bin"
done

# Check disk usage
du -sh /usr /var /etc 2>/dev/null

# Verify root's shell is bash
echo "=== Root shell ==="
grep "^root:" /etc/passwd
test -x /bin/bash && echo "OK: /bin/bash is executable" || echo "ERROR: /bin/bash missing!"

# Verify TTY/console configuration for RISC-V SBI
echo "=== TTY/Console configuration ==="
if [ -L "/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service" ]; then
    echo "OK: serial-getty@hvc0.service is enabled"
    ls -l /etc/systemd/system/getty.target.wants/serial-getty@hvc0.service
else
    echo "WARNING: serial-getty@hvc0.service is NOT enabled - enable it now!"
    systemctl enable serial-getty@hvc0.service 2>/dev/null || \
      ln -sf /lib/systemd/system/serial-getty@.service \
             /etc/systemd/system/getty.target.wants/serial-getty@hvc0.service
fi

if [ -f "/etc/systemd/system/serial-getty@hvc0.service.d/override.conf" ]; then
    echo "OK: Service override file exists"
    cat /etc/systemd/system/serial-getty@hvc0.service.d/override.conf
else
    echo "WARNING: Service override file missing - create it now!"
    mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/
    cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/hvc0
StandardInput=tty
StandardOutput=tty
Restart=always
RestartSec=0
EOF
    echo "Override file created!"
fi
```

**Note:** If you see `root@DESKTOP-SJAEBE7:/#`, you're already inside the chroot as root. Just run commands directly without `sudo` or `chroot`.

**Common Issues to Watch For:**
- Missing `/etc/fstab` or incorrect entries (must have mmcblk0p2 for root, mmcblk0p1 for boot)
- Missing `/etc/hostname` or empty file
- Root password not set (empty hash in /etc/shadow)
- Filesystem errors (from fsck)

If all checks pass, you're ready for Step 5!

```bash
# Unmount after verification (from host, not chroot)
exit  # if you're in chroot
sudo umount $MNT
```

### Step 5: Setup SD Card

**⚠️ Important: Choose ONE option.**

**Option A: Direct Linux device access (traditional method)**

**⚠️ Note for WSL users:** Direct device access in WSL is often limited. If your 64GB SD card doesn't show up properly in `lsblk`, **use Option C instead** (it's easier for WSL).

If you have direct Linux access to SD card device and it shows up correctly:

```bash
export SDCARD=/dev/???  # Replace with your SD card device (e.g., /dev/sdb)
export SDCARD_P1=${SDCARD}1
export SDCARD_P2=${SDCARD}2

# Write the partition table
(
echo o
echo n
echo p
echo 1
echo
echo +512M
echo y
echo n
echo p
echo 2
echo
echo +7168M
echo y
echo t
echo 1
echo b
echo p
echo w
) | sudo fdisk $SDCARD

sudo mkfs.vfat $SDCARD_P1

# Copy rootfs
sudo dd if=debian-sid-risc-v-root.img of=$SDCARD_P2 bs=64k iflag=fullblock oflag=direct conv=fsync status=progress

# Copy boot files
export BOOT=mnt_p1
mkdir -p $BOOT
sudo mount $SDCARD_P1 $BOOT
# boot.json is optional - only copy if it exists
[ -f build/alinx_ax7203/boot.json ] && sudo cp build/alinx_ax7203/boot.json $BOOT/
sudo cp build/alinx_ax7203/linux.dtb $BOOT/
sudo cp opensbi/build/platform/litex/naxriscv/firmware/fw_jump.bin $BOOT/opensbi.bin 
sudo cp opensbi/build/platform/litex/naxriscv/firmware/fw_jump.elf $BOOT/opensbi.elf
sudo cp litex-linux/vmlinux $BOOT/ 
sudo cp litex-linux/arch/riscv/boot/Image $BOOT/
sudo umount $BOOT
```

**Option B: Hybrid approach (recommended for WSL) ⭐**

**This is the easiest option for WSL users!** Since your SD card is already visible at `/mnt/e`, use this approach.

1. **Format SD card in Windows - Detailed Steps:**

   **Using Windows Disk Management:**
   
   a. **Open Disk Management:**
      - Press `Win + X` and select "Disk Management"
      - Or: Right-click Start button → Disk Management
      - Or: Run `diskmgmt.msc`
   
   b. **Identify your SD card:**
      - Look for your 64GB SD card in the list
      - **⚠️ CAREFUL:** Make sure you select the SD card, not your Windows drive!
      - Check the size (should be ~64GB) and make sure it's the removable device
   
   c. **Delete existing partitions (if any):**
      - Right-click each existing partition on the SD card
      - Select "Delete Volume..." 
      - Confirm deletion
      - Repeat for all partitions until the card shows as "Unallocated"
   
   d. **Create Boot Partition (Partition 1):**
      - Right-click the "Unallocated" space on your SD card
      - Select "New Simple Volume..."
      - Click Next
      - **Size:** Enter `512` (for 512 MB)
      - Click Next
      - **Assign drive letter:** Choose `E:` (or any available letter)
      - Click Next
      - **Format this volume:**
        - File system: **FAT32**
        - Volume label: `boot` (optional)
        - Leave "Perform a quick format" checked
      - Click Next, then Finish
      - Wait for formatting to complete
   
   e. **Create Root Partition (Partition 2):**
      - Right-click the remaining "Unallocated" space
      - Select "New Simple Volume..."
      - Click Next
      - **Size:** Leave default (will use all remaining space, or enter ~7168 for 7GB minimum)
      - Click Next
      - **Assign drive letter:** Choose a different letter (e.g., `F:`)
      - Click Next
      - **Format this volume:**
        - File system: **exFAT** or **NTFS** (Windows can't format ext4 natively)
        - OR select "Do not format this volume" (you'll format it later in Linux if needed)
      - Click Next, then Finish
   
   **Alternative: Using Command Prompt (PowerShell as Admin):**
   
   ```powershell
   # Open PowerShell as Administrator
   # List disks - identify your SD card disk number
   Get-Disk
   
   # Example: If SD card is Disk 3, replace with your disk number
   $disk = 3  # Change this!
   
   # Clear the disk
   Clear-Disk -Number $disk -RemoveData -Confirm:$false
   
   # Create boot partition (512MB, FAT32)
   New-Partition -DiskNumber $disk -Size 512MB -DriveLetter E
   Format-Volume -DriveLetter E -FileSystem FAT32 -NewFileSystemLabel "boot"
   
   # Create root partition (use remaining space)
   New-Partition -DiskNumber $disk -UseMaximumSize -DriveLetter F
   # Optionally format as NTFS (or leave unformatted)
   Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel "rootfs"
   ```
   
   **⚠️ Important:**
   - Make absolutely sure you're working with the SD card, not your main Windows drive!
   - The boot partition MUST be FAT32 and should be at least 512MB
   - The root partition can be NTFS/exFAT (for Windows compatibility) or unformatted (to format as ext4 later)

2. **Copy boot files from WSL:**
```bash
# Mount the boot partition explicitly (E: drive)
sudo umount /mnt/e 2>/dev/null || true
sudo mkdir -p /mnt/e
sudo mount -t drvfs E: /mnt/e

export BOOT=/mnt/e

# Copy all boot files
sudo cp build/alinx_ax7203/linux.dtb $BOOT/
sudo cp opensbi/build/platform/litex/naxriscv/firmware/fw_jump.bin $BOOT/opensbi.bin 
sudo cp opensbi/build/platform/litex/naxriscv/firmware/fw_jump.elf $BOOT/opensbi.elf
sudo cp litex-linux/vmlinux $BOOT/ 
sudo cp litex-linux/arch/riscv/boot/Image $BOOT/

# Create boot.json (required for LiteX BIOS)
cat > $BOOT/boot.json <<'EOF'
{
	"Image":       "0x41000000",
	"linux.dtb":   "0x46000000",
	"opensbi.bin": "0x40f00000"
}
EOF

# Verify boot.json was created
cat $BOOT/boot.json

# CRITICAL: Sync to ensure all data is written to SD card
sync

# Verify files are actually on the SD card
ls -lh $BOOT/
# Should show: boot.json, Image, linux.dtb, opensbi.bin, opensbi.elf, vmlinux

# Verify persistence by remounting
sudo umount /mnt/e
sudo mount -t drvfs E: /mnt/e
ls -lh /mnt/e
# Files should still be there after remount if written correctly
```

3. **Copy rootfs to the second partition:**

   **Using dd for Windows (Recommended when WSL can't detect SD card) ⭐**
   
   Since WSL can't detect your SD card device, we'll use dd for Windows to write the rootfs image directly to partition 2.
   
   **Step 1: Download dd for Windows**
   
   - Download from: https://www.chrysocome.net/dd
   - Get: `dd-0.6beta3.zip`
   - Extract `dd.exe` to a folder (e.g., `C:\tools\` or `C:\Windows\System32\`)
   
   **Step 2: Identify your SD card partition in Windows**
   
   ```powershell
   # Open PowerShell as Administrator
   # List all partitions to find your SD card
   Get-Partition | Format-Table DriveLetter, Size, Type, PartitionNumber
   
   # You should see:
   # - E: (512 MB, FAT32) = boot partition (Partition 1)
   # - F: (59 GB, Logical) = rootfs partition (Partition 2)
   ```
   
   **Step 3: VERIFY BEFORE WRITING (CRITICAL SAFETY CHECK)**
   
   ```powershell
   # CRITICAL: Verify your partitions BEFORE running dd!
   
   # Verify SD card partitions (should show E: and F:):
   Get-Partition -DiskNumber 1 | Format-Table DriveLetter, PartitionNumber, Size
   # Should show:
   # - E: PartitionNumber=1 (512MB) ← boot partition (DO NOT WRITE HERE!)
   # - F: PartitionNumber=2 (59GB) ← rootfs partition (THIS is what we write to)
   
   # Verify rootfs image file exists:
   Test-Path "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img"
   # Should return: True
   
   # Check image file size (should be ~7GB):
   (Get-Item "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img").Length / 1GB
   # Should show approximately 7GB
   
   # Get Volume GUID for F: drive (rootfs partition)
   (Get-Volume -DriveLetter F).UniqueId
   # Example output: \\?\Volume{f26c848a-b7e8-11f0-a777-e0d4e89fa73a}\
   # Note: We'll use \\.\Volume{...} format (without trailing backslash) for dd.exe
   ```
   
   **Step 4: Write rootfs image to partition 2 (ONLY AFTER VERIFICATION)**
   
   ```powershell
   # In PowerShell (as Administrator)
   cd C:\Windows\system32\dd-0.6beta3  # or wherever you extracted dd.exe
   
   # Get the Volume GUID for F: drive (rootfs partition)
   $volumeId = (Get-Volume -DriveLetter F).UniqueId
   # Extract just the GUID part (remove \\?\ and trailing \)
   $volumeGuid = $volumeId -replace '\\\\\?\\', '\\.\' -replace '\\$', ''
   Write-Host "Writing to: $volumeGuid"
   
   # Write command - USE QUOTES to prevent PowerShell from interpreting = as parameter
   # IMPORTANT: Use quotes around if= and of= values!
   .\dd.exe if="\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" of="$volumeGuid" bs=1M
   
   # Alternative: If WSL path doesn't work, copy image to Windows first:
   # Copy-Item "\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" -Destination "C:\temp\debian-sid-risc-v-root.img"
   # Then use:
   # .\dd.exe if="C:\temp\debian-sid-risc-v-root.img" of="$volumeGuid" bs=1M
   
   # This will take 5-15 minutes (image is 7GB)
   # You'll see progress as it writes
   # Wait for completion message
   ```
   
   **Manual method (if you prefer to type the GUID manually):**
   
   ```powershell
   # Get the GUID first:
   (Get-Volume -DriveLetter F).UniqueId
   # Output example: \\?\Volume{f26c848a-b7e8-11f0-a777-e0d4e89fa73a}\
   
   # Then use it manually (change \\?\ to \\.\ and remove trailing \):
   .\dd.exe if="\\wsl.localhost\Ubuntu\home\riscv_dev\debian-sid-risc-v-root.img" of="\\.\Volume{f26c848a-b7e8-11f0-a777-e0d4e89fa73a}" bs=1M
   ```
   
   **⚠️ CRITICAL SAFETY CHECKLIST - READ BEFORE RUNNING:**
   
   ✅ **Drive Letter:** F: = rootfs partition (~59GB, Partition 2)
   
   ✅ **NOT E:** E: = boot partition (~512MB, Partition 1) - DO NOT WRITE HERE!
   
   ✅ **Volume GUID:** Should be for F: drive (verify with `Get-Volume -DriveLetter F`)
   
   ✅ **Image file exists:** Verify the path to `debian-sid-risc-v-root.img` is correct
   
   ✅ **Quotes required:** Always use quotes around `if=` and `of=` values in PowerShell!
   
   **If anything doesn't match, STOP and verify before proceeding!**
   
   **Step 5: Verify the write completed**
   
   ```powershell
   # Check partition properties
   Get-Partition -DriveLetter F | Format-List
   
   # The partition should now contain data
   # Note: Windows can't read ext4, so F: will show as unreadable - that's normal!
   ```
   
   **Alternative: Using WSL if device becomes accessible**
   
   If your WSL later can detect the SD card (`lsblk` shows it), you can use this method instead:
   
   ```bash
   # Find SD card device
   lsblk
   # Mount partition 2
   sudo mount /dev/sdb2 /mnt/rootfs_target
   # Mount image and copy (see method below)
   ```
   
   **Important Notes:**
   - The rootfs image is 7GB, so writing will take 5-15 minutes
   - After writing, partition 2 will contain your complete Debian rootfs
   - Windows may show F: as unreadable - that's normal (it's ext4, Windows can't read it)
   - Don't format partition 2 after writing (the image already contains the filesystem)

**Final Checklist Before Booting:**

✅ Boot partition (E:) has all required files:

   **From WSL, verify files are present:**
   ```bash
   ls -lh /mnt/e/
   # Should show: boot.json, Image, linux.dtb, opensbi.bin, opensbi.elf, vmlinux
   ```
   
   **Required files:**
   - boot.json (boot configuration - REQUIRED, tells BIOS where to load files)
   - Image (kernel binary, ~19MB)
   - linux.dtb (device tree, ~3KB)
   - opensbi.bin (firmware, ~130KB)
   - opensbi.elf (optional, ~750KB)
   - vmlinux (optional, ~15MB)

✅ Rootfs partition (F:) verified:
   - Essential directories exist (bin, etc, usr, var, etc.)
   - Critical config files exist (fstab, hostname, shadow)
   - Size is ~1.5-2GB

✅ SD card safely ejected/unmounted from Windows

✅ Serial console ready (see below)

**Connect to serial console:**

```bash
# On Linux/WSL
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0 -b 115200

# On Windows: Use PuTTY or similar
# Port: COM3 (or your port), Speed: 115200
```

**Troubleshooting: "boot.json file not found" or "boot.bin file not found"**

If the BIOS can't find boot files on SD card:

1. **Verify files are actually on the SD card:**
   ```bash
   # In WSL, remount and check
   sudo umount /mnt/e 2>/dev/null || true
   sudo mount -t drvfs E: /mnt/e
   ls -lh /mnt/e/
   # Should show: Image, linux.dtb, opensbi.bin, opensbi.elf, vmlinux
   ```

2. **Check file names match what LiteX BIOS expects:**
   
   The BIOS is looking for `boot.json` or `boot.bin`, but you have `opensbi.bin`. Try:
   
   ```bash
   # In WSL, remount SD card
   sudo umount /mnt/e 2>/dev/null || true
   sudo mount -t drvfs E: /mnt/e
   cd /mnt/e
   
   # Create boot.json (required - the BIOS is looking for this file)
   sudo tee boot.json > /dev/null <<'EOF'
{
	"Image":       "0x41000000",
	"linux.dtb":   "0x46000000",
	"opensbi.bin": "0x40f00000"
}
EOF
   
   # Verify boot.json was created
   cat boot.json
   ls -lh boot.json
   
   # Sync to ensure it's written
   sync
   ```
   
   The boot.json file tells LiteX BIOS:
   - Where to load Image (kernel) at address 0x41000000
   - Where to load linux.dtb (device tree) at address 0x46000000
   - Where to load opensbi.bin (firmware) at address 0x40f00000

3. **SD card might not be properly ejected/written:**
   - Safely eject from Windows
   - Reinsert SD card
   - Remount and verify files are still there

4. **Check SD card filesystem:**
   - The boot partition should be FAT32
   - Windows might have corrupted it - try reformatting boot partition if needed

**Power on or reset the board** and watch for:

```
--=============== SoC ==================--
CPU:            NaxRiscv 64-bit @ 100MHz
...

Copying Image to 0x40000000 (20971520 bytes)...
Copying linux.dtb to 0x40ef0000 (3076 bytes)...
Copying opensbi.bin to 0x40f00000 (274016 bytes)...
Executing booted program at 0x40f00000
--============= Liftoff! ===============--

OpenSBI v1.3.1
Platform Name             : LiteX/VexRiscv-SMP
...

[    0.000000] Linux version 6.1.0 ...
[    0.000000] early console enabled
[    0.000000] printk: bootconsole [sbi0] enabled
...
[    0.XXX] Kernel panic - MMC driver probe failed
```

**Success indicators you should see:**
1. ✅ **"Liftoff!"** - OpenSBI started successfully
2. ✅ **OpenSBI banner** - Platform information displayed
3. ✅ **Linux kernel loading** - "Linux version..." message
4. ✅ **SBI console enabled** - "early console: sbi0" or "bootconsole [sbi0] enabled"
5. ✅ **Hardware detection** - Drivers initializing

**If you see MMC/SD card driver panic:**
The boot files are working correctly! The panic is in the SD card driver (`litex_mmc_probe`), which is a driver/hardware compatibility issue. This means:
- ✅ Boot files loaded correctly
- ✅ OpenSBI → Linux handoff succeeded
- ✅ Kernel is running
- ❌ SD card rootfs mounting failed (driver issue)

**Troubleshooting MMC driver panic:**

The panic is caused by a **hardware address mismatch** between:
- **Actual hardware** (from LiteX build): SD card at `0xf0004000` (check `build/alinx_ax7203/csr.csv`)
- **Device tree** (DTS): MMC device at `0xf0028000` (check `build/alinx_ax7203/linux.dts`)

**The Issue:**
- **csr.csv** = Auto-generated by LiteX (header says "Auto-generated by LiteX") - this is the source of truth for hardware addresses
- **linux.dts** = Likely manually created or copied from a template (doesn't have auto-generated header)
- When you manually added SD card support to LiteX, hardware was instantiated at `0xf0004000` (per csr.csv)
- But linux.dts was created/edited with addresses from a different template (`0xf0028000`)
- The Linux MMC driver tries to access `0xf0028000` (from DTS), but the actual hardware is at `0xf0004000`

**Why this happened:**
LiteX can generate DTS files, but if linux.dts was manually created or copied from another board, it won't match your actual hardware addresses. The csr.csv file (auto-generated) is the authoritative source for where hardware actually is.

**Solutions:**

1. **Fix the DTS addresses** (recommended):
   ```bash
   # Edit linux.dts to match your actual hardware addresses
   cd build/alinx_ax7203
   # Update mmc0 addresses in linux.dts to match csr.csv
   # Replace 0xf0028000 with 0xf0004000 (from csr.csv line 12)
   # Then recompile DTB:
   dtc -I dts -O dtb -o linux.dtb linux.dts
   ```

2. **Temporarily disable MMC in DTS** (quick test):
   ```bash
   # Change status from "okay" to "disabled" in linux.dts
   # mmc0: mmc@f0028000 {
   #     ...
   #     status = "disabled";  # Changed from "okay"
   # }
   ```

3. **Regenerate DTS from LiteX** (if supported):
   ```bash
   # LiteX can generate DTS files, check if there's a --csr-csv option or similar
   # Some LiteX targets generate .dts files automatically
   # Check your LiteX build output or target script for DTS generation
   ```

**Note on DTS generation:**
- **csr.csv** is always auto-generated by LiteX (authoritative hardware addresses)
- **linux.dts** may or may not be auto-generated - check if it has an "Auto-generated by LiteX" header
- If linux.dts was manually created/copied, you must manually update addresses to match csr.csv
- If LiteX generates DTS, ensure the target script properly includes SD card in DTS generation

---

## What to Expect

### ✅ Success Indicators

If everything is configured correctly, you should see:

1. **BIOS output**: Shows SoC info, memory initialization
2. **File loading**: Shows files being copied to RAM
3. **OpenSBI "Liftoff!"**: Critical - this means OpenSBI started
4. **OpenSBI banner**: Platform info, version
5. **Linux early messages**: "early console enabled" or "printk: console [sbi] enabled"
6. **Kernel messages**: Linux booting, drivers initializing

### ❌ Failure Patterns

**Hang right after "Liftoff!" with no OpenSBI banner:**
- Kernel SBI console not enabled
- Missing `CONFIG_SERIAL_EARLYCON_RISCV_SBI=y`
- Rebuild kernel

**Complete silence after "Liftoff!":**
- DTS bootargs not using `earlycon=sbi`
- Wrong bootargs format
- Recompile DTB

**Kernel panic or error messages:**
- Check the specific error
- May need rootfs or driver issues
- See troubleshooting section below

---

## If Root Filesystem Doesn't Exist

**You have two options:**

### Option A: Quick Test - Skip RootFS for Now

Boot without mounting rootfs to test OpenSBI output:

```bash
# Temporarily change DTS bootargs to:
bootargs = "earlycon=sbi console=ttyS0";

# Or use initramfs/cpio if you have one
```

### Option B: Build Minimal RootFS (Recommended)

**Using Debootstrap (15-30 minutes):**

```bash
# Install tools
sudo apt-get install debootstrap qemu-user-static binfmt-support debian-archive-keyring

# Bootstrap Debian (using main archive, not ports)
mkdir -p build/alinx_ax7203/rootfs
sudo debootstrap --arch=riscv64 --foreign --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    bookworm build/alinx_ax7203/rootfs http://deb.debian.org/debian

# Copy QEMU emulator
sudo cp /usr/bin/qemu-riscv64-static build/alinx_ax7203/rootfs/usr/bin/

# Complete installation
sudo DEBIAN_FRONTEND=noninteractive chroot build/alinx_ax7203/rootfs /debootstrap/debootstrap --second-stage

# Configure
sudo chroot build/alinx_ax7203/rootfs /bin/bash
echo "root:root" | chpasswd
echo "minima-board" > /etc/hostname
exit

# Create image
cd build/alinx_ax7203
dd if=/dev/zero of=rootfs.ext2 bs=1M count=1024
sudo mkfs.ext2 rootfs.ext2
sudo mount rootfs.ext2 /mnt
sudo cp -a rootfs/* /mnt/
sudo umount /mnt
```

---

## Troubleshooting

### Kernel Build Fails with "Error 2"

**Symptom:** Kernel build fails with `make: *** [Makefile:1992: .] Error 2` or similar.

**Root Cause:** The actual error message appears earlier in the build output. "Error 2" is just make's exit code.

**Solution:**
1. **Find the actual error:**
   ```bash
   cd litex-linux
   # Scroll up in your terminal to find the first line with "error:" or "Error"
   # Or save build output to file:
   make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- 2>&1 | tee build.log
   # The build.log file will be created in: litex-linux/build.log
   
   # View errors from the log:
   grep -i error build.log | head -20  # Shows first 20 errors
   ```

2. **Common fixes:**

   **Missing dependencies:**
   ```bash
   # Install build dependencies if missing
   sudo apt-get install -y libncurses-dev bison flex libssl-dev libelf-dev
   ```

   **Configuration conflicts:**
   ```bash
   # Regenerate config to resolve conflicts
   make ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- oldconfig
   # Press Enter for default choices when prompted
   ```

   **Clean rebuild:**
   ```bash
   # Clean previous build artifacts
   make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- clean
   # Or for deep clean:
   make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- mrproper
   # Then reconfigure:
   make ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- defconfig
   # Re-enable your custom options (MICREL_PHY, etc.)
   ```

   **Toolchain issues:**
   ```bash
   # Verify toolchain is working
   $HOME/riscv/bin/riscv64-unknown-linux-gnu-gcc --version
   # Should show GCC version, not "command not found"
   
   # Verify CROSS_COMPILE path
   export CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu-
   echo $CROSS_COMPILE
   ```

3. **Build with verbose output:**
   ```bash
   # Use single job to see errors clearly
   make -j1 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- V=1
   # V=1 shows full compiler commands
   ```

**If you share the actual error message (scroll up to find it), I can provide a specific fix.**

**Specific Error Fixes:**

**Error 1: BTRFS print-tree.c - unterminated string initialization**
```
fs/btrfs/print-tree.c:26:49: error: initializer-string for array of 'char' truncates NUL terminator
```

**Error 2: net/socket.c - array bounds warning**
```
net/socket.c:650:21: error: array subscript -1 is outside array bounds
```

**These are GCC warnings being treated as errors. Quick fix (recommended for getting build working):**

**Method 1: Disable -Werror globally (RECOMMENDED - simplest and works reliably):**

```bash
cd litex-linux

# Disable treating warnings as errors in kernel config
scripts/config --disable CONFIG_WERROR

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

**Method 2: Disable specific warnings for problematic files (alternative if you want to keep -Werror for other files):**

```bash
cd litex-linux

# Add per-file flags to disable the specific warnings for these source files
# This preserves error checking for other files

# Fix for btrfs/print-tree.c - disable warning for this specific file
echo 'CFLAGS_print-tree.o += -Wno-error=unterminated-string-initialization' >> fs/btrfs/Makefile

# Fix for net/socket.c - disable array bounds warning for this specific file
echo 'CFLAGS_socket.o += -Wno-error=array-bounds' >> net/Makefile

# Verify the flags were added
tail -2 fs/btrfs/Makefile
tail -2 net/Makefile

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

**Method 3: Patch the source code (proper fix, but more work):**

```bash
cd litex-linux

# Fix btrfs/print-tree.c (increase array size by 1)
sed -i '26s/\(.*\)\[16\]/\1[17]/' fs/btrfs/print-tree.c

# Fix net/socket.c (this requires understanding the code context)
# The array bounds warning might be a false positive, but check the code:
# Look at net/socket.c lines 650-651 to understand the context
# You may need to add bounds checking or adjust the code logic

# Rebuild
make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
```

**Recommended approach:** Use Method 1 (disable -Werror globally) - it's the simplest and most reliable. Method 2 is an alternative if you want to keep warnings as errors for other files. Method 3 is the proper fix but requires understanding the code context.

### Repeated Login Prompts (Login Loop) - System Exits After Login

**Symptom:** After entering password, you immediately get logged out and prompted to login again. The system appears to exit/restart the login process after each login attempt.

**Quick Fix Checklist (most common issues):**
1. ✅ Verify `/bin/bash` exists and is executable
2. ✅ Check `/etc/passwd` has `root:x:0:0:root:/root:/bin/bash` (not `/bin/sh` or `/bin/false`)
3. ✅ **For RISC-V SBI: Configure getty for `hvc0` console** (most likely fix for your system)
4. ✅ Check systemd getty service is running and configured correctly

**Common Causes:**
1. **Shell doesn't exist or isn't executable** - The shell specified in `/etc/passwd` (e.g., `/bin/bash`) doesn't exist or isn't executable
2. **Shell exits immediately** - The shell starts but exits due to missing libraries, configuration errors, or permission issues
3. **Console/TTY misconfiguration** - The console device (e.g., `hvc0`, `ttyS0`) isn't properly configured for login sessions
4. **Missing critical system files** - Essential files like `/etc/passwd`, `/etc/shadow`, or shell configuration files are corrupted or missing
5. **Systemd getty restart loop** - The getty service (manages login prompts) restarts immediately, causing logout
6. **Profile/shell configuration errors** - Errors in `/etc/profile`, `/etc/bash.bashrc`, or user's `~/.profile` cause immediate exit

**Diagnostic Steps (to identify which cause):**

From your running system (if you can get a brief moment before logout), try:

```bash
# 1. Check what shell root is configured to use
grep "^root:" /etc/passwd
# Should show: root:x:0:0:root:/root:/bin/bash
# If it shows /bin/sh, /bin/false, or nothing, that's the problem

# 2. Verify bash exists and is executable
ls -l /bin/bash
test -x /bin/bash && echo "bash is executable" || echo "bash NOT executable!"

# 3. Check if bash can actually run (may fail due to missing libraries)
/bin/bash --version 2>&1 | head -1

# 4. Check console/TTY configuration
# On RISC-V with SBI, console is typically hvc0
dmesg | grep -i "console\|tty\|hvc"

# 5. Check systemd getty status
systemctl status getty@hvc0.service 2>&1 | head -20
# Or for serial console:
systemctl status serial-getty@hvc0.service 2>&1 | head -20

# 6. Check for errors in system logs
journalctl -b | tail -50 | grep -i "error\|fail\|bash\|shell"
```

**Quick test (if you can login briefly):**
```bash
# Try to bypass the shell and see what error you get
exec /bin/sh  # Try simple shell instead of bash
# Or:
/bin/bash -c "echo 'Bash works'"  # Test if bash can execute commands
```

**Fix from chroot (before first boot - RECOMMENDED):**
```bash
sudo mount /dev/loop0 $MNT
sudo chroot $MNT /bin/bash

# Check root's shell
grep "^root:" /etc/passwd
# Should show: root:x:0:0:root:/root:/bin/bash

# If shell is wrong (shows /bin/false, /usr/sbin/nologin, or missing), fix it:
chsh -s /bin/bash root

# Verify bash exists
test -x /bin/bash && echo "OK" || echo "Bash missing!"

# If bash doesn't exist, install it:
apt-get install -y bash

# Also verify /etc/passwd line for root looks correct:
# root:x:0:0:root:/root:/bin/bash
```

**Fix from live system (if you can get in briefly):**
1. When you see the login prompt, try logging in as quickly as possible
2. Immediately run:
   ```bash
   chsh -s /bin/bash root
   exit
   ```
3. Log in again - should work now

**Alternative: Edit /etc/passwd directly:**
```bash
# In chroot or live system, edit /etc/passwd
# Find line: root:x:0:0:root:/root:/bin/sh
# Change to: root:x:0:0:root:/root:/bin/bash
# Or ensure the shell path is correct and executable
```

**Prevention:** Always verify root's shell during rootfs setup:
```bash
# Before unmounting rootfs image
grep "^root:" $MNT/etc/passwd
test -x $MNT/bin/bash && echo "bash OK"
```

**If bash/config is correct but login loop persists:**

**Root Cause:** This is likely a **console/TTY issue**, not a shell issue. On RISC-V systems with SBI (like your setup), the console device is typically `hvc0` (hypervisor console), not `ttyS0`. If systemd getty is configured for the wrong console device, it won't work properly.

**For RISC-V SBI systems, the console is `hvc0` (not `ttyS0` or `ttyUSB0`).**

**Fix: Configure getty for hvc0 in chroot:**

**Step-by-step (do this after mounting loop device):**

```bash
# You should already have:
# - Loop device set up: LOOP_DEV=/dev/loop0
# - Image mounted: sudo mount -t ext4 $LOOP_DEV $MNT

# 1. Enter chroot
sudo chroot $MNT /bin/bash

# 2. Verify you're in the chroot (prompt should change)
# You should see something like: root@DESKTOP-SJAEBE7:/#
# The path should be / (root of the filesystem image)

# 3. First, check basic shell configuration
grep "^root:" /etc/passwd
# Should show: root:x:0:0:root:/root:/bin/bash
# If it shows /bin/sh or /bin/false, fix it:
chsh -s /bin/bash root

# 4. Verify bash exists and is executable
test -x /bin/bash && echo "bash OK" || echo "bash missing or not executable"
ls -l /bin/bash

# 5. Check what console services exist
systemctl list-units --type=service 2>/dev/null | grep getty || echo "systemd not fully configured yet"

# 6. Check current getty configuration
ls -la /etc/systemd/system/getty.target.wants/ 2>/dev/null || echo "No getty services found"

# 7. Enable getty for hvc0 (SBI console - REQUIRED for RISC-V)
systemctl enable serial-getty@hvc0.service 2>/dev/null || \
  ln -sf /lib/systemd/system/serial-getty@.service /etc/systemd/system/getty.target.wants/serial-getty@hvc0.service

# 8. Create service override to ensure proper configuration
mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/
cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
TTYPath=/dev/hvc0
StandardInput=tty
StandardOutput=tty
Restart=always
RestartSec=0
EOF

# 9. Verify the override was created
cat /etc/systemd/system/serial-getty@hvc0.service.d/override.conf

# 10. Check that the service symlink was created
ls -la /etc/systemd/system/getty.target.wants/ | grep hvc0

# 11. Exit chroot when done
exit
# Now back in host system

# 12. Unmount when finished (optional - if you're done making changes)
# sudo umount $MNT
```

**Verification Checklist (what you should see):**
- ✅ `grep "^root:" /etc/passwd` shows: `root:x:0:0:root:/root:/bin/bash`
- ✅ `test -x /bin/bash` returns: `bash OK`
- ✅ Symlink exists: `/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service`
- ✅ Override file exists: `/etc/systemd/system/serial-getty@hvc0.service.d/override.conf`

**Note about copy-paste:** If you're copying multi-line commands, make sure to paste the entire command including the backslash continuation (`\`) on the same line. The command should work even if the prompt formatting looks odd.

**If you see any errors:** Check that:
- The symlink was created: `ls -la /etc/systemd/system/getty.target.wants/ | grep hvc0`
- The override directory exists: `ls -d /etc/systemd/system/serial-getty@hvc0.service.d/`
- The override file has correct content: `cat /etc/systemd/system/serial-getty@hvc0.service.d/override.conf`

**Alternative: Boot with emergency/rescue mode to fix:**

If you can briefly interrupt the boot, try:
- Boot with `systemd.unit=rescue.target` in kernel cmdline to get emergency shell
- Or add `rd.break` to get early shell before systemd starts

**Note:** The `+q6E616D65` in boot output (if present) may indicate console encoding issues, but the primary issue is usually console device mismatch (hvc0 vs ttyS0).

### Kernel Oops in LiteETH Driver (Memory Access Fault)

**Symptom:**
- Boot log shows: `Oops - store (or AMO) access fault [#1]`
- `epc : liteeth_open+0x20/0x176` (crash in LiteETH driver open function)
- `badaddr: ffffffc800405010` (invalid memory address being accessed)
- `networking.service` fails to start
- Login works initially but may disconnect after network attempts

**Root Cause:**
The LiteETH driver is trying to access hardware registers that either:
- Are not properly mapped in the device tree
- Have incorrect base addresses
- The PHY chip (KSZ9031RNX) initialization is failing and causing a crash

**Solution:**

**Option 1: Disable automatic network bringup (quick fix to allow login):**

**From chroot (before booting, or if you can get into rescue mode):**

```bash
# Mount your rootfs image first
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Enter chroot
sudo chroot $MNT /bin/bash

# Inside chroot - disable networking service
systemctl disable networking.service
systemctl mask networking.service

# Also disable network-dependent services that might trigger the crash
systemctl disable dhcpcd.service 2>/dev/null || true
systemctl disable NetworkManager.service 2>/dev/null || true
systemctl disable systemd-networkd.service 2>/dev/null || true

# Exit chroot
exit

# Unmount
sudo umount $MNT
sudo losetup -d $LOOP_DEV
```

**From running system (if you can briefly get a shell):**

```bash
# Disable networking
systemctl disable networking.service
systemctl mask networking.service

# Disable other network services
systemctl disable dhcpcd.service 2>/dev/null || true
systemctl stop networking.service 2>/dev/null || true

# If systemd-networkd is running, disable it too
systemctl disable systemd-networkd.service 2>/dev/null || true
```

**Alternative: Edit network interfaces to disable eth0:**

```bash
# In chroot, edit /etc/network/interfaces
sudo chroot $MNT /bin/bash
cat > /etc/network/interfaces <<'EOF'
# Loopback only - no ethernet
auto lo
iface lo inet loopback

# Ethernet disabled to prevent crash
# auto eth0
# iface eth0 inet dhcp
EOF
exit
```

This prevents `networking.service` from automatically trying to bring up the interface on boot, which triggers the crash.

**Option 2: Check device tree configuration:**

The LiteETH base address in the device tree must match what's configured in LiteX. Check:

```bash
# From running system or in chroot
cat /proc/device-tree/soc/ethernet@*/reg
# Should show the LiteETH base address (e.g., 0xf0024000)

# Check what the kernel sees
dmesg | grep -i liteeth
# Should show: liteeth f0024000.mac eth0: irq 1 slots: tx 2 rx 2 size 2048
```

**Option 3: Verify PHY driver is compiled in kernel:**

```bash
# On build system, check kernel config
grep -E "CONFIG_MICREL_PHY|CONFIG_MDIO" .config
# Should show:
# CONFIG_MICREL_PHY=y
# CONFIG_MDIO_BUS=y
# CONFIG_MDIO_DEVICE=y
```

**Option 4: Check if MDIO bus is properly configured:**

The crash might be because the MDIO bus (for PHY communication) isn't working. Verify in device tree that:
- MDIO bus is present and has correct compatible string
- PHY node references the MDIO bus correctly
- PHY reg address matches hardware

**Option 5: Workaround - Use static IP and skip DHCP:**

If you need networking, try configuring a static IP instead of DHCP (which triggers the crash):

```bash
# Edit /etc/network/interfaces in chroot
cat >> /etc/network/interfaces <<'EOF'
# Static configuration to avoid DHCP crash
auto lo
iface lo inet loopback

# Disable eth0 auto-configuration for now
# auto eth0
# iface eth0 inet static
#   address 192.168.1.100
#   netmask 255.255.255.0
#   gateway 192.168.1.1
EOF

# Disable networking service temporarily
systemctl disable networking.service
```

**To diagnose further:**

1. **Check kernel messages:**
   ```bash
   dmesg | grep -i -E "liteeth|ethernet|phy|mdio" | tail -50
   ```

2. **Check if eth0 device exists:**
   ```bash
   ip link show
   # or
   ifconfig -a
   ```

3. **Try manually bringing up interface (may crash again):**
   ```bash
   ip link set eth0 up
   # If this crashes, the driver has a bug
   ```

**Most likely fix:** This usually requires:
1. Rebuilding LiteX with correct LiteETH configuration
2. Ensuring device tree matches LiteX hardware description
3. Verifying PHY/MDIO bus is correctly configured in device tree

For now, **Option 1 (disabling networking.service)** will allow you to boot and login successfully, though without network.

### Networking Works But No IP Address / DHCP Client Missing

**Symptom:** `eth0` is UP and shows carrier, but no IPv4 address assigned. `dhclient` or `udhcpc` commands are not found.

**Root Cause:** DHCP client package (`isc-dhcp-client`) was not installed during rootfs creation, so the system cannot request an IP address from DHCP server.

**Solution: Install DHCP client in rootfs image (from host machine):**

```bash
# Mount your rootfs image
cd ~/riscv_dev
export MNT=$PWD/mnt
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Install DHCP client in chroot
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/ 2>/dev/null || true
sudo chroot $MNT apt-get update
sudo chroot $MNT apt-get install -y isc-dhcp-client

# Unmount
sudo umount $MNT
sudo losetup -d $LOOP_DEV

# Copy updated rootfs to SD card (use Step 5 instructions to write to partition 2)
```

**After rebooting with updated rootfs:**

```bash
# On the FPGA board, DHCP should work automatically via networking.service
# Or manually request IP:
dhclient eth0
ip addr show eth0
```

**Alternative: Static IP (quick workaround without reinstalling rootfs):**

If you can't update the rootfs immediately, set a static IP:

```bash
# Set static IP manually (adjust IP and gateway to match your network)
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1

# Test connectivity
ping -c 3 192.168.1.1
```

**Note:** For direct laptop-to-FPGA connections (not through router), you may need to configure static IPs on both sides regardless of DHCP client availability.

### networking.service Failed / Ethernet "Cannot find device"

**Symptom:** `[FAILED] Failed to start networking.service - Raise network interfaces` or "Cannot find device" error when trying to start networking.

**Note:** If LiteX BIOS can get an IP address but Linux can't, this confirms the hardware (Ethernet MAC + PHY) is working correctly. The issue is in the Linux kernel configuration, not the hardware.

**Root Cause:** Missing Ethernet PHY driver in kernel configuration. The LiteETH driver is present, but it cannot communicate with the KSZ9031RNX PHY chip without the Micrel PHY driver.

**Why BIOS works but Linux doesn't:**
- **LiteX BIOS** has its own Ethernet initialization code that directly accesses hardware registers or uses a simple driver - it doesn't need the Linux PHY driver abstraction layer
- **Linux Kernel** requires proper PHY drivers (CONFIG_MICREL_PHY) to initialize and configure the PHY chip through the PHY abstraction layer
- BIOS proving the hardware works confirms the issue is purely missing kernel configuration, not hardware failure

**Solution:**
1. **Verify kernel has Ethernet drivers enabled:**
   ```bash
   cd litex-linux
   grep -E "CONFIG_LITEETH|CONFIG_MICREL_PHY|CONFIG_MDIO_BUS|CONFIG_MII" .config
   ```
   Should show:
   - `CONFIG_LITEETH=y`
   - `CONFIG_MICREL_PHY=y` ← **Critical, often missing**
   - `CONFIG_MDIO_BUS=y`
   - `CONFIG_MII=y`

2. **If Micrel PHY is missing, enable it (see Step 2 for full instructions):**
   ```bash
   sed -i 's/# CONFIG_MICREL_PHY is not set/CONFIG_MICREL_PHY=y/' .config
   sed -i 's/# CONFIG_MDIO_BUS is not set/CONFIG_MDIO_BUS=y/' .config
   sed -i 's/# CONFIG_MDIO_DEVICE is not set/CONFIG_MDIO_DEVICE=y/' .config
   sed -i 's/# CONFIG_MII is not set/CONFIG_MII=y/' .config
   ```

3. **Rebuild kernel:**
   ```bash
   make -j4 ARCH=riscv CROSS_COMPILE=$HOME/riscv/bin/riscv64-unknown-linux-gnu- all
   cp arch/riscv/boot/Image ../build/alinx_ax7203/linux_kernel
   # Copy to SD card and reboot
   ```

4. **On boot, verify Ethernet interface appears:**
   ```bash
   ip link show          # Should show eth0 or similar (not just lo)
   dmesg | grep -i phy   # Should show PHY detection messages
   dmesg | grep -i eth   # Should show LiteETH initialization
   ```

**Other checks:**
- Verify `/etc/network/interfaces` matches actual interface name (`eth0`, `eth1`, etc.)
- Check MDIO communication in kernel logs: `dmesg | grep -i mdio`
- Verify PHY chip initialization: `dmesg | grep -i "micrel\|ksz9031"`
- Check IP address configuration in `/etc/network/interfaces`

**Note:** This configuration is documented in Step 2, but if you built the kernel before enabling these options, you'll need to rebuild.

**Quick Fix (try this first):**

In chroot, create a simple test to verify login actually works:
```bash
# Create a test script that runs on login
echo '#!/bin/sh
echo "=== LOGIN SUCCESSFUL ===" > /tmp/login_success.txt
/bin/bash' > /root/.profile

chmod +x /root/.profile
```

**If that doesn't work, the issue is likely systemd getty. Disable automatic getty restart:**
```bash
# In chroot - modify getty service to not auto-restart
mkdir -p /etc/systemd/system/serial-getty@hvc0.service.d/
cat > /etc/systemd/system/serial-getty@hvc0.service.d/override.conf <<'EOF'
[Service]
Restart=no
StandardInput=tty
StandardOutput=tty
TTYReset=no
TTYVHangup=no
EOF
```

**Alternative: Bypass getty and use direct console:**
If getty is the problem, you can access the system via:
- Press `Ctrl+Alt+F1` (if supported)
- Or boot with `systemd.unit=rescue.target` in kernel cmdline to get emergency shell

---

## Troubleshooting (continued)

### "System hangs after Liftoff!"

**Check:**
```bash
# Verify kernel config
grep CONFIG_SERIAL_EARLYCON_RISCV_SBI=y linux/.config
grep CONFIG_RISCV_SBI_V01=y linux/.config

# Verify DTS bootargs
grep bootargs build/alinx_ax7203/linux.dts | grep earlycon=sbi

# Verify DTB bootargs
dtc -I dtb -O dts build/alinx_ax7203/linux.dtb | grep bootargs

# Rebuild if any are missing
```

### "No output at all"

**Check:**
- Serial cable connected correctly
- Baud rate 115200
- BIOS output appears before boot attempt
- Boot.json on SD card
- OpenSBI file size is ~274KB

### "Unable to mount root fs"

- Normal if no rootfs yet, but means OpenSBI → Linux handoff worked

### "Invalid Release file, no entry for main/binary-riscv64/Packages"

**IMPORTANT:** As of July 2023, RISC-V 64-bit is an official Debian architecture. Use the **main Debian archive**, not Debian Ports.

**Solution 1: Use main Debian archive (correct approach)**
```bash
# Install Debian archive keyring (not ports keyring)
sudo apt-get update
sudo apt-get install -y debian-archive-keyring

# Verify keyring exists
ls -la /usr/share/keyrings/debian-archive-keyring.gpg

# Bootstrap from main Debian archive
sudo debootstrap --arch=riscv64 --foreign --keyring /usr/share/keyrings/debian-archive-keyring.gpg \
    unstable $MNT http://deb.debian.org/debian

# Copy qemu for emulation
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/

# Complete the installation in the chroot
sudo DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    LC_ALL=C LANGUAGE=C LANG=C chroot $MNT /debootstrap/debootstrap --second-stage
```

**Solution 2: Try alternative suite (sid or stable)**
```bash
# Try 'sid' (same as unstable) or 'bookworm' (stable)
sudo debootstrap --arch=riscv64 --foreign sid $MNT http://deb.debian.org/debian
# or
sudo debootstrap --arch=riscv64 --foreign bookworm $MNT http://deb.debian.org/debian

sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/
sudo DEBIAN_FRONTEND=noninteractive chroot $MNT /debootstrap/debootstrap --second-stage
```

**Solution 3: Use Buildroot instead (if Debian continues to fail)**
```bash
# Buildroot creates a minimal rootfs without package manager
# See Option B in "If Root Filesystem Doesn't Exist" section above
```

---

## Expected Final Boot Sequence

```
Power On
  ↓
FPGA loads bitstream
  ↓
LiteX BIOS runs
  ↓
BIOS: "Copying Image to 0x40000000..."
BIOS: "Copying linux.dtb to 0x40ef0000..."
BIOS: "Copying opensbi.bin to 0x40f00000..."
BIOS: "Executing booted program at 0x40f00000"
  ↓
OpenSBI: "--============= Liftoff! ===============--"
OpenSBI: "OpenSBI v1.3.1 Platform Name: LiteX/VexRiscv-SMP"
  ↓
Linux: "[    0.000000] Linux version 6.1.0 ..."
Linux: "[    0.000000] early console: using RISC-V SBI"
Linux: "[    0.123456] printk: console [sbi] enabled"
... more boot messages ...
```

---

## Success Criteria

✅ **Phase 1: OpenSBI Working**
- See "Liftoff!" message
- See OpenSBI banner
- No immediate crash

✅ **Phase 2: Linux Early Boot**
- See Linux kernel version
- See "early console enabled"
- See "console [sbi] enabled"

✅ **Phase 3: Full Boot**
- Kernel finds devices
- Drivers load
- Rootfs mounts
- Login prompt appears

**If you see MMC/SD card driver panic after Phase 2:**

**Root Cause:** Address mismatch between DTS and actual LiteX hardware

**What happened:**
1. ✅ Boot files are correct (you got past Phase 1 and Phase 2!)
2. ✅ OpenSBI → Linux handoff worked  
3. ✅ Kernel is running and initializing drivers
4. ❌ MMC driver tries to access hardware at wrong address (DTS says `0xf0028000`, hardware is at `0xf0004000`)

**Why this happened:**
- You manually added SD card support to LiteX (copied from another board)
- LiteX hardware instantiated SD card at `0xf0004000` (check `build/alinx_ax7203/csr.csv`)
- But DTS template expects it at `0xf0028000` (check `build/alinx_ax7203/linux.dts` line 130)
- When Linux MMC driver probes hardware, it accesses wrong address → panic

**Quick Fix - Update DTS addresses:**

Looking at your `csr.csv` (line 12), the SD card hardware is at `0xf0004000`, but your DTS says `0xf0028000`. Fix:

```bash
cd build/alinx_ax7203

# Edit linux.dts
nano linux.dts  # or use your preferred editor

# Find the mmc0 section (around line 130)
# Change from:
#   mmc0: mmc@f0028000 {
#       reg = <0xf0028000 0x18>,    # Wrong address!
#             <0xf002801c 0xa8>,
#             ...
#
# To match csr.csv addresses:
#   mmc0: mmc@f0004000 {
#       reg = <0xf0004000 0x18>,    # phy (sdcard_phy_* registers)
#             <0xf000401c 0xa8>,    # core (sdcard_core_* registers)
#             <0xf0004048 0x9c>,    # reader (sdcard_block2mem_dma_*)
#             <0xf0004064 0x9c>,    # writer (sdcard_mem2block_dma_*)
#             <0xf0004080 0x4>;     # irq (sdcard_ev_* registers)
#
# Note: Exact register layout may need adjustment based on LiteX MMC module version
# Check csr.csv for exact register addresses

# Recompile DTB
dtc -I dts -O dtb -o linux.dtb linux.dts

# Copy new DTB to SD card
sudo umount /mnt/e 2>/dev/null || true
sudo mount -t drvfs E: /mnt/e
sudo cp linux.dtb /mnt/e/
sync
```

**Alternative: Temporarily disable MMC** to test boot without SD card:
```bash
# In linux.dts, change:
#   status = "disabled";  # Instead of "okay"
```

---

## Files Checklist

Before booting, verify you have:

- ✅ `build/alinx_ax7203/linux_kernel` (~5-10MB, **with SBI console**)
- ✅ `build/alinx_ax7203/linux.dtb` (~3KB, **with earlycon=sbi**)
- ✅ `opensbi/build/platform/litex/vexriscv/firmware/fw_jump.bin` (~274KB)
- ❓ `build/alinx_ax7203/rootfs` (optional for initial test)

---

## Quick Command Reference

```bash
# Check kernel config
grep -E "(CONFIG_SERIAL_EARLYCON_RISCV_SBI|CONFIG_RISCV_SBI_V01)" linux/.config

# Check DTS bootargs
grep bootargs build/alinx_ax7203/linux.dts

# Verify all boot files
ls -lh build/alinx_ax7203/linux_kernel opensbi/build/platform/litex/vexriscv/firmware/fw_jump.bin build/alinx_ax7203/linux.dtb

# Rebuild kernel
cd linux && make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j4

# Recompile DTB
dtc -I dts -O dtb -o build/alinx_ax7203/linux.dtb build/alinx_ax7203/linux.dts
```

---

## Next After Successful Boot

Once you see Linux booting successfully:

1. **Verify hardware**: Ethernet, SD card, UART all working
2. **Install software**: Package manager, utilities
3. **Deploy applications**: Your target application (e.g., Minima)
4. **Optimize**: Adjust clock speeds, memory usage
5. **Document**: Record what works and any issues

Good luck! 🚀
