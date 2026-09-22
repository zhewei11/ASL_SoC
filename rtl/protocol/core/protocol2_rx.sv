`include "rtos_core_config.svh"

module protocol2_rx #(
     parameter int unsigned MAX_STUFFED_BODY_BYTES = `RTOS_CORE_PROTOCOL2_MAX_STUFFED_BODY_BYTES
    ,parameter int unsigned MAX_PARAMETER_BYTES = `RTOS_CORE_PROTOCOL2_MAX_PARAMETER_BYTES
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    // Receive command interface
    ,input  logic        start
    ,output logic        start_ready
    ,input  logic [7:0]  expected_id
    ,input  logic [31:0] response_timeout_cycles
    ,input  logic [31:0] inter_byte_timeout_cycles
    // UART byte-stream interface
    ,input  logic        rx_valid
    ,output logic        rx_ready
    ,input  logic [7:0]  rx_data
    ,input  logic        rx_framing_error
    // Packet result interface
    ,output logic        result_valid
    ,input  logic        result_ready
    ,output logic [7:0]  result_code
    ,output logic [7:0]  response_id
    ,output logic [7:0]  dynamixel_error
    ,output logic [15:0] parameter_length
    // Destuffed parameter stream
    ,output logic        parameter_valid
    ,input  logic        parameter_ready
    ,output logic [7:0]  parameter_data
    ,output logic        parameter_last
    ,output logic        packet_done
    ,output logic        busy
    ,output logic [2:0]  debug_state
    // Ping-pong buffer Port A: parser writes the active bank
    ,output logic        buffer_write_request
    ,input  logic        buffer_write_ready
    ,output logic [10:0] buffer_write_byte_address
    ,output logic [7:0]  buffer_write_data
    // Ping-pong buffer Port B: output drains the completed bank
    ,output logic        buffer_read_request
    ,input  logic        buffer_read_ready
    ,output logic [8:0]  buffer_read_word_address
    ,input  logic        buffer_read_valid
    ,input  logic [31:0] buffer_read_data
);

    typedef enum logic [2:0] {
        PARSER_IDLE          = 3'd0,
        PARSER_WAIT          = 3'd1,
        PARSER_SEARCH_HEADER = 3'd2,
        PARSER_READ_CONTROL  = 3'd3,
        PARSER_READ_PAYLOAD  = 3'd4,
        PARSER_COMMIT        = 3'd5
    } parser_state_t;

    typedef enum logic [1:0] {
        OUTPUT_IDLE       = 2'd0,
        OUTPUT_RESULT     = 2'd1,
        OUTPUT_WORD_READ  = 2'd2,
        OUTPUT_PARAMETERS = 2'd3
    } output_state_t;

    localparam logic [7:0] RESULT_SUCCESS            = 8'd0;
    localparam logic [7:0] RESULT_RESPONSE_TIMEOUT   = 8'd5;
    localparam logic [7:0] RESULT_INTER_BYTE_TIMEOUT = 8'd6;
    localparam logic [7:0] RESULT_LENGTH_ERROR       = 8'd7;
    localparam logic [7:0] RESULT_CRC_OR_FORMAT      = 8'd8;
    localparam logic [7:0] RESULT_ID_MISMATCH        = 8'd9;
    localparam logic [7:0] RESULT_BUFFER_OVERFLOW    = 8'd10;
    localparam logic [7:0] RESULT_FRAMING_ERROR      = 8'd11;

    localparam int unsigned BANK_BYTES = 1024;

    localparam logic [15:0] MAX_STUFFED_BODY_LIMIT =(MAX_STUFFED_BODY_BYTES > BANK_BYTES) ? BANK_BYTES[15:0] :
                                                                                            MAX_STUFFED_BODY_BYTES[15:0];

    localparam logic [15:0] MAX_PARAMETER_LIMIT    = (MAX_PARAMETER_BYTES > BANK_BYTES) ? BANK_BYTES[15:0] :
                                                                                          MAX_PARAMETER_BYTES[15:0];

    parser_state_t parser_state;
    output_state_t output_state;

    // Keep the original debug state encoding visible in waveforms and
    // standalone assertions. Parser activity has priority when receive and
    // drain overlap.
    logic [7:0]  expected_id_reg;
    logic [31:0] response_timeout_reg;
    logic [31:0] inter_byte_timeout_reg;
    logic [31:0] response_timeout_counter;
    logic [31:0] timeout_counter;

    logic [1:0]  header_match;
    logic [1:0]  control_index;
    logic [7:0]  length_low;
    logic [15:0] stuffed_length;
    logic [15:0] wire_index;
    logic [15:0] destuffed_length;

    logic [7:0]  previous_byte_1;
    logic [7:0]  previous_byte_2;
    logic        expect_stuffed_fd;
    logic [7:0]  status_instruction;
    logic [7:0]  received_crc_low;
    logic [15:0] crc;

    logic [7:0]  pending_result_code;
    logic [7:0]  pending_response_id;
    logic [7:0]  pending_dynamixel_error;
    logic [15:0] pending_parameter_length;

    logic [1:0]  bank_full;
    logic        write_bank;
    logic        read_bank;
    logic [7:0]  bank_result_code [0:1];
    logic [7:0]  bank_response_id [0:1];
    logic [7:0]  bank_dynamixel_error [0:1];
    logic [15:0] bank_parameter_length [0:1];

    logic [15:0] parameter_index;
    logic [10:0] parameter_byte_address;
    logic [31:0] output_word;
    logic        output_read_pending;

    logic        rx_byte_accepted;
    logic [15:0] received_length;
    logic [15:0] received_crc;
    logic        body_wire_byte;
    logic        body_data_byte;
    logic        body_stuff_marker;
    logic        payload_needs_write;
    logic        response_timeout_expiring;
    logic        inter_byte_timeout_expiring;

    function automatic logic [15:0] crc16_update(
         input logic [15:0] crc_in
        ,input logic [7:0]  data
    );
        logic [15:0] value;
        integer      bit_index;
        begin
            value = crc_in;
            for (bit_index = 0;
                 bit_index < 8;
                 bit_index = bit_index + 1) begin
                if (value[15] ^ data[7-bit_index]) begin
                    value =
                        {value[14:0], 1'b0} ^ 16'h8005;
                end else begin
                    value = {value[14:0], 1'b0};
                end
            end
            crc16_update = value;
        end
    endfunction

    assign debug_state =
        ((parser_state == PARSER_SEARCH_HEADER) || (parser_state == PARSER_READ_CONTROL) || (parser_state == PARSER_READ_PAYLOAD)) ?
            parser_state :
            (output_state == OUTPUT_RESULT)     ? 3'd5 :
            (output_state == OUTPUT_WORD_READ)  ? 3'd6 :
            (output_state == OUTPUT_PARAMETERS) ? 3'd7 :
            parser_state;

    assign start_ready = (parser_state == PARSER_WAIT) && !bank_full[write_bank];

    assign body_wire_byte = (parser_state == PARSER_READ_PAYLOAD) && (wire_index < stuffed_length);

    assign body_data_byte = body_wire_byte && !expect_stuffed_fd;

    assign body_stuff_marker = body_data_byte &&
        (previous_byte_2 == 8'hFF) &&
        (previous_byte_1 == 8'hFF) &&
        (rx_data == 8'hFD);

    assign payload_needs_write = body_data_byte && (destuffed_length < MAX_STUFFED_BODY_LIMIT);

    assign rx_ready =
        (parser_state == PARSER_SEARCH_HEADER) ||
        (parser_state == PARSER_READ_CONTROL)  ||
        ((parser_state == PARSER_READ_PAYLOAD) &&
         (!payload_needs_write || buffer_write_ready));

    assign rx_byte_accepted = rx_valid && rx_ready;
    assign received_length = {rx_data, length_low};
    assign received_crc = {rx_data, received_crc_low};

    // response_timeout is absolute from start until a complete packet result;
    // accepted noise bytes must not extend it. inter_byte_timeout is reset by
    // each accepted byte after the header has been found.
    assign response_timeout_expiring = (response_timeout_reg != 32'd0) &&
                                      ((response_timeout_counter + 32'd1) >= response_timeout_reg);

    assign inter_byte_timeout_expiring = (inter_byte_timeout_reg != 32'd0) &&
                                         ((timeout_counter + 32'd1) >= inter_byte_timeout_reg);

    assign buffer_write_request = rx_valid && (parser_state == PARSER_READ_PAYLOAD) &&
                                  payload_needs_write && !rx_framing_error;

    assign buffer_write_byte_address = {write_bank, destuffed_length[9:0]};
    assign buffer_write_data = rx_data;

    assign result_valid = (output_state == OUTPUT_RESULT);

    assign result_code = bank_result_code[read_bank];
    assign response_id = bank_response_id[read_bank];
    assign dynamixel_error = bank_dynamixel_error[read_bank];
    assign parameter_length = bank_parameter_length[read_bank];

    assign parameter_byte_address = {read_bank, parameter_index[9:0] + 10'd2};
    assign buffer_read_request = (output_state == OUTPUT_WORD_READ) && !output_read_pending;
    assign buffer_read_word_address = parameter_byte_address[10:2];

    assign parameter_valid = (output_state == OUTPUT_PARAMETERS);

    assign parameter_data =
        (parameter_byte_address[1:0] == 2'd0) ?
            output_word[7:0] :
        (parameter_byte_address[1:0] == 2'd1) ?
            output_word[15:8] :
        (parameter_byte_address[1:0] == 2'd2) ?
            output_word[23:16] :
            output_word[31:24];
    assign parameter_last = parameter_valid && (parameter_index + 16'd1 == parameter_length);

    assign busy =
        ((parser_state != PARSER_IDLE) &&
         (parser_state != PARSER_WAIT)) ||
        (output_state != OUTPUT_IDLE) ||
        (bank_full != 2'b00);

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            parser_state               <= PARSER_IDLE;
            output_state               <= OUTPUT_IDLE;
            expected_id_reg            <= 8'h00;
            response_timeout_reg       <= 32'h0000_0000;
            inter_byte_timeout_reg     <= 32'h0000_0000;
            response_timeout_counter   <= 32'h0000_0000;
            timeout_counter            <= 32'h0000_0000;
            header_match               <= 2'd0;
            control_index              <= 2'd0;
            length_low                 <= 8'h00;
            stuffed_length             <= 16'h0000;
            wire_index                 <= 16'h0000;
            destuffed_length           <= 16'h0000;
            previous_byte_1            <= 8'h00;
            previous_byte_2            <= 8'h00;
            expect_stuffed_fd          <= 1'b0;
            status_instruction         <= 8'h00;
            received_crc_low           <= 8'h00;
            crc                        <= 16'h0000;
            pending_result_code        <= RESULT_SUCCESS;
            pending_response_id        <= 8'h00;
            pending_dynamixel_error    <= 8'h00;
            pending_parameter_length   <= 16'h0000;
            bank_full                  <= 2'b00;
            write_bank                 <= 1'b0;
            read_bank                  <= 1'b0;
            bank_result_code[0]        <= RESULT_SUCCESS;
            bank_result_code[1]        <= RESULT_SUCCESS;
            bank_response_id[0]        <= 8'h00;
            bank_response_id[1]        <= 8'h00;
            bank_dynamixel_error[0]    <= 8'h00;
            bank_dynamixel_error[1]    <= 8'h00;
            bank_parameter_length[0]   <= 16'h0000;
            bank_parameter_length[1]   <= 16'h0000;
            parameter_index            <= 16'h0000;
            output_word                <= 32'h0000_0000;
            output_read_pending        <= 1'b0;
            packet_done                <= 1'b0;
        end else begin
            packet_done <= 1'b0;

            case (parser_state)
                PARSER_IDLE: begin
                    parser_state <= PARSER_WAIT;
                end

                PARSER_WAIT: begin
                    if (start && start_ready) begin
                        expected_id_reg          <= expected_id;
                        response_timeout_reg     <= response_timeout_cycles;
                        inter_byte_timeout_reg   <= inter_byte_timeout_cycles;
                        response_timeout_counter <= 32'h0000_0000;
                        timeout_counter          <= 32'h0000_0000;
                        header_match             <= 2'd0;
                        control_index            <= 2'd0;
                        length_low               <= 8'h00;
                        stuffed_length           <= 16'h0000;
                        wire_index               <= 16'h0000;
                        destuffed_length         <= 16'h0000;
                        previous_byte_1          <= 8'h00;
                        previous_byte_2          <= 8'h00;
                        expect_stuffed_fd        <= 1'b0;
                        status_instruction       <= 8'h00;
                        received_crc_low         <= 8'h00;
                        crc                      <= 16'h0000;
                        pending_result_code      <= RESULT_SUCCESS;
                        pending_response_id      <= 8'h00;
                        pending_dynamixel_error  <= 8'h00;
                        pending_parameter_length <= 16'h0000;
                        parser_state             <= PARSER_SEARCH_HEADER;
                    end
                end

                PARSER_SEARCH_HEADER: begin
                    if (response_timeout_expiring) begin
                        pending_result_code      <= RESULT_RESPONSE_TIMEOUT;
                        pending_parameter_length <= 16'h0000;
                        parser_state             <= PARSER_COMMIT;

                    end else if (rx_byte_accepted) begin
                        response_timeout_counter <= response_timeout_counter + 32'd1;
                        timeout_counter          <= 32'h0000_0000;

                        if (rx_framing_error) begin
                            pending_result_code      <= RESULT_FRAMING_ERROR;
                            pending_parameter_length <= 16'h0000;
                            parser_state             <= PARSER_COMMIT;
                        end else begin
                            case (header_match)
                                2'd0: begin
                                    header_match <= (rx_data == 8'hFF) ? 2'd1 : 2'd0;
                                end
                                2'd1: begin
                                    header_match <= (rx_data == 8'hFF) ? 2'd2 : 2'd0;
                                end
                                2'd2: begin
                                    header_match <= (rx_data == 8'hFD) ? 2'd3 :
                                                    (rx_data == 8'hFF) ? 2'd2 : 2'd0;
                                end

                                default: begin
                                    if (rx_data == 8'h00) begin
                                        crc <= crc16_update(crc16_update(crc16_update(crc16_update( 16'h0000, 8'hFF), 8'hFF), 8'hFD), 8'h00);
                                        control_index <= 2'd0;
                                        parser_state  <= PARSER_READ_CONTROL;
                                    end else begin
                                        header_match <= (rx_data == 8'hFF) ? 2'd1 : 2'd0;
                                    end
                                end
                            endcase
                        end
                    end else begin
                        response_timeout_counter <= response_timeout_counter + 32'd1;
                    end
                end

                PARSER_READ_CONTROL: begin
                    if (response_timeout_expiring) begin
                        pending_result_code      <= RESULT_RESPONSE_TIMEOUT;
                        pending_parameter_length <= 16'h0000;
                        parser_state             <= PARSER_COMMIT;

                    end else if (rx_byte_accepted) begin
                        response_timeout_counter <= response_timeout_counter + 32'd1;
                        timeout_counter          <= 32'h0000_0000;

                        if (rx_framing_error) begin
                            pending_result_code      <= RESULT_FRAMING_ERROR;
                            pending_parameter_length <= 16'h0000;
                            parser_state             <= PARSER_COMMIT;

                        end else begin
                            case (control_index)
                                2'd0: begin
                                    pending_response_id <= rx_data;
                                    crc                 <= crc16_update(crc, rx_data);
                                    control_index       <= 2'd1;
                                end
                                2'd1: begin
                                    length_low          <= rx_data;
                                    crc                 <= crc16_update(crc, rx_data);
                                    control_index       <= 2'd2;
                                end
                                default: begin
                                    crc                 <= crc16_update(crc, rx_data);

                                    if ((received_length < 16'd4) || (received_length > MAX_STUFFED_BODY_LIMIT + 16'd2)) begin
                                        pending_result_code      <= RESULT_LENGTH_ERROR;
                                        pending_parameter_length <= 16'h0000;
                                        parser_state             <= PARSER_COMMIT;

                                    end else begin
                                        stuffed_length           <= received_length - 16'd2;
                                        wire_index               <= 16'h0000;
                                        destuffed_length         <= 16'h0000;
                                        previous_byte_1          <= 8'h00;
                                        previous_byte_2          <= 8'h00;
                                        expect_stuffed_fd        <= 1'b0;
                                        status_instruction       <= 8'h00;
                                        pending_dynamixel_error  <= 8'h00;
                                        parser_state             <= PARSER_READ_PAYLOAD;
                                    end
                                end
                            endcase
                        end
                    end else if (inter_byte_timeout_expiring) begin
                        pending_result_code      <= RESULT_INTER_BYTE_TIMEOUT;
                        pending_parameter_length <= 16'h0000;
                        parser_state             <= PARSER_COMMIT;

                    end else begin
                        response_timeout_counter <= response_timeout_counter + 32'd1;
                        timeout_counter          <= timeout_counter + 32'd1;
                    end
                end

                PARSER_READ_PAYLOAD: begin
                    if (response_timeout_expiring) begin
                        pending_result_code          <= RESULT_RESPONSE_TIMEOUT;
                        pending_parameter_length     <= 16'h0000;
                        parser_state                 <= PARSER_COMMIT;

                    end else if (rx_byte_accepted) begin
                        response_timeout_counter     <= response_timeout_counter + 32'd1;
                        timeout_counter              <= 32'h0000_0000;
                        if (rx_framing_error) begin
                            pending_result_code      <= RESULT_FRAMING_ERROR;
                            pending_parameter_length <= 16'h0000;
                            parser_state             <= PARSER_COMMIT;

                        end else if (wire_index < stuffed_length) begin
                            crc <= crc16_update(crc, rx_data);
                            if (expect_stuffed_fd) begin
                                if (rx_data != 8'hFD) begin
                                    pending_result_code      <= RESULT_CRC_OR_FORMAT;
                                    pending_parameter_length <= 16'h0000;
                                    parser_state             <= PARSER_COMMIT;

                                end else begin
                                    expect_stuffed_fd <= 1'b0;
                                    wire_index        <= wire_index + 16'd1;
                                end

                            end else if (destuffed_length >= MAX_STUFFED_BODY_LIMIT) begin
                                pending_result_code       <= RESULT_BUFFER_OVERFLOW;
                                pending_parameter_length  <= 16'h0000;
                                parser_state              <= PARSER_COMMIT;

                            end else if (body_stuff_marker && (wire_index + 16'd1 == stuffed_length)) begin
                                pending_result_code       <= RESULT_CRC_OR_FORMAT;
                                pending_parameter_length  <= 16'h0000;
                                parser_state              <= PARSER_COMMIT;

                            end else begin
                                if (destuffed_length == 16'd0) begin
                                    status_instruction <= rx_data;
                                end
                                if (destuffed_length == 16'd1) begin
                                    pending_dynamixel_error <= rx_data;
                                end
                                previous_byte_2   <= previous_byte_1;
                                previous_byte_1   <= rx_data;
                                expect_stuffed_fd <= body_stuff_marker;
                                destuffed_length  <= destuffed_length + 16'd1;
                                wire_index        <= wire_index + 16'd1;
                            end

                        end else if (wire_index == stuffed_length) begin
                            received_crc_low <= rx_data;
                            wire_index       <= wire_index + 16'd1;

                        end else begin
                            if (received_crc != crc) begin
                                pending_result_code      <= RESULT_CRC_OR_FORMAT;
                                pending_parameter_length <= 16'h0000;

                            end else if ((destuffed_length < 16'd2) || (status_instruction != 8'h55)) begin
                                pending_result_code      <= RESULT_CRC_OR_FORMAT;
                                pending_parameter_length <= 16'h0000;

                            end else if ((expected_id_reg != 8'hFE) && (pending_response_id != expected_id_reg)) begin
                                pending_result_code      <= RESULT_ID_MISMATCH;
                                pending_parameter_length <= 16'h0000;

                            end else if ((destuffed_length - 16'd2) > MAX_PARAMETER_LIMIT) begin
                                pending_result_code      <= RESULT_BUFFER_OVERFLOW;
                                pending_parameter_length <= 16'h0000;

                            end else begin
                                pending_result_code      <= RESULT_SUCCESS;
                                pending_parameter_length <= destuffed_length - 16'd2;
                            end
                            parser_state                 <= PARSER_COMMIT;
                        end

                    end else if (inter_byte_timeout_expiring) begin
                        pending_result_code      <= RESULT_INTER_BYTE_TIMEOUT;
                        pending_parameter_length <= 16'h0000;
                        parser_state             <= PARSER_COMMIT;

                    end else begin
                        response_timeout_counter <= response_timeout_counter + 32'd1;
                        timeout_counter          <= timeout_counter + 32'd1;
                    end
                end

                PARSER_COMMIT: begin
                    bank_result_code[write_bank]      <= pending_result_code;
                    bank_response_id[write_bank]      <= pending_response_id;
                    bank_dynamixel_error[write_bank]  <= pending_dynamixel_error;
                    bank_parameter_length[write_bank] <= pending_parameter_length;
                    bank_full[write_bank]             <= 1'b1;
                    write_bank                        <= ~write_bank;
                    parser_state                      <= PARSER_WAIT;
                end

                default: begin
                    pending_result_code      <= RESULT_CRC_OR_FORMAT;
                    pending_parameter_length <= 16'h0000;
                    parser_state             <= PARSER_COMMIT;
                end
            endcase

            case (output_state)
                OUTPUT_IDLE: begin
                    output_read_pending <= 1'b0;
                    if (bank_full[read_bank]) begin
                        output_state <= OUTPUT_RESULT;
                    end
                end

                OUTPUT_RESULT: begin
                    if (result_valid && result_ready) begin
                        if ((result_code == RESULT_SUCCESS) && (parameter_length != 16'd0)) begin
                            parameter_index     <= 16'h0000;
                            output_read_pending <= 1'b0;
                            output_state        <= OUTPUT_WORD_READ;
                        end else begin
                            bank_full[read_bank] <= 1'b0;
                            read_bank            <= ~read_bank;
                            packet_done          <= 1'b1;
                            output_state         <= OUTPUT_IDLE;
                        end
                    end
                end

                OUTPUT_WORD_READ: begin
                    if (buffer_read_request && buffer_read_ready) begin
                        output_read_pending <= 1'b1;
                    end

                    if (buffer_read_valid && output_read_pending) begin
                        output_word         <= buffer_read_data;
                        output_read_pending <= 1'b0;
                        output_state        <= OUTPUT_PARAMETERS;
                    end
                end

                OUTPUT_PARAMETERS: begin
                    if (parameter_valid && parameter_ready) begin
                        if (parameter_last) begin
                            bank_full[read_bank] <= 1'b0;
                            read_bank            <= ~read_bank;
                            packet_done          <= 1'b1;
                            output_state         <= OUTPUT_IDLE;
                        end else begin

                            parameter_index      <= parameter_index + 16'd1;
                            if (parameter_byte_address[1:0] == 2'd3) begin
                                output_read_pending <= 1'b0;
                                output_state        <= OUTPUT_WORD_READ;
                            end
                        end
                    end
                end

                default: begin
                    output_read_pending <= 1'b0;
                    output_state <= OUTPUT_IDLE;
                end
            endcase
        end
    end

endmodule
