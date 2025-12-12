module tb_lse_solver;

    localparam RANK_MAX = 4;   // 4x4 system
    localparam N_ERR = 8;     // Expand to 8-bit error vector
    
    logic clk;
    logic rst;
    logic start;
    
    logic [RANK_MAX-1:0] syndrome;
    logic [RANK_MAX-1:0] H_inv_cols [0:RANK_MAX-1];
    logic [$clog2(N_ERR)-1:0] used_indices [0:RANK_MAX-1];
    logic [($clog2(RANK_MAX+1)-1):0] rank_in;
    
    logic [N_ERR-1:0] e_hat;
    logic done;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // DUT instantiation
    lse_solver #(
        .RANK_MAX(RANK_MAX),
        .N_ERR(N_ERR)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .syndrome(syndrome),
        .H_inv_cols(H_inv_cols),
        .used_indices(used_indices),
        .rank_in(rank_in),
        .e_hat(e_hat),
        .done(done)
    );
    
    logic [RANK_MAX-1:0] e_compact;
    
    // Helper function to verify the solution
    function automatic bit verify_solution();
        logic [RANK_MAX-1:0] computed_e_compact;
        
        // 1. Extract the compact error vector from the full e_hat
        for (int i = 0; i < rank_in; i++) begin
            e_compact[i] = e_hat[used_indices[i]];
        end
        
        // 2. Compute the expected e_compact = H_inv * syndrome
        computed_e_compact = '0;
        for (int j = 0; j < rank_in; j++) begin // j = row index of result
            logic sum = 0;
            for (int i = 0; i < rank_in; i++) begin // i = column index
                sum ^= (H_inv_cols[i][(RANK_MAX-1) - j] & syndrome[(RANK_MAX-1) - i]);
            end
            computed_e_compact[j] = sum;
        end
        
        // 3. Return 1 for pass, 0 for fail
        return (e_compact == computed_e_compact);
    endfunction
    
    // Test stimulus
    initial begin
        logic [RANK_MAX-1:0] expected_e_compact;
        
        $display("========================================");
        $display("     LSE Solver Testbench Results     ");
        $display("========================================");
        
        // Initialize
        rst = 1;
        start = 0;
        
        // Test Case 1: Simple system
        $display("\nTest Case 1: Basic (Identity H_inv, S=1011)");
        rank_in = 4;
        H_inv_cols[0] = 4'b0001; // Col 0
        H_inv_cols[1] = 4'b0010; // Col 1
        H_inv_cols[2] = 4'b0100; // Col 2
        H_inv_cols[3] = 4'b1000; // Col 3
        syndrome = 4'b1011;
        used_indices[0] = 2;
        used_indices[1] = 5;
        used_indices[2] = 7;
        used_indices[3] = 0;
        
        #20 rst = 0; #10 start = 1; #10 start = 0;
        wait(done); #1;
        

        if (verify_solution())
            $display("  ✓ PASS: e_compact matches expected value!");
        else
            $display("  ✗ FAIL: e_compact mismatch");
        
        
        // Test Case 2: Different H_inv
        $display("\nTest Case 2: Non-trivial (H_inv, S=1100)");
        rst = 1; #20 rst = 0;
        rank_in = 4;
        
        H_inv_cols[0] = 4'b0011; // Col 0
        H_inv_cols[1] = 4'b0110; // Col 1
        H_inv_cols[2] = 4'b1100; // Col 2
        H_inv_cols[3] = 4'b1001; // Col 3
        syndrome = 4'b1100;
        used_indices[0] = 0;
        used_indices[1] = 3;
        used_indices[2] = 6;
        used_indices[3] = 2;
        
        #10 start = 1; #10 start = 0;
        wait(done); #1;
        
     
        if (verify_solution())
            $display("  ✓ PASS: e_compact matches expected value!");
        else
            $display("  ✗ FAIL: e_compact mismatch");

        
        // Test Case 3: All zeros
        $display("\nTest Case 3: Zero Syndrome (Rank 0)");
        rst = 1; #20 rst = 0;
        rank_in = 0;
        syndrome = 4'b0000;
        
        #10 start = 1; #10 start = 0;
        wait(done); #1;
        
        if (e_hat == '0)
            $display("  ✓ PASS: All zeros as expected");
        else
            $display("  ✗ FAIL: Expected all zeros");

        // Test Case 4: Paper Example
        $display("\nTest Case 4: Paper Example (H_inv, S=1101)");
        rst = 1; #20 rst = 0;
        rank_in = 4;
        
        H_inv_cols[0] = 4'b1001; 
        H_inv_cols[1] = 4'b0101; 
        H_inv_cols[2] = 4'b1011;
        H_inv_cols[3] = 4'b0001; 
        
        syndrome = 4'b1101;
        
        used_indices[0] = 2; 
        used_indices[1] = 5; 
        used_indices[2] = 7; 
        used_indices[3] = 3; 
        
        expected_e_compact = 4'b0110;
        
        #10 start = 1; #10 start = 0;
        wait(done); #1;

        
        if (verify_solution())
            $display("  ✓ PASS: e_compact matches expected value (4'b0110)!");
        else
            $display("  ✗ FAIL: e_compact mismatch (Expected 4'b0110)");
        
        $display("\n========================================");
        $display("           All Tests Complete           ");
        $display("========================================");
        
        #100 $finish;
    end

endmodule