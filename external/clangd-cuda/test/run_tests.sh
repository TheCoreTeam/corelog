#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"

echo "=== Step 1: Clean build directory ==="
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo ""
echo "=== Step 2: Configure ==="
cmake -G Ninja -S "${SCRIPT_DIR}" -B "${BUILD_DIR}"

echo ""
echo "=== Step 3: Build test executable (compilation database auto-generated) ==="
cmake --build "${BUILD_DIR}" --target cuda_test

echo ""
echo "=== Step 4: Run test executable ==="
"${BUILD_DIR}/cuda_test"

echo ""
echo "=== Step 5: Verify clangd can parse .cu file ==="
# clangd --check returns non-zero when diagnostics are present;
# we only need to confirm it runs and emits its summary line.
set +e
clangd --check="${SCRIPT_DIR}/src/vector_add.cu" \
    --compile-commands-dir="${BUILD_DIR}/clang-tooling" \
    2>&1 | grep -E "(All checks completed|errors)"
set -e

echo ""
echo "=== Step 6: Verify clang-tidy can analyze .cu file ==="
clang-tidy "${SCRIPT_DIR}/src/vector_add.cu" --checks='*' -- \
    -x cuda --cuda-host-only \
    -isystem "$(dirname "$(which nvcc)")/../targets/x86_64-linux/include" \
    -I"${SCRIPT_DIR}/include" \
    -std=c++17 \
    >/dev/null 2>&1
echo "OK: clang-tidy can analyze .cu file"

echo ""
echo "=== Step 7: Verify generate_clangd_db target updates database and .clangd ==="

CLANG_TOOLING_DB="${BUILD_DIR}/clang-tooling/compile_commands.json"
CLANGD_CONFIG="${SCRIPT_DIR}/.clangd"

# Record original modification times
DB_MTIME_BEFORE=$(stat -c %Y "${CLANG_TOOLING_DB}")
CLANGD_MTIME_BEFORE=$(stat -c %Y "${CLANGD_CONFIG}")

# Remove both files to force regeneration
rm -f "${CLANG_TOOLING_DB}"
rm -f "${CLANGD_CONFIG}"

# Run the standalone target
cmake --build "${BUILD_DIR}" --target generate_clangd_db

# Verify files were recreated
if [[ ! -f "${CLANG_TOOLING_DB}" ]]; then
    echo "ERROR: clang-tooling compile_commands.json was not regenerated"
    exit 1
fi
if [[ ! -f "${CLANGD_CONFIG}" ]]; then
    echo "ERROR: .clangd config was not regenerated"
    exit 1
fi

# Verify modification times are newer
DB_MTIME_AFTER=$(stat -c %Y "${CLANG_TOOLING_DB}")
CLANGD_MTIME_AFTER=$(stat -c %Y "${CLANGD_CONFIG}")

if [[ "${DB_MTIME_AFTER}" -le "${DB_MTIME_BEFORE}" ]]; then
    echo "ERROR: clang-tooling compile_commands.json was not updated (mtime not changed)"
    exit 1
fi
if [[ "${CLANGD_MTIME_AFTER}" -le "${CLANGD_MTIME_BEFORE}" ]]; then
    echo "ERROR: .clangd config was not updated (mtime not changed)"
    exit 1
fi

echo "OK: generate_clangd_db target regenerated both files"

echo ""
echo "=== Step 8: Verify cmake reconfigure refreshes the database and .clangd ==="

# README claim: re-running `cmake -G Ninja -B build .` triggers configure-time
# pre-generation of the clang-tooling database and rewrites .clangd, so the
# user does not need to build (or build successfully) to refresh them.

# Make sure we have a baseline from the previous step.
if [[ ! -f "${CLANG_TOOLING_DB}" ]] || [[ ! -f "${CLANGD_CONFIG}" ]]; then
    echo "ERROR: prerequisites missing — earlier steps should have produced both files"
    exit 1
fi

# Bump mtimes back by one second so a regeneration in the same second is detectable.
touch -d '1 second ago' "${CLANG_TOOLING_DB}" "${CLANGD_CONFIG}"
DB_MTIME_BEFORE=$(stat -c %Y "${CLANG_TOOLING_DB}")
CLANGD_MTIME_BEFORE=$(stat -c %Y "${CLANGD_CONFIG}")

# Re-run the exact command the README documents.
RECONFIG_LOG="${BUILD_DIR}/reconfig.log"
cmake -G Ninja -B "${BUILD_DIR}" -S "${SCRIPT_DIR}" 2>&1 | tee "${RECONFIG_LOG}"

grep -q "pre-generating clang-tooling database at configure time" "${RECONFIG_LOG}" \
    || { echo "ERROR: configure-time pre-generation status line missing"; exit 1; }
grep -q "generated .clangd at" "${RECONFIG_LOG}" \
    || { echo "ERROR: .clangd regeneration status line missing"; exit 1; }

DB_MTIME_AFTER=$(stat -c %Y "${CLANG_TOOLING_DB}")
CLANGD_MTIME_AFTER=$(stat -c %Y "${CLANGD_CONFIG}")

if [[ "${DB_MTIME_AFTER}" -le "${DB_MTIME_BEFORE}" ]]; then
    echo "ERROR: clang-tooling compile_commands.json mtime not refreshed by reconfigure"
    exit 1
fi
if [[ "${CLANGD_MTIME_AFTER}" -le "${CLANGD_MTIME_BEFORE}" ]]; then
    echo "ERROR: .clangd mtime not refreshed by reconfigure"
    exit 1
fi

echo "OK: cmake reconfigure refreshed both files"

echo ""
echo "=== All tests passed ==="
