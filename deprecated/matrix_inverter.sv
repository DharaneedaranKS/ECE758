module matrix_inverter #(parameter RANK_MAX = 936, N_DET = 936)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [N_DET-1:0] Hs_cols [0:RANK_MAX-1],
    input  logic [($clog2(RANK_MAX+1)-1):0] rank_in,

    output logic done,
    output logic [N_DET-1:0] H_inv_cols [0:RANK_MAX-1],
    output logic success
);

    // Local memory copies
    logic [N_DET-1:0] A [0:RANK_MAX-1];
    logic [N_DET-1:0] I [0:RANK_MAX-1];
    
    int unsigned i, j, k;
    logic local_found_swap;
    int unsigned k_to_swap;
    
    typedef enum logic [3:0] {
        IDLE, 
        INIT, 
        PIVOT_CHECK, 
        PIVOT_SEARCH, 
        PIVOT_SWAP, 
        ELIMINATE, 
        COPY_OUTPUT
    } state_t;
    state_t state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done <= 0;
            success <= 0;
            state <= IDLE;
            i <= 0;
            j <= 0;
            k <= 0;
            local_found_swap <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= INIT;
                        i <= 0;
                        j <= 0;
                        done <= 0;
                        success <= 0;
                    end
                end
                
                INIT: begin
                    // Initialize one row per cycle
                    if (i < rank_in) begin
                        A[i] <= Hs_cols[i];
                        I[i] <= '0;
                        if (i < $unsigned(N_DET)) begin
                            I[i][i] <= 1'b1;
                        end
                        i <= i + 1;
                    end else begin
                        state <= PIVOT_CHECK;
                        j <= 0;
                    end
                end
                
                PIVOT_CHECK: begin
                    if (j < rank_in) begin
                        // Check if pivot is zero
                        if (A[j][j] == 0) begin
                            // Need to find a row to swap
                            state <= PIVOT_SEARCH;
                            k <= j + 1;
                            local_found_swap <= 0;
                        end else begin
                            // Pivot is good, go to elimination
                            state <= ELIMINATE;
                            i <= 0;
                        end
                    end else begin
                        // All pivots processed
                        state <= COPY_OUTPUT;
                        i <= 0;
                    end
                end
                
                PIVOT_SEARCH: begin
                    // Search for a row to swap (one row per cycle)
                    if (k < rank_in) begin
                        if (!local_found_swap && A[k][j] == 1) begin
                            // Found a row with non-zero pivot
                            k_to_swap <= k;
                            local_found_swap <= 1;
                            state <= PIVOT_SWAP;
                        end else begin
                            // Check next row
                            k <= k + 1;
                        end
                    end else begin
                        // Reached end of search
                        if (!local_found_swap) begin
                            // No swap found - matrix is singular
                            done <= 1;
                            success <= 0;
                            state <= IDLE;
                        end else begin
                            // This shouldn't happen, but go to swap
                            state <= PIVOT_SWAP;
                        end
                    end
                end
                
                PIVOT_SWAP: begin
                    // Perform the row swap using XOR
                    A[j] <= A[j] ^ A[k_to_swap];
                    I[j] <= I[j] ^ I[k_to_swap];
                    state <= ELIMINATE;
                    i <= 0;
                end
                
                ELIMINATE: begin
                    // Eliminate column j from other rows (one row per cycle)
                    if (i < rank_in) begin
                        if (i != j && A[i][j] == 1) begin
                            A[i] <= A[i] ^ A[j];
                            I[i] <= I[i] ^ I[j];
                        end
                        i <= i + 1;
                    end else begin
                        // Done with this pivot, move to next
                        j <= j + 1;
                        state <= PIVOT_CHECK;
                    end
                end
                
                COPY_OUTPUT: begin
                    // Copy result to output (one row per cycle)
                    if (i < rank_in) begin
                        H_inv_cols[i] <= I[i];
                        i <= i + 1;
                    end else begin
                        done <= 1;
                        success <= 1;
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule