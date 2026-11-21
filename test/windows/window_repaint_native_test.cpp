#include "../../windows/runner/win32_window.h"

#include <cassert>

int main() {
  assert(SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2));
  Win32Window host;
  assert(host.Create(L"LilygoBox repaint test", {10, 10}, {640, 480}));
  const HWND window = host.GetHandle();
  const auto original_brush = SetClassLongPtrW(
      window, GCLP_HBRBACKGROUND,
      reinterpret_cast<LONG_PTR>(GetStockObject(WHITE_BRUSH)));

  const HDC dc = CreateCompatibleDC(nullptr);
  assert(dc);
  const HBITMAP bitmap = CreateBitmap(16, 16, 1, 1, nullptr);
  assert(bitmap);
  const auto original_bitmap = SelectObject(dc, bitmap);
  assert(original_bitmap);
  const auto erase_background = [&] {
    assert(SendMessageW(window, WM_ERASEBKGND,
                        reinterpret_cast<WPARAM>(dc), 0) == TRUE);
  };

  assert(PatBlt(dc, 0, 0, 16, 16, BLACKNESS));
  erase_background();
  assert(GetPixel(dc, 8, 8) == RGB(255, 255, 255));

  const HWND child = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE,
                                    0, 0, 1, 1, window, nullptr,
                                    GetModuleHandleW(nullptr), nullptr);
  assert(child);
  host.SetChildContent(child);

  const SIZE sizes[] = {{750, 535}, {960, 740}, {604, 420}};
  for (const auto& size : sizes) {
    assert(SetWindowPos(window, nullptr, 0, 0, size.cx, size.cy,
                        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE));
    RECT child_rect{};
    assert(GetClientRect(child, &child_rect));
    const RECT host_rect = host.GetClientArea();
    assert(EqualRect(&child_rect, &host_rect));

    assert(PatBlt(dc, 0, 0, 16, 16, BLACKNESS));
    erase_background();
    assert(GetPixel(dc, 8, 8) == RGB(0, 0, 0));
  }

  SelectObject(dc, original_bitmap);
  DeleteObject(bitmap);
  DeleteDC(dc);
  SetClassLongPtrW(window, GCLP_HBRBACKGROUND, original_brush);
}
