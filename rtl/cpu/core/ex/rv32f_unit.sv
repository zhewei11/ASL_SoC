module rv32f_unit (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        flush
    ,input  logic        start
    ,input  logic [31:0] instruction
    ,input  logic [31:0] operand_a
    ,input  logic [31:0] operand_b
    ,input  logic [31:0] operand_c
    ,input  logic [2:0]  dynamic_rounding_mode
    ,output logic [31:0] result
    ,output logic [4:0]  exception_flags
    ,output logic        valid
);

    localparam logic [31:0] CANONICAL_NAN = 32'h7FC0_0000;
    localparam logic [6:0] OP_FP     = 7'b1010011;
    localparam logic [6:0] OP_FMADD  = 7'b1000011;
    localparam logic [6:0] OP_FMSUB  = 7'b1000111;
    localparam logic [6:0] OP_FNMSUB = 7'b1001011;
    localparam logic [6:0] OP_FNMADD = 7'b1001111;

    // RISC-V fflags bit positions: NV, DZ, OF, UF, NX = [4:0].
    localparam logic [4:0] FLAG_NV = 5'b1_0000;
    localparam logic [4:0] FLAG_DZ = 5'b0_1000;
    localparam logic [4:0] FLAG_OF = 5'b0_0100;
    localparam logic [4:0] FLAG_UF = 5'b0_0010;
    localparam logic [4:0] FLAG_NX = 5'b0_0001;

    function automatic logic fp_is_nan(input logic [31:0] value);
        fp_is_nan = (&value[30:23]) && (value[22:0] != 23'd0);
    endfunction

    function automatic logic fp_is_snan(input logic [31:0] value);
        fp_is_snan = fp_is_nan(value) && !value[22];
    endfunction

    function automatic logic fp_is_inf(input logic [31:0] value);
        fp_is_inf = (&value[30:23]) && (value[22:0] == 23'd0);
    endfunction

    function automatic logic fp_is_zero(input logic [31:0] value);
        fp_is_zero = (value[30:0] == 31'd0);
    endfunction

    function automatic logic [27:0] shift_right_sticky28(
         input logic [27:0] value
        ,input integer      amount
    );
        logic [27:0] shifted;
        logic        sticky;
        integer      bit_index;
        begin
            if (amount <= 0) begin
                shift_right_sticky28 = value;
            end else if (amount >= 28) begin
                shift_right_sticky28 = {27'd0, |value};
            end else begin
                shifted = value >> amount;
                sticky = 1'b0;
                for (bit_index = 0; bit_index < 28;
                     bit_index = bit_index + 1)
                    if (bit_index < amount)
                        sticky = sticky | value[bit_index];
                shifted[0] = shifted[0] | sticky;
                shift_right_sticky28 = shifted;
            end
        end
    endfunction

    function automatic logic [55:0] shift_right_sticky56(
         input logic [55:0] value
        ,input integer      amount
    );
        logic [55:0] shifted;
        logic        sticky;
        integer      bit_index;
        begin
            if (amount <= 0) begin
                shift_right_sticky56 = value;
            end else if (amount >= 56) begin
                shift_right_sticky56 = {55'd0, |value};
            end else begin
                shifted = value >> amount;
                sticky = 1'b0;
                for (bit_index = 0; bit_index < 56;
                     bit_index = bit_index + 1)
                    if (bit_index < amount)
                        sticky = sticky | value[bit_index];
                shifted[0] = shifted[0] | sticky;
                shift_right_sticky56 = shifted;
            end
        end
    endfunction

    function automatic logic [63:0] shift_right_sticky64(
         input logic [63:0] value
        ,input integer      amount
    );
        logic [63:0] shifted;
        logic        sticky;
        integer      bit_index;
        begin
            if (amount <= 0) begin
                shift_right_sticky64 = value;
            end else if (amount >= 64) begin
                shift_right_sticky64 = {63'd0, |value};
            end else begin
                shifted = value >> amount;
                sticky = 1'b0;
                for (bit_index = 0; bit_index < 64;
                     bit_index = bit_index + 1)
                    if (bit_index < amount)
                        sticky = sticky | value[bit_index];
                shifted[0] = shifted[0] | sticky;
                shift_right_sticky64 = shifted;
            end
        end
    endfunction

    // sig_ext uses bit 26 as the normal hidden bit and bits 2:0 as G/R/S.
    function automatic logic [36:0] round_pack(
         input logic        sign
        ,input integer      exponent_unbiased
        ,input logic [27:0] sig_ext_in
        ,input logic [2:0]  rounding_mode
    );
        logic [27:0] sig_ext;
        logic [23:0] mantissa;
        logic [24:0] rounded;
        logic [31:0] packed_result;
        logic [4:0]  flags;
        logic        inexact;
        logic        increment;
        logic        overflow_to_infinity;
        logic [7:0]  exponent_field;
        integer      exponent;
        integer      subnormal_shift;
        integer      normalize_step;
        begin
            sig_ext = sig_ext_in;
            exponent = exponent_unbiased;
            flags = 5'd0;

            if (sig_ext == 28'd0) begin
                round_pack = {5'd0, sign, 31'd0};
            end else begin
                if (sig_ext[27]) begin
                    sig_ext = shift_right_sticky28(sig_ext, 1);
                    exponent = exponent + 1;
                end
                // Statically bounded normalization is portable to synthesis;
                // at most 26 shifts can move a non-zero 27-bit significand to
                // the hidden-bit position.
                for (normalize_step = 0; normalize_step < 27;
                     normalize_step = normalize_step + 1)
                    if (!sig_ext[26] && (sig_ext != 0) &&
                        (exponent > -150)) begin
                        sig_ext = sig_ext << 1;
                        exponent = exponent - 1;
                    end

                if (exponent < -126) begin
                    subnormal_shift = -126 - exponent;
                    sig_ext = shift_right_sticky28(sig_ext,
                                                   subnormal_shift);
                    exponent = -126;
                end

                inexact = |sig_ext[2:0];
                case (rounding_mode)
                    3'b001: increment = 1'b0; // RTZ
                    3'b010: increment = sign && inexact; // RDN
                    3'b011: increment = !sign && inexact; // RUP
                    3'b100: increment = sig_ext[2]; // RMM
                    default: increment = sig_ext[2] &&
                        (sig_ext[1] || sig_ext[0] || sig_ext[3]); // RNE
                endcase

                rounded = {1'b0, sig_ext[26:3]} +
                          {{24{1'b0}}, increment};
                if (rounded[24]) begin
                    mantissa = rounded[24:1];
                    exponent = exponent + 1;
                end else begin
                    mantissa = rounded[23:0];
                end

                if (exponent > 127) begin
                    overflow_to_infinity =
                        (rounding_mode == 3'b000) ||
                        (rounding_mode == 3'b100) ||
                        ((rounding_mode == 3'b011) && !sign) ||
                        ((rounding_mode == 3'b010) && sign);
                    packed_result = overflow_to_infinity
                        ? {sign, 8'hFF, 23'd0}
                        : {sign, 8'hFE, 23'h7F_FFFF};
                    flags = FLAG_OF | FLAG_NX;
                end else begin
                    if ((exponent == -126) && !mantissa[23])
                        exponent_field = 8'd0;
                    else
                        exponent_field = 8'(exponent + 127);
                    packed_result = {sign, exponent_field,
                                     mantissa[22:0]};
                    if (inexact)
                        flags = flags | FLAG_NX;
                    if (inexact && (exponent_field == 8'd0))
                        flags = flags | FLAG_UF;
                end
                round_pack = {flags, packed_result};
            end
        end
    endfunction

    function automatic logic [36:0] fp_add_sub(
         input logic [31:0] a
        ,input logic [31:0] b
        ,input logic        subtract
        ,input logic [2:0]  rounding_mode
    );
        logic        sign_a;
        logic        sign_b;
        logic        sign_big;
        logic        sign_result;
        logic [23:0] sig_a;
        logic [23:0] sig_b;
        logic [23:0] sig_big;
        logic [23:0] sig_small;
        logic [27:0] ext_big;
        logic [27:0] ext_small;
        logic [28:0] ext_sum;
        logic [27:0] ext_result;
        integer      exp_a;
        integer      exp_b;
        integer      exp_big;
        integer      exp_small;
        begin
            sign_a = a[31];
            sign_b = b[31] ^ subtract;

            if (fp_is_nan(a) || fp_is_nan(b)) begin
                fp_add_sub = {(fp_is_snan(a) || fp_is_snan(b))
                              ? FLAG_NV : 5'd0, CANONICAL_NAN};
            end else if (fp_is_inf(a) && fp_is_inf(b) &&
                         (sign_a != sign_b)) begin
                fp_add_sub = {FLAG_NV, CANONICAL_NAN};
            end else if (fp_is_inf(a)) begin
                fp_add_sub = {5'd0, sign_a, 8'hFF, 23'd0};
            end else if (fp_is_inf(b)) begin
                fp_add_sub = {5'd0, sign_b, 8'hFF, 23'd0};
            end else if (fp_is_zero(a) && fp_is_zero(b)) begin
                sign_result = (sign_a == sign_b) ? sign_a :
                              (rounding_mode == 3'b010);
                fp_add_sub = {5'd0, sign_result, 31'd0};
            end else if (fp_is_zero(a)) begin
                fp_add_sub = {5'd0, sign_b, b[30:0]};
            end else if (fp_is_zero(b)) begin
                fp_add_sub = {5'd0, a};
            end else begin
                sig_a = {a[30:23] != 0, a[22:0]};
                sig_b = {b[30:23] != 0, b[22:0]};
                exp_a = (a[30:23] == 0) ? -126 : int'(a[30:23]) - 127;
                exp_b = (b[30:23] == 0) ? -126 : int'(b[30:23]) - 127;
                while (!sig_a[23]) begin
                    sig_a = sig_a << 1;
                    exp_a = exp_a - 1;
                end
                while (!sig_b[23]) begin
                    sig_b = sig_b << 1;
                    exp_b = exp_b - 1;
                end

                if ((exp_a > exp_b) ||
                    ((exp_a == exp_b) && (sig_a >= sig_b))) begin
                    sig_big = sig_a;
                    sig_small = sig_b;
                    exp_big = exp_a;
                    exp_small = exp_b;
                    sign_big = sign_a;
                end else begin
                    sig_big = sig_b;
                    sig_small = sig_a;
                    exp_big = exp_b;
                    exp_small = exp_a;
                    sign_big = sign_b;
                end
                ext_big = {1'b0, sig_big, 3'b000};
                ext_small = shift_right_sticky28(
                    {1'b0, sig_small, 3'b000}, exp_big-exp_small);
                if (sign_a == sign_b) begin
                    ext_sum = {1'b0, ext_big} + {1'b0, ext_small};
                    ext_result = ext_sum[27:0];
                end else begin
                    ext_result = ext_big - ext_small;
                end
                sign_result = sign_big;
                if (ext_result == 0)
                    sign_result = (rounding_mode == 3'b010);
                fp_add_sub = round_pack(sign_result, exp_big,
                                        ext_result, rounding_mode);
            end
        end
    endfunction

    function automatic logic [26:0] integer_sqrt54(
         input logic [53:0] radicand
    );
        logic [26:0] root;
        logic [26:0] trial;
        logic [53:0] square;
        integer      root_bit;
        begin
            root = 27'd0;
            for (root_bit = 26; root_bit >= 0; root_bit = root_bit - 1) begin
                trial = root | (27'd1 << root_bit);
                square = trial * trial;
                if (square <= radicand)
                    root = trial;
            end
            integer_sqrt54 = root;
        end
    endfunction

    function automatic logic [36:0] fp_square_root(
         input logic [31:0] a
        ,input logic [2:0]  rounding_mode
    );
        logic [23:0] sig_a;
        logic [24:0] sig_adjusted;
        logic [53:0] radicand;
        logic [26:0] root;
        logic [53:0] root_square;
        logic [27:0] sig_ext;
        integer      exponent;
        begin
            if (fp_is_nan(a)) begin
                fp_square_root = {fp_is_snan(a) ? FLAG_NV : 5'd0,
                                  CANONICAL_NAN};
            end else if (a[31] && !fp_is_zero(a)) begin
                fp_square_root = {FLAG_NV, CANONICAL_NAN};
            end else if (fp_is_inf(a) || fp_is_zero(a)) begin
                fp_square_root = {5'd0, a};
            end else begin
                sig_a = {a[30:23] != 0, a[22:0]};
                exponent = (a[30:23] == 0) ? -126 :
                           int'(a[30:23]) - 127;
                while (!sig_a[23]) begin
                    sig_a = sig_a << 1;
                    exponent = exponent - 1;
                end
                if (exponent[0]) begin
                    sig_adjusted = {sig_a, 1'b0};
                    exponent = exponent - 1;
                end else begin
                    sig_adjusted = {1'b0, sig_a};
                end
                radicand = {29'd0, sig_adjusted} << 29;
                root = integer_sqrt54(radicand);
                root_square = root * root;
                sig_ext = {1'b0, root};
                sig_ext[0] = sig_ext[0] | (root_square != radicand);
                fp_square_root = round_pack(1'b0, exponent/2,
                                            sig_ext, rounding_mode);
            end
        end
    endfunction

    function automatic logic fp_less_than(
         input logic [31:0] a
        ,input logic [31:0] b
    );
        begin
            if (fp_is_zero(a) && fp_is_zero(b))
                fp_less_than = 1'b0;
            else if (a[31] != b[31])
                fp_less_than = a[31];
            else if (!a[31])
                fp_less_than = a[30:0] < b[30:0];
            else
                fp_less_than = a[30:0] > b[30:0];
        end
    endfunction

    function automatic logic [9:0] fp_classify(input logic [31:0] a);
        logic zero;
        logic subnormal;
        logic normal;
        logic infinite;
        logic signaling_nan;
        logic quiet_nan;
        begin
            zero = fp_is_zero(a);
            subnormal = (a[30:23] == 0) && (a[22:0] != 0);
            normal = (a[30:23] != 0) && (a[30:23] != 8'hFF);
            infinite = fp_is_inf(a);
            signaling_nan = fp_is_snan(a);
            quiet_nan = fp_is_nan(a) && !signaling_nan;
            fp_classify = {
                quiet_nan,
                signaling_nan,
                !a[31] && infinite,
                !a[31] && normal,
                !a[31] && subnormal,
                !a[31] && zero,
                a[31] && zero,
                a[31] && subnormal,
                a[31] && normal,
                a[31] && infinite
            };
        end
    endfunction

    function automatic logic [36:0] integer_to_float(
         input logic [31:0] integer_value
        ,input logic        is_unsigned
        ,input logic [2:0]  rounding_mode
    );
        logic        sign;
        logic [31:0] magnitude;
        logic [63:0] extended;
        logic [27:0] sig_ext;
        integer      leading_bit;
        integer      bit_index;
        begin
            sign = !is_unsigned && integer_value[31];
            magnitude = sign ? (~integer_value + 32'd1) : integer_value;
            if (magnitude == 0) begin
                integer_to_float = 37'd0;
            end else begin
                leading_bit = 0;
                for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
                    if (magnitude[bit_index])
                        leading_bit = bit_index;
                extended = {29'd0, magnitude, 3'd0};
                if (leading_bit > 23) begin
                    extended = shift_right_sticky64(
                        extended, leading_bit-23);
                    sig_ext = extended[27:0];
                end else begin
                    sig_ext = extended[27:0] << (23-leading_bit);
                end
                integer_to_float = round_pack(sign, leading_bit,
                                              sig_ext, rounding_mode);
            end
        end
    endfunction

    function automatic logic [36:0] float_to_integer(
         input logic [31:0] a
        ,input logic        is_unsigned
        ,input logic [2:0]  rounding_mode
    );
        logic        sign;
        logic [23:0] sig;
        logic [63:0] magnitude_wide;
        logic [63:0] integer_magnitude;
        logic        discarded;
        logic        greater_than_half;
        logic        exactly_half;
        logic        increment;
        logic        invalid;
        logic [31:0] converted;
        integer      exponent;
        integer      shift;
        integer      bit_index;
        begin
            sign = a[31];
            invalid = 1'b0;
            converted = 32'd0;
            discarded = 1'b0;
            greater_than_half = 1'b0;
            exactly_half = 1'b0;
            integer_magnitude = 64'd0;

            if (fp_is_nan(a)) begin
                invalid = 1'b1;
                converted = is_unsigned ? 32'hFFFF_FFFF : 32'h7FFF_FFFF;
            end else if (fp_is_inf(a)) begin
                invalid = 1'b1;
                converted = is_unsigned
                    ? (sign ? 32'd0 : 32'hFFFF_FFFF)
                    : (sign ? 32'h8000_0000 : 32'h7FFF_FFFF);
            end else if (!fp_is_zero(a)) begin
                sig = {a[30:23] != 0, a[22:0]};
                exponent = (a[30:23] == 0) ? -126 :
                           int'(a[30:23]) - 127;
                while (!sig[23]) begin sig = sig << 1; exponent = exponent-1; end
                if (exponent >= 23) begin
                    if (exponent > 63)
                        magnitude_wide = 64'hFFFF_FFFF_FFFF_FFFF;
                    else
                        magnitude_wide = {40'd0, sig} << (exponent-23);
                    integer_magnitude = magnitude_wide;
                end else if (exponent >= 0) begin
                    shift = 23-exponent;
                    integer_magnitude = {40'd0, sig} >> shift;
                    for (bit_index = 0; bit_index < 24;
                         bit_index = bit_index + 1)
                        if ((bit_index < shift) && sig[bit_index])
                            discarded = 1'b1;
                    greater_than_half = sig[shift-1] &&
                        (|(sig & ((24'd1 << (shift-1))-1)));
                    exactly_half = sig[shift-1] && !greater_than_half;
                end else begin
                    discarded = 1'b1;
                    if (exponent == -1) begin
                        greater_than_half = sig > 24'h80_0000;
                        exactly_half = sig == 24'h80_0000;
                    end
                end

                case (rounding_mode)
                    3'b001: increment = 1'b0;
                    3'b010: increment = sign && discarded;
                    3'b011: increment = !sign && discarded;
                    3'b100: increment = greater_than_half || exactly_half;
                    default: increment = greater_than_half ||
                        (exactly_half && integer_magnitude[0]);
                endcase
                integer_magnitude = integer_magnitude +
                                    {{63{1'b0}}, increment};

                if (is_unsigned) begin
                    if (sign || (integer_magnitude > 64'hFFFF_FFFF)) begin
                        invalid = 1'b1;
                        converted = sign ? 32'd0 : 32'hFFFF_FFFF;
                    end else begin
                        converted = integer_magnitude[31:0];
                    end
                end else begin
                    if ((!sign && (integer_magnitude > 64'h7FFF_FFFF)) ||
                        (sign && (integer_magnitude > 64'h8000_0000))) begin
                        invalid = 1'b1;
                        converted = sign ? 32'h8000_0000 : 32'h7FFF_FFFF;
                    end else begin
                        converted = sign
                            ? (~integer_magnitude[31:0] + 32'd1)
                            : integer_magnitude[31:0];
                    end
                end
            end

            float_to_integer = {
                invalid ? FLAG_NV : (discarded ? FLAG_NX : 5'd0),
                converted
            };
        end
    endfunction

    function automatic logic [36:0] execute_fp(
         input logic [31:0] inst
        ,input logic [31:0] a
        ,input logic [31:0] b
        ,input logic [31:0] c
        ,input logic [2:0]  frm
    );
        logic [2:0]  rounding_mode;
        logic [6:0]  opcode;
        logic [6:0]  funct7;
        logic [2:0]  funct3;
        logic [31:0] misc_result;
        logic [4:0]  misc_flags;
        logic        less;
        logic        equal;
        logic        a_nan;
        logic        b_nan;
        begin
            opcode = inst[6:0];
            funct3 = inst[14:12];
            funct7 = inst[31:25];
            rounding_mode = (funct3 == 3'b111) ? frm : funct3;
            misc_result = 32'd0;
            misc_flags = 5'd0;
            a_nan = fp_is_nan(a);
            b_nan = fp_is_nan(b);
            less = fp_less_than(a, b);
            equal = (a == b) || (fp_is_zero(a) && fp_is_zero(b));

            if ((opcode == OP_FMADD) || (opcode == OP_FMSUB) ||
                (opcode == OP_FNMSUB) || (opcode == OP_FNMADD)) begin
                // Fused operations use the dedicated registered pipeline
                // below.  Excluding their arithmetic here prevents synthesis
                // from rebuilding a parallel single-cycle multiplier.
                execute_fp = {FLAG_NV, CANONICAL_NAN};
            end else if (opcode == OP_FP) begin
                case (funct7)
                    7'b0000000: execute_fp = fp_add_sub(
                        a, b, 1'b0, rounding_mode);
                    7'b0000100: execute_fp = fp_add_sub(
                        a, b, 1'b1, rounding_mode);
                    // FMUL.S and FDIV.S use the dedicated arithmetic
                    // pipelines below.  Keeping them out of this generic
                    // path prevents synthesis from rebuilding a single-cycle
                    // multiplier/divider in parallel with those pipelines.
                    7'b0001000: execute_fp = {FLAG_NV, CANONICAL_NAN};
                    7'b0001100: execute_fp = {FLAG_NV, CANONICAL_NAN};
                    7'b0101100: execute_fp = fp_square_root(
                        a, rounding_mode);
                    7'b0010000: begin
                        case (funct3)
                            3'b000: misc_result = {b[31], a[30:0]};
                            3'b001: misc_result = {~b[31], a[30:0]};
                            default: misc_result = {a[31]^b[31], a[30:0]};
                        endcase
                        execute_fp = {5'd0, misc_result};
                    end
                    7'b0010100: begin
                        if (a_nan && b_nan)
                            misc_result = CANONICAL_NAN;
                        else if (a_nan)
                            misc_result = b;
                        else if (b_nan)
                            misc_result = a;
                        else if (fp_is_zero(a) && fp_is_zero(b))
                            misc_result = (funct3 == 3'b000)
                                ? {a[31] | b[31], 31'd0}
                                : {a[31] & b[31], 31'd0};
                        else if (funct3 == 3'b000)
                            misc_result = less ? a : b;
                        else
                            misc_result = less ? b : a;
                        misc_flags = (fp_is_snan(a) || fp_is_snan(b))
                            ? FLAG_NV : 5'd0;
                        execute_fp = {misc_flags, misc_result};
                    end
                    7'b1010000: begin
                        if (a_nan || b_nan) begin
                            misc_result = 32'd0;
                            misc_flags = ((funct3 != 3'b010) ||
                                fp_is_snan(a) || fp_is_snan(b))
                                ? FLAG_NV : 5'd0;
                        end else begin
                            case (funct3)
                                3'b000: misc_result = {31'd0, less || equal};
                                3'b001: misc_result = {31'd0, less};
                                default: misc_result = {31'd0, equal};
                            endcase
                        end
                        execute_fp = {misc_flags, misc_result};
                    end
                    7'b1100000: execute_fp = float_to_integer(
                        a, inst[20], rounding_mode);
                    7'b1110000: begin
                        misc_result = (funct3 == 3'b001)
                            ? {22'd0, fp_classify(a)} : a;
                        execute_fp = {5'd0, misc_result};
                    end
                    7'b1101000: execute_fp = integer_to_float(
                        a, inst[20], rounding_mode);
                    7'b1111000: execute_fp = {5'd0, a};
                    default: execute_fp = {FLAG_NV, CANONICAL_NAN};
                endcase
            end else begin
                execute_fp = {FLAG_NV, CANONICAL_NAN};
            end
        end
    endfunction

    // =====================================================================
    // Fixed-latency request/response pipelines
    // =====================================================================
    // A common latency keeps responses ordered even when different RV32F
    // operations are issued on adjacent cycles. FMUL, fused multiply-add, and
    // FDIV use genuinely staged arithmetic below; the shorter operations are
    // delayed to the same interface latency.
    localparam integer FPU_PIPELINE_LATENCY = 11;
    localparam integer DIV_STEPS_PER_STAGE  = 5;
    localparam integer DIV_PIPELINE_STAGES  = 10;

    function automatic integer leading_zero_count24(
         input logic [23:0] value
    );
        integer bit_index;
        logic   found_one;
        begin
            leading_zero_count24 = 0;
            found_one = 1'b0;
            for (bit_index = 23; bit_index >= 0;
                 bit_index = bit_index - 1) begin
                if (!found_one) begin
                    if (value[bit_index])
                        found_one = 1'b1;
                    else
                        leading_zero_count24 =
                            leading_zero_count24 + 1;
                end
            end
        end
    endfunction

    function automatic logic [5:0] leading_zero_count56(
         input logic [55:0] value
    );
        integer bit_index;
        logic   found_one;
        begin
            leading_zero_count56 = 6'd0;
            found_one = 1'b0;
            for (bit_index = 55; bit_index >= 0;
                 bit_index = bit_index - 1) begin
                if (!found_one) begin
                    if (value[bit_index])
                        found_one = 1'b1;
                    else
                        leading_zero_count56 =
                            leading_zero_count56 + 6'd1;
                end
            end
        end
    endfunction

    wire [2:0] request_rounding_mode =
        (instruction[14:12] == 3'b111)
        ? dynamic_rounding_mode : instruction[14:12];
    wire request_is_multiply =
        (instruction[6:0] == OP_FP) &&
        (instruction[31:25] == 7'b0001000);
    wire request_is_divide =
        (instruction[6:0] == OP_FP) &&
        (instruction[31:25] == 7'b0001100);
    wire request_is_fma =
        (instruction[6:0] == OP_FMADD) ||
        (instruction[6:0] == OP_FMSUB) ||
        (instruction[6:0] == OP_FNMSUB) ||
        (instruction[6:0] == OP_FNMADD);
    wire request_is_generic = !request_is_multiply && !request_is_divide &&
                              !request_is_fma;

    // ---------------------------------------------------------------------
    // Generic RV32F path. These operations retain their existing bit-exact
    // implementation but are delayed to the common response latency.
    // ---------------------------------------------------------------------
    logic [36:0] generic_computed;
    logic [36:0] generic_result_pipe [0:FPU_PIPELINE_LATENCY];
    logic        generic_valid_pipe  [0:FPU_PIPELINE_LATENCY];
    integer      generic_stage;

    always @(*) begin
        generic_computed = 37'd0;
        if (start && request_is_generic)
            generic_computed = execute_fp(
                instruction, operand_a, operand_b, operand_c,
                dynamic_rounding_mode);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (generic_stage = 0;
                 generic_stage <= FPU_PIPELINE_LATENCY;
                 generic_stage = generic_stage + 1) begin
                generic_valid_pipe[generic_stage]  <= 1'b0;
                generic_result_pipe[generic_stage] <= 37'd0;
            end
        end else if (flush) begin
            for (generic_stage = 0;
                 generic_stage <= FPU_PIPELINE_LATENCY;
                 generic_stage = generic_stage + 1)
                generic_valid_pipe[generic_stage] <= 1'b0;
        end else begin
            generic_valid_pipe[0] <= start && request_is_generic;
            if (start && request_is_generic)
                generic_result_pipe[0] <= generic_computed;

            for (generic_stage = 1;
                 generic_stage <= FPU_PIPELINE_LATENCY;
                 generic_stage = generic_stage + 1) begin
                generic_valid_pipe[generic_stage] <=
                    generic_valid_pipe[generic_stage-1];
                if (generic_valid_pipe[generic_stage-1])
                    generic_result_pipe[generic_stage] <=
                        generic_result_pipe[generic_stage-1];
            end
        end
    end

    // ---------------------------------------------------------------------
    // Fused multiply-add pipeline
    // F0 classifies and normalizes all three operands. F1 and F2 form the
    // exact 48-bit product from four 12x12 partial products. F3..F5 scale,
    // compare, and align the full-precision product and addend. F6 performs
    // the add/subtract, F7 handles a carry-out, F8/F9 normalize, and F10
    // performs the only rounding step. F11 aligns the response with every
    // other RV32F operation. No intermediate product rounding is performed.
    // ---------------------------------------------------------------------
    typedef struct packed {
        logic        special;
        logic [36:0] special_result;
        logic        sign_product;
        logic        sign_c;
        logic [2:0]  rounding_mode;
    } fma_metadata_t;

    function automatic logic [134:0] prepare_fma(
         input logic [31:0] a
        ,input logic [31:0] b
        ,input logic [31:0] c
        ,input logic [6:0]  opcode
        ,input logic [2:0]  rounding_mode
    );
        logic        special;
        logic [36:0] special_result;
        logic        sign_product;
        logic        sign_c;
        logic        sign_result;
        logic [23:0] sig_a;
        logic [23:0] sig_b;
        logic [23:0] sig_c;
        logic        c_zero;
        integer      exp_a;
        integer      exp_b;
        integer      exp_c;
        integer      exp_product_base;
        integer      shift_a;
        integer      shift_b;
        integer      shift_c;
        begin
            sign_product = a[31] ^ b[31] ^
                           ((opcode == OP_FNMSUB) ||
                            (opcode == OP_FNMADD));
            sign_c = c[31] ^ ((opcode == OP_FMSUB) ||
                              (opcode == OP_FNMADD));
            special         = 1'b1;
            special_result  = 37'd0;
            sig_a           = 24'd0;
            sig_b           = 24'd0;
            sig_c           = 24'd0;
            c_zero          = 1'b1;
            exp_product_base = 0;
            exp_c            = 0;

            if (fp_is_nan(a) || fp_is_nan(b) || fp_is_nan(c)) begin
                special_result = {
                    (fp_is_snan(a) || fp_is_snan(b) || fp_is_snan(c))
                    ? FLAG_NV : 5'd0, CANONICAL_NAN};
            end else if ((fp_is_inf(a) && fp_is_zero(b)) ||
                         (fp_is_zero(a) && fp_is_inf(b))) begin
                special_result = {FLAG_NV, CANONICAL_NAN};
            end else if ((fp_is_inf(a) || fp_is_inf(b)) && fp_is_inf(c) &&
                         (sign_product != sign_c)) begin
                special_result = {FLAG_NV, CANONICAL_NAN};
            end else if (fp_is_inf(a) || fp_is_inf(b)) begin
                special_result = {5'd0, sign_product, 8'hFF, 23'd0};
            end else if (fp_is_inf(c)) begin
                special_result = {5'd0, sign_c, 8'hFF, 23'd0};
            end else if ((fp_is_zero(a) || fp_is_zero(b)) &&
                         fp_is_zero(c)) begin
                sign_result = (sign_product == sign_c) ? sign_product :
                              (rounding_mode == 3'b010);
                special_result = {5'd0, sign_result, 31'd0};
            end else if (fp_is_zero(a) || fp_is_zero(b)) begin
                special_result = {5'd0, sign_c, c[30:0]};
            end else begin
                special = 1'b0;
                shift_a = leading_zero_count24(
                    {a[30:23] != 0, a[22:0]});
                shift_b = leading_zero_count24(
                    {b[30:23] != 0, b[22:0]});
                sig_a = {a[30:23] != 0, a[22:0]} << shift_a;
                sig_b = {b[30:23] != 0, b[22:0]} << shift_b;
                exp_a = (a[30:23] == 0)
                    ? (-126 - shift_a) :
                      (int'(a[30:23]) - 127 - shift_a);
                exp_b = (b[30:23] == 0)
                    ? (-126 - shift_b) :
                      (int'(b[30:23]) - 127 - shift_b);
                exp_product_base = exp_a + exp_b;

                if (!fp_is_zero(c)) begin
                    c_zero = 1'b0;
                    shift_c = leading_zero_count24(
                        {c[30:23] != 0, c[22:0]});
                    sig_c = {c[30:23] != 0, c[22:0]} << shift_c;
                    exp_c = (c[30:23] == 0)
                        ? (-126 - shift_c)
                        : (int'(c[30:23]) - 127 - shift_c);
                end
            end

            prepare_fma = {
                special, special_result, sign_product, sign_c,
                sig_a, sig_b, sig_c, exp_product_base[10:0],
                exp_c[10:0], c_zero};
        end
    endfunction

    wire [134:0] fma_prepared = prepare_fma(
        operand_a, operand_b, operand_c, instruction[6:0],
        request_rounding_mode);
    wire               fma_special_in;
    wire [36:0]        fma_special_result_in;
    wire               fma_sign_product_in;
    wire               fma_sign_c_in;
    wire [23:0]        fma_sig_a_in;
    wire [23:0]        fma_sig_b_in;
    wire [23:0]        fma_sig_c_in;
    wire signed [10:0] fma_exp_product_base_in;
    wire signed [10:0] fma_exp_c_in;
    wire               fma_c_zero_in;
    assign {fma_special_in, fma_special_result_in,
            fma_sign_product_in, fma_sign_c_in,
            fma_sig_a_in, fma_sig_b_in, fma_sig_c_in,
            fma_exp_product_base_in, fma_exp_c_in,
            fma_c_zero_in} = fma_prepared;

    logic        fma_valid_pipe [0:FPU_PIPELINE_LATENCY];
    logic [36:0] fma_result_pipe [10:FPU_PIPELINE_LATENCY];

    fma_metadata_t fma_meta_s0;
    logic [23:0]        fma_sig_a_s0;
    logic [23:0]        fma_sig_b_s0;
    logic [23:0]        fma_sig_c_s0;
    logic signed [10:0] fma_exp_product_base_s0;
    logic signed [10:0] fma_exp_c_s0;
    logic               fma_c_zero_s0;

    fma_metadata_t fma_meta_s1;
    logic [23:0]        fma_pp_ll_s1;
    logic [23:0]        fma_pp_lh_s1;
    logic [23:0]        fma_pp_hl_s1;
    logic [23:0]        fma_pp_hh_s1;
    logic [23:0]        fma_sig_c_s1;
    logic signed [10:0] fma_exp_product_base_s1;
    logic signed [10:0] fma_exp_c_s1;
    logic               fma_c_zero_s1;

    fma_metadata_t fma_meta_s2;
    logic [47:0]        fma_product_s2;
    logic [23:0]        fma_sig_c_s2;
    logic signed [10:0] fma_exp_product_base_s2;
    logic signed [10:0] fma_exp_c_s2;
    logic               fma_c_zero_s2;

    fma_metadata_t fma_meta_s3;
    logic [55:0]        fma_product_wide_s3;
    logic [55:0]        fma_c_wide_s3;
    logic signed [10:0] fma_exp_product_s3;
    logic signed [10:0] fma_exp_c_s3;

    fma_metadata_t fma_meta_s4;
    logic [55:0]        fma_big_s4;
    logic [55:0]        fma_small_s4;
    logic signed [10:0] fma_exp_big_s4;
    logic signed [10:0] fma_exp_small_s4;
    logic               fma_sign_big_s4;

    fma_metadata_t fma_meta_s5;
    logic [55:0]        fma_big_s5;
    logic [55:0]        fma_small_aligned_s5;
    logic signed [10:0] fma_exp_big_s5;
    logic               fma_sign_big_s5;

    fma_metadata_t fma_meta_s6;
    logic [56:0]        fma_sum_s6;
    logic signed [10:0] fma_exp_big_s6;
    logic               fma_sign_big_s6;

    fma_metadata_t fma_meta_s7;
    logic [55:0]        fma_adjusted_s7;
    logic signed [10:0] fma_exp_adjusted_s7;
    logic               fma_sign_big_s7;

    fma_metadata_t fma_meta_s8;
    logic [55:0]        fma_adjusted_s8;
    logic signed [10:0] fma_exp_adjusted_s8;
    logic               fma_sign_big_s8;
    logic [5:0]         fma_normalize_shift_s8;

    fma_metadata_t fma_meta_s9;
    logic [55:0]        fma_normalized_s9;
    logic signed [10:0] fma_exp_normalized_s9;
    logic               fma_sign_result_s9;

    wire [24:0] fma_cross_sum_s1 = {1'b0, fma_pp_lh_s1} +
                                    {1'b0, fma_pp_hl_s1};
    wire [48:0] fma_product_sum_s1 =
        {25'd0, fma_pp_ll_s1} +
        ({24'd0, fma_cross_sum_s1} << 12) +
        ({25'd0, fma_pp_hh_s1} << 24);
    wire [55:0] fma_product_wide_from_s2 = fma_product_s2[47]
        ? {fma_product_s2, 8'd0}
        : ({8'd0, fma_product_s2} << 9);
    wire signed [10:0] fma_exp_product_from_s2 =
        fma_exp_product_base_s2 +
        (fma_product_s2[47] ? 11'sd1 : 11'sd0);
    wire [55:0] fma_c_wide_from_s2 = fma_c_zero_s2
        ? 56'd0 : {fma_sig_c_s2, 32'd0};
    wire signed [10:0] fma_exp_c_from_s2 = fma_c_zero_s2
        ? fma_exp_product_from_s2 : fma_exp_c_s2;
    integer fma_align_shift_s4;
    always @(*) begin
        fma_align_shift_s4 = int'($signed(fma_exp_big_s4)) -
                             int'($signed(fma_exp_small_s4));
    end
    wire [55:0] fma_aligned_small_from_s4 = shift_right_sticky56(
        fma_small_s4, fma_align_shift_s4);

    logic [55:0]        fma_adjusted_from_s6;
    logic signed [10:0] fma_exp_adjusted_from_s6;
    always @(*) begin
        fma_adjusted_from_s6 = fma_sum_s6[55:0];
        fma_exp_adjusted_from_s6 = fma_exp_big_s6;
        if (fma_sum_s6[56]) begin
            // Equivalent to a sticky right shift of the 57-bit carry result.
            fma_adjusted_from_s6 = fma_sum_s6[56:1];
            fma_adjusted_from_s6[0] = fma_adjusted_from_s6[0] |
                                      fma_sum_s6[0];
            fma_exp_adjusted_from_s6 = fma_exp_big_s6 + 11'sd1;
        end
    end

    function automatic logic [36:0] finish_fma(
         input logic        special
        ,input logic [36:0] special_result
        ,input logic        sign_result
        ,input logic signed [10:0] exponent_in
        ,input logic [2:0]  rounding_mode
        ,input logic [55:0] normalized
    );
        logic [27:0] sig_ext;
        integer      exponent;
        begin
            if (special) begin
                finish_fma = special_result;
            end else begin
                sig_ext = {1'b0, normalized[55:29]};
                sig_ext[0] = sig_ext[0] | (|normalized[28:0]);
                exponent = int'($signed(exponent_in));
                finish_fma = round_pack(
                    sign_result, exponent, sig_ext, rounding_mode);
            end
        end
    endfunction

    wire [36:0] fma_rounded_s9 = finish_fma(
        fma_meta_s9.special, fma_meta_s9.special_result,
        fma_sign_result_s9, fma_exp_normalized_s9,
        fma_meta_s9.rounding_mode, fma_normalized_s9);

    integer fma_stage;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (fma_stage = 0;
                 fma_stage <= FPU_PIPELINE_LATENCY;
                 fma_stage = fma_stage + 1)
                fma_valid_pipe[fma_stage] <= 1'b0;
            for (fma_stage = 10;
                 fma_stage <= FPU_PIPELINE_LATENCY;
                 fma_stage = fma_stage + 1)
                fma_result_pipe[fma_stage] <= 37'd0;
        end else if (flush) begin
            for (fma_stage = 0;
                 fma_stage <= FPU_PIPELINE_LATENCY;
                 fma_stage = fma_stage + 1)
                fma_valid_pipe[fma_stage] <= 1'b0;
        end else begin
            fma_valid_pipe[0] <= start && request_is_fma;
            for (fma_stage = 1;
                 fma_stage <= FPU_PIPELINE_LATENCY;
                 fma_stage = fma_stage + 1)
                fma_valid_pipe[fma_stage] <= fma_valid_pipe[fma_stage-1];

            if (start && request_is_fma) begin
                fma_meta_s0.special        <= fma_special_in;
                fma_meta_s0.special_result <= fma_special_result_in;
                fma_meta_s0.sign_product   <= fma_sign_product_in;
                fma_meta_s0.sign_c         <= fma_sign_c_in;
                fma_meta_s0.rounding_mode  <= request_rounding_mode;
                fma_sig_a_s0               <= fma_sig_a_in;
                fma_sig_b_s0               <= fma_sig_b_in;
                fma_sig_c_s0               <= fma_sig_c_in;
                fma_exp_product_base_s0    <= fma_exp_product_base_in;
                fma_exp_c_s0               <= fma_exp_c_in;
                fma_c_zero_s0              <= fma_c_zero_in;
            end

            if (fma_valid_pipe[0]) begin
                fma_meta_s1             <= fma_meta_s0;
                fma_pp_ll_s1            <= fma_sig_a_s0[11:0] *
                                           fma_sig_b_s0[11:0];
                fma_pp_lh_s1            <= fma_sig_a_s0[11:0] *
                                           fma_sig_b_s0[23:12];
                fma_pp_hl_s1            <= fma_sig_a_s0[23:12] *
                                           fma_sig_b_s0[11:0];
                fma_pp_hh_s1            <= fma_sig_a_s0[23:12] *
                                           fma_sig_b_s0[23:12];
                fma_sig_c_s1            <= fma_sig_c_s0;
                fma_exp_product_base_s1 <= fma_exp_product_base_s0;
                fma_exp_c_s1            <= fma_exp_c_s0;
                fma_c_zero_s1           <= fma_c_zero_s0;
            end

            if (fma_valid_pipe[1]) begin
                fma_meta_s2             <= fma_meta_s1;
                fma_product_s2          <= fma_product_sum_s1[47:0];
                fma_sig_c_s2            <= fma_sig_c_s1;
                fma_exp_product_base_s2 <= fma_exp_product_base_s1;
                fma_exp_c_s2            <= fma_exp_c_s1;
                fma_c_zero_s2           <= fma_c_zero_s1;
            end

            if (fma_valid_pipe[2]) begin
                fma_meta_s3         <= fma_meta_s2;
                fma_product_wide_s3 <= fma_product_wide_from_s2;
                fma_c_wide_s3       <= fma_c_wide_from_s2;
                fma_exp_product_s3  <= fma_exp_product_from_s2;
                fma_exp_c_s3        <= fma_exp_c_from_s2;
            end

            if (fma_valid_pipe[3]) begin
                fma_meta_s4 <= fma_meta_s3;
                if ((fma_exp_product_s3 > fma_exp_c_s3) ||
                    ((fma_exp_product_s3 == fma_exp_c_s3) &&
                     (fma_product_wide_s3 >= fma_c_wide_s3))) begin
                    fma_big_s4       <= fma_product_wide_s3;
                    fma_small_s4     <= fma_c_wide_s3;
                    fma_exp_big_s4   <= fma_exp_product_s3;
                    fma_exp_small_s4 <= fma_exp_c_s3;
                    fma_sign_big_s4  <= fma_meta_s3.sign_product;
                end else begin
                    fma_big_s4       <= fma_c_wide_s3;
                    fma_small_s4     <= fma_product_wide_s3;
                    fma_exp_big_s4   <= fma_exp_c_s3;
                    fma_exp_small_s4 <= fma_exp_product_s3;
                    fma_sign_big_s4  <= fma_meta_s3.sign_c;
                end
            end

            if (fma_valid_pipe[4]) begin
                fma_meta_s5          <= fma_meta_s4;
                fma_big_s5           <= fma_big_s4;
                fma_small_aligned_s5 <= fma_aligned_small_from_s4;
                fma_exp_big_s5       <= fma_exp_big_s4;
                fma_sign_big_s5      <= fma_sign_big_s4;
            end

            if (fma_valid_pipe[5]) begin
                fma_meta_s6     <= fma_meta_s5;
                fma_exp_big_s6  <= fma_exp_big_s5;
                fma_sign_big_s6 <= fma_sign_big_s5;
                if (fma_meta_s5.sign_product == fma_meta_s5.sign_c)
                    fma_sum_s6 <= {1'b0, fma_big_s5} +
                                  {1'b0, fma_small_aligned_s5};
                else
                    fma_sum_s6 <= {1'b0,
                                   fma_big_s5 - fma_small_aligned_s5};
            end

            if (fma_valid_pipe[6]) begin
                fma_meta_s7         <= fma_meta_s6;
                fma_adjusted_s7     <= fma_adjusted_from_s6;
                fma_exp_adjusted_s7 <= fma_exp_adjusted_from_s6;
                fma_sign_big_s7     <= fma_sign_big_s6;
            end

            if (fma_valid_pipe[7]) begin
                fma_meta_s8         <= fma_meta_s7;
                fma_adjusted_s8     <= fma_adjusted_s7;
                fma_exp_adjusted_s8 <= fma_exp_adjusted_s7;
                fma_sign_big_s8     <= fma_sign_big_s7;
                fma_normalize_shift_s8 <= (fma_adjusted_s7 == 56'd0)
                    ? 6'd0 : leading_zero_count56(fma_adjusted_s7);
            end

            if (fma_valid_pipe[8]) begin
                fma_meta_s9       <= fma_meta_s8;
                fma_normalized_s9 <= fma_adjusted_s8 <<
                                     fma_normalize_shift_s8;
                fma_exp_normalized_s9 <= fma_exp_adjusted_s8 -
                    $signed({5'd0, fma_normalize_shift_s8});
                fma_sign_result_s9 <= (fma_adjusted_s8 == 56'd0)
                    ? (fma_meta_s8.rounding_mode == 3'b010)
                    : fma_sign_big_s8;
            end

            if (fma_valid_pipe[9])
                fma_result_pipe[10] <= fma_rounded_s9;
            if (fma_valid_pipe[10])
                fma_result_pipe[11] <= fma_result_pipe[10];
        end
    end

    // ---------------------------------------------------------------------
    // FMUL.S pipeline
    // M0: classify/unpack/normalize
    // M1: four 12x12 partial products
    // M2: partial-product reduction
    // M3: normalize, round and pack
    // M4..M11: align with the common response latency
    // ---------------------------------------------------------------------
    function automatic logic [97:0] prepare_multiply(
         input logic [31:0] a
        ,input logic [31:0] b
    );
        logic        special;
        logic [36:0] special_result;
        logic        sign_result;
        logic [23:0] sig_a;
        logic [23:0] sig_b;
        integer      exp_a;
        integer      exp_b;
        integer      shift_a;
        integer      shift_b;
        integer      exponent;
        begin
            sign_result   = a[31] ^ b[31];
            special       = 1'b1;
            special_result = 37'd0;
            sig_a         = 24'd0;
            sig_b         = 24'd0;
            exponent      = 0;
            if (fp_is_nan(a) || fp_is_nan(b)) begin
                special_result = {
                    (fp_is_snan(a) || fp_is_snan(b))
                    ? FLAG_NV : 5'd0, CANONICAL_NAN};
            end else if ((fp_is_inf(a) && fp_is_zero(b)) ||
                         (fp_is_zero(a) && fp_is_inf(b))) begin
                special_result = {FLAG_NV, CANONICAL_NAN};
            end else if (fp_is_inf(a) || fp_is_inf(b)) begin
                special_result = {5'd0, sign_result, 8'hFF, 23'd0};
            end else if (fp_is_zero(a) || fp_is_zero(b)) begin
                special_result = {5'd0, sign_result, 31'd0};
            end else begin
                special = 1'b0;
                shift_a = leading_zero_count24(
                    {a[30:23] != 0, a[22:0]});
                shift_b = leading_zero_count24(
                    {b[30:23] != 0, b[22:0]});
                sig_a = {a[30:23] != 0, a[22:0]} << shift_a;
                sig_b = {b[30:23] != 0, b[22:0]} << shift_b;
                exp_a = (a[30:23] == 0)
                    ? (-126 - shift_a) :
                      (int'(a[30:23]) - 127 - shift_a);
                exp_b = (b[30:23] == 0)
                    ? (-126 - shift_b) :
                      (int'(b[30:23]) - 127 - shift_b);
                exponent = exp_a + exp_b;
            end
            prepare_multiply = {
                special, special_result, sign_result,
                sig_a, sig_b, exponent[10:0]};
        end
    endfunction

    wire [97:0] mul_prepared = prepare_multiply(operand_a, operand_b);
    wire               mul_special_in;
    wire [36:0]        mul_special_result_in;
    wire               mul_sign_in;
    wire [23:0]        mul_sig_a_in;
    wire [23:0]        mul_sig_b_in;
    wire signed [10:0] mul_exponent_in;
    assign {mul_special_in, mul_special_result_in, mul_sign_in,
            mul_sig_a_in, mul_sig_b_in, mul_exponent_in} = mul_prepared;

    logic        mul_valid_pipe [0:FPU_PIPELINE_LATENCY];
    logic [36:0] mul_result_pipe[3:FPU_PIPELINE_LATENCY];

    logic               mul_special_s0;
    logic [36:0]        mul_special_result_s0;
    logic               mul_sign_s0;
    logic [23:0]        mul_sig_a_s0;
    logic [23:0]        mul_sig_b_s0;
    logic signed [10:0] mul_exponent_s0;
    logic [2:0]         mul_rounding_s0;

    logic               mul_special_s1;
    logic [36:0]        mul_special_result_s1;
    logic               mul_sign_s1;
    logic signed [10:0] mul_exponent_s1;
    logic [2:0]         mul_rounding_s1;
    logic [23:0]        mul_pp_ll_s1;
    logic [23:0]        mul_pp_lh_s1;
    logic [23:0]        mul_pp_hl_s1;
    logic [23:0]        mul_pp_hh_s1;

    logic               mul_special_s2;
    logic [36:0]        mul_special_result_s2;
    logic               mul_sign_s2;
    logic signed [10:0] mul_exponent_s2;
    logic [2:0]         mul_rounding_s2;
    logic [47:0]        mul_product_s2;

    wire [24:0] mul_cross_sum_s1 = {1'b0, mul_pp_lh_s1} +
                                    {1'b0, mul_pp_hl_s1};
    wire [48:0] mul_product_sum_s1 =
        {25'd0, mul_pp_ll_s1} +
        ({24'd0, mul_cross_sum_s1} << 12) +
        ({25'd0, mul_pp_hh_s1} << 24);

    function automatic logic [36:0] finish_multiply(
         input logic        special
        ,input logic [36:0] special_result
        ,input logic        sign_result
        ,input logic signed [10:0] exponent_in
        ,input logic [2:0]  rounding_mode
        ,input logic [47:0] product
    );
        logic [27:0] sig_ext;
        integer      exponent;
        begin
            if (special) begin
                finish_multiply = special_result;
            end else begin
                exponent = int'($signed(exponent_in)) +
                           (product[47] ? 1 : 0);
                if (product[47])
                    sig_ext = {1'b0, product[47:22], (|product[21:0])};
                else
                    sig_ext = {1'b0, product[46:21], (|product[20:0])};
                finish_multiply = round_pack(
                    sign_result, exponent, sig_ext, rounding_mode);
            end
        end
    endfunction

    wire [36:0] mul_rounded_s2 = finish_multiply(
        mul_special_s2, mul_special_result_s2, mul_sign_s2,
        mul_exponent_s2, mul_rounding_s2, mul_product_s2);

    integer mul_stage;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (mul_stage = 0;
                 mul_stage <= FPU_PIPELINE_LATENCY;
                 mul_stage = mul_stage + 1)
                mul_valid_pipe[mul_stage] <= 1'b0;
            for (mul_stage = 3;
                 mul_stage <= FPU_PIPELINE_LATENCY;
                 mul_stage = mul_stage + 1)
                mul_result_pipe[mul_stage] <= 37'd0;
            mul_special_s0        <= 1'b0;
            mul_special_result_s0 <= 37'd0;
            mul_sign_s0           <= 1'b0;
            mul_sig_a_s0          <= 24'd0;
            mul_sig_b_s0          <= 24'd0;
            mul_exponent_s0       <= 11'sd0;
            mul_rounding_s0       <= 3'd0;
            mul_special_s1        <= 1'b0;
            mul_special_result_s1 <= 37'd0;
            mul_sign_s1           <= 1'b0;
            mul_exponent_s1       <= 11'sd0;
            mul_rounding_s1       <= 3'd0;
            mul_pp_ll_s1          <= 24'd0;
            mul_pp_lh_s1          <= 24'd0;
            mul_pp_hl_s1          <= 24'd0;
            mul_pp_hh_s1          <= 24'd0;
            mul_special_s2        <= 1'b0;
            mul_special_result_s2 <= 37'd0;
            mul_sign_s2           <= 1'b0;
            mul_exponent_s2       <= 11'sd0;
            mul_rounding_s2       <= 3'd0;
            mul_product_s2        <= 48'd0;
        end else if (flush) begin
            for (mul_stage = 0;
                 mul_stage <= FPU_PIPELINE_LATENCY;
                 mul_stage = mul_stage + 1)
                mul_valid_pipe[mul_stage] <= 1'b0;
        end else begin
            mul_valid_pipe[0] <= start && request_is_multiply;
            mul_valid_pipe[1] <= mul_valid_pipe[0];
            mul_valid_pipe[2] <= mul_valid_pipe[1];
            mul_valid_pipe[3] <= mul_valid_pipe[2];
            for (mul_stage = 4;
                 mul_stage <= FPU_PIPELINE_LATENCY;
                 mul_stage = mul_stage + 1) begin
                mul_valid_pipe[mul_stage] <= mul_valid_pipe[mul_stage-1];
                if (mul_valid_pipe[mul_stage-1])
                    mul_result_pipe[mul_stage] <=
                        mul_result_pipe[mul_stage-1];
            end

            if (start && request_is_multiply) begin
                mul_special_s0        <= mul_special_in;
                mul_special_result_s0 <= mul_special_result_in;
                mul_sign_s0           <= mul_sign_in;
                mul_sig_a_s0          <= mul_sig_a_in;
                mul_sig_b_s0          <= mul_sig_b_in;
                mul_exponent_s0       <= mul_exponent_in;
                mul_rounding_s0       <= request_rounding_mode;
            end

            if (mul_valid_pipe[0]) begin
                mul_pp_ll_s1          <= mul_sig_a_s0[11:0] *
                                         mul_sig_b_s0[11:0];
                mul_pp_lh_s1          <= mul_sig_a_s0[11:0] *
                                         mul_sig_b_s0[23:12];
                mul_pp_hl_s1          <= mul_sig_a_s0[23:12] *
                                         mul_sig_b_s0[11:0];
                mul_pp_hh_s1          <= mul_sig_a_s0[23:12] *
                                         mul_sig_b_s0[23:12];
                mul_special_s1        <= mul_special_s0;
                mul_special_result_s1 <= mul_special_result_s0;
                mul_sign_s1           <= mul_sign_s0;
                mul_exponent_s1       <= mul_exponent_s0;
                mul_rounding_s1       <= mul_rounding_s0;
            end

            if (mul_valid_pipe[1]) begin
                mul_product_s2        <= mul_product_sum_s1[47:0];
                mul_special_s2        <= mul_special_s1;
                mul_special_result_s2 <= mul_special_result_s1;
                mul_sign_s2           <= mul_sign_s1;
                mul_exponent_s2       <= mul_exponent_s1;
                mul_rounding_s2       <= mul_rounding_s1;
            end

            if (mul_valid_pipe[2])
                mul_result_pipe[3] <= mul_rounded_s2;
        end
    end

    // ---------------------------------------------------------------------
    // FDIV.S pipeline
    // D0 classifies and normalizes. D1..D10 implement a fully unrolled
    // restoring divider, five quotient steps per registered stage. D11
    // merges the remainder into sticky and performs final rounding.
    // ---------------------------------------------------------------------
    function automatic logic [74:0] divide_five_steps(
         input logic [24:0] remainder_in
        ,input logic [49:0] quotient_in
        ,input logic [49:0] numerator
        ,input logic [23:0] divisor
        ,input integer      high_bit
    );
        logic [24:0] remainder_work;
        logic [49:0] quotient_work;
        integer      divide_step;
        integer      numerator_bit;
        begin
            remainder_work = remainder_in;
            quotient_work  = quotient_in;
            for (divide_step = 0;
                 divide_step < DIV_STEPS_PER_STAGE;
                 divide_step = divide_step + 1) begin
                numerator_bit = high_bit - divide_step;
                remainder_work = {
                    remainder_work[23:0], numerator[numerator_bit]};
                if (remainder_work >= {1'b0, divisor}) begin
                    remainder_work = remainder_work - {1'b0, divisor};
                    quotient_work[numerator_bit] = 1'b1;
                end
            end
            divide_five_steps = {remainder_work, quotient_work};
        end
    endfunction

    function automatic logic [97:0] prepare_divide(
         input logic [31:0] a
        ,input logic [31:0] b
    );
        logic        special;
        logic [36:0] special_result;
        logic        sign_result;
        logic [23:0] sig_a;
        logic [23:0] sig_b;
        integer      exp_a;
        integer      exp_b;
        integer      shift_a;
        integer      shift_b;
        integer      exponent;
        begin
            sign_result    = a[31] ^ b[31];
            special        = 1'b1;
            special_result = 37'd0;
            sig_a          = 24'd0;
            sig_b          = 24'd1;
            exponent       = 0;
            if (fp_is_nan(a) || fp_is_nan(b)) begin
                special_result = {
                    (fp_is_snan(a) || fp_is_snan(b))
                    ? FLAG_NV : 5'd0, CANONICAL_NAN};
            end else if ((fp_is_zero(a) && fp_is_zero(b)) ||
                         (fp_is_inf(a) && fp_is_inf(b))) begin
                special_result = {FLAG_NV, CANONICAL_NAN};
            end else if (fp_is_inf(a)) begin
                special_result = {5'd0, sign_result, 8'hFF, 23'd0};
            end else if (fp_is_inf(b)) begin
                special_result = {5'd0, sign_result, 31'd0};
            end else if (fp_is_zero(b)) begin
                special_result = {FLAG_DZ, sign_result, 8'hFF, 23'd0};
            end else if (fp_is_zero(a)) begin
                special_result = {5'd0, sign_result, 31'd0};
            end else begin
                special = 1'b0;
                shift_a = leading_zero_count24(
                    {a[30:23] != 0, a[22:0]});
                shift_b = leading_zero_count24(
                    {b[30:23] != 0, b[22:0]});
                sig_a = {a[30:23] != 0, a[22:0]} << shift_a;
                sig_b = {b[30:23] != 0, b[22:0]} << shift_b;
                exp_a = (a[30:23] == 0)
                    ? (-126 - shift_a) :
                      (int'(a[30:23]) - 127 - shift_a);
                exp_b = (b[30:23] == 0)
                    ? (-126 - shift_b) :
                      (int'(b[30:23]) - 127 - shift_b);
                exponent = exp_a - exp_b;
            end
            prepare_divide = {
                special, special_result, sign_result,
                sig_a, sig_b, exponent[10:0]};
        end
    endfunction

    wire [97:0] div_prepared = prepare_divide(operand_a, operand_b);
    wire               div_special_in;
    wire [36:0]        div_special_result_in;
    wire               div_sign_in;
    wire [23:0]        div_sig_a_in;
    wire [23:0]        div_sig_b_in;
    wire signed [10:0] div_exponent_in;
    assign {div_special_in, div_special_result_in, div_sign_in,
            div_sig_a_in, div_sig_b_in, div_exponent_in} = div_prepared;

    logic               div_valid_pipe [0:FPU_PIPELINE_LATENCY];
    logic [49:0]        div_numerator_pipe [0:DIV_PIPELINE_STAGES];
    logic [23:0]        div_divisor_pipe [0:DIV_PIPELINE_STAGES];
    logic [24:0]        div_remainder_pipe [0:DIV_PIPELINE_STAGES];
    logic [49:0]        div_quotient_pipe [0:DIV_PIPELINE_STAGES];
    logic               div_special_pipe [0:DIV_PIPELINE_STAGES];
    logic [36:0]        div_special_result_pipe [0:DIV_PIPELINE_STAGES];
    logic               div_sign_pipe [0:DIV_PIPELINE_STAGES];
    logic signed [10:0] div_exponent_pipe [0:DIV_PIPELINE_STAGES];
    logic [2:0]         div_rounding_pipe [0:DIV_PIPELINE_STAGES];
    wire [74:0]         div_step_comb [1:DIV_PIPELINE_STAGES];

    genvar div_generate_stage;
    generate
        for (div_generate_stage = 1;
             div_generate_stage <= DIV_PIPELINE_STAGES;
             div_generate_stage = div_generate_stage + 1) begin : g_divide
            localparam integer DIV_HIGH_BIT =
                54 - (DIV_STEPS_PER_STAGE * div_generate_stage);
            assign div_step_comb[div_generate_stage] =
                div_valid_pipe[div_generate_stage-1]
                ? divide_five_steps(
                    div_remainder_pipe[div_generate_stage-1],
                    div_quotient_pipe[div_generate_stage-1],
                    div_numerator_pipe[div_generate_stage-1],
                    div_divisor_pipe[div_generate_stage-1],
                    DIV_HIGH_BIT)
                : {div_remainder_pipe[div_generate_stage-1],
                   div_quotient_pipe[div_generate_stage-1]};
        end
    endgenerate

    function automatic logic [36:0] finish_divide(
         input logic        special
        ,input logic [36:0] special_result
        ,input logic        sign_result
        ,input logic signed [10:0] exponent_in
        ,input logic [2:0]  rounding_mode
        ,input logic [49:0] quotient
        ,input logic [24:0] remainder
    );
        logic [27:0] sig_ext;
        integer      exponent;
        begin
            if (special) begin
                finish_divide = special_result;
            end else begin
                sig_ext = {quotient[27:1],
                           quotient[0] | (remainder != 25'd0)};
                exponent = int'($signed(exponent_in));
                finish_divide = round_pack(
                    sign_result, exponent, sig_ext, rounding_mode);
            end
        end
    endfunction

    wire [36:0] div_rounded_final = finish_divide(
        div_special_pipe[DIV_PIPELINE_STAGES],
        div_special_result_pipe[DIV_PIPELINE_STAGES],
        div_sign_pipe[DIV_PIPELINE_STAGES],
        div_exponent_pipe[DIV_PIPELINE_STAGES],
        div_rounding_pipe[DIV_PIPELINE_STAGES],
        div_quotient_pipe[DIV_PIPELINE_STAGES],
        div_remainder_pipe[DIV_PIPELINE_STAGES]);

    logic [36:0] div_result_final;
    integer      div_stage;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (div_stage = 0;
                 div_stage <= FPU_PIPELINE_LATENCY;
                 div_stage = div_stage + 1)
                div_valid_pipe[div_stage] <= 1'b0;
            for (div_stage = 0;
                 div_stage <= DIV_PIPELINE_STAGES;
                 div_stage = div_stage + 1) begin
                div_numerator_pipe[div_stage]      <= 50'd0;
                div_divisor_pipe[div_stage]        <= 24'd1;
                div_remainder_pipe[div_stage]      <= 25'd0;
                div_quotient_pipe[div_stage]       <= 50'd0;
                div_special_pipe[div_stage]        <= 1'b0;
                div_special_result_pipe[div_stage] <= 37'd0;
                div_sign_pipe[div_stage]           <= 1'b0;
                div_exponent_pipe[div_stage]       <= 11'sd0;
                div_rounding_pipe[div_stage]       <= 3'd0;
            end
            div_result_final <= 37'd0;
        end else if (flush) begin
            for (div_stage = 0;
                 div_stage <= FPU_PIPELINE_LATENCY;
                 div_stage = div_stage + 1)
                div_valid_pipe[div_stage] <= 1'b0;
        end else begin
            div_valid_pipe[0] <= start && request_is_divide;
            if (start && request_is_divide) begin
                div_numerator_pipe[0] <= {div_sig_a_in, 26'd0};
                div_divisor_pipe[0]   <= div_sig_b_in;
                div_remainder_pipe[0] <= 25'd0;
                div_quotient_pipe[0]  <= 50'd0;
                div_special_pipe[0]   <= div_special_in;
                div_special_result_pipe[0] <= div_special_result_in;
                div_sign_pipe[0]      <= div_sign_in;
                div_exponent_pipe[0]  <= div_exponent_in;
                div_rounding_pipe[0]  <= request_rounding_mode;
            end

            for (div_stage = 1;
                 div_stage <= DIV_PIPELINE_STAGES;
                 div_stage = div_stage + 1) begin
                div_valid_pipe[div_stage] <= div_valid_pipe[div_stage-1];
                if (div_valid_pipe[div_stage-1]) begin
                    div_numerator_pipe[div_stage] <=
                        div_numerator_pipe[div_stage-1];
                    div_divisor_pipe[div_stage] <=
                        div_divisor_pipe[div_stage-1];
                    div_remainder_pipe[div_stage] <=
                        div_step_comb[div_stage][74:50];
                    div_quotient_pipe[div_stage] <=
                        div_step_comb[div_stage][49:0];
                    div_special_pipe[div_stage] <=
                        div_special_pipe[div_stage-1];
                    div_special_result_pipe[div_stage] <=
                        div_special_result_pipe[div_stage-1];
                    div_sign_pipe[div_stage] <=
                        div_sign_pipe[div_stage-1];
                    div_exponent_pipe[div_stage] <=
                        div_exponent_pipe[div_stage-1];
                    div_rounding_pipe[div_stage] <=
                        div_rounding_pipe[div_stage-1];
                end
            end

            div_valid_pipe[FPU_PIPELINE_LATENCY] <=
                div_valid_pipe[DIV_PIPELINE_STAGES];
            if (div_valid_pipe[DIV_PIPELINE_STAGES])
                div_result_final <= div_rounded_final;
        end
    end

    // Every accepted request has exactly one response at N+11. Since all
    // paths have the same latency, these mutually-exclusive valid bits also
    // preserve issue order for back-to-back mixed operations.
    always @(*) begin
        valid           = 1'b0;
        result          = 32'd0;
        exception_flags = 5'd0;
        if (div_valid_pipe[FPU_PIPELINE_LATENCY]) begin
            valid           = 1'b1;
            result          = div_result_final[31:0];
            exception_flags = div_result_final[36:32];
        end else if (fma_valid_pipe[FPU_PIPELINE_LATENCY]) begin
            valid           = 1'b1;
            result          =
                fma_result_pipe[FPU_PIPELINE_LATENCY][31:0];
            exception_flags =
                fma_result_pipe[FPU_PIPELINE_LATENCY][36:32];
        end else if (mul_valid_pipe[FPU_PIPELINE_LATENCY]) begin
            valid           = 1'b1;
            result          =
                mul_result_pipe[FPU_PIPELINE_LATENCY][31:0];
            exception_flags =
                mul_result_pipe[FPU_PIPELINE_LATENCY][36:32];
        end else if (generic_valid_pipe[FPU_PIPELINE_LATENCY]) begin
            valid           = 1'b1;
            result          =
                generic_result_pipe[FPU_PIPELINE_LATENCY][31:0];
            exception_flags =
                generic_result_pipe[FPU_PIPELINE_LATENCY][36:32];
        end
    end

endmodule
