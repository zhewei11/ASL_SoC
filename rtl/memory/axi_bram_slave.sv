module axi_bram_slave #(
     parameter logic [31:0] BASE_ADDRESS = 32'h0000_0000
    ,parameter int unsigned MEMORY_BYTES = 8192
    ,parameter bit READ_ONLY = 1'b0
    ,parameter INIT_FILE = ""
) (
     input  logic        clk
    ,input  logic        rst
    // AXI4 AW slave interface
    ,input  logic [3:0]  s_axi_awid
    ,input  logic [31:0] s_axi_awaddr
    ,input  logic [7:0]  s_axi_awlen
    ,input  logic [2:0]  s_axi_awsize
    ,input  logic [1:0]  s_axi_awburst
    ,input  logic        s_axi_awvalid
    ,output logic        s_axi_awready
    // AXI4 W slave interface
    ,input  logic [31:0] s_axi_wdata
    ,input  logic [3:0]  s_axi_wstrb
    ,input  logic        s_axi_wlast
    ,input  logic        s_axi_wvalid
    ,output logic        s_axi_wready
    // AXI4 B slave interface
    ,output logic [3:0]  s_axi_bid
    ,output logic [1:0]  s_axi_bresp
    ,output logic        s_axi_bvalid
    ,input  logic        s_axi_bready
    // AXI4 AR slave interface
    ,input  logic [3:0]  s_axi_arid
    ,input  logic [31:0] s_axi_araddr
    ,input  logic [7:0]  s_axi_arlen
    ,input  logic [2:0]  s_axi_arsize
    ,input  logic [1:0]  s_axi_arburst
    ,input  logic        s_axi_arvalid
    ,output logic        s_axi_arready
    // AXI4 R slave interface
    ,output logic [3:0]  s_axi_rid
    ,output logic [31:0] s_axi_rdata
    ,output logic [1:0]  s_axi_rresp
    ,output logic        s_axi_rlast
    ,output logic        s_axi_rvalid
    ,input  logic        s_axi_rready
);

    localparam int unsigned WORD_COUNT = MEMORY_BYTES / 4;
    localparam int unsigned INDEX_WIDTH =
        (WORD_COUNT <= 1) ? 1 : $clog2(WORD_COUNT);

    typedef enum logic [2:0] {
        ST_IDLE, ST_READ_WAIT, ST_READ_DATA, ST_WRITE_DATA, ST_WRITE_RESP
    } state_t;
    state_t state;

    (* ram_style = "block" *) logic [31:0] memory [0:WORD_COUNT-1];
    logic [31:0] address_q;
    logic [7:0]  length_q;
    logic [7:0]  beat_q;
    logic [3:0]  id_q;
    logic        transaction_error_q;
    logic [31:0] read_data_q;
    logic        read_address_valid;
    logic        write_address_valid;
    logic        expected_last;
    integer      index;

    function automatic logic address_valid(input logic [31:0] address);
        logic [32:0] address_ext;
        logic [32:0] offset_ext;
        begin
            address_ext = {1'b0, address};
            offset_ext = address_ext - {1'b0, BASE_ADDRESS};
            address_valid = offset_ext <= MEMORY_BYTES - 4;
        end
    endfunction

    function automatic logic [INDEX_WIDTH-1:0] word_index(
         input logic [31:0] address
    );
        word_index = INDEX_WIDTH'((address - BASE_ADDRESS) >> 2);
    endfunction

    initial begin
        if (MEMORY_BYTES < 4 || (MEMORY_BYTES % 4) != 0)
            $error("MEMORY_BYTES must be a positive multiple of four");
        for (index = 0; index < WORD_COUNT; index = index + 1)
            memory[index] = 32'd0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    assign s_axi_awready = state == ST_IDLE;
    assign s_axi_arready = state == ST_IDLE && !s_axi_awvalid;
    assign s_axi_wready  = state == ST_WRITE_DATA;
    assign s_axi_bvalid  = state == ST_WRITE_RESP;
    assign s_axi_bid     = id_q;
    assign s_axi_bresp   = transaction_error_q ? 2'b10 : 2'b00;
    assign s_axi_rvalid  = state == ST_READ_DATA;
    assign s_axi_rid     = id_q;
    assign s_axi_rdata   = read_data_q;
    assign s_axi_rresp   = transaction_error_q ? 2'b10 : 2'b00;
    assign s_axi_rlast   = beat_q == length_q;
    assign expected_last = beat_q == length_q;
    assign read_address_valid = address_valid(s_axi_araddr) &&
                                s_axi_arsize == 3'd2 &&
                                s_axi_arburst == 2'b01;
    assign write_address_valid = address_valid(s_axi_awaddr) &&
                                 s_axi_awsize == 3'd2 &&
                                 s_axi_awburst == 2'b01;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            address_q <= 32'd0;
            length_q <= 8'd0;
            beat_q <= 8'd0;
            id_q <= 4'd0;
            transaction_error_q <= 1'b0;
            read_data_q <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    beat_q <= 8'd0;
                    transaction_error_q <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        address_q <= s_axi_awaddr;
                        length_q <= s_axi_awlen;
                        id_q <= s_axi_awid;
                        transaction_error_q <= !write_address_valid || READ_ONLY;
                        state <= ST_WRITE_DATA;
                    end else if (s_axi_arvalid && s_axi_arready) begin
                        address_q <= s_axi_araddr;
                        length_q <= s_axi_arlen;
                        id_q <= s_axi_arid;
                        transaction_error_q <= !read_address_valid;
                        state <= ST_READ_WAIT;
                    end
                end

                ST_READ_WAIT: begin
                    if (address_valid(address_q))
                        read_data_q <= memory[word_index(address_q)];
                    else
                        read_data_q <= 32'd0;
                    if (!address_valid(address_q))
                        transaction_error_q <= 1'b1;
                    state <= ST_READ_DATA;
                end

                ST_READ_DATA: begin
                    if (s_axi_rready) begin
                        if (expected_last) begin
                            state <= ST_IDLE;
                        end else begin
                            address_q <= address_q + 4;
                            beat_q <= beat_q + 1'b1;
                            state <= ST_READ_WAIT;
                        end
                    end
                end

                ST_WRITE_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (!transaction_error_q && address_valid(address_q)) begin
                            if (s_axi_wstrb[0])
                                memory[word_index(address_q)][7:0] <= s_axi_wdata[7:0];
                            if (s_axi_wstrb[1])
                                memory[word_index(address_q)][15:8] <= s_axi_wdata[15:8];
                            if (s_axi_wstrb[2])
                                memory[word_index(address_q)][23:16] <= s_axi_wdata[23:16];
                            if (s_axi_wstrb[3])
                                memory[word_index(address_q)][31:24] <= s_axi_wdata[31:24];
                        end
                        if (!address_valid(address_q) ||
                            (s_axi_wlast != expected_last))
                            transaction_error_q <= 1'b1;
                        if (expected_last || s_axi_wlast) begin
                            state <= ST_WRITE_RESP;
                        end else begin
                            address_q <= address_q + 4;
                            beat_q <= beat_q + 1'b1;
                        end
                    end
                end

                ST_WRITE_RESP: begin
                    if (s_axi_bready)
                        state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
