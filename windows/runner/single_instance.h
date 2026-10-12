/*
 * @Description: 限制当前 Windows 会话只运行一个主应用，重复启动时唤起已有窗口。
 * @Author: LILYGO_L
 * @Date: 2026-10-12 00:00:00
 * @LastEditTime: 2026-10-12 00:00:00
 * @License: GPL 3.0
 */
#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

namespace lilygobox {
inline constexpr wchar_t kInstanceName[] =
    L"Local\\LilygoBox.Main.5D67190D-7E46-4EA8-A99B-9C2E25668A0D";
inline constexpr wchar_t kWindowMarker[] =
    L"LilygoBox.MainWindow.5D67190D-7E46-4EA8-A99B-9C2E25668A0D";

inline UINT ActivateWindowMessage() {
  return RegisterWindowMessageW(kWindowMarker);
}

// 通过应用专属属性查找主窗口，避免误命中其他 Flutter 程序或托盘菜单。
inline BOOL CALLBACK FindMainWindow(HWND window, LPARAM result) {
  if (GetPropW(window, kWindowMarker)) {
    *reinterpret_cast<HWND*>(result) = window;
    return FALSE;
  }
  return TRUE;
}

class SingleInstance {
 public:
  SingleInstance() = default;
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  ~SingleInstance() {
    if (mutex_) {
      if (owns_mutex_) ReleaseMutex(mutex_);
      CloseHandle(mutex_);
    }
  }

  // 互斥量覆盖整个主程序生命周期；等待首个窗口就绪，处理同时双击启动。
  bool AcquireOrActivate() {
    mutex_ = CreateMutexW(nullptr, TRUE, kInstanceName);
    const DWORD error = GetLastError();
    if (!mutex_) {
      MessageBoxW(nullptr, L"Unable to initialize the application instance.",
                  L"LilygoBox", MB_OK | MB_ICONERROR);
      return false;
    }
    if (error != ERROR_ALREADY_EXISTS) {
      owns_mutex_ = true;
      return true;
    }
    for (int attempt = 0; attempt < 100; ++attempt) {
      // 原实例在启动期间退出或崩溃时，当前进程接管，不留下失效锁。
      const DWORD wait = WaitForSingleObject(mutex_, 50);
      if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
        owns_mutex_ = true;
        return true;
      }
      if (wait == WAIT_FAILED) return false;
      HWND window = nullptr;
      EnumWindows(FindMainWindow, reinterpret_cast<LPARAM>(&window));
      if (window) {
        DWORD process_id = 0;
        GetWindowThreadProcessId(window, &process_id);
        AllowSetForegroundWindow(process_id);
        PostMessageW(window, ActivateWindowMessage(), 0, 0);
        return false;
      }
    }
    // 原实例仍在启动时也不创建第二个 Flutter 引擎。
    return false;
  }

 private:
  HANDLE mutex_ = nullptr;
  bool owns_mutex_ = false;
};
}  // namespace lilygobox

#endif  // RUNNER_SINGLE_INSTANCE_H_
