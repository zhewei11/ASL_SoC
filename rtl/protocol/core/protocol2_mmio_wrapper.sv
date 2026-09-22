`include "rtos_core_config.svh"

module protocol2_mmio_wrapper #(
     parameter int unsigned CLOCK_HZ                = `RTOS_CORE_CPU_CLOCK_HZ
    ,parameter int unsigned BAUD_RATE               = `RTOS_CORE_PROTOCOL2_BAUD_RATE
    ,parameter int unsigned RX_OVERSAMPLE           = `RTOS_CORE_PROTOCOL2_RX_OVERSAMPLE
    ,parameter int unsigned DE_SETUP_CYCLES         = `RTOS_CORE_PROTOCOL2_DE_SETUP_CYCLES
    ,parameter int unsigned POST_TX_GUARD_CYCLES    = `RTOS_CORE_PROTOCOL2_POST_TX_GUARD_CYCLES
    ,parameter int unsigned MAX_BODY_BYTES          = `RTOS_CORE_PROTOCOL2_MAX_BODY_BYTES
    ,parameter int unsigned MAX_STUFFED_BODY_BYTES  = `RTOS_CORE_PROTOCOL2_MAX_STUFFED_BODY_BYTES
    ,parameter int unsigned MAX_PARAMETER_BYTES     = `RTOS_CORE_PROTOCOL2_MAX_PARAMETER_BYTES
    ,parameter int unsigned RT_COMMAND_BYTES        = `RTOS_CORE_PROTOCOL2_RT_COMMAND_BUFFER_BYTES
    ,parameter int unsigned RT_FEEDBACK_BYTES       = `RTOS_CORE_PROTOCOL2_RT_FEEDBACK_BUFFER_BYTES
    ,parameter int unsigned RT_DESCRIPTOR_WORDS     = `RTOS_CORE_PROTOCOL2_RT_DESCRIPTOR_WORDS
    ,parameter bit USE_EXTERNAL_FRAME_TICK          = 1'b0
    ,parameter bit USE_HX5_RT_SEQUENCER             = 1'b1
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        frame_tick
    ,input  logic        external_abort

    // CPU-clock-domain local MMIO interface. Address is a byte address.
    ,input  logic        mmio_valid
    ,output logic        mmio_ready
    ,input  logic        mmio_write
    ,input  logic [31:0] mmio_addr
    ,input  logic [31:0] mmio_wdata
    ,input  logic [3:0]  mmio_wstrb
    ,output logic [31:0] mmio_rdata

    ,output logic        irq
    ,output logic        rs485_tx
    ,input  logic        rs485_rx
    ,output logic        rs485_de
);
    // Register offsets for the MMIO interface.
    localparam logic [7:0] REG_CONTROL            = 8'h00;
    localparam logic [7:0] REG_STATUS             = 8'h04;
    localparam logic [7:0] REG_CMD_CONFIG         = 8'h08;
    localparam logic [7:0] REG_BODY_LENGTH        = 8'h0C;
    localparam logic [7:0] REG_RESPONSE_TIMEOUT   = 8'h10;
    localparam logic [7:0] REG_INTER_BYTE_TIMEOUT = 8'h14;
    localparam logic [7:0] REG_TX_DATA            = 8'h18;
    localparam logic [7:0] REG_RX_META            = 8'h1C;
    localparam logic [7:0] REG_RX_LENGTH          = 8'h20;
    localparam logic [7:0] REG_RX_DATA            = 8'h24;
    localparam logic [7:0] REG_IRQ_STATUS         = 8'h28;
    localparam logic [7:0] REG_IRQ_ENABLE         = 8'h2C;
    localparam logic [7:0] REG_ID                 = 8'h30;
    localparam logic [7:0] REG_TX_COUNT           = 8'h34;
    localparam logic [7:0] REG_RT_CONTROL         = 8'h40;
    localparam logic [7:0] REG_RT_STATUS          = 8'h44;
    localparam logic [7:0] REG_FRAME_PERIOD       = 8'h48;
    localparam logic [7:0] REG_COMM_DEADLINE      = 8'h4C;
    localparam logic [7:0] REG_COMMAND_DEADLINE   = 8'h50;
    localparam logic [7:0] REG_COMMAND_A_BASE     = 8'h54;
    localparam logic [7:0] REG_COMMAND_B_BASE     = 8'h58;
    localparam logic [7:0] REG_FEEDBACK_A_BASE    = 8'h5C;
    localparam logic [7:0] REG_FEEDBACK_B_BASE    = 8'h60;
    localparam logic [7:0] REG_DESCRIPTOR_BASE    = 8'h64;
    localparam logic [7:0] REG_EXPECTED_ID_MASK   = 8'h68;
    localparam logic [7:0] REG_RECEIVED_ID_MASK   = 8'h6C;
    localparam logic [7:0] REG_ERROR_ID_MASK      = 8'h70;
    localparam logic [7:0] REG_FRAME_SEQUENCE     = 8'h74;
    localparam logic [7:0] REG_FRAME_CYCLES       = 8'h78;
    localparam logic [7:0] REG_MIN_SLACK          = 8'h7C;
    localparam logic [7:0] REG_RT_IRQ_STATUS      = 8'h80;
    localparam logic [7:0] REG_RT_IRQ_ENABLE      = 8'h84;
    localparam logic [7:0] REG_ABORT_FLUSH        = 8'h88;
    localparam logic [7:0] REG_ERROR_COUNT        = 8'h8C;
    localparam logic [7:0] REG_PROTOCOL_OWNER     = 8'h90;
    localparam logic [7:0] REG_BAUD_REQUEST       = 8'h94;
    localparam logic [7:0] REG_BAUD_STATUS        = 8'h98;
    localparam logic [7:0] REG_TEST_CONTROL       = 8'h9C;
    localparam logic [7:0] REG_TEST_STATUS        = 8'hA8;
    localparam logic [7:0] REG_TEST_TX_COUNT      = 8'hAC;
    localparam logic [7:0] REG_TEST_RX_COUNT      = 8'hB0;
    localparam logic [7:0] REG_TEST_ERROR_COUNT   = 8'hB4;
    localparam logic [7:0] REG_RT_MEM_ADDR        = 8'hB8;
    localparam logic [7:0] REG_RT_MEM_DATA        = 8'hBC;
    localparam logic [7:0] REG_COMMAND_COMMIT     = 8'hC0;
    localparam logic [7:0] REG_DESCRIPTOR_COUNT   = 8'hC4;
    localparam logic [7:0] REG_COMMAND_SEQUENCE   = 8'hC8;
    localparam logic [7:0] REG_STALE_ID_MASK      = 8'hCC;
    localparam logic [7:0] REG_SCHEDULE_STATUS    = 8'hD0;
    localparam logic [7:0] REG_SCHEDULE_BUDGET    = 8'hD4;
    localparam logic [7:0] REG_COMMANDED_ID_MASK  = 8'hD8;

    localparam logic [1:0] OWNER_RT     = 2'd0;
    localparam logic [1:0] OWNER_DIRECT = 2'd1;
    localparam logic [1:0] OWNER_RAW    = 2'd2;
    localparam logic [1:0] DEFAULT_BAUD_SELECT = (BAUD_RATE == 4_500_000) ? 2'd1 : (BAUD_RATE == 6_000_000) ? 2'd2 : 2'd0;

    // descriptor == 10 words
    localparam int unsigned MAX_DESCRIPTOR_COUNT = RT_DESCRIPTOR_WORDS / 10;

    localparam logic [3:0] IRQ_DONE    = 4'b0001;
    localparam logic [3:0] IRQ_ERROR   = 4'b0010;
    localparam logic [3:0] IRQ_RESULT  = 4'b0100;
    localparam logic [3:0] IRQ_OVERRUN = 4'b1000;

    logic [7:0]  cmd_id_reg;
    logic [7:0]  expected_id_reg;
    logic [7:0]  response_count_reg;
    logic [15:0] body_length_reg;
    logic [31:0] response_timeout_reg;
    logic [31:0] inter_byte_timeout_reg;
    logic [15:0] tx_count_reg;

    logic        cmd_pending;
    logic        result_pending;
    logic [7:0]  result_index_reg;
    logic [7:0]  result_code_reg;
    logic [7:0]  response_id_reg;
    logic [7:0]  dynamixel_error_reg;
    logic [15:0] parameter_length_reg;
    logic [3:0]  irq_status_reg;
    logic [3:0]  irq_enable_reg;

    logic        rt_enable_reg;
    logic [31:0] frame_period_reg;
    logic [31:0] comm_deadline_reg;
    logic [31:0] command_deadline_reg;
    logic [7:0]  descriptor_count_reg;
    logic [31:0] command_sequence_reg;
    logic [31:0] rt_mem_addr_reg;
    logic [3:0]  rt_irq_status_reg;
    logic [3:0]  rt_irq_enable_reg;
    logic [1:0]  owner_reg;
    logic [1:0]  baud_request_reg;
    logic [1:0]  baud_active_reg;
    logic        baud_applied_reg;
    logic        owner_error_reg;
    logic [31:0] error_count_reg;

    logic        rt_single_step;
    logic        abort_flush_pulse;
    logic        abort_request;
    logic        command_commit_pulse;
    logic        rt_mem_access;
    logic        rt_mem_write;
    logic        rt_mem_ready;
    logic [31:0] rt_mem_rdata;
    logic        rt_mem_write_blocked;
    logic        rt_cmd_valid;
    logic        rt_cmd_ready;
    logic [7:0]  rt_cmd_id;
    logic [15:0] rt_cmd_body_len;
    logic [7:0]  rt_cmd_expected_id;
    logic [7:0]  rt_cmd_response_count;
    logic [31:0] rt_response_timeout;
    logic [31:0] rt_inter_byte_timeout;
    logic        rt_body_valid;
    logic        rt_body_ready;
    logic [7:0]  rt_body_data;
    logic        rt_result_ready;
    logic        rt_parameter_ready;
    logic        rt_core_abort;
    logic        rt_active;
    logic        rt_frame_done;
    logic        rt_frame_error;
    logic        rt_frame_deadline;
    logic        rt_buffer_error;
    logic        rt_active_command_bank;
    logic        rt_active_feedback_bank;
    logic        rt_committed_command_bank;
    logic [31:0] rt_frame_sequence;
    logic [31:0] rt_last_frame_cycles;
    logic [31:0] rt_minimum_slack;
    logic [31:0] rt_expected_mask;
    logic [31:0] rt_received_mask;
    logic [31:0] rt_error_mask;
    logic [31:0] rt_stale_mask;
    logic [31:0] rt_commanded_mask;
    logic        rt_schedule_valid;
    logic        rt_schedule_overflow;
    logic        rt_schedule_config_error;
    logic        rt_late_command_commit;
    logic [31:0] rt_schedule_budget;
    logic [1:0]  rt_command_bank_locked;
    logic [31:0] active_wire_byte_cycles;

    logic        core_cmd_valid;
    logic        core_cmd_ready;
    logic [7:0]  core_cmd_id;
    logic [15:0] core_cmd_body_len;
    logic [7:0]  core_cmd_expected_id;
    logic [7:0]  core_cmd_response_count;
    logic [31:0] core_response_timeout;
    logic [31:0] core_inter_byte_timeout;
    logic        core_body_valid;
    logic        core_body_ready;
    logic [7:0]  core_body_data;
    logic        core_result_ready;
    logic        core_parameter_ready;
    logic [31:0] active_baud_rate;
    logic        core_flush;

    logic        cmd_ready;
    logic        body_ready;
    logic        result_valid;
    logic [7:0]  result_index;
    logic [7:0]  result_code;
    logic [7:0]  response_id;
    logic [7:0]  dynamixel_error;
    logic [15:0] parameter_length;
    logic        parameter_valid;
    logic [7:0]  parameter_data;
    logic        parameter_last;
    logic        transaction_busy;
    logic        transaction_done;
    logic        transaction_error;
    logic        uart_rx_overrun_error;

    logic [31:0] status_word;
    logic [31:0] cmd_config_word;
    logic [31:0] rx_meta_word;
    logic [31:0] irq_clear_word;
    logic [31:0] cmd_config_write_word;
    logic [31:0] body_length_write_word;
    logic [31:0] irq_enable_write_word;
    logic [31:0] rt_irq_enable_write_word;
    logic [31:0] owner_write_word;
    logic [31:0] baud_request_write_word;
    logic [31:0] descriptor_count_write_word;
    logic [3:0]  irq_event;
    logic [7:0]  register_offset;

    logic        control_access;
    logic        control_start_request;
    logic        control_result_ack;
    logic        config_write_request;
    logic        tx_data_write_request;
    logic        rx_meta_read_request;
    logic        rx_data_read_request;
    logic        mmio_handshake;
    logic        command_handshake;
    logic        body_handshake;
    logic        result_handshake;
    logic        result_ack_handshake;
    logic        owner_write_request;
    logic        baud_write_request;
    logic [3:0]  rt_irq_event;
    logic [31:0] rt_status_word;
    logic [31:0] baud_status_word;
    logic        configuration_error_event;

    function automatic logic [31:0] baud_from_select(input logic [1:0] select);
        begin
            case (select)
                2'd0: baud_from_select = 32'd4_000_000;
                2'd1: baud_from_select = 32'd4_500_000;
                2'd2: baud_from_select = 32'd6_000_000;
                default: baud_from_select = 32'd4_000_000;
            endcase
        end
    endfunction

    function automatic logic [31:0] wire_cycles_from_select(
         input logic [1:0] select
    );
        begin
            case (select)
                2'd0: wire_cycles_from_select =
                    (CLOCK_HZ + 32'd399_999) / 32'd400_000;
                2'd1: wire_cycles_from_select =
                    (CLOCK_HZ + 32'd449_999) / 32'd450_000;
                2'd2: wire_cycles_from_select =
                    (CLOCK_HZ + 32'd599_999) / 32'd600_000;
                default: wire_cycles_from_select =
                    (CLOCK_HZ + 32'd399_999) / 32'd400_000;
            endcase
        end
    endfunction

    function automatic logic [31:0] apply_write_strobe(
         input logic [31:0] old_value
        ,input logic [31:0] new_value
        ,input logic [3:0]  write_strobe
    );
        integer byte_index;
        begin
            apply_write_strobe = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                if (write_strobe[byte_index]) begin
                    apply_write_strobe[byte_index * 8 +: 8] = new_value[byte_index * 8 +: 8];
                end
            end
        end
    endfunction

    function automatic logic [7:0] selected_write_byte(
         input logic [31:0] write_data
        ,input logic [3:0]  write_strobe
    );
        begin
            if (write_strobe[0]) begin
                selected_write_byte = write_data[7:0];
            end else if (write_strobe[1]) begin
                selected_write_byte = write_data[15:8];
            end else if (write_strobe[2]) begin
                selected_write_byte = write_data[23:16];
            end else begin
                selected_write_byte = write_data[31:24];
            end
        end
    endfunction

    assign register_offset       = mmio_addr[7:0];
    assign control_access        = mmio_valid && mmio_write && (register_offset == REG_CONTROL) && mmio_wstrb[0] && (owner_reg == OWNER_DIRECT);
    assign control_start_request = control_access && mmio_wdata[0];
    assign control_result_ack    = control_access && mmio_wdata[1];

    assign config_write_request  = mmio_valid && mmio_write && (owner_reg == OWNER_DIRECT) &&
        ((register_offset == REG_CMD_CONFIG)       ||
         (register_offset == REG_BODY_LENGTH)      ||
         (register_offset == REG_RESPONSE_TIMEOUT) ||
         (register_offset == REG_INTER_BYTE_TIMEOUT));

    assign tx_data_write_request = mmio_valid &&  mmio_write && (owner_reg == OWNER_DIRECT)             && (register_offset == REG_TX_DATA) && (|mmio_wstrb);
    assign rx_meta_read_request  = mmio_valid && !mmio_write && (owner_reg == OWNER_DIRECT)             && (register_offset == REG_RX_META);
    assign rx_data_read_request  = mmio_valid && !mmio_write && (owner_reg == OWNER_DIRECT)             && (register_offset == REG_RX_DATA);

    assign owner_write_request   = mmio_valid &&  mmio_write && (register_offset == REG_PROTOCOL_OWNER) && mmio_wstrb[0];
    assign baud_write_request    = mmio_valid &&  mmio_write && (register_offset == REG_BAUD_REQUEST)   && mmio_wstrb[0];


    assign configuration_error_event =
        mmio_handshake && mmio_write &&
        (((register_offset == REG_PROTOCOL_OWNER) && mmio_wstrb[0] &&
          ((owner_write_word[1:0] >= OWNER_RAW) || rt_enable_reg)) ||
         ((register_offset == REG_BAUD_REQUEST) && mmio_wstrb[0] &&
          ((baud_request_write_word[1:0] > 2'd2) || rt_enable_reg)) ||
         ((register_offset == REG_DESCRIPTOR_COUNT) && mmio_wstrb[0] &&
          (({24'd0, descriptor_count_write_word[7:0]} >
            MAX_DESCRIPTOR_COUNT) || rt_enable_reg || rt_active)) ||
         (((register_offset == REG_FRAME_PERIOD) ||
           (register_offset == REG_COMM_DEADLINE) ||
           (register_offset == REG_COMMAND_DEADLINE)) &&
          (|mmio_wstrb) && (rt_enable_reg || rt_active)));

    // A TX_DATA store and an RX_DATA load are naturally stalled by the CPU
    // until the byte stream endpoint can complete the transfer.
    assign mmio_ready =
        tx_data_write_request                 ? body_ready
        :rx_data_read_request                 ? parameter_valid
        :rx_meta_read_request                 ? result_pending
        :(register_offset == REG_RT_MEM_DATA) ? rt_mem_ready
        :control_start_request                ? (!cmd_pending && !transaction_busy && !result_pending)
        :config_write_request                 ? (!cmd_pending && !transaction_busy)
        :owner_write_request                  ? (!cmd_pending && !result_pending && !transaction_busy && !rt_active && !rs485_de)
        :baud_write_request                   ? (!cmd_pending && !result_pending && !transaction_busy && !rt_active && !rs485_de)
        :1'b1;

    assign mmio_handshake       = mmio_valid && mmio_ready;
    assign command_handshake    = (owner_reg == OWNER_DIRECT) && cmd_pending && cmd_ready;
    assign body_handshake       = tx_data_write_request && body_ready;
    assign result_handshake     = (owner_reg == OWNER_DIRECT) && result_valid && !result_pending;
    assign result_ack_handshake = mmio_handshake && control_result_ack;

    assign status_word = {
        23'd0,
        cmd_pending,
        irq_status_reg[3],
        irq_status_reg[1],
        irq_status_reg[0],
        parameter_valid,
        result_pending,
        body_ready,
        transaction_busy,
        (!cmd_pending && !transaction_busy && !result_pending)
    };

    assign cmd_config_word = {
        8'd0,
        response_count_reg,
        expected_id_reg,
        cmd_id_reg
    };

    assign rx_meta_word = {
        dynamixel_error_reg,
        response_id_reg,
        result_code_reg,
        result_index_reg
    };

    assign rt_status_word = {
        12'd0,
        rt_command_bank_locked,
        rt_late_command_commit,
        rt_schedule_config_error,
        rt_schedule_overflow,
        rt_schedule_valid,
        owner_error_reg,
        rt_mem_write_blocked,
        3'd0,
        rt_committed_command_bank,
        rt_active_feedback_bank,
        rt_active_command_bank,
        rt_irq_status_reg[3],
        rt_irq_status_reg[2],
        rt_irq_status_reg[1],
        rt_irq_status_reg[0],
        rt_active,
        rt_enable_reg
    };

    assign baud_status_word = {
        14'd0,
        owner_error_reg,
        baud_applied_reg,
        6'd0,
        baud_active_reg,
        6'd0,
        baud_request_reg
    };

    assign active_baud_rate        = baud_from_select(baud_active_reg);
    assign active_wire_byte_cycles = wire_cycles_from_select(baud_active_reg);
    assign rt_irq_event = {
        rt_buffer_error,
        rt_frame_deadline,
        rt_frame_error,
        rt_frame_done
    };

    assign rt_single_step       = mmio_handshake && mmio_write && (register_offset == REG_RT_CONTROL)     && mmio_wstrb[0] && mmio_wdata[1];
    assign abort_flush_pulse    = mmio_handshake && mmio_write && (register_offset == REG_ABORT_FLUSH)    && mmio_wstrb[0] && mmio_wdata[0];
    assign command_commit_pulse = mmio_handshake && mmio_write && (register_offset == REG_COMMAND_COMMIT) && mmio_wstrb[3] && mmio_wstrb[0] && mmio_wdata[31];
    assign abort_request        = abort_flush_pulse || external_abort;
    assign rt_mem_access        = mmio_valid && (register_offset == REG_RT_MEM_DATA);
    assign rt_mem_write = mmio_write;

    assign core_cmd_valid          = (owner_reg == OWNER_RT) ? rt_cmd_valid          : (owner_reg == OWNER_DIRECT) ? cmd_pending : 1'b0;
    assign core_cmd_id             = (owner_reg == OWNER_RT) ? rt_cmd_id             : cmd_id_reg;
    assign core_cmd_body_len       = (owner_reg == OWNER_RT) ? rt_cmd_body_len       : body_length_reg;
    assign core_cmd_expected_id    = (owner_reg == OWNER_RT) ? rt_cmd_expected_id    : expected_id_reg;
    assign core_cmd_response_count = (owner_reg == OWNER_RT) ? rt_cmd_response_count : response_count_reg;
    assign core_response_timeout   = (owner_reg == OWNER_RT) ? rt_response_timeout   : response_timeout_reg;
    assign core_inter_byte_timeout = (owner_reg == OWNER_RT) ? rt_inter_byte_timeout : inter_byte_timeout_reg;
    assign core_body_valid         = (owner_reg == OWNER_RT) ? rt_body_valid         : tx_data_write_request;
    assign core_body_data          = (owner_reg == OWNER_RT) ? rt_body_data          : selected_write_byte(mmio_wdata, mmio_wstrb);
    assign core_result_ready       = (owner_reg == OWNER_RT) ? rt_result_ready       : !result_pending;
    assign core_parameter_ready    = (owner_reg == OWNER_RT) ? rt_parameter_ready    : (rx_data_read_request && mmio_ready);

    assign cmd_ready               = (owner_reg == OWNER_DIRECT) && core_cmd_ready;
    assign body_ready              = (owner_reg == OWNER_DIRECT) && core_body_ready;
    assign rt_cmd_ready            = (owner_reg == OWNER_RT)     && core_cmd_ready;
    assign rt_body_ready           = (owner_reg == OWNER_RT)     && core_body_ready;
    assign core_flush              = rt_core_abort || abort_request;

    always_comb begin : mmio_read_logic
        case (register_offset)
            REG_STATUS:             mmio_rdata = status_word;
            REG_CMD_CONFIG:         mmio_rdata = cmd_config_word;
            REG_BODY_LENGTH:        mmio_rdata = {16'd0, body_length_reg};
            REG_RESPONSE_TIMEOUT:   mmio_rdata = response_timeout_reg;
            REG_INTER_BYTE_TIMEOUT: mmio_rdata = inter_byte_timeout_reg;
            REG_RX_META:            mmio_rdata = rx_meta_word;
            REG_RX_LENGTH:          mmio_rdata = {16'd0, parameter_length_reg};
            REG_RX_DATA:            mmio_rdata = {23'd0, parameter_last, parameter_data};
            REG_IRQ_STATUS:         mmio_rdata = {28'd0, irq_status_reg};
            REG_IRQ_ENABLE:         mmio_rdata = {28'd0, irq_enable_reg};
            REG_ID:                 mmio_rdata = 32'h5032_4D4D;
            REG_TX_COUNT:           mmio_rdata = {16'd0, tx_count_reg};
            REG_RT_CONTROL:         mmio_rdata = {31'd0, rt_enable_reg};
            REG_RT_STATUS:          mmio_rdata = rt_status_word;
            REG_FRAME_PERIOD:       mmio_rdata = frame_period_reg;
            REG_COMM_DEADLINE:      mmio_rdata = comm_deadline_reg;
            REG_COMMAND_DEADLINE:   mmio_rdata = command_deadline_reg;
            REG_COMMAND_A_BASE:     mmio_rdata = 32'h0000_0000;
            REG_COMMAND_B_BASE:     mmio_rdata = 32'h0000_1000;
            REG_FEEDBACK_A_BASE:    mmio_rdata = 32'h0000_2000;
            REG_FEEDBACK_B_BASE:    mmio_rdata = 32'h0000_3000;
            REG_DESCRIPTOR_BASE:    mmio_rdata = 32'h0000_4000;
            REG_EXPECTED_ID_MASK:   mmio_rdata = rt_expected_mask;
            REG_RECEIVED_ID_MASK:   mmio_rdata = rt_received_mask;
            REG_ERROR_ID_MASK:      mmio_rdata = rt_error_mask;
            REG_FRAME_SEQUENCE:     mmio_rdata = rt_frame_sequence;
            REG_FRAME_CYCLES:       mmio_rdata = rt_last_frame_cycles;
            REG_MIN_SLACK:          mmio_rdata = rt_minimum_slack;
            REG_RT_IRQ_STATUS:      mmio_rdata = {28'd0, rt_irq_status_reg};
            REG_RT_IRQ_ENABLE:      mmio_rdata = {28'd0, rt_irq_enable_reg};
            REG_ERROR_COUNT:        mmio_rdata = error_count_reg;
            REG_PROTOCOL_OWNER:     mmio_rdata = {30'd0, owner_reg};
            REG_BAUD_REQUEST:       mmio_rdata = {30'd0, baud_request_reg};
            REG_BAUD_STATUS:        mmio_rdata = baud_status_word;
            REG_TEST_CONTROL:       mmio_rdata = 32'd0;
            REG_TEST_STATUS:        mmio_rdata = {31'd0, owner_error_reg};
            REG_TEST_TX_COUNT:      mmio_rdata = 32'd0;
            REG_TEST_RX_COUNT:      mmio_rdata = 32'd0;
            REG_TEST_ERROR_COUNT:   mmio_rdata = {31'd0, owner_error_reg};
            REG_RT_MEM_ADDR:        mmio_rdata = rt_mem_addr_reg;
            REG_RT_MEM_DATA:        mmio_rdata = rt_mem_rdata;
            REG_COMMAND_COMMIT:     mmio_rdata = {31'd0, rt_committed_command_bank};
            REG_DESCRIPTOR_COUNT:   mmio_rdata = {24'd0, descriptor_count_reg};
            REG_STALE_ID_MASK:      mmio_rdata = rt_stale_mask;
            REG_SCHEDULE_STATUS:    mmio_rdata = {20'd0, rt_command_bank_locked, 6'd0, rt_late_command_commit, rt_schedule_config_error, rt_schedule_overflow, rt_schedule_valid};
            REG_SCHEDULE_BUDGET:    mmio_rdata = rt_schedule_budget;
            REG_COMMANDED_ID_MASK:  mmio_rdata = rt_commanded_mask;
            REG_COMMAND_SEQUENCE:   mmio_rdata = command_sequence_reg;
            default: mmio_rdata = 32'd0;
        endcase
    end
    // assign mmio_rdata =
    //     (register_offset == REG_STATUS) ? status_word :
    //     (register_offset == REG_CMD_CONFIG) ? cmd_config_word :
    //     (register_offset == REG_BODY_LENGTH) ? {16'd0, body_length_reg} :
    //     (register_offset == REG_RESPONSE_TIMEOUT) ? response_timeout_reg :
    //     (register_offset == REG_INTER_BYTE_TIMEOUT) ? inter_byte_timeout_reg :
    //     (register_offset == REG_RX_META) ? rx_meta_word :
    //     (register_offset == REG_RX_LENGTH) ? {16'd0, parameter_length_reg} :
    //     (register_offset == REG_RX_DATA) ? {23'd0, parameter_last, parameter_data} :
    //     (register_offset == REG_IRQ_STATUS) ? {28'd0, irq_status_reg} :
    //     (register_offset == REG_IRQ_ENABLE) ? {28'd0, irq_enable_reg} :
    //     (register_offset == REG_ID) ? 32'h5032_4D4D :
    //     (register_offset == REG_TX_COUNT) ? {16'd0, tx_count_reg} :
    //     (register_offset == REG_RT_CONTROL) ? {31'd0, rt_enable_reg} :
    //     (register_offset == REG_RT_STATUS) ? rt_status_word :
    //     (register_offset == REG_FRAME_PERIOD) ? frame_period_reg :
    //     (register_offset == REG_COMM_DEADLINE) ? comm_deadline_reg :
    //     (register_offset == REG_COMMAND_DEADLINE) ? command_deadline_reg :
    //     (register_offset == REG_COMMAND_A_BASE) ? 32'h0000_0000 :
    //     (register_offset == REG_COMMAND_B_BASE) ? 32'h0000_1000 :
    //     (register_offset == REG_FEEDBACK_A_BASE) ? 32'h0000_2000 :
    //     (register_offset == REG_FEEDBACK_B_BASE) ? 32'h0000_3000 :
    //     (register_offset == REG_DESCRIPTOR_BASE) ? 32'h0000_4000 :
    //     (register_offset == REG_EXPECTED_ID_MASK) ? rt_expected_mask :
    //     (register_offset == REG_RECEIVED_ID_MASK) ? rt_received_mask :
    //     (register_offset == REG_ERROR_ID_MASK) ? rt_error_mask :
    //     (register_offset == REG_FRAME_SEQUENCE) ? rt_frame_sequence :
    //     (register_offset == REG_FRAME_CYCLES) ? rt_last_frame_cycles :
    //     (register_offset == REG_MIN_SLACK) ? rt_minimum_slack :
    //     (register_offset == REG_RT_IRQ_STATUS) ? {28'd0, rt_irq_status_reg} :
    //     (register_offset == REG_RT_IRQ_ENABLE) ? {28'd0, rt_irq_enable_reg} :
    //     (register_offset == REG_ERROR_COUNT) ? error_count_reg :
    //     (register_offset == REG_PROTOCOL_OWNER) ? {30'd0, owner_reg} :
    //     (register_offset == REG_BAUD_REQUEST) ? {30'd0, baud_request_reg} :
    //     (register_offset == REG_BAUD_STATUS) ? baud_status_word :
    //     (register_offset == REG_TEST_CONTROL) ? 32'd0 :
    //     (register_offset == REG_TEST_STATUS) ? {31'd0, owner_error_reg} :
    //     (register_offset == REG_TEST_TX_COUNT) ? 32'd0 :
    //     (register_offset == REG_TEST_RX_COUNT) ? 32'd0 :
    //     (register_offset == REG_TEST_ERROR_COUNT) ? {31'd0, owner_error_reg} :
    //     (register_offset == REG_RT_MEM_ADDR) ? rt_mem_addr_reg :
    //     (register_offset == REG_RT_MEM_DATA) ? rt_mem_rdata :
    //     (register_offset == REG_COMMAND_COMMIT) ? {31'd0, rt_committed_command_bank} :
    //     (register_offset == REG_DESCRIPTOR_COUNT) ? {24'd0, descriptor_count_reg} :
    //     (register_offset == REG_STALE_ID_MASK) ? rt_stale_mask :
    //     (register_offset == REG_SCHEDULE_STATUS) ? {20'd0, rt_command_bank_locked, 6'd0, rt_late_command_commit, rt_schedule_config_error, rt_schedule_overflow, rt_schedule_valid} :
    //     (register_offset == REG_SCHEDULE_BUDGET) ? rt_schedule_budget :
    //     (register_offset == REG_COMMANDED_ID_MASK) ? rt_commanded_mask :
    //     (register_offset == REG_COMMAND_SEQUENCE) ? command_sequence_reg :
    //             32'd0;

    assign irq_clear_word = apply_write_strobe(32'd0, mmio_wdata, mmio_wstrb);

    assign cmd_config_write_word       = apply_write_strobe(cmd_config_word, mmio_wdata, mmio_wstrb);
    assign body_length_write_word      = apply_write_strobe({16'd0, body_length_reg}, mmio_wdata, mmio_wstrb);
    assign irq_enable_write_word       = apply_write_strobe({28'd0, irq_enable_reg}, mmio_wdata, mmio_wstrb);
    assign rt_irq_enable_write_word    = apply_write_strobe({28'd0, rt_irq_enable_reg}, mmio_wdata, mmio_wstrb);
    assign owner_write_word            = apply_write_strobe({30'd0, owner_reg}, mmio_wdata, mmio_wstrb);
    assign baud_request_write_word     = apply_write_strobe({30'd0, baud_request_reg}, mmio_wdata, mmio_wstrb);
    assign descriptor_count_write_word = apply_write_strobe({24'd0, descriptor_count_reg}, mmio_wdata, mmio_wstrb);

    assign irq_event =
        ({4{transaction_done && (owner_reg == OWNER_DIRECT)}} & IRQ_DONE) |
        ({4{transaction_error && (owner_reg == OWNER_DIRECT)}} & IRQ_ERROR) |
        ({4{result_handshake}} & IRQ_RESULT) |
        ({4{uart_rx_overrun_error && (owner_reg == OWNER_DIRECT)}} & IRQ_OVERRUN);

    assign irq = |(irq_status_reg & irq_enable_reg) ||
                 |(rt_irq_status_reg & rt_irq_enable_reg);

// Real-time engine instantiation.
    generate
        if (USE_HX5_RT_SEQUENCER) begin : g_hx5_rt
            protocol2_hx5_rt_sequencer #(
                 .COMMAND_BYTES           (RT_COMMAND_BYTES)
                ,.FEEDBACK_BYTES          (RT_FEEDBACK_BYTES)
                ,.USE_EXTERNAL_FRAME_TICK (USE_EXTERNAL_FRAME_TICK)
            ) u_protocol2_rt_engine (
                 .clk                       (clk)
                ,.rst                       (rst)
                ,.enable                    (rt_enable_reg  && (owner_reg == OWNER_RT) && !external_abort)
                ,.single_step               (rt_single_step && (owner_reg == OWNER_RT) && !external_abort)
                ,.abort_flush               (abort_request)
                ,.frame_tick                (frame_tick)
                ,.frame_period_cycles       (frame_period_reg)
                ,.comm_deadline_cycles      (comm_deadline_reg)
                ,.command_deadline_cycles   (command_deadline_reg)
                ,.descriptor_count          (descriptor_count_reg)
                ,.command_commit            (command_commit_pulse)
                ,.command_commit_bank       (mmio_wdata[0])
                ,.command_commit_sequence   (command_sequence_reg)
                ,.cpu_mem_valid             (rt_mem_access)
                ,.cpu_mem_write             (rt_mem_write)
                ,.cpu_mem_region            (rt_mem_addr_reg[14:12])
                ,.cpu_mem_byte_addr         (rt_mem_addr_reg[11:0])
                ,.cpu_mem_wdata             (mmio_wdata)
                ,.cpu_mem_wstrb             (mmio_wstrb)
                ,.cpu_mem_ready             (rt_mem_ready)
                ,.cpu_mem_rdata             (rt_mem_rdata)
                ,.cpu_mem_write_blocked     (rt_mem_write_blocked)
                ,.cmd_valid                 (rt_cmd_valid)
                ,.cmd_ready                 (rt_cmd_ready)
                ,.cmd_id                    (rt_cmd_id)
                ,.cmd_body_len              (rt_cmd_body_len)
                ,.cmd_expected_id           (rt_cmd_expected_id)
                ,.cmd_response_count        (rt_cmd_response_count)
                ,.response_timeout_cycles   (rt_response_timeout)
                ,.inter_byte_timeout_cycles (rt_inter_byte_timeout)
                ,.body_valid                (rt_body_valid)
                ,.body_ready                (rt_body_ready)
                ,.body_data                 (rt_body_data)
                ,.result_valid              (result_valid)
                ,.result_ready              (rt_result_ready)
                ,.result_index              (result_index)
                ,.result_code               (result_code)
                ,.response_id               (response_id)
                ,.dynamixel_error           (dynamixel_error)
                ,.parameter_length          (parameter_length)
                ,.parameter_valid           (parameter_valid)
                ,.parameter_ready           (rt_parameter_ready)
                ,.parameter_data            (parameter_data)
                ,.parameter_last            (parameter_last)
                ,.transaction_busy          (transaction_busy)
                ,.transaction_done          (transaction_done)
                ,.transaction_error         (transaction_error)
                ,.uart_rx_overrun_error     (uart_rx_overrun_error)
                ,.core_abort                (rt_core_abort)
                ,.active                    (rt_active)
                ,.frame_done                (rt_frame_done)
                ,.frame_error               (rt_frame_error)
                ,.frame_deadline            (rt_frame_deadline)
                ,.buffer_error              (rt_buffer_error)
                ,.active_command_bank       (rt_active_command_bank)
                ,.active_feedback_bank      (rt_active_feedback_bank)
                ,.committed_command_bank    (rt_committed_command_bank)
                ,.frame_sequence            (rt_frame_sequence)
                ,.frame_cycles              ()
                ,.last_frame_cycles         (rt_last_frame_cycles)
                ,.minimum_slack_cycles      (rt_minimum_slack)
                ,.expected_device_mask      (rt_expected_mask)
                ,.received_device_mask      (rt_received_mask)
                ,.error_device_mask         (rt_error_mask)
                ,.stale_device_mask         (rt_stale_mask)
                ,.commanded_device_mask     (rt_commanded_mask)
                ,.schedule_valid            (rt_schedule_valid)
                ,.schedule_overflow         (rt_schedule_overflow)
                ,.schedule_config_error     (rt_schedule_config_error)
                ,.late_command_commit       (rt_late_command_commit)
                ,.schedule_budget_cycles    (rt_schedule_budget)
                ,.command_bank_locked       (rt_command_bank_locked)
                ,.timestamp                 ()
            );
        end else begin : g_generic_rt
            protocol2_rt_engine #(
                 .COMMAND_BYTES           (RT_COMMAND_BYTES)
                ,.FEEDBACK_BYTES          (RT_FEEDBACK_BYTES)
                ,.DESCRIPTOR_WORDS        (RT_DESCRIPTOR_WORDS)
                ,.MAX_BODY_BYTES          (MAX_BODY_BYTES)
                ,.MAX_STUFFED_BODY_BYTES  (MAX_STUFFED_BODY_BYTES)
                ,.TX_FIXED_CYCLES         (DE_SETUP_CYCLES + POST_TX_GUARD_CYCLES + 4)
                ,.USE_EXTERNAL_FRAME_TICK (USE_EXTERNAL_FRAME_TICK)
            ) u_protocol2_rt_engine (
                 .clk                       (clk)
                ,.rst                       (rst)
                ,.enable                    (rt_enable_reg  && (owner_reg == OWNER_RT) && !external_abort)
                ,.single_step               (rt_single_step && (owner_reg == OWNER_RT) && !external_abort)
                ,.abort_flush               (abort_request)
                ,.frame_tick                (frame_tick)
                ,.frame_period_cycles       (frame_period_reg)
                ,.comm_deadline_cycles      (comm_deadline_reg)
                ,.command_deadline_cycles   (command_deadline_reg)
                ,.wire_byte_cycles          (active_wire_byte_cycles)
                ,.descriptor_count          (descriptor_count_reg)
                ,.command_commit            (command_commit_pulse)
                ,.command_commit_bank       (mmio_wdata[0])
                ,.command_commit_sequence   (command_sequence_reg)
                ,.cpu_mem_valid             (rt_mem_access)
                ,.cpu_mem_write             (rt_mem_write)
                ,.cpu_mem_region            (rt_mem_addr_reg[14:12])
                ,.cpu_mem_byte_addr         (rt_mem_addr_reg[11:0])
                ,.cpu_mem_wdata             (mmio_wdata)
                ,.cpu_mem_wstrb             (mmio_wstrb)
                ,.cpu_mem_ready             (rt_mem_ready)
                ,.cpu_mem_rdata             (rt_mem_rdata)
                ,.cpu_mem_write_blocked     (rt_mem_write_blocked)
                ,.cmd_valid                 (rt_cmd_valid)
                ,.cmd_ready                 (rt_cmd_ready)
                ,.cmd_id                    (rt_cmd_id)
                ,.cmd_body_len              (rt_cmd_body_len)
                ,.cmd_expected_id           (rt_cmd_expected_id)
                ,.cmd_response_count        (rt_cmd_response_count)
                ,.response_timeout_cycles   (rt_response_timeout)
                ,.inter_byte_timeout_cycles (rt_inter_byte_timeout)
                ,.body_valid                (rt_body_valid)
                ,.body_ready                (rt_body_ready)
                ,.body_data                 (rt_body_data)
                ,.result_valid              (result_valid)
                ,.result_ready              (rt_result_ready)
                ,.result_index              (result_index)
                ,.result_code               (result_code)
                ,.response_id               (response_id)
                ,.dynamixel_error           (dynamixel_error)
                ,.parameter_length          (parameter_length)
                ,.parameter_valid           (parameter_valid)
                ,.parameter_ready           (rt_parameter_ready)
                ,.parameter_data            (parameter_data)
                ,.parameter_last            (parameter_last)
                ,.transaction_busy          (transaction_busy)
                ,.transaction_done          (transaction_done)
                ,.transaction_error         (transaction_error)
                ,.uart_rx_overrun_error     (uart_rx_overrun_error)
                ,.core_abort                (rt_core_abort)
                ,.active                    (rt_active)
                ,.frame_done                (rt_frame_done)
                ,.frame_error               (rt_frame_error)
                ,.frame_deadline            (rt_frame_deadline)
                ,.buffer_error              (rt_buffer_error)
                ,.active_command_bank       (rt_active_command_bank)
                ,.active_feedback_bank      (rt_active_feedback_bank)
                ,.committed_command_bank    (rt_committed_command_bank)
                ,.frame_sequence            (rt_frame_sequence)
                ,.frame_cycles              ()
                ,.last_frame_cycles         (rt_last_frame_cycles)
                ,.minimum_slack_cycles      (rt_minimum_slack)
                ,.expected_device_mask      (rt_expected_mask)
                ,.received_device_mask      (rt_received_mask)
                ,.error_device_mask         (rt_error_mask)
                ,.stale_device_mask         (rt_stale_mask)
                ,.commanded_device_mask     (rt_commanded_mask)
                ,.schedule_valid            (rt_schedule_valid)
                ,.schedule_overflow         (rt_schedule_overflow)
                ,.schedule_config_error     (rt_schedule_config_error)
                ,.late_command_commit       (rt_late_command_commit)
                ,.schedule_budget_cycles    (rt_schedule_budget)
                ,.command_bank_locked       (rt_command_bank_locked)
                ,.timestamp                 ()
            );
        end
    endgenerate

    protocol2_core #(
         .CLOCK_HZ               (CLOCK_HZ)
        ,.BAUD_RATE              (BAUD_RATE)
        ,.RX_OVERSAMPLE          (RX_OVERSAMPLE)
        ,.DE_SETUP_CYCLES        (DE_SETUP_CYCLES)
        ,.POST_TX_GUARD_CYCLES   (POST_TX_GUARD_CYCLES)
        ,.MAX_BODY_BYTES         (MAX_BODY_BYTES)
        ,.MAX_STUFFED_BODY_BYTES (MAX_STUFFED_BODY_BYTES)
        ,.MAX_PARAMETER_BYTES    (MAX_PARAMETER_BYTES)
    ) u_protocol2_core (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.flush                     (core_flush)
        ,.cmd_valid                 (core_cmd_valid)
        ,.cmd_ready                 (core_cmd_ready)
        ,.cmd_id                    (core_cmd_id)
        ,.cmd_body_len              (core_cmd_body_len)
        ,.cmd_expected_id           (core_cmd_expected_id)
        ,.cmd_response_count        (core_cmd_response_count)
        ,.response_timeout_cycles   (core_response_timeout)
        ,.inter_byte_timeout_cycles (core_inter_byte_timeout)
        ,.baud_rate                 (active_baud_rate)
        ,.body_valid                (core_body_valid)
        ,.body_ready                (core_body_ready)
        ,.body_data                 (core_body_data)
        ,.result_valid              (result_valid)
        ,.result_ready              (core_result_ready)
        ,.result_index              (result_index)
        ,.result_code               (result_code)
        ,.response_id               (response_id)
        ,.dynamixel_error           (dynamixel_error)
        ,.parameter_length          (parameter_length)
        ,.parameter_valid           (parameter_valid)
        ,.parameter_ready           (core_parameter_ready)
        ,.parameter_data            (parameter_data)
        ,.parameter_last            (parameter_last)
        ,.transaction_busy          (transaction_busy)
        ,.transaction_done          (transaction_done)
        ,.transaction_error         (transaction_error)
        ,.uart_rx_overrun_error     (uart_rx_overrun_error)
        ,.rs485_tx                  (rs485_tx)
        ,.rs485_rx                  (rs485_rx)
        ,.rs485_de                  (rs485_de)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cmd_id_reg                <= 8'hFE;
            expected_id_reg           <= 8'hFE;
            response_count_reg        <= 8'd0;
            body_length_reg           <= 16'd0;
            response_timeout_reg      <= 32'd0;
            inter_byte_timeout_reg    <= 32'd0;
            tx_count_reg              <= 16'd0;
            cmd_pending               <= 1'b0;
            result_pending            <= 1'b0;
            result_index_reg          <= 8'd0;
            result_code_reg           <= 8'd0;
            response_id_reg           <= 8'd0;
            dynamixel_error_reg       <= 8'd0;
            parameter_length_reg      <= 16'd0;
            irq_status_reg            <= 4'd0;
            irq_enable_reg            <= 4'd0;
            rt_enable_reg             <= 1'b0;
            frame_period_reg          <= CLOCK_HZ / `RTOS_CORE_PROTOCOL2_RT_FRAME_HZ;
            comm_deadline_reg         <= (CLOCK_HZ / 1_000_000) * `RTOS_CORE_PROTOCOL2_RT_COMM_DEADLINE_US;
            command_deadline_reg      <= (CLOCK_HZ / 1_000_000) * `RTOS_CORE_PROTOCOL2_RT_COMMAND_DEADLINE_US;
            descriptor_count_reg      <= 8'd0;
            command_sequence_reg      <= 32'd0;
            rt_mem_addr_reg           <= 32'd0;
            rt_irq_status_reg         <= 4'd0;
            rt_irq_enable_reg         <= 4'd0;
            owner_reg                 <= OWNER_DIRECT;
            baud_request_reg          <= DEFAULT_BAUD_SELECT;
            baud_active_reg           <= DEFAULT_BAUD_SELECT;
            baud_applied_reg          <= 1'b1;
            owner_error_reg           <= 1'b0;
            error_count_reg           <= 32'd0;

        end else begin
            baud_applied_reg <= 1'b0;
            if (mmio_handshake && mmio_write) begin
                case (register_offset)
                    REG_CONTROL: begin
                        if (mmio_wstrb[0] && mmio_wdata[0]) begin
                            cmd_pending <= 1'b1;
                        end
                    end
                    REG_CMD_CONFIG: begin
                        {response_count_reg,
                         expected_id_reg,
                         cmd_id_reg} <= cmd_config_write_word[23:0];
                    end
                    REG_BODY_LENGTH: begin
                        body_length_reg <= body_length_write_word[15:0];
                    end
                    REG_RESPONSE_TIMEOUT: begin
                        response_timeout_reg <= apply_write_strobe(
                            response_timeout_reg,
                            mmio_wdata,
                            mmio_wstrb
                        );
                    end
                    REG_INTER_BYTE_TIMEOUT: begin
                        inter_byte_timeout_reg <= apply_write_strobe(
                            inter_byte_timeout_reg,
                            mmio_wdata,
                            mmio_wstrb
                        );
                    end
                    REG_IRQ_ENABLE: begin
                        irq_enable_reg <= irq_enable_write_word[3:0];
                    end
                    REG_RT_CONTROL: begin
                        if (mmio_wstrb[0]) begin
                            rt_enable_reg <= mmio_wdata[0];
                        end
                    end
                    REG_FRAME_PERIOD: begin
                        if (!rt_enable_reg && !rt_active) begin
                            frame_period_reg <= apply_write_strobe(
                                frame_period_reg, mmio_wdata, mmio_wstrb
                            );
                        end else begin
                            owner_error_reg <= 1'b1;
                        end
                    end
                    REG_COMM_DEADLINE: begin
                        if (!rt_enable_reg && !rt_active) begin
                            comm_deadline_reg <= apply_write_strobe(
                                comm_deadline_reg, mmio_wdata, mmio_wstrb
                            );
                        end else begin
                            owner_error_reg <= 1'b1;
                        end
                    end
                    REG_COMMAND_DEADLINE: begin
                        if (!rt_enable_reg && !rt_active) begin
                            command_deadline_reg <= apply_write_strobe(
                                command_deadline_reg, mmio_wdata, mmio_wstrb
                            );
                        end else begin
                            owner_error_reg <= 1'b1;
                        end
                    end
                    REG_RT_IRQ_ENABLE: begin
                        rt_irq_enable_reg <= rt_irq_enable_write_word[3:0];
                    end
                    REG_PROTOCOL_OWNER: begin
                        if (mmio_wstrb[0]) begin
                            if ((owner_write_word[1:0] < OWNER_RAW) &&
                                !rt_enable_reg) begin
                                owner_reg <= owner_write_word[1:0];
                                owner_error_reg <= 1'b0;
                            end else begin
                                // RAW owner is reserved until the protected raw
                                // FIFO/test engine is integrated.
                                owner_error_reg <= 1'b1;
                            end
                        end
                    end
                    REG_BAUD_REQUEST: begin
                        if (mmio_wstrb[0]) begin
                            baud_request_reg <= baud_request_write_word[1:0];
                            if ((baud_request_write_word[1:0] <= 2'd2) &&
                                !rt_enable_reg) begin
                                baud_active_reg <= baud_request_write_word[1:0];
                                baud_applied_reg <= 1'b1;
                                owner_error_reg <= 1'b0;
                            end else begin
                                owner_error_reg <= 1'b1;
                            end
                        end
                    end
                    REG_RT_MEM_ADDR: begin
                        rt_mem_addr_reg <= apply_write_strobe(
                            rt_mem_addr_reg, mmio_wdata, mmio_wstrb
                        );
                    end
                    REG_DESCRIPTOR_COUNT: begin
                        if (mmio_wstrb[0]) begin
                            if (({24'd0, descriptor_count_write_word[7:0]} <=
                                 MAX_DESCRIPTOR_COUNT) &&
                                !rt_enable_reg && !rt_active) begin
                                descriptor_count_reg <=
                                    descriptor_count_write_word[7:0];
                            end else begin
                                owner_error_reg <= 1'b1;
                            end
                        end
                    end
                    REG_COMMAND_SEQUENCE: begin
                        command_sequence_reg <= apply_write_strobe(
                            command_sequence_reg, mmio_wdata, mmio_wstrb
                        );
                    end
                    default: begin
                    end
                endcase
            end

            if (mmio_handshake && (register_offset == REG_RT_MEM_DATA) && rt_mem_addr_reg[31]) begin
                rt_mem_addr_reg[11:0] <= rt_mem_addr_reg[11:0] + 12'd4;
            end

            if (abort_request) begin
                cmd_pending    <= 1'b0;
                result_pending <= 1'b0;
            end

            if (command_handshake) begin
                cmd_pending  <= 1'b0;
                tx_count_reg <= 16'd0;
            end

            if (body_handshake) begin
                tx_count_reg <= tx_count_reg + 16'd1;
            end

            if (result_handshake) begin
                result_pending       <= 1'b1;
                result_index_reg     <= result_index;
                result_code_reg      <= result_code;
                response_id_reg      <= response_id;
                dynamixel_error_reg  <= dynamixel_error;
                parameter_length_reg <= parameter_length;
            end else if (result_ack_handshake) begin
                result_pending <= 1'b0;
            end

            irq_status_reg    <= (irq_status_reg & ~((mmio_handshake && mmio_write && (register_offset == REG_IRQ_STATUS)) ? irq_clear_word[3:0] : 4'd0)) | irq_event;

            rt_irq_status_reg <= (rt_irq_status_reg & ~((mmio_handshake && mmio_write && (register_offset == REG_RT_IRQ_STATUS)) ? irq_clear_word[3:0] : 4'd0)) | rt_irq_event;

            if ((transaction_error && (owner_reg == OWNER_DIRECT)) || rt_frame_error || rt_frame_deadline || rt_buffer_error || configuration_error_event) begin
                if (error_count_reg != 32'hFFFF_FFFF) begin
                    error_count_reg <= error_count_reg + 32'd1;
                end
            end
        end
    end

endmodule
