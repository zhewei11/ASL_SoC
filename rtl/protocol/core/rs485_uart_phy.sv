`include "rtos_core_config.svh"

module rs485_uart_phy #(
     parameter int unsigned CLOCK_HZ = `RTOS_CORE_CPU_CLOCK_HZ
    ,parameter int unsigned BAUD_RATE = `RTOS_CORE_PROTOCOL2_BAUD_RATE
    ,parameter int unsigned RX_OVERSAMPLE = `RTOS_CORE_PROTOCOL2_RX_OVERSAMPLE
    ,parameter int unsigned DE_SETUP_CYCLES = `RTOS_CORE_PROTOCOL2_DE_SETUP_CYCLES
    ,parameter int unsigned POST_TX_GUARD_CYCLES = `RTOS_CORE_PROTOCOL2_POST_TX_GUARD_CYCLES
) (
     input  logic       clk
    ,input  logic       rst
    ,input  logic       flush
    // Packet byte stream from Protocol TX
    ,input  logic       tx_valid
    ,output logic       tx_ready
    ,input  logic [7:0] tx_data
    ,input  logic       tx_last
    ,input  logic [31:0] baud_rate
    // Packet byte stream to Protocol RX
    ,output logic       rx_valid
    ,input  logic       rx_ready
    ,output logic [7:0] rx_data
    ,output logic       rx_framing_error
    ,output logic       rx_overrun_error
    // Physical MAX3485 pins
    ,output logic       rs485_tx
    ,input  logic       rs485_rx
    ,output logic       rs485_de
    // Transaction status
    ,output logic       tx_complete
    ,output logic       direction_idle
);

    typedef enum logic [2:0] {
        DIR_IDLE  = 3'd0,
        DIR_SETUP = 3'd1,
        DIR_SEND  = 3'd2,
        DIR_DRAIN = 3'd3,
        DIR_GUARD = 3'd4
    } direction_state_t;

    localparam int unsigned DELAY_COUNTER_WIDTH =
        ((DE_SETUP_CYCLES > POST_TX_GUARD_CYCLES ?
          DE_SETUP_CYCLES : POST_TX_GUARD_CYCLES) <= 1) ?
        1 :
        $clog2(DE_SETUP_CYCLES > POST_TX_GUARD_CYCLES ?
              DE_SETUP_CYCLES + 1 :
              POST_TX_GUARD_CYCLES + 1);
    localparam logic [DELAY_COUNTER_WIDTH-1:0] DE_SETUP_LAST =
        (DE_SETUP_CYCLES == 0) ?
        '0 :
        DE_SETUP_CYCLES[DELAY_COUNTER_WIDTH-1:0] - 1'b1;
    localparam logic [DELAY_COUNTER_WIDTH-1:0] POST_TX_GUARD_LAST =
        (POST_TX_GUARD_CYCLES == 0) ?
        '0 :
        POST_TX_GUARD_CYCLES[DELAY_COUNTER_WIDTH-1:0] - 1'b1;

    direction_state_t direction_state;

    logic [DELAY_COUNTER_WIDTH-1:0] delay_counter;
    logic                           uart_tx_valid;
    logic                           uart_tx_ready;
    logic                           uart_packet_done;

    assign direction_idle = (direction_state == DIR_IDLE);

    assign rs485_de =
        (direction_state == DIR_SETUP) ||
        (direction_state == DIR_SEND)  ||
        (direction_state == DIR_DRAIN);

    assign tx_ready =
        (direction_state == DIR_SEND) &&
        uart_tx_ready;
    assign uart_tx_valid =
        (direction_state == DIR_SEND) &&
        tx_valid;

    uart_tx #(
         .CLOCK_HZ  (CLOCK_HZ)
        ,.BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
         .clk         (clk)
        ,.rst         (rst)
        ,.flush       (flush)
        ,.input_valid (uart_tx_valid)
        ,.input_ready (uart_tx_ready)
        ,.input_data  (tx_data)
        ,.input_last  (tx_last)
        ,.baud_rate   (baud_rate)
        ,.serial_tx   (rs485_tx)
        ,.busy        ()
        ,.byte_done   ()
        ,.packet_done (uart_packet_done)
    );

    uart_rx #(
         .CLOCK_HZ   (CLOCK_HZ)
        ,.BAUD_RATE  (BAUD_RATE)
        ,.OVERSAMPLE (RX_OVERSAMPLE)
    ) u_uart_rx (
         .clk                  (clk)
        ,.rst                  (rst)
        ,.flush                (flush)
        ,.serial_rx            (rs485_de ? 1'b1 : rs485_rx)
        ,.baud_rate            (baud_rate)
        ,.output_valid         (rx_valid)
        ,.output_ready         (rx_ready)
        ,.output_data          (rx_data)
        ,.output_framing_error (rx_framing_error)
        ,.busy                 ()
        ,.overrun_error        (rx_overrun_error)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            direction_state <= DIR_IDLE;
            delay_counter    <= '0;
            tx_complete      <= 1'b0;
        end else begin
            tx_complete <= 1'b0;

            case (direction_state)
                DIR_IDLE: begin
                    delay_counter <= '0;
                    if (tx_valid) begin
                        direction_state <= DIR_SETUP;
                    end
                end

                DIR_SETUP: begin
                    if (DE_SETUP_CYCLES == 0) begin
                        direction_state <= DIR_SEND;
                    end else if (delay_counter == DE_SETUP_LAST) begin
                        delay_counter    <= '0;
                        direction_state <= DIR_SEND;
                    end else begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                end

                DIR_SEND: begin
                    if (tx_valid && tx_ready && tx_last) begin
                        direction_state <= DIR_DRAIN;
                    end
                end

                DIR_DRAIN: begin
                    if (uart_packet_done) begin
                        tx_complete <= 1'b1;
                        delay_counter <= '0;
                        if (POST_TX_GUARD_CYCLES == 0) begin
                            direction_state <= DIR_IDLE;
                        end else begin
                            direction_state <= DIR_GUARD;
                        end
                    end
                end

                DIR_GUARD: begin
                    if (delay_counter == POST_TX_GUARD_LAST) begin
                        delay_counter    <= '0;
                        direction_state <= DIR_IDLE;
                    end else begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                end

                default: begin
                    direction_state <= DIR_IDLE;
                    delay_counter   <= '0;
                end
            endcase
        end
    end

endmodule
