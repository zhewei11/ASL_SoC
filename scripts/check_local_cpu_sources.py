#!/usr/bin/env python3
"""Reject accidental dependencies on the sibling rtos_core CPU RTL."""

from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
FILE_LISTS = (
    PROJECT_ROOT / "rtl" / "cpu_rv32im.f",
    PROJECT_ROOT / "rtl" / "rtl_smoke.f",
)
REQUIRED_LOCAL_SOURCES = (
    "rtl/cpu/core/core.sv",
    "rtl/cpu/core/id/float_register_file.v",
    "rtl/cpu/core/ex/rv32f_unit.sv",
    "rtl/cpu/core/cache/CPU_wrapper.sv",
    "rtl/cpu/core/cache/L1C_inst.sv",
    "rtl/cpu/core/cache/L1C_data.sv",
    "rtl/cpu/core/cache/uncached_mmio_router.sv",
    "rtl/cpu/rv32im_cpu_subsystem.sv",
)
FORBIDDEN_EXTERNAL_CPU_PATHS = (
    "../rtos_core/src/IF/",
    "../rtos_core/src/ID/",
    "../rtos_core/src/EX/",
    "../rtos_core/src/MEM/",
    "../rtos_core/src/core.sv",
    "../rtos_core/src/L1C_inst.sv",
    "../rtos_core/src/L1C_data.sv",
    "../rtos_core/src/uncached_mmio_router.sv",
    "../rtos_core/src/CPU_wrapper.sv",
    "../rtos_core/include",
)


def main() -> None:
    failures: list[str] = []

    for file_list in FILE_LISTS:
        contents = file_list.read_text(encoding="utf-8")
        for forbidden in FORBIDDEN_EXTERNAL_CPU_PATHS:
            if forbidden in contents:
                failures.append(f"{file_list.relative_to(PROJECT_ROOT)}: {forbidden}")
        for required in REQUIRED_LOCAL_SOURCES:
            if required not in contents:
                failures.append(
                    f"{file_list.relative_to(PROJECT_ROOT)}: missing {required}"
                )

    local_rtl = tuple((PROJECT_ROOT / "rtl" / "cpu" / "core").rglob("*.sv"))
    local_rtl += tuple((PROJECT_ROOT / "rtl" / "cpu" / "core").rglob("*.v"))
    if not local_rtl:
        failures.append("rtl/cpu/core: no local RTL sources found")

    if failures:
        raise SystemExit("CPU source ownership check failed:\n  " + "\n  ".join(failures))

    print(
        f"CPU source ownership check passed: {len(local_rtl)} core RTL files are local; "
        "no external CPU RTL references"
    )


if __name__ == "__main__":
    main()
