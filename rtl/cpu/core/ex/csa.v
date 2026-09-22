// CSA 4-to-2 Compressor
// Compresses 4 numbers into 2 numbers (sum, carry)
// Faster than 2 layers of 3-2 CSA

module csa (
     input  [65:0] a
    ,input  [65:0] b
    ,input  [65:0] c
    ,input  [65:0] d
    ,output [65:0] sum
    ,output [65:0] carry
);

    localparam int WIDTH = 66;

    // 4-to-2 compressor: Uses two layers of 3-2 CSA
    // Layer 1: Compress a, b, c -> s1, c1
    wire [WIDTH-1:0] s1 = a ^ b ^ c;
    wire [WIDTH-1:0] c1_temp = (a & b) | (a & c) | (b & c);
    wire [WIDTH-1:0] c1 = {c1_temp[WIDTH-2:0], 1'b0};

    // Layer 2: Compress s1, c1, d -> sum, carry
    assign sum = s1 ^ c1 ^ d;
    wire [WIDTH-1:0] c2_temp = (s1 & c1) | (s1 & d) | (c1 & d);
    assign carry = {c2_temp[WIDTH-2:0], 1'b0};

endmodule
