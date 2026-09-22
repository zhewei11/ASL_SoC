//pc imm rs1 rs2 func3 opcode
module jb_unit (
     input [31:0] pc
    ,input [31:0] imm
    ,input [31:0] rs1
    ,input [31:0] rs2
    ,input [3:0]  bj_type
    ,output reg jb_pc_sel
    ,output reg [31:0] jb_pc
);

    localparam BJ_NONE = 4'b0000;
    localparam BJ_JAL  = 4'b1000;
    localparam BJ_JALR = 4'b1001;
    localparam BJ_BEQ  = 4'b1010;
    localparam BJ_BNE  = 4'b1011;
    localparam BJ_BLT  = 4'b1100;
    localparam BJ_BGE  = 4'b1101;
    localparam BJ_BLTU = 4'b1110;
    localparam BJ_BGEU = 4'b1111;

    always @(*) begin
        jb_pc_sel = 1'b0;
        jb_pc = pc;

        case (bj_type)
            BJ_BEQ: begin
                jb_pc_sel = (rs1 == rs2) ? 1'b1 : 1'b0;
                jb_pc = pc + imm;
            end
            BJ_BNE: begin
                jb_pc_sel = (rs1 != rs2) ? 1'b1 : 1'b0;
                jb_pc = pc + imm;
            end
            BJ_BLT: begin
                jb_pc_sel = ($signed(rs1) < $signed(rs2)) ? 1'b1 : 1'b0;
                jb_pc = pc + imm;
            end
            BJ_BLTU: begin
                jb_pc = pc + imm;
                jb_pc_sel = ($unsigned(rs1) < $unsigned(rs2)) ? 1'b1 : 1'b0;
            end
            BJ_BGE: begin
                jb_pc = pc + imm;
                jb_pc_sel = ($signed(rs1) >= $signed(rs2)) ? 1'b1 : 1'b0;
            end
            BJ_BGEU: begin
                jb_pc = pc + imm;
                jb_pc_sel = ($unsigned(rs1) >= $unsigned(rs2)) ? 1'b1 : 1'b0;
            end
            BJ_JAL: begin
                jb_pc = pc + imm;
                jb_pc_sel = 1'b1;
            end
            BJ_JALR: begin
                jb_pc = (rs1 + imm) & 32'hfffffffe;
                jb_pc_sel = 1'b1;
            end
            default: begin
                jb_pc = pc;
                jb_pc_sel = 1'b0;
            end
        endcase
    end

endmodule
