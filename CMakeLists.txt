cmake_minimum_required(VERSION 3.20)
project(corelog LANGUAGES CXX VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Options (define early, before find_package/add_library)
# ---------------------------------------------------------------------------
option(CORELOG_WITH_CUDA "Build with CUDA error-check helpers" ON)
option(CORELOG_WITH_NCCL "Build with NCCL error-check helpers" OFF)
option(CORELOG_BUILD_TESTS "Build corelog unit tests" ON)

# ---------------------------------------------------------------------------
# FetchContent base dir (outside build/ so deps survive build/ deletion)
# Only apply when corelog is the top-level project to avoid polluting parent.
# ---------------------------------------------------------------------------
if(CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
    set(FETCHCONTENT_BASE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/external CACHE PATH "" FORCE)
endif()

include(FetchContent)
FetchContent_Declare(
    spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG v1.15.0
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(spdlog)

# ---------------------------------------------------------------------------
# CUDA toolkit (before add_library, required by clangd-cuda module)
# ---------------------------------------------------------------------------
if(CORELOG_WITH_CUDA)
    find_package(CUDAToolkit REQUIRED)
endif()

# ---------------------------------------------------------------------------
# clangd-cuda: CMake module for clangd/clang-tidy with CUDA
# Must be included AFTER find_package(CUDAToolkit) and BEFORE add_library.
# ---------------------------------------------------------------------------
if(CORELOG_WITH_CUDA)
    list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/external/clangd-cuda/cmake)
    include(ClangdCudaCompileDb)
endif()

# ---------------------------------------------------------------------------
# corelog library
# ---------------------------------------------------------------------------
add_library(corelog)
add_library(corelog::corelog ALIAS corelog)

target_sources(corelog PRIVATE src/corelog.cpp)

target_include_directories(corelog
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_link_libraries(corelog PUBLIC spdlog::spdlog)

if(CORELOG_WITH_CUDA)
    target_sources(corelog PRIVATE src/cuda_check.cpp)
    target_link_libraries(corelog PUBLIC CUDA::cudart)
    target_compile_definitions(corelog PUBLIC CORELOG_WITH_CUDA=1)
    clangd_cuda_attach(corelog)
endif()

# ---------------------------------------------------------------------------
# NCCL support (optional, requires CUDA)
# ---------------------------------------------------------------------------
if(CORELOG_WITH_NCCL)
    if(NOT CORELOG_WITH_CUDA)
        message(FATAL_ERROR "CORELOG_WITH_NCCL requires CORELOG_WITH_CUDA=ON")
    endif()
    find_package(NCCL REQUIRED)
    target_link_libraries(corelog PUBLIC NCCL::NCCL)
    target_compile_definitions(corelog PUBLIC CORELOG_WITH_NCCL=1)
endif()

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if(CORELOG_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()
