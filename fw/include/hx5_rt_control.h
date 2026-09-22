#ifndef HX5_RT_CONTROL_H
#define HX5_RT_CONTROL_H

#include <stdint.h>

#include "hx5_d20_protocol.h"

// OS-independent CPU-side service for the fixed HX5 RT sequencer. An RTOS
// task or a bare-metal event loop may call these non-blocking helpers. The
// exact 1 kHz wire cadence remains in hardware.
typedef struct {
    uint32_t next_command_sequence;
    uint8_t hand_id;
    uint8_t enabled;
} hx5_rt_control_t;

static inline uint32_t hx5_rt_control_initialize(
    hx5_rt_control_t *control,
    uint32_t baud_select,
    uint32_t hand_id
) {
    volatile uint32_t *pose_hand_id;

    if (control == 0)
        return 0u;

    control->next_command_sequence = 1u;
    control->hand_id = hx5_d20_valid_hand_id(hand_id);
    control->enabled = 0u;

    // This is the CPU-owned path: stop/flush first, configure the fixed
    // two-transaction profile directly, then wait for the first complete
    // command bank before enabling the 1 kHz sequencer.
    PROTOCOL2_MMIO->rt_control = 0u;
    PROTOCOL2_MMIO->abort_flush = PROTOCOL2_ABORT_ALL;
    if (!hx5_d20_wait_mask_clear(
            &PROTOCOL2_MMIO->rt_status,
            PROTOCOL2_RT_STATUS_ACTIVE)) {
        return 0u;
    }

    pose_hand_id = (volatile uint32_t *)(uintptr_t)(
        ASL_SOC_POSE_MMIO_BASE + ASL_POSE_HAND_ID_OFFSET
    );
    *pose_hand_id = control->hand_id;
    PROTOCOL2_MMIO->protocol_owner = PROTOCOL2_OWNER_RT;
    PROTOCOL2_MMIO->baud_request = hx5_d20_supported_bus_baud(baud_select) ?
        baud_select : PROTOCOL2_BAUD_6M;
    PROTOCOL2_MMIO->frame_period_cycles = ASL_SOC_RT_FRAME_CYCLES;
    PROTOCOL2_MMIO->comm_deadline_cycles = PROTOCOL2_DEADLINE_DISABLED;
    PROTOCOL2_MMIO->command_deadline_cycles = PROTOCOL2_DEADLINE_DISABLED;
    hx5_d20_program_schedule(control->hand_id);

    PROTOCOL2_MMIO->rt_irq_enable =
        PROTOCOL2_RT_IRQ_FRAME_DONE |
        PROTOCOL2_RT_IRQ_FRAME_ERROR |
        PROTOCOL2_RT_IRQ_DEADLINE |
        PROTOCOL2_RT_IRQ_BUFFER_ERROR;
    return 1u;
}

static inline uint32_t hx5_rt_control_try_submit(
    hx5_rt_control_t *control,
    const hx5_d20_axis_command_t commands[HX5_D20_AXIS_COUNT]
) {
    uint32_t schedule_status;
    uint32_t committed_bank;
    uint32_t target_bank;
    uint32_t target_lock;

    if ((control == 0) || (commands == 0))
        return 0u;

    schedule_status = PROTOCOL2_MMIO->schedule_status;
    committed_bank = PROTOCOL2_MMIO->command_commit & 1u;
    target_bank = committed_bank ^ 1u;
    target_lock = target_bank ?
        PROTOCOL2_SCHEDULE_COMMAND_B_LOCKED :
        PROTOCOL2_SCHEDULE_COMMAND_A_LOCKED;

    if ((schedule_status & target_lock) != 0u)
        return 0u;

    hx5_d20_write_command_bank(
        target_bank,
        commands,
        control->next_command_sequence,
        control->hand_id
    );
    control->next_command_sequence++;

    // Enabling only after the atomic bank commit prevents the first frame
    // from being reported as stale or transmitting an all-zero payload.
    if (control->enabled == 0u) {
        PROTOCOL2_MMIO->rt_control = PROTOCOL2_RT_CONTROL_ENABLE;
        control->enabled = 1u;
    }
    return 1u;
}

static inline uint32_t hx5_rt_control_try_read_feedback(
    hx5_d20_feedback_t *feedback
) {
    return hx5_d20_read_feedback(feedback);
}

static inline uint32_t hx5_rt_control_take_irq(void) {
    uint32_t pending = PROTOCOL2_MMIO->rt_irq_status;

    if (pending != 0u)
        PROTOCOL2_MMIO->rt_irq_status = pending;

    return pending;
}

static inline void hx5_rt_control_abort(hx5_rt_control_t *control) {
    PROTOCOL2_MMIO->rt_control = 0u;
    PROTOCOL2_MMIO->abort_flush = PROTOCOL2_ABORT_ALL;
    if (control != 0)
        control->enabled = 0u;
}

#endif
