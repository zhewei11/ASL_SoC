

// ALU (Arithmetic Logic Unit) Module
module alu #(
     parameter ENABLE_FPU = 1'b1
) (
     input             clk
    ,input             rst
    ,input             flush
    ,input             enable
    ,input      [31:0] operand_a
    ,input      [31:0] operand_b
    ,input      [4:0]  alu_op
    ,input      [31:0] rd_data
    ,input      [31:0] operand_c
    ,input      [31:0] instruction
    ,input      [2:0]  fp_rounding_mode
    ,output reg [31:0] result
    ,output            valid
    ,output     [4:0]  fp_exception_flags
    ,output            fp_flags_valid
);

    // ALU Operation Code
    localparam ALU_ADD    = 5'b00000;
    localparam ALU_SUB    = 5'b00001;
    localparam ALU_SLL    = 5'b00010;
    localparam ALU_SLT    = 5'b00011;
    localparam ALU_SLTU   = 5'b00100;
    localparam ALU_XOR    = 5'b00101;
    localparam ALU_SRL    = 5'b00110;
    localparam ALU_SRA    = 5'b00111;
    localparam ALU_OR     = 5'b01000;
    localparam ALU_AND    = 5'b01001;
    localparam ALU_MUL    = 5'b01010;
    localparam ALU_MULH   = 5'b01011;
    localparam ALU_MULHSU = 5'b01100;
    localparam ALU_MULHU  = 5'b01101;
    localparam ALU_DIV    = 5'b01110;
    localparam ALU_DIVU   = 5'b01111;
    localparam ALU_REM    = 5'b10000;
    localparam ALU_REMU   = 5'b10001;
    localparam FPU_EXEC   = 5'b10110;
    localparam MAC        = 5'b11110;

    // --- Single Cycle Operations ---
    wire [31:0] sum  = operand_a + operand_b;
    wire [31:0] diff = operand_a - operand_b;
    wire slt = (operand_a[31] != operand_b[31]) ? operand_a[31] : diff[31];
    wire sltu = (operand_a < operand_b);
    wire [4:0] shamt = operand_b[4:0];

    // --- Multiplier Interface ---
    wire mul_start = enable && (
        (alu_op == ALU_MUL) || (alu_op == ALU_MULH) ||
        (alu_op == ALU_MULHSU) || (alu_op == ALU_MULHU) ||
        (alu_op == MAC)
    );

    wire [1:0] mul_type_in = (alu_op == ALU_MUL || alu_op == MAC) ? 2'b00 :
                             (alu_op == ALU_MULH)   ? 2'b01 :
                             (alu_op == ALU_MULHSU) ? 2'b10 :
                             (alu_op == ALU_MULHU)  ? 2'b11 : 2'b00;

    wire [31:0] mul_result;
    wire        mul_valid;

    // Optimization: Pass MAC addend to multiplier
    wire [31:0] mac_addend = (alu_op == MAC) ? rd_data : 32'b0;

    multiplier u_multiplier (
         .clk        (clk)
        ,.rst        (rst)
        ,.flush      (flush)
        ,.operand_a  (operand_a)
        ,.operand_b  (operand_b)
        ,.mul_type   (mul_type_in)
        ,.start      (mul_start)
        ,.mac_addend (mac_addend)
        ,.result     (mul_result)
        ,.valid      (mul_valid)
    );

    // --- Divider Interface ---
    wire div_operation = (alu_op == ALU_DIV)  ||
                         (alu_op == ALU_DIVU) ||
                         (alu_op == ALU_REM)  ||
                         (alu_op == ALU_REMU);
    wire div_start = enable && div_operation;
    wire [31:0] div_result;
    wire        div_valid;

    divider u_divider (
         .clk          (clk)
        ,.rst          (rst)
        ,.flush        (flush)
        ,.start        (div_start)
        ,.dividend     (operand_a)
        ,.divisor      (operand_b)
        ,.is_signed    ((alu_op == ALU_DIV) || (alu_op == ALU_REM))
        ,.is_remainder ((alu_op == ALU_REM) || (alu_op == ALU_REMU))
        ,.result       (div_result)
        ,.valid        (div_valid)
    );

    // --- RV32F Interface ---
    wire [31:0] fpu_result;
    wire        fpu_valid;
    wire [4:0]  fpu_flags;

    generate
        if (ENABLE_FPU) begin : g_fpu
            rv32f_unit u_fpu (
                 .clk                   (clk)
                ,.rst                   (rst)
                ,.flush                 (flush)
                ,.start                 (enable && (alu_op == FPU_EXEC))
                ,.instruction           (instruction)
                ,.operand_a             (operand_a)
                ,.operand_b             (operand_b)
                ,.operand_c             (operand_c)
                ,.dynamic_rounding_mode (fp_rounding_mode)
                ,.result                (fpu_result)
                ,.exception_flags       (fpu_flags)
                ,.valid                 (fpu_valid)
            );
        end else begin : g_no_fpu
            // FP opcodes are converted into illegal-instruction traps in the
            // decoder. Keep the ALU handshake live until that trap commits.
            assign fpu_result = 32'd0;
            assign fpu_flags  = 5'd0;
            assign fpu_valid  = 1'b1;
        end
    endgenerate

    assign fp_exception_flags = fpu_flags;
    assign fp_flags_valid = (alu_op == FPU_EXEC) && fpu_valid;

    // wire [31:0] mac_result = mul_result + rd_data; // Removed for optimization

    // --- Valid Signal Logic ---
    assign valid = (alu_op == ALU_MUL || alu_op == ALU_MULH || alu_op == ALU_MULHSU || alu_op == ALU_MULHU || alu_op == MAC) ? mul_valid :
                   div_operation ? div_valid :
                   (alu_op == FPU_EXEC) ? fpu_valid :
                   1'b1;

    // --- Output Select ---
    always @(*) begin
        case (alu_op)
            ALU_ADD:  result = sum;
            ALU_SUB:  result = diff;
            ALU_SLL:  result = operand_a << shamt;
            ALU_SLT:  result = {31'b0, slt};
            ALU_SLTU: result = {31'b0, sltu};
            ALU_XOR:  result = operand_a ^ operand_b;
            ALU_SRL:  result = operand_a >> shamt;
            ALU_SRA:  result = $signed(operand_a) >>> shamt;
            ALU_OR:   result = operand_a | operand_b;
            ALU_AND:  result = operand_a & operand_b;

            // Multi-cycle ops
            ALU_MUL, ALU_MULH, ALU_MULHSU, ALU_MULHU: begin
                result = mul_result;
            end

            ALU_DIV, ALU_DIVU, ALU_REM, ALU_REMU: begin
                result = div_result;
            end

            MAC: begin
                result = mul_result; // Multiplier now handles MAC internally
            end

            FPU_EXEC: begin
                result = fpu_result;
            end

            default: begin
                result = 32'h0;
            end
        endcase
    end
endmodule
