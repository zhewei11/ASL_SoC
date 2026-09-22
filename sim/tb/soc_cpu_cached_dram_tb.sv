`timescale 1ns/1ps

module soc_cpu_cached_dram_tb;
    localparam int MOTOR_COUNT = 20;
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
    logic [1:0] m_axi_awburst, m_axi_bresp, m_axi_arburst;
    logic [1:0] m_axi_rresp;
    logic m_axi_awvalid, m_axi_awready, m_axi_wlast, m_axi_wvalid;
    logic m_axi_wready, m_axi_bvalid, m_axi_bready;
    logic m_axi_arvalid, m_axi_arready, m_axi_rlast;
    logic m_axi_rvalid, m_axi_rready;
    logic ethernet_frame_irq;
    logic [31:0] ethernet_frame_bytes, ethernet_frame_checksum;
    logic host_uart_rx = 1, host_uart_tx, host_uart_irq;
    logic rs485_rx = 1, rs485_tx, rs485_de, protocol_irq;
    int cycles, checks;
    logic cnn_status_read_seen;
    logic uart_write_seen;
    integer dram_writes, dram_read_bursts;
    logic bad_dram_request;

    always @(posedge clk) begin
        if (rst)
            cnn_status_read_seen <= 1'b0;
        else if (dut.cpu_mmio_valid && dut.cpu_mmio_ready &&
                 !dut.cpu_mmio_write &&
                 dut.cpu_mmio_addr == 32'h1003_2004)
            cnn_status_read_seen <= 1'b1;
    end

    always @(posedge clk) begin
        if (rst)
            uart_write_seen <= 1'b0;
        else if (dut.uart_mmio_valid && dut.uart_mmio_ready &&
                 dut.uart_mmio_write &&
                 dut.uart_mmio_addr == 32'h1003_7008 &&
                 dut.uart_mmio_wdata[7:0] == 8'h41)
            uart_write_seen <= 1'b1;
    end

    soc_core_top #(
        .ENABLE_CPU(1'b1),
        .BOOT_ROM_INIT_FILE("build/cached_dram.mem"),
        .RT_FRAME_CYCLES_OVERRIDE(100_000)
    ) dut (.*);

    axi_bram_slave #(
        .BASE_ADDRESS(32'h2100_0000), .MEMORY_BYTES(4096)
    ) cached_dram (
        .clk(clk), .rst(rst), .s_axi_awid(m_axi_awid),
        .s_axi_awaddr(m_axi_awaddr), .s_axi_awlen(m_axi_awlen),
        .s_axi_awsize(m_axi_awsize), .s_axi_awburst(m_axi_awburst),
        .s_axi_awvalid(m_axi_awvalid), .s_axi_awready(m_axi_awready),
        .s_axi_wdata(m_axi_wdata), .s_axi_wstrb(m_axi_wstrb),
        .s_axi_wlast(m_axi_wlast), .s_axi_wvalid(m_axi_wvalid),
        .s_axi_wready(m_axi_wready), .s_axi_bid(m_axi_bid),
        .s_axi_bresp(m_axi_bresp), .s_axi_bvalid(m_axi_bvalid),
        .s_axi_bready(m_axi_bready), .s_axi_arid(m_axi_arid),
        .s_axi_araddr(m_axi_araddr), .s_axi_arlen(m_axi_arlen),
        .s_axi_arsize(m_axi_arsize), .s_axi_arburst(m_axi_arburst),
        .s_axi_arvalid(m_axi_arvalid), .s_axi_arready(m_axi_arready),
        .s_axi_rid(m_axi_rid), .s_axi_rdata(m_axi_rdata),
        .s_axi_rresp(m_axi_rresp), .s_axi_rlast(m_axi_rlast),
        .s_axi_rvalid(m_axi_rvalid), .s_axi_rready(m_axi_rready)
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

    always @(posedge clk) begin
        if (rst) begin
            dram_writes <= 0; dram_read_bursts <= 0; bad_dram_request <= 0;
        end else begin
            if (m_axi_awvalid && m_axi_awready) begin
                dram_writes <= dram_writes + 1;
                if (m_axi_awaddr < 32'h2100_0000 || m_axi_awlen != 0)
                    bad_dram_request <= 1;
            end
            if (m_axi_arvalid && m_axi_arready) begin
                dram_read_bursts <= dram_read_bursts + 1;
                if (m_axi_araddr != 32'h2100_0000 || m_axi_arlen != 3)
                    bad_dram_request <= 1;
            end
        end
    end

    task automatic check(input logic condition, input string message);
        if (!condition) begin
            $error("FAIL: %s", message);
            $fatal(1);
        end
        checks++;
        $display("PASS: %s", message);
    endtask

    initial begin
        repeat (6) @(posedge clk);
        rst = 1'b0;
        cycles = 0;
        while (dut.u_soc_cpu_cluster.u_dtcm.memory[5] !== 32'h4341_4348 &&
               cycles < 10000) begin
            @(posedge clk);
            cycles++;
        end
        if (cycles >= 10000) begin
            $display("timeout pc_word=%08x cache_state=%0d d_read_state=%0d d_write_state=%0d",
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.pc,
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_l1c_data.state,
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.d_read_state,
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.d_write_state);
            $display("AXI aw=%b/%b w=%b/%b b=%b/%b ar=%b/%b r=%b/%b last=%b counts=%0d/%0d bad=%b",
                     m_axi_awvalid, m_axi_awready, m_axi_wvalid, m_axi_wready,
                     m_axi_bvalid, m_axi_bready, m_axi_arvalid, m_axi_arready,
                     m_axi_rvalid, m_axi_rready, m_axi_rlast,
                     dram_writes, dram_read_bursts, bad_dram_request);
        end
        check(cycles < 10000, "cached DRAM firmware completes");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[0] == 32'h1122_3344 &&
              dut.u_soc_cpu_cluster.u_dtcm.memory[1] == 32'h5566_7788,
              "CPU reads first half of cached DRAM line correctly");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[2] == 32'h1357_9bdf &&
              dut.u_soc_cpu_cluster.u_dtcm.memory[3] == 32'h2468_ace0,
              "CPU reads second half of cached DRAM line correctly");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[4] == 32'h354a_9fa4,
              "repeat cached loads preserve data");
        check(cached_dram.memory[0] == 32'h1122_3344 &&
              cached_dram.memory[3] == 32'h2468_ace0,
              "write-through stores reach external DRAM");
        check(dram_writes == 4,
              "four CPU stores create four single-beat AXI writes");
        check(dram_read_bursts == 1 && !bad_dram_request,
              "one four-beat refill serves all cached DRAM loads");
        check(!mmio_ready,
              "external debug MMIO is isolated while internal CPU owns MMIO");
        $display("CPU cached DRAM regression: %0d checks passed", checks);
        $finish;
    end
endmodule
