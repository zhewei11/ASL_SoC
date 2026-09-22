`include "rtos_core_config.svh"

// Fixed-profile real-time sequencer for one HX5-D20 hand controller.
//
// Software owns profile construction and trajectory scheduling. Hardware only
// repeats the two wire transactions required by the committed command frame:
// a broadcast Sync Write followed by one unicast Read. The legacy descriptor
// window remains accepted as a configuration ABI, but no descriptor SRAM,
// linked-list walker, period counters, budget multiplier or multi-device
// response scatter is synthesized in this block.
module protocol2_hx5_rt_sequencer #(
     parameter int unsigned COMMAND_BYTES           = `RTOS_CORE_PROTOCOL2_RT_COMMAND_BUFFER_BYTES
    ,parameter int unsigned FEEDBACK_BYTES          = `RTOS_CORE_PROTOCOL2_RT_FEEDBACK_BUFFER_BYTES
    ,parameter int unsigned WRITE_BODY_OFFSET       = 0
    ,parameter int unsigned WRITE_BODY_BYTES        = 86
    ,parameter int unsigned READ_BODY_OFFSET        = 88
    ,parameter int unsigned READ_BODY_BYTES         = 5
    ,parameter int unsigned FEEDBACK_PAYLOAD_OFFSET = 56
    ,parameter int unsigned FEEDBACK_PAYLOAD_BYTES  = 165
    ,parameter bit USE_EXTERNAL_FRAME_TICK          = 1'b0
) (
     input  logic        clk
    ,input  logic        rst

    ,input  logic        enable
    ,input  logic        single_step
    ,input  logic        abort_flush
    ,input  logic        frame_tick
    ,input  logic [31:0] frame_period_cycles
    ,input  logic [31:0] comm_deadline_cycles
    ,input  logic [31:0] command_deadline_cycles
    ,input  logic [7:0]  descriptor_count

    ,input  logic        command_commit
    ,input  logic        command_commit_bank
    ,input  logic [31:0] command_commit_sequence

    // Regions 0/1 are Command A/B, 2/3 are Feedback A/B and region 4 is the
    // compatibility profile window. Only descriptor words 10, 15 and 16 are
    // stored: Read control, response timeout and inter-byte timeout.
    ,input  logic        cpu_mem_valid
    ,input  logic        cpu_mem_write
    ,input  logic [2:0]  cpu_mem_region
    ,input  logic [11:0] cpu_mem_byte_addr
    ,input  logic [31:0] cpu_mem_wdata
    ,input  logic [3:0]  cpu_mem_wstrb
    ,output logic        cpu_mem_ready
    ,output logic [31:0] cpu_mem_rdata
    ,output logic        cpu_mem_write_blocked

    ,output logic        cmd_valid
    ,input  logic        cmd_ready
    ,output logic [7:0]  cmd_id
    ,output logic [15:0] cmd_body_len
    ,output logic [7:0]  cmd_expected_id
    ,output logic [7:0]  cmd_response_count
    ,output logic [31:0] response_timeout_cycles
    ,output logic [31:0] inter_byte_timeout_cycles
    ,output logic        body_valid
    ,input  logic        body_ready
    ,output logic [7:0]  body_data

    ,input  logic        result_valid
    ,output logic        result_ready
    ,input  logic [7:0]  result_index
    ,input  logic [7:0]  result_code
    ,input  logic [7:0]  response_id
    ,input  logic [7:0]  dynamixel_error
    ,input  logic [15:0] parameter_length
    ,input  logic        parameter_valid
    ,output logic        parameter_ready
    ,input  logic [7:0]  parameter_data
    ,input  logic        parameter_last
    ,input  logic        transaction_busy
    ,input  logic        transaction_done
    ,input  logic        transaction_error
    ,input  logic        uart_rx_overrun_error

    ,output logic        core_abort
    ,output logic        active
    ,output logic        frame_done
    ,output logic        frame_error
    ,output logic        frame_deadline
    ,output logic        buffer_error
    ,output logic        active_command_bank
    ,output logic        active_feedback_bank
    ,output logic        committed_command_bank
    ,output logic [31:0] frame_sequence
    ,output logic [31:0] frame_cycles
    ,output logic [31:0] last_frame_cycles
    ,output logic [31:0] minimum_slack_cycles
    ,output logic [31:0] expected_device_mask
    ,output logic [31:0] received_device_mask
    ,output logic [31:0] error_device_mask
    ,output logic [31:0] stale_device_mask
    ,output logic [31:0] commanded_device_mask
    ,output logic        schedule_valid
    ,output logic        schedule_overflow
    ,output logic        schedule_config_error
    ,output logic        late_command_commit
    ,output logic [31:0] schedule_budget_cycles
    ,output logic [1:0]  command_bank_locked
    ,output logic [63:0] timestamp
);

    localparam int unsigned COMMAND_WORDS  = COMMAND_BYTES  / 4;
    localparam int unsigned FEEDBACK_WORDS = FEEDBACK_BYTES / 4;

    localparam logic [7:0] BROADCAST_ID = 8'hFE;
    localparam logic [31:0] LOGICAL_HAND_MASK = 32'h0000_0001;

    localparam logic [31:0] STATUS_COMPLETE      = 32'h0000_0001;
    localparam logic [31:0] STATUS_ERROR         = 32'h0000_0002;
    localparam logic [31:0] STATUS_DEADLINE      = 32'h0000_0004;
    localparam logic [31:0] STATUS_STALE_COMMAND = 32'h0000_0008;
    localparam logic [31:0] STATUS_ABORTED       = 32'h0000_0020;
    localparam logic [31:0] STATUS_BUFFER_ERROR  = 32'h0000_0040;
    localparam logic [31:0] STATUS_RX_OVERRUN    = 32'h0000_0080;
    localparam logic [31:0] STATUS_UNEXPECTED_ID = 32'h0000_0100;

    localparam int unsigned PROFILE_CONTROL_BYTE_ADDR            = 10 * 4;
    localparam int unsigned PROFILE_RESPONSE_TIMEOUT_BYTE_ADDR   = 15 * 4;
    localparam int unsigned PROFILE_INTER_BYTE_TIMEOUT_BYTE_ADDR = 16 * 4;
    localparam int unsigned PROFILE_WINDOW_BYTES                 = 20 * 4;

    localparam bit BUFFER_GEOMETRY_VALID = (COMMAND_BYTES >= (READ_BODY_OFFSET + READ_BODY_BYTES)) &&
                   (FEEDBACK_BYTES >= (FEEDBACK_PAYLOAD_OFFSET + FEEDBACK_PAYLOAD_BYTES))          &&
                   ((COMMAND_BYTES % 4) == 0) && ((FEEDBACK_BYTES % 4) == 0);

    typedef enum logic [2:0] {
        RT_IDLE        = 3'd0,
        RT_WAIT_FRAME  = 3'd1,
        RT_START_CMD   = 3'd2,
        RT_BODY_READ   = 3'd3,
        RT_STREAM_BODY = 3'd4,
        RT_WAIT_TRANS  = 3'd5,
        RT_COMMIT      = 3'd6
    } rt_state_t;

    logic [31:0] command_mem [0:(2*COMMAND_WORDS)-1];
    logic [31:0] feedback_mem [0:(2*FEEDBACK_WORDS)-1];

    rt_state_t state;
    logic [31:0] profile_read_control;
    logic [31:0] profile_response_timeout;
    logic [31:0] profile_inter_byte_timeout;

    logic [31:0] frame_period_counter;
    logic [31:0] active_command_sequence;
    logic [31:0] committed_command_sequence;
    logic        command_commit_valid;
    logic        last_command_valid;
    logic [31:0] last_command_sequence;
    logic        command_deadline_missed;
    logic        single_step_pending;

    logic        working_feedback_bank;
    logic        transaction_select;
    logic [15:0] body_index;
    logic [31:0] body_word;
    logic [15:0] parameter_index;
    logic        parameter_drop;
    logic        parameter_complete;
    logic        result_seen;
    logic        response_error_pending;
    logic        frame_error_pending;
    logic        frame_deadline_pending;
    logic        abort_pending;
    logic        buffer_error_pending;
    logic        rx_overrun_pending;
    logic        unexpected_id_pending;

    logic [63:0] frame_start_timestamp;
    logic [63:0] frame_done_timestamp_latched;
    logic [31:0] frame_status_latched;
    logic [31:0] frame_cycles_latched;
    logic [31:0] frame_slack_latched;
    logic [31:0] frame_error_mask_latched;
    logic [31:0] frame_stale_mask_latched;
    logic [3:0]  metadata_word_index;
    logic [31:0] metadata_word;

    integer unsigned cpu_word_address;
    integer unsigned active_body_word_address;
    integer unsigned feedback_write_word_address;
    logic [31:0]     active_body_byte_address;
    logic [31:0]     feedback_write_byte_address;
    logic            cpu_address_valid;
    logic            cpu_port_available;
    logic            cpu_read_pending;
    logic            cpu_read_start;
    logic            cpu_write_accept;
    logic            frame_trigger;
    logic            deadline_expired;
    logic            commit_is_late;
    logic            result_handshake;
    logic            parameter_handshake;
    logic            response_valid_now;
    logic            response_complete_now;
    logic            profile_configuration_valid;
    logic [31:0]     profile_read_word;
    logic [31:0]     current_body_offset;
    logic [15:0]     current_body_length;
    logic [31:0]     slack_now;

    assign profile_configuration_valid = BUFFER_GEOMETRY_VALID
                                &&(descriptor_count == 8'd2)
                                && profile_read_control[0]
                                &&(profile_read_control[15:8] <= 8'd252)
                                &&(profile_read_control[23:16] == FEEDBACK_PAYLOAD_BYTES[7:0])
                                &&(profile_response_timeout != 32'd0)
                                &&(profile_inter_byte_timeout != 32'd0);

    assign schedule_valid         = profile_configuration_valid;
    assign schedule_overflow      = 1'b0;
    assign schedule_config_error  = (enable || single_step_pending || single_step) & !profile_configuration_valid;
    assign schedule_budget_cycles = 32'd0;

    assign active = (state != RT_IDLE) && (state != RT_WAIT_FRAME);
    assign active_feedback_bank = active_feedback_bank_reg;

    logic active_feedback_bank_reg;

    assign command_bank_locked = {
        ((active &&  active_command_bank) || (command_commit_valid &&  committed_command_bank)),
        ((active && !active_command_bank) || (command_commit_valid && !committed_command_bank))
    };

    assign current_body_offset = transaction_select ? READ_BODY_OFFSET      : WRITE_BODY_OFFSET;
    assign current_body_length = transaction_select ? READ_BODY_BYTES[15:0] : WRITE_BODY_BYTES[15:0];

    assign active_body_byte_address = current_body_offset + {16'd0, body_index};

    always_comb begin
        active_body_word_address = (active_command_bank ? COMMAND_WORDS : 0) + (active_body_byte_address >> 2);
    end

    assign cmd_valid                 = (state == RT_START_CMD);
    assign cmd_id                    = transaction_select ? profile_read_control[15:8] : BROADCAST_ID;
    assign cmd_body_len              = current_body_length;
    assign cmd_expected_id           = transaction_select ? profile_read_control[15:8] : BROADCAST_ID;
    assign cmd_response_count        = transaction_select ? 8'd1 : 8'd0;
    assign response_timeout_cycles   = transaction_select ? profile_response_timeout : 32'd0;
    assign inter_byte_timeout_cycles = transaction_select ? profile_inter_byte_timeout : 32'd0;
    assign body_valid                = (state == RT_STREAM_BODY) && (body_index < current_body_length);

    always_comb begin
        case (active_body_byte_address[1:0])
            2'd0:    body_data = body_word[7:0];
            2'd1:    body_data = body_word[15:8];
            2'd2:    body_data = body_word[23:16];
            default: body_data = body_word[31:24];
        endcase
    end

    assign result_ready = (state == RT_WAIT_TRANS) && transaction_select;
    assign parameter_ready = result_ready;
    assign result_handshake = result_valid && result_ready;
    assign parameter_handshake = parameter_valid && parameter_ready;

    assign response_valid_now = (result_index == 8'd0)
                              &&(result_code == 8'd0)
                              &&(response_id == profile_read_control[15:8])
                              &&(dynamixel_error == 8'd0)
                              &&(parameter_length == FEEDBACK_PAYLOAD_BYTES[15:0]);

    assign response_complete_now = parameter_complete || (parameter_handshake && parameter_last &&
                                  (parameter_index + 16'd1 == FEEDBACK_PAYLOAD_BYTES[15:0]));

    assign feedback_write_byte_address = FEEDBACK_PAYLOAD_OFFSET + {16'd0, parameter_index};

    always_comb begin
        feedback_write_word_address = (working_feedback_bank ? FEEDBACK_WORDS : 0) + (feedback_write_byte_address >> 2);
    end

    assign frame_trigger = single_step_pending ||
        (enable && (USE_EXTERNAL_FRAME_TICK ? frame_tick :
        ((frame_period_cycles != 32'd0) && (frame_period_counter >= frame_period_cycles - 32'd1))));

    assign deadline_expired = active && !frame_deadline_pending &&
        (comm_deadline_cycles != 32'd0) &&
        (frame_cycles >= comm_deadline_cycles - 32'd1) &&
        !((state == RT_WAIT_TRANS) && transaction_done) &&
        (state != RT_COMMIT);

    assign commit_is_late = enable && (command_deadline_cycles != 32'd0) && (frame_period_counter >= command_deadline_cycles);

    assign slack_now = (comm_deadline_cycles != 32'd0) && (frame_cycles < comm_deadline_cycles) ?
                        comm_deadline_cycles - frame_cycles : 32'd0;

    always_comb begin
        cpu_word_address = 0;
        cpu_address_valid = (cpu_mem_byte_addr[1:0] == 2'd0);

        case (cpu_mem_region)
            3'd0, 3'd1: begin
                cpu_word_address  = (cpu_mem_region[0] ? COMMAND_WORDS : 0) + ({20'd0, cpu_mem_byte_addr} >> 2);
                cpu_address_valid = cpu_address_valid && ({20'd0, cpu_mem_byte_addr} < COMMAND_BYTES);
            end
            3'd2, 3'd3: begin
                cpu_word_address  = (cpu_mem_region[0] ? FEEDBACK_WORDS : 0) + ({20'd0, cpu_mem_byte_addr} >> 2);
                cpu_address_valid = cpu_address_valid && ({20'd0, cpu_mem_byte_addr} < FEEDBACK_BYTES);
            end
            3'd4: begin
                cpu_address_valid = cpu_address_valid && ({20'd0, cpu_mem_byte_addr} < PROFILE_WINDOW_BYTES);
            end
            default: cpu_address_valid = 1'b0;
        endcase

        case (cpu_mem_region)
            3'd0, 3'd1: cpu_port_available = (state != RT_BODY_READ);
            3'd2, 3'd3: cpu_port_available = !(parameter_handshake || (state == RT_COMMIT));
            default: cpu_port_available = 1'b1;
        endcase
    end

    always_comb begin
        case (cpu_mem_byte_addr)
            PROFILE_CONTROL_BYTE_ADDR[11:0]            :profile_read_word = profile_read_control;
            PROFILE_RESPONSE_TIMEOUT_BYTE_ADDR[11:0]   :profile_read_word = profile_response_timeout;
            PROFILE_INTER_BYTE_TIMEOUT_BYTE_ADDR[11:0] :profile_read_word = profile_inter_byte_timeout;
            default: profile_read_word = 32'd0;
        endcase
    end

    assign cpu_mem_ready    = cpu_mem_write ? cpu_port_available : cpu_read_pending;
    assign cpu_read_start   = cpu_mem_valid && !cpu_mem_write && !cpu_read_pending && cpu_port_available;
    assign cpu_write_accept = cpu_mem_valid && cpu_mem_write && cpu_mem_ready;

    always_comb begin
        case (metadata_word_index)
            4'd0:  metadata_word = frame_sequence;
            4'd1:  metadata_word = active_command_sequence;
            4'd2:  metadata_word = frame_start_timestamp[31:0];
            4'd3:  metadata_word = frame_start_timestamp[63:32];
            4'd4:  metadata_word = frame_done_timestamp_latched[31:0];
            4'd5:  metadata_word = frame_done_timestamp_latched[63:32];
            4'd6:  metadata_word = expected_device_mask;
            4'd7:  metadata_word = received_device_mask;
            4'd8:  metadata_word = frame_error_mask_latched;
            4'd9:  metadata_word = frame_stale_mask_latched;
            4'd10: metadata_word = frame_status_latched;
            4'd11: metadata_word = frame_cycles_latched;
            4'd12: metadata_word = frame_slack_latched;
            4'd13: metadata_word = frame_sequence;
            default: metadata_word = 32'd0;
        endcase
    end

    integer lane;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state                         <= RT_IDLE;
            profile_read_control          <= 32'd0;
            profile_response_timeout      <= 32'd0;
            profile_inter_byte_timeout    <= 32'd0;
            frame_period_counter          <= 32'd0;
            active_command_sequence       <= 32'd0;
            committed_command_sequence    <= 32'd0;
            command_commit_valid          <= 1'b0;
            last_command_valid            <= 1'b0;
            last_command_sequence         <= 32'd0;
            command_deadline_missed       <= 1'b0;
            single_step_pending           <= 1'b0;
            active_command_bank           <= 1'b0;
            committed_command_bank        <= 1'b0;
            active_feedback_bank_reg      <= 1'b0;
            working_feedback_bank         <= 1'b1;
            transaction_select            <= 1'b0;
            body_index                    <= 16'd0;
            body_word                     <= 32'd0;
            parameter_index               <= 16'd0;
            parameter_drop                <= 1'b0;
            parameter_complete            <= 1'b0;
            result_seen                   <= 1'b0;
            response_error_pending        <= 1'b0;
            frame_error_pending           <= 1'b0;
            frame_deadline_pending        <= 1'b0;
            abort_pending                 <= 1'b0;
            buffer_error_pending          <= 1'b0;
            rx_overrun_pending            <= 1'b0;
            unexpected_id_pending         <= 1'b0;
            frame_sequence                <= 32'd0;
            frame_cycles                  <= 32'd0;
            frame_cycles_latched          <= 32'd0;
            last_frame_cycles             <= 32'd0;
            minimum_slack_cycles          <= 32'hFFFF_FFFF;
            frame_start_timestamp         <= 64'd0;
            frame_done_timestamp_latched  <= 64'd0;
            frame_status_latched          <= 32'd0;
            frame_slack_latched           <= 32'd0;
            frame_error_mask_latched      <= 32'd0;
            frame_stale_mask_latched      <= 32'd0;
            metadata_word_index           <= 4'd0;
            expected_device_mask          <= 32'd0;
            received_device_mask          <= 32'd0;
            error_device_mask             <= 32'd0;
            stale_device_mask             <= 32'd0;
            commanded_device_mask         <= 32'd0;
            late_command_commit           <= 1'b0;
            timestamp                     <= 64'd0;
            cpu_read_pending              <= 1'b0;
            cpu_mem_rdata                 <= 32'd0;
            cpu_mem_write_blocked         <= 1'b0;
            core_abort                    <= 1'b0;
            frame_done                    <= 1'b0;
            frame_error                   <= 1'b0;
            frame_deadline                <= 1'b0;
            buffer_error                  <= 1'b0;
        end else begin
            timestamp             <= timestamp + 64'd1;
            core_abort            <= 1'b0;
            frame_done            <= 1'b0;
            frame_error           <= 1'b0;
            frame_deadline        <= 1'b0;
            buffer_error          <= 1'b0;
            cpu_mem_write_blocked <= 1'b0;

            if (cpu_read_pending && cpu_mem_valid && cpu_mem_ready) begin
                cpu_read_pending <= 1'b0;
            end

            if (cpu_read_start) begin
                cpu_read_pending  <= 1'b1;
                if (!cpu_address_valid) begin
                    cpu_mem_rdata <= 32'd0;
                end else begin
                    case (cpu_mem_region)
                        3'd0, 3'd1:
                            cpu_mem_rdata <= command_mem[cpu_word_address];
                        3'd2, 3'd3:
                            cpu_mem_rdata <= feedback_mem[cpu_word_address];
                        3'd4:
                            cpu_mem_rdata <= profile_read_word;
                        default:
                            cpu_mem_rdata <= 32'd0;
                    endcase
                end
            end

            if (!enable) begin
                frame_period_counter <= 32'd0;
            end else if (frame_trigger) begin
                frame_period_counter <= 32'd0;
            end else begin
                frame_period_counter <= frame_period_counter + 32'd1;
            end

            if (single_step) begin
                single_step_pending <= 1'b1;
            end

            if (command_commit) begin
                if ((active && (command_commit_bank == active_command_bank)) || (command_commit_valid && (command_commit_bank == committed_command_bank))) begin
                    buffer_error            <= 1'b1;
                    buffer_error_pending    <= 1'b1;
                end else if (commit_is_late) begin
                    command_deadline_missed <= 1'b1;
                    late_command_commit     <= 1'b1;
                end else begin
                    committed_command_bank     <= command_commit_bank;
                    committed_command_sequence <= command_commit_sequence;
                    command_commit_valid       <= 1'b1;
                    command_deadline_missed    <= 1'b0;
                    late_command_commit        <= 1'b0;
                end
            end

            if (enable && (command_deadline_cycles != 32'd0) && (frame_period_counter >= command_deadline_cycles) &&
                (!command_commit_valid ||(last_command_valid && (committed_command_sequence == last_command_sequence)))) begin
                command_deadline_missed <= 1'b1;
            end

            if (cpu_write_accept) begin
                if (!cpu_address_valid) begin
                    cpu_mem_write_blocked <= 1'b1;
                    buffer_error          <= 1'b1;
                    buffer_error_pending  <= 1'b1;

                end else if ((cpu_mem_region <= 3'd1) && command_bank_locked[cpu_mem_region[0]]) begin
                    cpu_mem_write_blocked   <= 1'b1;
                    buffer_error            <= 1'b1;
                    buffer_error_pending    <= 1'b1;

                end else if (cpu_mem_region <= 3'd1) begin
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        if (cpu_mem_wstrb[lane]) begin
                            command_mem[cpu_word_address][lane*8 +: 8] <= cpu_mem_wdata[lane*8 +: 8];
                        end
                    end
                end else if ((cpu_mem_region == 3'd4) && !enable && !active) begin
                    case (cpu_mem_byte_addr)
                        PROFILE_CONTROL_BYTE_ADDR[11:0]: begin
                            for (lane = 0; lane < 4; lane = lane + 1) begin
                                if (cpu_mem_wstrb[lane]) begin
                                    profile_read_control[lane*8 +: 8] <= cpu_mem_wdata[lane*8 +: 8];
                                end
                            end
                        end
                        PROFILE_RESPONSE_TIMEOUT_BYTE_ADDR[11:0]: begin
                            for (lane = 0; lane < 4; lane = lane + 1) begin
                                if (cpu_mem_wstrb[lane]) begin
                                    profile_response_timeout[lane*8 +: 8] <= cpu_mem_wdata[lane*8 +: 8];
                                end
                            end
                        end
                        PROFILE_INTER_BYTE_TIMEOUT_BYTE_ADDR[11:0]: begin
                            for (lane = 0; lane < 4; lane = lane + 1) begin
                                if (cpu_mem_wstrb[lane]) begin
                                    profile_inter_byte_timeout[lane*8 +: 8] <= cpu_mem_wdata[lane*8 +: 8];
                                end
                            end
                        end
                        default: begin
                        end
                    endcase
                end else begin
                    cpu_mem_write_blocked <= 1'b1;
                    buffer_error          <= 1'b1;
                    buffer_error_pending  <= 1'b1;
                end
            end

            if (abort_flush) begin
                command_commit_valid <= 1'b0;
                last_command_valid   <= 1'b0;
            end

            if (active) begin
                frame_cycles               <= frame_cycles + 32'd1;
                if (uart_rx_overrun_error) begin
                    rx_overrun_pending       <= 1'b1;
                    frame_error_pending      <= 1'b1;
                    response_error_pending   <= 1'b1;
                end
            end

            if (deadline_expired) begin
                frame_deadline_pending       <= 1'b1;
                frame_error_pending          <= 1'b1;
                abort_pending                <= 1'b1;
                core_abort                   <= 1'b1;
                frame_done_timestamp_latched <= timestamp;
                frame_cycles_latched         <= frame_cycles + 32'd1;
                frame_slack_latched          <= 32'd0;
                frame_error_mask_latched     <= LOGICAL_HAND_MASK;
                frame_stale_mask_latched     <= command_deadline_missed ? LOGICAL_HAND_MASK : 32'd0;
                frame_status_latched         <= STATUS_COMPLETE | STATUS_ERROR | STATUS_DEADLINE | STATUS_ABORTED;
                metadata_word_index          <= 4'd0;
                state                        <= RT_COMMIT;

            end else if (abort_flush && active) begin
                abort_pending                <= 1'b1;
                frame_error_pending          <= 1'b1;
                core_abort                   <= 1'b1;
                frame_done_timestamp_latched <= timestamp;
                frame_cycles_latched         <= frame_cycles;
                frame_slack_latched          <= slack_now;
                frame_error_mask_latched     <= result_seen ? error_device_mask : LOGICAL_HAND_MASK;
                frame_stale_mask_latched     <= command_deadline_missed ? LOGICAL_HAND_MASK : 32'd0;
                frame_status_latched         <= STATUS_COMPLETE | STATUS_ERROR | STATUS_ABORTED;
                metadata_word_index          <= 4'd0;
                state                        <= RT_COMMIT;

            end else begin
                case (state)
                    RT_IDLE: begin
                        frame_cycles <= 32'd0;
                        if ((enable || single_step_pending) && profile_configuration_valid) begin
                            state <= RT_WAIT_FRAME;
                        end
                    end

                    RT_WAIT_FRAME: begin
                        frame_cycles <= 32'd0;
                        if (!enable && !single_step_pending) begin
                            state <= RT_IDLE;
                        end else if (frame_trigger) begin
                            single_step_pending     <= 1'b0;
                            frame_sequence          <= frame_sequence + 32'd1;
                            frame_start_timestamp   <= timestamp;
                            active_command_bank     <= committed_command_bank;
                            active_command_sequence <= committed_command_sequence;
                            working_feedback_bank   <= ~active_feedback_bank_reg;
                            expected_device_mask    <= LOGICAL_HAND_MASK;
                            received_device_mask    <= 32'd0;
                            error_device_mask       <= 32'd0;
                            stale_device_mask       <= 32'd0;
                            commanded_device_mask   <= LOGICAL_HAND_MASK;
                            frame_error_pending     <= 1'b0;
                            frame_deadline_pending  <= 1'b0;
                            abort_pending           <= 1'b0;
                            buffer_error_pending    <= 1'b0;
                            rx_overrun_pending      <= 1'b0;
                            unexpected_id_pending   <= 1'b0;
                            response_error_pending  <= 1'b0;
                            result_seen             <= 1'b0;
                            parameter_complete      <= 1'b0;
                            parameter_drop          <= 1'b0;
                            parameter_index         <= 16'd0;
                            frame_cycles            <= 32'd1;

                            if (!command_commit_valid || command_deadline_missed || late_command_commit ||
                                (last_command_valid   && (committed_command_sequence == last_command_sequence))) begin
                                last_command_valid           <= command_commit_valid;
                                last_command_sequence        <= committed_command_sequence;
                                command_deadline_missed      <= 1'b0;
                                frame_done_timestamp_latched <= timestamp;
                                frame_cycles_latched         <= 32'd1;
                                frame_slack_latched          <= (comm_deadline_cycles > 32'd1) ? comm_deadline_cycles - 32'd1 : 32'd0;
                                frame_error_mask_latched     <= 32'd0;
                                frame_stale_mask_latched     <= LOGICAL_HAND_MASK;
                                frame_status_latched         <= STATUS_COMPLETE | STATUS_ERROR | STATUS_STALE_COMMAND;
                                metadata_word_index          <= 4'd0;
                                state                        <= RT_COMMIT;
                            end else begin
                                last_command_valid      <= 1'b1;
                                last_command_sequence   <= committed_command_sequence;
                                command_deadline_missed <= 1'b0;
                                transaction_select      <= 1'b0;
                                body_index              <= 16'd0;
                                state                   <= RT_START_CMD;
                            end
                        end
                    end

                    RT_START_CMD: begin
                        if (cmd_valid && cmd_ready) begin
                            body_index <= 16'd0;
                            state      <= RT_BODY_READ;
                        end
                    end

                    RT_BODY_READ: begin
                        if (active_body_word_address < (2 * COMMAND_WORDS)) begin
                            body_word <= command_mem[active_body_word_address];
                            state     <= RT_STREAM_BODY;
                        end else begin
                            frame_error_pending  <= 1'b1;
                            buffer_error_pending <= 1'b1;
                            buffer_error         <= 1'b1;
                            core_abort           <= 1'b1;
                            state                <= RT_WAIT_TRANS;
                        end
                    end

                    RT_STREAM_BODY: begin
                        if (body_valid && body_ready) begin
                            body_index <= body_index + 16'd1;
                            if (body_index + 16'd1 >= current_body_length) begin
                                state  <= RT_WAIT_TRANS;
                            end else if (active_body_byte_address[1:0] == 2'd3) begin
                                state  <= RT_BODY_READ;
                            end
                        end
                    end

                    RT_WAIT_TRANS: begin
                        if (result_handshake) begin
                            result_seen        <= 1'b1;
                            parameter_index    <= 16'd0;
                            parameter_complete <= 1'b0;
                            parameter_drop     <= !response_valid_now;

                            if (response_valid_now) begin
                                received_device_mask      <= LOGICAL_HAND_MASK;
                            end else begin
                                error_device_mask         <= LOGICAL_HAND_MASK;
                                frame_error_pending       <= 1'b1;
                                response_error_pending    <= 1'b1;
                                if (response_id != profile_read_control[15:8]) begin
                                    unexpected_id_pending <= 1'b1;
                                end
                            end
                        end

                        if (parameter_handshake) begin
                            if (!parameter_drop && (!result_handshake || response_valid_now) &&
                                (parameter_index < FEEDBACK_PAYLOAD_BYTES[15:0])) begin
                                case (feedback_write_byte_address[1:0])
                                    2'd0: feedback_mem[feedback_write_word_address][7:0]      <= parameter_data;
                                    2'd1: feedback_mem[feedback_write_word_address][15:8]     <= parameter_data;
                                    2'd2: feedback_mem[feedback_write_word_address][23:16]    <= parameter_data;
                                    2'd3: feedback_mem[feedback_write_word_address][31:24]    <= parameter_data;
                                    default: feedback_mem[feedback_write_word_address][31:24] <= parameter_data;
                                endcase
                            end else begin
                                frame_error_pending    <= 1'b1;
                                response_error_pending <= 1'b1;
                            end

                            parameter_index <= parameter_index + 16'd1;

                            if (parameter_last) begin
                                parameter_complete <= (parameter_index + 16'd1 == FEEDBACK_PAYLOAD_BYTES[15:0]);

                                if (parameter_index + 16'd1 != FEEDBACK_PAYLOAD_BYTES[15:0]) begin
                                    error_device_mask      <= LOGICAL_HAND_MASK;
                                    frame_error_pending    <= 1'b1;
                                    response_error_pending <= 1'b1;
                                end
                            end
                        end

                        if (transaction_done) begin
                            if (!transaction_select && !transaction_error && !buffer_error_pending && !uart_rx_overrun_error) begin
                                transaction_select <= 1'b1;
                                body_index         <= 16'd0;
                                result_seen        <= 1'b0;
                                parameter_complete <= 1'b0;
                                parameter_drop     <= 1'b0;
                                parameter_index    <= 16'd0;
                                state              <= RT_START_CMD;

                            end else begin
                                frame_done_timestamp_latched <= timestamp;
                                frame_cycles_latched         <= frame_cycles;
                                frame_slack_latched          <= slack_now;
                                frame_stale_mask_latched     <= 32'd0;
                                metadata_word_index          <= 4'd0;

                                if (!transaction_select
                                    || transaction_error
                                    || uart_rx_overrun_error
                                    || response_error_pending
                                    ||  (result_handshake && !response_valid_now)
                                    || !(result_seen || result_handshake)
                                    || !response_complete_now)
                                begin
                                    frame_error_mask_latched <= LOGICAL_HAND_MASK;
                                    frame_status_latched     <= STATUS_COMPLETE | STATUS_ERROR |
                                    (uart_rx_overrun_error ? STATUS_RX_OVERRUN : 32'd0) |
                                    ((unexpected_id_pending || (result_handshake && (response_id != profile_read_control[15:8]))) ? STATUS_UNEXPECTED_ID : 32'd0) |
                                    ((!transaction_select   || transaction_error) ? STATUS_ABORTED : 32'd0) |
                                    (buffer_error_pending ? STATUS_BUFFER_ERROR : 32'd0);

                                end else begin
                                    frame_error_mask_latched <= 32'd0;
                                    frame_status_latched     <= STATUS_COMPLETE;
                                end

                                state <= RT_COMMIT;
                            end
                        end
                    end

                    RT_COMMIT: begin
                        feedback_mem[ (working_feedback_bank ? FEEDBACK_WORDS : 0) +{28'd0, metadata_word_index}] <= metadata_word;

                        if (metadata_word_index == 4'd13) begin
                            active_feedback_bank_reg <= working_feedback_bank;
                            error_device_mask        <= frame_error_mask_latched;
                            stale_device_mask        <= frame_stale_mask_latched;
                            last_frame_cycles        <= frame_cycles_latched;
                            frame_done               <= 1'b1;
                            frame_error              <= frame_status_latched[1];
                            frame_deadline           <= frame_status_latched[2];

                            if ((comm_deadline_cycles != 32'd0) && (frame_slack_latched < minimum_slack_cycles)) begin
                                minimum_slack_cycles <= frame_slack_latched;
                            end

                            state <= enable ? RT_WAIT_FRAME : RT_IDLE;
                        end else begin
                            metadata_word_index <= metadata_word_index + 4'd1;
                        end
                    end

                    default: begin
                        core_abort <= 1'b1;
                        state      <= RT_IDLE;
                    end
                endcase
            end
        end
    end

// Unused signals to avoid synthesis warnings
    logic unused_transaction_busy;
    logic unused_frame_flags;
    assign unused_transaction_busy = transaction_busy;
    assign unused_frame_flags = frame_error_pending | frame_deadline_pending |  abort_pending | rx_overrun_pending;

endmodule
