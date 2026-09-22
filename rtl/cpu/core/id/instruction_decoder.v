// Instruction Decoder Module
module instruction_decoder (
     input  [31:0] instruction
    ,output [6:0]  opcode
    ,output [4:0]  rd
    ,output [4:0]  rs1
    ,output [4:0]  rs2
    ,output [4:0]  rs3
    ,output [2:0]  funct3
    ,output [6:0]  funct7
    ,output [11:0] csr_addr
);

    // Standard RISC-V Instruction Format
    assign opcode   = instruction[6:0];
    assign rd       = instruction[11:7];
    assign funct3   = instruction[14:12];
    assign rs1      = instruction[19:15];
    assign rs2      = instruction[24:20];
    assign rs3      = instruction[31:27];
    assign funct7   = instruction[31:25];

    // CSR address
    assign csr_addr = instruction[31:20];

endmodule
