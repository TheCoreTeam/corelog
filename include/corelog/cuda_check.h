#pragma once

#include <cuda_runtime.h>

#include "corelog/corelog.h"

namespace corelog {
namespace detail {

inline const char* DescribeCudartStatus(int code) noexcept {
  return cudaGetErrorString(static_cast<cudaError_t>(code));
}

}  // namespace detail
}  // namespace corelog

#define CORELOG_CHECK_CUDART(statement)                                                        \
  do {                                                                                         \
    const auto corelog_code = (statement);                                                     \
    if (static_cast<int>(corelog_code) != 0) {                                                 \
      ::corelog::detail::AssertionFailed(                                                      \
          #statement, ::corelog::detail::DescribeCudartStatus(static_cast<int>(corelog_code)), \
          __FILE__, __LINE__, __func__);                                                       \
    }                                                                                          \
  } while (false)
