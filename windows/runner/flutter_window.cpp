#include "flutter_window.h"

#include <windows.h>
#include <winhttp.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr,
                                       0, nullptr, nullptr);
  if (size <= 1) {
    return std::string();
  }
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, out.data(), size, nullptr,
                      nullptr);
  if (!out.empty() && out.back() == '\0') {
    out.pop_back();
  }
  return out;
}

std::wstring Trim(const std::wstring& value) {
  const auto start = value.find_first_not_of(L" \t\r\n");
  if (start == std::wstring::npos) {
    return std::wstring();
  }
  const auto end = value.find_last_not_of(L" \t\r\n");
  return value.substr(start, end - start + 1);
}

std::wstring ExtractProxyEntry(const std::wstring& proxy_text,
                               const std::wstring& scheme) {
  const auto raw = Trim(proxy_text);
  if (raw.empty()) {
    return std::wstring();
  }

  const auto scheme_key = scheme + L"=";
  size_t segment_start = 0;
  while (segment_start < raw.size()) {
    const auto segment_end = raw.find(L';', segment_start);
    const auto segment = Trim(raw.substr(
        segment_start, segment_end == std::wstring::npos
                           ? std::wstring::npos
                           : segment_end - segment_start));
    if (!segment.empty()) {
      if (segment.rfind(scheme_key, 0) == 0) {
        return Trim(segment.substr(scheme_key.size()));
      }
      if (segment.find(L'=') == std::wstring::npos && scheme == L"https") {
        return segment;
      }
    }
    if (segment_end == std::wstring::npos) {
      break;
    }
    segment_start = segment_end + 1;
  }

  return std::wstring();
}

std::optional<std::string> GetSystemHttpProxyUrl() {
  WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config;
  if (!WinHttpGetIEProxyConfigForCurrentUser(&config)) {
    return std::nullopt;
  }

  std::wstring proxy_text;
  if (config.lpszProxy != nullptr) {
    proxy_text = config.lpszProxy;
  }

  if (config.lpszAutoConfigUrl != nullptr) {
    GlobalFree(config.lpszAutoConfigUrl);
  }
  if (config.lpszProxy != nullptr) {
    GlobalFree(config.lpszProxy);
  }
  if (config.lpszProxyBypass != nullptr) {
    GlobalFree(config.lpszProxyBypass);
  }

  auto proxy = ExtractProxyEntry(proxy_text, L"https");
  if (proxy.empty()) {
    proxy = ExtractProxyEntry(proxy_text, L"http");
  }
  if (proxy.empty()) {
    return std::nullopt;
  }

  auto utf8 = WideToUtf8(proxy);
  if (utf8.empty()) {
    return std::nullopt;
  }
  if (utf8.find("://") == std::string::npos) {
    utf8 = "http://" + utf8;
  }
  return utf8;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "linplayer/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "setBorderlessFullscreen") {
          bool enabled = false;
          if (call.arguments() &&
              std::holds_alternative<bool>(*call.arguments())) {
            enabled = std::get<bool>(*call.arguments());
          }
          SetBorderlessFullscreen(enabled);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  device_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "linplayer/device",
          &flutter::StandardMethodCodec::GetInstance());
  device_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "systemHttpProxyUrl") {
          const auto proxy_url = GetSystemHttpProxyUrl();
          if (proxy_url.has_value()) {
            result->Success(flutter::EncodableValue(*proxy_url));
          } else {
            result->Success();
          }
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  window_channel_ = nullptr;
  device_channel_ = nullptr;

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
