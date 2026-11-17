#include "../../windows/runner/window_snap_geometry.h"

#include <dwmapi.h>
#include <cassert>
#include <iostream>

namespace {
LRESULT CALLBACK HiddenWindowProc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_NCCALCSIZE) return 0;
  return DefWindowProcW(window, message, wp, lp);
}
}  // namespace

int main() {
  // 独立隐藏窗口不操作用户窗口，复现尺寸变化后 normal 与当前尺寸相同的情况。
  const auto instance = GetModuleHandleW(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = HiddenWindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"LilygoBoxSnapGeometryTest";
  assert(RegisterClassW(&window_class));
  const HWND window = CreateWindowExW(0, window_class.lpszClassName, L"",
      WS_OVERLAPPEDWINDOW, 200, 150, 800, 600, nullptr, nullptr, instance, nullptr);
  assert(window);
  MONITORINFO monitor{sizeof(MONITORINFO)};
  assert(GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                         &monitor));
  const RECT work = monitor.rcWork;
  const LONG half = (work.right - work.left) / 2;
  assert(SetWindowPos(window, nullptr, work.left, work.top, half,
                       work.bottom - work.top,
                       SWP_NOACTIVATE | SWP_NOZORDER));
  RECT bounds{};
  assert(GetWindowRect(window, &bounds));
  WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
  assert(GetWindowPlacement(window, &placement));
  assert(bounds.right - bounds.left ==
         placement.rcNormalPosition.right - placement.rcNormalPosition.left);
  assert(bounds.bottom - bounds.top ==
         placement.rcNormalPosition.bottom - placement.rcNormalPosition.top);
  assert(lilygobox::HasSnappedGeometry(bounds, work, 2));
  const auto arranged = GetProcAddress(GetModuleHandleW(L"user32.dll"),
                                      "IsWindowArranged");
  std::cout << "IsWindowArranged available=" << (arranged != nullptr)
            << "; normalMatchesCurrent=true; halfScreenDetected=true\n";
  assert(DestroyWindow(window));
  assert(UnregisterClassW(window_class.lpszClassName, instance));
}
