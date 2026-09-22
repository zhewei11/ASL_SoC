`include "rtos_core_config.svh"

module protocol2_tx #(
     parameter int unsigned MAX_BODY_BYTES = `RTOS_CORE_PROTOCOL2_MAX_BODY_BYTES
    ,parameter int unsigned MAX_STUFFED_BODY_BYTES = `RTOS_CORE_PROTOCOL2_MAX_STUFFED_BODY_BYTES
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    // Command interface
    ,input  logic        cmd_valid
    ,output logic        cmd_ready
    ,input  logic [7:0]  cmd_id
    ,input  logic [15:0] cmd_body_len
    // Body interface
    ,input  logic        body_valid
    ,output logic        body_ready
    ,input  logic [7:0]  body_data
    // Shared ping-pong packet-buffer port
    ,input  logic        buffer_bank
    ,output logic        buffer_request
    ,input  logic        buffer_ready
    ,output logic        buffer_write_enable
    ,output logic [10:0] buffer_byte_address
    ,output logic [7:0]  buffer_write_data
    ,input  logic        buffer_read_valid
    ,input  logic [31:0] buffer_read_data
    // Transmit interface
    ,output logic        tx_valid
    ,input  logic        tx_ready
    ,output logic [7:0]  tx_data
    ,output logic        tx_last
    // Status interface
    ,output logic        busy
    ,output logic        done
    ,output logic        error
);

    typedef enum logic [2:0] {
        IDLE          = 3'd0,
        WAIT          = 3'd1,
        LOAD_BODY     = 3'd2,
        INSERT_STUFF  = 3'd3,
        SEND_HEADER   = 3'd4,
        BODY_READ     = 3'd5,
        SEND_BODY     = 3'd6,
        SEND_CRC      = 3'd7
    } state_t;

    localparam int unsigned LOCAL_SRAM_BYTES = 1024;
    localparam logic [15:0] MAX_BODY_BYTES_LIMIT = MAX_BODY_BYTES[15:0];
    localparam logic [15:0] MAX_STUFFED_BODY_BYTES_LIMIT = (MAX_STUFFED_BODY_BYTES > LOCAL_SRAM_BYTES)
                                                            ? LOCAL_SRAM_BYTES[15:0] : MAX_STUFFED_BODY_BYTES[15:0];

    state_t state;

    logic [7:0]  command_id;
    logic [15:0] body_length;
    logic [15:0] body_index;
    logic [15:0] stuffed_length;
    logic [15:0] send_index;
    logic [15:0] crc;
    logic [7:0]  previous_byte_1;
    logic [7:0]  previous_byte_2;
    logic        insert_was_last;
    logic        overflow_pending;

    logic        sram_enable;
    logic        sram_write_enable;
    logic [10:0] sram_byte_address;
    logic [7:0]  sram_write_data;
    logic [31:0] sram_read_word;

    // The 32-bit current buffer feeds four ordered TX bytes.  While it is
    // being drained, the next SRAM word is prefetched into next_word.
    logic [31:0] current_word;
    logic [31:0] next_word;
    logic        current_word_valid;
    logic        body_read_pending;
    logic        prefetch_pending;
    logic        next_word_valid;

    logic        input_is_last;
    logic        input_needs_stuffing;
    logic [15:0] protocol_length;
    logic        load_sram_write;
    logic        insert_sram_write;
    logic        body_read_request;
    logic        prefetch_request;
    logic        next_word_exists;
    logic [31:0] active_word;
    logic [7:0]  current_body_byte;
    logic [31:0] worst_case_stuffed_length;

    function automatic logic [15:0] crc16_update(
         input logic [15:0] crc_in
        ,input logic [7:0]  data
    );
        logic [15:0] value;
        integer      bit_index;
        begin
            value = crc_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (value[15] ^ data[7-bit_index]) begin
                    value = {value[14:0], 1'b0} ^ 16'h8005;
                end else begin
                    value = {value[14:0], 1'b0};
                end
            end
            crc16_update = value;
        end
    endfunction

    function automatic logic [7:0] header_byte(
         input logic [15:0] index
        ,input logic [7:0]  packet_id
        ,input logic [15:0] packet_length
    );
        begin
            case (index)
                16'd0: header_byte = 8'hFF;
                16'd1: header_byte = 8'hFF;
                16'd2: header_byte = 8'hFD;
                16'd3: header_byte = 8'h00;
                16'd4: header_byte = packet_id;
                16'd5: header_byte = packet_length[7:0];
                16'd6: header_byte = packet_length[15:8];
                default: header_byte = 8'h00;
            endcase
        end
    endfunction

    assign input_is_last              = (body_index + 16'd1 == body_length);
    assign protocol_length            = stuffed_length + 16'd2;
    assign worst_case_stuffed_length  = {16'd0, cmd_body_len} + (({16'd0, cmd_body_len} + 32'd4) / 32'd3);

    assign active_word = current_word_valid ? current_word : sram_read_word;

    assign current_body_byte =
        (send_index[1:0] == 2'd0) ? active_word[7:0]   :
        (send_index[1:0] == 2'd1) ? active_word[15:8]  :
        (send_index[1:0] == 2'd2) ? active_word[23:16] :
                                    active_word[31:24];

    assign next_word_exists = ({send_index[15:2], 2'b00} + 16'd4) < stuffed_length;

    // Match Protocol2PacketHandler::addStuffing exactly.  The SDK
    // returns early when Length is below 8 and starts at Parameter[0].
    assign input_needs_stuffing =
        (body_length      >= 16'd6) &&
        (body_index       >= 16'd3) &&
        (previous_byte_2  == 8'hFF) &&
        (previous_byte_1  == 8'hFF) &&
        (body_data        == 8'hFD);

    assign cmd_ready = (state == WAIT) && !done && !error;

    assign body_ready = (state == LOAD_BODY) &&
        (overflow_pending || (stuffed_length >= MAX_STUFFED_BODY_BYTES_LIMIT) || buffer_ready);

    assign busy = (((state != IDLE) && (state != WAIT)) || done || error);

    assign tx_valid =
        (state == SEND_HEADER) ||
        (state == SEND_BODY)   ||
        (state == SEND_CRC);

    assign tx_last = (state == SEND_CRC) && (send_index == 16'd1);

    assign tx_data =
        (state == SEND_HEADER) ? header_byte(send_index, command_id, protocol_length) :
        (state == SEND_BODY)   ? current_body_byte :
        ((state == SEND_CRC) && (send_index == 16'd0)) ? crc[7:0] :
        (state == SEND_CRC)    ? crc[15:8] : 8'h00;

    assign load_sram_write = (state == LOAD_BODY) && body_valid &&
                                       body_ready && !overflow_pending &&
                                       (stuffed_length < MAX_STUFFED_BODY_BYTES_LIMIT);

    assign insert_sram_write = (state == INSERT_STUFF) && (stuffed_length < MAX_STUFFED_BODY_BYTES_LIMIT);

    assign body_read_request = (state == BODY_READ) && !body_read_pending && !prefetch_pending;

    assign prefetch_request = (state == SEND_BODY) && next_word_exists && !next_word_valid && !prefetch_pending;

    assign sram_enable = load_sram_write || insert_sram_write || body_read_request || prefetch_request;

    assign sram_write_enable = load_sram_write || insert_sram_write;

    assign sram_byte_address = body_read_request ? {buffer_bank, send_index[9:2], 2'b00} :
                                prefetch_request ? {buffer_bank, (send_index[9:2] + 8'd1), 2'b00} :
                                {buffer_bank, stuffed_length[9:0]};

    assign sram_write_data = (state == INSERT_STUFF) ? 8'hFD : body_data;

    assign buffer_request       = sram_enable;
    assign buffer_write_enable  = sram_write_enable;
    assign buffer_byte_address  = sram_byte_address;
    assign buffer_write_data    = sram_write_data;
    assign sram_read_word       = buffer_read_data;

    // State and registers are updated together, matching the controller
    // style used by the reference cache/DMA RTL.
    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            state              <= IDLE;
            command_id         <= 8'h00;
            body_length        <= 16'h0000;
            body_index         <= 16'h0000;
            stuffed_length     <= 16'h0000;
            send_index         <= 16'h0000;
            crc                <= 16'h0000;
            previous_byte_1    <= 8'h00;
            previous_byte_2    <= 8'h00;
            insert_was_last    <= 1'b0;
            overflow_pending   <= 1'b0;
            current_word       <= 32'h0000_0000;
            next_word          <= 32'h0000_0000;
            current_word_valid <= 1'b0;
            body_read_pending  <= 1'b0;
            prefetch_pending   <= 1'b0;
            next_word_valid    <= 1'b0;
            done               <= 1'b0;
            error              <= 1'b0;
        end else begin
            done               <= 1'b0;
            error              <= 1'b0;

            if ((state == SEND_BODY) && prefetch_pending && buffer_read_valid) begin
                next_word        <= sram_read_word;
                next_word_valid  <= 1'b1;
                prefetch_pending <= 1'b0;
            end else if (prefetch_request && buffer_ready) begin
                prefetch_pending <= 1'b1;
            end

            case (state)
                IDLE: begin
                    state <= WAIT;
                end

                WAIT: begin
                    if (cmd_valid && cmd_ready) begin
                        if ((cmd_body_len == 16'd0) || (cmd_body_len > MAX_BODY_BYTES_LIMIT) ||
                            (worst_case_stuffed_length > MAX_STUFFED_BODY_BYTES_LIMIT)) begin
                            error            <= 1'b1;
                        end
                        else begin
                            command_id       <= cmd_id;
                            body_length      <= cmd_body_len;
                            body_index       <= 16'h0000;
                            stuffed_length   <= 16'h0000;
                            send_index       <= 16'h0000;
                            crc              <= 16'h0000;
                            previous_byte_1  <= 8'h00;
                            previous_byte_2  <= 8'h00;
                            insert_was_last  <= 1'b0;
                            overflow_pending <= 1'b0;
                            current_word     <= 32'h0000_0000;
                            next_word        <= 32'h0000_0000;
                            current_word_valid <= 1'b0;
                            body_read_pending <= 1'b0;
                            prefetch_pending <= 1'b0;
                            next_word_valid  <= 1'b0;
                            state            <= LOAD_BODY;
                        end
                    end
                end

                LOAD_BODY: begin
                    if (body_valid && body_ready) begin
                        if (overflow_pending || (stuffed_length >= MAX_STUFFED_BODY_BYTES_LIMIT)) begin
                            overflow_pending <= 1'b1;
                            if (input_is_last) begin
                                state       <= WAIT;
                                error       <= 1'b1;
                            end
                            else begin
                                body_index  <= body_index + 16'd1;
                            end
                        end
                        else begin
                            stuffed_length  <= stuffed_length + 16'd1;
                            previous_byte_2 <= previous_byte_1;
                            previous_byte_1 <= body_data;

                            if (!input_is_last) begin
                                body_index  <= body_index + 16'd1;
                            end

                            if (input_needs_stuffing) begin
                                insert_was_last <= input_is_last;
                                state           <= INSERT_STUFF;
                            end
                            else if (input_is_last) begin
                                send_index <= 16'h0000;
                                crc        <= 16'h0000;
                                state      <= SEND_HEADER;
                            end
                        end
                    end
                end

                INSERT_STUFF: begin
                    if (stuffed_length >= MAX_STUFFED_BODY_BYTES_LIMIT) begin
                        overflow_pending <= 1'b1;
                        if (insert_was_last) begin
                            state     <= WAIT;
                            error     <= 1'b1;
                        end
                        else begin
                            state <= LOAD_BODY;
                        end
                    end else if (buffer_ready) begin
                        stuffed_length <= stuffed_length + 16'd1;
                        if (insert_was_last) begin
                            send_index <= 16'h0000;
                            crc        <= 16'h0000;
                            state      <= SEND_HEADER;
                        end
                        else begin
                            state <= LOAD_BODY;
                        end
                    end
                end

                SEND_HEADER: begin
                    if (tx_valid && tx_ready) begin
                        crc <= crc16_update(crc, tx_data);
                        if (send_index == 16'd6) begin
                            send_index        <= 16'h0000;
                            current_word_valid <= 1'b0;
                            body_read_pending  <= 1'b0;
                            prefetch_pending  <= 1'b0;
                            next_word_valid   <= 1'b0;
                            state             <= BODY_READ;
                        end else begin
                            send_index <= send_index + 16'd1;
                        end
                    end
                end

                BODY_READ: begin
                    if (body_read_request && buffer_ready) begin
                        body_read_pending <= 1'b1;
                    end

                    if (buffer_read_valid && (body_read_pending || prefetch_pending)) begin
                        current_word       <= sram_read_word;
                        current_word_valid <= 1'b1;
                        body_read_pending  <= 1'b0;
                        prefetch_pending   <= 1'b0;
                        next_word_valid    <= 1'b0;
                        state              <= SEND_BODY;
                    end
                end

                SEND_BODY: begin
                    // Preserve the first SRAM word before a prefetch changes
                    // the SRAM Q output.
                    if (!current_word_valid) begin
                        current_word       <= sram_read_word;
                        current_word_valid <= 1'b1;
                    end

                    if (tx_valid && tx_ready) begin
                        crc <= crc16_update(crc, tx_data);
                        if (send_index + 16'd1 == stuffed_length) begin
                            send_index        <= 16'h0000;
                            current_word_valid <= 1'b0;
                            body_read_pending  <= 1'b0;
                            prefetch_pending  <= 1'b0;
                            next_word_valid   <= 1'b0;
                            state             <= SEND_CRC;
                        end
                        else begin
                            send_index <= send_index + 16'd1;
                            if (send_index[1:0] == 2'd3) begin
                                if (next_word_valid) begin
                                    current_word    <= next_word;
                                    next_word_valid <= 1'b0;
                                end else if (buffer_read_valid && prefetch_pending) begin
                                    current_word       <= sram_read_word;
                                    current_word_valid <= 1'b1;
                                    prefetch_pending   <= 1'b0;
                                    next_word_valid    <= 1'b0;
                                end else begin
                                    current_word_valid <= 1'b0;
                                    state             <= BODY_READ;
                                end
                            end
                        end
                    end
                end

                SEND_CRC: begin
                    if (tx_valid && tx_ready) begin
                        if (send_index == 16'd0) begin
                            send_index <= 16'd1;
                        end
                        else begin
                            send_index        <= 16'h0000;
                            current_word_valid <= 1'b0;
                            body_read_pending  <= 1'b0;
                            prefetch_pending  <= 1'b0;
                            next_word_valid   <= 1'b0;
                            state             <= WAIT;
                            done              <= 1'b1;
                        end
                    end
                end

                default: begin
                    current_word_valid <= 1'b0;
                    body_read_pending <= 1'b0;
                    prefetch_pending  <= 1'b0;
                    next_word_valid   <= 1'b0;
                    state             <= IDLE;
                    error             <= 1'b1;
                end
            endcase
        end
    end

endmodule
