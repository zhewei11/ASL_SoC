#!/usr/bin/env python3
"""Reject accidental dependencies on the sibling rtos_core Protocol RTL."""

from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
FILE_LIST = PROJECT_ROOT / "rtl" / "rtl_smoke.f"
PROTOCOL_DIR = PROJECT_ROOT / "rtl" / "protocol" / "core"
REQUIRED_LOCAL_SOURCES = (
    "uart_fractional_tick.sv",
    "uart_tx.sv",
    "uart_rx.sv",
    "rs485_uart_phy.sv",
    "protocol2_pingpong_sram.sv",
    "protocol2_tx.sv",
    "protocol2_rx.sv",
    "protocol2_core.sv",
    "protocol2_hx5_rt_sequencer.sv",
    "protocol2_rt_engine.sv",
    "protocol2_mmio_wrapper.sv",
)
FORBIDDEN_EXTERNAL_PATHS = (
    "../rtos_core/src/protocol2/",
    "../rtos_core/src/protocol2_mmio_wrapper.sv",
)


def main() -> None:
    contents = FILE_LIST.read_text(encoding="utf-8")
    failures: list[str] = []

    for forbidden in FORBIDDEN_EXTERNAL_PATHS:
        if forbidden in contents:
            failures.append(f"rtl/rtl_smoke.f: {forbidden}")

    for name in REQUIRED_LOCAL_SOURCES:
        local_path = PROTOCOL_DIR / name
        file_list_entry = f"rtl/protocol/core/{name}"
        if not local_path.is_file():
            failures.append(f"missing {file_list_entry}")
        if file_list_entry not in contents:
            failures.append(f"rtl/rtl_smoke.f: missing {file_list_entry}")

    if failures:
        raise SystemExit(
            "Protocol source ownership check failed:\n  " + "\n  ".join(failures)
        )

    print(
        f"Protocol source ownership check passed: {len(REQUIRED_LOCAL_SOURCES)} "
        "core RTL files are local; no external Protocol RTL references"
    )


if __name__ == "__main__":
    main()
