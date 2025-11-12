# Alinx AX7203 Board Modifications - Ethernet and SD Card Support

This document details the exact code changes made to add Ethernet and SD Card support to the Alinx AX7203 board in the LiteX-Boards repository.

## Overview

The Alinx AX7203 board support in LiteX-Boards originally did **not** include Ethernet or SD Card support. These peripherals were manually added to this custom configuration to enable network connectivity and persistent storage capabilities.

## Files Modified

1. `litex-boards/litex_boards/platforms/alinx_ax7203.py` - Platform pin definitions
2. `litex-boards/litex_boards/targets/alinx_ax7203.py` - Target SoC configuration

---

## 1. Platform File Changes

**File:** `litex-boards/litex_boards/platforms/alinx_ax7203.py`

### 1.1 Ethernet Support Addition

**Location:** Lines 103-131

Added Ethernet PHY pin definitions for KSZ9031RNX chip with RGMII interface:

```python
# ================================================================================================
# ETHERNET SUPPORT - Added for KSZ9031RNX PHY (RGMII Interface)
# ================================================================================================
# Pin assignments from AX7203 board schematic:
# E1_GTXC (TX clock) = E18, E1_RXC (RX clock) = B17
# E1_TXD[3:0] = A18, A19, D20, C20 | E1_RXD[3:0] = C19, C18, B18, A16
# E1_TXEN (TX enable) = F18 | E1_RXDV (RX data valid) = A15
# E1_MDC = B16, E1_MDIO = B15, E1_RESET = D16
# ================================================================================================
("eth_clocks", 0,
    Subsignal("tx", Pins("E18")),  # E1_GTXC - RGMII TX clock
    Subsignal("rx", Pins("B17")),  # E1_RXC - RGMII RX clock
    IOStandard("LVCMOS33")
),
("eth", 0,
    Subsignal("rst_n",   Pins("D16")),                    # E1_RESET - PHY chip reset
    Subsignal("mdio",    Pins("B15")),                    # E1_MDIO - MDIO data
    Subsignal("mdc",     Pins("B16")),                    # E1_MDC - MDIO clock
    Subsignal("rx_ctl",  Pins("A15")),                    # E1_RXDV - RX data valid
    Subsignal("rx_data", Pins("A16 B18 C18 C19")),       # E1_RXD[0:3] - RX data bits
    Subsignal("tx_ctl",  Pins("F18")),                    # E1_TXEN - TX enable
    Subsignal("tx_data", Pins("C20 D20 A19 A18")),       # E1_TXD[0:3] - TX data bits
    IOStandard("LVCMOS33"),
    Misc("SLEW=FAST"),
    Drive(16),
),
# ================================================================================================
# END ETHERNET SUPPORT
# ================================================================================================
```

**Ethernet Clock Timing Constraints:** Lines 182-186

Added timing constraints for 125 MHz RGMII clocks:

```python
# ============================================================================================
# ETHERNET TIMING CONSTRAINTS - Added for RGMII 125MHz clock timing
# ============================================================================================
self.add_period_constraint(self.lookup_request("eth_clocks:tx", loose=True), 1e9/125e6)
self.add_period_constraint(self.lookup_request("eth_clocks:rx", loose=True), 1e9/125e6)
```

### 1.2 SD Card Support Addition

**Location:** Lines 133-156

Added both SPI-mode and 4-bit SD mode pin definitions:

```python
# ================================================================================================
# SDCARD SUPPORT - Added for MicroSD SPI mode support
# ================================================================================================
# Pin assignments from AX7203 board schematic:
# ================================================================================================
("spisdcard", 0,
    Subsignal("clk",  Pins("AB12")),  # SD_CLK 
    Subsignal("cs_n", Pins("AA14")),  # SD_DAT3 
    Subsignal("mosi", Pins("AB11"), Misc("PULLUP")),  # SD_CMD 
    Subsignal("miso", Pins("AA13"), Misc("PULLUP")),  # SD_DAT0 
    Misc("SLEW=FAST"),
    IOStandard("LVCMOS33")
),
("sdcard", 0,
    Subsignal("clk",  Pins("AB12")),  # SD_CLK
    Subsignal("cmd",  Pins("AB11"), Misc("PULLUP True")),  # SD_CMD
    Subsignal("data", Pins("AA13 AB13 Y13 AA14"), Misc("PULLUP True")),  # SD_DAT[0:3]
    Misc("SLEW=FAST"),
    IOStandard("LVCMOS33")
),
# ================================================================================================
# END SDCARD SUPPORT
# ================================================================================================
```

**Pin Mapping:**
- `clk` (AB12): SD Clock
- `cs_n` (AA14): SPI Chip Select / SD DAT3
- `mosi` (AB11): SPI Master Out / SD CMD
- `miso` (AA13): SPI Master In / SD DAT0
- `data[1]` (AB13): SD DAT1
- `data[2]` (Y13): SD DAT2
- `data[3]` (AA14): SD DAT3

---

## 2. Target File Changes

**File:** `litex-boards/litex_boards/targets/alinx_ax7203.py`

### 2.1 Ethernet Import

**Location:** Lines 29-33

Added import for Ethernet PHY:

```python
# ====================================================================================================
# ETHERNET SUPPORT - Added for ethernet PHY support
# ====================================================================================================
from liteeth.phy.s7rgmii import LiteEthPHYRGMII
# ====================================================================================================
```

### 2.2 Ethernet Parameter

**Location:** Line 72

Added `with_ethernet` parameter to BaseSoC:

```python
def __init__(self,
             sys_clk_freq           = int(200e6),
             with_led_chaser        = True,
             with_pcie              = False,
             with_video_framebuffer = False,
             with_ethernet          = False,  # <-- ETHERNET: Added parameter
             **kwargs):
```

### 2.3 Ethernet Instantiation

**Location:** Lines 137-147

Added Ethernet PHY instantiation in BaseSoC:

```python
# ============================================================================================
# ETHERNET SUPPORT - Added ethernet PHY instantiation
# ============================================================================================
if with_ethernet:
    # RGMII Ethernet PHY (KSZ9031RNX)
    # NOTE: Ensure ethernet pins are properly defined in the platform file before building
    self.ethphy = LiteEthPHYRGMII(
        clock_pads = self.platform.request("eth_clocks"),
        pads       = self.platform.request("eth"))
    self.add_ethernet(phy=self.ethphy)
# ============================================================================================
```

### 2.4 Ethernet CLI Argument

**Location:** Lines 164-168

Added `--with-ethernet` command-line argument:

```python
# ================================================================================================
# ETHERNET: Added command-line argument for ethernet support
# ================================================================================================
parser.add_target_argument("--with-ethernet",          action="store_true",          help="Enable Ethernet support.")
# ================================================================================================
```

### 2.5 Ethernet Argument Passing

**Location:** Line 181

Passed ethernet argument to BaseSoC:

```python
soc = BaseSoC(
    sys_clk_freq           = args.sys_clk_freq,
    with_led_chaser        = True,
    with_pcie              = args.with_pcie,
    with_video_framebuffer = args.with_video_framebuffer,
    with_ethernet          = args.with_ethernet,  # <-- ETHERNET: Added argument passing
    **parser.soc_argdict
)
```

### 2.6 SD Card CLI Arguments

**Location:** Lines 169-173

Added SD card command-line arguments:

```python
# ================================================================================================
# SDCARD: Added command-line arguments for SDCard support
# ================================================================================================
parser.add_target_argument("--with-spi-sdcard",       action="store_true",          help="Enable SPI-mode SDCard support.")
parser.add_target_argument("--with-sdcard",           action="store_true",          help="Enable 4-bit SD mode SDCard support.")
# ================================================================================================
```

### 2.7 SD Card Instantiation

**Location:** Lines 186-190

Added SD card instantiation:

```python
# SDCard -------------------------------------------------------------------------------------
if args.with_spi_sdcard:
    soc.add_spi_sdcard()
if args.with_sdcard:
    soc.add_sdcard()
```

---

## Summary of Changes

### Platform File (`platforms/alinx_ax7203.py`)
- **Ethernet:** Added 2 pin groups (`eth_clocks`, `eth`) with 12 total signal definitions
- **SD Card:** Added 2 pin groups (`spisdcard`, `sdcard`) with SPI and 4-bit SD mode support
- **Timing:** Added RGMII clock timing constraints

### Target File (`targets/alinx_ax7203.py`)
- **Imports:** Added `LiteEthPHYRGMII` import
- **Parameters:** Added `with_ethernet` parameter to BaseSoC
- **Hardware:** Instantiated Ethernet PHY when enabled
- **CLI Args:** Added `--with-ethernet`, `--with-spi-sdcard`, `--with-sdcard` flags
- **Integration:** Passed arguments and instantiated modules based on flags

---

## Testing

After these modifications, the board can be built with:

```bash
# With Ethernet and 4-bit SD mode
python3 litex-boards/litex_boards/targets/alinx_ax7203.py \
    --build \
    --cpu-type=naxriscv \
    --xlen=64 \
    --with-ethernet \
    --with-sdcard \
    --sys-clk-freq=100e6 \
    --toolchain=vivado

# Or with SPI-mode SD card
python3 litex-boards/litex_boards/targets/alinx_ax7203.py \
    --build \
    --cpu-type=naxriscv \
    --xlen=64 \
    --with-ethernet \
    --with-spi-sdcard \
    --sys-clk-freq=100e6 \
    --toolchain=vivado
```

---

## Known Issues / Notes

1. **Flash Size:** The platform currently sets flash size to 16MB in `write_cfgmem` commands, but the board uses a 256Mbit (32MB) flash. The `.bin` files are still compatible.

2. **Pin Verification:** SD card pins were assigned based on standard MicroSD socket layout. Physical board verification recommended.

3. **Performance:** 4-bit SD mode provides better performance than SPI mode for larger transfers.

---

*Last Updated: Based on LiteX-Boards commit adding Alinx AX7203 support (PR #678)*

