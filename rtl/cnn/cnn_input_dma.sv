module cnn_input_dma #(
     parameter int unsigned MAX_INPUT_BYTES  = 25_600
    ,parameter int unsigned MAX_BURST_BEATS  = 16
    ,parameter logic [3:0]  AXI_ID           = 4'd3
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        start
    ,input  logic [31:0] input_address
    ,input  logic [31:0] input_bytes

    ,output logic        busy
    ,output logic        done
    ,output logic        error
    ,output logic [31:0] checksum
    ,output logic [31:0] bytes_read

    ,output logic        data_valid
    ,input  logic        data_ready
    ,output logic [31:0] data
    ,output logic [3:0]  data_keep
    ,output logic        data_last

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

    typedef enum logic [1:0] {
        DMA_IDLE,
        DMA_AR,
        DMA_R
    } state_t;

    state_t state;

    logic [31:0] base_address;
    logic [31:0] transfer_bytes;
    logic [31:0] read_offset;
    logic [31:0] remaining_bytes;
    logic [31:0] remaining_words;
    logic [10:0] words_until_4k;

    logic [8:0] planned_burst_beats;
    logic [8:0] active_burst_beats;
    logic [8:0] beat_index;
    logic       expected_last;

    logic [31:0] current_read_address;
    logic [31:0] beat_byte_offset;
    logic [31:0] beat_remaining_bytes;
    logic [31:0] masked_read_data;

    initial begin
        if (MAX_INPUT_BYTES == 0)
            $error("MAX_INPUT_BYTES must be non-zero");
        if ((MAX_BURST_BEATS == 0) || (MAX_BURST_BEATS > 256))
            $error("MAX_BURST_BEATS must be in the range 1..256");
    end

    assign current_read_address = base_address + read_offset;
    assign remaining_bytes = transfer_bytes - read_offset;
    assign remaining_words = (remaining_bytes + 32'd3) >> 2;
    assign words_until_4k = 11'((32'd4096 -
        {20'd0, current_read_address[11:0]}) >> 2);

    always_comb begin
        planned_burst_beats = 9'(MAX_BURST_BEATS);
        if (remaining_words < planned_burst_beats)
            planned_burst_beats = 9'(remaining_words);
        if (words_until_4k < 11'(planned_burst_beats))
            planned_burst_beats = 9'(words_until_4k);
    end

    assign beat_byte_offset = read_offset + ({23'd0, beat_index} << 2);
    assign beat_remaining_bytes = transfer_bytes - beat_byte_offset;

    always_comb begin
        case (beat_remaining_bytes)
            32'd1: masked_read_data = {24'd0, m_axi_rdata[7:0]};
            32'd2: masked_read_data = {16'd0, m_axi_rdata[15:0]};
            32'd3: masked_read_data = {8'd0, m_axi_rdata[23:0]};
            default: masked_read_data = m_axi_rdata;
        endcase
    end

    assign expected_last = (beat_index + 1'b1 == active_burst_beats);

    assign data_valid = (state == DMA_R) && m_axi_rvalid;
    assign data = m_axi_rdata;
    assign data_last = data_valid &&
                       (beat_byte_offset + 32'd4 >= transfer_bytes);

    always_comb begin
        case (beat_remaining_bytes)
            32'd1: data_keep = 4'b0001;
            32'd2: data_keep = 4'b0011;
            32'd3: data_keep = 4'b0111;
            default: data_keep = 4'b1111;
        endcase
    end

    assign m_axi_arid    = AXI_ID;
    assign m_axi_araddr  = current_read_address;
    assign m_axi_arlen   = 8'(planned_burst_beats - 1'b1);
    assign m_axi_arsize  = 3'd2;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (state == DMA_AR);
    assign m_axi_rready  = (state == DMA_R) && data_ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state              <= DMA_IDLE;
            base_address       <= 32'd0;
            transfer_bytes     <= 32'd0;
            read_offset        <= 32'd0;
            active_burst_beats <= 9'd0;
            beat_index         <= 9'd0;
            busy               <= 1'b0;
            done               <= 1'b0;
            error              <= 1'b0;
            checksum           <= 32'd0;
            bytes_read         <= 32'd0;
        end else begin
            done <= 1'b0;

            case (state)
                DMA_IDLE: begin
                    if (start) begin
                        error       <= 1'b0;
                        checksum    <= 32'd0;
                        bytes_read  <= 32'd0;
                        read_offset <= 32'd0;
                        beat_index  <= 9'd0;

                        if ((input_bytes == 0) ||
                            (input_address[1:0] != 2'b00) ||
                            (input_bytes > MAX_INPUT_BYTES)) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            busy  <= 1'b0;
                        end else begin
                            base_address   <= input_address;
                            transfer_bytes <= input_bytes;
                            busy           <= 1'b1;
                            state          <= DMA_AR;
                        end
                    end
                end

                DMA_AR: begin
                    if (m_axi_arready) begin
                        active_burst_beats <= planned_burst_beats;
                        beat_index         <= 9'd0;
                        state              <= DMA_R;
                    end
                end

                DMA_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if ((m_axi_rid != AXI_ID) ||
                            (m_axi_rresp != 2'b00) ||
                            (m_axi_rlast != expected_last)) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            busy  <= 1'b0;
                            state <= DMA_IDLE;
                        end else begin
                            checksum <= checksum ^ masked_read_data;

                            if (expected_last) begin
                                if (read_offset +
                                    ({23'd0, active_burst_beats} << 2) >=
                                    transfer_bytes) begin
                                    bytes_read <= transfer_bytes;
                                    done       <= 1'b1;
                                    busy       <= 1'b0;
                                    state      <= DMA_IDLE;
                                end else begin
                                    read_offset <= read_offset +
                                        ({23'd0, active_burst_beats} << 2);
                                    beat_index <= 9'd0;
                                    state      <= DMA_AR;
                                end
                            end else begin
                                beat_index <= beat_index + 1'b1;
                            end
                        end
                    end
                end

                default: begin
                    busy  <= 1'b0;
                    error <= 1'b1;
                    done  <= 1'b1;
                    state <= DMA_IDLE;
                end
            endcase
        end
    end

endmodule
