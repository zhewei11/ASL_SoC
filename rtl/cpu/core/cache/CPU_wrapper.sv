`include "rtos_core_config.svh"

module CPU_wrapper #(
     parameter logic [31:0] MMIO_BASE = `RTOS_CORE_LOCAL_MMIO_BASE
    ,parameter logic [31:0] MMIO_MASK = `RTOS_CORE_LOCAL_MMIO_MASK
    ,parameter bit ENABLE_FPU = 1'b1
    ,parameter bit EXTERNAL_MMIO_ONLY = 1'b0
) (
     input  logic        ACLK
    ,input  logic        rst
    ,input  logic        interrupt
    ,input  logic        protocol_interrupt
    ,input  logic        WTO
    ,input  logic [3:0]  platform_interrupts
    ,input  logic        external_timer_interrupt
    ,input  logic [63:0] external_mtime_value

    // Generic DSP/AI coprocessor command/response interface.
    ,output logic        cp_cmd_valid
    ,input  logic        cp_cmd_ready
    ,output logic [7:0]  cp_cmd_opcode
    ,output logic [7:0]  cp_cmd_flags
    ,output logic [7:0]  cp_cmd_tag
    ,output logic [31:0] cp_cmd_arg0
    ,output logic [31:0] cp_cmd_arg1
    ,output logic [31:0] cp_cmd_arg2
    ,output logic [31:0] cp_cmd_arg3
    ,input  logic        cp_rsp_valid
    ,output logic        cp_rsp_ready
    ,input  logic [7:0]  cp_rsp_status
    ,input  logic [7:0]  cp_rsp_tag
    ,input  logic [31:0] cp_rsp_result0
    ,input  logic [31:0] cp_rsp_result1
    ,output logic        cp_abort

    // Uncached local MMIO. The request remains valid until mmio_ready.
    ,output logic        mmio_valid
    ,input  logic        mmio_ready
    ,output logic        mmio_write
    ,output logic [31:0] mmio_addr
    ,output logic [31:0] mmio_wdata
    ,output logic [3:0]  mmio_wstrb
    ,input  logic [31:0] mmio_rdata

    // AXI master 1: data read/write
    ,output logic [3:0]  AWID_M1
    ,output logic [31:0] AWADDR_M1
    ,output logic [3:0]  AWLEN_M1
    ,output logic [2:0]  AWSIZE_M1
    ,output logic [1:0]  AWBURST_M1
    ,output logic        AWVALID_M1
    ,input  logic        AWREADY_M1

    ,output logic [31:0] WDATA_M1
    ,output logic [3:0]  WSTRB_M1
    ,output logic        WLAST_M1
    ,output logic        WVALID_M1
    ,input  logic        WREADY_M1

    ,input  logic [3:0]  BID_M1
    ,input  logic [1:0]  BRESP_M1
    ,input  logic        BVALID_M1
    ,output logic        BREADY_M1

    ,output logic [3:0]  ARID_M1
    ,output logic [31:0] ARADDR_M1
    ,output logic [3:0]  ARLEN_M1
    ,output logic [2:0]  ARSIZE_M1
    ,output logic [1:0]  ARBURST_M1
    ,output logic        ARVALID_M1
    ,input  logic        ARREADY_M1

    ,input  logic [3:0]  RID_M1
    ,input  logic [31:0] RDATA_M1
    ,input  logic [1:0]  RRESP_M1
    ,input  logic        RLAST_M1
    ,input  logic        RVALID_M1
    ,output logic        RREADY_M1

    // AXI master 0: instruction read
    ,output logic [3:0]  ARID_M0
    ,output logic [31:0] ARADDR_M0
    ,output logic [3:0]  ARLEN_M0
    ,output logic [2:0]  ARSIZE_M0
    ,output logic [1:0]  ARBURST_M0
    ,output logic        ARVALID_M0
    ,input  logic        ARREADY_M0

    ,input  logic [3:0]  RID_M0
    ,input  logic [31:0] RDATA_M0
    ,input  logic [1:0]  RRESP_M0
    ,input  logic        RLAST_M0
    ,input  logic        RVALID_M0
    ,output logic        RREADY_M0
);

    logic        im_valid;
    logic [31:0] im_read_data;
    logic        im_stall;
    logic [31:0] im_addr;
    logic        im_flush;
    logic        im_invalidate;
    logic        im_access_allowed;

    logic        dm_valid;
    logic [31:0] dm_read_data;
    logic        dm_req;
    logic        dm_stall;
    logic        dm_WEB;
    logic [31:0] dm_bit_en;
    logic [31:0] dm_addr;
    logic [31:0] dm_write_data;
    logic        dcache_req;
    logic        dcache_valid;
    logic [31:0] dcache_read_data;
    logic [3:0]  dm_write_strb;
    logic        local_mmio_valid;
    logic        local_mmio_ready;
    logic        local_mmio_write;
    logic [31:0] local_mmio_addr;
    logic [31:0] local_mmio_wdata;
    logic [3:0]  local_mmio_wstrb;
    logic [31:0] local_mmio_rdata;
    logic        timer_interrupt;
    logic        external_interrupt;
    logic [63:0] mtime_value;

    logic         i_mem_req;
    logic [31:0]  i_mem_addr;
    logic         i_mem_ready;
    logic         i_line_valid;
    logic [127:0] i_line;

    logic         d_read_req;
    logic [31:0]  d_read_addr;
    logic         d_read_ready;
    logic         d_line_valid;
    logic [127:0] d_line;

    logic        d_write_req;
    logic [31:0] d_write_addr;
    logic [31:0] d_write_data;
    logic [3:0]  d_write_strb;
    logic        d_write_ready;
    logic        d_write_done;

    // =============================================
    // Cache coherence
    // =============================================
    logic dma_interrupt_q;
    logic wdt_interrupt_q;
    logic cache_invalidate;

    // DMA completion and WDT timeout can both make cached contents stale:
    // DMA writes memory behind the caches, while the WDT testbench restores
    // an instruction in SRAM before restarting the program. Convert both
    // interrupt rising edges into one-cycle cache invalidation events.
    always_ff @(posedge ACLK or posedge rst) begin
        if (rst) begin
            dma_interrupt_q <= 1'b0;
            wdt_interrupt_q <= 1'b0;
        end else begin
            dma_interrupt_q <= interrupt;
            wdt_interrupt_q <= WTO;
        end
    end

    assign cache_invalidate = (interrupt && !dma_interrupt_q) ||
                              (WTO && !wdt_interrupt_q);

    function automatic logic [3:0] bweb_to_wstrb(
         input logic [31:0] bweb
    );
        bweb_to_wstrb = {
            ~bweb[24],
            ~bweb[16],
            ~bweb[8],
            ~bweb[0]
        };
    endfunction

    assign dm_write_strb = bweb_to_wstrb(dm_bit_en);

    core #(
         .ENABLE_FPU (ENABLE_FPU)
    ) u_core (
         .clk               (ACLK)
        ,.rst               (rst)
        ,.dma_interrupt     (external_interrupt)
        ,.timer_interrupt   (timer_interrupt)
        ,.wdt_interrupt     (1'b0)
        ,.time_value        (mtime_value)
        ,.im_valid          (im_valid)
        ,.im_read_data      (im_read_data)
        ,.im_stall          (im_stall)
        ,.im_addr           (im_addr)
        ,.im_flush          (im_flush)
        ,.im_invalidate     (im_invalidate)
        ,.im_access_allowed (im_access_allowed)
        ,.dm_valid          (dm_valid)
        ,.dm_read_data      (dm_read_data)
        ,.dm_req            (dm_req)
        ,.dm_stall          (dm_stall)
        ,.dm_WEB            (dm_WEB)
        ,.dm_bit_en         (dm_bit_en)
        ,.dm_addr           (dm_addr)
        ,.dm_write_data     (dm_write_data)
    );

    L1C_inst u_l1c_inst (
         .clk                 (ACLK)
        ,.rst                 (rst)
        ,.invalidate          (cache_invalidate || im_invalidate)
        ,.core_addr           (im_addr)
        ,.core_flush          (im_flush)
        ,.core_stall          (im_stall)
        ,.core_access_allowed (im_access_allowed)
        ,.core_valid          (im_valid)
        ,.core_out            (im_read_data)
        ,.mem_req             (i_mem_req)
        ,.mem_addr            (i_mem_addr)
        ,.mem_ready           (i_mem_ready)
        ,.mem_line_valid      (i_line_valid)
        ,.mem_line            (i_line)
    );

    L1C_data u_l1c_data (
         .clk             (ACLK)
        ,.rst             (rst)
        ,.invalidate      (cache_invalidate)
        ,.core_req        (dcache_req)
        ,.core_write      (!dm_WEB)
        ,.core_addr       (dm_addr)
        ,.core_in         (dm_write_data)
        ,.core_wstrb      (dm_write_strb)
        ,.core_stall      (dm_stall)
        ,.core_valid      (dcache_valid)
        ,.core_out        (dcache_read_data)
        ,.mem_read_req    (d_read_req)
        ,.mem_read_addr   (d_read_addr)
        ,.mem_read_ready  (d_read_ready)
        ,.mem_line_valid  (d_line_valid)
        ,.mem_line        (d_line)
        ,.mem_write_req   (d_write_req)
        ,.mem_write_addr  (d_write_addr)
        ,.mem_write_data  (d_write_data)
        ,.mem_write_strb  (d_write_strb)
        ,.mem_write_ready (d_write_ready)
        ,.mem_write_done  (d_write_done)
    );

    // MMIO reads must bypass the data cache. In particular, status and
    // RX-data registers must never be cached or expanded into a four-beat
    // cache-line refill. Memory accesses continue through L1C_data.
    uncached_mmio_router #(
         .MMIO_BASE (MMIO_BASE)
        ,.MMIO_MASK (MMIO_MASK)
    ) u_uncached_mmio_router (
         .core_req       (dm_req)
        ,.core_write     (!dm_WEB)
        ,.core_word_addr (dm_addr)
        ,.core_wdata     (dm_write_data)
        ,.core_wstrb     (dm_write_strb)
        ,.core_valid     (dm_valid)
        ,.core_rdata     (dm_read_data)
        ,.cache_req      (dcache_req)
        ,.cache_valid    (dcache_valid)
        ,.cache_rdata    (dcache_read_data)
        ,.mmio_valid     (local_mmio_valid)
        ,.mmio_ready     (local_mmio_ready)
        ,.mmio_write     (local_mmio_write)
        ,.mmio_addr      (local_mmio_addr)
        ,.mmio_wdata     (local_mmio_wdata)
        ,.mmio_wstrb     (local_mmio_wstrb)
        ,.mmio_rdata     (local_mmio_rdata)
    );

    generate
        if (!EXTERNAL_MMIO_ONLY) begin : g_legacy_local_mmio
            local_mmio_subsystem #(
                 .PROTOCOL_BASE    (`RTOS_CORE_PROTOCOL2_MMIO_BASE)
                ,.INTERRUPT_BASE   (`RTOS_CORE_INTERRUPT_CONTROLLER_BASE)
                ,.COPROCESSOR_BASE (`RTOS_CORE_COPROCESSOR_MMIO_BASE)
                ,.MTIMECMP_ADDR    (`RTOS_CORE_MTIMECMP_BASE)
                ,.MTIME_ADDR       (`RTOS_CORE_MTIME_BASE)
            ) u_local_mmio_subsystem (
                 .clk                 (ACLK)
                ,.rst                 (rst)
                ,.core_valid          (local_mmio_valid)
                ,.core_ready          (local_mmio_ready)
                ,.core_write          (local_mmio_write)
                ,.core_addr           (local_mmio_addr)
                ,.core_wdata          (local_mmio_wdata)
                ,.core_wstrb          (local_mmio_wstrb)
                ,.core_rdata          (local_mmio_rdata)
                ,.peripheral_valid    (mmio_valid)
                ,.peripheral_ready    (mmio_ready)
                ,.peripheral_write    (mmio_write)
                ,.peripheral_addr     (mmio_addr)
                ,.peripheral_wdata    (mmio_wdata)
                ,.peripheral_wstrb    (mmio_wstrb)
                ,.peripheral_rdata    (mmio_rdata)
                ,.dma_interrupt       (interrupt)
                ,.protocol_interrupt  (protocol_interrupt)
                ,.wdt_interrupt       (WTO)
                ,.platform_interrupts (platform_interrupts)
                ,.external_interrupt  (external_interrupt)
                ,.cp_cmd_valid        (cp_cmd_valid)
                ,.cp_cmd_ready        (cp_cmd_ready)
                ,.cp_cmd_opcode       (cp_cmd_opcode)
                ,.cp_cmd_flags        (cp_cmd_flags)
                ,.cp_cmd_tag          (cp_cmd_tag)
                ,.cp_cmd_arg0         (cp_cmd_arg0)
                ,.cp_cmd_arg1         (cp_cmd_arg1)
                ,.cp_cmd_arg2         (cp_cmd_arg2)
                ,.cp_cmd_arg3         (cp_cmd_arg3)
                ,.cp_rsp_valid        (cp_rsp_valid)
                ,.cp_rsp_ready        (cp_rsp_ready)
                ,.cp_rsp_status       (cp_rsp_status)
                ,.cp_rsp_tag          (cp_rsp_tag)
                ,.cp_rsp_result0      (cp_rsp_result0)
                ,.cp_rsp_result1      (cp_rsp_result1)
                ,.cp_abort            (cp_abort)
                ,.timer_interrupt     (timer_interrupt)
                ,.mtime_value         (mtime_value)
            );
        end else begin : g_external_mmio
            assign local_mmio_ready = mmio_ready;
            assign local_mmio_rdata = mmio_rdata;
            assign mmio_valid       = local_mmio_valid;
            assign mmio_write       = local_mmio_write;
            assign mmio_addr        = local_mmio_addr;
            assign mmio_wdata       = local_mmio_wdata;
            assign mmio_wstrb       = local_mmio_wstrb;
            assign external_interrupt = interrupt || protocol_interrupt ||
                                        (|platform_interrupts);
            assign timer_interrupt = external_timer_interrupt;
            assign mtime_value = external_mtime_value;

            assign cp_cmd_valid  = 1'b0;
            assign cp_cmd_opcode = 8'd0;
            assign cp_cmd_flags  = 8'd0;
            assign cp_cmd_tag    = 8'd0;
            assign cp_cmd_arg0   = 32'd0;
            assign cp_cmd_arg1   = 32'd0;
            assign cp_cmd_arg2   = 32'd0;
            assign cp_cmd_arg3   = 32'd0;
            assign cp_rsp_ready  = 1'b0;
            assign cp_abort      = 1'b0;
        end
    endgenerate

    // =============================================
    // AXI bridge state
    // =============================================
    typedef enum logic [1:0] {
        I_BUS_IDLE,
        I_BUS_ADDRESS,
        I_BUS_DATA
    } i_bus_state_t;

    typedef enum logic [1:0] {
        D_READ_IDLE,
        D_READ_ADDRESS,
        D_READ_DATA
    } d_read_state_t;

    typedef enum logic [2:0] {
        D_WRITE_IDLE,
        D_WRITE_ADDRESS,
        D_WRITE_DATA,
        D_WRITE_RESPONSE
    } d_write_state_t;

    i_bus_state_t i_bus_state;
    d_read_state_t d_read_state;
    d_write_state_t d_write_state;

    logic [1:0]   i_beat_count;
    logic [1:0]   d_beat_count;
    logic [127:0] i_line_q;
    logic [127:0] d_line_q;
    logic [31:0]  d_awaddr_q;
    logic [31:0]  d_wdata_q;
    logic [3:0]   d_wstrb_q;

    assign i_mem_ready = (i_bus_state == I_BUS_IDLE);
    assign d_read_ready = (d_read_state == D_READ_IDLE);
    assign d_write_ready = (d_write_state == D_WRITE_IDLE);
    assign i_line = i_line_q;
    assign d_line = d_line_q;

    always_ff @(posedge ACLK or posedge rst) begin
        if (rst) begin
            i_bus_state  <= I_BUS_IDLE;
            i_beat_count <= 2'd0;
            i_line_q     <= 128'd0;
            i_line_valid <= 1'b0;
        end else begin
            i_line_valid <= 1'b0;

            case (i_bus_state)
                I_BUS_IDLE: begin
                    if (i_mem_req)
                        i_bus_state <= I_BUS_ADDRESS;
                end

                I_BUS_ADDRESS: begin
                    if (ARVALID_M0 && ARREADY_M0) begin
                        i_beat_count <= 2'd0;
                        i_line_q     <= 128'd0;
                        i_bus_state  <= I_BUS_DATA;
                    end
                end

                I_BUS_DATA: begin
                    if (RVALID_M0 && RREADY_M0) begin
                        case (i_beat_count)
                            2'd0: i_line_q[31:0]   <= RDATA_M0;
                            2'd1: i_line_q[63:32]  <= RDATA_M0;
                            2'd2: i_line_q[95:64]  <= RDATA_M0;
                            2'd3: i_line_q[127:96] <= RDATA_M0;
                        endcase

                        if (RLAST_M0 || (i_beat_count == 2'd3)) begin
                            i_line_valid <= 1'b1;
                            i_bus_state  <= I_BUS_IDLE;
                        end else begin
                            i_beat_count <= i_beat_count + 2'd1;
                        end
                    end
                end

                default: i_bus_state <= I_BUS_IDLE;
            endcase
        end
    end

    always_ff @(posedge ACLK or posedge rst) begin
        if (rst) begin
            d_read_state <= D_READ_IDLE;
            d_beat_count <= 2'd0;
            d_line_q     <= 128'd0;
            d_line_valid <= 1'b0;
        end else begin
            d_line_valid <= 1'b0;

            case (d_read_state)
                D_READ_IDLE: begin
                    if (d_read_req)
                        d_read_state <= D_READ_ADDRESS;
                end

                D_READ_ADDRESS: begin
                    if (ARVALID_M1 && ARREADY_M1) begin
                        d_beat_count <= 2'd0;
                        d_line_q     <= 128'd0;
                        d_read_state <= D_READ_DATA;
                    end
                end

                D_READ_DATA: begin
                    if (RVALID_M1 && RREADY_M1) begin
                        case (d_beat_count)
                            2'd0: d_line_q[31:0]   <= RDATA_M1;
                            2'd1: d_line_q[63:32]  <= RDATA_M1;
                            2'd2: d_line_q[95:64]  <= RDATA_M1;
                            2'd3: d_line_q[127:96] <= RDATA_M1;
                        endcase

                        if (RLAST_M1 || (d_beat_count == 2'd3)) begin
                            d_line_valid <= 1'b1;
                            d_read_state <= D_READ_IDLE;
                        end else begin
                            d_beat_count <= d_beat_count + 2'd1;
                        end
                    end
                end

                default: d_read_state <= D_READ_IDLE;
            endcase
        end
    end

    always_ff @(posedge ACLK or posedge rst) begin
        if (rst) begin
            d_write_state <= D_WRITE_IDLE;
            d_awaddr_q     <= 32'd0;
            d_wdata_q      <= 32'd0;
            d_wstrb_q      <= 4'd0;
            d_write_done   <= 1'b0;
        end else begin
            d_write_done <= 1'b0;

            case (d_write_state)
                D_WRITE_IDLE: begin
                    if (d_write_req) begin
                        d_awaddr_q     <= d_write_addr;
                        d_wdata_q      <= d_write_data;
                        d_wstrb_q      <= d_write_strb;
                        d_write_state  <= D_WRITE_ADDRESS;
                    end
                end

                D_WRITE_ADDRESS: begin
                    if (AWVALID_M1 && AWREADY_M1)
                        d_write_state <= D_WRITE_DATA;
                end

                D_WRITE_DATA: begin
                    if (WVALID_M1 && WREADY_M1)
                        d_write_state <= D_WRITE_RESPONSE;
                end

                D_WRITE_RESPONSE: begin
                    if (BVALID_M1 && BREADY_M1) begin
                        d_write_done  <= 1'b1;
                        d_write_state <= D_WRITE_IDLE;
                    end
                end

                default: d_write_state <= D_WRITE_IDLE;
            endcase
        end
    end

    assign ARID_M0    = 4'd0;
    assign ARADDR_M0  = i_mem_addr;
    assign ARLEN_M0   = 4'd3;
    assign ARSIZE_M0  = 3'b010;
    assign ARBURST_M0 = 2'b01;
    assign ARVALID_M0 = (i_bus_state == I_BUS_ADDRESS);
    assign RREADY_M0  = (i_bus_state == I_BUS_DATA);

    assign ARID_M1    = 4'd0;
    assign ARADDR_M1  = d_read_addr;
    assign ARLEN_M1   = 4'd3;
    assign ARSIZE_M1  = 3'b010;
    assign ARBURST_M1 = 2'b01;
    assign ARVALID_M1 = (d_read_state == D_READ_ADDRESS);
    assign RREADY_M1  = (d_read_state == D_READ_DATA);

    assign AWID_M1    = 4'd0;
    assign AWADDR_M1  = d_awaddr_q;
    assign AWLEN_M1   = 4'd0;
    assign AWSIZE_M1  = 3'b010;
    assign AWBURST_M1 = 2'b01;
    assign AWVALID_M1 = (d_write_state == D_WRITE_ADDRESS);

    assign WDATA_M1   = d_wdata_q;
    assign WSTRB_M1   = d_wstrb_q;
    assign WLAST_M1   = 1'b1;
    assign WVALID_M1  = (d_write_state == D_WRITE_DATA);
    assign BREADY_M1  = (d_write_state == D_WRITE_RESPONSE);

    // Response IDs and response codes are checked by the AXI interconnect.
    // They remain ports here so protocol errors are visible in simulation.

endmodule
