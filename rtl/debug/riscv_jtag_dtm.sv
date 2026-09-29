// IEEE 1149.1 TAP carrying a RISC-V Debug Transport Module (DTM) v1.
// The bundled-data toggle handshake keeps the asynchronous JTAG clock out of
// the SoC clock domain; request/response payloads remain stable until acked.
module riscv_jtag_dtm (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        jtag_tck
    ,input  logic        jtag_tms
    ,input  logic        jtag_tdi
    ,input  logic        jtag_trst_n
    ,output logic        jtag_tdo

    ,output logic        dmi_valid
    ,output logic        dmi_write
    ,output logic [6:0]  dmi_addr
    ,output logic [31:0] dmi_wdata
    ,input  logic        dmi_ready
    ,input  logic [31:0] dmi_rdata
    ,input  logic [1:0]  dmi_resp
    ,output logic        dm_hard_reset
);
    localparam logic [4:0] IR_IDCODE = 5'h01;
    localparam logic [4:0] IR_DTMCS  = 5'h10;
    localparam logic [4:0] IR_DMI    = 5'h11;
    localparam logic [4:0] IR_BYPASS = 5'h1f;

    localparam logic [3:0] TEST_LOGIC_RESET = 4'd0;
    localparam logic [3:0] RUN_TEST_IDLE    = 4'd1;
    localparam logic [3:0] SELECT_DR_SCAN   = 4'd2;
    localparam logic [3:0] CAPTURE_DR       = 4'd3;
    localparam logic [3:0] SHIFT_DR         = 4'd4;
    localparam logic [3:0] EXIT1_DR         = 4'd5;
    localparam logic [3:0] PAUSE_DR         = 4'd6;
    localparam logic [3:0] EXIT2_DR         = 4'd7;
    localparam logic [3:0] UPDATE_DR        = 4'd8;
    localparam logic [3:0] SELECT_IR_SCAN   = 4'd9;
    localparam logic [3:0] CAPTURE_IR       = 4'd10;
    localparam logic [3:0] SHIFT_IR         = 4'd11;
    localparam logic [3:0] EXIT1_IR         = 4'd12;
    localparam logic [3:0] PAUSE_IR         = 4'd13;
    localparam logic [3:0] EXIT2_IR         = 4'd14;
    localparam logic [3:0] UPDATE_IR        = 4'd15;

    logic [3:0] tap_state_q;
    logic [3:0] tap_state_d;
    logic [4:0] ir_q;
    logic [4:0] ir_shift_q;
    logic [40:0] dr_shift_q;

    // JTAG-domain request payload and toggle.
    logic        req_toggle_tck;
    logic [1:0]  req_op_tck;
    logic [6:0]  req_addr_tck;
    logic [31:0] req_data_tck;
    logic [6:0]  last_addr_tck;
    logic        dmi_busy_sticky_tck;
    logic        hard_reset_toggle_tck;

    // System-domain synchronization and response payload.
    logic req_sync1_q;
    logic req_sync2_q;
    logic req_seen_q;
    logic req_active_q;
    logic [1:0]  req_op_sys_q;
    logic [6:0]  req_addr_sys_q;
    logic [31:0] req_data_sys_q;
    logic        ack_toggle_sys_q;
    logic [31:0] response_data_sys_q;
    logic [1:0]  response_status_sys_q;
    logic hard_reset_sync1_q;
    logic hard_reset_sync2_q;
    logic hard_reset_seen_q;

    // Return-toggle synchronization into TCK domain.
    logic ack_sync1_q;
    logic ack_sync2_q;

    wire request_outstanding = ack_sync2_q != req_toggle_tck;
    wire [1:0] captured_dmi_status = request_outstanding ? 2'b11 :
                                     response_status_sys_q;
    wire [31:0] dtmcs_value = {
        11'd0,
        3'd0,                // errinfo
        1'b0,                // dmihardreset is write-only
        1'b0,                // dmireset is write-only
        1'b0,
        3'd1,                // idle: one Run-Test/Idle cycle
        dmi_busy_sticky_tck ? 2'b11 : 2'b00,
        6'd7,                // abits
        4'd1                 // DTM version 1
    };

    always_comb begin
        case (tap_state_q)
            TEST_LOGIC_RESET: tap_state_d = jtag_tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE:    tap_state_d = jtag_tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            SELECT_DR_SCAN:   tap_state_d = jtag_tms ? SELECT_IR_SCAN : CAPTURE_DR;
            CAPTURE_DR:       tap_state_d = jtag_tms ? EXIT1_DR : SHIFT_DR;
            SHIFT_DR:         tap_state_d = jtag_tms ? EXIT1_DR : SHIFT_DR;
            EXIT1_DR:         tap_state_d = jtag_tms ? UPDATE_DR : PAUSE_DR;
            PAUSE_DR:         tap_state_d = jtag_tms ? EXIT2_DR : PAUSE_DR;
            EXIT2_DR:         tap_state_d = jtag_tms ? UPDATE_DR : SHIFT_DR;
            UPDATE_DR:        tap_state_d = jtag_tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            SELECT_IR_SCAN:   tap_state_d = jtag_tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR:       tap_state_d = jtag_tms ? EXIT1_IR : SHIFT_IR;
            SHIFT_IR:         tap_state_d = jtag_tms ? EXIT1_IR : SHIFT_IR;
            EXIT1_IR:         tap_state_d = jtag_tms ? UPDATE_IR : PAUSE_IR;
            PAUSE_IR:         tap_state_d = jtag_tms ? EXIT2_IR : PAUSE_IR;
            EXIT2_IR:         tap_state_d = jtag_tms ? UPDATE_IR : SHIFT_IR;
            UPDATE_IR:        tap_state_d = jtag_tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            default:          tap_state_d = TEST_LOGIC_RESET;
        endcase
    end

    always_comb begin
        if (tap_state_q == SHIFT_IR)
            jtag_tdo = ir_shift_q[0];
        else if (tap_state_q == SHIFT_DR)
            jtag_tdo = dr_shift_q[0];
        else
            jtag_tdo = 1'b0;
    end

    always_ff @(posedge jtag_tck or posedge rst or negedge jtag_trst_n) begin
        if (rst || !jtag_trst_n) begin
            tap_state_q            <= TEST_LOGIC_RESET;
            ir_q                   <= IR_IDCODE;
            ir_shift_q             <= IR_IDCODE;
            dr_shift_q             <= 41'd0;
            req_toggle_tck         <= 1'b0;
            req_op_tck             <= 2'b00;
            req_addr_tck           <= 7'd0;
            req_data_tck           <= 32'd0;
            last_addr_tck          <= 7'd0;
            dmi_busy_sticky_tck    <= 1'b0;
            hard_reset_toggle_tck  <= 1'b0;
            ack_sync1_q            <= 1'b0;
            ack_sync2_q            <= 1'b0;
        end else begin
            tap_state_q <= tap_state_d;
            ack_sync1_q <= ack_toggle_sys_q;
            ack_sync2_q <= ack_sync1_q;

            if (tap_state_q == TEST_LOGIC_RESET)
                ir_q <= IR_IDCODE;

            case (tap_state_q)
                CAPTURE_IR:
                    ir_shift_q <= 5'b00001;
                SHIFT_IR:
                    ir_shift_q <= {jtag_tdi, ir_shift_q[4:1]};
                UPDATE_IR:
                    ir_q <= ir_shift_q;
                CAPTURE_DR: begin
                    case (ir_q)
                        IR_IDCODE:
                            // Version=1, part=ASL (0xA51), JEDEC field=0.
                            dr_shift_q <= {
                                9'd0, 4'h1, 16'h0A51, 11'd0, 1'b1
                            };
                        IR_DTMCS:
                            dr_shift_q <= {9'd0, dtmcs_value};
                        IR_DMI: begin
                            dr_shift_q <= {
                                last_addr_tck,
                                response_data_sys_q,
                                captured_dmi_status
                            };
                            if (request_outstanding)
                                dmi_busy_sticky_tck <= 1'b1;
                        end
                        default:
                            dr_shift_q <= 41'd0;
                    endcase
                end
                SHIFT_DR:
                    dr_shift_q <= {jtag_tdi, dr_shift_q[40:1]};
                UPDATE_DR: begin
                    if (ir_q == IR_DTMCS) begin
                        if (dr_shift_q[16])
                            dmi_busy_sticky_tck <= 1'b0;
                        if (dr_shift_q[17]) begin
                            dmi_busy_sticky_tck <= 1'b0;
                            hard_reset_toggle_tck <= ~hard_reset_toggle_tck;
                        end
                    end else if (ir_q == IR_DMI &&
                                 (dr_shift_q[1:0] != 2'b00)) begin
                        if (!request_outstanding &&
                            (dr_shift_q[1:0] != 2'b11) &&
                            !dmi_busy_sticky_tck) begin
                            req_op_tck     <= dr_shift_q[1:0];
                            req_data_tck   <= dr_shift_q[33:2];
                            req_addr_tck   <= dr_shift_q[40:34];
                            last_addr_tck  <= dr_shift_q[40:34];
                            req_toggle_tck <= ~req_toggle_tck;
                        end else begin
                            dmi_busy_sticky_tck <= 1'b1;
                        end
                    end
                end
                default: begin
                end
            endcase
        end
    end

    assign dmi_valid = req_active_q;
    assign dmi_write = req_op_sys_q == 2'b10;
    assign dmi_addr = req_addr_sys_q;
    assign dmi_wdata = req_data_sys_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            req_sync1_q          <= 1'b0;
            req_sync2_q          <= 1'b0;
            req_seen_q           <= 1'b0;
            req_active_q         <= 1'b0;
            req_op_sys_q         <= 2'b00;
            req_addr_sys_q       <= 7'd0;
            req_data_sys_q       <= 32'd0;
            ack_toggle_sys_q     <= 1'b0;
            response_data_sys_q  <= 32'd0;
            response_status_sys_q <= 2'b00;
            hard_reset_sync1_q   <= 1'b0;
            hard_reset_sync2_q   <= 1'b0;
            hard_reset_seen_q    <= 1'b0;
            dm_hard_reset        <= 1'b0;
        end else begin
            req_sync1_q <= req_toggle_tck;
            req_sync2_q <= req_sync1_q;
            hard_reset_sync1_q <= hard_reset_toggle_tck;
            hard_reset_sync2_q <= hard_reset_sync1_q;
            dm_hard_reset <= 1'b0;

            if (hard_reset_sync2_q != hard_reset_seen_q) begin
                hard_reset_seen_q <= hard_reset_sync2_q;
                dm_hard_reset <= 1'b1;
            end

            if (!req_active_q && (req_sync2_q != req_seen_q)) begin
                // Payload has been stable for two synchronizer cycles before
                // this bundled-data sample.
                req_seen_q     <= req_sync2_q;
                req_op_sys_q   <= req_op_tck;
                req_addr_sys_q <= req_addr_tck;
                req_data_sys_q <= req_data_tck;
                req_active_q   <= 1'b1;
            end else if (req_active_q && dmi_ready) begin
                response_data_sys_q   <= dmi_rdata;
                response_status_sys_q <= dmi_resp;
                ack_toggle_sys_q      <= req_seen_q;
                req_active_q          <= 1'b0;
            end
        end
    end
endmodule
