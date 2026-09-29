`timescale 1ns/1ps

module hpm_csr_tb;
    logic debug_halt = 1'b0;
    logic clk;
    logic rst;
    logic execute;
    logic instr_valid;
    logic csr_en;
    logic mret;
    logic wfi;
    logic ecall;
    logic ebreak;
    logic illegal_instr;
    logic instruction_access_fault;
    logic [2:0] csr_funct3;
    logic [11:0] csr_addr;
    logic [4:0] csr_rs1;
    logic [31:0] csr_rs1_data;
    logic [31:0] current_pc;
    logic [31:0] trap_resume_pc;
    logic [31:0] instruction;
    logic [31:0] fetch_address;
    logic [31:0] data_address;
    logic data_access;
    logic data_write;
    logic [2:0] data_access_bytes;
    logic dma_interrupt;
    logic timer_interrupt;
    logic wdt_interrupt;
    logic [63:0] time_value;
    logic [7:0] hpm_events;
    logic fp_flags_valid;
    logic [4:0] fp_flags;
    logic fp_state_dirty;
    wire [31:0] csr_read_data;
    wire [31:0] redirect_pc;
    wire trap_taken;
    wire mret_taken;
    wire wfi_active;
    wire [2:0] fp_rounding_mode;
    wire fp_enabled;
    wire fetch_access_allowed;
    wire data_access_allowed;
    wire [1:0] current_privilege;
    integer checks;
    logic [63:0] saved_cycle;
    logic [63:0] saved_instret;

    always #5 clk = ~clk;

    csr_registers dut (.*);

    task automatic check(input logic condition, input string message);
        begin
            if (!condition) begin
                $error("FAIL: %s", message);
                $fatal(1);
            end
            checks = checks + 1;
            $display("PASS: %s", message);
        end
    endtask

    task automatic csr_write(
        input logic [11:0] address,
        input logic [31:0] value
    );
        begin
            @(negedge clk);
            execute = 1'b1;
            instr_valid = 1'b1;
            csr_en = 1'b1;
            csr_funct3 = 3'b001;
            csr_addr = address;
            csr_rs1_data = value;
            instruction = {address, 5'd1, 3'b001, 5'd0, 7'h73};
            #1;
            check(!trap_taken, "machine HPM CSR write is legal");
            @(posedge clk);
            #1;
            execute = 1'b0;
            instr_valid = 1'b0;
            csr_en = 1'b0;
        end
    endtask

    task automatic csr_read_check(
        input logic [11:0] address,
        input logic [31:0] expected,
        input string message
    );
        begin
            @(negedge clk);
            execute = 1'b1;
            instr_valid = 1'b1;
            csr_en = 1'b1;
            csr_funct3 = 3'b010;
            csr_addr = address;
            csr_rs1_data = 32'd0;
            instruction = {address, 5'd0, 3'b010, 5'd1, 7'h73};
            #1;
            check(!trap_taken, "HPM CSR read is legal");
            check(csr_read_data == expected, message);
            @(posedge clk);
            #1;
            execute = 1'b0;
            instr_valid = 1'b0;
            csr_en = 1'b0;
        end
    endtask

    task automatic enter_user_mode;
        begin
            csr_write(12'h300, 32'd0);
            csr_write(12'h341, 32'h0000_0100);
            @(negedge clk);
            execute = 1'b1;
            instr_valid = 1'b1;
            mret = 1'b1;
            instruction = 32'h3020_0073;
            #1;
            check(mret_taken, "MRET enters U-mode for counter gating test");
            @(posedge clk);
            #1;
            execute = 1'b0;
            instr_valid = 1'b0;
            mret = 1'b0;
            check(current_privilege == 2'b00, "processor is in U-mode");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        execute = 1'b0;
        instr_valid = 1'b0;
        csr_en = 1'b0;
        mret = 1'b0;
        wfi = 1'b0;
        ecall = 1'b0;
        ebreak = 1'b0;
        illegal_instr = 1'b0;
        instruction_access_fault = 1'b0;
        csr_funct3 = 3'b001;
        csr_addr = 12'd0;
        csr_rs1 = 5'd1;
        csr_rs1_data = 32'd0;
        current_pc = 32'h0000_0040;
        trap_resume_pc = 32'h0000_0044;
        instruction = 32'h0000_0013;
        fetch_address = 32'h0000_0040;
        data_address = 32'd0;
        data_access = 1'b0;
        data_write = 1'b0;
        data_access_bytes = 3'd4;
        dma_interrupt = 1'b0;
        timer_interrupt = 1'b0;
        wdt_interrupt = 1'b0;
        time_value = 64'd0;
        hpm_events = 8'd0;
        fp_flags_valid = 1'b0;
        fp_flags = 5'd0;
        fp_state_dirty = 1'b0;
        checks = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        csr_read_check(12'h323, 32'h01, "HPM3 defaults to branch event");
        csr_read_check(12'h324, 32'h02, "HPM4 defaults to branch-miss event");
        csr_read_check(12'h325, 32'h04, "HPM5 defaults to I-cache miss event");
        csr_read_check(12'h326, 32'h08, "HPM6 defaults to D-cache miss event");

        @(negedge clk);
        hpm_events = 8'h01;
        repeat (3) @(posedge clk);
        #1;
        hpm_events = 8'h00;
        check(dut.hpm_counter[0] == 64'd3,
              "HPM3 counts one branch event per cycle");

        @(negedge clk);
        hpm_events = 8'h02;
        repeat (2) @(posedge clk);
        #1;
        hpm_events = 8'h00;
        check(dut.hpm_counter[1] == 64'd2,
              "HPM4 counts branch-miss events");

        csr_write(12'h325, 32'h0000_0018);
        @(negedge clk);
        hpm_events = 8'h18;
        @(posedge clk);
        #1;
        hpm_events = 8'h00;
        check(dut.hpm_counter[2] == 64'd1,
              "an event mask increments at most once per cycle");

        csr_write(12'h320, 32'h0000_0020);
        @(negedge clk);
        hpm_events = 8'h18;
        repeat (3) @(posedge clk);
        #1;
        hpm_events = 8'h00;
        check(dut.hpm_counter[2] == 64'd1,
              "mcountinhibit stops the selected HPM counter");

        csr_write(12'h320, 32'h0000_0001);
        saved_cycle = dut.cycle_counter;
        repeat (3) @(posedge clk);
        #1;
        check(dut.cycle_counter == saved_cycle,
              "mcountinhibit.CY stops mcycle");
        csr_write(12'h320, 32'h0000_0004);
        saved_instret = dut.instret_counter;
        @(negedge clk);
        execute = 1'b1;
        instr_valid = 1'b1;
        csr_en = 1'b0;
        instruction = 32'h0000_0013;
        repeat (3) @(posedge clk);
        #1;
        execute = 1'b0;
        instr_valid = 1'b0;
        check(dut.instret_counter == saved_instret,
              "mcountinhibit.IR stops minstret");
        csr_write(12'h320, 32'd0);

        csr_write(12'hB03, 32'h89AB_CDEF);
        csr_write(12'hB83, 32'h0123_4567);
        csr_read_check(12'hB03, 32'h89AB_CDEF,
                       "machine HPM low word is writable");
        csr_read_check(12'hB83, 32'h0123_4567,
                       "machine HPM high word is writable");

        csr_write(12'h306, 32'd0);
        enter_user_mode();
        @(negedge clk);
        execute = 1'b1;
        instr_valid = 1'b1;
        csr_en = 1'b1;
        csr_funct3 = 3'b010;
        csr_addr = 12'hC03;
        csr_rs1_data = 32'd0;
        instruction = 32'hC030_20F3;
        #1;
        check(trap_taken, "U-mode HPM read is gated by mcounteren");
        @(posedge clk);
        #1;
        execute = 1'b0;
        instr_valid = 1'b0;
        csr_en = 1'b0;
        check(current_privilege == 2'b11,
              "denied U-mode HPM read traps to M-mode");

        csr_write(12'h306, 32'h0000_0008);
        enter_user_mode();
        csr_read_check(12'hC03, 32'h89AB_CDEF,
                       "mcounteren.HPM3 exposes the user counter alias");

        $display("[HPM CSR PASS] %0d checks passed", checks);
        $finish;
    end
endmodule
