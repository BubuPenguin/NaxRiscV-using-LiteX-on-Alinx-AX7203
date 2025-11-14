#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ========== Software SHA3-256 Implementation ==========
#define SHA3_256_RATE 136

static const uint64_t keccakf_rndc[24] = {
    0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
    0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
    0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
    0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
    0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
    0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
    0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
    0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};

static const int keccakf_rotc[24] = {
    1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14,
    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
};

static const int keccakf_piln[24] = {
    10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4,
    15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1
};

#define ROTL64(x, y) (((x) << (y)) | ((x) >> (64 - (y))))

static void keccakf(uint64_t st[25]) {
    uint64_t t, bc[5];
    for (int round = 0; round < 24; round++) {
        for (int i = 0; i < 5; i++)
            bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
        for (int i = 0; i < 5; i++) {
            t = bc[(i + 4) % 5] ^ ROTL64(bc[(i + 1) % 5], 1);
            for (int j = 0; j < 25; j += 5)
                st[j + i] ^= t;
        }
        t = st[1];
        for (int i = 0; i < 24; i++) {
            int j = keccakf_piln[i];
            bc[0] = st[j];
            st[j] = ROTL64(t, keccakf_rotc[i]);
            t = bc[0];
        }
        for (int j = 0; j < 25; j += 5) {
            for (int i = 0; i < 5; i++)
                bc[i] = st[j + i];
            for (int i = 0; i < 5; i++)
                st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5];
        }
        st[0] ^= keccakf_rndc[round];
    }
}

static void sha3_256_sw(const uint8_t *input, size_t len, uint8_t output[32]) {
    uint64_t state[25] = {0};
    size_t rate_bytes = SHA3_256_RATE;
    size_t idx = 0;
    while (len >= rate_bytes) {
        for (size_t i = 0; i < rate_bytes / 8; i++) {
            uint64_t word = 0;
            for (int j = 0; j < 8; j++)
                word |= ((uint64_t)input[idx++]) << (8 * j);
            state[i] ^= word;
        }
        keccakf(state);
        len -= rate_bytes;
    }
    uint8_t temp[SHA3_256_RATE] = {0};
    for (size_t i = 0; i < len; i++)
        temp[i] = input[idx++];
    temp[len] = 0x06;
    temp[rate_bytes - 1] |= 0x80;
    for (size_t i = 0; i < rate_bytes / 8; i++) {
        uint64_t word = 0;
        for (int j = 0; j < 8; j++)
            word |= ((uint64_t)temp[i * 8 + j]) << (8 * j);
        state[i] ^= word;
    }
    keccakf(state);
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 8; j++)
            output[i * 8 + j] = (state[i] >> (8 * j)) & 0xFF;
    }
}

int main(int argc, char **argv) {
    const size_t DATA_SIZE = 850;
    const size_t NUM_HASHES = 1000000;
    
    uint8_t *input = (uint8_t *)malloc(DATA_SIZE);
    uint8_t hash[32];
    
    // Fill with test pattern
    for (size_t i = 0; i < DATA_SIZE; i++) {
        input[i] = (uint8_t)(i & 0xFF);
    }
    
    printf("========================================\n");
    printf("SHA3-256 Software Benchmark\n");
    printf("========================================\n");
    printf("Data size: %zu bytes\n", DATA_SIZE);
    printf("Number of hashes: %zu\n", NUM_HASHES);
    printf("Starting benchmark...\n\n");
    
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    for (size_t i = 0; i < NUM_HASHES; i++) {
        sha3_256_sw(input, DATA_SIZE, hash);
    }
    
    clock_gettime(CLOCK_MONOTONIC, &end);
    
    double elapsed = (end.tv_sec - start.tv_sec) + 
                     (end.tv_nsec - start.tv_nsec) / 1e9;
    double hash_rate = NUM_HASHES / elapsed / 1e6; // MH/s
    double throughput = (DATA_SIZE * NUM_HASHES) / elapsed / (1024.0 * 1024.0); // MB/s
    
    printf("Elapsed time: %.3f seconds\n", elapsed);
    printf("Hash rate: %.3f MH/s\n", hash_rate);
    printf("Throughput: %.3f MB/s\n", throughput);
    printf("Average time per hash: %.3f µs\n", (elapsed * 1e6) / NUM_HASHES);
    
    printf("\nFinal hash: ");
    for (int i = 0; i < 32; i++) printf("%02x", hash[i]);
    printf("\n");
    
    free(input);
    return 0;
}
