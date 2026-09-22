module safety_supervisor #(
     parameter int unsigned WATCHDOG_TIMEOUT_CYCLES = 100_000_000
) (
     input  logic clk
    ,input  logic rst
    ,input  logic emergency_stop_n
    ,input  logic external_fault
    ,input  logic torque_enable_request
    ,input  logic watchdog_enable
    ,input  logic watchdog_kick
    ,input  logic clear_fault
    ,output logic torque_enable_allow
    ,output logic rs485_de_inhibit
    ,output logic watchdog_fault
    ,output logic safety_fault_latched
);

    localparam int unsigned COUNTER_WIDTH =
        (WATCHDOG_TIMEOUT_CYCLES <= 1) ? 1 : $clog2(WATCHDOG_TIMEOUT_CYCLES);

    logic [COUNTER_WIDTH-1:0] watchdog_counter;
    logic                     immediate_external_fault;
    logic                     safety_fault_active;

    assign immediate_external_fault = !emergency_stop_n || external_fault;
    assign safety_fault_active = immediate_external_fault ||
                                 watchdog_fault || safety_fault_latched;

    // The two external safety inputs remain combinational in the final gate so
    // assertion is not delayed by a clock or by CPU/MMIO service latency.
    assign torque_enable_allow = torque_enable_request && !safety_fault_active;
    assign rs485_de_inhibit    = safety_fault_active;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            watchdog_counter    <= '0;
            watchdog_fault      <= 1'b0;
            safety_fault_latched <= 1'b0;
        end else begin
            if (immediate_external_fault)
                safety_fault_latched <= 1'b1;

            if (!watchdog_enable) begin
                watchdog_counter <= '0;
            end else if (watchdog_kick && !watchdog_fault) begin
                watchdog_counter <= '0;
            end else if (!watchdog_fault) begin
                if ((WATCHDOG_TIMEOUT_CYCLES <= 1) ||
                    (watchdog_counter ==
                     COUNTER_WIDTH'(WATCHDOG_TIMEOUT_CYCLES - 1))) begin
                    watchdog_fault       <= 1'b1;
                    safety_fault_latched <= 1'b1;
                end else begin
                    watchdog_counter <= watchdog_counter + 1'b1;
                end
            end

            // Fault clearing is accepted only while the physical inputs are
            // safe. Firmware cannot mask an asserted E-stop/external fault.
            if (clear_fault && !immediate_external_fault) begin
                watchdog_counter     <= '0;
                watchdog_fault       <= 1'b0;
                safety_fault_latched <= 1'b0;
            end
        end
    end

endmodule
