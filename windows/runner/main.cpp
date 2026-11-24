#include <flutter/dart_project.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <ole2.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"
#include "tray_icon.h"

namespace {
int RunSpeechWorker() {
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint("speechWorkerMain");
  flutter::FlutterEngine engine(project);
  if (!engine.Run()) return EXIT_FAILURE;

  MSG message;
  while (GetMessage(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
  return EXIT_FAILURE;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const auto launch_arguments = GetCommandLineArguments();
  for (const auto& argument : launch_arguments) {
    if (argument == "--lilygobox-speech-worker") return RunSpeechWorker();
    const std::string prefix = "--lilygobox-tray-host=";
    if (argument.rfind(prefix, 0) == 0) {
      const HWND owner = reinterpret_cast<HWND>(static_cast<uintptr_t>(
          _strtoui64(argument.c_str() + prefix.size(), nullptr, 10)));
      if (!IsWindow(owner)) return EXIT_FAILURE;
      const HRESULT initialized = OleInitialize(nullptr);
      if (FAILED(initialized)) return EXIT_FAILURE;
      flutter::DartProject menu_project(L"data");
      const int result = TrayIcon::RunMenuHost(menu_project, owner);
      OleUninitialize();
      return result;
    }
  }
  // 重复启动只唤起已有主窗口，不重复加载 Flutter、配置与设备连接。
  lilygobox::SingleInstance single_instance;
  if (!single_instance.AcquireOrActivate()) return EXIT_SUCCESS;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // 图片剪贴板使用 OleGetClipboard/OleSetClipboard，需初始化完整 OLE。
  // OleInitialize 同时初始化 STA COM，不能只调用 CoInitializeEx。
  const HRESULT ole_result = ::OleInitialize(nullptr);
  if (FAILED(ole_result)) return EXIT_FAILURE;

  flutter::DartProject project(L"data");
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"LilygoBox", origin, size)) {
    ::OleUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::OleUninitialize();
  return EXIT_SUCCESS;
}
