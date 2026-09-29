# Vendored RV32IMF Core

This directory owns the synthesizable fabric CPU used by `soc_core_top`.
It contains the integer pipeline, RV32M and RV32F units, 32-entry floating-point
register file, CSR/trap logic, branch predictor, instruction/data caches and
AXI/MMIO bridge. The production `soc_core_top` is frozen to RV32IMF and always
enables the FPU; lower-level `ENABLE_FPU` parameters remain only for isolated
core verification and are not a supported SoC configuration.

The production MISA value is `0x40101120`: I, M, F and U are present, while A
and C are deliberately absent. The core implements a drained-pipeline Debug
Mode entry/exit, abstract GPR access and `dcsr`/`dpc`/`dscratch0`. The SoC-level
JTAG DTM and single-hart Debug Module are under `rtl/debug`; memory abstract
commands use the halted hart's normal uncached/cache data path.

Four 64-bit RISC-V HPM counters are implemented at `mhpmcounter3..6`, with
implementation-defined event masks in `mhpmevent3..6`. See
`docs/CPU_PERFORMANCE_MONITOR.md` for the event map and RTOS measurement flow.

The sources were imported from the sibling `rtos_core` implementation and are
owned locally by this project. The ASL SoC build must not reference
`../rtos_core/src/IF`, `ID`, `EX`, `MEM`, `core.sv`, cache files or
`CPU_wrapper.sv`. Protocol 2.0 is independently owned by `rtl/protocol/core`.
