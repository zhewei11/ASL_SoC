// Control Unit Module
module control_unit (
     input  [6:0] opcode
    ,input  [2:0] funct3
    ,input  [6:0] funct7
    ,input  [11:0] system_imm
    // Control Signals
    ,output reg       reg_write
    ,output reg [3:0] use_mem_type  // 0000: none, 0001: SW, 0010: SH, 0011: SB, 0100: LW, 0101: LH, 0110: LB, 0111: LBU, 1000: LHU
    ,output reg [2:0] write_back_type //000: alu, 001: mem, 010: pc, 011: imm, 100: csr
    ,output reg [4:0] alu_type
    ,output reg [3:0] bj_type   //000:jal, 001:jalr, 010:beq, 011:bne, 100:blt, 101: bge, 110:bltu, 111:bgeu
    ,output reg [2:0] imm_type  //000:imm_i, 001:imm_s, 010:imm_b, 011:imm_u, 100:imm_j
    ,output reg       is_float  //1:float, 0:not float
    // Operand usage flags for Scoreboard/Hazards
    ,output reg       use_rs1
    ,output reg       use_rs2
    ,output reg       use_rs3
    ,output reg       use_rd_as_src // For MAC: rd = rd + rs1*rs2
    ,output reg       rs1_is_fp
    ,output reg       rs2_is_fp
    ,output reg       rs3_is_fp
    ,output reg       rd_is_fp
    ,output reg       alu_src_a // 0: rs1, 1: pc
    ,output reg       alu_src_b // 0: rs2, 1: imm
    ,output reg       instr_nop
    ,output reg       csr_en
    ,output reg       mret
    ,output reg       wfi
    ,output reg       ecall
    ,output reg       ebreak
    ,output reg       fence_i
    ,output reg       illegal_instr
);

    // Opcode Definition
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;
    localparam OP_MISC_MEM = 7'b0001111;
    localparam OP_SYSTEM = 7'b1110011;
    localparam OP_MAC    = 7'b0101011;
    localparam OP_FLOAD  = 7'b0000111;
    localparam OP_FSTORE = 7'b0100111;
    localparam OP_FCOMP  = 7'b1010011;
    localparam OP_FMADD  = 7'b1000011;
    localparam OP_FMSUB  = 7'b1000111;
    localparam OP_FNMSUB = 7'b1001011;
    localparam OP_FNMADD = 7'b1001111;

    // ALU Operation Code (Matching alu.v)
    localparam ALU_ADD    = 5'b00000;
    localparam ALU_SUB    = 5'b00001;
    localparam ALU_SLL    = 5'b00010;
    localparam ALU_SLT    = 5'b00011;
    localparam ALU_SLTU   = 5'b00100;
    localparam ALU_XOR    = 5'b00101;
    localparam ALU_SRL    = 5'b00110;
    localparam ALU_SRA    = 5'b00111;
    localparam ALU_OR     = 5'b01000;
    localparam ALU_AND    = 5'b01001;
    localparam ALU_MUL    = 5'b01010;
    localparam ALU_MULH   = 5'b01011;
    localparam ALU_MULHSU = 5'b01100;
    localparam ALU_MULHU  = 5'b01101;
    localparam ALU_DIV    = 5'b01110;
    localparam ALU_DIVU   = 5'b01111;
    localparam ALU_REM    = 5'b10000;
    localparam ALU_REMU   = 5'b10001;
    localparam FPU_EXEC   = 5'b10110;
    localparam MAC        = 5'b11110;

    // write_back_type
    localparam WB_ALU  = 3'b000;
    localparam WB_MEM  = 3'b001;
    localparam WB_PC   = 3'b010;
    localparam WB_IMM  = 3'b011;
    localparam WB_CSR  = 3'b100;
    localparam WB_SMEM = 3'b101;

    // bj_type
    localparam BJ_NONE = 4'b0000;
    localparam BJ_JAL  = 4'b1000;
    localparam BJ_JALR = 4'b1001;
    localparam BJ_BEQ  = 4'b1010;
    localparam BJ_BNE  = 4'b1011;
    localparam BJ_BLT  = 4'b1100;
    localparam BJ_BGE  = 4'b1101;
    localparam BJ_BLTU = 4'b1110;
    localparam BJ_BGEU = 4'b1111;

    // use_mem_type
    localparam MEM_NONE = 4'b0000;
    localparam MEM_SW   = 4'b0001;
    localparam MEM_SH   = 4'b0010;
    localparam MEM_SB   = 4'b0011;
    localparam MEM_LW   = 4'b0100;
    localparam MEM_LH   = 4'b0101;
    localparam MEM_LB   = 4'b0110;
    localparam MEM_LBU  = 4'b0111;
    localparam MEM_LHU  = 4'b1100;

    // Immediate Type (imm_gen.v compatible)
    localparam IMM_I = 3'b000;
    localparam IMM_S = 3'b001;
    localparam IMM_B = 3'b010;
    localparam IMM_U = 3'b011;
    localparam IMM_J = 3'b100;

    always @(*) begin
        // Default Values
        reg_write       = 1'b0;
        use_mem_type    = MEM_NONE;
        write_back_type = WB_ALU;
        alu_type        = ALU_ADD;
        bj_type         = BJ_NONE;
        imm_type        = IMM_I;
        is_float        = 1'b0;
        use_rs1         = 1'b1;
        use_rs2         = 1'b1;
        use_rs3         = 1'b0;
        use_rd_as_src   = 1'b0;
        rs1_is_fp       = 1'b0;
        rs2_is_fp       = 1'b0;
        rs3_is_fp       = 1'b0;
        rd_is_fp        = 1'b0;
        alu_src_a       = 1'b0;
        alu_src_b       = 1'b0;
        instr_nop       = 1'b1;
        csr_en           = 1'b0;
        mret             = 1'b0;
        wfi              = 1'b0;
        ecall            = 1'b0;
        ebreak           = 1'b0;
        fence_i          = 1'b0;
        illegal_instr    = 1'b0;

        case (opcode)
            7'b0000000: begin // NOP (all zeros case)
                use_rs1 =   1'b0;
                use_rs2 =   1'b0;
                instr_nop = 1'b0;
                illegal_instr = 1'b1;
            end

            OP_LUI: begin
                reg_write       = 1'b1;
                write_back_type = WB_IMM;
                imm_type        = IMM_U;
                use_rs1         = 1'b0;
                use_rs2         = 1'b0;
                alu_src_b       = 1'b1;
            end

            OP_AUIPC: begin
                reg_write       = 1'b1;
                write_back_type = WB_ALU; // Result = PC + imm handled in EX
                alu_type        = ALU_ADD;
                imm_type        = IMM_U;
                use_rs1         = 1'b0;
                use_rs2         = 1'b0;
                alu_src_a       = 1'b1; // PC
                alu_src_b       = 1'b1; // Imm
            end

            OP_JAL: begin
                reg_write       = 1'b1;
                write_back_type = WB_PC;  // Save PC+4
                bj_type         = BJ_JAL;
                imm_type        = IMM_J;
                use_rs1         = 1'b0;
                use_rs2         = 1'b0;
            end

            OP_JALR: begin
                reg_write       = 1'b1;
                write_back_type = WB_PC;  // Save PC+4
                bj_type         = BJ_JALR;
                imm_type        = IMM_I;
                use_rs2         = 1'b0;
                alu_src_a       = 1'b0; // RS1
                alu_src_b       = 1'b1; // Imm
                if (funct3 != 3'b000)
                    illegal_instr = 1'b1;
            end

            OP_BRANCH: begin
                imm_type = IMM_B;
                case (funct3)
                    3'b000: bj_type = BJ_BEQ;
                    3'b001: bj_type = BJ_BNE;
                    3'b100: bj_type = BJ_BLT;
                    3'b101: bj_type = BJ_BGE;
                    3'b110: bj_type = BJ_BLTU;
                    3'b111: bj_type = BJ_BGEU;
                    default: begin
                        bj_type = BJ_NONE;
                        illegal_instr = 1'b1;
                    end
                endcase
            end

            OP_LOAD: begin
                reg_write       = 1'b1;
                write_back_type = WB_MEM;
                alu_type        = ALU_ADD;
                imm_type        = IMM_I;
                use_rs2         = 1'b0;
                case (funct3)
                    3'b010:  use_mem_type = MEM_LW;
                    3'b001:  use_mem_type = MEM_LH;
                    3'b000:  use_mem_type = MEM_LB;
                    3'b100:  use_mem_type = MEM_LBU;
                    3'b101:  use_mem_type = MEM_LHU;
                    default: begin
                        use_mem_type = MEM_NONE;
                        illegal_instr = 1'b1;
                    end
                endcase
                alu_src_b       = 1'b1; // Imm
            end

            OP_STORE: begin
                alu_type        = ALU_ADD;
                imm_type        = IMM_S;
                write_back_type = WB_SMEM;
                case (funct3)
                    3'b010:  use_mem_type = MEM_SW;
                    3'b001:  use_mem_type = MEM_SH;
                    3'b000:  use_mem_type = MEM_SB;
                    default: begin
                        use_mem_type = MEM_NONE;
                        illegal_instr = 1'b1;
                    end
                endcase
                alu_src_b       = 1'b1; // Imm
            end

            OP_IMM: begin
                reg_write = 1'b1;
                imm_type  = IMM_I;
                use_rs2   = 1'b0;
                case (funct3)
                    3'b000: alu_type = ALU_ADD;
                    3'b010: alu_type = ALU_SLT;
                    3'b011: alu_type = ALU_SLTU;
                    3'b100: alu_type = ALU_XOR;
                    3'b110: alu_type = ALU_OR;
                    3'b111: alu_type = ALU_AND;
                    3'b001: begin
                        alu_type = ALU_SLL;
                        if (funct7 != 7'b0000000)
                            illegal_instr = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_type = ALU_SRL;
                        else if (funct7 == 7'b0100000)
                            alu_type = ALU_SRA;
                        else
                            illegal_instr = 1'b1;
                    end
                    default: illegal_instr = 1'b1;
                endcase
                alu_src_b       = 1'b1; // Imm
            end

            OP_REG: begin
                reg_write = 1'b1;
                if (funct7 == 7'b0000001) begin // M-extension
                    case (funct3)
                        3'b000: alu_type = ALU_MUL;
                        3'b001: alu_type = ALU_MULH;
                        3'b010: alu_type = ALU_MULHSU;
                        3'b011: alu_type = ALU_MULHU;
                        3'b100: alu_type = ALU_DIV;
                        3'b101: alu_type = ALU_DIVU;
                        3'b110: alu_type = ALU_REM;
                        3'b111: alu_type = ALU_REMU;
                    endcase
                end else if (funct7 == 7'b0000000) begin
                    case (funct3)
                        3'b000: alu_type = ALU_ADD;
                        3'b001: alu_type = ALU_SLL;
                        3'b010: alu_type = ALU_SLT;
                        3'b011: alu_type = ALU_SLTU;
                        3'b100: alu_type = ALU_XOR;
                        3'b101: alu_type = ALU_SRL;
                        3'b110: alu_type = ALU_OR;
                        3'b111: alu_type = ALU_AND;
                    endcase
                end else if (funct7 == 7'b0100000) begin
                    if (funct3 == 3'b000)
                        alu_type = ALU_SUB;
                    else if (funct3 == 3'b101)
                        alu_type = ALU_SRA;
                    else
                        illegal_instr = 1'b1;
                end else begin
                    illegal_instr = 1'b1;
                end
            end

            OP_MISC_MEM: begin
                use_rs1 = 1'b0;
                use_rs2 = 1'b0;
                if (funct3 == 3'b000) begin
                    // The in-order pipeline already waits for every older
                    // memory operation before FENCE can retire.
                    fence_i = 1'b0;
                end else if ((funct3 == 3'b001) &&
                             (system_imm == 12'd0)) begin
                    fence_i = 1'b1;
                end else begin
                    illegal_instr = 1'b1;
                end
            end

            OP_MAC: begin // opcode = 0101011
                if (funct7 == 7'b0001000 && funct3 == 3'b000) begin
                    reg_write     = 1'b1;
                    alu_type      = MAC;
                    use_rd_as_src = 1'b1;
                end else
                    illegal_instr = 1'b1;
            end

            OP_FLOAD: begin // opcode = 0000111 (FLW)
                reg_write       = 1'b1;
                is_float        = 1'b1;
                rd_is_fp        = 1'b1;
                use_mem_type    = MEM_LW;
                write_back_type = WB_MEM;
                alu_type        = ALU_ADD;
                imm_type        = IMM_I;
                use_rs2         = 1'b0;
                alu_src_b       = 1'b1; // Imm
                if (funct3 != 3'b010)
                    illegal_instr = 1'b1;
            end

            OP_FSTORE: begin // opcode = 0100111 (FSW)
                is_float        = 1'b1;
                rs2_is_fp       = 1'b1;
                use_mem_type    = MEM_SW;
                write_back_type = WB_SMEM;
                alu_type        = ALU_ADD;
                imm_type        = IMM_S;
                alu_src_b       = 1'b1; // Imm
                if (funct3 != 3'b010)
                    illegal_instr = 1'b1;
            end

            OP_FCOMP: begin // Standard OP-FP opcode = 1010011
                reg_write       = 1'b1;
                rs1_is_fp       = 1'b1;
                rs2_is_fp       = 1'b1;
                rd_is_fp        = 1'b1;
                alu_type        = FPU_EXEC;
                case (funct7)
                    7'b0000000, // FADD.S
                    7'b0000100, // FSUB.S
                    7'b0001000, // FMUL.S
                    7'b0001100: begin // FDIV.S
                        if ((funct3 == 3'b101) || (funct3 == 3'b110))
                            illegal_instr = 1'b1;
                    end
                    7'b0101100: begin // FSQRT.S
                        use_rs2 = 1'b0;
                        if ((system_imm[4:0] != 5'd0) ||
                            (funct3 == 3'b101) || (funct3 == 3'b110))
                            illegal_instr = 1'b1;
                    end
                    7'b0010000: begin // FSGNJ.S/FSGNJN.S/FSGNJX.S
                        if (funct3 > 3'b010)
                            illegal_instr = 1'b1;
                    end
                    7'b0010100: begin // FMIN.S/FMAX.S
                        if (funct3 > 3'b001)
                            illegal_instr = 1'b1;
                    end
                    7'b1010000: begin // FLE.S/FLT.S/FEQ.S
                        rd_is_fp = 1'b0;
                        if ((funct3 != 3'b000) && (funct3 != 3'b001) &&
                            (funct3 != 3'b010))
                            illegal_instr = 1'b1;
                    end
                    7'b1100000: begin // FCVT.W[U].S
                        rd_is_fp = 1'b0;
                        use_rs2 = 1'b0;
                        if ((system_imm[4:0] > 5'd1) ||
                            (funct3 == 3'b101) || (funct3 == 3'b110))
                            illegal_instr = 1'b1;
                    end
                    7'b1110000: begin // FMV.X.W/FCLASS.S
                        rd_is_fp = 1'b0;
                        use_rs2 = 1'b0;
                        if ((system_imm[4:0] != 5'd0) ||
                            ((funct3 != 3'b000) && (funct3 != 3'b001)))
                            illegal_instr = 1'b1;
                    end
                    7'b1101000: begin // FCVT.S.W[U]
                        rs1_is_fp = 1'b0;
                        use_rs2 = 1'b0;
                        if ((system_imm[4:0] > 5'd1) ||
                            (funct3 == 3'b101) || (funct3 == 3'b110))
                            illegal_instr = 1'b1;
                    end
                    7'b1111000: begin // FMV.W.X
                        rs1_is_fp = 1'b0;
                        use_rs2 = 1'b0;
                        if ((system_imm[4:0] != 5'd0) ||
                            (funct3 != 3'b000))
                            illegal_instr = 1'b1;
                    end
                    default: illegal_instr = 1'b1;
                endcase
            end

            OP_FMADD, OP_FMSUB, OP_FNMSUB, OP_FNMADD: begin
                reg_write = 1'b1;
                rd_is_fp  = 1'b1;
                rs1_is_fp = 1'b1;
                rs2_is_fp = 1'b1;
                use_rs3   = 1'b1;
                rs3_is_fp = 1'b1;
                alu_type  = FPU_EXEC;
                // funct7[1:0] is fmt; only binary32 (S) is implemented.
                if ((funct7[1:0] != 2'b00) ||
                    (funct3 == 3'b101) || (funct3 == 3'b110))
                    illegal_instr = 1'b1;
            end

            OP_SYSTEM: begin
                use_rs2 = 1'b0;
                if (funct3 == 3'b000) begin
                    use_rs1 = 1'b0;
                    if (system_imm == 12'h000)
                        ecall = 1'b1;
                    else if (system_imm == 12'h001)
                        ebreak = 1'b1;
                    else if (system_imm == 12'h302)
                        mret = 1'b1;
                    else if (system_imm == 12'h105)
                        wfi = 1'b1;
                    else
                        illegal_instr = 1'b1;
                end else if (funct3 == 3'b100) begin
                    use_rs1       = 1'b0;
                    illegal_instr = 1'b1;
                end else begin
                    csr_en           = 1'b1;
                    reg_write        = 1'b1;
                    write_back_type  = WB_CSR;
                    // Immediate CSR forms use instruction[19:15] as zimm.
                    use_rs1          = ~funct3[2];
                end
            end

            default: begin
                illegal_instr = 1'b1;
            end
        endcase

        // is_float tracks the destination register bank, not merely whether an
        // instruction happens to consume floating-point operands.
        is_float = rd_is_fp;

        // Illegal instructions must not mutate architectural state before the
        // precise exception redirects execution to mtvec.
        if (illegal_instr) begin
            reg_write       = 1'b0;
            use_mem_type    = MEM_NONE;
            write_back_type = WB_ALU;
            bj_type         = BJ_NONE;
            use_rs1         = 1'b0;
            use_rs2         = 1'b0;
            use_rs3         = 1'b0;
            use_rd_as_src   = 1'b0;
            instr_nop       = 1'b0;
            csr_en          = 1'b0;
            mret            = 1'b0;
            wfi             = 1'b0;
            ecall           = 1'b0;
            ebreak          = 1'b0;
            fence_i         = 1'b0;
        end
    end
endmodule
