FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(googletest)

add_executable(test_corelog test_corelog.cpp)
target_link_libraries(test_corelog PRIVATE corelog::corelog GTest::gtest_main)

# ---------------------------------------------------------------------------
# CUDA / cuBLAS tests
# ---------------------------------------------------------------------------
find_package(CUDAToolkit)
if(CUDAToolkit_FOUND)
    add_executable(test_cuda_check test_cuda_check.cpp)
    target_link_libraries(test_cuda_check PRIVATE corelog::corelog CUDA::cudart GTest::gtest_main)

    add_executable(test_cublas_check test_cublas_check.cpp)
    target_link_libraries(test_cublas_check PRIVATE corelog::corelog CUDA::cudart CUDA::cublas GTest::gtest_main)
else()
    message(WARNING "CUDAToolkit not found — skipping CUDA/cuBLAS tests")
endif()

# ---------------------------------------------------------------------------
# NCCL tests (manual find, no standard CMake module)
# ---------------------------------------------------------------------------
find_path(NCCL_INCLUDE_DIR nccl.h)
find_library(NCCL_LIBRARY nccl)
if(NCCL_INCLUDE_DIR AND NCCL_LIBRARY)
    add_executable(test_nccl_check test_nccl_check.cpp)
    target_link_libraries(test_nccl_check PRIVATE corelog::corelog GTest::gtest_main)
    target_include_directories(test_nccl_check PRIVATE ${NCCL_INCLUDE_DIR})
    target_link_libraries(test_nccl_check PRIVATE ${NCCL_LIBRARY})
else()
    message(WARNING "NCCL not found — skipping NCCL tests")
endif()

# ---------------------------------------------------------------------------
# MPI tests
# ---------------------------------------------------------------------------
find_package(MPI)
if(MPI_FOUND)
    add_executable(test_mpi_check test_mpi_check.cpp)
    target_link_libraries(test_mpi_check PRIVATE corelog::corelog MPI::MPI_CXX GTest::gtest_main)
else()
    message(WARNING "MPI not found — skipping MPI tests")
endif()

# ---------------------------------------------------------------------------
# Discover tests
# ---------------------------------------------------------------------------
include(GoogleTest)
gtest_discover_tests(test_corelog)
if(CUDAToolkit_FOUND)
    gtest_discover_tests(test_cuda_check)
    gtest_discover_tests(test_cublas_check)
endif()
if(NCCL_INCLUDE_DIR AND NCCL_LIBRARY)
    gtest_discover_tests(test_nccl_check)
endif()
if(MPI_FOUND)
    gtest_discover_tests(test_mpi_check)
endif()
