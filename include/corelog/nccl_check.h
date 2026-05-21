#pragma once

#include <nccl.h>

#include "corelog/corelog.h"

namespace corelog {
namespace detail {

inline const char* DescribeNcclStatus(int code) noexcept {
  return ncclGetErrorString(static_cast<ncclResult_t>(code));
}

}  // namespace detail
}  // namespace corelog

#define CORELOG_CHECK_NCCL(statement)                                                        \
  do {                                                                                       \
    const auto corelog_code = (statement);                                                   \
    if (static_cast<int>(corelog_code) != 0) {                                               \
      ::corelog::detail::AssertionFailed(                                                    \
          #statement, ::corelog::detail::DescribeNcclStatus(static_cast<int>(corelog_code)), \
          __FILE__, __LINE__, __func__);                                                     \
    }                                                                                        \
  } while (false)
