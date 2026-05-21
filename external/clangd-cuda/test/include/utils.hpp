#pragma once

#include <string>
#include <vector>

namespace test {

/**
 * Generate a vector of floating-point values.
 */
std::vector<float> generate_floats(std::size_t count, float value);

/**
 * Compare two float vectors with an epsilon tolerance.
 */
bool compare_vectors(const std::vector<float> &a,
                     const std::vector<float> &b,
                     float epsilon = 1e-5f);

} // namespace test
