module pose_protocol_command_adapter #(
     parameter int unsigned MOTOR_COUNT = 20
    ,parameter logic [31:0] PROTOCOL_BASE = 32'h1003_0000
) (
     input  logic clk
    ,input  logic rst

    ,input  logic pose_valid
    ,output logic pose_ready
    ,input  logic [$clog2(MOTOR_COUNT)-1:0] pose_motor_index
    ,input  logic [15:0] pose_goal_current
    ,input  logic [31:0] pose_goal_velocity
    ,input  logic [31:0] pose_profile_acceleration
    ,input  logic [31:0] pose_profile_velocity
    ,input  logic [15:0] pose_position
    ,input  logic pose_last
    ,input  logic pose_commit
    ,input  logic [31:0] pose_sequence
    ,input  logic [7:0] hand_id

    ,output logic mmio_valid
    ,input  logic mmio_ready
    ,output logic mmio_write
    ,output logic [31:0] mmio_addr
    ,output logic [31:0] mmio_wdata
    ,output logic [3:0] mmio_wstrb
    ,input  logic [31:0] mmio_rdata

    ,output logic busy
    ,output logic error
    ,output logic committed_bank
    ,output logic [31:0] committed_sequence
);
    // The official ROS 2 profile exposes one indirect write window on the
    // hand controller. One Sync Write updates all 20 virtual actuators:
    //   Goal Position low 16 bits, Goal Current 16 bits.
    // A word-aligned unicast Read template follows it for the 165-byte
    // indirect feedback window (20 motor records plus five tactile records).
    localparam int unsigned FINGER_COUNT = 5;
    localparam int unsigned MOTORS_PER_FINGER = 4;
    localparam int unsigned AXIS_COMMAND_BYTES = 4;
    localparam int unsigned COMMAND_PAYLOAD_BYTES =
        MOTOR_COUNT * AXIS_COMMAND_BYTES;
    localparam int unsigned SYNC_WRITE_BODY_BYTES =
        1 + 2 + 2 + 1 + COMMAND_PAYLOAD_BYTES;
    localparam int unsigned READ_BODY_OFFSET = 88;
    localparam int unsigned COMMAND_BYTES = 96;
    localparam int unsigned WORD_COUNT = COMMAND_BYTES / 4;

    localparam logic [15:0] INDIRECT_WRITE_ADDRESS = 16'd799;
    localparam logic [15:0] INDIRECT_READ_ADDRESS = 16'd634;
    localparam logic [15:0] FEEDBACK_BYTES = 16'd165;

    localparam logic [31:0] REG_RT_MEM_ADDR      = 32'hB8;
    localparam logic [31:0] REG_RT_MEM_DATA      = 32'hBC;
    localparam logic [31:0] REG_COMMAND_COMMIT   = 32'hC0;
    localparam logic [31:0] REG_COMMAND_SEQUENCE = 32'hC8;

    localparam int unsigned CAPTURE_COUNT_WIDTH = $clog2(MOTOR_COUNT + 1);
    localparam int unsigned MOTOR_INDEX_WIDTH = $clog2(MOTOR_COUNT);
    localparam int unsigned WORD_INDEX_WIDTH = $clog2(WORD_COUNT + 1);
    localparam logic [MOTOR_COUNT-1:0] ALL_MOTORS_SEEN =
        {MOTOR_COUNT{1'b1}};

    typedef enum logic [2:0] {
        ST_CAPTURE,
        ST_READ_BANK,
        ST_SET_ADDRESS,
        ST_WRITE_WORDS,
        ST_WRITE_SEQUENCE,
        ST_COMMIT,
        ST_VERIFY
    } state_t;

    state_t state;

    logic [15:0] goal_current [0:MOTOR_COUNT-1];
    logic [15:0] goal_position [0:MOTOR_COUNT-1];

    logic [CAPTURE_COUNT_WIDTH-1:0] capture_count;
    logic [MOTOR_COUNT-1:0]         capture_seen;
    logic                           capture_invalid;
    logic [WORD_INDEX_WIDTH-1:0]    word_index;
    logic                           target_bank;
    logic [31:0]                    sequence_q;
    logic [7:0]                     hand_id_q;

    integer index;

    function automatic logic [7:0] axis_command_byte(
         input integer motor_index
        ,input integer byte_index
    );
        begin
            case (byte_index)
                0: axis_command_byte = goal_position[motor_index][7:0];
                1: axis_command_byte = goal_position[motor_index][15:8];
                2: axis_command_byte = goal_current[motor_index][7:0];
                3: axis_command_byte = goal_current[motor_index][15:8];
                default: axis_command_byte = 8'd0;
            endcase
        end
    endfunction

    function automatic logic [7:0] command_byte(input integer byte_index);
        integer payload_byte_index;
        integer motor_index;
        integer axis_byte_index;
        begin
            payload_byte_index = byte_index - 6;
            motor_index = payload_byte_index / AXIS_COMMAND_BYTES;
            axis_byte_index = payload_byte_index % AXIS_COMMAND_BYTES;

            if (byte_index == 0) begin
                command_byte = 8'h83;
            end else if (byte_index == 1) begin
                command_byte = INDIRECT_WRITE_ADDRESS[7:0];
            end else if (byte_index == 2) begin
                command_byte = INDIRECT_WRITE_ADDRESS[15:8];
            end else if (byte_index == 3) begin
                command_byte = COMMAND_PAYLOAD_BYTES[7:0];
            end else if (byte_index == 4) begin
                command_byte = COMMAND_PAYLOAD_BYTES[15:8];
            end else if (byte_index == 5) begin
                command_byte = hand_id_q;
            end else if (byte_index < SYNC_WRITE_BODY_BYTES) begin
                command_byte = axis_command_byte(motor_index, axis_byte_index);
            end else if (byte_index == READ_BODY_OFFSET) begin
                command_byte = 8'h02;
            end else if (byte_index == READ_BODY_OFFSET + 1) begin
                command_byte = INDIRECT_READ_ADDRESS[7:0];
            end else if (byte_index == READ_BODY_OFFSET + 2) begin
                command_byte = INDIRECT_READ_ADDRESS[15:8];
            end else if (byte_index == READ_BODY_OFFSET + 3) begin
                command_byte = FEEDBACK_BYTES[7:0];
            end else if (byte_index == READ_BODY_OFFSET + 4) begin
                command_byte = FEEDBACK_BYTES[15:8];
            end else begin
                command_byte = 8'd0;
            end
        end
    endfunction

    initial begin
        if (MOTOR_COUNT != FINGER_COUNT * MOTORS_PER_FINGER)
            $error("HX5-D20 command adapter requires exactly 20 motors");
    end

    assign pose_ready = state == ST_CAPTURE;
    assign busy = state != ST_CAPTURE;
    assign mmio_valid = state != ST_CAPTURE;
    assign mmio_wstrb = mmio_write ? 4'hF : 4'h0;

    always_comb begin
        mmio_write = 1'b0;
        mmio_addr = PROTOCOL_BASE;
        mmio_wdata = 32'd0;

        case (state)
            ST_READ_BANK, ST_VERIFY: begin
                mmio_addr = PROTOCOL_BASE + REG_COMMAND_COMMIT;
            end

            ST_SET_ADDRESS: begin
                mmio_write = 1'b1;
                mmio_addr = PROTOCOL_BASE + REG_RT_MEM_ADDR;
                // bit31 enables the wrapper's four-byte auto increment.
                mmio_wdata = 32'h8000_0000 |
                             ({31'd0, target_bank} << 12);
            end

            ST_WRITE_WORDS: begin
                mmio_write = 1'b1;
                mmio_addr = PROTOCOL_BASE + REG_RT_MEM_DATA;
                mmio_wdata = {
                    command_byte(word_index * 4 + 3),
                    command_byte(word_index * 4 + 2),
                    command_byte(word_index * 4 + 1),
                    command_byte(word_index * 4)
                };
            end

            ST_WRITE_SEQUENCE: begin
                mmio_write = 1'b1;
                mmio_addr = PROTOCOL_BASE + REG_COMMAND_SEQUENCE;
                mmio_wdata = sequence_q;
            end

            ST_COMMIT: begin
                mmio_write = 1'b1;
                mmio_addr = PROTOCOL_BASE + REG_COMMAND_COMMIT;
                mmio_wdata = 32'h8000_0000 | {31'd0, target_bank};
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_CAPTURE;
            capture_count <= '0;
            capture_seen <= '0;
            capture_invalid <= 1'b0;
            word_index <= '0;
            target_bank <= 1'b1;
            sequence_q <= 32'd0;
            hand_id_q <= 8'd110;
            error <= 1'b0;
            committed_bank <= 1'b0;
            committed_sequence <= 32'd0;

            for (index = 0; index < MOTOR_COUNT; index = index + 1) begin
                goal_current[index] <= 16'd0;
                goal_position[index] <= 16'd0;
            end
        end else begin
            if (state == ST_CAPTURE && pose_valid && pose_ready) begin
                if (pose_motor_index < MOTOR_INDEX_WIDTH'(MOTOR_COUNT)) begin
                    if (capture_seen[pose_motor_index]) begin
                        capture_invalid <= 1'b1;
                        error <= 1'b1;
                    end else begin
                        goal_current[pose_motor_index] <= pose_goal_current;
                        goal_position[pose_motor_index] <= pose_position;
                        capture_seen[pose_motor_index] <= 1'b1;
                        capture_count <= capture_count + 1'b1;
                    end
                end else begin
                    capture_invalid <= 1'b1;
                    error <= 1'b1;
                end

                if (pose_motor_index != capture_count) begin
                    capture_invalid <= 1'b1;
                    error <= 1'b1;
                end
                if (pose_last != (pose_motor_index ==
                    MOTOR_INDEX_WIDTH'(MOTOR_COUNT - 1))) begin
                    capture_invalid <= 1'b1;
                    error <= 1'b1;
                end
            end

            if (state == ST_CAPTURE && pose_commit) begin
                if ((capture_count != CAPTURE_COUNT_WIDTH'(MOTOR_COUNT)) ||
                    (capture_seen != ALL_MOTORS_SEEN) ||
                    capture_invalid || pose_valid) begin
                    error <= 1'b1;
                    capture_count <= '0;
                    capture_seen <= '0;
                    capture_invalid <= 1'b0;
                end else begin
                    sequence_q <= pose_sequence;
                    hand_id_q <= hand_id;
                    state <= ST_READ_BANK;
                end
            end else if (mmio_valid && mmio_ready) begin
                case (state)
                    ST_READ_BANK: begin
                        target_bank <= ~mmio_rdata[0];
                        word_index <= '0;
                        state <= ST_SET_ADDRESS;
                    end

                    ST_SET_ADDRESS: state <= ST_WRITE_WORDS;

                    ST_WRITE_WORDS: begin
                        if (word_index == WORD_INDEX_WIDTH'(WORD_COUNT - 1)) begin
                            state <= ST_WRITE_SEQUENCE;
                        end else begin
                            word_index <= word_index + 1'b1;
                        end
                    end

                    ST_WRITE_SEQUENCE: state <= ST_COMMIT;
                    ST_COMMIT: state <= ST_VERIFY;

                    ST_VERIFY: begin
                        if (mmio_rdata[0] != target_bank) begin
                            error <= 1'b1;
                        end else begin
                            error <= 1'b0;
                            committed_bank <= mmio_rdata[0];
                            committed_sequence <= sequence_q;
                        end
                        capture_count <= '0;
                        capture_seen <= '0;
                        capture_invalid <= 1'b0;
                        state <= ST_CAPTURE;
                    end

                    default: state <= ST_CAPTURE;
                endcase
            end
        end
    end
endmodule
