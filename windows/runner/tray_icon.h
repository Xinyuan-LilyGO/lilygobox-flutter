/*
 * @Description: Windows 托盘图标及独立右键菜单，支持窗口隐藏后显示和退出。
 */
#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <memory>
#include <string>

class TrayIcon {
 public:
  TrayIcon(HWND owner, flutter::BinaryMessenger* messenger,
           const flutter::DartProject& project);
  ~TrayIcon();
  static int RunMenuHost(const flutter::DartProject& project, HWND owner);
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool EnsureIcon();
  bool EnsureMenuProcess();
  bool SendMenuCommand(const std::string& command);
  static LRESULT CALLBACK HostProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);
  bool EnsureMenu();
  void ShowMenu(int duration_ms);
  void TickFade();
  void CheckMenuDismissal();
  void OpenMenu();
  void PrepareMenu();
  void PresentMenu();
  void DismissMenu();
  void ResizeMenu();
  void Activate(int item);
  void StartMouseWatch();
  void StopMouseWatch();
  bool ContainsCardPoint(POINT point) const;
  static LRESULT CALLBACK MouseProc(int code, WPARAM wparam, LPARAM lparam);
  static TrayIcon* mouse_owner_;
  static LRESULT CALLBACK MenuProc(HWND hwnd, UINT message,
                                   WPARAM wparam, LPARAM lparam);

  HWND owner_;
  HWND menu_ = nullptr;
  HWND menu_foreground_ = nullptr;
  NOTIFYICONDATAW icon_{};
  UINT taskbar_created_;
  bool configured_ = false;
  bool warmup_scheduled_ = false;
  bool menu_warming_ = false;
  bool menu_ready_ = false;
  bool menu_requested_ = false;
  UINT_PTR open_generation_ = 0;
  bool is_menu_host_ = false;
  bool menu_host_painted_ = false;
  HWND menu_host_window_ = nullptr;
  HANDLE menu_process_ = nullptr;
  HANDLE menu_job_ = nullptr;
  DWORD menu_process_id_ = 0;
  bool menu_presented_ = false;
  int64_t request_id_ = 0;
  HHOOK mouse_hook_ = nullptr;
  UINT swallow_mouse_up_ = 0;
  ULONGLONG fade_started_ = 0;
  int fade_duration_ms_ = 150;
  POINT menu_position_{};
  float scale_ = 1.0f;
  flutter::DartProject project_;
  flutter::EncodableMap appearance_;
  std::unique_ptr<flutter::FlutterViewController> menu_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> menu_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
