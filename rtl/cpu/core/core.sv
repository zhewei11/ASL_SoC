module core #(
     parameter bit ENABLE_FPU = 1'b1
) (
     input         clk
    ,input         rst
    ,input         dma_interrupt
    ,input         timer_interrupt
    ,input         wdt_interrupt
    ,input  [63:0] time_value

    // IM Interface
    ,input         im_valid
    ,input  [31:0] im_read_data
    ,output        im_stall
    ,output [31:0] im_addr
    ,output        im_flush
    ,output        im_invalidate
    ,output        im_access_allowed

    // DM Interface
    ,input         dm_valid
    ,input  [31:0] dm_read_data
    ,output        dm_req
    ,output        dm_stall
    ,output        dm_WEB
    ,output [31:0] dm_bit_en
    ,output [31:0] dm_addr
    ,output [31:0] dm_write_data
);


    // ==================================
    //    register structure building
    // ==================================

    //     IF/ID register
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] predicted_next_pc;
        logic [31:0] instruction;
        logic        instruction_access_fault;
    } if_id_reg_t;

    //     ID/EX register
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] predicted_next_pc;
        logic [31:0] instruction;
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] rs3_data;
        logic [31:0] rd_data;
        logic [31:0] immediate;
        logic [4:0]  rs1;
        logic [4:0]  rd;
        logic [11:0] csr_addr;
        logic [2:0]  csr_funct3;
        logic [3:0]  use_mem_type;
        logic [2:0]  write_back_type;
        logic [4:0]  alu_type;
        logic [3:0]  bj_type;
        logic        reg_write;
        logic        is_float;
        logic        alu_src_a;
        logic        alu_src_b;
        logic [1:0]  fwd_a_sel;
        logic [1:0]  fwd_b_sel;
        logic [1:0]  fwd_c_sel;
        logic [1:0]  fwd_d_sel;
        logic        instr_nop;
        logic        csr_en;
        logic        mret;
        logic        wfi;
        logic        ecall;
        logic        ebreak;
        logic        fence_i;
        logic        illegal_instr;
        logic        instruction_access_fault;
    } id_ex_reg_t;

    //     EX/MEM register
    typedef struct packed {
        logic        valid;
        logic [31:0] alu_result;
        logic [31:0] rs2_data;
        logic [31:0] immediate;
        logic [4:0]  rd;
        logic [3:0]  use_mem_type;
        logic [2:0]  write_back_type;
        logic        reg_write;
        logic        is_float;
    } ex_mem_reg_t;

    //     MEM/WB register
    typedef struct packed {
        logic        valid;
        logic [31:0] write_back_data;
        logic [4:0]  rd;
        logic        reg_write;
        logic        is_float;
    } mem_wb_reg_t;


    if_id_reg_t     reg_if_id;
    id_ex_reg_t     reg_id_ex;
    ex_mem_reg_t    reg_ex_mem;
    mem_wb_reg_t    reg_mem_wb;

    localparam logic [1:0] FWD_REG = 2'b00;
    localparam logic [1:0] FWD_EX  = 2'b01;
    localparam logic [1:0] FWD_MEM = 2'b10;
    localparam logic [1:0] FWD_WB  = 2'b11;

    logic        bubble;
    logic        flush;
    wire         alu_valid;
    wire         wfi_active;
    wire         trap_taken;
    wire         mret_taken;
    wire         fetch_accept;
    wire         if_id_allow_in;
    wire         id_fire;
    wire         id_wait;
    wire         mem_dependency_wait;
    wire         ex_allow_in;
    wire         ex_fire;
    wire         ex_result_valid;
    wire         mem_allow_in;
    wire         mem_stage_done;
    wire         mem_operation;
    wire         fetch_access_allowed;
    wire         data_access_allowed;
    logic        ex_result_pending_q;
    logic [31:0] ex_result_q;
    logic        ex_started_q;
    logic [4:0]  ex_fp_flags_q;
    logic        ex_fp_flags_valid_q;

    //=============================================
    //=                     IF                    =
    //=============================================
    logic [31:0] next_pc;
    logic [31:0] pc;
    logic        pc_enable;
    wire [31:0]  branch_target;
    wire [31:0]  predicted_next_pc;
    wire [31:0]  actual_next_pc;
    wire         branch_taken;
    wire         pred_taken;
    wire         bp_update_en;
    wire [31:0]  bp_update_pc;
    wire         bp_update_taken;
    wire [31:0]  bp_update_target;
    wire [1:0]   bp_update_type;
    wire         bp_resolve_en;
    wire [31:0]  bp_resolve_pc;

    assign next_pc = flush ? actual_next_pc : predicted_next_pc;
    assign pc_enable = fetch_accept || flush;

    // PC register
    pc_register u_pc_register (
         .clk       (clk)
        ,.rst       (rst)
        ,.pc_enable (pc_enable)
        ,.next_pc   (next_pc)
        ,.pc        (pc)
    );

    branch_predictor u_branch_predictor (
         .clk           (clk)
        ,.rst           (rst)
        ,.pc            (pc)
        ,.next_pc       (predicted_next_pc)
        ,.pred_taken    (pred_taken)
        ,.update_en     (bp_update_en)
        ,.update_pc     (bp_update_pc)
        ,.update_taken  (bp_update_taken)
        ,.update_target (bp_update_target)
        ,.update_type   (bp_update_type)
        ,.resolve_en    (bp_resolve_en)
        ,.resolve_pc    (bp_resolve_pc)
    );

    // Use the registered PC for cache lookup to avoid combinational feedback
    // through the cache-valid and pipeline-stall paths.
    assign im_addr = {2'b0, pc[31:2]};
    assign im_stall = !if_id_allow_in || wfi_active;
    assign im_flush = flush;
    assign im_access_allowed = fetch_access_allowed;


    //=============================================
    //=                  IF/ID                    =
    //=============================================
    always_ff @( posedge clk or posedge rst ) begin : if_id
        if (rst) begin
            reg_if_id <= '0;
        end else if (flush) begin
            reg_if_id <= '0;
        end else if (if_id_allow_in) begin
            reg_if_id.valid <= fetch_accept;
            if (fetch_accept) begin
                reg_if_id.pc                <= pc;
                reg_if_id.predicted_next_pc <= predicted_next_pc;
                reg_if_id.instruction       <= fetch_access_allowed ?
                                               im_read_data :
                                               32'h0000_0013;
                reg_if_id.instruction_access_fault <=
                    !fetch_access_allowed;
            end
        end
    end

    assign fetch_accept = (im_valid || !fetch_access_allowed) &&
                          if_id_allow_in &&
                          !wfi_active && !flush;

    //=============================================
    //=                     ID                    =
    //=============================================

    //     Wire
    // decoder
    wire [6:0]  opcode;
    wire [4:0]  rd;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [4:0]  rs3;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [11:0] csr_addr;

    //controller
    wire        reg_write;
    wire [3:0]  use_mem_type;
    wire [2:0]  write_back_type;
    wire [4:0]  alu_type;
    wire [3:0]  bj_type;
    wire [2:0]  imm_type;
    wire        is_float;
    wire        use_rs1;
    wire        use_rs2;
    wire        use_rs3;
    wire        use_rd_as_src;
    wire        rs1_is_fp;
    wire        rs2_is_fp;
    wire        rs3_is_fp;
    wire        rd_is_fp;
    wire        alu_src_a;
    wire        alu_src_b;
    wire [31:0] immediate;
    wire        instr_nop;
    wire        csr_en;
    wire        mret;
    wire        wfi;
    wire        ecall;
    wire        ebreak;
    wire        fence_i;
    wire        illegal_instr;
    wire [2:0]  fp_rounding_mode;
    wire [4:0]  fp_exception_flags;
    wire        fp_exception_flags_valid;
    wire        fp_enabled;

    wire fp_instruction = (opcode == 7'b0000111) ||
                          (opcode == 7'b0100111) ||
                          (opcode == 7'b1010011) ||
                          (opcode == 7'b1000011) ||
                          (opcode == 7'b1000111) ||
                          (opcode == 7'b1001011) ||
                          (opcode == 7'b1001111);
    wire fp_csr_access = (opcode == 7'b1110011) && (funct3 != 3'b000) &&
                         ((csr_addr == 12'h001) || (csr_addr == 12'h002) ||
                          (csr_addr == 12'h003));
    wire fp_instruction_uses_rm =
        (opcode == 7'b1000011) || (opcode == 7'b1000111) ||
        (opcode == 7'b1001011) || (opcode == 7'b1001111) ||
        ((opcode == 7'b1010011) &&
         ((funct7 == 7'b0000000) || (funct7 == 7'b0000100) ||
          (funct7 == 7'b0001000) || (funct7 == 7'b0001100) ||
          (funct7 == 7'b0101100) || (funct7 == 7'b1100000) ||
          (funct7 == 7'b1101000)));
    wire fp_dynamic_rm_illegal = fp_instruction_uses_rm &&
                                 (funct3 == 3'b111) &&
                                 (fp_rounding_mode > 3'b100);
    wire fp_access_illegal = ((!ENABLE_FPU || !fp_enabled) &&
                              (fp_instruction || fp_csr_access)) ||
                             fp_dynamic_rm_illegal;
    wire decoded_illegal_instr = illegal_instr || fp_access_illegal;
    wire decoded_reg_write = reg_write && !fp_access_illegal;
    wire [3:0] decoded_mem_type = fp_access_illegal ? 4'b0000 : use_mem_type;
    wire decoded_csr_en = csr_en && !fp_access_illegal;

    //register file
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] rs1_int_data;
    wire [31:0] rs2_int_data;
    wire [31:0] rs1_float_data;
    wire [31:0] rs2_float_data;
    wire [31:0] rs3_float_data;
    wire [31:0] rd_data_reg_out;
    wire [31:0] rd_data;
    wire [31:0] write_data;
    wire        write_en_int;
    wire        write_en_float;

    //scoreboard
    wire [1:0] fwd_a_sel;
    wire [1:0] fwd_b_sel;
    wire [1:0] fwd_c_sel;
    wire [1:0] fwd_d_sel;


    instruction_decoder u_instruction_decoder (
        //input
         .instruction (reg_if_id.instruction)
        //output
        ,.opcode      (opcode)
        ,.rd          (rd)
        ,.rs1         (rs1)
        ,.rs2         (rs2)
        ,.rs3         (rs3)
        ,.funct3      (funct3)
        ,.funct7      (funct7)
        ,.csr_addr    (csr_addr)
    );

    control_unit u_control_unit (
        //input
         .opcode          (opcode)
        ,.funct3          (funct3)
        ,.funct7          (funct7)
        ,.system_imm      (csr_addr)
        //output
        ,.reg_write       (reg_write)
        ,.use_mem_type    (use_mem_type)
        ,.write_back_type (write_back_type)
        ,.alu_type        (alu_type)
        ,.bj_type         (bj_type)
        ,.imm_type        (imm_type)
        ,.is_float        (is_float)
        ,.use_rs1         (use_rs1)
        ,.use_rs2         (use_rs2)
        ,.use_rs3         (use_rs3)
        ,.use_rd_as_src   (use_rd_as_src)
        ,.rs1_is_fp       (rs1_is_fp)
        ,.rs2_is_fp       (rs2_is_fp)
        ,.rs3_is_fp       (rs3_is_fp)
        ,.rd_is_fp        (rd_is_fp)
        ,.alu_src_a       (alu_src_a)
        ,.alu_src_b       (alu_src_b)
        ,.instr_nop       (instr_nop)
        ,.csr_en          (csr_en)
        ,.mret            (mret)
        ,.wfi             (wfi)
        ,.ecall           (ecall)
        ,.ebreak          (ebreak)
        ,.fence_i         (fence_i)
        ,.illegal_instr   (illegal_instr)
    );

    imm_gen u_imm_gen (
        //input
         .instruction (reg_if_id.instruction)
        //output
        ,.imm_type    (imm_type)
        ,.immediate   (immediate)
    );

    integer_register_file u_int_register_file (
        //input
         .clk          (clk)
        ,.rst          (rst)
        ,.rs1          (rs1)
        ,.rs2          (rs2)
        ,.rd_read      (rd)
        //output
        ,.read_data1   (rs1_int_data)
        ,.read_data2   (rs2_int_data)
        ,.read_data3   (rd_data_reg_out)
        //write input
        ,.rd_write     (reg_mem_wb.rd)
        ,.write_enable (write_en_int)
        ,.write_data   (write_data)
    );

    generate
        if (ENABLE_FPU) begin : g_float_register_file
            float_register_file u_float_register_file (
                //input
                 .clk          (clk)
                ,.rst          (rst)
                ,.rs1          (rs1)
                ,.rs2          (rs2)
                ,.rs3          (rs3)
                //output
                ,.read_data1   (rs1_float_data)
                ,.read_data2   (rs2_float_data)
                ,.read_data3   (rs3_float_data)
                //write input
                ,.rd           (reg_mem_wb.rd)
                ,.write_enable (write_en_float)
                ,.write_data   (write_data)
            );
        end else begin : g_no_float_register_file
            assign rs1_float_data = 32'd0;
            assign rs2_float_data = 32'd0;
            assign rs3_float_data = 32'd0;
        end
    endgenerate

    scoreboard u_scoreboard (
         .rs1           (rs1)
        ,.rs2           (rs2)
        ,.rs3           (rs3)
        ,.rd            (rd)
        ,.use_rs1       (use_rs1)
        ,.use_rs2       (use_rs2)
        ,.use_rs3       (use_rs3)
        ,.use_rd_as_src (use_rd_as_src)
        ,.rs1_is_fp     (ENABLE_FPU && rs1_is_fp)
        ,.rs2_is_fp     (ENABLE_FPU && rs2_is_fp)
        ,.rs3_is_fp     (ENABLE_FPU && rs3_is_fp)
        ,.rd_is_fp      (ENABLE_FPU && rd_is_fp)
        ,.ex_rd         (reg_id_ex.rd)
        ,.ex_reg_write  (reg_id_ex.valid && reg_id_ex.reg_write)
        ,.ex_is_load        (reg_id_ex.valid &&
                             (reg_id_ex.write_back_type == 3'b001))
        ,.ex_is_fp      (reg_id_ex.is_float)
        ,.mem_rd        (reg_ex_mem.rd)
        ,.mem_reg_write (reg_ex_mem.valid && reg_ex_mem.reg_write)
        ,.mem_is_fp     (reg_ex_mem.is_float)
        ,.wb_rd         (reg_mem_wb.rd)
        ,.wb_reg_write  (reg_mem_wb.valid && reg_mem_wb.reg_write)
        ,.wb_is_fp      (reg_mem_wb.is_float)
        ,.flush         (flush)
        ,.fwd_a_sel     (fwd_a_sel)
        ,.fwd_b_sel     (fwd_b_sel)
        ,.fwd_c_sel     (fwd_c_sel)
        ,.fwd_d_sel     (fwd_d_sel)
        ,.bubble        (bubble)
    );
    //=============================================
    //=                    MUX                    =
    //=============================================

    // RS1 Forwarding Mux
    assign rs1_data = (fwd_a_sel == FWD_WB) ?
                      reg_mem_wb.write_back_data :
                      rs1_is_fp ? rs1_float_data : rs1_int_data;

    // RS2 Forwarding Mux
    assign rs2_data = (fwd_b_sel == FWD_WB) ?
                      reg_mem_wb.write_back_data :
                      rs2_is_fp ? rs2_float_data : rs2_int_data;

    assign rd_data = (fwd_c_sel == FWD_WB) ?
                     reg_mem_wb.write_back_data : rd_data_reg_out;

    wire [31:0] rs3_data = (fwd_d_sel == FWD_WB) ?
                           reg_mem_wb.write_back_data : rs3_float_data;

    // A consumer may enter EX behind a MEM-stage producer only when that
    // producer advances to WB on the same edge.  This is the extra dependency
    // check required once the pipeline stages can stall independently.
    assign mem_dependency_wait = reg_if_id.valid && !mem_stage_done &&
                                 ((fwd_a_sel == FWD_MEM) ||
                                  (fwd_b_sel == FWD_MEM) ||
                                  (fwd_c_sel == FWD_MEM) ||
                                  (fwd_d_sel == FWD_MEM));
    // Serialize CSR instructions so an immediately following FP operation sees
    // the updated mstatus.FS or frm value.
    wire csr_serialization_wait = reg_id_ex.valid && reg_id_ex.csr_en;
    assign id_wait       = bubble || mem_dependency_wait || wfi_active ||
                           csr_serialization_wait;
    assign id_fire       = reg_if_id.valid && ex_allow_in && !id_wait;
    assign if_id_allow_in = !reg_if_id.valid || id_fire;

    //=============================================
    //=                  ID/EX                    =
    //=============================================
    always_ff @( posedge clk or posedge rst ) begin : id_ex
        if (rst) begin
            reg_id_ex <= '0;
        end else if (flush) begin
            reg_id_ex <= '0;
        end else if (ex_allow_in) begin
            reg_id_ex.valid <= id_fire;
            if (id_fire) begin
                reg_id_ex.pc                <= reg_if_id.pc;
                reg_id_ex.predicted_next_pc <= reg_if_id.predicted_next_pc;
                reg_id_ex.instruction       <= reg_if_id.instruction;
                reg_id_ex.rs1_data          <= rs1_data;
                reg_id_ex.rs2_data          <= rs2_data;
                reg_id_ex.rs3_data          <= rs3_data;
                reg_id_ex.rd_data           <= rd_data;
                reg_id_ex.immediate         <= immediate;
                reg_id_ex.rs1               <= rs1;
                reg_id_ex.rd                <= rd;
                reg_id_ex.csr_addr          <= csr_addr;
                reg_id_ex.csr_funct3        <= funct3;
                reg_id_ex.use_mem_type      <= decoded_mem_type;
                reg_id_ex.write_back_type   <= write_back_type;
                reg_id_ex.alu_type          <= alu_type;
                reg_id_ex.bj_type           <= bj_type;
                reg_id_ex.reg_write         <= decoded_reg_write;
                reg_id_ex.is_float          <= ENABLE_FPU && is_float;
                reg_id_ex.alu_src_a         <= alu_src_a;
                reg_id_ex.alu_src_b         <= alu_src_b;
                reg_id_ex.fwd_a_sel         <= fwd_a_sel;
                reg_id_ex.fwd_b_sel         <= fwd_b_sel;
                reg_id_ex.fwd_c_sel         <= fwd_c_sel;
                reg_id_ex.fwd_d_sel         <= fwd_d_sel;
                reg_id_ex.instr_nop         <= instr_nop;
                reg_id_ex.csr_en            <= decoded_csr_en;
                reg_id_ex.mret              <= mret;
                reg_id_ex.wfi               <= wfi;
                reg_id_ex.ecall             <= ecall;
                reg_id_ex.ebreak            <= ebreak;
                reg_id_ex.fence_i           <= fence_i;
                reg_id_ex.illegal_instr     <= decoded_illegal_instr;
                reg_id_ex.instruction_access_fault <=
                    reg_if_id.instruction_access_fault;
            end
        end
    end


    //=============================================
    //=                     EX                    =
    //=============================================

    // alu
    wire [31:0] alu_result;
    wire [31:0] ex_result;
    wire        alu_enable;
    wire [31:0] dm_rs2_data;
    wire [31:0] operand_a;
    wire [31:0] operand_b;
    wire [31:0] operand_c;
    wire [31:0] operand_d;
    // jb_unit

    // csr_registers
    wire [31:0] csr_read_data;
    wire [31:0] csr_redirect_pc;
    wire        csr_execute;
    wire [4:0]  ex_commit_fp_flags;
    wire        ex_commit_fp_flags_valid;
    wire [31:0] branch_actual_next_pc;
    wire        branch_flush;
    wire        fence_i_flush;
    wire        ex_data_access = reg_id_ex.valid &&
                                 (reg_id_ex.use_mem_type != 4'b0000);
    wire        ex_data_write = (reg_id_ex.use_mem_type >= 4'b0001) &&
                                (reg_id_ex.use_mem_type <= 4'b0011);
    logic [2:0] ex_data_access_bytes;
    wire        pmp_data_access_fault = ex_fire && ex_data_access &&
                                        !data_access_allowed;

    always_comb begin
        case (reg_id_ex.use_mem_type)
            4'b0001, 4'b0100: ex_data_access_bytes = 3'd4;
            4'b0010, 4'b0101,
            4'b1000:          ex_data_access_bytes = 3'd2;
            default:          ex_data_access_bytes = 3'd1;
        endcase
    end

    // EX may continue a multi-cycle operation while IF or MEM is stalled.  A
    // one-entry result buffer preserves a pulse-style MUL/FPU result when MEM
    // cannot accept it immediately.
    assign alu_enable  = reg_id_ex.valid && !wfi_active &&
                         !ex_result_pending_q && !ex_started_q;
    assign ex_result_valid = reg_id_ex.valid && !wfi_active &&
                             (ex_result_pending_q || alu_valid);
    assign ex_fire     = ex_result_valid && mem_allow_in;
    assign ex_allow_in = !reg_id_ex.valid || ex_fire;
    assign csr_execute = ex_fire && !wfi_active;

    alu #(
         .ENABLE_FPU (ENABLE_FPU)
    ) u_alu(
         .clk                (clk)
        ,.rst                (rst)
        ,.flush              (flush)
        ,.enable             (alu_enable)
        ,.operand_a          (operand_a)
        ,.operand_b          (operand_b)
        ,.alu_op             (reg_id_ex.alu_type)
        ,.rd_data            (operand_c)
        ,.operand_c          (operand_d)
        ,.instruction        (reg_id_ex.instruction)
        ,.fp_rounding_mode   (fp_rounding_mode)
        ,.result             (alu_result)
        ,.valid              (alu_valid)
        ,.fp_exception_flags (fp_exception_flags)
        ,.fp_flags_valid     (fp_exception_flags_valid)
    );

    jb_unit u_jb_unit (
        //input
         .pc        (reg_id_ex.pc)
        ,.rs1       (operand_a)
        ,.rs2       (operand_b)
        ,.imm       (reg_id_ex.immediate)
        ,.bj_type   (reg_id_ex.bj_type)
        //output
        ,.jb_pc_sel (branch_taken)
        ,.jb_pc     (branch_target)
    );

    wire ex_is_jal    = (reg_id_ex.bj_type == 4'b1000);
    wire ex_is_jalr   = (reg_id_ex.bj_type == 4'b1001);
    wire ex_is_bj     = (reg_id_ex.bj_type != 4'b0000);
    wire ex_is_call   = (ex_is_jal || ex_is_jalr) && (reg_id_ex.rd == 5'd1 || reg_id_ex.rd == 5'd5);
    wire ex_is_ret    = ex_is_jalr && (reg_id_ex.rd == 5'd0) && (reg_id_ex.rs1 == 5'd1 || reg_id_ex.rs1 == 5'd5);

    assign branch_actual_next_pc = branch_taken ? branch_target
                                                : reg_id_ex.pc + 32'd4;
    // A BTB entry can become stale when software/DMA replaces an instruction
    // (the WDT test deliberately changes a normal instruction into a dead-loop
    // JAL and later restores it).  Check every valid instruction, not only an
    // instruction that currently decodes as a branch, so a stale taken prediction
    // on a restored non-branch is redirected to PC+4.
    assign branch_flush     = reg_id_ex.valid && reg_id_ex.instr_nop && ex_fire &&
                              (reg_id_ex.predicted_next_pc != branch_actual_next_pc);
    assign fence_i_flush    = reg_id_ex.valid && reg_id_ex.fence_i && ex_fire;
    assign actual_next_pc   = (trap_taken || mret_taken) ? csr_redirect_pc :
                              fence_i_flush ? reg_id_ex.pc + 32'd4 :
                              branch_actual_next_pc;
    assign flush            = trap_taken || mret_taken || branch_flush ||
                              fence_i_flush;
    assign im_invalidate    = fence_i_flush;
    assign bp_update_en     = reg_id_ex.valid && ex_is_bj && ex_fire;
    assign bp_update_pc     = reg_id_ex.pc;
    assign bp_update_taken  = branch_taken;
    assign bp_update_target = branch_target;
    assign bp_resolve_en    = reg_id_ex.valid && reg_id_ex.instr_nop && ex_fire;
    assign bp_resolve_pc    = reg_id_ex.pc;
    assign bp_update_type   = ex_is_call ? 2'b10 :
                              ex_is_ret  ? 2'b11 :
                              (ex_is_jal || ex_is_jalr) ? 2'b01 : 2'b00;

    csr_registers #(
         .ENABLE_FPU (ENABLE_FPU)
    ) u_csr_registers(
        //input
         .clk                  (clk)
        ,.rst                  (rst)
        ,.execute              (csr_execute)
        ,.instr_valid          (reg_id_ex.instr_nop)
        ,.csr_en               (reg_id_ex.csr_en)
        ,.mret                 (reg_id_ex.mret)
        ,.wfi                  (reg_id_ex.wfi)
        ,.ecall                (reg_id_ex.ecall)
        ,.ebreak               (reg_id_ex.ebreak)
        ,.illegal_instr        (reg_id_ex.illegal_instr)
        ,.instruction_access_fault
                            (reg_id_ex.instruction_access_fault)
        ,.csr_funct3           (reg_id_ex.csr_funct3)
        ,.csr_addr             (reg_id_ex.csr_addr)
        ,.csr_rs1              (reg_id_ex.rs1)
        ,.csr_rs1_data         (operand_a)
        ,.current_pc           (reg_id_ex.pc)
        // An asynchronous interrupt retires the current instruction first.  Resume
        // at its architectural successor, including the target of a taken branch
        // or jump, rather than unconditionally at the sequential PC.
        ,.trap_resume_pc       (branch_actual_next_pc)
        ,.instruction          (reg_id_ex.instruction)
        ,.fetch_address        (pc)
        ,.data_address         (ex_result)
        ,.data_access          (ex_data_access)
        ,.data_write           (ex_data_write)
        ,.data_access_bytes    (ex_data_access_bytes)
        ,.dma_interrupt        (dma_interrupt)
        ,.timer_interrupt      (timer_interrupt)
        ,.wdt_interrupt        (wdt_interrupt)
        ,.time_value           (time_value)
        ,.fp_flags_valid    (ex_commit_fp_flags_valid && ex_fire &&
                             reg_id_ex.instr_nop)
        ,.fp_flags             (ex_commit_fp_flags)
        ,.fp_state_dirty       (write_en_float)
        //output
        ,.csr_read_data        (csr_read_data)
        ,.redirect_pc          (csr_redirect_pc)
        ,.trap_taken           (trap_taken)
        ,.mret_taken           (mret_taken)
        ,.wfi_active           (wfi_active)
        ,.fp_rounding_mode     (fp_rounding_mode)
        ,.fp_enabled           (fp_enabled)
        ,.fetch_access_allowed (fetch_access_allowed)
        ,.data_access_allowed  (data_access_allowed)
        ,.current_privilege    ()
    );

    //     mux
    assign operand_a =  (reg_id_ex.alu_src_a)           ? reg_id_ex.pc :
                        (reg_id_ex.fwd_a_sel == FWD_EX)  ? reg_ex_mem.alu_result :
                        (reg_id_ex.fwd_a_sel == FWD_MEM) ? reg_mem_wb.write_back_data :
                        reg_id_ex.rs1_data;

    assign operand_b =  (reg_id_ex.alu_src_b)           ? reg_id_ex.immediate :
                        (reg_id_ex.fwd_b_sel == FWD_EX)  ? reg_ex_mem.alu_result :
                        (reg_id_ex.fwd_b_sel == FWD_MEM) ? reg_mem_wb.write_back_data :
                        reg_id_ex.rs2_data;

    assign dm_rs2_data = (reg_id_ex.fwd_b_sel == FWD_EX)  ? reg_ex_mem.alu_result :
                         (reg_id_ex.fwd_b_sel == FWD_MEM) ? reg_mem_wb.write_back_data :
                         reg_id_ex.rs2_data;

    assign operand_c =  (reg_id_ex.fwd_c_sel == FWD_EX)  ? reg_ex_mem.alu_result :
                        (reg_id_ex.fwd_c_sel == FWD_MEM) ? reg_mem_wb.write_back_data :
                        reg_id_ex.rd_data;

    assign operand_d =  (reg_id_ex.fwd_d_sel == FWD_EX)  ? reg_ex_mem.alu_result :
                        (reg_id_ex.fwd_d_sel == FWD_MEM) ? reg_mem_wb.write_back_data :
                        reg_id_ex.rs3_data;

    wire [31:0] pc_plus_4 = reg_id_ex.pc + 4;
    logic [31:0] ex_result_comb;
    assign ex_result = ex_result_pending_q ? ex_result_q : ex_result_comb;
    assign ex_commit_fp_flags = ex_result_pending_q
                              ? ex_fp_flags_q
                              : fp_exception_flags;
    assign ex_commit_fp_flags_valid = ex_result_pending_q
                                    ? ex_fp_flags_valid_q
                                    : fp_exception_flags_valid;

    always @(*) begin
        case (reg_id_ex.write_back_type)
            3'b000:  ex_result_comb = alu_result;       // WB_ALU
            3'b010:  ex_result_comb = pc_plus_4;        // WB_PC (JAL/JALR)
            3'b011:  ex_result_comb = reg_id_ex.immediate; // WB_IMM (LUI)
            3'b100:  ex_result_comb = csr_read_data;    // WB_CSR
            default: ex_result_comb = alu_result;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin : ex_result_buffer
        if (rst) begin
            ex_result_pending_q <= 1'b0;
            ex_result_q         <= 32'd0;
            ex_started_q        <= 1'b0;
            ex_fp_flags_q       <= 5'd0;
            ex_fp_flags_valid_q <= 1'b0;
        end else if (flush) begin
            ex_result_pending_q <= 1'b0;
            ex_started_q        <= 1'b0;
            ex_fp_flags_valid_q <= 1'b0;
        end else if (ex_fire) begin
            ex_result_pending_q <= 1'b0;
            ex_started_q        <= 1'b0;
            ex_fp_flags_valid_q <= 1'b0;
        end else if (reg_id_ex.valid && !wfi_active &&
                     alu_valid && !ex_result_pending_q) begin
            ex_result_pending_q <= 1'b1;
            ex_result_q         <= ex_result_comb;
            ex_fp_flags_q       <= fp_exception_flags;
            ex_fp_flags_valid_q <= fp_exception_flags_valid;
        end else if (alu_enable && !alu_valid) begin
            // Multi-cycle functional units receive exactly one start pulse.
            ex_started_q <= 1'b1;
        end
    end


    //     EX -> MEM
    always_ff @( posedge clk or posedge rst ) begin : ex_mem
        if (rst) begin
            reg_ex_mem <= '0;
        end else if (mem_allow_in) begin
            reg_ex_mem.valid <= ex_fire && !pmp_data_access_fault;
            if (ex_fire && !pmp_data_access_fault) begin
                reg_ex_mem.alu_result      <= ex_result;
                reg_ex_mem.rs2_data        <= dm_rs2_data;
                reg_ex_mem.immediate       <= reg_id_ex.immediate;
                reg_ex_mem.rd              <= reg_id_ex.rd;
                reg_ex_mem.use_mem_type    <= reg_id_ex.use_mem_type;
                reg_ex_mem.write_back_type <= reg_id_ex.write_back_type;
                reg_ex_mem.reg_write       <= reg_id_ex.reg_write;
                reg_ex_mem.is_float        <= reg_id_ex.is_float;
            end
        end
    end

    //=============================================
    //=                     MEM                   =
    //=============================================

    assign mem_operation  = reg_ex_mem.valid &&
                            (reg_ex_mem.use_mem_type != 4'b0000);
    assign mem_stage_done = !reg_ex_mem.valid || !mem_operation || dm_valid;
    assign mem_allow_in   = !reg_ex_mem.valid || mem_stage_done;

    assign dm_req = mem_operation;
    assign dm_addr  = {2'b0, reg_ex_mem.alu_result[31:2]};
    assign dm_write_data =  (reg_ex_mem.alu_result[1:0] == 2'b00) ? reg_ex_mem.rs2_data:
                            (reg_ex_mem.alu_result[1:0] == 2'b01) ? {reg_ex_mem.rs2_data[23:0], 8'd0} :
                            (reg_ex_mem.alu_result[1:0] == 2'b10) ? {reg_ex_mem.rs2_data[15:0], 16'd0} : {reg_ex_mem.rs2_data[7:0], 24'd0};
    assign dm_WEB = reg_ex_mem.use_mem_type[2];
    assign dm_bit_en =  (reg_ex_mem.use_mem_type[1:0] == 2'b01) ? 32'h0000_0000 :
                        (reg_ex_mem.use_mem_type[1:0] == 2'b10) ? (reg_ex_mem.alu_result[1] ? 32'h0000_ffff : 32'hffff_0000) :
                        (reg_ex_mem.use_mem_type[1:0] == 2'b11) ? (reg_ex_mem.alu_result[1] ? (reg_ex_mem.alu_result[0] ? 32'h00ff_ffff : 32'hff00_ffff) : (reg_ex_mem.alu_result[0] ? 32'hffff_00ff : 32'hffff_ff00) ) : 32'hffff_ffff;

    // WB is always ready, so a completed cache response is consumed immediately.
    assign dm_stall = 1'b0;

    logic [31:0] ld_result;
    wire [31:0]  write_back_data;
    assign write_back_data = (reg_ex_mem.use_mem_type[2] == 1'b1) ? ld_result : reg_ex_mem.alu_result;

    LD_filter u_ld_filter (
         .use_mem_type  (reg_ex_mem.use_mem_type)
        ,.mem_read_data (dm_read_data)
        ,.addr_offset   (reg_ex_mem.alu_result[1:0])
        ,.load_result   (ld_result)
    );


    //     MEM -> WB
    //      Reg
    always_ff @( posedge clk or posedge rst ) begin : mem_wb
        if (rst) begin
            reg_mem_wb <= '0;
        end else begin
            reg_mem_wb.valid <= reg_ex_mem.valid && mem_stage_done;
            if (reg_ex_mem.valid && mem_stage_done) begin
                reg_mem_wb.write_back_data <= write_back_data;
                reg_mem_wb.rd              <= reg_ex_mem.rd;
                reg_mem_wb.reg_write       <= reg_ex_mem.reg_write;
                reg_mem_wb.is_float        <= reg_ex_mem.is_float;
            end
        end
    end


    //=============================================
    //=                     WB                    =
    //=============================================

    assign write_en_int   = reg_mem_wb.valid && reg_mem_wb.reg_write &&
                            !reg_mem_wb.is_float;
    assign write_en_float = reg_mem_wb.valid && reg_mem_wb.reg_write &&
                             reg_mem_wb.is_float;
    assign write_data     = reg_mem_wb.write_back_data;

endmodule
