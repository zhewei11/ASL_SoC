// Fully-pipelined RV32M multiplier.
//
// The datapath is split into operand preparation, four 16x16 partial
// products, partial-product reduction, and result selection. A request may
// be accepted on every cycle and its result is returned three cycles later.
// flush clears every valid bit so a killed instruction cannot later write a
// stale result.
module multiplier (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    ,input  logic [31:0] operand_a
    ,input  logic [31:0] operand_b
    ,input  logic [1:0]  mul_type
    ,input  logic        start
    ,input  logic [31:0] mac_addend
    ,output logic [31:0] result
    ,output logic        valid
);

    localparam logic [1:0] MUL   = 2'b00;
    localparam logic [1:0] MULHU = 2'b11;

    // MUL only observes the low word, so treating both operands as signed is
    // equivalent modulo 2^32. High-word variants use their architectural
    // signedness explicitly.
    // Encoding: 00=MUL, 01=MULH, 10=MULHSU, 11=MULHU.  Bit 1 therefore
    // selects an unsigned B operand; only 11 also makes A unsigned.
    wire operand_a_signed = (mul_type != MULHU);
    wire operand_b_signed = !mul_type[1];
    wire [31:0] operand_a_magnitude =
        (operand_a_signed && operand_a[31])
        ? (~operand_a + 32'd1) : operand_a;
    wire [31:0] operand_b_magnitude =
        (operand_b_signed && operand_b[31])
        ? (~operand_b + 32'd1) : operand_b;
    wire product_negative =
        (operand_a_signed && operand_a[31]) ^
        (operand_b_signed && operand_b[31]);

    // Stage 0: prepared operands and request metadata.
    logic        valid_s0;
    logic [15:0] a_lo_s0;
    logic [15:0] a_hi_s0;
    logic [15:0] b_lo_s0;
    logic [15:0] b_hi_s0;
    logic        negative_s0;
    logic [1:0]  type_s0;
    logic [31:0] addend_s0;

    // Stage 1: four small products. These map cleanly to DSP blocks and
    // avoid one 32x32 combinational multiplier between registers.
    logic        valid_s1;
    logic [31:0] pp_ll_s1;
    logic [31:0] pp_lh_s1;
    logic [31:0] pp_hl_s1;
    logic [31:0] pp_hh_s1;
    logic        negative_s1;
    logic [1:0]  type_s1;
    logic [31:0] addend_s1;

    // Stage 2: partial-product reduction.
    logic        valid_s2;
    logic [63:0] magnitude_s2;
    logic        negative_s2;
    logic [1:0]  type_s2;
    logic [31:0] addend_s2;

    wire [32:0] cross_sum_s1 = {1'b0, pp_lh_s1} +
                                {1'b0, pp_hl_s1};
    wire [63:0] magnitude_sum_s1 =
        {32'd0, pp_ll_s1} +
        ({31'd0, cross_sum_s1} << 16) +
        ({32'd0, pp_hh_s1} << 32);

    // Stage 3: apply the product sign, optional MAC addend, and word select.
    wire [63:0] signed_product_s2 = negative_s2
        ? (~magnitude_s2 + 64'd1) : magnitude_s2;
    wire [31:0] product_with_addend_s2 =
        signed_product_s2[31:0] + addend_s2;
    wire [31:0] selected_result_s2 = (type_s2 == MUL)
        ? product_with_addend_s2 : signed_product_s2[63:32];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_s0     <= 1'b0;
            valid_s1     <= 1'b0;
            valid_s2     <= 1'b0;
            valid        <= 1'b0;
            result       <= 32'd0;
            a_lo_s0      <= 16'd0;
            a_hi_s0      <= 16'd0;
            b_lo_s0      <= 16'd0;
            b_hi_s0      <= 16'd0;
            negative_s0  <= 1'b0;
            type_s0      <= MUL;
            addend_s0    <= 32'd0;
            pp_ll_s1     <= 32'd0;
            pp_lh_s1     <= 32'd0;
            pp_hl_s1     <= 32'd0;
            pp_hh_s1     <= 32'd0;
            negative_s1  <= 1'b0;
            type_s1      <= MUL;
            addend_s1    <= 32'd0;
            magnitude_s2 <= 64'd0;
            negative_s2  <= 1'b0;
            type_s2      <= MUL;
            addend_s2    <= 32'd0;
        end else if (flush) begin
            valid_s0 <= 1'b0;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid    <= 1'b0;
        end else begin
            valid_s0 <= start;
            valid_s1 <= valid_s0;
            valid_s2 <= valid_s1;
            valid    <= valid_s2;

            if (start) begin
                a_lo_s0     <= operand_a_magnitude[15:0];
                a_hi_s0     <= operand_a_magnitude[31:16];
                b_lo_s0     <= operand_b_magnitude[15:0];
                b_hi_s0     <= operand_b_magnitude[31:16];
                negative_s0 <= product_negative;
                type_s0     <= mul_type;
                addend_s0   <= mac_addend;
            end

            if (valid_s0) begin
                pp_ll_s1    <= a_lo_s0 * b_lo_s0;
                pp_lh_s1    <= a_lo_s0 * b_hi_s0;
                pp_hl_s1    <= a_hi_s0 * b_lo_s0;
                pp_hh_s1    <= a_hi_s0 * b_hi_s0;
                negative_s1 <= negative_s0;
                type_s1     <= type_s0;
                addend_s1   <= addend_s0;
            end

            if (valid_s1) begin
                magnitude_s2 <= magnitude_sum_s1;
                negative_s2  <= negative_s1;
                type_s2      <= type_s1;
                addend_s2    <= addend_s1;
            end

            if (valid_s2)
                result <= selected_result_s2;
        end
    end

endmodule
