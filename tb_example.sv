module tb_example;

    // --- Parameters matching top.sv ---
    localparam DATA_WIDTH = 32;
    localparam NUM_OF_ENTERIES = 8;  // N_COLS
    localparam H_ROW_SIZE = 4;       // M
    localparam IDX_SIZE = 8;         // Width for index
    localparam CLK_PERIOD = 1ns;
    localparam INDEX_SIZE = $clog2(NUM_OF_ENTERIES);

    // --- Signals for DUT Connection ---
    logic clk, rst_n;
    
    // Inputs to top
    logic vld_in;
    logic [DATA_WIDTH-1:0] llr_in;
    logic [H_ROW_SIZE-1:0] H_col_in;
    logic [H_ROW_SIZE-1:0] syndrome_in; // Correctly named signal
    
    // Outputs from top
    logic [INDEX_SIZE-1:0] H_col_index_out;
    logic vld_out;
    logic [NUM_OF_ENTERIES-1:0] e_hat_out;

    // --- Internal Memories ---
    // We need to store the H-Matrix and LLRs by their "Real Index" (0 to 7)
    // so we can feed them into the sorter sequentially.
    logic [H_ROW_SIZE-1:0] H_mem [0:NUM_OF_ENTERIES-1];
    logic [DATA_WIDTH-1:0] LLR_mem [0:NUM_OF_ENTERIES-1];

    // --- Reference Data Definition ---
    typedef struct packed {
        logic [H_ROW_SIZE-1:0] col;
        logic [INDEX_SIZE-1:0] idx;
        logic [DATA_WIDTH-1:0] llr_val;
    } col_info_t;

    // This is the SORTED expectation (Golden Model for setting up the test)
    // We use this to populate H_mem and LLR_mem correctly.
    col_info_t H_sorted_ref[NUM_OF_ENTERIES] = {
        // format: {column, index, LLR}


        {4'b1010, 3'd0, 32'hBAE147AE}, // Idx 0, LLR 0.73
        {4'b0110, 3'd1, 32'h26666666}, // Idx 1, LLR 0.15
        {4'b1001, 3'd2, 32'hEB851EB8}, // Idx 2, LLR 0.92 (High)
        {4'b0101, 3'd3, 32'h7AE147AE}, // Idx 3, LLR 0.48
        {4'b1101, 3'd4, 32'h4F5C28F5}, // Idx 4, LLR 0.31
        {4'b1010, 3'd5, 32'hDC28F5C2}, // Idx 5, LLR 0.86
        {4'b0110, 3'd6, 32'h0A3D70A3},  // Idx 6, LLR 0.04 (Low)
        {4'b0001, 3'd7, 32'hAB851EB8} // Idx 7, LLR 0.67

        

    };

    // Expected Final Error Pattern (Indices 5 and 7 have errors)
    // 8'b10100000 -> Bits 7 and 5 are set.
    localparam [NUM_OF_ENTERIES-1:0] EXPECTED_E_HAT = 8'b10100000;

    // --- DUT Instantiation ---
    osd_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_OF_ENTERIES(NUM_OF_ENTERIES),
        .H_ROW_SIZE(H_ROW_SIZE),
        .IDX_SIZE(IDX_SIZE)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .vld_in(vld_in),
        .llr(llr_in),
        .H_col(H_col_in),
        .syndrome(syndrome_in), // Fixed: Use the declared 'syndrome_in'
        .H_col_index(H_col_index_out),
        .vld_out(vld_out),
        .e_hat(e_hat_out)
    );

    // --- Combinational Memory Lookup (Simulating ROM/RAM) ---
    // When DUT requests an index, provide the corresponding H-column
    // Note: The DUT top logic likely registers the index, so we provide data combinationally
    // effectively creating 0 or 1 cycle latency depending on top's internal sampling.
    assign H_col_in = H_mem[H_col_index_out];

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- Main Test Process ---
    initial begin
        // 1. Initialize Memories from the Reference Data
        // We iterate through the sorted reference and place data into the 
        // "Real Index" slots.
        for (int i = 0; i < NUM_OF_ENTERIES; i++) begin
            automatic int idx = H_sorted_ref[i].idx; // Added 'automatic' to fix warning
            H_mem[idx]   = H_sorted_ref[i].col;
            LLR_mem[idx] = H_sorted_ref[i].llr_val;
        end

        // 2. Initialize Signals
        rst_n = 1;
        vld_in = 0;
        llr_in = 0;
        syndrome_in = 4'b1011; // Fixed: Assign to declared 'syndrome_in'

        $display("=================================================");
        $display("   OSD INTEGRATION TESTBENCH (Top Level)");
        $display("=================================================");

        // 3. Reset
        repeat(10) @(posedge clk);
        rst_n = 0;
        repeat(5) @(posedge clk);

        $display("--- Step 1: Feeding LLRs to Sorter ---");
        
        // 4. Feed Data to Sorter
        // We feed indices 0 through 7 sequentially.
        // The sorter inside 'top' will handle the re-ordering.
        vld_in = 1;
        for (int i = 0; i < NUM_OF_ENTERIES; i++) begin
            llr_in = LLR_mem[i];
            $display("Feeding Index %0d, LLR: 0x%h", i, llr_in);
            @(posedge clk);
        end
        vld_in = 0;
        llr_in = 0;

        $display("--- Step 2: Waiting for Sorting & Processing ---");
        $display("Note: Monitor H_col_index_out to see DUT requesting sorted columns.");

        // 5. Wait for Completio             // Wait for valid output flag
                wait(vld_out);
                @(posedge clk); // Capture stable output
                
                $display("\n========================================");
                $display("       COMPUTATION COMPLETED");
                $display("========================================");
                $display("Final Error Vector: %b", e_hat_out);
                
                if (e_hat_out == EXPECTED_E_HAT) begin
                    $display("RESULT: [PASS] Matches Expected (10100000)");
                end else begin
                    $display("RESULT: [FAIL] Mismatch! Expected: %b", EXPECTED_E_HAT);
                end
                $display("========================================");
           
        $stop;
    end
    
    // Optional: Monitor the requested indices to verify sorting order
//    always @(posedge clk) begin
//        if (!rst_n && (H_col_index_out !== 0 || H_col_index_out === 0)) begin
//            // This print might be spammy, depends on how stable H_col_index_out is
//            $display("DUT Requesting Index: %0d -> Returning H_Col: %b", H_col_index_out, H_col_in);
//        end
//    end

endmodule