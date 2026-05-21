#include "vector_add.cuh"

#include <cuda_runtime.h>
#include <iostream>

namespace test {

__global__ void vector_add_kernel(const float *a,
                                  const float *b,
                                  float *out,
                                  std::size_t n) {
    std::size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        out[idx] = a[idx] + b[idx];
    }
}

bool launch_vector_add(const std::vector<float> &a,
                       const std::vector<float> &b,
                       std::vector<float> &out) {
    if (a.size() != b.size() || out.size() != a.size()) {
        return false;
    }

    const std::size_t n = a.size();
    const std::size_t bytes = n * sizeof(float);

    float *d_a = nullptr;
    float *d_b = nullptr;
    float *d_out = nullptr;

    cudaError_t err = cudaMalloc(&d_a, bytes);
    if (err != cudaSuccess) {
        return false;
    }
    err = cudaMalloc(&d_b, bytes);
    if (err != cudaSuccess) {
        cudaFree(d_a);
        return false;
    }
    err = cudaMalloc(&d_out, bytes);
    if (err != cudaSuccess) {
        cudaFree(d_a);
        cudaFree(d_b);
        return false;
    }

    cudaMemcpy(d_a, a.data(), bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_b, b.data(), bytes, cudaMemcpyHostToDevice);

    constexpr int threads_per_block = 256;
    const int blocks = static_cast<int>((n + threads_per_block - 1) / threads_per_block);

    vector_add_kernel<<<blocks, threads_per_block>>>(d_a, d_b, d_out, n);

    cudaMemcpy(out.data(), d_out, bytes, cudaMemcpyDeviceToHost);

    cudaFree(d_a);
    cudaFree(d_b);
    cudaFree(d_out);

    return true;
}

} // namespace test
