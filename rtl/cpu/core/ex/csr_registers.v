`include "rtos_core_config.svh"

module csr_registers #(
     parameter ENABLE_FPU = 1'b1
) (
     input              clk
    ,input              rst
    ,input              execute
    ,input              instr_valid
    ,input              csr_en
    ,input              mret
    ,input              wfi
    ,input              ecall
    ,input              ebreak
    ,input              illegal_instr
    ,input              instruction_access_fault
    ,input      [2:0]   csr_funct3
    ,input      [11:0]  csr_addr
    ,input      [4:0]   csr_rs1
    ,input      [31:0]  csr_rs1_data
    ,input      [31:0]  current_pc
    ,input      [31:0]  trap_resume_pc
    ,input      [31:0]  instruction
    ,input      [31:0]  fetch_address
    ,input      [31:0]  data_address
    ,input              data_access
    ,input              data_write
    ,input      [2:0]   data_access_bytes
    ,input              dma_interrupt
    ,input              timer_interrupt
    ,input              wdt_interrupt
    ,input      [63:0]  time_value
    ,input              fp_flags_valid
    ,input      [4:0]   fp_flags
    ,input              fp_state_dirty
    ,output reg [31:0]  csr_read_data
    ,output     [31:0]  redirect_pc
    ,output             trap_taken
    ,output             mret_taken
    ,output reg         wfi_active
    ,output     [2:0]   fp_rounding_mode
    ,output             fp_enabled
    ,output             fetch_access_allowed
    ,output             data_access_allowed
    ,output     [1:0]   current_privilege
);

    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_M = 2'b11;

    localparam CSR_FFLAGS     = 12'h001;
    localparam CSR_FRM        = 12'h002;
    localparam CSR_FCSR       = 12'h003;
    localparam CSR_MSTATUS    = 12'h300;
    localparam CSR_MISA       = 12'h301;
    localparam CSR_MIE        = 12'h304;
    localparam CSR_MTVEC      = 12'h305;
    localparam CSR_MCOUNTEREN = 12'h306;
    localparam CSR_MSCRATCH   = 12'h340;
    localparam CSR_MEPC       = 12'h341;
    localparam CSR_MCAUSE     = 12'h342;
    localparam CSR_MTVAL      = 12'h343;
    localparam CSR_MIP        = 12'h344;
    localparam CSR_PMPCFG0    = 12'h3A0;
    localparam CSR_PMPCFG1    = 12'h3A1;
    localparam CSR_PMPADDR0   = 12'h3B0;
    localparam CSR_PMPADDR7   = 12'h3B7;
    localparam CSR_MCYCLE     = 12'hB00;
    localparam CSR_MINSTRET   = 12'hB02;
    localparam CSR_MCYCLEH    = 12'hB80;
    localparam CSR_MINSTRETH  = 12'hB82;
    localparam CSR_CYCLE      = 12'hC00;
    localparam CSR_TIME       = 12'hC01;
    localparam CSR_INSTRET    = 12'hC02;
    localparam CSR_CYCLEH     = 12'hC80;
    localparam CSR_TIMEH      = 12'hC81;
    localparam CSR_INSTRETH   = 12'hC82;
    localparam CSR_MVENDORID  = 12'hF11;
    localparam CSR_MARCHID    = 12'hF12;
    localparam CSR_MIMPID     = 12'hF13;
    localparam CSR_MHARTID    = 12'hF14;
    localparam CSR_MCONFIGPTR = 12'hF15;

    localparam [1:0] PMP_ACCESS_READ  = 2'd0;
    localparam [1:0] PMP_ACCESS_WRITE = 2'd1;
    localparam [1:0] PMP_ACCESS_EXEC  = 2'd2;
    localparam [1:0] PMP_A_OFF        = 2'd0;
    localparam [1:0] PMP_A_TOR        = 2'd1;
    localparam [1:0] PMP_A_NA4        = 2'd2;
    localparam [1:0] PMP_A_NAPOT      = 2'd3;

    // MPRV lets an M-mode kernel validate/copy a task buffer using the
    // privilege stored in MPP.  It affects data accesses only.
    localparam [31:0] MSTATUS_MASK = ENABLE_FPU ? 32'h0002_7888 :
                                                    32'h0002_1888;
    localparam [31:0] MIE_MASK = 32'h0000_0880;
    localparam [31:0] MISA_VALUE = ENABLE_FPU ?
                                     `RTOS_CORE_CPU_MISA_VALUE :
                                     32'h4010_1100;

    localparam [31:0] CAUSE_INSTRUCTION_ACCESS = 32'd1;
    localparam [31:0] CAUSE_ILLEGAL_INSTRUCTION = 32'd2;
    localparam [31:0] CAUSE_BREAKPOINT = 32'd3;
    localparam [31:0] CAUSE_LOAD_ACCESS = 32'd5;
    localparam [31:0] CAUSE_STORE_ACCESS = 32'd7;
    localparam [31:0] CAUSE_ECALL_U = 32'd8;
    localparam [31:0] CAUSE_ECALL_M = 32'd11;
    localparam [31:0] CAUSE_M_TIMER_INTERRUPT = 32'h8000_0007;
    localparam [31:0] CAUSE_M_EXTERNAL_INTERRUPT = 32'h8000_000B;

    reg [31:0] mstatus;
    reg [31:0] mie;
    reg [31:0] mtvec;
    reg [31:0] mcounteren;
    reg [31:0] mscratch;
    reg [31:0] mepc;
    reg [31:0] mcause;
    reg [31:0] mtval;
    reg [4:0]  fflags;
    reg [2:0]  frm;
    reg [31:0] wfi_resume_pc;
    reg [63:0] cycle_counter;
    reg [63:0] instret_counter;
    reg        wdt_pending_q;
    reg [1:0]  privilege_q;
    reg [7:0]  pmpcfg [0:7];
    reg [31:0] pmpaddr [0:7];
    integer    pmp_i;

    assign current_privilege = privilege_q;
    assign fp_rounding_mode = frm;
    assign fp_enabled = ENABLE_FPU && |mstatus[14:13];

    function automatic pmp_byte_matches;
        input integer entry;
        input [32:0] byte_address;
        reg [33:0] extended_address;
        reg [33:0] lower_bound;
        reg [33:0] upper_bound;
        reg [31:0] address_granule;
        reg [31:0] napot_mask;
        reg        found_zero;
        integer    bit_i;
        begin
            extended_address = {1'b0, byte_address};
            address_granule = {2'b00, byte_address[31:2]};
            lower_bound = 34'd0;
            upper_bound = 34'd0;
            napot_mask = 32'hffff_ffff;
            found_zero = 1'b0;
            pmp_byte_matches = 1'b0;

            if (!byte_address[32]) begin
                case (pmpcfg[entry][4:3])
                    PMP_A_TOR: begin
                        lower_bound = (entry == 0) ? 34'd0 :
                                      {pmpaddr[entry-1], 2'b00};
                        upper_bound = {pmpaddr[entry], 2'b00};
                        pmp_byte_matches =
                            (extended_address >= lower_bound) &&
                            (extended_address < upper_bound);
                    end
                    PMP_A_NA4:
                        pmp_byte_matches =
                            (address_granule == pmpaddr[entry]);
                    PMP_A_NAPOT: begin
                        // Ignore the trailing-one run and the first zero above
                        // it. Therefore x...x0 is the minimum 8-byte region.
                        for (bit_i = 0; bit_i < 32; bit_i = bit_i + 1) begin
                            if (!found_zero) begin
                                napot_mask[bit_i] = 1'b0;
                                if (!pmpaddr[entry][bit_i])
                                    found_zero = 1'b1;
                            end
                        end
                        pmp_byte_matches =
                            ((address_granule & napot_mask) ==
                             (pmpaddr[entry] & napot_mask));
                    end
                    default:
                        pmp_byte_matches = 1'b0;
                endcase
            end
        end
    endfunction

    // The lowest-numbered entry which overlaps any byte controls the access.
    // A transaction that crosses that entry's boundary is denied.
    function automatic pmp_access_allowed;
        input [31:0] address;
        input [2:0]  access_bytes;
        input [1:0]  privilege;
        input [1:0]  access_kind;
        reg        entry_any_match;
        reg        entry_all_match;
        reg        entry_permission;
        reg        found_entry;
        reg [32:0] checked_address;
        integer    entry_i;
        integer    byte_i;
        begin
            pmp_access_allowed = (privilege == PRIV_M);
            found_entry = 1'b0;

            for (entry_i = 0; entry_i < 8; entry_i = entry_i + 1) begin
                entry_any_match = 1'b0;
                entry_all_match = 1'b1;
                for (byte_i = 0; byte_i < 4; byte_i = byte_i + 1) begin
                    checked_address = {1'b0, address} + byte_i;
                    if (byte_i < access_bytes) begin
                        if (pmp_byte_matches(entry_i, checked_address))
                            entry_any_match = 1'b1;
                        else
                            entry_all_match = 1'b0;
                    end
                end

                if (!found_entry && entry_any_match) begin
                    found_entry = 1'b1;
                    case (access_kind)
                        PMP_ACCESS_READ:
                            entry_permission = pmpcfg[entry_i][0];
                        PMP_ACCESS_WRITE:
                            entry_permission = pmpcfg[entry_i][1];
                        default:
                            entry_permission = pmpcfg[entry_i][2];
                    endcase

                    if ((privilege == PRIV_M) && !pmpcfg[entry_i][7])
                        pmp_access_allowed = entry_all_match;
                    else
                        pmp_access_allowed = entry_all_match &&
                                             entry_permission;
                end
            end
        end
    endfunction

    function automatic [7:0] sanitize_pmpcfg;
        input [7:0] value;
        reg [7:0] sanitized;
        begin
            sanitized = value & 8'h9f;
            if (!sanitized[0])
                sanitized[1] = 1'b0;
            sanitize_pmpcfg = sanitized;
        end
    endfunction

    function automatic [31:0] sanitize_mstatus;
        input [31:0] old_value;
        input [31:0] new_value;
        reg [31:0] value;
        begin
            value = (old_value & ~MSTATUS_MASK) |
                    (new_value & MSTATUS_MASK);
            if (value[12:11] != PRIV_M)
                value[12:11] = PRIV_U;
            sanitize_mstatus = value;
        end
    endfunction

    function automatic pmp_address_locked;
        input [2:0] index;
        begin
            case (index)
                3'd0: pmp_address_locked = pmpcfg[0][7] ||
                    (pmpcfg[1][7] && (pmpcfg[1][4:3] == PMP_A_TOR));
                3'd1: pmp_address_locked = pmpcfg[1][7] ||
                    (pmpcfg[2][7] && (pmpcfg[2][4:3] == PMP_A_TOR));
                3'd2: pmp_address_locked = pmpcfg[2][7] ||
                    (pmpcfg[3][7] && (pmpcfg[3][4:3] == PMP_A_TOR));
                3'd3: pmp_address_locked = pmpcfg[3][7] ||
                    (pmpcfg[4][7] && (pmpcfg[4][4:3] == PMP_A_TOR));
                3'd4: pmp_address_locked = pmpcfg[4][7] ||
                    (pmpcfg[5][7] && (pmpcfg[5][4:3] == PMP_A_TOR));
                3'd5: pmp_address_locked = pmpcfg[5][7] ||
                    (pmpcfg[6][7] && (pmpcfg[6][4:3] == PMP_A_TOR));
                3'd6: pmp_address_locked = pmpcfg[6][7] ||
                    (pmpcfg[7][7] && (pmpcfg[7][4:3] == PMP_A_TOR));
                default: pmp_address_locked = pmpcfg[7][7];
            endcase
        end
    endfunction

    wire [1:0] data_effective_privilege =
        (privilege_q == PRIV_M && mstatus[17]) ? mstatus[12:11] :
                                                privilege_q;

    assign fetch_access_allowed = pmp_access_allowed(
        fetch_address, 3'd4, privilege_q, PMP_ACCESS_EXEC);
    assign data_access_allowed = pmp_access_allowed(
        data_address, data_access_bytes, data_effective_privilege,
        data_write ? PMP_ACCESS_WRITE : PMP_ACCESS_READ);

    wire [31:0] mip_value =
        (dma_interrupt ? 32'h0000_0800 : 32'd0) |
        ((timer_interrupt || wdt_pending_q) ? 32'h0000_0080 : 32'd0);
    wire machine_interrupts_enabled =
        (privilege_q != PRIV_M) || mstatus[3];
    wire external_pending = machine_interrupts_enabled && mie[11] &&
                            dma_interrupt;
    wire timer_pending = machine_interrupts_enabled && mie[7] &&
                         (timer_interrupt || wdt_pending_q);

    wire pmpcfg_address = (csr_addr == CSR_PMPCFG0) ||
                          (csr_addr == CSR_PMPCFG1);
    wire pmpaddr_address = (csr_addr >= CSR_PMPADDR0) &&
                           (csr_addr <= CSR_PMPADDR7);
    wire [2:0] pmp_csr_index = csr_addr[2:0];
    wire user_counter_address =
        (csr_addr == CSR_CYCLE) || (csr_addr == CSR_CYCLEH) ||
        (csr_addr == CSR_TIME) || (csr_addr == CSR_TIMEH) ||
        (csr_addr == CSR_INSTRET) || (csr_addr == CSR_INSTRETH);

    wire csr_address_implemented =
        (ENABLE_FPU && ((csr_addr == CSR_FFLAGS) ||
                        (csr_addr == CSR_FRM) ||
                        (csr_addr == CSR_FCSR))) ||
        (csr_addr == CSR_MSTATUS)    || (csr_addr == CSR_MISA)       ||
        (csr_addr == CSR_MIE)        || (csr_addr == CSR_MTVEC)      ||
        (csr_addr == CSR_MCOUNTEREN) || (csr_addr == CSR_MSCRATCH)   ||
        (csr_addr == CSR_MEPC)       || (csr_addr == CSR_MCAUSE)     ||
        (csr_addr == CSR_MTVAL)      || (csr_addr == CSR_MIP)        ||
        pmpcfg_address               || pmpaddr_address              ||
        (csr_addr == CSR_MCYCLE)     || (csr_addr == CSR_MINSTRET)   ||
        (csr_addr == CSR_MCYCLEH)    || (csr_addr == CSR_MINSTRETH)  ||
        user_counter_address         || (csr_addr == CSR_MVENDORID)  ||
        (csr_addr == CSR_MARCHID)    || (csr_addr == CSR_MIMPID)     ||
        (csr_addr == CSR_MHARTID)    || (csr_addr == CSR_MCONFIGPTR);

    wire csr_address_writable =
        (ENABLE_FPU && ((csr_addr == CSR_FFLAGS) ||
                        (csr_addr == CSR_FRM) ||
                        (csr_addr == CSR_FCSR))) ||
        (csr_addr == CSR_MSTATUS)    || (csr_addr == CSR_MIE)        ||
        (csr_addr == CSR_MTVEC)      || (csr_addr == CSR_MCOUNTEREN) ||
        (csr_addr == CSR_MSCRATCH)   || (csr_addr == CSR_MEPC)       ||
        (csr_addr == CSR_MCAUSE)     || (csr_addr == CSR_MTVAL)      ||
        pmpcfg_address               || pmpaddr_address              ||
        (csr_addr == CSR_MCYCLE)     || (csr_addr == CSR_MINSTRET)   ||
        (csr_addr == CSR_MCYCLEH)    || (csr_addr == CSR_MINSTRETH);

    wire [31:0] csr_operand = csr_funct3[2]
                            ? {27'd0, csr_rs1} : csr_rs1_data;
    wire csr_write_attempt = (csr_funct3[1:0] == 2'b01) ?
                             1'b1 : (csr_operand != 32'd0);
    wire counter_access_allowed =
        ((csr_addr == CSR_CYCLE) || (csr_addr == CSR_CYCLEH)) ?
            mcounteren[0] :
        ((csr_addr == CSR_TIME) || (csr_addr == CSR_TIMEH)) ?
            mcounteren[1] : mcounteren[2];
    wire csr_privilege_illegal = privilege_q < csr_addr[9:8];
    wire csr_counter_illegal = (privilege_q == PRIV_U) &&
                               user_counter_address &&
                               !counter_access_allowed;
    wire csr_access_illegal = execute && csr_en &&
                              (!csr_address_implemented ||
                               csr_privilege_illegal ||
                               csr_counter_illegal ||
                               (csr_write_attempt &&
                                !csr_address_writable));
    wire privileged_instruction_illegal = execute &&
        (privilege_q != PRIV_M) && (mret || wfi);
    wire instruction_fault = execute && instruction_access_fault;
    wire data_fault = execute && data_access && !data_access_allowed;
    wire sync_exception = execute &&
        (instruction_access_fault || data_fault || illegal_instr ||
         csr_access_illegal || privileged_instruction_illegal || ebreak ||
         ecall);
    wire async_interrupt = (external_pending || timer_pending) &&
                           (execute || wfi_active) && !sync_exception;
    wire mip_read = execute && csr_en && (csr_addr == CSR_MIP) &&
                    !csr_access_illegal;

    reg [31:0] selected_cause;
    reg [31:0] selected_mtval;

    always @(*) begin
        selected_cause = 32'd0;
        selected_mtval = 32'd0;

        if (sync_exception) begin
            if (instruction_fault) begin
                selected_cause = CAUSE_INSTRUCTION_ACCESS;
                selected_mtval = current_pc;
            end else if (data_fault) begin
                selected_cause = data_write ? CAUSE_STORE_ACCESS :
                                              CAUSE_LOAD_ACCESS;
                selected_mtval = data_address;
            end else if (illegal_instr || csr_access_illegal ||
                         privileged_instruction_illegal) begin
                selected_cause = CAUSE_ILLEGAL_INSTRUCTION;
                selected_mtval = instruction;
            end else if (ebreak) begin
                selected_cause = CAUSE_BREAKPOINT;
                selected_mtval = current_pc;
            end else begin
                selected_cause = (privilege_q == PRIV_U) ?
                                 CAUSE_ECALL_U : CAUSE_ECALL_M;
            end
        end else if (external_pending) begin
            selected_cause = CAUSE_M_EXTERNAL_INTERRUPT;
        end else if (timer_pending) begin
            selected_cause = CAUSE_M_TIMER_INTERRUPT;
        end
    end

    assign trap_taken = sync_exception || async_interrupt;
    assign mret_taken = execute && mret && !trap_taken;
    wire [31:0] mtvec_base = {mtvec[31:2], 2'b00};
    wire [31:0] vector_offset = {25'd0, selected_cause[4:0], 2'b00};
    wire [31:0] trap_vector = (selected_cause[31] && mtvec[0]) ?
                              mtvec_base + vector_offset : mtvec_base;
    assign redirect_pc = trap_taken ? trap_vector :
                                    {mepc[31:2], 2'b00};

    reg [31:0] csr_write_value;
    reg        csr_write_enable;

    always @(*) begin
        case (csr_addr)
            CSR_FFLAGS:     csr_read_data = {27'd0, fflags};
            CSR_FRM:        csr_read_data = {29'd0, frm};
            CSR_FCSR:       csr_read_data = {24'd0, frm, fflags};
            CSR_MSTATUS:    csr_read_data = mstatus;
            CSR_MISA:       csr_read_data = MISA_VALUE;
            CSR_MIE:        csr_read_data = mie;
            CSR_MTVEC:      csr_read_data = mtvec;
            CSR_MCOUNTEREN: csr_read_data = mcounteren;
            CSR_MSCRATCH:   csr_read_data = mscratch;
            CSR_MEPC:       csr_read_data = mepc;
            CSR_MCAUSE:     csr_read_data = mcause;
            CSR_MTVAL:      csr_read_data = mtval;
            CSR_MIP:        csr_read_data = mip_value;
            CSR_PMPCFG0:    csr_read_data = {pmpcfg[3], pmpcfg[2],
                                             pmpcfg[1], pmpcfg[0]};
            CSR_PMPCFG1:    csr_read_data = {pmpcfg[7], pmpcfg[6],
                                             pmpcfg[5], pmpcfg[4]};
            CSR_PMPADDR0, 12'h3B1, 12'h3B2, 12'h3B3,
            12'h3B4, 12'h3B5, 12'h3B6, CSR_PMPADDR7:
                csr_read_data = pmpaddr[pmp_csr_index];
            CSR_MCYCLE,
            CSR_CYCLE:      csr_read_data = cycle_counter[31:0];
            CSR_TIME:       csr_read_data = time_value[31:0];
            CSR_MINSTRET,
            CSR_INSTRET:    csr_read_data = instret_counter[31:0];
            CSR_MCYCLEH,
            CSR_CYCLEH:     csr_read_data = cycle_counter[63:32];
            CSR_TIMEH:      csr_read_data = time_value[63:32];
            CSR_MINSTRETH,
            CSR_INSTRETH:   csr_read_data = instret_counter[63:32];
            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID,
            CSR_MCONFIGPTR: csr_read_data = 32'd0;
            default:        csr_read_data = 32'd0;
        endcase
    end

    always @(*) begin
        csr_write_enable = 1'b0;
        csr_write_value = csr_read_data;
        case (csr_funct3)
            3'b001, 3'b101: begin
                csr_write_enable = 1'b1;
                csr_write_value = csr_operand;
            end
            3'b010, 3'b110: begin
                csr_write_enable = (csr_operand != 32'd0);
                csr_write_value = csr_read_data | csr_operand;
            end
            3'b011, 3'b111: begin
                csr_write_enable = (csr_operand != 32'd0);
                csr_write_value = csr_read_data & ~csr_operand;
            end
            default: begin
                csr_write_enable = 1'b0;
                csr_write_value = csr_read_data;
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            wdt_pending_q <= 1'b0;
        else if (wdt_interrupt)
            wdt_pending_q <= 1'b1;
        else if (mip_read)
            wdt_pending_q <= 1'b0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus         <= ENABLE_FPU ? 32'h0000_2000 : 32'd0;
            mie             <= 32'd0;
            mtvec           <= `RTOS_CORE_CPU_MACHINE_TRAP_VECTOR;
            mcounteren      <= 32'd0;
            mscratch        <= 32'd0;
            mepc            <= 32'd0;
            mcause          <= 32'd0;
            mtval           <= 32'd0;
            fflags          <= 5'd0;
            frm             <= 3'd0;
            wfi_active      <= 1'b0;
            wfi_resume_pc   <= 32'd0;
            cycle_counter   <= 64'd0;
            instret_counter <= 64'd0;
            privilege_q     <= PRIV_M;
            for (pmp_i = 0; pmp_i < 8; pmp_i = pmp_i + 1) begin
                pmpcfg[pmp_i] <= 8'd0;
                pmpaddr[pmp_i] <= 32'd0;
            end
        end else begin
            cycle_counter <= cycle_counter + 64'd1;
            if (execute && instr_valid && !sync_exception)
                instret_counter <= instret_counter + 64'd1;

            if (ENABLE_FPU && fp_flags_valid)
                fflags <= fflags | fp_flags;
            if (ENABLE_FPU && (fp_flags_valid || fp_state_dirty))
                mstatus[14:13] <= 2'b11;

            if (trap_taken) begin
                mepc <= sync_exception ? {current_pc[31:2], 2'b00} :
                        wfi_active ? {wfi_resume_pc[31:2], 2'b00} :
                                     {trap_resume_pc[31:2], 2'b00};
                mcause         <= selected_cause;
                mtval          <= selected_mtval;
                mstatus[7]     <= mstatus[3];
                mstatus[3]     <= 1'b0;
                mstatus[12:11] <= privilege_q;
                privilege_q    <= PRIV_M;
                wfi_active     <= 1'b0;
            end else if (execute) begin
                if (mret) begin
                    mstatus[3]     <= mstatus[7];
                    mstatus[7]     <= 1'b1;
                    mstatus[12:11] <= PRIV_U;
                    if (mstatus[12:11] != PRIV_M)
                        mstatus[17] <= 1'b0;
                    privilege_q    <= (mstatus[12:11] == PRIV_M) ?
                                      PRIV_M : PRIV_U;
                    wfi_active     <= 1'b0;
                end else if (wfi) begin
                    wfi_active    <= 1'b1;
                    wfi_resume_pc <= trap_resume_pc;
                end else if (csr_en && csr_write_enable) begin
                    case (csr_addr)
                        CSR_FFLAGS: begin
                            fflags <= csr_write_value[4:0];
                            mstatus[14:13] <= 2'b11;
                        end
                        CSR_FRM: begin
                            frm <= csr_write_value[2:0];
                            mstatus[14:13] <= 2'b11;
                        end
                        CSR_FCSR: begin
                            frm <= csr_write_value[7:5];
                            fflags <= csr_write_value[4:0];
                            mstatus[14:13] <= 2'b11;
                        end
                        CSR_MSTATUS:
                            mstatus <= sanitize_mstatus(mstatus,
                                                       csr_write_value);
                        CSR_MIE:
                            mie <= (mie & ~MIE_MASK) |
                                   (csr_write_value & MIE_MASK);
                        CSR_MTVEC:
                            mtvec <= {csr_write_value[31:2], 1'b0,
                                      csr_write_value[0]};
                        CSR_MCOUNTEREN:
                            mcounteren <= csr_write_value & 32'h0000_0007;
                        CSR_MSCRATCH:
                            mscratch <= csr_write_value;
                        CSR_MEPC:
                            mepc <= {csr_write_value[31:2], 2'b00};
                        CSR_MCAUSE:
                            mcause <= csr_write_value;
                        CSR_MTVAL:
                            mtval <= csr_write_value;
                        CSR_PMPCFG0: begin
                            for (pmp_i = 0; pmp_i < 4;
                                 pmp_i = pmp_i + 1)
                                if (!pmpcfg[pmp_i][7])
                                    pmpcfg[pmp_i] <= sanitize_pmpcfg(
                                        csr_write_value[pmp_i*8 +: 8]);
                        end
                        CSR_PMPCFG1: begin
                            for (pmp_i = 0; pmp_i < 4;
                                 pmp_i = pmp_i + 1)
                                if (!pmpcfg[pmp_i+4][7])
                                    pmpcfg[pmp_i+4] <= sanitize_pmpcfg(
                                        csr_write_value[pmp_i*8 +: 8]);
                        end
                        CSR_PMPADDR0, 12'h3B1, 12'h3B2, 12'h3B3,
                        12'h3B4, 12'h3B5, 12'h3B6, CSR_PMPADDR7: begin
                            if (!pmp_address_locked(pmp_csr_index))
                                pmpaddr[pmp_csr_index] <= csr_write_value;
                        end
                        CSR_MCYCLE:
                            cycle_counter[31:0] <= csr_write_value;
                        CSR_MCYCLEH:
                            cycle_counter[63:32] <= csr_write_value;
                        CSR_MINSTRET:
                            instret_counter[31:0] <= csr_write_value;
                        CSR_MINSTRETH:
                            instret_counter[63:32] <= csr_write_value;
                        default: begin
                        end
                    endcase
                end
            end
        end
    end

endmodule
