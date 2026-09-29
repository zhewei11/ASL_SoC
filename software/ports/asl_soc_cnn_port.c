#include "asl_soc_cnn_port.h"

#include "asl_soc_mmio.h"

void asl_soc_cnn_port_initialize(asl_soc_cnn_port_t *port) {
    volatile uint32_t *sequence;

    if (port == NULL)
        return;
    sequence = asl_mmio_register(
        ASL_SOC_CNN_MMIO_BASE,
        ASL_CNN_SEQUENCE_OFFSET
    );
    port->last_sequence = *sequence;
}

bool asl_soc_cnn_port_try_read(
    asl_soc_cnn_port_t *port,
    asl_soc_cnn_prediction_t *prediction
) {
    volatile uint32_t *status;
    volatile uint32_t *result_register;
    volatile uint32_t *sequence_register;
    volatile uint32_t *control;
    uint32_t sequence_before;
    uint32_t sequence_after;
    uint32_t result;
    uint32_t confidence_u8;

    if (port == NULL || prediction == NULL)
        return false;

    status = asl_mmio_register(ASL_SOC_CNN_MMIO_BASE, ASL_CNN_STATUS_OFFSET);
    if ((*status & (ASL_CNN_STATUS_DONE | ASL_CNN_STATUS_ERROR)) !=
        ASL_CNN_STATUS_DONE) {
        return false;
    }

    sequence_register = asl_mmio_register(
        ASL_SOC_CNN_MMIO_BASE,
        ASL_CNN_SEQUENCE_OFFSET
    );
    result_register = asl_mmio_register(
        ASL_SOC_CNN_MMIO_BASE,
        ASL_CNN_RESULT_OFFSET
    );
    sequence_before = *sequence_register;
    result = *result_register;
    sequence_after = *sequence_register;
    if (sequence_before != sequence_after ||
        sequence_after == port->last_sequence) {
        return false;
    }

    prediction->source_index = (uint8_t)(result & UINT32_C(0xFF));
    confidence_u8 = (result >> ASL_CNN_CLASS_CONFIDENCE_SHIFT) &
        UINT32_C(0xFF);
    prediction->confidence_q15 = (uint16_t)(
        (confidence_u8 * ASL_CONFIDENCE_Q15_MAX + 127u) / 255u
    );
    prediction->sequence = sequence_after;
    port->last_sequence = sequence_after;

    control = asl_mmio_register(
        ASL_SOC_CNN_MMIO_BASE,
        ASL_CNN_CONTROL_OFFSET
    );
    *control = ASL_CNN_CONTROL_CLEAR_IRQ;
    return prediction->source_index < ASL_SOURCE_CLASS_COUNT;
}
