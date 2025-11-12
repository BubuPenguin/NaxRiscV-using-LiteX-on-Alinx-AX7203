# User Accelerator Implementation Guide

This document explains how to use the placeholder accelerator added to the Alinx AX7203 target board and how to replace it with your specific accelerator logic.

## Overview

A modular accelerator framework has been added with two files:

1. **`user_accelerator.py`** - Contains accelerator class definitions (this is where you add your logic)
2. **`litex-boards/litex_boards/targets/alinx_ax7203.py`** - Board target that imports and integrates the accelerator

The placeholder accelerator demonstrates:

1. **CSR Registers** - CPU control interface
2. **DMA Interface** - Direct memory access to DDR
3. **Interrupt Support** - Notification to CPU
4. **State Machine** - Example control flow

## Build Command

To build with the user accelerator enabled:

```bash
python3 litex-boards/litex_boards/targets/alinx_ax7203.py \
    --build \
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
    --with-user-accelerator \
    --toolchain=vivado
```

**Key flag:** `--with-user-accelerator` enables the custom accelerator.

## Generated Hardware

When enabled, the accelerator is synthesized with:

### Memory Map
- **CSR Base Address**: Auto-assigned in CSR region (check `build/alinx_ax7203/csr.csv`)
- **Registers**:
  - `user_accel_control` - Control register (offset 0x00)
  - `user_accel_status` - Status register (offset 0x04)
  - `user_accel_src_addr` - Source address (offset 0x08)
  - `user_accel_dst_addr` - Destination address (offset 0x0C)
  - `user_accel_length` - Transfer length (offset 0x10)
  - `user_accel_error` - Error code (offset 0x14)

### Interrupt
- **IRQ Line**: 16 (configurable in code)

### DMA Connection
- **Bus**: Connected to `dma_bus` (coherent with CPU cache when using `--with-coherent-dma`)
- **Data Width**: 32 bits (configurable in code)
- **Address Width**: 32 bits (byte-addressable)

## Software Access Example

After building, you can control the accelerator from software:

### C Example (Linux/Bare Metal)

```c
#include <generated/csr.h>

// Start the accelerator
void accel_start(uint32_t src, uint32_t dst, uint32_t len) {
    // Set up parameters
    user_accel_src_addr_write(src);
    user_accel_dst_addr_write(dst);
    user_accel_length_write(len);
    
    // Start operation (set bit 0)
    user_accel_control_write(1);
}

// Check if accelerator is busy
int accel_is_busy(void) {
    return user_accel_status_read() & 0x1;
}

// Check if accelerator is done
int accel_is_done(void) {
    return (user_accel_status_read() & 0x2) >> 1;
}

// Poll for completion
void accel_wait(void) {
    while (accel_is_busy()) {
        // Wait
    }
}

// Usage example
int main(void) {
    uint32_t src_addr = 0x40000000;  // DDR address
    uint32_t dst_addr = 0x40010000;  // DDR address
    uint32_t length = 1024;           // bytes
    
    // Start accelerator
    accel_start(src_addr, dst_addr, length);
    
    // Wait for completion
    accel_wait();
    
    // Check if done
    if (accel_is_done()) {
        printf("Accelerator completed successfully\n");
    }
    
    return 0;
}
```

## File Structure

```
riscv_dev/
├── user_accelerator.py              # ← Your accelerator classes (modify this!)
├── litex-boards/
│   └── litex_boards/
│       └── targets/
│           └── alinx_ax7203.py      # ← Board integration (imports from user_accelerator.py)
└── user_accelerator_usage.md        # ← This guide
```

### Benefits of This Structure

✅ **Modular**: Accelerator logic is separate from board definition  
✅ **Reusable**: Import your accelerator into any LiteX board target  
✅ **Version Control**: Easy to track changes to accelerator vs board config  
✅ **Testable**: Can test `user_accelerator.py` independently  
✅ **Maintainable**: Clear separation of concerns  
✅ **Multiple Options**: Include several accelerator implementations in one file

## Available Accelerator Templates

The `user_accelerator.py` file contains four example implementations:

### 1. UserAccelerator (Default)
- **Purpose**: Simple placeholder with counter FSM
- **Use Case**: Starting point for learning, minimal example
- **Features**: Basic CSR registers, interrupt, simple state machine

### 2. SimpleDMAEngine
- **Purpose**: Complete DMA memory copy engine
- **Use Case**: Reference for actual DMA read/write operations
- **Features**: Real memory access, proper Wishbone protocol, progress tracking

### 3. StreamProcessor
- **Purpose**: Stream-based data processing
- **Use Case**: Video processing, DSP, continuous data flow
- **Features**: Stream endpoints, pipeline-friendly interface

### 4. SHA3Accelerator
- **Purpose**: Cryptographic hash accelerator (SHA3/Keccak)
- **Use Case**: Hardware-accelerated hashing for blockchain, security applications
- **Features**: DMA input, multiple SHA3 modes (224/256/384/512-bit), Keccak state machine
- **Note**: Placeholder structure - requires full Keccak-f[1600] implementation

### Choosing an Accelerator

To switch between implementations, edit `alinx_ax7203.py` around line 174:

```python
# Option 1: Simple placeholder (default)
self.user_accel = UserAccelerator(data_width=32, address_width=32)

# Option 2: Complete DMA engine
# self.user_accel = SimpleDMAEngine(data_width=32, address_width=32)

# Option 3: Stream processor
# self.user_accel = StreamProcessor(data_width=32)

# Option 4: SHA3 hash accelerator
# self.user_accel = SHA3Accelerator(data_width=64, address_width=32)
```

## Replacing with Your Custom Accelerator

### Step 1: Modify an Existing Class or Create New One

In `user_accelerator.py`, find the `UserAccelerator` class. Replace the placeholder logic:

```python
class UserAccelerator(LiteXModule):
    def __init__(self, data_width=32, address_width=32):
        # Keep the CSR registers (or modify as needed)
        self.control    = CSRStorage(32)
        self.status     = CSRStatus(32)
        # ... add your custom CSRs ...
        
        # Keep the DMA interface
        self.wb_dma = wishbone.Interface(data_width=data_width, address_width=address_width)
        
        # Keep the interrupt
        self.interrupt = Signal()
        
        # ===== REPLACE THIS SECTION WITH YOUR LOGIC =====
        # Remove the placeholder FSM (lines 78-132)
        # Add your custom accelerator logic here:
        
        # Example: DMA Read Controller
        self.submodules.dma_reader = DMAReader(self.wb_dma)
        
        # Example: Your Processing Core
        self.submodules.my_core = MyProcessingCore()
        
        # Example: DMA Write Controller
        self.submodules.dma_writer = DMAWriter(self.wb_dma)
        
        # Connect your pipeline
        self.comb += [
            self.my_core.input.eq(self.dma_reader.output),
            self.dma_writer.input.eq(self.my_core.output),
        ]
        # ===============================================
```

### Step 2: Example - Simple Memory Copy DMA

Here's a more realistic DMA example:

```python
class SimpleDMA(LiteXModule):
    """Simple DMA engine that copies data from src to dst"""
    def __init__(self):
        self.control   = CSRStorage(32)
        self.status    = CSRStatus(32)
        self.src_addr  = CSRStorage(32)
        self.dst_addr  = CSRStorage(32)
        self.length    = CSRStorage(32)
        
        self.wb_dma = wishbone.Interface(data_width=32)
        self.interrupt = Signal()
        
        # Internal state
        src = Signal(32)
        dst = Signal(32)
        count = Signal(32)
        data = Signal(32)
        
        # FSM for DMA operation
        self.submodules.fsm = FSM(reset_state="IDLE")
        
        self.fsm.act("IDLE",
            If(self.control.storage[0],
                NextValue(src, self.src_addr.storage),
                NextValue(dst, self.dst_addr.storage),
                NextValue(count, 0),
                NextState("READ")
            )
        )
        
        self.fsm.act("READ",
            # Set up read request
            self.wb_dma.stb.eq(1),
            self.wb_dma.cyc.eq(1),
            self.wb_dma.we.eq(0),
            self.wb_dma.adr.eq(src[2:]),  # Word-aligned
            
            # Wait for ack
            If(self.wb_dma.ack,
                NextValue(data, self.wb_dma.dat_r),
                NextValue(src, src + 4),
                NextState("WRITE")
            )
        )
        
        self.fsm.act("WRITE",
            # Set up write request
            self.wb_dma.stb.eq(1),
            self.wb_dma.cyc.eq(1),
            self.wb_dma.we.eq(1),
            self.wb_dma.adr.eq(dst[2:]),
            self.wb_dma.dat_w.eq(data),
            self.wb_dma.sel.eq(0xF),
            
            # Wait for ack
            If(self.wb_dma.ack,
                NextValue(dst, dst + 4),
                NextValue(count, count + 4),
                If(count >= self.length.storage,
                    NextState("DONE")
                ).Else(
                    NextState("READ")
                )
            )
        )
        
        self.fsm.act("DONE",
            NextValue(self.interrupt, 1),
            NextState("IDLE")
        )
        
        # Status bits
        self.comb += self.status.status[0].eq(~self.fsm.ongoing("IDLE"))
```

### Step 3: Common Accelerator Patterns

#### Pattern 1: Stream Processing

```python
# For data streaming (e.g., video, DSP)
from litex.soc.interconnect import stream

class StreamAccelerator(LiteXModule):
    def __init__(self):
        # Stream input
        self.sink = stream.Endpoint([("data", 32)])
        
        # Your processing logic
        # ...
        
        # Stream output
        self.source = stream.Endpoint([("data", 32)])
```

#### Pattern 2: AXI Interface (for IP integration)

```python
from litex.soc.interconnect import axi

class AXIAccelerator(LiteXModule):
    def __init__(self):
        # AXI interface (instead of Wishbone)
        self.axi = axi.AXIInterface(data_width=64, address_width=32)
        
        # Your logic
        # ...
```

#### Pattern 3: Multi-Channel DMA

```python
class MultiChannelDMA(LiteXModule):
    def __init__(self, n_channels=4):
        self.dma_channels = []
        for i in range(n_channels):
            dma = SimpleDMA()
            setattr(self, f"dma{i}", dma)
            self.dma_channels.append(dma)
```

## Integration Tips

### 1. Adjust Data Width for Performance

```python
# In BaseSoC.__init__()
self.user_accel = UserAccelerator(
    data_width    = 128,  # Wider = more bandwidth
    address_width = 32
)
```

### 2. Verify CSR Addresses

After building, check `build/alinx_ax7203/csr.csv` for actual addresses:

```bash
grep user_accel build/alinx_ax7203/csr.csv
```

### 3. Test with LiteX BIOS

Before Linux, test via LiteX BIOS serial console:

```
litex> mem_write 0xF0000000 0x1  # Write to control register
litex> mem_read 0xF0000004       # Read status register
```

### 4. Handle Cache Coherency

With `--with-coherent-dma`:
- ✅ Cache coherency is automatic
- ✅ CPU and DMA see consistent data
- ✅ No manual cache flushes needed

Without coherent DMA:
- ⚠️ Must manually flush caches
- ⚠️ Use cache maintenance instructions

## Debugging

### Check Resource Usage

```bash
# After build, check utilization
grep -A 20 "Final Summary" build/alinx_ax7203/gateware/vivado.log
```

### View Generated Verilog

```bash
# Check generated RTL
ls build/alinx_ax7203/gateware/
cat build/alinx_ax7203/gateware/alinx_ax7203.v | grep user_accel
```

### Simulation

Add to your testbench:

```python
# In a separate test file
from migen.fhdl import verilog

dut = UserAccelerator()
print(verilog.convert(dut))
```

## Next Steps

1. **Build with placeholder**: Test that the build works
2. **Verify in hardware**: Load bitstream and test CSR access
3. **Replace logic**: Implement your specific accelerator
4. **Optimize**: Adjust data widths, add pipelining, etc.
5. **Benchmark**: Measure performance vs software implementation

## Resources

- **LiteX Documentation**: https://github.com/enjoy-digital/litex
- **Migen Documentation**: https://m-labs.hk/gateware/migen/
- **Wishbone Spec**: https://cdn.opencores.org/downloads/wbspec_b4.pdf
- **Your Board Guide**: `alinx_ax7203_boot_guide.md`

---

**Note**: The placeholder accelerator does nothing useful - it's just a counter. Replace it with your actual processing logic for real applications.

