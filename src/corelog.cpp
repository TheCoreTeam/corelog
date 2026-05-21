#include <corelog/corelog.h>
#include <cstdlib>
#include <mutex>
#include <spdlog/fmt/fmt.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>
#include <string>
#include <string_view>

namespace {

struct SpdlogShutdownGuard {
  SpdlogShutdownGuard() {
    std::atexit([] { spdlog::shutdown(); });
  }
};

struct LogState {
  std::mutex mutex;
  corelog::LogSink sink;
};

LogState& GetLogState() {
  static LogState state;
  return state;
}

spdlog::logger& GetDefaultLogger() {
  static SpdlogShutdownGuard shutdown_guard;
  static auto sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
  static spdlog::logger logger{"CORELOG", sink};
  static const auto kConfigured = [] {
    logger.set_level(spdlog::level::info);
    logger.flush_on(spdlog::level::critical);
    return true;
  }();
  static_cast<void>(kConfigured);
  return logger;
}

spdlog::level::level_enum ToSpdlogLevel(corelog::LogLevel level) noexcept {
  switch (level) {
    case corelog::LogLevel::kTrace:
      return spdlog::level::trace;
    case corelog::LogLevel::kInfo:
      return spdlog::level::info;
    case corelog::LogLevel::kWarn:
      return spdlog::level::warn;
    case corelog::LogLevel::kCritical:
      return spdlog::level::critical;
  }
  return spdlog::level::info;
}

bool LogLevelEnabled(corelog::LogLevel level, corelog::LogLevel min_level) noexcept {
  return static_cast<int>(level) >= static_cast<int>(min_level);
}

void LogToDefaultSink(const corelog::LogRecord& record) noexcept {
  auto& logger = GetDefaultLogger();
  fmt::memory_buffer message;
  fmt::format_to(std::back_inserter(message), "[{}] {}",
                 record.category != nullptr ? record.category : "",
                 record.message != nullptr ? record.message : "");
  logger.log(ToSpdlogLevel(record.level), spdlog::string_view_t(message.data(), message.size()));
}

}  // namespace

namespace corelog {

namespace detail {

namespace {

std::string BuildAssertionMessage(const char* statement, std::string_view detail) {
  std::string message = "Assert '";
  message += statement;
  message += "' failed";
  if (!detail.empty()) {
    message += ": '";
    message.append(detail.data(), detail.size());
    message += "'";
  }
  return message;
}

}  // namespace

[[noreturn]] void AssertionFailed(const char* statement, std::string_view detail, const char* file,
                                  int line, const char* function) noexcept {
  const std::string message = BuildAssertionMessage(statement, detail);
  const LogRecord record{LogLevel::kCritical, "assert", message.c_str(), file, line, function};
  LogFatal(record);
}

void WarningFailed(const char* statement, std::string_view detail, const char* file, int line,
                   const char* function) noexcept {
  const std::string message = BuildAssertionMessage(statement, detail);
  const LogRecord record{LogLevel::kWarn, "assert", message.c_str(), file, line, function};
  LogMessage(record);
}

void InfoMessage(std::string_view message, const char* file, int line,
                 const char* function) noexcept {
  const std::string owned_message(message);
  const LogRecord record{LogLevel::kInfo, "info", owned_message.c_str(), file, line, function};
  LogMessage(record);
}

}  // namespace detail

void SetLogSink(const LogSink& sink) noexcept {
  auto& state = GetLogState();
  std::lock_guard<std::mutex> lock(state.mutex);
  state.sink = sink;
}

void ResetLogSink() noexcept {
  auto& state = GetLogState();
  std::lock_guard<std::mutex> lock(state.mutex);
  state.sink = LogSink{};
}

void LogMessage(const LogRecord& record) noexcept {
  LogSink sink;
  {
    auto& state = GetLogState();
    std::lock_guard<std::mutex> lock(state.mutex);
    sink = state.sink;
  }

  if (sink.callback != nullptr) {
    if (LogLevelEnabled(record.level, sink.min_level)) {
      sink.callback(&record, sink.user_data);
    }
    return;
  }

  LogToDefaultSink(record);
}

[[noreturn]] void LogFatal(const LogRecord& record) noexcept {
  LogMessage(record);
  std::abort();
}

}  // namespace corelog
