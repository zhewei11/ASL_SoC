// Minimal single-hart RISC-V External Debug Support v1.0 Debug Module.
//
// Implemented abstract commands:
//   - Access Register (cmdtype 0): RV32 GPRs plus dcsr/dpc/dscratch0
//   - Access Memory   (cmdtype 2): aligned 32-bit physical accesses
// Program Buffer and System Bus Access are deliberately not implemented.
module riscv_debug_module (
     input  logic        clk
    ,input  logic        rst

    // Debug Module Interface (DMI).
    ,input  logic        dmi_valid
    ,input  logic        dmi_write
    ,input  logic [6:0]  dmi_addr
    ,input  logic [31:0] dmi_wdata
    ,output logic        dmi_ready
    ,output logic [31:0] dmi_rdata
    ,output logic [1:0]  dmi_resp

    // Run-control interface to hart 0.
    ,output logic        hart_halt_req
    ,output logic        hart_resume_req
    ,input  logic        hart_halted
    ,input  logic        hart_reset
    ,output logic        ndmreset

    // Abstract register access. The hart accepts requests only while halted.
    ,output logic        hart_reg_valid
    ,output logic        hart_reg_write
    ,output logic [15:0] hart_regno
    ,output logic [31:0] hart_reg_wdata
    ,input  logic        hart_reg_ready
    ,input  logic [31:0] hart_reg_rdata
    ,input  logic        hart_reg_error

    // Abstract memory access through the halted hart's data path.
    ,output logic        hart_mem_valid
    ,output logic        hart_mem_write
    ,output logic [31:0] hart_mem_addr
    ,output logic [31:0] hart_mem_wdata
    ,output logic [3:0]  hart_mem_wstrb
    ,input  logic        hart_mem_ready
    ,input  logic [31:0] hart_mem_rdata
    ,input  logic        hart_mem_error
);
    localparam logic [6:0] DMI_DATA0        = 7'h04;
    localparam logic [6:0] DMI_DATA1        = 7'h05;
    localparam logic [6:0] DMI_DMCONTROL    = 7'h10;
    localparam logic [6:0] DMI_DMSTATUS     = 7'h11;
    localparam logic [6:0] DMI_HARTINFO     = 7'h12;
    localparam logic [6:0] DMI_ABSTRACTCS   = 7'h16;
    localparam logic [6:0] DMI_COMMAND      = 7'h17;
    localparam logic [6:0] DMI_ABSTRACTAUTO = 7'h18;

    localparam logic [2:0] CMDERR_NONE        = 3'd0;
    localparam logic [2:0] CMDERR_BUSY        = 3'd1;
    localparam logic [2:0] CMDERR_NOTSUP      = 3'd2;
    localparam logic [2:0] CMDERR_EXCEPTION   = 3'd3;
    localparam logic [2:0] CMDERR_HALT_RESUME = 3'd4;

    typedef enum logic [1:0] {
        CMD_IDLE,
        CMD_REGISTER,
        CMD_MEMORY
    } command_state_t;

    logic           dmactive_q;
    logic           haltreq_q;
    logic           ndmreset_q;
    logic           resethaltreq_q;
    logic           havereset_q;
    logic           resumeack_q;
    logic [31:0]    data0_q;
    logic [31:0]    data1_q;
    logic [31:0]    command_q;
    logic [2:0]     cmderr_q;
    command_state_t command_state_q;

    wire command_busy = command_state_q != CMD_IDLE;
    wire selected_hart_exists = 1'b1; // HARTSELLEN=0, only hart 0 exists.

    assign dmi_ready = 1'b1;
    assign dmi_resp = 2'b00;
    assign hart_halt_req = dmactive_q && haltreq_q;
    assign ndmreset = dmactive_q && ndmreset_q;

    assign hart_reg_valid = dmactive_q && (command_state_q == CMD_REGISTER);
    assign hart_reg_write = command_q[16];
    assign hart_regno = command_q[15:0];
    assign hart_reg_wdata = data0_q;

    assign hart_mem_valid = dmactive_q && (command_state_q == CMD_MEMORY);
    assign hart_mem_write = command_q[16];
    assign hart_mem_addr = data1_q;
    assign hart_mem_wdata = data0_q;
    assign hart_mem_wstrb = 4'hf;

    always_comb begin
        dmi_rdata = 32'd0;
        if (dmactive_q) begin
            case (dmi_addr)
                DMI_DATA0: dmi_rdata = data0_q;
                DMI_DATA1: dmi_rdata = data1_q;
                DMI_DMCONTROL: begin
                    dmi_rdata[31] = haltreq_q;
                    dmi_rdata[3] = resethaltreq_q;
                    dmi_rdata[1] = ndmreset_q;
                    dmi_rdata[0] = dmactive_q;
                end
                DMI_DMSTATUS: begin
                    dmi_rdata[19] = havereset_q;
                    dmi_rdata[18] = havereset_q;
                    dmi_rdata[17] = resumeack_q;
                    dmi_rdata[16] = resumeack_q;
                    dmi_rdata[15] = !selected_hart_exists;
                    dmi_rdata[14] = !selected_hart_exists;
                    dmi_rdata[11] = !hart_halted;
                    dmi_rdata[10] = !hart_halted;
                    dmi_rdata[9] = hart_halted;
                    dmi_rdata[8] = hart_halted;
                    dmi_rdata[7] = 1'b1; // authenticated
                    dmi_rdata[5] = 1'b1; // hasresethaltreq
                    dmi_rdata[3:0] = 4'd3; // Debug Spec 1.0
                end
                // Hart has no memory-mapped data registers and supports four
                // bytes per abstract memory/register transfer.
                DMI_HARTINFO: dmi_rdata = 32'd0;
                DMI_ABSTRACTCS: begin
                    dmi_rdata[28:24] = 5'd0; // progbufsize
                    dmi_rdata[12] = command_busy;
                    dmi_rdata[10:8] = cmderr_q;
                    dmi_rdata[3:0] = 4'd2; // data0 and data1
                end
                DMI_COMMAND: dmi_rdata = command_q;
                DMI_ABSTRACTAUTO: dmi_rdata = 32'd0;
                default: dmi_rdata = 32'd0;
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dmactive_q       <= 1'b0;
            haltreq_q        <= 1'b0;
            ndmreset_q       <= 1'b0;
            resethaltreq_q   <= 1'b0;
            havereset_q      <= 1'b1;
            resumeack_q      <= 1'b0;
            hart_resume_req  <= 1'b0;
            data0_q          <= 32'd0;
            data1_q          <= 32'd0;
            command_q        <= 32'd0;
            cmderr_q         <= CMDERR_NONE;
            command_state_q  <= CMD_IDLE;
        end else begin
            hart_resume_req <= 1'b0;

            if (hart_reset)
                havereset_q <= 1'b1;

            if (command_state_q == CMD_REGISTER && hart_reg_ready) begin
                if (hart_reg_error)
                    cmderr_q <= CMDERR_EXCEPTION;
                else if (!hart_reg_write)
                    data0_q <= hart_reg_rdata;
                command_state_q <= CMD_IDLE;
            end else if (command_state_q == CMD_MEMORY && hart_mem_ready) begin
                if (hart_mem_error)
                    cmderr_q <= CMDERR_EXCEPTION;
                else if (!hart_mem_write)
                    data0_q <= hart_mem_rdata;
                if (!hart_mem_error && command_q[19])
                    data1_q <= data1_q + 32'd4;
                command_state_q <= CMD_IDLE;
            end

            if (hart_halted)
                resumeack_q <= 1'b0;

            if (dmi_valid && dmi_write) begin
                if (dmi_addr == DMI_DMCONTROL) begin
                    if (!dmi_wdata[0]) begin
                        dmactive_q      <= 1'b0;
                        haltreq_q       <= 1'b0;
                        ndmreset_q      <= 1'b0;
                        resethaltreq_q  <= 1'b0;
                        resumeack_q     <= 1'b0;
                        cmderr_q        <= CMDERR_NONE;
                        command_state_q <= CMD_IDLE;
                    end else begin
                        dmactive_q  <= 1'b1;
                        haltreq_q   <= dmi_wdata[31];
                        ndmreset_q  <= dmi_wdata[1];
                        if (dmi_wdata[3])
                            resethaltreq_q <= 1'b1;
                        if (dmi_wdata[2])
                            resethaltreq_q <= 1'b0;
                        if (dmi_wdata[28])
                            havereset_q <= 1'b0;
                        if (dmactive_q && dmi_wdata[30] && hart_halted &&
                            !dmi_wdata[31]) begin
                            hart_resume_req <= 1'b1;
                            resumeack_q <= 1'b1;
                        end
                    end
                end else if (dmactive_q) begin
                    case (dmi_addr)
                        DMI_DATA0: begin
                            if (command_busy)
                                cmderr_q <= CMDERR_BUSY;
                            else
                                data0_q <= dmi_wdata;
                        end
                        DMI_DATA1: begin
                            if (command_busy)
                                cmderr_q <= CMDERR_BUSY;
                            else
                                data1_q <= dmi_wdata;
                        end
                        DMI_ABSTRACTCS:
                            cmderr_q <= cmderr_q & ~dmi_wdata[10:8];
                        DMI_COMMAND: begin
                            if (command_busy) begin
                                cmderr_q <= CMDERR_BUSY;
                            end else if (cmderr_q == CMDERR_NONE) begin
                                command_q <= dmi_wdata;
                                if (!hart_halted) begin
                                    cmderr_q <= CMDERR_HALT_RESUME;
                                end else begin
                                    case (dmi_wdata[31:24])
                                        8'd0: begin // Access Register
                                            if ((dmi_wdata[22:20] != 3'd2) ||
                                                dmi_wdata[18] || dmi_wdata[19])
                                                cmderr_q <= CMDERR_NOTSUP;
                                            else if (dmi_wdata[17])
                                                command_state_q <= CMD_REGISTER;
                                        end
                                        8'd2: begin // Access Memory
                                            if ((dmi_wdata[22:20] != 3'd2) ||
                                                dmi_wdata[23] ||
                                                (data1_q[1:0] != 2'b00))
                                                cmderr_q <= CMDERR_NOTSUP;
                                            else
                                                command_state_q <= CMD_MEMORY;
                                        end
                                        default:
                                            cmderr_q <= CMDERR_NOTSUP;
                                    endcase
                                end
                            end
                        end
                        DMI_ABSTRACTAUTO: begin
                            if (dmi_wdata != 32'd0)
                                cmderr_q <= CMDERR_NOTSUP;
                        end
                        default: begin
                        end
                    endcase
                end
            end

            // Optional halt-on-reset behavior. haltreq remains level-sensitive
            // until the debugger clears it through dmcontrol.
            if (dmactive_q && hart_reset && resethaltreq_q)
                haltreq_q <= 1'b1;
        end
    end
endmodule
