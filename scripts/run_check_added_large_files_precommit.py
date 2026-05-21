#!/usr/bin/env python3

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys


def NormalizePath(path: pathlib.Path | str) -> str:
    return str(path).removeprefix('./')


def GetCandidatePaths(raw_paths: list[str]) -> list[pathlib.Path]:
    candidate_paths: list[pathlib.Path] = []
    for raw_path in raw_paths:
        path = pathlib.Path(raw_path)
        if path.exists() and path.is_file() and not path.is_symlink():
            candidate_paths.append(path)
    return candidate_paths


def GetAddedPathSet(candidate_paths: list[pathlib.Path]) -> set[str] | None:
    if not candidate_paths:
        return set()
    command = ['git', 'diff', '--cached', '--name-only', '--diff-filter=A', '-z', '--']
    command.extend(NormalizePath(path) for path in candidate_paths)
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        return None
    return {
        entry.decode('utf-8')
        for entry in result.stdout.split(b'\0')
        if entry
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--maxkb', type=int, default=1024)
    parser.add_argument('paths', nargs='*')
    args = parser.parse_args(argv[1:])

    candidate_paths = GetCandidatePaths(args.paths)
    added_path_set = GetAddedPathSet(candidate_paths)
    if added_path_set is None:
        paths_to_check = candidate_paths
    else:
        filtered_paths = [
            path for path in candidate_paths if NormalizePath(path) in added_path_set
        ]
        paths_to_check = filtered_paths if filtered_paths else candidate_paths

    max_bytes = args.maxkb * 1024
    oversized_paths: list[tuple[str, int]] = []
    for path in paths_to_check:
        size_bytes = path.stat().st_size
        if size_bytes > max_bytes:
            oversized_paths.append((str(path), size_bytes))

    for path, size_bytes in oversized_paths:
        size_kb = (size_bytes + 1023) // 1024
        print(
            f'check-added-large-files: {path} is {size_kb} KB; limit is {args.maxkb} KB.',
            file=sys.stderr,
        )
    return 1 if oversized_paths else 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
