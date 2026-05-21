FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.15.2
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(googletest)

add_executable(test_corelog test_corelog.cpp)
target_link_libraries(test_corelog PRIVATE corelog::corelog GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(test_corelog)
