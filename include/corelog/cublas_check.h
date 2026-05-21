#pragma once

#include <cublas_v2.h>

#include "corelog/corelog.h"

namespace corelog {
namespace detail {

inline const char* DescribeCublasStatus(int code) noexcept {
  return cublasGetStatusString(static_cast<cublasStatus_t>(code));
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
