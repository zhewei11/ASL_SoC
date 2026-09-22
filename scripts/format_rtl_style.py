#!/usr/bin/env python3
"""Normalize RTL layout to the project's comma-first SystemVerilog style."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RTL_ROOT = PROJECT_ROOT / "rtl"
RTL_SUFFIXES = {".sv", ".v"}

ENTRY_RE = re.compile(
    r"^(?:,)?(?:input\b|output\b|inout\b|parameter\b|\.[A-Za-z_$][\w$]*\s*\()"
)
DECLARATION_RE = re.compile(
    r"^(?P<prefix>\s*(?:logic|wire|reg|integer|int)"
    r"(?:\s+(?:signed|unsigned))?(?:\s*\[[^\]]+\])*\s+)"
    r"(?P<body>.*?)(?P<suffix>;\s*(?://.*)?)$"
)
LOCALPARAM_RE = re.compile(
    r"^(?P<prefix>\s*localparam\s+(?:(?:logic|bit|wire|reg|integer|int)"
    r"(?:\s+(?:signed|unsigned))?(?:\s*\[[^\]]+\])*\s+)?)"
    r"(?P<body>.*?)(?P<suffix>;\s*(?://.*)?)$"
)


def split_top_level(text: str) -> list[str]:
    """Split commas that are outside (), [] and {}."""
    pieces: list[str] = []
    start = 0
    round_depth = square_depth = brace_depth = 0
    in_string = False
    escaped = False

    for index, char in enumerate(text):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "(":
            round_depth += 1
        elif char == ")":
            round_depth -= 1
        elif char == "[":
            square_depth += 1
        elif char == "]":
            square_depth -= 1
        elif char == "{":
            brace_depth += 1
        elif char == "}":
            brace_depth -= 1
        elif char == "," and not (round_depth or square_depth or brace_depth):
            pieces.append(text[start:index].strip())
            start = index + 1

    pieces.append(text[start:].strip())
    return pieces


def expand_named_connections(lines: list[str]) -> list[str]:
    expanded: list[str] = []
    for line in lines:
        code, separator, comment = line.partition("//")
        indent = code[: len(code) - len(code.lstrip())]
        stripped = code.strip()
        had_leading_comma = stripped.startswith(",")
        had_trailing_comma = stripped.endswith(",")
        connection_text = stripped.lstrip(",").rstrip(",").strip()
        pieces = split_top_level(connection_text)

        if len(pieces) > 1 and all(piece.startswith(".") for piece in pieces):
            for index, piece in enumerate(pieces):
                prefix = "," if had_leading_comma or index > 0 else ""
                suffix = "," if had_trailing_comma and index == len(pieces) - 1 else ""
                expanded.append(f"{indent}{prefix}{piece}{suffix}")
            if separator:
                expanded[-1] += f" //{comment}"
        else:
            expanded.append(line)
    return expanded


def convert_lists_to_comma_first(lines: list[str]) -> list[str]:
    converted = list(lines)

    for index, line in enumerate(converted):
        stripped = line.lstrip()
        if not ENTRY_RE.match(stripped):
            continue

        previous = index - 1
        while previous >= 0:
            previous_text = converted[previous].strip()
            if previous_text and not previous_text.startswith("//"):
                break
            previous -= 1

        if previous >= 0 and converted[previous].rstrip().endswith("("):
            opener_indent = len(converted[previous]) - len(converted[previous].lstrip())
            expected_indent = opener_indent + 5
            current_indent = len(line) - len(stripped)
            if not stripped.startswith(",") and current_indent != expected_indent:
                converted[index] = " " * expected_indent + stripped

    for index in range(len(converted) - 1):
        next_index = index + 1
        while next_index < len(converted):
            next_text = converted[next_index].strip()
            if next_text and not next_text.startswith("//"):
                break
            next_index += 1
        if next_index >= len(converted):
            continue

        next_stripped = converted[next_index].lstrip()
        if not ENTRY_RE.match(next_stripped):
            continue

        code, separator, comment = converted[index].partition("//")
        if not code.rstrip().endswith(","):
            continue

        code = code.rstrip()
        converted[index] = code[:-1].rstrip()
        if separator:
            converted[index] += f" //{comment}"

        if not next_stripped.startswith(","):
            indent = converted[next_index][: len(converted[next_index]) - len(next_stripped)]
            converted[next_index] = f"{indent},{next_stripped}"

    return converted


def split_declarations(lines: list[str]) -> list[str]:
    expanded: list[str] = []
    for line in lines:
        match = DECLARATION_RE.match(line) or LOCALPARAM_RE.match(line)
        if not match:
            expanded.append(line)
            continue

        pieces = split_top_level(match.group("body"))
        if len(pieces) == 1:
            expanded.append(line)
            continue

        suffix = match.group("suffix")
        for index, piece in enumerate(pieces):
            line_suffix = suffix if index == len(pieces) - 1 else ";"
            expanded.append(f"{match.group('prefix')}{piece}{line_suffix}")
    return expanded


def align_named_connections(lines: list[str]) -> list[str]:
    connection_re = re.compile(
        r"^(?P<indent>\s*)(?P<comma>,?)(?P<name>\.[A-Za-z_$][\w$]*)"
        r"\s*\((?P<value>.*)\)\s*$"
    )
    aligned = list(lines)
    index = 0

    while index < len(aligned):
        first = connection_re.match(aligned[index])
        if not first:
            index += 1
            continue

        end = index
        matches: list[tuple[int, re.Match[str]]] = []
        while end < len(aligned):
            stripped = aligned[end].strip()
            if end > index and (
                stripped.startswith(");")
                or (stripped.startswith(")") and stripped.endswith("("))
            ):
                break
            match = connection_re.match(aligned[end])
            if match:
                matches.append((end, match))
            end += 1

        widest_name = max(len(match.group("name")) for _, match in matches)
        for line_index, match in matches:
            padding = " " * (widest_name - len(match.group("name")) + 1)
            aligned[line_index] = (
                f"{match.group('indent')}{match.group('comma')}"
                f"{match.group('name')}{padding}({match.group('value')})"
            )
        index = end

    return aligned


def align_declarations(lines: list[str]) -> list[str]:
    declaration_re = re.compile(
        r"^(?P<indent>\s*)(?P<type>(?:logic|wire|reg|integer|int)"
        r"(?:\s+(?:signed|unsigned))?(?:\s*\[[^\]]+\])*)\s+"
        r"(?P<name>[A-Za-z_$][\w$]*(?:\s*\[[^\]]+\])*)"
        r"(?P<suffix>;\s*(?://.*)?)$"
    )
    aligned = list(lines)
    index = 0

    while index < len(aligned):
        first = declaration_re.match(aligned[index])
        if not first:
            index += 1
            continue

        end = index
        matches: list[re.Match[str]] = []
        while end < len(aligned):
            match = declaration_re.match(aligned[end])
            if not match:
                break
            matches.append(match)
            end += 1

        widest_type = max(len(match.group("type")) for match in matches)
        for offset, match in enumerate(matches):
            padding = " " * (widest_type - len(match.group("type")) + 1)
            aligned[index + offset] = (
                f"{match.group('indent')}{match.group('type')}{padding}"
                f"{match.group('name')}{match.group('suffix')}"
            )
        index = end

    return aligned


def indent_module_bodies(lines: list[str]) -> list[str]:
    indented = list(lines)
    search_from = 0

    while search_from < len(indented):
        module_index = next(
            (
                index
                for index in range(search_from, len(indented))
                if re.match(r"^\s*module\s+[A-Za-z_$][\w$]*", indented[index])
            ),
            None,
        )
        if module_index is None:
            break

        if indented[module_index].rstrip().endswith(";"):
            header_end = module_index
        else:
            header_end = next(
                index
                for index in range(module_index + 1, len(indented))
                if indented[index].strip().startswith(");")
            )

        module_end = next(
            index
            for index in range(header_end + 1, len(indented))
            if re.match(r"^\s*endmodule\b", indented[index])
        )
        body_lines = [
            line
            for line in indented[header_end + 1 : module_end]
            if line.strip()
            and not line.lstrip().startswith(("//", "/*", "*", "`"))
        ]

        if body_lines and min(len(line) - len(line.lstrip()) for line in body_lines) == 0:
            for index in range(header_end + 1, module_end):
                if indented[index].strip() and not indented[index].lstrip().startswith("`"):
                    indented[index] = "    " + indented[index]

        search_from = module_end + 1

    return indented


def format_text(text: str) -> str:
    lines = [line.rstrip() for line in text.splitlines()]
    lines = expand_named_connections(lines)
    lines = convert_lists_to_comma_first(lines)
    lines = split_declarations(lines)
    lines = indent_module_bodies(lines)
    lines = align_declarations(lines)
    lines = align_named_connections(lines)

    for index, line in enumerate(lines):
        lines[index] = re.sub(r"^(\s*module\s+[A-Za-z_$][\w$]*)\(", r"\1 (", line)
        lines[index] = re.sub(
            r"^(\s*[A-Za-z_$][\w$]*\s+[A-Za-z_$][\w$]*)\($", r"\1 (", line
        )

    return "\n".join(lines).rstrip() + "\n"


def rtl_files() -> list[Path]:
    return sorted(
        path for path in RTL_ROOT.rglob("*") if path.suffix in RTL_SUFFIXES
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="report files that need formatting"
    )
    args = parser.parse_args()

    changed: list[Path] = []
    for path in rtl_files():
        original = path.read_text(encoding="utf-8")
        formatted = format_text(original)
        if original == formatted:
            continue
        changed.append(path)
        if not args.check:
            path.write_text(formatted, encoding="utf-8")

    if args.check and changed:
        relative = "\n".join(str(path.relative_to(PROJECT_ROOT)) for path in changed)
        raise SystemExit(f"RTL formatting required:\n{relative}")

    action = "checked" if args.check else "formatted"
    print(f"{action} {len(rtl_files())} RTL files; {len(changed)} changed")


if __name__ == "__main__":
    main()
