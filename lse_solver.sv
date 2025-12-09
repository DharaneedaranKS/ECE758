module lse_solver #(parameter RANK_MAX = 936, N_ERR = 8784)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [RANK_MAX-1:0] syndrome,                             // Syndrome vector
    input  logic [RANK_MAX-1:0] H_inv_cols [0:RANK_MAX-1],            // Inverted matrix (array of COLUMNS)
    input  logic [($clog2(N_ERR)-1):0] used_indices [0:RANK_MAX-1],   // Where to embed each compact bit
    input  logic [($clog2(RANK_MAX+1)-1):0] rank_in,                  // Actual rank

    output logic [N_ERR-1:0] e_hat,                                   // Final 8784-bit error vector
    output logic done
);

    logic [RANK_MAX-1:0] e_compact;  // Compact 936-bit error vector
    
    // --- Pipelining Registers ---
    logic [$clog2(RANK_MAX)-1:0] j; // ROW counter (outer loop)
    logic [$clog2(RANK_MAX)-1:0] i; // COL counter (inner loop)
    logic sum_reg;                  // 1-bit accumulator for the dot product
    
    typedef enum logic [2:0] {IDLE, COMPUTE_START, ACCUMULATE, EXPAND_START, EXPAND, DONE} state_t;
    state_t state;
    
    // --- Combinational logic for ONE step of the dot product ---
    // This is a very small and fast combinational path.
    logic bit_to_add;
    always_comb begin
        // H_inv[j][i] & syndrome[i]
        bit_to_add = H_inv_cols[i][(RANK_MAX-1) - j] & syndrome[(RANK_MAX-1) - i];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            e_hat     <= '0;
            e_compact <= '0;
            done      <= 1'b0;
            state     <= IDLE;
            j         <= '0;
            i         <= '0;
            sum_reg   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        e_compact <= '0;
                        e_hat     <= '0;
                        done      <= 1'b0;
                        j         <= '0;
                        i         <= '0;
                        sum_reg   <= 1'b0;
                        
                        if (rank_in > 0) begin
                            state <= COMPUTE_START;
                        end else begin
                            state <= EXPAND_START; // Skip compute if rank is 0
                        end
                    end
                end

                COMPUTE_START: begin
                    // Start of the *inner* loop (dot product for row 'j')
                    i         <= '0;
                    sum_reg   <= 1'b0;
                    state     <= ACCUMULATE;
                end
                
                // This state loops RANK_MAX times for each row
                ACCUMULATE: begin
                    // This is the *inner loop*
                    // sum_reg = sum_reg ^ (H_inv[j][i] & syndrome[i])
                    sum_reg <= sum_reg ^ bit_to_add;
                    
                    if (i == rank_in - 1) begin
                        // --- Inner loop is done. Save the result ---
                        // The final result is the accumulator's current value
                        // XOR'd with the final bit_to_add.
                        e_compact[j] <= sum_reg ^ bit_to_add; 
                        
                        // --- Now check the *outer* loop ---
                        if (j == rank_in - 1) begin
                            // Outer loop is also done. Move to Expand.
                            state <= EXPAND_START;
                        end else begin
                            // More rows to compute.
                            j <= j + 1;
                            state <= COMPUTE_START; // Go start the next dot product
                        end
                    end else begin
                        i <= i + 1; // Continue inner loop
                    end
                end

                EXPAND_START: begin
                    j <= '0; // Reset 'j' to be the expand counter
                    if (rank_in > 0) begin
                        state <= EXPAND;
                    end else begin
                        state <= DONE; // Nothing to expand
                        done <= 1'b1;
                    end
                end

                EXPAND: begin
                    // This is the *original* expand loop. It's already pipelined.
                    e_hat[used_indices[j]] <= e_compact[j];
                    
                    if (j == rank_in - 1) begin
                        state <= DONE;
                        done  <= 1;
                    end else begin
                        j <= j + 1;
                    end
                end

                DONE: begin
                    if (start) begin
                        // Re-initialize (copied from IDLE state)
                        e_compact <= '0;
                        e_hat     <= '0;
                        done      <= 1'b0;
                        j         <= '0;
                        i         <= '0;
                        sum_reg   <= 1'b0;
                        if (rank_in > 0) begin
                            state <= COMPUTE_START;
                        end else begin
                            state <= EXPAND_START;
                        end
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
                
            endcase
        end
    end

endmodule