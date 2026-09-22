`include "rtos_core_config.svh"

module uart_rx #(
     parameter int unsigned CLOCK_HZ  = `RTOS_CORE_CPU_CLOCK_HZ
    ,parameter int unsigned BAUD_RATE = `RTOS_CORE_PROTOCOL2_BAUD_RATE
    ,parameter int unsigned OVERSAMPLE = `RTOS_CORE_PROTOCOL2_RX_OVERSAMPLE
) (
     input  logic       clk
    ,input  logic       rst
    ,input  logic       flush
    // Serial input
    ,input  logic       serial_rx
    ,input  logic [31:0] baud_rate
    // Byte-stream output
    ,output logic       output_valid
    ,input  logic       output_ready
    ,output logic [7:0] output_data
    ,output logic       output_framing_error
    // Status
    ,output logic       busy
    ,output logic       overrun_error
);

    typedef enum logic [1:0] {
        RX_IDLE  = 2'd0,
        RX_START = 2'd1,
        RX_DATA  = 2'd2,
        RX_STOP  = 2'd3
    } state_t;

    localparam int unsigned HALF_OVERSAMPLE =
        OVERSAMPLE / 2;
    localparam int unsigned SAMPLE_COUNTER_WIDTH =
        (OVERSAMPLE <= 2) ? 1 : $clog2(OVERSAMPLE);
    localparam logic [SAMPLE_COUNTER_WIDTH-1:0] HALF_SAMPLE_LAST =
        HALF_OVERSAMPLE[SAMPLE_COUNTER_WIDTH-1:0] - 1'b1;
    localparam logic [SAMPLE_COUNTER_WIDTH-1:0] FULL_SAMPLE_LAST =
        OVERSAMPLE[SAMPLE_COUNTER_WIDTH-1:0] - 1'b1;

    state_t state;

    logic                            serial_rx_meta;
    logic                            serial_rx_sync;
    logic                            serial_rx_previous;
    logic                            start_edge;
    logic                            sample_tick;
    logic                            sample_restart;
    logic [SAMPLE_COUNTER_WIDTH-1:0] sample_counter;
    logic [2:0]                      data_index;
    logic [7:0]                      data_shift;
    logic [31:0]                     oversample_tick_hz;

    assign oversample_tick_hz = baud_rate * OVERSAMPLE;

    assign start_edge =
        serial_rx_previous &&
        !serial_rx_sync;
    assign sample_restart =
        (state == RX_IDLE) &&
        start_edge;
    assign busy = (state != RX_IDLE);

    uart_fractional_tick #(
         .CLOCK_HZ (CLOCK_HZ)
    ) u_sample_tick (
         .clk     (clk)
        ,.rst     (rst)
        ,.flush   (flush)
        ,.enable  (busy)
        ,.restart (sample_restart)
        ,.tick_hz (oversample_tick_hz)
        ,.tick    (sample_tick)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            serial_rx_meta     <= 1'b1;
            serial_rx_sync     <= 1'b1;
            serial_rx_previous <= 1'b1;
        end else begin
            serial_rx_meta     <= serial_rx;
            serial_rx_sync     <= serial_rx_meta;
            serial_rx_previous <= serial_rx_sync;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            state                <= RX_IDLE;
            sample_counter       <= '0;
            data_index           <= 3'd0;
            data_shift           <= 8'h00;
            output_valid         <= 1'b0;
            output_data          <= 8'h00;
            output_framing_error <= 1'b0;
            overrun_error        <= 1'b0;
        end else begin
            overrun_error <= 1'b0;

            if (output_valid && output_ready) begin
                output_valid <= 1'b0;
            end

            case (state)
                RX_IDLE: begin
                    sample_counter <= '0;
                    if (start_edge) begin
                        state <= RX_START;
                    end
                end

                RX_START: begin
                    if (sample_tick) begin
                        if (sample_counter == HALF_SAMPLE_LAST) begin
                            sample_counter <= '0;
                            if (!serial_rx_sync) begin
                                data_index <= 3'd0;
                                state      <= RX_DATA;
                            end else begin
                                state <= RX_IDLE;
                            end
                        end else begin
                            sample_counter <=
                                sample_counter + 1'b1;
                        end
                    end
                end

                RX_DATA: begin
                    if (sample_tick) begin
                        if (sample_counter == FULL_SAMPLE_LAST) begin
                            sample_counter         <= '0;
                            data_shift[data_index] <= serial_rx_sync;
                            if (data_index == 3'd7) begin
                                state <= RX_STOP;
                            end else begin
                                data_index <= data_index + 3'd1;
                            end
                        end else begin
                            sample_counter <=
                                sample_counter + 1'b1;
                        end
                    end
                end

                RX_STOP: begin
                    if (sample_tick) begin
                        if (sample_counter == FULL_SAMPLE_LAST) begin
                            sample_counter <= '0;
                            state          <= RX_IDLE;
                            if (!output_valid || output_ready) begin
                                output_data <= data_shift;
                                output_framing_error <=
                                    !serial_rx_sync;
                                output_valid <= 1'b1;
                            end else begin
                                overrun_error <= 1'b1;
                            end
                        end else begin
                            sample_counter <=
                                sample_counter + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= RX_IDLE;
                end
            endcase
        end
    end

endmodule
