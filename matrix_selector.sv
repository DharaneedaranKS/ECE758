module matrix_selector #(parameter N_DET = 936, parameter N_ERR = 8784, parameter RANK_MAX = 936)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [$clog2(N_ERR)-1:0] sorted_indices [0:N_ERR-1],
    input  logic [N_DET-1:0] H_data_in,
    output logic [$clog2(N_ERR)-1:0] H_addr,

    output logic done,
    output logic [N_DET-1:0] Hs_cols [0:RANK_MAX-1],
    output logic [$clog2(N_ERR)-1:0] used_indices [0:RANK_MAX-1],
    output logic [$clog2(RANK_MAX)-1:0] rank_out
);

    logic [N_DET-1:0] selected_cols [0:RANK_MAX-1];
    logic [$clog2(N_ERR)-1:0] selected_indices [0:RANK_MAX-1];
    logic [$clog2(RANK_MAX)-1:0] rank;
    logic selecting;
    logic [$clog2(N_ERR)-1:0] scan_idx;

    logic is_indep;
    logic [N_DET-1:0] xor_chain [0:RANK_MAX];
    logic [N_DET-1:0] xor_result;
    
    // Independence check using XOR chain
    always_comb begin
        xor_chain[0] = H_data_in;
        for (int unsigned i = 0; i < RANK_MAX; i++) begin
            if (i < rank) begin
                xor_chain[i+1] = xor_chain[i] ^ selected_cols[i];
            end else begin
                xor_chain[i+1] = xor_chain[i];
            end
        end
        xor_result = xor_chain[rank];
        is_indep = |xor_result; // Check if any bit is 1 (not zero vector)
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rank <= 0;
            scan_idx <= 0;
            selecting <= 0;
            done <= 0;
        end else begin
            if (start && !selecting) begin
                rank <= 0;
                scan_idx <= 0;
                selecting <= 1;
                done <= 0;
            end else if (selecting && rank < RANK_MAX && scan_idx < N_ERR) begin
                H_addr <= sorted_indices[scan_idx];
                if (is_indep) begin
                    selected_cols[rank]    <= H_data_in;
                    selected_indices[rank] <= sorted_indices[scan_idx];
                    rank <= rank + 1;
                end
                scan_idx <= scan_idx + 1;
                if (rank == $unsigned(RANK_MAX - 1)) begin
                    selecting <= 0;
                    done <= 1;
                end
            end
        end
    end

    assign Hs_cols = selected_cols;
    assign used_indices = selected_indices;
    assign rank_out = rank;

endmodule