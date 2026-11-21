#include "../../windows/runner/reader_mode.h"
#include "../../windows/runner/window_messages.h"

#include <atomic>
#include <cstdio>
#include <thread>

namespace {
ReaderMode reader;
std::atomic<int> samples{0};
std::atomic<double> distance{0};
constexpr UINT kSample = WM_APP + 10;
int session = 0;

HCURSOR VisibleCursor() {
  CURSORINFO info{sizeof(info)};
  return GetCursorInfo(&info) && (info.flags & CURSOR_SHOWING) ? info.hCursor : nullptr;
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM key, LPARAM data) {
  if (message == WM_MBUTTONDOWN) {
    POINT client{static_cast<SHORT>(LOWORD(data)), static_cast<SHORT>(HIWORD(data))};
    SetCapture(window);
    if (!reader.Start(window, window, session, false, client)) {
      std::printf("start rejected: foreground=%p, test=%p\n", GetForegroundWindow(), window);
      PostQuitMessage(1);
    }
    return 0;
  }
  if (message == WM_MBUTTONUP && GetCapture() == window) ReleaseCapture();
  if (message == lilygobox::messages::kBeginReaderMode) {
    const auto began = GetTickCount64();
    reader.Run(static_cast<int>(key));
    std::printf("modal %llu ms\n", GetTickCount64() - began);
    PostQuitMessage(0);
    return 0;
  }
  if (message == kSample) {
    const double change = reader.Take();
    if (change != 0) ++samples;
    distance = distance.load() + change;
    return 0;
  }
  if (message == WM_SETCURSOR && LOWORD(data) == HTCLIENT) return TRUE;
  return DefWindowProcW(window, message, key, data);
}
}

int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const auto instance = GetModuleHandleW(nullptr);
  WNDCLASSW type{};
  type.lpfnWndProc = WindowProc;
  type.hCursor = LoadCursorW(nullptr, IDC_IBEAM);
  type.hInstance = instance;
  type.lpszClassName = L"LilygoBoxNativeReaderTest";
  if (!RegisterClassW(&type)) return 1;
  const HWND previous = GetForegroundWindow();
  POINT original{};
  GetCursorPos(&original);
  const HWND window = CreateWindowExW(WS_EX_TOPMOST, type.lpszClassName, L"Reader test",
      WS_POPUP | WS_VISIBLE, 200, 160, 640, 480, nullptr, nullptr, instance, nullptr);
  int failures = 0;
  const DWORD thread = GetCurrentThreadId();
  for (const UINT cancel : {UINT(WM_KEYDOWN), UINT(WM_LBUTTONDOWN), UINT(WM_MBUTTONUP)}) {
    POINT anchor{300, 100};
    ClientToScreen(window, &anchor);
    if (WindowFromPoint(anchor) != window) { std::puts("window not visible"); ++failures; break; }
    SetCursorPos(anchor.x, anchor.y);
    SetForegroundWindow(window);
    SetFocus(window);
    SetCursor(type.hCursor);
    session = static_cast<int>(cancel);
    samples = 0;
    distance = 0;
    std::atomic<bool> returned{false};
    std::atomic<bool> rescued{false};
    HCURSOR before{}, neutral{}, neutral_after_idle{}, up{}, down{};
    std::thread input([&, anchor, cancel]() {
      Sleep(100);
      before = VisibleCursor();
      if (WindowFromPoint(anchor) == window) {
        mouse_event(MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, 0);
      }
      Sleep(50);
      POINT located{};
      GetCursorPos(&located);
      std::printf("cursor %ld %ld expected %ld %ld\n", located.x, located.y, anchor.x, anchor.y);
      if (cancel != WM_MBUTTONUP) mouse_event(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0);
      Sleep(80);
      neutral = VisibleCursor();
      for (int poll = 0; poll < 35 && !returned; ++poll) {
        PostMessageW(window, kSample, 0, 0);
        Sleep(16);
      }
      neutral_after_idle = VisibleCursor();
      SetCursorPos(anchor.x, anchor.y - 70);
      Sleep(120);
      up = VisibleCursor();
      SetCursorPos(anchor.x, anchor.y + 160);
      for (int poll = 0; poll < 35 && !returned; ++poll) {
        PostMessageW(window, kSample, 0, 0);
        Sleep(16);
      }
      down = VisibleCursor();
      PostMessageW(window, cancel, cancel == WM_KEYDOWN ? VK_ESCAPE : 0,
                   MAKELPARAM(300,260));
      if (cancel == WM_MBUTTONUP) mouse_event(MOUSEEVENTF_MIDDLEUP, 0, 0, 0, 0);
      for (int poll = 0; poll < 20 && !returned; ++poll) Sleep(15);
      if (!returned) {
        rescued = true;
        PostThreadMessageW(thread, WM_KEYDOWN, VK_ESCAPE, 0);
        PostThreadMessageW(thread, WM_QUIT, 0, 0);
      }
    });
    MSG event{};
    while (GetMessageW(&event, nullptr, 0, 0) > 0) {
      TranslateMessage(&event);
      DispatchMessageW(&event);
    }
    returned = true;
    input.join();
    const bool stopped = !rescued && !reader.active(session);
    const auto after = VisibleCursor();
    std::printf("cursors before=%p neutral=%p idle=%p up=%p down=%p after=%p\n",
                before, neutral, neutral_after_idle, up, down, after);
    if (!before || !neutral || !up || !down || neutral == before ||
        neutral_after_idle != neutral || up == before || down == before ||
        neutral == up || neutral == down ||
        up == down || after != before) ++failures;
    std::printf("cancel=%u samples=%d distance=%.0f stopped=%d\n", cancel,
                samples.load(), distance.load(), stopped);
    if (distance.load() <= 0 || !stopped || reader.Take() != 0) ++failures;
    while (PeekMessageW(&event, nullptr, 0, 0, PM_REMOVE)) {}
  }
  DestroyWindow(window);
  UnregisterClassW(type.lpszClassName, instance);
  SetCursorPos(original.x, original.y);
  if (previous) SetForegroundWindow(previous);
  return failures;
}
