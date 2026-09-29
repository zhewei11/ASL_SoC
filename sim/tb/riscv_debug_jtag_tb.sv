`timescale 1ns/1ps

module riscv_debug_jtag_tb;
    localparam int MOTOR_COUNT = 20;
    localparam logic [4:0] JTAG_IR_DTMCS = 5'h10;
    localparam logic [4:0] JTAG_IR_DMI   = 5'h11;
    localparam logic [6:0] DMI_DATA0      = 7'h04;
    localparam logic [6:0] DMI_DATA1      = 7'h05;
    localparam logic [6:0] DMI_DMCONTROL  = 7'h10;
    localparam logic [6:0] DMI_DMSTATUS   = 7'h11;
    localparam logic [6:0] DMI_ABSTRACTCS = 7'h16;
    localparam logic [6:0] DMI_COMMAND    = 7'h17;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic jtag_tck = 1'b0;
    logic jtag_tms = 1'b1;
    logic jtag_tdi = 1'b0;
    logic jtag_trst_n = 1'b1;
    logic jtag_tdo;

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

    integer checks = 0;
    integer cycles;
    logic sampled_tdo;
    logic [40:0] dmi_scan_result;
    logic [31:0] dmi_read_data;
    logic [31:0] abstractcs;
    logic [31:0] original_dpc;

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

    // Sample TDO immediately before the rising edge, as required by the TAP.
    task automatic jtag_cycle(
        input logic tms_value,
        input logic tdi_value,
        output logic tdo_value
    );
        begin
            jtag_tms = tms_value;
            jtag_tdi = tdi_value;
            #4;
            tdo_value = jtag_tdo;
            #1 jtag_tck = 1'b1;
            #5 jtag_tck = 1'b0;
        end
    endtask

    task automatic jtag_idle_cycles(input integer count);
        integer i;
        begin
            for (i = 0; i < count; i++)
                jtag_cycle(1'b0, 1'b0, sampled_tdo);
        end
    endtask

    task automatic jtag_reset_tap;
        integer i;
        begin
            for (i = 0; i < 6; i++)
                jtag_cycle(1'b1, 1'b0, sampled_tdo);
            jtag_cycle(1'b0, 1'b0, sampled_tdo);
        end
    endtask

    task automatic jtag_shift_ir(input logic [4:0] value);
        integer i;
        begin
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Select-DR
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Select-IR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Capture-IR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Shift-IR
            for (i = 0; i < 5; i++)
                jtag_cycle(i == 4, value[i], sampled_tdo);
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Update-IR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Run-Test/Idle
        end
    endtask

    task automatic jtag_shift_dr32(
        input logic [31:0] value,
        output logic [31:0] result
    );
        integer i;
        begin
            result = 32'd0;
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Select-DR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Capture-DR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Shift-DR
            for (i = 0; i < 32; i++) begin
                jtag_cycle(i == 31, value[i], sampled_tdo);
                result[i] = sampled_tdo;
            end
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Update-DR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Run-Test/Idle
        end
    endtask

    task automatic jtag_shift_dmi(
        input logic [40:0] value,
        output logic [40:0] result
    );
        integer i;
        begin
            result = 41'd0;
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Select-DR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Capture-DR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Shift-DR
            for (i = 0; i < 41; i++) begin
                jtag_cycle(i == 40, value[i], sampled_tdo);
                result[i] = sampled_tdo;
            end
            jtag_cycle(1'b1, 1'b0, sampled_tdo); // Update-DR
            jtag_cycle(1'b0, 1'b0, sampled_tdo); // Run-Test/Idle
        end
    endtask

    task automatic dmi_access(
        input logic [1:0] op,
        input logic [6:0] address,
        input logic [31:0] write_data,
        output logic [31:0] read_data
    );
        logic [40:0] ignored;
        begin
            jtag_shift_dmi({address, write_data, op}, ignored);
            jtag_idle_cycles(12);
            jtag_shift_dmi(41'd0, dmi_scan_result);
            check(dmi_scan_result[1:0] == 2'b00,
                  "DMI transaction completes without transport error");
            check(dmi_scan_result[40:34] == address,
                  "DMI response returns the requested address");
            read_data = dmi_scan_result[33:2];
        end
    endtask

    task automatic dmi_write(
        input logic [6:0] address,
        input logic [31:0] value
    );
        logic [31:0] ignored;
        begin
            dmi_access(2'b10, address, value, ignored);
        end
    endtask

    task automatic dmi_read(
        input logic [6:0] address,
        output logic [31:0] value
    );
        begin
            dmi_access(2'b01, address, 32'd0, value);
        end
    endtask

    task automatic abstract_read_reg(
        input logic [15:0] regno,
        output logic [31:0] value
    );
        begin
            dmi_write(DMI_COMMAND, 32'h0022_0000 | regno);
            dmi_read(DMI_ABSTRACTCS, abstractcs);
            check(!abstractcs[12] && abstractcs[10:8] == 3'd0,
                  "abstract register read completes without cmderr");
            dmi_read(DMI_DATA0, value);
        end
    endtask

    task automatic abstract_write_reg(
        input logic [15:0] regno,
        input logic [31:0] value
    );
        begin
            dmi_write(DMI_DATA0, value);
            dmi_write(DMI_COMMAND, 32'h0023_0000 | regno);
            dmi_read(DMI_ABSTRACTCS, abstractcs);
            check(!abstractcs[12] && abstractcs[10:8] == 3'd0,
                  "abstract register write completes without cmderr");
        end
    endtask

    initial begin
        logic [31:0] dtmcs;

        #1 jtag_trst_n = 1'b0;
        repeat (6) @(posedge clk);
        rst <= 1'b0;
        #2 jtag_trst_n = 1'b1;

        // Let the boot program reach its terminal loop before stopping it.
        cycles = 0;
        while (dut.u_soc_cpu_cluster.u_dtcm.memory[5] !== 32'h4650_5521 &&
               cycles < 5000) begin
            @(posedge clk);
            cycles++;
        end
        check(cycles < 5000, "CPU reaches the boot program terminal loop");

        jtag_reset_tap();
        jtag_shift_ir(JTAG_IR_DTMCS);
        jtag_shift_dr32(32'd0, dtmcs);
        check(dtmcs[3:0] == 4'd1 && dtmcs[9:4] == 6'd7,
              "JTAG DTM reports version 1 and seven DMI address bits");

        jtag_shift_ir(JTAG_IR_DMI);
        dmi_write(DMI_DMCONTROL, 32'h0000_0001); // dmactive
        dmi_read(DMI_DMSTATUS, dmi_read_data);
        check(dmi_read_data[7] && dmi_read_data[3:0] == 4'd3,
              "Debug Module is authenticated and reports Debug Spec 1.0");

        dmi_write(DMI_DMCONTROL, 32'h8000_0001); // haltreq
        dmi_read(DMI_DMSTATUS, dmi_read_data);
        check(dmi_read_data[9:8] == 2'b11,
              "haltreq drains the pipeline and halts hart 0");

        abstract_read_reg(16'h1009, dmi_read_data);
        check(dmi_read_data == 32'h4650_5521,
              "abstract command reads integer register x9");
        abstract_write_reg(16'h1009, 32'hD06B_0009);
        abstract_read_reg(16'h1009, dmi_read_data);
        check(dmi_read_data == 32'hD06B_0009,
              "abstract command writes integer register x9");

        abstract_read_reg(16'h07b0, dmi_read_data);
        check(dmi_read_data[31:28] == 4'd4 &&
              dmi_read_data[8:6] == 3'd3,
              "dcsr reports Debug Spec 1.0 and haltreq cause");
        abstract_read_reg(16'h07b1, original_dpc);
        check(original_dpc[1:0] == 2'b00,
              "dpc is readable and instruction aligned");

        dmi_write(DMI_DATA1, 32'h0002_0080);
        dmi_write(DMI_DATA0, 32'hD06B_A55A);
        dmi_write(DMI_COMMAND, 32'h0221_0000); // Access Memory, write word
        dmi_read(DMI_ABSTRACTCS, abstractcs);
        check(!abstractcs[12] && abstractcs[10:8] == 3'd0,
              "abstract memory write completes without cmderr");
        dmi_write(DMI_COMMAND, 32'h0220_0000); // Access Memory, read word
        dmi_read(DMI_ABSTRACTCS, abstractcs);
        dmi_read(DMI_DATA0, dmi_read_data);
        check(dmi_read_data == 32'hD06B_A55A,
              "abstract memory command writes and reads local DTCM");

        dmi_write(DMI_DMCONTROL, 32'h4000_0001); // clear haltreq + resume
        dmi_read(DMI_DMSTATUS, dmi_read_data);
        check(dmi_read_data[11:10] == 2'b11,
              "resumereq returns hart 0 to running state");

        dmi_write(DMI_DMCONTROL, 32'h8000_0001);
        dmi_read(DMI_DMSTATUS, dmi_read_data);
        check(dmi_read_data[9:8] == 2'b11,
              "hart can be halted again after resume");

        // Keep the Debug Module alive while ndmreset resets the hart and all
        // non-debug SoC state, then verify halt-on-reset and havereset.
        dmi_write(DMI_DMCONTROL, 32'h0000_000b);
        dmi_write(DMI_DMCONTROL, 32'h0000_0001);
        dmi_read(DMI_DMSTATUS, dmi_read_data);
        check(dmi_read_data[19:18] == 2'b11 &&
              dmi_read_data[9:8] == 2'b11,
              "ndmreset preserves DM and halt-on-reset stops hart 0");

        $display("RISC-V JTAG debug integration: %0d checks passed", checks);
        $finish;
    end
endmodule
