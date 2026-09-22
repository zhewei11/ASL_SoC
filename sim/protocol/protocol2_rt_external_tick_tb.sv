`include "rtos_core_config.svh"

module protocol2_rt_external_tick_tb;

    logic clk;
    logic rst;
    logic enable;
    logic frame_tick;
    logic frame_done;
    logic frame_error;
    logic active_feedback_bank;
    logic schedule_valid;
    logic [31:0] frame_sequence;

    protocol2_rt_engine #(
         .COMMAND_BYTES          (64)
        ,.FEEDBACK_BYTES         (64)
        ,.DESCRIPTOR_WORDS       (10)
        ,.MAX_BODY_BYTES         (16)
        ,.MAX_STUFFED_BODY_BYTES (32)
        ,.TX_FIXED_CYCLES        (0)
        ,.USE_EXTERNAL_FRAME_TICK(1'b1)
    ) dut (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.enable                    (enable)
        ,.single_step               (1'b0)
        ,.abort_flush               (1'b0)
        ,.frame_tick                (frame_tick)
        ,.frame_period_cycles       (32'd8)
        ,.comm_deadline_cycles      (32'd0)
        ,.command_deadline_cycles   (32'd0)
        ,.wire_byte_cycles          (32'd1)
        ,.descriptor_count          (8'd0)
        ,.command_commit            (1'b0)
        ,.command_commit_bank       (1'b0)
        ,.command_commit_sequence   (32'd0)
        ,.cpu_mem_valid             (1'b0)
        ,.cpu_mem_write             (1'b0)
        ,.cpu_mem_region            (3'd0)
        ,.cpu_mem_byte_addr         (12'd0)
        ,.cpu_mem_wdata             (32'd0)
        ,.cpu_mem_wstrb             (4'd0)
        ,.cpu_mem_ready             ()
        ,.cpu_mem_rdata             ()
        ,.cpu_mem_write_blocked     ()
        ,.cmd_valid                 ()
        ,.cmd_ready                 (1'b1)
        ,.cmd_id                    ()
        ,.cmd_body_len              ()
        ,.cmd_expected_id           ()
        ,.cmd_response_count        ()
        ,.response_timeout_cycles   ()
        ,.inter_byte_timeout_cycles ()
        ,.body_valid                ()
        ,.body_ready                (1'b1)
        ,.body_data                 ()
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
        ,.transaction_done          (1'b0)
        ,.transaction_error         (1'b0)
        ,.uart_rx_overrun_error     (1'b0)
        ,.core_abort                ()
        ,.active                    ()
        ,.frame_done                (frame_done)
        ,.frame_error               (frame_error)
        ,.frame_deadline            ()
        ,.buffer_error              ()
        ,.active_command_bank       ()
        ,.active_feedback_bank      (active_feedback_bank)
        ,.committed_command_bank    ()
        ,.frame_sequence            (frame_sequence)
        ,.frame_cycles              ()
        ,.last_frame_cycles         ()
        ,.minimum_slack_cycles      ()
        ,.expected_device_mask      ()
        ,.received_device_mask      ()
        ,.error_device_mask         ()
        ,.stale_device_mask         ()
        ,.commanded_device_mask     ()
        ,.schedule_valid            (schedule_valid)
        ,.schedule_overflow         ()
        ,.schedule_config_error     ()
        ,.late_command_commit       ()
        ,.schedule_budget_cycles    ()
        ,.command_bank_locked       ()
        ,.timestamp                 ()
    );

    always #5 clk = ~clk;

    task automatic pulse_frame_tick;
        begin
            @(negedge clk);
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
        end
    endtask

    task automatic wait_for_frame(input logic [31:0] expected_sequence);
        integer watchdog;
        begin
            watchdog = 0;
            while (!frame_done) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100) begin
                    $fatal(1, "External-tick frame did not complete");
                end
            end
            if (frame_sequence != expected_sequence || !frame_error) begin
                $fatal(1,
                       "External-tick frame metadata mismatch: sequence=%0d error=%0d",
                       frame_sequence, frame_error);
            end
        end
    endtask

    initial begin
        logic previous_feedback_bank;

        clk = 1'b0;
        rst = 1'b1;
        enable = 1'b0;
        frame_tick = 1'b0;

        repeat (4) @(negedge clk);
        rst = 1'b0;
        enable = 1'b1;

        while (!schedule_valid) begin
            @(negedge clk);
        end

        // The internal period is deliberately only eight clocks. In external
        // mode no frame may start until the shared SoC tick arrives.
        repeat (40) @(negedge clk);
        if (frame_sequence != 32'd0) begin
            $fatal(1, "Internal timer started an externally-clocked frame");
        end

        previous_feedback_bank = active_feedback_bank;
        pulse_frame_tick();
        wait_for_frame(32'd1);
        if (active_feedback_bank == previous_feedback_bank) begin
            $fatal(1, "First external-tick frame did not commit feedback bank");
        end

        repeat (40) @(negedge clk);
        if (frame_sequence != 32'd1) begin
            $fatal(1, "Frame repeated without another external tick");
        end

        previous_feedback_bank = active_feedback_bank;
        pulse_frame_tick();
        wait_for_frame(32'd2);
        if (active_feedback_bank == previous_feedback_bank) begin
            $fatal(1, "Second external-tick frame did not alternate bank");
        end

        $display("[PROTOCOL2 EXTERNAL TICK PASS] shared frame tick controls RT cadence");
        $finish;
    end

endmodule
