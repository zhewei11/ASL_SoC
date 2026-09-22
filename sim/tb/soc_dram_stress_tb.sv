`timescale 1ns/1ps

module soc_dram_stress_tb;
    localparam int MOTOR_COUNT = 20;
    localparam int MEMORY_BYTES = 131_072;
    localparam int FRAME_WORDS = 6_400;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic mmio_valid = 0, mmio_ready, mmio_write = 0, mmio_error;
    logic [31:0] mmio_addr = 0, mmio_wdata = 0, mmio_rdata;
    logic [3:0] mmio_wstrb = 0;
    logic eth_rx_valid = 0, eth_rx_last = 0, eth_rx_ready;
    logic [31:0] eth_rx_data = 0;
    logic [3:0] eth_rx_keep = 0;
    logic eth_tx_valid, eth_tx_last, eth_tx_ready = 1;
    logic [31:0] eth_tx_data;
    logic [3:0] eth_tx_keep;
    logic emergency_stop_n = 1, external_fault = 0;
    logic torque_enable_request = 1, watchdog_enable = 0;
    logic watchdog_kick = 0, safety_clear_fault = 0;
    logic torque_enable_allow, rs485_de_inhibit, watchdog_fault;
    logic safety_fault_latched;
    logic cnn_test_class_valid = 0, cnn_clear_irq = 0;
    logic [7:0] cnn_test_class_id = 0, cnn_test_confidence = 0;
    logic cnn_busy, cnn_done, cnn_error, cnn_irq;
    logic [7:0] cnn_class_id, cnn_confidence;
    logic protocol_command_valid, protocol_command_ready = 1;
    logic [$clog2(MOTOR_COUNT)-1:0] protocol_motor_index;
    logic [15:0] protocol_command_position;
    logic protocol_command_last, protocol_command_commit;
    logic [31:0] protocol_command_sequence;
    logic pose_frame_busy;
    logic [7:0] pose_active_class_id;
    logic [3:0] m_axi_awid, m_axi_wstrb, m_axi_bid, m_axi_arid, m_axi_rid;
    logic [31:0] m_axi_awaddr, m_axi_wdata, m_axi_araddr, m_axi_rdata;
    logic [7:0] m_axi_awlen, m_axi_arlen;
    logic [2:0] m_axi_awsize, m_axi_arsize;
    logic [1:0] m_axi_awburst, m_axi_bresp, m_axi_arburst, m_axi_rresp;
    logic m_axi_awvalid, m_axi_awready, m_axi_wlast, m_axi_wvalid;
    logic m_axi_wready, m_axi_bvalid, m_axi_bready;
    logic m_axi_arvalid, m_axi_arready, m_axi_rlast;
    logic m_axi_rvalid, m_axi_rready;
    logic ethernet_frame_irq;
    logic [31:0] ethernet_frame_bytes, ethernet_frame_checksum;
    logic host_uart_rx = 1, host_uart_tx, host_uart_irq;
    logic rs485_rx = 1, rs485_tx, rs485_de, protocol_irq;

    integer checks = 0;
    integer cycles = 0;
    integer init_index;
    integer ethernet_reads = 0;
    integer ethernet_writes = 0;
    integer ethernet_write_beats = 0;
    integer ethernet_frames = 0;
    integer cnn_reads = 0;
    integer cpu_reads = 0;
    integer cnn_completions = 0;
    integer protocol_frames = 0;
    integer previous_rt_sequence = 0;
    integer previous_rt_trigger_cycle = 0;
    integer cpu_read_wait = 0;
    integer cnn_read_wait = 0;
    integer max_cpu_read_wait = 0;
    integer max_cnn_read_wait = 0;
    logic protocol_deadline_seen = 0;
    logic protocol_interval_error = 0;
    logic protocol_de_seen = 0;
    logic ethernet_size_error = 0;
    logic read_contention_seen = 0;
    logic dma_duplex_seen = 0;
    logic dram_delay_seen = 0;
    logic test_done = 0;

    soc_core_top #(
        .ENABLE_CPU(1'b1),
        .CPU_OWNS_PROTOCOL_COMMANDS(1'b0),
        .USE_HX5_RT_SEQUENCER(1'b0),
        .BOOT_ROM_INIT_FILE("build/dram_stress.mem"),
        .RT_FRAME_CYCLES_OVERRIDE(100_000),
        .CNN_STUB_LATENCY_CYCLES(32)
    ) dut (.*);

    axi_dram_model #(
        .MEMORY_BYTES(MEMORY_BYTES),
        .READ_LATENCY_CYCLES(5),
        .WRITE_RESPONSE_LATENCY_CYCLES(4),
        .READY_STALL_CYCLES(3),
        .RANDOM_READ_LATENCY_CYCLES(11),
        .RANDOM_WRITE_LATENCY_CYCLES(9),
        .RANDOM_READY_STALL_CYCLES(7),
        .RANDOM_SEED(32'hc001_cafe)
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

`ifdef ASL_SOC_SVA
    axi_master_assertions u_axi_master_assertions (
        .clk(clk), .rst(rst), .awid(m_axi_awid), .awaddr(m_axi_awaddr),
        .awlen(m_axi_awlen), .awsize(m_axi_awsize),
        .awburst(m_axi_awburst), .awvalid(m_axi_awvalid),
        .awready(m_axi_awready), .wdata(m_axi_wdata),
        .wstrb(m_axi_wstrb), .wlast(m_axi_wlast),
        .wvalid(m_axi_wvalid), .wready(m_axi_wready),
        .arid(m_axi_arid), .araddr(m_axi_araddr), .arlen(m_axi_arlen),
        .arsize(m_axi_arsize), .arburst(m_axi_arburst),
        .arvalid(m_axi_arvalid), .arready(m_axi_arready)
    );
`endif

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            $fatal(1);
        end
        checks++;
        $display("PASS: %s", message);
    endtask

    task automatic send_full_ethernet_frame(input integer frame_number);
        integer word_index;
        begin
            for (word_index = 0; word_index < FRAME_WORDS; word_index++) begin
                @(negedge clk);
                eth_rx_valid = 1'b1;
                eth_rx_data = 32'(frame_number ^ word_index ^ 32'hA5A5_0000);
                eth_rx_keep = 4'hf;
                eth_rx_last = (word_index == FRAME_WORDS - 1);
                while (!eth_rx_ready)
                    @(negedge clk);
            end
            @(negedge clk);
            eth_rx_valid = 1'b0;
            eth_rx_last = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            cycles <= cycles + 1;
            if (m_axi_awvalid && m_axi_awready &&
                m_axi_awaddr >= 32'h2000_0000 &&
                m_axi_awaddr < 32'h2000_6400)
                ethernet_writes <= ethernet_writes + 1;
            if (m_axi_wvalid && m_axi_wready &&
                dut.fabric_write_owner == 2)
                ethernet_write_beats <= ethernet_write_beats + 1;
            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_araddr >= 32'h2001_0000 &&
                    m_axi_araddr < 32'h2002_0000)
                    cpu_reads <= cpu_reads + 1;
                if (m_axi_araddr < 32'h2000_6400)
                    ethernet_reads <= ethernet_reads + 1;
            end
            if (m_axi_rvalid && m_axi_rready && m_axi_rid == 4'd3)
                cnn_reads <= cnn_reads + 1;
            if (cnn_done)
                cnn_completions <= cnn_completions + 1;
            if (dut.frame_done) begin
                ethernet_frames <= ethernet_frames + 1;
                if (ethernet_frame_bytes != 25_600 || dut.frame_error)
                    ethernet_size_error <= 1'b1;
            end
            if (dut.u_protocol2_mmio_wrapper.rt_frame_done)
                protocol_frames <= protocol_frames + 1;
            if (dut.u_protocol2_mmio_wrapper.rt_frame_deadline)
                protocol_deadline_seen <= 1'b1;
            if (dut.protocol_rs485_de)
                protocol_de_seen <= 1'b1;
            if (dut.fabric_arvalid[1] && dut.fabric_arvalid[2])
                read_contention_seen <= 1'b1;
            if (dut.fabric_wvalid[2] && dut.fabric_rvalid[2])
                dma_duplex_seen <= 1'b1;
            if (dram.read_pending || dram.write_response_pending ||
                dram.read_ready_stall != 0 || dram.write_ready_stall != 0)
                dram_delay_seen <= 1'b1;

            if (dut.fabric_arvalid[1] && !dut.fabric_arready[1]) begin
                cpu_read_wait <= cpu_read_wait + 1;
                if (cpu_read_wait + 1 > max_cpu_read_wait)
                    max_cpu_read_wait <= cpu_read_wait + 1;
            end else begin
                cpu_read_wait <= 0;
            end
            if (dut.fabric_arvalid[2] && !dut.fabric_arready[2]) begin
                cnn_read_wait <= cnn_read_wait + 1;
                if (cnn_read_wait + 1 > max_cnn_read_wait)
                    max_cnn_read_wait <= cnn_read_wait + 1;
            end else begin
                cnn_read_wait <= 0;
            end

            if (dut.u_protocol2_mmio_wrapper.rt_frame_sequence !=
                previous_rt_sequence) begin
                if (previous_rt_sequence != 0 &&
                    cycles - previous_rt_trigger_cycle != 100_000)
                    protocol_interval_error <= 1'b1;
                previous_rt_sequence <=
                    dut.u_protocol2_mmio_wrapper.rt_frame_sequence;
                previous_rt_trigger_cycle <= cycles;
            end
        end
    end

    initial begin
        for (init_index = 0; init_index < MEMORY_BYTES; init_index++)
            dram.mem[init_index] = 8'(init_index ^ (init_index >> 8));

        repeat (8) @(posedge clk);
        rst = 1'b0;

        while (dut.u_soc_cpu_cluster.u_dtcm.memory[0] !== 32'h5354_5253 &&
               cycles < 20_000)
            @(posedge clk);
        check(cycles < 20_000,
              "CPU firmware configures Protocol and CNN stress engines");

        fork
            begin : ethernet_stimulus
                integer frame_index;
                frame_index = 0;
                while (!test_done) begin
                    send_full_ethernet_frame(frame_index);
                    frame_index = frame_index + 1;
                end
            end
        join_none

        while (protocol_frames < 5 && cycles < 650_000)
            @(posedge clk);
        test_done = 1'b1;
        repeat (10) @(posedge clk);

        $display("Stress counters before checks: CPU reads=%0d CNN reads=%0d ETH writes=%0d CNN done=%0d Protocol frames=%0d frame_cycles=%0d min_slack=%0d",
                 cpu_reads, cnn_reads, ethernet_writes, cnn_completions,
                 protocol_frames,
                 dut.u_protocol2_mmio_wrapper.rt_last_frame_cycles,
                 dut.u_protocol2_mmio_wrapper.rt_minimum_slack);

        check(protocol_frames >= 5,
              "five real 100,000-cycle Protocol frames complete");
        check(!protocol_interval_error,
              "Protocol trigger interval remains exactly 100,000 cycles");
        check(!protocol_deadline_seen,
              "Protocol reports no deadline miss under DRAM saturation");
        check(dut.u_protocol2_mmio_wrapper.rt_last_frame_cycles > 32'd1000 &&
              dut.u_protocol2_mmio_wrapper.rt_last_frame_cycles < 32'd70_000,
              "real RS-485 transaction completes inside 700 us deadline");
        check(dut.u_protocol2_mmio_wrapper.rt_minimum_slack > 32'd0,
              "Protocol minimum deadline slack remains positive");
        check(dut.u_protocol2_mmio_wrapper.rt_schedule_valid &&
              !dut.u_protocol2_mmio_wrapper.rt_schedule_overflow &&
              !dut.u_protocol2_mmio_wrapper.rt_schedule_config_error,
              "Protocol schedule remains valid during stress");
        check(protocol_de_seen,
              "Protocol exercises the real RS-485 transmit path");
        check(cpu_reads > 8_000,
              "CPU continuously reads uncached DRAM during the test");
        check(cnn_reads >= FRAME_WORDS * 2,
              "CNN DMA completes multiple full 25,600-byte DRAM scans");
        check(cnn_completions >= 2 && !cnn_error,
              "CNN DMA/stub repeatedly completes without error");
        check(ethernet_writes >= (FRAME_WORDS / 16) * 2 &&
              ethernet_write_beats >= FRAME_WORDS * 2,
              "Ethernet burst DMA writes multiple maximum-size frames");
        check(dma_duplex_seen,
              "S2MM and MM2S DMA channels make concurrent AXI progress");
        check(ethernet_frames >= 2 && !ethernet_size_error &&
              ethernet_reads == 0,
              "Ethernet traffic remains write-only and preserves frame size");
        check(dram_delay_seen,
              "stress run exercises configured DRAM response latency and stalls");
        check(read_contention_seen && max_cpu_read_wait < 64 &&
              max_cnn_read_wait < 64,
              "round-robin read arbitration gives CPU and CNN bounded progress");

        $display("Stress counters: CPU reads=%0d CNN reads=%0d ETH writes=%0d ETH frames=%0d CNN done=%0d Protocol frames=%0d frame_cycles=%0d min_slack=%0d max_cpu_wait=%0d max_cnn_wait=%0d",
                 cpu_reads, cnn_reads, ethernet_writes, ethernet_frames, cnn_completions,
                 protocol_frames,
                 dut.u_protocol2_mmio_wrapper.rt_last_frame_cycles,
                 dut.u_protocol2_mmio_wrapper.rt_minimum_slack,
                 max_cpu_read_wait, max_cnn_read_wait);
        $display("SoC DRAM saturation regression: %0d checks passed", checks);
        $finish;
    end

    initial begin
        #7_000_000;
        $fatal(1, "SoC DRAM stress global timeout");
    end

endmodule
