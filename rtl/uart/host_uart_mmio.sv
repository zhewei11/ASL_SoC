module host_uart_mmio #(
     parameter int unsigned CLOCK_HZ = 100_000_000
    ,parameter int unsigned BAUD_RATE = 115_200
) (
     input  logic clk
    ,input  logic rst
    ,input  logic mmio_valid
    ,output logic mmio_ready
    ,input  logic mmio_write
    ,input  logic [31:0] mmio_addr
    ,input  logic [31:0] mmio_wdata
    ,input  logic [3:0] mmio_wstrb
    ,output logic [31:0] mmio_rdata
    ,input  logic uart_rx
    ,output logic uart_tx
    ,output logic irq
);
    localparam int unsigned CLKS_PER_BIT_RAW =
        (BAUD_RATE == 0) ? 2 :
        (CLOCK_HZ + BAUD_RATE / 2) / BAUD_RATE;
    localparam int unsigned CLKS_PER_BIT =
        (CLKS_PER_BIT_RAW < 2) ? 2 : CLKS_PER_BIT_RAW;
    localparam int unsigned COUNTER_WIDTH = $clog2(CLKS_PER_BIT + 1);

    localparam logic [7:0] REG_ID         = 8'h00;
    localparam logic [7:0] REG_STATUS     = 8'h04;
    localparam logic [7:0] REG_TX_DATA    = 8'h08;
    localparam logic [7:0] REG_RX_DATA    = 8'h0C;
    localparam logic [7:0] REG_DIVISOR    = 8'h10;
    localparam logic [7:0] REG_IRQ_ENABLE = 8'h14;
    localparam logic [7:0] REG_IRQ_STATUS = 8'h18;

    logic [7:0] register_offset;
    logic [2:0] irq_enable_q;
    logic       tx_done_pending_q;
    logic       framing_error_q;
    logic       overrun_error_q;

    logic                     tx_busy_q;
    logic [9:0]               tx_shift_q;
    logic [3:0]               tx_bit_q;
    logic [COUNTER_WIDTH-1:0] tx_count_q;
    logic                     tx_start;
    logic                     tx_done_pulse;

    logic                     rx_meta_q;
    logic                     rx_sync_q;
    logic                     rx_busy_q;
    logic [7:0]               rx_shift_q;
    logic [3:0]               rx_bit_q;
    logic [COUNTER_WIDTH-1:0] rx_count_q;
    logic [7:0]               rx_data_q;
    logic                     rx_valid_q;
    logic                     rx_data_pulse;
    logic                     framing_pulse;

    logic       tx_access;
    logic       rx_access;
    logic       handshake;
    logic [2:0] irq_status;

    // initial begin
    //     if (CLOCK_HZ == 0 || BAUD_RATE == 0)
    //         $error("CLOCK_HZ and BAUD_RATE must be non-zero");
    // end

    assign register_offset = mmio_addr[7:0];
    assign tx_access = mmio_valid && mmio_write &&
                       register_offset == REG_TX_DATA;
    assign rx_access = mmio_valid && !mmio_write &&
                       register_offset == REG_RX_DATA;
    assign mmio_ready = tx_access ? !tx_busy_q :
                        rx_access ? rx_valid_q : 1'b1;
    assign handshake = mmio_valid && mmio_ready;
    assign tx_start = handshake && tx_access && mmio_wstrb[0];
    assign irq_status = {framing_error_q || overrun_error_q,
                         rx_valid_q, tx_done_pending_q};
    assign irq = |(irq_status & irq_enable_q);
    assign uart_tx = tx_busy_q ? tx_shift_q[0] : 1'b1;

    always_comb begin
        case (register_offset)
            REG_ID: mmio_rdata = 32'h5541_5254;
            REG_STATUS: mmio_rdata = {
                26'd0, irq, overrun_error_q, framing_error_q,
                rx_valid_q, tx_busy_q, !tx_busy_q
            };
            REG_RX_DATA: mmio_rdata = {24'd0, rx_data_q};
            REG_DIVISOR: mmio_rdata = CLKS_PER_BIT;
            REG_IRQ_ENABLE: mmio_rdata = {29'd0, irq_enable_q};
            REG_IRQ_STATUS: mmio_rdata = {29'd0, irq_status};
            default: mmio_rdata = 32'd0;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_busy_q <= 1'b0;
            tx_shift_q <= 10'h3FF;
            tx_bit_q <= 4'd0;
            tx_count_q <= '0;
            tx_done_pulse <= 1'b0;
        end else begin
            tx_done_pulse <= 1'b0;
            if (tx_start) begin
                tx_busy_q <= 1'b1;
                tx_shift_q <= {1'b1, mmio_wdata[7:0], 1'b0};
                tx_bit_q <= 4'd0;
                tx_count_q <= COUNTER_WIDTH'(CLKS_PER_BIT - 1);
            end else if (tx_busy_q) begin
                if (tx_count_q == 0) begin
                    if (tx_bit_q == 4'd9) begin
                        tx_busy_q <= 1'b0;
                        tx_done_pulse <= 1'b1;
                    end else begin
                        tx_shift_q <= {1'b1, tx_shift_q[9:1]};
                        tx_bit_q <= tx_bit_q + 1'b1;
                        tx_count_q <= COUNTER_WIDTH'(CLKS_PER_BIT - 1);
                    end
                end else begin
                    tx_count_q <= tx_count_q - 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_meta_q <= 1'b1;
            rx_sync_q <= 1'b1;
            rx_busy_q <= 1'b0;
            rx_shift_q <= 8'd0;
            rx_bit_q <= 4'd0;
            rx_count_q <= '0;
            rx_data_pulse <= 1'b0;
            framing_pulse <= 1'b0;
        end else begin
            rx_meta_q <= uart_rx;
            rx_sync_q <= rx_meta_q;
            rx_data_pulse <= 1'b0;
            framing_pulse <= 1'b0;

            if (!rx_busy_q) begin
                if (!rx_sync_q) begin
                    rx_busy_q <= 1'b1;
                    rx_bit_q <= 4'd0;
                    rx_count_q <= COUNTER_WIDTH'(CLKS_PER_BIT / 2);
                end
            end else if (rx_count_q != 0) begin
                rx_count_q <= rx_count_q - 1'b1;
            end else if (rx_bit_q == 0) begin
                if (!rx_sync_q) begin
                    rx_bit_q <= 4'd1;
                    rx_count_q <= COUNTER_WIDTH'(CLKS_PER_BIT - 1);
                end else begin
                    rx_busy_q <= 1'b0;
                end
            end else if (rx_bit_q <= 8) begin
                rx_shift_q[3'(rx_bit_q - 1'b1)] <= rx_sync_q;
                rx_bit_q <= rx_bit_q + 1'b1;
                rx_count_q <= COUNTER_WIDTH'(CLKS_PER_BIT - 1);
            end else begin
                if (rx_sync_q)
                    rx_data_pulse <= 1'b1;
                else
                    framing_pulse <= 1'b1;
                rx_busy_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            irq_enable_q <= 3'd0;
            tx_done_pending_q <= 1'b0;
            framing_error_q <= 1'b0;
            overrun_error_q <= 1'b0;
            rx_data_q <= 8'd0;
            rx_valid_q <= 1'b0;
        end else begin
            if (tx_done_pulse)
                tx_done_pending_q <= 1'b1;
            if (framing_pulse)
                framing_error_q <= 1'b1;
            if (rx_data_pulse) begin
                if (rx_valid_q)
                    overrun_error_q <= 1'b1;
                else begin
                    rx_data_q <= rx_shift_q;
                    rx_valid_q <= 1'b1;
                end
            end
            if (handshake && rx_access)
                rx_valid_q <= 1'b0;

            if (handshake && mmio_write && |mmio_wstrb) begin
                case (register_offset)
                    REG_IRQ_ENABLE: if (mmio_wstrb[0])
                        irq_enable_q <= mmio_wdata[2:0];
                    REG_IRQ_STATUS: if (mmio_wstrb[0]) begin
                        if (mmio_wdata[0]) tx_done_pending_q <= 1'b0;
                        if (mmio_wdata[2]) begin
                            framing_error_q <= 1'b0;
                            overrun_error_q <= 1'b0;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
