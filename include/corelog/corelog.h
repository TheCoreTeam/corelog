#pragma once

#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>

#if defined(CORELOG_BUILD_SHARED)
#if defined(_WIN32)
#define CORELOG_API __declspec(dllexport)
#else
#define CORELOG_API __attribute__((visibility("default")))
#endif
#else
#define CORELOG_API
#endif

namespace corelog {

enum class LogLevel : int {
  kTrace = 0,
  kInfo = 1,
  kWarn = 2,
  kCritical = 3,
};

struct LogRecord {
  LogLevel level;
  const char* category;
  const char* message;
  const char* file;
  int line;
  const char* function;
};

using LogCallback = void (*)(const LogRecord*, void*) noexcept;

struct LogSink {
  LogCallback callback = nullptr;
  void* user_data = nullptr;
  LogLevel min_level = LogLevel::kInfo;
};

CORELOG_API void SetLogSink(const LogSink& sink) noexcept;
CORELOG_API void ResetLogSink() noexcept;
CORELOG_API void LogMessage(const LogRecord& record) noexcept;
[[noreturn]] CORELOG_API void LogFatal(const LogRecord& record) noexcept;

namespace detail {

template <typename T>
concept StreamableLogValue = requires(std::ostringstream& out, const T& value) { out << value; };

class LogText {
 public:
  explicit LogText(const char* message) noexcept
      : view_(message != nullptr ? std::string_view(message) : std::string_view{}) {}

  explicit LogText(char* message) noexcept
      : view_(message != nullptr ? std::string_view(message) : std::string_view{}) {}

  explicit LogText(std::string_view message) noexcept : view_(message) {}

  explicit LogText(const std::string& message) noexcept : view_(message) {}

  explicit LogText(std::string&& message) noexcept
      : storage_(std::move(message)), view_(storage_) {}

  template <typename T>
    requires(!std::is_same_v<std::remove_cvref_t<T>, LogText> &&
             !std::is_convertible_v<T, const char*> &&
             !std::is_convertible_v<T, std::string_view> &&
             !std::is_same_v<std::remove_cvref_t<T>, std::string> && StreamableLogValue<T>)
  explicit LogText(T&& value) : storage_(StreamToString(std::forward<T>(value))), view_(storage_) {}

  std::string_view View() const noexcept { return view_; }

 private:
  template <typename T>
  static std::string StreamToString(T&& value) {
    std::ostringstream out;
    out << std::forward<T>(value);
    return std::move(out).str();
  }

  std::string storage_;
  std::string_view view_;
};

inline LogText ToLogText(const char* message) noexcept { return LogText(message); }
inline LogText ToLogText(char* message) noexcept { return LogText(message); }
inline LogText ToLogText(std::string_view message) noexcept { return LogText(message); }
inline LogText ToLogText(const std::string& message) noexcept { return LogText(message); }
inline LogText ToLogText(std::string&& message) noexcept { return LogText(std::move(message)); }

template <typename T>
inline LogText ToLogText(T&& message) {
  return LogText(std::forward<T>(message));
}

[[noreturn]] CORELOG_API void AssertionFailed(const char* statement, std::string_view detail,
                                              const char* file, int line,
                                              const char* function) noexcept;
CORELOG_API void WarningFailed(const char* statement, std::string_view detail, const char* file,
                               int line, const char* function) noexcept;
CORELOG_API void InfoMessage(std::string_view message, const char* file, int line,
                             const char* function) noexcept;

}  // namespace detail

}  // namespace corelog

#define CORELOG_ASSERT_TRUE(statement, detail_arg)                                         \
  do {                                                                                     \
    if (!(statement)) {                                                                    \
      auto&& corelog_detail = (detail_arg);                                                \
      const auto corelog_detail_text = ::corelog::detail::ToLogText(corelog_detail);       \
      ::corelog::detail::AssertionFailed(#statement, corelog_detail_text.View(), __FILE__, \
                                         __LINE__, __func__);                              \
    }                                                                                      \
  } while (false)

#define CORELOG_WARN_TRUE(statement, detail_arg)                                                   \
  do {                                                                                             \
    if (!(statement)) {                                                                            \
      auto&& corelog_detail = (detail_arg);                                                        \
      const auto corelog_detail_text = ::corelog::detail::ToLogText(corelog_detail);               \
      ::corelog::detail::WarningFailed(#statement, corelog_detail_text.View(), __FILE__, __LINE__, \
                                       __func__);                                                  \
    }                                                                                              \
  } while (false)

#define CORELOG_INFO(statement)                                                                \
  do {                                                                                         \
    auto&& corelog_message = (statement);                                                      \
    const auto corelog_message_text = ::corelog::detail::ToLogText(corelog_message);           \
    ::corelog::detail::InfoMessage(corelog_message_text.View(), __FILE__, __LINE__, __func__); \
  } while (false)
