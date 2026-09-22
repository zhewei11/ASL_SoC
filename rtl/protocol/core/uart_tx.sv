`include "rtos_core_config.svh"

module uart_tx #(
     parameter int unsigned CLOCK_HZ = `RTOS_CORE_CPU_CLOCK_HZ
    ,parameter int unsigned BAUD_RATE = `RTOS_CORE_PROTOCOL2_BAUD_RATE
) (
     input  logic       clk
    ,input  logic       rst
    ,input  logic       flush
    // Byte-stream input
    ,input  logic       input_valid
    ,output logic       input_ready
    ,input  logic [7:0] input_data
    ,input  logic       input_last
    ,input  logic [31:0] baud_rate
    // Serial output
    ,output logic       serial_tx
    // Status
    ,output logic       busy
    ,output logic       byte_done
    ,output logic       packet_done
);

    logic [8:0] frame_shift;
    logic [3:0] frame_index;
    logic       byte_is_last;
    logic       baud_tick;
    logic       baud_restart;

    assign input_ready = !busy;
    assign baud_restart = input_valid && input_ready;

    uart_fractional_tick #(
         .CLOCK_HZ (CLOCK_HZ)
    ) u_baud_tick (
         .clk     (clk)
        ,.rst     (rst)
        ,.flush   (flush)
        ,.enable  (busy)
        ,.restart (baud_restart)
        ,.tick_hz (baud_rate)
        ,.tick    (baud_tick)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            frame_shift <= 9'h1FF;
            frame_index <= 4'd0;
            byte_is_last <= 1'b0;
            serial_tx   <= 1'b1;
            busy        <= 1'b0;
            byte_done   <= 1'b0;
            packet_done <= 1'b0;
        end else begin
            byte_done   <= 1'b0;
            packet_done <= 1'b0;

            if (input_valid && input_ready) begin
                frame_shift <= {1'b1, input_data};
                frame_index <= 4'd0;
                byte_is_last <= input_last;
                serial_tx   <= 1'b0;
                busy        <= 1'b1;
            end else if (busy && baud_tick) begin
                if (frame_index == 4'd9) begin
                    serial_tx <= 1'b1;
                    busy      <= 1'b0;
                    byte_done <= 1'b1;
                    if (byte_is_last) begin
                        packet_done <= 1'b1;
                    end
                end else begin
                    frame_shift <= {1'b1, frame_shift[8:1]};
                    frame_index <= frame_index + 4'd1;
                    serial_tx   <= frame_shift[0];
                end
            end
        end
    end

endmodule
