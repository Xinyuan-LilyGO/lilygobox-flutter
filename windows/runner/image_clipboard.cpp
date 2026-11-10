#include "image_clipboard.h"

#include <cstring>
#include <cstdint>
#include <vector>

namespace {
constexpr size_t kMaxBytes = 64 * 1024 * 1024;

class ClipboardLock {
 public:
  explicit ClipboardLock(HWND owner) : opened_(OpenClipboard(owner) != FALSE) {}
  ~ClipboardLock() { if (opened_) CloseClipboard(); }
  bool opened() const { return opened_; }
 private:
  bool opened_;
};

HGLOBAL CopyToGlobal(const std::vector<uint8_t>& bytes) {
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (!memory) return nullptr;
  void* target = GlobalLock(memory);
  if (!target) { GlobalFree(memory); return nullptr; }
  std::memcpy(target, bytes.data(), bytes.size());
  GlobalUnlock(memory);
  return memory;
}

std::vector<uint8_t> ReadBytes(UINT format) {
  HANDLE data = GetClipboardData(format);
  if (!data) return {};
  const SIZE_T length = GlobalSize(data);
  if (length == 0 || length > kMaxBytes) return {};
  const auto* bytes = static_cast<const uint8_t*>(GlobalLock(data));
  if (!bytes) return {};
  std::vector<uint8_t> result(bytes, bytes + length);
  GlobalUnlock(data);
  return result;
}
}  // namespace

void ReadClipboardImage(HWND owner,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  ClipboardLock clipboard(owner);
  if (!clipboard.opened()) {
    result->Error("clipboard_busy", "Windows clipboard is busy");
    return;
  }
  auto png = ReadBytes(RegisterClipboardFormatW(L"PNG"));
  if (!png.empty()) { result->Success(flutter::EncodableValue(png)); return; }
  auto dib = ReadBytes(CF_DIBV5);
  if (dib.empty()) dib = ReadBytes(CF_DIB);
  if (dib.size() < sizeof(BITMAPINFOHEADER)) { result->Success(); return; }
  BITMAPINFOHEADER info{};
  std::memcpy(&info, dib.data(), sizeof(info));
  if (info.biSize < sizeof(info) || info.biSize > dib.size() ||
      info.biPlanes != 1 || info.biBitCount > 32 || info.biBitCount == 0) {
    result->Error("invalid_image", "Invalid clipboard bitmap header");
    return;
  }
  size_t offset = info.biSize;
  if (info.biSize == sizeof(info) && info.biCompression == BI_BITFIELDS) offset += 12;
  const size_t colors = info.biClrUsed != 0 ? info.biClrUsed :
      (info.biBitCount <= 8 ? (size_t{1} << info.biBitCount) : 0);
  offset += colors * sizeof(RGBQUAD);
  if (offset > dib.size()) {
    result->Error("invalid_image", "Invalid clipboard bitmap palette");
    return;
  }
  BITMAPFILEHEADER file{};
  file.bfType = 0x4d42;
  file.bfSize = static_cast<DWORD>(sizeof(file) + dib.size());
  file.bfOffBits = static_cast<DWORD>(sizeof(file) + offset);
  std::vector<uint8_t> bmp(sizeof(file) + dib.size());
  std::memcpy(bmp.data(), &file, sizeof(file));
  std::memcpy(bmp.data() + sizeof(file), dib.data(), dib.size());
  result->Success(flutter::EncodableValue(bmp));
}

void WriteClipboardImage(HWND owner, const flutter::EncodableValue* arguments,
                         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* values = arguments ? std::get_if<flutter::EncodableMap>(arguments) : nullptr;
  if (!values) { result->Error("invalid_image", "Image arguments required"); return; }
  const auto field = [values](const char* key) -> const flutter::EncodableValue* {
    auto found = values->find(flutter::EncodableValue(key));
    return found == values->end() ? nullptr : &found->second;
  };
  const auto* png_value = field("png");
  const auto* rgba_value = field("rgba");
  const auto* width_value = field("width");
  const auto* height_value = field("height");
  const auto* png = png_value ? std::get_if<std::vector<uint8_t>>(png_value) : nullptr;
  const auto* rgba = rgba_value ? std::get_if<std::vector<uint8_t>>(rgba_value) : nullptr;
  const auto* width = width_value ? std::get_if<int32_t>(width_value) : nullptr;
  const auto* height = height_value ? std::get_if<int32_t>(height_value) : nullptr;
  if (!png || !rgba || !width || !height || *width <= 0 || *height <= 0 ||
      png->empty() || png->size() > kMaxBytes ||
      static_cast<uint64_t>(*width) * static_cast<uint64_t>(*height) * 4 > kMaxBytes ||
      rgba->size() != static_cast<size_t>(*width) * static_cast<size_t>(*height) * 4) {
    result->Error("invalid_image", "Invalid clipboard image dimensions or bytes"); return;
  }
  BITMAPV5HEADER header{};
  header.bV5Size = sizeof(header);
  header.bV5Width = *width;
  header.bV5Height = -*height;
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5SizeImage = static_cast<DWORD>(rgba->size());
  header.bV5RedMask = 0x00ff0000;
  header.bV5GreenMask = 0x0000ff00;
  header.bV5BlueMask = 0x000000ff;
  header.bV5AlphaMask = 0xff000000;
  header.bV5CSType = LCS_sRGB;
  std::vector<uint8_t> v5(sizeof(header) + rgba->size());
  std::memcpy(v5.data(), &header, sizeof(header));
  for (size_t i = 0; i < rgba->size(); i += 4) {
    v5[sizeof(header) + i] = (*rgba)[i + 2];
    v5[sizeof(header) + i + 1] = (*rgba)[i + 1];
    v5[sizeof(header) + i + 2] = (*rgba)[i];
    v5[sizeof(header) + i + 3] = (*rgba)[i + 3];
  }
  BITMAPINFOHEADER legacy{};
  legacy.biSize = sizeof(legacy);
  legacy.biWidth = *width;
  legacy.biHeight = -*height;
  legacy.biPlanes = 1;
  legacy.biBitCount = 32;
  legacy.biCompression = BI_RGB;
  legacy.biSizeImage = static_cast<DWORD>(rgba->size());
  std::vector<uint8_t> dib(sizeof(legacy) + rgba->size());
  std::memcpy(dib.data(), &legacy, sizeof(legacy));
  std::memcpy(dib.data() + sizeof(legacy), v5.data() + sizeof(header), rgba->size());
  const UINT formats[] = {RegisterClipboardFormatW(L"PNG"), CF_DIBV5, CF_DIB};
  HGLOBAL blocks[] = {CopyToGlobal(*png), CopyToGlobal(v5), CopyToGlobal(dib)};
  bool success = blocks[0] && blocks[1] && blocks[2];
  {
    ClipboardLock clipboard(owner);
    if (!clipboard.opened()) {
      for (auto block : blocks) if (block) GlobalFree(block);
      result->Error("clipboard_busy", "Windows clipboard is busy"); return;
    }
    if (success) success = EmptyClipboard() != FALSE;
    for (size_t i = 0; success && i < 3; ++i) {
      success = SetClipboardData(formats[i], blocks[i]) != nullptr;
      if (success) blocks[i] = nullptr;  // Ownership transfers to Windows.
    }
  }
  for (auto block : blocks) if (block) GlobalFree(block);
  if (success) result->Success();
  else result->Error("clipboard_write_failed", "Could not publish Windows clipboard image");
}
