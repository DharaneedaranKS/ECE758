// --- OSD Processing Element (PE) ---
module osd_pe (
    input wire clk,
    input wire reset,
    
    // Parameters for PE's Position and Matrix Size
    parameter H_ROW_SIZE = 3, // M
    parameter IDX_SIZE   = 8,
    parameter P_POS      = 0, // Pivot position for this specific PE (0 to M-1)
    
    // Inputs from the left (or Top)
    input wire [H_ROW_SIZE-1:0] in_col,
    input wire [IDX_SIZE-1:0] in_idx,
    input wire in_valid,
    
    // Control Signal
    input wire backwards_en, // Controls forward substituition to backward substition
    
    // Outputs to the right (or discarded)
    output reg [H_ROW_SIZE-1:0] out_col,
    output reg [IDX_SIZE-1:0] out_idx,
    output reg out_valid,
    
    // Output for the Inverse Column (used during backwards phase)
    output wire [H_ROW_SIZE-1:0] inv_out_col,
    output wire [IDX_SIZE-1:0] inv_out_idx,
    output wire inv_out_valid
);

    // Internal Registers for the Fixed Pivot Column
    reg [H_ROW_SIZE-1:0] fixed_col;
    reg [IDX_SIZE-1:0] fixed_idx;
    reg is_fixed = 1'b0;

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


















