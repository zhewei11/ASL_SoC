# Vendored Protocol 2.0 RT Core

This directory owns the synthesizable Protocol 2.0 implementation used by
`soc_core_top`: fractional UART timing, RS-485 PHY control, packet stuffing and
CRC TX/RX, ping-pong packet SRAM, the 1 kHz sequencer and MMIO wrapper.

`soc_core_top` now selects `protocol2_hx5_rt_sequencer` and sets
`CPU_OWNS_PROTOCOL_COMMANDS=1` by default. Software constructs the command
frame and owns trajectory policy; the sequencer repeats
one fixed 86-byte broadcast Sync Write and one fixed 5-byte unicast Read per
frame. It retains command/feedback ping-pong banks, atomic commit, timeout,
response ID/length validation, stale-command rejection and abort handling.
The hardware Pose-to-Protocol adapter remains an elaboration-time compatibility
path (`CPU_OWNS_PROTOCOL_COMMANDS=0`) and is never active beside the CPU writer.

The generic `protocol2_rt_engine` remains selectable through
`USE_HX5_RT_SEQUENCER=0` for compatibility regression. It is not elaborated in
the default SoC and therefore contributes no descriptor walker, period-counter,
budget or multi-device scatter logic to the synthesized design.

The source set is imported from the verified Protocol 2.0 implementation in
the sibling `rtos_core`. The ASL SoC build must not reference
`../rtos_core/src/protocol2` or `../rtos_core/src/protocol2_mmio_wrapper.sv`.
Board-specific wrappers are deliberately excluded from `soc_core_top`.

The 1 kHz frame period is a nominal trigger cadence rather than a mandatory
wire-time limit.  A zero `COMM_DEADLINE` disables runtime frame-deadline abort;
a zero `COMMAND_DEADLINE` disables the command-commit window. Response and
inter-byte timeouts, packet
validation, missing-device reporting and explicit abort remain active in this
best-effort mode.  Software can restore hard real-time enforcement by writing
non-zero deadlines before enabling the RT engine.

CPU software owns static wire-budget and deadline-contract validation. A
non-zero communication deadline remains enforced at runtime by the sequencer.

The packet SRAM holds 1015 stuffed body bytes. Direct TX commands expose a
760-byte unstuffed-body limit. The fixed RT bodies are compile-time checked
against the command banks. Runtime abort covers core errors and RT-layer
response faults (device error, unexpected ID, invalid length and UART overrun). Abort
uses a clocked flush throughout the protocol/UART hierarchy; only the external
`rst` input remains asynchronous.

The default sequencer has no descriptor SRAM. Its compatibility profile window
stores only the Read control word, response timeout and inter-byte timeout.
MMIO control fields honor byte write strobes, including owner, baud, profile
count and the two-byte command-commit operation.
