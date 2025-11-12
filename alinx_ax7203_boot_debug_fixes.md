# Alinx AX7203 Boot Debug - Fixes Based on Reference

## Current Issue
**System hangs after OpenSBI "Liftoff!" with no kernel output**

## Key Finding from NaxRiscv Documentation
> "NaxRiscv is **image compatible** with linux-on-litex-vexriscv, you will have to adapt the dts/dtb (removing peripherals)."

This means:
- ✅ OpenSBI built for VexRiscv should work with NaxRiscv
- ✅ Kernel approach is correct
- ⚠️ Device tree may have issues or missing early console setup

## Critical Fixes to Try

### 1. Fix Memory Size Documentation (Already Correct in DTS)

The DTS currently has:
```dts
memory: memory@40000000 {
    reg = <0x40000000 0x40000000>;  // 1GB (0x40000000 = 1,073,741,824 bytes)
};
```

This is **correct for 1GB** as reported by BIOS. The documentation saying "512MB" is incorrect - update the boot guide.

### 2. Verify Early Console Configuration

The current bootargs are:
```
console=liteuart earlycon=liteuart,0xf0021000 rootwait root=/dev/mmcblk0p2
```

**Check:**
- Kernel must have `CONFIG_SERIAL_LITEUART=y` (early console support)
- Early console must be enabled in kernel config
- UART address must match: `0xf0021000`

### 3. Enable Early Printk in Kernel Config

The kernel needs to print messages during early boot. Check kernel config:

```bash
cd /home/riscv_dev/linux
make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- menuconfig
```

**Enable these options:**
- `Kernel hacking` → `Early printk` → `y`
- `Kernel hacking` → `Kernel low-level debugging functions` → `y`
- `Device Drivers` → `Character devices` → `Serial drivers` → `LiteX UART driver` → `y`
- Ensure `LiteX UART early console support` is enabled

### 4. Check Kernel Configuration Matches Reference

Compare your kernel `.config` with linux-on-litex-vexriscv's kernel config:

```bash
# Check what linux-on-litex-vexriscv uses
cat linux-on-litex-vexriscv/buildroot/board/litex_vexriscv/linux.config | grep -i "uart\|console\|early"
```

Key kernel config options needed:
```
CONFIG_SERIAL_LITEUART=y
CONFIG_SERIAL_LITEUART_CONSOLE=y
CONFIG_EARLY_PRINTK=y
CONFIG_PRINTK_TIME=y
```

### 5. Verify OpenSBI Platform Compatibility

You're using:
```bash
PLATFORM=litex/vexriscv
```

According to NaxRiscv docs, this should work, but verify the handoff:

OpenSBI expects:
- Kernel at `0x40000000`
- DTB at `0x40ef0000` (or passed via `a1` register)
- OpenSBI at `0x40f00000`

Your boot.json matches:
```json
{
    "Image": "0x40000000",
    "linux.dtb": "0x40ef0000",
    "opensbi.bin": "0x40f00000"
}
```

**But check:** OpenSBI might expect DTB address in register `a1`, or kernel might need different boot parameters.

### 6. Simplify Device Tree (Remove Unnecessary Peripherals)

As NaxRiscv docs suggest, try a **minimal DTS** with only essential peripherals:

```dts
/dts-v1/;

/ {
	compatible = "litex,vexriscv";
	model = "LiteX SoC";
	#address-cells = <1>;
	#size-cells    <1>;

	chosen {
		bootargs = "console=liteuart,0xf0021000 earlycon=liteuart,0xf0021000 rootwait root=/dev/mmcblk0p2";
	};

	memory@40000000 {
		device_type = "memory";
		reg = <0x40000000 0x40000000>;  // 1GB
	};

	cpus {
		#address-cells = <1>;
		#size-cells    <0>;
		timebase-frequency = <100000000>;
		cpu@0 {
			device_type = "cpu";
			compatible = "riscv";
			riscv,isa = "rv64i2p0_mafdc";
			mmu-type = "riscv,sv39";
			reg = <0>;
			clock-frequency = <100000000>;
			status = "okay";
			interrupt-controller {
				#interrupt-cells = <1>;
				interrupt-controller;
				compatible = "riscv,cpu-intc";
			};
		};
	};

	soc {
		#address-cells = <1>;
		#size-cells    <1>;
		compatible = "simple-bus";
		ranges;

		liteuart0: serial@f0021000 {
			compatible = "litex,liteuart";
			reg = <0xf0021000 0x100>;
			status = "okay";
		};

		mmc0: mmc@f0028000 {
			compatible = "litex,mmc";
			reg = <0xf0028000 0x18>,
			      <0xf002801c 0xa8>,
			      <0xf00280c4 0x9c>,
			      <0xf0028160 0x9c>,
			      <0xf00281fc 0x4>;
			reg-names = "phy", "core", "reader", "writer", "irq";
			bus-width = <0x04>;
			status = "okay";
		};
	};

	aliases {
		serial0 = &liteuart0;
	};
};
```

This removes:
- Ethernet (can add back later)
- Interrupt controller details
- Cache details
- Regulators

### 7. Check Kernel Boot Command Line

The kernel might need additional parameters. Compare with reference:

From linux-on-litex-vexriscv, bootargs typically include:
```
console=liteuart,0xf0021000 earlycon=liteuart,0xf0021000 rootwait root=/dev/mmcblk0p2
```

You might also need:
```
loglevel=8  # Show all kernel messages
```

### 8. Verify Kernel Image Format

Ensure the kernel is built correctly:
```bash
file build/alinx_ax7203/linux_kernel
```

Should show: `ELF 64-bit LSB executable, UCB RISC-V`

### 9. Test with Minimal Kernel Configuration

If still hanging, rebuild kernel with **defconfig + minimal LiteX support only**:

```bash
cd /home/riscv_dev/linux
make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig

# Enable ONLY these:
make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- menuconfig
# Enable:
# - Device Drivers → LiteX → LiteX SoC Controller
# - Character devices → Serial drivers → LiteX UART
# - Kernel hacking → Early printk
# - MMC/SD support → LiteX MMC

make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j$(nproc)
```

## Recommended Testing Order

1. **First**: Rebuild kernel with early printk enabled and verify config
2. **Second**: Try simplified DTS (remove Ethernet, keep only UART + SD card)
3. **Third**: Add `loglevel=8` to bootargs
4. **Fourth**: Check if kernel image format is correct

## Expected Boot Sequence

After OpenSBI "Liftoff!", you should see:
```
[    0.000000] Linux version 6.1.0 ...
[    0.000000] OF: fdt: Ignoring memory range 0x40f00000 - 0x41000000
[    0.000000] efi: UEFI not found.
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x40000000-0x7fffffff]
...
```

If you see **nothing**, the kernel isn't reaching early printk stage, which suggests:
- Kernel not loading correctly
- OpenSBI handoff failing
- Early console not initialized

## Debug Commands

### In BIOS, before boot:
```
litex> dmesg  # Check BIOS messages
litex> mem_list  # Verify memory map
litex> reboot  # Restart
```

### Check kernel config:
```bash
cd /home/riscv_dev/linux
grep -E "EARLY_PRINTK|LITEUART|CONSOLE" .config
```

### Verify OpenSBI:
```bash
file build/alinx_ax7203/opensbi.bin
# Should be RISC-V ELF binary
```

## Next Steps

1. Enable early printk and rebuild kernel
2. Try simplified DTS without Ethernet
3. Add debug bootargs (loglevel=8)
4. Verify all file formats are correct

If still hanging, check:
- Serial console baud rate (115200)
- UART initialization in kernel
- OpenSBI console output (should show something before kernel)
