module tb_matrix_selector;

    localparam N_DET = 4;      // 4-bit columns
    localparam N_ERR = 8;      // 8 total columns
    localparam RANK_MAX = 4;   // Max 4 independent columns
    
    logic clk;
    logic rst;
    logic start;
    
    logic [$clog2(N_ERR)-1:0] sorted_indices [0:N_ERR-1];
    logic [N_DET-1:0] H_data_in;
    logic [$clog2(N_ERR)-1:0] H_addr;
    
    logic done;
    logic [N_DET-1:0] Hs_cols [0:RANK_MAX-1];
    logic [$clog2(N_ERR)-1:0] used_indices [0:RANK_MAX-1];
    
    logic [$clog2(RANK_MAX+1)-1:0] rank_out;
    logic [$clog2(N_ERR+1):0] scan_idx_out;
    
    // Memory to store H matrix columns
    logic [N_DET-1:0] H_matrix [0:N_ERR-1];
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    

    matrix_selector #(
        .N_DET(N_DET),
        .N_ERR(N_ERR),
        .RANK_MAX(RANK_MAX)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sorted_indices(sorted_indices),
        .H_data_in(H_data_in),
        .H_addr(H_addr),
        .scan_idx_out(scan_idx_out),
        .done(done),
        .Hs_cols(Hs_cols),
        .used_indices(used_indices),
        .rank_out(rank_out)
    );
    
    // Memory read logic (simulates H matrix storage)
    always_ff @(posedge clk) begin
        H_data_in <= H_matrix[H_addr];
    end
    
    // Test stimulus
    initial begin
        $display("========================================");
        $display("     Matrix Selector Test Results     ");
        $display("========================================");
        
        // Initialize
        rst = 1;
        start = 0;
        
        // Initialize H matrix with test data
        H_matrix[0]  = 4'b1010;  // c0
        H_matrix[1]  = 4'b0110;  // c1 
        H_matrix[2]  = 4'b1001;  // c2
        H_matrix[3]  = 4'b0101;  // c3 
        H_matrix[4]  = 4'b1101;  // c4 
        H_matrix[5]  = 4'b1010;  // c5
        H_matrix[6]  = 4'b0110;  // c6 
        H_matrix[7]  = 4'b0001;  // c7 
        

        // Sorted indices: 2, 5, 3, 7, 0, 4, 1, 6
        sorted_indices[0] = 2;
        sorted_indices[1] = 5;
        sorted_indices[2] = 3; 
        sorted_indices[3] = 7; 
        sorted_indices[4] = 0; 
        sorted_indices[5] = 4;
        sorted_indices[6] = 1;
        sorted_indices[7] = 6;  
        
        // Release reset
        #20 rst = 0;
        
        // Start selection
        #10 start = 1;
        #10 start = 0;
        
        // Wait for completion
        wait(done);
        #20;
        
        // Display results
        $display("\nTest Case 1: Select 4 independent columns");
        $display("  Rank achieved: %0d (out of max %0d)", rank_out, RANK_MAX);
        
        $display("\n  Selected columns (Format: Pos, Col_Idx, Col_Val):");
        for (int i = 0; i < rank_out; i++) begin
            $display("    %0d: Column %2d = %4b", 
                     i, used_indices[i], Hs_cols[i]);
        end
        
        // Verify independence (basic check)
        if (rank_out == RANK_MAX) begin
            $display("  ? PASS: Found full rank!");
        end else begin
            $display("  ? FAIL: Did not achieve full rank");
        end
        
        $display("\n========================================");
        $display("           All Tests Complete           ");
        $display("========================================");
        
        #100 $finish;
    end
    

endmodule