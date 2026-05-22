# =============================================================================
# ClangdCudaCompileDb
# =============================================================================
# Generate a clang-tooling-friendly compilation database from a CMake-generated
# compile_commands.json. This is essential for mixed C++/CUDA projects where
# nvcc and clang++ have incompatible command-line interfaces.
#
# For .cu files, nvcc compile commands are rewritten into clang++ commands that
# clangd and clang-tidy can consume directly.
#
# Usage:
#   project(MyProj LANGUAGES CXX CUDA)
#   find_package(CUDAToolkit REQUIRED)        # optional, enables auto-detect
#   include(ClangdCudaCompileDb)              # must come AFTER project()
#
#   add_executable(my_app ...)
#   clangd_cuda_attach(my_app)                # attach POST_BUILD hook
# =============================================================================

include_guard(GLOBAL)

# ---------------------------------------------------------------------------
# Must be included after project(): we rely on PROJECT_SOURCE_DIR and want
# CMAKE_EXPORT_COMPILE_COMMANDS to apply to subsequent targets.
# ---------------------------------------------------------------------------

if(NOT DEFINED PROJECT_SOURCE_DIR)
    message(FATAL_ERROR
        "ClangdCudaCompileDb must be included after project()")
endif()

# ---------------------------------------------------------------------------
# Warn if targets already exist at the project root: their
# EXPORT_COMPILE_COMMANDS target property was captured at creation time
# from the (then unset) CMAKE_EXPORT_COMPILE_COMMANDS, and forcing the
# variable now won't retroactively enable export for them.
# ---------------------------------------------------------------------------

get_property(_clangd_cuda_existing_targets
    DIRECTORY "${PROJECT_SOURCE_DIR}"
    PROPERTY BUILDSYSTEM_TARGETS)
if(_clangd_cuda_existing_targets)
    message(WARNING
        "ClangdCudaCompileDb: targets ${_clangd_cuda_existing_targets} were "
        "created before this module was included; they will not appear in "
        "compile_commands.json. Include this module right after project() "
        "and before any add_executable/add_library.")
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON CACHE BOOL
    "Export compile_commands.json (forced by ClangdCudaCompileDb)" FORCE)

# ---------------------------------------------------------------------------
# Optional configuration variables (set before include(), or override after
# include but before clangd_cuda_attach())
# ---------------------------------------------------------------------------

if(NOT DEFINED CLANGD_CUDA_SOURCE_DB)
    set(CLANGD_CUDA_SOURCE_DB "${PROJECT_BINARY_DIR}/compile_commands.json")
endif()

if(NOT DEFINED CLANGD_CUDA_OUTPUT_DIR)
    set(CLANGD_CUDA_OUTPUT_DIR "${PROJECT_BINARY_DIR}/clang-tooling")
endif()

if(NOT DEFINED CLANGD_CUDA_REPO_ROOT)
    set(CLANGD_CUDA_REPO_ROOT "${PROJECT_SOURCE_DIR}")
endif()

if(NOT DEFINED CLANGD_CUDA_CLANG_CXX)
    set(CLANGD_CUDA_CLANG_CXX "")
endif()

if(NOT DEFINED CLANGD_CUDA_ENABLE_CLANGD_CONFIG)
    set(CLANGD_CUDA_ENABLE_CLANGD_CONFIG ON)
endif()

if(NOT DEFINED CLANGD_CUDA_CLANGD_CONFIG_PATH)
    set(CLANGD_CUDA_CLANGD_CONFIG_PATH "${PROJECT_SOURCE_DIR}/.clangd")
endif()

if(NOT DEFINED CLANGD_CUDA_PATH)
    set(CLANGD_CUDA_PATH "")
endif()

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------

set(_clangd_cuda_output_db "${CLANGD_CUDA_OUTPUT_DIR}/compile_commands.json")

get_filename_component(_clangd_cuda_module_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
get_filename_component(_clangd_cuda_repo_root "${_clangd_cuda_module_dir}/.." ABSOLUTE)
set(_clangd_cuda_script "${_clangd_cuda_repo_root}/scripts/nvcc_to_clang_compile_db.py")

find_package(Python3 REQUIRED COMPONENTS Interpreter)

# ---------------------------------------------------------------------------
# Auto-detect CUDA include directories if not explicitly provided
# ---------------------------------------------------------------------------

if(NOT DEFINED CLANGD_CUDA_EXTRA_INCLUDE_DIRS)
    if(TARGET CUDA::cudart)
        get_target_property(_cuda_inc_dirs CUDA::cudart INTERFACE_INCLUDE_DIRECTORIES)
        if(_cuda_inc_dirs)
            set(CLANGD_CUDA_EXTRA_INCLUDE_DIRS "${_cuda_inc_dirs}")
            message(STATUS "ClangdCudaCompileDb: auto-detected CUDA includes from CUDA::cudart")
        endif()
    endif()
    # CUDAToolkit_INCLUDE_DIRS contains the real toolkit include path
    # (e.g. .../targets/x86_64-linux/include) which may differ from
    # CUDA::cudart INTERFACE_INCLUDE_DIRECTORIES (e.g. .../include).
    # Both must be promoted to -isystem to prevent clang-tidy from linting them.
    if(DEFINED CUDAToolkit_INCLUDE_DIRS AND CUDAToolkit_INCLUDE_DIRS)
        foreach(_cudatk_inc_dir IN LISTS CUDAToolkit_INCLUDE_DIRS)
            if(_cudatk_inc_dir AND NOT _cudatk_inc_dir IN_LIST CLANGD_CUDA_EXTRA_INCLUDE_DIRS)
                list(APPEND CLANGD_CUDA_EXTRA_INCLUDE_DIRS "${_cudatk_inc_dir}")
                message(STATUS "ClangdCudaCompileDb: added CUDAToolkit include dir: ${_cudatk_inc_dir}")
            endif()
        endforeach()
    endif()
endif()

# ---------------------------------------------------------------------------
# Auto-detect conda environment include directories.
# When building inside a conda environment, MPI/NCCL headers live under
# $CONDA_PREFIX/include but are not explicitly listed in compile_commands.json
# (the conda toolchain finds them via environment variables).  clangd/clang-tidy
# do not inherit those variables, so we inject the path explicitly.
# ---------------------------------------------------------------------------

if(DEFINED ENV{CONDA_PREFIX})
    if(NOT DEFINED CLANGD_CUDA_EXTRA_INCLUDE_DIRS)
        set(CLANGD_CUDA_EXTRA_INCLUDE_DIRS "")
    endif()
    list(APPEND CLANGD_CUDA_EXTRA_INCLUDE_DIRS "$ENV{CONDA_PREFIX}/include")
    message(STATUS "ClangdCudaCompileDb: auto-detected conda include: $ENV{CONDA_PREFIX}/include")
endif()

# ---------------------------------------------------------------------------
# Auto-detect CUDA toolkit root (for --cuda-path). Without this, clang emits
# 'drv_no_cuda_installation' and fails to declare CUDA builtins like
# threadIdx/blockIdx, plus cudaConfigureCall for <<<>>>.
# ---------------------------------------------------------------------------

if(NOT CLANGD_CUDA_PATH)
    if(DEFINED CUDAToolkit_TARGET_DIR AND EXISTS "${CUDAToolkit_TARGET_DIR}/include/cuda.h")
        set(CLANGD_CUDA_PATH "${CUDAToolkit_TARGET_DIR}")
        message(STATUS "ClangdCudaCompileDb: auto-detected --cuda-path from CUDAToolkit_TARGET_DIR")
    elseif(CLANGD_CUDA_EXTRA_INCLUDE_DIRS)
        list(GET CLANGD_CUDA_EXTRA_INCLUDE_DIRS 0 _first_inc)
        if(EXISTS "${_first_inc}/cuda.h")
            get_filename_component(CLANGD_CUDA_PATH "${_first_inc}" DIRECTORY)
            message(STATUS "ClangdCudaCompileDb: derived --cuda-path from CUDA include dir")
        endif()
    endif()
endif()

# ---------------------------------------------------------------------------
# Build the --cuda-include-dir argument list
# ---------------------------------------------------------------------------

set(_clangd_cuda_include_args "")
foreach(_inc_dir IN LISTS CLANGD_CUDA_EXTRA_INCLUDE_DIRS)
    if(_inc_dir)
        list(APPEND _clangd_cuda_include_args "--cuda-include-dir")
        list(APPEND _clangd_cuda_include_args "${_inc_dir}")
    endif()
endforeach()

set(_clangd_cuda_clang_cxx_args "")
if(CLANGD_CUDA_CLANG_CXX)
    list(APPEND _clangd_cuda_clang_cxx_args "--clang-cxx")
    list(APPEND _clangd_cuda_clang_cxx_args "${CLANGD_CUDA_CLANG_CXX}")
endif()

set(_clangd_cuda_path_args "")
if(CLANGD_CUDA_PATH)
    list(APPEND _clangd_cuda_path_args "--cuda-path")
    list(APPEND _clangd_cuda_path_args "${CLANGD_CUDA_PATH}")
endif()

# ---------------------------------------------------------------------------
# Unified argument list for the conversion script (used by POST_BUILD,
# custom target, and configure-time pre-generation)
# ---------------------------------------------------------------------------

set(_clangd_cuda_script_args
    --input "${CLANGD_CUDA_SOURCE_DB}"
    --output "${_clangd_cuda_output_db}"
    --repo-root "${CLANGD_CUDA_REPO_ROOT}"
    ${_clangd_cuda_clang_cxx_args}
    ${_clangd_cuda_path_args}
    ${_clangd_cuda_include_args}
)

message(STATUS "ClangdCudaCompileDb: source compile database = ${CLANGD_CUDA_SOURCE_DB}")
message(STATUS "ClangdCudaCompileDb: derived compile database = ${_clangd_cuda_output_db}")

# ---------------------------------------------------------------------------
# Optional: generate .clangd configuration file
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Auto-detect the exact libstdc++ include directories used by the project's
# GCC-based build so that clangd (which uses clang++) can resolve the same
# standard-library headers.  We query GCC directly via -print-file-name and
# emit -isystem flags rather than --gcc-toolchain, because the latter does
# not recognise the deeply-nested layout used by conda cross-compilation
# toolchains (lib/gcc/<target>/<version>/include/c++).
# ---------------------------------------------------------------------------

set(_clangd_cuda_stdlib_flags "")

# ---------------------------------------------------------------------------
# Prepend clang's cuda_wrappers/ directory.  In -x cuda mode clang predefines
# __CUDACC__, which makes CUDA's crt/host_defines.h define __noinline__ as a
# macro expanding to __attribute__((noinline)).  libstdc++ writes
# __attribute__((__noinline__, __noclone__, __cold__)) on functions, and the
# macro expansion turns that into invalid syntax.  Clang ships wrappers under
# <resource-dir>/include/cuda_wrappers/ that #undef __noinline__ around the
# affected libstdc++ headers (and provide device-side operator new overloads
# in cuda_wrappers/new).  Those wrappers must be searched BEFORE any explicit
# libstdc++ -isystem path emitted below, otherwise libstdc++'s own
# bits/basic_string.h is found first and the wrappers are bypassed.
# ---------------------------------------------------------------------------

set(_clangd_cuda_clang_for_resource "${CLANGD_CUDA_CLANG_CXX}")
if(NOT _clangd_cuda_clang_for_resource)
    find_program(_clangd_cuda_clang_for_resource_probe
        NAMES clang++-20 clang++ clang-20 clang
        DOC "Clang driver queried for cuda_wrappers resource directory")
    if(_clangd_cuda_clang_for_resource_probe)
        set(_clangd_cuda_clang_for_resource
            "${_clangd_cuda_clang_for_resource_probe}")
    endif()
endif()
if(_clangd_cuda_clang_for_resource)
    execute_process(
        COMMAND "${_clangd_cuda_clang_for_resource}" -print-resource-dir
        OUTPUT_VARIABLE _clangd_cuda_resource_dir
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _clangd_cuda_resource_result
    )
    if(_clangd_cuda_resource_result EQUAL 0
       AND EXISTS "${_clangd_cuda_resource_dir}/include/cuda_wrappers")
        list(APPEND _clangd_cuda_stdlib_flags "    - -isystem")
        list(APPEND _clangd_cuda_stdlib_flags
            "    - ${_clangd_cuda_resource_dir}/include/cuda_wrappers")
        message(STATUS
            "ClangdCudaCompileDb: prepended clang cuda_wrappers: "
            "${_clangd_cuda_resource_dir}/include/cuda_wrappers")
    endif()
endif()

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    execute_process(
        COMMAND "${CMAKE_CXX_COMPILER}" -print-file-name=include/c++/vector
        OUTPUT_VARIABLE _gcc_vector_path
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _gcc_result
    )
    if(_gcc_result EQUAL 0 AND _gcc_vector_path MATCHES "^/")
        # GCC returned an absolute path → libstdc++ is present.
        get_filename_component(_gcc_vector_real "${_gcc_vector_path}" REALPATH)
        get_filename_component(_gcc_cxx_include "${_gcc_vector_real}" DIRECTORY)

        list(APPEND _clangd_cuda_stdlib_flags "    - -isystem")
        list(APPEND _clangd_cuda_stdlib_flags "    - ${_gcc_cxx_include}")
        message(STATUS "ClangdCudaCompileDb: detected GCC libstdc++ include: ${_gcc_cxx_include}")

        # Look for the target-specific subdirectory (e.g. x86_64-conda-linux-gnu)
        # It lives directly under include/c++.
        file(GLOB _gcc_target_children RELATIVE "${_gcc_cxx_include}" "${_gcc_cxx_include}/*")
        foreach(_child IN LISTS _gcc_target_children)
            if(IS_DIRECTORY "${_gcc_cxx_include}/${_child}" AND NOT _child STREQUAL "backward")
                if(EXISTS "${_gcc_cxx_include}/${_child}/bits/c++config.h")
                    list(APPEND _clangd_cuda_stdlib_flags "    - -isystem")
                    list(APPEND _clangd_cuda_stdlib_flags "    - ${_gcc_cxx_include}/${_child}")
                    message(STATUS "ClangdCudaCompileDb: detected GCC target include: ${_gcc_cxx_include}/${_child}")
                    break()
                endif()
            endif()
        endforeach()
    endif()
endif()

# ---------------------------------------------------------------------------
# Build the .clangd file content and helper script for updating it at
# configure time *and* at build time (via generate_clangd_db / POST_BUILD).
# ---------------------------------------------------------------------------

set(_clangd_cuda_config_content "# This file is generated by CMake. Do not edit manually.
CompileFlags:
  CompilationDatabase: '${CLANGD_CUDA_OUTPUT_DIR}'
")
if(_clangd_cuda_stdlib_flags)
    string(APPEND _clangd_cuda_config_content "  Add:
")
    foreach(_flag IN LISTS _clangd_cuda_stdlib_flags)
        string(APPEND _clangd_cuda_config_content "${_flag}
")
    endforeach()
endif()

# Suppress false positives caused by clang's cuda_wrappers headers.
# cuda_wrappers/new provides __device__ operator new overloads that clash
# with host declarations in libstdc++ <new> in clangd's unified AST.
# cuda_wrappers/bits/c++config.h declares a device __glibcxx_assert_fail
# with a differing exception spec from the host version.  Both are valid
# CUDA code (the __device__ attribute distinguishes the symbols) but
# clangd reports them as errors.  See commit ce2ee61 for context.
#
# deduction_guide_target_attr: libstdc++ deduction guides live inside
# `std _GLIBCXX_VISIBILITY(default)`; clangd in CUDA mode rejects the
# implicit visibility attribute on deduction guides.
string(APPEND _clangd_cuda_config_content "Diagnostics:
  Suppress:
    - redefinition
    - mismatched_exception_spec
    - deduction_guide_target_attr
")

set(_clangd_cuda_update_script "${PROJECT_BINARY_DIR}/_clangd_cuda_update.cmake")
file(WRITE "${_clangd_cuda_update_script}"
    "file(WRITE \"${CLANGD_CUDA_CLANGD_CONFIG_PATH}\" \"${_clangd_cuda_config_content}\")")

if(CLANGD_CUDA_ENABLE_CLANGD_CONFIG)
    file(WRITE "${CLANGD_CUDA_CLANGD_CONFIG_PATH}" "${_clangd_cuda_config_content}")
    message(STATUS "ClangdCudaCompileDb: generated .clangd at ${CLANGD_CUDA_CLANGD_CONFIG_PATH}")
endif()

# ---------------------------------------------------------------------------
# Public API: attach a POST_BUILD hook to the given targets so the
# clang-tooling compilation database is regenerated after each build.
# ---------------------------------------------------------------------------

function(clangd_cuda_attach)
    foreach(_target IN LISTS ARGN)
        if(NOT TARGET ${_target})
            message(WARNING "clangd_cuda_attach: '${_target}' is not a target")
            continue()
        endif()
        add_custom_command(TARGET ${_target} POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${CLANGD_CUDA_OUTPUT_DIR}"
            COMMAND "${Python3_EXECUTABLE}" "${_clangd_cuda_script}" ${_clangd_cuda_script_args}
            COMMAND "${CMAKE_COMMAND}" -P "${_clangd_cuda_update_script}"
            COMMENT "Generating clang-tooling compilation database"
            VERBATIM
        )
    endforeach()
endfunction()

# ---------------------------------------------------------------------------
# Stand-alone target: generate the clang-tooling database on demand without
# requiring a successful build. This is useful when compilation is broken but
# clangd indexing is still needed for code navigation and completion.
# ---------------------------------------------------------------------------

if(NOT TARGET generate_clangd_db)
  add_custom_target(generate_clangd_db
      COMMAND "${CMAKE_COMMAND}" -E make_directory "${CLANGD_CUDA_OUTPUT_DIR}"
      COMMAND "${Python3_EXECUTABLE}" "${_clangd_cuda_script}" ${_clangd_cuda_script_args}
      COMMAND "${CMAKE_COMMAND}" -P "${_clangd_cuda_update_script}"
      COMMENT "Generating clang-tooling compilation database and .clangd config (on-demand)"
      VERBATIM
  )
endif()

# ---------------------------------------------------------------------------
# Pre-generate at configure time if the source database already exists.
# This means a simple 'cmake -B build .' is enough to produce a usable
# clangd database; the user does not have to wait for (or succeed at)
# building before clangd can index the project.
# ---------------------------------------------------------------------------

if(EXISTS "${CLANGD_CUDA_SOURCE_DB}")
    message(STATUS "ClangdCudaCompileDb: pre-generating clang-tooling database at configure time")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${CLANGD_CUDA_OUTPUT_DIR}"
        COMMAND "${Python3_EXECUTABLE}" "${_clangd_cuda_script}" ${_clangd_cuda_script_args}
        RESULT_VARIABLE _clangd_cuda_pre_gen_result
        OUTPUT_VARIABLE _clangd_cuda_pre_gen_output
        ERROR_VARIABLE _clangd_cuda_pre_gen_error
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )
    if(NOT _clangd_cuda_pre_gen_result EQUAL 0)
        message(WARNING "ClangdCudaCompileDb: pre-generation failed (will retry at build time):\n${_clangd_cuda_pre_gen_error}")
    else()
        message(STATUS "ClangdCudaCompileDb: pre-generated clang-tooling database")
    endif()
else()
    message(STATUS "ClangdCudaCompileDb: source database not found yet; run cmake --build to generate it")
endif()
