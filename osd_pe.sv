// --- OSD Processing Element (PE) ---

module osd_pe #( parameter H_ROW_SIZE = 4, parameter IDX_SIZE   = 8, parameter P_POS = 0)
(
    input logic clk,
    input logic reset,
    
    // Inputs from the left (or Top)
    input logic [H_ROW_SIZE-1:0] in_col,
    input logic [IDX_SIZE-1:0] in_idx,
    input logic in_valid,
    
    // Control Signal
    input logic backwards_en, // Controls forward substituition to backward substition
    
    // Outputs to the right (or discarded)
    output logic [H_ROW_SIZE-1:0] out_col,
    output logic [IDX_SIZE-1:0] out_idx,
    output logic out_valid,
    
    // Output for the Inverse Column (used during backwards phase)
    output logic [H_ROW_SIZE-1:0] inv_out_col,
    output logic [IDX_SIZE-1:0] inv_out_idx,
    output logic inv_out_valid
);

    // Internal Registers for the Fixed Pivot Column
    logic [H_ROW_SIZE-1:0] fixed_col;
    logic [IDX_SIZE-1:0] fixed_idx;
    logic is_fixed = 1'b0;

    // Output is the content of the PE when backwards elimination is active
    assign inv_out_col = fixed_col; 
    assign inv_out_idx = fixed_idx;
    assign inv_out_valid = backwards_en & is_fixed;

    always @(posedge clk) begin
        if (reset) begin
            fixed_col <= 0;
            fixed_idx <= 0;
            is_fixed  <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            // --- FORWARD ELIMINATION / SELECTION PHASE ---
            if (~backwards_en) begin 
                if (in_valid) begin
                    // 1. Keep it (Fix pivot)
                    if (~is_fixed && in_col[P_POS]) begin
                        fixed_col <= in_col;
                        fixed_idx <= in_idx;
                        is_fixed  <= 1'b1;
                        out_valid <= 1'b0; // Column fixed here, not passed right
                    end
                    // 2. Perform Gaussian Elimination
                    else if (is_fixed && in_col[P_POS]) begin
                        out_col <= in_col ^ fixed_col;
			out_col[P_POS] <= 1; 
                        out_idx <= in_idx;
                        out_valid <= 1'b1;
                    end
                    // 3. Pass unmodified
                    else begin
                        out_col <= in_col;
                        out_idx <= in_idx;
                        out_valid <= 1'b1;
                    end
                end else begin
                    out_valid <= 1'b0;
                end
            end
            
            // --- BACKWARDS ELIMINATION / INVERSION PHASE ---
            else begin
		// need to understand and work here (TODO)
                out_valid <= 1'b0; 
            end
        end
    end
endmodule