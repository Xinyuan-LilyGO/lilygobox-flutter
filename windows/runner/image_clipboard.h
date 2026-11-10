#ifndef RUNNER_IMAGE_CLIPBOARD_H_
#define RUNNER_IMAGE_CLIPBOARD_H_

#include <flutter/encodable_value.h>
#include <flutter/method_result.h>
#include <windows.h>

#include <memory>

// 在窗口 UI 线程读写已实体化的 PNG/DIB，避免依赖延迟渲染的数据对象。
void ReadClipboardImage(HWND owner,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
void WriteClipboardImage(HWND owner, const flutter::EncodableValue* arguments,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

#endif
