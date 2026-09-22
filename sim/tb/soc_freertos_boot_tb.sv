`timescale 1ns/1ps

module soc_freertos_boot_tb;
    localparam int MOTOR_COUNT = 20;
    localparam int SIGNATURE_WORD = (32'h0002_ff00 - 32'h0002_0000) / 4;
    localparam logic [31:0] PASS_SIGNATURE = 32'h4652_544f;
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
    int cycles, checks, max_cycles;

    soc_core_top #(
        .ENABLE_CPU(1'b1),
        .BOOT_ROM_INIT_FILE("build/freertos_rom.mem"),
        .ITCM_INIT_FILE("build/freertos_itcm.mem"),
        .DTCM_INIT_FILE("build/freertos_dtcm.mem"),
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
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 2_000_000;
        while (dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD] !==
                   PASS_SIGNATURE &&
               dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD][31:12] !==
                   20'hbad00 &&
               cycles < max_cycles) begin
            @(posedge clk);
            cycles++;
            if ($test$plusargs("TRACE_PROGRESS") &&
                (cycles % 10_000) == 0)
                $display("FreeRTOS progress: cycle=%0d pc=%08x instret=%0d status=%08x",
                         cycles,
                         dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.pc,
                         dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.u_csr_registers.instret_counter,
                         dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD]);
        end

        if (cycles == max_cycles)
            $display("FreeRTOS timeout: pc=%08x status=%08x task_a=%0d task_b=%0d tick=%0d mcause=%08x mepc=%08x mtvec=%08x mstatus=%08x",
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.pc,
                     dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD],
                     dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 1],
                     dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 2],
                     dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 3],
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.u_csr_registers.mcause,
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.u_csr_registers.mepc,
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.u_csr_registers.mtvec,
                     dut.u_soc_cpu_cluster.u_cpu.u_cpu_wrapper.u_core.u_csr_registers.mstatus);
        check(cycles < max_cycles,
              "FreeRTOS reaches a terminal signature before timeout");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD] ==
                  PASS_SIGNATURE,
              "FreeRTOS scheduler publishes its pass signature");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 1] >= 3,
              "task A runs after repeated preemption");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 2] >= 3,
              "task B runs after repeated preemption");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 3] >= 2,
              "machine-timer interrupts advance the RTOS tick");
        check(dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 4] == 0 &&
              dut.u_soc_cpu_cluster.u_dtcm.memory[SIGNATURE_WORD + 5] == 0,
              "RTOS completes without recording an exception");
        check(!m_axi_awvalid && !m_axi_arvalid,
              "FreeRTOS executes entirely from local TCM memories");
        $display("Integrated FreeRTOS SoC regression: %0d checks passed in %0d cycles",
                 checks, cycles);
        $finish;
    end
endmodule
