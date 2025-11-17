module lse_solver #(parameter RANK_MAX = 936, N_ERR = 8784)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [RANK_MAX-1:0] syndrome,                             // Syndrome vector
    input  logic [RANK_MAX-1:0] H_inv_cols [0:RANK_MAX-1],            // Inverted matrix columns
    input  logic [($clog2(N_ERR)-1):0] used_indices [0:RANK_MAX-1],   // Where to embed each compact bit
    input  logic [($clog2(RANK_MAX)-1):0] rank_in,                    // Actual rank

    output logic [N_ERR-1:0] e_hat,                                   // Final 8784-bit error vector
    output logic done
);

    logic [RANK_MAX-1:0] e_compact;  // Compact 936-bit error vector
    int unsigned j;
    
    typedef enum logic [1:0] {IDLE, COMPUTE, EXPAND, DONE} state_t;
    state_t state;
    
    // Combinational logic for matrix-vector multiply (one row at a time)
    logic sum_next;
    logic [RANK_MAX-1:0] masked_col;
    
    always_comb begin
        // Mask the column with syndrome (AND each bit with syndrome bit)
        for (int unsigned i = 0; i < RANK_MAX; i++) begin
            if (i < rank_in) begin
                masked_col[i] = H_inv_cols[j][i] & syndrome[i];
            end else begin
                masked_col[i] = 1'b0;
            end
        end
        
        // XOR reduction of masked column
        sum_next = ^masked_col;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            e_hat      <= '0;
            e_compact  <= '0;
            done       <= 0;
            state      <= IDLE;
            j          <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        e_compact  <= '0;
                        e_hat      <= '0;
                        done       <= 0;
                        j          <= 0;
                        state      <= COMPUTE;
                    end
                end
                
                COMPUTE: begin
                    // Compute one element of e_compact per cycle
                    e_compact[j] <= sum_next;
                    
                    if (j == rank_in - 1) begin
                        state <= EXPAND;
                        j <= 0;
                    end else begin
                        j <= j + 1;
                    end
                end
                
                EXPAND: begin
                    // Expand one bit per cycle
                    if (j < rank_in) begin
                        e_hat[used_indices[j]] <= e_compact[j];
                        j <= j + 1;
                    end else begin
                        state <= DONE;
                        done <= 1;
                    end
                end
                
                DONE: begin
                    // Stay here until reset or new start
                    if (start) begin
                        e_compact  <= '0;
                        e_hat      <= '0;
                        done       <= 0;
                        j          <= 0;
                        state      <= COMPUTE;
                    end
                end
            endcase
        end
    end

endmodule