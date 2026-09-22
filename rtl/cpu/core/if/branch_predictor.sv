`include "rtos_core_config.svh"

module branch_predictor (
     input  logic        clk
    ,input  logic        rst

    // Interface with IF Stage (PC)
    ,input  logic [31:0] pc
    ,output logic [31:0] next_pc // Predicted PC
    ,output logic        pred_taken

    // Update Interface from EX Stage
    ,input  logic        update_en // Resolution valid
    ,input  logic [31:0] update_pc // PC of instruction being resolved
    ,input  logic        update_taken // Actual taken/not taken
    ,input  logic [31:0] update_target // Actual target
    ,input  logic [1:0]  update_type // 00:Cond, 01:Jump, 10:Call, 11:Ret

    // Every resolved instruction is reported so a stale BTB entry can be
    // removed when code at that PC is replaced by a non-branch instruction.
    ,input  logic        resolve_en
    ,input  logic [31:0] resolve_pc
);

    // Internal Signals
    logic        btb_hit;
    logic [31:0] btb_target;
    logic [1:0]  btb_type;

    logic bht_taken;

    logic        ras_valid;
    logic [31:0] ras_target;
    logic        ras_push;
    logic        ras_pop;
    logic [31:0] ras_push_addr;

    // -------------------------------------------------------------------------
    // Branch Target Buffer (BPB/BTB)
    // -------------------------------------------------------------------------
    bpb #(
         .ENTRIES (`RTOS_CORE_BTB_ENTRIES)
    ) u_bpb (
         .clk           (clk)
        ,.rst           (rst)
        ,.pc            (pc)
        ,.hit           (btb_hit)
        ,.target_pc     (btb_target)
        ,.branch_type   (btb_type)
        ,.update_en(update_en) // We update BTB for any branch/jump
        ,.update_pc     (update_pc)
        ,.update_target (update_target)
        ,.update_type   (update_type)
        ,.clear_en      (resolve_en && !update_en)
        ,.clear_pc      (resolve_pc)
    );

    // -------------------------------------------------------------------------
    // Branch History Table (BHT) - Direction Prediction
    // -------------------------------------------------------------------------
    // Only update BHT for conditional branches
    logic bht_update_en;
    assign bht_update_en = update_en && (update_type == 2'b00);

    bht #(
         .ENTRIES (`RTOS_CORE_BHT_ENTRIES)
    ) u_bht (
         .clk           (clk)
        ,.rst           (rst)
        ,.pc            (pc)
        ,.predict_taken (bht_taken)
        ,.update_en(bht_update_en) // Update only on conditional
        ,.update_pc     (update_pc)
        ,.actual_taken  (update_taken)
    );

    // -------------------------------------------------------------------------
    // Return Address Stack (RAS)
    // -------------------------------------------------------------------------
    // Push on Call, Pop on Ret
    // We rely on BTB to tell us if it's a Call or Ret during Fetch.

    // We use the architectural updates (from EX stage) to manage the RAS stack
    // to prevent corruption from speculative fetching.
    // This introduces latency for back-to-back Call-Ret pairs but guarantees correctness.

    assign ras_push = update_en && (update_type == 2'b10); // CALL
    assign ras_pop  = update_en && (update_type == 2'b11); // RET
    // Note: checks if RVC is supported, if so +2, else +4. Core is 32-bit aligned currently.
    assign ras_push_addr = update_pc + 32'd4;

    ras #(
         .DEPTH (`RTOS_CORE_RAS_DEPTH)
    ) u_ras (
         .clk       (clk)
        ,.rst       (rst)
        ,.push      (ras_push)
        ,.pop       (ras_pop)
        ,.push_addr (ras_push_addr)
        ,.pop_addr  (ras_target)
        ,.valid     (ras_valid)
    );

    // -------------------------------------------------------------------------
    // Prediction Logic
    // -------------------------------------------------------------------------
    always_comb begin
        next_pc = pc + 32'd4; // Default: Not Taken
        pred_taken = 1'b0;

        if (btb_hit) begin
            case (btb_type)
                2'b00: begin // Conditional
                    if (bht_taken) begin
                        next_pc = btb_target;
                        pred_taken = 1'b1;
                    end
                end
                2'b01: begin // Jump (Unconditional)
                    next_pc = btb_target;
                    pred_taken = 1'b1;
                end
                2'b10: begin // Call
                    next_pc = btb_target;
                    pred_taken = 1'b1;
                end
                2'b11: begin // Ret
                    if (ras_valid) begin
                        next_pc = ras_target; // Predict return address from RAS
                        pred_taken = 1'b1;
                    end else begin
                        next_pc = btb_target; // Fallback to BTB if RAS empty
                        pred_taken = 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
