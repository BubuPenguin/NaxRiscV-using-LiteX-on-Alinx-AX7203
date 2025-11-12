# Ethernet Configuration and Troubleshooting - Alinx AX7203

**Hardware:** Alinx AX7203 FPGA board with LiteX SoC  
**Ethernet MAC:** LiteX LiteETH  
**Ethernet PHY:** KSZ9031RNX (Micrel)  

## Hardware Description

### Ethernet Components

1. **LiteETH MAC (Media Access Controller)**
   - Open-source Ethernet MAC implementation for LiteX
   - Located at base address: `0xf0002000` (check `csr.csv` for your build)
   - Register size: `0x40` (64 bytes)
   - Interrupt: IRQ 3
   - Buffer: Located at `0x80000000`, size `0x2000` (8KB)
   - Configuration:
     - RX slots: 2
     - TX slots: 2
     - Slot size: 2048 bytes

2. **KSZ9031RNX PHY (Physical Layer)**
   - Micrel/Microchip Ethernet PHY chip
   - 10/100/1000 Mbps capable
   - Uses MDIO (Management Data Input/Output) interface for configuration
   - MDIO base address: `0xf0002800` (check `csr.csv`)
   - MDIO register size: `0x10` (16 bytes)
   - PHY ID: `0x0022a162`

3. **MDIO Bus**
   - Used for communication between MAC and PHY
   - Allows reading/writing PHY registers
   - Required for PHY initialization and link status

## Kernel Configuration Requirements

### Required Kernel Options

The following kernel configuration options must be enabled for Ethernet to work:

```bash
# Ethernet support
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_LITEX=y
CONFIG_LITEX_LITEETH=y           # LiteETH driver

# PHY support
CONFIG_PHYLIB=y                  # PHY abstraction layer
CONFIG_MICREL_PHY=y              # KSZ9031RNX PHY driver (CRITICAL!)
CONFIG_MDIO_BUS=y                # MDIO bus support
CONFIG_MDIO_DEVICE=y             # MDIO device support
CONFIG_MII=y                     # MII interface support
```

### How to Enable

```bash
cd litex-linux

# Enable Micrel PHY driver (required for KSZ9031RNX)
sed -i 's/# CONFIG_MICREL_PHY is not set/CONFIG_MICREL_PHY=y/' .config

# Enable MDIO bus support
sed -i 's/# CONFIG_MDIO_BUS is not set/CONFIG_MDIO_BUS=y/' .config
sed -i 's/# CONFIG_MDIO_DEVICE is not set/CONFIG_MDIO_DEVICE=y/' .config

# Enable MII interface
sed -i 's/# CONFIG_MII is not set/CONFIG_MII=y/' .config

# Verify
grep -E "CONFIG_MICREL_PHY|CONFIG_MDIO_BUS|CONFIG_MII|CONFIG_LITEETH" .config
```

### Note on CONFIG_MICREL_PHY

**This is the most critical missing configuration.** Without it:
- Ethernet interface may not appear
- `networking.service` fails with "Cannot find device"
- PHY cannot be detected or initialized

**Why BIOS works but Linux doesn't:**
- LiteX BIOS has its own Ethernet initialization code that directly accesses hardware
- Linux requires proper PHY drivers through the PHY abstraction layer
- BIOS proving hardware works confirms the issue is kernel configuration, not hardware failure

## Device Tree Configuration

### Correct Device Tree Structure

The device tree must match the actual hardware addresses from `csr.csv`. **This is critical!**

```dts
mac0: mac@f0002000 {
    compatible = "litex,liteeth";
    reg = <0xf0002000 0x40>,      /* MAC registers - CHECK csr.csv for actual address! */
          <0xf0002800 0x10>,      /* MDIO registers - CHECK csr.csv for actual address! */
          <0x80000000 0x2000>;    /* Buffer memory */
    reg-names = "mac", "mdio", "buffer";
    litex,rx-slots = <2>;
    litex,tx-slots = <2>;
    litex,slot-size = <2048>;
    interrupts = <3>;
    status = "okay";
};
```

### How to Get Correct Addresses

**Always check `csr.csv` file from your LiteX build:**

```bash
cat build/alinx_ax7203/csr.csv | grep -i "eth\|mac"
```

Look for:
- `csr_base,ethmac,0xf0002000,,` → MAC base address
- `csr_base,ethphy,0xf0002800,,` → MDIO/PHY base address

### Common Mistake: Wrong Addresses

**Problem:** Device tree had wrong addresses:
- MAC: `0xf0024000` ❌ (should be `0xf0002000` ✅)
- MDIO: `0xf0025000` ❌ (should be `0xf0002800` ✅)

**Result:** Kernel oops when trying to bring up interface:
```
Oops - store (or AMO) access fault [#1]
epc : liteeth_open+0x20/0x176
badaddr: ffffffc800405010
```

**Solution:** Always verify addresses in device tree match `csr.csv` before compiling DTB.

### MDIO Bus Configuration

The LiteETH driver appears to handle MDIO/PHY detection automatically if the register space is correctly defined. An explicit MDIO bus node may not be required, but the MDIO register space must be specified in the `reg` property with `reg-names = "mdio"`.

## Problems Encountered and Solutions

### Problem 1: Kernel Oops in LiteETH Driver

**Symptom:**
```
[ 1622.869036] Oops - store (or AMO) access fault [#1]
[ 1622.890143] epc : liteeth_open+0x20/0x176
[ 1622.972116] badaddr: ffffffc800405010
Segmentation fault: ip link set eth0 up
```

**Root Cause:**
- Device tree had incorrect hardware addresses
- MAC address was `0xf0024000` but actual hardware is at `0xf0002000`
- MDIO address was `0xf0025000` but actual hardware is at `0xf0002800`
- Driver tried to access invalid memory locations → crash

**Solution:**
1. Check `csr.csv` for actual hardware addresses
2. Update device tree to match:
   ```dts
   mac0: mac@f0002000 {  /* Changed from f0024000 */
       reg = <0xf0002000 0x40>,   /* Changed from f0024000 */
             <0xf0002800 0x10>,   /* Changed from f0025000 */
             <0x80000000 0x2000>;
   ```
3. Recompile DTB: `dtc -I dts -O dtb -o linux.dtb linux.dts`
4. Copy to SD card and reboot

**Result:** Interface can be brought up without crash.

### Problem 2: networking.service Failed / "Cannot find device"

**Symptom:**
```
[FAILED] Failed to start networking.service - Raise network interfaces
Cannot find device eth0
```

**Root Cause:**
- Missing `CONFIG_MICREL_PHY=y` in kernel configuration
- PHY cannot be detected/initialized
- Ethernet interface never appears

**Solution:**
- Enable `CONFIG_MICREL_PHY=y` in kernel `.config`
- Rebuild kernel
- Interface should appear: `ip link show eth0`

### Problem 3: No IP Address / DHCP Client Missing

**Symptom:**
- `eth0` is UP and shows carrier (`LOWER_UP`)
- No IPv4 address assigned
- `dhclient` command not found

**Root Cause:**
- `isc-dhcp-client` package not installed in rootfs
- System cannot request IP address from DHCP server

**Solution:**

**During rootfs creation (recommended):**
```bash
# In chroot during Step 4
apt-get -y install openssh-server openntpd net-tools isc-dhcp-client
```

**After rootfs creation:**
```bash
# Mount rootfs image
LOOP_DEV=$(sudo losetup --partscan --find --show debian-sid-risc-v-root.img)
sudo mount -t ext4 $LOOP_DEV $MNT

# Install in chroot
sudo cp /usr/bin/qemu-riscv64-static $MNT/usr/bin/
sudo chroot $MNT apt-get update
sudo chroot $MNT apt-get install -y isc-dhcp-client

# Unmount and copy to SD card
sudo umount $MNT
sudo losetup -d $LOOP_DEV
```

**Alternative: Static IP (for direct laptop-to-FPGA connections):**
```bash
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
```

### Problem 4: Direct Connection Issues (Laptop-to-FPGA)

**Symptom:**
- FPGA shows `LOWER_UP` (link detected)
- Windows shows "Disconnected" on Ethernet adapter
- Ping fails both directions
- IP addresses configured but no connectivity

**Root Cause:**
- Auto-negotiation issues between FPGA PHY and Windows Ethernet adapter
- Direct connections without switch/router can have link negotiation problems
- Windows may not properly detect the link

**Possible Solutions:**

1. **Use a router/switch** (recommended):
   - Connect both devices to a network switch or router
   - Better auto-negotiation handling
   - DHCP server available

2. **Enable Internet Connection Sharing on Windows:**
   - Settings → Network & Internet → Mobile hotspot
   - Or: Control Panel → Network and Sharing Center → Change adapter settings
   - Right-click WiFi adapter → Properties → Sharing tab
   - Enable "Allow other network users to connect"
   - Windows will provide DHCP

3. **Try different Ethernet cable:**
   - Some cables may have auto-negotiation issues
   - Try a known-good cable

4. **Configure static IPs on both sides:**
   - FPGA: `192.168.1.100/24`
   - Windows Ethernet: `192.168.1.101/24`
   - May still have link detection issues even with static IPs

**Status:** Link negotiation between FPGA PHY and Windows adapter may require router/switch or additional PHY configuration.

## Verification and Testing

### Check Interface Status

```bash
# Check if interface exists and is UP
ip link show eth0

# Should show:
# eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
# LOWER_UP means physical link is detected
```

### Check PHY Detection

```bash
# Check kernel messages for PHY detection
dmesg | grep -i "phy\|mdio\|ethernet" | tail -20

# Check carrier (link) status
cat /sys/class/net/eth0/carrier
# Output: 1 = link detected, 0 = no link
# Note: Returns "Invalid argument" if interface is DOWN
#       LiteETH may not populate /sys/class/net/eth0/phydev/ even when working
```

**Note on LiteETH PHY Detection:**
- LiteETH may not fully integrate with Linux's standard PHY subsystem sysfs interface
- `/sys/class/net/eth0/phydev/` may not exist even when PHY is working
- The `carrier` file requires the interface to be UP (`ip link set eth0 up`) to read
- Check interface state with `ip link show eth0` - `LOWER_UP` flag indicates physical link

### Verify Device Tree is Loaded

```bash
# Check if MAC node exists in running device tree
ls -la /proc/device-tree/soc/mac@f0002000/

# Check MAC address
cat /proc/device-tree/soc/mac@f0002000/reg
```

### Test Network Connectivity

```bash
# Request IP via DHCP
dhclient eth0

# Check assigned IP
ip addr show eth0

# Test connectivity
ping -c 3 8.8.8.8
ping -c 3 <gateway_ip>
```

## Current Status

### ✅ What Works

- Kernel driver loads without crash
- Interface appears: `eth0` shows up in `ip link show`
- Interface can be brought UP: `ip link set eth0 up` works
- Physical link detected: `LOWER_UP` status, carrier = 1
- No kernel oops when accessing interface

### ⚠️ Known Issues / Limitations

1. **Direct laptop-to-FPGA connection:**
   - Link negotiation issues between FPGA PHY and Windows Ethernet adapter
   - Windows may show "Disconnected" even though FPGA detects link
   - Connectivity may require router/switch between devices

2. **PHY status information:**
   - `ethtool eth0` command not available (package not installed)
   - `/sys/class/net/eth0/speed` and `/sys/class/net/eth0/duplex` return "Invalid argument"
   - PHY may not be fully reporting link parameters

3. **DHCP on direct connections:**
   - Direct laptop-to-FPGA connections have no DHCP server
   - Must use static IPs or enable Internet Connection Sharing on Windows

### 🔧 Recommendations

1. **For testing/debugging:**
   - Connect FPGA to network router/switch instead of directly to laptop
   - Better auto-negotiation and DHCP support

2. **For production:**
   - Use static IPs if direct connection is required
   - Consider adding `ethtool` package to rootfs for link debugging
   - May need to add explicit PHY configuration in device tree if auto-detection fails

3. **Device tree maintenance:**
   - **Always check `csr.csv`** before updating device tree addresses
   - Document address mappings if hardware changes
   - Verify addresses after each LiteX rebuild

## Key Takeaways

1. **Device tree addresses MUST match `csr.csv`** - Wrong addresses cause kernel crashes
2. **`CONFIG_MICREL_PHY=y` is critical** - Without it, PHY cannot be detected
3. **MDIO register space must be defined** - Even if no explicit MDIO node, register space is needed
4. **Direct connections can have negotiation issues** - Use router/switch when possible
5. **Install `isc-dhcp-client` in rootfs** - Required for automatic IP address assignment

## References

- LiteX LiteETH: https://github.com/enjoy-digital/liteeth
- KSZ9031RNX Datasheet: Microchip/Micrel documentation
- Linux PHY subsystem: Kernel documentation
- Device Tree Specification: https://www.devicetree.org/

## Troubleshooting Checklist

- [ ] Kernel config has `CONFIG_MICREL_PHY=y`
- [ ] Kernel config has `CONFIG_MDIO_BUS=y`
- [ ] Device tree MAC address matches `csr.csv` (`csr_base,ethmac`)
- [ ] Device tree MDIO address matches `csr.csv` (`csr_base,ethphy`)
- [ ] DTB was recompiled after DTS changes
- [ ] New DTB copied to SD card boot partition
- [ ] Interface appears: `ip link show eth0`
- [ ] Interface can be brought UP: `ip link set eth0 up` (no crash)
- [ ] Carrier detected: `cat /sys/class/net/eth0/carrier` shows `1`
- [ ] DHCP client installed: `which dhclient` or `which udhcpc`
- [ ] Network cable connected
- [ ] If direct connection, static IPs configured on both sides


CURRENTLY WORKING STUFF:
- Kernel driver loads without crash
- Interface appears: `eth0` shows up in `ip link show`
- Interface can be brought UP: `ip link set eth0 up` works
- Physical link detected: `LOWER_UP` status, carrier = 1
- Kernel build already includes `CONFIG_LITEETH`, `CONFIG_MICREL_PHY`, `CONFIG_MDIO_BUS`, `CONFIG_MDIO_DEVICE`, and `CONFIG_MII`
- Device tree addresses for MAC/MDIO/buffer match `csr.csv` (`mac@0xf0002000`, `mdio@0xf0002800`, buffer `0x80000000`)
- Rootfs networking stack (`ifupdown`, `dhclient`, `/etc/network/interfaces`) starts correctly and launches DHCP attempts
- No kernel oops when accessing interface