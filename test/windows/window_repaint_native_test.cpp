#include "../../windows/runner/win32_window.h"

#include <cassert>
#include <cstdlib>

namespace {

struct ResizeObservation {
  HWND host;
  RECT host_bounds{};
  int size_messages = 0;
  UINT position_flags = 0;
};

LRESULT CALLBACK ObserveChildSize(HWND child, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  auto* observation = reinterpret_cast<ResizeObservation*>(
      GetWindowLongPtrW(child, GWLP_USERDATA));
  if (observation) {
    if (message == WM_SIZE) {
      assert(GetWindowRect(observation->host, &observation->host_bounds));
      ++observation->size_messages;
    } else if (message == WM_WINDOWPOSCHANGING) {
      observation->position_flags = reinterpret_cast<WINDOWPOS*>(lparam)->flags;
    }
  }
  return DefWindowProcW(child, message, wparam, lparam);
}

}  // namespace

int main() {
  _set_error_mode(_OUT_TO_STDERR);
  assert(SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2));
  Win32Window host;
  assert(host.Create(L"LilygoBox repaint test", {10, 10}, {640, 480}));
  const HWND window = host.GetHandle();
  assert((GetWindowLongPtrW(window, GWL_STYLE) & WS_CLIPCHILDREN) != 0);
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

  WNDCLASSW child_class{};
  child_class.style = CS_HREDRAW | CS_VREDRAW;
  child_class.lpfnWndProc = ObserveChildSize;
  child_class.hInstance = GetModuleHandleW(nullptr);
  child_class.lpszClassName = L"LilygoBoxResizeTestChild";
  assert(RegisterClassW(&child_class));
  const HWND child = CreateWindowExW(
      0, child_class.lpszClassName, L"", WS_CHILD | WS_VISIBLE, 0, 0, 1, 1,
      window, nullptr, child_class.hInstance, nullptr);
  assert(child);
  host.SetChildContent(child);
  ResizeObservation observation{window};
  SetWindowLongPtrW(child, GWLP_USERDATA,
                    reinterpret_cast<LONG_PTR>(&observation));

  WINDOWPOS resize{};
  resize.hwnd = window;
  SendMessageW(window, WM_WINDOWPOSCHANGING, 0,
               reinterpret_cast<LPARAM>(&resize));
  assert((resize.flags & SWP_NOCOPYBITS) != 0);
  assert((resize.flags & SWP_DEFERERASE) != 0);

  WINDOWPOS move{};
  move.hwnd = window;
  move.flags = SWP_NOSIZE;
  SendMessageW(window, WM_WINDOWPOSCHANGING, 0,
               reinterpret_cast<LPARAM>(&move));
  assert((move.flags & SWP_NOCOPYBITS) == 0);
  assert((move.flags & SWP_DEFERERASE) == 0);

  RECT frame{};
  assert(GetWindowRect(window, &frame));
  const auto resize_window = [&](const RECT& bounds) {
    assert(SetWindowPos(window, nullptr, bounds.left, bounds.top,
                        bounds.right - bounds.left, bounds.bottom - bounds.top,
                        SWP_NOZORDER | SWP_NOACTIVATE));
  };
  const auto expect_client_covered = [&] {
    RECT child_rect{};
    assert(GetClientRect(child, &child_rect));
    const RECT host_rect = host.GetClientArea();
    assert(EqualRect(&child_rect, &host_rect));
    assert(PatBlt(dc, 0, 0, 16, 16, BLACKNESS));
    erase_background();
    assert(GetPixel(dc, 8, 8) == RGB(0, 0, 0));
  };
  const struct {
    WPARAM edge;
    RECT bounds;
    bool prepares_child;
  } resizes[] = {
      {WMSZ_LEFT, {frame.left - 90, frame.top, frame.right, frame.bottom}, true},
      {WMSZ_RIGHT, {frame.left, frame.top, frame.right + 120, frame.bottom},
       true},
      {WMSZ_TOP, {frame.left, frame.top - 80, frame.right, frame.bottom}, true},
      {WMSZ_BOTTOM, {frame.left, frame.top, frame.right, frame.bottom + 100},
       true},
      {WMSZ_TOPLEFT,
       {frame.left - 40, frame.top - 30, frame.right, frame.bottom}, true},
      {WMSZ_TOPRIGHT,
       {frame.left, frame.top - 30, frame.right + 40, frame.bottom}, true},
      {WMSZ_BOTTOMLEFT,
       {frame.left - 40, frame.top, frame.right, frame.bottom + 30}, true},
      {WMSZ_BOTTOMRIGHT,
       {frame.left, frame.top, frame.right + 40, frame.bottom + 30}, true},
      {WMSZ_TOPLEFT,
       {frame.left + 20, frame.top + 20, frame.right, frame.bottom}, false},
      {WMSZ_TOPLEFT,
       {frame.left + 20, frame.top - 20, frame.right, frame.bottom}, false},
  };
  for (const auto& resize_case : resizes) {
    SendMessageW(window, WM_ENTERSIZEMOVE, 0, 0);
    RECT bounds = resize_case.bounds;
    SendMessageW(window, WM_SIZING, resize_case.edge,
                 reinterpret_cast<LPARAM>(&bounds));
    WINDOWPOS live_position{};
    live_position.hwnd = window;
    live_position.cx = frame.right - frame.left;
    live_position.cy = frame.bottom - frame.top;
    live_position.flags = SWP_NOCOPYBITS;
    SendMessageW(window, WM_WINDOWPOSCHANGING, 0,
                 reinterpret_cast<LPARAM>(&live_position));
    assert((live_position.flags & SWP_NOCOPYBITS) == 0);
    assert((live_position.flags & SWP_DEFERERASE) != 0);
    observation.size_messages = 0;
    resize_window(bounds);
    assert(observation.size_messages == 1);
    assert((observation.position_flags & SWP_NOREDRAW) != 0);
    assert((observation.position_flags & SWP_NOCOPYBITS) == 0);
    assert(EqualRect(&observation.host_bounds,
                     resize_case.prepares_child ? &frame : &bounds));
    expect_client_covered();
    SendMessageW(window, WM_EXITSIZEMOVE, 0, 0);
    observation.size_messages = 0;
    resize_window(frame);
    assert(observation.size_messages == 1);
    assert((observation.position_flags & SWP_NOREDRAW) == 0);
    assert((observation.position_flags & SWP_NOCOPYBITS) != 0);
    assert(EqualRect(&observation.host_bounds, &frame));
    expect_client_covered();
  }

  SetWindowLongPtrW(child, GWLP_USERDATA, 0);
  SelectObject(dc, original_bitmap);
  DeleteObject(bitmap);
  DeleteDC(dc);
  SetClassLongPtrW(window, GCLP_HBRBACKGROUND, original_brush);
}
