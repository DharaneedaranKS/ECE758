`timescale 1ns/100ps

module tb_serial_sorter;

  // ------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------
  localparam WIDTH      = 32;
  localparam NUM_NODES  = 8500;
  localparam CLK_PERIOD = 10;

  // ------------------------------------------------------------
  // DUT I/O
  // ------------------------------------------------------------
  logic                   clk;
  logic                   rst_n;
  logic                   load_en;
  logic  [WIDTH-1:0]      data_in;
  logic                   clear;

  logic                   out_vld;
  logic  [WIDTH-1:0]      data_out [NUM_NODES:0];
  logic  [$clog2(NUM_NODES)-1:0] idx_out [NUM_NODES:0];

  // ------------------------------------------------------------
  // Internal TB variables
  // ------------------------------------------------------------
  int unsigned   input_values   [NUM_NODES];
  int unsigned   expected_values[NUM_NODES];
  int unsigned   expected_index [NUM_NODES];
  int            test_id;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  serial_sorter #(
      .WIDTH(WIDTH),
      .NUM_NODES(NUM_NODES)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .load_en(load_en),
      .data_in(data_in),
      .clear(clear),
      .out_vld(out_vld),
      .data_out(data_out),
      .idx_out(idx_out)
  );

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  always #(CLK_PERIOD/2) clk = ~clk;

  // ------------------------------------------------------------
  // Reset
  // ------------------------------------------------------------
  task automatic do_reset;
    rst_n = 0;
    load_en = 0;
    data_in = '0;
    repeat (5) @(posedge clk);
    rst_n = 1;
  endtask

  // ------------------------------------------------------------
  // Scoreboard – Expected Output Computation
  // ------------------------------------------------------------
  task automatic compute_expected;
    int temp_val [NUM_NODES];
    int temp_idx [NUM_NODES];

    for (int i = 0; i < NUM_NODES; i++) begin
      temp_val[i] = input_values[i];
      temp_idx[i] = i;
    end

    // Bubble Sort
    // for (int i = 0; i < NUM_NODES; i++) begin
    //   for (int j = i+1; j < NUM_NODES; j++) begin
    //     if (temp_val[j] < temp_val[i]) begin
    //       int tmpv = temp_val[i];
    //       int tmpi = temp_idx[i];
    //       temp_val[i] = temp_val[j];
    //       temp_idx[i] = temp_idx[j];
    //       temp_val[j] = tmpv;
    //       temp_idx[j] = tmpi;
    //     end
    //   end
    // end

    // Bubble Sort (stable, and reverse-index order on ties)
    for (int i = 0; i < NUM_NODES; i++) begin
    for (int j = i+1; j < NUM_NODES; j++) begin

        // If value[j] < value[i], swap
        // If equal, and index[j] > index[i], swap
        if ((temp_val[j] < temp_val[i]) ||
            ((temp_val[j] == temp_val[i]) && (temp_idx[j] > temp_idx[i]))) begin

        int tmpv = temp_val[i];
        int tmpi = temp_idx[i];

        temp_val[i] = temp_val[j];
        temp_idx[i] = temp_idx[j];

        temp_val[j] = tmpv;
        temp_idx[j] = tmpi;
        end
    end
    end


    for (int k = 0; k < NUM_NODES; k++) begin
      expected_values[k] = temp_val[k];
      expected_index [k] = temp_idx[k];
    end
  endtask

  // ------------------------------------------------------------
  // Drive Inputs
  // ------------------------------------------------------------
  task automatic drive_inputs;
    load_en = 1;
    for (int i = 0; i < NUM_NODES; i++) begin
      data_in = input_values[i];
      @(posedge clk);
    end
    load_en = 0;
    data_in = '1;
  endtask

  // ------------------------------------------------------------
  // Check Results
  // ------------------------------------------------------------
  task automatic check_results;
    @(posedge clk);        // wait for next clock edge
    wait(out_vld);         // portable replacement for (posedge clk iff out_vld)

    $display("TB: Checking outputs for test %0d ...", test_id);

    for (int i = 0; i < NUM_NODES; i++) begin
      if (data_out[i] !== expected_values[i]) begin
        $error("Mismatch: data_out[%0d] = %0d, expected %0d",
               i, data_out[i], expected_values[i]);
      end
      if (idx_out[i] !== expected_index[i]) begin
        $error("Mismatch: idx_out[%0d] = %0d, expected %0d",
               i, idx_out[i], expected_index[i]);
      end
    end

    $display("TB: Test %0d PASSED", test_id);
  endtask

  // ------------------------------------------------------------
  // Random Tests
  // ------------------------------------------------------------
  task automatic run_random_tests(int num_tests);
    for (int t = 0; t < num_tests; t++) begin
      test_id = t;

      for (int i = 0; i < NUM_NODES; i++)
        input_values[i] = $urandom_range(0, 255);

      compute_expected();
      drive_inputs();
      check_results();
      
      clear = 1'b1;
      @(posedge clk);
      clear = 1'b0;
      repeat (5) @(posedge clk);
    end
  endtask

  // ------------------------------------------------------------
  // Directed Tests
  // ------------------------------------------------------------
  task automatic run_directed_tests;
    // Test 1: Sorted
    test_id = 100;
    for (int i = 0; i < NUM_NODES; i++)
      input_values[i] = i*10;
    compute_expected();
    drive_inputs();
    check_results();

    clear = 1'b1;
    @(posedge clk);
    clear = 1'b0;
    repeat (5) @(posedge clk);

    // Test 2: Reverse
    test_id = 101;
    for (int i = 0; i < NUM_NODES; i++)
      input_values[i] = (NUM_NODES-1-i)*4;
    compute_expected();
    drive_inputs();
    check_results();

    clear = 1'b1;
    @(posedge clk);
    clear = 1'b0;
    repeat (5) @(posedge clk);

    // Test 3: All equal
    test_id = 102;
    for (int i = 0; i < NUM_NODES; i++)
      input_values[i] = 33;
    compute_expected();
    drive_inputs();
    check_results();
    clear = 1'b1;
    @(posedge clk);
    clear = 1'b0;
    repeat (5) @(posedge clk);
  endtask

  // ------------------------------------------------------------
  // Testbench Main
  // ------------------------------------------------------------
  initial begin
    clk = 0;

    do_reset();

    run_directed_tests();
    run_random_tests(50);

    $display("TB: ALL TESTS COMPLETED.");
    $finish;
  end

endmodule
