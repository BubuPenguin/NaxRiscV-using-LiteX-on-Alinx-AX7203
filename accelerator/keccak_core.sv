// keccak_f_round.v
//
// This is the stub module for the Keccak 24-round permutation.
// You must replace this with your own implementation of the 5 steps:
// Theta, Rho, Pi, Chi, and Iota based on the FIPS 202 standard.
//
// This is a PURELY COMBINATORIAL block. It should have no registers.
//
`timescale 1 ps / 1 ps
module keccak_core (
    input  wire [1599:0] state_in,    // Current 1600-bit state
    input  wire [63:0]   round_const, // 64-bit round constant for Iota
    output wire [1599:0] state_out     // Resulting 1600-bit state
);

    // This is the full, combinatorial implementation of one Keccak-f[1600] round.
    // It is organized into the 5 steps as defined in FIPS 202.

    genvar x, y;

    //=========================================================================
    // Helper Functions
    //=========================================================================

    // Helper function for 64-bit rotate left
    function automatic [63:0] ROL64;
        input [63:0] data;
        input [5:0]  shift;
        ROL64 = (data << shift) | (data >> (64 - shift));
    endfunction
    
    //=========================================================================
    // State Representation
    //=========================================================================
    
    // 1. Reshape the 1600-bit linear `state_in` into a 5x5 array of 64-bit lanes
    // state_A[x][y]
    wire [63:0] state_A [0:4][0:4];
    generate
        for (y = 0; y < 5; y = y + 1) begin : unflatten
            for (x = 0; x < 5; x = x + 1) begin : lane
                // A[x,y] = state[(w/8)*(5*y + x) + b]
                assign state_A[x][y] = state_in[ (5*y + x)*64 +: 64 ];
            end
        end
    endgenerate

    //=========================================================================
    // Step 1: Theta (θ)
    //=========================================================================
    wire [63:0] C [0:4];
    wire [63:0] D [0:4];
    wire [63:0] state_B [0:4][0:4];

    // C[x] = A[x,0] ^ A[x,1] ^ A[x,2] ^ A[x,3] ^ A[x,4]
    generate
        for (x = 0; x < 5; x = x + 1) begin : theta_C
            assign C[x] = state_A[x][0] ^ state_A[x][1] ^ state_A[x][2] ^ state_A[x][3] ^ state_A[x][4];
        end
    endgenerate

    // D[x] = C[x-1] ^ ROL(C[x+1], 1)
    generate
        for (x = 0; x < 5; x = x + 1) begin : theta_D
            assign D[x] = C[(x+4)%5] ^ ROL64(C[(x+1)%5], 1);
        end
    endgenerate

    // A'[x,y] = A[x,y] ^ D[x]
    generate
        for (y = 0; y < 5; y = y + 1) begin : theta_A
            for (x = 0; x < 5; x = x + 1) begin : inner_theta_A
                assign state_B[x][y] = state_A[x][y] ^ D[x];
            end
        end
    endgenerate

    //=========================================================================
    // Step 2: Rho (ρ)
    //=========================================================================
    // A'[x,y] = ROL(A[x,y], r[x,y])
    // These are the 25 fixed rotation offsets from the FIPS 202 standard.
    wire [63:0] state_C [0:4][0:4];
    
    assign state_C[0][0] = ROL64(state_B[0][0], 0);
    assign state_C[1][0] = ROL64(state_B[1][0], 1);
    assign state_C[2][0] = ROL64(state_B[2][0], 62);
    assign state_C[3][0] = ROL64(state_B[3][0], 28);
    assign state_C[4][0] = ROL64(state_B[4][0], 27);

    assign state_C[0][1] = ROL64(state_B[0][1], 36);
    assign state_C[1][1] = ROL64(state_B[1][1], 44);
    assign state_C[2][1] = ROL64(state_B[2][1], 6);
    assign state_C[3][1] = ROL64(state_B[3][1], 55);
    assign state_C[4][1] = ROL64(state_B[4][1], 20);

    assign state_C[0][2] = ROL64(state_B[0][2], 3);
    assign state_C[1][2] = ROL64(state_B[1][2], 10);
    assign state_C[2][2] = ROL64(state_B[2][2], 43);
    assign state_C[3][2] = ROL64(state_B[3][2], 25);
    assign state_C[4][2] = ROL64(state_B[4][2], 39);

    assign state_C[0][3] = ROL64(state_B[0][3], 41);
    assign state_C[1][3] = ROL64(state_B[1][3], 45);
    assign state_C[2][3] = ROL64(state_B[2][3], 15);
    assign state_C[3][3] = ROL64(state_B[3][3], 21);
    assign state_C[4][3] = ROL64(state_B[4][3], 8);

    assign state_C[0][4] = ROL64(state_B[0][4], 18);
    assign state_C[1][4] = ROL64(state_B[1][4], 2);
    assign state_C[2][4] = ROL64(state_B[2][4], 61);
    assign state_C[3][4] = ROL64(state_B[3][4], 56);
    assign state_C[4][4] = ROL64(state_B[4][4], 14);

    //=========================================================================
    // Step 3: Pi (π)
    //=========================================================================
    // A'[Y, (2X+3Y)%5] = A[X,Y]
    wire [63:0] state_D [0:4][0:4];
    
    generate
        for (y = 0; y < 5; y = y + 1) begin : pi
            for (x = 0; x < 5; x = x + 1) begin : lane
                // This implements the (x,y) -> (y, (2x+3y)%5) permutation
                assign state_D[y][(2*x + 3*y) % 5] = state_C[x][y];
            end
        end
    endgenerate

    //=========================================================================
    // Step 4: Chi (χ)
    //=========================================================================
    // A'[x,y] = A[x,y] ^ ( (~A[x+1, y]) & A[x+2, y] )
    wire [63:0] state_E [0:4][0:4];
    
    generate
        for (y = 0; y < 5; y = y + 1) begin : chi
            for (x = 0; x < 5; x = x + 1) begin : lane
                assign state_E[x][y] = state_D[x][y] ^ 
                                       ( (~state_D[(x+1)%5][y]) & state_D[(x+2)%5][y] );
            end
        end
    endgenerate

    //=========================================================================
    // Step 5: Iota (ι)
    //=========================================================================
    // A'[0,0] = A'[0,0] ^ RC
    // All other lanes are passed through.
    wire [63:0] state_F [0:4][0:4];
    
    assign state_F[0][0] = state_E[0][0] ^ round_const;

    generate
        for (y = 0; y < 5; y = y + 1) begin : iota
            for (x = 0; x < 5; x = x + 1) begin : lane
                if (x != 0 || y != 0) begin
                    assign state_F[x][y] = state_E[x][y];
                end
            end
        end
    endgenerate

    //=========================================================================
    // Final Output: Flattening
    //=========================================================================
    
    // 2. Reshape the 5x5x64 `state_F` back into the 1600-bit `state_out`
    generate
        for (y = 0; y < 5; y = y + 1) begin : flatten
            for (x = 0; x < 5; x = x + 1) begin : lane
                assign state_out[ (5*y + x)*64 +: 64 ] = state_F[x][y];
            end
        end
    endgenerate
    
endmodule

