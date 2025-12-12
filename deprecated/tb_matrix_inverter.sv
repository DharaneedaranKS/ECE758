module tb_matrix_inverter;

    localparam RANK_MAX = 4;
    localparam N_DET = 4;

    logic clk, rst, start;
    logic [N_DET-1:0] Hs_cols [0:RANK_MAX-1];
    logic [$clog2(RANK_MAX+1)-1:0] rank_in; // Use fixed width
    logic done, success;
    logic [N_DET-1:0] H_inv_cols [0:RANK_MAX-1];

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    matrix_inverter #(.RANK_MAX(RANK_MAX), .N_DET(N_DET)) dut (
        .clk(clk), .rst(rst), .start(start),
        .Hs_cols(Hs_cols), .rank_in(rank_in),
        .done(done), .H_inv_cols(H_inv_cols), .success(success)
    );

    // Task to verify the inverse by checking H * H_inv == I
    task automatic verify_inverse();
        logic [N_DET-1:0] product [0:RANK_MAX-1];
        bit is_identity = 1;

        // Calculate Product = H * H_inv
        for (int i = 0; i < rank_in; i++) begin
            product[i] = '0;
            for (int j = 0; j < rank_in; j++) begin
                bit sum = 0;
                for (int k = 0; k < rank_in; k++) begin
                    // Correct matrix multiplication: P[i][j] = sum(H[i][k] * H_inv[k][j])
                    sum ^= (Hs_cols[i][k] & H_inv_cols[k][j]);
                end
                product[i][j] = sum;
            end
        end

        // Check if the product is an identity matrix
        for (int i = 0; i < rank_in; i++) begin
            for (int j = 0; j < rank_in; j++) begin
                if ((i == j && product[i][j] != 1) || (i != j && product[i][j] != 0)) begin
                    is_identity = 0;
                end
            end
        end
        
        if (is_identity)
            $display("  ? PASS: H * H_inv equals the identity matrix.");
        else
            $display("  ? FAIL: H * H_inv does NOT equal the identity matrix.");
    endtask


    initial begin
        $display("========================================");
        $display("     Matrix Inverter Test Results     ");
        $display("========================================");

        // === Test Case 1 ===
        $display("\nTest Case 1: Invertible Matrix (Paper Example)");
        rst = 1; start = 0;
        rank_in = 4;
        Hs_cols[0] = 4'b1001; // Using known-good matrix from old TC4
        Hs_cols[1] = 4'b1010;
        Hs_cols[2] = 4'b0001;
        Hs_cols[3] = 4'b0101;
        #10 rst = 0; #10 start = 1; #10 start = 0;

        wait(done); #10;
        if (success) begin
            $display("  Module reported SUCCESS.");
            verify_inverse();
        end else begin
            $display("  ? FAIL: Module reported FAILURE on an invertible matrix.");
        end

        // === Test Case 2 ===
        $display("\nTest Case 2: Singular Matrix (Zero Row)");
        rst = 1; #10 rst = 0;
        rank_in = 4;
        Hs_cols[0] = 4'b1000;
        Hs_cols[1] = 4'b0100;
        Hs_cols[2] = 4'b0000; // Singular row
        Hs_cols[3] = 4'b0001;
        #10 start = 1; #10 start = 0;
        wait(done); #10;

        if (!success)
            $display("  ? PASS: Correctly detected singular matrix (success = 0).");
        else begin
            $display("  ? FAIL: Module reported SUCCESS on a singular matrix.");
            verify_inverse();
        end

        // === Test Case 3 ===
        $display("\nTest Case 3: Identity Matrix");
        rst = 1; #10 rst = 0;
        rank_in = 4;
        Hs_cols[0] = 4'b1000;
        Hs_cols[1] = 4'b0100;
        Hs_cols[2] = 4'b0010;
        Hs_cols[3] = 4'b0001;
        #10 start = 1; #10 start = 0;
        wait(done); #10;

        if (success) begin
            $display("  Module reported SUCCESS.");
            verify_inverse();
        end else begin
            $display("  ? FAIL: Module reported FAILURE on the identity matrix.");
        end

        $display("\n========================================");
        $display("           All Tests Complete           ");
        $display("========================================");
        #100 $finish;
    end

endmodule