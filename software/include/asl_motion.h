#ifndef ASL_MOTION_H
#define ASL_MOTION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ASL_JOINT_COUNT                 20u
#define ASL_SOURCE_CLASS_COUNT          24u
#define ASL_Q12_FRACTION_BITS           12u
#define ASL_CONFIDENCE_Q15_MAX          UINT16_C(32767)
#define ASL_ACTION_QUEUE_CAPACITY       8u
#define ASL_CLASS_INVALID               UINT8_C(255)

/*
 * Stable application ABI.  Alphabetic IDs deliberately keep the J and Z
 * holes even though those two letters require dynamic trajectories that are
 * not present in the current source data.
 */
typedef enum {
    ASL_CLASS_OPEN = 0,
    ASL_CLASS_A = 1,
    ASL_CLASS_B = 2,
    ASL_CLASS_C = 3,
    ASL_CLASS_D = 4,
    ASL_CLASS_E = 5,
    ASL_CLASS_F = 6,
    ASL_CLASS_G = 7,
    ASL_CLASS_H = 8,
    ASL_CLASS_I = 9,
    ASL_CLASS_J = 10,
    ASL_CLASS_K = 11,
    ASL_CLASS_L = 12,
    ASL_CLASS_M = 13,
    ASL_CLASS_N = 14,
    ASL_CLASS_O = 15,
    ASL_CLASS_P = 16,
    ASL_CLASS_Q = 17,
    ASL_CLASS_R = 18,
    ASL_CLASS_S = 19,
    ASL_CLASS_T = 20,
    ASL_CLASS_U = 21,
    ASL_CLASS_V = 22,
    ASL_CLASS_W = 23,
    ASL_CLASS_X = 24,
    ASL_CLASS_Y = 25,
    ASL_CLASS_Z = 26
} asl_class_id_t;

typedef enum {
    ASL_PHASE_UNKNOWN = 0,
    ASL_PHASE_RELEASE_THUMB,
    ASL_PHASE_PREPARE_RELEASE_CROSSING,
    ASL_PHASE_RELEASE_FINGER_SPREAD,
    ASL_PHASE_RELEASE_NON_THUMB,
    ASL_PHASE_RETRACT_THUMB,
    ASL_PHASE_FORM_NON_THUMB_SHAPE,
    ASL_PHASE_SET_FINGER_SPREAD,
    ASL_PHASE_SETTLE_CROSSING,
    ASL_PHASE_POSITION_THUMB,
    ASL_PHASE_TARGET_HOLD
} asl_phase_t;

enum {
    ASL_KEYFRAME_FLAG_HOLD = 1u << 0,
    ASL_KEYFRAME_FLAG_ACTION_END = 1u << 1
};

typedef struct {
    uint16_t duration_ticks;
    uint8_t phase;
    uint8_t flags;
    int16_t target_q12[ASL_JOINT_COUNT];
} asl_keyframe_t;

typedef struct {
    const char *plan_id;
    uint16_t first_keyframe;
    uint16_t total_ticks;
    uint8_t keyframe_count;
    uint8_t class_id;
    char letter;
    uint8_t collision_approved;
} asl_action_descriptor_t;

/* Maps CNN/source indices A-I,K-Y (0..23) onto the stable class ABI. */
uint8_t asl_source_index_to_class_id(uint8_t source_index);
char asl_class_id_to_letter(uint8_t class_id);
bool asl_class_has_static_action(uint8_t class_id);
const asl_action_descriptor_t *asl_action_find(uint8_t class_id);
const char *asl_phase_name(uint8_t phase);

typedef struct {
    uint16_t confidence_threshold_q15;
    uint16_t stable_sample_count;
    uint16_t release_sample_count;
    uint16_t repeat_guard_ms;
} asl_class_filter_config_t;

typedef struct {
    asl_class_filter_config_t config;
    uint16_t stable_count;
    uint16_t release_count;
    uint16_t guard_ms_left;
    uint8_t candidate_class;
    uint8_t latched_class;
} asl_class_filter_t;

void asl_class_filter_init(
    asl_class_filter_t *filter,
    const asl_class_filter_config_t *config
);
void asl_class_filter_advance_time_ms(
    asl_class_filter_t *filter,
    uint16_t elapsed_ms
);
void asl_class_filter_tick_1khz(asl_class_filter_t *filter);

/*
 * Returns true once for a newly accepted letter.  A stable OPEN observation
 * is required before the same or another letter can be emitted again.
 */
bool asl_class_filter_update(
    asl_class_filter_t *filter,
    uint8_t class_id,
    uint16_t confidence_q15,
    uint8_t *accepted_class_id
);

typedef struct {
    uint8_t entries[ASL_ACTION_QUEUE_CAPACITY];
    uint8_t read_index;
    uint8_t write_index;
    uint8_t count;
} asl_action_queue_t;

void asl_action_queue_init(asl_action_queue_t *queue);
bool asl_action_queue_push(asl_action_queue_t *queue, uint8_t class_id);
bool asl_action_queue_pop(asl_action_queue_t *queue, uint8_t *class_id);
uint8_t asl_action_queue_count(const asl_action_queue_t *queue);

typedef struct {
    const asl_action_descriptor_t *action;
    int16_t current_q12[ASL_JOINT_COUNT];
    int16_t segment_start_q12[ASL_JOINT_COUNT];
    uint16_t segment_elapsed_ticks;
    uint8_t keyframe_index;
    uint8_t completed_class_id;
    uint8_t active;
} asl_action_player_t;

/* The approved source plans all start and finish at OPEN (all-zero Q4.12). */
void asl_action_player_init_open(asl_action_player_t *player);
bool asl_action_player_start(asl_action_player_t *player, uint8_t class_id);

/* Advances exactly one 1 kHz sample and writes all 20 joint targets. */
bool asl_action_player_tick_1khz(
    asl_action_player_t *player,
    int16_t output_q12[ASL_JOINT_COUNT],
    uint8_t *phase
);

bool asl_action_player_is_active(const asl_action_player_t *player);
bool asl_action_player_take_completed(
    asl_action_player_t *player,
    uint8_t *completed_class_id
);
void asl_action_player_get_current(
    const asl_action_player_t *player,
    int16_t output_q12[ASL_JOINT_COUNT]
);

typedef struct {
    int16_t center_raw;
    int16_t minimum_raw;
    int16_t maximum_raw;
    int8_t direction;
    uint8_t valid;
    uint16_t reserved;
    uint32_t counts_per_radian_q16;
} asl_joint_calibration_t;

bool asl_joint_calibration_table_valid(
    const asl_joint_calibration_t calibration[ASL_JOINT_COUNT]
);
bool asl_q12_to_raw_positions(
    const int16_t q12[ASL_JOINT_COUNT],
    const asl_joint_calibration_t calibration[ASL_JOINT_COUNT],
    int16_t raw_position[ASL_JOINT_COUNT]
);

#ifdef __cplusplus
}
#endif

#endif
