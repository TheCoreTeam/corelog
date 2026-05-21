cmake_minimum_required(VERSION 3.20)

project(CudaTest
    VERSION 0.1.0
    LANGUAGES CXX CUDA
    DESCRIPTION "Test project for cmake-clangd-cuda"
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

find_package(CUDAToolkit REQUIRED)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/ClangdCudaCompileDb.cmake")

add_executable(cuda_test
    src/main.cpp
    src/utils.cpp
    src/vector_add.cu
)

target_include_directories(cuda_test PRIVATE
    include
)

target_link_libraries(cuda_test PRIVATE
    CUDA::cudart
)

clangd_cuda_attach(cuda_test)

# ---------------------------------------------------------------------------
# Print diagnostic info for CI/verification
# ---------------------------------------------------------------------------
message(STATUS "")
message(STATUS "=== Test project configured ===")
message(STATUS "  compile_commands.json: ${PROJECT_BINARY_DIR}/compile_commands.json")
message(STATUS "  .clangd config: ${PROJECT_SOURCE_DIR}/.clangd")
message(STATUS "")
