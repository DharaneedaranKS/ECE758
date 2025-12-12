module matrix_selector #(parameter N_DET = 936, parameter N_ERR = 8784, parameter RANK_MAX = 936)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [$clog2(N_ERR)-1:0] sorted_indices [0:N_ERR-1],
    input  logic [N_DET-1:0] H_data_in,
    output logic [$clog2(N_ERR)-1:0] H_addr,

    output logic [$clog2(N_ERR+1):0] scan_idx_out, // Debug port

    output logic done,
    output logic [N_DET-1:0] Hs_cols [0:RANK_MAX-1],
    output logic [$clog2(N_ERR)-1:0] used_indices [0:RANK_MAX-1],
    output logic [$clog2(RANK_MAX+1)-1:0] rank_out // Fixed width
);

    // --- Internal "Memory" for Pivots ---
    logic [N_DET-1:0] pivot_cols [0:RANK_MAX-1]; 
    
    // Create an internal BRAM for Hs_cols
    logic [N_DET-1:0] Hs_cols_internal [0:RANK_MAX-1]; 
    
    logic [$clog2(N_ERR)-1:0] selected_indices [0:RANK_MAX-1];
    
    // --- FSM Registers ---
    typedef enum logic [2:0] {IDLE, FETCH, WAIT_FOR_DATA, 
                            ELIM_ACCUMULATE, ELIM_CHECK_SAVE, 
                            DONE} state_t;
    state_t state;

    logic [$clog2(RANK_MAX+1)-1:0] rank;         // How many columns we have found
    logic [$clog2(N_ERR+1):0]      scan_idx;     // Which column we are testing
    
    // --- Inner Loop (Pipelining) Registers ---
    logic [$clog2(RANK_MAX+1):0] i;              // Inner loop counter (for XORing)
    logic [N_DET-1:0]             xor_accum;     // Accumulator for the XOR-chain
    logic [N_DET-1:0]             current_col;   // Holds the column being tested
    logic [$clog2(N_ERR)-1:0]     current_idx;   // Holds the index of the column
    logic [$clog2(N_ERR)-1:0]     idx_to_save;   // Delayed index
    logic                         is_indep;      // 1-bit result of the check
    logic                         pipe_valid;    // Pipeline valid flag

    // --- Pipeline Latch ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_col <= '0;
            current_idx <= '0;
        end else if (state == WAIT_FOR_DATA) begin 
            current_col <= H_data_in;
            current_idx <= H_addr;
        end
    end

    // --- Main FSM ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rank     <= 0;
            scan_idx <= 0;
            state    <= IDLE;
            done     <= 0;
            H_addr   <= '0;
            i        <= 0;
            xor_accum <= '0;
            is_indep <= 0;
            idx_to_save <= '0; 
            pipe_valid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        rank     <= 0;
                        scan_idx <= 0;
                        done     <= 0;
                        i        <= 0;
                        state    <= FETCH;
                        pipe_valid <= 0; 
                    end
                end
                
                FETCH: begin
                    if (rank == $unsigned(RANK_MAX) || scan_idx == $unsigned(N_ERR)) begin
                        state <= DONE;
                    end else begin
                        H_addr <= sorted_indices[scan_idx];
                        state  <= WAIT_FOR_DATA;
                        scan_idx <= scan_idx + 1;
                    end
                end

                WAIT_FOR_DATA: begin
                    state <= ELIM_ACCUMULATE;
                    i     <= 0;
                    idx_to_save <= current_idx; 
                end

                ELIM_ACCUMULATE: begin
                    if (i == 0) begin
                        xor_accum <= current_col;
                    end
                    else if (i <= rank) begin 
                        xor_accum <= xor_accum ^ pivot_cols[i-1];
                    end else begin
                        state <= ELIM_CHECK_SAVE;
                    end
                    i <= i + 1;
                end
                
                ELIM_CHECK_SAVE: begin
                    is_indep <= (xor_accum != '0);
                    
                    if ((xor_accum != '0) && pipe_valid) begin
                        pivot_cols[rank]       <= xor_accum;
                        Hs_cols_internal[rank] <= current_col;
                        selected_indices[rank] <= idx_to_save;
                        rank                   <= rank + 1;
                    end
                    
                    pipe_valid <= 1; 
                    state <= FETCH;
                end

                DONE: begin
                    done <= 1;
                    if (start) begin
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

    // Connect the internal to the output ports
    assign Hs_cols = Hs_cols_internal;
    assign used_indices = selected_indices;
    assign rank_out = rank;
    assign scan_idx_out = scan_idx;

endmodule