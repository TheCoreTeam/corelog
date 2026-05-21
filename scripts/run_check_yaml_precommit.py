#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import sys

try:
    import yaml
except ModuleNotFoundError:
    print(
        'check-yaml: missing python module `yaml`; install PyYAML in the active python3 environment.',
        file=sys.stderr,
    )
    raise SystemExit(1)


def main(argv: list[str]) -> int:
    status = 0
    for raw_path in argv[1:]:
        path = pathlib.Path(raw_path)
        if not path.exists() or path.is_dir():
            continue
        try:
            with path.open('rb') as handle:
                list(yaml.safe_load_all(handle))
        except yaml.YAMLError as exception:
            print(f'check-yaml: {path}: {exception}', file=sys.stderr)
            status = 1
        except OSError as exception:
            print(f'check-yaml: {path}: {exception}', file=sys.stderr)
            status = 1
    return status


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
