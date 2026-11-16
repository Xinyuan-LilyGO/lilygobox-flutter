/*
 * @Description: 托盘原生桥接只处理图标和窗口，右键菜单由独立 Flutter 视图绘制。
 */
#include "tray_icon.h"

#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>
#include <dwmapi.h>
#include <algorithm>
#include <cmath>
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 71;
constexpr UINT kDismissMenuMessage = WM_APP + 72;
constexpr UINT kMenuHostReady = WM_APP + 73;
constexpr UINT kMenuHostAction = WM_APP + 74;
constexpr UINT kMenuHostPainted = WM_APP + 75;
constexpr UINT kOpenMenuMessage = WM_APP + 77;
constexpr UINT kPrepareMenuMessage = WM_APP + 78;
constexpr UINT kMenuHostPrepared = WM_APP + 79;
constexpr UINT_PTR kMenuWarmupTimer = 0x4c4b;
constexpr UINT_PTR kMenuStartupTimer = 0x4c4a;
constexpr UINT kMenuStartupTimeoutMs = 15000;

// Explorer 会在任务栏和托盘溢出面板之间切换前台 HWND。
// 仅将这些托盘界面视为同一上下文，不包含其他 Explorer 窗口。
bool IsTraySurface(HWND window) {
  for (HWND current = window; current; current = GetParent(current)) {
    wchar_t name[128]{};
    GetClassNameW(current, name, 128);
    if (wcscmp(name, L"Shell_TrayWnd") == 0 ||
        wcscmp(name, L"Shell_SecondaryTrayWnd") == 0 ||
        wcscmp(name, L"NotifyIconOverflowWindow") == 0 ||
        wcscmp(name, L"TopLevelWindowForOverflowXamlIsland") == 0) {
      return true;
    }
  }
  return false;
}

constexpr UINT_PTR kParentWatchTimer = 0x4c47;
constexpr wchar_t kHostClass[] = L"LilygoBoxTrayHost";
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

bool TrayIcon::EnsureMenuProcess() {
  if (menu_process_ && WaitForSingleObject(menu_process_, 0) == WAIT_TIMEOUT) return true;
  if (menu_process_) CloseHandle(menu_process_);
  menu_process_ = nullptr;
  menu_host_window_ = nullptr;
  menu_warming_ = false;
  if (!menu_job_) {
    menu_job_ = CreateJobObjectW(nullptr, nullptr);
    if (!menu_job_) return false;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(menu_job_, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
      CloseHandle(menu_job_);
      menu_job_ = nullptr;
      return false;
    }
  }
  wchar_t executable[32768];
  if (!GetModuleFileNameW(nullptr, executable, 32768)) return false;
  std::wstring command = L"\"" + std::wstring(executable) + L"\" --lilygobox-tray-host=" +
      std::to_wstring(reinterpret_cast<uintptr_t>(owner_));
  // 辅助引擎不能继承主引擎的 VM 端口及启动暂停参数。
  std::vector<wchar_t> environment;
  LPWCH inherited = GetEnvironmentStringsW();
  if (!inherited) return false;
  for (const wchar_t* entry = inherited; *entry; entry += wcslen(entry) + 1) {
    if (_wcsnicmp(entry, L"FLUTTER_ENGINE_SWITCH", 21) == 0) continue;
    environment.insert(environment.end(), entry, entry + wcslen(entry) + 1);
  }
  FreeEnvironmentStringsW(inherited);
  environment.push_back(0);
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable, command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT, environment.data(), nullptr, &startup, &process)) return false;
  if (!AssignProcessToJobObject(menu_job_, process.hProcess)) {
    TerminateProcess(process.hProcess, EXIT_FAILURE);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return false;
  }
  ResumeThread(process.hThread);
  menu_process_ = process.hProcess;
  menu_process_id_ = process.dwProcessId;
  CloseHandle(process.hThread);
  return true;
}

bool TrayIcon::SendMenuCommand(const std::string& command) {
  if (!menu_host_window_ || !IsWindow(menu_host_window_)) return false;
  auto args = appearance_;
  args[flutter::EncodableValue("command")] = flutter::EncodableValue(command);
  if (command == "open") {
    args[flutter::EncodableValue("openX")] = flutter::EncodableValue(static_cast<int32_t>(menu_position_.x));
    args[flutter::EncodableValue("openY")] = flutter::EncodableValue(static_cast<int32_t>(menu_position_.y));
  }
  auto bytes = flutter::StandardMessageCodec::GetInstance().EncodeMessage(flutter::EncodableValue(args));
  if (!bytes || bytes->size() > 65536) return false;
  COPYDATASTRUCT data{0x4c474254, static_cast<DWORD>(bytes->size()), bytes->data()};
  DWORD_PTR result = FALSE;
  const bool delivered = SendMessageTimeoutW(
      menu_host_window_, WM_COPYDATA, reinterpret_cast<WPARAM>(owner_),
      reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 1000, &result) != 0;
  if (!delivered || result == FALSE) {
    OutputDebugStringW(L"LilygoBox tray: menu IPC was not acknowledged.\n");
    return false;
  }
  return true;
}

int TrayIcon::RunMenuHost(const flutter::DartProject& project, HWND owner) {
  DWORD parent_id = 0;
  GetWindowThreadProcessId(owner, &parent_id);
  HANDLE parent = OpenProcess(SYNCHRONIZE, FALSE, parent_id);
  if (!parent) return EXIT_FAILURE;
  TrayIcon host(owner, nullptr, project);
  WNDCLASSW wc{};
  wc.lpfnWndProc = HostProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = kHostClass;
  RegisterClassW(&wc);
  const HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, kHostClass, L"LilygoBox Tray Host",
      WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, wc.hInstance, &host);
  if (!window) { CloseHandle(parent); return EXIT_FAILURE; }
  SetTimer(window, kParentWatchTimer, 1000, nullptr);
  PostMessage(owner, kMenuHostReady, reinterpret_cast<WPARAM>(window), 0);
  MSG message;
  while (GetMessage(&message, nullptr, 0, 0) > 0) {
    if (message.hwnd == window && message.message == WM_TIMER &&
        message.wParam == kParentWatchTimer && WaitForSingleObject(parent, 0) != WAIT_TIMEOUT) break;
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
  KillTimer(window, kParentWatchTimer);
  DestroyWindow(window);
  CloseHandle(parent);
  return EXIT_SUCCESS;
}

LRESULT CALLBACK TrayIcon::HostProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* host = reinterpret_cast<TrayIcon*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    host = static_cast<TrayIcon*>(reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(host));
    host->menu_host_window_ = hwnd;
  }
  if (message == WM_COPYDATA && host && reinterpret_cast<HWND>(wparam) == host->owner_) {
    const auto* data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
    if (!data || data->dwData != 0x4c474254 || !data->lpData || data->cbData > 65536) return FALSE;
    auto decoded = flutter::StandardMessageCodec::GetInstance().DecodeMessage(
        static_cast<const uint8_t*>(data->lpData), data->cbData);
    const auto* args = decoded ? std::get_if<flutter::EncodableMap>(decoded.get()) : nullptr;
    if (!args) return FALSE;
    auto command = args->find(flutter::EncodableValue("command"));
    if (command == args->end() || !std::get_if<std::string>(&command->second)) return FALSE;
    const auto action = std::get<std::string>(command->second);
    if (action == "open") {
      const auto x = args->find(flutter::EncodableValue("openX"));
      const auto y = args->find(flutter::EncodableValue("openY"));
      if (x == args->end() || y == args->end() ||
          !std::get_if<int32_t>(&x->second) || !std::get_if<int32_t>(&y->second)) return FALSE;
      host->menu_position_ = {std::get<int32_t>(x->second), std::get<int32_t>(y->second)};
    }
    host->appearance_ = *args;
    host->appearance_.erase(flutter::EncodableValue("command"));
    host->appearance_.erase(flutter::EncodableValue("openX"));
    host->appearance_.erase(flutter::EncodableValue("openY"));
    if (action == "open") {
      host->menu_requested_ = true;
      const auto generation = ++host->open_generation_;
      if (!PostMessageW(hwnd, kOpenMenuMessage, generation, 0)) {
        host->menu_requested_ = false;
        return FALSE;
      }
    }
    else if (action == "dismiss") host->DismissMenu();
    else if (action == "quit") {
      ++host->open_generation_;
      host->menu_requested_ = false;
      PostQuitMessage(0);
    }
    else if (action == "configure") {
      if (host->menu_requested_ && host->menu_ready_) host->PresentMenu();
      else if (!host->menu_controller_) PostMessageW(hwnd, kPrepareMenuMessage, 0, 0);
    }
    return TRUE;
  }
  if (message == kPrepareMenuMessage && host) {
    // 先确认 IPC，再创建引擎，避免占用主窗口的同步 IPC 等待时间。
    if (!host->menu_requested_ && !host->menu_controller_) {
      GetCursorPos(&host->menu_position_);
      host->EnsureMenu();
    }
    return 0;
  }
  if (message == kOpenMenuMessage && host) {
    if (host->menu_requested_ && wparam == host->open_generation_) {
      host->OpenMenu();
    }
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}


TrayIcon::TrayIcon(HWND owner, flutter::BinaryMessenger* messenger,
                   const flutter::DartProject& project)
    : owner_(owner), taskbar_created_(RegisterWindowMessage(L"TaskbarCreated")),
      project_(project) {
  if (!messenger) {
    is_menu_host_ = true;
    return;
  }
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
      if (!menu_warming_) SendMenuCommand("configure");
      result->Success(flutter::EncodableValue(EnsureIcon()));
      // 延后一次准备，避开主窗口首帧；失败时仍可由实际右键按需启动。
      if (!warmup_scheduled_) {
        warmup_scheduled_ = SetTimer(owner_, kMenuWarmupTimer, 750, nullptr) != 0;
      }
    } else if (call.method_name() == "openMenu") {
      OpenMenu();
      result->Success();
    } else if (call.method_name() == "dismissMenu") {
      DismissMenu();
      result->Success();
    } else if (call.method_name() == "menuReady") {
      result->Success(flutter::EncodableValue(menu_host_painted_ && menu_process_ &&
          WaitForSingleObject(menu_process_, 0) == WAIT_TIMEOUT));
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
  if (!is_menu_host_) {
    KillTimer(owner_, kMenuStartupTimer);
    KillTimer(owner_, kMenuWarmupTimer);
  }
  StopMouseWatch();
  if (!is_menu_host_) SendMenuCommand("quit");
  if (menu_process_) CloseHandle(menu_process_);
  if (menu_job_) CloseHandle(menu_job_);
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  if (menu_channel_) menu_channel_->SetMethodCallHandler(nullptr);
  menu_ready_ = false;
  menu_channel_.reset();
  menu_controller_.reset();
  if (menu_) DestroyWindow(menu_);
  if (!is_menu_host_) Shell_NotifyIcon(NIM_DELETE, &icon_);
  if (icon_.hIcon) DestroyIcon(icon_.hIcon);
}

bool TrayIcon::EnsureIcon() {
  if (!icon_.hIcon) return false;
  if (Shell_NotifyIcon(NIM_MODIFY, &icon_)) return true;
  return Shell_NotifyIcon(NIM_ADD, &icon_) != FALSE;
}

bool TrayIcon::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == kMenuWarmupTimer) {
    KillTimer(owner_, kMenuWarmupTimer);
    EnsureMenuProcess();
    return true;
  }
  if (message == WM_TIMER && wparam == kMenuStartupTimer) {
    KillTimer(owner_, kMenuStartupTimer);
    if (menu_requested_ && !menu_host_painted_) {
      OutputDebugStringW(L"LilygoBox tray: menu did not paint before startup deadline.\n");
      DismissMenu();
      channel_->InvokeMethod("show", nullptr);
    }
    return true;
  }
  if (message == kMenuHostReady) {
    DWORD process_id = 0;
    const HWND host = reinterpret_cast<HWND>(wparam);
    GetWindowThreadProcessId(host, &process_id);
    if (process_id == menu_process_id_) {
      menu_host_window_ = host;
      menu_warming_ = !menu_requested_;
      if (!SendMenuCommand(menu_requested_ ? "open" : "configure") &&
          menu_requested_) {
        KillTimer(owner_, kMenuStartupTimer);
        menu_requested_ = false;
        channel_->InvokeMethod("show", nullptr);
      }
    }
    return true;
  }
  if (message == kMenuHostPrepared && reinterpret_cast<HWND>(wparam) == menu_host_window_) {
    menu_warming_ = false;
    if (menu_requested_ && !SendMenuCommand("open")) {
      DismissMenu();
      channel_->InvokeMethod("show", nullptr);
    }
    return true;
  }
  if (message == kMenuHostPainted && reinterpret_cast<HWND>(wparam) == menu_host_window_) {
    menu_host_painted_ = true;
    KillTimer(owner_, kMenuStartupTimer);
    return true;
  }
  if (message == kMenuHostAction && reinterpret_cast<HWND>(lparam) == menu_host_window_) {
    channel_->InvokeMethod(wparam == 0 ? "show" : "exit", nullptr);
    return true;
  }
  if (message == taskbar_created_ && configured_) {
    if (!EnsureIcon()) channel_->InvokeMethod("show", nullptr);
    return true;
  }
  if (message != kTrayMessage || wparam != icon_.uID) return false;
  if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
    OpenMenu();
  }
  if (lparam == WM_LBUTTONUP || lparam == NIN_KEYSELECT) Activate(0);
  return true;
}

void TrayIcon::OpenMenu() {
  if (!is_menu_host_) {
    GetCursorPos(&menu_position_);
    menu_host_painted_ = false;
    menu_requested_ = true;
    if (!SetTimer(owner_, kMenuStartupTimer, kMenuStartupTimeoutMs, nullptr)) {
      OutputDebugStringW(L"LilygoBox tray: startup timer could not be created.\n");
    }
    if (!EnsureMenuProcess() ||
        (menu_host_window_ && !menu_warming_ && !SendMenuCommand("open"))) {
      KillTimer(owner_, kMenuStartupTimer);
      menu_requested_ = false;
      channel_->InvokeMethod("show", nullptr);
    }
    return;
  }
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
    if (!menu_) {
      DismissMenu();
      PostMessage(owner_, kMenuHostAction, 0, reinterpret_cast<LPARAM>(menu_host_window_));
      return false;
    }
    EnableTransparentComposition(menu_);
  }
  // 先透明显示宿主，再启动菜单引擎，避免向隐藏表面提交首帧。
  SetLayeredWindowAttributes(menu_, 0, 0, LWA_ALPHA);
  ShowWindow(menu_, SW_SHOWNOACTIVATE);
  // 不注册主窗口插件或启动账号、设备等服务。
  if (!menu_controller_) {
    auto menu_project = project_;
    menu_project.set_dart_entrypoint("trayMain");
    menu_project.set_dart_entrypoint_arguments({});
    menu_controller_ = std::make_unique<flutter::FlutterViewController>(
        kMenuWidth, kMenuHeight, menu_project);
    if (!menu_controller_->engine() || !menu_controller_->view()) {
      menu_controller_.reset();
      DismissMenu();
      PostMessage(owner_, kMenuHostAction, 0, reinterpret_cast<LPARAM>(menu_host_window_));
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
        if (menu_requested_) {
          PresentMenu();
        } else {
          PrepareMenu();
        }
        // 首次准备使用透明可见宿主，之后隐藏时只缓存外观，避免隐藏重绘。
      } else if (call.method_name() == "prepared") {
        result->Success();
        // 真实打开会递增 request_id_，旧预热回复不能隐藏新打开的菜单。
        if (!menu_requested_ && ReadRequestId(call.arguments()) == request_id_) {
          ShowWindow(menu_, SW_HIDE);
          PostMessage(owner_, kMenuHostPrepared, reinterpret_cast<WPARAM>(menu_host_window_), 0);
        }
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
          PostMessage(owner_, kMenuHostPainted, reinterpret_cast<WPARAM>(menu_host_window_), 0);
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

void TrayIcon::PrepareMenu() {
  auto args = appearance_;
  args[flutter::EncodableValue("requestId")] = flutter::EncodableValue(++request_id_);
  // EnsureMenu 已使宿主透明可见；完成首帧后再隐藏，不在隐藏表面绘制。
  menu_channel_->InvokeMethod("prepare", std::make_unique<flutter::EncodableValue>(args));
  menu_controller_->ForceRedraw();
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
  if (GetAsyncKeyState(VK_ESCAPE) & 0x8000) {
    DismissMenu();
  } else if (foreground && foreground != menu_foreground_ && foreground != menu_ &&
             !IsChild(menu_, foreground) &&
             !(IsTraySurface(menu_foreground_) && IsTraySurface(foreground))) {
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
  if (!is_menu_host_) {
    KillTimer(owner_, kMenuStartupTimer);
    menu_requested_ = false;
    if (!menu_warming_) SendMenuCommand("dismiss");
    return;
  }
  ++open_generation_;
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
  if (is_menu_host_) PostMessage(owner_, kMenuHostAction, item, reinterpret_cast<LPARAM>(menu_host_window_));
  else channel_->InvokeMethod(item == 0 ? "show" : "exit", nullptr);
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
