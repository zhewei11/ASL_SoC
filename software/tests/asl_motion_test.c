#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "asl_actions_generated.h"
#include "asl_motion.h"
#include "hx5_d20_protocol.h"

static unsigned checks;

#define CHECK(condition, message)                                            \
    do {                                                                     \
        if (!(condition)) {                                                  \
            fprintf(stderr, "FAIL: %s\n", (message));                      \
            return false;                                                    \
        }                                                                    \
        ++checks;                                                            \
    } while (0)

static bool vectors_equal(
    const int16_t left[ASL_JOINT_COUNT],
    const int16_t right[ASL_JOINT_COUNT]
) {
    uint32_t joint;

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        if (left[joint] != right[joint])
            return false;
    }
    return true;
}

static bool vector_is_open(const int16_t q12[ASL_JOINT_COUNT]) {
    uint32_t joint;

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        if (q12[joint] != 0)
            return false;
    }
    return true;
}

static bool test_all_action_players(void) {
    uint8_t source_index;

    for (source_index = 0u;
         source_index < ASL_SOURCE_CLASS_COUNT;
         ++source_index) {
        asl_action_player_t player;
        const asl_action_descriptor_t *action;
        int16_t output_q12[ASL_JOINT_COUNT];
        uint32_t elapsed = 0u;
        uint32_t keyframe_end = 0u;
        uint8_t expected_keyframe = 0u;
        uint8_t phase = ASL_PHASE_UNKNOWN;
        uint8_t completed = ASL_CLASS_INVALID;
        uint8_t class_id = asl_source_index_to_class_id(source_index);

        action = asl_action_find(class_id);
        CHECK(action != NULL, "static action lookup failed");
        CHECK(action->collision_approved != 0u, "unapproved action exposed");
        CHECK(action->letter == asl_class_id_to_letter(class_id),
              "class-to-letter mapping mismatch");

        asl_action_player_init_open(&player);
        CHECK(asl_action_player_start(&player, class_id),
              "approved action did not start from OPEN");

        keyframe_end = asl_generated_keyframes[
            action->first_keyframe
        ].duration_ticks;
        while (asl_action_player_is_active(&player)) {
            const asl_keyframe_t *keyframe = &asl_generated_keyframes[
                action->first_keyframe + expected_keyframe
            ];

            CHECK(asl_action_player_tick_1khz(&player, output_q12, &phase),
                  "active action failed to emit a frame");
            ++elapsed;
            CHECK(phase == keyframe->phase, "reported phase mismatch");
            if (elapsed == keyframe_end) {
                CHECK(vectors_equal(output_q12, keyframe->target_q12),
                      "segment did not finish at its keyframe");
                ++expected_keyframe;
                if (expected_keyframe < action->keyframe_count) {
                    keyframe_end += asl_generated_keyframes[
                        action->first_keyframe + expected_keyframe
                    ].duration_ticks;
                }
            }
            CHECK(elapsed <= action->total_ticks,
                  "action exceeded descriptor duration");
        }

        CHECK(elapsed == action->total_ticks, "action duration mismatch");
        CHECK(expected_keyframe == action->keyframe_count,
              "not every keyframe was reached");
        CHECK(vector_is_open(output_q12), "action did not return to OPEN");
        CHECK(asl_action_player_take_completed(&player, &completed),
              "completion event missing");
        CHECK(completed == class_id, "wrong completion class");
    }
    return true;
}

static bool test_filter_and_queue(void) {
    const asl_class_filter_config_t config = {
        .confidence_threshold_q15 = 28000u,
        .stable_sample_count = 3u,
        .release_sample_count = 2u,
        .repeat_guard_ms = 10u,
    };
    asl_class_filter_t filter;
    asl_action_queue_t queue;
    uint8_t accepted = ASL_CLASS_INVALID;
    uint8_t value = ASL_CLASS_INVALID;
    uint32_t sample;

    CHECK(asl_source_index_to_class_id(9u) == ASL_CLASS_K,
          "compact index did not skip J");
    CHECK(asl_source_index_to_class_id(ASL_SOURCE_CLASS_COUNT) ==
          ASL_CLASS_INVALID, "out-of-range source class accepted");
    CHECK(!asl_class_has_static_action(ASL_CLASS_J),
          "dynamic J incorrectly exposed as static");
    CHECK(!asl_class_has_static_action(ASL_CLASS_Z),
          "dynamic Z incorrectly exposed as static");

    asl_class_filter_init(&filter, &config);
    for (sample = 0u; sample < 2u; ++sample) {
        CHECK(!asl_class_filter_update(
                  &filter, ASL_CLASS_K, ASL_CONFIDENCE_Q15_MAX, &accepted),
              "filter accepted an unstable K");
    }
    CHECK(asl_class_filter_update(
              &filter, ASL_CLASS_K, ASL_CONFIDENCE_Q15_MAX, &accepted),
          "stable K was not accepted");
    CHECK(accepted == ASL_CLASS_K, "filter returned wrong class");

    asl_class_filter_advance_time_ms(&filter, 10u);
    for (sample = 0u; sample < 2u; ++sample) {
        CHECK(!asl_class_filter_update(
                  &filter, ASL_CLASS_L, ASL_CONFIDENCE_Q15_MAX, &accepted),
              "filter accepted an unstable direct transition");
    }
    CHECK(asl_class_filter_update(
              &filter, ASL_CLASS_L, ASL_CONFIDENCE_Q15_MAX, &accepted),
          "stable direct K-to-L transition was not accepted");

    asl_class_filter_advance_time_ms(&filter, 10u);
    CHECK(!asl_class_filter_update(&filter, ASL_CLASS_L, 0u, &accepted),
          "single low-confidence sample caused an event");
    CHECK(!asl_class_filter_update(&filter, ASL_CLASS_L, 0u, &accepted),
          "release observation caused an event");
    for (sample = 0u; sample < 2u; ++sample) {
        CHECK(!asl_class_filter_update(
                  &filter, ASL_CLASS_L, ASL_CONFIDENCE_Q15_MAX, &accepted),
              "same letter retriggered before stable count");
    }
    CHECK(asl_class_filter_update(
              &filter, ASL_CLASS_L, ASL_CONFIDENCE_Q15_MAX, &accepted),
          "same letter did not retrigger after release");

    asl_action_queue_init(&queue);
    for (sample = 0u; sample < ASL_ACTION_QUEUE_CAPACITY; ++sample)
        CHECK(asl_action_queue_push(&queue, ASL_CLASS_A), "queue fill failed");
    CHECK(!asl_action_queue_push(&queue, ASL_CLASS_B),
          "queue overflow was not rejected");
    CHECK(asl_action_queue_count(&queue) == ASL_ACTION_QUEUE_CAPACITY,
          "queue count mismatch");
    for (sample = 0u; sample < ASL_ACTION_QUEUE_CAPACITY; ++sample) {
        CHECK(asl_action_queue_pop(&queue, &value), "queue pop failed");
        CHECK(value == ASL_CLASS_A, "queue order mismatch");
    }
    CHECK(!asl_action_queue_pop(&queue, &value),
          "empty queue pop was not rejected");
    return true;
}

static bool capture_hold_pose(
    uint8_t class_id,
    int16_t target_q12[ASL_JOINT_COUNT]
) {
    asl_action_player_t player;
    int16_t output_q12[ASL_JOINT_COUNT];
    uint8_t phase = ASL_PHASE_UNKNOWN;
    uint32_t joint;

    asl_action_player_init_open(&player);
    if (!asl_action_player_start(&player, class_id))
        return false;
    while (asl_action_player_is_active(&player)) {
        if (!asl_action_player_tick_1khz(&player, output_q12, &phase))
            return false;
        if (phase == ASL_PHASE_TARGET_HOLD) {
            for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint)
                target_q12[joint] = output_q12[joint];
            return true;
        }
    }
    return false;
}

static bool build_protocol_vector(char letter, const char *output_path) {
    asl_joint_calibration_t calibration[ASL_JOINT_COUNT];
    hx5_d20_axis_command_t commands[HX5_D20_AXIS_COUNT];
    int16_t target_q12[ASL_JOINT_COUNT];
    int16_t raw_position[ASL_JOINT_COUNT];
    uint8_t frame[HX5_D20_COMMAND_FRAME_BYTES];
    uint8_t class_id;
    uint32_t joint;
    uint32_t byte;
    FILE *output;

    CHECK(letter >= 'A' && letter <= 'Z', "invalid requested letter");
    class_id = (uint8_t)(letter - 'A' + ASL_CLASS_A);
    CHECK(asl_class_has_static_action(class_id),
          "requested letter has no static action");
    CHECK(capture_hold_pose(class_id, target_q12),
          "failed to capture target-hold pose");

    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        calibration[joint].center_raw = 2048;
        calibration[joint].minimum_raw = 0;
        calibration[joint].maximum_raw = 4095;
        calibration[joint].direction = 1;
        calibration[joint].valid = 1u;
        calibration[joint].reserved = 0u;
        calibration[joint].counts_per_radian_q16 = UINT32_C(100) << 16;
    }
    CHECK(asl_q12_to_raw_positions(
              target_q12, calibration, raw_position),
          "Q4.12-to-raw calibration failed");

    for (joint = 0u; joint < HX5_D20_AXIS_COUNT; ++joint) {
        commands[joint].goal_position = raw_position[joint];
        commands[joint].goal_current = INT16_C(0x0123);
    }
    hx5_d20_build_command_frame(
        frame,
        commands,
        (uint8_t)HX5_D20_RIGHT_HAND_ID_DEFAULT
    );

    CHECK(frame[0] == HX5_D20_INSTRUCTION_SYNC_WRITE,
          "Sync Write instruction missing");
    CHECK(frame[1] == 0x1Fu && frame[2] == 0x03u,
          "indirect write address mismatch");
    CHECK(frame[3] == 80u && frame[4] == 0u,
          "20-axis payload length mismatch");
    CHECK(frame[5] == HX5_D20_RIGHT_HAND_ID_DEFAULT,
          "hand ID mismatch");
    CHECK(frame[HX5_D20_READ_BODY_OFFSET] == HX5_D20_INSTRUCTION_READ,
          "feedback Read instruction missing");

    output = fopen(output_path, "w");
    CHECK(output != NULL, "cannot create Protocol vector file");
    for (byte = 0u; byte < HX5_D20_COMMAND_FRAME_BYTES; ++byte) {
        if (fprintf(output, "%02X\n", frame[byte]) < 0) {
            (void)fclose(output);
            CHECK(false, "cannot write Protocol vector file");
        }
    }
    CHECK(fclose(output) == 0, "cannot close Protocol vector file");

    printf("%c target using simulation calibration ", letter);
    printf("(center=2048, 100 counts/rad):\n");
    for (joint = 0u; joint < ASL_JOINT_COUNT; ++joint) {
        double radians = (double)target_q12[joint] / (double)(1u << 12);
        double degrees = radians * 57.29577951308232;
        printf("  J%02u: q12=%6d, %8.3f deg, raw=%4d\n",
               joint + 1u, target_q12[joint], degrees, raw_position[joint]);
    }
    return true;
}

int main(int argc, char **argv) {
    char letter = 'A';
    const char *output_path = "build/asl_letter_command.mem";

    if (argc >= 2)
        letter = argv[1][0];
    if (argc >= 3)
        output_path = argv[2];

    if (!test_all_action_players() ||
        !test_filter_and_queue() ||
        !build_protocol_vector(letter, output_path)) {
        return EXIT_FAILURE;
    }
    printf("ASL motion software: %u checks passed; vector=%s\n",
           checks, output_path);
    return EXIT_SUCCESS;
}
