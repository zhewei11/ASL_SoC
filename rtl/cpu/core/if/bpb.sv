`include "rtos_core_config.svh"

module bpb #(
     parameter ENTRIES = `RTOS_CORE_BTB_ENTRIES
)(
     input  logic        clk
    ,input  logic        rst

    // Prediction Interface
    ,input  logic [31:0] pc
    ,output logic        hit
    ,output logic [31:0] target_pc
    ,output logic [1:0]  branch_type // 00:Cond, 01:Jump, 10:Call, 11:Ret

    // Update Interface
    ,input  logic        update_en
    ,input  logic [31:0] update_pc
    ,input  logic [31:0] update_target
    ,input  logic [1:0]  update_type

    // Remove an entry if the instruction at that exact PC resolves as a
    // non-branch. This handles software/DMA instruction replacement.
    ,input  logic        clear_en
    ,input  logic [31:0] clear_pc
);

    localparam INDEX_BITS = $clog2(ENTRIES);
    localparam TAG_BITS = 32 - INDEX_BITS - 2;

    typedef enum logic [1:0] {
        TYPE_COND = 2'b00,
        TYPE_JUMP = 2'b01,
        TYPE_CALL = 2'b10,
        TYPE_RET  = 2'b11
    } branch_type_t;

    reg                valid_array [ENTRIES-1:0];
    reg [TAG_BITS-1:0] tag_array [ENTRIES-1:0];
    reg [31:0]         target_array [ENTRIES-1:0];
    branch_type_t branch_type_array [ENTRIES-1:0];

    wire [INDEX_BITS-1:0] read_index;
    wire [TAG_BITS-1:0]   read_tag;

    wire [INDEX_BITS-1:0] write_index;
    wire [TAG_BITS-1:0]   write_tag;
    wire [INDEX_BITS-1:0] clear_index;
    wire [TAG_BITS-1:0]   clear_tag;

    // Assuming word-aligned PC, drop bottom 2 bits
    assign read_index = pc[INDEX_BITS+1:2];
    assign read_tag   = pc[31 : 32-TAG_BITS];

    assign write_index = update_pc[INDEX_BITS+1:2];
    assign write_tag   = update_pc[31 : 32-TAG_BITS];
    assign clear_index = clear_pc[INDEX_BITS+1:2];
    assign clear_tag   = clear_pc[31 : 32-TAG_BITS];

    // Read Logic
    assign hit = valid_array[read_index] && (tag_array[read_index] == read_tag);
    assign target_pc = target_array[read_index];
    assign branch_type = branch_type_array[read_index];

    // Update Logic
    integer i;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid_array[i] <= 1'b0;
                // Do not reset memory contents (tag, target, branch_type) to allow BRAM inference
            end
        end else if (update_en) begin
            valid_array[write_index]  <= 1'b1;
            tag_array[write_index]    <= write_tag;
            target_array[write_index] <= update_target;
            branch_type_array[write_index] <= branch_type_t'(update_type);
        end else if (clear_en &&
                     valid_array[clear_index] &&
                     (tag_array[clear_index] == clear_tag)) begin
            valid_array[clear_index] <= 1'b0;
        end
    end

endmodule
