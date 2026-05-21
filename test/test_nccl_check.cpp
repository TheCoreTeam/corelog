#include <corelog/nccl_check.h>
#include <gtest/gtest.h>

TEST(NcclCheck, SuccessCodeDoesNotThrow) { CORELOG_CHECK_NCCL(ncclSuccess); }

TEST(NcclCheck, ErrorDescriptionIsNotEmpty) {
  auto desc = ::corelog::detail::DescribeNcclStatus(ncclInvalidArgument);
  EXPECT_NE(desc, nullptr);
  EXPECT_NE(strlen(desc), 0U);
}

TEST(NcclCheck, SuccessDescriptionIsNotEmpty) {
  auto desc = ::corelog::detail::DescribeNcclStatus(ncclSuccess);
  EXPECT_NE(desc, nullptr);
  EXPECT_NE(strlen(desc), 0U);
}
