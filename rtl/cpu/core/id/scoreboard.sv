module scoreboard (
    // Consumer currently in ID.
     input  logic [4:0] rs1
    ,input  logic [4:0] rs2
    ,input  logic [4:0] rs3
    ,input  logic [4:0] rd
    ,input  logic       use_rs1
    ,input  logic       use_rs2
    ,input  logic       use_rs3
    ,input  logic       use_rd_as_src
    ,input  logic       rs1_is_fp
    ,input  logic       rs2_is_fp
    ,input  logic       rs3_is_fp
    ,input  logic       rd_is_fp

    // Producers already present in the five-stage pipeline.
    ,input  logic [4:0] ex_rd
    ,input  logic       ex_reg_write
    ,input  logic       ex_is_load
    ,input  logic       ex_is_fp
    ,input  logic [4:0] mem_rd
    ,input  logic       mem_reg_write
    ,input  logic       mem_is_fp
    ,input  logic [4:0] wb_rd
    ,input  logic       wb_reg_write
    ,input  logic       wb_is_fp

    ,input  logic       flush

    ,output logic [1:0] fwd_a_sel
    ,output logic [1:0] fwd_b_sel
    ,output logic [1:0] fwd_c_sel
    ,output logic [1:0] fwd_d_sel
    ,output logic       bubble
);

    localparam logic [1:0] FWD_REG = 2'b00;
    localparam logic [1:0] FWD_EX  = 2'b01;
    localparam logic [1:0] FWD_MEM = 2'b10;
    localparam logic [1:0] FWD_WB  = 2'b11;

    function automatic logic register_match (
         input logic [4:0] source_index
        ,input logic       source_is_fp
        ,input logic [4:0] destination_index
        ,input logic       destination_is_fp
    );
        register_match = (source_index == destination_index) &&
                         (source_is_fp == destination_is_fp) &&
                         (source_is_fp || (source_index != 5'd0));
    endfunction

    function automatic logic [1:0] select_forward (
         input logic [4:0] source_index
        ,input logic       source_is_fp
    );
        begin
            if (ex_reg_write &&
                register_match(source_index, source_is_fp,
                               ex_rd, ex_is_fp))
                select_forward = FWD_EX;
            else if (mem_reg_write &&
                     register_match(source_index, source_is_fp,
                                    mem_rd, mem_is_fp))
                select_forward = FWD_MEM;
            else if (wb_reg_write &&
                     register_match(source_index, source_is_fp,
                                    wb_rd, wb_is_fp))
                select_forward = FWD_WB;
            else
                select_forward = FWD_REG;
        end
    endfunction

    always_comb begin
        fwd_a_sel = use_rs1 ?
                    select_forward(rs1, rs1_is_fp) : FWD_REG;
        fwd_b_sel = use_rs2 ?
                    select_forward(rs2, rs2_is_fp) : FWD_REG;
        fwd_c_sel = use_rd_as_src ?
                    select_forward(rd, rd_is_fp) : FWD_REG;
        fwd_d_sel = use_rs3 ?
                    select_forward(rs3, rs3_is_fp) : FWD_REG;

        bubble = !flush && ex_reg_write && ex_is_load &&
                 ((use_rs1 &&
                   register_match(rs1, rs1_is_fp, ex_rd, ex_is_fp)) ||
                  (use_rs2 &&
                   register_match(rs2, rs2_is_fp, ex_rd, ex_is_fp)) ||
                  (use_rs3 &&
                   register_match(rs3, rs3_is_fp, ex_rd, ex_is_fp)) ||
                  (use_rd_as_src &&
                   register_match(rd, rd_is_fp, ex_rd, ex_is_fp)));

        if (bubble) begin
            fwd_a_sel = FWD_REG;
            fwd_b_sel = FWD_REG;
            fwd_c_sel = FWD_REG;
            fwd_d_sel = FWD_REG;
        end
    end

endmodule
