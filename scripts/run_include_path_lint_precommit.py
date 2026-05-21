#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import re
import sys


kEligibleExtensions = {
    '.c',
    '.cc',
    '.cpp',
    '.cuh',
    '.cu',
    '.cxx',
    '.h',
    '.hh',
    '.hpp',
    '.hxx',
}
kEligibleRoots = {'include', 'src'}
kIncludePattern = re.compile(r'^\s*#\s*include\s*[<"]([^">]+)[>"]')


def NormalizePath(path: pathlib.Path | str) -> pathlib.PurePosixPath:
    candidate = pathlib.Path(path)
    if candidate.is_absolute():
        try:
            return pathlib.PurePosixPath(candidate.resolve().relative_to(pathlib.Path.cwd()).as_posix())
        except ValueError:
            return pathlib.PurePosixPath(candidate.as_posix())
    return pathlib.PurePosixPath(str(candidate).replace('\\', '/').removeprefix('./'))


def ShouldCheck(path: pathlib.Path) -> bool:
    if not path.exists() or path.is_dir():
        return False
    if path.suffix.lower() not in kEligibleExtensions:
        return False
    normalized_path = NormalizePath(path)
    return bool(normalized_path.parts) and normalized_path.parts[0] in kEligibleRoots


def UsesParentTraversal(include_target: str) -> bool:
    return '..' in pathlib.PurePosixPath(include_target).parts


def main(argv: list[str]) -> int:
    status = 0
    for raw_path in argv[1:]:
        path = pathlib.Path(raw_path)
        if not ShouldCheck(path):
            continue
        try:
            with path.open(encoding='utf-8') as handle:
                for line_number, line in enumerate(handle, start=1):
                    match = kIncludePattern.match(line)
                    if not match:
                        continue
                    include_target = match.group(1)
                    if not UsesParentTraversal(include_target):
                        continue
                    print(
                        'include-path-lint: '
                        f'{path}:{line_number}: forbidden parent-directory include path: '
                        f'{include_target}',
                        file=sys.stderr,
                    )
                    status = 1
        except OSError as exception:
            print(f'include-path-lint: {path}: {exception}', file=sys.stderr)
            status = 1
    return status


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
