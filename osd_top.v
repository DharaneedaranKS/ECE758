//  OSD Systolic Array Top Module with FSM Control 
module osd_systolic_array_top (
    input wire clk,
    input wire reset,
    
    // Inputs (from BP Sorting Module)
    input wire [H_ROW_SIZE-1:0] sorted_col_in,  // H column
    input wire [IDX_SIZE-1:0] sorted_idx_in,    // Index (tag)
    
    // Outputs (Inverse Matrix Stream)
    output wire [H_ROW_SIZE-1:0] h_inv_col_out,
    output wire [IDX_SIZE-1:0] h_inv_idx_out,
    output wire h_inv_out_valid
);

    parameter H_ROW_SIZE = 3; // M: Number of Syndromes/Detectors
    parameter IDX_SIZE   = 8; 
    localparam NUM_PES = H_ROW_SIZE;
    localparam N_COLS = 8; // N: Total number of columns (Error Locations)

    // FSM States
    localparam S_IDLE              = 2'd0;
    localparam S_FORWARD_INPUT     = 2'd1;
    localparam S_FORWARD_FINAL     = 2'd2;
    localparam S_BACKWARDS_OUTPUT  = 2'd3;

    reg [1:0] state = S_IDLE;
    reg [IDX_SIZE-1:0] cycle_counter = 0;
    
    // Control Wires
    reg  forward_in_valid = 1'b0;
    reg  backwards_en = 1'b0;

    // Wires connecting the PEs
    wire [NUM_PES:0][H_ROW_SIZE-1:0] pe_col_w;
    wire [NUM_PES:0][IDX_SIZE-1:0] pe_idx_w;
    wire [NUM_PES:0] pe_valid_w;

    // Inverse Output Wires
    wire [NUM_PES-1:0][H_ROW_SIZE-1:0] pe_inv_out_col;
    wire [NUM_PES-1:0][IDX_SIZE-1:0] pe_inv_out_idx;
    wire [NUM_PES-1:0] pe_inv_out_valid;

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
                    if (/* start_signal */ 1'b1) begin // Assume immediate start for demo
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
            osd_pe #(
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
    
    reg [H_ROW_SIZE-1:0] output_col_reg = 0;
    reg [IDX_SIZE-1:0] output_idx_reg = 0;
    reg output_valid_reg = 0;
    
    // Output selector for the inverse column
    always @(posedge clk) begin
        if (state == S_BACKWARDS_OUTPUT) begin  
            // Output PEs fixed content sequentially based on the counter.
            case (cycle_counter)
                0: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[0], pe_inv_out_idx[0], pe_inv_out_valid[0]};
                1: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[1], pe_inv_out_idx[1], pe_inv_out_valid[1]};
                2: {output_col_reg, output_idx_reg, output_valid_reg} <= {pe_inv_out_col[2], pe_inv_out_idx[2], pe_inv_out_valid[2]};
                default: {output_col_reg, output_idx_reg, output_valid_reg} <= 0;
            endcase
        end else begin
             output_valid_reg <= 1'b0;
        end
    end
    
    assign h_inv_col_out = output_col_reg;
    assign h_inv_idx_out = output_idx_reg;
    assign h_inv_out_valid = output_valid_reg;

endmodule

