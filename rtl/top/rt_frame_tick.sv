module rt_frame_tick #(
     parameter int unsigned FRAME_CYCLES = 100_000
) (
     input  logic clk
    ,input  logic rst
    ,output logic tick
);

    localparam int unsigned COUNTER_WIDTH =
        (FRAME_CYCLES <= 1) ? 1 : $clog2(FRAME_CYCLES);
    logic [COUNTER_WIDTH-1:0] counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter <= '0;
            tick    <= 1'b0;
        end else begin
            tick <= 1'b0;
            if ((FRAME_CYCLES <= 1) ||
                (counter == COUNTER_WIDTH'(FRAME_CYCLES - 1))) begin
                counter <= '0;
                tick    <= 1'b1;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule
