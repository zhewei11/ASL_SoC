`timescale 1ns/1ps
`include "rtos_core_config.svh"

module core_pmp_user_tb;
    localparam logic [31:0] TRAP_VECTOR_WORD =
        `RTOS_CORE_CPU_MACHINE_TRAP_VECTOR >> 2;
    logic clk;
    logic rst;
    wire [31:0] im_addr;
    logic [31:0] im_read_data;
    wire im_stall;
    wire im_flush;
    wire im_invalidate;
    wire im_access_allowed;
    wire dm_req;
    wire dm_stall;
    wire dm_web;
    wire [31:0] dm_bit_en;
    wire [31:0] dm_addr;
    wire [31:0] dm_write_data;
    logic test_fetch_fault;
    logic saw_user_mode;
    logic saw_data_request;
    logic saw_denied_fetch;
    integer cycles;

    always #5 clk = ~clk;

    always_comb begin
        im_read_data = 32'h0000_0013;
        if (im_addr == TRAP_VECTOR_WORD)
            im_read_data = 32'h3420_22F3; // csrr x5,mcause
        else if (im_addr == TRAP_VECTOR_WORD + 1)
            im_read_data = 32'h3430_2373; // csrr x6,mtval
        else if (im_addr == TRAP_VECTOR_WORD + 2)
            im_read_data = 32'h05A0_0393; // addi x7,x0,0x5a
        else if (im_addr == TRAP_VECTOR_WORD + 3)
            im_read_data = 32'h0000_006F; // jal x0,0
        else if (test_fetch_fault) begin
            case (im_addr)
                32'd0: im_read_data = 32'h0100_0093; // addi x1,x0,0x10
                32'd1: im_read_data = 32'h3B00_9073; // csrw pmpaddr0,x1
                32'd2: im_read_data = 32'h00D0_0093; // addi x1,x0,0x0d
                32'd3: im_read_data = 32'h3A00_9073; // csrw pmpcfg0,x1
                32'd4: im_read_data = 32'h1000_0093; // addi x1,x0,0x100
                32'd5: im_read_data = 32'h3410_9073; // csrw mepc,x1
                32'd6: im_read_data = 32'h3000_1073; // csrw mstatus,x0
                32'd7: im_read_data = 32'h3020_0073; // mret
                default: im_read_data = 32'h0000_006F;
            endcase
        end else begin
            case (im_addr)
                32'd0: im_read_data = 32'h0400_0093; // addi x1,x0,0x40
                32'd1: im_read_data = 32'h3B00_9073; // csrw pmpaddr0,x1
                32'd2: im_read_data = 32'h00D0_0093; // addi x1,x0,0x0d
                32'd3: im_read_data = 32'h3A00_9073; // csrw pmpcfg0,x1
                32'd4: im_read_data = 32'h0200_0093; // addi x1,x0,0x20
                32'd5: im_read_data = 32'h3410_9073; // csrw mepc,x1
                32'd6: im_read_data = 32'h3000_1073; // csrw mstatus,x0
                32'd7: im_read_data = 32'h3020_0073; // mret
                32'd8: im_read_data = 32'h02A0_0113; // addi x2,x0,42
                32'd9: im_read_data = 32'h0020_2023; // sw x2,0(x0)
                default: im_read_data = 32'h0000_006F;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            saw_user_mode <= 1'b0;
            saw_data_request <= 1'b0;
            saw_denied_fetch <= 1'b0;
        end else begin
            if (dut.u_csr_registers.current_privilege == 2'b00)
                saw_user_mode <= 1'b1;
            if (dm_req)
                saw_data_request <= 1'b1;
            if (!im_access_allowed)
                saw_denied_fetch <= 1'b1;
        end
    end

    core dut (
         .clk(clk), .rst(rst)
        ,.dma_interrupt(1'b0), .timer_interrupt(1'b0)
        ,.wdt_interrupt(1'b0), .time_value(64'd0)
        ,.im_valid(im_access_allowed), .im_read_data(im_read_data)
        ,.im_stall(im_stall), .im_addr(im_addr)
        ,.im_flush(im_flush), .im_invalidate(im_invalidate)
        ,.im_access_allowed(im_access_allowed)
        ,.dm_valid(1'b1), .dm_read_data(32'd0)
        ,.dm_req(dm_req), .dm_stall(dm_stall), .dm_WEB(dm_web)
        ,.dm_bit_en(dm_bit_en), .dm_addr(dm_addr)
        ,.dm_write_data(dm_write_data)
    );

    task automatic reset_and_wait_for_handler;
        begin
            rst = 1'b1;
            repeat (3) @(posedge clk);
            rst = 1'b0;
            cycles = 0;
            while ((dut.u_int_register_file.registers[7] !== 32'h5a) &&
                   (cycles < 150)) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (cycles >= 150)
                $fatal(1, "U-mode PMP integration test timed out");
        end
    endtask

    initial begin
        clk = 1'b0;
        test_fetch_fault = 1'b0;
        rst = 1'b1;
        saw_user_mode = 1'b0;
        saw_data_request = 1'b0;
        saw_denied_fetch = 1'b0;
        reset_and_wait_for_handler();

        if (!saw_user_mode)
            $fatal(1, "MRET never entered U-mode");
        if (dut.u_int_register_file.registers[2] !== 32'd42)
            $fatal(1, "U-mode instruction did not execute");
        if (dut.u_int_register_file.registers[5] !== 32'd7 ||
            dut.u_int_register_file.registers[6] !== 32'd0)
            $fatal(1, "denied U-mode store did not trap precisely");
        if (saw_data_request)
            $fatal(1, "denied store escaped the core onto the data bus");

        test_fetch_fault = 1'b1;
        reset_and_wait_for_handler();
        if (!saw_user_mode || !saw_denied_fetch)
            $fatal(1, "denied U-mode instruction fetch was not observed");
        if (dut.u_int_register_file.registers[5] !== 32'd1 ||
            dut.u_int_register_file.registers[6] !== 32'h0000_0100)
            $fatal(1, "denied U-mode fetch did not trap precisely");
        if (saw_data_request)
            $fatal(1, "fetch-fault test unexpectedly accessed the data bus");

        $display("[CORE PMP USER PASS] U-mode fetch/store faults are precise and contained");
        $finish;
    end
endmodule
