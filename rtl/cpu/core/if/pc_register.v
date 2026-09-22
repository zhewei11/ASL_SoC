`include "rtos_core_config.svh"

// Program Counter Module
module pc_register (
     input              clk
    ,input              rst
    ,input              pc_enable
    ,input      [31:0]  next_pc
    ,output reg [31:0]  pc
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            pc <= `RTOS_CORE_CPU_RESET_VECTOR;
        else if (pc_enable)
            pc <= next_pc;
    end

endmodule
