#pragma once

#include <cublas_v2.h>

#include "corelog/corelog.h"

namespace corelog {
namespace detail {

inline const char* DescribeCublasStatus(int code) noexcept {
  switch (static_cast<cublasStatus_t>(code)) {
    case CUBLAS_STATUS_SUCCESS:
      return "CUBLAS_STATUS_SUCCESS";
    case CUBLAS_STATUS_NOT_INITIALIZED:
      return "CUBLAS_STATUS_NOT_INITIALIZED";
    case CUBLAS_STATUS_ALLOC_FAILED:
      return "CUBLAS_STATUS_ALLOC_FAILED";
    case CUBLAS_STATUS_INVALID_VALUE:
      return "CUBLAS_STATUS_INVALID_VALUE";
    case CUBLAS_STATUS_ARCH_MISMATCH:
      return "CUBLAS_STATUS_ARCH_MISMATCH";
    case CUBLAS_STATUS_MAPPING_ERROR:
      return "CUBLAS_STATUS_MAPPING_ERROR";
    case CUBLAS_STATUS_EXECUTION_FAILED:
      return "CUBLAS_STATUS_EXECUTION_FAILED";
    case CUBLAS_STATUS_INTERNAL_ERROR:
      return "CUBLAS_STATUS_INTERNAL_ERROR";
#if defined(CUBLAS_STATUS_NOT_SUPPORTED)
    case CUBLAS_STATUS_NOT_SUPPORTED:
      return "CUBLAS_STATUS_NOT_SUPPORTED";
#endif
#if defined(CUBLAS_STATUS_LICENSE_ERROR)
    case CUBLAS_STATUS_LICENSE_ERROR:
      return "CUBLAS_STATUS_LICENSE_ERROR";
#endif
    default:
      return "CUBLAS_STATUS_UNKNOWN";
  }
}

}  // namespace detail
}  // namespace corelog

#define CORELOG_CHECK_CUBLAS(statement)                                                        \
  do {                                                                                         \
    const auto corelog_code = (statement);                                                     \
    if (static_cast<int>(corelog_code) != 0) {                                                 \
      ::corelog::detail::AssertionFailed(                                                      \
          #statement, ::corelog::detail::DescribeCublasStatus(static_cast<int>(corelog_code)), \
          __FILE__, __LINE__, __func__);                                                       \
    }                                                                                          \
  } while (false)
