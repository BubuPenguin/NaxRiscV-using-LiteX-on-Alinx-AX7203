# NaxRiscv Configuration for Alinx AX7203 Board

This document describes the configuration for running NaxRiscv CPU on the Alinx AX7203 FPGA development board using LiteX.

## Configuration Summary

This configuration is optimized for running modern software stacks (Linux, JVM) and high-performance workloads on the Alinx AX7203 board:

**CPU Configuration:**
- **Type:** NaxRiscv (high-performance CPU core)
- **Architecture:** 64-bit RISC-V (`--xlen=64`)
- **Variant:** Standard (balanced performance/resources)
- **CPU Count:** 1 core
- **L1 I-Cache:** 16 KB (64 sets, 64-byte blocks)
- **L1 D-Cache:** 16 KB (64 sets, 64-byte blocks)
- **L2 Cache:** 128 KB (256 sets, 64-byte blocks, unified)

**Instruction Set Extensions:**
- **RVC:** Enabled (compressed instructions for 20-30% code size reduction)
- **FPU:** Enabled (hardware floating-point unit for modern software)

**System Configuration:**
- **Clock Frequency:** 100 MHz (2x default, conservative for Artix-7 timing)
- **Bus Standard:** AXI (industry-standard, better IP compatibility)
- **Coherent DMA:** Enabled (automatic cache coherency for accelerators)

**Peripherals:**
- **Ethernet:** Enabled (KSZ9031RNX PHY with RGMII)
- **SD Card:** Enabled (4-bit SD mode for persistent storage)
- **SDRAM:** 512 MB DDR3 (MT41J256M16, default configuration)

**Build Tools:**
- **Toolchain:** Vivado (explicitly specified for Xilinx Artix-7 FPGA)

**Target Use Cases:**
- Running Linux on RISC-V
- Java/JVM applications (OpenJDK)
- Cryptocurrency/mining with accelerators
- Scientific computing
- Network services and embedded systems

---

## Build Command

```bash
python3 litex-boards/litex_boards/targets/alinx_ax7203.py --build --cpu-type=naxriscv --cpu-variant=standard --cpu-count=1 --xlen=64 --with-rvc --with-fpu --with-coherent-dma --bus-standard=axi --sys-clk-freq=100e6 --with-ethernet --with-sdcard --toolchain=vivado --with_user_accelerator
```

**Optional flags for loading/programming:**
- `--load`: Load bitstream to FPGA SRAM (volatile, for testing)
- `--flash`: Program bitstream to SPI flash (permanent, survives power-off)

**Usage after building:**
If you've already built the target, you can load or flash without rebuilding:

```bash
# Load to FPGA SRAM (temporary, for testing)
python litex-boards/litex_boards/targets/alinx_ax7203.py \
    --load \
    --cpu-type=naxriscv \
    --cpu-variant=standard \
    --cpu-count=1 \
    --xlen=64 \
    --with-rvc \
    --with-fpu \
    --with-coherent-dma \
    --bus-standard=axi \
    --sys-clk-freq=100e6 \
    --with-ethernet \
    --with-sdcard \
    --toolchain=vivado

# Or flash to SPI flash (permanent)
python litex-boards/litex_boards/targets/alinx_ax7203.py \
    --flash \
    --cpu-type=naxriscv \
    --cpu-variant=standard \
    --cpu-count=1 \
    --xlen=64 \
    --with-rvc \
    --with-fpu \
    --with-coherent-dma \
    --bus-standard=axi \
    --sys-clk-freq=100e6 \
    --with-ethernet \
    --with-sdcard \
    --toolchain=vivado
```

Note: The configuration flags (--cpu-type, --xlen, --bus-standard, etc.) are still needed when using --load or --flash alone because LiteX uses them to locate the correct bitstream file in the build directory.

---

### Usage After Building (Windows/WSL)

**Important:** When building in WSL (Windows Subsystem for Linux), it may be difficult to detect the FPGA from the WSL environment. To program the FPGA, you can use the Vivado GUI on Windows.

**Workflow:**

1. **Build in WSL:** Complete the build process using the build command shown above. This generates the bitstream file in the build directory.

2. **Locate the bitstream file:** After building, locate the generated bitstream file:
   - Path in WSL: `build/alinx_ax7203/gateware/top.bit`
   - Or look for `alinx_ax7203_operational.bin` 

3. **Copy to Windows:** Copy the bitstream file from WSL to a Windows-accessible location:
   ```bash
   # From WSL, copy to Windows path
   cp build/alinx_ax7203/gateware/top.bit /mnt/c/path/to/vivado/project/
   ```
   
   Or copy `alinx_ax7203_operational.bin` if that's the file generated:
   ```bash
   cp build/alinx_ax7203/gateware/alinx_ax7203_operational.bin /mnt/c/path/to/vivado/directory/
   ```

4. **Program via Vivado GUI:**
   
   **Option A: Program to FPGA SRAM (Volatile - Temporary)**
   - Open Vivado on Windows
   - Connect your Alinx AX7203 board via JTAG/USB
   - Use **Hardware Manager** in Vivado:
     - Click "Open Target" → "Auto Connect"
     - Select your FPGA device
     - Right-click the device → "Program Device"
     - Browse to the copied `.bit` or `.bin` file
     - Click "Program" to load the bitstream to FPGA SRAM
     - **Note:** This is volatile - the bitstream will be lost on power cycle

   **Option B: Flash to SPI Flash (Permanent - Survives Power-Off)**
   - Open Vivado on Windows
   - Connect your Alinx AX7203 board via JTAG/USB
   - Use **Hardware Manager** in Vivado:
     - Click "Open Target" → "Auto Connect"
     - Right-click the SPI flash memory device → "Program Flash Memory Device" (or "Program SPI Flash")
     - If prompted, select the memory part: **`mt25ql128-spi-x1_x2_x4`**
     - Browse to the copied `.bit` or `.bin` file
     - Configure flash settings if needed:
       - Memory part: `mt25ql128-spi-x1_x2_x4` (128 Mbit Micron SPI flash)
       - File type: Bitstream (`.bit`) or Binary (`.bin`)
     - Click "OK" or "Program" to flash the bitstream
     - Wait for programming to complete (may take several minutes)
   - **Note:** After flashing, power cycle the board and the design will automatically load from SPI flash on startup

**Alternative:** You can also copy the bitstream file to your Vivado installation directory or project folder on Windows, then use Vivado's GUI to program it.

**Note:** The `--load` and `--flash` flags will not work from WSL as they require direct hardware access. Always use Vivado GUI on Windows for programming when building in WSL.

---

## Default Values vs. Configuration Changes

### System Clock Frequency

**Default:** `50e6` (50 MHz)  
**Configured:** `100e6` (100 MHz)  
**Change:** 2x increase

**Reasoning:**
- 100 MHz is a conservative increase that should meet timing on the Artix-7 FPGA
---

### CPU Type

**Default:** None (must be specified)  
**Configured:** `naxriscv`  
**Change:** Explicitly specified

**Reasoning:**
- Suitable choice for applications requiring good performance (Linux, JVM, complex applications)
- Better suited than smaller cores like VexRiscv for 64-bit workloads

---

### CPU Variant

**Default:** `standard` (when NaxRiscv is selected)  
**Configured:** `standard`  
**Change:** None (using default)

**Reasoning:**
- Standard variant provides balanced performance and resource usage
- Suitable for most applications
- Includes standard instruction pipeline and cache configuration

---

### Data Width (XLEN)

**Default:** `32` (32-bit)  
**Configured:** `64` (64-bit)  
**Change:** 32-bit → 64-bit

**Reasoning:**
- **64-bit required for modern software:**
  - Java Virtual Machine (JVM) - OpenJDK for RISC-V requires 64-bit
  - Linux kernel - Full 64-bit Linux support
  - Modern applications expecting 64-bit address space
- **Memory addressing:** Can address >4GB of memory directly
- **Native 64-bit operations:** Better performance for cryptographic operations (SHA-3 accelerator), large integer math
- **Trade-off:** Approximately 2x FPGA resource usage compared to 32-bit, but necessary for target applications

---

### RISC-V Compressed Instructions (RVC)

**Default:** Disabled (`False`)  
**Configured:** Enabled (`--with-rvc`)  
**Change:** Disabled → Enabled

**Reasoning:**
- **Code size reduction:** Typically 20-30% smaller binaries
- **Better instruction cache utilization:** More instructions fit per cache line
- **Lower memory bandwidth:** Fewer instruction fetches from DRAM
- **Minimal resource overhead:** Compressed instruction decoder adds very little FPGA logic
- **Performance benefit:** Especially beneficial for embedded systems and applications with code size constraints

---

### Floating-Point Unit (FPU)

**Default:** Disabled (`False`)  
**Configured:** Enabled (`--with-fpu`)  
**Change:** Disabled → Enabled

**Reasoning:**
- **Required for modern software stacks:**
  - Java applications (JVM uses FPU extensively)
  - Scientific computing applications
  - Many standard libraries expect FPU support
- **Hardware acceleration:** Floating-point operations run much faster than software emulation
- **ABI compatibility:** Enables `lp64d` ABI (vs `lp64`) for proper floating-point calling conventions
- **Future-proofing:** Essential for running full-featured operating systems and applications

---

### Coherent DMA

**Default:** Disabled (`False`)  
**Configured:** Enabled (`--with-coherent-dma`)  
**Change:** Disabled → Enabled

**Reasoning:**
- **Essential for accelerators:**
  - SHA-3 accelerator (or other custom accelerators) can use DMA to move data
  - Automatic cache coherency between CPU and DMA transfers
- **Simplified software:**
  - No manual cache flush/invalidate operations required
  - CPU and DMA see consistent memory view automatically
- **Performance:**
  - Lower latency than non-coherent DMA
  - No software overhead for cache management
- **Reduced bugs:** Eliminates cache coherency issues that are hard to debug

---

### Bus Standard (AXI)

**Default:** `wishbone` (Wishbone bus)  
**Configured:** `axi` (`--bus-standard=axi`)  
**Change:** Wishbone → AXI

**Reasoning:**
- **NaxRiscv AXI support:** NaxRiscv has native AXI interface support
- **Industry standard:** AXI is widely used and well-supported in Xilinx FPGAs
- **Better compatibility:** Many third-party IP cores and accelerators use AXI interfaces

---

## Modifications to Board Config

The following peripherals were not originally supported in the LiteX-Boards AX7203 target.

### Ethernet Support

**Default:** Disabled  
**Configured:** Enabled (`--with-ethernet`)  
**Change:** Disabled → Enabled

**Reasoning:**
- **Network connectivity:**
  - Remote access via SSH
  - Network boot (TFTP) for loading OS/images
  - Downloading software packages
- **Development convenience:**
  - Faster file transfer than serial
  - Remote debugging capabilities
- **Production use:**
  - Network services
  - Remote monitoring
  - IoT/embedded network applications

**Hardware:** KSZ9031RNX PHY with RGMII interface

---

### SD Card Support

**Default:** Disabled  
**Configured:** Enabled (`--with-sdcard`)  
**Change:** Disabled → Enabled

**Reasoning:**
- **Persistent storage:**
  - Store coin ledger and transaction history
  - Boot from SD card for Linux distributions
  - Application data persistence
- **Development convenience:**
  - Easy to update root filesystem
  - No network required for file transfer
  - Faster than network boot for large files
- **Production use:**
  - Reliable data storage for blockchain/ledger applications
  - Non-volatile storage that survives power cycles

**Note:** Both SPI-mode (`--with-spi-sdcard`) and 4-bit SD mode (`--with-sdcard`) are supported. 4-bit SD mode is recommended for better performance.

**Hardware:** MicroSD card slot supporting both SPI and SD protocols

---

### Toolchain

**Default:** First available toolchain from platform (typically Vivado for Xilinx)  
**Configured:** `vivado` (explicitly specified)  
**Change:** Explicit specification

**Reasoning:**
- **Explicit control:** Ensures correct toolchain is used
- **Vivado required:** Alinx AX7203 uses Xilinx Artix-7 FPGA, which requires Vivado
- **Reproducibility:** Same toolchain used across builds

---

## Additional Defaults (Not Changed)

### SDRAM Configuration

**Module:** `MT41J256M16` (hardcoded in target)  
- **Capacity:** 512 MB DDR3
- **Rate:** 1:4 (DDR clock = 4x system clock)
- **Timings:** DDR3-1600 default speed grade

**Reasoning for not changing:**
- Matches the physical memory on the AX7203 board
- Sufficient for Linux/JVM workloads with 512 MB
- Standard DDR3 configuration appropriate for the application

---

### L2 Cache

**Default:** 128 KB, 8 ways  
**Not changed in this configuration**

**Reasoning:**
- Default L2 cache size is appropriate for most workloads
- 128 KB provides good hit rate without excessive resource usage
- Can be tuned if needed with `--l2-bytes` and `--l2-ways` flags

**Actual Configuration (from build output):**
- **L2 Cache:** 128 KB (131,072 bytes)
- **Organization:** 256 sets, 64-byte block size
- **Type:** Unified cache (shared instruction and data)

---

### L1 Caches

**Default:** Configured automatically by NaxRiscv  
**Not configurable via LiteX command-line flags**

**Reasoning:**
- L1 caches are internal to the NaxRiscv CPU core
- Size and configuration depend on CPU variant selected
- Standard variant provides balanced L1 cache sizes

**Actual Configuration (from build output):**
- **L1 Instruction Cache:** 16 KB (16,384 bytes)
  - Organization: 64 sets, 64-byte block size
  - Direct-mapped or low-associativity
- **L1 Data Cache:** 16 KB (16,384 bytes)
  - Organization: 64 sets, 64-byte block size
  - Direct-mapped or low-associativity

**Cache Hierarchy:**
```
NaxRiscv CPU Core
├─ L1 I-Cache: 16 KB (64 sets × 64 bytes)
└─ L1 D-Cache: 16 KB (64 sets × 64 bytes)
        ↓
   L2 Unified Cache: 128 KB (256 sets × 64 bytes)
        ↓
   DDR3 Controller
        ↓
   512 MB DDR3 Memory
```

---

### Integrated RAM

**Default:** None (uses external SDRAM)  
**Not changed in this configuration**

**Reasoning:**
- External SDRAM provides 512 MB capacity
- Integrated RAM unnecessary when SDRAM is available
- SDRAM provides much larger memory pool than on-chip BRAM

---

## Summary of Configuration Strategy

This configuration is optimized for:

1. **Running full operating systems** (Linux)
   - 64-bit required
   - FPU required
   - Sufficient DRAM (512 MB)

2. **Modern software stacks** (Java/JVM)
   - 64-bit architecture
   - FPU for floating-point operations
   - Coherent DMA for accelerator integration

3. **High-performance workloads**
   - 100 MHz CPU clock
   - RVC for code efficiency
   - L2 cache for memory performance

4. **Development integrity**
   - Ethernet for network access
   - SD card for persistent storage
   - Explicit toolchain specification

---

## Resource Usage Estimates

With this configuration, expect:

- **FPGA Resources:** Higher than 32-bit (approximately 2x for CPU core)
- **Memory:** 512 MB external SDRAM available
- **Performance:** ~100 MIPS at 100 MHz (64-bit RISC-V)
- **Power:** Moderate (100 MHz is reasonable for Artix-7)

---

## Recommended Use Cases

This configuration is ideal for:

- ✅ Running Linux on RISC-V
- ✅ Java applications (JVM with OpenJDK)
- ✅ Cryptocurrency/mining applications (with SHA-3 accelerator and ledger storage)
- ✅ Scientific computing
- ✅ Network services
- ✅ Embedded systems requiring full OS capabilities
- ✅ Applications requiring persistent storage (SD card)

---

## Potential Adjustments

Depending on your needs, consider:

- **Higher clock frequency:** `--sys-clk-freq=125e6` or `150e6` (requires timing verification)
- **JTAG debugging:** `--with-jtag-tap` or `--with-jtag-instruction` for hardware debugging
- **Larger L2 cache:** `--l2-bytes=262144` (256 KB) for better cache performance
- **Video output:** `--with-video-framebuffer` for HDMI graphics support
- **Multiple CPUs:** `--cpu-count=2` for multi-core (if resources allow)

---

## Build Output

After building, you'll find:

- **Gateware:** `build/alinx_ax7203/gateware/top.bit` (FPGA bitstream)
- **Software:** `build/alinx_ax7203/software/include/generated/` (CSR headers, memory map)
- **Documentation:** `build/alinx_ax7203/csr.json`, `csr.csv` (SoC register map)

---

## Next Steps

1. **Load bitstream:** Use `--load` flag or program FPGA manually
2. **Boot BIOS:** Connect via serial/UART to access BIOS prompt
3. **Load OS:** Use BIOS `boot` command to load Linux or other OS
4. **Develop:** Use generated headers (`csr.h`, `mem.h`) in your applications

---

*Generated for Alinx AX7203 with NaxRiscv CPU configuration*

