/*
 * @Description: 托盘原生桥接只处理图标和窗口，右键菜单由独立 Flutter 视图绘制。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 00:20:00
 * @LastEditTime: 2026-10-04 13:14:48
 * @License: GPL 3.0
 */
#include "tray_icon.h"

#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <algorithm>
#include <cmath>
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 71;
constexpr UINT kDismissMenuMessage = WM_APP + 72;
constexpr UINT_PTR kWarmupTimer = 0x4c47;
constexpr UINT_PTR kFadeTimer = 0x4c48;
constexpr UINT_PTR kMenuWatchTimer = 0x4c49;
constexpr wchar_t kMenuClass[] = L"LilygoBoxTrayMenu";
// 与 Flutter 托盘视图保持一致，容纳主窗口样式的紧凑阴影。
constexpr int kShadowPadding = 16;
constexpr int kMenuWidth = 150 + kShadowPadding * 2;
constexpr int kMenuHeight = 75 + kShadowPadding * 2;

int64_t ReadRequestId(const flutter::EncodableValue* arguments) {
  const auto* args = arguments ? std::get_if<flutter::EncodableMap>(arguments) : nullptr;
  if (!args) return -1;
  auto id = args->find(flutter::EncodableValue("requestId"));
  if (id == args->end()) return -1;
  if (const auto* value = std::get_if<int64_t>(&id->second)) return *value;
  if (const auto* value = std::get_if<int32_t>(&id->second)) return *value;
  return -1;
}

void EnableTransparentComposition(HWND window) {
  // 阴影只由 Flutter 按卡片轮廓绘制，禁用宿主矩形的系统非客户区装饰。
  const DWMNCRENDERINGPOLICY rendering = DWMNCRP_DISABLED;
  DwmSetWindowAttribute(window, DWMWA_NCRENDERING_POLICY, &rendering, sizeof(rendering));
  // 与 window_manager 的透明主窗口保持相同的 Windows 合成设置。
  struct AccentPolicy { int state; int flags; int color; int animation; };
  struct CompositionData { int attribute; void* data; ULONG size; };
  using SetComposition = BOOL(WINAPI*)(HWND, CompositionData*);
  auto set_composition = reinterpret_cast<SetComposition>(GetProcAddress(
      GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute"));
  if (set_composition) {
    AccentPolicy policy{2, 2, 0, 0}; // ACCENT_ENABLE_TRANSPARENTGRADIENT
    CompositionData data{19, &policy, sizeof(policy)};
    set_composition(window, &data);
  }
}
}  // namespace

TrayIcon* TrayIcon::mouse_owner_ = nullptr;

TrayIcon::TrayIcon(HWND owner, flutter::BinaryMessenger* messenger,
                   const flutter::DartProject& project)
    : owner_(owner), taskbar_created_(RegisterWindowMessage(L"TaskbarCreated")),
      project_(project) {
  icon_.cbSize = sizeof(icon_);
  icon_.hWnd = owner_;
  icon_.uID = 1;
  icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon_.uCallbackMessage = kTrayMessage;
  icon_.hIcon = static_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  wcscpy_s(icon_.szTip, L"LilygoBox");

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "lilygobox/tray", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "configure") {
      const auto* args = call.arguments()
          ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      if (!args) {
        result->Error("invalid_arguments", "Tray appearance is required");
        return;
      }
      appearance_ = *args;
      configured_ = true;
      if (menu_ready_) {
        if (menu_requested_) PresentMenu();
        else PrepareMenu();
      }
      result->Success(flutter::EncodableValue(EnsureIcon()));
      // 主窗口启动后预热一次，把引擎、字体和首帧开销移出右键事件。
      if (!menu_controller_ && !warmup_scheduled_) {
        warmup_scheduled_ = SetTimer(owner_, kWarmupTimer, 300, nullptr) != 0;
      }
    } else if (call.method_name() == "hide") {
      const bool ready = configured_ && EnsureIcon();
      if (ready) {
        DismissMenu();
        ShowWindow(owner_, SW_HIDE);
      }
      result->Success(flutter::EncodableValue(ready));
    } else {
      result->NotImplemented();
    }
  });
}

TrayIcon::~TrayIcon() {
  StopMouseWatch();
  KillTimer(owner_, kWarmupTimer);
  channel_->SetMethodCallHandler(nullptr);
  if (menu_channel_) menu_channel_->SetMethodCallHandler(nullptr);
  menu_ready_ = false;
  menu_channel_.reset();
  menu_controller_.reset();
  if (menu_) DestroyWindow(menu_);
  Shell_NotifyIcon(NIM_DELETE, &icon_);
  if (icon_.hIcon) DestroyIcon(icon_.hIcon);
}

bool TrayIcon::EnsureIcon() {
  if (!icon_.hIcon) return false;
  if (Shell_NotifyIcon(NIM_MODIFY, &icon_)) return true;
  return Shell_NotifyIcon(NIM_ADD, &icon_) != FALSE;
}

bool TrayIcon::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == kWarmupTimer) {
    KillTimer(owner_, kWarmupTimer);
    warmup_scheduled_ = false;
    GetCursorPos(&menu_position_);
    EnsureMenu();
    return true;
  }
  if (message == taskbar_created_ && configured_) {
    if (!EnsureIcon()) channel_->InvokeMethod("show", nullptr);
    return true;
  }
  if (message != kTrayMessage || wparam != icon_.uID) return false;
  if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) OpenMenu();
  if (lparam == WM_LBUTTONUP || lparam == NIN_KEYSELECT) Activate(0);
  return true;
}

void TrayIcon::OpenMenu() {
  KillTimer(owner_, kWarmupTimer);
  warmup_scheduled_ = false;
  GetCursorPos(&menu_position_);
  menu_foreground_ = GetForegroundWindow();
  menu_requested_ = true;
  menu_presented_ = false;
  if (!EnsureMenu()) return;
  ResizeMenu();
  if (menu_ready_) PresentMenu();
}

bool TrayIcon::EnsureMenu() {
  if (!menu_) {
    WNDCLASSW wc{};
    wc.lpfnWndProc = MenuProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = kMenuClass;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&wc);
    menu_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_NOACTIVATE, kMenuClass,
        L"LilygoBox Tray Menu", WS_POPUP | WS_CLIPCHILDREN,
        menu_position_.x, menu_position_.y, kMenuWidth, kMenuHeight,
        nullptr, nullptr, wc.hInstance, this);
    if (!menu_) return false;
    EnableTransparentComposition(menu_);
  }
  // 菜单独立预热，不注册主窗口插件或启动账号、设备等服务。
  if (!menu_controller_) {
    auto menu_project = project_;
    menu_project.set_dart_entrypoint("trayMain");
    menu_project.set_dart_entrypoint_arguments({});
    menu_controller_ = std::make_unique<flutter::FlutterViewController>(
        kMenuWidth, kMenuHeight, menu_project);
    if (!menu_controller_->engine() || !menu_controller_->view()) {
      menu_controller_.reset();
      if (menu_requested_) channel_->InvokeMethod("show", nullptr);
      menu_requested_ = false;
      return false;
    }
    const HWND child = menu_controller_->view()->GetNativeWindow();
    SetParent(child, menu_);
    menu_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        menu_controller_->engine()->messenger(), "lilygobox/tray_menu",
        &flutter::StandardMethodCodec::GetInstance());
    menu_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "ready") {
        menu_ready_ = true;
        result->Success();
        if (menu_requested_) PresentMenu();
        else PrepareMenu();
      } else if (call.method_name() == "painted") {
        result->Success();
        if (menu_requested_ && ReadRequestId(call.arguments()) == request_id_) {
          int duration = 150;
          const auto* args = call.arguments()
              ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
          if (args) {
            auto fade = args->find(flutter::EncodableValue("fadeDurationMs"));
            if (fade != args->end()) {
              if (const auto* ms = std::get_if<int32_t>(&fade->second)) duration = std::clamp(*ms, 0, 1000);
            }
            auto reduced = args->find(flutter::EncodableValue("reduceMotion"));
            if (reduced != args->end() && std::get_if<bool>(&reduced->second) &&
                std::get<bool>(reduced->second)) duration = 0;
          }
          ShowMenu(duration);
        }
      } else if (call.method_name() == "show" || call.method_name() == "exit") {
        result->Success();
        if (menu_requested_ && ReadRequestId(call.arguments()) == request_id_)
          Activate(call.method_name() == "show" ? 0 : 1);
      } else if (call.method_name() == "dismiss") {
        result->Success();
        if (menu_requested_ && ReadRequestId(call.arguments()) == request_id_) DismissMenu();
      } else {
        result->NotImplemented();
      }
    });
    ResizeMenu();
  }
  return true;
}

void TrayIcon::ResizeMenu() {
  MONITORINFO monitor{sizeof(MONITORINFO)};
  GetMonitorInfo(MonitorFromPoint(menu_position_, MONITOR_DEFAULTTONEAREST), &monitor);
  // 只移动到目标屏幕获取 DPI，保留尺寸，避免每次从 1×1 重建渲染表面。
  SetWindowPos(menu_, nullptr, menu_position_.x, menu_position_.y, 0, 0,
               SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER);
  scale_ = static_cast<float>(GetDpiForWindow(menu_)) / 96.0f;
  const int width = static_cast<int>(std::ceil(kMenuWidth * scale_));
  const int height = static_cast<int>(std::ceil(kMenuHeight * scale_));
  const int padding = static_cast<int>(std::lround(kShadowPadding * scale_));
  const int card_width = static_cast<int>(std::ceil(150 * scale_));
  const int card_height = static_cast<int>(std::ceil(75 * scale_));
  const int gap = static_cast<int>(std::lround(4 * scale_));
  // 卡片左下角对齐右键松开的位置，允许覆盖任务栏；只按整个屏幕避让，
  // 不能用 rcWork 或图标顶部，否则菜单会被推到任务栏上方而远离点击点。
  int card_x = menu_position_.x;
  int card_y = menu_position_.y - card_height;
  if (card_y < monitor.rcMonitor.top + gap) card_y = menu_position_.y;
  card_x = std::clamp(card_x, static_cast<int>(monitor.rcMonitor.left) + gap,
      std::max(static_cast<int>(monitor.rcMonitor.left) + gap,
               static_cast<int>(monitor.rcMonitor.right) - gap - card_width));
  card_y = std::clamp(card_y, static_cast<int>(monitor.rcMonitor.top) + gap,
      std::max(static_cast<int>(monitor.rcMonitor.top) + gap,
               static_cast<int>(monitor.rcMonitor.bottom) - gap - card_height));
  const int x = card_x - padding;
  const int y = card_y - padding;
  // 不使用整数像素区域裁剪，保留 Flutter 圆角边缘的逐像素透明度。
  SetWindowPos(menu_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
}

void TrayIcon::PresentMenu() {
  auto args = appearance_;
  args[flutter::EncodableValue("requestId")] = flutter::EncodableValue(++request_id_);
  // 隐藏的 Flutter 视图可能停止调度帧。先透明显示以恢复绘制，再等待首帧，避免互相等待。
  if (!IsWindowVisible(menu_)) {
    SetLayeredWindowAttributes(menu_, 0, 0, LWA_ALPHA);
    ShowWindow(menu_, SW_SHOWNOACTIVATE);
  }
  StartMouseWatch();
  // 菜单不激活就不会收到失焦和键盘消息，仅在打开期间检查关闭条件。
  SetTimer(menu_, kMenuWatchTimer, 50, nullptr);
  menu_channel_->InvokeMethod("present", std::make_unique<flutter::EncodableValue>(args));
  menu_controller_->ForceRedraw();
}

void TrayIcon::PrepareMenu() {
  auto args = appearance_;
  args[flutter::EncodableValue("requestId")] = flutter::EncodableValue(++request_id_);
  menu_channel_->InvokeMethod("prepare", std::make_unique<flutter::EncodableValue>(args));
  menu_controller_->ForceRedraw();
}

void TrayIcon::ShowMenu(int duration_ms) {
  if (!menu_presented_) {
    menu_presented_ = true;
    KillTimer(menu_, kFadeTimer);
    fade_duration_ms_ = duration_ms;
    fade_started_ = GetTickCount64();
    // 宿主窗口的透明度同时影响卡片背景、图标和文字。
    SetLayeredWindowAttributes(menu_, 0, duration_ms > 0 ? 0 : 255, LWA_ALPHA);
    ShowWindow(menu_, SW_SHOWNOACTIVATE);
    if (duration_ms > 0 && !SetTimer(menu_, kFadeTimer, 16, nullptr)) {
      SetLayeredWindowAttributes(menu_, 0, 255, LWA_ALPHA);
    }
  }
  // 不抢占 Explorer 的焦点，否则隐藏图标面板会在菜单交互期间收起。
}

void TrayIcon::CheckMenuDismissal() {
  if (!menu_requested_) return;
  const HWND foreground = GetForegroundWindow();
  if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) ||
      (foreground && foreground != menu_foreground_ && foreground != menu_ &&
       !IsChild(menu_, foreground))) {
    DismissMenu();
  }
}

void TrayIcon::TickFade() {
  const double progress = std::min(1.0,
      static_cast<double>(GetTickCount64() - fade_started_) / fade_duration_ms_);
  SetLayeredWindowAttributes(menu_, 0, static_cast<BYTE>(std::lround(255 * progress)), LWA_ALPHA);
  if (progress >= 1.0) KillTimer(menu_, kFadeTimer);
}

void TrayIcon::DismissMenu() {
  if (!menu_requested_) return;
  menu_requested_ = false;
  menu_presented_ = false;
  ++request_id_;
  if (!swallow_mouse_up_) StopMouseWatch();
  if (menu_) {
    KillTimer(menu_, kFadeTimer);
    KillTimer(menu_, kMenuWatchTimer);
    ShowWindow(menu_, SW_HIDE);
  }
  if (menu_ready_) {
    flutter::EncodableMap args{{flutter::EncodableValue("requestId"), flutter::EncodableValue(request_id_)}};
    menu_channel_->InvokeMethod("dismiss", std::make_unique<flutter::EncodableValue>(args));
  }
}

bool TrayIcon::ContainsCardPoint(POINT point) const {
  ScreenToClient(menu_, &point);
  const float x = point.x / scale_ - kShadowPadding;
  const float y = point.y / scale_ - kShadowPadding;
  if (x < 0 || y < 0 || x >= 150 || y >= 75) return false;
  const float dx = x - std::clamp(x, 8.0f, 142.0f);
  const float dy = y - std::clamp(y, 8.0f, 67.0f);
  return dx * dx + dy * dy <= 64;
}

void TrayIcon::StartMouseWatch() {
  if (mouse_hook_) return;
  mouse_owner_ = this;
  // 仅菜单打开期间监听按键，不依赖 Explorer 激活规则，也不记录鼠标数据。
  mouse_hook_ = SetWindowsHookExW(WH_MOUSE_LL, MouseProc, GetModuleHandle(nullptr), 0);
  if (!mouse_hook_) mouse_owner_ = nullptr;
}

void TrayIcon::StopMouseWatch() {
  if (mouse_hook_) UnhookWindowsHookEx(mouse_hook_);
  mouse_hook_ = nullptr;
  swallow_mouse_up_ = 0;
  if (mouse_owner_ == this) mouse_owner_ = nullptr;
}

LRESULT CALLBACK TrayIcon::MouseProc(int code, WPARAM wparam, LPARAM lparam) {
  auto* self = mouse_owner_;
  if (code == HC_ACTION && self) {
    // 吞掉同一次外部点击的抬起事件，防止关闭菜单后又触发底下的托盘图标。
    if (self->swallow_mouse_up_ == wparam) {
      self->StopMouseWatch();
      return 1;
    }
    UINT up = wparam == WM_LBUTTONDOWN ? WM_LBUTTONUP :
              wparam == WM_RBUTTONDOWN ? WM_RBUTTONUP :
              wparam == WM_MBUTTONDOWN ? WM_MBUTTONUP : 0;
    if (up && self->menu_requested_ &&
        !self->ContainsCardPoint(reinterpret_cast<MSLLHOOKSTRUCT*>(lparam)->pt)) {
      self->swallow_mouse_up_ = up;
      // 回调中只投递消息，避免跨 Flutter 通道阻塞系统鼠标处理。
      PostMessage(self->menu_, kDismissMenuMessage, static_cast<WPARAM>(self->request_id_), 0);
      return 1;
    }
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}

void TrayIcon::Activate(int item) {
  DismissMenu();
  channel_->InvokeMethod(item == 0 ? "show" : "exit", nullptr);
}

LRESULT CALLBACK TrayIcon::MenuProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<TrayIcon*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<TrayIcon*>(reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->menu_ = hwnd;
  }
  if (!self) return DefWindowProc(hwnd, message, wparam, lparam);
  if (message == kDismissMenuMessage) {
    if (static_cast<int64_t>(wparam) == self->request_id_) self->DismissMenu();
    return 0;
  }
  if (message == WM_TIMER && wparam == kFadeTimer) {
    self->TickFade();
    return 0;
  }
  if (message == WM_TIMER && wparam == kMenuWatchTimer) {
    self->CheckMenuDismissal();
    return 0;
  }
  // 点击或系统的悬停激活设置都不应激活菜单，鼠标事件仍交给 Flutter。
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  // 先处理菜单退出条件，避免 Flutter 提前消费窗口消息后漏掉失焦关闭。
  if (self->menu_presented_ && ((message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE) ||
      (message == WM_ACTIVATEAPP && !wparam) || message == WM_CANCELMODE)) {
    self->DismissMenu();
  }
  if (message == WM_CLOSE) {
    self->DismissMenu();
    return 0;
  }
  if (self->menu_controller_) {
    auto result = self->menu_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  switch (message) {
    // 阴影区域交给 Flutter 的外部点击处理，不能依赖跨进程 HTTRANSPARENT。
    case WM_NCHITTEST: return HTCLIENT;
    case WM_SIZE:
      if (self->menu_controller_) {
        RECT rect;
        GetClientRect(hwnd, &rect);
        MoveWindow(self->menu_controller_->view()->GetNativeWindow(), 0, 0,
                    rect.right, rect.bottom, TRUE);
      }
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
