// Two fixed-function DMA channels share one AXI4 master interface.
// Channel 0 is Ethernet stream-to-memory; channel 1 is CNN memory-to-engine.
// Read and write channels are independent, so both directions may progress at
// the same time without a second arbitration layer.
module axi_multichannel_burst_dma #(
     parameter logic [31:0] FRAME_BUFFER_BASE = 32'h2000_0000
    ,parameter int unsigned MAX_FRAME_BYTES   = 25_600
    ,parameter int unsigned MAX_INPUT_BYTES   = 25_600
    ,parameter int unsigned MAX_BURST_BEATS   = 16
    ,parameter logic [3:0]  S2MM_AXI_ID       = 4'd2
    ,parameter logic [3:0]  MM2S_AXI_ID       = 4'd3
) (
     input  logic        clk
    ,input  logic        rst

    // Channel 0: Ethernet stream-to-memory.
    ,input  logic        s2mm_valid
    ,input  logic [31:0] s2mm_data
    ,input  logic [3:0]  s2mm_keep
    ,input  logic        s2mm_last
    ,output logic        s2mm_ready
    ,output logic        s2mm_frame_done
    ,output logic        s2mm_frame_error
    ,output logic [31:0] s2mm_frame_bytes
    ,output logic [31:0] s2mm_frame_checksum
    ,output logic [31:0] s2mm_frame_sequence
    ,input  logic        s2mm_hold_after_frame
    ,input  logic        s2mm_frame_release
    ,output logic        s2mm_frame_buffer_held

    // Channel 1: memory-to-CNN input engine.
    ,input  logic        mm2s_start
    ,input  logic [31:0] mm2s_address
    ,input  logic [31:0] mm2s_bytes
    ,output logic        mm2s_busy
    ,output logic        mm2s_done
    ,output logic        mm2s_error
    ,output logic [31:0] mm2s_checksum
    ,output logic [31:0] mm2s_bytes_read
    ,output logic        mm2s_valid
    ,input  logic        mm2s_ready
    ,output logic [31:0] mm2s_data
    ,output logic [3:0]  mm2s_keep
    ,output logic        mm2s_last

    // Shared AXI4 memory master.
    ,output logic [3:0]  m_axi_awid
    ,output logic [31:0] m_axi_awaddr
    ,output logic [7:0]  m_axi_awlen
    ,output logic [2:0]  m_axi_awsize
    ,output logic [1:0]  m_axi_awburst
    ,output logic        m_axi_awvalid
    ,input  logic        m_axi_awready
    ,output logic [31:0] m_axi_wdata
    ,output logic [3:0]  m_axi_wstrb
    ,output logic        m_axi_wlast
    ,output logic        m_axi_wvalid
    ,input  logic        m_axi_wready
    ,input  logic [3:0]  m_axi_bid
    ,input  logic [1:0]  m_axi_bresp
    ,input  logic        m_axi_bvalid
    ,output logic        m_axi_bready
    ,output logic [3:0]  m_axi_arid
    ,output logic [31:0] m_axi_araddr
    ,output logic [7:0]  m_axi_arlen
    ,output logic [2:0]  m_axi_arsize
    ,output logic [1:0]  m_axi_arburst
    ,output logic        m_axi_arvalid
    ,input  logic        m_axi_arready
    ,input  logic [3:0]  m_axi_rid
    ,input  logic [31:0] m_axi_rdata
    ,input  logic [1:0]  m_axi_rresp
    ,input  logic        m_axi_rlast
    ,input  logic        m_axi_rvalid
    ,output logic        m_axi_rready
);

    ethernet_rx_dma_shell #(
         .FRAME_BUFFER_BASE (FRAME_BUFFER_BASE)
        ,.MAX_FRAME_BYTES   (MAX_FRAME_BYTES)
        ,.MAX_BURST_BEATS   (MAX_BURST_BEATS)
        ,.AXI_ID            (S2MM_AXI_ID)
    ) u_s2mm_channel (
         .clk               (clk)
        ,.rst               (rst)
        ,.eth_rx_valid      (s2mm_valid)
        ,.eth_rx_data       (s2mm_data)
        ,.eth_rx_keep       (s2mm_keep)
        ,.eth_rx_last       (s2mm_last)
        ,.eth_rx_ready      (s2mm_ready)
        ,.frame_done        (s2mm_frame_done)
        ,.frame_error       (s2mm_frame_error)
        ,.frame_bytes       (s2mm_frame_bytes)
        ,.frame_checksum    (s2mm_frame_checksum)
        ,.frame_sequence    (s2mm_frame_sequence)
        ,.hold_after_frame  (s2mm_hold_after_frame)
        ,.frame_release     (s2mm_frame_release)
        ,.frame_buffer_held (s2mm_frame_buffer_held)
        ,.m_axi_awid        (m_axi_awid)
        ,.m_axi_awaddr      (m_axi_awaddr)
        ,.m_axi_awlen       (m_axi_awlen)
        ,.m_axi_awsize      (m_axi_awsize)
        ,.m_axi_awburst     (m_axi_awburst)
        ,.m_axi_awvalid     (m_axi_awvalid)
        ,.m_axi_awready     (m_axi_awready)
        ,.m_axi_wdata       (m_axi_wdata)
        ,.m_axi_wstrb       (m_axi_wstrb)
        ,.m_axi_wlast       (m_axi_wlast)
        ,.m_axi_wvalid      (m_axi_wvalid)
        ,.m_axi_wready      (m_axi_wready)
        ,.m_axi_bid         (m_axi_bid)
        ,.m_axi_bresp       (m_axi_bresp)
        ,.m_axi_bvalid      (m_axi_bvalid)
        ,.m_axi_bready      (m_axi_bready)
    );

    cnn_input_dma #(
         .MAX_INPUT_BYTES (MAX_INPUT_BYTES)
        ,.MAX_BURST_BEATS (MAX_BURST_BEATS)
        ,.AXI_ID          (MM2S_AXI_ID)
    ) u_mm2s_channel (
         .clk           (clk)
        ,.rst           (rst)
        ,.start         (mm2s_start)
        ,.input_address (mm2s_address)
        ,.input_bytes   (mm2s_bytes)
        ,.busy          (mm2s_busy)
        ,.done          (mm2s_done)
        ,.error         (mm2s_error)
        ,.checksum      (mm2s_checksum)
        ,.bytes_read    (mm2s_bytes_read)
        ,.data_valid    (mm2s_valid)
        ,.data_ready    (mm2s_ready)
        ,.data          (mm2s_data)
        ,.data_keep     (mm2s_keep)
        ,.data_last     (mm2s_last)
        ,.m_axi_arid    (m_axi_arid)
        ,.m_axi_araddr  (m_axi_araddr)
        ,.m_axi_arlen   (m_axi_arlen)
        ,.m_axi_arsize  (m_axi_arsize)
        ,.m_axi_arburst (m_axi_arburst)
        ,.m_axi_arvalid (m_axi_arvalid)
        ,.m_axi_arready (m_axi_arready)
        ,.m_axi_rid     (m_axi_rid)
        ,.m_axi_rdata   (m_axi_rdata)
        ,.m_axi_rresp   (m_axi_rresp)
        ,.m_axi_rlast   (m_axi_rlast)
        ,.m_axi_rvalid  (m_axi_rvalid)
        ,.m_axi_rready  (m_axi_rready)
    );

endmodule
