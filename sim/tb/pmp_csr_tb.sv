`timescale 1ns/1ps

module pmp_csr_tb;
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
            check(!trap_taken, "machine CSR write is legal");
            @(posedge clk);
            #1;
            execute = 1'b0;
            instr_valid = 1'b0;
            csr_en = 1'b0;
        end
    endtask

    task automatic execute_mret;
        begin
            @(negedge clk);
            execute = 1'b1;
            instr_valid = 1'b1;
            mret = 1'b1;
            instruction = 32'h3020_0073;
            #1;
            check(mret_taken, "legal MRET redirects to lower privilege");
            @(posedge clk);
            #1;
            execute = 1'b0;
            instr_valid = 1'b0;
            mret = 1'b0;
        end
    endtask

    task automatic take_fault(
        input logic instruction_fault,
        input logic memory_access,
        input logic memory_write,
        input logic [31:0] expected_cause,
        input logic [31:0] expected_mtval
    );
        begin
            @(negedge clk);
            execute = 1'b1;
            instr_valid = 1'b1;
            instruction_access_fault = instruction_fault;
            data_access = memory_access;
            data_write = memory_write;
            #1;
            check(trap_taken, "denied access raises a precise trap");
            @(posedge clk);
            #1;
            execute = 1'b0;
            instr_valid = 1'b0;
            instruction_access_fault = 1'b0;
            data_access = 1'b0;
            check(dut.mcause == expected_cause, "access-fault cause is correct");
            check(dut.mtval == expected_mtval, "access-fault mtval is correct");
            check(current_privilege == 2'b11, "trap returns control to M-mode");
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
        current_pc = 32'h0000_0100;
        trap_resume_pc = 32'h0000_0104;
        instruction = 32'h0000_0013;
        fetch_address = 32'h0000_0100;
        data_address = 32'd0;
        data_access = 1'b0;
        data_write = 1'b0;
        data_access_bytes = 3'd4;
        dma_interrupt = 1'b0;
        timer_interrupt = 1'b0;
        wdt_interrupt = 1'b0;
        time_value = 64'd0;
        fp_flags_valid = 1'b0;
        fp_flags = 5'd0;
        fp_state_dirty = 1'b0;
        checks = 0;

        repeat (3) @(posedge clk);
        rst = 1'b0;
        #1;
        check(current_privilege == 2'b11, "reset starts in M-mode");
        check(fetch_access_allowed, "M-mode allows an unmatched fetch");

        // Entry 0: TOR [0x0000,0x1000), R-X.
        // Entry 1: TOR [0x1000,0x2000), RW-.
        // Entry 2: NA4 [0x3000,0x3004), R--.
        // Entry 3: NAPOT [0x4000,0x4010), RWX.
        csr_write(12'h3B0, 32'h0000_0400);
        csr_write(12'h3B1, 32'h0000_0800);
        csr_write(12'h3B2, 32'h0000_0C00);
        csr_write(12'h3B3, 32'h0000_1001);
        csr_write(12'h3A0, 32'h1F11_0B0D);

        // Entry 4 denies an overlapping NA4 range before entry 5's permissive
        // NAPOT range. Entry 7 is a locked TOR entry and locks pmpaddr6 too.
        csr_write(12'h3B4, 32'h0000_1400);
        csr_write(12'h3B5, 32'h0000_1400);
        csr_write(12'h3B6, 32'h0000_1800);
        csr_write(12'h3B7, 32'h0000_1900);
        csr_write(12'h3A1, 32'h8900_1F10);
        csr_write(12'h3B6, 32'hdead_beef);
        csr_write(12'h3B7, 32'hdead_beef);
        check(dut.pmpaddr[6] == 32'h0000_1800,
              "locked TOR entry locks its lower-bound register");
        check(dut.pmpaddr[7] == 32'h0000_1900,
              "locked PMP entry rejects address updates");
        data_address = 32'h0000_6000;
        data_access_bytes = 3'd4;
        data_write = 1'b0;
        #1;
        check(data_access_allowed, "locked PMP read permission applies in M-mode");
        data_write = 1'b1;
        #1;
        check(!data_access_allowed,
              "locked PMP write denial is enforced in M-mode");

        // MPRV applies MPP privilege to load/store without lowering the
        // kernel itself.  Instruction fetch remains at the real privilege.
        data_address = 32'h0000_7000;
        data_write = 1'b0;
        #1;
        check(data_access_allowed,
              "M-mode unmatched data access is allowed without MPRV");
        csr_write(12'h300, 32'h0002_0000);
        #1;
        check(!data_access_allowed,
              "MPRV applies U-mode PMP policy to M-mode data access");
        fetch_address = 32'h0000_7000;
        #1;
        check(fetch_access_allowed,
              "MPRV does not change instruction-fetch privilege");

        csr_write(12'h341, 32'h0000_0100);
        execute_mret();
        check(current_privilege == 2'b00, "MRET enters U-mode");
        check(!dut.mstatus[17], "MRET to U-mode clears MPRV");

        fetch_address = 32'h0000_0100;
        #1;
        check(fetch_access_allowed, "U-mode executes inside an X TOR region");
        fetch_address = 32'h0000_1000;
        #1;
        check(!fetch_access_allowed, "U-mode cannot execute a non-X region");
        fetch_address = 32'h0000_400c;
        #1;
        check(fetch_access_allowed, "NAPOT covers its complete encoded range");
        fetch_address = 32'h0000_4010;
        #1;
        check(!fetch_access_allowed, "NAPOT rejects the first byte past range");
        fetch_address = 32'h0000_5000;
        #1;
        check(!fetch_access_allowed, "lowest-numbered matching entry wins");

        data_address = 32'h0000_1004;
        data_access_bytes = 3'd4;
        data_write = 1'b0;
        #1;
        check(data_access_allowed, "U-mode can read an RW TOR region");
        data_write = 1'b1;
        #1;
        check(data_access_allowed, "U-mode can write an RW TOR region");
        data_address = 32'h0000_0000;
        #1;
        check(!data_access_allowed, "R-X region blocks U-mode stores");
        data_address = 32'h0000_3000;
        data_write = 1'b0;
        #1;
        check(data_access_allowed, "NA4 permits its four-byte word");
        data_address = 32'h0000_3004;
        #1;
        check(!data_access_allowed, "NA4 rejects the adjacent word");
        data_address = 32'h0000_0ffe;
        data_access_bytes = 3'd4;
        #1;
        check(!data_access_allowed, "access crossing PMP entries is denied");

        current_pc = 32'h0000_1000;
        take_fault(1'b1, 1'b0, 1'b0, 32'd1, 32'h0000_1000);
        execute_mret();
        data_address = 32'h0000_0000;
        data_access_bytes = 3'd4;
        take_fault(1'b0, 1'b1, 1'b1, 32'd7, 32'h0000_0000);

        execute_mret();
        @(negedge clk);
        execute = 1'b1;
        instr_valid = 1'b1;
        csr_en = 1'b1;
        csr_funct3 = 3'b010;
        csr_addr = 12'h300;
        csr_rs1_data = 32'd0;
        instruction = 32'h3000_2273;
        #1;
        check(trap_taken, "U-mode access to a machine CSR is illegal");
        @(posedge clk);
        #1;
        check(dut.mcause == 32'd2, "illegal CSR access reports cause 2");

        $display("[PMP CSR PASS] %0d U-mode/PMP checks passed", checks);
        $finish;
    end
endmodule
