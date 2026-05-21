#pragma once

#include "corelog/corelog.h"

#if !defined(CORELOG_WITH_CUDA)

namespace corelog {
namespace detail {

inline const char* DescribeCudartStatus(int) noexcept { return "CUDA_NOT_ENABLED"; }
inline const char* DescribeCublasStatus(int) noexcept { return "CUBLAS_NOT_ENABLED"; }
inline const char* DescribeNcclStatus(int) noexcept { return "NCCL_NOT_ENABLED"; }

}  // namespace detail
}  // namespace corelog

#else

namespace corelog {
namespace detail {

CORELOG_API const char* DescribeCudartStatus(int code) noexcept;
CORELOG_API const char* DescribeCublasStatus(int code) noexcept;
CORELOG_API const char* DescribeNcclStatus(int code) noexcept;

}  // namespace detail
}  // namespace corelog

#endif

#define CORELOG_CHECK_CUDART(statement)                                                              \
  do {                                                                                               \
    const auto corelog_code = (statement);                                                           \
    if (static_cast<int>(corelog_code) != 0) {                                                       \
      ::corelog::detail::AssertionFailed(                                                            \
          #statement, ::corelog::detail::DescribeCudartStatus(static_cast<int>(corelog_code)),       \
          __FILE__, __LINE__, __func__);                                                             \
    }                                                                                                \
  } while (false)

#define CORELOG_CHECK_CUBLAS(statement)                                                              \
  do {                                                                                               \
    const auto corelog_code = (statement);                                                           \
    if (static_cast<int>(corelog_code) != 0) {                                                       \
      ::corelog::detail::AssertionFailed(                                                            \
          #statement, ::corelog::detail::DescribeCublasStatus(static_cast<int>(corelog_code)),       \
          __FILE__, __LINE__, __func__);                                                             \
    }                                                                                                \
  } while (false)

#define CORELOG_CHECK_NCCL(statement)                                                                \
  do {                                                                                               \
    const auto corelog_code = (statement);                                                           \
    if (static_cast<int>(corelog_code) != 0) {                                                       \
      ::corelog::detail::AssertionFailed(                                                            \
          #statement, ::corelog::detail::DescribeNcclStatus(static_cast<int>(corelog_code)),         \
          __FILE__, __LINE__, __func__);                                                             \
    }                                                                                                \
  } while (false)
