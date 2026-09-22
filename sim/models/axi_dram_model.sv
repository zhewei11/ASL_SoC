module axi_dram_model #(
     parameter logic [31:0] BASE_ADDRESS = 32'h2000_0000
    ,parameter int unsigned MEMORY_BYTES = 65_536
    ,parameter int unsigned READ_LATENCY_CYCLES = 0
    ,parameter int unsigned WRITE_RESPONSE_LATENCY_CYCLES = 0
    ,parameter int unsigned READY_STALL_CYCLES = 0
    ,parameter int unsigned RANDOM_READ_LATENCY_CYCLES = 0
    ,parameter int unsigned RANDOM_WRITE_LATENCY_CYCLES = 0
    ,parameter int unsigned RANDOM_READY_STALL_CYCLES = 0
    ,parameter logic [31:0] RANDOM_SEED = 32'h1ace_b00c
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic [3:0]  s_axi_awid
    ,input  logic [31:0] s_axi_awaddr
    ,input  logic [7:0]  s_axi_awlen
    ,input  logic [2:0]  s_axi_awsize
    ,input  logic [1:0]  s_axi_awburst
    ,input  logic        s_axi_awvalid
    ,output logic        s_axi_awready
    ,input  logic [31:0] s_axi_wdata
    ,input  logic [3:0]  s_axi_wstrb
    ,input  logic        s_axi_wlast
    ,input  logic        s_axi_wvalid
    ,output logic        s_axi_wready
    ,output logic [3:0]  s_axi_bid
    ,output logic [1:0]  s_axi_bresp
    ,output logic        s_axi_bvalid
    ,input  logic        s_axi_bready
    ,input  logic [3:0]  s_axi_arid
    ,input  logic [31:0] s_axi_araddr
    ,input  logic [7:0]  s_axi_arlen
    ,input  logic [2:0]  s_axi_arsize
    ,input  logic [1:0]  s_axi_arburst
    ,input  logic        s_axi_arvalid
    ,output logic        s_axi_arready
    ,output logic [3:0]  s_axi_rid
    ,output logic [31:0] s_axi_rdata
    ,output logic [1:0]  s_axi_rresp
    ,output logic        s_axi_rlast
    ,output logic        s_axi_rvalid
    ,input  logic        s_axi_rready
);

    logic [7:0] mem [0:MEMORY_BYTES-1];

    logic        have_aw;
    logic [3:0]  saved_awid;
    logic [31:0] saved_awaddr;
    logic [7:0]  saved_awlen;
    logic [7:0]  write_beat_index;
    logic        saved_aw_error;

    logic       write_response_pending;
    logic [3:0] pending_bid;
    logic [1:0] pending_bresp;
    integer     write_response_delay;
    integer     write_ready_stall;

    logic        read_active;
    logic        read_pending;
    logic [3:0]  saved_arid;
    logic [31:0] saved_araddr;
    logic [7:0]  saved_arlen;
    logic [7:0]  read_beat_index;
    logic        saved_ar_error;
    integer      read_response_delay;
    integer      read_ready_stall;

    integer offset;
    integer selected_delay;
    logic [31:0] read_lfsr;
    logic [31:0] write_lfsr;

    function automatic logic [31:0] lfsr_next(input logic [31:0] value);
        lfsr_next = {value[30:0],
                     value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    function automatic integer random_component(
         input logic [31:0] value
        ,input integer maximum
    );
        if (maximum == 0)
            random_component = 0;
        else
            random_component = value % (maximum + 1);
    endfunction

    function automatic logic address_valid(input logic [31:0] address);
        logic [32:0] address_ext;
        logic [32:0] limit_ext;
        begin
            address_ext = {1'b0, address};
            limit_ext = {1'b0, BASE_ADDRESS} + MEMORY_BYTES;
            address_valid = address_ext >= {1'b0, BASE_ADDRESS} &&
                            address_ext + 4 <= limit_ext;
        end
    endfunction

    function automatic logic burst_valid(
         input logic [31:0] address
        ,input logic [7:0]  length
    );
        logic [32:0] address_ext;
        logic [32:0] final_byte_ext;
        logic [32:0] limit_ext;
        logic [12:0] burst_bytes;
        begin
            address_ext = {1'b0, address};
            burst_bytes = ({5'd0, length} + 1'b1) << 2;
            final_byte_ext = address_ext + burst_bytes;
            limit_ext = {1'b0, BASE_ADDRESS} + MEMORY_BYTES;
            burst_valid = address[1:0] == 2'b00 &&
                          address_ext >= {1'b0, BASE_ADDRESS} &&
                          final_byte_ext <= limit_ext &&
                          ({1'b0, address[11:0]} + burst_bytes <= 13'd4096);
        end
    endfunction

    assign s_axi_awready = !have_aw && !s_axi_bvalid &&
                           !write_response_pending &&
                           (write_ready_stall == 0);
    assign s_axi_wready = have_aw && !s_axi_bvalid &&
                          !write_response_pending;
    assign s_axi_arready = !read_active && !s_axi_rvalid && !read_pending &&
                           (read_ready_stall == 0);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            have_aw <= 1'b0;
            saved_awid <= 4'd0;
            saved_awaddr <= 32'd0;
            saved_awlen <= 8'd0;
            write_beat_index <= 8'd0;
            saved_aw_error <= 1'b0;

            write_response_pending <= 1'b0;
            pending_bid <= 4'd0;
            pending_bresp <= 2'b00;
            write_response_delay <= 0;
            write_ready_stall <= 0;

            read_active <= 1'b0;
            read_pending <= 1'b0;
            saved_arid <= 4'd0;
            saved_araddr <= 32'd0;
            saved_arlen <= 8'd0;
            read_beat_index <= 8'd0;
            saved_ar_error <= 1'b0;
            read_response_delay <= 0;
            read_ready_stall <= 0;

            read_lfsr <= (RANDOM_SEED == 0) ? 32'h1 : RANDOM_SEED;
            write_lfsr <= (RANDOM_SEED == 0) ? 32'h5eed_1234 :
                                             (RANDOM_SEED ^ 32'ha5a5_5a5a);

            s_axi_bid <= 4'd0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b0;
            s_axi_rid <= 4'd0;
            s_axi_rdata <= 32'd0;
            s_axi_rresp <= 2'b00;
            s_axi_rlast <= 1'b0;
            s_axi_rvalid <= 1'b0;
        end else begin
            if (write_ready_stall > 0)
                write_ready_stall <= write_ready_stall - 1;
            if (read_ready_stall > 0)
                read_ready_stall <= read_ready_stall - 1;

            if (s_axi_awvalid && s_axi_awready) begin
                have_aw <= 1'b1;
                saved_awid <= s_axi_awid;
                saved_awaddr <= s_axi_awaddr;
                saved_awlen <= s_axi_awlen;
                write_beat_index <= 8'd0;
                saved_aw_error <= !burst_valid(s_axi_awaddr, s_axi_awlen) ||
                                  (s_axi_awsize != 3'd2) ||
                                  (s_axi_awburst != 2'b01);
            end

            if (s_axi_wvalid && s_axi_wready) begin
                write_lfsr <= lfsr_next(write_lfsr);
                offset = saved_awaddr - BASE_ADDRESS +
                         (write_beat_index << 2);

                if (!saved_aw_error && address_valid(
                    saved_awaddr + (write_beat_index << 2))) begin
                    if (s_axi_wstrb[0])
                        mem[offset] <= s_axi_wdata[7:0];
                    if (s_axi_wstrb[1])
                        mem[offset + 1] <= s_axi_wdata[15:8];
                    if (s_axi_wstrb[2])
                        mem[offset + 2] <= s_axi_wdata[23:16];
                    if (s_axi_wstrb[3])
                        mem[offset + 3] <= s_axi_wdata[31:24];
                end

                if (s_axi_wlast || (write_beat_index == saved_awlen)) begin
                    have_aw <= 1'b0;
                    selected_delay = WRITE_RESPONSE_LATENCY_CYCLES +
                        random_component(write_lfsr,
                                         RANDOM_WRITE_LATENCY_CYCLES);

                    if (selected_delay == 0) begin
                        s_axi_bid <= saved_awid;
                        s_axi_bresp <= (saved_aw_error ||
                            (s_axi_wlast !=
                             (write_beat_index == saved_awlen))) ?
                            2'b11 : 2'b00;
                        s_axi_bvalid <= 1'b1;
                    end else begin
                        pending_bid <= saved_awid;
                        pending_bresp <= (saved_aw_error ||
                            (s_axi_wlast !=
                             (write_beat_index == saved_awlen))) ?
                            2'b11 : 2'b00;
                        write_response_delay <= selected_delay;
                        write_response_pending <= 1'b1;
                    end
                end else begin
                    write_beat_index <= write_beat_index + 1'b1;
                end
            end

            if (write_response_pending) begin
                if (write_response_delay <= 1) begin
                    s_axi_bid <= pending_bid;
                    s_axi_bresp <= pending_bresp;
                    s_axi_bvalid <= 1'b1;
                    write_response_pending <= 1'b0;
                end else begin
                    write_response_delay <= write_response_delay - 1;
                end
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
                write_ready_stall <= READY_STALL_CYCLES +
                    random_component(write_lfsr,
                                     RANDOM_READY_STALL_CYCLES);
            end

            if (s_axi_arvalid && s_axi_arready) begin
                read_lfsr <= lfsr_next(read_lfsr);
                saved_arid <= s_axi_arid;
                saved_araddr <= s_axi_araddr;
                saved_arlen <= s_axi_arlen;
                read_beat_index <= 8'd0;
                saved_ar_error <= !burst_valid(s_axi_araddr, s_axi_arlen) ||
                                  (s_axi_arsize != 3'd2) ||
                                  (s_axi_arburst != 2'b01);
                read_active <= 1'b1;

                selected_delay = READ_LATENCY_CYCLES +
                    random_component(read_lfsr,
                                     RANDOM_READ_LATENCY_CYCLES);

                if (selected_delay == 0) begin
                    offset = s_axi_araddr - BASE_ADDRESS;
                    s_axi_rid <= s_axi_arid;
                    s_axi_rlast <= (s_axi_arlen == 0);
                    s_axi_rvalid <= 1'b1;

                    if (!burst_valid(s_axi_araddr, s_axi_arlen) ||
                        (s_axi_arsize != 3'd2) ||
                        (s_axi_arburst != 2'b01)) begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b11;
                    end else begin
                        s_axi_rdata <= {
                            mem[offset + 3], mem[offset + 2],
                            mem[offset + 1], mem[offset]
                        };
                        s_axi_rresp <= 2'b00;
                    end
                end else begin
                    read_response_delay <= selected_delay;
                    read_pending <= 1'b1;
                end
            end

            if (read_pending) begin
                if (read_response_delay <= 1) begin
                    offset = saved_araddr - BASE_ADDRESS;
                    s_axi_rid <= saved_arid;
                    s_axi_rlast <= (saved_arlen == 0);
                    s_axi_rvalid <= 1'b1;

                    if (saved_ar_error) begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b11;
                    end else begin
                        s_axi_rdata <= {
                            mem[offset + 3], mem[offset + 2],
                            mem[offset + 1], mem[offset]
                        };
                        s_axi_rresp <= 2'b00;
                    end
                    read_pending <= 1'b0;
                end else begin
                    read_response_delay <= read_response_delay - 1;
                end
            end

            if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    s_axi_rvalid <= 1'b0;
                    read_active <= 1'b0;
                    read_ready_stall <= READY_STALL_CYCLES +
                        random_component(read_lfsr,
                                         RANDOM_READY_STALL_CYCLES);
                end else begin
                    read_beat_index <= read_beat_index + 1'b1;
                    offset = saved_araddr - BASE_ADDRESS +
                             ((read_beat_index + 1'b1) << 2);
                    s_axi_rid <= saved_arid;
                    s_axi_rlast <= (read_beat_index + 1'b1 == saved_arlen);

                    if (saved_ar_error) begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b11;
                    end else begin
                        s_axi_rdata <= {
                            mem[offset + 3], mem[offset + 2],
                            mem[offset + 1], mem[offset]
                        };
                        s_axi_rresp <= 2'b00;
                    end
                end
            end
        end
    end

endmodule
