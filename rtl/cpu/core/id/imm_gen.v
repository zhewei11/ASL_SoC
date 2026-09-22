// Immediate Generator Module
module imm_gen (
     input  [31:0] instruction
    ,input  [2:0]  imm_type
    ,output [31:0] immediate
);

    // Immediate Type Definition
    localparam IMM_I = 3'b000;  // I-type
    localparam IMM_S = 3'b001;  // S-type
    localparam IMM_B = 3'b010;  // B-type
    localparam IMM_U = 3'b011;  // U-type
    localparam IMM_J = 3'b100;  // J-type

    wire [31:0] imm_i_type = {{20{instruction[31]}}, instruction[31:20]};

    wire [31:0] imm_s_type = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};

    wire [31:0] imm_b_type = {{19{instruction[31]}}, instruction[31], instruction[7],
                              instruction[30:25], instruction[11:8], 1'b0};

    wire [31:0] imm_u_type = {instruction[31:12], 12'b0};

    wire [31:0] imm_j_type = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                              instruction[20], instruction[30:21], 1'b0};

    assign immediate = (imm_type == IMM_I) ? imm_i_type :
                       (imm_type == IMM_S) ? imm_s_type :
                       (imm_type == IMM_B) ? imm_b_type :
                       (imm_type == IMM_U) ? imm_u_type :
                       (imm_type == IMM_J) ? imm_j_type :
                       32'h0;

endmodule
