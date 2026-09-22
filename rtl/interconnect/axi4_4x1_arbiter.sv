module axi4_4x1_arbiter (
     input  logic clk
    ,input  logic rst
    // AXI4 AW slave interface
    ,input  logic [3:0][3:0]  s_axi_awid
    ,input  logic [3:0][31:0] s_axi_awaddr
    ,input  logic [3:0][7:0]  s_axi_awlen
    ,input  logic [3:0][2:0]  s_axi_awsize
    ,input  logic [3:0][1:0]  s_axi_awburst
    ,input  logic [3:0]       s_axi_awvalid
    ,output logic [3:0]       s_axi_awready
    // AXI4 W slave interface
    ,input  logic [3:0][31:0] s_axi_wdata
    ,input  logic [3:0][3:0]  s_axi_wstrb
    ,input  logic [3:0]       s_axi_wlast
    ,input  logic [3:0]       s_axi_wvalid
    ,output logic [3:0]       s_axi_wready
    // AXI4 B slave interface
    ,output logic [3:0][3:0]  s_axi_bid
    ,output logic [3:0][1:0]  s_axi_bresp
    ,output logic [3:0]       s_axi_bvalid
    ,input  logic [3:0]       s_axi_bready
    // AXI4 AR slave interface
    ,input  logic [3:0][3:0]  s_axi_arid
    ,input  logic [3:0][31:0] s_axi_araddr
    ,input  logic [3:0][7:0]  s_axi_arlen
    ,input  logic [3:0][2:0]  s_axi_arsize
    ,input  logic [3:0][1:0]  s_axi_arburst
    ,input  logic [3:0]       s_axi_arvalid
    ,output logic [3:0]       s_axi_arready
    // AXI4 R slave interface
    ,output logic [3:0][3:0]  s_axi_rid
    ,output logic [3:0][31:0] s_axi_rdata
    ,output logic [3:0][1:0]  s_axi_rresp
    ,output logic [3:0]       s_axi_rlast
    ,output logic [3:0]       s_axi_rvalid
    ,input  logic [3:0]       s_axi_rready
    // AXI4 AW master interface
    ,output logic [3:0]       m_axi_awid
    ,output logic [31:0]      m_axi_awaddr
    ,output logic [7:0]       m_axi_awlen
    ,output logic [2:0]       m_axi_awsize
    ,output logic [1:0]       m_axi_awburst
    ,output logic             m_axi_awvalid
    ,input  logic             m_axi_awready
    // AXI4 W master interface
    ,output logic [31:0]      m_axi_wdata
    ,output logic [3:0]       m_axi_wstrb
    ,output logic             m_axi_wlast
    ,output logic             m_axi_wvalid
    ,input  logic             m_axi_wready
    // AXI4 B master interface
    ,input  logic [3:0]       m_axi_bid
    ,input  logic [1:0]       m_axi_bresp
    ,input  logic             m_axi_bvalid
    ,output logic             m_axi_bready
    // AXI4 AR master interface
    ,output logic [3:0]       m_axi_arid
    ,output logic [31:0]      m_axi_araddr
    ,output logic [7:0]       m_axi_arlen
    ,output logic [2:0]       m_axi_arsize
    ,output logic [1:0]       m_axi_arburst
    ,output logic             m_axi_arvalid
    ,input  logic             m_axi_arready
    // AXI4 R master interface
    ,input  logic [3:0]       m_axi_rid
    ,input  logic [31:0]      m_axi_rdata
    ,input  logic [1:0]       m_axi_rresp
    ,input  logic             m_axi_rlast
    ,input  logic             m_axi_rvalid
    ,output logic             m_axi_rready
    ,output logic [1:0]       write_owner_debug
    ,output logic [1:0]       read_owner_debug
);

    logic       write_active;
    logic       read_active;
    logic [1:0] write_owner;
    logic [1:0] read_owner;
    logic [1:0] write_round_robin;
    logic [1:0] read_round_robin;
    logic [1:0] write_grant;
    logic [1:0] read_grant;
    logic       write_address_pending;
    logic       read_address_pending;
    logic [1:0] write_address_owner;
    logic [1:0] read_address_owner;
    logic [1:0] write_address_select;
    logic [1:0] read_address_select;
    logic       write_grant_valid;
    logic       read_grant_valid;
    integer     scan_w;
    integer     candidate_w;
    integer     scan_r;
    integer     candidate_r;

    always_comb begin
        write_grant = write_round_robin;
        write_grant_valid = 1'b0;
        for (scan_w = 0; scan_w < 4; scan_w = scan_w + 1) begin
            candidate_w = (32'(write_round_robin) + scan_w) & 3;
            if (!write_grant_valid && s_axi_awvalid[candidate_w]) begin
                write_grant = 2'(candidate_w);
                write_grant_valid = 1'b1;
            end
        end
    end

    always_comb begin
        read_grant = read_round_robin;
        read_grant_valid = 1'b0;
        for (scan_r = 0; scan_r < 4; scan_r = scan_r + 1) begin
            candidate_r = (32'(read_round_robin) + scan_r) & 3;
            if (!read_grant_valid && s_axi_arvalid[candidate_r]) begin
                read_grant = 2'(candidate_r);
                read_grant_valid = 1'b1;
            end
        end
    end

    always_comb begin
        s_axi_awready = 4'd0;
        s_axi_wready = 4'd0;
        s_axi_bid = '0;
        s_axi_bresp = '0;
        s_axi_bvalid = 4'd0;
        s_axi_arready = 4'd0;
        s_axi_rid = '0;
        s_axi_rdata = '0;
        s_axi_rresp = '0;
        s_axi_rlast = 4'd0;
        s_axi_rvalid = 4'd0;

        write_address_select = write_address_pending ?
                               write_address_owner : write_grant;
        m_axi_awid = s_axi_awid[write_address_select];
        m_axi_awaddr = s_axi_awaddr[write_address_select];
        m_axi_awlen = s_axi_awlen[write_address_select];
        m_axi_awsize = s_axi_awsize[write_address_select];
        m_axi_awburst = s_axi_awburst[write_address_select];
        m_axi_awvalid = !write_active &&
            (write_address_pending ? s_axi_awvalid[write_address_owner] :
                                     write_grant_valid);
        if (!write_active && m_axi_awvalid)
            s_axi_awready[write_address_select] = m_axi_awready;

        m_axi_wdata = s_axi_wdata[write_owner];
        m_axi_wstrb = s_axi_wstrb[write_owner];
        m_axi_wlast = s_axi_wlast[write_owner];
        m_axi_wvalid = write_active && s_axi_wvalid[write_owner];
        if (write_active) begin
            s_axi_wready[write_owner] = m_axi_wready;
            s_axi_bid[write_owner] = m_axi_bid;
            s_axi_bresp[write_owner] = m_axi_bresp;
            s_axi_bvalid[write_owner] = m_axi_bvalid;
        end
        m_axi_bready = write_active && s_axi_bready[write_owner];

        read_address_select = read_address_pending ?
                              read_address_owner : read_grant;
        m_axi_arid = s_axi_arid[read_address_select];
        m_axi_araddr = s_axi_araddr[read_address_select];
        m_axi_arlen = s_axi_arlen[read_address_select];
        m_axi_arsize = s_axi_arsize[read_address_select];
        m_axi_arburst = s_axi_arburst[read_address_select];
        m_axi_arvalid = !read_active &&
            (read_address_pending ? s_axi_arvalid[read_address_owner] :
                                    read_grant_valid);
        if (!read_active && m_axi_arvalid)
            s_axi_arready[read_address_select] = m_axi_arready;

        if (read_active) begin
            s_axi_rid[read_owner] = m_axi_rid;
            s_axi_rdata[read_owner] = m_axi_rdata;
            s_axi_rresp[read_owner] = m_axi_rresp;
            s_axi_rlast[read_owner] = m_axi_rlast;
            s_axi_rvalid[read_owner] = m_axi_rvalid;
        end
        m_axi_rready = read_active && s_axi_rready[read_owner];
    end

    assign write_owner_debug = write_owner;
    assign read_owner_debug = read_owner;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_active <= 1'b0;
            read_active <= 1'b0;
            write_owner <= 2'd0;
            read_owner <= 2'd0;
            write_round_robin <= 2'd0;
            read_round_robin <= 2'd0;
            write_address_pending <= 1'b0;
            read_address_pending <= 1'b0;
            write_address_owner <= 2'd0;
            read_address_owner <= 2'd0;
        end else begin
            if (!write_active && m_axi_awvalid && m_axi_awready) begin
                write_active <= 1'b1;
                write_owner <= write_address_select;
                write_address_pending <= 1'b0;
            end else if (!write_active && m_axi_awvalid) begin
                write_address_pending <= 1'b1;
                write_address_owner <= write_address_select;
            end else if (write_active && m_axi_bvalid && m_axi_bready) begin
                write_active <= 1'b0;
                write_round_robin <= write_owner + 1'b1;
            end

            if (!read_active && m_axi_arvalid && m_axi_arready) begin
                read_active <= 1'b1;
                read_owner <= read_address_select;
                read_address_pending <= 1'b0;
            end else if (!read_active && m_axi_arvalid) begin
                read_address_pending <= 1'b1;
                read_address_owner <= read_address_select;
            end else if (read_active && m_axi_rvalid && m_axi_rready &&
                         m_axi_rlast) begin
                read_active <= 1'b0;
                read_round_robin <= read_owner + 1'b1;
            end
        end
    end

endmodule
