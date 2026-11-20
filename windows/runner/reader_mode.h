#ifndef RUNNER_READER_MODE_H_
#define RUNNER_READER_MODE_H_

#include <windows.h>

#include <cstdint>
#include <utility>

class ReaderMode {
 public:
  bool Start(HWND owner, HWND view, int session, bool horizontal, POINT anchor);
  void Run(int session);
  void Stop(int session);
  bool active(int session) const { return session != 0 && session == session_; }
  double Take() { return std::exchange(distance_, 0.0); }

 private:
  struct Info;
  static BOOL CALLBACK Scroll(Info* info, int horizontal, int vertical);
  HWND view_ = nullptr;
  RECT anchor_{};
  int session_ = 0;
  bool horizontal_ = false;
  bool running_ = false;
  double distance_ = 0;
};

#endif
