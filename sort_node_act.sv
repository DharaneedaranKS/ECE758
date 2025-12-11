module sort_node_act #(
    parameter WIDTH = 8,
    parameter MAX_VAL = 8'hFF, // Explicit 8-bit FF
    parameter NUM_NODES = 8
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             mode_load,
    input  logic             clear,

    input  logic [$clog2(NUM_NODES)-1:0] idx_in,
    output logic [$clog2(NUM_NODES)-1:0] idx_out,
    output logic [$clog2(NUM_NODES)-1:0] my_idx,
    
    // Left side
    input  logic [WIDTH-1:0] val_in_left,
    output logic [WIDTH-1:0] val_out_left,
    
    // Right side
    input  logic [WIDTH-1:0] val_in_right,
    output logic  [WIDTH-1:0] val_out_right
);

    logic [WIDTH-1:0] L_reg;
    logic [$clog2(NUM_NODES)-1:0] L_idx;

    logic [WIDTH-1:0] R_reg;
    logic [$clog2(NUM_NODES)-1:0] R_idx;

    // In unload mode, we output the stored value to the left
    assign val_out_left = L_reg;
    assign val_out_right = R_reg;
    assign idx_out      = R_idx;
    assign my_idx       = L_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            L_reg         <= MAX_VAL;
            L_idx         <= 0;
            R_reg         <= MAX_VAL;
            R_idx         <= 0;
        end else if (clear) begin
            L_reg         <= MAX_VAL;
            L_idx         <= 0;
            R_reg         <= MAX_VAL;
            R_idx         <= 0;
        end else begin
            if (mode_load) begin
                // --- SORT MODE ---
                // If New Input <= Stored Min:
                // 1. Store New Input
                // 2. Push OLD Stored Min to Right
                if (val_in_left <= L_reg) begin
                    L_reg         <= val_in_left;
                    L_idx         <= idx_in;
                    R_reg          <= L_reg;
                    R_idx          <= L_idx;
                end else begin
                // If New Input > Stored Min:
                // 1. Keep Stored Min
                // 2. Push New Input to Right
                    R_reg       <= val_in_left;
                    R_idx       <= idx_in;
                end
            end 
        end
    end

endmodule