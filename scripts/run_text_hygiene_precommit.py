#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import sys


kMarkdownExtensions = {'.md', '.markdown'}


def NormalizeLineEndings(data: bytes) -> bytes:
    return data.replace(b'\r\n', b'\n').replace(b'\r', b'\n')


def PreserveMarkdownHardBreak(original_line: bytes, stripped_line: bytes) -> bytes:
    trailing = original_line[len(stripped_line):]
    if stripped_line and trailing and all(byte == 0x20 for byte in trailing) and len(trailing) >= 2:
        return stripped_line + b'  '
    return stripped_line


def TrimTrailingWhitespace(data: bytes, is_markdown: bool) -> bytes:
    ends_with_newline = data.endswith(b'\n')
    lines = data.split(b'\n')
    cleaned_lines: list[bytes] = []
    last_index = len(lines) - 1
    for index, line in enumerate(lines):
        if ends_with_newline and index == last_index and line == b'':
            cleaned_lines.append(b'')
            continue
        stripped_line = line.rstrip(b' \t\f\v')
        if is_markdown:
            stripped_line = PreserveMarkdownHardBreak(line, stripped_line)
        cleaned_lines.append(stripped_line)
    return b'\n'.join(cleaned_lines)


def FixEndOfFile(data: bytes) -> bytes:
    if not data:
        return data
    return data.rstrip(b'\n') + b'\n'


def FixFile(path: pathlib.Path) -> bool:
    original_data = path.read_bytes()
    updated_data = NormalizeLineEndings(original_data)
    updated_data = TrimTrailingWhitespace(
        updated_data, path.suffix.lower() in kMarkdownExtensions
    )
    updated_data = FixEndOfFile(updated_data)
    if updated_data == original_data:
        return False
    path.write_bytes(updated_data)
    return True


def main(argv: list[str]) -> int:
    modified_paths: list[str] = []
    failed_paths: list[str] = []
    for raw_path in argv[1:]:
        path = pathlib.Path(raw_path)
        if not path.exists() or path.is_dir():
            continue
        try:
            if FixFile(path):
                modified_paths.append(str(path))
        except OSError as exception:
            print(f'text-hygiene: {path}: {exception}', file=sys.stderr)
            failed_paths.append(str(path))
    for modified_path in modified_paths:
        print(f'text-hygiene: fixed {modified_path}')
    return 1 if modified_paths or failed_paths else 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
