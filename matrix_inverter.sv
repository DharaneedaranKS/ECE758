module matrix_inverter #(parameter RANK_MAX = 936, N_DET = 936)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    input  logic [N_DET-1:0] Hs_cols [0:RANK_MAX-1], // Full-rank H matrix columns (RANK x N_DET)
    input  logic [($clog2(RANK_MAX)-1):0] rank_in,

    output logic done,
    output logic [N_DET-1:0] H_inv_cols [0:RANK_MAX-1], // Inverted matrix (N_DET x RANK)
    output logic success
);

  // Local memory copies
  logic [N_DET-1:0] A [0:RANK_MAX-1];      // Working copy of H
  logic [N_DET-1:0] I [0:RANK_MAX-1];      // Start as identity matrix

  int unsigned i, j, k;
  logic working;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      done <= 0;
      working <= 0;
      success <= 0;
    end else begin
      if (start && !working) begin
        // Initialize matrices
        for (i = 0; i < RANK_MAX; i++) begin
          if (i < rank_in) begin
            A[i] = Hs_cols[i];
            I[i] = '0;
            I[i][i] = 1'b1;
          end
        end
        working <= 1;
        done <= 0;
        success <= 0;
        j = 0;  // pivot index
      end
      else if (working && j < rank_in) begin
        // Make sure pivot exists
        if (A[j][j] == 0) begin
          // Try to swap with a row below
          for (k = 0; k < RANK_MAX; k++) begin
            if (k > j && k < rank_in && A[k][j] == 1) begin
              A[j] ^= A[k];
              I[j] ^= I[k];
              break;
            end
          end
        end

        // If still zero, fail
        if (A[j][j] == 0) begin
          done <= 1;
          success <= 0;
          working <= 0;
        end else begin
          // Eliminate other rows
          for (i = 0; i < rank_in; i++) begin
            if (i != j && A[i][j]) begin
              A[i] ^= A[j];
              I[i] ^= I[j];
            end
          end
          j = j + 1;
          if (j == rank_in) begin
            // Done
            for (i = 0; i < rank_in; i++)
              H_inv_cols[i] = I[i];
            done <= 1;
            success <= 1;
            working <= 0;
          end
        end
      end
    end
  end

endmodule