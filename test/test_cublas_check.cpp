#include <corelog/cublas_check.h>

#include <gtest/gtest.h>

TEST(CublasCheck, SuccessCodeDoesNotThrow) {
  CORELOG_CHECK_CUBLAS(CUBLAS_STATUS_SUCCESS);
}

TEST(CublasCheck, ErrorDescriptionMapsCorrectly) {
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_SUCCESS),
               "CUBLAS_STATUS_SUCCESS");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_NOT_INITIALIZED),
               "CUBLAS_STATUS_NOT_INITIALIZED");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_ALLOC_FAILED),
               "CUBLAS_STATUS_ALLOC_FAILED");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_INVALID_VALUE),
               "CUBLAS_STATUS_INVALID_VALUE");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_ARCH_MISMATCH),
               "CUBLAS_STATUS_ARCH_MISMATCH");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_MAPPING_ERROR),
               "CUBLAS_STATUS_MAPPING_ERROR");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_EXECUTION_FAILED),
               "CUBLAS_STATUS_EXECUTION_FAILED");
  EXPECT_STREQ(::corelog::detail::DescribeCublasStatus(CUBLAS_STATUS_INTERNAL_ERROR),
               "CUBLAS_STATUS_INTERNAL_ERROR");
}
