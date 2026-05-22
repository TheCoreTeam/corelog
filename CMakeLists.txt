cmake_minimum_required(VERSION 3.20)
project(corelog LANGUAGES CXX VERSION 0.1.0)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
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
# clangd-cuda: compilation database for clangd/clang-tidy
# Must be included BEFORE add_library so targets appear in compile_commands.json.
# ---------------------------------------------------------------------------
find_package(CUDAToolkit)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
include(ClangdCudaCompileDb)

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
clangd_cuda_attach(corelog)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if(CORELOG_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()

# ---------------------------------------------------------------------------
# Install / export
# ---------------------------------------------------------------------------
include(GNUInstallDirs)

target_include_directories(corelog
    PUBLIC
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

install(TARGETS corelog
    EXPORT corelogTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(EXPORT corelogTargets
    FILE corelogTargets.cmake
    NAMESPACE corelog::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/corelog
)

include(CMakePackageConfigHelpers)
configure_package_config_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/corelogConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/corelogConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/corelog
)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/corelogConfigVersion.cmake
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/corelogConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/corelogConfigVersion.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/corelog
)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/include/corelog
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    FILES_MATCHING PATTERN "*.h"
)
