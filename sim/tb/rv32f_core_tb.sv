`timescale 1ns/1ps

module core_rv32f_tb;
    logic clk;
    logic rst;
    wire [31:0] im_addr;
    logic [31:0] im_read_data;
    wire im_stall;
    wire im_flush;
    wire im_invalidate;
    wire dm_req;
    logic dm_valid;
    wire dm_stall;
    wire dm_web;
    wire [31:0] dm_bit_en;
    wire [31:0] dm_addr;
    wire [31:0] dm_write_data;
    integer cycles;
    logic saw_buffered_fp_result;
    logic saw_buffered_fp_flags;

    always #5 clk = ~clk;

    always_comb begin
        case (im_addr)
            32'd0:  im_read_data = 32'h3F80_00B7; // lui x1,0x3f800 (1.0f)
            32'd1:  im_read_data = 32'hF000_80D3; // fmv.w.x f1,x1
            32'd2:  im_read_data = 32'h3380_0137; // lui x2,0x33800 (2^-24)
            32'd3:  im_read_data = 32'hF001_0153; // fmv.w.x f2,x2
            32'd4:  im_read_data = 32'h0000_2483; // lw x9,0(x0), forced stall
            32'd5:  im_read_data = 32'h0020_81D3; // fadd.s f3,f1,f2 (NX)
            32'd6:  im_read_data = 32'h1021_8253; // fmul.s f4,f3,f2 (RAW)
            32'd7:  im_read_data = 32'h0810_82C3; // fmadd.s f5,f1,f1,f1 = 2.0
            32'd8:  im_read_data = 32'hE002_8553; // fmv.x.w x10,f5 (FMA RAW)
            32'd9:  im_read_data = 32'hC002_02D3; // fcvt.w.s x5,f4,rne
            32'd10: im_read_data = 32'h0010_2373; // csrr x6,fflags
            32'd11: im_read_data = 32'h3000_23F3; // csrr x7,mstatus
            32'd12: im_read_data = 32'h0550_0413; // addi x8,x0,0x55
            32'd13: im_read_data = 32'h0000_006F; // jal x0,0
            default: im_read_data = 32'h0000_0013;
        endcase
    end

    core dut (
         .clk(clk), .rst(rst)
        ,.dma_interrupt(1'b0), .timer_interrupt(1'b0)
        ,.wdt_interrupt(1'b0), .time_value(64'd0)
        ,.im_valid(1'b1), .im_read_data(im_read_data)
        ,.im_stall(im_stall), .im_addr(im_addr)
        ,.im_flush(im_flush), .im_invalidate(im_invalidate)
        ,.dm_valid(dm_valid), .dm_read_data(32'hCAFE_BABE)
        ,.dm_req(dm_req), .dm_stall(dm_stall), .dm_WEB(dm_web)
        ,.dm_bit_en(dm_bit_en), .dm_addr(dm_addr)
        ,.dm_write_data(dm_write_data)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            saw_buffered_fp_result <= 1'b0;
            saw_buffered_fp_flags  <= 1'b0;
        end else if (dut.ex_result_pending_q) begin
            saw_buffered_fp_result <= 1'b1;
            if (dut.ex_fp_flags_valid_q && (dut.ex_fp_flags_q == 5'b0_0001))
                saw_buffered_fp_flags <= 1'b1;
        end
    end

    // Hold the older LW in MEM beyond the FADD response. This forces the EX
    // result/fflags pulse through the one-entry retirement buffer.
    initial begin
        dm_valid = 1'b0;
        wait (rst == 1'b0);
        wait (dm_req == 1'b1);
        repeat (18) @(posedge clk);
        dm_valid = 1'b1;
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        cycles = 0;
        while ((dut.u_int_register_file.registers[8] !== 32'h55) &&
               (cycles < 180)) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
        end
        if (cycles >= 180)
            $fatal(1, "RV32F core program timed out");
        if (dut.g_float_register_file.u_float_register_file.registers[3] !== 32'h3F80_0000)
            $fatal(1, "FADD pipeline result mismatch: %08h",
                   dut.g_float_register_file.u_float_register_file.registers[3]);
        if (dut.g_float_register_file.u_float_register_file.registers[4] !== 32'h3380_0000)
            $fatal(1, "FMUL forwarding result mismatch: %08h",
                   dut.g_float_register_file.u_float_register_file.registers[4]);
        if (dut.g_float_register_file.u_float_register_file.registers[5] !== 32'h4000_0000 ||
            dut.u_int_register_file.registers[10] !== 32'h4000_0000)
            $fatal(1, "FMA pipeline/forwarding result mismatch");
        if (dut.u_int_register_file.registers[5] !== 32'd0)
            $fatal(1, "FCVT integer destination mismatch");
        if (dut.u_int_register_file.registers[6] !== 32'd1)
            $fatal(1, "fflags did not accumulate NX");
        if ((dut.u_int_register_file.registers[7] & 32'h6000) !== 32'h6000)
            $fatal(1, "mstatus.FS was not marked dirty");
        if (!saw_buffered_fp_result || !saw_buffered_fp_flags)
            $fatal(1, "MEM stall did not preserve the FPU result and fflags");

        $display("[CORE RV32F PASS] FMUL/FMA RAW, MEM-stall buffering, fflags and FS dirty completed in %0d cycles",
                 cycles);
        $finish;
    end
endmodule
