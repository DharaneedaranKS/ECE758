module osd_top #(
    parameter DATA_WIDTH = 32,
    parameter NUM_OF_ENTERIES = 8,
    parameter H_ROW_SIZE = 4,
    parameter IDX_SIZE = $clog2(NUM_OF_ENTERIES),
    parameter INDEX_SIZE = $clog2(NUM_OF_ENTERIES),
    parameter H_ROW_INDEX = $clog2(H_ROW_SIZE)) (
    input logic                  clk,
    input logic                  rst_n,
    input logic                  vld_in, // Input is valid, needs to be on for NUM_OF_ENTERIES cycles
    input logic [DATA_WIDTH-1:0] llr, // The BP probability which comes in one at a time 
    input logic [H_ROW_SIZE-1:0] H_col,
    input logic [H_ROW_SIZE-1:0] syndrome,
    output logic [INDEX_SIZE-1:0]       H_col_index,
    output logic                        vld_out, // Signal to denote entire computation is done
    output logic [NUM_OF_ENTERIES-1:0]  e_hat // final output --> readout      
);

    //localparam IDX_SIZE = $clog2(NUM_OF_ENTERIES);

    // Local variables 
    int i;

    // Control Signals for sorter 
    logic clear_sorter;
    logic sorter_done;

    // Data flow from sorter 
    logic [DATA_WIDTH-1:0] sorted_array [NUM_OF_ENTERIES:0]; // wires to carry the value of  the sorted array to reconfigure
    logic [INDEX_SIZE-1:0] sorted_array_index [NUM_OF_ENTERIES:0];
    logic [INDEX_SIZE-1:0] sorted_to_systolic_array_index [NUM_OF_ENTERIES-1:0];
    
    // Data flow to sorter
    logic [DATA_WIDTH-1:0] llr_in;
    logic act_sa;
    assign llr_in = vld_in ? llr : {DATA_WIDTH{1'b1}};
    serial_sorter #(.NUM_NODES(NUM_OF_ENTERIES), .WIDTH(DATA_WIDTH)) sort (
        .clk(clk),
        .rst_n(rst_n),
        .load_en(vld_in), // Input to the sorter depends on the valid input coming 
        .data_in(llr_in), // Input probability 
        .clear(clear_sorter),
        .out_vld(sorter_done),
        .activate_systolic_array(act_sa),
        .data_out(sorted_array),
        .idx_out(sorted_array_index)
    );

    always_comb begin : refactoring_data
        for (i=0; i<NUM_OF_ENTERIES; i+=1) begin
            sorted_to_systolic_array_index[i] = sorted_array_index[NUM_OF_ENTERIES-i-1];
        end
    end

    // Sending the inputs to the H_ROW_ROM one by one to get the H_COL value to send into the OSD
    
    logic [INDEX_SIZE-1:0] index_count;
    always_ff @(posedge clk or posedge rst_n) begin
        if (rst_n) begin
            index_count <= (NUM_OF_ENTERIES-1);
            //H_col_index <= 0;
        end

        else if (sorter_done) begin
            index_count <= |index_count ? index_count - 1'b1 : index_count;
            //H_col_index <= sorted_to_systolic_array_index[index_count];
        end
    end
    
    assign H_col_index = sorter_done ? sorted_array_index[index_count] : 0; 



    sys_arr_lse_sol #(.H_ROW_SIZE(H_ROW_SIZE), .IDX_SIZE(IDX_SIZE), .N_COLS(NUM_OF_ENTERIES)) osd_and_lse_solver (
        .clk(clk),
        .reset(rst_n),
        .sorted_col_in(H_col),
        .sorted_idx_in(H_col_index),
        .syndrome_in(syndrome),
        .h_inv_col_out(),
        .h_inv_idx_out(),
        .h_inv_out_valid(),
        .sorter_vld(sorter_done),
        .act_sa(act_sa),
        .final_e_hat(e_hat),
        .final_done(vld_out)
    );

endmodule