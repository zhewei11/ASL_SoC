module ethernet_rx_dma_shell #(
     parameter logic [31:0] FRAME_BUFFER_BASE = 32'h2000_0000
    ,parameter int unsigned MAX_FRAME_BYTES   = 25_600
    ,parameter int unsigned MAX_BURST_BEATS   = 16
    ,parameter logic [3:0]  AXI_ID            = 4'd2
) (
     input  logic        clk
    ,input  logic        rst

    ,input  logic        eth_rx_valid
    ,input  logic [31:0] eth_rx_data
    ,input  logic [3:0]  eth_rx_keep
    ,input  logic        eth_rx_last
    ,output logic        eth_rx_ready

    ,output logic        frame_done
    ,output logic        frame_error
    ,output logic [31:0] frame_bytes
    ,output logic [31:0] frame_checksum
    ,output logic [31:0] frame_sequence
    ,input  logic        hold_after_frame
    ,input  logic        frame_release
    ,output logic        frame_buffer_held

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
);

    localparam int unsigned COUNT_WIDTH =
        (MAX_BURST_BEATS <= 1) ? 1 : $clog2(MAX_BURST_BEATS + 1);

    localparam int unsigned INDEX_WIDTH =
        (MAX_BURST_BEATS <= 1) ? 1 : $clog2(MAX_BURST_BEATS);

    typedef enum logic [2:0] {
        RX_COLLECT,
        AXI_AW,
        AXI_W,
        AXI_B,
        RX_DROP
    } state_t;

    state_t state;

    logic [31:0] burst_data [0:MAX_BURST_BEATS-1];
    logic [3:0]  burst_keep [0:MAX_BURST_BEATS-1];

    logic [COUNT_WIDTH-1:0] buffered_beats;
    logic [COUNT_WIDTH-1:0] active_burst_beats;
    logic [INDEX_WIDTH-1:0] write_beat_index;

    logic [31:0]            write_offset;
    logic [31:0]            current_write_address;
    logic [10:0]            words_until_4k;
    logic [COUNT_WIDTH-1:0] collect_limit;

    logic burst_contains_last;
    logic drop_after_burst;
    logic finish_bad_after_burst;
    logic current_frame_bad;

    logic [2:0]  incoming_byte_count;
    logic [31:0] incoming_masked_data;
    logic        first_frame_beat;
    logic [31:0] accepted_frame_bytes;
    logic        incoming_invalid;

    function automatic logic [2:0] keep_count(input logic [3:0] keep);
        keep_count = {2'd0, keep[0]} + {2'd0, keep[1]} +
                     {2'd0, keep[2]} + {2'd0, keep[3]};
    endfunction

    function automatic logic [31:0] masked_data(
         input logic [31:0] data
        ,input logic [3:0]  keep
    );
        masked_data = {
            keep[3] ? data[31:24] : 8'd0,
            keep[2] ? data[23:16] : 8'd0,
            keep[1] ? data[15:8]  : 8'd0,
            keep[0] ? data[7:0]   : 8'd0
        };
    endfunction

    initial begin
        if (MAX_FRAME_BYTES == 0)
            $error("MAX_FRAME_BYTES must be non-zero");
        if ((MAX_BURST_BEATS == 0) || (MAX_BURST_BEATS > 256))
            $error("MAX_BURST_BEATS must be in the range 1..256");
        if (FRAME_BUFFER_BASE[1:0] != 2'b00)
            $error("FRAME_BUFFER_BASE must be word aligned");
    end

    assign current_write_address = FRAME_BUFFER_BASE + write_offset;
    assign words_until_4k = 11'((32'd4096 -
        {20'd0, current_write_address[11:0]}) >> 2);

    always_comb begin
        collect_limit = COUNT_WIDTH'(MAX_BURST_BEATS);
        if (words_until_4k < 11'(collect_limit))
            collect_limit = COUNT_WIDTH'(words_until_4k);
    end

    assign incoming_byte_count = keep_count(eth_rx_keep);
    assign incoming_masked_data = masked_data(eth_rx_data, eth_rx_keep);
    assign first_frame_beat = (write_offset == 0) && (buffered_beats == 0);
    assign accepted_frame_bytes = first_frame_beat ? 32'd0 : frame_bytes;
    assign incoming_invalid = (incoming_byte_count == 0) ||
        (accepted_frame_bytes + 32'(incoming_byte_count) > MAX_FRAME_BYTES);

    assign eth_rx_ready = !frame_buffer_held &&
                          (state == RX_COLLECT) &&
                          (buffered_beats < collect_limit);

    assign m_axi_awid    = AXI_ID;
    assign m_axi_awaddr  = current_write_address;
    assign m_axi_awlen   = 8'(active_burst_beats - 1'b1);
    assign m_axi_awsize  = 3'd2;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = (state == AXI_AW);

    assign m_axi_wdata = burst_data[write_beat_index];
    assign m_axi_wstrb = burst_keep[write_beat_index];
    assign m_axi_wlast = (write_beat_index + 1'b1 == active_burst_beats);
    assign m_axi_wvalid = (state == AXI_W);
    assign m_axi_bready = (state == AXI_B);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state                  <= RX_COLLECT;
            buffered_beats         <= '0;
            active_burst_beats     <= '0;
            write_beat_index       <= '0;
            write_offset           <= 32'd0;
            burst_contains_last    <= 1'b0;
            drop_after_burst       <= 1'b0;
            finish_bad_after_burst <= 1'b0;
            current_frame_bad      <= 1'b0;
            frame_done             <= 1'b0;
            frame_error            <= 1'b0;
            frame_bytes            <= 32'd0;
            frame_checksum         <= 32'd0;
            frame_sequence         <= 32'd0;
            frame_buffer_held      <= 1'b0;
        end else begin
            frame_done  <= 1'b0;
            frame_error <= 1'b0;

            if (frame_release)
                frame_buffer_held <= 1'b0;

            case (state)
                RX_COLLECT: begin
                    if (eth_rx_valid && eth_rx_ready) begin
                        if (incoming_invalid) begin
                            current_frame_bad <= 1'b1;

                            if (buffered_beats != 0) begin
                                active_burst_beats <= buffered_beats;
                                burst_contains_last <= 1'b0;
                                drop_after_burst <= !eth_rx_last;
                                finish_bad_after_burst <= eth_rx_last;
                                write_beat_index <= '0;
                                state <= AXI_AW;
                            end else if (eth_rx_last) begin
                                frame_done <= 1'b1;
                                frame_error <= 1'b1;
                                frame_sequence <= frame_sequence + 1'b1;
                                write_offset <= 32'd0;
                                current_frame_bad <= 1'b0;
                            end else begin
                                state <= RX_DROP;
                            end
                        end else begin
                            burst_data[INDEX_WIDTH'(buffered_beats)] <=
                                eth_rx_data;
                            burst_keep[INDEX_WIDTH'(buffered_beats)] <=
                                eth_rx_keep;

                            if (first_frame_beat) begin
                                frame_bytes <= 32'(incoming_byte_count);
                                frame_checksum <= incoming_masked_data;
                            end else begin
                                frame_bytes <= frame_bytes +
                                               32'(incoming_byte_count);
                                frame_checksum <= frame_checksum ^
                                                  incoming_masked_data;
                            end

                            if (eth_rx_last ||
                                (buffered_beats + 1'b1 == collect_limit)) begin
                                active_burst_beats <= buffered_beats + 1'b1;
                                burst_contains_last <= eth_rx_last;
                                drop_after_burst <= 1'b0;
                                finish_bad_after_burst <= 1'b0;
                                write_beat_index <= '0;
                                state <= AXI_AW;
                            end else begin
                                buffered_beats <= buffered_beats + 1'b1;
                            end
                        end
                    end
                end

                AXI_AW: begin
                    if (m_axi_awready) begin
                        write_beat_index <= '0;
                        state <= AXI_W;
                    end
                end

                AXI_W: begin
                    if (m_axi_wready) begin
                        if (m_axi_wlast)
                            state <= AXI_B;
                        else
                            write_beat_index <= write_beat_index + 1'b1;
                    end
                end

                AXI_B: begin
                    if (m_axi_bvalid) begin
                        if ((m_axi_bresp != 2'b00) || (m_axi_bid != AXI_ID))
                            current_frame_bad <= 1'b1;

                        buffered_beats <= '0;

                        if (burst_contains_last || finish_bad_after_burst) begin
                            frame_done <= 1'b1;
                            frame_error <= current_frame_bad ||
                                           finish_bad_after_burst ||
                                           (m_axi_bresp != 2'b00) ||
                                           (m_axi_bid != AXI_ID);
                            frame_sequence <= frame_sequence + 1'b1;
                            write_offset <= 32'd0;
                            current_frame_bad <= 1'b0;

                            if (hold_after_frame && burst_contains_last &&
                                !current_frame_bad &&
                                (m_axi_bresp == 2'b00) &&
                                (m_axi_bid == AXI_ID))
                                frame_buffer_held <= 1'b1;

                            state <= RX_COLLECT;
                        end else if (drop_after_burst) begin
                            write_offset <= 32'd0;
                            state <= RX_DROP;
                        end else begin
                            write_offset <= write_offset +
                                (32'(active_burst_beats) << 2);
                            state <= RX_COLLECT;
                        end
                    end
                end

                RX_DROP: begin
                    if (eth_rx_valid && eth_rx_last) begin
                        frame_done <= 1'b1;
                        frame_error <= 1'b1;
                        frame_sequence <= frame_sequence + 1'b1;
                        write_offset <= 32'd0;
                        current_frame_bad <= 1'b0;
                        state <= RX_COLLECT;
                    end
                end

                default: begin
                    current_frame_bad <= 1'b1;
                    state <= RX_DROP;
                end
            endcase
        end
    end

endmodule
