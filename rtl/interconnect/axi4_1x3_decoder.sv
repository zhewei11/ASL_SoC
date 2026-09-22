// One AXI4 master to two local regions plus one default/external target.
// Write ownership is held from AW through B; read ownership is held from AR
// through the accepted RLAST beat.
module axi4_1x3_decoder #(
     parameter logic [31:0] REGION0_BASE  = 32'h0000_0000
    ,parameter int unsigned REGION0_BYTES = 8192
    ,parameter logic [31:0] REGION1_BASE  = 32'h0001_0000
    ,parameter int unsigned REGION1_BYTES = 64 * 1024
) (
     input  logic        clk
    ,input  logic        rst
    // AXI4 AW slave interface
    ,input  logic [3:0]  s_awid
    ,input  logic [31:0] s_awaddr
    ,input  logic [7:0]  s_awlen
    ,input  logic [2:0]  s_awsize
    ,input  logic [1:0]  s_awburst
    ,input  logic        s_awvalid
    ,output logic        s_awready
    // AXI4 W slave interface
    ,input  logic [31:0] s_wdata
    ,input  logic [3:0]  s_wstrb
    ,input  logic        s_wlast
    ,input  logic        s_wvalid
    ,output logic        s_wready
    // AXI4 B slave interface
    ,output logic [3:0]  s_bid
    ,output logic [1:0]  s_bresp
    ,output logic        s_bvalid
    ,input  logic        s_bready
    // AXI4 AR slave interface
    ,input  logic [3:0]  s_arid
    ,input  logic [31:0] s_araddr
    ,input  logic [7:0]  s_arlen
    ,input  logic [2:0]  s_arsize
    ,input  logic [1:0]  s_arburst
    ,input  logic        s_arvalid
    ,output logic        s_arready
    // AXI4 R slave interface
    ,output logic [3:0]  s_rid
    ,output logic [31:0] s_rdata
    ,output logic [1:0]  s_rresp
    ,output logic        s_rlast
    ,output logic        s_rvalid
    ,input  logic        s_rready
    // AXI4 AW master interface
    ,output logic [2:0][3:0]  m_awid
    ,output logic [2:0][31:0] m_awaddr
    ,output logic [2:0][7:0]  m_awlen
    ,output logic [2:0][2:0]  m_awsize
    ,output logic [2:0][1:0]  m_awburst
    ,output logic [2:0]       m_awvalid
    ,input  logic [2:0]       m_awready
    // AXI4 W master interface
    ,output logic [2:0][31:0] m_wdata
    ,output logic [2:0][3:0]  m_wstrb
    ,output logic [2:0]       m_wlast
    ,output logic [2:0]       m_wvalid
    ,input  logic [2:0]       m_wready
    // AXI4 B master interface
    ,input  logic [2:0][3:0]  m_bid
    ,input  logic [2:0][1:0]  m_bresp
    ,input  logic [2:0]       m_bvalid
    ,output logic [2:0]       m_bready
    // AXI4 AR master interface
    ,output logic [2:0][3:0]  m_arid
    ,output logic [2:0][31:0] m_araddr
    ,output logic [2:0][7:0]  m_arlen
    ,output logic [2:0][2:0]  m_arsize
    ,output logic [2:0][1:0]  m_arburst
    ,output logic [2:0]       m_arvalid
    ,input  logic [2:0]       m_arready
    // AXI4 R master interface
    ,input  logic [2:0][3:0]  m_rid
    ,input  logic [2:0][31:0] m_rdata
    ,input  logic [2:0][1:0]  m_rresp
    ,input  logic [2:0]       m_rlast
    ,input  logic [2:0]       m_rvalid
    ,output logic [2:0]       m_rready
);
    logic       write_active_q;
    logic       read_active_q;
    logic [1:0] write_select_q;
    logic [1:0] read_select_q;
    logic [1:0] write_address_select;
    logic [1:0] read_address_select;

    function automatic logic in_region(
         input logic [31:0] address
        ,input logic [31:0] base
        ,input int unsigned bytes
    );
        logic [32:0] address_ext;
        logic [32:0] base_ext;
        logic [32:0] limit_ext;
        begin
            address_ext = {1'b0, address};
            base_ext = {1'b0, base};
            limit_ext = base_ext + bytes;
            in_region = (bytes != 0) && address_ext >= base_ext &&
                        address_ext < limit_ext;
        end
    endfunction

    always_comb begin
        write_address_select = in_region(s_awaddr, REGION0_BASE,
                                         REGION0_BYTES) ? 2'd0 :
                               in_region(s_awaddr, REGION1_BASE,
                                         REGION1_BYTES) ? 2'd1 : 2'd2;
        read_address_select = in_region(s_araddr, REGION0_BASE,
                                        REGION0_BYTES) ? 2'd0 :
                              in_region(s_araddr, REGION1_BASE,
                                        REGION1_BYTES) ? 2'd1 : 2'd2;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_active_q <= 1'b0;
            write_select_q <= 2'd0;
            read_active_q <= 1'b0;
            read_select_q <= 2'd0;
        end else begin
            if (!write_active_q && s_awvalid && s_awready) begin
                write_active_q <= 1'b1;
                write_select_q <= write_address_select;
            end else if (write_active_q && s_bvalid && s_bready) begin
                write_active_q <= 1'b0;
            end
            if (!read_active_q && s_arvalid && s_arready) begin
                read_active_q <= 1'b1;
                read_select_q <= read_address_select;
            end else if (read_active_q && s_rvalid && s_rready && s_rlast) begin
                read_active_q <= 1'b0;
            end
        end
    end

    always_comb begin
        m_awid    = '0;
        m_awaddr  = '0;
        m_awlen   = '0;
        m_awsize  = '0;
        m_awburst = '0;
        m_awvalid = '0;
        m_wdata   = '0;
        m_wstrb   = '0;
        m_wlast   = '0;
        m_wvalid  = '0;
        m_bready  = '0;
        m_arid    = '0;
        m_araddr  = '0;
        m_arlen   = '0;
        m_arsize  = '0;
        m_arburst = '0;
        m_arvalid = '0;
        m_rready  = '0;
        s_awready = 1'b0;
        s_wready  = 1'b0;
        s_bid     = '0;
        s_bresp   = '0;
        s_bvalid  = 1'b0;
        s_arready = 1'b0;
        s_rid     = '0;
        s_rdata   = '0;
        s_rresp   = '0;
        s_rlast   = 1'b0;
        s_rvalid  = 1'b0;

        if (!write_active_q) begin
            m_awid[write_address_select]    = s_awid;
            m_awaddr[write_address_select]  = s_awaddr;
            m_awlen[write_address_select]   = s_awlen;
            m_awsize[write_address_select]  = s_awsize;
            m_awburst[write_address_select] = s_awburst;
            m_awvalid[write_address_select] = s_awvalid;
            s_awready = m_awready[write_address_select];
        end else begin
            m_wdata[write_select_q] = s_wdata;
            m_wstrb[write_select_q] = s_wstrb;
            m_wlast[write_select_q] = s_wlast;
            m_wvalid[write_select_q] = s_wvalid;
            s_wready = m_wready[write_select_q];
            s_bid = m_bid[write_select_q];
            s_bresp = m_bresp[write_select_q];
            s_bvalid = m_bvalid[write_select_q];
            m_bready[write_select_q] = s_bready;
        end

        if (!read_active_q) begin
            m_arid[read_address_select]    = s_arid;
            m_araddr[read_address_select]  = s_araddr;
            m_arlen[read_address_select]   = s_arlen;
            m_arsize[read_address_select]  = s_arsize;
            m_arburst[read_address_select] = s_arburst;
            m_arvalid[read_address_select] = s_arvalid;
            s_arready = m_arready[read_address_select];
        end else begin
            s_rid = m_rid[read_select_q];
            s_rdata = m_rdata[read_select_q];
            s_rresp = m_rresp[read_select_q];
            s_rlast = m_rlast[read_select_q];
            s_rvalid = m_rvalid[read_select_q];
            m_rready[read_select_q] = s_rready;
        end
    end
endmodule
