# NaxRiscv using LiteX on Alinx AX7203

This repository contains the configuration and software support for running the NaxRiscv CPU (64-bit multi-core RISC-V) on the Alinx AX7203 FPGA board (Artix-7 XC7A200T) using the LiteX SoC generator.

## Documentation

- **[NaxRiscv Configuration Guide](alinx_ax7203_naxriscv_config.md)**: Detailed reference for the build command flags, hardware configuration, and resource usage.
- **[Boot Guide](alinx_ax7203_boot_guide.md)**: Instructions for booting Linux, flashing bitstreams, and setting up the software environment.

## Integration with SHA3 Accelerator

This project is tailored to integrate with the hardware-accelerated SHA3/Keccak Proof-of-Work engine for Minima.

For the details, source code, and benchmarks of the accelerator itself, please refer to the dedicated repository:
👉 **[SHA3 TxPoW Accelerator](https://github.com/BubuPenguin/SHA3_TxPoW_Accelerator)**

The `versions/` directory in this repository contains snapshots of the SoC configuration with and without the accelerator integration for regression testing.
