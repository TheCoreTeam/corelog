#include <corelog/mpi_check.h>
#include <gtest/gtest.h>

TEST(MpiCheck, SuccessCodeDoesNotThrow) { CORELOG_CHECK_MPI(MPI_SUCCESS); }

TEST(MpiCheck, SuccessDescriptionIsCorrect) {
  auto desc = ::corelog::detail::DescribeMpiStatus(MPI_SUCCESS);
  EXPECT_STREQ(desc, "MPI_SUCCESS");
}

TEST(MpiCheck, InvalidErrorCodeDescriptionIsNotEmpty) {
  // MPI_ERR_BUFFER = 1 is a valid MPI error code
  auto desc = ::corelog::detail::DescribeMpiStatus(MPI_ERR_BUFFER);
  EXPECT_NE(desc, nullptr);
  EXPECT_NE(strlen(desc), 0U);
}
