module serial_sorter #(
    parameter WIDTH = 8,
    parameter NUM_NODES = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load_en,
    input  wire [WIDTH-1:0] data_in,
    input  wire             clear,
    output wire             out_vld,
    output wire [WIDTH-1:0] data_out [NUM_NODES:0],
    output wire [$clog2(NUM_NODES)-1:0] idx_out [NUM_NODES:0]
);

    // Wires connecting the nodes
    wire [WIDTH-1:0] right_wires [NUM_NODES:0]; 
    //wire [WIDTH-1:0] left_wires  [NUM_NODES:0]; 
    logic [$clog2(NUM_NODES)-1:0] index [NUM_NODES:0];
    logic [$clog2(NUM_NODES)-1:0] idx; // To store the input of the index 
    logic keep_running;
    logic [$clog2(NUM_NODES):0] tmr;

    // Connections to the outside world
    assign right_wires[0] = data_in;        // Feed input into Node 0
    //assign left_wires[NUM_NODES] = 8'hFF;   // Feed FFs from the far right during unload
    assign data_out[NUM_NODES] = {WIDTH{1'b1}};
    //assign data_out = left_wires[0];        // Output comes from Node 0
    assign index[0] = idx;
    assign out_vld = &tmr;
    //assign clear = ~|tmr && !load_en;
    genvar i;
    generate
        for (i = 0; i < NUM_NODES; i = i + 1) begin : nodes
            sort_node_act #(
                .WIDTH(WIDTH),
                .MAX_VAL({WIDTH{1'b1}}),
                .NUM_NODES(NUM_NODES)
            ) nodes (
                .clk(clk),
                .rst_n(rst_n),
                .clear(clear),
                .mode_load(keep_running|load_en),
                .idx_in(index[i]),
                .idx_out(index[i+1]),
                .my_idx(idx_out[i]),
                .val_in_left  (right_wires[i]),
                .val_out_left (data_out[i]),
                
                .val_in_right (data_out[i+1]),
                .val_out_right(right_wires[i+1])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 0;
            keep_running <= 0;
            tmr <= 0;
        end
        else if (clear) begin
            idx <= 0;
            keep_running <= 0;
            tmr <= 0;
        end
        else if (load_en) begin
            idx <= idx + 1;
            keep_running <= 1;
            tmr <= tmr + 1;
        end
        else begin
            //idx <= 0;
            tmr <= keep_running ? tmr + 1 : 0;
            keep_running <= tmr > 0;
        end

    end


endmodule