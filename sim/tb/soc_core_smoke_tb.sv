`timescale 1ns/1ps
`include "asl_soc_config.svh"

module soc_core_smoke_tb;
    localparam int MOTOR_COUNT = 20;
    localparam int COMMAND_BANK_WORDS =
        `ASL_SOC_PROTOCOL_COMMAND_BYTES / 4;
    localparam int HX5_FRAME_BYTES = 96;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic mmio_valid;
    logic mmio_ready;
    logic mmio_write;
    logic [31:0] mmio_addr;
    logic [31:0] mmio_wdata;
    logic [3:0] mmio_wstrb;
    logic [31:0] mmio_rdata;
    logic mmio_error;

    logic eth_rx_valid;
    logic [31:0] eth_rx_data;
    logic [3:0] eth_rx_keep;
    logic eth_rx_last;
    logic eth_rx_ready;
    logic eth_tx_valid;
    logic [31:0] eth_tx_data;
    logic [3:0] eth_tx_keep;
    logic eth_tx_last;
    logic eth_tx_ready = 1'b1;

    logic emergency_stop_n;
    logic external_fault;
    logic torque_enable_request;
    logic watchdog_enable;
    logic watchdog_kick;
    logic safety_clear_fault;
    logic torque_enable_allow;
    logic rs485_de_inhibit;
    logic watchdog_fault;
    logic safety_fault_latched;

    logic cnn_test_class_valid;
    logic [7:0] cnn_test_class_id;
    logic [7:0] cnn_test_confidence;
    logic cnn_clear_irq;
    logic cnn_busy;
    logic cnn_done;
    logic cnn_error;
    logic [7:0] cnn_class_id;
    logic [7:0] cnn_confidence;
    logic cnn_irq;

    logic protocol_command_valid;
    logic protocol_command_ready = 1'b1;
    logic [$clog2(MOTOR_COUNT)-1:0] protocol_motor_index;
    logic [15:0] protocol_command_position;
    logic protocol_command_last;
    logic protocol_command_commit;
    logic [31:0] protocol_command_sequence;
    logic pose_frame_busy;
    logic [7:0] pose_active_class_id;

    logic [3:0] m_axi_awid;
    logic [31:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen;
    logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst;
    logic m_axi_awvalid;
    logic m_axi_awready;
    logic [31:0] m_axi_wdata;
    logic [3:0] m_axi_wstrb;
    logic m_axi_wlast;
    logic m_axi_wvalid;
    logic m_axi_wready;
    logic [3:0] m_axi_bid;
    logic [1:0] m_axi_bresp;
    logic m_axi_bvalid;
    logic m_axi_bready;
    logic [3:0] m_axi_arid;
    logic [31:0] m_axi_araddr;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst;
    logic m_axi_arvalid;
    logic m_axi_arready;
    logic [3:0] m_axi_rid;
    logic [31:0] m_axi_rdata;
    logic [1:0] m_axi_rresp;
    logic m_axi_rlast;
    logic m_axi_rvalid;
    logic m_axi_rready;

    logic ethernet_frame_irq;
    logic [31:0] ethernet_frame_bytes;
    logic [31:0] ethernet_frame_checksum;
    logic host_uart_rx = 1'b1;
    logic host_uart_tx;
    logic host_uart_irq;
    logic rs485_rx = 1'b1;
    logic rs485_tx;
    logic rs485_de;
    logic protocol_irq;

    logic [31:0] attr_address;
    logic attr_local;
    logic attr_mmio;
    logic attr_dram;
    logic attr_uncached;
    logic attr_cached_dram;

    integer checks = 0;
    integer command_count = 0;
    integer timeout;
    integer command_byte_index;

    soc_core_top #(
        .ENABLE_CPU            (1'b0),
        .CPU_OWNS_PROTOCOL_COMMANDS(1'b0),
        .CPU_HZ                 (100_000_000),
        .RT_FRAME_HZ            (1_000),
        .RT_FRAME_CYCLES_OVERRIDE(100),
        .MOTOR_COUNT            (MOTOR_COUNT),
        .CNN_STUB_LATENCY_CYCLES(12),
        .HOST_UART_BAUD         (10_000_000),
        .WATCHDOG_TIMEOUT_CYCLES(8),
        .POSE_MAX_STEP          (16'd1024),
        .POSE_GOAL_CURRENT      (16'h1234),
        .POSE_GOAL_VELOCITY     (32'h89AB_CDEF),
        .POSE_PROFILE_ACCELERATION(32'h1020_3040),
        .POSE_PROFILE_VELOCITY  (32'h5060_7080)
    ) dut (.*);

    function automatic logic [7:0] expected_hx5_byte(input integer byte_index);
        integer payload_byte;
        integer motor;
        integer axis_byte;
        integer position;
        begin
            expected_hx5_byte = 8'd0;

            if (byte_index == 0) begin
                expected_hx5_byte = 8'h83;
            end else if (byte_index == 1) begin
                expected_hx5_byte = 8'h1F;
            end else if (byte_index == 2) begin
                expected_hx5_byte = 8'h03;
            end else if (byte_index == 3) begin
                expected_hx5_byte = 8'h50;
            end else if (byte_index == 4) begin
                expected_hx5_byte = 8'h00;
            end else if (byte_index == 5) begin
                expected_hx5_byte = 8'd110;
            end else if (byte_index < 86) begin
                payload_byte = byte_index - 6;
                motor = payload_byte / 4;
                axis_byte = payload_byte % 4;
                position = 2200 + motor * 4;
                case (axis_byte)
                    0: expected_hx5_byte = position[7:0];
                    1: expected_hx5_byte = position[15:8];
                    2: expected_hx5_byte = 8'h34;
                    3: expected_hx5_byte = 8'h12;
                    default: expected_hx5_byte = 8'd0;
                endcase
            end else if (byte_index == 88) begin
                expected_hx5_byte = 8'h02;
            end else if (byte_index == 89) begin
                expected_hx5_byte = 8'h7A;
            end else if (byte_index == 90) begin
                expected_hx5_byte = 8'h02;
            end else if (byte_index == 91) begin
                expected_hx5_byte = 8'hA5;
            end else if (byte_index == 92) begin
                expected_hx5_byte = 8'h00;
            end
        end
    endfunction

    function automatic logic [7:0] command_memory_byte(
         input integer bank
        ,input integer byte_index
    );
        integer memory_word_index;
        logic [31:0] memory_word;
        begin
            memory_word_index = bank * COMMAND_BANK_WORDS + byte_index / 4;
            memory_word =
                dut.u_protocol2_mmio_wrapper.g_hx5_rt.
                    u_protocol2_rt_engine.command_mem[
                    memory_word_index
                ];
            case (byte_index % 4)
                0: command_memory_byte = memory_word[7:0];
                1: command_memory_byte = memory_word[15:8];
                2: command_memory_byte = memory_word[23:16];
                default: command_memory_byte = memory_word[31:24];
            endcase
        end
    endfunction

    axi_dram_model #(
        .MEMORY_BYTES(65_536)
    ) dram (
        .clk(clk), .rst(rst),
        .s_axi_awid(m_axi_awid), .s_axi_awaddr(m_axi_awaddr),
        .s_axi_awlen(m_axi_awlen), .s_axi_awsize(m_axi_awsize),
        .s_axi_awburst(m_axi_awburst), .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready), .s_axi_wdata(m_axi_wdata),
        .s_axi_wstrb(m_axi_wstrb), .s_axi_wlast(m_axi_wlast),
        .s_axi_wvalid(m_axi_wvalid), .s_axi_wready(m_axi_wready),
        .s_axi_bid(m_axi_bid), .s_axi_bresp(m_axi_bresp),
        .s_axi_bvalid(m_axi_bvalid), .s_axi_bready(m_axi_bready),
        .s_axi_arid(m_axi_arid), .s_axi_araddr(m_axi_araddr),
        .s_axi_arlen(m_axi_arlen), .s_axi_arsize(m_axi_arsize),
        .s_axi_arburst(m_axi_arburst), .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready), .s_axi_rid(m_axi_rid),
        .s_axi_rdata(m_axi_rdata), .s_axi_rresp(m_axi_rresp),
        .s_axi_rlast(m_axi_rlast), .s_axi_rvalid(m_axi_rvalid),
        .s_axi_rready(m_axi_rready)
    );

    address_attributes attrs (
        .address       (attr_address),
        .is_local      (attr_local),
        .is_mmio       (attr_mmio),
        .is_dram       (attr_dram),
        .is_uncached   (attr_uncached),
        .is_cached_dram(attr_cached_dram)
    );

    task automatic check_condition(input logic condition, input string message);
        begin
            if (!condition) begin
                $display("FAIL: %s", message);
                $fatal(1);
            end
            checks = checks + 1;
        end
    endtask

    task automatic send_word(
        input logic [31:0] data,
        input logic [3:0] keep,
        input logic last
    );
        begin
            @(negedge clk);
            eth_rx_valid = 1'b1;
            eth_rx_data  = data;
            eth_rx_keep  = keep;
            eth_rx_last  = last;
            while (!eth_rx_ready)
                @(negedge clk);
            @(negedge clk);
            eth_rx_valid = 1'b0;
            eth_rx_last  = 1'b0;
        end
    endtask

    task automatic mmio_write32(
        input logic [31:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            mmio_valid = 1'b1;
            mmio_write = 1'b1;
            mmio_addr  = address;
            mmio_wdata = data;
            mmio_wstrb = 4'hF;
            while (!mmio_ready)
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            mmio_valid = 1'b0;
            mmio_write = 1'b0;
            mmio_wstrb = 4'd0;
        end
    endtask

    task automatic mmio_read32(
        input  logic [31:0] address,
        output logic [31:0] data
    );
        begin
            @(negedge clk);
            mmio_valid = 1'b1;
            mmio_write = 1'b0;
            mmio_addr  = address;
            mmio_wstrb = 4'd0;
            while (!mmio_ready)
                @(negedge clk);
            #1 data = mmio_rdata;
            @(posedge clk);
            @(negedge clk);
            mmio_valid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst && protocol_command_valid && dut.pose_adapter_ready &&
            pose_active_class_id == 8'd1 && command_count < MOTOR_COUNT) begin
            check_condition(protocol_motor_index == command_count,
                   "pose stream motor index must be sequential");
            check_condition(protocol_command_position == 2200 + command_count * 4,
                   "class A must select the expected per-axis position");
            command_count = command_count + 1;
        end
    end

    initial begin
        eth_rx_valid            = 1'b0;
        eth_rx_data             = 32'd0;
        eth_rx_keep             = 4'd0;
        eth_rx_last             = 1'b0;
        mmio_valid              = 1'b0;
        mmio_write              = 1'b0;
        mmio_addr               = 32'd0;
        mmio_wdata              = 32'd0;
        mmio_wstrb              = 4'd0;
        emergency_stop_n        = 1'b1;
        external_fault          = 1'b0;
        torque_enable_request   = 1'b1;
        watchdog_enable         = 1'b0;
        watchdog_kick           = 1'b0;
        safety_clear_fault      = 1'b0;
        cnn_test_class_valid    = 1'b0;
        cnn_test_class_id       = 8'd0;
        cnn_test_confidence     = 8'd0;
        cnn_clear_irq           = 1'b0;
        attr_address            = 32'd0;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        check_condition(torque_enable_allow, "safe reset state must allow requested torque");
        check_condition(!rs485_de_inhibit, "safe reset state must not inhibit RS-485");

        mmio_read32(32'h1003_0030, mmio_wdata);
        check_condition(mmio_wdata == 32'h5032_4D4D,
               "Protocol 2.0 ID register must be reachable through SoC MMIO");
        mmio_read32(32'h1003_7000, mmio_wdata);
        check_condition(mmio_wdata == 32'h5541_5254,
               "Host UART ID register must be reachable through SoC MMIO");
        mmio_read32(32'h1003_501C, mmio_wdata);
        check_condition(mmio_wdata == 32'd110,
               "right-hand Protocol ID must default to 110");
        mmio_write32(32'h1003_501C, 32'd111);
        mmio_read32(32'h1003_501C, mmio_wdata);
        check_condition(mmio_wdata == 32'd111,
               "software must be able to update the hand Protocol ID");
        mmio_write32(32'h1003_501C, 32'd110);
        mmio_write32(32'h1003_2014, 32'h8000_E601);
        mmio_read32(32'h1003_2014, mmio_wdata);
        check_condition(mmio_wdata == 32'h8000_E601,
               "CNN class override must round-trip through MMIO");

        @(negedge clk);
        mmio_valid = 1'b1;
        mmio_write = 1'b0;
        mmio_addr  = 32'h1003_8000;
        #1;
        check_condition(mmio_ready && mmio_error,
               "unimplemented MMIO page must complete with an error response");
        @(negedge clk);
        mmio_valid = 1'b0;

        attr_address = 32'h0000_0100; #1;
        check_condition(attr_local && attr_uncached && !attr_dram,
               "Boot ROM must bypass the cache");
        attr_address = 32'h0001_0100; #1;
        check_condition(attr_local && attr_uncached && !attr_dram,
               "ITCM must bypass the cache");
        attr_address = 32'h0002_0100; #1;
        check_condition(attr_local && attr_uncached && !attr_dram,
               "DTCM must bypass the cache");
        attr_address = 32'h1003_2000; #1;
        check_condition(attr_mmio && attr_uncached && !attr_cached_dram,
               "CNN MMIO page must be uncached");
        attr_address = 32'h2000_0100; #1;
        check_condition(attr_dram && attr_uncached && !attr_cached_dram,
               "DMA DRAM window must be uncached");
        attr_address = 32'h2100_0100; #1;
        check_condition(attr_dram && !attr_uncached && attr_cached_dram,
               "general DRAM window must be cached");

        send_word(32'h4433_2211, 4'b1111, 1'b0);
        send_word(32'h8877_6655, 4'b1111, 1'b0);
        send_word(32'h0000_AA99, 4'b0011, 1'b1);

        timeout = 0;
        while (!cnn_done && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check_condition(timeout < 200, "Ethernet frame must start and complete CNN stub");
        check_condition(ethernet_frame_bytes == 10, "DMA byte count must honor tkeep");
        check_condition(cnn_class_id == 1 && cnn_confidence == 230,
               "CNN stub must return configured class and confidence");
        check_condition(cnn_irq && !cnn_error, "CNN completion must raise a clean IRQ");
        check_condition(dut.cnn_dma_checksum == ethernet_frame_checksum &&
                        dut.cnn_dma_bytes_read == 10,
               "CNN DMA must read the complete Ethernet payload from DRAM");
        check_condition(dram.mem[0] == 8'h11 && dram.mem[1] == 8'h22 &&
               dram.mem[8] == 8'h99 && dram.mem[9] == 8'hAA,
               "Ethernet DMA must preserve byte lanes in DRAM");
        mmio_read32(32'h1003_2018, mmio_wdata);
        check_condition(mmio_wdata[15:0] == 16'hE601,
               "CNN result must be software-readable through MMIO");
        mmio_read32(32'h1003_2020, mmio_wdata);
        check_condition(mmio_wdata == ethernet_frame_checksum,
               "CNN DMA checksum must be software-readable through MMIO");
        mmio_read32(32'h1003_2024, mmio_wdata);
        check_condition(mmio_wdata == 10,
               "CNN DMA byte count must be software-readable through MMIO");
        mmio_read32(32'h1003_3014, mmio_wdata);
        check_condition(mmio_wdata == 1,
               "Ethernet frame sequence must be software-readable");

        timeout = 0;
        while (!protocol_command_commit && timeout < 300) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check_condition(timeout < 300, "pose player must commit one 20-axis frame");
        check_condition(command_count == MOTOR_COUNT,
               "pose commit must follow exactly 20 accepted commands");
        check_condition(protocol_command_sequence == 1,
               "pose command sequence must increment on commit");

        timeout = 0;
        while (dut.pose_protocol_sequence != 1 && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check_condition(timeout < 200,
               "pose adapter must finish Protocol command-bank commit");
        check_condition(dut.pose_protocol_bank && !dut.pose_protocol_error,
               "first pose frame must commit cleanly into command bank B");
        for (command_byte_index = 0;
             command_byte_index < HX5_FRAME_BYTES;
             command_byte_index = command_byte_index + 1) begin
            check_condition(
                command_memory_byte(1, command_byte_index) ==
                    expected_hx5_byte(command_byte_index),
                "HX5 indirect-data frame must reach Protocol bank B"
            );
        end
        mmio_read32(32'h1003_5014, mmio_wdata);
        check_condition(mmio_wdata[3:0] == 4'b1001,
               "Pose MMIO must report committed bank and clean adapter state");
        mmio_read32(32'h1003_5018, mmio_wdata);
        check_condition(mmio_wdata == 1,
               "Pose MMIO must report Protocol committed sequence");

        timeout = 0;
        while (dut.pose_protocol_sequence != 2 && timeout < 200) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        check_condition(timeout < 200,
               "next 1 kHz pose frame must complete a second bank commit");
        check_condition(!dut.pose_protocol_bank && !dut.pose_protocol_error,
               "second pose frame must alternate cleanly into command bank A");
        for (command_byte_index = 0;
             command_byte_index < HX5_FRAME_BYTES;
             command_byte_index = command_byte_index + 1) begin
            check_condition(
                command_memory_byte(0, command_byte_index) ==
                    expected_hx5_byte(command_byte_index),
                "second HX5 indirect-data frame must reach Protocol bank A"
            );
        end

        mmio_write32(32'h1003_6004, 32'h0000_0000);
        #1;
        check_condition(!torque_enable_allow,
               "software torque request must be able to disable torque");
        mmio_write32(32'h1003_6004, 32'h0000_0001);
        #1;
        check_condition(torque_enable_allow,
               "software torque request may re-enable only while hardware is safe");

        force dut.protocol_rs485_de = 1'b1;
        #1;
        check_condition(rs485_de,
               "Protocol DE must pass through while the safety supervisor is clear");

        emergency_stop_n = 1'b0;
        #1;
        check_condition(!torque_enable_allow && rs485_de_inhibit && !rs485_de,
               "E-stop must gate torque and RS-485 without a clock wait");
        @(posedge clk);
        emergency_stop_n = 1'b1;
        @(posedge clk);
        check_condition(safety_fault_latched && rs485_de_inhibit,
               "E-stop must remain latched after physical release");
        @(negedge clk);
        safety_clear_fault = 1'b1;
        @(posedge clk);
        @(negedge clk);
        safety_clear_fault = 1'b0;
        #1;
        check_condition(torque_enable_allow && !rs485_de_inhibit,
               "safe explicit clear must release the safety latch");
        check_condition(rs485_de,
               "Protocol DE may pass again only after an explicit safe clear");
        release dut.protocol_rs485_de;

        watchdog_enable = 1'b1;
        repeat (10) @(posedge clk);
        #1;
        check_condition(watchdog_fault && !torque_enable_allow && rs485_de_inhibit,
               "watchdog timeout must enter the same hardware-safe state");
        @(negedge clk);
        watchdog_enable    = 1'b0;
        safety_clear_fault = 1'b1;
        @(posedge clk);
        @(negedge clk);
        safety_clear_fault = 1'b0;
        #1;
        check_condition(!watchdog_fault && torque_enable_allow,
               "watchdog fault must clear only through explicit safe clear");

        mmio_read32(32'h1003_1000, mmio_wdata);
        check_condition(mmio_wdata == 32'h4C49_4330,
               "local interrupt controller ID must be reachable");
        mmio_read32(32'h1003_1004, mmio_wdata);
        check_condition(mmio_wdata[7:0] == 8,
               "interrupt controller must expose all eight sources");
        mmio_write32(32'h1003_100C, 32'h0000_0001);
        mmio_write32(32'h1003_1044, 32'h0000_00FF);
        mmio_write32(32'h1003_1040, 32'h0000_0001);
        mmio_read32(32'h1003_1008, mmio_wdata);
        check_condition(mmio_wdata[0] && dut.local_external_irq,
               "software-pended enabled source must raise external IRQ");
        mmio_read32(32'h1003_101C, mmio_wdata);
        check_condition(mmio_wdata == 1,
               "claim must return the lowest-ID highest-priority source");
        mmio_read32(32'h1003_1048, mmio_wdata);
        check_condition(mmio_wdata[0] && !dut.local_external_irq,
               "claim must atomically move source into service");
        mmio_write32(32'h1003_101C, 32'h0000_0001);
        mmio_read32(32'h1003_1048, mmio_wdata);
        check_condition(!mmio_wdata[0],
               "completion must release the claimed source");

        mmio_write32(32'h1003_4004, 32'hFFFF_FFFF);
        mmio_write32(32'h1003_4000, 32'd20);
        mmio_write32(32'h1003_400C, 32'd0);
        mmio_write32(32'h1003_4008, 32'd0);
        mmio_write32(32'h1003_4004, 32'd0);
        repeat (25) @(posedge clk);
        check_condition(dut.machine_timer_irq,
               "mtime >= mtimecmp must assert the CPU timer interrupt");
        mmio_read32(32'h1003_4008, mmio_wdata);
        check_condition(mmio_wdata >= 20,
               "machine timer must increment and be software readable");
        mmio_write32(32'h1003_4004, 32'hFFFF_FFFF);
        check_condition(!dut.machine_timer_irq,
               "raising mtimecmp must deassert the timer interrupt");

        $display("PASS: soc_core_smoke_tb (%0d checks)", checks);
        $finish;
    end

    initial begin
        #20_000;
        $fatal(1, "global timeout");
    end

endmodule
