module tb_scaled;

    // --- 1. Dimensions (Matches text files) ---
    localparam M = 936;    // H_ROW_SIZE (Syndrome Length)
    localparam N = 8784;   // N_COLS (Codeword Length)
    localparam IDX_W = 14; // $clog2(8784) = 13.1 -> 14 bits required for indices
    
    localparam CLK_PERIOD = 1ns; 

    // --- 2. DUT Interface Signals ---
    logic clk, reset;
    
    // Stream Inputs (From Sorter)
    logic [M-1:0]   sorted_col_in;
    logic [IDX_W-1:0] sorted_idx_in;
    logic           forward_in_valid_tb;
    
    // Solver Input
    logic [M-1:0]   syndrome_tb; 
    
    // Stream Outputs (Optional Debug)
    logic [M-1:0]   h_inv_col_out;
    logic [IDX_W-1:0] h_inv_idx_out;
    logic           h_inv_out_valid;
    
    // Final Result
    logic [N-1:0]   final_e_hat_tb;
    logic           final_done_tb;

    // --- 3. Testbench Memory (The "Golden" Data) ---
    // H_mem stores the binary H-matrix columns. 
    // idx_mem stores the integer priority order.
    logic [M-1:0] H_mem [0:N-1];
    int           idx_mem [0:N-1];

    // File Handles
    integer f_idx, f_syn, f_gold;
    integer scan_status;
    integer real_idx;
    
    // Statistics
    integer test_case_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // --- 4. DUT Instantiation ---
    sys_arr_lse_sol #(
        .H_ROW_SIZE(M), 
        .IDX_SIZE(IDX_W), 
        .N_COLS(N)
    ) DUT (
        .clk(clk),
        .reset(reset),
        
        // Sorting Stream Interface
        .sorted_col_in(sorted_col_in),
        .sorted_idx_in(sorted_idx_in),
        
        // Solver Interface
        .syndrome_in(syndrome_tb),
        
        // Stream Outputs (Unused for automated check, but connected)
        .h_inv_col_out(h_inv_col_out),
        .h_inv_idx_out(h_inv_idx_out),
        .h_inv_out_valid(h_inv_out_valid),
        
        // Final Answer
        .final_e_hat(final_e_hat_tb),
        .final_done(final_done_tb)
    );

    // --- 5. Clock Generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- 6. Main Test Process ---
    initial begin
        // Initialize
        reset = 1;
        forward_in_valid_tb = 0;
        sorted_col_in = 0;
        sorted_idx_in = 0;
        syndrome_tb = 0;

        $display("===============================================================");
        $display("   OSD SYSTOLIC ARRAY - FILE I/O TESTBENCH (REVERSED GOLDEN)");
        $display("===============================================================");

        // --- A. Load Static Data (H Matrix & Indices) ---
        $display("Loading H-Matrix (8784 x 936)...");
        // Assumes H_matrix_formatted.txt has binary strings (1s and 0s)
        $readmemb("H_matrix_formatted.txt", H_mem);
        
        $display("Loading Sorted Indices...");
        f_idx = $fopen("sorted_indices.txt", "r");
        if (f_idx == 0) begin $error("Error opening sorted_indices.txt"); $finish; end
        
        for (int i = 0; i < N; i++) begin
            scan_status = $fscanf(f_idx, "%d", idx_mem[i]);
        end
        $fclose(f_idx);
        
        // --- B. Open Dynamic Data (Syndromes & Golden Outputs) ---
        f_syn  = $fopen("syndromes_formatted.txt", "r");
        f_gold = $fopen("golden_formatted.txt", "r");
        
        if (f_syn == 0 || f_gold == 0) begin 
            $error("Error opening input/output files."); 
            $finish; 
        end

        // Wait for global reset
        repeat(10) @(posedge clk);
        reset = 0;
        repeat(10) @(posedge clk);

        // --- C. Main Testing Loop ---
        while (!$feof(f_syn) && !$feof(f_gold)) begin
            
            logic [M-1:0] curr_syndrome_bits;
            logic [N-1:0] curr_golden_bits_raw;
            logic [N-1:0] curr_golden_bits_reversed; // Stores the flipped version
            int s_scan, g_scan;

            // Read one line from each file
            s_scan = $fscanf(f_syn, "%b", curr_syndrome_bits);
            g_scan = $fscanf(f_gold, "%b", curr_golden_bits_raw);

            // If read was successful
            if (s_scan == 1 && g_scan == 1) begin
                
                // --- REVERSE THE GOLDEN BITS ---
                // Convert [LSB...MSB] file format to [MSB...LSB] Verilog format
                for (int k = 0; k < N; k++) begin
                    curr_golden_bits_reversed[k] = curr_golden_bits_raw[(N-1)-k];
                end
                
                $display("--------------------------------------------------");
                $display("Running Test Case %0d...", test_case_count);
                
                // 1. Apply Reset & Set Syndrome
                //reset = 1;
                syndrome_tb = curr_syndrome_bits;
                //@(posedge clk);
                //reset = 0;
                //@(posedge clk);

                // 2. Stream Data into Systolic Array
                forward_in_valid_tb = 1;
                
                for (int i = 0; i < N; i++) begin
                    @(posedge clk);
                    real_idx = idx_mem[i];
                    sorted_idx_in = real_idx[IDX_W-1:0];
                    sorted_col_in = H_mem[real_idx]; 
                    
                end
                
                @(posedge clk);
                // End of Stream
                forward_in_valid_tb = 0;
                sorted_col_in = 0;
                sorted_idx_in = 0;

                // 3. Wait for DUT Result (Watchdog Timer)
                fork
                    begin
                        wait(final_done_tb);
                    end
                    begin
                        // Latency: N + 3*M. Setting generous timeout.
                        //repeat(50000) @(posedge clk);
                        //$display("Error: Timeout on Test Case %0d", test_case_count);
                        //$finish; 
                    end
                join_any
                
                // 4. Compare Result against REVERSED Golden
                @(posedge clk); 
                
                if (final_e_hat_tb === curr_golden_bits_reversed) begin
                    pass_count++;
                    $display("  [PASS]");
                end else begin
                    fail_count++;
                    $error("  [FAIL] Mismatch!");
                    // Uncomment for detailed bit comparison (prints huge log):
                    $display("    Expected (Rev): %b", curr_golden_bits_reversed);
                    $display("    Got:            %b", final_e_hat_tb);
                end
                
              
                test_case_count++;
                  if(test_case_count == 1)
                  break;
            end
        end

        // --- D. Final Summary ---
        $display("===============================================================");
        $display("SIMULATION COMPLETE");
        $display("Total Tests: %0d", test_case_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("===============================================================");
        
        $fclose(f_syn);
        $fclose(f_gold);
        
        $finish; 
    end

endmodule