#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import sys


kForbiddenSuffixes = {'.cc'}


def main(argv: list[str]) -> int:
    status = 0
    for raw_path in argv[1:]:
        path = pathlib.Path(raw_path)
        if not path.exists() or path.is_dir():
            continue
        suffix = path.suffix.lower()
        if suffix in kForbiddenSuffixes:
            print(
                f'file-suffix-lint: {path}: forbidden file suffix "{suffix}", '
                'use .cpp instead',
                file=sys.stderr,
            )
            status = 1
    return status


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
