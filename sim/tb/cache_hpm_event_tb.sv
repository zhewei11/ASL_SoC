`timescale 1ns/1ps

module cache_hpm_event_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic i_invalidate = 1'b0;
    logic [31:0] i_core_addr = 32'd0;
    logic i_core_flush = 1'b0;
    logic i_core_stall = 1'b1;
    logic i_core_access_allowed = 1'b1;
    logic i_core_valid;
    logic [31:0] i_core_out;
    logic i_miss_event;
    logic i_mem_req;
    logic [31:0] i_mem_addr;
    logic i_mem_ready = 1'b0;
    logic i_mem_line_valid = 1'b0;
    logic [127:0] i_mem_line =
        128'h4444_4444_3333_3333_2222_2222_1111_1111;

    logic d_invalidate = 1'b0;
    logic d_core_req = 1'b0;
    logic d_core_write = 1'b0;
    logic [31:0] d_core_addr = 32'd0;
    logic [31:0] d_core_in = 32'hCAFE_BABE;
    logic [3:0] d_core_wstrb = 4'hf;
    logic d_core_stall = 1'b0;
    logic d_core_valid;
    logic [31:0] d_core_out;
    logic d_read_miss_event;
    logic d_mem_read_req;
    logic [31:0] d_mem_read_addr;
    logic d_mem_read_ready = 1'b0;
    logic d_mem_line_valid = 1'b0;
    logic [127:0] d_mem_line =
        128'hDDDD_DDDD_CCCC_CCCC_BBBB_BBBB_AAAA_AAAA;
    logic d_mem_write_req;
    logic [31:0] d_mem_write_addr;
    logic [31:0] d_mem_write_data;
    logic [3:0] d_mem_write_strb;
    logic d_mem_write_ready = 1'b0;
    logic d_mem_write_done = 1'b0;
    integer checks = 0;

    L1C_inst u_icache (
         .clk(clk), .rst(rst), .invalidate(i_invalidate)
        ,.core_addr(i_core_addr), .core_flush(i_core_flush)
        ,.core_stall(i_core_stall)
        ,.core_access_allowed(i_core_access_allowed)
        ,.core_valid(i_core_valid), .core_out(i_core_out)
        ,.miss_event(i_miss_event), .mem_req(i_mem_req)
        ,.mem_addr(i_mem_addr), .mem_ready(i_mem_ready)
        ,.mem_line_valid(i_mem_line_valid), .mem_line(i_mem_line)
    );

    L1C_data u_dcache (
         .clk(clk), .rst(rst), .invalidate(d_invalidate)
        ,.core_req(d_core_req), .core_write(d_core_write)
        ,.core_addr(d_core_addr), .core_in(d_core_in)
        ,.core_wstrb(d_core_wstrb), .core_stall(d_core_stall)
        ,.core_valid(d_core_valid), .core_out(d_core_out)
        ,.read_miss_event(d_read_miss_event)
        ,.mem_read_req(d_mem_read_req), .mem_read_addr(d_mem_read_addr)
        ,.mem_read_ready(d_mem_read_ready)
        ,.mem_line_valid(d_mem_line_valid), .mem_line(d_mem_line)
        ,.mem_write_req(d_mem_write_req)
        ,.mem_write_addr(d_mem_write_addr)
        ,.mem_write_data(d_mem_write_data)
        ,.mem_write_strb(d_mem_write_strb)
        ,.mem_write_ready(d_mem_write_ready)
        ,.mem_write_done(d_mem_write_done)
    );

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("FAIL: %s", message);
                $fatal(1);
            end
            checks = checks + 1;
            $display("PASS: %s", message);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;

        check(i_miss_event, "I-cache emits a demand-miss event");
        @(posedge clk);
        #1;
        check(!i_miss_event && i_mem_req,
              "I-cache miss event is a one-cycle pulse");
        i_mem_ready = 1'b1;
        @(posedge clk);
        #1;
        i_mem_ready = 1'b0;
        i_mem_line_valid = 1'b1;
        @(posedge clk);
        #1;
        i_mem_line_valid = 1'b0;
        check(i_core_valid && i_core_out == 32'h1111_1111,
              "I-cache hit after refill does not emit another miss");
        check(!i_miss_event, "I-cache hit keeps miss event low");

        d_core_req = 1'b1;
        #1;
        check(d_read_miss_event, "D-cache emits a demand-load-miss event");
        @(posedge clk);
        #1;
        check(!d_read_miss_event && d_mem_read_req,
              "D-cache miss event is a one-cycle pulse");
        d_mem_read_ready = 1'b1;
        @(posedge clk);
        #1;
        d_mem_read_ready = 1'b0;
        d_mem_line_valid = 1'b1;
        @(posedge clk);
        #1;
        d_mem_line_valid = 1'b0;
        check(d_core_valid && d_core_out == 32'hAAAA_AAAA,
              "D-cache completes the refill");
        @(posedge clk);
        #1;
        check(!d_read_miss_event,
              "D-cache hit does not emit another load-miss event");

        d_core_write = 1'b1;
        d_core_addr = 32'd4;
        #1;
        check(!d_read_miss_event,
              "write-through store miss is excluded from load-miss event");

        $display("[CACHE HPM EVENT PASS] %0d checks passed", checks);
        $finish;
    end
endmodule
