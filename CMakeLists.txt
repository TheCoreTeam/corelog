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

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if(CORELOG_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()
