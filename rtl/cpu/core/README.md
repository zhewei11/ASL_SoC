# Vendored RV32IMF Core

This directory owns the synthesizable fabric CPU used by `soc_core_top`.
It contains the integer pipeline, RV32M and RV32F units, 32-entry floating-point
register file, CSR/trap logic, branch predictor, instruction/data caches and
AXI/MMIO bridge. The SoC build defaults to `ENABLE_FPU=1`; the parameter can be
cleared for an integer-only resource-constrained build.

The sources were imported from the sibling `rtos_core` implementation and are
owned locally by this project. The ASL SoC build must not reference
`../rtos_core/src/IF`, `ID`, `EX`, `MEM`, `core.sv`, cache files or
`CPU_wrapper.sv`. Protocol 2.0 is independently owned by `rtl/protocol/core`.
