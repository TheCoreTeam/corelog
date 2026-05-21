#include "utils.hpp"

#include <cmath>
#include <numeric>

namespace test {

std::vector<float> generate_floats(std::size_t count, float value) {
    return std::vector<float>(count, value);
}

bool compare_vectors(const std::vector<float> &a,
                     const std::vector<float> &b,
                     float epsilon) {
    if (a.size() != b.size()) {
        return false;
    }
    for (std::size_t i = 0; i < a.size(); ++i) {
        if (std::fabs(a[i] - b[i]) > epsilon) {
            return false;
        }
    }
    return true;
}

} // namespace test
