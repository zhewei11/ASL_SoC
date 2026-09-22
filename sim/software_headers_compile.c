#include "asl_soc_config.h"
#include "asl_soc_mmio.h"
#include "hx5_d20_protocol.h"
#include "hx5_rt_control.h"
#include "protocol2_mmio.h"

_Static_assert(ASL_SOC_CNN_MMIO_BASE == UINT32_C(0x10032000),
               "CNN MMIO base mismatch");
_Static_assert(ASL_SOC_DMA_UNCACHED_BASE == UINT32_C(0x20000000),
               "DMA window mismatch");
_Static_assert(ASL_SOC_MOTOR_COUNT == 20u, "motor count mismatch");
_Static_assert(PROTOCOL2_MMIO_BASE == ASL_SOC_PROTOCOL2_MMIO_BASE,
               "Protocol MMIO base mismatch");
_Static_assert(ASL_IRQ_SOURCE_ETH_ERROR == 8u,
               "interrupt source ABI mismatch");
_Static_assert(ASL_TIMER_MTIME_LO_OFFSET == UINT32_C(0x008),
               "machine timer ABI mismatch");
_Static_assert(sizeof(protocol2_descriptor_t) == 40u,
               "Protocol descriptor ABI mismatch");
_Static_assert(HX5_D20_COMMAND_FRAME_BYTES <=
                   ASL_SOC_PROTOCOL_COMMAND_BYTES,
               "HX5 command frame exceeds Protocol command bank");
_Static_assert(HX5_D20_AXIS_COUNT == ASL_SOC_MOTOR_COUNT,
               "HX5 axis count mismatch");
_Static_assert(HX5_D20_RIGHT_HAND_ID_DEFAULT == 110u,
               "HX5 right-hand communication ID mismatch");
_Static_assert(sizeof(hx5_d20_axis_command_t) ==
                   HX5_D20_AXIS_COMMAND_BYTES,
               "HX5 compact command layout mismatch");
_Static_assert(HX5_D20_MOTOR_FEEDBACK_TOTAL +
                   HX5_D20_TACTILE_FEEDBACK_TOTAL ==
                   HX5_D20_FEEDBACK_BYTES,
               "HX5 feedback layout mismatch");
_Static_assert(HX5_D20_FEEDBACK_MAP_OFFSET + HX5_D20_FEEDBACK_BYTES <=
                   ASL_SOC_PROTOCOL_FEEDBACK_BYTES,
               "HX5 feedback frame exceeds Protocol feedback bank");
_Static_assert(HX5_D20_FEEDBACK_FRAME_BYTES <=
                   ASL_SOC_PROTOCOL_FEEDBACK_BYTES,
               "HX5 aligned feedback copy exceeds Protocol feedback bank");
_Static_assert(sizeof(hx5_rt_control_t) == 8u,
               "HX5 RT CPU control context layout mismatch");

int main(void) {
    return (int)(ASL_CNN_CONTROL_START | ASL_POSE_CONTROL_APPLY |
                 ASL_SAFETY_TORQUE_REQUEST | ASL_ETH_STATUS_BUFFER_HELD);
}
