`include "rtos_core_config.svh"

module ras #(
     parameter DEPTH = `RTOS_CORE_RAS_DEPTH
)(
     input  logic        clk
    ,input  logic        rst

    ,input  logic        push
    ,input  logic        pop
    ,input  logic [31:0] push_addr

    ,output logic [31:0] pop_addr
    ,output logic        valid // Indicates if stack is not empty
);

    localparam int PTR_WIDTH = $clog2(DEPTH);
    localparam logic [PTR_WIDTH-1:0] LAST_INDEX = PTR_WIDTH'(DEPTH - 1);

    logic [31:0]            stack [DEPTH-1:0];
    logic [PTR_WIDTH-1:0]   ptr; // Points to the next empty slot
    logic [$clog2(DEPTH):0] count;
    logic [PTR_WIDTH-1:0]   top_index;
    integer                 index;

    // Do not use an unsized "ptr - 1" array index.  When ptr is zero some
    // simulators widen the subtraction to 32 bits and index stack[-1], which
    // turns a valid full-stack return prediction into X.
    always_comb begin
        top_index = (ptr == '0) ? LAST_INDEX : ptr - 1'b1;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ptr <= '0;
            count <= '0;
            for (index = 0; index < DEPTH; index = index + 1)
                stack[index] <= 32'd0;
        end else begin
            if (push && pop) begin
                // A simultaneous pop/push replaces the current top.  If the
                // stack is empty it behaves as a normal push.
                if (count != 0) begin
                    stack[top_index] <= push_addr;
                end else begin
                    stack[ptr] <= push_addr;
                    ptr <= (ptr == LAST_INDEX) ? '0 : ptr + 1'b1;
                    count <= 1;
                end
            end else if (push) begin
                stack[ptr] <= push_addr;
                ptr <= (ptr == LAST_INDEX) ? '0 : ptr + 1'b1;
                if (count < DEPTH) count <= count + 1;
            end else if (pop) begin
                if (count > 0) begin
                    ptr <= top_index;
                    count <= count - 1;
                end
            end
        end
    end

    // Read logic for pop
    // If we pop, the address comes from ptr-1.
    // If we are just peeking, we read ptr-1.
    // Speculative RAS: we output the Top of Stack always. Pop signal commits the pop (moves pointer).

    assign pop_addr = (count > 0) ? stack[top_index] : 32'd0;
    assign valid = (count > 0);

endmodule
