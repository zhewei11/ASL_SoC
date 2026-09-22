#ifndef HX5_D20_PROTOCOL_H
#define HX5_D20_PROTOCOL_H

#include <stdint.h>

#include "asl_soc_config.h"
#include "asl_soc_mmio.h"
#include "protocol2_mmio.h"

#define HX5_D20_RIGHT_HAND_ID_DEFAULT      UINT32_C(110)
#define HX5_D20_BROADCAST_ID               UINT32_C(254)
#define HX5_D20_FINGER_COUNT               UINT32_C(5)
#define HX5_D20_MOTORS_PER_FINGER          UINT32_C(4)
#define HX5_D20_AXIS_COUNT                  UINT32_C(20)

#define HX5_D20_AXIS_COMMAND_BYTES         UINT32_C(4)
#define HX5_D20_COMMAND_PAYLOAD_BYTES      UINT32_C(80)
#define HX5_D20_SYNC_WRITE_BODY_BYTES      UINT32_C(86)
#define HX5_D20_READ_BODY_OFFSET           UINT32_C(88)
#define HX5_D20_READ_BODY_BYTES            UINT32_C(5)
#define HX5_D20_COMMAND_FRAME_BYTES        UINT32_C(96)

#define HX5_D20_MOTOR_FEEDBACK_BYTES       UINT32_C(6)
#define HX5_D20_MOTOR_FEEDBACK_TOTAL       UINT32_C(120)
#define HX5_D20_TACTILE_FEEDBACK_BYTES     UINT32_C(9)
#define HX5_D20_TACTILE_FEEDBACK_TOTAL     UINT32_C(45)
#define HX5_D20_FEEDBACK_BYTES             UINT32_C(165)
#define HX5_D20_FEEDBACK_MAP_OFFSET        PROTOCOL2_FEEDBACK_METADATA_BYTES
#define HX5_D20_FEEDBACK_FRAME_BYTES       UINT32_C(224)

#define HX5_D20_INSTRUCTION_READ           UINT32_C(0x02)
#define HX5_D20_INSTRUCTION_SYNC_WRITE     UINT32_C(0x83)
#define HX5_D20_INDIRECT_READ_ADDRESS      UINT32_C(634)
#define HX5_D20_INDIRECT_WRITE_ADDRESS     UINT32_C(799)
#define HX5_D20_LOGICAL_DEVICE_MASK        UINT32_C(0x00000001)
#define HX5_D20_RESPONSE_TIMEOUT_CYCLES    UINT32_C(60000)
#define HX5_D20_INTER_BYTE_TIMEOUT_CYCLES  UINT32_C(1000)
#define HX5_D20_RECONFIG_POLL_LIMIT        (ASL_SOC_RT_FRAME_CYCLES * 4u)

typedef struct {
    int16_t goal_position;
    int16_t goal_current;
} hx5_d20_axis_command_t;

typedef struct {
    int16_t present_position;
    int16_t present_velocity;
    int16_t present_current;
} hx5_d20_axis_feedback_t;

typedef struct {
    uint8_t pressure[HX5_D20_TACTILE_FEEDBACK_BYTES];
} hx5_d20_finger_feedback_t;

typedef struct {
    hx5_d20_axis_feedback_t axis[HX5_D20_AXIS_COUNT];
    hx5_d20_finger_feedback_t finger[HX5_D20_FINGER_COUNT];
} hx5_d20_feedback_t;

static inline void hx5_d20_store_u16_le(uint8_t *destination, uint16_t value) {
    destination[0] = (uint8_t)value;
    destination[1] = (uint8_t)(value >> 8);
}

static inline int16_t hx5_d20_load_i16_le(const uint8_t *source) {
    return (int16_t)((uint16_t)source[0] | ((uint16_t)source[1] << 8));
}

static inline uint32_t hx5_d20_load_u32_le(const uint8_t *source) {
    return (uint32_t)source[0] |
           ((uint32_t)source[1] << 8) |
           ((uint32_t)source[2] << 16) |
           ((uint32_t)source[3] << 24);
}

static inline uint8_t hx5_d20_valid_hand_id(uint32_t hand_id) {
    return (uint8_t)(hand_id <= 252u ?
        hand_id : HX5_D20_RIGHT_HAND_ID_DEFAULT);
}

static inline void hx5_d20_pack_axis_command(
    uint8_t destination[HX5_D20_AXIS_COMMAND_BYTES],
    const hx5_d20_axis_command_t *command
) {
    hx5_d20_store_u16_le(&destination[0], (uint16_t)command->goal_position);
    hx5_d20_store_u16_le(&destination[2], (uint16_t)command->goal_current);
}

static inline void hx5_d20_write_command_bank(
    uint32_t bank,
    const hx5_d20_axis_command_t commands[HX5_D20_AXIS_COUNT],
    uint32_t sequence,
    uint8_t hand_id
) {
    uint8_t frame[HX5_D20_COMMAND_FRAME_BYTES] = {0};

    frame[0] = (uint8_t)HX5_D20_INSTRUCTION_SYNC_WRITE;
    hx5_d20_store_u16_le(
        &frame[1],
        (uint16_t)HX5_D20_INDIRECT_WRITE_ADDRESS
    );
    hx5_d20_store_u16_le(
        &frame[3],
        (uint16_t)HX5_D20_COMMAND_PAYLOAD_BYTES
    );
    frame[5] = hx5_d20_valid_hand_id(hand_id);

    for (uint32_t axis = 0; axis < HX5_D20_AXIS_COUNT; ++axis) {
        hx5_d20_pack_axis_command(
            &frame[6u + axis * HX5_D20_AXIS_COMMAND_BYTES],
            &commands[axis]
        );
    }

    frame[HX5_D20_READ_BODY_OFFSET] = (uint8_t)HX5_D20_INSTRUCTION_READ;
    hx5_d20_store_u16_le(
        &frame[HX5_D20_READ_BODY_OFFSET + 1u],
        (uint16_t)HX5_D20_INDIRECT_READ_ADDRESS
    );
    hx5_d20_store_u16_le(
        &frame[HX5_D20_READ_BODY_OFFSET + 3u],
        (uint16_t)HX5_D20_FEEDBACK_BYTES
    );

    protocol2_rt_select_memory(
        bank ? PROTOCOL2_MEM_COMMAND_B : PROTOCOL2_MEM_COMMAND_A,
        0u,
        1u
    );
    for (uint32_t byte = 0; byte < HX5_D20_COMMAND_FRAME_BYTES; byte += 4u) {
        PROTOCOL2_MMIO->rt_mem_data =
            (uint32_t)frame[byte] |
            ((uint32_t)frame[byte + 1u] << 8) |
            ((uint32_t)frame[byte + 2u] << 16) |
            ((uint32_t)frame[byte + 3u] << 24);
    }

    protocol2_rt_commit_command(bank, sequence);
}

static inline void hx5_d20_program_schedule(uint8_t hand_id) {
    protocol2_rt_select_memory(PROTOCOL2_MEM_DESCRIPTOR, 0u, 1u);

    PROTOCOL2_MMIO->rt_mem_data = protocol2_descriptor_control(
        (uint8_t)HX5_D20_BROADCAST_ID,
        0u,
        PROTOCOL2_DESCRIPTOR_VALID | PROTOCOL2_DESCRIPTOR_ABORT_ON_ERROR
    );
    PROTOCOL2_MMIO->rt_mem_data = 0u;
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_SYNC_WRITE_BODY_BYTES;
    PROTOCOL2_MMIO->rt_mem_data = 0u;
    PROTOCOL2_MMIO->rt_mem_data = 0u;
    PROTOCOL2_MMIO->rt_mem_data = 0u;
    PROTOCOL2_MMIO->rt_mem_data = 0u;
    PROTOCOL2_MMIO->rt_mem_data = 0u;
    PROTOCOL2_MMIO->rt_mem_data = 1u;
    PROTOCOL2_MMIO->rt_mem_data = 1u;

    PROTOCOL2_MMIO->rt_mem_data = protocol2_descriptor_control(
        hand_id,
        (uint8_t)HX5_D20_FEEDBACK_BYTES,
        PROTOCOL2_DESCRIPTOR_VALID | PROTOCOL2_DESCRIPTOR_ABORT_ON_ERROR
    );
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_READ_BODY_OFFSET;
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_READ_BODY_BYTES;
    PROTOCOL2_MMIO->rt_mem_data = 1u;
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_LOGICAL_DEVICE_MASK;
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_RESPONSE_TIMEOUT_CYCLES;
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_INTER_BYTE_TIMEOUT_CYCLES;
    PROTOCOL2_MMIO->rt_mem_data = HX5_D20_FEEDBACK_MAP_OFFSET;
    PROTOCOL2_MMIO->rt_mem_data = 1u;
    PROTOCOL2_MMIO->rt_mem_data = PROTOCOL2_DESCRIPTOR_END;

    PROTOCOL2_MMIO->descriptor_count = PROTOCOL2_HX5_PROFILE_COUNT;
}

static inline uint32_t hx5_d20_supported_bus_baud(uint32_t baud_select) {
    return baud_select == PROTOCOL2_BAUD_4M ||
           baud_select == PROTOCOL2_BAUD_4M5 ||
           baud_select == PROTOCOL2_BAUD_6M;
}

static inline uint32_t hx5_d20_wait_mask_clear(
    volatile uint32_t *reg,
    uint32_t mask
) {
    uint32_t poll_count = 0u;

    while ((*reg & mask) != 0u) {
        if (++poll_count >= HX5_D20_RECONFIG_POLL_LIMIT)
            return 0u;
    }

    return 1u;
}

static inline uint32_t hx5_d20_set_hand_id(uint32_t hand_id) {
    volatile uint32_t *pose_hand_id = (volatile uint32_t *)(uintptr_t)(
        ASL_SOC_POSE_MMIO_BASE + ASL_POSE_HAND_ID_OFFSET
    );
    volatile uint32_t *pose_protocol_status =
        (volatile uint32_t *)(uintptr_t)(
            ASL_SOC_POSE_MMIO_BASE + ASL_POSE_PROTOCOL_STATUS_OFFSET
        );
    volatile uint32_t *pose_protocol_sequence =
        (volatile uint32_t *)(uintptr_t)(
            ASL_SOC_POSE_MMIO_BASE + ASL_POSE_PROTOCOL_SEQUENCE_OFFSET
        );
    uint32_t selected_hand_id = hx5_d20_valid_hand_id(hand_id);
    uint32_t restore_enable = PROTOCOL2_MMIO->rt_control &
        PROTOCOL2_RT_CONTROL_ENABLE;
    uint32_t sequence_before;

    // Stop and invalidate the current schedule before changing either copy of
    // the device ID. This prevents a new-ID Read descriptor from being paired
    // with an old-ID Sync Write command bank.
    PROTOCOL2_MMIO->rt_control = 0u;
    PROTOCOL2_MMIO->abort_flush = PROTOCOL2_ABORT_ALL;
    if (!hx5_d20_wait_mask_clear(
            &PROTOCOL2_MMIO->rt_status,
            PROTOCOL2_RT_STATUS_ACTIVE)) {
        return 0u;
    }

    if (!hx5_d20_wait_mask_clear(
            pose_protocol_status,
            ASL_POSE_PROTOCOL_BUSY)) {
        return 0u;
    }

    sequence_before = *pose_protocol_sequence;
    *pose_hand_id = selected_hand_id;

    // The adapter samples hand_id only when it commits a complete 20-axis
    // frame. Wait for that new-ID bank before re-enabling the RT owner.
    for (uint32_t poll_count = 0u;
         poll_count < HX5_D20_RECONFIG_POLL_LIMIT;
         ++poll_count) {
        uint32_t status = *pose_protocol_status;

        if ((*pose_protocol_sequence != sequence_before) &&
            ((status & ASL_POSE_PROTOCOL_BUSY) == 0u) &&
            ((status & ASL_POSE_PROTOCOL_ERROR) == 0u)) {
            hx5_d20_program_schedule((uint8_t)selected_hand_id);
            if (restore_enable != 0u)
                PROTOCOL2_MMIO->rt_control = PROTOCOL2_RT_CONTROL_ENABLE;
            return 1u;
        }
    }

    return 0u;
}

static inline void hx5_d20_enable_1khz_schedule(
    uint32_t bus_baud_select,
    uint32_t hand_id
) {
    uint8_t selected_hand_id = hx5_d20_valid_hand_id(hand_id);

    PROTOCOL2_MMIO->rt_control = 0u;
    PROTOCOL2_MMIO->protocol_owner = PROTOCOL2_OWNER_RT;
    PROTOCOL2_MMIO->baud_request = hx5_d20_supported_bus_baud(bus_baud_select) ?
        bus_baud_select : PROTOCOL2_BAUD_6M;
    PROTOCOL2_MMIO->frame_period_cycles = ASL_SOC_RT_FRAME_CYCLES;
    PROTOCOL2_MMIO->comm_deadline_cycles = PROTOCOL2_DEADLINE_DISABLED;
    PROTOCOL2_MMIO->command_deadline_cycles = PROTOCOL2_DEADLINE_DISABLED;
    if (!hx5_d20_set_hand_id(selected_hand_id))
        return;
    PROTOCOL2_MMIO->rt_control = PROTOCOL2_RT_CONTROL_ENABLE;
}

static inline uint32_t hx5_d20_read_feedback(hx5_d20_feedback_t *feedback) {
    uint8_t raw[HX5_D20_FEEDBACK_FRAME_BYTES];
    uint32_t status_before = PROTOCOL2_MMIO->rt_status;
    uint32_t bank =
        (status_before & PROTOCOL2_RT_STATUS_ACTIVE_FEEDBACK_BANK) != 0u;

    if (feedback == 0)
        return 0u;

    protocol2_rt_select_memory(
        bank ? PROTOCOL2_MEM_FEEDBACK_B : PROTOCOL2_MEM_FEEDBACK_A,
        0u,
        1u
    );
    for (uint32_t byte = 0; byte < HX5_D20_FEEDBACK_FRAME_BYTES; byte += 4u) {
        uint32_t word = PROTOCOL2_MMIO->rt_mem_data;

        for (uint32_t lane = 0; lane < 4u; ++lane)
            raw[byte + lane] = (uint8_t)(word >> (lane * 8u));
    }

    if (((PROTOCOL2_MMIO->rt_status &
          PROTOCOL2_RT_STATUS_ACTIVE_FEEDBACK_BANK) != 0u) != bank)
        return 0u;
    if (hx5_d20_load_u32_le(&raw[0]) != hx5_d20_load_u32_le(&raw[52]))
        return 0u;
    if ((hx5_d20_load_u32_le(&raw[40]) &
         (PROTOCOL2_FRAME_COMPLETE | PROTOCOL2_FRAME_ERROR)) !=
        PROTOCOL2_FRAME_COMPLETE)
        return 0u;

    for (uint32_t axis = 0; axis < HX5_D20_AXIS_COUNT; ++axis) {
        uint32_t offset = HX5_D20_FEEDBACK_MAP_OFFSET +
            axis * HX5_D20_MOTOR_FEEDBACK_BYTES;

        feedback->axis[axis].present_current =
            hx5_d20_load_i16_le(&raw[offset]);
        feedback->axis[axis].present_velocity =
            hx5_d20_load_i16_le(&raw[offset + 2u]);
        feedback->axis[axis].present_position =
            hx5_d20_load_i16_le(&raw[offset + 4u]);
    }

    for (uint32_t finger = 0; finger < HX5_D20_FINGER_COUNT; ++finger) {
        uint32_t offset = HX5_D20_FEEDBACK_MAP_OFFSET +
            HX5_D20_MOTOR_FEEDBACK_TOTAL +
            finger * HX5_D20_TACTILE_FEEDBACK_BYTES;

        for (uint32_t pressure = 0;
             pressure < HX5_D20_TACTILE_FEEDBACK_BYTES;
             ++pressure) {
            feedback->finger[finger].pressure[pressure] =
                raw[offset + pressure];
        }
    }

    return 1u;
}

#endif
