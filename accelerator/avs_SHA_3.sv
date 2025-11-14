// avs_SHA_3.v

// This file was auto-generated as a prototype implementation of a module
// created in component editor.  It ties off all outputs to ground and
// ignores all inputs.  It needs to be edited to make it do something
// useful.
// 
// This file will not be automatically regenerated.  You should check it in
// to your version control system if you want to keep it.

`timescale 1 ps / 1 ps
module avs_SHA_3 (
		input  wire        clock_clk,          //   clock.clk
		input  wire        reset_reset,        //   reset.reset
		input  wire [3:0]  avs_s0_address,     // avs_SHA.address
		input  wire        avs_s0_read,        //        .read
		output wire [31:0] avs_s0_readdata,    //        .readdata
		input  wire        avs_s0_write,       //        .write
		input  wire [31:0] avs_s0_writedata,   //        .writedata
		output wire        avs_s0_waitrequest, //        .waitrequest
		input  wire        avs_s0_chipselect,  //        .chipselect
        input  wire  [3:0] avs_s0_byteenable,  //        .byteenable
        output wire        avs_s0_readdatavalid, //        .readdatavalid
		output wire        led_processing,
		output wire        led_write_activity,
		output wire        led_core_ready
	);

    //=========================================================================
    // Register Map Definition
    //=========================================================================
    localparam [3:0] REG_CSR          = 4'h0;
    localparam [3:0] REG_DATA_IN      = 4'h1;
    localparam [3:0] REG_HASH_OUT_0   = 4'h2;
    localparam [3:0] REG_HASH_OUT_1   = 4'h3;
    localparam [3:0] REG_HASH_OUT_2   = 4'h4;
    localparam [3:0] REG_HASH_OUT_3   = 4'h5;
    localparam [3:0] REG_HASH_OUT_4   = 4'h6;
    localparam [3:0] REG_HASH_OUT_5   = 4'h7;
    localparam [3:0] REG_HASH_OUT_6   = 4'h8;
    localparam [3:0] REG_HASH_OUT_7   = 4'h9;

    //=========================================================================
    // Internal Wires for Bus Interface
    //=========================================================================

    wire        write_strobe;    // Single-cycle pulse for a valid write
    wire        read_strobe;     // Single-cycle pulse for a valid read
    reg         read_strobe_reg; // Delayed read strobe for readdatavalid
    reg  [31:0] csr_reg;       // Internal storage for Control bits
    reg  [23:0] write_pulse_timer;

    // --- Wires to connect to the sha3_control core ---
    wire        core_reset;      // From CSR
    wire        core_last_word;  // From CSR
    wire        core_empty_message; // From CSR - bit 3
    wire        core_data_in_strobe; // HPS wrote to DATA_IN
    wire [31:0] core_data_in_data;   // Data from HPS
    wire [3:0]  core_byteenable;     // Which bytes are valid

    wire        core_busy;       // Status from core
    wire        core_done;       // Status from core
    wire [255:0] core_hash_out;   // Final hash from core
    wire        core_waitrequest;  // Core is busy, stall the bus
    wire [31:0] core_csr_status; // Latched CSR status from core
    wire        core_ready;      // FSM idle indicator

    //=========================================================================
    // Avalon Bus Logic (Write, Read, Waitrequest)
    //=========================================================================

    assign write_strobe = avs_s0_chipselect & avs_s0_write;
    assign read_strobe  = avs_s0_chipselect & avs_s0_read;
    assign avs_s0_readdatavalid = read_strobe_reg;
    
    // Connect waitrequest directly from the control core
    assign avs_s0_waitrequest = core_waitrequest;

    // LED status indicators
    always_ff @(posedge clock_clk or posedge reset_reset) begin
        if (reset_reset) begin
            write_pulse_timer <= 24'd0;
            read_strobe_reg <= 1'b0;
        end
        else begin
            // Register the read strobe for readdatavalid
            read_strobe_reg <= read_strobe & ~core_waitrequest;
            
            if (write_strobe) begin
                write_pulse_timer <= 24'hFFFFFF;
            end
            else if (write_pulse_timer != 24'd0) begin
                write_pulse_timer <= write_pulse_timer - 24'd1;
            end
        end
    end

    assign led_write_activity = |write_pulse_timer;
    assign led_processing     = core_busy;
    assign led_core_ready     = core_ready;

    //=========================================================================
    // SHA-3 Control Core Instantiation
    //=========================================================================
    sha3_ctrl sha3_core_inst (
        .clk                 ( clock_clk ),
        .reset               ( reset_reset ),
        
        // --- Control Inputs ---
        .core_reset          ( core_reset ),
        .core_last_word      ( core_last_word ),
        .core_empty_message  ( core_empty_message ),
        .data_in_strobe      ( core_data_in_strobe ),
        .data_in_data        ( core_data_in_data ),
        .data_in_byteenable  ( core_byteenable ),
        
        // --- Status Outputs ---
        .core_busy           ( core_busy ),
        .core_done           ( core_done ),
        .core_waitrequest    ( core_waitrequest ),
        .hash_out_data       ( core_hash_out ),
        .csr_status          ( core_csr_status ),
        .core_ready          ( core_ready )
    );

    // --- Write Logic ---
    // Handle writes from the HPS and generate simple strobes for the core
    
    // Store the CSR control bits - simplified without auto-clear
    always_ff @(posedge clock_clk or posedge reset_reset) begin
        if (reset_reset) begin
            csr_reg <= 32'b0;
        end
        else begin
            // Handle new CSR writes
            if (write_strobe && avs_s0_address == REG_CSR) begin
                csr_reg <= avs_s0_writedata;
            end
            else begin
                // Auto-clear core_reset after one cycle (this is safe)
                if (csr_reg[1]) begin
                    csr_reg[1] <= 1'b0;
                end
                // Auto-clear core_last_word after it's been processed
                // Only clear when FSM moves to DONE state
                if (csr_reg[2] && core_done) begin
                    csr_reg[2] <= 1'b0;
                end
                // Auto-clear core_empty_message after it's been processed
                if (csr_reg[3] && core_done) begin
                    csr_reg[3] <= 1'b0;
                end
            end
        end
    end

    // Derive control signals from the CSR
    assign core_reset     = csr_reg[1]; // bit 1 = reset
    assign core_last_word = csr_reg[2]; // bit 2 = last word
    assign core_empty_message = csr_reg[3]; // bit 3 = empty message
    
    // Generate a single-cycle strobe when DATA_IN is written
    assign core_data_in_strobe = (write_strobe && avs_s0_address == REG_DATA_IN);
    assign core_data_in_data   = avs_s0_writedata;
    assign core_byteenable     = avs_s0_byteenable;

    // --- Read Logic ---
    // Handle reads from the HPS
    reg  [31:0] avs_s0_readdata_reg;
    assign avs_s0_readdata = avs_s0_readdata_reg;

    always_ff @(posedge clock_clk) begin
        if (read_strobe && !core_waitrequest) begin
            case (avs_s0_address)
                REG_CSR: begin
                    avs_s0_readdata_reg <= core_csr_status;
                end
                REG_HASH_OUT_0: begin
                    avs_s0_readdata_reg <= core_hash_out[31:0];
                end
                REG_HASH_OUT_1: begin
                    avs_s0_readdata_reg <= core_hash_out[63:32];
                end
                REG_HASH_OUT_2: begin
                    avs_s0_readdata_reg <= core_hash_out[95:64];
                end
                REG_HASH_OUT_3: begin
                    avs_s0_readdata_reg <= core_hash_out[127:96];
                end
                REG_HASH_OUT_4: begin
                    avs_s0_readdata_reg <= core_hash_out[159:128];
                end
                REG_HASH_OUT_5: begin
                    avs_s0_readdata_reg <= core_hash_out[191:160];
                end
                REG_HASH_OUT_6: begin
                    avs_s0_readdata_reg <= core_hash_out[223:192];
                end
                REG_HASH_OUT_7: begin
                    avs_s0_readdata_reg <= core_hash_out[255:224];
                end
                default: begin
                    avs_s0_readdata_reg <= 32'hDEADBEEF;
                end
            endcase
        end
    end
endmodule

