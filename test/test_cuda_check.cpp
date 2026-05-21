#include <corelog/cuda_check.h>
#include <gtest/gtest.h>

TEST(CudaCheck, SuccessCodeDoesNotThrow) {
  // cudaSuccess = 0, should not trigger assertion
  CORELOG_CHECK_CUDART(cudaSuccess);
}

TEST(CudaCheck, ErrorDescriptionIsValid) {
  auto desc = ::corelog::detail::DescribeCudartStatus(cudaErrorInvalidValue);
  EXPECT_NE(desc, nullptr);
  EXPECT_STREQ(desc, "invalid argument");
}

TEST(CudaCheck, SuccessDescriptionIsValid) {
  auto desc = ::corelog::detail::DescribeCudartStatus(cudaSuccess);
  EXPECT_NE(desc, nullptr);
  EXPECT_STREQ(desc, "no error");
}
