`ifdef PROTOCOL2_RT_SVA
module protocol2_rt_assertions (
     input logic clk, rst, active, abort_flush, core_abort, cmd_valid
    ,input logic frame_done, frame_error, frame_deadline
    ,input logic active_command_bank, active_feedback_bank
    ,input logic [31:0] last_frame_cycles
    ,input logic schedule_valid, schedule_overflow, schedule_config_error
    ,input logic [1:0] command_bank_locked
);
    property p_overflow_never_executes;
        @(posedge clk) disable iff (rst)
            schedule_overflow |-> (!schedule_valid && !active && !cmd_valid);
    endproperty
    property p_invalid_schedule_never_executes;
        @(posedge clk) disable iff (rst)
            schedule_config_error |-> (!schedule_valid && !active && !cmd_valid);
    endproperty
    property p_active_command_bank_is_locked;
        @(posedge clk) disable iff (rst)
            active |-> command_bank_locked[active_command_bank];
    endproperty
    property p_abort_reaches_core;
        @(posedge clk) disable iff (rst)
            abort_flush && active |=> core_abort;
    endproperty
    property p_deadline_is_an_error;
        @(posedge clk) disable iff (rst)
            frame_deadline |-> frame_error;
    endproperty
    property p_feedback_switch_is_atomic;
        @(posedge clk) disable iff (rst)
            $changed(active_feedback_bank) |-> frame_done;
    endproperty
    property p_completed_frame_has_duration;
        @(posedge clk) disable iff (rst)
            frame_done |-> (last_frame_cycles != 32'd0);
    endproperty
    assert property (p_overflow_never_executes);
    assert property (p_invalid_schedule_never_executes);
    assert property (p_active_command_bank_is_locked);
    assert property (p_abort_reaches_core);
    assert property (p_deadline_is_an_error);
    assert property (p_feedback_switch_is_atomic);
    assert property (p_completed_frame_has_duration);
endmodule
`endif
