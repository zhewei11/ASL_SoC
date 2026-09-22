`include "rtos_core_config.svh"

module uart_fractional_tick #(
     parameter int unsigned CLOCK_HZ = `RTOS_CORE_CPU_CLOCK_HZ
) (
     input  logic clk
    ,input  logic rst
    ,input  logic flush
    ,input  logic enable
    ,input  logic restart
    ,input  logic [31:0] tick_hz
    ,output logic tick
);

    localparam logic [63:0] CLOCK_HZ_VALUE = {32'd0, CLOCK_HZ};
    logic [63:0] phase_accumulator;
    logic [63:0] phase_sum;

    assign phase_sum = phase_accumulator + {32'd0, tick_hz};
    assign tick =
        enable &&
        !restart &&
        (phase_sum >= CLOCK_HZ_VALUE);

    always_ff @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            phase_accumulator <= 64'd0;
        end else if (restart || !enable) begin
            phase_accumulator <= 64'd0;
        end else if (tick) begin
            phase_accumulator <= phase_sum - CLOCK_HZ_VALUE;
        end else begin
            phase_accumulator <= phase_sum;
        end
    end

endmodule
