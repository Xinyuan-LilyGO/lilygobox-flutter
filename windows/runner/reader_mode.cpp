#include "reader_mode.h"
#include "window_messages.h"

#include <cmath>
#include <cstdlib>
#include <cstring>

struct ReaderMode::Info {
  UINT size;
  HWND view;
  DWORD flags;
  RECT* area;
  BOOL(CALLBACK* scroll)(Info*, int, int);
  BOOL(CALLBACK* translate)(const MSG*);
  LPARAM context;
};

namespace {
using Reader = void(WINAPI*)(void*);
thread_local POINT origin;
thread_local bool released;
thread_local RECT neutral_area;
constexpr DWORD kCenterCursor = 1;
constexpr DWORD kVerticalOnly = 2;
constexpr DWORD kHorizontalOnly = 4;

BOOL CALLBACK ReaderMessage(const MSG* message) {
  if (message->message != WM_MBUTTONUP || released) return FALSE;
  released = true;
  return std::abs(message->pt.x - origin.x) <= GetSystemMetrics(SM_CXDRAG) &&
         std::abs(message->pt.y - origin.y) <= GetSystemMetrics(SM_CYDRAG);
}

Reader SystemReader() {
  static const auto reader = []() -> Reader {
    const HMODULE library = LoadLibraryExW(L"comctl32.dll", nullptr,
                                           LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!library) return nullptr;
    const auto address = GetProcAddress(library, MAKEINTRESOURCEA(383));
    if (!address) {
      FreeLibrary(library);
      return nullptr;
    }
    Reader function;
    static_assert(sizeof(function) == sizeof(address));
    std::memcpy(&function, &address, sizeof(function));
    return function;
  }();
  return reader;
}
}  // namespace

bool ReaderMode::Start(HWND owner, HWND view, int session, bool horizontal,
                       POINT anchor) {
  if (!session || session_ || running_ || !SystemReader() ||
      owner != GetForegroundWindow() || !IsWindowVisible(view)) return false;
  if (!PostMessageW(owner, lilygobox::messages::kBeginReaderMode,
                    static_cast<WPARAM>(session), 0)) return false;
  owner_ = owner;
  view_ = view;
  session_ = session;
  distance_ = 0;
  horizontal_ = horizontal;
  const int radius = MulDiv(8, GetDpiForWindow(view), 96);
  anchor_ = {anchor.x - radius, anchor.y - radius, anchor.x + radius,
             anchor.y + radius};
  return true;
}

BOOL CALLBACK ReaderMode::Scroll(Info* info, int horizontal, int vertical) {
  auto* state = reinterpret_cast<ReaderMode*>(info->context);
  if (state->session_) {
    state->distance_ += state->horizontal_ ? horizontal : vertical;
  }
  return TRUE;
}

void ReaderMode::Run(int session) {
  if (!active(session)) return;
  if (!IsWindow(view_) || GetAncestor(view_, GA_ROOT) != GetForegroundWindow()) {
    Stop(session);
    return;
  }
  const auto previous_cursor = GetCursor();
  if (IsWindow(view_) && GetCapture() == view_) {
    POINT anchor{(anchor_.left + anchor_.right) / 2,
                 (anchor_.top + anchor_.bottom) / 2};
    SendMessageW(view_, WM_MBUTTONUP, 0, MAKELPARAM(anchor.x, anchor.y));
  }
  if (!active(session) || !IsWindow(view_)) {
    Stop(session);
    return;
  }
  running_ = true;
  neutral_area = anchor_;
  MapWindowPoints(view_, nullptr, reinterpret_cast<POINT*>(&neutral_area), 2);
  origin = {(neutral_area.left + neutral_area.right) / 2,
            (neutral_area.top + neutral_area.bottom) / 2};
  released = false;
  const DWORD flags = (horizontal_ ? kHorizontalOnly : kVerticalOnly) | kCenterCursor;
  Info info{sizeof(Info), view_, flags, &anchor_, Scroll,
            ReaderMessage, reinterpret_cast<LPARAM>(this)};
  reader_thread_id_ = GetCurrentThreadId();
  SystemReader()(&info);
  reader_thread_id_ = 0;
  SetCursor(previous_cursor);
  POINT point{};
  if (IsWindow(view_) && GetCursorPos(&point) && WindowFromPoint(point) == view_) {
    SendMessageW(view_, WM_SETCURSOR, reinterpret_cast<WPARAM>(view_),
                 MAKELPARAM(HTCLIENT, WM_MOUSEMOVE));
  }
  session_ = 0;
  distance_ = 0;
  running_ = false;
}

void ReaderMode::Stop(int session) {
  if (!session_ || (session && !active(session))) return;
  session_ = 0;
  distance_ = 0;
  if (running_) {
    // DoReaderMode runs a nested message loop.  Use the owner first because
    // the child Flutter view can already be in WM_DESTROY while the reader is
    // still unwinding.
    const HWND target = IsWindow(owner_) ? owner_ : view_;
    if (!IsWindow(target) ||
        !PostMessageW(target, WM_KEYDOWN, VK_ESCAPE, 0)) {
      const auto thread_id = reader_thread_id_;
      if (thread_id != 0) {
        PostThreadMessageW(thread_id, WM_KEYDOWN, VK_ESCAPE, 0);
      }
    }
  }
}
