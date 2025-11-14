#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#define ACCEL_BASE 0xF0000000  // Check your csr.csv
#define ACCEL_CONTROL   (*(volatile uint32_t*)(ACCEL_BASE + 0x00))
#define ACCEL_STATUS    (*(volatile uint32_t*)(ACCEL_BASE + 0x04))
#define ACCEL_SRC_ADDR  (*(volatile uint32_t*)(ACCEL_BASE + 0x08))
#define ACCEL_DST_ADDR  (*(volatile uint32_t*)(ACCEL_BASE + 0x0C))
#define ACCEL_LENGTH    (*(volatile uint32_t*)(ACCEL_BASE + 0x10))
#define ACCEL_PROGRESS  (*(volatile uint32_t*)(ACCEL_BASE + 0x14))

// Read CPU cycle counter (RISC-V)
static inline uint64_t read_cycles(void) {
    uint64_t cycles;
    asm volatile ("rdcycle %0" : "=r" (cycles));
    return cycles;
}

void test_dma_speed(uint32_t transfer_size) {
    uint32_t *src = (uint32_t *)malloc(transfer_size);
    uint32_t *dst = (uint32_t *)malloc(transfer_size);
    
    // Initialize source data
    for (int i = 0; i < transfer_size/4; i++) {
        src[i] = i;
    }
    
    printf("\n=== DMA Speed Test ===\n");
    printf("Transfer size: %d bytes (%.2f KB, %.2f MB)\n", 
           transfer_size, 
           transfer_size/1024.0, 
           transfer_size/(1024.0*1024.0));
    
    // Configure accelerator
    ACCEL_SRC_ADDR = (uint32_t)src;
    ACCEL_DST_ADDR = (uint32_t)dst;
    ACCEL_LENGTH = transfer_size;
    
    // Start timing and operation
    uint64_t start_cycles = read_cycles();
    ACCEL_CONTROL = 0x1;  // Start
    
    // Poll for completion
    while (ACCEL_STATUS & 0x1);  // Wait while busy
    
    uint64_t end_cycles = read_cycles();
    uint64_t elapsed_cycles = end_cycles - start_cycles;
    
    // Calculate performance
    uint32_t sys_clk_freq = 100000000;  // 100 MHz (adjust for your system)
    double elapsed_sec = (double)elapsed_cycles / sys_clk_freq;
    double bandwidth_mbps = (transfer_size / elapsed_sec) / (1024.0 * 1024.0);
    double cycles_per_word = (double)elapsed_cycles / (transfer_size / 4);
    
    printf("\nResults:\n");
    printf("  Cycles elapsed:     %llu\n", elapsed_cycles);
    printf("  Time elapsed:       %.6f seconds\n", elapsed_sec);
    printf("  Bandwidth:          %.2f MB/s\n", bandwidth_mbps);
    printf("  Cycles per word:    %.2f\n", cycles_per_word);
    printf("  Bus utilization:    %.1f%%\n", 
           (400.0 / bandwidth_mbps) * 100.0);  // Theoretical max ~400 MB/s at 100MHz 32-bit
    
    // Verify correctness
    int errors = 0;
    for (int i = 0; i < transfer_size/4 && i < 10; i++) {
        if (src[i] != dst[i]) {
            printf("  ERROR at [%d]: 0x%08x != 0x%08x\n", i, src[i], dst[i]);
            errors++;
        }
    }
    
    if (errors == 0) {
        printf("  ✓ Data integrity: PASS\n");
    } else {
        printf("  ✗ Data integrity: FAIL\n");
    }
    
    free(src);
    free(dst);
}

int main(void) {
    // Test various transfer sizes
    printf("DMA Performance Characterization\n");
    printf("=================================\n");
    
    test_dma_speed(64);           // 64 bytes
    test_dma_speed(256);          // 256 bytes
    test_dma_speed(1024);         // 1 KB
    test_dma_speed(4096);         // 4 KB
    test_dma_speed(16384);        // 16 KB
    test_dma_speed(65536);        // 64 KB
    test_dma_speed(262144);       // 256 KB
    test_dma_speed(1048576);      // 1 MB
    
    return 0;
}