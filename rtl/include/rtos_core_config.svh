// Local compatibility configuration shared by the vendored CPU and Protocol 2.0 RTL.
`ifndef RTOS_CORE_CONFIG_SVH
`define RTOS_CORE_CONFIG_SVH

`include "asl_soc_config.svh"

`define RTOS_CORE_CPU_RESET_VECTOR         32'h0000_0000
`define RTOS_CORE_CPU_MACHINE_TRAP_VECTOR  32'h0001_0000
`define RTOS_CORE_CPU_MISA_VALUE           32'h4010_1120

`define RTOS_CORE_LOCAL_MMIO_BASE          32'h1003_0000
`define RTOS_CORE_LOCAL_MMIO_MASK          32'hFFFF_0000

// Parsed by the configurable CPU wrapper; EXTERNAL_MMIO_ONLY removes its
// legacy page decoder during elaboration in this SoC.
`define RTOS_CORE_PROTOCOL2_MMIO_BASE       32'h1003_0000
`define RTOS_CORE_INTERRUPT_CONTROLLER_BASE 32'h1003_1000
`define RTOS_CORE_COPROCESSOR_MMIO_BASE     32'h1003_2000
`define RTOS_CORE_MTIMECMP_BASE             32'h1003_4000
`define RTOS_CORE_MTIME_BASE                32'h1003_BFF8

`define RTOS_CORE_BTB_ENTRIES              64
`define RTOS_CORE_BHT_ENTRIES              1024
`define RTOS_CORE_RAS_DEPTH                8
`define RTOS_CORE_CACHE_SETS               32
`define RTOS_CORE_ICACHE_PREFETCH_ENABLE   1

`define RTOS_CORE_CPU_CLOCK_HZ              `ASL_SOC_CPU_HZ
`define RTOS_CORE_PROTOCOL2_BAUD_RATE       `ASL_SOC_PROTOCOL_BAUD
`define RTOS_CORE_PROTOCOL2_RX_OVERSAMPLE   16
`define RTOS_CORE_PROTOCOL2_DE_SETUP_CYCLES 2
`define RTOS_CORE_PROTOCOL2_POST_TX_GUARD_CYCLES 0
`define RTOS_CORE_PROTOCOL2_MAX_BODY_BYTES  760
`define RTOS_CORE_PROTOCOL2_MAX_STUFFED_BODY_BYTES 1015
`define RTOS_CORE_PROTOCOL2_MAX_PARAMETER_BYTES 1013
`define RTOS_CORE_PROTOCOL2_RT_FRAME_HZ     `ASL_SOC_RT_FRAME_HZ
// Zero selects best-effort Protocol scheduling. Per-response timeouts and all
// packet/error checks remain active, but the 1 kHz frame is not a hard
// communication or command-commit deadline.
`define RTOS_CORE_PROTOCOL2_RT_COMM_DEADLINE_US 0
`define RTOS_CORE_PROTOCOL2_RT_COMMAND_DEADLINE_US 0
`define RTOS_CORE_PROTOCOL2_RT_COMMAND_BUFFER_BYTES \
    `ASL_SOC_PROTOCOL_COMMAND_BYTES
`define RTOS_CORE_PROTOCOL2_RT_FEEDBACK_BUFFER_BYTES \
    `ASL_SOC_PROTOCOL_FEEDBACK_BYTES
`define RTOS_CORE_PROTOCOL2_RT_DESCRIPTOR_WORDS 256

`endif
