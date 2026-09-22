`timescale 1ns/1ps

module axi_infrastructure_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic [3:0][3:0] s_axi_awid;
    logic [3:0][31:0] s_axi_awaddr;
    logic [3:0][7:0] s_axi_awlen;
    logic [3:0][2:0] s_axi_awsize;
    logic [3:0][1:0] s_axi_awburst;
    logic [3:0] s_axi_awvalid;
    logic [3:0] s_axi_awready;
    logic [3:0][31:0] s_axi_wdata;
    logic [3:0][3:0] s_axi_wstrb;
    logic [3:0] s_axi_wlast;
    logic [3:0] s_axi_wvalid;
    logic [3:0] s_axi_wready;
    logic [3:0][3:0] s_axi_bid;
    logic [3:0][1:0] s_axi_bresp;
    logic [3:0] s_axi_bvalid;
    logic [3:0] s_axi_bready;
    logic [3:0][3:0] s_axi_arid;
    logic [3:0][31:0] s_axi_araddr;
    logic [3:0][7:0] s_axi_arlen;
    logic [3:0][2:0] s_axi_arsize;
    logic [3:0][1:0] s_axi_arburst;
    logic [3:0] s_axi_arvalid;
    logic [3:0] s_axi_arready;
    logic [3:0][3:0] s_axi_rid;
    logic [3:0][31:0] s_axi_rdata;
    logic [3:0][1:0] s_axi_rresp;
    logic [3:0] s_axi_rlast;
    logic [3:0] s_axi_rvalid;
    logic [3:0] s_axi_rready;

    logic [3:0] m_axi_awid;
    logic [31:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen;
    logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst;
    logic m_axi_awvalid;
    logic m_axi_awready;
    logic [31:0] m_axi_wdata;
    logic [3:0] m_axi_wstrb;
    logic m_axi_wlast;
    logic m_axi_wvalid;
    logic m_axi_wready;
    logic [3:0] m_axi_bid;
    logic [1:0] m_axi_bresp;
    logic m_axi_bvalid;
    logic m_axi_bready;
    logic [3:0] m_axi_arid;
    logic [31:0] m_axi_araddr;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst;
    logic m_axi_arvalid;
    logic m_axi_arready;
    logic [3:0] m_axi_rid;
    logic [31:0] m_axi_rdata;
    logic [1:0] m_axi_rresp;
    logic m_axi_rlast;
    logic m_axi_rvalid;
    logic m_axi_rready;
    logic [1:0] write_owner_debug;
    logic [1:0] read_owner_debug;

    logic [3:0] rom_awid;
    logic [31:0] rom_awaddr;
    logic [7:0] rom_awlen;
    logic [2:0] rom_awsize;
    logic [1:0] rom_awburst;
    logic rom_awvalid;
    logic rom_awready;
    logic [31:0] rom_wdata;
    logic [3:0] rom_wstrb;
    logic rom_wlast;
    logic rom_wvalid;
    logic rom_wready;
    logic [3:0] rom_bid;
    logic [1:0] rom_bresp;
    logic rom_bvalid;
    logic rom_bready;
    logic rom_arready;
    logic [3:0] rom_rid;
    logic [31:0] rom_rdata;
    logic [1:0] rom_rresp;
    logic rom_rlast;
    logic rom_rvalid;

    integer checks = 0;
    integer timeout;

    axi4_4x1_arbiter arbiter (.*);

    axi_bram_slave #(
        .BASE_ADDRESS(32'h2000_0000),
        .MEMORY_BYTES(256)
    ) ram (
        .clk(clk), .rst(rst),
        .s_axi_awid(m_axi_awid), .s_axi_awaddr(m_axi_awaddr),
        .s_axi_awlen(m_axi_awlen), .s_axi_awsize(m_axi_awsize),
        .s_axi_awburst(m_axi_awburst), .s_axi_awvalid(m_axi_awvalid),
        .s_axi_awready(m_axi_awready), .s_axi_wdata(m_axi_wdata),
        .s_axi_wstrb(m_axi_wstrb), .s_axi_wlast(m_axi_wlast),
        .s_axi_wvalid(m_axi_wvalid), .s_axi_wready(m_axi_wready),
        .s_axi_bid(m_axi_bid), .s_axi_bresp(m_axi_bresp),
        .s_axi_bvalid(m_axi_bvalid), .s_axi_bready(m_axi_bready),
        .s_axi_arid(m_axi_arid), .s_axi_araddr(m_axi_araddr),
        .s_axi_arlen(m_axi_arlen), .s_axi_arsize(m_axi_arsize),
        .s_axi_arburst(m_axi_arburst), .s_axi_arvalid(m_axi_arvalid),
        .s_axi_arready(m_axi_arready), .s_axi_rid(m_axi_rid),
        .s_axi_rdata(m_axi_rdata), .s_axi_rresp(m_axi_rresp),
        .s_axi_rlast(m_axi_rlast), .s_axi_rvalid(m_axi_rvalid),
        .s_axi_rready(m_axi_rready)
    );

    axi_bram_slave #(
        .BASE_ADDRESS(32'h0000_0000),
        .MEMORY_BYTES(256),
        .READ_ONLY(1'b1)
    ) rom (
        .clk(clk), .rst(rst),
        .s_axi_awid(rom_awid), .s_axi_awaddr(rom_awaddr),
        .s_axi_awlen(rom_awlen), .s_axi_awsize(rom_awsize),
        .s_axi_awburst(rom_awburst), .s_axi_awvalid(rom_awvalid),
        .s_axi_awready(rom_awready), .s_axi_wdata(rom_wdata),
        .s_axi_wstrb(rom_wstrb), .s_axi_wlast(rom_wlast),
        .s_axi_wvalid(rom_wvalid), .s_axi_wready(rom_wready),
        .s_axi_bid(rom_bid), .s_axi_bresp(rom_bresp),
        .s_axi_bvalid(rom_bvalid), .s_axi_bready(rom_bready),
        .s_axi_arid(4'd0), .s_axi_araddr(32'd0), .s_axi_arlen(8'd0),
        .s_axi_arsize(3'd2), .s_axi_arburst(2'b01),
        .s_axi_arvalid(1'b0), .s_axi_arready(rom_arready),
        .s_axi_rid(rom_rid), .s_axi_rdata(rom_rdata),
        .s_axi_rresp(rom_rresp), .s_axi_rlast(rom_rlast),
        .s_axi_rvalid(rom_rvalid), .s_axi_rready(1'b1)
    );

    task automatic check_condition(input logic condition, input string message);
        begin
            if (!condition) begin
                $display("FAIL: %s", message);
                $fatal(1);
            end
            checks = checks + 1;
        end
    endtask

    task automatic send_write_data(
        input integer master,
        input logic [31:0] data,
        input logic [3:0] strobe
    );
        begin
            @(negedge clk);
            s_axi_wdata[master] = data;
            s_axi_wstrb[master] = strobe;
            s_axi_wlast[master] = 1'b1;
            s_axi_wvalid[master] = 1'b1;
            while (!s_axi_wready[master])
                @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            s_axi_wvalid[master] = 1'b0;
        end
    endtask

    initial begin
        s_axi_awid = '0; s_axi_awaddr = '0; s_axi_awlen = '0;
        s_axi_awsize = '0; s_axi_awburst = '0; s_axi_awvalid = '0;
        s_axi_wdata = '0; s_axi_wstrb = '0; s_axi_wlast = '0;
        s_axi_wvalid = '0; s_axi_bready = 4'hF;
        s_axi_arid = '0; s_axi_araddr = '0; s_axi_arlen = '0;
        s_axi_arsize = '0; s_axi_arburst = '0; s_axi_arvalid = '0;
        s_axi_rready = '0;
        rom_awid = 4'hC; rom_awaddr = 32'd0; rom_awlen = 8'd0;
        rom_awsize = 3'd2; rom_awburst = 2'b01; rom_awvalid = 1'b0;
        rom_wdata = 32'hDEAD_BEEF; rom_wstrb = 4'hF;
        rom_wlast = 1'b1; rom_wvalid = 1'b0; rom_bready = 1'b1;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // A grant must be held even before the AR handshake. Master 3 arrives
        // first while the slave is stalled; master 0 must not steal the
        // visible address when it arrives one cycle later.
        force m_axi_arready = 1'b0;
        @(negedge clk);
        s_axi_arid[3] = 4'hD;
        s_axi_araddr[3] = 32'h2000_0008;
        s_axi_arlen[3] = 0; s_axi_arsize[3] = 3'd2;
        s_axi_arburst[3] = 2'b01; s_axi_arvalid[3] = 1;
        #1;
        check_condition(m_axi_arvalid && m_axi_araddr == 32'h2000_0008,
                        "first stalled read request becomes pending grant");
        @(posedge clk); @(negedge clk);
        s_axi_arid[0] = 4'hE;
        s_axi_araddr[0] = 32'h2000_000C;
        s_axi_arlen[0] = 0; s_axi_arsize[0] = 3'd2;
        s_axi_arburst[0] = 2'b01; s_axi_arvalid[0] = 1;
        #1;
        check_condition(m_axi_arvalid && m_axi_arid == 4'hD &&
                        m_axi_araddr == 32'h2000_0008,
                        "AR payload remains stable when a competitor arrives");
        release m_axi_arready;
        #1;
        check_condition(s_axi_arready[3] && !s_axi_arready[0],
                        "held read grant handshakes only its original owner");
        @(posedge clk); @(negedge clk);
        s_axi_arvalid[3] = 0; s_axi_arvalid[0] = 0;
        s_axi_rready[3] = 1;
        repeat (3) @(posedge clk);
        @(negedge clk); s_axi_rready[3] = 0;

        @(negedge clk);
        s_axi_awid[0] = 4'hA;
        s_axi_awaddr[0] = 32'h2000_0000;
        s_axi_awlen[0] = 0;
        s_axi_awsize[0] = 3'd2;
        s_axi_awburst[0] = 2'b01;
        s_axi_awvalid[0] = 1'b1;
        s_axi_awid[1] = 4'hB;
        s_axi_awaddr[1] = 32'h2000_0004;
        s_axi_awlen[1] = 0;
        s_axi_awsize[1] = 3'd2;
        s_axi_awburst[1] = 2'b01;
        s_axi_awvalid[1] = 1'b1;
        #1;
        check_condition(s_axi_awready[0] && !s_axi_awready[1],
                        "round-robin reset grant must select master 0");
        @(posedge clk);
        @(negedge clk);
        s_axi_awvalid[0] = 1'b0;
        check_condition(write_owner_debug == 0 && !s_axi_awready[1],
                        "write owner must remain locked until B response");
        send_write_data(0, 32'h1122_3344, 4'hF);
        timeout = 0;
        while (!s_axi_bvalid[0] && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        check_condition(timeout < 20 && s_axi_bid[0] == 4'hA &&
                        s_axi_bresp[0] == 0,
                        "write response must return only to owner 0");

        timeout = 0;
        while (!s_axi_awready[1] && timeout < 20) begin
            @(negedge clk); timeout = timeout + 1;
        end
        check_condition(timeout < 20, "master 1 must receive the next write grant");
        @(posedge clk);
        @(negedge clk);
        s_axi_awvalid[1] = 1'b0;
        send_write_data(1, 32'hAABB_CCDD, 4'b0101);
        timeout = 0;
        while (!s_axi_bvalid[1] && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        check_condition(timeout < 20 && s_axi_bid[1] == 4'hB,
                        "write response must return only to owner 1");

        @(negedge clk);
        s_axi_arid[2] = 4'h2;
        s_axi_araddr[2] = 32'h2000_0000;
        s_axi_arlen[2] = 1;
        s_axi_arsize[2] = 3'd2;
        s_axi_arburst[2] = 2'b01;
        s_axi_arvalid[2] = 1'b1;
        s_axi_arid[3] = 4'h3;
        s_axi_araddr[3] = 32'h2000_0004;
        s_axi_arlen[3] = 0;
        s_axi_arsize[3] = 3'd2;
        s_axi_arburst[3] = 2'b01;
        s_axi_arvalid[3] = 1'b1;
        #1;
        check_condition(s_axi_arready[2] && !s_axi_arready[3],
                        "read arbitration must select master 2 first");
        @(posedge clk);
        @(negedge clk);
        s_axi_arvalid[2] = 1'b0;
        timeout = 0;
        while (!s_axi_rvalid[2] && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        check_condition(timeout < 20 && read_owner_debug == 2 &&
                        !s_axi_arready[3],
                        "read owner must remain locked while R is stalled");
        check_condition(s_axi_rdata[2] == 32'h1122_3344 && !s_axi_rlast[2],
                        "first burst beat must return word zero");
        s_axi_rready[2] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        timeout = 0;
        while (!s_axi_rvalid[2] && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        check_condition(s_axi_rdata[2] == 32'h00BB_00DD && s_axi_rlast[2],
                        "byte strobes and second burst beat must be preserved");
        @(posedge clk);
        @(negedge clk);
        s_axi_rready[2] = 1'b0;
        s_axi_arvalid[3] = 1'b0;

        rom_awvalid = 1'b1;
        while (!rom_awready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        rom_awvalid = 1'b0;
        rom_wvalid = 1'b1;
        while (!rom_wready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        rom_wvalid = 1'b0;
        timeout = 0;
        while (!rom_bvalid && timeout < 20) begin
            @(posedge clk); timeout = timeout + 1;
        end
        check_condition(timeout < 20 && rom_bid == 4'hC && rom_bresp == 2'b10,
                        "Boot ROM must reject writes with SLVERR");

        $display("PASS: axi_infrastructure_tb (%0d checks)", checks);
        $finish;
    end

    initial begin
        #20_000;
        $fatal(1, "global timeout");
    end
endmodule
