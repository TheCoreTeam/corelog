#!/usr/bin/env python3
"""
Convert a CMake/nvcc-generated compile_commands.json into a clang-tooling-friendly
compilation database.

nvcc and clang++ have incompatible command-line interfaces. This script transforms
nvcc compile commands (especially for .cu files) into clang++ commands that clangd
and clang-tidy can consume directly.

Usage:
    python3 nvcc_to_clang_compile_db.py \
        --input compile_commands.json \
        --output clang-tooling/compile_commands.json \
        --repo-root /path/to/repo \
        --cuda-include-dir /usr/local/cuda/include
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


# Flags that nvcc accepts but clang++ does not; drop them silently.
SKIP_EXACT = {
    "--compile",
    "--extended-lambda",
    "--expt-relaxed-constexpr",
    "--forward-unknown-to-host-compiler",
    "-forward-unknown-to-host-compiler",
    "-fopenmp",
}

# Flag prefixes that should be dropped entirely.
SKIP_PREFIXES = (
    "--generate-code=",
    "--relocatable-device-code=",
    "-diag-suppress=",
    "-gencode=",
    "-rdc=",
    "-fmodules",
    "-fmodule-mapper",
    "-fdeps-format",
)

# Single-letter prefixes that are passed through as-is.
PASS_THROUGH_SINGLE = (
    "-f",
    "-g",
    "-m",
    "-O",
    "-W",
)

# Exact flags that are passed through.
PASS_THROUGH_EXACT = {
    "-c",
    "-fPIC",
    "-pthread",
}

# Additional tooling-level adjustments: flags that break clangd/clang-tidy.
TOOLING_SKIP_EXACT = {
    "-fopenmp",
}

# Flags to append for tooling compatibility.
TOOLING_APPEND_EXACT = ("-U_OPENMP",)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a clang-tooling-friendly compilation database."
    )
    parser.add_argument("--input", required=True, help="Source compile_commands.json")
    parser.add_argument("--output", required=True, help="Derived compile_commands.json")
    parser.add_argument("--repo-root", required=True, help="Repository root")
    parser.add_argument(
        "--clang-cxx",
        default="",
        help="Optional clang++ executable to place in CUDA entries",
    )
    parser.add_argument(
        "--cuda-include-dir",
        default=[],
        action="append",
        help="CUDA toolkit include directory (for clang tooling to find cuda.h). May be specified multiple times.",
    )
    parser.add_argument(
        "--cuda-path",
        default="",
        help=(
            "CUDA toolkit root directory containing 'include/cuda.h' "
            "(emitted as '--cuda-path=<path>' so clang stops emitting "
            "drv_no_cuda_installation and resolves builtins like threadIdx)"
        ),
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress the generated-database status line",
    )
    return parser.parse_args()


def discover_cuda_include_dir() -> str | None:
    """Probe nvcc verbose output to find the CUDA toolkit include directory."""
    nvcc = shutil.which("nvcc")
    if not nvcc:
        return None

    try:
        result = subprocess.run(
            [nvcc, "--verbose", "-E", "-x", "cu", "-"],
            input="",
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None

    for line in result.stderr.splitlines():
        match = re.search(r'-I(\S*targets/[^\s"]*include[^\s"]*)', line)
        if match:
            raw = match.group(1).rstrip('"')
            resolved = str(Path(raw).resolve())
            if Path(resolved, "cuda.h").exists():
                return resolved
    return None


def choose_clang_driver(explicit: str) -> str:
    if explicit:
        return explicit

    for candidate in ("clang++-20", "clang++", "clang-20", "clang"):
        resolved = shutil.which(candidate)
        if resolved:
            return resolved

    raise SystemExit(
        "clang-tooling db generation failed: no clang++/clang compiler was found in PATH"
    )


def load_compile_db(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def tokenize(entry: dict) -> list[str]:
    if "arguments" in entry:
        return list(entry["arguments"])
    return shlex.split(entry["command"])


def normalize_path(value: str, workdir: Path) -> str:
    if value.startswith("="):
        value = value[1:]
    path = Path(value)
    if path.is_absolute():
        return str(path)
    return str((workdir / path).resolve())


def split_host_compiler_args(value: str) -> list[str]:
    split_args: list[str] = []
    for chunk in shlex.split(value):
        split_args.extend(part for part in chunk.split(",") if part)
    return split_args


def add_flag(flags: list[str], seen: set[tuple[str, ...]], *parts: str) -> None:
    cleaned = tuple(part for part in parts if part)
    if cleaned and cleaned not in seen:
        seen.add(cleaned)
        flags.extend(cleaned)


def _promote_cuda_include_to_isystem(
    arguments: list[str], cuda_include_dirs: list[str]
) -> list[str]:
    """Replace -I<cuda_include_dir> with -isystem<cuda_include_dir> in args."""
    if not cuda_include_dirs:
        return arguments
    cuda_paths = [Path(d).resolve() for d in cuda_include_dirs if d]
    if not cuda_paths:
        return arguments
    result: list[str] = []
    i = 0
    while i < len(arguments):
        arg = arguments[i]
        # Merged form: -I/path
        if arg.startswith("-I") and arg != "-I":
            path_val = arg[2:]
            if path_val and any(Path(path_val).resolve() == cp for cp in cuda_paths):
                result.append(f"-isystem{path_val}")
                i += 1
                continue
        # Split form: -I /path
        if arg == "-I" and i + 1 < len(arguments):
            path_val = arguments[i + 1]
            if path_val and any(Path(path_val).resolve() == cp for cp in cuda_paths):
                result.append("-isystem")
                result.append(path_val)
                i += 2
                continue
        result.append(arg)
        i += 1
    return result


def sanitize_tooling_arguments(arguments: list[str]) -> list[str]:
    sanitized = []
    skip_next = False
    for arg in arguments:
        if skip_next:
            skip_next = False
            continue
        if arg in TOOLING_SKIP_EXACT:
            continue
        if arg.startswith(SKIP_PREFIXES):
            # Drop -fmodule-mapper=... and standalone -fmodule-mapper
            if arg == "-fmodule-mapper":
                skip_next = True
            continue
        sanitized.append(arg)
    for arg in TOOLING_APPEND_EXACT:
        if arg not in sanitized:
            sanitized.append(arg)
    return sanitized


def derive_cuda_arguments(
    entry: dict,
    clang_driver: str,
    cuda_include_dirs: list[str] | None = None,
    cuda_path: str = "",
) -> list[str]:
    workdir = Path(entry["directory"]).resolve()
    source_path = str(Path(entry["file"]).resolve())
    output_path = entry.get("output", "")

    flags: list[str] = []
    seen: set[tuple[str, ...]] = set()

    if cuda_path:
        add_flag(flags, seen, f"--cuda-path={cuda_path}")

    def _resolve_include_paths_from_flags(flag_list: list[str]) -> set[str]:
        """Extract resolved absolute paths from -I and -isystem flags."""
        paths: set[str] = set()
        for i, f in enumerate(flag_list):
            if f == "-I" and i + 1 < len(flag_list):
                paths.add(str(Path(flag_list[i + 1]).resolve()))
            elif f.startswith("-I") and f != "-I":
                paths.add(str(Path(f[2:]).resolve()))
            elif f == "-isystem" and i + 1 < len(flag_list):
                paths.add(str(Path(flag_list[i + 1]).resolve()))
            elif f.startswith("-isystem") and f != "-isystem":
                paths.add(str(Path(f[len("-isystem"):]).resolve()))
        return paths

    def feed_tokens(items: list[str]) -> None:
        index = 0
        while index < len(items):
            token = items[index]

            if not token:
                index += 1
                continue

            candidate_source = Path(token)
            if token == source_path or (
                not candidate_source.is_absolute()
                and str((workdir / candidate_source).resolve()) == source_path
            ):
                index += 1
                continue

            if token in SKIP_EXACT or token.startswith(SKIP_PREFIXES):
                index += 1
                continue

            if token == "-o":
                index += 2
                continue

            if token in ("-I", "-isystem", "-include", "-D", "-U", "-std", "-x"):
                if index + 1 >= len(items):
                    index += 1
                    continue
                value = items[index + 1]
                if token in ("-I", "-isystem", "-include"):
                    value = normalize_path(value, workdir)
                elif token == "-x" and value in ("cu", "cuda"):
                    value = "cuda"
                add_flag(flags, seen, token, value)
                index += 2
                continue

            handled = False
            for prefix in ("-I", "-D", "-U", "-std="):
                if token.startswith(prefix) and token != prefix:
                    value = token[len(prefix) :]
                    if prefix == "-I":
                        value = normalize_path(value, workdir)
                    add_flag(flags, seen, f"{prefix}{value}")
                    handled = True
                    break
            if handled:
                index += 1
                continue

            if token.startswith("-isystem") and token != "-isystem":
                add_flag(
                    flags,
                    seen,
                    "-isystem",
                    normalize_path(token[len("-isystem") :], workdir),
                )
                index += 1
                continue

            if token.startswith("-include") and token != "-include":
                add_flag(
                    flags,
                    seen,
                    "-include",
                    normalize_path(token[len("-include") :], workdir),
                )
                index += 1
                continue

            if token.startswith("--options-file="):
                rsp_path = normalize_path(token.split("=", 1)[1], workdir)
                if os.path.exists(rsp_path):
                    with open(rsp_path, encoding="utf-8") as rsp_file:
                        feed_tokens(shlex.split(rsp_file.read()))
                index += 1
                continue

            if token == "--options-file":
                if index + 1 < len(items):
                    rsp_path = normalize_path(items[index + 1], workdir)
                    if os.path.exists(rsp_path):
                        with open(rsp_path, encoding="utf-8") as rsp_file:
                            feed_tokens(shlex.split(rsp_file.read()))
                index += 2
                continue

            if token.startswith("-Xcompiler="):
                for host_arg in split_host_compiler_args(token.split("=", 1)[1]):
                    feed_tokens([host_arg])
                index += 1
                continue

            if token == "-Xcompiler":
                if index + 1 < len(items):
                    for host_arg in split_host_compiler_args(items[index + 1]):
                        feed_tokens([host_arg])
                index += 2
                continue

            if token in ("-ccbin", "--compiler-bindir"):
                index += 2
                continue

            if token.startswith("--compiler-bindir=") or token.startswith("-ccbin="):
                index += 1
                continue

            if token in PASS_THROUGH_EXACT or token.startswith(PASS_THROUGH_SINGLE):
                add_flag(flags, seen, token)
                index += 1
                continue

            index += 1

    tokens = tokenize(entry)
    feed_tokens(tokens[1:])

    # Inject auto-detected include dirs that are not already covered by the
    # original compile command to work around CMake generator expressions that
    # may have failed to expand for CUDA response files.
    covered_paths = _resolve_include_paths_from_flags(flags)
    for cuda_include_dir in (cuda_include_dirs or []):
        if cuda_include_dir:
            resolved = str(Path(cuda_include_dir).resolve())
            if resolved not in covered_paths:
                add_flag(flags, seen, "-isystem", cuda_include_dir)

    add_flag(flags, seen, "-x", "cuda")
    add_flag(flags, seen, "--cuda-host-only")
    add_flag(flags, seen, "-Wno-unknown-cuda-version")

    arguments = [clang_driver, *flags]
    if "-c" not in flags:
        arguments.append("-c")
    arguments.append(source_path)
    if output_path:
        arguments.extend(["-o", output_path])
    return sanitize_tooling_arguments(arguments)


def transform_entry(
    entry: dict,
    clang_driver: str,
    cuda_include_dirs: list[str] | None = None,
    cuda_path: str = "",
) -> dict:
    transformed = dict(entry)
    file_path = Path(entry["file"])
    if file_path.suffix != ".cu":
        transformed.pop("command", None)
        args = sanitize_tooling_arguments(tokenize(entry))
        # Project headers (platform.h, robust_kernel.h) use CUDA keywords
        # __host__ / __device__ / __forceinline__ as function qualifiers.
        # When clangd parses a .cpp file these keywords are not defined.
        # Stub them out so clangd can parse the translation unit.
        args = [args[0], "-D__host__=", "-D__device__=", "-D__forceinline__=inline"] + args[1:]
        transformed["arguments"] = _promote_cuda_include_to_isystem(
            args, cuda_include_dirs
        )
        return transformed

    transformed.pop("command", None)
    args = derive_cuda_arguments(
        entry, clang_driver, cuda_include_dirs, cuda_path
    )
    transformed["arguments"] = _promote_cuda_include_to_isystem(
        args, cuda_include_dirs
    )
    return transformed


def main() -> int:
    args = parse_args()
    input_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()
    repo_root = Path(args.repo_root).resolve()
    clang_driver = choose_clang_driver(args.clang_cxx)

    cuda_include_dirs: list[str] = args.cuda_include_dir or []
    if not cuda_include_dirs:
        discovered = discover_cuda_include_dir()
        if discovered:
            cuda_include_dirs = [discovered]
            if not args.quiet:
                print(f"clang-tooling: discovered CUDA include dir: {discovered}", file=sys.stderr)

    cuda_path = args.cuda_path or ""
    if not cuda_path and cuda_include_dirs:
        # For standard CUDA layout: include/ is under the toolkit root.
        # For conda cross-compilation layout: targets/<arch>/include/ —
        # nvvm/libdevice lives at the *grandparent* (toolkit root).
        first_inc = cuda_include_dirs[0]
        candidate = str(Path(first_inc).parent)
        if Path(candidate, "include", "cuda.h").exists():
            # If the candidate has nvvm/libdevice, it's the true toolkit root.
            # Otherwise walk up one more level (conda targets/<arch>/ case).
            if not list(Path(candidate).glob("nvvm/libdevice/libdevice*.bc")):
                parent_candidate = str(Path(candidate).parent)
                if list(Path(parent_candidate).glob("nvvm/libdevice/libdevice*.bc")):
                    candidate = parent_candidate
            cuda_path = candidate
            if not args.quiet:
                print(f"clang-tooling: derived CUDA toolkit path: {cuda_path}", file=sys.stderr)

    if not input_path.exists():
        print(
            f"clang-tooling: {input_path} not found yet. "
            "Build your project first to generate it, then re-run this target.",
            file=sys.stderr,
        )
        return 1

    source_db = load_compile_db(input_path)
    derived_db = [
        transform_entry(entry, clang_driver, cuda_include_dirs, cuda_path)
        for entry in source_db
    ]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(derived_db, handle, indent=2)
        handle.write("\n")

    rel_output = output_path
    try:
        rel_output = output_path.relative_to(repo_root)
    except ValueError:
        pass
    if not args.quiet:
        print(f"Generated clang-tooling compilation database: {rel_output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
