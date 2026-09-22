`timescale 1ns/1ps
`include "rtos_core_config.svh"

module core_rv32f_trap_tb;
    localparam logic [31:0] TRAP_VECTOR_WORD =
        `RTOS_CORE_CPU_MACHINE_TRAP_VECTOR >> 2;
    logic clk;
    logic rst;
    logic test_dynamic_rm;
    wire [31:0] im_addr;
    logic [31:0] im_read_data;
    wire im_stall;
    wire im_flush;
    wire im_invalidate;
    wire dm_req;
    wire dm_stall;
    wire dm_web;
    wire [31:0] dm_bit_en;
    wire [31:0] dm_addr;
    wire [31:0] dm_write_data;
    integer cycles;

    always #5 clk = ~clk;

    always_comb begin
        im_read_data = 32'h0000_0013;
        if (im_addr == TRAP_VECTOR_WORD)
            im_read_data = 32'h3420_22F3; // csrr x5,mcause
        else if (im_addr == TRAP_VECTOR_WORD + 1)
            im_read_data = 32'h3410_2373; // csrr x6,mepc
        else if (im_addr == TRAP_VECTOR_WORD + 2)
            im_read_data = 32'h3430_23F3; // csrr x7,mtval
        else if (im_addr == TRAP_VECTOR_WORD + 3)
            im_read_data = 32'h0550_0413; // addi x8,x0,0x55
        else if (im_addr == TRAP_VECTOR_WORD + 4)
            im_read_data = 32'h0000_006F; // jal x0,0
        else if (!test_dynamic_rm) begin
            case (im_addr)
                32'd0: im_read_data = 32'h0000_0093; // addi x1,x0,0
                32'd1: im_read_data = 32'h3000_9073; // csrw mstatus,x1
                32'd2: im_read_data = 32'hF000_80D3; // fmv.w.x f1,x1
                default: im_read_data = 32'h0000_006F;
            endcase
        end else begin
            case (im_addr)
                32'd0: im_read_data = 32'h0050_0093; // addi x1,x0,5
                32'd1: im_read_data = 32'h0020_9073; // csrw frm,x1
                32'd2: im_read_data = 32'hF000_00D3; // fmv.w.x f1,x0
                32'd3: im_read_data = 32'h0010_F153; // fadd.s f2,f1,f1,dyn
                default: im_read_data = 32'h0000_006F;
            endcase
        end
    end

    core dut (
         .clk(clk), .rst(rst)
        ,.dma_interrupt(1'b0), .timer_interrupt(1'b0)
        ,.wdt_interrupt(1'b0), .time_value(64'd0)
        ,.im_valid(1'b1), .im_read_data(im_read_data)
        ,.im_stall(im_stall), .im_addr(im_addr)
        ,.im_flush(im_flush), .im_invalidate(im_invalidate)
        ,.dm_valid(1'b1), .dm_read_data(32'd0)
        ,.dm_req(dm_req), .dm_stall(dm_stall), .dm_WEB(dm_web)
        ,.dm_bit_en(dm_bit_en), .dm_addr(dm_addr)
        ,.dm_write_data(dm_write_data)
    );

    task automatic reset_and_wait_for_trap_handler;
        begin
            rst = 1'b1;
            repeat (3) @(posedge clk);
            rst = 1'b0;
            cycles = 0;
            while ((dut.u_int_register_file.registers[8] !== 32'h55) &&
                   (cycles < 100)) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
            end
            if (cycles >= 100)
                $fatal(1, "FP illegal-instruction test timed out");
        end
    endtask

    initial begin
        clk = 1'b0;
        test_dynamic_rm = 1'b0;
        reset_and_wait_for_trap_handler();
        if (dut.u_int_register_file.registers[5] !== 32'd2 ||
            dut.u_int_register_file.registers[6] !== 32'd8 ||
            dut.u_int_register_file.registers[7] !== 32'hF000_80D3)
            $fatal(1, "mstatus.FS=Off did not produce a precise illegal trap");
        if (dut.g_float_register_file.u_float_register_file.registers[1] !== 32'd0)
            $fatal(1, "FS=Off instruction modified an FP register");

        test_dynamic_rm = 1'b1;
        reset_and_wait_for_trap_handler();
        if (dut.u_int_register_file.registers[5] !== 32'd2 ||
            dut.u_int_register_file.registers[6] !== 32'd12 ||
            dut.u_int_register_file.registers[7] !== 32'h0010_F153)
            $fatal(1, "reserved dynamic frm did not produce a precise illegal trap");
        if (dut.g_float_register_file.u_float_register_file.registers[2] !== 32'd0)
            $fatal(1, "illegal dynamic-rm instruction modified an FP register");

        $display("[CORE RV32F TRAP PASS] FS=Off and reserved dynamic frm trap precisely");
        $finish;
    end
endmodule
