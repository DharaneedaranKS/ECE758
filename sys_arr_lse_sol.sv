module sys_arr_lse_sol #(parameter H_ROW_SIZE = 4, parameter IDX_SIZE = 8, parameter N_COLS = 8)
(
    input logic clk,
    input logic reset,
    
    // Inputs (from BP Sorting Module)
    input logic                  sorter_vld,
    input logic                  act_sa,
    input logic [H_ROW_SIZE-1:0] sorted_col_in,  // H column
    input logic [$clog2(N_COLS)-1:0] sorted_idx_in,    // Index (tag)
    
    // NEW: Input for the Solver (The error pattern we are trying to fix)
    input logic [H_ROW_SIZE-1:0] syndrome_in,
    
    // Outputs (Inverse Matrix Stream)
    output logic [H_ROW_SIZE-1:0] h_inv_col_out,
    output logic [IDX_SIZE-1:0] h_inv_idx_out,
    output logic h_inv_out_valid,
    
    // NEW: Final Answer from the Solver
    output logic [N_COLS-1:0]     final_e_hat,
    output logic final_done
);

     // M: Number of Syndromes/Detectors
 
    localparam NUM_PES = H_ROW_SIZE;
    //localparam N_COLS = 8; // N: Total number of columns (Error Locations)

    // FSM States
    localparam S_IDLE              = 2'd0;
    localparam S_FORWARD_INPUT     = 2'd1;
    localparam S_FORWARD_FINAL     = 2'd2;
    localparam S_BACKWARDS_OUTPUT  = 2'd3;

    logic [1:0] state;// = S_IDLE;
    logic [IDX_SIZE-1:0] cycle_counter;
    logic [1:0] lse_state_in = 0;
    
    // Control Wires
    logic  forward_in_valid = 1'b0;
    logic  backwards_en = 1'b0;
    logic systolic_done = 1'b0;

    // Wires connecting the PEs
    logic [NUM_PES:0][H_ROW_SIZE-1:0] pe_col_w;
    logic [NUM_PES:0][IDX_SIZE-1:0] pe_idx_w;
    logic [NUM_PES:0] pe_valid_w;

    // Inverse Output Wires
    logic [NUM_PES-1:0][H_ROW_SIZE-1:0] pe_inv_out_col;
    logic [NUM_PES-1:0][IDX_SIZE-1:0] pe_inv_out_idx;
    logic [NUM_PES-1:0] pe_inv_out_valid;

    // --- FSM Control Logic ---
    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            cycle_counter <= 0;
            forward_in_valid <= 1'b0;
            backwards_en <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    // Wait for start signal (e.g., BP failure)
                    if (!systolic_done && (sorter_vld | act_sa)) begin // Assume immediate start for demo
                        state <= S_FORWARD_INPUT;
                        cycle_counter <= 0;
                        forward_in_valid <= 1'b1;
                    end
                end
                
                // N cycles for all columns to stream in
                S_FORWARD_INPUT: begin
                    cycle_counter <= cycle_counter + 1;
                    if (cycle_counter == N_COLS - 1) begin
                        state <= S_FORWARD_FINAL;
                        forward_in_valid <= 1'b0; // Stop input stream
                        cycle_counter <= 0;
                    end
                end
                
                // M cycles for final column eliminations to propagate
                S_FORWARD_FINAL: begin
                    cycle_counter <= cycle_counter + 1;
                    // M cycles to flush the array after the last input
                    if (cycle_counter == NUM_PES - 1) begin
                        state <= S_BACKWARDS_OUTPUT;
                        backwards_en <= 1'b1;
                        cycle_counter <= 0;
                    end
                end
                
                // M cycles to activate and output the inverse columns
                S_BACKWARDS_OUTPUT: begin
                    cycle_counter <= cycle_counter + 1;
                    if (cycle_counter == NUM_PES - 1) begin
                        state <= S_IDLE;
                        backwards_en <= 1'b0;
                        systolic_done <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // --- PE Array Instantiation ---
    
    // Input to the first PE (P0)
    // NOTE: This assumes the BP module delivers N columns synchronously.
    assign pe_col_w[0] = sorted_col_in;
    assign pe_idx_w[0] = sorted_idx_in;
    assign pe_valid_w[0] = forward_in_valid;
    
    genvar i;
    generate
        for (i = 0; i < NUM_PES; i = i + 1) begin : pe_array
            sa_pe #(
                .H_ROW_SIZE(H_ROW_SIZE),
                .IDX_SIZE(IDX_SIZE),
                .P_POS(NUM_PES - 1 - i) // P0 works on pivot M-1, P1 on M-2, etc.
            ) pe_inst (
                .clk(clk),
                .reset(reset),
                
                .in_col(pe_col_w[i]),
                .in_idx(pe_idx_w[i]),
                .in_valid(pe_valid_w[i]),
                .backwards_en(backwards_en),
                
                .out_col(pe_col_w[i+1]),
                .out_idx(pe_idx_w[i+1]),
                .out_valid(pe_valid_w[i+1]),
                
                .inv_out_col(pe_inv_out_col[i]),
                .inv_out_idx(pe_inv_out_idx[i]),
                .inv_out_valid(pe_inv_out_valid[i])
            );
        end
    endgenerate

    // Final Output Selection
    // Need to revisit all the comments below as these steps are vital (TODO) 
    // The inverse columns are outputted sequentially (M columns over M cycles).
    // This logic cycles through the 'inv_out_col' outputs during S_BACKWARDS_OUTPUT.
    
    // Since all PEs output simultaneously, an M-to-1 multiplexer selects the column
    // corresponding to the current output cycle (i.e., the column that exits after 
    // M cycles of backwards propagation).
    
    // We will use a simple fixed output for this conceptual model, assuming a linear 
    // sequence from P0 to PM-1 is sufficient to represent the M output cycles.
    
    logic [H_ROW_SIZE-1:0] output_col_reg = 0;
    logic [IDX_SIZE-1:0] output_idx_reg = 0;
    logic output_valid_reg = 0;
    
    // Output selector for the inverse column
    /*always @(posedge clk) begin
        if (state == S_BACKWARDS_OUTPUT) begin  
            // Output PEs fixed content sequentially based on the counter.
            case (cycle_counter)
                0: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[0], pe_inv_out_idx[0], pe_inv_out_valid[0]};
                1: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[1], pe_inv_out_idx[1], pe_inv_out_valid[1]};
                2: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[2], pe_inv_out_idx[2], pe_inv_out_valid[2]};
                3: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[3], pe_inv_out_idx[3], pe_inv_out_valid[3]};
                default: {output_col_reg, output_idx_reg, output_valid_reg} <= 0;
            endcase
        end else begin
             output_valid_reg <= 1'b0;
        end
    end*/
      always @(posedge clk or posedge reset) begin
            if (reset) begin
                output_col_reg <= 0;
                output_idx_reg <= 0;
                output_valid_reg <= 0;
            end
            else if (state == S_BACKWARDS_OUTPUT) begin  
            // Output PEs fixed content sequentially based on the counter.
            // Using generic array indexing instead of hardcoded case statement
            // This works for any H_ROW_SIZE
            output_col_reg   <= pe_inv_out_col[cycle_counter];
            output_idx_reg   <= pe_inv_out_idx[cycle_counter];
            output_valid_reg <= pe_inv_out_valid[cycle_counter];
        end else begin
             output_valid_reg <= 1'b0;
        end
    end
    
    assign h_inv_col_out = output_col_reg;
    assign h_inv_idx_out = output_idx_reg;
    assign h_inv_out_valid = output_valid_reg;

    // NEW SECTION: INTEGRATION WITH LSE SOLVER

    // 1. Determine Solver Index Width
    // Solver uses $clog2(N_ERR). For N_COLS=8, this is 3 bits.
    localparam SOLVER_IDX_W = $clog2(N_COLS);

    // 2. The Buffers
    logic [H_ROW_SIZE-1:0] H_inv_matrix_buffer [0:H_ROW_SIZE-1];
    
    // Define buffer with the width the SOLVER expects (3 bits)
    logic [SOLVER_IDX_W-1:0] indices_buffer_compact [0:H_ROW_SIZE-1];
    
    logic [IDX_SIZE-1:0]   buffer_counter;
    
    // Changed: 'matrix_loaded' is no longer a latching flag, we use a pulse register
    logic                  start_solver_pulse;
    
    always_ff @(posedge clk) begin
        if(reset) begin
            lse_state_in <= S_IDLE;
        end 
        else begin
            lse_state_in <= state;
        end
     end
        
    // 3. Buffer Capture & Trigger Logic
    always_ff @(posedge clk) begin
        if (reset) begin
            buffer_counter <= 0;
            start_solver_pulse <= 0;
            for (integer j=0; j<H_ROW_SIZE; j+=1) begin
                H_inv_matrix_buffer[j] <= 0;
                indices_buffer_compact[j] <= 0;
             end
            
        end else if (lse_state_in == S_BACKWARDS_OUTPUT && h_inv_out_valid) begin
            // Store Column
            H_inv_matrix_buffer[buffer_counter] <= h_inv_col_out;
            
            // Truncate the 8-bit index down to 3 bits for the solver
            indices_buffer_compact[buffer_counter] <= h_inv_idx_out[SOLVER_IDX_W-1:0];
            
            buffer_counter <= buffer_counter + 1;
        end else if (lse_state_in == S_IDLE && buffer_counter == NUM_PES && !start_solver_pulse) begin
            // Pulse the start signal exactly once when back in IDLE with a full buffer
            start_solver_pulse <= 1;
        end else begin
            start_solver_pulse <= 0; // Clear pulse immediately
        end
    end

    // 4. Trigger Logic
    logic start_solver;
    assign start_solver = start_solver_pulse;

    // 5. Instantiate the Solver
    lse_solver #(
        .RANK_MAX(H_ROW_SIZE), 
        .N_ERR(N_COLS) 
    ) u_solver (
        .clk(clk),
        .rst(reset),
        .start(start_solver),
        .syndrome(syndrome_in),
        .H_inv_cols(H_inv_matrix_buffer),
        
        // Connect the COMPACT buffer (3 bits) instead of the 8-bit one
        .used_indices(indices_buffer_compact),
        
        // Cast NUM_PES to correct width
        .rank_in(NUM_PES[$clog2(H_ROW_SIZE+1)-1:0]),
        
        .e_hat(final_e_hat),
        .done(final_done)
    );
endmodule