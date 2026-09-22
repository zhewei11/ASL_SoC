`include "rtos_core_config.svh"

module protocol2_rt_safety_tb;
    logic clk = 1'b0;
    logic rst;
    logic enable;
    logic single_step;
    logic abort_flush;
    logic [31:0] comm_deadline;
    logic command_commit;
    logic cpu_mem_valid;
    logic cpu_mem_write;
    logic [2:0] cpu_mem_region;
    logic [11:0] cpu_mem_byte_addr;
    logic [31:0] cpu_mem_wdata;
    logic [3:0] cpu_mem_wstrb;
    logic cpu_mem_ready;
    logic [31:0] cpu_mem_rdata;
    logic cmd_ready;
    logic body_ready;
    logic transaction_done;
    logic core_abort;
    logic active;
    logic frame_done;
    logic frame_error;
    logic schedule_valid;
    logic schedule_overflow;
    logic schedule_config_error;
    logic [31:0] schedule_budget_cycles;
    logic [31:0] frame_sequence;
    logic [31:0] frame_cycles;
    logic [31:0] last_frame_cycles;
    integer checks;
    logic saw_core_abort;

    protocol2_rt_engine #(
        .COMMAND_BYTES(64), .FEEDBACK_BYTES(64),
        .DESCRIPTOR_WORDS(10), .MAX_BODY_BYTES(16),
        .TX_FIXED_CYCLES(0)
    ) dut (
        .clk(clk), .rst(rst), .enable(enable), .single_step(single_step),
        .abort_flush(abort_flush), .frame_period_cycles(32'd1_000_000),
        .frame_tick(1'b0),
        .comm_deadline_cycles(comm_deadline),
        .command_deadline_cycles(32'd900_000), .wire_byte_cycles(32'd1),
        .descriptor_count(8'd1), .command_commit(command_commit),
        .command_commit_bank(1'b0), .command_commit_sequence(32'd1),
        .cpu_mem_valid(cpu_mem_valid), .cpu_mem_write(cpu_mem_write),
        .cpu_mem_region(cpu_mem_region), .cpu_mem_byte_addr(cpu_mem_byte_addr),
        .cpu_mem_wdata(cpu_mem_wdata), .cpu_mem_wstrb(cpu_mem_wstrb),
        .cpu_mem_ready(cpu_mem_ready), .cpu_mem_rdata(cpu_mem_rdata),
        .cpu_mem_write_blocked(), .cmd_valid(), .cmd_ready(cmd_ready),
        .cmd_id(), .cmd_body_len(), .cmd_expected_id(), .cmd_response_count(),
        .response_timeout_cycles(), .inter_byte_timeout_cycles(),
        .body_valid(), .body_ready(body_ready), .body_data(),
        .result_valid(1'b0), .result_ready(), .result_index(8'd0),
        .result_code(8'd0), .response_id(8'd0), .dynamixel_error(8'd0),
        .parameter_length(16'd0), .parameter_valid(1'b0),
        .parameter_ready(), .parameter_data(8'd0), .parameter_last(1'b0),
        .transaction_busy(1'b0), .transaction_done(transaction_done),
        .transaction_error(1'b0), .uart_rx_overrun_error(1'b0),
        .core_abort(core_abort), .active(active), .frame_done(frame_done),
        .frame_error(frame_error), .frame_deadline(), .buffer_error(),
        .active_command_bank(), .active_feedback_bank(),
        .committed_command_bank(), .frame_sequence(frame_sequence),
        .frame_cycles(frame_cycles), .last_frame_cycles(last_frame_cycles),
        .minimum_slack_cycles(), .expected_device_mask(),
        .received_device_mask(), .error_device_mask(), .stale_device_mask(),
        .commanded_device_mask(), .schedule_valid(schedule_valid),
        .schedule_overflow(schedule_overflow),
        .schedule_config_error(schedule_config_error),
        .late_command_commit(), .schedule_budget_cycles(schedule_budget_cycles),
        .command_bank_locked(), .timestamp()
    );

`ifdef PROTOCOL2_RT_SVA
    protocol2_rt_assertions u_rt_assertions (
        .clk(clk), .rst(rst), .active(active), .abort_flush(abort_flush),
        .core_abort(core_abort), .cmd_valid(dut.cmd_valid),
        .frame_done(frame_done), .frame_error(frame_error),
        .frame_deadline(dut.frame_deadline),
        .active_command_bank(dut.active_command_bank),
        .active_feedback_bank(dut.active_feedback_bank),
        .last_frame_cycles(last_frame_cycles), .schedule_valid(schedule_valid),
        .schedule_overflow(schedule_overflow),
        .schedule_config_error(schedule_config_error),
        .command_bank_locked(dut.command_bank_locked)
    );
`endif

    always #5 clk = ~clk;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) saw_core_abort <= 1'b0;
        else if (core_abort) saw_core_abort <= 1'b1;
    end

    task automatic mem_write(
        input logic [2:0] region,
        input logic [11:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            cpu_mem_region = region;
            cpu_mem_byte_addr = address;
            cpu_mem_wdata = data;
            cpu_mem_wstrb = 4'hf;
            cpu_mem_write = 1'b1;
            cpu_mem_valid = 1'b1;
            while (!cpu_mem_ready) @(negedge clk);
            @(negedge clk);
            cpu_mem_valid = 1'b0;
            cpu_mem_write = 1'b0;
        end
    endtask

    task automatic configure;
        begin
            mem_write(3'd0, 12'd0, 32'h5544_3322);
            mem_write(3'd0, 12'd4, 32'h0000_0066);
            mem_write(3'd4, 12'd0, 32'h0000_0103);
            mem_write(3'd4, 12'd4, 32'd0);
            mem_write(3'd4, 12'd8, 32'd5);
            mem_write(3'd4, 12'd12, 32'd0);
            mem_write(3'd4, 12'd16, 32'd0);
            mem_write(3'd4, 12'd20, 32'd0);
            mem_write(3'd4, 12'd24, 32'd0);
            mem_write(3'd4, 12'd28, 32'd0);
            mem_write(3'd4, 12'd32, 32'd1);
            mem_write(3'd4, 12'd36, 32'hffff_ffff);
            @(negedge clk); command_commit = 1'b1;
            @(negedge clk); command_commit = 1'b0;
        end
    endtask

    task automatic pulse_single_step;
        begin
            @(negedge clk); single_step = 1'b1;
            @(negedge clk); single_step = 1'b0;
        end
    endtask

    task automatic abort_state(input logic [3:0] target_state);
        integer watchdog;
        begin
            rst = 1'b1;
            enable = 1'b0;
            single_step = 1'b0;
            abort_flush = 1'b0;
            cmd_ready = 1'b1;
            body_ready = 1'b1;
            transaction_done = 1'b0;
            repeat (3) @(negedge clk);
            rst = 1'b0;
            configure();
            if (target_state == 4'd4) cmd_ready = 1'b0;
            if (target_state == 4'd5) body_ready = 1'b0;
            pulse_single_step();
            watchdog = 0;
            while (!((dut.state == target_state) && active)) begin
                if ((target_state == 4'd7) && (dut.state == 4'd6))
                    transaction_done = 1'b1;
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 300) $fatal(1, "State %0d not reached", target_state);
            end
            transaction_done = 1'b0;
            @(negedge clk); abort_flush = 1'b1;
            @(negedge clk); abort_flush = 1'b0;
            watchdog = 0;
            while (!frame_done) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100) $fatal(1, "Abort commit timed out in state %0d", target_state);
            end
            if (!frame_error || !saw_core_abort ||
                !dut.feedback_mem[(dut.active_feedback_bank ? 16 : 0) + 10][5])
                $fatal(1, "Abort result missing in state %0d", target_state);
            checks = checks + 1;
        end
    endtask

    initial begin
        logic [31:0] exact_budget;
        integer watchdog;
        rst = 1'b1;
        enable = 1'b0;
        single_step = 1'b0;
        abort_flush = 1'b0;
        comm_deadline = 32'd1000;
        command_commit = 1'b0;
        cpu_mem_valid = 1'b0;
        cpu_mem_write = 1'b0;
        cpu_mem_region = 3'd0;
        cpu_mem_byte_addr = 12'd0;
        cpu_mem_wdata = 32'd0;
        cpu_mem_wstrb = 4'd0;
        cmd_ready = 1'b1;
        body_ready = 1'b1;
        transaction_done = 1'b0;
        checks = 0;
        repeat (3) @(negedge clk);
        rst = 1'b0;
        configure();

        enable = 1'b1;
        watchdog = 0;
        while (!schedule_valid) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (watchdog > 100) $fatal(1, "Initial validation timeout");
        end
        exact_budget = schedule_budget_cycles;
        enable = 1'b0;
        repeat (3) @(negedge clk);

        comm_deadline = exact_budget;
        enable = 1'b1;
        repeat (30) @(negedge clk);
        if (!schedule_valid || schedule_overflow || schedule_config_error)
            $fatal(1, "Exact schedule budget boundary rejected");
        checks = checks + 1;
        enable = 1'b0;
        repeat (3) @(negedge clk);

        comm_deadline = exact_budget - 32'd1;
        enable = 1'b1;
        repeat (30) @(negedge clk);
        if (!schedule_overflow || schedule_valid)
            $fatal(1, "Budget-minus-one schedule was not rejected");
        checks = checks + 1;

        comm_deadline = 32'd1000;
        abort_state(4'd9);  // runtime descriptor read
        abort_state(4'd3);  // descriptor loaded
        abort_state(4'd4);  // command handshake
        abort_state(4'd10); // synchronous body SRAM read
        abort_state(4'd5);  // body stream
        abort_state(4'd6);  // transaction wait
        abort_state(4'd7);  // feedback commit

        $display("[PROTOCOL2 RT SAFETY PASS] %0d checks", checks);
        $finish;
    end
endmodule
