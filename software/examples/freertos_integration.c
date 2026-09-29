/*
 * Integration template only.  Define ASL_ENABLE_FREERTOS_EXAMPLE in the
 * application that supplies the classifier and calibrated motor constants.
 */
#if defined(ASL_ENABLE_FREERTOS_EXAMPLE)

#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include "asl_motion.h"
#include "asl_soc_hx5_port.h"

typedef struct {
    uint8_t source_index;       /* A-I,K-Y => 0..23 */
    uint16_t confidence_q15;
    uint8_t no_gesture;
} app_asl_prediction_t;

/* These two hooks belong to the application/CNN driver. */
extern bool app_wait_for_asl_prediction(app_asl_prediction_t *prediction);
extern void app_report_motion_fault(void);

/* Fill these from measured HX5 calibration; zero/placeholder data is unsafe. */
extern const asl_joint_calibration_t app_hx5_calibration[ASL_JOINT_COUNT];
extern const int16_t app_hx5_goal_current[ASL_JOINT_COUNT];

static QueueHandle_t action_queue;
static TaskHandle_t motion_task_handle;
static asl_soc_hx5_port_t hx5_port;
static volatile uint32_t motion_fault_pending;

/* Wire this function into the SoC Protocol 2.0 interrupt handler. */
void app_asl_protocol2_isr(void) {
    BaseType_t higher_priority_task_woken = pdFALSE;
    uint32_t pending = hx5_rt_control_take_irq();

    if ((pending & (PROTOCOL2_RT_IRQ_FRAME_ERROR |
                    PROTOCOL2_RT_IRQ_DEADLINE |
                    PROTOCOL2_RT_IRQ_BUFFER_ERROR)) != 0u) {
        motion_fault_pending = 1u;
    }
    if ((pending & (PROTOCOL2_RT_IRQ_FRAME_DONE |
                    PROTOCOL2_RT_IRQ_FRAME_ERROR |
                    PROTOCOL2_RT_IRQ_DEADLINE |
                    PROTOCOL2_RT_IRQ_BUFFER_ERROR)) != 0u &&
        motion_task_handle != NULL) {
        vTaskNotifyGiveFromISR(
            motion_task_handle,
            &higher_priority_task_woken
        );
    }
    portYIELD_FROM_ISR(higher_priority_task_woken);
}

static void classifier_task(void *argument) {
    asl_class_filter_t filter;
    app_asl_prediction_t prediction;
    TickType_t previous_tick;
    uint8_t accepted;
    (void)argument;

    asl_class_filter_init(&filter, NULL);
    previous_tick = xTaskGetTickCount();
    for (;;) {
        TickType_t current_tick;
        uint64_t elapsed_ms;

        if (!app_wait_for_asl_prediction(&prediction))
            continue;
        current_tick = xTaskGetTickCount();
        elapsed_ms = ((uint64_t)(current_tick - previous_tick) * 1000u) /
            configTICK_RATE_HZ;
        if (elapsed_ms > UINT16_MAX)
            elapsed_ms = UINT16_MAX;
        asl_class_filter_advance_time_ms(&filter, (uint16_t)elapsed_ms);
        previous_tick = current_tick;
        if (asl_class_filter_update(
                &filter,
                prediction.no_gesture ? ASL_CLASS_OPEN :
                    asl_source_index_to_class_id(prediction.source_index),
                prediction.confidence_q15,
                &accepted)) {
            (void)xQueueSend(action_queue, &accepted, 0u);
        }
    }
}

static void motion_task(void *argument) {
    asl_action_player_t player;
    int16_t command_q12[ASL_JOINT_COUNT];
    uint8_t class_id;
    (void)argument;

    asl_action_player_init_open(&player);
    asl_action_player_get_current(&player, command_q12);

    /* First complete OPEN bank enables the hardware 1 kHz sequencer safely. */
    if (!asl_soc_hx5_port_try_submit_q12(&hx5_port, command_q12)) {
        app_report_motion_fault();
        vTaskSuspend(NULL);
    }

    for (;;) {
        /* Protocol frame-done ISR calls vTaskNotifyGiveFromISR(). */
        (void)ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        if (motion_fault_pending != 0u) {
            asl_soc_hx5_port_abort(&hx5_port);
            app_report_motion_fault();
            vTaskSuspend(NULL);
        }
        if (!asl_soc_hx5_port_ready(&hx5_port))
            continue;

        if (!asl_action_player_is_active(&player) &&
            xQueueReceive(action_queue, &class_id, 0u) == pdPASS) {
            (void)asl_action_player_start(&player, class_id);
        }

        if (asl_action_player_is_active(&player))
            (void)asl_action_player_tick_1khz(&player, command_q12, NULL);
        else
            asl_action_player_get_current(&player, command_q12);

        if (!asl_soc_hx5_port_try_submit_q12(&hx5_port, command_q12)) {
            app_report_motion_fault();
            asl_soc_hx5_port_abort(&hx5_port);
            vTaskSuspend(NULL);
        }
    }
}

/* Call only after clocks/MMIO/interrupt routing and the physical E-stop work. */
bool app_start_asl_tasks(void) {
    motion_fault_pending = 0u;
    motion_task_handle = NULL;
    action_queue = xQueueCreate(ASL_ACTION_QUEUE_CAPACITY, sizeof(uint8_t));
    if (action_queue == NULL ||
        !asl_soc_hx5_port_initialize(
            &hx5_port,
            PROTOCOL2_BAUD_6M,
            HX5_D20_RIGHT_HAND_ID_DEFAULT,
            app_hx5_calibration,
            app_hx5_goal_current)) {
        return false;
    }

    if (xTaskCreate(
            motion_task, "asl_motion", 1024u, NULL,
            configMAX_PRIORITIES - 1u, &motion_task_handle) != pdPASS) {
        return false;
    }
    return xTaskCreate(
        classifier_task, "asl_class", 1024u, NULL,
        tskIDLE_PRIORITY + 1u, NULL
    ) == pdPASS;
}

#endif
