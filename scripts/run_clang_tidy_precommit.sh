#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Single source of truth: which directories and extensions to lint.
#
# Override via environment variables if your project uses a different layout:
#   LINT_DIRS="src lib tests" LINT_EXTS=".c .cc .cpp .cu" ./run_clang_tidy_precommit.sh
# ---------------------------------------------------------------------------
read -r -a LINT_DIRS <<< "${LINT_DIRS:-src test example benchmark}"
read -r -a LINT_EXTS <<< "${LINT_EXTS:-.c .cc .cpp .cxx .cu}"

# Build a comma-separated string to pass into Python.
_build_py_dirs() {
  local dirs=("$@")
  local IFS=','
  echo "${dirs[*]}"
}

LINT_PY_DIRS="$(_build_py_dirs "${LINT_DIRS[@]}")"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

compile_db=""
run_all=0
declare -a extra_tidy_args=()

while (($# > 0)); do
  case "$1" in
    --compile-db)
      shift
      if (($# == 0)); then
        echo "clang-tidy: --compile-db requires a path" >&2
        exit 1
      fi
      compile_db="$1"
      shift
      ;;
    --all)
      run_all=1
      shift
      ;;
    --tidy-arg)
      shift
      if (($# == 0)); then
        echo "clang-tidy: --tidy-arg requires a value" >&2
        exit 1
      fi
      extra_tidy_args+=("$1")
      shift
      ;;
    --tidy-arg=*)
      extra_tidy_args+=("${1#--tidy-arg=}")
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "clang-tidy: unknown option: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ -z "$compile_db" ]]; then
  # Discover the compilation database from .clangd.
  clangd_file=".clangd"
  if [[ ! -f "$clangd_file" ]]; then
    echo "clang-tidy: .clangd not found. Generate it with CMake or use --compile-db." >&2
    exit 1
  fi
  db_dir="$(grep -m1 'CompilationDatabase:' "$clangd_file" | sed 's/.*CompilationDatabase:[[:space:]]*["'\'']\?//;s/["'\'']\?[[:space:]]*$//')"
  if [[ -z "$db_dir" ]]; then
    echo "clang-tidy: CompilationDatabase not found in .clangd. Use --compile-db to specify." >&2
    exit 1
  fi
  candidate="$db_dir/compile_commands.json"
  if [[ ! -f "$candidate" ]]; then
    echo "clang-tidy: compilation database not found: $candidate" >&2
    exit 1
  fi
  compile_db="$candidate"
fi

declare -a files=()
declare -A seen=()

collect_file() {
  local input="$1"
  local rel
  [[ -n "$input" ]] || return 0
  [[ -e "$input" ]] || return 0
  rel="${input#./}"

  local matched=0
  for d in "${LINT_DIRS[@]}"; do
    if [[ "$rel" == "$d"/* ]]; then
      matched=1
      break
    fi
  done
  ((matched)) || return 0

  local ext_matched=0
  for ext in "${LINT_EXTS[@]}"; do
    if [[ "$rel" == *"$ext" ]]; then
      ext_matched=1
      break
    fi
  done
  ((ext_matched)) || return 0

  if [[ -z "${seen[$rel]:-}" ]]; then
    files+=("$rel")
    seen[$rel]=1
  fi
}

if ((run_all == 0)); then
  for input in "$@"; do
    collect_file "$input"
  done
  if (( ${#files[@]} == 0 )); then
    echo "clang-tidy: no eligible first-party translation units to check"
    exit 0
  fi
fi

ensure_clang_tooling_compile_db() {
  local requested_db="$1"
  local requested_dir requested_dir_base

  requested_dir="$(dirname "$requested_db")"
  requested_dir_base="$(basename "$requested_dir")"

  if [[ "$requested_dir_base" != "clang-tooling" ]]; then
    echo "clang-tidy: expected a clang-tooling compilation database, got: $requested_db" >&2
    exit 1
  fi

  if [[ ! -f "$requested_db" ]]; then
    echo "clang-tidy: missing clang-tooling compilation database: $requested_db" >&2
    exit 1
  fi

  printf '%s\n' "$requested_db"
}

active_compile_db="$(ensure_clang_tooling_compile_db "$compile_db")"
active_compile_db_dir="$(dirname "$active_compile_db")"

if ((run_all)); then
  while IFS= read -r rel; do
    collect_file "$rel"
  done < <(
    LINT_EXTS_CSV="$(IFS=','; echo "${LINT_EXTS[*]}")" \
      python3 - "$active_compile_db" "$repo_root" "$LINT_PY_DIRS" <<'PYEOF'
import json
import os
import sys

db_path, repo_root, lint_dirs_csv = sys.argv[1:4]
repo_root = os.path.abspath(repo_root)
lint_dirs = tuple(d.strip() + "/" for d in lint_dirs_csv.split(",") if d.strip())
lint_exts = tuple(e.strip() for e in os.environ.get("LINT_EXTS_CSV", "").split(",") if e.strip())

with open(db_path, encoding="utf-8") as handle:
    db = json.load(handle)

seen = set()
for entry in db:
    src = os.path.abspath(entry["file"])
    if not src.startswith(repo_root + os.sep):
        continue
    rel = os.path.relpath(src, repo_root)
    if not rel.startswith(lint_dirs):
        continue
    if not rel.endswith(lint_exts):
        continue
    if rel not in seen:
        seen.add(rel)
        print(rel)
PYEOF
  )
fi

if (( ${#files[@]} == 0 )); then
  echo "clang-tidy: no eligible first-party translation units to check"
  exit 0
fi

common_args=(
  "--quiet"
)
common_args+=("${extra_tidy_args[@]}")

status=0
for rel in "${files[@]}"; do
  if ! clang-tidy "$rel" "${common_args[@]}" -p "$active_compile_db_dir" 2>&1; then
    status=1
  fi
done

exit "$status"
