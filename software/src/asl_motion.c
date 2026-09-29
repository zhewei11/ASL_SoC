#include "asl_motion.h"

#include <limits.h>

#include "asl_actions_generated.h"

#define ASL_BLEND_ONE_Q16 UINT32_C(65536)

static uint16_t asl_nonzero_or_one(uint16_t value) {
    return value == 0u ? 1u : value;
}

static int16_t asl_interpolate_q12(
    int16_t start,
    int16_t target,
    uint16_t elapsed,
    uint16_t duration
) {
    uint32_t u;
    uint64_t u2;
    uint64_t u3;
    uint64_t u4;
    uint64_t u5;
    int64_t blend;
    int64_t scaled;
    int64_t rounded;

    if (elapsed >= duration)
        return target;

    u = (uint32_t)(((uint64_t)elapsed << 16) / duration);
    u2 = ((uint64_t)u * u) >> 16;
    u3 = (u2 * u) >> 16;
    u4 = (u3 * u) >> 16;
    u5 = (u4 * u) >> 16;
    blend = 10 * (int64_t)u3 - 15 * (int64_t)u4 + 6 * (int64_t)u5;
    if (blend < 0)
        blend = 0;
    if (blend > ASL_BLEND_ONE_Q16)
        blend = ASL_BLEND_ONE_Q16;

    scaled = (int64_t)(target - start) * blend;
    rounded = scaled >= 0 ?
        scaled + (ASL_BLEND_ONE_Q16 / 2u) :
        scaled - (ASL_BLEND_ONE_Q16 / 2u);
    return (int16_t)(start + rounded / (int64_t)ASL_BLEND_ONE_Q16);
}

uint8_t asl_source_index_to_class_id(uint8_t source_index) {
    if (source_index >= ASL_SOURCE_CLASS_COUNT)
        return ASL_CLASS_INVALID;
    return asl_generated_source_class_map[source_index];
}

char asl_class_id_to_letter(uint8_t class_id) {
    if (class_id >= ASL_CLASS_A && class_id <= ASL_CLASS_Z)
        return (char)('A' + (class_id - ASL_CLASS_A));
    return class_id == ASL_CLASS_OPEN ? '-' : '?';
}

const asl_action_descriptor_t *asl_action_find(uint8_t class_id) {
    size_t index;

    for (index = 0u; index < ASL_GENERATED_ACTION_COUNT; ++index) {
        if (asl_generated_actions[index].class_id == class_id)
            return &asl_generated_actions[index];
    }
    return NULL;
}

bool asl_class_has_static_action(uint8_t class_id) {
    return asl_action_find(class_id) != NULL;
}

const char *asl_phase_name(uint8_t phase) {
    switch ((asl_phase_t)phase) {
    case ASL_PHASE_RELEASE_THUMB:
        return "release_thumb";
    case ASL_PHASE_PREPARE_RELEASE_CROSSING:
        return "prepare_release_crossing";
    case ASL_PHASE_RELEASE_FINGER_SPREAD:
        return "release_finger_spread";
    case ASL_PHASE_RELEASE_NON_THUMB:
        return "release_non_thumb";
    case ASL_PHASE_RETRACT_THUMB:
        return "retract_thumb";
    case ASL_PHASE_FORM_NON_THUMB_SHAPE:
        return "form_non_thumb_shape";
    case ASL_PHASE_SET_FINGER_SPREAD:
        return "set_finger_spread";
    case ASL_PHASE_SETTLE_CROSSING:
        return "settle_crossing";
    case ASL_PHASE_POSITION_THUMB:
        return "position_thumb";
    case ASL_PHASE_TARGET_HOLD:
        return "target_hold";
    default:
        return "unknown";
    }
}

void asl_class_filter_init(
    asl_class_filter_t *filter,
    const asl_class_filter_config_t *config
) {
    if (filter == NULL)
        return;

    filter->config.confidence_threshold_q15 =
        config != NULL ? config->confidence_threshold_q15 : UINT16_C(27852);
    filter->config.stable_sample_count = asl_nonzero_or_one(
        config != NULL ? config->stable_sample_count : 4u
    );
    filter->config.release_sample_count = asl_nonzero_or_one(
        config != NULL ? config->release_sample_count : 3u
    );
    filter->config.repeat_guard_ms =
        config != NULL ? config->repeat_guard_ms : 250u;
    filter->stable_count = 0u;
    filter->release_count = 0u;
    filter->guard_ms_left = 0u;
    filter->candidate_class = ASL_CLASS_INVALID;
    filter->latched_class = ASL_CLASS_OPEN;
}

void asl_class_filter_advance_time_ms(
    asl_class_filter_t *filter,
    uint16_t elapsed_ms
) {
    if (filter == NULL)
        return;
    if (elapsed_ms >= filter->guard_ms_left)
        filter->guard_ms_left = 0u;
    else
        filter->guard_ms_left = (uint16_t)(filter->guard_ms_left - elapsed_ms);
}

void asl_class_filter_tick_1khz(asl_class_filter_t *filter) {
    asl_class_filter_advance_time_ms(filter, 1u);
}

bool asl_class_filter_update(
    asl_class_filter_t *filter,
    uint8_t class_id,
    uint16_t confidence_q15,
    uint8_t *accepted_class_id
) {
    bool release_observation;

    if (filter == NULL)
        return false;

    release_observation = class_id == ASL_CLASS_OPEN ||
        confidence_q15 < filter->config.confidence_threshold_q15 ||
        !asl_class_has_static_action(class_id);
    if (release_observation) {
        filter->candidate_class = ASL_CLASS_INVALID;
        filter->stable_count = 0u;
        if (filter->release_count < UINT16_MAX)
            ++filter->release_count;
        if (filter->release_count >= filter->config.release_sample_count) {
            filter->latched_class = ASL_CLASS_OPEN;
            filter->release_count = filter->config.release_sample_count;
        }
        return false;
    }

    filter->release_count = 0u;
    /* The same letter needs a release gap; a different stable letter does not. */
    if (filter->latched_class == class_id) {
        filter->candidate_class = ASL_CLASS_INVALID;
        filter->stable_count = 0u;
        return false;
    }

    if (filter->candidate_class != class_id) {
        filter->candidate_class = class_id;
        filter->stable_count = 1u;
    } else if (filter->stable_count < UINT16_MAX) {
        ++filter->stable_count;
    }

    if (filter->stable_count < filter->config.stable_sample_count ||
        filter->guard_ms_left != 0u) {
        return false;
    }

    filter->latched_class = class_id;
    filter->candidate_class = ASL_CLASS_INVALID;
    filter->stable_count = 0u;
    filter->guard_ms_left = filter->config.repeat_guard_ms;
    if (accepted_class_id != NULL)
        *accepted_class_id = class_id;
    return true;
}

void asl_action_queue_init(asl_action_queue_t *queue) {
    if (queue == NULL)
        return;
    queue->read_index = 0u;
    queue->write_index = 0u;
    queue->count = 0u;
}

bool asl_action_queue_push(asl_action_queue_t *queue, uint8_t class_id) {
    if (queue == NULL || queue->count >= ASL_ACTION_QUEUE_CAPACITY ||
        !asl_class_has_static_action(class_id)) {
        return false;
    }

    queue->entries[queue->write_index] = class_id;
    queue->write_index =
        (uint8_t)((queue->write_index + 1u) % ASL_ACTION_QUEUE_CAPACITY);
    ++queue->count;
    return true;
}

bool asl_action_queue_pop(asl_action_queue_t *queue, uint8_t *class_id) {
    if (queue == NULL || class_id == NULL || queue->count == 0u)
        return false;

    *class_id = queue->entries[queue->read_index];
    queue->read_index =
        (uint8_t)((queue->read_index + 1u) % ASL_ACTION_QUEUE_CAPACITY);
    --queue->count;
    return true;
}

uint8_t asl_action_queue_count(const asl_action_queue_t *queue) {
    return queue != NULL ? queue->count : 0u;
}

void asl_action_player_init_open(asl_action_player_t *player) {
    uint32_t joint;

    if (player == NULL)
        return;

    player->action = NULL;
    player->segment_elapsed_ticks = 0u;
    player->keyframe_index = 0u;
    player->completed_class_id = ASL_CLASS_INVALID;
    player->active = 0u;
    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        player->current_q12[joint] = 0;
        player->segment_start_q12[joint] = 0;
    }
}

bool asl_action_player_start(asl_action_player_t *player, uint8_t class_id) {
    const asl_action_descriptor_t *action;
    uint32_t joint;

    if (player == NULL || player->active != 0u)
        return false;

    action = asl_action_find(class_id);
    if (action == NULL || action->collision_approved == 0u ||
        action->keyframe_count == 0u) {
        return false;
    }

    /* Every generated/approved plan has OPEN as its required initial state. */
    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        if (player->current_q12[joint] != 0)
            return false;
        player->segment_start_q12[joint] = 0;
    }

    player->action = action;
    player->segment_elapsed_ticks = 0u;
    player->keyframe_index = 0u;
    player->completed_class_id = ASL_CLASS_INVALID;
    player->active = 1u;
    return true;
}

bool asl_action_player_tick_1khz(
    asl_action_player_t *player,
    int16_t output_q12[ASL_JOINT_COUNT],
    uint8_t *phase
) {
    const asl_keyframe_t *keyframe;
    uint16_t duration;
    uint32_t joint;

    if (player == NULL || output_q12 == NULL || player->active == 0u ||
        player->action == NULL) {
        return false;
    }

    keyframe = &asl_generated_keyframes[
        player->action->first_keyframe + player->keyframe_index
    ];
    duration = asl_nonzero_or_one(keyframe->duration_ticks);
    if (player->segment_elapsed_ticks < duration)
        ++player->segment_elapsed_ticks;

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        player->current_q12[joint] = asl_interpolate_q12(
            player->segment_start_q12[joint],
            keyframe->target_q12[joint],
            player->segment_elapsed_ticks,
            duration
        );
        output_q12[joint] = player->current_q12[joint];
    }
    if (phase != NULL)
        *phase = keyframe->phase;

    if (player->segment_elapsed_ticks < duration)
        return true;

    ++player->keyframe_index;
    player->segment_elapsed_ticks = 0u;
    if (player->keyframe_index >= player->action->keyframe_count) {
        player->completed_class_id = player->action->class_id;
        player->active = 0u;
        player->action = NULL;
        return true;
    }

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint)
        player->segment_start_q12[joint] = player->current_q12[joint];
    return true;
}

bool asl_action_player_is_active(const asl_action_player_t *player) {
    return player != NULL && player->active != 0u;
}

bool asl_action_player_take_completed(
    asl_action_player_t *player,
    uint8_t *completed_class_id
) {
    if (player == NULL || player->completed_class_id == ASL_CLASS_INVALID)
        return false;

    if (completed_class_id != NULL)
        *completed_class_id = player->completed_class_id;
    player->completed_class_id = ASL_CLASS_INVALID;
    return true;
}

void asl_action_player_get_current(
    const asl_action_player_t *player,
    int16_t output_q12[ASL_JOINT_COUNT]
) {
    uint32_t joint;

    if (player == NULL || output_q12 == NULL)
        return;
    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint)
        output_q12[joint] = player->current_q12[joint];
}

bool asl_joint_calibration_table_valid(
    const asl_joint_calibration_t calibration[ASL_JOINT_COUNT]
) {
    uint32_t joint;

    if (calibration == NULL)
        return false;

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        if (calibration[joint].valid == 0u ||
            calibration[joint].counts_per_radian_q16 == 0u ||
            (calibration[joint].direction != 1 &&
             calibration[joint].direction != -1) ||
            calibration[joint].minimum_raw > calibration[joint].center_raw ||
            calibration[joint].center_raw > calibration[joint].maximum_raw) {
            return false;
        }
    }
    return true;
}

bool asl_q12_to_raw_positions(
    const int16_t q12[ASL_JOINT_COUNT],
    const asl_joint_calibration_t calibration[ASL_JOINT_COUNT],
    int16_t raw_position[ASL_JOINT_COUNT]
) {
    const int64_t q28_half = INT64_C(1) << 27;
    const int64_t q28_one = INT64_C(1) << 28;
    uint32_t joint;

    if (q12 == NULL || raw_position == NULL ||
        !asl_joint_calibration_table_valid(calibration)) {
        return false;
    }

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        int64_t product =
            (int64_t)q12[joint] * calibration[joint].counts_per_radian_q16;
        int64_t magnitude = product >= 0 ? product : -product;
        int64_t delta = (magnitude + q28_half) / q28_one;
        int64_t raw;

        if (product < 0)
            delta = -delta;
        raw = calibration[joint].center_raw +
            (int64_t)calibration[joint].direction * delta;
        if (raw < calibration[joint].minimum_raw)
            raw = calibration[joint].minimum_raw;
        if (raw > calibration[joint].maximum_raw)
            raw = calibration[joint].maximum_raw;
        raw_position[joint] = (int16_t)raw;
    }
    return true;
}
