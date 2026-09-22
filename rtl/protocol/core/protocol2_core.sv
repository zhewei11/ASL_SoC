`include "rtos_core_config.svh"

module protocol2_core #(
     parameter int unsigned CLOCK_HZ =               `RTOS_CORE_CPU_CLOCK_HZ
    ,parameter int unsigned BAUD_RATE =              `RTOS_CORE_PROTOCOL2_BAUD_RATE
    ,parameter int unsigned RX_OVERSAMPLE =          `RTOS_CORE_PROTOCOL2_RX_OVERSAMPLE
    ,parameter int unsigned DE_SETUP_CYCLES =        `RTOS_CORE_PROTOCOL2_DE_SETUP_CYCLES
    ,parameter int unsigned POST_TX_GUARD_CYCLES =   `RTOS_CORE_PROTOCOL2_POST_TX_GUARD_CYCLES
    ,parameter int unsigned MAX_BODY_BYTES =         `RTOS_CORE_PROTOCOL2_MAX_BODY_BYTES
    ,parameter int unsigned MAX_STUFFED_BODY_BYTES = `RTOS_CORE_PROTOCOL2_MAX_STUFFED_BODY_BYTES
    ,parameter int unsigned MAX_PARAMETER_BYTES =    `RTOS_CORE_PROTOCOL2_MAX_PARAMETER_BYTES
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    // Transaction command. cmd_body_len includes Instruction + Parameters.
    ,input  logic        cmd_valid
    ,output logic        cmd_ready
    ,input  logic [7:0]  cmd_id
    ,input  logic [15:0] cmd_body_len
    ,input  logic [7:0]  cmd_expected_id
    ,input  logic [7:0]  cmd_response_count
    ,input  logic [31:0] response_timeout_cycles
    ,input  logic [31:0] inter_byte_timeout_cycles
    ,input  logic [31:0] baud_rate
    // Command body byte stream
    ,input  logic        body_valid
    ,output logic        body_ready
    ,input  logic [7:0]  body_data
    // One result is emitted for each received Status Packet.
    ,output logic        result_valid
    ,input  logic        result_ready
    ,output logic [7:0]  result_index
    ,output logic [7:0]  result_code
    ,output logic [7:0]  response_id
    ,output logic [7:0]  dynamixel_error
    ,output logic [15:0] parameter_length
    // Parameters belonging to the most recently accepted result
    ,output logic        parameter_valid
    ,input  logic        parameter_ready
    ,output logic [7:0]  parameter_data
    ,output logic        parameter_last
    // Transaction status
    ,output logic        transaction_busy
    ,output logic        transaction_done
    ,output logic        transaction_error
    ,output logic        uart_rx_overrun_error
    // AXU15EGB MAX3485-side pins
    ,output logic        rs485_tx
    ,input  logic        rs485_rx
    ,output logic        rs485_de
);

    typedef enum logic [1:0] {
        CORE_IDLE = 2'd0,
        CORE_WAIT = 2'd1,
        CORE_TX   = 2'd2,
        CORE_RX   = 2'd3
    } core_state_t;

    localparam logic [7:0] RESULT_SUCCESS = 8'd0;

    core_state_t core_state;

    logic [7:0]  expected_id_reg;
    logic [7:0]  expected_response_count_reg;
    logic [31:0] response_timeout_reg;
    logic [31:0] inter_byte_timeout_reg;
    logic [7:0]  received_response_count;
    logic        result_consumed;
    logic        tx_complete_seen;

    logic        tx_cmd_valid;
    logic        tx_cmd_ready;
    logic        tx_body_valid;
    logic        tx_body_ready;
    logic        tx_valid;
    logic        tx_ready;
    logic [7:0]  tx_data;
    logic        tx_last;
    logic        tx_error;
    logic        tx_buffer_request;
    logic        tx_buffer_ready;
    logic        tx_buffer_write_enable;
    logic [10:0] tx_buffer_byte_address;
    logic [7:0]  tx_buffer_write_data;
    logic        tx_buffer_read_valid;
    logic [31:0] tx_buffer_read_data;

    logic        rx_start;
    logic        rx_start_ready;
    logic        rx_valid;
    logic        rx_ready;
    logic [7:0]  rx_data;
    logic        rx_framing_error;
    logic        rx_overrun_error;
    logic        rx_packet_done;
    logic        rx_buffer_write_request;
    logic        rx_buffer_write_ready;
    logic [10:0] rx_buffer_write_byte_address;
    logic [7:0]  rx_buffer_write_data;
    logic        rx_buffer_read_request;
    logic        rx_buffer_read_ready;
    logic [8:0]  rx_buffer_read_word_address;
    logic        rx_buffer_read_valid;
    logic [31:0] rx_buffer_read_data;

    logic        buffer_a_request;
    logic        buffer_a_ready;
    logic        buffer_a_write_enable;
    logic [10:0] buffer_a_byte_address;
    logic [7:0]  buffer_a_write_data;
    logic        buffer_a_read_valid;
    logic [31:0] buffer_a_read_data;

    logic phy_tx_complete;
    logic phy_direction_idle;
    logic first_rx_start;
    logic next_rx_start;
    logic result_handshake;

    assign cmd_ready = (core_state == CORE_WAIT) && tx_cmd_ready &&
                                  rx_start_ready && phy_direction_idle;

    assign tx_cmd_valid = (core_state == CORE_WAIT) && cmd_valid;

    assign body_ready = (core_state == CORE_TX) && tx_body_ready;

    assign tx_body_valid = (core_state == CORE_TX) && body_valid;

    assign transaction_busy = ((core_state != CORE_IDLE) &&
                              (core_state != CORE_WAIT)) || !phy_direction_idle;


    assign result_index = received_response_count;
    assign result_handshake = result_valid && result_ready;

    assign first_rx_start = (core_state == CORE_TX) &&
              (tx_complete_seen || phy_tx_complete) && phy_direction_idle &&
              (expected_response_count_reg != 8'd0) && rx_start_ready;

    assign next_rx_start = (core_state == CORE_RX) && rx_start_ready &&
        result_consumed && (received_response_count < expected_response_count_reg);

    assign rx_start = first_rx_start || next_rx_start;

    protocol2_tx #(
         .MAX_BODY_BYTES         (MAX_BODY_BYTES)
        ,.MAX_STUFFED_BODY_BYTES (MAX_STUFFED_BODY_BYTES)
    ) u_protocol2_tx (
         .clk                 (clk)
        ,.rst                 (rst)
        ,.flush               (flush)
        ,.cmd_valid           (tx_cmd_valid)
        ,.cmd_ready           (tx_cmd_ready)
        ,.cmd_id              (cmd_id)
        ,.cmd_body_len        (cmd_body_len)
        ,.body_valid          (tx_body_valid)
        ,.body_ready          (tx_body_ready)
        ,.body_data           (body_data)
        ,.buffer_bank         (1'b0)
        ,.buffer_request      (tx_buffer_request)
        ,.buffer_ready        (tx_buffer_ready)
        ,.buffer_write_enable (tx_buffer_write_enable)
        ,.buffer_byte_address (tx_buffer_byte_address)
        ,.buffer_write_data   (tx_buffer_write_data)
        ,.buffer_read_valid   (tx_buffer_read_valid)
        ,.buffer_read_data    (tx_buffer_read_data)
        ,.tx_valid            (tx_valid)
        ,.tx_ready            (tx_ready)
        ,.tx_data             (tx_data)
        ,.tx_last             (tx_last)
        ,.busy                ()
        ,.done                ()
        ,.error               (tx_error)
    );

    rs485_uart_phy #(
         .CLOCK_HZ             (CLOCK_HZ)
        ,.BAUD_RATE            (BAUD_RATE)
        ,.RX_OVERSAMPLE        (RX_OVERSAMPLE)
        ,.DE_SETUP_CYCLES      (DE_SETUP_CYCLES)
        ,.POST_TX_GUARD_CYCLES (POST_TX_GUARD_CYCLES)
    ) u_rs485_uart_phy (
         .clk              (clk)
        ,.rst              (rst)
        ,.flush            (flush)
        ,.tx_valid         (tx_valid)
        ,.tx_ready         (tx_ready)
        ,.tx_data          (tx_data)
        ,.tx_last          (tx_last)
        ,.baud_rate        (baud_rate)
        ,.rx_valid         (rx_valid)
        ,.rx_ready         (rx_ready)
        ,.rx_data          (rx_data)
        ,.rx_framing_error (rx_framing_error)
        ,.rx_overrun_error (rx_overrun_error)
        ,.rs485_tx         (rs485_tx)
        ,.rs485_rx         (rs485_rx)
        ,.rs485_de         (rs485_de)
        ,.tx_complete      (phy_tx_complete)
        ,.direction_idle   (phy_direction_idle)
    );

    protocol2_rx #(
         .MAX_STUFFED_BODY_BYTES (MAX_STUFFED_BODY_BYTES)
        ,.MAX_PARAMETER_BYTES    (MAX_PARAMETER_BYTES)
    ) u_protocol2_rx (
         .clk                       (clk)
        ,.rst                       (rst)
        ,.flush                     (flush)
        ,.start                     (rx_start)
        ,.start_ready               (rx_start_ready)
        ,.expected_id               (expected_id_reg)
        ,.response_timeout_cycles   (response_timeout_reg)
        ,.inter_byte_timeout_cycles (inter_byte_timeout_reg)
        ,.rx_valid                  (rx_valid)
        ,.rx_ready                  (rx_ready)
        ,.rx_data                   (rx_data)
        ,.rx_framing_error          (rx_framing_error)
        ,.result_valid              (result_valid)
        ,.result_ready              (result_ready)
        ,.result_code               (result_code)
        ,.response_id               (response_id)
        ,.dynamixel_error           (dynamixel_error)
        ,.parameter_length          (parameter_length)
        ,.parameter_valid           (parameter_valid)
        ,.parameter_ready           (parameter_ready)
        ,.parameter_data            (parameter_data)
        ,.parameter_last            (parameter_last)
        ,.packet_done               (rx_packet_done)
        ,.busy                      ()
        ,.debug_state               ()
        ,.buffer_write_request      (rx_buffer_write_request)
        ,.buffer_write_ready        (rx_buffer_write_ready)
        ,.buffer_write_byte_address (rx_buffer_write_byte_address)
        ,.buffer_write_data         (rx_buffer_write_data)
        ,.buffer_read_request       (rx_buffer_read_request)
        ,.buffer_read_ready         (rx_buffer_read_ready)
        ,.buffer_read_word_address  (rx_buffer_read_word_address)
        ,.buffer_read_valid         (rx_buffer_read_valid)
        ,.buffer_read_data          (rx_buffer_read_data)
    );

    assign buffer_a_request      = (core_state == CORE_TX) ? tx_buffer_request :
                                   (core_state == CORE_RX) ? rx_buffer_write_request : 1'b0;

    assign buffer_a_write_enable = (core_state == CORE_TX) ? tx_buffer_write_enable : 1'b1;
    assign buffer_a_byte_address = (core_state == CORE_TX) ? tx_buffer_byte_address : rx_buffer_write_byte_address;
    assign buffer_a_write_data   = (core_state == CORE_TX) ? tx_buffer_write_data : rx_buffer_write_data;

    assign tx_buffer_ready       = (core_state == CORE_TX) && buffer_a_ready;
    assign tx_buffer_read_valid  = (core_state == CORE_TX) && buffer_a_read_valid;
    assign rx_buffer_write_ready = (core_state == CORE_RX) && buffer_a_ready;

    assign tx_buffer_read_data   = buffer_a_read_data;

    protocol2_pingpong_sram u_packet_buffer (
         .clk                 (clk)
        ,.rst                 (rst)
        ,.flush               (flush)
        ,.port_a_request      (buffer_a_request)
        ,.port_a_ready        (buffer_a_ready)
        ,.port_a_write_enable (buffer_a_write_enable)
        ,.port_a_byte_address (buffer_a_byte_address)
        ,.port_a_write_data   (buffer_a_write_data)
        ,.port_a_read_valid   (buffer_a_read_valid)
        ,.port_a_read_data    (buffer_a_read_data)
        ,.port_b_request      (rx_buffer_read_request)
        ,.port_b_ready        (rx_buffer_read_ready)
        ,.port_b_word_address (rx_buffer_read_word_address)
        ,.port_b_read_valid   (rx_buffer_read_valid)
        ,.port_b_read_data    (rx_buffer_read_data)
    );

    assign uart_rx_overrun_error = rx_overrun_error;

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            core_state                  <= CORE_IDLE;
            expected_id_reg             <= 8'h00;
            expected_response_count_reg <= 8'h00;
            response_timeout_reg        <= 32'h0000_0000;
            inter_byte_timeout_reg      <= 32'h0000_0000;
            received_response_count     <= 8'h00;
            result_consumed             <= 1'b0;
            tx_complete_seen            <= 1'b0;
            transaction_done            <= 1'b0;
            transaction_error           <= 1'b0;
        end else begin
            transaction_done  <= 1'b0;
            transaction_error <= 1'b0;

            case (core_state)
                CORE_IDLE: begin
                    core_state <= CORE_WAIT;
                end

                CORE_WAIT: begin
                    if (cmd_valid && cmd_ready) begin
                        expected_id_reg             <= cmd_expected_id;
                        expected_response_count_reg <= cmd_response_count;
                        response_timeout_reg        <= response_timeout_cycles;
                        inter_byte_timeout_reg      <= inter_byte_timeout_cycles;
                        received_response_count     <= 8'h00;
                        result_consumed             <= 1'b0;
                        tx_complete_seen            <= 1'b0;
                        core_state                  <= CORE_TX;
                    end
                end

                CORE_TX: begin
                    if (tx_error) begin
                        transaction_done  <= 1'b1;
                        transaction_error <= 1'b1;
                        tx_complete_seen  <= 1'b0;
                        core_state        <= CORE_WAIT;
                    end else begin
                        if (phy_tx_complete) begin
                            tx_complete_seen <= 1'b1;
                        end
                    end

                    if (!tx_error && (tx_complete_seen || phy_tx_complete) && phy_direction_idle) begin
                        if (expected_response_count_reg == 8'd0) begin
                            transaction_done  <= 1'b1;
                            tx_complete_seen  <= 1'b0;
                            core_state        <= CORE_WAIT;
                        end else if (first_rx_start) begin
                            result_consumed   <= 1'b0;
                            tx_complete_seen  <= 1'b0;
                            core_state        <= CORE_RX;
                        end
                    end
                end

                CORE_RX: begin
                    if (result_handshake) begin
                        if (result_code != RESULT_SUCCESS) begin
                            transaction_done  <= 1'b1;
                            transaction_error <= 1'b1;
                            result_consumed   <= 1'b0;
                            core_state        <= CORE_WAIT;
                        end else begin
                            result_consumed         <= 1'b1;
                            received_response_count <= received_response_count + 8'd1;

                            if (rx_packet_done && (received_response_count + 8'd1 >= expected_response_count_reg)) begin
                                transaction_done <= 1'b1;
                                result_consumed  <= 1'b0;
                                core_state       <= CORE_WAIT;
                            end
                        end
                    end

                    if (next_rx_start && rx_start_ready) begin
                        result_consumed <= 1'b0;
                    end

                    if (rx_packet_done && !result_handshake && (received_response_count >= expected_response_count_reg)) begin
                        transaction_done <= 1'b1;
                        result_consumed  <= 1'b0;
                        core_state       <= CORE_WAIT;
                    end
                end

                default: begin
                    core_state        <= CORE_IDLE;
                    transaction_done  <= 1'b1;
                    transaction_error <= 1'b1;
                end
            endcase
        end
    end

endmodule
