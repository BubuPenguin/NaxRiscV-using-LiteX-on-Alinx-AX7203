# LiteX FPGA Accelerators Guide

Comprehensive guide to internal FPGA accelerators in LiteX: what's already available and how to add your own.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Currently Implemented Accelerators](#2-currently-implemented-accelerators)
3. [How to Add Custom Accelerators](#3-how-to-add-custom-accelerators)
4. [Integration Methods](#4-integration-methods)
5. [Complete Examples](#5-complete-examples)
6. [Best Practices](#6-best-practices)
7. [References](#7-references)

---

## 1. Overview

### Internal vs External Accelerators

| Type | Location | Interface | Use Case |
|------|----------|-----------|----------|
| **Internal** | FPGA fabric | Wishbone/AXI/CSR | On-chip acceleration |
| **External** | Host PC | PCIe DMA | Off-chip processing |

This guide focuses on **internal FPGA accelerators** that are synthesized within the FPGA fabric alongside your CPU.

### Key Benefits of Internal Accelerators

- ✅ **Low latency**: Direct access to on-chip memory (nanoseconds)
- ✅ **High bandwidth**: Full memory bandwidth (GB/s)
- ✅ **Tight integration**: Shares memory space with CPU
- ✅ **No external deps**: Self-contained SoC
- ✅ **Deterministic**: Predictable performance

---

## 2. Currently Implemented Accelerators

### 2.1 Video/Display Accelerators

#### **VideoS7HDMIPHY** (Xilinx 7-Series)

**Location**: `litex.soc.cores.video`

**Found in**:
- Digilent Nexys Video
- Digilent Genesys 2
- Various Xilinx evaluation boards

**What it does**:
- HDMI/DVI video output
- Framebuffer controller
- Video terminal (text mode)
- DMA from DRAM to display

**Example usage**:
```python
from litex.soc.cores.video import VideoS7HDMIPHY

class BaseSoC(SoCCore):
    def __init__(self, **kwargs):
        # Video PHY
        self.videophy = VideoS7HDMIPHY(
            platform.request("hdmi_out"), 
            clock_domain="hdmi"
        )
        
        # Framebuffer mode (DMA from memory to display)
        self.add_video_framebuffer(
            phy=self.videophy, 
            timings="800x600@60Hz", 
            clock_domain="hdmi"
        )
        
        # OR Terminal mode (text console)
        self.add_video_terminal(
            phy=self.videophy, 
            timings="800x600@60Hz"
        )
```

**Features**:
- Hardware video DMA
- Color space conversion
- Timing generator
- Multiple resolution support

---

### 2.2 USB Host Controller

#### **USBOHCI** (USB 1.1/2.0 Host)

**Location**: `litex.soc.cores.usb_ohci`

**Found in**:
- Digilent Nexys Video (with PMOD)
- Custom designs with USB PHY

**What it does**:
- USB host controller
- Internal DMA engine
- Interrupt handling
- Full/Low speed USB support

**Example usage**:
```python
from litex.soc.cores.usb_ohci import USBOHCI

self.submodules.usb_ohci = USBOHCI(
    self.platform, 
    self.platform.request("usb_pmodb_dual"), 
    usb_clk_freq=int(48e6)
)

# Memory-mapped control interface
self.bus.add_slave("usb_ohci_ctrl", 
                   self.usb_ohci.wb_ctrl, 
                   region=SoCRegion(origin=0x90000000, size=0x1000))

# Internal DMA bus for USB transfers
self.dma_bus.add_master("usb_ohci_dma", 
                        master=self.usb_ohci.wb_dma)

# Connect interrupt
self.comb += self.cpu.interrupt[16].eq(self.usb_ohci.interrupt)
```

**Features**:
- Hardware USB packet processing
- DMA scatter-gather
- Transaction scheduling
- Error handling

---

### 2.3 Memory Controllers

#### **LiteDRAM** (DDR/LPDDR/GDDR Controller)

**Location**: External package `litedram`

**Found in**: Almost all boards with external DRAM

**What it does**:
- DDR2/DDR3/DDR4 controller
- Multi-port arbitration
- Hardware L2 cache
- ECC support (some variants)

**Example usage**:
```python
from litedram.modules import MT41K128M16
from litedram.phy import s7ddrphy

# DDR PHY
self.ddrphy = s7ddrphy.A7DDRPHY(
    platform.request("ddram"),
    memtype      = "DDR3",
    nphases      = 4,
    sys_clk_freq = sys_clk_freq
)

# Add SDRAM controller
self.add_sdram("sdram",
    phy           = self.ddrphy,
    module        = MT41K128M16(sys_clk_freq, "1:4"),
    l2_cache_size = 8192  # Hardware L2 cache!
)
```

**Internal accelerator features**:
- **Hardware cache**: L2 cache in FPGA fabric
- **Multi-port arbiter**: Concurrent CPU + DMA access
- **Auto-refresh**: Background DRAM refresh
- **Address translation**: Virtual to physical mapping

---

### 2.4 Network Accelerators

#### **LiteEth** (Ethernet MAC)

**Location**: External package `liteeth`

**Found in**: Boards with Ethernet PHY

**What it does**:
- 10/100/1000 Mbps Ethernet MAC
- Hardware packet processing
- **Internal SRAM buffers** (CPU-managed, no DMA currently)
- UDP/IP offload (optional)

**Example usage**:
```python
from liteeth.phy.mii import LiteEthPHYMII

# Ethernet PHY
self.ethphy = LiteEthPHYMII(
    clock_pads = self.platform.request("eth_clocks"),
    pads       = self.platform.request("eth")
)

# Full Ethernet stack
self.add_ethernet(phy=self.ethphy)

# OR Etherbone (LiteX bridge over Ethernet)
self.add_etherbone(phy=self.ethphy)
```

**Features**:
- Hardware CRC calculation
- Packet filtering
- Internal SRAM packet buffers (typically 8KB total)
- Flow control

**Important Note**:
- **LiteEth does NOT currently have DMA support**
- Packets are stored in internal SRAM buffers
- CPU must copy data between SRAM and main DDR memory
- "Add DMA interface to MAC" is listed as a future improvement
- For high packet rates, CPU overhead can be significant

**Data Flow**:
```
RX: Network → PHY → MAC → SRAM → (CPU copies) → DDR
TX: DDR → (CPU copies) → SRAM → MAC → PHY → Network
```

---

### 2.5 Storage Accelerators

#### **LiteSATA** (SATA Controller)

**Location**: External package `litesata`

**Found in**: 
- Xilinx KCU105
- Digilent Nexys Video (with adapter)
- High-end development boards

**What it does**:
- SATA Gen1/Gen2/Gen3 controller
- Hardware command queuing
- DMA read/write
- FIS (Frame Information Structure) processing

**Example usage**:
```python
from litesata.phy import LiteSATAPHY

# SATA PHY
self.sata_phy = LiteSATAPHY(
    platform.device,
    refclk     = sata_refclk,
    pads       = platform.request("sata"),
    gen        = "gen2",
    clk_freq   = sys_clk_freq,
    data_width = 16
)

# SATA core with DMA
self.add_sata(phy=self.sata_phy, mode="read+write")
```

**Features**:
- Hardware command processing
- Native Command Queuing (NCQ)
- Link power management
- Error recovery

#### **LiteSDCard** (SD/MMC Controller)

**Location**: `litex.soc.cores.mmc` or external package

**Found in**: Many embedded boards

**What it does**:
- SD/SDIO/MMC interface
- Hardware CRC
- Block read/write
- DMA transfers

---

### 2.6 PCIe DMA Engine

#### **LitePCIe** (PCIe Endpoint)

**Location**: External package `litepcie`

**Found in**: 
- Alinx AX7203 (with `--with-pcie`)
- SQRL Acorn
- Xilinx KCU105
- All PCIe-capable boards

**What it does**:
- PCIe Gen1/Gen2/Gen3 endpoint
- Multiple DMA channels
- Memory-mapped I/O (MMIO)
- MSI/MSI-X interrupts

**Example usage**:
```python
from litepcie.phy.s7pciephy import S7PCIEPHY

# PCIe PHY
self.pcie_phy = S7PCIEPHY(
    platform, 
    platform.request("pcie_x4"),
    data_width = 128,
    bar0_size  = 0x20000
)

# Add PCIe with DMA
self.add_pcie(phy=self.pcie_phy, ndmas=1)  # 1 DMA channel
# OR multiple channels:
self.add_pcie(phy=self.pcie_phy, ndmas=4)  # 4 DMA channels
```

**Features**:
- Scatter-gather DMA
- Multiple concurrent transfers
- Hardware TLP (Transaction Layer Packet) processing
- Interrupt coalescing

**Note**: This is for **external host communication**, but the DMA engine itself is an internal FPGA accelerator.

---

### 2.7 Signal Processing

#### **LiteJESD204B** (High-Speed DAC/ADC Interface)

**Location**: External package `litejesd204b`

**Found in**: RF/SDR boards

**What it does**:
- JESD204B serial interface
- Multi-lane synchronization
- Frame alignment
- Link management

**Used for**: High-speed ADCs/DACs in software-defined radio (SDR) applications.

---

### 2.8 System Utilities

#### **LedChaser**

**Location**: `litex.soc.cores.led`

**Found in**: Almost every board

**What it does**: Simple LED animation (not really an accelerator, but a good example)

```python
from litex.soc.cores.led import LedChaser

self.leds = LedChaser(
    pads         = platform.request_all("user_led"),
    sys_clk_freq = sys_clk_freq
)
```

#### **ICAP** (FPGA Reconfiguration)

**Location**: `litex.soc.cores.icap`

**What it does**: Allows FPGA to reconfigure itself (reload bitstream)

---

## 3. How to Add Custom Accelerators

### 3.1 Basic Structure

Every accelerator has three main components:

```python
from migen import *
from litex.soc.interconnect.csr import *

class MyAccelerator(Module, AutoCSR):
    """Template for custom accelerator"""
    def __init__(self, data_width=32):
        # 1. Control/Status Registers (CPU interface)
        self.control = CSRStorage(32, description="Control register")
        self.status  = CSRStatus(32, description="Status register")
        
        # 2. Data interface (if needed)
        self.data_in  = CSRStorage(data_width)
        self.data_out = CSRStatus(data_width)
        
        # 3. Hardware logic (FSM, datapath, etc.)
        # Your accelerator implementation here
```

### 3.2 Integration into SoC

```python
class BaseSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, platform, sys_clk_freq, **kwargs)
        
        # Add accelerator
        self.submodules.my_accel = MyAccelerator()
        
        # CSR registers automatically mapped to memory space
        # CPU can access via memory-mapped I/O
```

---

## 4. Integration Methods

### 4.1 CSR Interface (Simple Control)

**Use case**: Simple accelerators with register-based control

**Pros**:
- ✅ Simple to implement
- ✅ Direct CPU access
- ✅ Good for configuration

**Cons**:
- ❌ Limited bandwidth
- ❌ CPU must poll for status
- ❌ Not suitable for bulk data

**Example**:
```python
class SimpleAccelerator(Module, AutoCSR):
    def __init__(self):
        # Control register bits
        self.control = CSRStorage(fields=[
            CSRField("start",  size=1, offset=0, description="Start operation"),
            CSRField("reset",  size=1, offset=1, description="Reset accelerator"),
            CSRField("mode",   size=2, offset=2, description="Operation mode"),
        ])
        
        # Status register
        self.status = CSRStatus(fields=[
            CSRField("busy",   size=1, offset=0, description="Operation in progress"),
            CSRField("done",   size=1, offset=1, description="Operation complete"),
            CSRField("error",  size=1, offset=2, description="Error occurred"),
        ])
        
        # Data registers
        self.input_data  = CSRStorage(32, description="Input data")
        self.output_data = CSRStatus(32, description="Output data")
```

**CPU access** (from software):
```c
// Memory-mapped access
#define ACCEL_BASE 0xF0020000

volatile uint32_t *accel_control = (uint32_t *)(ACCEL_BASE + 0x00);
volatile uint32_t *accel_status  = (uint32_t *)(ACCEL_BASE + 0x04);
volatile uint32_t *accel_input   = (uint32_t *)(ACCEL_BASE + 0x08);
volatile uint32_t *accel_output  = (uint32_t *)(ACCEL_BASE + 0x0C);

// Write input
*accel_input = 0x12345678;

// Start operation
*accel_control = 0x1;  // Set start bit

// Poll for completion
while (*accel_status & 0x1);  // Wait for not busy

// Read result
uint32_t result = *accel_output;
```

---

### 4.2 Wishbone Master (DMA Access)

**Use case**: Accelerators that need direct memory access

**Pros**:
- ✅ High bandwidth
- ✅ Can access DRAM directly
- ✅ No CPU involvement during transfer
- ✅ Suitable for bulk data

**Cons**:
- ❌ More complex to implement
- ❌ Need proper bus arbitration

**Example**:
```python
from litex.soc.interconnect import wishbone

class DMAAccelerator(Module, AutoCSR):
    def __init__(self):
        # CSR for control
        self.src_addr = CSRStorage(32, description="Source address")
        self.dst_addr = CSRStorage(32, description="Destination address")
        self.length   = CSRStorage(32, description="Transfer length")
        self.control  = CSRStorage(1,  description="Start transfer")
        self.status   = CSRStatus(1,   description="Done")
        
        # Wishbone master for DMA
        self.bus = wishbone.Interface()
        
        # FSM for DMA transfers
        self.submodules.fsm = FSM(reset_state="IDLE")
        
        read_data = Signal(32)
        byte_count = Signal(32)
        
        self.fsm.act("IDLE",
            If(self.control.storage,
                NextValue(byte_count, 0),
                NextState("READ")
            )
        )
        
        self.fsm.act("READ",
            # Read from source address
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            self.bus.we.eq(0),
            self.bus.adr.eq(self.src_addr.storage + byte_count),
            If(self.bus.ack,
                NextValue(read_data, self.bus.dat_r),
                NextState("PROCESS")
            )
        )
        
        self.fsm.act("PROCESS",
            # Process data (e.g., transform, filter, etc.)
            # ... your processing logic ...
            NextState("WRITE")
        )
        
        self.fsm.act("WRITE",
            # Write to destination address
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            self.bus.we.eq(1),
            self.bus.adr.eq(self.dst_addr.storage + byte_count),
            self.bus.dat_w.eq(read_data),  # Or processed data
            If(self.bus.ack,
                NextValue(byte_count, byte_count + 4),
                If(byte_count >= self.length.storage,
                    NextState("DONE")
                ).Else(
                    NextState("READ")
                )
            )
        )
        
        self.fsm.act("DONE",
            self.status.status.eq(1),
            NextState("IDLE")
        )

# Integration:
class BaseSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, **kwargs)
        
        self.submodules.dma_accel = DMAAccelerator()
        
        # Add as Wishbone master (can access memory)
        self.bus.add_master(name="dma_accel", 
                           master=self.dma_accel.bus)
```

---

### 4.3 Stream Interface (Pipeline Processing)

**Use case**: Data processing pipelines, video/audio processing

**Pros**:
- ✅ High throughput
- ✅ Natural for streaming data
- ✅ Easy to chain multiple stages
- ✅ Backpressure support

**Cons**:
- ❌ Requires stream sources/sinks
- ❌ Not suitable for random access

**Example**:
```python
from litex.soc.interconnect import stream

class StreamProcessor(Module):
    """Stream-based data processor"""
    def __init__(self, data_width=32):
        # Input stream
        self.sink = stream.Endpoint([
            ("data", data_width),
            ("valid", 1),
            ("last", 1)  # End of packet/frame
        ])
        
        # Output stream
        self.source = stream.Endpoint([
            ("data", data_width),
            ("valid", 1),
            ("last", 1)
        ])
        
        # Processing pipeline
        # Example: multiply by 2
        self.comb += [
            self.source.data.eq(self.sink.data * 2),
            self.source.valid.eq(self.sink.valid),
            self.source.last.eq(self.sink.last),
            self.sink.ready.eq(self.source.ready),
        ]

# Chain multiple processors:
class PipelineAccelerator(Module):
    def __init__(self):
        self.sink = stream.Endpoint([("data", 32)])
        self.source = stream.Endpoint([("data", 32)])
        
        # Multiple processing stages
        self.submodules.stage1 = StreamProcessor()
        self.submodules.stage2 = StreamProcessor()
        self.submodules.stage3 = StreamProcessor()
        
        # Pipeline: sink → stage1 → stage2 → stage3 → source
        self.comb += [
            self.sink.connect(self.stage1.sink),
            self.stage1.source.connect(self.stage2.sink),
            self.stage2.source.connect(self.stage3.sink),
            self.stage3.source.connect(self.source),
        ]
```

---

### 4.4 AXI Interface (Zynq Integration)

**Use case**: Integration with Xilinx Zynq/ZynqMP ARM cores

**Pros**:
- ✅ Standard ARM interface
- ✅ High performance
- ✅ Cache coherent options (ACP)
- ✅ Industry standard

**Cons**:
- ❌ Complex protocol
- ❌ Requires AXI to Wishbone bridge in LiteX

**Example**:
```python
from litex.soc.interconnect import axi

class AXIAccelerator(Module):
    def __init__(self):
        # AXI-Lite interface (for control)
        self.axi_lite = axi.AXILiteInterface(
            data_width    = 32,
            address_width = 32
        )
        
        # AXI interface (for DMA)
        self.axi = axi.AXIInterface(
            data_width    = 64,
            address_width = 32,
            id_width      = 4
        )
        
        # Your accelerator logic
        # ...

# Bridge to Wishbone (if not using Zynq):
class BaseSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, **kwargs)
        
        self.submodules.axi_accel = AXIAccelerator()
        
        # Bridge AXI to Wishbone
        self.submodules.axi2wb = axi.AXI2Wishbone(
            axi          = self.axi_accel.axi_lite,
            wishbone     = self.bus,
            base_address = 0xF0030000
        )
```

---

## 5. Complete Examples

### 5.1 Matrix Multiplier Accelerator

```python
from migen import *
from litex.soc.interconnect import wishbone
from litex.soc.interconnect.csr import *

class MatrixMultiplier(Module, AutoCSR):
    """
    Hardware matrix multiplier with DMA
    Computes C = A × B where all matrices are 4x4
    """
    def __init__(self):
        # Control registers
        self.matrix_a_addr = CSRStorage(32, description="Matrix A base address")
        self.matrix_b_addr = CSRStorage(32, description="Matrix B base address")
        self.matrix_c_addr = CSRStorage(32, description="Result matrix C address")
        self.control = CSRStorage(fields=[
            CSRField("start", size=1, description="Start computation"),
            CSRField("size",  size=4, description="Matrix size (NxN)"),
        ])
        self.status = CSRStatus(fields=[
            CSRField("busy", size=1, description="Computation in progress"),
            CSRField("done", size=1, description="Computation complete"),
        ])
        
        # Wishbone master for memory access
        self.bus = wishbone.Interface()
        
        # Internal storage
        matrix_a = Array([Signal(32, name=f"a{i}") for i in range(16)])
        matrix_b = Array([Signal(32, name=f"b{i}") for i in range(16)])
        matrix_c = Array([Signal(32, name=f"c{i}") for i in range(16)])
        
        read_count = Signal(8)
        write_count = Signal(8)
        
        # State machine
        self.submodules.fsm = FSM(reset_state="IDLE")
        
        self.fsm.act("IDLE",
            self.status.fields.done.eq(1),
            If(self.control.fields.start,
                NextValue(read_count, 0),
                NextValue(write_count, 0),
                NextState("READ_A")
            )
        )
        
        self.fsm.act("READ_A",
            self.status.fields.busy.eq(1),
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            self.bus.we.eq(0),
            self.bus.adr.eq(self.matrix_a_addr.storage + (read_count << 2)),
            If(self.bus.ack,
                NextValue(matrix_a[read_count], self.bus.dat_r),
                NextValue(read_count, read_count + 1),
                If(read_count == 15,
                    NextValue(read_count, 0),
                    NextState("READ_B")
                )
            )
        )
        
        self.fsm.act("READ_B",
            self.status.fields.busy.eq(1),
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            self.bus.we.eq(0),
            self.bus.adr.eq(self.matrix_b_addr.storage + (read_count << 2)),
            If(self.bus.ack,
                NextValue(matrix_b[read_count], self.bus.dat_r),
                NextValue(read_count, read_count + 1),
                If(read_count == 15,
                    NextState("COMPUTE")
                )
            )
        )
        
        self.fsm.act("COMPUTE",
            self.status.fields.busy.eq(1),
            # Matrix multiplication logic
            # For simplicity, this is a placeholder
            # Real implementation would use DSP slices or pipeline
            NextState("WRITE_C")
        )
        
        self.fsm.act("WRITE_C",
            self.status.fields.busy.eq(1),
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            self.bus.we.eq(1),
            self.bus.adr.eq(self.matrix_c_addr.storage + (write_count << 2)),
            self.bus.dat_w.eq(matrix_c[write_count]),
            If(self.bus.ack,
                NextValue(write_count, write_count + 1),
                If(write_count == 15,
                    NextState("IDLE")
                )
            )
        )

# Integration:
class BaseSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, **kwargs)
        
        # Add matrix multiplier
        self.submodules.matmul = MatrixMultiplier()
        
        # Connect to bus (can access DRAM)
        self.bus.add_master(name="matmul", master=self.matmul.bus)
```

**Software usage**:
```c
// Define matrix addresses in DRAM
#define MATRIX_A_ADDR 0x40100000
#define MATRIX_B_ADDR 0x40110000
#define MATRIX_C_ADDR 0x40120000

// Accelerator registers
#define MATMUL_BASE 0xF0020000
volatile uint32_t *matmul_a_addr = (uint32_t *)(MATMUL_BASE + 0x00);
volatile uint32_t *matmul_b_addr = (uint32_t *)(MATMUL_BASE + 0x04);
volatile uint32_t *matmul_c_addr = (uint32_t *)(MATMUL_BASE + 0x08);
volatile uint32_t *matmul_control = (uint32_t *)(MATMUL_BASE + 0x0C);
volatile uint32_t *matmul_status  = (uint32_t *)(MATMUL_BASE + 0x10);

// Initialize matrices in DRAM
float *matrix_a = (float *)MATRIX_A_ADDR;
float *matrix_b = (float *)MATRIX_B_ADDR;
// Fill matrix_a and matrix_b...

// Configure accelerator
*matmul_a_addr = MATRIX_A_ADDR;
*matmul_b_addr = MATRIX_B_ADDR;
*matmul_c_addr = MATRIX_C_ADDR;

// Start computation
*matmul_control = 0x11;  // start=1, size=4 (4x4 matrix)

// Wait for completion
while (*matmul_status & 0x1);  // Wait for not busy

// Result is now in MATRIX_C_ADDR
float *matrix_c = (float *)MATRIX_C_ADDR;
```

---

### 5.2 Image Filter Accelerator (Stream)

```python
from litex.soc.interconnect import stream
from migen import *

class ImageFilter(Module):
    """
    Real-time image filter (e.g., Gaussian blur, edge detection)
    Processes pixels as they stream through
    """
    def __init__(self, width=640):
        # Input/output streams (24-bit RGB)
        self.sink = stream.Endpoint([
            ("data", 24),    # RGB pixel
            ("hsync", 1),    # Horizontal sync
            ("vsync", 1),    # Vertical sync
            ("de", 1),       # Data enable
        ])
        
        self.source = stream.Endpoint([
            ("data", 24),
            ("hsync", 1),
            ("vsync", 1),
            ("de", 1),
        ])
        
        # Line buffers for 3x3 kernel
        self.line_buffer0 = Memory(24, width)
        self.line_buffer1 = Memory(24, width)
        
        # Read/write ports
        self.specials += self.line_buffer0, self.line_buffer1
        rd_port0 = self.line_buffer0.get_port(write_capable=False)
        rd_port1 = self.line_buffer1.get_port(write_capable=False)
        wr_port0 = self.line_buffer0.get_port(write_capable=True)
        wr_port1 = self.line_buffer1.get_port(write_capable=True)
        self.specials += rd_port0, rd_port1, wr_port0, wr_port1
        
        # Pixel position counter
        x_count = Signal(max=width)
        
        # 3x3 window of pixels
        pixels = Array([Signal(24) for _ in range(9)])
        
        # Extract RGB components from center pixel
        r = Signal(8)
        g = Signal(8)
        b = Signal(8)
        self.comb += [
            r.eq(pixels[4][0:8]),
            g.eq(pixels[4][8:16]),
            b.eq(pixels[4][16:24]),
        ]
        
        # Simple box blur (average of 3x3 neighborhood)
        r_sum = Signal(12)
        g_sum = Signal(12)
        b_sum = Signal(12)
        
        # Sum all pixels in 3x3 window
        self.comb += [
            r_sum.eq(sum([pixels[i][0:8] for i in range(9)])),
            g_sum.eq(sum([pixels[i][8:16] for i in range(9)])),
            b_sum.eq(sum([pixels[i][16:24] for i in range(9)])),
        ]
        
        # Divide by 9 (approximate with shift right by 3 for simplicity)
        r_avg = Signal(8)
        g_avg = Signal(8)
        b_avg = Signal(8)
        self.comb += [
            r_avg.eq(r_sum >> 3),
            g_avg.eq(g_sum >> 3),
            b_avg.eq(b_sum >> 3),
        ]
        
        # Output filtered pixel
        self.comb += [
            self.source.data.eq(Cat(r_avg, g_avg, b_avg)),
            self.source.hsync.eq(self.sink.hsync),
            self.source.vsync.eq(self.sink.vsync),
            self.source.de.eq(self.sink.de),
            self.source.valid.eq(self.sink.valid),
            self.sink.ready.eq(self.source.ready),
        ]

# Integration with video pipeline:
class VideoSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, **kwargs)
        
        # Video input (camera, framebuffer, etc.)
        # Video PHY
        self.videophy = VideoS7HDMIPHY(...)
        
        # Image filter
        self.submodules.filter = ImageFilter(width=800)
        
        # Connect: video_in → filter → video_out
        self.comb += [
            video_input.connect(self.filter.sink),
            self.filter.source.connect(video_output),
        ]
```

---

### 5.3 AES Crypto Accelerator

```python
from migen import *
from litex.soc.interconnect.csr import *

class AESAccelerator(Module, AutoCSR):
    """
    AES-128 encryption accelerator
    Simple interface for symmetric encryption
    """
    def __init__(self):
        # Control/status registers
        self.key = CSRStorage(128, description="128-bit encryption key")
        self.plaintext = CSRStorage(128, description="128-bit plaintext input")
        self.ciphertext = CSRStatus(128, description="128-bit ciphertext output")
        
        self.control = CSRStorage(fields=[
            CSRField("encrypt", size=1, description="Start encryption"),
            CSRField("decrypt", size=1, description="Start decryption"),
        ])
        
        self.status = CSRStatus(fields=[
            CSRField("busy", size=1, description="Operation in progress"),
            CSRField("done", size=1, description="Operation complete"),
        ])
        
        # AES core (simplified - real implementation more complex)
        # This would contain:
        # - Key expansion logic
        # - S-box substitution
        # - ShiftRows, MixColumns
        # - AddRoundKey operations
        
        # For demonstration, placeholder FSM
        self.submodules.fsm = FSM(reset_state="IDLE")
        
        round_count = Signal(4)
        
        self.fsm.act("IDLE",
            self.status.fields.done.eq(1),
            If(self.control.fields.encrypt,
                NextValue(round_count, 0),
                NextState("KEY_EXPANSION")
            )
        )
        
        self.fsm.act("KEY_EXPANSION",
            # Expand encryption key
            NextState("ENCRYPT_ROUND")
        )
        
        self.fsm.act("ENCRYPT_ROUND",
            self.status.fields.busy.eq(1),
            # Perform one AES round
            # SubBytes, ShiftRows, MixColumns, AddRoundKey
            NextValue(round_count, round_count + 1),
            If(round_count == 10,  # AES-128 has 10 rounds
                NextState("DONE")
            )
        )
        
        self.fsm.act("DONE",
            # Copy result to ciphertext register
            NextState("IDLE")
        )

# Usage:
class SecureSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, **kwargs)
        
        # Add AES accelerator
        self.submodules.aes = AESAccelerator()
```

**Software usage**:
```c
#define AES_BASE 0xF0030000

volatile uint32_t *aes_key       = (uint32_t *)(AES_BASE + 0x00);
volatile uint32_t *aes_plaintext = (uint32_t *)(AES_BASE + 0x10);
volatile uint32_t *aes_ciphertext= (uint32_t *)(AES_BASE + 0x20);
volatile uint32_t *aes_control   = (uint32_t *)(AES_BASE + 0x30);
volatile uint32_t *aes_status    = (uint32_t *)(AES_BASE + 0x34);

// Set encryption key (128 bits = 4x 32-bit words)
aes_key[0] = 0x2b7e1516;
aes_key[1] = 0x28aed2a6;
aes_key[2] = 0xabf71588;
aes_key[3] = 0x09cf4f3c;

// Set plaintext
aes_plaintext[0] = 0x3243f6a8;
aes_plaintext[1] = 0x885a308d;
aes_plaintext[2] = 0x313198a2;
aes_plaintext[3] = 0xe0370734;

// Start encryption
*aes_control = 0x1;  // encrypt bit

// Wait for completion
while (*aes_status & 0x1);  // Wait for not busy

// Read ciphertext
uint32_t encrypted[4];
encrypted[0] = aes_ciphertext[0];
encrypted[1] = aes_ciphertext[1];
encrypted[2] = aes_ciphertext[2];
encrypted[3] = aes_ciphertext[3];
```

---

### 5.4 FFT Accelerator (DSP-Heavy)

```python
from migen import *
from litex.soc.interconnect import stream
from litex.soc.interconnect.csr import *

class FFTAccelerator(Module, AutoCSR):
    """
    Fast Fourier Transform accelerator
    Uses DSP48 slices for multiply-accumulate
    """
    def __init__(self, n_points=1024):
        # Control registers
        self.control = CSRStorage(fields=[
            CSRField("start", size=1, description="Start FFT"),
            CSRField("inverse", size=1, description="Inverse FFT (IFFT)"),
        ])
        
        self.status = CSRStatus(fields=[
            CSRField("busy", size=1),
            CSRField("done", size=1),
            CSRField("overflow", size=1, description="Overflow detected"),
        ])
        
        # Input buffer address
        self.input_addr = CSRStorage(32, description="Input buffer address")
        self.output_addr = CSRStorage(32, description="Output buffer address")
        
        # Wishbone master for memory access
        self.bus = wishbone.Interface()
        
        # Internal buffers (dual-port RAM)
        # Real/Imaginary parts
        self.buffer_real = Memory(32, n_points)
        self.buffer_imag = Memory(32, n_points)
        
        # FFT stages (butterfly operations)
        # This is a simplified placeholder
        # Real FFT would use:
        # - Radix-2/4 butterflies
        # - Twiddle factor ROM
        # - Bit-reversal addressing
        # - Multiple DSP48 slices for parallel computation
        
        # State machine
        self.submodules.fsm = FSM(reset_state="IDLE")
        
        stage = Signal(max=10)  # log2(1024) = 10 stages
        index = Signal(max=n_points)
        
        self.fsm.act("IDLE",
            self.status.fields.done.eq(1),
            If(self.control.fields.start,
                NextValue(stage, 0),
                NextValue(index, 0),
                NextState("LOAD_INPUT")
            )
        )
        
        self.fsm.act("LOAD_INPUT",
            # DMA input data from memory
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            # ... load data ...
            If(index == n_points - 1,
                NextState("COMPUTE_FFT")
            )
        )
        
        self.fsm.act("COMPUTE_FFT",
            self.status.fields.busy.eq(1),
            # Perform FFT butterfly operations
            # This would use DSP48 slices for complex multiply
            # ... FFT computation ...
            If(stage == 9,  # 10 stages complete
                NextState("STORE_OUTPUT")
            )
        )
        
        self.fsm.act("STORE_OUTPUT",
            # DMA output data to memory
            self.bus.cyc.eq(1),
            self.bus.stb.eq(1),
            self.bus.we.eq(1),
            # ... store data ...
            NextState("IDLE")
        )

# Integration:
class DSPSoC(SoCCore):
    def __init__(self, **kwargs):
        SoCCore.__init__(self, **kwargs)
        
        # Add FFT accelerator
        self.submodules.fft = FFTAccelerator(n_points=1024)
        
        # Connect to memory bus
        self.bus.add_master(name="fft", master=self.fft.bus)
```

---

## 6. Best Practices

### 6.1 Design Guidelines

#### ✅ DO:

1. **Use CSRs for control**
   - Simple, standardized interface
   - Automatic address mapping
   - Easy CPU access

2. **Implement proper handshaking**
   - busy/done flags
   - Error reporting
   - Interrupt support (when needed)

3. **Add hardware interlocks**
   - Prevent invalid states
   - Protect against race conditions
   - Validate inputs in hardware

4. **Optimize for throughput**
   - Pipeline deep paths
   - Use DSP slices for arithmetic
   - Minimize memory accesses

5. **Test thoroughly**
   - Write testbenches
   - Verify FSM coverage
   - Test edge cases

#### ❌ DON'T:

1. **Don't block the CPU bus**
   - Use DMA for bulk transfers
   - Implement timeouts
   - Return control quickly

2. **Don't assume memory is fast**
   - Cache frequently accessed data
   - Burst transfers when possible
   - Hide latency with pipelining

3. **Don't ignore timing**
   - Meet clock constraints
   - Pipeline long paths
   - Use proper clock crossing

4. **Don't waste resources**
   - Share logic when possible
   - Use block RAM efficiently
   - Consider resource usage early

---

### 6.2 Performance Optimization

#### Memory Bandwidth

```python
# BAD: Single-word transfers
for i in range(1000):
    data = read_memory(addr + i*4)
    process(data)
    write_memory(result_addr + i*4, result)

# GOOD: Burst transfers
burst_read(addr, buffer, 1000)
for i in range(1000):
    buffer[i] = process(buffer[i])
burst_write(result_addr, buffer, 1000)
```

#### Pipelining

```python
class PipelinedAccelerator(Module):
    def __init__(self):
        # BAD: Single-cycle operation (long critical path)
        result = Signal(32)
        self.comb += result.eq((input_a * input_b) + (input_c * input_d))
        
        # GOOD: Pipelined operation (shorter critical path)
        stage1_a = Signal(32)
        stage1_b = Signal(32)
        stage2 = Signal(32)
        
        self.sync += [
            # Stage 1: Multiply
            stage1_a.eq(input_a * input_b),
            stage1_b.eq(input_c * input_d),
            # Stage 2: Add
            stage2.eq(stage1_a + stage1_b),
            # Stage 3: Output
            result.eq(stage2),
        ]
```

#### Resource Utilization

```python
# Use DSP48 slices for multiply:
from migen.genlib.misc import WaitTimer

# Xilinx DSP48 inference
product = Signal(32)
self.sync += product.eq(a * b)  # Infers DSP48

# Use Block RAM for buffers:
buffer = Memory(32, 1024)  # Infers BRAM
```

---

### 6.3 Debugging Tips

#### 1. Add Debug Registers

```python
class DebugAccelerator(Module, AutoCSR):
    def __init__(self):
        # Normal registers
        self.control = CSRStorage(32)
        
        # Debug registers (optional, ifdef DEBUG)
        self.debug_state = CSRStatus(4, description="FSM state")
        self.debug_counter = CSRStatus(32, description="Operation counter")
        self.debug_error = CSRStatus(8, description="Last error code")
```

#### 2. Use Simulation

```python
# test_accelerator.py
from migen.sim import run_simulation

def testbench(dut):
    # Write control register
    yield dut.control.storage.eq(0x1)
    yield
    
    # Wait for done
    for _ in range(100):
        status = yield dut.status.status
        if status & 0x2:  # Done bit
            break
        yield
    
    # Check result
    result = yield dut.output_data.status
    assert result == expected_value

# Run simulation
run_simulation(MyAccelerator(), testbench(dut), vcd_name="accel.vcd")
```

#### 3. Integrate Logic Analyzer

```python
# Add LiteScope for hardware debugging
from litescope import LiteScopeAnalyzer

analyzer_signals = [
    self.accelerator.fsm.state,
    self.accelerator.bus.cyc,
    self.accelerator.bus.stb,
    self.accelerator.bus.ack,
]

self.submodules.analyzer = LiteScopeAnalyzer(
    analyzer_signals,
    depth=1024,
    clock_domain="sys"
)
```

---

## 7. References

### Official Documentation

- **LiteX Documentation**: https://github.com/enjoy-digital/litex/wiki
- **Migen Documentation**: https://m-labs.hk/migen/manual/
- **LiteX Cores**: https://github.com/enjoy-digital/litex

### Example Repositories

- **LiteX-Boards**: https://github.com/litex-hub/litex-boards
- **LiteX Examples**: https://github.com/enjoy-digital/litex/tree/master/litex/soc/cores
- **LiteDRAM**: https://github.com/enjoy-digital/litedram
- **LiteEth**: https://github.com/enjoy-digital/liteeth
- **LitePCIe**: https://github.com/enjoy-digital/litepcie
- **LiteSATA**: https://github.com/enjoy-digital/litesata

### Community Resources

- **LiteX Discord**: https://discord.gg/litex
- **LiteX Forum**: https://github.com/enjoy-digital/litex/discussions

### Academic Papers

- **"LiteX: An Open-Source SoC Builder"** - Florent Kermarrec
- **"Migen: A Python Toolbox for Building Complex Digital Hardware"**

---

## Appendix A: Quick Reference

### Common CSR Patterns

```python
# Read-only status
self.status = CSRStatus(32)

# Write-only control
self.control = CSRStorage(32)

# With bit fields
self.reg = CSRStorage(fields=[
    CSRField("field1", size=8, offset=0),
    CSRField("field2", size=8, offset=8),
])

# Auto-pulsed (self-clearing)
self.trigger = CSRStorage(1, reset=0)
```

### Wishbone Master Template

```python
self.bus = wishbone.Interface()

# Read cycle
self.comb += [
    self.bus.cyc.eq(1),
    self.bus.stb.eq(1),
    self.bus.we.eq(0),
    self.bus.adr.eq(address),
]
# Check self.bus.ack for completion
# Read data from self.bus.dat_r

# Write cycle
self.comb += [
    self.bus.cyc.eq(1),
    self.bus.stb.eq(1),
    self.bus.we.eq(1),
    self.bus.adr.eq(address),
    self.bus.dat_w.eq(data),
]
```

### Stream Interface Template

```python
from litex.soc.interconnect import stream

self.sink = stream.Endpoint([("data", 32)])
self.source = stream.Endpoint([("data", 32)])

# Connect
self.comb += [
    self.source.data.eq(self.sink.data),
    self.source.valid.eq(self.sink.valid),
    self.sink.ready.eq(self.source.ready),
]
```

---

## Appendix B: Memory Map Example

Typical memory map for SoC with accelerators:

```
0x00000000 - 0x0001FFFF : ROM (128 KB)
0x00020000 - 0x0002FFFF : SRAM (64 KB)
0x40000000 - 0x5FFFFFFF : SDRAM (512 MB)

0xF0000000 - 0xF0000FFF : UART
0xF0001000 - 0xF0001FFF : Timer
0xF0002000 - 0xF0002FFF : Ethernet MAC
0xF0003000 - 0xF0003FFF : SD Card

0xF0020000 - 0xF0020FFF : Matrix Accelerator (CSR)
0xF0021000 - 0xF0021FFF : AES Accelerator (CSR)
0xF0022000 - 0xF0022FFF : FFT Accelerator (CSR)
0xF0023000 - 0xF0023FFF : Custom Accelerator (CSR)
```

---

**Last Updated**: 2025-11-09

**Version**: 1.0

**Author**: LiteX Community

---

Happy accelerating! 🚀

