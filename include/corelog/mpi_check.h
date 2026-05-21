#pragma once

#include "corelog/corelog.h"

#include <mpi.h>

namespace corelog {
namespace detail {

inline const char* DescribeMpiStatus(int code) noexcept {
  if (code == MPI_SUCCESS) {
    return "MPI_SUCCESS";
  }
  int initialized = 0;
  MPI_Initialized(&initialized);
  if (!initialized) {
    return "MPI error (MPI not initialized)";
  }
  static thread_local char buffer[MPI_MAX_ERROR_STRING];
  int len = 0;
  MPI_Error_string(code, buffer, &len);
  return buffer;
}

}  // namespace detail
}  // namespace corelog

#define CORELOG_CHECK_MPI(statement)                                                                 \
  do {                                                                                             \
    const auto corelog_code = (statement);                                                         \
    if (static_cast<int>(corelog_code) != 0) {                                                     \
      ::corelog::detail::AssertionFailed(                                                          \
          #statement, ::corelog::detail::DescribeMpiStatus(static_cast<int>(corelog_code)),        \
          __FILE__, __LINE__, __func__);                                                           \
    }                                                                                              \
  } while (false)
