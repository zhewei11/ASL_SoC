#!/usr/bin/env python3
"""Convert a little-endian firmware binary into readmemh 32-bit words."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--bytes", type=int, default=8192)
    args = parser.parse_args()

    data = args.input.read_bytes()
    if len(data) > args.bytes:
        raise SystemExit(f"firmware is {len(data)} bytes; limit is {args.bytes}")
    data += bytes(args.bytes - len(data))
    words = [
        int.from_bytes(data[offset : offset + 4], "little")
        for offset in range(0, len(data), 4)
    ]
    args.output.write_text(
        "".join(f"{word:08x}\n" for word in words), encoding="ascii"
    )


if __name__ == "__main__":
    main()

