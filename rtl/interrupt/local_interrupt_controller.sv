module local_interrupt_controller #(
     parameter int unsigned NUM_SOURCES = 8
    ,parameter logic [NUM_SOURCES-1:0] RESET_ENABLE = '0
    ,parameter logic [NUM_SOURCES-1:0] RESET_EDGE = '1
    ,parameter logic [2:0] RESET_PRIORITY = 3'd1
    ,parameter logic [2:0] RESET_THRESHOLD = 3'd0
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        mmio_valid
    ,output logic        mmio_ready
    ,input  logic        mmio_write
    ,input  logic [31:0] mmio_addr
    ,input  logic [31:0] mmio_wdata
    ,input  logic [3:0]  mmio_wstrb
    ,output logic [31:0] mmio_rdata
    ,output logic        external_interrupt
    ,input  logic [NUM_SOURCES-1:0] irq_sources
    ,output logic [$clog2(NUM_SOURCES+1)-1:0] active_source
);
    localparam int unsigned SOURCE_ID_WIDTH = $clog2(NUM_SOURCES + 1);
    localparam int unsigned PRIORITY_INDEX_WIDTH =
        NUM_SOURCES <= 1 ? 1 : $clog2(NUM_SOURCES);
    localparam logic [7:0] REG_ID = 8'h00;
    localparam logic [7:0] REG_INFO = 8'h04;
    localparam logic [7:0] REG_PENDING = 8'h08;
    localparam logic [7:0] REG_ENABLE = 8'h0c;
    localparam logic [7:0] REG_EDGE = 8'h10;
    localparam logic [7:0] REG_RAW = 8'h14;
    localparam logic [7:0] REG_THRESHOLD = 8'h18;
    localparam logic [7:0] REG_CLAIM = 8'h1c;
    localparam logic [7:0] REG_PRIORITY_BASE = 8'h20;
    localparam logic [7:0] REG_PENDING_SET = 8'h40;
    localparam logic [7:0] REG_PENDING_CLEAR = 8'h44;
    localparam logic [7:0] REG_IN_SERVICE = 8'h48;

    logic [NUM_SOURCES-1:0]          pending_q;
    logic [NUM_SOURCES-1:0]          enable_q;
    logic [NUM_SOURCES-1:0]          edge_q;
    logic [NUM_SOURCES-1:0]          in_service_q;
    logic [NUM_SOURCES-1:0]          irq_sources_q;
    logic [2:0]                      priority_q [0:NUM_SOURCES-1];
    logic [2:0]                      threshold_q;
    logic [2:0]                      best_priority;
    logic [SOURCE_ID_WIDTH-1:0]      best_source;
    logic [SOURCE_ID_WIDTH-1:0]      completion_id;
    logic [NUM_SOURCES-1:0]          irq_rise;
    logic [NUM_SOURCES-1:0]          irq_events;
    logic [31:0]                     write_word;
    logic [7:0]                      offset;
    logic [PRIORITY_INDEX_WIDTH-1:0] priority_index;
    integer                          index;

    function automatic logic [31:0] merge_wstrb(
         input logic [31:0] old_value, input logic [31:0] new_value
        ,input logic [3:0] strobe);
        integer lane;
        begin
            merge_wstrb = old_value;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (strobe[lane])
                    merge_wstrb[lane*8 +: 8] = new_value[lane*8 +: 8];
        end
    endfunction

    assign offset = mmio_addr[7:0];
    assign priority_index = PRIORITY_INDEX_WIDTH'(
        (32'(offset) - 32'(REG_PRIORITY_BASE)) >> 2);
    assign mmio_ready = 1'b1;
    assign irq_rise = irq_sources & ~irq_sources_q;
    assign irq_events = ((irq_sources & ~edge_q) | (irq_rise & edge_q)) &
                        ~in_service_q;
    assign active_source = best_source;
    assign external_interrupt = best_source != 0;

    always_comb begin
        best_source = '0;
        best_priority = threshold_q;
        for (index = 0; index < NUM_SOURCES; index = index + 1)
            if (pending_q[index] && enable_q[index] &&
                !in_service_q[index] && priority_q[index] > best_priority) begin
                best_source = SOURCE_ID_WIDTH'(index + 1);
                best_priority = priority_q[index];
            end
    end

    always_comb begin
        mmio_rdata = 32'd0;
        case (offset)
            REG_ID: mmio_rdata = 32'h4c49_4330;
            REG_INFO: mmio_rdata = {16'd0, 8'd3, 8'(NUM_SOURCES)};
            REG_PENDING: mmio_rdata[NUM_SOURCES-1:0] = pending_q;
            REG_ENABLE: mmio_rdata[NUM_SOURCES-1:0] = enable_q;
            REG_EDGE: mmio_rdata[NUM_SOURCES-1:0] = edge_q;
            REG_RAW: mmio_rdata[NUM_SOURCES-1:0] = irq_sources;
            REG_THRESHOLD: mmio_rdata = {29'd0, threshold_q};
            REG_CLAIM: mmio_rdata[SOURCE_ID_WIDTH-1:0] = best_source;
            REG_IN_SERVICE: mmio_rdata[NUM_SOURCES-1:0] = in_service_q;
            default: if (offset >= REG_PRIORITY_BASE &&
                         32'(offset) < 32'(REG_PRIORITY_BASE) + NUM_SOURCES*4 &&
                         offset[1:0] == 0)
                mmio_rdata = {29'd0,
                    priority_q[priority_index]};
        endcase
    end

    always_comb begin
        case (offset)
            REG_ENABLE: write_word = merge_wstrb(
                {{(32-NUM_SOURCES){1'b0}}, enable_q}, mmio_wdata, mmio_wstrb);
            REG_EDGE: write_word = merge_wstrb(
                {{(32-NUM_SOURCES){1'b0}}, edge_q}, mmio_wdata, mmio_wstrb);
            REG_THRESHOLD: write_word = merge_wstrb(
                {29'd0, threshold_q}, mmio_wdata, mmio_wstrb);
            default: write_word = merge_wstrb(32'd0, mmio_wdata, mmio_wstrb);
        endcase
        completion_id = write_word[SOURCE_ID_WIDTH-1:0];
    end

    integer reset_index;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pending_q <= '0; enable_q <= RESET_ENABLE; edge_q <= RESET_EDGE;
            in_service_q <= '0; irq_sources_q <= '0;
            threshold_q <= RESET_THRESHOLD;
            for (reset_index = 0; reset_index < NUM_SOURCES;
                 reset_index = reset_index + 1)
                priority_q[reset_index] <= RESET_PRIORITY;
        end else begin
            irq_sources_q <= irq_sources;
            pending_q <= pending_q | irq_events;
            if (mmio_valid && !mmio_write && offset == REG_CLAIM &&
                best_source != 0) begin
                pending_q[best_source-1] <= 1'b0;
                in_service_q[best_source-1] <= 1'b1;
            end
            if (mmio_valid && mmio_write) begin
                case (offset)
                    REG_ENABLE: enable_q <= write_word[NUM_SOURCES-1:0];
                    REG_EDGE: edge_q <= write_word[NUM_SOURCES-1:0];
                    REG_THRESHOLD: threshold_q <= write_word[2:0];
                    REG_CLAIM: if (completion_id > 0 &&
                                   32'(completion_id) <= NUM_SOURCES)
                        in_service_q[completion_id-1] <= 1'b0;
                    REG_PENDING_SET: pending_q <= (pending_q | irq_events) |
                                                     write_word[NUM_SOURCES-1:0];
                    REG_PENDING_CLEAR: pending_q <= (pending_q | irq_events) &
                                                       ~write_word[NUM_SOURCES-1:0];
                    default: if (offset >= REG_PRIORITY_BASE &&
                                 32'(offset) < 32'(REG_PRIORITY_BASE) + NUM_SOURCES*4 &&
                                 offset[1:0] == 0)
                        priority_q[priority_index] <= write_word[2:0];
                endcase
            end
        end
    end
endmodule
