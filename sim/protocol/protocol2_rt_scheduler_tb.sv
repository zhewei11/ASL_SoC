`include "rtos_core_config.svh"

module protocol2_rt_scheduler_tb #(
     parameter int unsigned FAST_FRAME_PERIOD = 100
    ,parameter int unsigned FAST_FRAME_COUNT = 10_000
    ,parameter int unsigned REAL_FRAME_COUNT = 2
);

    logic clk;
    logic rst;
    logic enable;
    logic single_step;
    logic abort_flush;
    logic command_commit;
    logic command_commit_bank;
    logic [31:0] command_commit_sequence;
    logic cpu_mem_valid;
    logic cpu_mem_write;
    logic [2:0] cpu_mem_region;
    logic [11:0] cpu_mem_byte_addr;
    logic [31:0] cpu_mem_wdata;
    logic [3:0] cpu_mem_wstrb;
    logic [31:0] cpu_mem_rdata;
    logic cpu_mem_ready;
    logic cpu_mem_write_blocked;
    logic cmd_valid;
    logic body_valid;
    logic [7:0] body_data;
    logic transaction_done;
    logic core_abort;
    logic active;
    logic frame_done;
    logic frame_error;
    logic frame_deadline;
    logic buffer_error;
    logic active_command_bank;
    logic active_feedback_bank;
    logic committed_command_bank;
    logic [31:0] frame_sequence;
    logic [31:0] frame_cycles;
    logic [31:0] minimum_slack_cycles;
    logic [31:0] expected_device_mask;
    logic [31:0] received_device_mask;
    logic [31:0] error_device_mask;
    logic [31:0] stale_device_mask;
    logic [31:0] commanded_device_mask;
    logic schedule_valid;
    logic schedule_overflow;
    logic schedule_config_error;
    logic late_command_commit;
    logic [31:0] schedule_budget_cycles;
    logic [1:0] command_bank_locked;
    logic [63:0] timestamp;
    logic [31:0] test_frame_period;
    logic [31:0] expected_frame_period;
    logic [31:0] phase_start_sequence;

    integer done_count;
    integer trigger_count;
    integer body_byte_index;
    logic [31:0] previous_sequence;
    logic [63:0] previous_trigger_timestamp;

    protocol2_rt_engine #(
         .COMMAND_BYTES    (64)
        ,.FEEDBACK_BYTES   (64)
        ,.DESCRIPTOR_WORDS (10)
        ,.MAX_BODY_BYTES   (16)
        ,.TX_FIXED_CYCLES  (0)
    ) dut (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.enable                    (enable)
        ,.single_step               (single_step)
        ,.abort_flush               (abort_flush)
        ,.frame_tick                (1'b0)
        ,.frame_period_cycles       (test_frame_period)
        ,.comm_deadline_cycles      (32'd90)
        ,.command_deadline_cycles   (32'd95)
        ,.wire_byte_cycles          (32'd1)
        ,.descriptor_count          (8'd1)
        ,.command_commit            (command_commit)
        ,.command_commit_bank       (command_commit_bank)
        ,.command_commit_sequence   (command_commit_sequence)
        ,.cpu_mem_valid             (cpu_mem_valid)
        ,.cpu_mem_write             (cpu_mem_write)
        ,.cpu_mem_region            (cpu_mem_region)
        ,.cpu_mem_byte_addr         (cpu_mem_byte_addr)
        ,.cpu_mem_wdata             (cpu_mem_wdata)
        ,.cpu_mem_wstrb             (cpu_mem_wstrb)
        ,.cpu_mem_ready             (cpu_mem_ready)
        ,.cpu_mem_rdata             (cpu_mem_rdata)
        ,.cpu_mem_write_blocked     (cpu_mem_write_blocked)
        ,.cmd_valid                 (cmd_valid)
        ,.cmd_ready                 (1'b1)
        ,.cmd_id                    ()
        ,.cmd_body_len              ()
        ,.cmd_expected_id           ()
        ,.cmd_response_count        ()
        ,.response_timeout_cycles   ()
        ,.inter_byte_timeout_cycles ()
        ,.body_valid                (body_valid)
        ,.body_ready                (1'b1)
        ,.body_data                 (body_data)
        ,.result_valid              (1'b0)
        ,.result_ready              ()
        ,.result_index              (8'd0)
        ,.result_code               (8'd0)
        ,.response_id               (8'd0)
        ,.dynamixel_error           (8'd0)
        ,.parameter_length          (16'd0)
        ,.parameter_valid           (1'b0)
        ,.parameter_ready           ()
        ,.parameter_data            (8'd0)
        ,.parameter_last            (1'b0)
        ,.transaction_busy          (1'b0)
        ,.transaction_done          (transaction_done)
        ,.transaction_error         (1'b0)
        ,.uart_rx_overrun_error     (1'b0)
        ,.core_abort                (core_abort)
        ,.active                    (active)
        ,.frame_done                (frame_done)
        ,.frame_error               (frame_error)
        ,.frame_deadline            (frame_deadline)
        ,.buffer_error              (buffer_error)
        ,.active_command_bank       (active_command_bank)
        ,.active_feedback_bank      (active_feedback_bank)
        ,.committed_command_bank    (committed_command_bank)
        ,.frame_sequence            (frame_sequence)
        ,.frame_cycles              (frame_cycles)
        ,.last_frame_cycles         ()
        ,.minimum_slack_cycles      (minimum_slack_cycles)
        ,.expected_device_mask      (expected_device_mask)
        ,.received_device_mask      (received_device_mask)
        ,.error_device_mask         (error_device_mask)
        ,.stale_device_mask         (stale_device_mask)
        ,.commanded_device_mask     (commanded_device_mask)
        ,.schedule_valid            (schedule_valid)
        ,.schedule_overflow         (schedule_overflow)
        ,.schedule_config_error     (schedule_config_error)
        ,.late_command_commit       (late_command_commit)
        ,.schedule_budget_cycles    (schedule_budget_cycles)
        ,.command_bank_locked       (command_bank_locked)
        ,.timestamp                 (timestamp)
    );

    always #5 clk = ~clk;

    // No-response transaction model: complete one cycle after the final body
    // byte handshake, when the scheduler has entered RT_WAIT_TRANS.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            transaction_done <= 1'b0;
        end else begin
            transaction_done <= body_valid;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            done_count <= 0;
            trigger_count <= 0;
            body_byte_index <= 0;
            previous_sequence <= 32'd0;
            previous_trigger_timestamp <= 64'd0;
        end else begin
            if (cmd_valid) begin
                body_byte_index <= 0;
            end
            if (body_valid) begin
                case (body_byte_index)
                    0: if (body_data !== 8'h22) $fatal(1, "body byte 0 mismatch");
                    1: if (body_data !== 8'h33) $fatal(1, "body byte 1 mismatch");
                    2: if (body_data !== 8'h44) $fatal(1, "body byte 2 mismatch");
                    3: if (body_data !== 8'h55) $fatal(1, "body byte 3 mismatch");
                    4: if (body_data !== 8'h66) $fatal(1, "body byte 4 mismatch");
                    default: $fatal(1, "unexpected extra body byte");
                endcase
                body_byte_index <= body_byte_index + 1;
            end
            if (frame_done) begin
                done_count <= done_count + 1;
            end
            if (frame_sequence != previous_sequence) begin
                if ((frame_sequence > phase_start_sequence + 32'd1) &&
                    (timestamp - previous_trigger_timestamp !=
                     {32'd0, expected_frame_period})) begin
                    $fatal(1, "frame interval changed: expected %0d, got %0d",
                           expected_frame_period,
                           timestamp - previous_trigger_timestamp);
                end
                previous_sequence <= frame_sequence;
                previous_trigger_timestamp <= timestamp;
                trigger_count <= trigger_count + 1;
            end
        end
    end

    task automatic write_memory(
         input logic [2:0] region
        ,input logic [11:0] address
        ,input logic [31:0] data
    );
        begin
            @(negedge clk);
            cpu_mem_region = region;
            cpu_mem_byte_addr = address;
            cpu_mem_wdata = data;
            cpu_mem_wstrb = 4'hF;
            cpu_mem_write = 1'b1;
            cpu_mem_valid = 1'b1;
            while (!cpu_mem_ready) begin
                @(negedge clk);
            end
            @(negedge clk);
            cpu_mem_valid = 1'b0;
            cpu_mem_write = 1'b0;
        end
    endtask

    initial begin
        integer watchdog;
        clk = 1'b0;
        rst = 1'b1;
        enable = 1'b0;
        single_step = 1'b0;
        abort_flush = 1'b0;
        command_commit = 1'b0;
        command_commit_bank = 1'b0;
        command_commit_sequence = 32'd1;
        cpu_mem_valid = 1'b0;
        cpu_mem_write = 1'b0;
        cpu_mem_region = 3'd0;
        cpu_mem_byte_addr = 12'd0;
        cpu_mem_wdata = 32'd0;
        cpu_mem_wstrb = 4'd0;
        test_frame_period = 32'd100_000;
        expected_frame_period = 32'd100_000;
        phase_start_sequence = 32'd0;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        // Five bytes beginning at an unaligned offset cross a 32-bit SRAM
        // word boundary and exercise the synchronous command word cache.
        write_memory(3'd0, 12'd0, 32'h4433_2211);
        write_memory(3'd0, 12'd4, 32'h8877_6655);
        write_memory(3'd4, 12'd0, 32'h0000_0103);
        write_memory(3'd4, 12'd4, 32'd1);
        write_memory(3'd4, 12'd8, 32'd5);
        write_memory(3'd4, 12'd12, 32'd0);
        write_memory(3'd4, 12'd16, 32'd1);
        write_memory(3'd4, 12'd20, 32'd0);
        write_memory(3'd4, 12'd24, 32'd0);
        write_memory(3'd4, 12'd28, 32'd0);
        write_memory(3'd4, 12'd32, 32'd1);
        write_memory(3'd4, 12'd36, 32'hFFFF_FFFF);

        @(negedge clk);
        command_commit = 1'b1;
        @(negedge clk);
        command_commit = 1'b0;
        enable = 1'b1;

        // Exercise the actual 100 MHz / 1 kHz period before the accelerated
        // long-run phase.
        watchdog = 0;
        while (done_count < REAL_FRAME_COUNT) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (watchdog > (REAL_FRAME_COUNT + 1) * 200_000) begin
                $fatal(1, "default 1 kHz scheduler interval timed out");
            end
        end
        enable = 1'b0;
        repeat (4) @(negedge clk);
        test_frame_period = FAST_FRAME_PERIOD;
        expected_frame_period = FAST_FRAME_PERIOD;
        phase_start_sequence = frame_sequence;
        enable = 1'b1;

        watchdog = 0;
        while (done_count < FAST_FRAME_COUNT + REAL_FRAME_COUNT) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (watchdog > (FAST_FRAME_COUNT + 1) * FAST_FRAME_PERIOD * 2) begin
                $fatal(1, "accelerated scheduler regression timed out");
            end
        end

        enable = 1'b0;
        @(negedge clk);
        if (frame_sequence != FAST_FRAME_COUNT + REAL_FRAME_COUNT ||
            trigger_count != FAST_FRAME_COUNT + REAL_FRAME_COUNT ||
            done_count != FAST_FRAME_COUNT + REAL_FRAME_COUNT) begin
            $fatal(1, "frame accounting mismatch: seq=%0d trigger=%0d done=%0d",
                   frame_sequence, trigger_count, done_count);
        end
        if (!schedule_valid || schedule_overflow || schedule_config_error ||
            frame_deadline || buffer_error) begin
            $fatal(1, "scheduler status failed after long regression");
        end
        $display("[PROTOCOL2 RT SCHEDULER PASS] %0d frames at 100000 cycles and %0d frames at %0d cycles",
                 REAL_FRAME_COUNT, FAST_FRAME_COUNT, FAST_FRAME_PERIOD);
        $finish;
    end

endmodule
