#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "single_instance.h"

namespace {

bool IsSystemSnapped(HWND window) {
  using IsArranged = BOOL(WINAPI*)(HWND);
  const auto is_arranged = reinterpret_cast<IsArranged>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "IsWindowArranged"));
  return is_arranged != nullptr && is_arranged(window) != FALSE;
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
  layout_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "lilygobox/window_layout",
          &flutter::StandardMethodCodec::GetInstance());
  layout_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "isSnapped") {
          result->NotImplemented();
          return;
        }
        // 直接读取系统贴靠状态，避免用坐标猜测而误判普通靠边窗口。
        result->Success(flutter::EncodableValue(
            interactive_move_
                ? interactive_resize_ && snapped_before_interaction_
                : IsSystemSnapped(GetHandle())));
      });
  tray_ = std::make_unique<TrayIcon>(GetHandle(), flutter_controller_->engine()->messenger(), project_);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  SetPropW(GetHandle(), lilygobox::kWindowMarker,
           reinterpret_cast<HANDLE>(1));

  return true;
}

void FlutterWindow::OnDestroy() {
  RemovePropW(GetHandle(), lilygobox::kWindowMarker);
  tray_.reset();
  layout_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 拖动中的贴靠预览保留普通外框，松开鼠标提交贴靠后再切换铺满外观。
  if (message == WM_ENTERSIZEMOVE) {
    interactive_move_ = true;
    snapped_before_interaction_ = IsSystemSnapped(hwnd);
    // 尚未收到移动或缩放消息时保留原外观，避免仅按住边缘就闪回圆角。
    interactive_resize_ = true;
  } else if (message == WM_MOVING) {
    interactive_resize_ = false;
  } else if (message == WM_SIZING) {
    interactive_resize_ = true;
  } else if (message == WM_EXITSIZEMOVE) {
    interactive_move_ = false;
    interactive_resize_ = false;
  }
  // 已有窗口响应重复启动：从托盘显示或恢复最小化，并保留最大化状态。
  if (message == lilygobox::ActivateWindowMessage()) {
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(hwnd);
    return 0;
  }
  if (tray_ && tray_->HandleMessage(message, wparam, lparam)) return 0;
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
