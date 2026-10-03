/*
 * @Description: Windows 托盘图标及独立右键菜单，支持窗口隐藏后显示和退出。
 * @Author: LILYGO_L
 * @Date: 2026-10-04 00:20:00
 * @LastEditTime: 2026-10-04 01:57:39
 * @License: GPL 3.0
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
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool EnsureIcon();
  bool EnsureMenu();
  void PrepareMenu();
  void ShowMenu(int duration_ms);
  void TickFade();
  void OpenMenu();
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
  NOTIFYICONDATAW icon_{};
  UINT taskbar_created_;
  bool configured_ = false;
  bool menu_ready_ = false;
  bool menu_requested_ = false;
  bool warmup_scheduled_ = false;
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
