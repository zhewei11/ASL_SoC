module protocol2_hx5_rt_sequencer_tb;

    localparam int unsigned COMMAND_BYTES = 64;
    localparam int unsigned FEEDBACK_BYTES = 64;
    localparam int unsigned COMMAND_WORDS = COMMAND_BYTES / 4;
    localparam int unsigned FEEDBACK_WORDS = FEEDBACK_BYTES / 4;

    logic clk = 1'b0;
    logic rst;
    logic enable;
    logic single_step;
    logic abort_flush;
    logic [7:0] descriptor_count;
    logic command_commit;
    logic command_commit_bank;
    logic [31:0] command_commit_sequence;
    logic cpu_mem_valid;
    logic cpu_mem_write;
    logic [2:0] cpu_mem_region;
    logic [11:0] cpu_mem_byte_addr;
    logic [31:0] cpu_mem_wdata;
    logic [3:0] cpu_mem_wstrb;
    logic cpu_mem_ready;
    logic [31:0] cpu_mem_rdata;
    logic cpu_mem_write_blocked;
    logic cmd_valid;
    logic cmd_ready;
    logic [7:0] cmd_id;
    logic [15:0] cmd_body_len;
    logic [7:0] cmd_expected_id;
    logic [7:0] cmd_response_count;
    logic body_valid;
    logic body_ready;
    logic [7:0] body_data;
    logic result_valid;
    logic result_ready;
    logic [7:0] result_index;
    logic [7:0] result_code;
    logic [7:0] response_id;
    logic [7:0] dynamixel_error;
    logic [15:0] parameter_length;
    logic parameter_valid;
    logic parameter_ready;
    logic [7:0] parameter_data;
    logic parameter_last;
    logic transaction_done;
    logic transaction_error;
    logic frame_done;
    logic frame_error;
    logic active_feedback_bank;
    logic [31:0] frame_sequence;
    logic schedule_valid;
    logic schedule_config_error;
    integer checks;

    protocol2_hx5_rt_sequencer #(
         .COMMAND_BYTES          (COMMAND_BYTES)
        ,.FEEDBACK_BYTES         (FEEDBACK_BYTES)
        ,.WRITE_BODY_OFFSET      (0)
        ,.WRITE_BODY_BYTES       (5)
        ,.READ_BODY_OFFSET       (8)
        ,.READ_BODY_BYTES        (5)
        ,.FEEDBACK_PAYLOAD_OFFSET(56)
        ,.FEEDBACK_PAYLOAD_BYTES (4)
    ) dut (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.enable                    (enable)
        ,.single_step               (single_step)
        ,.abort_flush               (abort_flush)
        ,.frame_tick                (1'b0)
        ,.frame_period_cycles       (32'd1000)
        ,.comm_deadline_cycles      (32'd0)
        ,.command_deadline_cycles   (32'd0)
        ,.descriptor_count          (descriptor_count)
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
        ,.cmd_ready                 (cmd_ready)
        ,.cmd_id                    (cmd_id)
        ,.cmd_body_len              (cmd_body_len)
        ,.cmd_expected_id           (cmd_expected_id)
        ,.cmd_response_count        (cmd_response_count)
        ,.response_timeout_cycles   ()
        ,.inter_byte_timeout_cycles ()
        ,.body_valid                (body_valid)
        ,.body_ready                (body_ready)
        ,.body_data                 (body_data)
        ,.result_valid              (result_valid)
        ,.result_ready              (result_ready)
        ,.result_index              (result_index)
        ,.result_code               (result_code)
        ,.response_id               (response_id)
        ,.dynamixel_error           (dynamixel_error)
        ,.parameter_length          (parameter_length)
        ,.parameter_valid           (parameter_valid)
        ,.parameter_ready           (parameter_ready)
        ,.parameter_data            (parameter_data)
        ,.parameter_last            (parameter_last)
        ,.transaction_busy          (1'b0)
        ,.transaction_done          (transaction_done)
        ,.transaction_error         (transaction_error)
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
        ,.schedule_config_error     (schedule_config_error)
        ,.late_command_commit       ()
        ,.schedule_budget_cycles    ()
        ,.command_bank_locked       ()
        ,.timestamp                 ()
    );

    always #5 clk = ~clk;

    task automatic check_condition(
         input logic condition
        ,input string message
    );
        begin
            if (!condition) begin
                $fatal(1, "%s", message);
            end
            checks = checks + 1;
        end
    endtask

    task automatic memory_write(
         input logic [2:0] region
        ,input logic [11:0] byte_address
        ,input logic [31:0] value
    );
        begin
            @(negedge clk);
            cpu_mem_region = region;
            cpu_mem_byte_addr = byte_address;
            cpu_mem_wdata = value;
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

    task automatic accept_command(
         input logic [7:0] expected_id
        ,input integer expected_length
        ,input logic [7:0] byte_0
        ,input logic [7:0] byte_1
        ,input logic [7:0] byte_2
        ,input logic [7:0] byte_3
        ,input logic [7:0] byte_4
    );
        logic [7:0] expected_byte;
        integer byte_index;
        integer watchdog;
        begin
            watchdog = 0;
            while (!cmd_valid) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100) begin
                    $fatal(1, "command request timeout");
                end
            end
            check_condition(cmd_id == expected_id, "command ID mismatch");
            check_condition(
                cmd_body_len == expected_length,
                "command length mismatch"
            );

            for (byte_index = 0;
                 byte_index < expected_length;
                 byte_index = byte_index + 1) begin
                watchdog = 0;
                while (!body_valid) begin
                    @(negedge clk);
                    watchdog = watchdog + 1;
                    if (watchdog > 100) begin
                        $fatal(1, "body byte timeout");
                    end
                end

                case (byte_index)
                    0: expected_byte = byte_0;
                    1: expected_byte = byte_1;
                    2: expected_byte = byte_2;
                    3: expected_byte = byte_3;
                    default: expected_byte = byte_4;
                endcase
                check_condition(body_data == expected_byte, "body mismatch");
                @(negedge clk);
            end
        end
    endtask

    task automatic pulse_transaction_done;
        begin
            transaction_done = 1'b1;
            @(negedge clk);
            transaction_done = 1'b0;
        end
    endtask

    initial begin
        integer watchdog;
        integer parameter_index_loop;
        logic [31:0] payload_word;
        logic [31:0] status_word;

        rst = 1'b1;
        enable = 1'b0;
        single_step = 1'b0;
        abort_flush = 1'b0;
        descriptor_count = 8'd0;
        command_commit = 1'b0;
        command_commit_bank = 1'b0;
        command_commit_sequence = 32'd1;
        cpu_mem_valid = 1'b0;
        cpu_mem_write = 1'b0;
        cpu_mem_region = 3'd0;
        cpu_mem_byte_addr = 12'd0;
        cpu_mem_wdata = 32'd0;
        cpu_mem_wstrb = 4'd0;
        cmd_ready = 1'b1;
        body_ready = 1'b1;
        result_valid = 1'b0;
        result_index = 8'd0;
        result_code = 8'd0;
        response_id = 8'd110;
        dynamixel_error = 8'd0;
        parameter_length = 16'd4;
        parameter_valid = 1'b0;
        parameter_data = 8'd0;
        parameter_last = 1'b0;
        transaction_done = 1'b0;
        transaction_error = 1'b0;
        checks = 0;

        repeat (4) @(negedge clk);
        rst = 1'b0;

        check_condition(!schedule_valid, "empty profile accepted");

        memory_write(3'd0, 12'd0, 32'h4433_2211);
        memory_write(3'd0, 12'd4, 32'h0000_0055);
        memory_write(3'd0, 12'd8, 32'h0402_7A02);
        memory_write(3'd0, 12'd12, 32'h0000_0000);

        // Compatibility descriptor 1 control/timeout words. The generic
        // descriptor body is intentionally not stored by the fixed sequencer.
        memory_write(3'd4, 12'd40, 32'h0004_6E03);
        memory_write(3'd4, 12'd60, 32'd100);
        memory_write(3'd4, 12'd64, 32'd10);
        descriptor_count = 8'd2;
        #1;
        check_condition(schedule_valid, "valid HX5 profile rejected");
        check_condition(!schedule_config_error, "profile reports error");

        @(negedge clk);
        command_commit = 1'b1;
        @(negedge clk);
        command_commit = 1'b0;
        single_step = 1'b1;
        @(negedge clk);
        single_step = 1'b0;

        accept_command(
            8'hFE, 5, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55
        );
        check_condition(
            cmd_response_count == 8'd0,
            "Sync Write requested a response"
        );
        pulse_transaction_done();

        accept_command(
            8'd110, 5, 8'h02, 8'h7A, 8'h02, 8'h04, 8'h00
        );
        check_condition(
            cmd_expected_id == 8'd110,
            "Read expected ID mismatch"
        );
        check_condition(
            cmd_response_count == 8'd1,
            "Read response count mismatch"
        );

        result_valid = 1'b1;
        while (!result_ready) begin
            @(negedge clk);
        end
        @(negedge clk);
        result_valid = 1'b0;

        for (parameter_index_loop = 0;
             parameter_index_loop < 4;
             parameter_index_loop = parameter_index_loop + 1) begin
            parameter_valid = 1'b1;
            parameter_data = 8'hA0 + parameter_index_loop;
            parameter_last = (parameter_index_loop == 3);
            while (!parameter_ready) begin
                @(negedge clk);
            end
            @(negedge clk);
        end
        parameter_valid = 1'b0;
        parameter_last = 1'b0;
        pulse_transaction_done();

        watchdog = 0;
        while (!frame_done) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (watchdog > 100) begin
                $fatal(1, "frame completion timeout");
            end
        end

        check_condition(!frame_error, "valid frame reported an error");
        check_condition(frame_sequence == 32'd1, "frame sequence mismatch");
        check_condition(active_feedback_bank, "feedback bank did not swap");

        payload_word = dut.feedback_mem[FEEDBACK_WORDS + 14];
        status_word = dut.feedback_mem[FEEDBACK_WORDS + 10];
        check_condition(
            payload_word == 32'hA3A2_A1A0,
            "feedback payload mismatch"
        );
        check_condition(status_word == 32'h0000_0001, "status mismatch");
        check_condition(
            dut.feedback_mem[FEEDBACK_WORDS] ==
            dut.feedback_mem[FEEDBACK_WORDS + 13],
            "atomic feedback sequence mismatch"
        );

        // A second step without a new command commit must not retransmit the
        // previous command. It is committed as a stale frame instead.
        single_step = 1'b1;
        @(negedge clk);
        single_step = 1'b0;
        watchdog = 0;
        while (!frame_done) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (cmd_valid) begin
                $fatal(1, "stale frame retransmitted a command");
            end
            if (watchdog > 100) begin
                $fatal(1, "stale frame completion timeout");
            end
        end
        check_condition(frame_error, "stale frame was not rejected");

        $display("[HX5 RT SEQUENCER PASS] %0d checks", checks);
        $finish;
    end

endmodule
