`include "asl_soc_config.svh"

// Fabric RV32IMF CPU integration boundary.
//
// All 0x1003_xxxx accesses leave through the uncached MMIO port; the legacy
// rtos_core timer/coprocessor/Protocol decoder and ASIC SRAM wrappers are
// deliberately not part of this subsystem. ENABLE_FPU remains a parameter so
// resource-constrained builds can still elaborate the integer-only variant.
module rv32im_cpu_subsystem #(
     parameter logic [31:0] MMIO_BASE = 32'h1003_0000
    ,parameter logic [31:0] MMIO_MASK = 32'hFFFF_0000
    ,parameter bit ENABLE_FPU = 1'b1
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        dma_irq
    ,input  logic        protocol_irq
    ,input  logic        watchdog_irq
    ,input  logic [3:0]  platform_irqs
    ,input  logic        timer_irq
    ,input  logic [63:0] mtime_value

    ,output logic        mmio_valid
    ,input  logic        mmio_ready
    ,output logic        mmio_write
    ,output logic [31:0] mmio_addr
    ,output logic [31:0] mmio_wdata
    ,output logic [3:0]  mmio_wstrb
    ,input  logic [31:0] mmio_rdata

    // Instruction AXI read master.
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

    // Data AXI read/write master.
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
    logic [3:0] i_arlen_narrow;
    logic [3:0] d_awlen_narrow;
    logic [3:0] d_arlen_narrow;

    logic        unused_cp_cmd_valid;
    logic [7:0]  unused_cp_cmd_opcode;
    logic [7:0]  unused_cp_cmd_flags;
    logic [7:0]  unused_cp_cmd_tag;
    logic [31:0] unused_cp_cmd_arg0;
    logic [31:0] unused_cp_cmd_arg1;
    logic [31:0] unused_cp_cmd_arg2;
    logic [31:0] unused_cp_cmd_arg3;
    logic        unused_cp_rsp_ready;
    logic        unused_cp_abort;

    assign i_axi_arlen = {4'd0, i_arlen_narrow};
    assign d_axi_awlen = {4'd0, d_awlen_narrow};
    assign d_axi_arlen = {4'd0, d_arlen_narrow};

    CPU_wrapper #(
         .MMIO_BASE          (MMIO_BASE)
        ,.MMIO_MASK          (MMIO_MASK)
        ,.ENABLE_FPU         (ENABLE_FPU)
        ,.EXTERNAL_MMIO_ONLY (1'b1)
    ) u_cpu_wrapper (
         .ACLK                     (clk)
        ,.rst                      (rst)
        // Interrupts
        ,.interrupt                (dma_irq)
        ,.protocol_interrupt       (protocol_irq)
        ,.WTO                      (watchdog_irq)
        ,.platform_interrupts      (platform_irqs)
        ,.external_timer_interrupt (timer_irq)
        ,.external_mtime_value     (mtime_value)
        // Coprocessor interface (unused)
        ,.cp_cmd_valid             (unused_cp_cmd_valid)
        ,.cp_cmd_ready             (1'b0)
        ,.cp_cmd_opcode            (unused_cp_cmd_opcode)
        ,.cp_cmd_flags             (unused_cp_cmd_flags)
        ,.cp_cmd_tag               (unused_cp_cmd_tag)
        ,.cp_cmd_arg0              (unused_cp_cmd_arg0)
        ,.cp_cmd_arg1              (unused_cp_cmd_arg1)
        ,.cp_cmd_arg2              (unused_cp_cmd_arg2)
        ,.cp_cmd_arg3              (unused_cp_cmd_arg3)
        ,.cp_rsp_valid             (1'b0)
        ,.cp_rsp_ready             (unused_cp_rsp_ready)
        ,.cp_rsp_status            (8'd0)
        ,.cp_rsp_tag               (8'd0)
        ,.cp_rsp_result0           (32'd0)
        ,.cp_rsp_result1           (32'd0)
        ,.cp_abort                 (unused_cp_abort)
        // AXI4-Lite MMIO interface
        ,.mmio_valid               (mmio_valid)
        ,.mmio_ready               (mmio_ready)
        ,.mmio_write               (mmio_write)
        ,.mmio_addr                (mmio_addr)
        ,.mmio_wdata               (mmio_wdata)
        ,.mmio_wstrb               (mmio_wstrb)
        ,.mmio_rdata               (mmio_rdata)
        // Write Address Channel
        ,.AWID_M1                  (d_axi_awid)
        ,.AWADDR_M1                (d_axi_awaddr)
        ,.AWLEN_M1                 (d_awlen_narrow)
        ,.AWSIZE_M1                (d_axi_awsize)
        ,.AWBURST_M1               (d_axi_awburst)
        ,.AWVALID_M1               (d_axi_awvalid)
        ,.AWREADY_M1               (d_axi_awready)
        // Write Data Channel
        ,.WDATA_M1                 (d_axi_wdata)
        ,.WSTRB_M1                 (d_axi_wstrb)
        ,.WLAST_M1                 (d_axi_wlast)
        ,.WVALID_M1                (d_axi_wvalid)
        ,.WREADY_M1                (d_axi_wready)
        // Write Response Channel
        ,.BID_M1                   (d_axi_bid)
        ,.BRESP_M1                 (d_axi_bresp)
        ,.BVALID_M1                (d_axi_bvalid)
        ,.BREADY_M1                (d_axi_bready)
        // Read Address Channel
        ,.ARID_M1                  (d_axi_arid)
        ,.ARADDR_M1                (d_axi_araddr)
        ,.ARLEN_M1                 (d_arlen_narrow)
        ,.ARSIZE_M1                (d_axi_arsize)
        ,.ARBURST_M1               (d_axi_arburst)
        ,.ARVALID_M1               (d_axi_arvalid)
        ,.ARREADY_M1               (d_axi_arready)
        // Read Data Channel
        ,.RID_M1                   (d_axi_rid)
        ,.RDATA_M1                 (d_axi_rdata)
        ,.RRESP_M1                 (d_axi_rresp)
        ,.RLAST_M1                 (d_axi_rlast)
        ,.RVALID_M1                (d_axi_rvalid)
        ,.RREADY_M1                (d_axi_rready)
        // Instruction Read Address Channel
        ,.ARID_M0                  (i_axi_arid)
        ,.ARADDR_M0                (i_axi_araddr)
        ,.ARLEN_M0                 (i_arlen_narrow)
        ,.ARSIZE_M0                (i_axi_arsize)
        ,.ARBURST_M0               (i_axi_arburst)
        ,.ARVALID_M0               (i_axi_arvalid)
        ,.ARREADY_M0               (i_axi_arready)
        // Instruction Read Data Channel
        ,.RID_M0                   (i_axi_rid)
        ,.RDATA_M0                 (i_axi_rdata)
        ,.RRESP_M0                 (i_axi_rresp)
        ,.RLAST_M0                 (i_axi_rlast)
        ,.RVALID_M0                (i_axi_rvalid)
        ,.RREADY_M0                (i_axi_rready)
    );
endmodule
