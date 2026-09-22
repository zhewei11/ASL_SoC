`timescale 1ns/1ps

module rv32f_unit_tb;
    logic clk;
    logic rst;
    logic flush;
    logic start;
    logic [31:0] instruction;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] operand_c;
    logic [2:0] frm;
    wire [31:0] result;
    wire [4:0] flags;
    wire valid;
    integer checks;

    always #5 clk = ~clk;

    rv32f_unit dut (
         .clk(clk), .rst(rst), .flush(flush), .start(start)
        ,.instruction(instruction)
        ,.operand_a(operand_a), .operand_b(operand_b)
        ,.operand_c(operand_c), .dynamic_rounding_mode(frm)
        ,.result(result), .exception_flags(flags), .valid(valid)
    );

    function automatic logic [31:0] op_fp(
         input logic [6:0] funct7
        ,input logic [4:0] rs2
        ,input logic [2:0] rm
    );
        op_fp = {funct7, rs2, 5'd1, rm, 5'd3, 7'b1010011};
    endfunction

    function automatic logic [31:0] op_fma(input logic [6:0] opcode);
        op_fma = {5'd3, 2'b00, 5'd2, 5'd1, 3'b000, 5'd4, opcode};
    endfunction

    task automatic run_case(
         input logic [31:0] inst
        ,input logic [31:0] a
        ,input logic [31:0] b
        ,input logic [31:0] c
        ,input logic [31:0] expected_result
        ,input logic [4:0]  expected_flags
        ,input string       label_text
    );
        integer cycles;
        begin
            @(negedge clk);
            instruction = inst;
            operand_a = a;
            operand_b = b;
            operand_c = c;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            cycles = 0;
            while (!valid) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (cycles > 20)
                    $fatal(1, "%s timed out", label_text);
            end
            if (cycles != 11)
                $fatal(1, "%s latency=%0d expected=11",
                       label_text, cycles);
            if (result !== expected_result || flags !== expected_flags)
                $fatal(1, "%s result=%08h flags=%02h expected=%08h/%02h",
                       label_text, result, flags,
                       expected_result, expected_flags);
            checks = checks + 1;
            @(posedge clk);
            #1;
            if (valid)
                $fatal(1, "%s valid was not a one-cycle response", label_text);
        end
    endtask

    task automatic run_mixed_pipeline_burst;
        integer issue_index;
        integer response_index;
        integer wait_cycles;
        logic [31:0] expected_result;
        logic [4:0] expected_flags;
        begin
            // Generic, multiply, divide, and fused requests are accepted
            // on adjacent cycles and must return in exactly the same order.
            for (issue_index = 0; issue_index < 4;
                 issue_index = issue_index + 1) begin
                @(negedge clk);
                operand_c = 32'd0;
                case (issue_index)
                    0: begin
                        instruction = op_fp(7'b0000000, 5'd2, 3'b000);
                        operand_a = 32'h3FC0_0000;
                        operand_b = 32'h4010_0000;
                    end
                    1: begin
                        instruction = op_fp(7'b0001000, 5'd2, 3'b000);
                        operand_a = 32'h3FC0_0000;
                        operand_b = 32'h4010_0000;
                    end
                    2: begin
                        instruction = op_fp(7'b0001100, 5'd2, 3'b000);
                        operand_a = 32'h3FC0_0000;
                        operand_b = 32'h4010_0000;
                    end
                    default: begin
                        instruction = op_fma(7'b1000011);
                        operand_a = 32'h3FC0_0000;
                        operand_b = 32'h4000_0000;
                        operand_c = 32'h3E80_0000;
                    end
                endcase
                start = 1'b1;
                @(posedge clk);
                #1;
                if (valid)
                    $fatal(1, "Mixed FPU pipeline responded too early");
            end
            start = 1'b0;

            wait_cycles = 0;
            while (!valid) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 12)
                    $fatal(1, "Mixed FPU pipeline timed out");
            end
            if (wait_cycles != 8)
                $fatal(1, "Mixed pipeline first response delay=%0d",
                       wait_cycles);

            for (response_index = 0; response_index < 4;
                 response_index = response_index + 1) begin
                case (response_index)
                    0: begin
                        expected_result = 32'h4070_0000;
                        expected_flags = 5'd0;
                    end
                    1: begin
                        expected_result = 32'h4058_0000;
                        expected_flags = 5'd0;
                    end
                    2: begin
                        expected_result = 32'h3F2A_AAAB;
                        expected_flags = 5'b0_0001;
                    end
                    default: begin
                        expected_result = 32'h4050_0000;
                        expected_flags = 5'd0;
                    end
                endcase
                if (!valid || result !== expected_result ||
                    flags !== expected_flags)
                    $fatal(1,
                           "Mixed response %0d got=%08h/%02h expected=%08h/%02h",
                           response_index, result, flags,
                           expected_result, expected_flags);
                checks = checks + 1;
                if (response_index < 3) begin
                    @(posedge clk);
                    #1;
                end
            end
            @(posedge clk);
            #1;
            if (valid)
                $fatal(1, "Mixed FPU pipeline emitted an extra response");
        end
    endtask

    task automatic run_fma_pipeline_burst;
        integer issue_index;
        integer response_index;
        integer wait_cycles;
        logic [31:0] expected_result;
        begin
            // All four fused opcodes enter on adjacent cycles. Their products
            // must remain unrounded until the add/subtract and responses must
            // retain issue order at the common eleven-cycle latency.
            for (issue_index = 0; issue_index < 4;
                 issue_index = issue_index + 1) begin
                @(negedge clk);
                case (issue_index)
                    0: instruction = op_fma(7'b1000011); // FMADD.S
                    1: instruction = op_fma(7'b1000111); // FMSUB.S
                    2: instruction = op_fma(7'b1001011); // FNMSUB.S
                    default: instruction = op_fma(7'b1001111); // FNMADD.S
                endcase
                operand_a = 32'h3FC0_0000; // 1.5
                operand_b = 32'h4000_0000; // 2.0
                operand_c = 32'h3E80_0000; // 0.25
                start = 1'b1;
                @(posedge clk);
                #1;
                if (valid)
                    $fatal(1, "FMA pipeline responded too early");
            end
            start = 1'b0;

            wait_cycles = 0;
            while (!valid) begin
                @(posedge clk);
                #1;
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 12)
                    $fatal(1, "FMA pipeline timed out");
            end
            if (wait_cycles != 8)
                $fatal(1, "FMA pipeline first response delay=%0d",
                       wait_cycles);

            for (response_index = 0; response_index < 4;
                 response_index = response_index + 1) begin
                case (response_index)
                    0: expected_result = 32'h4050_0000; // +3.25
                    1: expected_result = 32'h4030_0000; // +2.75
                    2: expected_result = 32'hC030_0000; // -2.75
                    default: expected_result = 32'hC050_0000; // -3.25
                endcase
                if (!valid || result !== expected_result || flags !== 5'd0)
                    $fatal(1,
                           "FMA response %0d got=%08h/%02h expected=%08h/00",
                           response_index, result, flags, expected_result);
                checks = checks + 1;
                if (response_index < 3) begin
                    @(posedge clk);
                    #1;
                end
            end
            @(posedge clk);
            #1;
            if (valid)
                $fatal(1, "FMA pipeline emitted an extra response");
        end
    endtask

    task automatic flush_divide_pipeline;
        integer wait_cycle;
        begin
            @(negedge clk);
            instruction = op_fp(7'b0001100, 5'd2, 3'b000);
            operand_a = 32'h4120_0000;
            operand_b = 32'h4040_0000;
            operand_c = 32'd0;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            flush = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            flush = 1'b0;
            for (wait_cycle = 0; wait_cycle < 13;
                 wait_cycle = wait_cycle + 1) begin
                @(posedge clk);
                #1;
                if (valid)
                    $fatal(1, "Flushed FDIV produced a ghost response");
            end
            checks = checks + 1;
        end
    endtask

    task automatic flush_fma_pipeline;
        integer wait_cycle;
        begin
            @(negedge clk);
            instruction = op_fma(7'b1000011);
            operand_a = 32'h4461_0959;
            operand_b = 32'hC09A_511D;
            operand_c = 32'h4465_6612;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            repeat (5) @(posedge clk);
            @(negedge clk);
            flush = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            flush = 1'b0;
            for (wait_cycle = 0; wait_cycle < 13;
                 wait_cycle = wait_cycle + 1) begin
                @(posedge clk);
                #1;
                if (valid)
                    $fatal(1, "Flushed FMA produced a ghost response");
            end
            checks = checks + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        flush = 1'b0;
        start = 1'b0;
        instruction = 32'd0;
        operand_a = 32'd0;
        operand_b = 32'd0;
        operand_c = 32'd0;
        frm = 3'b000;
        checks = 0;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        run_case(op_fp(7'b0000000, 5'd2, 3'b000),
                 32'h3FC0_0000, 32'h4010_0000, 32'd0,
                 32'h4070_0000, 5'd0, "FADD.S");
        run_case(op_fp(7'b0000100, 5'd2, 3'b000),
                 32'h3FC0_0000, 32'h4010_0000, 32'd0,
                 32'hBF40_0000, 5'd0, "FSUB.S");
        run_case(op_fp(7'b0001000, 5'd2, 3'b000),
                 32'h3FC0_0000, 32'h4010_0000, 32'd0,
                 32'h4058_0000, 5'd0, "FMUL.S");
        run_case(op_fp(7'b0001100, 5'd2, 3'b000),
                 32'h3FC0_0000, 32'h4010_0000, 32'd0,
                 32'h3F2A_AAAB, 5'b0_0001, "FDIV.S");
        run_case(op_fp(7'b0101100, 5'd0, 3'b000),
                 32'h4010_0000, 32'd0, 32'd0,
                 32'h3FC0_0000, 5'd0, "FSQRT.S");
        run_case(op_fma(7'b1000011),
                 32'h3FC0_0000, 32'h4000_0000, 32'h3E80_0000,
                 32'h4050_0000, 5'd0, "FMADD.S");
        // This vector differs by one ULP from a separately rounded multiply
        // followed by add, so it guards the fused single-rounding property.
        run_case(op_fma(7'b1000011),
                 32'h4461_0959, 32'hC09A_511D, 32'h4465_6612,
                 32'hC555_F455, 5'b0_0001, "FMADD.S fused rounding");
        run_case(op_fma(7'b1000011),
                 32'h7F80_0000, 32'h0000_0000, 32'h3F80_0000,
                 32'h7FC0_0000, 5'b1_0000, "FMADD.S infinity times zero");
        run_case(op_fp(7'b0010000, 5'd2, 3'b001),
                 32'h3FC0_0000, 32'h8000_0000, 32'd0,
                 32'h3FC0_0000, 5'd0, "FSGNJN.S");
        run_case(op_fp(7'b1010000, 5'd2, 3'b001),
                 32'hBF80_0000, 32'h3F80_0000, 32'd0,
                 32'd1, 5'd0, "FLT.S");
        run_case(op_fp(7'b1100000, 5'd0, 3'b000),
                 32'h4070_0000, 32'd0, 32'd0,
                 32'd4, 5'b0_0001, "FCVT.W.S");
        run_case(op_fp(7'b1101000, 5'd0, 3'b000),
                 32'hFFFF_FFF9, 32'd0, 32'd0,
                 32'hC0E0_0000, 5'd0, "FCVT.S.W");
        run_case(op_fp(7'b1110000, 5'd0, 3'b001),
                 32'h7FC0_0000, 32'd0, 32'd0,
                 32'h0000_0200, 5'd0, "FCLASS.S");
        run_case(op_fp(7'b0001100, 5'd2, 3'b000),
                 32'h3F80_0000, 32'h0000_0000, 32'd0,
                 32'h7F80_0000, 5'b0_1000, "FDIV.S divide by zero");
        run_case(op_fp(7'b0101100, 5'd0, 3'b000),
                 32'hBF80_0000, 32'd0, 32'd0,
                 32'h7FC0_0000, 5'b1_0000, "FSQRT.S negative");
        run_case(op_fp(7'b0000000, 5'd2, 3'b000),
                 32'h3F80_0000, 32'h3380_0000, 32'd0,
                 32'h3F80_0000, 5'b0_0001, "RNE tie-to-even");
        run_case(op_fp(7'b0000000, 5'd2, 3'b100),
                 32'h3F80_0000, 32'h3380_0000, 32'd0,
                 32'h3F80_0001, 5'b0_0001, "RMM tie-away");
        run_case(op_fp(7'b0001000, 5'd2, 3'b000),
                 32'h0000_0001, 32'h3F00_0000, 32'd0,
                 32'h0000_0000, 5'b0_0011, "subnormal underflow");

        run_mixed_pipeline_burst();
        run_fma_pipeline_burst();
        flush_divide_pipeline();
        flush_fma_pipeline();
        run_case(op_fp(7'b0001000, 5'd2, 3'b000),
                 32'h4000_0000, 32'h4040_0000, 32'd0,
                 32'h40C0_0000, 5'd0, "FMUL.S after flush");

        $display("[RV32F PASS] %0d arithmetic, conversion and flag checks passed",
                 checks);
        $finish;
    end
endmodule
