// Iterative radix-2 divider for the RV32M DIV/DIVU/REM/REMU operations.
// One result is produced after at most 32 divide steps.  Division by zero and
// signed overflow use the architecturally defined results and complete early.
module divider (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    ,input  logic        start
    ,input  logic [31:0] dividend
    ,input  logic [31:0] divisor
    ,input  logic        is_signed
    ,input  logic        is_remainder
    ,output logic [31:0] result
    ,output logic        valid
);

    logic        busy_q;
    logic [5:0]  iteration_q;
    logic [31:0] quotient_q;
    logic [32:0] remainder_q;
    logic [31:0] divisor_q;
    logic        quotient_negative_q;
    logic        remainder_negative_q;
    logic        return_remainder_q;

    logic [32:0] shifted_remainder;
    logic [31:0] shifted_quotient;
    logic [32:0] next_remainder;
    logic [31:0] next_quotient;
    logic [31:0] unsigned_result;

    wire signed_overflow = is_signed &&
                           (dividend == 32'h8000_0000) &&
                           (divisor == 32'hFFFF_FFFF);
    wire [31:0] dividend_magnitude =
        (is_signed && dividend[31]) ? (~dividend + 32'd1) : dividend;
    wire [31:0] divisor_magnitude =
        (is_signed && divisor[31]) ? (~divisor + 32'd1) : divisor;

    always @(*) begin
        shifted_remainder = {remainder_q[31:0], quotient_q[31]};
        shifted_quotient  = {quotient_q[30:0], 1'b0};

        if (shifted_remainder >= {1'b0, divisor_q}) begin
            next_remainder   = shifted_remainder - {1'b0, divisor_q};
            next_quotient    = shifted_quotient;
            next_quotient[0] = 1'b1;
        end else begin
            next_remainder = shifted_remainder;
            next_quotient  = shifted_quotient;
        end

        unsigned_result = return_remainder_q ? next_remainder[31:0]
                                             : next_quotient;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_q                <= 1'b0;
            iteration_q           <= 6'd0;
            quotient_q            <= 32'd0;
            remainder_q           <= 33'd0;
            divisor_q             <= 32'd0;
            quotient_negative_q   <= 1'b0;
            remainder_negative_q  <= 1'b0;
            return_remainder_q     <= 1'b0;
            result                 <= 32'd0;
            valid                  <= 1'b0;
        end else if (flush) begin
            busy_q      <= 1'b0;
            iteration_q <= 6'd0;
            valid       <= 1'b0;
        end else if (valid) begin
            // Keep valid pulse-shaped.  Ignore a still-asserted start from the
            // instruction that is being accepted by the pipeline this cycle.
            valid <= 1'b0;
        end else if (busy_q) begin
            quotient_q  <= next_quotient;
            remainder_q <= next_remainder;

            if (iteration_q == 6'd31) begin
                busy_q <= 1'b0;
                valid  <= 1'b1;

                if (return_remainder_q)
                    result <= remainder_negative_q
                            ? (~unsigned_result + 32'd1)
                            : unsigned_result;
                else
                    result <= quotient_negative_q
                            ? (~unsigned_result + 32'd1)
                            : unsigned_result;
            end else begin
                iteration_q <= iteration_q + 6'd1;
            end
        end else if (start) begin
            if (divisor == 32'd0) begin
                // DIV[U] by zero returns all ones.  REM[U] returns dividend.
                result <= is_remainder ? dividend : 32'hFFFF_FFFF;
                valid  <= 1'b1;
            end else if (signed_overflow) begin
                // INT_MIN / -1 cannot be represented in two's complement.
                result <= is_remainder ? 32'd0 : 32'h8000_0000;
                valid  <= 1'b1;
            end else begin
                busy_q               <= 1'b1;
                iteration_q          <= 6'd0;
                quotient_q           <= dividend_magnitude;
                remainder_q          <= 33'd0;
                divisor_q            <= divisor_magnitude;
                quotient_negative_q  <= is_signed &&
                                        (dividend[31] ^ divisor[31]);
                remainder_negative_q <= is_signed && dividend[31];
                return_remainder_q    <= is_remainder;
            end
        end
    end

endmodule
