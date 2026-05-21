#include <corelog/corelog.h>
#include <gtest/gtest.h>
#include <string>
#include <string_view>
#include <vector>

namespace {

struct CapturedRecord {
  corelog::LogLevel level;
  std::string category;
  std::string message;
  std::string file;
  int line;
  std::string function;
};

struct CaptureState {
  std::vector<CapturedRecord> records;
  int callback_count = 0;
};

void CaptureCallback(const corelog::LogRecord* record, void* user_data) noexcept {
  auto* state = static_cast<CaptureState*>(user_data);
  state->callback_count += 1;
  state->records.push_back(CapturedRecord{record->level, record->category, record->message,
                                          record->file, record->line, record->function});
}

class LogSinkScope {
 public:
  LogSinkScope() = default;
  ~LogSinkScope() { corelog::ResetLogSink(); }

  LogSinkScope(LogSinkScope&&) = default;
  LogSinkScope& operator=(LogSinkScope&&) = default;

  LogSinkScope(const LogSinkScope&) = delete;
  LogSinkScope& operator=(const LogSinkScope&) = delete;
};

TEST(TestCoreLog, CallbackReceivesLogRecordFromInfoHelper) {
  LogSinkScope guard;
  CaptureState state;
  corelog::SetLogSink(
      {.callback = &CaptureCallback, .user_data = &state, .min_level = corelog::LogLevel::kTrace});

  CORELOG_INFO(std::string("phase3 info message"));

  ASSERT_EQ(state.callback_count, 1);
  ASSERT_EQ(state.records.size(), 1U);
  EXPECT_EQ(state.records[0].level, corelog::LogLevel::kInfo);
  EXPECT_EQ(state.records[0].category, "info");
  EXPECT_EQ(state.records[0].message, "phase3 info message");
  EXPECT_TRUE(state.records[0].file.find("test_corelog.cpp") != std::string::npos);
  EXPECT_GT(state.records[0].line, 0);
  EXPECT_FALSE(state.records[0].function.empty());
}

TEST(TestCoreLog, StringViewAndTemporaryStringMessagesAreSafe) {
  LogSinkScope guard;
  CaptureState state;
  corelog::SetLogSink(
      {.callback = &CaptureCallback, .user_data = &state, .min_level = corelog::LogLevel::kTrace});

  CORELOG_INFO(std::string_view{"info via string_view"});
  CORELOG_WARN_TRUE(false, std::string("warn detail from temporary"));

  ASSERT_EQ(state.callback_count, 2);
  ASSERT_EQ(state.records.size(), 2U);
  EXPECT_EQ(state.records[0].message, "info via string_view");
  EXPECT_EQ(state.records[1].level, corelog::LogLevel::kWarn);
  EXPECT_EQ(state.records[1].message, "Assert 'false' failed: 'warn detail from temporary'");
}

TEST(TestCoreLog, ScalarDetailIsMaterializedSafely) {
  LogSinkScope guard;
  CaptureState state;
  corelog::SetLogSink(
      {.callback = &CaptureCallback, .user_data = &state, .min_level = corelog::LogLevel::kTrace});

  CORELOG_WARN_TRUE(false, 123);

  ASSERT_EQ(state.callback_count, 1);
  ASSERT_EQ(state.records.size(), 1U);
  EXPECT_EQ(state.records[0].level, corelog::LogLevel::kWarn);
  EXPECT_EQ(state.records[0].message, "Assert 'false' failed: '123'");
}

TEST(TestCoreLog, UserDataIsPassedThroughAndMinLevelFilters) {
  LogSinkScope guard;
  CaptureState state;
  corelog::SetLogSink(
      {.callback = &CaptureCallback, .user_data = &state, .min_level = corelog::LogLevel::kWarn});

  const corelog::LogRecord info{
      corelog::LogLevel::kInfo, "test", "ignore-info", __FILE__, __LINE__, __func__};
  const corelog::LogRecord warn{
      corelog::LogLevel::kWarn, "test", "keep-warn", __FILE__, __LINE__, __func__};

  corelog::LogMessage(info);
  corelog::LogMessage(warn);

  ASSERT_EQ(state.callback_count, 1);
  ASSERT_EQ(state.records.size(), 1U);
  EXPECT_EQ(state.records[0].message, "keep-warn");
  EXPECT_EQ(state.records[0].category, "test");
}

TEST(TestCoreLog, ResetLogSinkStopsUsingPreviousCallback) {
  LogSinkScope guard;
  CaptureState state;
  corelog::SetLogSink(
      {.callback = &CaptureCallback, .user_data = &state, .min_level = corelog::LogLevel::kTrace});

  CORELOG_INFO("before reset");
  ASSERT_EQ(state.callback_count, 1);

  corelog::ResetLogSink();

  const corelog::LogRecord trace{
      corelog::LogLevel::kTrace, "test", "after reset", __FILE__, __LINE__, __func__};
  corelog::LogMessage(trace);

  EXPECT_EQ(state.callback_count, 1);
  ASSERT_EQ(state.records.size(), 1U);
  EXPECT_EQ(state.records[0].message, "before reset");
}

}  // namespace
