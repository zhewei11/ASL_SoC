# HX5-D20 official indirect-data profile

The external RS-485 link addresses one HX5-D20 hand controller. This project
defaults to the official right-hand communication ID 110, but firmware may
select another valid Protocol 2.0 ID before enabling the schedule.

The cyclic layout follows the ROBOTIS ROS 2 configuration and uses both levels
of indirect mapping:

1. The controller's five TableSync channels exchange compact records with the
   internal XM335 actuators.
2. The host exchanges one contiguous indirect-data block with the hand
   controller, instead of sending five large direct TableSync writes.

Official references:

- [HX5-D20 right-hand ROS 2 control configuration](https://github.com/ROBOTIS-GIT/robotis_hand/blob/main/robotis_hand_description/ros2_control/hx5_d20_rev2/hx5_d20_right.ros2_control.xacro)
- [ROBOTIS hand controller control table](https://ai.robotis.com/hands/control_table_hands.html)
- [HX5-D20 controller model used by dynamixel_hardware_interface](https://github.com/ROBOTIS-GIT/dynamixel_hardware_interface/blob/main/param/dxl_model/hx5_d20_rr.model)

## One-time hand-controller setup

The official internal TableSync mapping is:

| Channel contents | Read | Write |
|---|---:|---:|
| Four XM335 motors per finger | Indirect Data 224, 6 bytes/motor | Indirect Data 230, 4 bytes/motor |
| One tactile sensor per finger | Address 72, 9 bytes | none |

Each motor's internal indirect addresses map:

| Direction | Bytes |
|---|---|
| Read | Present Current low 16, Present Velocity low 16, Present Position low 16 |
| Write | Goal Current 16, Goal Position low 16 |

The controller's host-facing indirect windows are:

| Window | Address | Bytes |
|---|---:|---:|
| Indirect Data Read | 634 | 165 |
| Indirect Data Write | 799 | 80 |

Operating Mode 5, Profile Velocity 100, and Profile Acceleration 50 are
initialization settings in the official right-hand profile. They are not
rewritten in every 1 kHz command. Goal Current remains the per-command current
limit for Current-Based Position Control.

The external Bus baud and internal DXL baud are different control-table
settings. The external bus supports 4, 4.5, and 6 Mbps. The internal actuator
bus remains at its supported maximum of 4 Mbps. Configure the controller's Bus
baud to the same value selected in the SoC before enabling cyclic traffic.

## TX command-bank ABI

The 96-byte staged command frame contains two word-aligned Protocol 2.0 bodies:

| Offset | Body | Transmitted bytes |
|---:|---|---:|
| 0 | Broadcast Sync Write (0x83) to address 799 | 86 |
| 88 | Unicast Read (0x02) from address 634 | 5 |

The Sync Write parameters declare an 80-byte item and contain one configurable
hand ID followed by 20 four-byte axis records. Each record is little-endian:

| Axis offset | Field | Size |
|---:|---|---:|
| 0 | Goal Position low 16 bits | 2 |
| 2 | Goal Current/current limit | 2 |

Bytes 86–87 and 93–95 are alignment padding and are not transmitted.

The Read descriptor uses the same configurable hand ID and requests 165 bytes.
For a one-device response, the RTL compares the complete 8-bit Protocol ID;
therefore ID 110 is no longer rejected by the legacy 32-device group mask.
ROBOTIS dynamixel_hardware_interface uses Fast Sync Read because its API is
generic for groups. This single-hand profile uses an ordinary unicast Read to
the same official indirect window; with exactly one communication ID it returns
the same 165 data bytes and avoids the embedded multi-device status format.

## RX feedback ABI

The validated 165-byte response is stored after the 56-byte atomic feedback
metadata. The CPU helper decodes the official actuator byte order:

| Payload offset | Contents | Bytes |
|---:|---|---:|
| 0 | 20 x (Present Current, Present Velocity, Present Position), 16-bit LE | 120 |
| 120 | Five fingers x nine tactile pressure bytes | 45 |

The hx5_d20_read_feedback() helper validates the atomic sequence and frame
status, then decodes all 20 motor records and all five tactile records. It
returns zero if the active ping-pong bank changes during the copy, so software
can retry without consuming a mixed or failed frame.

## Firmware controls

fw/include/hx5_d20_protocol.h provides:

- hx5_d20_write_command_bank(..., hand_id) for the same 96-byte ABI.
- hx5_d20_enable_1khz_schedule(baud_select, hand_id) for a matched TX/RX
  schedule.
- hx5_d20_set_hand_id(hand_id) to atomically stop/flush RT traffic, update the
  hardware Pose adapter, wait for a new complete command bank, rebuild the Read
  descriptor with the same ID, and restore RT enable only on success.
- hx5_d20_read_feedback() to return every motor and tactile value.

For the default CPU-owned architecture, `fw/include/hx5_rt_control.h` provides
non-blocking RTOS/bare-metal helpers. `hx5_rt_control_initialize()` stops and
flushes the engine, selects baud/ID and programs the fixed profile without
waiting for the hardware Pose adapter. `hx5_rt_control_try_submit()` writes an
unlocked inactive bank and enables the sequencer only after the first atomic
commit. The application must use either this CPU-owned path or the hardware
Pose adapter path, never both.

The hand ID also appears at Pose MMIO 0x1003_501C. Its reset value is 110;
software may write IDs 0–252. Invalid values passed through the firmware helper
fall back to 110.

Baud selectors are PROTOCOL2_BAUD_4M, PROTOCOL2_BAUD_4M5, and
PROTOCOL2_BAUD_6M. The default generated SoC clock profile is 6 Mbps.
Communication and command deadline registers remain disabled, so the scheduler
does not reject a valid command merely because a conservative timing estimate
exceeds one millisecond.

## Wire time and SRAM

Without byte stuffing, a cycle is:

- Sync Write: 95 bytes.
- Read request: 14 bytes.
- Status response with 165 parameters: 176 bytes.
- Total: 285 bytes.

That is approximately 712.5 us at 4 Mbps, 633.3 us at 4.5 Mbps, and 475 us at
6 Mbps, before turnaround and stuffing margins. Unlike the previous five-packet
380-byte command layout, the compact official mapping fits inside a 1 ms cycle
even at 4 Mbps in the normal unstuffed case.

Each command and feedback bank is 256 bytes. The command uses 96 bytes; feedback
uses 221 bytes including metadata. Two banks are retained on each side so a
frame can be transmitted or consumed while the next one is written atomically.
The default fixed HX5 sequencer stores only three 32-bit profile registers and
does not instantiate the generic 1 KiB descriptor SRAM.
