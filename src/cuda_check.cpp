#include <corelog/corelog.h>

#include <cuda_runtime.h>
#include <cublas_v2.h>

#if defined(CORELOG_WITH_NCCL)
#include <nccl.h>
#endif

namespace corelog {

namespace detail {

const char* DescribeCudartStatus(int code) noexcept {
  return cudaGetErrorString(static_cast<cudaError_t>(code));
}

const char* DescribeCublasStatus(int code) noexcept {
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

const char* DescribeNcclStatus(int code) noexcept {
#if defined(CORELOG_WITH_NCCL)
  return ncclGetErrorString(static_cast<ncclResult_t>(code));
#else
  (void)code;
  return "NCCL_DISABLED";
#endif
}

}  // namespace detail

}  // namespace corelog
