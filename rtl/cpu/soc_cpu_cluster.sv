`include "asl_soc_config.svh"

// RV32IMF CPU plus local Boot ROM/ITCM/DTCM. Cache-line traffic which does not
// hit a local region is exported as separate instruction/data AXI masters.
module soc_cpu_cluster #(
     parameter BOOT_ROM_INIT_FILE = ""
    ,parameter ITCM_INIT_FILE = ""
    ,parameter DTCM_INIT_FILE = ""
    ,parameter bit ENABLE_FPU = 1'b1
) (
     input  logic        clk
    ,input  logic        rst
    // Interrupts
    ,input  logic        dma_irq
    ,input  logic        protocol_irq
    ,input  logic        watchdog_irq
    ,input  logic [3:0]  platform_irqs
    ,input  logic        timer_irq
    ,input  logic [63:0] mtime_value

    // MMIO interface
    ,output logic        mmio_valid
    ,input  logic        mmio_ready
    ,output logic        mmio_write
    ,output logic [31:0] mmio_addr
    ,output logic [31:0] mmio_wdata
    ,output logic [3:0]  mmio_wstrb
    ,input  logic [31:0] mmio_rdata

    // External AXI master interfaces
    ,output logic [3:0]  i_axi_arid
    ,output logic [31:0] i_axi_araddr
    ,output logic [7:0]  i_axi_arlen
    ,output logic [2:0]  i_axi_arsize
    ,output logic [1:0]  i_axi_arburst
    ,output logic        i_axi_arvalid
    ,input  logic        i_axi_arready
    ,input  logic [3:0]  i_axi_rid
    ,input  logic [31:0] i_axi_rdata
    ,input  logic [1:0]  i_axi_rresp
    ,input  logic        i_axi_rlast
    ,input  logic        i_axi_rvalid
    ,output logic        i_axi_rready

    // External AXI master interfaces
    ,output logic [3:0]  d_axi_awid
    ,output logic [31:0] d_axi_awaddr
    ,output logic [7:0]  d_axi_awlen
    ,output logic [2:0]  d_axi_awsize
    ,output logic [1:0]  d_axi_awburst
    ,output logic        d_axi_awvalid
    ,input  logic        d_axi_awready
    ,output logic [31:0] d_axi_wdata
    ,output logic [3:0]  d_axi_wstrb
    ,output logic        d_axi_wlast
    ,output logic        d_axi_wvalid
    ,input  logic        d_axi_wready
    ,input  logic [3:0]  d_axi_bid
    ,input  logic [1:0]  d_axi_bresp
    ,input  logic        d_axi_bvalid
    ,output logic        d_axi_bready
    ,output logic [3:0]  d_axi_arid
    ,output logic [31:0] d_axi_araddr
    ,output logic [7:0]  d_axi_arlen
    ,output logic [2:0]  d_axi_arsize
    ,output logic [1:0]  d_axi_arburst
    ,output logic        d_axi_arvalid
    ,input  logic        d_axi_arready
    ,input  logic [3:0]  d_axi_rid
    ,input  logic [31:0] d_axi_rdata
    ,input  logic [1:0]  d_axi_rresp
    ,input  logic        d_axi_rlast
    ,input  logic        d_axi_rvalid
    ,output logic        d_axi_rready
);
    // CPU instruction AXI read address channel.
    logic [3:0]  cpu_i_arid;
    logic [31:0] cpu_i_araddr;
    logic [7:0]  cpu_i_arlen;
    logic [2:0]  cpu_i_arsize;
    logic [1:0]  cpu_i_arburst;
    logic        cpu_i_arvalid;
    logic        cpu_i_arready;

    // CPU instruction AXI read data channel.
    logic [3:0]  cpu_i_rid;
    logic [31:0] cpu_i_rdata;
    logic [1:0]  cpu_i_rresp;
    logic        cpu_i_rlast;
    logic        cpu_i_rvalid;
    logic        cpu_i_rready;

    // CPU data AXI write address channel.
    logic [3:0]  cpu_d_awid;
    logic [31:0] cpu_d_awaddr;
    logic [7:0]  cpu_d_awlen;
    logic [2:0]  cpu_d_awsize;
    logic [1:0]  cpu_d_awburst;
    logic        cpu_d_awvalid;
    logic        cpu_d_awready;

    // CPU data AXI write data channel.
    logic [31:0] cpu_d_wdata;
    logic [3:0]  cpu_d_wstrb;
    logic        cpu_d_wlast;
    logic        cpu_d_wvalid;
    logic        cpu_d_wready;

    // CPU data AXI write response channel.
    logic [3:0] cpu_d_bid;
    logic [1:0] cpu_d_bresp;
    logic       cpu_d_bvalid;
    logic       cpu_d_bready;

    // CPU data AXI read address channel.
    logic [3:0]  cpu_d_arid;
    logic [31:0] cpu_d_araddr;
    logic [7:0]  cpu_d_arlen;
    logic [2:0]  cpu_d_arsize;
    logic [1:0]  cpu_d_arburst;
    logic        cpu_d_arvalid;
    logic        cpu_d_arready;

    // CPU data AXI read data channel.
    logic [3:0]  cpu_d_rid;
    logic [31:0] cpu_d_rdata;
    logic [1:0]  cpu_d_rresp;
    logic        cpu_d_rlast;
    logic        cpu_d_rvalid;
    logic        cpu_d_rready;

    // Instruction-side decoder write address channel (unused by the CPU).
    logic [2:0][3:0]  im_awid;
    logic [2:0][31:0] im_awaddr;
    logic [2:0][7:0]  im_awlen;
    logic [2:0][2:0]  im_awsize;
    logic [2:0][1:0]  im_awburst;
    logic [2:0]       im_awvalid;
    logic [2:0]       im_awready;

    // Instruction-side decoder write data and response channels.
    logic [2:0][31:0] im_wdata;
    logic [2:0][3:0]  im_wstrb;
    logic [2:0]       im_wlast;
    logic [2:0]       im_wvalid;
    logic [2:0]       im_wready;
    logic [2:0][3:0]  im_bid;
    logic [2:0][1:0]  im_bresp;
    logic [2:0]       im_bvalid;
    logic [2:0]       im_bready;

    // Instruction-side decoder read address channel.
    logic [2:0][3:0]  im_arid;
    logic [2:0][31:0] im_araddr;
    logic [2:0][7:0]  im_arlen;
    logic [2:0][2:0]  im_arsize;
    logic [2:0][1:0]  im_arburst;
    logic [2:0]       im_arvalid;
    logic [2:0]       im_arready;

    // Instruction-side decoder read data channel.
    logic [2:0][3:0]  im_rid;
    logic [2:0][31:0] im_rdata;
    logic [2:0][1:0]  im_rresp;
    logic [2:0]       im_rlast;
    logic [2:0]       im_rvalid;
    logic [2:0]       im_rready;

    // Data-side decoder write address channel.
    logic [2:0][3:0]  dm_awid;
    logic [2:0][31:0] dm_awaddr;
    logic [2:0][7:0]  dm_awlen;
    logic [2:0][2:0]  dm_awsize;
    logic [2:0][1:0]  dm_awburst;
    logic [2:0]       dm_awvalid;
    logic [2:0]       dm_awready;

    // Data-side decoder write data channel.
    logic [2:0][31:0] dm_wdata;
    logic [2:0][3:0]  dm_wstrb;
    logic [2:0]       dm_wlast;
    logic [2:0]       dm_wvalid;
    logic [2:0]       dm_wready;

    // Data-side decoder write response channel.
    logic [2:0][3:0] dm_bid;
    logic [2:0][1:0] dm_bresp;
    logic [2:0]      dm_bvalid;
    logic [2:0]      dm_bready;

    // Data-side decoder read address channel.
    logic [2:0][3:0]  dm_arid;
    logic [2:0][31:0] dm_araddr;
    logic [2:0][7:0]  dm_arlen;
    logic [2:0][2:0]  dm_arsize;
    logic [2:0][1:0]  dm_arburst;
    logic [2:0]       dm_arvalid;
    logic [2:0]       dm_arready;

    // Data-side decoder read data channel.
    logic [2:0][3:0]  dm_rid;
    logic [2:0][31:0] dm_rdata;
    logic [2:0][1:0]  dm_rresp;
    logic [2:0]       dm_rlast;
    logic [2:0]       dm_rvalid;
    logic [2:0]       dm_rready;

    rv32im_cpu_subsystem #(
         .ENABLE_FPU (ENABLE_FPU)
    ) u_cpu (
         .clk           (clk)
        ,.rst           (rst)
        ,.dma_irq       (dma_irq)
        ,.protocol_irq  (protocol_irq)
        ,.watchdog_irq  (watchdog_irq)
        ,.platform_irqs (platform_irqs)
        ,.timer_irq     (timer_irq)
        ,.mtime_value   (mtime_value)
        ,.mmio_valid    (mmio_valid)
        ,.mmio_ready    (mmio_ready)
        ,.mmio_write    (mmio_write)
        ,.mmio_addr     (mmio_addr)
        ,.mmio_wdata    (mmio_wdata)
        ,.mmio_wstrb    (mmio_wstrb)
        ,.mmio_rdata    (mmio_rdata)
        ,.i_axi_arid    (cpu_i_arid)
        ,.i_axi_araddr  (cpu_i_araddr)
        ,.i_axi_arlen   (cpu_i_arlen)
        ,.i_axi_arsize  (cpu_i_arsize)
        ,.i_axi_arburst (cpu_i_arburst)
        ,.i_axi_arvalid (cpu_i_arvalid)
        ,.i_axi_arready (cpu_i_arready)
        ,.i_axi_rid     (cpu_i_rid)
        ,.i_axi_rdata   (cpu_i_rdata)
        ,.i_axi_rresp   (cpu_i_rresp)
        ,.i_axi_rlast   (cpu_i_rlast)
        ,.i_axi_rvalid  (cpu_i_rvalid)
        ,.i_axi_rready  (cpu_i_rready)
        ,.d_axi_awid    (cpu_d_awid)
        ,.d_axi_awaddr  (cpu_d_awaddr)
        ,.d_axi_awlen   (cpu_d_awlen)
        ,.d_axi_awsize  (cpu_d_awsize)
        ,.d_axi_awburst (cpu_d_awburst)
        ,.d_axi_awvalid (cpu_d_awvalid)
        ,.d_axi_awready (cpu_d_awready)
        ,.d_axi_wdata   (cpu_d_wdata)
        ,.d_axi_wstrb   (cpu_d_wstrb)
        ,.d_axi_wlast   (cpu_d_wlast)
        ,.d_axi_wvalid  (cpu_d_wvalid)
        ,.d_axi_wready  (cpu_d_wready)
        ,.d_axi_bid     (cpu_d_bid)
        ,.d_axi_bresp   (cpu_d_bresp)
        ,.d_axi_bvalid  (cpu_d_bvalid)
        ,.d_axi_bready  (cpu_d_bready)
        ,.d_axi_arid    (cpu_d_arid)
        ,.d_axi_araddr  (cpu_d_araddr)
        ,.d_axi_arlen   (cpu_d_arlen)
        ,.d_axi_arsize  (cpu_d_arsize)
        ,.d_axi_arburst (cpu_d_arburst)
        ,.d_axi_arvalid (cpu_d_arvalid)
        ,.d_axi_arready (cpu_d_arready)
        ,.d_axi_rid     (cpu_d_rid)
        ,.d_axi_rdata   (cpu_d_rdata)
        ,.d_axi_rresp   (cpu_d_rresp)
        ,.d_axi_rlast   (cpu_d_rlast)
        ,.d_axi_rvalid  (cpu_d_rvalid)
        ,.d_axi_rready  (cpu_d_rready)
    );

    axi4_1x3_decoder #(
         .REGION0_BASE  (`ASL_SOC_BOOT_ROM_BASE)
        ,.REGION0_BYTES (`ASL_SOC_BOOT_ROM_BYTES)
        ,.REGION1_BASE  (`ASL_SOC_ITCM_BASE)
        ,.REGION1_BYTES (`ASL_SOC_ITCM_BYTES)
    ) u_instruction_decoder (
         .clk       (clk)
        ,.rst       (rst)
        ,.s_awid    ('0)
        ,.s_awaddr  ('0)
        ,.s_awlen   ('0)
        ,.s_awsize  ('0)
        ,.s_awburst ('0)
        ,.s_awvalid (1'b0)
        ,.s_awready ()
        ,.s_wdata   ('0)
        ,.s_wstrb   ('0)
        ,.s_wlast   (1'b0)
        ,.s_wvalid  (1'b0)
        ,.s_wready  ()
        ,.s_bid     ()
        ,.s_bresp   ()
        ,.s_bvalid  ()
        ,.s_bready  (1'b0)
        ,.s_arid    (cpu_i_arid)
        ,.s_araddr  (cpu_i_araddr)
        ,.s_arlen   (cpu_i_arlen)
        ,.s_arsize  (cpu_i_arsize)
        ,.s_arburst (cpu_i_arburst)
        ,.s_arvalid (cpu_i_arvalid)
        ,.s_arready (cpu_i_arready)
        ,.s_rid     (cpu_i_rid)
        ,.s_rdata   (cpu_i_rdata)
        ,.s_rresp   (cpu_i_rresp)
        ,.s_rlast   (cpu_i_rlast)
        ,.s_rvalid  (cpu_i_rvalid)
        ,.s_rready  (cpu_i_rready)
        ,.m_awid    (im_awid)
        ,.m_awaddr  (im_awaddr)
        ,.m_awlen   (im_awlen)
        ,.m_awsize  (im_awsize)
        ,.m_awburst (im_awburst)
        ,.m_awvalid (im_awvalid)
        ,.m_awready (im_awready)
        ,.m_wdata   (im_wdata)
        ,.m_wstrb   (im_wstrb)
        ,.m_wlast   (im_wlast)
        ,.m_wvalid  (im_wvalid)
        ,.m_wready  (im_wready)
        ,.m_bid     (im_bid)
        ,.m_bresp   (im_bresp)
        ,.m_bvalid  (im_bvalid)
        ,.m_bready  (im_bready)
        ,.m_arid    (im_arid)
        ,.m_araddr  (im_araddr)
        ,.m_arlen   (im_arlen)
        ,.m_arsize  (im_arsize)
        ,.m_arburst (im_arburst)
        ,.m_arvalid (im_arvalid)
        ,.m_arready (im_arready)
        ,.m_rid     (im_rid)
        ,.m_rdata   (im_rdata)
        ,.m_rresp   (im_rresp)
        ,.m_rlast   (im_rlast)
        ,.m_rvalid  (im_rvalid)
        ,.m_rready  (im_rready)
    );

    axi4_1x3_decoder #(
         .REGION0_BASE  (`ASL_SOC_DTCM_BASE)
        ,.REGION0_BYTES (`ASL_SOC_DTCM_BYTES)
        ,.REGION1_BASE  (32'd0)
        ,.REGION1_BYTES (0)
    ) u_data_decoder (
         .clk       (clk)
        ,.rst       (rst)
        ,.s_awid    (cpu_d_awid)
        ,.s_awaddr  (cpu_d_awaddr)
        ,.s_awlen   (cpu_d_awlen)
        ,.s_awsize  (cpu_d_awsize)
        ,.s_awburst (cpu_d_awburst)
        ,.s_awvalid (cpu_d_awvalid)
        ,.s_awready (cpu_d_awready)
        ,.s_wdata   (cpu_d_wdata)
        ,.s_wstrb   (cpu_d_wstrb)
        ,.s_wlast   (cpu_d_wlast)
        ,.s_wvalid  (cpu_d_wvalid)
        ,.s_wready  (cpu_d_wready)
        ,.s_bid     (cpu_d_bid)
        ,.s_bresp   (cpu_d_bresp)
        ,.s_bvalid  (cpu_d_bvalid)
        ,.s_bready  (cpu_d_bready)
        ,.s_arid    (cpu_d_arid)
        ,.s_araddr  (cpu_d_araddr)
        ,.s_arlen   (cpu_d_arlen)
        ,.s_arsize  (cpu_d_arsize)
        ,.s_arburst (cpu_d_arburst)
        ,.s_arvalid (cpu_d_arvalid)
        ,.s_arready (cpu_d_arready)
        ,.s_rid     (cpu_d_rid)
        ,.s_rdata   (cpu_d_rdata)
        ,.s_rresp   (cpu_d_rresp)
        ,.s_rlast   (cpu_d_rlast)
        ,.s_rvalid  (cpu_d_rvalid)
        ,.s_rready  (cpu_d_rready)
        ,.m_awid    (dm_awid)
        ,.m_awaddr  (dm_awaddr)
        ,.m_awlen   (dm_awlen)
        ,.m_awsize  (dm_awsize)
        ,.m_awburst (dm_awburst)
        ,.m_awvalid (dm_awvalid)
        ,.m_awready (dm_awready)
        ,.m_wdata   (dm_wdata)
        ,.m_wstrb   (dm_wstrb)
        ,.m_wlast   (dm_wlast)
        ,.m_wvalid  (dm_wvalid)
        ,.m_wready  (dm_wready)
        ,.m_bid     (dm_bid)
        ,.m_bresp   (dm_bresp)
        ,.m_bvalid  (dm_bvalid)
        ,.m_bready  (dm_bready)
        ,.m_arid    (dm_arid)
        ,.m_araddr  (dm_araddr)
        ,.m_arlen   (dm_arlen)
        ,.m_arsize  (dm_arsize)
        ,.m_arburst (dm_arburst)
        ,.m_arvalid (dm_arvalid)
        ,.m_arready (dm_arready)
        ,.m_rid     (dm_rid)
        ,.m_rdata   (dm_rdata)
        ,.m_rresp   (dm_rresp)
        ,.m_rlast   (dm_rlast)
        ,.m_rvalid  (dm_rvalid)
        ,.m_rready  (dm_rready)
    );

    axi_bram_slave #(.BASE_ADDRESS(`ASL_SOC_BOOT_ROM_BASE)
         ,.MEMORY_BYTES (`ASL_SOC_BOOT_ROM_BYTES)
         ,.READ_ONLY    (1'b1)
         ,.INIT_FILE    (BOOT_ROM_INIT_FILE)
    )u_boot_rom (
         .clk           (clk)
        ,.rst           (rst)
        ,.s_axi_awid    (im_awid[0])
        ,.s_axi_awaddr  (im_awaddr[0])
        ,.s_axi_awlen   (im_awlen[0])
        ,.s_axi_awsize  (im_awsize[0])
        ,.s_axi_awburst (im_awburst[0])
        ,.s_axi_awvalid (im_awvalid[0])
        ,.s_axi_awready (im_awready[0])
        ,.s_axi_wdata   (im_wdata[0])
        ,.s_axi_wstrb   (im_wstrb[0])
        ,.s_axi_wlast   (im_wlast[0])
        ,.s_axi_wvalid  (im_wvalid[0])
        ,.s_axi_wready  (im_wready[0])
        ,.s_axi_bid     (im_bid[0])
        ,.s_axi_bresp   (im_bresp[0])
        ,.s_axi_bvalid  (im_bvalid[0])
        ,.s_axi_bready  (im_bready[0])
        ,.s_axi_arid    (im_arid[0])
        ,.s_axi_araddr  (im_araddr[0])
        ,.s_axi_arlen   (im_arlen[0])
        ,.s_axi_arsize  (im_arsize[0])
        ,.s_axi_arburst (im_arburst[0])
        ,.s_axi_arvalid (im_arvalid[0])
        ,.s_axi_arready (im_arready[0])
        ,.s_axi_rid     (im_rid[0])
        ,.s_axi_rdata   (im_rdata[0])
        ,.s_axi_rresp   (im_rresp[0])
        ,.s_axi_rlast   (im_rlast[0])
        ,.s_axi_rvalid  (im_rvalid[0])
        ,.s_axi_rready(im_rready[0]));

    axi_bram_slave #(.BASE_ADDRESS(`ASL_SOC_ITCM_BASE)
        ,.MEMORY_BYTES  (`ASL_SOC_ITCM_BYTES)
        ,.READ_ONLY     (1'b0)
        ,.INIT_FILE     (ITCM_INIT_FILE)
    )u_itcm (
         .clk           (clk)
        ,.rst           (rst)
        ,.s_axi_awid    (im_awid[1])
        ,.s_axi_awaddr  (im_awaddr[1])
        ,.s_axi_awlen   (im_awlen[1])
        ,.s_axi_awsize  (im_awsize[1])
        ,.s_axi_awburst (im_awburst[1])
        ,.s_axi_awvalid (im_awvalid[1])
        ,.s_axi_awready (im_awready[1])
        ,.s_axi_wdata   (im_wdata[1])
        ,.s_axi_wstrb   (im_wstrb[1])
        ,.s_axi_wlast   (im_wlast[1])
        ,.s_axi_wvalid  (im_wvalid[1])
        ,.s_axi_wready  (im_wready[1])
        ,.s_axi_bid     (im_bid[1])
        ,.s_axi_bresp   (im_bresp[1])
        ,.s_axi_bvalid  (im_bvalid[1])
        ,.s_axi_bready  (im_bready[1])
        ,.s_axi_arid    (im_arid[1])
        ,.s_axi_araddr  (im_araddr[1])
        ,.s_axi_arlen   (im_arlen[1])
        ,.s_axi_arsize  (im_arsize[1])
        ,.s_axi_arburst (im_arburst[1])
        ,.s_axi_arvalid (im_arvalid[1])
        ,.s_axi_arready (im_arready[1])
        ,.s_axi_rid     (im_rid[1])
        ,.s_axi_rdata   (im_rdata[1])
        ,.s_axi_rresp   (im_rresp[1])
        ,.s_axi_rlast   (im_rlast[1])
        ,.s_axi_rvalid  (im_rvalid[1])
        ,.s_axi_rready(im_rready[1]));

    axi_bram_slave #(.BASE_ADDRESS(`ASL_SOC_DTCM_BASE)
        ,.MEMORY_BYTES  (`ASL_SOC_DTCM_BYTES)
        ,.READ_ONLY     (1'b0)
        ,.INIT_FILE     (DTCM_INIT_FILE)
    ) u_dtcm (
         .clk           (clk)
        ,.rst           (rst)
        ,.s_axi_awid    (dm_awid[0])
        ,.s_axi_awaddr  (dm_awaddr[0])
        ,.s_axi_awlen   (dm_awlen[0])
        ,.s_axi_awsize  (dm_awsize[0])
        ,.s_axi_awburst (dm_awburst[0])
        ,.s_axi_awvalid (dm_awvalid[0])
        ,.s_axi_awready (dm_awready[0])
        ,.s_axi_wdata   (dm_wdata[0])
        ,.s_axi_wstrb   (dm_wstrb[0])
        ,.s_axi_wlast   (dm_wlast[0])
        ,.s_axi_wvalid  (dm_wvalid[0])
        ,.s_axi_wready  (dm_wready[0])
        ,.s_axi_bid     (dm_bid[0])
        ,.s_axi_bresp   (dm_bresp[0])
        ,.s_axi_bvalid  (dm_bvalid[0])
        ,.s_axi_bready  (dm_bready[0])
        ,.s_axi_arid    (dm_arid[0])
        ,.s_axi_araddr  (dm_araddr[0])
        ,.s_axi_arlen   (dm_arlen[0])
        ,.s_axi_arsize  (dm_arsize[0])
        ,.s_axi_arburst (dm_arburst[0])
        ,.s_axi_arvalid (dm_arvalid[0])
        ,.s_axi_arready (dm_arready[0])
        ,.s_axi_rid     (dm_rid[0])
        ,.s_axi_rdata   (dm_rdata[0])
        ,.s_axi_rresp   (dm_rresp[0])
        ,.s_axi_rlast   (dm_rlast[0])
        ,.s_axi_rvalid  (dm_rvalid[0])
        ,.s_axi_rready(dm_rready[0]));

    // Decoder target 1 is deliberately absent on the data side.
    assign dm_awready[1] = 1'b0;
    assign dm_wready[1]  = 1'b0;
    assign dm_bid[1]     =  '0;
    assign dm_bresp[1]   = 2'b10;
    assign dm_bvalid[1]  = 1'b0;
    assign dm_arready[1] = 1'b0;
    assign dm_rid[1]     =  '0;
    assign dm_rdata[1]   =  '0;
    assign dm_rresp[1]   = 2'b10;
    assign dm_rlast[1]   = 1'b1;
    assign dm_rvalid[1]  = 1'b0;

    // Default instruction target -> external AXI master.
    assign i_axi_arid    = im_arid[2];
    assign i_axi_araddr  = im_araddr[2];
    assign i_axi_arlen   = im_arlen[2];
    assign i_axi_arsize  = im_arsize[2];
    assign i_axi_arburst = im_arburst[2];
    assign i_axi_arvalid = im_arvalid[2];
    assign im_arready[2] = i_axi_arready;
    assign im_rid[2]     = i_axi_rid;
    assign im_rdata[2]   = i_axi_rdata;
    assign im_rresp[2]   = i_axi_rresp;
    assign im_rlast[2]   = i_axi_rlast;
    assign im_rvalid[2]  = i_axi_rvalid;
    assign i_axi_rready  = im_rready[2];
    assign im_awready[2] = 1'b0;
    assign im_wready[2]  = 1'b0;
    assign im_bid[2]     = '0;
    assign im_bresp[2]   = 2'b10;
    assign im_bvalid[2]  = 1'b0;

    // Default data target -> external AXI master.
    assign d_axi_awid    = dm_awid[2];
    assign d_axi_awaddr  = dm_awaddr[2];
    assign d_axi_awlen   = dm_awlen[2];
    assign d_axi_awsize  = dm_awsize[2];
    assign d_axi_awburst = dm_awburst[2];
    assign d_axi_awvalid = dm_awvalid[2];
    assign dm_awready[2] = d_axi_awready;
    assign d_axi_wdata   = dm_wdata[2];
    assign d_axi_wstrb   = dm_wstrb[2];
    assign d_axi_wlast   = dm_wlast[2];
    assign d_axi_wvalid  = dm_wvalid[2];
    assign dm_wready[2]  = d_axi_wready;
    assign dm_bid[2]     = d_axi_bid;
    assign dm_bresp[2]   = d_axi_bresp;
    assign dm_bvalid[2]  = d_axi_bvalid;
    assign d_axi_bready  = dm_bready[2];
    assign d_axi_arid    = dm_arid[2];
    assign d_axi_araddr  = dm_araddr[2];
    assign d_axi_arlen   = dm_arlen[2];
    assign d_axi_arsize  = dm_arsize[2];
    assign d_axi_arburst = dm_arburst[2];
    assign d_axi_arvalid = dm_arvalid[2];
    assign dm_arready[2] = d_axi_arready;
    assign dm_rid[2]     = d_axi_rid;
    assign dm_rdata[2]   = d_axi_rdata;
    assign dm_rresp[2]   = d_axi_rresp;
    assign dm_rlast[2]   = d_axi_rlast;
    assign dm_rvalid[2]  = d_axi_rvalid;
    assign d_axi_rready  = dm_rready[2];
endmodule
