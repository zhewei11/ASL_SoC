module rv32im_boot_tb;
    localparam logic [31:0] PROTOCOL_ID = 32'h5032_4D4D;
    localparam logic [31:0] RV32IMFU_MISA = 32'h4010_1120;
    localparam logic [31:0] FPU_DONE = 32'h4650_5521;

    logic clk = 1'b0;
    logic rst = 1'b1;
    int checks;
    int cycles;
    logic uart_write_seen;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst)
            uart_write_seen <= 1'b0;
        else if (mmio_valid && mmio_ready && mmio_write &&
                 mmio_addr == 32'h1003_7008 && mmio_wdata[7:0] == 8'h41)
            uart_write_seen <= 1'b1;
    end

    always @(posedge clk) begin
        if (!rst && u_cpu.u_cpu_wrapper.u_core.trap_taken)
            $display("CPU trap: pc=%08x instruction=%08x illegal=%b mtval_next=%08x",
                     u_cpu.u_cpu_wrapper.u_core.reg_id_ex.pc,
                     u_cpu.u_cpu_wrapper.u_core.reg_id_ex.instruction,
                     u_cpu.u_cpu_wrapper.u_core.reg_id_ex.illegal_instr,
                     u_cpu.u_cpu_wrapper.u_core.u_csr_registers.selected_mtval);
    end

    logic mmio_valid, mmio_ready, mmio_write;
    logic [31:0] mmio_addr, mmio_wdata, mmio_rdata;
    logic [3:0] mmio_wstrb;

    logic [3:0] i_arid, i_rid;
    logic [31:0] i_araddr, i_rdata;
    logic [7:0] i_arlen;
    logic [2:0] i_arsize;
    logic [1:0] i_arburst, i_rresp;
    logic i_arvalid, i_arready, i_rlast, i_rvalid, i_rready;

    logic [3:0] d_awid, d_bid, d_arid, d_rid;
    logic [31:0] d_awaddr, d_wdata, d_araddr, d_rdata;
    logic [7:0] d_awlen, d_arlen;
    logic [2:0] d_awsize, d_arsize;
    logic [1:0] d_awburst, d_bresp, d_arburst, d_rresp;
    logic d_awvalid, d_awready, d_wlast, d_wvalid, d_wready;
    logic d_bvalid, d_bready, d_arvalid, d_arready;
    logic d_rlast, d_rvalid, d_rready;
    logic [3:0] d_wstrb;

    assign mmio_ready = mmio_valid;
    assign mmio_rdata = (mmio_addr == 32'h1003_0030) ?
                        PROTOCOL_ID : 32'hDEAD_BEEF;

    rv32im_cpu_subsystem u_cpu (
        .timer_irq(1'b0), .mtime_value(64'd0),
        .clk(clk), .rst(rst),
        .dma_irq(1'b0), .protocol_irq(1'b0), .watchdog_irq(1'b0),
        .platform_irqs(4'd0),
        .mmio_valid(mmio_valid), .mmio_ready(mmio_ready),
        .mmio_write(mmio_write), .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata), .mmio_wstrb(mmio_wstrb),
        .mmio_rdata(mmio_rdata),
        .i_axi_arid(i_arid), .i_axi_araddr(i_araddr),
        .i_axi_arlen(i_arlen), .i_axi_arsize(i_arsize),
        .i_axi_arburst(i_arburst), .i_axi_arvalid(i_arvalid),
        .i_axi_arready(i_arready), .i_axi_rid(i_rid),
        .i_axi_rdata(i_rdata), .i_axi_rresp(i_rresp),
        .i_axi_rlast(i_rlast), .i_axi_rvalid(i_rvalid),
        .i_axi_rready(i_rready),
        .d_axi_awid(d_awid), .d_axi_awaddr(d_awaddr),
        .d_axi_awlen(d_awlen), .d_axi_awsize(d_awsize),
        .d_axi_awburst(d_awburst), .d_axi_awvalid(d_awvalid),
        .d_axi_awready(d_awready), .d_axi_wdata(d_wdata),
        .d_axi_wstrb(d_wstrb), .d_axi_wlast(d_wlast),
        .d_axi_wvalid(d_wvalid), .d_axi_wready(d_wready),
        .d_axi_bid(d_bid), .d_axi_bresp(d_bresp),
        .d_axi_bvalid(d_bvalid), .d_axi_bready(d_bready),
        .d_axi_arid(d_arid), .d_axi_araddr(d_araddr),
        .d_axi_arlen(d_arlen), .d_axi_arsize(d_arsize),
        .d_axi_arburst(d_arburst), .d_axi_arvalid(d_arvalid),
        .d_axi_arready(d_arready), .d_axi_rid(d_rid),
        .d_axi_rdata(d_rdata), .d_axi_rresp(d_rresp),
        .d_axi_rlast(d_rlast), .d_axi_rvalid(d_rvalid),
        .d_axi_rready(d_rready)
    );

    axi_bram_slave #(
        .BASE_ADDRESS(32'h0000_0000), .MEMORY_BYTES(8192),
        .READ_ONLY(1'b1), .INIT_FILE("build/rv32im_boot.mem")
    ) u_boot_rom (
        .clk(clk), .rst(rst),
        .s_axi_awid(4'd0), .s_axi_awaddr(32'd0), .s_axi_awlen(8'd0),
        .s_axi_awsize(3'd2), .s_axi_awburst(2'b01),
        .s_axi_awvalid(1'b0), .s_axi_awready(),
        .s_axi_wdata(32'd0), .s_axi_wstrb(4'd0), .s_axi_wlast(1'b1),
        .s_axi_wvalid(1'b0), .s_axi_wready(), .s_axi_bid(),
        .s_axi_bresp(), .s_axi_bvalid(), .s_axi_bready(1'b1),
        .s_axi_arid(i_arid), .s_axi_araddr(i_araddr),
        .s_axi_arlen(i_arlen), .s_axi_arsize(i_arsize),
        .s_axi_arburst(i_arburst), .s_axi_arvalid(i_arvalid),
        .s_axi_arready(i_arready), .s_axi_rid(i_rid),
        .s_axi_rdata(i_rdata), .s_axi_rresp(i_rresp),
        .s_axi_rlast(i_rlast), .s_axi_rvalid(i_rvalid),
        .s_axi_rready(i_rready)
    );

    axi_bram_slave #(
        .BASE_ADDRESS(32'h0002_0000), .MEMORY_BYTES(64 * 1024),
        .READ_ONLY(1'b0)
    ) u_dtcm (
        .clk(clk), .rst(rst),
        .s_axi_awid(d_awid), .s_axi_awaddr(d_awaddr),
        .s_axi_awlen(d_awlen), .s_axi_awsize(d_awsize),
        .s_axi_awburst(d_awburst), .s_axi_awvalid(d_awvalid),
        .s_axi_awready(d_awready), .s_axi_wdata(d_wdata),
        .s_axi_wstrb(d_wstrb), .s_axi_wlast(d_wlast),
        .s_axi_wvalid(d_wvalid), .s_axi_wready(d_wready),
        .s_axi_bid(d_bid), .s_axi_bresp(d_bresp),
        .s_axi_bvalid(d_bvalid), .s_axi_bready(d_bready),
        .s_axi_arid(d_arid), .s_axi_araddr(d_araddr),
        .s_axi_arlen(d_arlen), .s_axi_arsize(d_arsize),
        .s_axi_arburst(d_arburst), .s_axi_arvalid(d_arvalid),
        .s_axi_arready(d_arready), .s_axi_rid(d_rid),
        .s_axi_rdata(d_rdata), .s_axi_rresp(d_rresp),
        .s_axi_rlast(d_rlast), .s_axi_rvalid(d_rvalid),
        .s_axi_rready(d_rready)
    );

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
        while ((u_dtcm.memory[5] !== FPU_DONE) &&
               (u_dtcm.memory[5] !== 32'h0000_0BAD) && cycles < 4000) begin
            @(posedge clk);
            cycles++;
        end

        check(cycles < 4000, "RV32IMF firmware reaches completion marker");
        check(u_dtcm.memory[0] == 32'h1234_5678,
              "Boot ROM executes and writes DTCM signature");
        check(u_dtcm.memory[1] == PROTOCOL_ID,
              "uncached Protocol ID MMIO read reaches external bus");
        check(u_dtcm.memory[2] == 32'h4070_0000,
              "FADD.S executes through the integrated FPU");
        check(u_dtcm.memory[3] == 32'h4058_0000,
              "FMUL.S executes through the integrated FPU");
        check(u_dtcm.memory[4] == RV32IMFU_MISA,
              "MISA reports RV32IMF plus U-mode");
        check(u_dtcm.memory[7] == 32'h3FC0_0000,
              "FDIV.S executes through the integrated FPU");
        check(u_dtcm.memory[8] == 32'd4,
              "FCVT.W.S writes the integer register file");
        check(u_dtcm.memory[9] == 32'd1,
              "FCVT.W.S accumulates the inexact flag in fflags");
        check(u_dtcm.memory[10] == 32'h4070_0000,
              "FLW and FSW transfer floating-point data through DTCM");
        check(u_dtcm.memory[11] == 32'd0 && u_dtcm.memory[12] == 32'd0,
              "floating-point program completes without a trap");
        check((u_dtcm.memory[13] & 32'h0000_6000) == 32'h0000_6000,
              "mstatus.FS becomes Dirty after floating-point execution");
        check(u_dtcm.memory[6] == 32'hDEAD_BEEF,
              "second uncached MMIO page is read by firmware");
        check(uart_write_seen,
              "firmware writes boot marker to Host UART MMIO page");
        check(u_dtcm.memory[5] == FPU_DONE,
              "firmware publishes the FPU completion signature");
        check(i_arlen == 8'd3 || !i_arvalid,
              "instruction cache uses four-beat AXI line fills");

        $display("RV32IMF boot regression: %0d checks passed", checks);
        $finish;
    end
endmodule
