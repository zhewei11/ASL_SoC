module pose_player #(
     parameter int unsigned MOTOR_COUNT      = 20
    ,parameter int unsigned POSE_COUNT       = 24
    ,parameter logic [15:0] NEUTRAL_POSITION = 16'd2048
    ,parameter logic [15:0] DEFAULT_MAX_STEP = 16'd64
    ,parameter logic [15:0] DEFAULT_GOAL_CURRENT = 16'd0
    ,parameter logic [31:0] DEFAULT_GOAL_VELOCITY = 32'd0
    ,parameter logic [31:0] DEFAULT_PROFILE_ACCELERATION = 32'd0
    ,parameter logic [31:0] DEFAULT_PROFILE_VELOCITY = 32'd0
) (
     input  logic        clk
    ,input  logic        rst
    ,input  logic        frame_tick
    ,input  logic        safety_allow
    ,input  logic        target_valid
    ,input  logic [7:0]  target_class_id
    ,input  logic [15:0] max_step
    ,output logic        command_valid
    ,input  logic        command_ready
    ,output logic [$clog2(MOTOR_COUNT)-1:0] command_motor_index
    ,output logic [15:0] command_goal_current
    ,output logic [31:0] command_goal_velocity
    ,output logic [31:0] command_profile_acceleration
    ,output logic [31:0] command_profile_velocity
    ,output logic [15:0] command_position
    ,output logic        command_last
    ,output logic        command_commit
    ,output logic [31:0] command_sequence
    ,output logic        frame_busy
    ,output logic [7:0]  active_class_id
);

    logic [15:0]                    current_position [0:MOTOR_COUNT-1];
    logic [15:0]                    requested_position;
    logic [15:0]                    effective_step;
    logic [7:0]                     selected_class;
    logic [$clog2(MOTOR_COUNT)-1:0] lookup_motor_index;
    integer                         i;

    assign effective_step = (max_step == 0) ? DEFAULT_MAX_STEP : max_step;
    assign selected_class = safety_allow ? active_class_id : 8'd0;
    assign command_goal_current = DEFAULT_GOAL_CURRENT;
    assign command_goal_velocity = DEFAULT_GOAL_VELOCITY;
    assign command_profile_acceleration = DEFAULT_PROFILE_ACCELERATION;
    assign command_profile_velocity = DEFAULT_PROFILE_VELOCITY;
    assign lookup_motor_index =
        (command_valid && command_ready && !command_last) ?
            command_motor_index + 1'b1 :
        frame_busy ? command_motor_index : '0;

    pose_library #(
         .MOTOR_COUNT      (MOTOR_COUNT)
        ,.NEUTRAL_POSITION (NEUTRAL_POSITION)
    ) u_pose_library (
         .class_id    (selected_class)
        ,.motor_index (lookup_motor_index)
        ,.position    (requested_position)
    );

    function automatic logic [15:0] limited_position(
         input logic [15:0] current
        ,input logic [15:0] requested
        ,input logic [15:0] step
    );
        logic [16:0] upper;
        begin
            upper = {1'b0, current} + {1'b0, step};
            if (requested > current && {1'b0, requested} > upper)
                limited_position = upper[15:0];
            else if (requested < current && current - requested > step)
                limited_position = current - step;
            else
                limited_position = requested;
        end
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            command_valid       <= 1'b0;
            command_motor_index <= '0;
            command_position    <= NEUTRAL_POSITION;
            command_last        <= 1'b0;
            command_commit      <= 1'b0;
            command_sequence    <= 32'd0;
            frame_busy          <= 1'b0;
            active_class_id     <= 8'd0;
            for (i = 0; i < MOTOR_COUNT; i = i + 1)
                current_position[i] <= NEUTRAL_POSITION;
        end else begin
            command_commit <= 1'b0;

            if (target_valid) begin
                if (target_class_id < 8'(POSE_COUNT))
                    active_class_id <= target_class_id;
                else
                    active_class_id <= 8'd0;
            end

            if (frame_tick && !frame_busy) begin
                frame_busy          <= 1'b1;
                command_valid       <= 1'b1;
                command_motor_index <= '0;
                command_position <= limited_position(
                    current_position[0],
                    requested_position,
                    effective_step
                );
                command_last <= (MOTOR_COUNT == 1);
            end else if (command_valid && command_ready) begin
                current_position[command_motor_index] <= command_position;
                if (command_last) begin
                    command_valid    <= 1'b0;
                    command_last     <= 1'b0;
                    command_commit   <= 1'b1;
                    command_sequence <= command_sequence + 1'b1;
                    frame_busy       <= 1'b0;
                end else begin
                    command_motor_index <= command_motor_index + 1'b1;
                    command_position <= limited_position(
                        current_position[command_motor_index + 1'b1],
                        requested_position,
                        effective_step
                    );
                    command_last <=
                        (command_motor_index ==
                         $clog2(MOTOR_COUNT)'(MOTOR_COUNT - 2));
                end
            end
        end
    end

endmodule
