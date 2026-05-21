#include <corelog/cublas_check.h>
#include <gtest/gtest.h>

TEST(CublasCheck, SuccessCodeDoesNotThrow) { CORELOG_CHECK_CUBLAS(CUBLAS_STATUS_SUCCESS); }

TEST(CublasCheck, ErrorDescriptionMapsCorrectly) {
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_SUCCESS), "success");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_NOT_INITIALIZED),
               "the library was not initialized");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_ALLOC_FAILED),
               "the resource allocation failed");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_INVALID_VALUE),
               "an unsupported value or parameter was passed to the function");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_ARCH_MISMATCH),
               "the function requires an architectural feature absent from the device");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_MAPPING_ERROR),
               "an access to GPU memory space failed");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_EXECUTION_FAILED),
               "the function failed to launch on the GPU");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_INTERNAL_ERROR),
               "an internal operation failed");
}
