module cnn_accelerator_stub #(
     parameter int unsigned POSE_COUNT      = 24
    ,parameter int unsigned LATENCY_CYCLES  = 32
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        start
    ,input  logic [31:0] input_address
    ,input  logic [31:0] input_bytes
    ,input  logic        test_class_valid
    ,input  logic [7:0]  test_class_id
    ,input  logic [7:0]  test_confidence
    ,input  logic        clear_irq
    ,output logic        busy
    ,output logic        done
    ,output logic        error
    ,output logic [7:0]  class_id
    ,output logic [7:0]  confidence
    ,output logic [31:0] result_sequence
    ,output logic        irq

    ,output logic        dma_start
    ,output logic [31:0] dma_input_address
    ,output logic [31:0] dma_input_bytes
    ,input  logic        dma_done
    ,input  logic        dma_error
    ,input  logic [31:0] dma_checksum
);

    localparam int unsigned COUNTER_WIDTH =
        (LATENCY_CYCLES <= 1) ? 1 : $clog2(LATENCY_CYCLES + 1);

    logic [COUNTER_WIDTH-1:0] latency_counter;
    logic [7:0]               pending_class;
    logic [7:0]               pending_confidence;
    logic                     latched_test_class_valid;
    logic [7:0]               latched_test_class_id;
    logic [7:0]               latched_test_confidence;
    logic                     compute_active;

    initial begin
        if (POSE_COUNT == 0 || LATENCY_CYCLES == 0)
            $error("CNN stub parameters must be non-zero");
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy                     <= 1'b0;
            done                     <= 1'b0;
            error                    <= 1'b0;
            class_id                 <= 8'd0;
            confidence               <= 8'd0;
            result_sequence          <= 32'd0;
            irq                      <= 1'b0;
            latency_counter          <= '0;
            pending_class            <= 8'd0;
            pending_confidence       <= 8'd0;
            latched_test_class_valid <= 1'b0;
            latched_test_class_id    <= 8'd0;
            latched_test_confidence  <= 8'd0;
            dma_input_address        <= 32'd0;
            dma_input_bytes          <= 32'd0;
            dma_start                <= 1'b0;
            compute_active           <= 1'b0;
        end else begin
            done      <= 1'b0;
            dma_start <= 1'b0;

            if (clear_irq) begin
                irq   <= 1'b0;
                error <= 1'b0;
            end

            if (start) begin
                if (busy) begin
                    error <= 1'b1;
                    irq   <= 1'b1;
                end else begin
                    busy                     <= 1'b1;
                    error                    <= 1'b0;
                    compute_active           <= 1'b0;
                    latency_counter          <= '0;
                    latched_test_class_valid <= test_class_valid;
                    latched_test_class_id    <= test_class_id;
                    latched_test_confidence  <= test_confidence;
                    dma_input_address        <= input_address;
                    dma_input_bytes          <= input_bytes;
                    dma_start                <= 1'b1;
                end
            end else if (busy && !compute_active && dma_done) begin
                if (dma_error) begin
                    busy  <= 1'b0;
                    error <= 1'b1;
                    irq   <= 1'b1;
                end else begin
                    compute_active  <= 1'b1;
                    latency_counter <= COUNTER_WIDTH'(LATENCY_CYCLES);
                    pending_class <= latched_test_class_valid ?
                        latched_test_class_id :
                        ((POSE_COUNT == 0) ? 8'd0 :
                         8'(dma_checksum % POSE_COUNT));
                    pending_confidence <= latched_test_class_valid ?
                        latched_test_confidence : 8'd128;
                end
            end else if (busy && compute_active) begin
                if (latency_counter <= 1) begin
                    busy            <= 1'b0;
                    done            <= 1'b1;
                    irq             <= 1'b1;
                    class_id        <= pending_class;
                    confidence      <= pending_confidence;
                    result_sequence <= result_sequence + 1'b1;
                    latency_counter <= '0;
                    compute_active  <= 1'b0;
                end else begin
                    latency_counter <= latency_counter - 1'b1;
                end
            end
        end
    end

endmodule
