`include "rtos_core_config.svh"

module protocol2_mmio_wrapper_tb;

    localparam int unsigned CLOCK_HZ = `RTOS_CORE_CPU_CLOCK_HZ;
    localparam int unsigned BAUD_RATE = `RTOS_CORE_PROTOCOL2_BAUD_RATE;
    localparam int unsigned RX_OVERSAMPLE =
        `RTOS_CORE_PROTOCOL2_RX_OVERSAMPLE;
    localparam logic [31:0] BASE = `RTOS_CORE_PROTOCOL2_MMIO_BASE;

    localparam logic [31:0] CONTROL            = BASE + 32'h00;
    localparam logic [31:0] STATUS             = BASE + 32'h04;
    localparam logic [31:0] CMD_CONFIG         = BASE + 32'h08;
    localparam logic [31:0] BODY_LENGTH        = BASE + 32'h0C;
    localparam logic [31:0] RESPONSE_TIMEOUT   = BASE + 32'h10;
    localparam logic [31:0] INTER_BYTE_TIMEOUT = BASE + 32'h14;
    localparam logic [31:0] TX_DATA            = BASE + 32'h18;
    localparam logic [31:0] RX_META            = BASE + 32'h1C;
    localparam logic [31:0] RX_LENGTH          = BASE + 32'h20;
    localparam logic [31:0] RX_DATA            = BASE + 32'h24;
    localparam logic [31:0] IRQ_STATUS         = BASE + 32'h28;
    localparam logic [31:0] IRQ_ENABLE         = BASE + 32'h2C;
    localparam logic [31:0] ID_REGISTER        = BASE + 32'h30;
    localparam logic [31:0] TX_COUNT           = BASE + 32'h34;
    localparam logic [31:0] RT_CONTROL         = BASE + 32'h40;
    localparam logic [31:0] RT_STATUS          = BASE + 32'h44;
    localparam logic [31:0] FRAME_PERIOD       = BASE + 32'h48;
    localparam logic [31:0] COMM_DEADLINE      = BASE + 32'h4C;
    localparam logic [31:0] COMMAND_DEADLINE   = BASE + 32'h50;
    localparam logic [31:0] FRAME_SEQUENCE     = BASE + 32'h74;
    localparam logic [31:0] FRAME_CYCLES       = BASE + 32'h78;
    localparam logic [31:0] MINIMUM_SLACK      = BASE + 32'h7C;
    localparam logic [31:0] RECEIVED_ID_MASK   = BASE + 32'h6C;
    localparam logic [31:0] ERROR_ID_MASK      = BASE + 32'h70;
    localparam logic [31:0] RT_IRQ_STATUS      = BASE + 32'h80;
    localparam logic [31:0] RT_IRQ_ENABLE      = BASE + 32'h84;
    localparam logic [31:0] ABORT_FLUSH        = BASE + 32'h88;
    localparam logic [31:0] PROTOCOL_OWNER     = BASE + 32'h90;
    localparam logic [31:0] BAUD_REQUEST       = BASE + 32'h94;
    localparam logic [31:0] BAUD_STATUS        = BASE + 32'h98;
    localparam logic [31:0] RT_MEM_ADDR        = BASE + 32'hB8;
    localparam logic [31:0] RT_MEM_DATA        = BASE + 32'hBC;
    localparam logic [31:0] COMMAND_COMMIT     = BASE + 32'hC0;
    localparam logic [31:0] DESCRIPTOR_COUNT   = BASE + 32'hC4;
    localparam logic [31:0] COMMAND_SEQUENCE   = BASE + 32'hC8;
    localparam logic [31:0] STALE_ID_MASK      = BASE + 32'hCC;
    localparam logic [31:0] SCHEDULE_STATUS    = BASE + 32'hD0;
    localparam logic [31:0] SCHEDULE_BUDGET    = BASE + 32'hD4;
    localparam logic [31:0] COMMANDED_ID_MASK  = BASE + 32'hD8;

    logic        clk;
    logic        rst;
    logic        mmio_valid;
    logic        mmio_ready;
    logic        mmio_write;
    logic [31:0] mmio_addr;
    logic [31:0] mmio_wdata;
    logic [3:0]  mmio_wstrb;
    logic [31:0] mmio_rdata;
    logic        irq;
    logic        rs485_tx;
    logic        rs485_rx;
    logic        rs485_de;
    logic        frame_tick;
    logic        external_abort;
    logic [31:0] test_baud_rate;

    logic        motor_tx_valid;
    logic        motor_tx_ready;
    logic [7:0]  motor_tx_data;
    logic        motor_tx_last;
    logic        motor_serial_tx;
    logic        motor_tx_busy;
    logic        motor_byte_done;
    logic        motor_packet_done;

    logic        monitor_valid;
    logic [7:0]  monitor_data;
    logic        monitor_framing_error;
    logic        monitor_busy;
    logic        monitor_overrun_error;

    logic [7:0] response_packet [0:255];
    logic [7:0] response_body [0:255];
    logic [7:0] captured_tx [0:511];
    integer response_packet_length;
    integer captured_tx_count;
    integer tests_passed;
    logic   rs485_de_seen;

    protocol2_mmio_wrapper #(
         .CLOCK_HZ      (CLOCK_HZ)
        ,.BAUD_RATE     (BAUD_RATE)
        ,.RX_OVERSAMPLE (RX_OVERSAMPLE)
        ,.USE_HX5_RT_SEQUENCER (1'b0)
    ) dut (
         .clk        (clk)
        ,.rst        (rst)
        ,.frame_tick (frame_tick)
        ,.external_abort(external_abort)
        ,.mmio_valid (mmio_valid)
        ,.mmio_ready (mmio_ready)
        ,.mmio_write (mmio_write)
        ,.mmio_addr  (mmio_addr)
        ,.mmio_wdata (mmio_wdata)
        ,.mmio_wstrb (mmio_wstrb)
        ,.mmio_rdata (mmio_rdata)
        ,.irq        (irq)
        ,.rs485_tx   (rs485_tx)
        ,.rs485_rx   (rs485_rx)
        ,.rs485_de   (rs485_de)
    );

    uart_tx #(
         .CLOCK_HZ  (CLOCK_HZ)
        ,.BAUD_RATE (BAUD_RATE)
    ) u_motor_uart_tx (
         .clk         (clk)
        ,.rst         (rst)
        ,.flush       (1'b0)
        ,.input_valid (motor_tx_valid)
        ,.input_ready (motor_tx_ready)
        ,.input_data  (motor_tx_data)
        ,.input_last  (motor_tx_last)
        ,.baud_rate   (test_baud_rate)
        ,.serial_tx   (motor_serial_tx)
        ,.busy        (motor_tx_busy)
        ,.byte_done   (motor_byte_done)
        ,.packet_done (motor_packet_done)
    );

    uart_rx #(
         .CLOCK_HZ   (CLOCK_HZ)
        ,.BAUD_RATE  (BAUD_RATE)
        ,.OVERSAMPLE (RX_OVERSAMPLE)
    ) u_tx_monitor (
         .clk                  (clk)
        ,.rst                  (rst)
        ,.flush                (1'b0)
        ,.serial_rx            (rs485_tx)
        ,.baud_rate            (test_baud_rate)
        ,.output_valid         (monitor_valid)
        ,.output_ready         (1'b1)
        ,.output_data          (monitor_data)
        ,.output_framing_error (monitor_framing_error)
        ,.busy                 (monitor_busy)
        ,.overrun_error        (monitor_overrun_error)
    );

    assign rs485_rx = motor_serial_tx;

    always #5 clk = ~clk;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            captured_tx_count <= 0;
            rs485_de_seen <= 1'b0;
        end else begin
            if (monitor_valid) begin
                captured_tx[captured_tx_count] <= monitor_data;
                captured_tx_count <= captured_tx_count + 1;
            end
            if (rs485_de) begin
                rs485_de_seen <= 1'b1;
            end
        end
    end

    function automatic logic [15:0] crc16_update(
         input logic [15:0] crc_in
        ,input logic [7:0]  data
    );
        logic [15:0] value;
        integer bit_index;
        begin
            value = crc_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (value[15] ^ data[7-bit_index]) begin
                    value = {value[14:0], 1'b0} ^ 16'h8005;
                end else begin
                    value = {value[14:0], 1'b0};
                end
            end
            crc16_update = value;
        end
    endfunction

    task automatic build_two_parameter_status(
         input logic [7:0] response_device_id
        ,input logic [7:0] parameter_0
        ,input logic [7:0] parameter_1
    );
        logic [15:0] crc_value;
        integer byte_index;
        begin
            response_packet[0]  = 8'hFF;
            response_packet[1]  = 8'hFF;
            response_packet[2]  = 8'hFD;
            response_packet[3]  = 8'h00;
            response_packet[4]  = response_device_id;
            response_packet[5]  = 8'h06;
            response_packet[6]  = 8'h00;
            response_packet[7]  = 8'h55;
            response_packet[8]  = 8'h00;
            response_packet[9]  = parameter_0;
            response_packet[10] = parameter_1;
            crc_value = 16'h0000;
            for (byte_index = 0; byte_index < 11; byte_index = byte_index + 1) begin
                crc_value = crc16_update(crc_value, response_packet[byte_index]);
            end
            response_packet[11] = crc_value[7:0];
            response_packet[12] = crc_value[15:8];
            response_packet_length = 13;
        end
    endtask

    task automatic build_hx5_status(input logic [7:0] response_device_id);
        logic [15:0] crc_value;
        integer body_index;
        integer packet_index;
        integer parameter_index;
        integer stuffed_body_length;
        begin
            response_body[0] = 8'h55;
            response_body[1] = 8'h00;
            for (parameter_index = 0;
                 parameter_index < 165;
                 parameter_index = parameter_index + 1) begin
                response_body[parameter_index + 2] =
                    (parameter_index * 7 + 3) & 8'hFF;
            end

            // Force a Protocol 2.0 stuffing pattern inside the real-size HX5
            // feedback payload. The following inserted FD must not appear in
            // the 165-byte parameter stream delivered by protocol2_rx.
            response_body[52] = 8'hFF;
            response_body[53] = 8'hFF;
            response_body[54] = 8'hFD;

            response_packet[0] = 8'hFF;
            response_packet[1] = 8'hFF;
            response_packet[2] = 8'hFD;
            response_packet[3] = 8'h00;
            response_packet[4] = response_device_id;
            packet_index = 7;

            for (body_index = 0; body_index < 167;
                 body_index = body_index + 1) begin
                response_packet[packet_index] = response_body[body_index];
                packet_index = packet_index + 1;
                if ((body_index >= 2) &&
                    (response_body[body_index-2] == 8'hFF) &&
                    (response_body[body_index-1] == 8'hFF) &&
                    (response_body[body_index] == 8'hFD)) begin
                    response_packet[packet_index] = 8'hFD;
                    packet_index = packet_index + 1;
                end
            end

            stuffed_body_length = packet_index - 7;
            response_packet[5] = (stuffed_body_length + 2) & 8'hFF;
            response_packet[6] = (stuffed_body_length + 2) >> 8;
            crc_value = 16'h0000;
            for (body_index = 0; body_index < packet_index;
                 body_index = body_index + 1) begin
                crc_value = crc16_update(crc_value, response_packet[body_index]);
            end
            response_packet[packet_index] = crc_value[7:0];
            response_packet[packet_index + 1] = crc_value[15:8];
            response_packet_length = packet_index + 2;
        end
    endtask

    task automatic transmit_built_status;
        integer byte_index;
        begin
            for (byte_index = 0;
                 byte_index < response_packet_length;
                 byte_index = byte_index + 1) begin
                while (!motor_tx_ready) begin
                    @(negedge clk);
                end
                motor_tx_data = response_packet[byte_index];
                motor_tx_last = (byte_index + 1 == response_packet_length);
                motor_tx_valid = 1'b1;
                @(negedge clk);
                motor_tx_valid = 1'b0;
                motor_tx_last = 1'b0;
                @(negedge clk);
            end
            while (!motor_packet_done) begin
                @(negedge clk);
            end
        end
    endtask

    task automatic mmio_write_word(
         input logic [31:0] address
        ,input logic [31:0] data
        ,input logic [3:0]  strobe
    );
        integer watchdog;
        begin
            @(negedge clk);
            mmio_addr  = address;
            mmio_wdata = data;
            mmio_wstrb = strobe;
            mmio_write = 1'b1;
            mmio_valid = 1'b1;
            #1;
            watchdog = 0;
            while (!mmio_ready) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100000) begin
                    $fatal(1, "MMIO write timeout at %08h", address);
                end
            end
            @(negedge clk);
            mmio_valid = 1'b0;
            mmio_write = 1'b0;
            mmio_wstrb = 4'd0;
            mmio_wdata = 32'd0;
        end
    endtask

    task automatic mmio_read_word(
         input  logic [31:0] address
        ,output logic [31:0] data
    );
        integer watchdog;
        begin
            @(negedge clk);
            mmio_addr  = address;
            mmio_write = 1'b0;
            mmio_valid = 1'b1;
            #1;
            watchdog = 0;
            while (!mmio_ready) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100000) begin
                    $fatal(1, "MMIO read timeout at %08h", address);
                end
            end
            @(posedge clk);
            data = mmio_rdata;
            @(negedge clk);
            mmio_valid = 1'b0;
        end
    endtask

    task automatic wait_irq_status(input logic [3:0] mask);
        logic [31:0] value;
        integer watchdog;
        begin
            value = 32'd0;
            watchdog = 0;
            while ((value[3:0] & mask) != mask) begin
                mmio_read_word(IRQ_STATUS, value);
                watchdog = watchdog + 1;
                if (watchdog > 100000) begin
                    $fatal(1, "IRQ status timeout, expected mask %h", mask);
                end
            end
        end
    endtask

    task automatic wait_rt_irq_status(input logic [3:0] mask);
        logic [31:0] value;
        integer watchdog;
        begin
            value = 32'd0;
            watchdog = 0;
            while ((value[3:0] & mask) != mask) begin
                mmio_read_word(RT_IRQ_STATUS, value);
                watchdog = watchdog + 1;
                if (watchdog > 300000) begin
                    $fatal(1, "RT IRQ status timeout, expected mask %h", mask);
                end
            end
        end
    endtask

    task automatic rt_mem_write_word(
         input logic [2:0]  region
        ,input logic [11:0] byte_address
        ,input logic [31:0] data
    );
        begin
            mmio_write_word(
                RT_MEM_ADDR,
                {17'd0, region, byte_address},
                4'hF
            );
            mmio_write_word(RT_MEM_DATA, data, 4'hF);
        end
    endtask

    task automatic rt_mem_read_word(
         input  logic [2:0]  region
        ,input  logic [11:0] byte_address
        ,output logic [31:0] data
    );
        begin
            mmio_write_word(
                RT_MEM_ADDR,
                {17'd0, region, byte_address},
                4'hF
            );
            mmio_read_word(RT_MEM_DATA, data);
        end
    endtask

    task automatic send_motor_status;
        integer watchdog;
        begin
            watchdog = 0;
            while (!rs485_de) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100_000) begin
                    $fatal(1, "Motor response saw no TX: rt=%08h sched=%08h",
                           dut.rt_status_word,
                           {20'd0, dut.rt_command_bank_locked, 6'd0,
                            dut.rt_late_command_commit,
                            dut.rt_schedule_config_error,
                            dut.rt_schedule_overflow,
                            dut.rt_schedule_valid});
                end
            end
            while (rs485_de) begin
                @(negedge clk);
            end
            repeat (4) @(negedge clk);

            transmit_built_status();
        end
    endtask

    task automatic send_two_motor_statuses(
         input logic [7:0] first_id
        ,input logic [7:0] first_p0
        ,input logic [7:0] first_p1
        ,input logic [7:0] second_id
        ,input logic [7:0] second_p0
        ,input logic [7:0] second_p1
    );
        begin
            while (!rs485_de) begin
                @(negedge clk);
            end
            while (rs485_de) begin
                @(negedge clk);
            end
            repeat (4) @(negedge clk);
            build_two_parameter_status(first_id, first_p0, first_p1);
            transmit_built_status();
            repeat (4) @(negedge clk);
            build_two_parameter_status(second_id, second_p0, second_p1);
            transmit_built_status();
        end
    endtask

    task automatic send_twenty_motor_statuses;
        integer device_id;
        integer watchdog;
        begin
            watchdog = 0;
            while (!rs485_de) begin
                @(negedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 100_000) begin
                    $fatal(1,
                        "20-device TX never started: status=%08h state=%0d ctrl=%08h body=%0d count=%0d mask=%08h timeout=%0d rx_min=%0d fields_invalid=%0d budget=%0d",
                        dut.rt_status_word,
                        dut.g_generic_rt.u_protocol2_rt_engine.state,
                        dut.g_generic_rt.u_protocol2_rt_engine.desc_control,
                        dut.g_generic_rt.u_protocol2_rt_engine.desc_body_length,
                        dut.g_generic_rt.u_protocol2_rt_engine.
                            desc_response_count,
                        dut.g_generic_rt.u_protocol2_rt_engine.
                            desc_expected_mask,
                        dut.g_generic_rt.u_protocol2_rt_engine.
                            desc_response_timeout,
                        dut.g_generic_rt.u_protocol2_rt_engine.
                            descriptor_rx_min_cycles,
                        dut.g_generic_rt.u_protocol2_rt_engine.
                            descriptor_fields_invalid,
                        dut.g_generic_rt.u_protocol2_rt_engine.
                            descriptor_budget_cycles);
                end
            end
            while (rs485_de) begin
                @(negedge clk);
            end
            repeat (4) @(negedge clk);
            for (device_id = 1; device_id <= 20;
                 device_id = device_id + 1) begin
                build_two_parameter_status(
                    device_id[7:0],
                    device_id[7:0],
                    ~device_id[7:0]
                );
                transmit_built_status();
                repeat (4) @(negedge clk);
            end
        end
    endtask

    task automatic expect_equal(
         input logic [31:0] actual
        ,input logic [31:0] expected
        ,input string       label_text
    );
        begin
            if (actual !== expected) begin
                $fatal(1, "%s: expected %08h, got %08h",
                       label_text, expected, actual);
            end
            tests_passed = tests_passed + 1;
        end
    endtask

    initial begin
        logic [31:0] value;

        clk = 1'b0;
        rst = 1'b1;
        mmio_valid = 1'b0;
        mmio_write = 1'b0;
        mmio_addr = 32'd0;
        mmio_wdata = 32'd0;
        mmio_wstrb = 4'd0;
        motor_tx_valid = 1'b0;
        motor_tx_data = 8'd0;
        motor_tx_last = 1'b0;
        test_baud_rate = BAUD_RATE;
        frame_tick = 1'b0;
        external_abort = 1'b0;
        tests_passed = 0;

`ifdef DUMP_WAVE
        $dumpfile("protocol2_mmio_wrapper.vcd");
        $dumpvars(0, protocol2_mmio_wrapper_tb);
`endif

        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (4) @(negedge clk);

        mmio_read_word(ID_REGISTER, value);
        expect_equal(value, 32'h5032_4D4D, "peripheral ID");

        mmio_read_word(COMM_DEADLINE, value);
        expect_equal(value, 32'd0, "default communication deadline disabled");
        mmio_read_word(COMMAND_DEADLINE, value);
        expect_equal(value, 32'd0, "default command deadline disabled");

        // Upper-byte-only writes must not alter low-byte control registers.
        mmio_write_word(PROTOCOL_OWNER, 32'h0000_0000, 4'b1000);
        mmio_read_word(PROTOCOL_OWNER, value);
        expect_equal(value, 32'd1, "owner ignores unselected low byte");
        mmio_write_word(BAUD_REQUEST, 32'h0000_0000, 4'b1000);
        mmio_read_word(BAUD_REQUEST, value);
        expect_equal(value, 32'd2, "baud request ignores unselected low byte");
        mmio_write_word(DESCRIPTOR_COUNT, 32'd25, 4'hF);
        mmio_write_word(DESCRIPTOR_COUNT, 32'd1, 4'b1000);
        mmio_read_word(DESCRIPTOR_COUNT, value);
        expect_equal(value, 32'd25, "descriptor count write strobes");
        mmio_write_word(DESCRIPTOR_COUNT, 32'd26, 4'hF);
        mmio_read_word(DESCRIPTOR_COUNT, value);
        expect_equal(value, 32'd25, "descriptor count hardware limit");
        mmio_write_word(DESCRIPTOR_COUNT, 32'd1, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'b1000);
        mmio_read_word(COMMAND_COMMIT, value);
        expect_equal(value, 32'd0, "command commit requires bank byte");

        // Byte write strobes must update only their selected CMD_CONFIG lane.
        mmio_write_word(CMD_CONFIG, 32'h0001_0101, 4'hF);
        mmio_write_word(CMD_CONFIG, 32'h0000_0200, 4'b0010);
        mmio_read_word(CMD_CONFIG, value);
        expect_equal(value, 32'h0001_0201, "CMD_CONFIG write strobes");

        // Reject a command whose worst-case byte stuffing cannot fit SRAM at
        // command acceptance, before requesting any body bytes.
        mmio_write_word(CMD_CONFIG, 32'h0000_0101, 4'hF);
        mmio_write_word(BODY_LENGTH, 32'd761, 4'hF);
        mmio_write_word(IRQ_ENABLE, 32'h0000_000F, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        repeat (20) @(negedge clk);
        mmio_read_word(IRQ_STATUS, value);
        if (!value[1]) begin
            $fatal(1,
                   "Oversized stuffed packet was not rejected: irq=%08h core=%0d tx=%0d worst=%0d",
                   value, dut.u_protocol2_core.core_state,
                   dut.u_protocol2_core.u_protocol2_tx.state,
                   dut.u_protocol2_core.u_protocol2_tx.worst_case_stuffed_length);
        end
        if (rs485_de) begin
            $fatal(1, "Oversized stuffed packet reached RS-485");
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(IRQ_STATUS, 32'h0000_000F, 4'h1);

        // Transaction abort is a synchronous flush, and must return the
        // complete protocol/UART datapath to idle without a generated reset.
        mmio_write_word(BODY_LENGTH, 32'd10, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        repeat (4) @(negedge clk);
        mmio_write_word(ABORT_FLUSH, 32'h0000_0001, 4'h1);
        mmio_read_word(STATUS, value);
        if (!value[0] || value[1] || rs485_de) begin
            $fatal(1, "Synchronous abort did not return core to idle: %08h",
                   value);
        end
        tests_passed = tests_passed + 1;

        // A hardware safety abort uses the same flush path as the software
        // abort register. It must stop an in-flight UART packet and keep the
        // protocol core idle for the entire asserted safety interval.
        mmio_write_word(BODY_LENGTH, 32'd1, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        mmio_write_word(TX_DATA, 32'h0000_0001, 4'h1);
        while (!rs485_de) begin
            @(negedge clk);
        end
        external_abort = 1'b1;
        @(posedge clk);
        #1;
        if (rs485_de || !dut.core_flush ||
            dut.u_protocol2_core.core_state != 2'd0) begin
            $fatal(1,
                   "External safety abort did not flush TX/PHY: de=%0d flush=%0d state=%0d",
                   rs485_de, dut.core_flush,
                   dut.u_protocol2_core.core_state);
        end
        repeat (3) @(posedge clk);
        if (dut.u_protocol2_core.core_state != 2'd0) begin
            $fatal(1, "Protocol core left IDLE while safety abort was active");
        end
        external_abort = 1'b0;
        repeat (3) @(negedge clk);
        mmio_read_word(STATUS, value);
        if (!value[0] || value[1] || rs485_de) begin
            $fatal(1, "Core did not recover cleanly after safety release: %08h",
                   value);
        end
        tests_passed = tests_passed + 1;

        // First command: no response. Verify TX, sticky DONE and W1C.
        mmio_write_word(CMD_CONFIG, 32'h0000_0101, 4'hF);
        mmio_write_word(BODY_LENGTH, 32'd1, 4'hF);
        mmio_write_word(RESPONSE_TIMEOUT, 32'd20000, 4'hF);
        mmio_write_word(INTER_BYTE_TIMEOUT, 32'd2000, 4'hF);
        mmio_write_word(IRQ_ENABLE, 32'h0000_000F, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        mmio_write_word(TX_DATA, 32'h0000_0001, 4'h1);

        wait_irq_status(4'b0001);
        if (!rs485_de_seen) begin
            $fatal(1, "RS-485 DE never asserted during TX");
        end
        mmio_read_word(TX_COUNT, value);
        expect_equal(value, 32'd1, "TX byte count");
        if (captured_tx_count != 10 ||
            captured_tx[0] !== 8'hFF ||
            captured_tx[2] !== 8'hFD ||
            captured_tx[4] !== 8'h01 ||
            captured_tx[7] !== 8'h01) begin
            $fatal(1, "Unexpected first transmitted Protocol 2.0 packet");
        end
        tests_passed = tests_passed + 1;

        mmio_write_word(IRQ_STATUS, 32'h0000_0001, 4'h1);
        if (irq) begin
            $fatal(1, "IRQ did not deassert after DONE W1C");
        end
        tests_passed = tests_passed + 1;

        // Second command: receive one Status Packet containing AA BB.
        build_two_parameter_status(8'd1, 8'hAA, 8'hBB);
        mmio_write_word(CMD_CONFIG, 32'h0001_0101, 4'hF);
        mmio_write_word(BODY_LENGTH, 32'd1, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        mmio_write_word(TX_DATA, 32'h0000_0001, 4'h1);
        send_motor_status();

        wait_irq_status(4'b0100);
        mmio_read_word(RX_META, value);
        expect_equal(value, 32'h0001_0000, "RX result metadata");
        mmio_read_word(RX_LENGTH, value);
        expect_equal(value, 32'd2, "RX parameter length");
        mmio_write_word(CONTROL, 32'h0000_0002, 4'h1);

        mmio_read_word(RX_DATA, value);
        expect_equal(value, 32'h0000_00AA, "first RX parameter");
        mmio_read_word(RX_DATA, value);
        expect_equal(value, 32'h0000_01BB, "last RX parameter");

        wait_irq_status(4'b0101);
        mmio_read_word(STATUS, value);
        if (value[8:0] !== 9'b0_0_0_1_0_0_0_0_1) begin
            $fatal(1, "Unexpected final STATUS value %08h", value);
        end
        tests_passed = tests_passed + 1;

        mmio_write_word(IRQ_STATUS, 32'h0000_000F, 4'h1);
        if (irq) begin
            $fatal(1, "IRQ did not deassert after W1C clear");
        end
        tests_passed = tests_passed + 1;

        // Runtime baud changes are accepted only at an idle boundary. Exercise
        // both fractional 4.5 Mbps and 6 Mbps before returning to 4 Mbps.
        mmio_write_word(BAUD_REQUEST, 32'd1, 4'hF);
        test_baud_rate = 32'd4_500_000;
        mmio_read_word(BAUD_STATUS, value);
        if (value[9:8] !== 2'd1) begin
            $fatal(1, "4.5 Mbps baud was not applied: %08h", value);
        end
        mmio_write_word(CMD_CONFIG, 32'h0000_0101, 4'hF);
        mmio_write_word(BODY_LENGTH, 32'd1, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        mmio_write_word(TX_DATA, 32'h0000_0001, 4'h1);
        wait_irq_status(4'b0001);
        mmio_write_word(IRQ_STATUS, 32'h0000_000F, 4'h1);
        tests_passed = tests_passed + 1;

        mmio_write_word(BAUD_REQUEST, 32'd2, 4'hF);
        test_baud_rate = 32'd6_000_000;
        mmio_read_word(BAUD_STATUS, value);
        if (value[9:8] !== 2'd2) begin
            $fatal(1, "6 Mbps baud was not applied: %08h", value);
        end
        mmio_write_word(CMD_CONFIG, 32'h0000_0101, 4'hF);
        mmio_write_word(BODY_LENGTH, 32'd1, 4'hF);
        mmio_write_word(CONTROL, 32'h0000_0001, 4'h1);
        mmio_write_word(TX_DATA, 32'h0000_0001, 4'h1);
        wait_irq_status(4'b0001);
        mmio_write_word(IRQ_STATUS, 32'h0000_000F, 4'h1);
        tests_passed = tests_passed + 1;

        mmio_write_word(BAUD_REQUEST, 32'd0, 4'hF);
        test_baud_rate = 32'd4_000_000;

        // RT mode: one descriptor sends a no-response PING body from Command A.
        // Feedback B must become active only after all metadata and commit are
        // written, and only one frame IRQ is generated.
        rt_mem_write_word(3'd0, 12'd0, 32'h0000_0001);
        rt_mem_write_word(3'd4, 12'd0, 32'h0008_0103); // valid, abort, ID=1, stride=8
        rt_mem_write_word(3'd4, 12'd4, 32'd0);         // command offset
        rt_mem_write_word(3'd4, 12'd8, 32'd1);         // body length
        rt_mem_write_word(3'd4, 12'd12, 32'd0);        // no response
        rt_mem_write_word(3'd4, 12'd16, 32'd0);        // expected mask
        rt_mem_write_word(3'd4, 12'd20, 32'd20000);    // response/return budget
        rt_mem_write_word(3'd4, 12'd24, 32'd10000);    // inter-byte timeout
        rt_mem_write_word(3'd4, 12'd28, 32'd0);        // ignored: no response
        rt_mem_write_word(3'd4, 12'd32, 32'd1);        // every frame
        rt_mem_write_word(3'd4, 12'd36, 32'hFFFF_FFFF);// end of chain
        mmio_write_word(DESCRIPTOR_COUNT, 32'd1, 4'hF);
        mmio_write_word(COMMAND_SEQUENCE, 32'd42, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0000, 4'hF);
        // COMMITTED ownership must make bank A immutable before frame start.
        rt_mem_write_word(3'd0, 12'd0, 32'h0000_0002);
        rt_mem_read_word(3'd0, 12'd0, value);
        expect_equal(value, 32'h0000_0001, "Committed command bank write blocked");
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);
        mmio_write_word(FRAME_PERIOD, 32'd1000, 4'hF);
        mmio_write_word(COMM_DEADLINE, 32'd1001, 4'hF);
        mmio_write_word(PROTOCOL_OWNER, 32'd0, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        wait_rt_irq_status(4'b1000);
        mmio_read_word(SCHEDULE_STATUS, value);
        if ((value & 32'h0000_0004) == 0 || rs485_de) begin
            $fatal(1, "Invalid strict timing configuration was accepted: %08h",
                   value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);
        mmio_write_word(FRAME_PERIOD, 32'd200000, 4'hF);
        mmio_write_word(COMM_DEADLINE, 32'd100000, 4'hF);
        mmio_write_word(RT_IRQ_ENABLE, 32'h0000_000F, 4'hF);
        mmio_write_word(PROTOCOL_OWNER, 32'd0, 4'hF);
        // ENABLE remains zero: SINGLE_STEP must validate and start immediately.
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);

        wait_rt_irq_status(4'b0001);
        mmio_read_word(FRAME_SEQUENCE, value);
        expect_equal(value, 32'd1, "RT frame sequence");
        rt_mem_read_word(3'd3, 12'd0, value);
        expect_equal(value, 32'd1, "Feedback frame sequence");
        rt_mem_read_word(3'd3, 12'd4, value);
        expect_equal(value, 32'd42, "Feedback command sequence");
        rt_mem_read_word(3'd3, 12'd40, value);
        expect_equal(value, 32'd1, "Feedback frame status");
        rt_mem_read_word(3'd3, 12'd52, value);
        expect_equal(value, 32'd1, "Feedback atomic commit");
        mmio_read_word(SCHEDULE_STATUS, value);
        if ((value & 32'h0000_0001) == 0 ||
            (value & 32'h0000_0006) != 0) begin
            $fatal(1, "Validated schedule status is invalid: %08h", value);
        end
        tests_passed = tests_passed + 1;
        if (captured_tx_count < 30 ||
            captured_tx[captured_tx_count-10] !== 8'hFF ||
            captured_tx[captured_tx_count-6] !== 8'h01 ||
            captured_tx[captured_tx_count-3] !== 8'h01) begin
            $fatal(1, "Unexpected RT transmitted Protocol 2.0 packet");
        end
        tests_passed = tests_passed + 1;

        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // Second RT frame receives and scatters a validated Status Packet.
        // A one-device descriptor compares the full Protocol ID, so the
        // official right-hand ID 110 is not limited by the 32-bit group mask.
        rt_mem_write_word(3'd1, 12'd0, 32'h0000_0001);
        rt_mem_write_word(3'd4, 12'd0, 32'h0008_6E03);
        rt_mem_write_word(3'd4, 12'd12, 32'd1); // one response
        rt_mem_write_word(3'd4, 12'd16, 32'd1); // logical hand slot
        rt_mem_write_word(3'd4, 12'd28, 32'd64); // feedback payload base
        mmio_write_word(COMMAND_SEQUENCE, 32'd43, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        build_two_parameter_status(8'd110, 8'hAA, 8'hBB);
        send_motor_status();
        wait_rt_irq_status(4'b0001);
        mmio_read_word(FRAME_SEQUENCE, value);
        expect_equal(value, 32'd2, "RT response frame sequence");
        mmio_read_word(RECEIVED_ID_MASK, value);
        expect_equal(value, 32'd1, "RT received device mask");
        mmio_read_word(ERROR_ID_MASK, value);
        expect_equal(value, 32'd0, "RT error device mask");
        rt_mem_read_word(3'd2, 12'd64, value);
        if (value[15:0] !== 16'hBBAA) begin
            $fatal(1, "RT scattered parameters: expected BBAA, got %04h",
                   value[15:0]);
        end
        tests_passed = tests_passed + 1;
        rt_mem_read_word(3'd2, 12'd52, value);
        expect_equal(value, 32'd2, "Second feedback atomic commit");

        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // Reusing the same command sequence is stale even when the device
        // replies successfully; the commanded device must appear in stale.
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        send_motor_status();
        wait_rt_irq_status(4'b0011);
        mmio_read_word(STALE_ID_MASK, value);
        expect_equal(value, 32'd1, "Stale-command device mask");
        mmio_read_word(COMMANDED_ID_MASK, value);
        expect_equal(value, 32'd1, "Commanded device mask");
        rt_mem_read_word(3'd3, 12'd40, value);
        if ((value & 32'h0000_0008) == 0) begin
            $fatal(1, "Stale command status was not committed: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // A schedule whose declared worst-case response budget cannot fit the
        // communication deadline must be rejected before RS-485 starts.
        rt_mem_write_word(3'd0, 12'd0, 32'h0000_0001);
        mmio_write_word(COMMAND_SEQUENCE, 32'd44, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0000, 4'hF);
        mmio_write_word(COMM_DEADLINE, 32'd5000, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd3, 4'h1);
        wait_rt_irq_status(4'b1000);
        if (rs485_de) begin
            $fatal(1, "RS-485 DE asserted for an overflowing schedule");
        end
        tests_passed = tests_passed + 1;
        mmio_read_word(SCHEDULE_STATUS, value);
        if ((value & 32'h0000_0002) == 32'd0) begin
            $fatal(1, "Schedule overflow status was not reported: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_read_word(FRAME_SEQUENCE, value);
        expect_equal(value, 32'd3, "Rejected schedule did not start a frame");

        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // A commit after the command window must not replace the already
        // committed snapshot selected for the next periodic frame.
        rt_mem_write_word(3'd4, 12'd20, 32'd6000);
        mmio_write_word(COMM_DEADLINE, 32'd10000, 4'hF);
        mmio_write_word(COMMAND_DEADLINE, 32'd11000, 4'hF);
        mmio_write_word(FRAME_PERIOD, 32'd20000, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd1, 4'h1);
        repeat (11060) @(negedge clk);
        rt_mem_write_word(3'd1, 12'd0, 32'h0000_0001);
        mmio_write_word(COMMAND_SEQUENCE, 32'd45, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'hF);
        send_motor_status();
        wait_rt_irq_status(4'b0011);
        rt_mem_read_word(3'd2, 12'd4, value);
        expect_equal(value, 32'd44, "Late commit did not replace next command");
        mmio_read_word(SCHEDULE_STATUS, value);
        if ((value & 32'h0000_0008) == 0) begin
            $fatal(1, "Late command commit status was not reported: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // Two replies deliberately arrive in ID 3, ID 1 order. Their slots
        // must still be selected by ID rank in expected_device_mask.
        mmio_write_word(COMM_DEADLINE, 32'd80000, 4'hF);
        mmio_write_word(COMMAND_DEADLINE, 32'd90000, 4'hF);
        mmio_write_word(FRAME_PERIOD, 32'd100000, 4'hF);
        rt_mem_write_word(3'd1, 12'd0, 32'h0000_0001);
        rt_mem_write_word(3'd4, 12'd12, 32'd2);
        rt_mem_write_word(3'd4, 12'd16, 32'h0000_0005); // IDs 1 and 3
        rt_mem_write_word(3'd4, 12'd20, 32'd30000);
        mmio_write_word(COMMAND_SEQUENCE, 32'd46, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        send_two_motor_statuses(
            8'd3, 8'hC3, 8'hD3,
            8'd1, 8'hA1, 8'hB1
        );
        wait_rt_irq_status(4'b0001);
        rt_mem_read_word(3'd3, 12'd64, value);
        if (value[15:0] !== 16'hB1A1) begin
            $fatal(1, "ID 1 response was mapped to wrong slot: %08h", value);
        end
        tests_passed = tests_passed + 1;
        rt_mem_read_word(3'd3, 12'd72, value);
        if (value[15:0] !== 16'hD3C3) begin
            $fatal(1, "ID 3 response was mapped to wrong slot: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // A duplicate packet must set error status but must not overwrite the
        // first validated packet already scattered into ID 1's slot.
        rt_mem_write_word(3'd0, 12'd0, 32'h0000_0001);
        mmio_write_word(COMMAND_SEQUENCE, 32'd47, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0000, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        send_two_motor_statuses(
            8'd1, 8'h11, 8'h22,
            8'd1, 8'h33, 8'h44
        );
        wait_rt_irq_status(4'b0011);
        rt_mem_read_word(3'd2, 12'd64, value);
        if (value[15:0] !== 16'h2211) begin
            $fatal(1, "Duplicate response overwrote validated data: %08h", value);
        end
        tests_passed = tests_passed + 1;
        rt_mem_read_word(3'd2, 12'd40, value);
        if ((value & 32'h0000_0030) != 32'h0000_0030) begin
            $fatal(1,
                   "Duplicate response did not abort its descriptor: %08h",
                   value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // An otherwise CRC-valid response from an unexpected ID is dropped;
        // it cannot consume ID 3's deterministic slot.
        rt_mem_write_word(3'd1, 12'd0, 32'h0000_0001);
        mmio_write_word(COMMAND_SEQUENCE, 32'd48, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        send_two_motor_statuses(
            8'd2, 8'h99, 8'h88,
            8'd1, 8'h55, 8'h66
        );
        wait_rt_irq_status(4'b0011);
        rt_mem_read_word(3'd3, 12'd64, value);
        if (value[15:0] !== 16'h6655) begin
            $fatal(1, "Expected ID data was not preserved: %08h", value);
        end
        tests_passed = tests_passed + 1;
        rt_mem_read_word(3'd3, 12'd72, value);
        if (value[15:0] !== 16'hD3C3) begin
            $fatal(1, "Unexpected ID polluted ID 3 slot: %08h", value);
        end
        tests_passed = tests_passed + 1;
        rt_mem_read_word(3'd3, 12'd40, value);
        if ((value & 32'h0000_0120) != 32'h0000_0120) begin
            $fatal(1,
                   "Unexpected ID did not abort its descriptor: %08h",
                   value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // Real HX5-D20 response size: validate all 165 parameter bytes and a
        // payload FF FF FD sequence through UART, de-stuffing, CRC, RT scatter
        // and the atomic feedback bank.
        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(BAUD_REQUEST, 32'd2, 4'hF);
        test_baud_rate = 32'd6_000_000;
        rt_mem_write_word(3'd4, 12'd0, 32'h00A5_6E03);
        rt_mem_write_word(3'd4, 12'd12, 32'd1);
        rt_mem_write_word(3'd4, 12'd16, 32'd1);
        rt_mem_write_word(3'd4, 12'd20, 32'd60000);
        rt_mem_write_word(3'd4, 12'd28, 32'd56);
        mmio_write_word(COMMAND_SEQUENCE, 32'd100, 4'hF);
        if (dut.rt_committed_command_bank) begin
            mmio_write_word(COMMAND_COMMIT, 32'h8000_0000, 4'hF);
        end else begin
            mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'hF);
        end
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        build_hx5_status(8'd110);
        send_motor_status();
        wait_rt_irq_status(4'b0001);
        mmio_read_word(RECEIVED_ID_MASK, value);
        expect_equal(value, 32'd1, "HX5 full response received mask");
        mmio_read_word(ERROR_ID_MASK, value);
        expect_equal(value, 32'd0, "HX5 full response error mask");
        if (dut.rt_active_feedback_bank) begin
            rt_mem_read_word(3'd3, 12'd56, value);
        end else begin
            rt_mem_read_word(3'd2, 12'd56, value);
        end
        expect_equal(value, 32'h1811_0A03,
                     "HX5 first four feedback bytes");
        if (dut.rt_active_feedback_bank) begin
            rt_mem_read_word(3'd3, 12'd104, value);
        end else begin
            rt_mem_read_word(3'd2, 12'd104, value);
        end
        expect_equal(value, 32'hFFFF_5A53,
                     "HX5 bytes before stuffed marker");
        if (dut.rt_active_feedback_bank) begin
            rt_mem_read_word(3'd3, 12'd108, value);
        end else begin
            rt_mem_read_word(3'd2, 12'd108, value);
        end
        expect_equal(value, 32'h847D_76FD,
                     "HX5 de-stuffed marker and following bytes");
        if (dut.rt_active_feedback_bank) begin
            rt_mem_read_word(3'd3, 12'd220, value);
        end else begin
            rt_mem_read_word(3'd2, 12'd220, value);
        end
        if (value[7:0] !== 8'h7F) begin
            $fatal(1, "HX5 final feedback byte mismatch: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);
        mmio_write_word(ABORT_FLUSH, 32'h0000_0001, 4'h1);
        mmio_write_word(BAUD_REQUEST, 32'd0, 4'hF);
        test_baud_rate = 32'd4_000_000;

        // Real 6 Mbps UART/RS-485 worst-load profile: one broadcast command
        // followed by 20 CRC-checked Status Packets in the same 1 kHz frame.
        $display("[20-device] starting 6 Mbps profile");
        rt_mem_write_word(3'd0, 12'd0, 32'h0000_0001);
        rt_mem_write_word(3'd4, 12'd0, 32'h0008_FE03); // valid, abort, FE, stride 8
        rt_mem_write_word(3'd4, 12'd4, 32'd0);
        rt_mem_write_word(3'd4, 12'd8, 32'd1);
        rt_mem_write_word(3'd4, 12'd12, 32'd20);
        rt_mem_write_word(3'd4, 12'd16, 32'h000F_FFFF); // IDs 1..20
        rt_mem_write_word(3'd4, 12'd20, 32'd6500);
        rt_mem_write_word(3'd4, 12'd24, 32'd1000);
        rt_mem_write_word(3'd4, 12'd28, 32'd64);
        rt_mem_write_word(3'd4, 12'd32, 32'd1);
        rt_mem_write_word(3'd4, 12'd36, 32'hFFFF_FFFF);
        mmio_write_word(COMM_DEADLINE, 32'd99000, 4'hF);
        mmio_write_word(COMMAND_DEADLINE, 32'd99500, 4'hF);
        mmio_write_word(FRAME_PERIOD, 32'd100000, 4'hF);
        mmio_write_word(COMMAND_SEQUENCE, 32'd49, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0000, 4'hF);

        // The conservative worst-case schedule must be rejected at 4 and
        // 4.5 Mbps before any wire activity. Report those budgets alongside
        // the successful 6 Mbps measured frame below.
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        wait_rt_irq_status(4'b1000);
        mmio_read_word(SCHEDULE_BUDGET, value);
        if (value <= 32'd99000) begin
            $fatal(1,
                   "4 Mbps 20-device budget was not rejected: %0d state=%0d count=%0d desc0=%08h owner_error=%0d",
                   value, dut.g_generic_rt.u_protocol2_rt_engine.state,
                   dut.descriptor_count_reg,
                   dut.g_generic_rt.u_protocol2_rt_engine.descriptor_mem[0],
                   dut.owner_error_reg);
        end
        $display("[4 Mbps 20-device] rejected_budget=%0d", value);
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // Best-effort mode removes the hard 1 kHz budget gate while retaining
        // each response timeout and all packet/error checks.
        mmio_write_word(COMM_DEADLINE, 32'd0, 4'hF);
        mmio_write_word(COMMAND_DEADLINE, 32'd0, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        send_twenty_motor_statuses();
        wait_rt_irq_status(4'b0001);
        mmio_read_word(SCHEDULE_STATUS, value);
        if ((value & 32'h0000_0001) == 0 ||
            (value & 32'h0000_0006) != 0) begin
            $fatal(1, "4 Mbps best-effort schedule was rejected: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_read_word(RECEIVED_ID_MASK, value);
        expect_equal(value, 32'h000F_FFFF,
                     "4 Mbps best-effort received mask");
        mmio_read_word(FRAME_CYCLES, value);
        if (value == 32'd0) begin
            $fatal(1, "4 Mbps best-effort frame duration was not recorded");
        end
        $display("[4 Mbps 20-device best-effort] frame_cycles=%0d", value);
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        mmio_write_word(COMM_DEADLINE, 32'd99000, 4'hF);
        mmio_write_word(COMMAND_DEADLINE, 32'd99500, 4'hF);
        mmio_write_word(BAUD_REQUEST, 32'd1, 4'hF);
        test_baud_rate = 32'd4_500_000;
        rt_mem_write_word(3'd4, 12'd20, 32'd6000);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        wait_rt_irq_status(4'b1000);
        mmio_read_word(SCHEDULE_BUDGET, value);
        if (value <= 32'd99000) begin
            $fatal(1, "4.5 Mbps 20-device budget was not rejected: %0d", value);
        end
        $display("[4.5 Mbps 20-device] rejected_budget=%0d", value);
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        mmio_write_word(BAUD_REQUEST, 32'd2, 4'hF);
        test_baud_rate = 32'd6_000_000;
        rt_mem_write_word(3'd4, 12'd20, 32'd4500);
        mmio_write_word(COMMAND_SEQUENCE, 32'd50, 4'hF);
        mmio_write_word(COMMAND_COMMIT, 32'h8000_0001, 4'hF);
        mmio_write_word(RT_CONTROL, 32'd2, 4'h1);
        send_twenty_motor_statuses();
        wait_rt_irq_status(4'b0001);
        mmio_read_word(RECEIVED_ID_MASK, value);
        expect_equal(value, 32'h000F_FFFF, "20-device received mask");
        mmio_read_word(ERROR_ID_MASK, value);
        expect_equal(value, 32'd0, "20-device error mask");
        if (dut.rt_active_feedback_bank) begin
            rt_mem_read_word(3'd3, 12'd216, value);
        end else begin
            rt_mem_read_word(3'd2, 12'd216, value);
        end
        if (value[15:0] !== 16'hEB14) begin
            $fatal(1, "ID 20 feedback slot mismatch: %08h", value);
        end
        tests_passed = tests_passed + 1;
        mmio_read_word(FRAME_CYCLES, value);
        if ((value == 32'd0) || (value >= 32'd99000)) begin
            $fatal(1, "6 Mbps 20-device frame cycles invalid: %0d", value);
        end
        $display("[6 Mbps 20-device] frame_cycles=%0d", value);
        mmio_read_word(MINIMUM_SLACK, value);
        if (value == 32'd0) begin
            $fatal(1, "6 Mbps 20-device frame has no measured slack");
        end
        $display("[6 Mbps 20-device] minimum_slack=%0d", value);
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_CONTROL, 32'd0, 4'h1);
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);

        // W1C must be set-dominant when clear and a new event share a cycle.
        force dut.rt_frame_done = 1'b1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_0001, 4'h1);
        release dut.rt_frame_done;
        mmio_read_word(RT_IRQ_STATUS, value);
        if (!value[0]) begin
            $fatal(1, "RT IRQ clear lost a same-cycle frame-done event");
        end
        tests_passed = tests_passed + 1;
        mmio_write_word(RT_IRQ_STATUS, 32'h0000_000F, 4'h1);
        mmio_write_word(PROTOCOL_OWNER, 32'd1, 4'hF);

        $display("[MMIO WRAPPER PASS] %0d checks passed", tests_passed);
        $finish;
    end

endmodule
