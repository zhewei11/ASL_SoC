module machine_timer #(
     parameter logic [31:0] BASE_ADDRESS = 32'h1003_4000
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        mmio_valid
    ,output logic        mmio_ready
    ,input  logic        mmio_write
    ,input  logic [31:0] mmio_addr
    ,input  logic [31:0] mmio_wdata
    ,input  logic [3:0]  mmio_wstrb
    ,output logic [31:0] mmio_rdata
    ,output logic        timer_interrupt
    ,output logic [63:0] mtime_value
);
    logic [63:0] mtime_q;
    logic [63:0] mtimecmp_q;
    logic [63:0] mtime_next;
    logic [63:0] mtimecmp_next;
    logic        write_handshake;

    function automatic logic [31:0] merge_wstrb(
         input logic [31:0] old_value, input logic [31:0] new_value
        ,input logic [3:0] strobe);
        integer lane;
        begin
            merge_wstrb = old_value;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (strobe[lane])
                    merge_wstrb[lane*8 +: 8] = new_value[lane*8 +: 8];
        end
    endfunction

    assign mmio_ready = 1'b1;
    assign write_handshake = mmio_valid && mmio_write;
    assign mtime_value = mtime_q;
    assign timer_interrupt = mtime_q >= mtimecmp_q;

    always_comb begin
        case (mmio_addr - BASE_ADDRESS)
            32'h0: mmio_rdata = mtimecmp_q[31:0];
            32'h4: mmio_rdata = mtimecmp_q[63:32];
            32'h8: mmio_rdata = mtime_q[31:0];
            32'hc: mmio_rdata = mtime_q[63:32];
            default: mmio_rdata = 32'd0;
        endcase
    end

    always_comb begin
        mtime_next = mtime_q + 1'b1;
        mtimecmp_next = mtimecmp_q;
        if (write_handshake) begin
            case (mmio_addr - BASE_ADDRESS)
                32'h0: mtimecmp_next[31:0] = merge_wstrb(
                    mtimecmp_q[31:0], mmio_wdata, mmio_wstrb);
                32'h4: mtimecmp_next[63:32] = merge_wstrb(
                    mtimecmp_q[63:32], mmio_wdata, mmio_wstrb);
                32'h8: begin
                    mtime_next = mtime_q;
                    mtime_next[31:0] = merge_wstrb(
                        mtime_q[31:0], mmio_wdata, mmio_wstrb);
                end
                32'hc: begin
                    mtime_next = mtime_q;
                    mtime_next[63:32] = merge_wstrb(
                        mtime_q[63:32], mmio_wdata, mmio_wstrb);
                end
                default: begin end
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mtime_q <= 64'd0;
            mtimecmp_q <= 64'hffff_ffff_ffff_ffff;
        end else begin
            mtime_q <= mtime_next;
            mtimecmp_q <= mtimecmp_next;
        end
    end
endmodule
