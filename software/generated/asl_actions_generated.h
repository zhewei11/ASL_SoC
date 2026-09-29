#ifndef ASL_ACTIONS_GENERATED_H
#define ASL_ACTIONS_GENERATED_H

#include <stddef.h>
#include <stdint.h>

#include "asl_motion.h"

#define ASL_GENERATED_TICK_HZ 1000u
#define ASL_GENERATED_ACTION_COUNT 24u

extern const uint8_t asl_generated_source_class_map[ASL_SOURCE_CLASS_COUNT];
extern const asl_keyframe_t asl_generated_keyframes[];
extern const size_t asl_generated_keyframe_count;
extern const asl_action_descriptor_t
    asl_generated_actions[ASL_GENERATED_ACTION_COUNT];

#endif
