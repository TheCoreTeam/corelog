#pragma once

#include <cuda_runtime.h>
#include <vector>

namespace test {

/**
 * Launch a CUDA kernel that adds two float vectors element-wise.
 *
 * @param a     Input vector A
 * @param b     Input vector B
 * @param out   Output vector (must be pre-sized to a.size())
 * @return      true on success, false on CUDA error
 */
bool launch_vector_add(const std::vector<float> &a,
                       const std::vector<float> &b,
                       std::vector<float> &out);

} // namespace test
