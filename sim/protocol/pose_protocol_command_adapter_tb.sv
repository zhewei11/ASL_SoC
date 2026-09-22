module pose_protocol_command_adapter_tb;

    localparam int unsigned MOTOR_COUNT = 20;
    localparam logic [31:0] PROTOCOL_BASE = 32'h1003_0000;
    localparam logic [31:0] REG_RT_MEM_ADDR = PROTOCOL_BASE + 32'hB8;
    localparam logic [31:0] REG_RT_MEM_DATA = PROTOCOL_BASE + 32'hBC;
    localparam logic [31:0] REG_COMMAND_COMMIT = PROTOCOL_BASE + 32'hC0;

    logic clk;
    logic rst;

    logic pose_valid;
    logic pose_ready;
    logic [$clog2(MOTOR_COUNT)-1:0] pose_motor_index;
    logic [15:0] pose_goal_current;
    logic [15:0] pose_position;
    logic pose_last;
    logic pose_commit;
    logic [31:0] pose_sequence;

    logic mmio_valid;
    logic mmio_ready;
    logic mmio_write;
    logic [31:0] mmio_addr;
    logic [31:0] mmio_wdata;
    logic [3:0] mmio_wstrb;
    logic [31:0] mmio_rdata;

    logic busy;
    logic error;
    logic committed_bank;
    logic [31:0] committed_sequence;

    logic model_committed_bank;
    logic [11:0] model_byte_address;
    integer model_commit_count;

    pose_protocol_command_adapter #(
         .MOTOR_COUNT  (MOTOR_COUNT)
        ,.PROTOCOL_BASE(PROTOCOL_BASE)
    ) dut (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.pose_valid                (pose_valid)
        ,.pose_ready                (pose_ready)
        ,.pose_motor_index          (pose_motor_index)
        ,.pose_goal_current         (pose_goal_current)
        ,.pose_goal_velocity        (32'd0)
        ,.pose_profile_acceleration (32'd0)
        ,.pose_profile_velocity     (32'd0)
        ,.pose_position             (pose_position)
        ,.pose_last                 (pose_last)
        ,.pose_commit               (pose_commit)
        ,.pose_sequence             (pose_sequence)
        ,.hand_id                   (8'd110)
        ,.mmio_valid                (mmio_valid)
        ,.mmio_ready                (mmio_ready)
        ,.mmio_write                (mmio_write)
        ,.mmio_addr                 (mmio_addr)
        ,.mmio_wdata                (mmio_wdata)
        ,.mmio_wstrb                (mmio_wstrb)
        ,.mmio_rdata                (mmio_rdata)
        ,.busy                      (busy)
        ,.error                     (error)
        ,.committed_bank            (committed_bank)
        ,.committed_sequence        (committed_sequence)
    );

    assign mmio_ready = 1'b1;
    assign mmio_rdata = {31'd0, model_committed_bank};

    always #5 clk = ~clk;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            model_committed_bank <= 1'b0;
            model_byte_address <= 12'd0;
            model_commit_count <= 0;
        end else if (mmio_valid && mmio_ready && mmio_write) begin
            if (mmio_addr == REG_RT_MEM_ADDR) begin
                model_byte_address <= mmio_wdata[11:0];
            end else if (mmio_addr == REG_RT_MEM_DATA) begin
                model_byte_address <= model_byte_address + 12'd4;
            end else if (mmio_addr == REG_COMMAND_COMMIT && mmio_wdata[31]) begin
                model_committed_bank <= mmio_wdata[0];
                model_commit_count <= model_commit_count + 1;
            end
        end
    end

    task automatic send_axis(
         input logic [$clog2(MOTOR_COUNT)-1:0] index
        ,input logic last
    );
        begin
            @(negedge clk);
            while (!pose_ready) begin
                @(negedge clk);
            end
            pose_motor_index = index;
            pose_goal_current = 16'h1200 + index;
            pose_position = 16'h0800 + index;
            pose_last = last;
            pose_valid = 1'b1;
            @(negedge clk);
            pose_valid = 1'b0;
            pose_last = 1'b0;
        end
    endtask

    task automatic commit_frame(input logic [31:0] sequence_value);
        begin
            @(negedge clk);
            pose_sequence = sequence_value;
            pose_commit = 1'b1;
            @(negedge clk);
            pose_commit = 1'b0;
        end
    endtask

    task automatic send_complete_frame(input logic [31:0] sequence_value);
        integer axis_index;
        begin
            for (axis_index = 0;
                 axis_index < MOTOR_COUNT;
                 axis_index = axis_index + 1) begin
                send_axis(
                    $clog2(MOTOR_COUNT)'(axis_index),
                    axis_index == MOTOR_COUNT - 1
                );
            end
            commit_frame(sequence_value);
        end
    endtask

    task automatic wait_for_sequence(input logic [31:0] sequence_value);
        integer watchdog;
        begin
            watchdog = 0;
            while (committed_sequence != sequence_value) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 200) begin
                    $fatal(1, "Command adapter commit timed out");
                end
            end
        end
    endtask

    initial begin
        integer axis_index;

        clk = 1'b0;
        rst = 1'b1;
        pose_valid = 1'b0;
        pose_motor_index = '0;
        pose_goal_current = 16'd0;
        pose_position = 16'd0;
        pose_last = 1'b0;
        pose_commit = 1'b0;
        pose_sequence = 32'd0;

        repeat (4) @(negedge clk);
        rst = 1'b0;

        // A short frame must be rejected without touching the committed bank.
        for (axis_index = 0;
             axis_index < MOTOR_COUNT - 1;
             axis_index = axis_index + 1) begin
            send_axis($clog2(MOTOR_COUNT)'(axis_index), 1'b0);
        end
        commit_frame(32'd1);
        repeat (4) @(negedge clk);
        if (busy || !error || model_commit_count != 0 ||
            committed_sequence != 32'd0) begin
            $fatal(1, "Incomplete frame was not rejected atomically");
        end

        // A complete ordered frame recovers from the previous error and is
        // the first frame allowed to switch the command bank.
        send_complete_frame(32'd2);
        wait_for_sequence(32'd2);
        if (error || model_commit_count != 1 || !committed_bank) begin
            $fatal(1, "Complete frame did not commit cleanly after rejection");
        end

        // Duplicate/out-of-order axes invalidate the whole frame. No partial
        // data may replace the previously committed snapshot.
        send_axis(5'd0, 1'b0);
        send_axis(5'd0, 1'b0);
        for (axis_index = 1;
             axis_index < MOTOR_COUNT;
             axis_index = axis_index + 1) begin
            send_axis(
                $clog2(MOTOR_COUNT)'(axis_index),
                axis_index == MOTOR_COUNT - 1
            );
        end
        commit_frame(32'd3);
        repeat (4) @(negedge clk);
        if (!error || model_commit_count != 1 ||
            committed_sequence != 32'd2) begin
            $fatal(1, "Duplicate-axis frame replaced a valid command bank");
        end

        // Width permits indices 20..31; they must be rejected before indexing
        // the 20-entry storage arrays.
        send_axis(5'd20, 1'b0);
        commit_frame(32'd4);
        repeat (4) @(negedge clk);
        if (!error || model_commit_count != 1 ||
            committed_sequence != 32'd2) begin
            $fatal(1, "Out-of-range axis reached command memory");
        end

        $display("[POSE PROTOCOL ADAPTER PASS] malformed frames cannot commit");
        $finish;
    end

endmodule
