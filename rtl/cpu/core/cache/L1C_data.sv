`include "rtos_core_config.svh"

module L1C_data (
     input  logic         clk
    ,input  logic         rst
    ,input  logic         invalidate

    // Core interface
    ,input  logic         core_req
    ,input  logic         core_write
    ,input  logic [31:0]  core_addr
    ,input  logic [31:0]  core_in
    ,input  logic [3:0]   core_wstrb
    ,input  logic         core_stall
    ,output logic         core_valid
    ,output logic [31:0]  core_out

    // Memory read interface
    ,output logic         mem_read_req
    ,output logic [31:0]  mem_read_addr
    ,input  logic         mem_read_ready
    ,input  logic         mem_line_valid
    ,input  logic [127:0] mem_line

    // Memory write interface
    ,output logic         mem_write_req
    ,output logic [31:0]  mem_write_addr
    ,output logic [31:0]  mem_write_data
    ,output logic [3:0]   mem_write_strb
    ,input  logic         mem_write_ready
    ,input  logic         mem_write_done
);

    // =============================================
    // Cache state and storage
    // =============================================
    localparam int CACHE_SETS = `RTOS_CORE_CACHE_SETS;
    localparam int CACHE_INDEX_BITS = $clog2(CACHE_SETS);
    localparam int CACHE_TAG_BITS = 30 - CACHE_INDEX_BITS - 2;

    typedef enum logic [2:0] {
        CACHE_IDLE,
        READ_REQUEST,
        READ_WAIT,
        READ_DONE,
        WRITE_REQUEST,
        WRITE_WAIT,
        WRITE_DONE
    } cache_state_t;

    cache_state_t state;

    logic [CACHE_TAG_BITS-1:0] tag_way0 [0:CACHE_SETS-1];
    logic [CACHE_TAG_BITS-1:0] tag_way1 [0:CACHE_SETS-1];
    logic [127:0]              data_way0 [0:CACHE_SETS-1];
    logic [127:0]              data_way1 [0:CACHE_SETS-1];
    logic [CACHE_SETS-1:0]     valid_way0;
    logic [CACHE_SETS-1:0]     valid_way1;
    logic [CACHE_SETS-1:0]     lru_victim;

    logic [31:0] request_addr_q;
    logic [31:0] write_data_q;
    logic [3:0]  write_strb_q;
    logic [31:0] read_data_q;
    logic        miss_way_q;
    logic        read_miss_killed_q;

    logic [CACHE_INDEX_BITS-1:0] lookup_index;
    logic [CACHE_TAG_BITS-1:0]   lookup_tag;
    logic [1:0]                  lookup_word;
    logic                        hit_way0;
    logic                        hit_way1;
    logic                        hit;
    logic                        victim_way;
    logic [127:0]                hit_line;

    // These counters are intentionally visible in the waveform so the
    // data-cache hit rate can be reported after simulation.
    logic [31:0] access_count;
    logic [31:0] hit_count;

    integer index_i;

    function automatic logic [31:0] select_word(
         input logic [127:0] line
        ,input logic [1:0]   word_index
    );
        case (word_index)
            2'd0: select_word = line[31:0];
            2'd1: select_word = line[63:32];
            2'd2: select_word = line[95:64];
            default: select_word = line[127:96];
        endcase
    endfunction

    function automatic logic [127:0] merge_store(
         input logic [127:0] line
        ,input logic [1:0]   word_index
        ,input logic [31:0]  write_data
        ,input logic [3:0]   write_strb
    );
        logic [127:0] merged_line;
        integer       byte_i;
        begin
            merged_line = line;
            for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1) begin
                if (write_strb[byte_i])
                    merged_line[(word_index * 32) + (byte_i * 8) +: 8] =
                        write_data[(byte_i * 8) +: 8];
            end
            merge_store = merged_line;
        end
    endfunction

    // =============================================
    // Lookup
    // =============================================
    assign lookup_tag   = core_addr[29:CACHE_INDEX_BITS+2];
    assign lookup_index = core_addr[CACHE_INDEX_BITS+1:2];
    assign lookup_word  = core_addr[1:0];

    assign hit_way0 = valid_way0[lookup_index] &&
                      (tag_way0[lookup_index] == lookup_tag);
    assign hit_way1 = valid_way1[lookup_index] &&
                      (tag_way1[lookup_index] == lookup_tag);
    assign hit       = hit_way0 || hit_way1;
    assign hit_line  = hit_way0 ? data_way0[lookup_index] :
                                   data_way1[lookup_index];

    // =============================================
    // Core and memory interfaces
    // =============================================
    always_comb begin
        if (!valid_way0[lookup_index])
            victim_way = 1'b0;
        else if (!valid_way1[lookup_index])
            victim_way = 1'b1;
        else
            victim_way = lru_victim[lookup_index];
    end

    always_comb begin
        core_valid = 1'b0;
        core_out   = 32'd0;

        if (!invalidate) begin
            case (state)
                CACHE_IDLE: begin
                    if (!core_req)
                        core_valid = 1'b1;
                    else if (!core_write && hit) begin
                        core_valid = 1'b1;
                        core_out   = select_word(hit_line, lookup_word);
                    end
                end

                READ_DONE: begin
                    core_valid = 1'b1;
                    core_out   = read_data_q;
                end

                WRITE_DONE: begin
                    core_valid = 1'b1;
                end

                default: begin
                    core_valid = 1'b0;
                end
            endcase
        end
    end

    assign mem_read_req  = (state == READ_REQUEST);
    assign mem_read_addr = {request_addr_q[29:2], 4'b0000};

    assign mem_write_req  = (state == WRITE_REQUEST);
    assign mem_write_addr = {request_addr_q[29:0], 2'b00};
    assign mem_write_data = write_data_q;
    assign mem_write_strb = write_strb_q;

    // =============================================
    // Cache controller
    // =============================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= CACHE_IDLE;
            valid_way0     <= '0;
            valid_way1     <= '0;
            lru_victim     <= '0;
            request_addr_q <= 32'd0;
            write_data_q   <= 32'd0;
            write_strb_q   <= 4'd0;
            read_data_q    <= 32'd0;
            miss_way_q     <= 1'b0;
            read_miss_killed_q <= 1'b0;
            access_count   <= 32'd0;
            hit_count      <= 32'd0;

            for (index_i = 0; index_i < CACHE_SETS;
                 index_i = index_i + 1) begin
                tag_way0[index_i] <= '0;
                tag_way1[index_i] <= '0;
            end
        end else begin
            // DMA writes do not snoop this cache.  Clear all valid bits on
            // DMA completion so subsequent loads fetch the updated memory.
            if (invalidate) begin
                valid_way0 <= '0;
                valid_way1 <= '0;
                lru_victim <= '0;

                if ((state == READ_REQUEST) || (state == READ_WAIT))
                    read_miss_killed_q <= 1'b1;
                else if (state == READ_DONE)
                    state <= CACHE_IDLE;
            end

            case (state)
                CACHE_IDLE: begin
                    if (core_req && !invalidate) begin
                        if (core_write) begin
                            access_count   <= access_count + 32'd1;
                            if (hit)
                                hit_count <= hit_count + 32'd1;

                            request_addr_q <= core_addr;
                            write_data_q   <= core_in;
                            write_strb_q   <= core_wstrb;

                            // Write-through on a hit.  A write miss does not
                            // allocate a new line.
                            if (hit_way0) begin
                                data_way0[lookup_index] <= merge_store(
                                    data_way0[lookup_index],
                                    lookup_word,
                                    core_in,
                                    core_wstrb
                                );
                                lru_victim[lookup_index] <= 1'b1;
                            end else if (hit_way1) begin
                                data_way1[lookup_index] <= merge_store(
                                    data_way1[lookup_index],
                                    lookup_word,
                                    core_in,
                                    core_wstrb
                                );
                                lru_victim[lookup_index] <= 1'b0;
                            end

                            state <= WRITE_REQUEST;
                        end else if (hit) begin
                            if (!core_stall) begin
                                access_count <= access_count + 32'd1;
                                hit_count    <= hit_count + 32'd1;

                                if (hit_way0)
                                    lru_victim[lookup_index] <= 1'b1;
                                else
                                    lru_victim[lookup_index] <= 1'b0;
                            end
                        end else begin
                            access_count   <= access_count + 32'd1;
                            request_addr_q <= core_addr;
                            miss_way_q     <= victim_way;
                            read_miss_killed_q <= 1'b0;
                            state          <= READ_REQUEST;
                        end
                    end
                end

                READ_REQUEST: begin
                    if (mem_read_ready)
                        state <= READ_WAIT;
                end

                READ_WAIT: begin
                    if (mem_line_valid) begin
                        if (invalidate || read_miss_killed_q) begin
                            // The core keeps its request asserted while
                            // stalled, so return to IDLE and retry the load.
                            state <= CACHE_IDLE;
                        end else begin
                            read_data_q <= select_word(
                                mem_line, request_addr_q[1:0]
                            );

                            if (!miss_way_q) begin
                                tag_way0[request_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    request_addr_q[29:CACHE_INDEX_BITS+2];
                                data_way0[request_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    mem_line;
                                valid_way0[request_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b1;
                                lru_victim[request_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b1;
                            end else begin
                                tag_way1[request_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    request_addr_q[29:CACHE_INDEX_BITS+2];
                                data_way1[request_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    mem_line;
                                valid_way1[request_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b1;
                                lru_victim[request_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b0;
                            end

                            state <= READ_DONE;
                        end

                        read_miss_killed_q <= 1'b0;
                    end
                end

                READ_DONE: begin
                    if (!core_stall)
                        state <= CACHE_IDLE;
                end

                WRITE_REQUEST: begin
                    if (mem_write_ready)
                        state <= WRITE_WAIT;
                end

                WRITE_WAIT: begin
                    if (mem_write_done)
                        state <= WRITE_DONE;
                end

                WRITE_DONE: begin
                    if (!core_stall)
                        state <= CACHE_IDLE;
                end

                default: state <= CACHE_IDLE;
            endcase
        end
    end

endmodule
