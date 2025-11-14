`timescale 1 ps / 1 ps
module sha3_ctrl (
    input  wire        clk,
    input  wire        reset,
    
    // --- Control Inputs from avs_SHA_3 ---
    input  wire        core_reset,          // Reset FSM (from CSR)
    input  wire        core_last_word,      // Last word signal (from CSR)
    input  wire        core_empty_message,  // Empty message flag (from CSR)
    input  wire        data_in_strobe,      // 32-bit word is valid
    input  wire [31:0] data_in_data,        // The 32-bit word
    input  wire [3:0]  data_in_byteenable,  // Byte enable mask
    
    // --- Status Outputs to avs_SHA_3 ---
    output wire        core_busy,           // Core is working (FSM not IDLE/DONE)
    output wire        core_done,           // Hash is complete (FSM is DONE)
    output wire        core_waitrequest,    // Stall the bus
    output wire [255:0] hash_out_data,        // Final 256-bit hash
    output wire [31:0]  csr_status,           // Packed CSR status
    output wire         core_ready            // FSM idle indicator
);

    //=========================================================================
    // FSM State Definitions
    //=========================================================================
    localparam FSM_IDLE       = 3'd0; // Waiting for data
    localparam FSM_ABSORB     = 3'd1; // Absorbing 32-bit words
    localparam FSM_PAD        = 3'd2; // Applying padding to the last block
    localparam FSM_RUN_KECCAK = 3'd3; // Running 24-round permutation
    localparam FSM_SQUEEZE    = 3'd4; // Copying hash to output registers
    localparam FSM_DONE       = 3'd5; // Hashing complete, waiting for reset

    reg [2:0] state_reg, state_next;

    //=========================================================================
    // Datapath Registers
    //=========================================================================
    reg [1599:0] state;          // The 1600-bit Keccak state
    reg [1087:0] block_buffer;   // 1088-bit (136-byte) block buffer
    reg [5:0]    word_count;     // Counts 32-bit words (0 to 33)
    reg [7:0]    byte_count;     // Counts payload bytes (0 to 136)
    reg [3:0]    last_byteenable; // Store byteenable for last word
    reg [4:0]    round_count;    // Counts Keccak rounds (0 to 24)
    reg          last_word_latch; // Remembers if HPS sent 'last_word'
    reg          padding_block;   // Flag: We are processing the final padding block
    reg [255:0]  hash_out_reg;   // Holds the final 256-bit hash

    // --- Keccak Round Logic ---
    wire [1599:0] keccak_round_out; // Output of the permutation
    wire [63:0]   round_const;      // Round constant for Iota step
    wire [4:0]    round_const_index;
    wire [7:0]    word_byte_count;
    wire [31:0]   masked_data_in;
    
    assign hash_out_data = hash_out_reg; // Connect output
    assign core_ready    = (state_reg == FSM_IDLE);
    assign core_busy = (state_reg != FSM_IDLE) && (state_reg != FSM_DONE);
    assign core_done = (state_reg == FSM_DONE);
    assign csr_status    = {26'b0, core_ready, state_reg, core_done, core_busy};

    //=========================================================================
    // Keccak-f[1600] Round Constants
    //=========================================================================
    reg [63:0] keccak_round_constants [0:23];

    initial begin
        keccak_round_constants[ 0] = 64'h0000000000000001;
        keccak_round_constants[ 1] = 64'h0000000000008082;
        keccak_round_constants[ 2] = 64'h800000000000808a;
        keccak_round_constants[ 3] = 64'h8000000080008000;
        keccak_round_constants[ 4] = 64'h000000000000808b;
        keccak_round_constants[ 5] = 64'h0000000080000001;
        keccak_round_constants[ 6] = 64'h8000000080008081;
        keccak_round_constants[ 7] = 64'h8000000000008009;
        keccak_round_constants[ 8] = 64'h000000000000008a;
        keccak_round_constants[ 9] = 64'h0000000000000088;
        keccak_round_constants[10] = 64'h0000000080008009;
        keccak_round_constants[11] = 64'h000000008000000a;
        keccak_round_constants[12] = 64'h000000008000808b;
        keccak_round_constants[13] = 64'h800000000000008b;
        keccak_round_constants[14] = 64'h8000000000008089;
        keccak_round_constants[15] = 64'h8000000000008003;
        keccak_round_constants[16] = 64'h8000000000008002;
        keccak_round_constants[17] = 64'h8000000000000080;
        keccak_round_constants[18] = 64'h000000000000800a;
        keccak_round_constants[19] = 64'h800000008000000a;
        keccak_round_constants[20] = 64'h8000000080008081;
        keccak_round_constants[21] = 64'h8000000000008080;
        keccak_round_constants[22] = 64'h0000000080000001;
        keccak_round_constants[23] = 64'h8000000080008008;
    end
    
    //=========================================================================
    // Keccak Round Logic Instantiation
    //=========================================================================
    
    assign round_const_index = (round_count == 5'd0) ? 5'd0 : (round_count - 5'd1);
    assign round_const = keccak_round_constants[round_const_index];
    
    // Count how many bytes are valid based on byteenable
    assign word_byte_count = data_in_byteenable[0] + data_in_byteenable[1] +
                             data_in_byteenable[2] + data_in_byteenable[3];
    
    // Mask the data based on byteenable
    assign masked_data_in = {data_in_byteenable[3] ? data_in_data[31:24] : 8'h00,
                            data_in_byteenable[2] ? data_in_data[23:16] : 8'h00,
                            data_in_byteenable[1] ? data_in_data[15:8]  : 8'h00,
                            data_in_byteenable[0] ? data_in_data[7:0]   : 8'h00};

    keccak_core round_logic_inst (
        .state_in    ( state ),
        .round_const ( round_const ),
        .state_out   ( keccak_round_out )
    );

    //=========================================================================
    // Main SHA-3 FSM (Datapath Control)
    //=========================================================================
    
    // Stall the HPS only when we cannot accept new data:
    // 1. During PAD (applying padding, 1 cycle)
    // 2. During final block processing (RUN_KECCAK with padding_block set)
    // 3. During SQUEEZE (1 cycle to copy hash)
    // 4. During DONE (waiting for reset)
    // 5. When buffer is full in ABSORB state
    assign core_waitrequest = (state_reg == FSM_PAD) || 
                             (state_reg == FSM_SQUEEZE) || 
                             (state_reg == FSM_DONE) ||
                             ((state_reg == FSM_RUN_KECCAK) && padding_block) ||
                             ((state_reg == FSM_ABSORB) && (byte_count >= 8'd136));


    // --- Combinational FSM Logic ---
    always_comb begin
        state_next = state_reg; // Default: stay in current state

        case (state_reg)
            FSM_IDLE: begin
                // Check for empty message signal
                if (core_empty_message) begin
                    state_next = FSM_PAD;
                end
                // Wait for a write to DATA_IN
                else if (data_in_strobe) begin
                    state_next = FSM_ABSORB;
                end
            end
            
            FSM_ABSORB: begin
                // Check if block will be full after current write
                // Priority 1: Block is/will be full (136 bytes)
                if ( (byte_count >= 8'd136) || 
                     (data_in_strobe && (byte_count + word_byte_count) >= 8'd136) ) begin
                    state_next = FSM_RUN_KECCAK;
                end
                // Priority 2: Last word received (but block not full)
                else if (last_word_latch || (data_in_strobe && core_last_word)) begin
                    state_next = FSM_PAD;
                end
            end
            
            FSM_PAD: begin
                // Single-cycle state to apply padding
                state_next = FSM_RUN_KECCAK;
            end

            FSM_RUN_KECCAK: begin
                // This is a 25-cycle state (0=XOR, 1-24=Rounds)
                if (round_count == 5'd24) begin // Finished final round
                    if (padding_block) begin
                        // Case A: We just finished the *padding block*. We are done.
                        state_next = FSM_SQUEEZE;
                    end
                    else if (last_word_latch) begin
                        // Case B: We just finished the *last data block*.
                        // Now we must create and process the padding block.
                        state_next = FSM_PAD;
                    end
                    else begin
                        // Case C: We just finished a normal data block. Go get more.
                        state_next = FSM_IDLE; 
                    end
                end
            end

            FSM_SQUEEZE: begin
                // Single-cycle state to copy hash to output regs
                state_next = FSM_DONE;
            end

            FSM_DONE: begin
                // Stay here until the HPS resets the core
                if (core_reset) begin
                    state_next = FSM_IDLE;
                end
            end
        endcase
    end

    // --- Sequential FSM Logic (Registered) ---
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Reset all state
            state_reg         <= FSM_IDLE;
            state             <= 1600'b0;
            block_buffer      <= 1088'b0;
            word_count        <= 6'b0;
            byte_count        <= 8'b0;
            round_count       <= 5'b0;
            last_word_latch   <= 1'b0;
            last_byteenable   <= 4'b0;
            hash_out_reg      <= 256'b0;
            padding_block     <= 1'b0; 
        end
        else begin
            // Latch the next state
            state_reg <= state_next;
            
            // Handle core reset from CSR
            if (core_reset) begin
                 state_reg <= FSM_IDLE;
            end

            // --- FSM State Actions ---
            case (state_reg)
                FSM_IDLE: begin
                    // Reset counters and clear buffer for a new message
                    word_count      <= 6'b0;
                    block_buffer    <= 1088'b0;
                    last_word_latch <= 1'b0;
                    hash_out_reg    <= 256'b0;
                    round_count     <= 5'b0;
                    padding_block   <= 1'b0; 
                    byte_count      <= 8'd0;
                    last_byteenable <= 4'b0;

                    // Handle empty message transition
                    if (state_next == FSM_PAD && core_empty_message) begin
                        padding_block <= 1'b1;
                        byte_count <= 8'd0;
                    end
                    // On the transition cycle (IDLE -> ABSORB)
                    else if (state_next == FSM_ABSORB && data_in_strobe) begin
                        int i;
                        int idx;
                        idx = 0; // start of a fresh block
                        for (i = 0; i < 4; i = i + 1) begin
                            if (data_in_byteenable[i]) begin
                                block_buffer[(idx * 8) +: 8] <= data_in_data[(8*i) +: 8];
                                idx = idx + 1;
                            end
                        end
                        byte_count <= idx;
                        word_count <= (idx + 3) >> 2;
                        if (core_last_word) begin 
                            last_word_latch <= 1'b1;
                            last_byteenable <= data_in_byteenable;
                        end
                    end
                end

                FSM_ABSORB: begin
                    // Append incoming bytes sequentially at the current byte_count
                    if (data_in_strobe) begin
                        int i;
                        int idx;
                        idx = byte_count;
                        for (i = 0; i < 4; i = i + 1) begin
                            if (data_in_byteenable[i]) begin
                                block_buffer[(idx * 8) +: 8] <= data_in_data[(8*i) +: 8];
                                idx = idx + 1;
                            end
                        end
                        byte_count <= idx;
                        word_count <= (idx + 3) >> 2;
                        if (core_last_word) begin 
                            last_word_latch <= 1'b1; // latch only when a write occurs
                            last_byteenable <= data_in_byteenable;
                        end
                    end
                end

                FSM_PAD: begin
                    // Apply padding starting at byte boundary (byte_count tells where message ended)
                    int pad_byte_index;
                    
                    // If the last write filled the block exactly, we need a fresh padding block
                    if (byte_count >= 8'd136) begin
                        // Start fresh padding block
                        pad_byte_index = 0;
                        block_buffer <= 1088'b0;
                    end else begin
                        // Pad in current partially-filled block
                        pad_byte_index = byte_count;
                    end

                    // SHA-3 domain suffix: append 0x06 at the pad start byte
                    // 0x06 = 0b00000110, which in LSB-first bit ordering is:
                    // bit 0 = 0, bit 1 = 1, bit 2 = 1
                    block_buffer[(pad_byte_index * 8)]     <= 1'b0; 
                    block_buffer[(pad_byte_index * 8) + 1] <= 1'b1; 
                    block_buffer[(pad_byte_index * 8) + 2] <= 1'b1; 

                    // Mark final '1' at rate end (bit 1087)
                    block_buffer[1087] <= 1'b1;

                    padding_block <= 1'b1;
                end

                FSM_RUN_KECCAK: begin
                    if (round_count == 5'd0) begin
                        // XOR the 1088-bit block_buffer into the low part of the state
                        state[1087:0] <= state[1087:0] ^ block_buffer;

                        // Clear buffer and byte_count for the *next* block (including padding block)
                        block_buffer <= 1088'b0;
                        word_count   <= 6'b0;
                        byte_count   <= 8'b0;  // Always reset - padding block starts at byte 0
                        
                        round_count  <= round_count + 1;
                    end
                    else if (round_count == 5'd24) begin
                        // --- Final round complete ---
                        state       <= keccak_round_out;
                        round_count <= 5'b0;
                        
                        // Clear last_word_latch only if we're done or going back to IDLE
                        if (padding_block || !last_word_latch) begin
                            last_word_latch <= 1'b0;
                        end
                    end
                    else begin
                        // --- Cycles 1-23: Run the permutation ---
                        state       <= keccak_round_out;
                        round_count <= round_count + 1;
                    end
                end

                FSM_SQUEEZE: begin
                    // Copy the 256-bit hash result from the state
                    hash_out_reg <= state[255:0];
                end

                FSM_DONE: begin
                    // The 'done' bit is high. Wait for reset.
                    if (core_reset) begin
                        // Clear the 'done' state
                        state[1599:0] <= 1600'b0;
                    end
                end
            endcase
        end
    end
    
endmodule

