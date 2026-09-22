#!/usr/bin/env python3
"""Validate the ASL SoC platform configuration and generate RTL/C headers."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config" / "asl_soc_config.json"


def number(value: int | str) -> int:
    return int(value, 0) if isinstance(value, str) else int(value)


def region(base: int, size: int, name: str) -> tuple[int, int, str]:
    if base & 3 or size <= 0 or size & 3:
        raise ValueError(f"{name} must be positive and 4-byte aligned")
    if base + size > 1 << 32:
        raise ValueError(f"{name} exceeds the 32-bit address space")
    return base, size, name


def contains(outer: tuple[int, int, str], inner: tuple[int, int, str]) -> bool:
    return outer[0] <= inner[0] and inner[0] + inner[1] <= outer[0] + outer[1]


def overlaps(a: tuple[int, int, str], b: tuple[int, int, str]) -> bool:
    return a[0] < b[0] + b[1] and b[0] < a[0] + a[1]


def define(name: str, value: int) -> str:
    return f"`define ASL_SOC_{name} 32'h{value:08X}"


def cdefine(name: str, value: int) -> str:
    return f"#define ASL_SOC_{name} UINT32_C(0x{value:08X})"


def validate_config(cfg: dict) -> dict[str, int]:
    if cfg.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")

    clock = cfg["clock"]
    memory = cfg["memory"]
    dma_config = cfg["dma"]
    mmio = cfg["mmio"]
    eth = cfg["ethernet"]
    cnn = cfg["cnn"]
    hand = cfg["hand"]
    protocol = cfg["protocol2"]
    uart = cfg["uart"]

    cpu_hz = number(clock["cpu_hz"])
    frame_hz = number(clock["rt_frame_hz"])
    if cpu_hz <= 0 or frame_hz <= 0 or cpu_hz % frame_hz:
        raise ValueError("cpu_hz must be an integer multiple of rt_frame_hz")

    boot = region(number(memory["boot_rom_base"]),
                  number(memory["boot_rom_bytes"]), "boot_rom")
    itcm = region(number(memory["itcm_base"]),
                  number(memory["itcm_bytes"]), "itcm")
    dtcm = region(number(memory["dtcm_base"]),
                  number(memory["dtcm_bytes"]), "dtcm")
    local_regions = (boot, itcm, dtcm)
    for index, first in enumerate(local_regions):
        for second in local_regions[index + 1:]:
            if overlaps(first, second):
                raise ValueError(f"{first[2]} and {second[2]} overlap")

    dram = region(number(memory["dram_base"]), number(memory["dram_bytes"]), "dram")
    dma = region(number(memory["dma_uncached_base"]), number(memory["dma_uncached_bytes"]), "dma_uncached")
    cached = region(number(memory["cached_dram_base"]), number(memory["cached_dram_bytes"]), "cached_dram")
    if not contains(dram, dma) or not contains(dram, cached):
        raise ValueError("cached and DMA windows must be contained in DRAM")
    if dma[0] + dma[1] > cached[0] and cached[0] + cached[1] > dma[0]:
        raise ValueError("cached and DMA windows overlap")

    max_burst_beats = number(dma_config["max_burst_beats"])
    if (max_burst_beats <= 0 or max_burst_beats > 256 or
            max_burst_beats & (max_burst_beats - 1)):
        raise ValueError("DMA max_burst_beats must be a 1..256 power of two")

    mmio_window = region(number(mmio["base"]), number(mmio["bytes"]), "mmio")
    page_addresses = []
    for key in (
        "protocol2_base", "interrupt_base", "cnn_base", "ethernet_base",
        "timer_base", "pose_base", "safety_base", "uart_base",
    ):
        address = number(mmio[key])
        page_addresses.append(address)
        if address & 0xFFF or not contains(mmio_window, region(address, 0x1000, key)):
            raise ValueError(f"{key} must be a 4 KiB page inside the MMIO window")
    if len(page_addresses) != len(set(page_addresses)):
        raise ValueError("MMIO peripheral pages must be unique")
    for local in local_regions:
        if overlaps(local, dram) or overlaps(local, mmio_window):
            raise ValueError(f"{local[2]} overlaps DRAM or MMIO")
    if overlaps(dram, mmio_window):
        raise ValueError("DRAM and MMIO overlap")

    if number(eth["stream_width"]) != 32:
        raise ValueError("the current Ethernet DMA shell supports a 32-bit stream")
    eth_buffer = region(number(eth["frame_buffer_base"]),
                        number(eth["max_frame_bytes"]), "ethernet_frame_buffer")
    if not contains(dma, eth_buffer):
        raise ValueError("Ethernet frame buffer exceeds the uncached DMA window")
    expected_input = number(cnn["input_width"]) * number(cnn["input_height"]) * number(cnn["input_channels"])
    if number(eth["max_frame_bytes"]) < expected_input:
        raise ValueError("Ethernet frame buffer cannot hold one CNN input")
    if number(hand["motor_count"]) != 20:
        raise ValueError("the first integration milestone requires exactly 20 motors")
    if number(hand["pose_count"]) < 3:
        raise ValueError("pose_count must include Neutral, A and B")
    if any(number(cnn[key]) <= 0 for key in (
        "input_width", "input_height", "input_channels", "mac_lanes",
        "local_sram_bytes", "stub_latency_cycles",
    )):
        raise ValueError("CNN dimensions and resource parameters must be positive")
    if number(protocol["baud"]) <= 0 or number(uart["baud"]) <= 0:
        raise ValueError("UART baud rates must be positive")
    for key in ("command_bytes", "feedback_bytes"):
        value = number(protocol[key])
        if value < 64 or value > 4096 or value & (value - 1):
            raise ValueError(f"protocol2 {key} must be a 64..4096 power of two")

    values = {
        "CPU_HZ": cpu_hz,
        "RT_FRAME_HZ": frame_hz,
        "RT_FRAME_CYCLES": cpu_hz // frame_hz,
        "BOOT_ROM_BASE": boot[0],
        "BOOT_ROM_BYTES": boot[1],
        "ITCM_BASE": itcm[0],
        "ITCM_BYTES": itcm[1],
        "DTCM_BASE": dtcm[0],
        "DTCM_BYTES": dtcm[1],
        "DRAM_BASE": dram[0],
        "DRAM_BYTES": dram[1],
        "DMA_UNCACHED_BASE": dma[0],
        "DMA_UNCACHED_BYTES": dma[1],
        "CACHED_DRAM_BASE": cached[0],
        "CACHED_DRAM_BYTES": cached[1],
        "DMA_MAX_BURST_BEATS": max_burst_beats,
        "MMIO_BASE": mmio_window[0],
        "MMIO_BYTES": mmio_window[1],
        "PROTOCOL2_MMIO_BASE": number(mmio["protocol2_base"]),
        "INTERRUPT_MMIO_BASE": number(mmio["interrupt_base"]),
        "CNN_MMIO_BASE": number(mmio["cnn_base"]),
        "ETHERNET_MMIO_BASE": number(mmio["ethernet_base"]),
        "TIMER_MMIO_BASE": number(mmio["timer_base"]),
        "POSE_MMIO_BASE": number(mmio["pose_base"]),
        "SAFETY_MMIO_BASE": number(mmio["safety_base"]),
        "UART_MMIO_BASE": number(mmio["uart_base"]),
        "ETH_STREAM_WIDTH": number(eth["stream_width"]),
        "ETH_FRAME_BUFFER_BASE": number(eth["frame_buffer_base"]),
        "ETH_MAX_FRAME_BYTES": number(eth["max_frame_bytes"]),
        "CNN_INPUT_WIDTH": number(cnn["input_width"]),
        "CNN_INPUT_HEIGHT": number(cnn["input_height"]),
        "CNN_INPUT_CHANNELS": number(cnn["input_channels"]),
        "CNN_MAC_LANES": number(cnn["mac_lanes"]),
        "CNN_LOCAL_SRAM_BYTES": number(cnn["local_sram_bytes"]),
        "CNN_STUB_LATENCY_CYCLES": number(cnn["stub_latency_cycles"]),
        "MOTOR_COUNT": number(hand["motor_count"]),
        "POSE_COUNT": number(hand["pose_count"]),
        "NEUTRAL_POSITION": number(hand["neutral_position"]),
        "DEFAULT_MAX_STEP": number(hand["default_max_step"]),
        "PROTOCOL_BAUD": number(protocol["baud"]),
        "PROTOCOL_COMMAND_BYTES": number(protocol["command_bytes"]),
        "PROTOCOL_FEEDBACK_BYTES": number(protocol["feedback_bytes"]),
        "UART_BAUD": number(uart["baud"]),
    }
    return values


def main() -> None:
    cfg = json.loads(CONFIG.read_text())
    values = validate_config(cfg)

    sv = [
        "// Generated by scripts/generate_config.py. Do not edit.",
        "`ifndef ASL_SOC_CONFIG_SVH",
        "`define ASL_SOC_CONFIG_SVH",
        *(define(name, value) for name, value in values.items()),
        "`endif",
        "",
    ]
    ch = [
        "/* Generated by scripts/generate_config.py. Do not edit. */",
        "#ifndef ASL_SOC_CONFIG_H",
        "#define ASL_SOC_CONFIG_H",
        "#include <stdint.h>",
        *(cdefine(name, value) for name, value in values.items()),
        "#endif",
        "",
    ]
    (ROOT / "rtl" / "include" / "asl_soc_config.svh").write_text("\n".join(sv))
    (ROOT / "fw" / "include" / "asl_soc_config.h").write_text("\n".join(ch))
    print(f"validated {CONFIG.relative_to(ROOT)}; generated {len(values)} constants")


if __name__ == "__main__":
    main()
