// Modified Booth Radix-4 Encoder
// Unified Booth Encoding Module, processes a single group to generate partial product

module booth_encoder (
     input  [32:0]                   multiplicand // Signed multiplicand (33-bit)
    ,input  [2:0]                    booth_bits // 3-bit Booth window
    ,input  [5:0]                    group_idx // Group index (0-15)
    ,output [65:0]                   partial // Output partial product (66-bit)
    ,output                          corr_pos // Correction +1 (bit k)
    ,output                          corr_shifted   // Correction +2 (bit k+1)
);

    localparam int MULTIPLICAND_WIDTH = 33;
    localparam int PARTIAL_WIDTH      = 66;

    // Booth Decoding
    wire zero    = (booth_bits == 3'b000) || (booth_bits == 3'b111);
    wire neg     = (booth_bits == 3'b100) || (booth_bits == 3'b101) || (booth_bits == 3'b110);
    wire times2  = (booth_bits == 3'b011) || (booth_bits == 3'b100);

    // Calculate Shift Amount
    wire [5:0] shift_amount = group_idx << 1;

    // Sign-extended multiplicand
    wire [PARTIAL_WIDTH-1:0] multiplicand_ext;
    assign multiplicand_ext = {{(PARTIAL_WIDTH-MULTIPLICAND_WIDTH){multiplicand[MULTIPLICAND_WIDTH-1]}}, multiplicand};

    // Optimization: Invert BEFORE shift to avoid garbage bits at LSBs
    wire [PARTIAL_WIDTH-1:0] op_to_shift;
    assign op_to_shift = neg ? ~multiplicand_ext : multiplicand_ext;

    // Shift operation
    wire [PARTIAL_WIDTH-1:0] shifted_1x = op_to_shift << shift_amount;
    wire [PARTIAL_WIDTH-1:0] shifted_2x = shifted_1x << 1;

    assign partial = zero ? {PARTIAL_WIDTH{1'b0}} :
                     (times2 ? shifted_2x : shifted_1x);

    // Correction Logic:
    // If neg (-1 or -2): we computed (~M) shifted.
    // -1: (~M) << k. Want (-M)<<k = ( (~M)+1 )<<k = (~M)<<k + 1<<k. Correction +1 @ k.
    // -2: (~M) << k+1. Want (-2M)<<k = (-M)<<k+1 = ( (~M)+1 )<<k+1 = (~M)<<k+1 + 1<<k+1.
    // So for -2, we need correction +1 @ k+1.

    assign corr_pos = zero ? 1'b0 : (neg && !times2); // -1 case
    assign corr_shifted = zero ? 1'b0 : (neg && times2); // -2 case

endmodule
