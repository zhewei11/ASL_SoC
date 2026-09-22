`include "rtos_core_config.svh"

module L1C_inst (
     input  logic         clk
    ,input  logic         rst
    ,input  logic         invalidate

    // Core interface
    ,input  logic [31:0]  core_addr
    ,input  logic         core_flush
    ,input  logic         core_stall
    ,input  logic         core_access_allowed
    ,output logic         core_valid
    ,output logic [31:0]  core_out

    // Memory interface
    ,output logic         mem_req
    ,output logic [31:0]  mem_addr
    ,input  logic         mem_ready
    ,input  logic         mem_line_valid
    ,input  logic [127:0] mem_line
);

    // =============================================
    // Cache state and storage
    // =============================================
    localparam int CACHE_SETS = `RTOS_CORE_CACHE_SETS;
    localparam int CACHE_INDEX_BITS = $clog2(CACHE_SETS);
    localparam int CACHE_TAG_BITS = 30 - CACHE_INDEX_BITS - 2;

    typedef enum logic [1:0] {
        CACHE_IDLE,
        MISS_REQUEST,
        MISS_WAIT
    } cache_state_t;

    cache_state_t state;

    logic [CACHE_TAG_BITS-1:0] tag_way0 [0:CACHE_SETS-1];
    logic [CACHE_TAG_BITS-1:0] tag_way1 [0:CACHE_SETS-1];
    logic [127:0]              data_way0 [0:CACHE_SETS-1];
    logic [127:0]              data_way1 [0:CACHE_SETS-1];
    logic [CACHE_SETS-1:0]     valid_way0;
    logic [CACHE_SETS-1:0]     valid_way1;
    logic [CACHE_SETS-1:0]     lru_victim;

    logic [31:0]           miss_addr_q;
    logic                  miss_way_q;
    logic                  miss_is_prefetch_q;
    logic                  miss_killed_q;
    logic [CACHE_SETS-1:0] prefetched_way0;
    logic [CACHE_SETS-1:0] prefetched_way1;

    logic [CACHE_INDEX_BITS-1:0] lookup_index;
    logic [CACHE_TAG_BITS-1:0]   lookup_tag;
    logic [1:0]                  lookup_word;
    logic                        hit_way0;
    logic                        hit_way1;
    logic                        hit;
    logic                        victim_way;
    logic [127:0]                hit_line;
    logic [31:0]                 next_line_addr;
    logic [CACHE_INDEX_BITS-1:0] next_line_index;
    logic [CACHE_TAG_BITS-1:0]   next_line_tag;
    logic                        next_line_resident;
    logic                        next_line_victim_way;
    logic                        core_accept;

    // These counters are intentionally visible in the waveform so the
    // instruction-cache hit rate can be reported after simulation.
    logic [31:0] access_count;
    logic [31:0] hit_count;
    logic [31:0] prefetch_request_count;
    logic [31:0] prefetch_useful_count;

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

    // =============================================
    // Lookup
    // =============================================
    // core_addr is the word address produced by core.sv. This is equivalent
    // to byte-address fields [31:9] tag, [8:4] set and [3:2] word offset.
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

    // Sequential next-line prefetch. core_addr is a word address, therefore
    // adding one to [29:2] advances by one 16-byte cache line.
    assign next_line_addr     = {2'b00, core_addr[29:2] + 28'd1, 2'b00};
    assign next_line_index =
        next_line_addr[CACHE_INDEX_BITS+1:2];
    assign next_line_tag =
        next_line_addr[29:CACHE_INDEX_BITS+2];
    assign next_line_resident =
        (valid_way0[next_line_index] &&
         (tag_way0[next_line_index] == next_line_tag)) ||
        (valid_way1[next_line_index] &&
         (tag_way1[next_line_index] == next_line_tag));

    always_comb begin
        if (!valid_way0[lookup_index])
            victim_way = 1'b0;
        else if (!valid_way1[lookup_index])
            victim_way = 1'b1;
        else
            victim_way = lru_victim[lookup_index];
    end

    always_comb begin
        if (!valid_way0[next_line_index])
            next_line_victim_way = 1'b0;
        else if (!valid_way1[next_line_index])
            next_line_victim_way = 1'b1;
        else
            next_line_victim_way = lru_victim[next_line_index];
    end

    // =============================================
    // Core and memory interfaces
    // =============================================
    // A flush discards the IF/ID value in core.sv, so it must not feed back
    // into the cache hit-valid path.  Keeping core_valid independent of
    // core_flush avoids a trap/flush -> im_valid -> CSR execute loop.
    // Demand hits remain available while a prefetch transaction is in
    // flight. A demand miss waits until the single AXI read port is free.
    assign core_valid = core_access_allowed && !invalidate && hit;
    assign core_out   = select_word(hit_line, lookup_word);
    assign core_accept = core_valid && !core_stall && !core_flush;

    assign mem_req  = (state == MISS_REQUEST);
    assign mem_addr = {miss_addr_q[29:2], 4'b0000};

    // =============================================
    // Cache controller
    // =============================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= CACHE_IDLE;
            valid_way0   <= '0;
            valid_way1   <= '0;
            lru_victim   <= '0;
            miss_addr_q  <= 32'd0;
            miss_way_q   <= 1'b0;
            miss_is_prefetch_q <= 1'b0;
            miss_killed_q <= 1'b0;
            prefetched_way0 <= '0;
            prefetched_way1 <= '0;
            access_count <= 32'd0;
            hit_count    <= 32'd0;
            prefetch_request_count <= 32'd0;
            prefetch_useful_count  <= 32'd0;

            for (index_i = 0; index_i < CACHE_SETS;
                 index_i = index_i + 1) begin
                tag_way0[index_i] <= '0;
                tag_way1[index_i] <= '0;
            end
        end else begin
            // DMA writes bypass the CPU caches.  Invalidate all resident
            // lines when the DMA-completion event arrives so instruction
            // fetches cannot observe pre-DMA contents.
            if (invalidate) begin
                valid_way0 <= '0;
                valid_way1 <= '0;
                lru_victim <= '0;
                prefetched_way0 <= '0;
                prefetched_way1 <= '0;
                if (state != CACHE_IDLE)
                    miss_killed_q <= 1'b1;
            end

            // Hits can be consumed while a background prefetch is active.
            if (core_accept && !invalidate) begin
                access_count <= access_count + 32'd1;
                hit_count    <= hit_count + 32'd1;

                if (hit_way0) begin
                    lru_victim[lookup_index] <= 1'b1;
                    if (prefetched_way0[lookup_index]) begin
                        prefetched_way0[lookup_index] <= 1'b0;
                        prefetch_useful_count <= prefetch_useful_count + 32'd1;
                    end
                end else begin
                    lru_victim[lookup_index] <= 1'b0;
                    if (prefetched_way1[lookup_index]) begin
                        prefetched_way1[lookup_index] <= 1'b0;
                        prefetch_useful_count <= prefetch_useful_count + 32'd1;
                    end
                end
            end

            case (state)
                CACHE_IDLE: begin
                    if (core_access_allowed && !core_flush && !invalidate) begin
                        if (hit) begin
                            // Start the next-line request as soon as the
                            // current instruction is accepted. The remaining
                            // words of the current line can still hit while
                            // this transaction proceeds in the background.
                            if (`RTOS_CORE_ICACHE_PREFETCH_ENABLE &&
                                core_accept && !next_line_resident) begin
                                miss_addr_q        <= next_line_addr;
                                miss_way_q         <= next_line_victim_way;
                                miss_is_prefetch_q <= 1'b1;
                                miss_killed_q      <= 1'b0;
                                prefetch_request_count <=
                                    prefetch_request_count + 32'd1;
                                state <= MISS_REQUEST;
                            end
                        end else begin
                            miss_addr_q        <= core_addr;
                            miss_way_q         <= victim_way;
                            miss_is_prefetch_q <= 1'b0;
                            miss_killed_q      <= 1'b0;
                            access_count       <= access_count + 32'd1;
                            state              <= MISS_REQUEST;
                        end
                    end
                end

                MISS_REQUEST: begin
                    if (mem_ready)
                        state <= MISS_WAIT;
                end

                MISS_WAIT: begin
                    if (mem_line_valid) begin
                        // An invalidate may arrive several cycles before the
                        // AXI refill. Remember it and consume, but never
                        // install, the stale response.
                        if (!invalidate && !miss_killed_q) begin
                            if (!miss_way_q) begin
                                tag_way0[miss_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    miss_addr_q[29:CACHE_INDEX_BITS+2];
                                data_way0[miss_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    mem_line;
                                valid_way0[miss_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b1;
                                lru_victim[miss_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b1;
                                prefetched_way0[miss_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    miss_is_prefetch_q;
                            end else begin
                                tag_way1[miss_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    miss_addr_q[29:CACHE_INDEX_BITS+2];
                                data_way1[miss_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    mem_line;
                                valid_way1[miss_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b1;
                                lru_victim[miss_addr_q[CACHE_INDEX_BITS+1:2]] <= 1'b0;
                                prefetched_way1[miss_addr_q[CACHE_INDEX_BITS+1:2]] <=
                                    miss_is_prefetch_q;
                            end
                        end

                        miss_is_prefetch_q <= 1'b0;
                        miss_killed_q <= 1'b0;
                        state <= CACHE_IDLE;
                    end
                end

                default: state <= CACHE_IDLE;
            endcase
        end
    end

endmodule
