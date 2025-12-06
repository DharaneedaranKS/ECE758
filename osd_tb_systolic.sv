module osd_systolic_array_tb;

    localparam M = 4; // H_ROW_SIZE (Number of Syndrome Detectors)
    localparam N = 8; // N_COLS (Total Error Locations)
    localparam IDX_W = 8;
    localparam CLK_PERIOD = 10ns;

    // --- Signals for DUT Connection ---
    logic clk, reset;
    logic [M-1:0] sorted_col_in;
    logic [IDX_W-1:0] sorted_idx_in;
    logic forward_in_valid_tb;
    
    logic [M-1:0] h_inv_col_out;
    logic [IDX_W-1:0] h_inv_idx_out;
    logic h_inv_out_valid;

    // --- Golden Reference Data ---
    // Input Columns and Indices. The columns are represented LSB (Row 0) to MSB (Row 3).
    typedef packed struct {
        logic [M-1:0] col;
        logic [IDX_W-1:0] idx;
    } col_info_t;

    // FINAL CORRECTED Input Stream: 
    // Independent Set: e2, e5, e3, e7. Dependent Set: e0, e1, e4, e6.
    // The columns are the original H matrix columns (LSB R0 to MSB R3).
    col_info_t H_in_stream[N] = {
        // H_s selected columns (Indices 2, 5, 3, 7) - Must be linearly independent
        {4'b1001, IDX_W'd2}, // C1 (e2) - [1,0,0,1]^T 
        {4'b0101, IDX_W'd5}, // C2 (e5) - [1,0,1,0]^T 
        {4'b1010, IDX_W'd3}, // C3 (e3) - [0,1,0,1]^T 
        {4'b0110, IDX_W'd7}, // C4 (e7) - [0,1,1,0]^T 
        
        // Dependent Columns (e0, e1, e4, e6) - Will be eliminated/discarded
        {4'b1101, IDX_W'd0}, // C5 (e0) - [1,0,1,1]^T 
        {4'b1100, IDX_W'd1}, // C6 (e1) - [0,0,1,1]^T 
        {4'b0010, IDX_W'd4}, // C7 (e4) - [0,1,0,0]^T 
        {4'b0110, IDX_W'd6}  // C8 (e6) - [0,1,1,0]^T 
    };

    col_info_t H_inv_expected[M] = {
        // Output 1 (from PE0, index 2): Column [1, 0, 0, 1]^T
        {4'b1001, IDX_W'd2}, 
        // Output 2 (from PE1, index 5): Column [0, 1, 0, 1]^T
        {4'b1010, IDX_W'd5}, 
        // Output 3 (from PE2, index 3): Column [1, 0, 1, 1]^T
        {4'b1101, IDX_W'd3},
        // Output 4 (from PE3, index 7): Column [0, 0, 0, 1]^T
        {4'b1000, IDX_W'd7}
    };
    
    // --- Golden Reference Checker Class (Gaussian Elimination over F2) ---
    class GoldenChecker;
        // H_s stores the *reduced* columns selected by the DUT
        logic [M-1:0] H_s[M];       
        // H_inv stores the final inverse matrix (by column)
        logic [M-1:0] H_inv[M];     
        // H_idx stores the indices of the selected columns in order of selection
        logic [IDX_W-1:0] H_idx[M]; 
        int selected_count = 0;
        
        // Function to perform XOR-based Gaussian Elimination (Selection/Reduction)
        function void eliminate_and_select(logic [M-1:0] new_col, logic [IDX_W-1:0] new_idx);
            logic [M-1:0] current_col = new_col;
            
            // Forward Elimination: Reduce the column using already fixed columns
            for (int i = 0; i < selected_count; i++) begin
                // Pivot position: M-1-i
                if (current_col[M-1-i]) begin
                    current_col = current_col ^ H_s[i];
                end
            end
            
            // Selection: Check for linear independence at the next available pivot position
            if (selected_count < M && current_col[M-2-selected_count]) begin
                $display("Checker: Selected column %0d (Index %0d) at pivot %0d. Reduced Col: %b", 
                         selected_count, new_idx, M-1-selected_count, current_col);
                // Store the REDUCED column for future elimination steps
                H_s[selected_count] = current_col; 
                H_idx[selected_count] = new_idx;
                selected_count++;
            end else if (selected_count < M) begin
                $display("Checker: Discarded column (Index %0d) - linearly dependent or wrong pivot.", new_idx);
            end
        end

        // Function to perform full matrix inversion
        function void perform_inversion();
            logic [M-1:0] H_s_full[M];     // H_s matrix formed by original columns
            logic [M-1:0] A_aug[M][2*M];   // Augmented matrix [H_s | I]
            
            $display("Checker: Starting Inversion on selected H_s.");
            
            //  Re-assemble the *original* H_s columns that were selected (simplified)
            // We use the H_in_stream since the first M columns are guaranteed to be selected
            for (int i = 0; i < M; i++) begin
                H_s_full[i] = H_in_stream[i].col;
            end
            
            //  Setup Augmented Matrix [H_s | I]
            for (int r = 0; r < M; r++) begin // Row index (0 to M-1)
                for (int c = 0; c < M; c++) begin // Column index (0 to M-1)
                    // A_aug[row][col] = H_s[col][row] (Transpose/re-orient)
                    A_aug[r][c] = H_s_full[c][r]; 
                    A_aug[r][M+c] = (r == c) ? 1'b1 : 1'b0; // Identity Matrix
                end
            end
            
            //  Perform Gaussian Elimination (Row Reduction)
            for (int j = 0; j < M; j++) begin // Column index (Pivot column)
                // Find pivot row (p)
                int p = j;
                while (p < M && A_aug[p][j] == 0) p++;
                
                if (p < M) begin
                    // Swap rows if necessary
                    if (p != j) begin
                        logic [2*M-1:0] temp_row;
                        temp_row = A_aug[j];
                        A_aug[j] = A_aug[p];
                        A_aug[p] = temp_row;
                    end
                    
                    // Eliminate other rows (above and below pivot)
                    for (int i = 0; i < M; i++) begin
                        if (i != j && A_aug[i][j] == 1) begin
                            A_aug[i] = A_aug[i] ^ A_aug[j]; // XOR row operation
                        end
                    end
                end
            end
            
            //  Extract Inverse H_s^{-1} (Right half of the reduced augmented matrix)
            // H_inv[column_index] contains the column vector.
            for (int i = 0; i < M; i++) begin 
                for (int j = 0; j < M; j++) begin 
                    // H_inv[col_idx][row_idx] = A_aug[row_idx][M + col_idx]
                    H_inv[i][j] = A_aug[j][M+i]; 
                end
            end
        endfunction

        // Function to compare DUT output against the expected inverse
        function int check_output(col_info_t dut_output[M]);
            int errors = 0;
            $display("Expected Output Order (PE0 to PE3): Index 2 -> Index 5 -> Index 3 -> Index 7");

            for (int i = 0; i < M; i++) begin
                logic [M-1:0] expected_col = H_inv_expected[i].col;
                logic [IDX_W-1:0] expected_idx = H_inv_expected[i].idx;
                
                $write("Output %0d (Index %0d): DUT Col=%b, DUT Idx=%0d | ", i, expected_idx, dut_output[i].col, dut_output[i].idx);
                
                if (dut_output[i].col === expected_col && dut_output[i].idx === expected_idx) begin
                    $display("PASS: Golden Col=%b", expected_col);
                end else begin
                    $display("FAIL: Expected Col=%b, Expected Idx=%0d", expected_col, expected_idx);
                    errors++;
                end
            end
            return errors;
        end
    endclass

    GoldenChecker checker_handle;

    osd_systolic_array_top #(.H_ROW_SIZE(M), .IDX_SIZE(IDX_W), .N_COLS(N))
    DUT (
        .clk(clk),
        .reset(reset),
        .sorted_col_in(sorted_col_in),
        .sorted_idx_in(sorted_idx_in),
        .h_inv_col_out(h_inv_col_out),
        .h_inv_idx_out(h_inv_idx_out),
        .h_inv_out_valid(h_inv_out_valid)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        int errors;
        col_info_t dut_output_array[M];
        int output_count = 0;
        
        checker_handle = new();

        // 1. Reset DUT
        reset = 1;
        forward_in_valid_tb = 0;
        @(posedge clk);
        #CLK_PERIOD;
        reset = 0;
        
        forward_in_valid_tb = 1;
        
        $display("\n--- Starting Forward Elimination Phase (N=%0d cycles) ---", N);
        
        for (int i = 0; i < N; i++) begin
            @(posedge clk);
            sorted_col_in = H_in_stream[i].col;
            sorted_idx_in = H_in_stream[i].idx;
            
            checker_handle.eliminate_and_select(H_in_stream[i].col, H_in_stream[i].idx);
        end
        
        // Signal DUT that input is done (transition to S_FORWARD_FINAL)
        forward_in_valid_tb = 0;
        
        $display("\n--- Starting Final Forward Propagation Phase (M=%0d cycles) ---", M);
        repeat (M) @(posedge clk); 
        
        $display("\n--- Starting Backwards Elimination/Output Phase (M=%0d cycles) ---", M);
        
        for (int i = 0; i < M; i++) begin
            @(posedge clk);
            if (h_inv_out_valid) begin
                dut_output_array[output_count].col = h_inv_col_out;
                dut_output_array[output_count].idx = h_inv_idx_out;
                output_count++;
            end
        end
        
        // 5. Run Golden Reference Inversion and Compare
        if (checker_handle.selected_count != M) begin
            $fatal(1, "Checker failed to select a full-rank M=%0d submatrix. Selection count was %0d.", M, checker_handle.selected_count);
        }
        
        // Compare DUT output array (sorted by PE) with the hardcoded expected array.
        errors = checker_handle.check_output(dut_output_array);
        
        if (errors == 0) begin
            $display("\n*** TEST PASSED! *** All %0d inverse columns matched the golden reference.", M);
        end else begin
            $error("### TEST FAILED! ### Total errors: %0d", errors);
        end
        
        $finish;
    end

endmodule
