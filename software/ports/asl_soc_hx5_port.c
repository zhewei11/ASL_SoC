#include "asl_soc_hx5_port.h"

bool asl_soc_hx5_port_initialize(
    asl_soc_hx5_port_t *port,
    uint32_t baud_select,
    uint32_t hand_id,
    const asl_joint_calibration_t calibration[ASL_JOINT_COUNT],
    const int16_t goal_current[ASL_JOINT_COUNT]
) {
    uint32_t joint;

    if (port == NULL || goal_current == NULL ||
        !asl_joint_calibration_table_valid(calibration)) {
        return false;
    }

    port->configured = 0u;
    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        port->calibration[joint] = calibration[joint];
        port->goal_current[joint] = goal_current[joint];
    }

    if (hx5_rt_control_initialize(
            &port->rt_control,
            baud_select,
            hand_id) == 0u) {
        return false;
    }

    port->configured = 1u;
    return true;
}

bool asl_soc_hx5_port_ready(const asl_soc_hx5_port_t *port) {
    uint32_t committed_bank;
    uint32_t target_lock;

    if (port == NULL || port->configured == 0u)
        return false;

    committed_bank = PROTOCOL2_MMIO->command_commit & 1u;
    target_lock = (committed_bank ^ 1u) != 0u ?
        PROTOCOL2_SCHEDULE_COMMAND_B_LOCKED :
        PROTOCOL2_SCHEDULE_COMMAND_A_LOCKED;
    return (PROTOCOL2_MMIO->schedule_status & target_lock) == 0u;
}

bool asl_soc_hx5_port_try_submit_q12(
    asl_soc_hx5_port_t *port,
    const int16_t q12[ASL_JOINT_COUNT]
) {
    hx5_d20_axis_command_t commands[HX5_D20_AXIS_COUNT];
    int16_t raw_position[ASL_JOINT_COUNT];
    uint32_t joint;

    if (port == NULL || port->configured == 0u ||
        !asl_q12_to_raw_positions(q12, port->calibration, raw_position)) {
        return false;
    }

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        commands[joint].goal_position = raw_position[joint];
        commands[joint].goal_current = port->goal_current[joint];
    }

    return hx5_rt_control_try_submit(&port->rt_control, commands) != 0u;
}

void asl_soc_hx5_port_abort(asl_soc_hx5_port_t *port) {
    if (port == NULL)
        return;
    hx5_rt_control_abort(&port->rt_control);
    port->configured = 0u;
}
