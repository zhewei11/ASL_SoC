module pose_library #(
     parameter int unsigned MOTOR_COUNT      = 20
    ,parameter logic [15:0] NEUTRAL_POSITION = 16'd2048
) (
     input  logic [7:0] class_id
    ,input  logic [$clog2(MOTOR_COUNT)-1:0] motor_index
    ,output logic [15:0] position
);

    logic [15:0] motor_offset;

    always_comb begin
        motor_offset = {{(16-$clog2(MOTOR_COUNT)){1'b0}}, motor_index} << 2;
        // Milestone test poses only. Class 0 and all unassigned classes are
        // neutral; classes 1 and 2 are deterministic 20-axis A/B poses.
        case (class_id)
            8'd1: position = 16'd2200 + motor_offset;
            8'd2: position = 16'd1800 + motor_offset;
            default: position = NEUTRAL_POSITION;
        endcase
    end

endmodule
