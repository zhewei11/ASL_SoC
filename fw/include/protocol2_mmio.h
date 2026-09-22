#ifndef PROTOCOL2_MMIO_H
#define PROTOCOL2_MMIO_H

#include <stdint.h>
#include "asl_soc_config.h"

#define PROTOCOL2_MMIO_BASE                 ASL_SOC_PROTOCOL2_MMIO_BASE

/* Legacy/direct Protocol 2.0 registers (kept ABI compatible). */
#define PROTOCOL2_CONTROL_OFFSET            0x00u
#define PROTOCOL2_STATUS_OFFSET             0x04u
#define PROTOCOL2_CMD_CONFIG_OFFSET         0x08u
#define PROTOCOL2_BODY_LENGTH_OFFSET        0x0Cu
#define PROTOCOL2_RESPONSE_TIMEOUT_OFFSET   0x10u
#define PROTOCOL2_INTER_BYTE_TIMEOUT_OFFSET 0x14u
#define PROTOCOL2_TX_DATA_OFFSET            0x18u
#define PROTOCOL2_RX_META_OFFSET            0x1Cu
#define PROTOCOL2_RX_LENGTH_OFFSET          0x20u
#define PROTOCOL2_RX_DATA_OFFSET            0x24u
#define PROTOCOL2_IRQ_STATUS_OFFSET         0x28u
#define PROTOCOL2_IRQ_ENABLE_OFFSET         0x2Cu
#define PROTOCOL2_ID_OFFSET                 0x30u
#define PROTOCOL2_TX_COUNT_OFFSET           0x34u

/* 1 kHz RT extension. */
#define PROTOCOL2_RT_CONTROL_OFFSET         0x40u
#define PROTOCOL2_RT_STATUS_OFFSET          0x44u
#define PROTOCOL2_FRAME_PERIOD_OFFSET       0x48u
#define PROTOCOL2_COMM_DEADLINE_OFFSET      0x4Cu
#define PROTOCOL2_COMMAND_DEADLINE_OFFSET   0x50u
#define PROTOCOL2_COMMAND_A_BASE_OFFSET     0x54u
#define PROTOCOL2_COMMAND_B_BASE_OFFSET     0x58u
#define PROTOCOL2_FEEDBACK_A_BASE_OFFSET    0x5Cu
#define PROTOCOL2_FEEDBACK_B_BASE_OFFSET    0x60u
#define PROTOCOL2_DESCRIPTOR_BASE_OFFSET    0x64u
#define PROTOCOL2_EXPECTED_MASK_OFFSET      0x68u
#define PROTOCOL2_RECEIVED_MASK_OFFSET      0x6Cu
#define PROTOCOL2_ERROR_MASK_OFFSET         0x70u
#define PROTOCOL2_FRAME_SEQUENCE_OFFSET     0x74u
#define PROTOCOL2_FRAME_CYCLES_OFFSET       0x78u
#define PROTOCOL2_MIN_SLACK_OFFSET          0x7Cu
#define PROTOCOL2_RT_IRQ_STATUS_OFFSET      0x80u
#define PROTOCOL2_RT_IRQ_ENABLE_OFFSET      0x84u
#define PROTOCOL2_ABORT_FLUSH_OFFSET        0x88u
#define PROTOCOL2_ERROR_COUNT_OFFSET        0x8Cu
#define PROTOCOL2_OWNER_OFFSET              0x90u
#define PROTOCOL2_BAUD_REQUEST_OFFSET       0x94u
#define PROTOCOL2_BAUD_STATUS_OFFSET        0x98u
#define PROTOCOL2_TEST_CONTROL_OFFSET       0x9Cu
#define PROTOCOL2_RAW_TX_DATA_OFFSET        0xA0u
#define PROTOCOL2_RAW_RX_DATA_OFFSET        0xA4u
#define PROTOCOL2_TEST_STATUS_OFFSET        0xA8u
#define PROTOCOL2_TEST_TX_COUNT_OFFSET      0xACu
#define PROTOCOL2_TEST_RX_COUNT_OFFSET      0xB0u
#define PROTOCOL2_TEST_ERROR_COUNT_OFFSET   0xB4u
#define PROTOCOL2_RT_MEM_ADDR_OFFSET        0xB8u
#define PROTOCOL2_RT_MEM_DATA_OFFSET        0xBCu
#define PROTOCOL2_COMMAND_COMMIT_OFFSET     0xC0u
#define PROTOCOL2_DESCRIPTOR_COUNT_OFFSET   0xC4u
#define PROTOCOL2_COMMAND_SEQUENCE_OFFSET   0xC8u
#define PROTOCOL2_STALE_MASK_OFFSET         0xCCu
#define PROTOCOL2_SCHEDULE_STATUS_OFFSET    0xD0u
#define PROTOCOL2_SCHEDULE_BUDGET_OFFSET    0xD4u
#define PROTOCOL2_COMMANDED_MASK_OFFSET     0xD8u

#define PROTOCOL2_CONTROL_START             (1u << 0)
#define PROTOCOL2_CONTROL_RESULT_ACK        (1u << 1)

#define PROTOCOL2_STATUS_COMMAND_READY      (1u << 0)
#define PROTOCOL2_STATUS_BUSY               (1u << 1)
#define PROTOCOL2_STATUS_BODY_READY         (1u << 2)
#define PROTOCOL2_STATUS_RESULT_PENDING     (1u << 3)
#define PROTOCOL2_STATUS_PARAMETER_VALID    (1u << 4)
#define PROTOCOL2_STATUS_DONE               (1u << 5)
#define PROTOCOL2_STATUS_ERROR              (1u << 6)
#define PROTOCOL2_STATUS_OVERRUN            (1u << 7)
#define PROTOCOL2_STATUS_COMMAND_PENDING    (1u << 8)

#define PROTOCOL2_IRQ_DONE                  (1u << 0)
#define PROTOCOL2_IRQ_ERROR                 (1u << 1)
#define PROTOCOL2_IRQ_RESULT                (1u << 2)
#define PROTOCOL2_IRQ_OVERRUN               (1u << 3)

#define PROTOCOL2_RT_CONTROL_ENABLE         (1u << 0)
#define PROTOCOL2_RT_CONTROL_SINGLE_STEP    (1u << 1)
#define PROTOCOL2_DEADLINE_DISABLED          0u
#define PROTOCOL2_RT_IRQ_FRAME_DONE         (1u << 0)
#define PROTOCOL2_RT_IRQ_FRAME_ERROR        (1u << 1)
#define PROTOCOL2_RT_IRQ_DEADLINE           (1u << 2)
#define PROTOCOL2_RT_IRQ_BUFFER_ERROR       (1u << 3)
#define PROTOCOL2_ABORT_ALL                 (1u << 0)

#define PROTOCOL2_RT_STATUS_SCHEDULE_VALID  (1u << 14)
#define PROTOCOL2_RT_STATUS_ENABLE          (1u << 0)
#define PROTOCOL2_RT_STATUS_ACTIVE          (1u << 1)
#define PROTOCOL2_RT_STATUS_SCHEDULE_OVERFLOW (1u << 15)
#define PROTOCOL2_RT_STATUS_SCHEDULE_CONFIG_ERROR (1u << 16)
#define PROTOCOL2_RT_STATUS_LATE_COMMIT     (1u << 17)
#define PROTOCOL2_RT_STATUS_COMMAND_A_LOCKED (1u << 18)
#define PROTOCOL2_RT_STATUS_COMMAND_B_LOCKED (1u << 19)
#define PROTOCOL2_RT_STATUS_ACTIVE_FEEDBACK_BANK (1u << 7)

#define PROTOCOL2_SCHEDULE_VALID            (1u << 0)
#define PROTOCOL2_SCHEDULE_OVERFLOW         (1u << 1)
#define PROTOCOL2_SCHEDULE_CONFIG_ERROR     (1u << 2)
#define PROTOCOL2_SCHEDULE_LATE_COMMIT      (1u << 3)
#define PROTOCOL2_SCHEDULE_COMMAND_A_LOCKED (1u << 10)
#define PROTOCOL2_SCHEDULE_COMMAND_B_LOCKED (1u << 11)

#define PROTOCOL2_FRAME_COMPLETE            (1u << 0)
#define PROTOCOL2_FRAME_ERROR               (1u << 1)
#define PROTOCOL2_FRAME_DEADLINE             (1u << 2)
#define PROTOCOL2_FRAME_STALE_COMMAND        (1u << 3)
#define PROTOCOL2_FRAME_DUPLICATE_ID         (1u << 4)
#define PROTOCOL2_FRAME_ABORTED              (1u << 5)
#define PROTOCOL2_FRAME_BUFFER_ERROR         (1u << 6)
#define PROTOCOL2_FRAME_RX_OVERRUN           (1u << 7)
#define PROTOCOL2_FRAME_UNEXPECTED_ID        (1u << 8)

#define PROTOCOL2_OWNER_RT                  0u
#define PROTOCOL2_OWNER_DIRECT              1u
#define PROTOCOL2_OWNER_RAW                 2u /* reserved until raw engine */

#define PROTOCOL2_BAUD_4M                   0u
#define PROTOCOL2_BAUD_4M5                  1u
#define PROTOCOL2_BAUD_6M                   2u

#define PROTOCOL2_MEM_COMMAND_A             0u
#define PROTOCOL2_MEM_COMMAND_B             1u
#define PROTOCOL2_MEM_FEEDBACK_A            2u
#define PROTOCOL2_MEM_FEEDBACK_B            3u
/* Generic descriptor RAM, or the fixed HX5 profile compatibility window. */
#define PROTOCOL2_MEM_DESCRIPTOR            4u
#define PROTOCOL2_MEM_AUTOINCREMENT         (1u << 31)
#define PROTOCOL2_COMMAND_COMMIT_VALID       (1u << 31)

#define PROTOCOL2_DESCRIPTOR_VALID           (1u << 0)
#define PROTOCOL2_DESCRIPTOR_ABORT_ON_ERROR  (1u << 1)
#define PROTOCOL2_DESCRIPTOR_ID_SHIFT        8u
#define PROTOCOL2_DESCRIPTOR_STRIDE_SHIFT    16u
#define PROTOCOL2_DESCRIPTOR_END             0xFFFFFFFFu
#define PROTOCOL2_MAX_BODY_BYTES             760u
#define PROTOCOL2_MAX_DESCRIPTOR_COUNT       25u
#define PROTOCOL2_HX5_PROFILE_COUNT           2u
#define PROTOCOL2_FEEDBACK_METADATA_BYTES    56u

#define PROTOCOL2_RX_DATA_VALUE_MASK        0xFFu
#define PROTOCOL2_RX_DATA_LAST              (1u << 8)
#define PROTOCOL2_PERIPHERAL_ID             0x50324D4Du

/* Used only when USE_HX5_RT_SEQUENCER=0; retained for firmware ABI reuse. */
typedef struct {
    uint32_t control;
    uint32_t tx_template_offset;
    uint32_t tx_body_length;
    uint32_t expected_response_count;
    /* Commanded devices; for responses, popcount must equal response_count. */
    uint32_t expected_device_mask;
    uint32_t response_timeout_cycles;
    uint32_t inter_byte_timeout_cycles;
    uint32_t response_map_offset;
    uint32_t period_divider;
    uint32_t next_descriptor;
} protocol2_descriptor_t;

typedef struct {
    uint32_t sequence;
    uint32_t command_sequence;
    uint64_t frame_start_timestamp;
    uint64_t frame_done_timestamp;
    uint32_t expected_device_mask;
    uint32_t received_device_mask;
    uint32_t error_device_mask;
    uint32_t stale_device_mask;
    uint32_t frame_status;
    uint32_t frame_cycles;
    uint32_t deadline_slack_cycles;
    uint32_t commit;
} protocol2_feedback_metadata_t;

typedef struct {
    volatile uint32_t control;              /* 0x00 */
    volatile uint32_t status;
    volatile uint32_t cmd_config;
    volatile uint32_t body_length;
    volatile uint32_t response_timeout;
    volatile uint32_t inter_byte_timeout;
    volatile uint32_t tx_data;
    volatile uint32_t rx_meta;
    volatile uint32_t rx_length;
    volatile uint32_t rx_data;
    volatile uint32_t irq_status;
    volatile uint32_t irq_enable;
    volatile uint32_t id;
    volatile uint32_t tx_count;             /* 0x34 */
    volatile uint32_t reserved_38[2];
    volatile uint32_t rt_control;           /* 0x40 */
    volatile uint32_t rt_status;
    volatile uint32_t frame_period_cycles;
    volatile uint32_t comm_deadline_cycles;
    volatile uint32_t command_deadline_cycles;
    volatile uint32_t command_a_base;
    volatile uint32_t command_b_base;
    volatile uint32_t feedback_a_base;
    volatile uint32_t feedback_b_base;
    volatile uint32_t descriptor_base;
    volatile uint32_t expected_id_mask;
    volatile uint32_t received_id_mask;
    volatile uint32_t error_id_mask;
    volatile uint32_t frame_sequence;
    volatile uint32_t frame_cycles;
    volatile uint32_t min_slack_cycles;
    volatile uint32_t rt_irq_status;
    volatile uint32_t rt_irq_enable;
    volatile uint32_t abort_flush;
    volatile uint32_t error_count;
    volatile uint32_t protocol_owner;
    volatile uint32_t baud_request;
    volatile uint32_t baud_status;
    volatile uint32_t test_control;
    volatile uint32_t raw_tx_data;
    volatile uint32_t raw_rx_data;
    volatile uint32_t test_status;
    volatile uint32_t test_tx_count;
    volatile uint32_t test_rx_count;
    volatile uint32_t test_error_count;
    volatile uint32_t rt_mem_addr;
    volatile uint32_t rt_mem_data;
    volatile uint32_t command_commit;
    volatile uint32_t descriptor_count;
    volatile uint32_t command_sequence;
    volatile uint32_t stale_id_mask;
    volatile uint32_t schedule_status;
    volatile uint32_t schedule_budget_cycles;
    volatile uint32_t commanded_id_mask;
} protocol2_mmio_regs_t;

#define PROTOCOL2_MMIO \
    ((protocol2_mmio_regs_t *)(uintptr_t)PROTOCOL2_MMIO_BASE)

static inline uint32_t protocol2_cmd_config(
    uint8_t id,
    uint8_t expected_id,
    uint8_t response_count
) {
    return ((uint32_t)id) |
           ((uint32_t)expected_id << 8) |
           ((uint32_t)response_count << 16);
}

static inline uint32_t protocol2_descriptor_control(
    uint8_t id,
    uint8_t response_stride,
    uint32_t flags
) {
    return flags |
           ((uint32_t)id << PROTOCOL2_DESCRIPTOR_ID_SHIFT) |
           ((uint32_t)response_stride << PROTOCOL2_DESCRIPTOR_STRIDE_SHIFT);
}

static inline void protocol2_start(void) {
    PROTOCOL2_MMIO->control = PROTOCOL2_CONTROL_START;
}

static inline void protocol2_write_body_byte(uint8_t value) {
    PROTOCOL2_MMIO->tx_data = value;
}

static inline uint32_t protocol2_read_parameter(void) {
    return PROTOCOL2_MMIO->rx_data;
}

static inline void protocol2_ack_result(void) {
    PROTOCOL2_MMIO->control = PROTOCOL2_CONTROL_RESULT_ACK;
}

static inline void protocol2_clear_irq(uint32_t mask) {
    PROTOCOL2_MMIO->irq_status = mask;
}

static inline void protocol2_rt_select_memory(
    uint32_t region,
    uint32_t byte_offset,
    uint32_t autoincrement
) {
    PROTOCOL2_MMIO->rt_mem_addr =
        ((region & 7u) << 12) |
        (byte_offset & 0xFFFu) |
        (autoincrement ? PROTOCOL2_MEM_AUTOINCREMENT : 0u);
}

static inline void protocol2_rt_commit_command(
    uint32_t bank,
    uint32_t sequence
) {
    PROTOCOL2_MMIO->command_sequence = sequence;
    PROTOCOL2_MMIO->command_commit =
        PROTOCOL2_COMMAND_COMMIT_VALID | (bank & 1u);
}

#endif
