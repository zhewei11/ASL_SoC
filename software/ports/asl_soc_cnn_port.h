#ifndef ASL_SOC_CNN_PORT_H
#define ASL_SOC_CNN_PORT_H

#include <stdbool.h>
#include <stdint.h>

#include "asl_motion.h"

typedef struct {
    uint32_t last_sequence;
} asl_soc_cnn_port_t;

typedef struct {
    uint32_t sequence;
    uint16_t confidence_q15;
    uint8_t source_index;
} asl_soc_cnn_prediction_t;

void asl_soc_cnn_port_initialize(asl_soc_cnn_port_t *port);

/*
 * Reads one coherent, previously unseen CNN result.  The current RTL result
 * class is the compact A-I,K-Y source index (0..23), not asl_class_id_t.
 */
bool asl_soc_cnn_port_try_read(
    asl_soc_cnn_port_t *port,
    asl_soc_cnn_prediction_t *prediction
);

#endif
