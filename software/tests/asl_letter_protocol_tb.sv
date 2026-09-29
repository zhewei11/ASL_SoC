`include "rtos_core_config.svh"

module asl_letter_protocol_tb;

    localparam int unsigned CLOCK_HZ = 100_000_000;
    localparam int unsigned BAUD_RATE = 6_000_000;
    localparam int unsigned RX_OVERSAMPLE = 4;
    localparam logic [31:0] BASE = 32'h1003_0000;
    localparam logic [31:0] RT_CONTROL = BASE + 32'h40;
    localparam logic [31:0] FRAME_PERIOD = BASE + 32'h48;
    localparam logic [31:0] COMM_DEADLINE = BASE + 32'h4C;
    localparam logic [31:0] COMMAND_DEADLINE = BASE + 32'h50;
    localparam logic [31:0] PROTOCOL_OWNER = BASE + 32'h90;
    localparam logic [31:0] BAUD_REQUEST = BASE + 32'h94;
    localparam logic [31:0] RT_MEM_ADDR = BASE + 32'hB8;
    localparam logic [31:0] RT_MEM_DATA = BASE + 32'hBC;
    localparam logic [31:0] COMMAND_COMMIT = BASE + 32'hC0;
    localparam logic [31:0] DESCRIPTOR_COUNT = BASE + 32'hC4;
    localparam logic [31:0] COMMAND_SEQUENCE = BASE + 32'hC8;
    localparam int unsigned COMMAND_BODY_BYTES = 96;
    localparam int unsigned SYNC_WRITE_BODY_BYTES = 86;
    localparam int unsigned PACKET_BYTES = 7 + SYNC_WRITE_BODY_BYTES + 2;

    logic clk = 1'b0;
    logic rst;
    logic mmio_valid;
    logic mmio_ready;
    logic mmio_write;
    logic [31:0] mmio_addr;
    logic [31:0] mmio_wdata;
    logic [3:0] mmio_wstrb;
    logic [31:0] mmio_rdata;
    logic irq;
    logic rs485_tx;
    logic rs485_rx = 1'b1;
    logic rs485_de;
    logic monitor_valid;
    logic [7:0] monitor_data;
    logic monitor_framing_error;
    logic monitor_overrun_error;
    logic [7:0] command_body [0:COMMAND_BODY_BYTES-1];
    logic [7:0] captured [0:PACKET_BYTES-1];
    integer captured_count;
    integer checks;
    logic de_seen;

    protocol2_mmio_wrapper #(
         .CLOCK_HZ(CLOCK_HZ)
        ,.BAUD_RATE(BAUD_RATE)
        ,.RX_OVERSAMPLE(RX_OVERSAMPLE)
        ,.USE_HX5_RT_SEQUENCER(1'b1)
    ) dut (
         .clk(clk)
        ,.rst(rst)
        ,.frame_tick(1'b0)
        ,.external_abort(1'b0)
        ,.mmio_valid(mmio_valid)
        ,.mmio_ready(mmio_ready)
        ,.mmio_write(mmio_write)
        ,.mmio_addr(mmio_addr)
        ,.mmio_wdata(mmio_wdata)
        ,.mmio_wstrb(mmio_wstrb)
        ,.mmio_rdata(mmio_rdata)
        ,.irq(irq)
        ,.rs485_tx(rs485_tx)
        ,.rs485_rx(rs485_rx)
        ,.rs485_de(rs485_de)
    );

    uart_rx #(
         .CLOCK_HZ(CLOCK_HZ)
        ,.BAUD_RATE(BAUD_RATE)
        ,.OVERSAMPLE(RX_OVERSAMPLE)
    ) monitor (
         .clk(clk)
        ,.rst(rst)
        ,.flush(1'b0)
        ,.serial_rx(rs485_tx)
        ,.baud_rate(32'(BAUD_RATE))
        ,.output_valid(monitor_valid)
        ,.output_ready(1'b1)
        ,.output_data(monitor_data)
        ,.output_framing_error(monitor_framing_error)
        ,.busy()
        ,.overrun_error(monitor_overrun_error)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            captured_count <= 0;
            de_seen <= 1'b0;
        end else begin
            if (rs485_de)
                de_seen <= 1'b1;
            if (monitor_valid && captured_count < PACKET_BYTES) begin
                captured[captured_count] <= monitor_data;
                captured_count <= captured_count + 1;
            end
        end
    end

    function automatic logic [15:0] crc16_update(
         input logic [15:0] crc_in
        ,input logic [7:0] data
    );
        logic [15:0] value;
        integer bit_index;
        begin
            value = crc_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (value[15] ^ data[7-bit_index])
                    value = {value[14:0], 1'b0} ^ 16'h8005;
                else
                    value = {value[14:0], 1'b0};
            end
            crc16_update = value;
        end
    endfunction

    task automatic check_condition(
         input logic condition
        ,input string message
    );
        begin
            if (!condition)
                $fatal(1, "%s", message);
            checks = checks + 1;
        end
    endtask

    task automatic mmio_write32(
         input logic [31:0] address
        ,input logic [31:0] value
    );
        integer watchdog;
        begin
            @(negedge clk);
            mmio_addr = address;
            mmio_wdata = value;
            mmio_wstrb = 4'hF;
            mmio_write = 1'b1;
            mmio_valid = 1'b1;
            #1;
            watchdog = 0;
            while (!mmio_ready) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 1000)
                    $fatal(1, "MMIO write timeout at %08h", address);
            end
            @(negedge clk);
            mmio_valid = 1'b0;
            mmio_write = 1'b0;
            mmio_wstrb = 4'd0;
            mmio_wdata = 32'd0;
        end
    endtask

    task automatic write_descriptor(input logic [31:0] value);
        begin
            mmio_write32(RT_MEM_DATA, value);
        end
    endtask

    initial begin
        logic [31:0] word;
        logic [15:0] crc;
        integer byte_index;
        integer watchdog;

        $readmemh("build/asl_letter_command.mem", command_body);
        rst = 1'b1;
        mmio_valid = 1'b0;
        mmio_write = 1'b0;
        mmio_addr = 32'd0;
        mmio_wdata = 32'd0;
        mmio_wstrb = 4'd0;
        checks = 0;
        repeat (8) @(negedge clk);
        rst = 1'b0;

        mmio_write32(RT_CONTROL, 32'd0);
        mmio_write32(PROTOCOL_OWNER, 32'd0);
        mmio_write32(BAUD_REQUEST, 32'd2);
        mmio_write32(FRAME_PERIOD, 32'd100000);
        mmio_write32(COMM_DEADLINE, 32'd0);
        mmio_write32(COMMAND_DEADLINE, 32'd0);

        mmio_write32(RT_MEM_ADDR, 32'h8000_4000);
        write_descriptor(32'h0000_FE03);
        write_descriptor(32'd0);
        write_descriptor(32'd86);
        write_descriptor(32'd0);
        write_descriptor(32'd0);
        write_descriptor(32'd0);
        write_descriptor(32'd0);
        write_descriptor(32'd0);
        write_descriptor(32'd1);
        write_descriptor(32'd1);
        write_descriptor(32'h00A5_6E03);
        write_descriptor(32'd88);
        write_descriptor(32'd5);
        write_descriptor(32'd1);
        write_descriptor(32'd1);
        write_descriptor(32'd60000);
        write_descriptor(32'd1000);
        write_descriptor(32'd56);
        write_descriptor(32'd1);
        write_descriptor(32'hFFFF_FFFF);
        mmio_write32(DESCRIPTOR_COUNT, 32'd2);

        /* The first CPU submission targets command bank B. */
        mmio_write32(RT_MEM_ADDR, 32'h8000_1000);
        for (byte_index = 0;
             byte_index < COMMAND_BODY_BYTES;
             byte_index = byte_index + 4) begin
            word = command_body[byte_index] |
                (command_body[byte_index + 1] << 8) |
                (command_body[byte_index + 2] << 16) |
                (command_body[byte_index + 3] << 24);
            mmio_write32(RT_MEM_DATA, word);
        end
        mmio_write32(COMMAND_SEQUENCE, 32'd1);
        mmio_write32(COMMAND_COMMIT, 32'h8000_0001);
        mmio_write32(RT_CONTROL, 32'd1);

        watchdog = 0;
        while (captured_count < PACKET_BYTES) begin
            @(negedge clk);
            watchdog = watchdog + 1;
            if (watchdog > 400000) begin
                $display(
                    "debug owner=%0d enable=%0d desc=%0d schedule=%0d commit_valid=%0d bank=%0d state=%0d frame_counter=%0d profile=%08h timeout=%0d interbyte=%0d captured=%0d",
                    dut.owner_reg,
                    dut.rt_enable_reg,
                    dut.descriptor_count_reg,
                    dut.rt_schedule_valid,
                    dut.g_hx5_rt.u_protocol2_rt_engine.command_commit_valid,
                    dut.g_hx5_rt.u_protocol2_rt_engine.committed_command_bank,
                    dut.g_hx5_rt.u_protocol2_rt_engine.state,
                    dut.g_hx5_rt.u_protocol2_rt_engine.frame_period_counter,
                    dut.g_hx5_rt.u_protocol2_rt_engine.profile_read_control,
                    dut.g_hx5_rt.u_protocol2_rt_engine.profile_response_timeout,
                    dut.g_hx5_rt.u_protocol2_rt_engine.profile_inter_byte_timeout,
                    captured_count
                );
                $fatal(1, "6 Mbps Sync Write packet timeout");
            end
        end

        check_condition(de_seen, "RS-485 DE was never asserted");
        check_condition(!monitor_framing_error, "UART framing error");
        check_condition(!monitor_overrun_error, "UART monitor overrun");
        check_condition(captured[0] == 8'hFF && captured[1] == 8'hFF &&
                        captured[2] == 8'hFD && captured[3] == 8'h00,
                        "Protocol 2.0 header mismatch");
        check_condition(captured[4] == 8'hFE,
                        "Sync Write did not use broadcast ID");
        check_condition(captured[5] == 8'h58 && captured[6] == 8'h00,
                        "Protocol length mismatch");
        for (byte_index = 0;
             byte_index < SYNC_WRITE_BODY_BYTES;
             byte_index = byte_index + 1) begin
            check_condition(captured[7 + byte_index] == command_body[byte_index],
                            "letter command body mismatch on UART");
        end

        crc = 16'd0;
        for (byte_index = 0;
             byte_index < 7 + SYNC_WRITE_BODY_BYTES;
             byte_index = byte_index + 1) begin
            crc = crc16_update(crc, captured[byte_index]);
        end
        check_condition(captured[PACKET_BYTES-2] == crc[7:0] &&
                        captured[PACKET_BYTES-1] == crc[15:8],
                        "Protocol CRC mismatch");
        check_condition(command_body[0] == 8'h83 &&
                        command_body[1] == 8'h1F &&
                        command_body[2] == 8'h03,
                        "generated body is not HX5 indirect Sync Write");

        $display(
            "ASL letter -> motor raw -> Protocol 2.0 UART: %0d checks passed",
            checks
        );
        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "ASL Protocol end-to-end test timeout");
    end

endmodule
