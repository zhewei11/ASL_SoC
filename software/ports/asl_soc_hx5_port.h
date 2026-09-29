#ifndef ASL_SOC_HX5_PORT_H
#define ASL_SOC_HX5_PORT_H

#include <stdbool.h>
#include <stdint.h>

#include "asl_motion.h"
#include "hx5_rt_control.h"

typedef struct {
    hx5_rt_control_t rt_control;
    asl_joint_calibration_t calibration[ASL_JOINT_COUNT];
    int16_t goal_current[ASL_JOINT_COUNT];
    uint8_t configured;
} asl_soc_hx5_port_t;

/* Configures the existing CPU-owned HX5 Protocol 2.0 RT path. */
bool asl_soc_hx5_port_initialize(
    asl_soc_hx5_port_t *port,
    uint32_t baud_select,
    uint32_t hand_id,
    const asl_joint_calibration_t calibration[ASL_JOINT_COUNT],
    const int16_t goal_current[ASL_JOINT_COUNT]
);

/* Check this before advancing the trajectory so a locked bank drops no step. */
bool asl_soc_hx5_port_ready(const asl_soc_hx5_port_t *port);

bool asl_soc_hx5_port_try_submit_q12(
    asl_soc_hx5_port_t *port,
    const int16_t q12[ASL_JOINT_COUNT]
);

void asl_soc_hx5_port_abort(asl_soc_hx5_port_t *port);

#endif
