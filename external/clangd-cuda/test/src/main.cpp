#include "utils.hpp"
#include "vector_add.cuh"

#include <cstdlib>
#include <iostream>
#include <vector>

int main() {
    constexpr std::size_t count = 1024;
    constexpr float value_a = 1.5f;
    constexpr float value_b = 2.5f;

    const auto a = test::generate_floats(count, value_a);
    const auto b = test::generate_floats(count, value_b);
    auto out = test::generate_floats(count, 0.0f);

    if (!test::launch_vector_add(a, b, out)) {
        std::cerr << "CUDA kernel launch failed" << std::endl;
        return EXIT_FAILURE;
    }

    const auto expected = test::generate_floats(count, value_a + value_b);
    if (!test::compare_vectors(out, expected)) {
        std::cerr << "Result mismatch" << std::endl;
        return EXIT_FAILURE;
    }

    std::cout << "All tests passed!" << std::endl;
    return EXIT_SUCCESS;
}
