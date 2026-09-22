`timescale 1ns/1ps

module soc_cpu_boot_tb;
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
    logic [1:0] m_axi_awburst, m_axi_bresp = 0, m_axi_arburst;
    logic [1:0] m_axi_rresp = 0;
    logic m_axi_awvalid, m_axi_awready = 0, m_axi_wlast, m_axi_wvalid;
    logic m_axi_wready = 0, m_axi_bvalid = 0, m_axi_bready;
    logic m_axi_arvalid, m_axi_arready = 0, m_axi_rlast = 0;
    logic m_axi_rvalid = 0, m_axi_rready;
    logic ethernet_frame_irq;
    logic [31:0] ethernet_frame_bytes, ethernet_frame_checksum;
    logic host_uart_rx = 1, host_uart_tx, host_uart_irq;
    logic rs485_rx = 1, rs485_tx, rs485_de, protocol_irq;
    int cycles, checks;
    logic cnn_status_read_seen;
    logic uart_write_seen;

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
        .BOOT_ROM_INIT_FILE("build/rv32im_boot.mem"),
        .RT_FRAME_CYCLES_OVERRIDE(100_000)
    ) dut (.*);

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
        rst <= 1'b0;
        cycles = 0;
        while (dut.u_soc_cpu_cluster.u_dtcm.memory[5] !== 32'h4650_5521 &&
               dut.u_soc_cpu_cluster.u_dtcm.memory[5] !== 32'h0000_0BAD &&
               cycles < 5000) begin
            @(posedge clk);
            cycles++;
        end
        check(cycles < 5000, "integrated SoC RV32IMF reaches completion marker");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[0] == 32'h1234_5678,
              "integrated Boot ROM writes local DTCM");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[1] == 32'h5032_4D4D,
              "CPU reads real Protocol 2.0 ID through SoC MMIO");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[2] == 32'h4070_0000,
              "integrated CPU executes FADD.S");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[3] == 32'h4058_0000,
              "integrated CPU executes FMUL.S");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[4] == 32'h4010_1120,
              "integrated CPU MISA reports RV32IMF plus U-mode");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[7] == 32'h3FC0_0000,
              "integrated CPU executes FDIV.S");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[8] == 32'd4,
              "integrated CPU executes FCVT.W.S");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[10] == 32'h4070_0000,
              "integrated CPU executes FLW/FSW through DTCM");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[11] == 32'd0 &&
              dut.u_soc_cpu_cluster.u_dtcm.memory[12] == 32'd0,
              "integrated floating-point program completes without a trap");
        check((dut.u_soc_cpu_cluster.u_dtcm.memory[13] & 32'h0000_6000) ==
              32'h0000_6000,
              "integrated CPU marks mstatus.FS Dirty");
        check(cnn_status_read_seen,
              "CPU reaches CNN status through the new MMIO page decoder");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[6] == 32'd0,
              "firmware stores the idle CNN status in DTCM");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[5] == 32'h4650_5521,
              "integrated CPU publishes the FPU completion signature");
        check(uart_write_seen,
              "integrated CPU writes boot marker through Host UART MMIO");
        check(!m_axi_awvalid && !m_axi_arvalid,
              "local Boot ROM and DTCM traffic does not escape to DRAM AXI");
        check(!mmio_ready,
              "external debug MMIO is isolated while internal CPU owns MMIO");
        $display("Integrated SoC CPU boot regression: %0d checks passed", checks);
        $finish;
    end
endmodule
