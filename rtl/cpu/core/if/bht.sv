`include "rtos_core_config.svh"

module bht #(
     parameter ENTRIES = `RTOS_CORE_BHT_ENTRIES
)(
     input  logic        clk
    ,input  logic        rst

    // Prediction Interface
    ,input  logic [31:0] pc
    ,output logic        predict_taken

    // Update Interface
    ,input  logic        update_en
    ,input  logic [31:0] update_pc
    ,input  logic        actual_taken
);

    localparam int PC_BITS = $clog2(ENTRIES);

    // 2-bit Saturating Counters
    // 00: Strongly Not Taken
    // 01: Weakly Not Taken
    // 10: Weakly Taken
    // 11: Strongly Taken
    logic [1:0] counters [ENTRIES-1:0];

    wire [PC_BITS-1:0] read_index;
    wire [PC_BITS-1:0] write_index;

    assign read_index = pc[PC_BITS+1:2]; // Use bits [11:2] for word-aligned PC
    assign write_index = update_pc[PC_BITS+1:2];

    assign predict_taken = counters[read_index][1]; // MSB determines direction

    integer i;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                counters[i] <= 2'b01; // Initialize to Weakly Not Taken
            end
        end else if (update_en) begin
            case (counters[write_index])
                2'b00: counters[write_index] <= actual_taken ? 2'b01 : 2'b00;
                2'b01: counters[write_index] <= actual_taken ? 2'b10 : 2'b00;
                2'b10: counters[write_index] <= actual_taken ? 2'b11 : 2'b01;
                2'b11: counters[write_index] <= actual_taken ? 2'b11 : 2'b10;
            endcase
        end
    end

endmodule
