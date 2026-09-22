`timescale 1ns/1ps
module interrupt_timer_tb;
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;
    logic [3:0] irq_sources;
    logic irq_valid, irq_ready, irq_write;
    logic [31:0] irq_addr, irq_wdata, irq_rdata;
    logic [3:0] irq_wstrb;
    logic external_interrupt;
    logic [2:0] active_source;
    logic timer_valid, timer_ready, timer_write;
    logic [31:0] timer_addr, timer_wdata, timer_rdata;
    logic [3:0] timer_wstrb;
    logic timer_interrupt;
    logic [63:0] mtime_value;
    integer checks;

    local_interrupt_controller #(
        .NUM_SOURCES(4), .RESET_ENABLE(4'hf), .RESET_EDGE(4'b0101)
    ) lic (
        .clk(clk), .rst(rst), .irq_sources(irq_sources),
        .mmio_valid(irq_valid), .mmio_ready(irq_ready),
        .mmio_write(irq_write), .mmio_addr(irq_addr),
        .mmio_wdata(irq_wdata), .mmio_wstrb(irq_wstrb),
        .mmio_rdata(irq_rdata), .external_interrupt(external_interrupt),
        .active_source(active_source)
    );
    machine_timer #(.BASE_ADDRESS(32'h1003_4000)) timer (
        .clk(clk), .rst(rst), .mmio_valid(timer_valid),
        .mmio_ready(timer_ready), .mmio_write(timer_write),
        .mmio_addr(timer_addr), .mmio_wdata(timer_wdata),
        .mmio_wstrb(timer_wstrb), .mmio_rdata(timer_rdata),
        .timer_interrupt(timer_interrupt), .mtime_value(mtime_value)
    );

    task automatic check(input logic condition, input string message);
        if (!condition) begin $error("FAIL: %s", message); $fatal(1); end
        checks++; $display("PASS: %s", message);
    endtask
    task automatic irq_write32(input logic [7:0] offset,
                               input logic [31:0] data,
                               input logic [3:0] strobe);
        begin
            @(negedge clk); irq_valid=1; irq_write=1;
            irq_addr={24'h100310,offset}; irq_wdata=data; irq_wstrb=strobe;
            @(posedge clk); @(negedge clk); irq_valid=0; irq_write=0;
        end
    endtask
    task automatic irq_read32(input logic [7:0] offset,
                              output logic [31:0] data);
        begin
            @(negedge clk); irq_valid=1; irq_write=0;
            irq_addr={24'h100310,offset}; #1 data=irq_rdata;
            @(posedge clk); @(negedge clk); irq_valid=0;
        end
    endtask
    task automatic timer_write32(input logic [3:0] offset,
                                 input logic [31:0] data,
                                 input logic [3:0] strobe);
        begin
            @(negedge clk); timer_valid=1; timer_write=1;
            timer_addr=32'h1003_4000+offset; timer_wdata=data;
            timer_wstrb=strobe; @(posedge clk); @(negedge clk);
            timer_valid=0; timer_write=0;
        end
    endtask
    task automatic timer_read32(input logic [3:0] offset,
                                output logic [31:0] data);
        begin
            @(negedge clk); timer_valid=1; timer_write=0;
            timer_addr=32'h1003_4000+offset; #1 data=timer_rdata;
            @(posedge clk); @(negedge clk); timer_valid=0;
        end
    endtask

    initial begin
        logic [31:0] data;
        checks=0; irq_sources=0; irq_valid=0; irq_write=0;
        irq_addr=0; irq_wdata=0; irq_wstrb=0;
        timer_valid=0; timer_write=0; timer_addr=0;
        timer_wdata=0; timer_wstrb=0;
        repeat(4) @(posedge clk); rst=0;

        irq_read32(8'h00,data); check(data==32'h4c49_4330,"LIC ID register");
        irq_read32(8'h04,data); check(data[7:0]==4,"LIC source count");
        irq_read32(8'h0c,data); check(data[3:0]==4'hf,"LIC reset enable mask");
        irq_read32(8'h10,data); check(data[3:0]==4'b0101,"LIC reset edge mask");

        @(negedge clk); irq_sources[0]=1;
        @(posedge clk); @(negedge clk); irq_sources[0]=0;
        repeat(2) @(posedge clk);
        check(external_interrupt && active_source==1,
              "edge pulse remains pending after raw source drops");
        irq_read32(8'h1c,data); check(data==1,"edge source claim ID");
        irq_read32(8'h48,data); check(data[0],"claim marks source in service");
        irq_write32(8'h1c,1,4'hf); repeat(2) @(posedge clk);
        check(!external_interrupt,"completed edge source does not repend");

        @(negedge clk); irq_sources[1]=1; repeat(2) @(posedge clk);
        check(active_source==2,"level source becomes pending");
        irq_read32(8'h1c,data); check(data==2,"level source claim ID");
        irq_write32(8'h1c,2,4'hf); repeat(2) @(posedge clk);
        check(external_interrupt && active_source==2,
              "asserted level source repends after completion");
        @(negedge clk); irq_sources[1]=0;
        irq_write32(8'h44,4'hf,4'hf); repeat(2) @(posedge clk);

        irq_write32(8'h20,32'd1,4'hf);
        irq_write32(8'h28,32'd3,4'hf);
        irq_write32(8'h40,4'b0101,4'hf); repeat(2) @(posedge clk);
        check(active_source==3,"higher priority wins over lower source ID");
        irq_write32(8'h18,32'd3,4'hf); repeat(1) @(posedge clk);
        check(!external_interrupt,"threshold masks equal-priority source");
        irq_write32(8'h18,32'd0,4'hf);
        irq_read32(8'h1c,data); check(data==3,"priority source claims correctly");
        irq_write32(8'h1c,3,4'hf);
        irq_write32(8'h44,4'hf,4'hf);
        irq_write32(8'h0c,32'hffff_0000,4'b1100);
        irq_read32(8'h0c,data);
        check(data[3:0]==4'hf,"disabled byte strobes preserve enable mask");

        check(!timer_interrupt,"timer reset compare disables MTIP");
        timer_read32(4'h8,data); check(data>0,"mtime increments every CPU clock");
        timer_write32(4'h0,32'h1122_3344,4'hf);
        timer_write32(4'h0,32'haaBB_ccDD,4'b0101);
        timer_read32(4'h0,data);
        check(data==32'h11BB_33DD,"mtimecmp honors per-byte write strobes");
        timer_write32(4'h4,32'hffff_ffff,4'hf);
        timer_write32(4'hc,32'd0,4'hf);
        timer_write32(4'h8,32'd100,4'hf);
        timer_write32(4'h0,32'd112,4'hf);
        timer_write32(4'h4,32'd0,4'hf);
        repeat(15) @(posedge clk);
        check(timer_interrupt && mtime_value>=112,
              "mtimecmp asserts MTIP at the programmed 64-bit boundary");
        timer_write32(4'h4,32'hffff_ffff,4'hf);
        check(!timer_interrupt,"raising compare deasserts MTIP");

        timer_write32(4'hc,32'd1,4'hf);
        timer_write32(4'h8,32'hffff_fffe,4'hf);
        repeat(4) @(posedge clk);
        timer_read32(4'hc,data);
        check(data>=2,"mtime carries correctly across low-word rollover");

        $display("Interrupt/timer regression: %0d checks passed",checks);
        $finish;
    end
endmodule
