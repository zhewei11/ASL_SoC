`include "rtos_core_config.svh"

// Protocol 2.0 deterministic frame engine.
//
// The current SoC has no peripheral AXI master, so the uncached control-I/O
// memories live inside this peripheral.  Software accesses them through the
// indirect RT_MEM_ADDR/RT_MEM_DATA window in protocol2_mmio_wrapper.  Replacing
// these arrays with SRAM macros or an AXI SRAM port does not change the RT ABI.
module protocol2_rt_engine #(
     parameter int unsigned COMMAND_BYTES = `RTOS_CORE_PROTOCOL2_RT_COMMAND_BUFFER_BYTES
    ,parameter int unsigned FEEDBACK_BYTES = `RTOS_CORE_PROTOCOL2_RT_FEEDBACK_BUFFER_BYTES
    ,parameter int unsigned DESCRIPTOR_WORDS = `RTOS_CORE_PROTOCOL2_RT_DESCRIPTOR_WORDS
    ,parameter int unsigned MAX_BODY_BYTES = `RTOS_CORE_PROTOCOL2_MAX_BODY_BYTES
    ,parameter int unsigned MAX_STUFFED_BODY_BYTES =
        `RTOS_CORE_PROTOCOL2_MAX_STUFFED_BODY_BYTES
    ,parameter int unsigned TX_FIXED_CYCLES = 8
    ,parameter bit USE_EXTERNAL_FRAME_TICK = 1'b0
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
    ,input  logic [31:0] wire_byte_cycles
    ,input  logic [7:0]  descriptor_count

    ,input  logic        command_commit
    ,input  logic        command_commit_bank
    ,input  logic [31:0] command_commit_sequence

    // CPU indirect access. Regions 0/1 are Command A/B, 2/3 Feedback A/B,
    // and 4 is Descriptor RAM. Addresses are byte offsets inside a region.
    ,input  logic        cpu_mem_valid
    ,input  logic        cpu_mem_write
    ,input  logic [2:0]  cpu_mem_region
    ,input  logic [11:0] cpu_mem_byte_addr
    ,input  logic [31:0] cpu_mem_wdata
    ,input  logic [3:0]  cpu_mem_wstrb
    ,output logic        cpu_mem_ready
    ,output logic [31:0] cpu_mem_rdata
    ,output logic        cpu_mem_write_blocked

    // Shared protocol2_core command interface.
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

    localparam logic [31:0] DESC_END = 32'hFFFF_FFFF;
    localparam int unsigned MAX_DESCRIPTOR_COUNT = DESCRIPTOR_WORDS / 10;

    localparam logic [31:0] STATUS_COMPLETE      = 32'h0000_0001;
    localparam logic [31:0] STATUS_ERROR         = 32'h0000_0002;
    localparam logic [31:0] STATUS_DEADLINE      = 32'h0000_0004;
    localparam logic [31:0] STATUS_STALE_COMMAND = 32'h0000_0008;
    localparam logic [31:0] STATUS_DUPLICATE     = 32'h0000_0010;
    localparam logic [31:0] STATUS_ABORTED       = 32'h0000_0020;
    localparam logic [31:0] STATUS_BUFFER_ERROR  = 32'h0000_0040;
    localparam logic [31:0] STATUS_RX_OVERRUN    = 32'h0000_0080;
    localparam logic [31:0] STATUS_UNEXPECTED_ID = 32'h0000_0100;
    localparam logic [63:0] FRAME_FIXED_CYCLES = 64'd16;
    localparam logic [63:0] DESCRIPTOR_LOAD_CYCLES = 64'd11;

    typedef enum logic [3:0] {
        RT_IDLE        = 4'd0,
        RT_VALIDATE    = 4'd1,
        RT_WAIT_FRAME  = 4'd2,
        RT_LOAD_DESC   = 4'd3,
        RT_START_CMD   = 4'd4,
        RT_STREAM_BODY = 4'd5,
        RT_WAIT_TRANS  = 4'd6,
        RT_COMMIT      = 4'd7,
        RT_SCHED_ERROR = 4'd8,
        RT_DESC_READ   = 4'd9,
        RT_BODY_READ   = 4'd10
    } rt_state_t;

    localparam int unsigned COMMAND_WORDS = COMMAND_BYTES / 4;
    localparam int unsigned FEEDBACK_WORDS = FEEDBACK_BYTES / 4;
    localparam int unsigned DESC_COUNTER_INDEX_WIDTH =
        (MAX_DESCRIPTOR_COUNT <= 1) ? 1 : $clog2(MAX_DESCRIPTOR_COUNT);

    // All bulk memories are word-wide, synchronous, single-port arrays.  Byte
    // writes use packed-array lane enables so these arrays can be replaced by
    // conventional 32-bit SRAM macros without changing the RT interface.
    logic [31:0] command_mem [0:(2*COMMAND_WORDS)-1];
    logic [31:0] feedback_mem [0:(2*FEEDBACK_WORDS)-1];
    logic [31:0] descriptor_mem [0:DESCRIPTOR_WORDS-1];

    rt_state_t state;
    logic [31:0] frame_period_counter;
    logic [31:0] active_command_sequence;
    logic [31:0] committed_command_sequence;
    logic        command_commit_valid;
    logic        working_feedback_bank;
    logic [7:0]  descriptor_index;
    logic [7:0]  descriptor_steps;
    logic [15:0] body_index;
    logic [15:0] parameter_index;
    logic [11:0] parameter_base;
    logic [7:0]  metadata_word_index;
    logic [63:0] frame_start_timestamp;
    logic [63:0] frame_done_timestamp_latched;
    logic [31:0] frame_cycles_latched;
    logic [31:0] frame_slack_latched;
    logic [31:0] frame_status_latched;
    logic [31:0] frame_error_mask_latched;
    logic [31:0] frame_stale_mask_latched;
    logic        frame_error_pending;
    logic        frame_deadline_pending;
    logic        duplicate_pending;
    logic        unexpected_id_pending;
    logic        buffer_error_pending;
    logic        rx_overrun_pending;
    logic        abort_pending;
    logic        descriptor_error_pending;
    logic        stale_command_pending;
    logic        command_deadline_missed;
    logic        last_command_valid;
    logic [31:0] last_command_sequence;
    logic        single_step_pending;

    logic [7:0]  validation_index;
    logic [7:0]  validation_steps;
    logic [63:0] validation_budget;
    logic [31:0] validation_commanded_mask;
    logic [31:0] schedule_commanded_mask;
    logic [31:0] descriptor_period_counter [0:(DESCRIPTOR_WORDS/10)-1];
    logic [3:0]  descriptor_load_word;
    logic        descriptor_load_validation;
    logic [31:0] body_word;
    logic        cpu_read_pending;

    logic [31:0]     desc_control;
    logic [31:0]     desc_tx_offset;
    logic [31:0]     desc_body_length;
    logic [31:0]     desc_response_count;
    logic [31:0]     desc_expected_mask;
    logic [31:0]     desc_response_timeout;
    logic [31:0]     desc_inter_byte_timeout;
    logic [31:0]     desc_response_map_offset;
    logic [31:0]     desc_period_divider;
    logic [31:0]     desc_next;
    logic [31:0]     response_id_mask;
    logic            response_single_id;
    logic [31:0]     metadata_word;
    logic [31:0]     active_body_byte_address;
    logic [31:0]     feedback_write_byte_address;
    integer unsigned descriptor_read_address;
    integer unsigned active_body_word_address;
    integer unsigned feedback_write_word_address;
    integer unsigned cpu_word_address;
    logic            cpu_port_available;
    logic            cpu_address_valid;
    logic            cpu_read_start;
    logic            cpu_write_accept;
    logic            descriptor_due;
    logic            descriptor_valid;
    logic            descriptor_abort_on_error;
    logic [7:0]      descriptor_response_stride;
    logic [31:0]     missing_mask_now;
    logic [31:0]     final_status_now;
    logic [31:0]     final_error_mask_now;
    logic [31:0]     slack_now;
    logic            frame_trigger;
    logic            result_handshake;
    logic            parameter_handshake;
    logic            parameter_drop;
    logic            deadline_expired;
    logic            commit_is_late;
    logic            response_expected;
    logic            response_duplicate;
    logic            response_invalid;
    logic [5:0]      response_slot;
    logic [31:0]     response_slot_offset;
    logic [31:0]     descriptor_command_mask;
    logic [5:0]      descriptor_device_count;
    logic [31:0]     descriptor_tx_wire_bytes;
    logic [31:0]     descriptor_rx_wire_bytes_per_response;
    logic [31:0]     descriptor_command_word_reads;
    logic [63:0]     descriptor_tx_cycles;
    logic [63:0]     descriptor_rx_min_cycles;
    logic [63:0]     descriptor_tx_prepare_cycles;
    logic [63:0]     descriptor_response_timeout_budget;
    logic [63:0]     descriptor_response_scatter_cycles;
    logic [63:0]     descriptor_internal_cycles;
    logic [63:0]     descriptor_budget_cycles;
    logic            descriptor_fields_invalid;
    logic            descriptor_chain_end;
    logic            strict_timing_config_invalid;

    function automatic logic [5:0] popcount32(input logic [31:0] value);
        integer bit_index;
        begin
            popcount32 = 6'd0;
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
                popcount32 = popcount32 + {5'd0, value[bit_index]};
            end
        end
    endfunction

    function automatic logic [31:0] id_mask(input logic [7:0] id);
        begin
            id_mask = ((id >= 8'd1) && (id <= 8'd32)) ?
                (32'h0000_0001 << (id - 8'd1)) : 32'd0;
        end
    endfunction

    // Protocol 2.0 stuffing inserts at most one byte per three bytes in the
    // stuffed section. The extra two bytes conservatively cover CRC boundary
    // patterns without requiring packet contents during schedule validation.
    function automatic logic [31:0] stuffing_allowance(input logic [31:0] bytes);
        begin
            stuffing_allowance = (bytes + 32'd4) / 32'd3;
        end
    endfunction

    assign active =
        (state != RT_IDLE) &&
        (state != RT_VALIDATE) &&
        !((state == RT_DESC_READ) && descriptor_load_validation) &&
        (state != RT_WAIT_FRAME) &&
        (state != RT_SCHED_ERROR);
    assign active_feedback_bank = active_feedback_bank_reg;

    logic active_feedback_bank_reg;

    always_comb begin
        descriptor_read_address =
            ({24'd0, (descriptor_load_validation ?
                validation_index : descriptor_index)} * 32'd10) +
            {28'd0, descriptor_load_word};
    end

    assign descriptor_valid = desc_control[0];
    assign descriptor_abort_on_error = desc_control[1];
    assign descriptor_response_stride = desc_control[23:16];
    assign descriptor_due =
        (desc_period_divider <= 32'd1) ||
        (descriptor_period_counter[
            descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] == 32'd0);

    assign cmd_valid = (state == RT_START_CMD);
    assign cmd_id = desc_control[15:8];
    assign cmd_body_len = desc_body_length[15:0];
    assign cmd_expected_id =
        (desc_response_count[7:0] > 8'd1) ? 8'hFE : desc_control[15:8];
    assign cmd_response_count = desc_response_count[7:0];
    assign response_timeout_cycles = desc_response_timeout;
    assign inter_byte_timeout_cycles = desc_inter_byte_timeout;

    assign active_body_byte_address =
        desc_tx_offset + {16'd0, body_index};
    always_comb begin
        active_body_word_address =
            (active_command_bank ? COMMAND_WORDS : 0) +
            (active_body_byte_address >> 2);
    end
    assign body_valid =
        (state == RT_STREAM_BODY) &&
        (body_index < desc_body_length[15:0]);
    always_comb begin
        case (active_body_byte_address[1:0])
            2'd0: body_data = body_word[7:0];
            2'd1: body_data = body_word[15:8];
            2'd2: body_data = body_word[23:16];
            default: body_data = body_word[31:24];
        endcase
    end

    assign result_ready = (state == RT_WAIT_TRANS);
    assign parameter_ready = (state == RT_WAIT_TRANS);
    assign result_handshake = result_valid && result_ready;
    assign parameter_handshake = parameter_valid && parameter_ready;

    assign response_single_id =
        (desc_response_count[7:0] == 8'd1) &&
        (response_id == desc_control[15:8]);
    assign response_id_mask = response_single_id ?
        desc_expected_mask : id_mask(response_id);
    assign response_expected = response_single_id ||
        ((desc_response_count[7:0] != 8'd1) &&
         (response_id_mask != 32'd0) &&
         ((desc_expected_mask & response_id_mask) != 32'd0));
    assign response_duplicate =
        (response_id_mask != 32'd0) &&
        ((received_device_mask & response_id_mask) != 32'd0);
    assign response_slot = response_single_id ? 6'd0 : popcount32(
        desc_expected_mask & (response_id_mask - 32'd1));
    assign response_slot_offset =
        desc_response_map_offset +
        (response_slot * descriptor_response_stride);
    assign response_invalid =
        (result_code != 8'd0) ||
        (dynamixel_error != 8'd0) ||
        !response_expected || response_duplicate ||
        (parameter_length > {8'd0, descriptor_response_stride}) ||
        ({16'd0, parameter_length} + response_slot_offset > FEEDBACK_BYTES);
    assign feedback_write_byte_address =
        {20'd0, parameter_base} + {16'd0, parameter_index};

    always_comb begin
        feedback_write_word_address =
            (working_feedback_bank ? FEEDBACK_WORDS : 0) +
            (feedback_write_byte_address >> 2);
    end

    assign frame_trigger =
        single_step_pending ||
        (enable &&
         (USE_EXTERNAL_FRAME_TICK ?
             frame_tick :
             ((frame_period_cycles != 32'd0) &&
              (frame_period_counter >= frame_period_cycles - 32'd1))));

    assign deadline_expired =
        active && !frame_deadline_pending &&
        (comm_deadline_cycles != 32'd0) &&
        (frame_cycles >= comm_deadline_cycles - 32'd1) &&
        !((state == RT_WAIT_TRANS) && transaction_done) &&
        (state != RT_COMMIT);

    assign commit_is_late =
        enable && (command_deadline_cycles != 32'd0) &&
        (frame_period_counter >= command_deadline_cycles);
    assign command_bank_locked = {
        ((active && (active_command_bank == 1'b1)) ||
         (command_commit_valid && (committed_command_bank == 1'b1))),
        ((active && (active_command_bank == 1'b0)) ||
         (command_commit_valid && (committed_command_bank == 1'b0)))
    };

    assign descriptor_device_count = popcount32(desc_expected_mask);
    assign descriptor_command_mask =
        (desc_response_count[7:0] == 8'd1) ? desc_expected_mask :
        desc_expected_mask | id_mask(desc_control[15:8]);
    assign descriptor_tx_wire_bytes =
        32'd9 + desc_body_length + stuffing_allowance(desc_body_length + 32'd2);
    assign descriptor_rx_wire_bytes_per_response =
        32'd11 + {24'd0, descriptor_response_stride} +
        stuffing_allowance({24'd0, descriptor_response_stride} + 32'd4);
    assign descriptor_command_word_reads =
        ({30'd0, desc_tx_offset[1:0]} + desc_body_length + 32'd3) / 32'd4;
    assign descriptor_tx_cycles =
        descriptor_tx_wire_bytes * wire_byte_cycles +
        {32'd0, TX_FIXED_CYCLES[31:0]};
    assign descriptor_rx_min_cycles =
        descriptor_rx_wire_bytes_per_response * wire_byte_cycles;
    assign descriptor_tx_prepare_cycles =
        64'd2 + {32'd0, desc_body_length} +
        {32'd0, stuffing_allowance(desc_body_length)} +
        {32'd0, descriptor_command_word_reads};
    assign descriptor_response_timeout_budget =
        desc_response_count * desc_response_timeout;
    assign descriptor_response_scatter_cycles =
        desc_response_count *
        (64'd2 + {56'd0, descriptor_response_stride} +
         (({56'd0, descriptor_response_stride} + 64'd5) / 64'd4));
    assign descriptor_internal_cycles =
        DESCRIPTOR_LOAD_CYCLES + descriptor_tx_prepare_cycles +
        descriptor_response_scatter_cycles;
    // Budget includes RT-side descriptor fetch, command SRAM reads and TX
    // stuffing preload, one absolute RX timeout per expected response,
    // response scatter/drain, plus the wire and PHY direction time.
    assign descriptor_budget_cycles = descriptor_tx_cycles +
        descriptor_internal_cycles + descriptor_response_timeout_budget;
    assign descriptor_fields_invalid =
        (desc_body_length == 32'd0) ||
        (desc_body_length > MAX_BODY_BYTES) ||
        (desc_body_length + stuffing_allowance(desc_body_length) >
         MAX_STUFFED_BODY_BYTES) ||
        (desc_tx_offset >= COMMAND_BYTES) ||
        (desc_tx_offset + desc_body_length > COMMAND_BYTES) ||
        (desc_response_count > 32'd32) ||
        ((desc_response_count != 32'd0) &&
         ((descriptor_device_count != desc_response_count[5:0]) ||
          (descriptor_response_stride == 8'd0) ||
          (desc_response_timeout == 32'd0) ||
          (descriptor_rx_min_cycles > {32'd0, desc_response_timeout}) ||
          (desc_response_map_offset < 32'd56) ||
          (desc_response_map_offset >= FEEDBACK_BYTES) ||
          (desc_response_map_offset +
           (desc_response_count * descriptor_response_stride) > FEEDBACK_BYTES)));
    assign descriptor_chain_end = (desc_next == DESC_END);
    assign strict_timing_config_invalid =
        ((frame_period_cycles != 32'd0) &&
         (((comm_deadline_cycles != 32'd0) &&
           (comm_deadline_cycles > frame_period_cycles)) ||
          ((command_deadline_cycles != 32'd0) &&
           (command_deadline_cycles >= frame_period_cycles)))) ||
        ((comm_deadline_cycles != 32'd0) &&
         (command_deadline_cycles != 32'd0) &&
         (command_deadline_cycles < comm_deadline_cycles));
    assign last_frame_cycles = frame_cycles_latched;

    assign missing_mask_now = expected_device_mask & ~received_device_mask;
    assign final_error_mask_now = error_device_mask | missing_mask_now;
    assign slack_now =
        (frame_cycles < comm_deadline_cycles) ?
        (comm_deadline_cycles - frame_cycles) : 32'd0;
    assign final_status_now =
        STATUS_COMPLETE |
        ((frame_error_pending || (missing_mask_now != 32'd0)) ?
            STATUS_ERROR : 32'd0) |
        (frame_deadline_pending ? STATUS_DEADLINE : 32'd0) |
        (stale_command_pending ? STATUS_STALE_COMMAND : 32'd0) |
        (duplicate_pending ? STATUS_DUPLICATE : 32'd0) |
        (abort_pending ? STATUS_ABORTED : 32'd0) |
        (buffer_error_pending ? STATUS_BUFFER_ERROR : 32'd0) |
        (rx_overrun_pending ? STATUS_RX_OVERRUN : 32'd0) |
        (unexpected_id_pending ? STATUS_UNEXPECTED_ID : 32'd0);

    always_comb begin
        cpu_word_address = 0;
        cpu_address_valid = (cpu_mem_byte_addr[1:0] == 2'd0);
        case (cpu_mem_region)
            3'd0, 3'd1: begin
                cpu_word_address =
                    (cpu_mem_region[0] ? COMMAND_WORDS : 0) +
                    ({20'd0, cpu_mem_byte_addr} >> 2);
                cpu_address_valid = cpu_address_valid &&
                    ({20'd0, cpu_mem_byte_addr} < COMMAND_BYTES);
            end
            3'd2, 3'd3: begin
                cpu_word_address =
                    (cpu_mem_region[0] ? FEEDBACK_WORDS : 0) +
                    ({20'd0, cpu_mem_byte_addr} >> 2);
                cpu_address_valid = cpu_address_valid &&
                    ({20'd0, cpu_mem_byte_addr} < FEEDBACK_BYTES);
            end
            3'd4: begin
                cpu_word_address = {20'd0, cpu_mem_byte_addr} >> 2;
                cpu_address_valid = cpu_address_valid &&
                    (({20'd0, cpu_mem_byte_addr} >> 2) < DESCRIPTOR_WORDS);
            end
            default: cpu_address_valid = 1'b0;
        endcase

        // Each array is used as a single-port SRAM. CPU accesses wait while
        // the real-time side is consuming that array's port.
        case (cpu_mem_region)
            3'd0, 3'd1: cpu_port_available = (state != RT_BODY_READ);
            3'd2, 3'd3: cpu_port_available =
                !((parameter_handshake && !parameter_drop) ||
                  (state == RT_COMMIT));
            3'd4: cpu_port_available = (state != RT_DESC_READ);
            default: cpu_port_available = 1'b1;
        endcase
    end

    assign cpu_mem_ready = cpu_mem_write ?
        cpu_port_available : cpu_read_pending;
    assign cpu_read_start = cpu_mem_valid && !cpu_mem_write &&
        !cpu_read_pending && cpu_port_available;
    assign cpu_write_accept = cpu_mem_valid && cpu_mem_write &&
        cpu_mem_ready;

    always_comb begin
        case (metadata_word_index)
            8'd0:  metadata_word = frame_sequence;
            8'd1:  metadata_word = active_command_sequence;
            8'd2:  metadata_word = frame_start_timestamp[31:0];
            8'd3:  metadata_word = frame_start_timestamp[63:32];
            8'd4:  metadata_word = frame_done_timestamp_latched[31:0];
            8'd5:  metadata_word = frame_done_timestamp_latched[63:32];
            8'd6:  metadata_word = expected_device_mask;
            8'd7:  metadata_word = received_device_mask;
            8'd8:  metadata_word = frame_error_mask_latched;
            8'd9:  metadata_word = frame_stale_mask_latched;
            8'd10: metadata_word = frame_status_latched;
            8'd11: metadata_word = frame_cycles_latched;
            8'd12: metadata_word = frame_slack_latched;
            8'd13: metadata_word = frame_sequence; // Atomic commit, written last.
            default: metadata_word = 32'd0;
        endcase
    end

    integer lane;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state                       <= RT_IDLE;
            frame_period_counter        <= 32'd0;
            timestamp                   <= 64'd0;
            frame_sequence              <= 32'd0;
            frame_cycles                <= 32'd0;
            frame_cycles_latched        <= 32'd0;
            frame_slack_latched         <= 32'd0;
            minimum_slack_cycles        <= 32'hFFFF_FFFF;
            frame_start_timestamp       <= 64'd0;
            frame_done_timestamp_latched <= 64'd0;
            active_command_bank         <= 1'b0;
            active_feedback_bank_reg    <= 1'b0;
            working_feedback_bank       <= 1'b1;
            committed_command_bank      <= 1'b0;
            active_command_sequence     <= 32'd0;
            committed_command_sequence  <= 32'd0;
            command_commit_valid        <= 1'b0;
            descriptor_index            <= 8'd0;
            descriptor_steps            <= 8'd0;
            body_index                  <= 16'd0;
            parameter_index             <= 16'd0;
            parameter_base              <= 12'd0;
            parameter_drop              <= 1'b0;
            metadata_word_index         <= 8'd0;
            expected_device_mask        <= 32'd0;
            received_device_mask        <= 32'd0;
            error_device_mask           <= 32'd0;
            stale_device_mask           <= 32'd0;
            commanded_device_mask       <= 32'd0;
            schedule_valid              <= 1'b0;
            schedule_overflow           <= 1'b0;
            schedule_config_error       <= 1'b0;
            late_command_commit         <= 1'b0;
            schedule_budget_cycles      <= 32'd0;
            frame_status_latched        <= 32'd0;
            frame_error_mask_latched    <= 32'd0;
            frame_stale_mask_latched    <= 32'd0;
            frame_error_pending         <= 1'b0;
            frame_deadline_pending      <= 1'b0;
            duplicate_pending           <= 1'b0;
            unexpected_id_pending       <= 1'b0;
            buffer_error_pending        <= 1'b0;
            rx_overrun_pending          <= 1'b0;
            abort_pending               <= 1'b0;
            descriptor_error_pending    <= 1'b0;
            stale_command_pending       <= 1'b0;
            command_deadline_missed     <= 1'b0;
            last_command_valid          <= 1'b0;
            last_command_sequence       <= 32'd0;
            single_step_pending         <= 1'b0;
            validation_index            <= 8'd0;
            validation_steps            <= 8'd0;
            validation_budget           <= 64'd0;
            validation_commanded_mask   <= 32'd0;
            schedule_commanded_mask     <= 32'd0;
            descriptor_load_word        <= 4'd0;
            descriptor_load_validation  <= 1'b0;
            desc_control                <= 32'd0;
            desc_tx_offset              <= 32'd0;
            desc_body_length            <= 32'd0;
            desc_response_count         <= 32'd0;
            desc_expected_mask          <= 32'd0;
            desc_response_timeout       <= 32'd0;
            desc_inter_byte_timeout     <= 32'd0;
            desc_response_map_offset    <= 32'd0;
            desc_period_divider         <= 32'd0;
            desc_next                   <= DESC_END;
            body_word                   <= 32'd0;
            cpu_read_pending            <= 1'b0;
            cpu_mem_rdata               <= 32'd0;
            core_abort                  <= 1'b0;
            frame_done                  <= 1'b0;
            frame_error                 <= 1'b0;
            frame_deadline              <= 1'b0;
            buffer_error                <= 1'b0;
            cpu_mem_write_blocked       <= 1'b0;
        end else begin
            timestamp <= timestamp + 64'd1;
            core_abort <= 1'b0;
            frame_done <= 1'b0;
            frame_error <= 1'b0;
            frame_deadline <= 1'b0;
            buffer_error <= 1'b0;
            cpu_mem_write_blocked <= 1'b0;

            if (cpu_read_pending && cpu_mem_valid && cpu_mem_ready) begin
                cpu_read_pending <= 1'b0;
            end

            if (cpu_read_start) begin
                cpu_read_pending <= 1'b1;
                if (!cpu_address_valid) begin
                    cpu_mem_rdata <= 32'd0;
                end else begin
                    case (cpu_mem_region)
                        3'd0, 3'd1:
                            cpu_mem_rdata <= command_mem[cpu_word_address];
                        3'd2, 3'd3:
                            cpu_mem_rdata <= feedback_mem[cpu_word_address];
                        3'd4:
                            cpu_mem_rdata <= descriptor_mem[cpu_word_address];
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

            if (command_commit) begin
                if ((active && (command_commit_bank == active_command_bank)) ||
                    (command_commit_valid &&
                     (command_commit_bank == committed_command_bank))) begin
                    buffer_error <= 1'b1;
                    buffer_error_pending <= 1'b1;
                end else if (commit_is_late) begin
                    command_deadline_missed <= 1'b1;
                    late_command_commit <= 1'b1;
                    frame_error_pending <= 1'b1;
                end else begin
                    committed_command_bank <= command_commit_bank;
                    committed_command_sequence <= command_commit_sequence;
                    command_commit_valid <= 1'b1;
                    command_deadline_missed <= 1'b0;
                    late_command_commit <= 1'b0;
                end
            end

            // A flush invalidates the last command snapshot as well as the
            // in-flight transaction. After a safety release or software
            // reconfiguration, RT transmission therefore remains suppressed
            // until the producer commits a fresh complete command bank.
            if (abort_flush) begin
                command_commit_valid <= 1'b0;
                last_command_valid <= 1'b0;
            end

            if (enable &&
                (command_deadline_cycles != 32'd0) &&
                (frame_period_counter >= command_deadline_cycles) &&
                (!command_commit_valid ||
                 (last_command_valid &&
                  (committed_command_sequence == last_command_sequence)))) begin
                command_deadline_missed <= 1'b1;
            end

            if (cpu_write_accept) begin
                if (!cpu_address_valid) begin
                    cpu_mem_write_blocked <= 1'b1;
                    buffer_error <= 1'b1;
                    buffer_error_pending <= 1'b1;
                end else if ((cpu_mem_region <= 3'd1) &&
                    command_bank_locked[cpu_mem_region[0]]) begin
                    cpu_mem_write_blocked <= 1'b1;
                    buffer_error <= 1'b1;
                    buffer_error_pending <= 1'b1;
                end else if (cpu_mem_region <= 3'd1) begin
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        if (cpu_mem_wstrb[lane]) begin
                            command_mem[cpu_word_address][lane*8 +: 8]
                                <= cpu_mem_wdata[lane*8 +: 8];
                        end
                    end
                end else if ((cpu_mem_region == 3'd4) &&
                             (state == RT_IDLE) && !enable) begin
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        if (cpu_mem_wstrb[lane]) begin
                            descriptor_mem[cpu_word_address][lane*8 +: 8]
                                <= cpu_mem_wdata[lane*8 +: 8];
                        end
                    end
                end else begin
                    cpu_mem_write_blocked <= 1'b1;
                    buffer_error <= 1'b1;
                    buffer_error_pending <= 1'b1;
                end
            end

            if (active) begin
                frame_cycles <= frame_cycles + 32'd1;
                if (uart_rx_overrun_error) begin
                    rx_overrun_pending <= 1'b1;
                    frame_error_pending <= 1'b1;
                    descriptor_error_pending <= 1'b1;
                end
                if (deadline_expired) begin
                    frame_deadline_pending <= 1'b1;
                    frame_error_pending <= 1'b1;
                    abort_pending <= 1'b1;
                    core_abort <= 1'b1;
                    frame_done_timestamp_latched <= timestamp;
                    frame_cycles_latched <= frame_cycles + 32'd1;
                    frame_slack_latched <= 32'd0;
                    frame_error_mask_latched <=
                        error_device_mask |
                        (expected_device_mask & ~received_device_mask);
                    frame_stale_mask_latched <=
                        (expected_device_mask & ~received_device_mask) |
                        (stale_command_pending ? commanded_device_mask : 32'd0);
                    frame_status_latched <= final_status_now |
                        STATUS_ERROR | STATUS_DEADLINE | STATUS_ABORTED;
                    metadata_word_index <= 8'd0;
                    state <= RT_COMMIT;
                end
            end

            if (abort_flush && active) begin
                abort_pending <= 1'b1;
                frame_error_pending <= 1'b1;
                core_abort <= 1'b1;
                frame_done_timestamp_latched <= timestamp;
                frame_cycles_latched <= frame_cycles;
                frame_slack_latched <= slack_now;
                frame_error_mask_latched <= final_error_mask_now;
                frame_stale_mask_latched <= missing_mask_now |
                    (stale_command_pending ? commanded_device_mask : 32'd0);
                frame_status_latched <= final_status_now |
                    STATUS_ERROR | STATUS_ABORTED;
                metadata_word_index <= 8'd0;
                state <= RT_COMMIT;
            end

            if (!(deadline_expired || (abort_flush && active))) begin
            case (state)
                RT_IDLE: begin
                    frame_cycles <= 32'd0;
                    if (enable || single_step) begin
                        single_step_pending <= single_step;
                        schedule_valid <= 1'b0;
                        schedule_overflow <= 1'b0;
                        schedule_config_error <= 1'b0;
                        schedule_budget_cycles <= FRAME_FIXED_CYCLES[31:0];
                        validation_index <= 8'd0;
                        validation_steps <= 8'd0;
                        validation_budget <= FRAME_FIXED_CYCLES;
                        validation_commanded_mask <= 32'd0;
                        descriptor_error_pending <= 1'b0;
                        for (lane = 0; lane < (DESCRIPTOR_WORDS/10); lane = lane + 1) begin
                            descriptor_period_counter[lane] <= 32'd0;
                        end
                        if (strict_timing_config_invalid) begin
                            single_step_pending <= 1'b0;
                            schedule_config_error <= 1'b1;
                            buffer_error <= 1'b1;
                            state <= RT_SCHED_ERROR;
                        end else if (descriptor_count == 8'd0) begin
                            schedule_valid <= 1'b1;
                            schedule_budget_cycles <= FRAME_FIXED_CYCLES[31:0];
                            schedule_commanded_mask <= 32'd0;
                            state <= RT_WAIT_FRAME;
                        end else begin
                            descriptor_load_word <= 4'd0;
                            descriptor_load_validation <= 1'b1;
                            state <= RT_DESC_READ;
                        end
                    end
                end

                RT_DESC_READ: begin
                    if (descriptor_read_address >= DESCRIPTOR_WORDS) begin
                        if (descriptor_load_validation) begin
                            schedule_config_error <= 1'b1;
                            buffer_error <= 1'b1;
                            state <= RT_SCHED_ERROR;
                        end else begin
                            frame_error_pending <= 1'b1;
                            buffer_error_pending <= 1'b1;
                            buffer_error <= 1'b1;
                            frame_done_timestamp_latched <= timestamp;
                            frame_cycles_latched <= frame_cycles;
                            frame_slack_latched <= slack_now;
                            frame_error_mask_latched <= final_error_mask_now;
                            frame_stale_mask_latched <= missing_mask_now;
                            frame_status_latched <= final_status_now |
                                STATUS_ERROR | STATUS_BUFFER_ERROR;
                            metadata_word_index <= 8'd0;
                            state <= RT_COMMIT;
                        end
                    end else begin
                        case (descriptor_load_word)
                            4'd0: desc_control <=
                                descriptor_mem[descriptor_read_address];
                            4'd1: desc_tx_offset <=
                                descriptor_mem[descriptor_read_address];
                            4'd2: desc_body_length <=
                                descriptor_mem[descriptor_read_address];
                            4'd3: desc_response_count <=
                                descriptor_mem[descriptor_read_address];
                            4'd4: desc_expected_mask <=
                                descriptor_mem[descriptor_read_address];
                            4'd5: desc_response_timeout <=
                                descriptor_mem[descriptor_read_address];
                            4'd6: desc_inter_byte_timeout <=
                                descriptor_mem[descriptor_read_address];
                            4'd7: desc_response_map_offset <=
                                descriptor_mem[descriptor_read_address];
                            4'd8: desc_period_divider <=
                                descriptor_mem[descriptor_read_address];
                            default: desc_next <=
                                descriptor_mem[descriptor_read_address];
                        endcase
                        if (descriptor_load_word == 4'd9) begin
                            descriptor_load_word <= 4'd0;
                            state <= descriptor_load_validation ?
                                RT_VALIDATE : RT_LOAD_DESC;
                        end else begin
                            descriptor_load_word <= descriptor_load_word + 4'd1;
                        end
                    end
                end

                RT_VALIDATE: begin
                    frame_cycles <= 32'd0;
                    if (!enable && !single_step_pending) begin
                        state <= RT_IDLE;
                    end else if ((validation_index >= descriptor_count) ||
                                 ({24'd0, validation_index} >= MAX_DESCRIPTOR_COUNT) ||
                                 (validation_steps >= descriptor_count) ||
                                 (!descriptor_chain_end &&
                                  (desc_next >= descriptor_count)) ||
                                 (descriptor_valid && descriptor_fields_invalid) ||
                                 ((validation_steps + 8'd1 >= descriptor_count) &&
                                  !descriptor_chain_end)) begin
                        schedule_config_error <= 1'b1;
                        buffer_error <= 1'b1;
                        state <= RT_SCHED_ERROR;
                    // A zero communication deadline selects best-effort mode:
                    // retain the computed budget for telemetry, but do not
                    // reject or abort a schedule against the frame cadence.
                    end else if (descriptor_valid &&
                                 (comm_deadline_cycles != 32'd0) &&
                                 (validation_budget + descriptor_budget_cycles >
                                  {32'd0, comm_deadline_cycles})) begin
                        schedule_budget_cycles <=
                            (validation_budget + descriptor_budget_cycles > 64'hFFFF_FFFF) ?
                            32'hFFFF_FFFF :
                            validation_budget[31:0] + descriptor_budget_cycles[31:0];
                        schedule_overflow <= 1'b1;
                        buffer_error <= 1'b1;
                        state <= RT_SCHED_ERROR;
                    end else begin
                        validation_steps <= validation_steps + 8'd1;
                        if (descriptor_valid) begin
                            validation_budget <=
                                validation_budget + descriptor_budget_cycles;
                            validation_commanded_mask <=
                                validation_commanded_mask | descriptor_command_mask;
                        end
                        if (descriptor_chain_end) begin
                            if (descriptor_valid &&
                                (validation_budget + descriptor_budget_cycles >
                                 64'hFFFF_FFFF)) begin
                                schedule_budget_cycles <= 32'hFFFF_FFFF;
                            end else if (!descriptor_valid &&
                                         (validation_budget >
                                          64'hFFFF_FFFF)) begin
                                schedule_budget_cycles <= 32'hFFFF_FFFF;
                            end else begin
                                schedule_budget_cycles <= descriptor_valid ?
                                    validation_budget[31:0] +
                                        descriptor_budget_cycles[31:0] :
                                    validation_budget[31:0];
                            end
                            schedule_commanded_mask <= descriptor_valid ?
                                validation_commanded_mask | descriptor_command_mask :
                                validation_commanded_mask;
                            schedule_valid <= 1'b1;
                            state <= RT_WAIT_FRAME;
                        end else begin
                            validation_index <= desc_next[7:0];
                            descriptor_load_word <= 4'd0;
                            state <= RT_DESC_READ;
                        end
                    end
                end

                RT_SCHED_ERROR: begin
                    frame_cycles <= 32'd0;
                    single_step_pending <= 1'b0;
                    if (!enable) begin
                        state <= RT_IDLE;
                    end
                end

                RT_WAIT_FRAME: begin
                    frame_cycles <= 32'd0;
                    if (!enable && !single_step_pending) begin
                        state <= RT_IDLE;
                    end else if (frame_trigger) begin
                        single_step_pending <= 1'b0;
                        frame_sequence <= frame_sequence + 32'd1;
                        frame_start_timestamp <= timestamp;
                        active_command_bank <= committed_command_bank;
                        active_command_sequence <= committed_command_sequence;
                        last_command_sequence <= committed_command_sequence;
                        last_command_valid <= command_commit_valid;
                        working_feedback_bank <= ~active_feedback_bank_reg;
                        descriptor_index <= 8'd0;
                        descriptor_steps <= 8'd0;
                        expected_device_mask <= 32'd0;
                        commanded_device_mask <= 32'd0;
                        received_device_mask <= 32'd0;
                        error_device_mask <= 32'd0;
                        stale_device_mask <= 32'd0;
                        stale_command_pending <=
                            !command_commit_valid || command_deadline_missed ||
                            late_command_commit ||
                            (last_command_valid &&
                             (committed_command_sequence == last_command_sequence));
                        frame_error_pending <=
                            !command_commit_valid || command_deadline_missed ||
                            late_command_commit ||
                            (last_command_valid &&
                             (committed_command_sequence == last_command_sequence));
                        command_deadline_missed <= 1'b0;
                        frame_deadline_pending <= 1'b0;
                        duplicate_pending <= 1'b0;
                        unexpected_id_pending <= 1'b0;
                        buffer_error_pending <= 1'b0;
                        rx_overrun_pending <= 1'b0;
                        abort_pending <= 1'b0;
                        descriptor_error_pending <= 1'b0;
                        frame_cycles <= 32'd1;
                        if (!command_commit_valid || (descriptor_count == 8'd0)) begin
                            commanded_device_mask <= schedule_commanded_mask;
                            frame_done_timestamp_latched <= timestamp;
                            frame_cycles_latched <= 32'd1;
                            frame_slack_latched <=
                                (comm_deadline_cycles > 32'd1) ?
                                comm_deadline_cycles - 32'd1 : 32'd0;
                            frame_error_mask_latched <= 32'd0;
                            frame_stale_mask_latched <= schedule_commanded_mask;
                            frame_status_latched <= STATUS_COMPLETE |
                                STATUS_ERROR | STATUS_STALE_COMMAND;
                            metadata_word_index <= 8'd0;
                            state <= RT_COMMIT;
                        end else begin
                            descriptor_load_validation <= 1'b0;
                            descriptor_load_word <= 4'd0;
                            state <= RT_DESC_READ;
                        end
                    end
                end

                RT_LOAD_DESC: begin
                    if ((descriptor_index >= descriptor_count) ||
                        (descriptor_steps >= descriptor_count)) begin
                        frame_error_pending <= 1'b1;
                        buffer_error_pending <= 1'b1;
                        buffer_error <= 1'b1;
                        frame_done_timestamp_latched <= timestamp;
                        frame_cycles_latched <= frame_cycles;
                        frame_slack_latched <= slack_now;
                        frame_error_mask_latched <= final_error_mask_now;
                        frame_stale_mask_latched <= missing_mask_now |
                            (stale_command_pending ? commanded_device_mask : 32'd0);
                        frame_status_latched <= final_status_now |
                            STATUS_ERROR | STATUS_BUFFER_ERROR;
                        metadata_word_index <= 8'd0;
                        state <= RT_COMMIT;
                    end else if (!descriptor_valid || !descriptor_due) begin
                        if (desc_period_divider <= 32'd1) begin
                            descriptor_period_counter[
                                descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] <= 32'd0;
                        end else if (descriptor_due) begin
                            descriptor_period_counter[
                                descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] <=
                                desc_period_divider - 32'd1;
                        end else begin
                            descriptor_period_counter[
                                descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] <=
                                descriptor_period_counter[
                                    descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] - 32'd1;
                        end
                        descriptor_steps <= descriptor_steps + 8'd1;
                        if ((desc_next == DESC_END) ||
                            (descriptor_steps + 8'd1 >= descriptor_count)) begin
                            frame_done_timestamp_latched <= timestamp;
                            frame_cycles_latched <= frame_cycles;
                            frame_slack_latched <= slack_now;
                            frame_error_mask_latched <= final_error_mask_now;
                            frame_stale_mask_latched <= missing_mask_now |
                                (stale_command_pending ? commanded_device_mask : 32'd0);
                            frame_status_latched <= final_status_now;
                            metadata_word_index <= 8'd0;
                            state <= RT_COMMIT;
                        end else begin
                            descriptor_index <= desc_next[7:0];
                            descriptor_load_word <= 4'd0;
                            state <= RT_DESC_READ;
                        end
                    end else if (descriptor_fields_invalid) begin
                        frame_error_pending <= 1'b1;
                        buffer_error_pending <= 1'b1;
                        buffer_error <= 1'b1;
                        frame_done_timestamp_latched <= timestamp;
                        frame_cycles_latched <= frame_cycles;
                        frame_slack_latched <= slack_now;
                        frame_error_mask_latched <= final_error_mask_now;
                        frame_stale_mask_latched <= missing_mask_now |
                            (stale_command_pending ? commanded_device_mask : 32'd0);
                        frame_status_latched <= final_status_now |
                            STATUS_ERROR | STATUS_BUFFER_ERROR;
                        metadata_word_index <= 8'd0;
                        state <= RT_COMMIT;
                    end else begin
                        descriptor_error_pending <= 1'b0;
                        if (desc_period_divider <= 32'd1) begin
                            descriptor_period_counter[
                                descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] <= 32'd0;
                        end else begin
                            descriptor_period_counter[
                                descriptor_index[DESC_COUNTER_INDEX_WIDTH-1:0]] <=
                                desc_period_divider - 32'd1;
                        end
                        if (desc_response_count != 32'd0) begin
                            expected_device_mask <=
                                expected_device_mask | desc_expected_mask;
                        end
                        commanded_device_mask <=
                            commanded_device_mask | descriptor_command_mask;
                        body_index <= 16'd0;
                        state <= RT_START_CMD;
                    end
                end

                RT_START_CMD: begin
                    if (cmd_valid && cmd_ready) begin
                        state <= RT_BODY_READ;
                    end
                end

                RT_BODY_READ: begin
                    if (active_body_word_address < (2 * COMMAND_WORDS)) begin
                        body_word <= command_mem[active_body_word_address];
                        state <= RT_STREAM_BODY;
                    end else begin
                        frame_error_pending <= 1'b1;
                        buffer_error_pending <= 1'b1;
                        buffer_error <= 1'b1;
                        core_abort <= 1'b1;
                        state <= RT_WAIT_TRANS;
                    end
                end

                RT_STREAM_BODY: begin
                    if (body_valid && body_ready) begin
                        body_index <= body_index + 16'd1;
                        if (body_index + 16'd1 >= desc_body_length[15:0]) begin
                            state <= RT_WAIT_TRANS;
                        end else if (active_body_byte_address[1:0] == 2'd3) begin
                            state <= RT_BODY_READ;
                        end
                    end
                end

                RT_WAIT_TRANS: begin
                    if (result_handshake) begin
                        parameter_index <= 16'd0;
                        parameter_base <= response_slot_offset[11:0];
                        parameter_drop <= response_invalid;
                        if (response_duplicate) begin
                            duplicate_pending <= 1'b1;
                            frame_error_pending <= 1'b1;
                        end else if (!response_expected) begin
                            unexpected_id_pending <= 1'b1;
                            frame_error_pending <= 1'b1;
                        end else begin
                            received_device_mask <=
                                received_device_mask | response_id_mask;
                        end
                        if (response_invalid) begin
                            error_device_mask <=
                                error_device_mask | response_id_mask;
                            frame_error_pending <= 1'b1;
                            descriptor_error_pending <= 1'b1;
                        end
                    end
                    if (parameter_handshake) begin
                        if (!parameter_drop) begin
                            case (feedback_write_byte_address[1:0])
                                2'd0: feedback_mem[feedback_write_word_address][7:0]
                                    <= parameter_data;
                                2'd1: feedback_mem[feedback_write_word_address][15:8]
                                    <= parameter_data;
                                2'd2: feedback_mem[feedback_write_word_address][23:16]
                                    <= parameter_data;
                                default:
                                    feedback_mem[feedback_write_word_address][31:24]
                                    <= parameter_data;
                            endcase
                        end else begin
                            frame_error_pending <= 1'b1;
                        end
                        parameter_index <= parameter_index + 16'd1;
                        if (parameter_last &&
                            (parameter_index + 16'd1 != parameter_length)) begin
                            frame_error_pending <= 1'b1;
                            error_device_mask <=
                                error_device_mask | response_id_mask;
                            descriptor_error_pending <= 1'b1;
                        end
                    end
                    if (transaction_done) begin
                        descriptor_steps <= descriptor_steps + 8'd1;
                        if (transaction_error) begin
                            frame_error_pending <= 1'b1;
                        end
                        if ((transaction_error || descriptor_error_pending ||
                             uart_rx_overrun_error) &&
                            descriptor_abort_on_error) begin
                            frame_done_timestamp_latched <= timestamp;
                            frame_cycles_latched <= frame_cycles;
                            frame_slack_latched <= slack_now;
                            frame_error_mask_latched <= final_error_mask_now;
                            frame_stale_mask_latched <= missing_mask_now |
                                (stale_command_pending ? commanded_device_mask : 32'd0);
                            frame_status_latched <= final_status_now |
                                STATUS_ERROR | STATUS_ABORTED;
                            metadata_word_index <= 8'd0;
                            state <= RT_COMMIT;
                        end else if ((desc_next == DESC_END) ||
                                     (descriptor_steps + 8'd1 >= descriptor_count)) begin
                            frame_done_timestamp_latched <= timestamp;
                            frame_cycles_latched <= frame_cycles;
                            frame_slack_latched <= slack_now;
                            frame_error_mask_latched <= final_error_mask_now;
                            frame_stale_mask_latched <= missing_mask_now |
                                (stale_command_pending ? commanded_device_mask : 32'd0);
                            frame_status_latched <= final_status_now |
                                (transaction_error ? STATUS_ERROR : 32'd0);
                            metadata_word_index <= 8'd0;
                            state <= RT_COMMIT;
                        end else begin
                            descriptor_index <= desc_next[7:0];
                            descriptor_load_word <= 4'd0;
                            state <= RT_DESC_READ;
                        end
                    end
                end

                RT_COMMIT: begin
                    feedback_mem[
                        (working_feedback_bank ? FEEDBACK_WORDS : 0) +
                        {24'd0, metadata_word_index}
                    ] <= metadata_word;
                    if (metadata_word_index == 8'd13) begin
                        active_feedback_bank_reg <= working_feedback_bank;
                        expected_device_mask <= expected_device_mask;
                        error_device_mask <= frame_error_mask_latched;
                        stale_device_mask <= frame_stale_mask_latched;
                        frame_done <= 1'b1;
                        frame_error <= frame_status_latched[1];
                        frame_deadline <= frame_status_latched[2];
                        if ((comm_deadline_cycles != 32'd0) &&
                            (frame_slack_latched < minimum_slack_cycles)) begin
                            minimum_slack_cycles <= frame_slack_latched;
                        end
                        state <= enable ? RT_WAIT_FRAME : RT_IDLE;
                    end else begin
                        metadata_word_index <= metadata_word_index + 8'd1;
                    end
                end

                default: begin
                    core_abort <= 1'b1;
                    state <= RT_IDLE;
                end
            endcase
            end
        end
    end

endmodule
