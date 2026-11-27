#define LILYGO_AEC3_EXPORTS
#include "lilygo_aec3.h"

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#ifdef _WIN32
#  ifndef NOMINMAX
#    define NOMINMAX
#  endif
#  include <windows.h>
#endif

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_WAV
#include "miniaudio.h"

#include "api/echo_canceller3_config.h"
#include "api/echo_canceller3_factory.h"
#include "audio_processing/audio_buffer.h"
#include "audio_processing/audio_frame.h"
#include "audio_processing/high_pass_filter.h"
#include "audio_processing/include/audio_processing.h"

namespace {

class PcmRingBuffer {
 public:
  explicit PcmRingBuffer(size_t capacity_samples)
      : buffer_(capacity_samples, 0), capacity_(capacity_samples) {}

  void Push(const int16_t* data, size_t count) {
    if (count == 0 || capacity_ == 0) return;
    std::lock_guard<std::mutex> lock(mutex_);
    if (count >= capacity_) {
      data += (count - capacity_);
      count = capacity_;
      read_pos_ = 0;
      write_pos_ = 0;
      size_ = 0;
    }
    while (size_ + count > capacity_) {
      const size_t drop = (size_ + count) - capacity_;
      read_pos_ = (read_pos_ + drop) % capacity_;
      size_ -= drop;
    }
    const size_t first = std::min(count, capacity_ - write_pos_);
    std::memcpy(buffer_.data() + write_pos_, data, first * sizeof(int16_t));
    if (count > first) {
      std::memcpy(buffer_.data(), data + first, (count - first) * sizeof(int16_t));
    }
    write_pos_ = (write_pos_ + count) % capacity_;
    size_ += count;
  }

  size_t Pop(int16_t* out, size_t max_count) {
    std::lock_guard<std::mutex> lock(mutex_);
    const size_t to_read = std::min(max_count, size_);
    if (to_read == 0) return 0;
    const size_t first = std::min(to_read, capacity_ - read_pos_);
    std::memcpy(out, buffer_.data() + read_pos_, first * sizeof(int16_t));
    if (to_read > first) {
      std::memcpy(out + first, buffer_.data(), (to_read - first) * sizeof(int16_t));
    }
    read_pos_ = (read_pos_ + to_read) % capacity_;
    size_ -= to_read;
    return to_read;
  }

  size_t PopExactOrZero(int16_t* out, size_t count) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (size_ < count) {
      std::fill_n(out, count, static_cast<int16_t>(0));
      return 0;
    }
    const size_t first = std::min(count, capacity_ - read_pos_);
    std::memcpy(out, buffer_.data() + read_pos_, first * sizeof(int16_t));
    if (count > first) {
      std::memcpy(out + first, buffer_.data(), (count - first) * sizeof(int16_t));
    }
    read_pos_ = (read_pos_ + count) % capacity_;
    size_ -= count;
    return count;
  }

 private:
  std::mutex mutex_;
  std::vector<int16_t> buffer_;
  size_t capacity_ = 0;
  size_t read_pos_ = 0;
  size_t write_pos_ = 0;
  size_t size_ = 0;
};

struct Aec3Instance {
  int32_t sample_rate_hz = 16000;
  int32_t num_channels = 1;
  int32_t samples_per_channel = 160;
  std::unique_ptr<webrtc::EchoControl> echo_control;
  std::unique_ptr<webrtc::HighPassFilter> hp_filter;
  std::unique_ptr<webrtc::AudioBuffer> ref_buffer;
  std::unique_ptr<webrtc::AudioBuffer> cap_buffer;
  webrtc::AudioFrame ref_frame;
  webrtc::AudioFrame cap_frame;
  std::mutex mutex;
};

struct LiveCaptureSession {
  Aec3Instance* aec = nullptr;
  ma_context context{};
  ma_device loopback_device{};
  ma_device capture_device{};
  bool has_context = false;
  bool has_loopback = false;
  bool has_capture = false;
  std::atomic<bool> failed{false};

  int32_t frame_samples = 160;
  PcmRingBuffer render_ring;
  PcmRingBuffer output_ring;
  std::vector<int16_t> mic_accum;
  std::vector<int16_t> temp_ref;
  std::vector<int16_t> temp_out;

  explicit LiveCaptureSession(int32_t sample_rate_hz)
      : frame_samples(sample_rate_hz / 100),
        render_ring(static_cast<size_t>(sample_rate_hz) * 2),
        output_ring(static_cast<size_t>(sample_rate_hz) * 4),
        temp_ref(static_cast<size_t>(frame_samples), 0),
        temp_out(static_cast<size_t>(frame_samples), 0) {}
};

void OnLoopbackData(ma_device* device, void* /*output*/, const void* input, ma_uint32 frame_count) {
  auto* session = static_cast<LiveCaptureSession*>(device->pUserData);
  if (!session || !input || frame_count == 0) return;
  session->render_ring.Push(static_cast<const int16_t*>(input), frame_count);
}

void OnCaptureData(ma_device* device, void* /*output*/, const void* input, ma_uint32 frame_count) {
  auto* session = static_cast<LiveCaptureSession*>(device->pUserData);
  if (!session || !session->aec || !input || frame_count == 0) return;

  const auto* samples = static_cast<const int16_t*>(input);
  session->mic_accum.insert(session->mic_accum.end(), samples, samples + frame_count);

  const size_t needed = static_cast<size_t>(session->frame_samples);
  size_t offset = 0;
  while (session->mic_accum.size() - offset >= needed) {
    session->render_ring.PopExactOrZero(session->temp_ref.data(), needed);
    aec3_process_render(session->aec, session->temp_ref.data(), static_cast<int32_t>(needed));
    aec3_process_capture(
        session->aec,
        session->mic_accum.data() + offset,
        session->temp_out.data(),
        static_cast<int32_t>(needed),
        0);
    session->output_ring.Push(session->temp_out.data(), needed);
    offset += needed;
  }
  if (offset > 0) {
    session->mic_accum.erase(session->mic_accum.begin(), session->mic_accum.begin() + static_cast<ptrdiff_t>(offset));
  }
}

std::string DeviceIdToUtf8(const ma_device_id& id) {
#ifdef _WIN32
  const wchar_t* wide = id.wasapi;
  if (!wide || wide[0] == L'\0') return std::string();
  const int len = WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (len <= 1) return std::string();
  std::string out(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), len, nullptr, nullptr);
  return out;
#else
  (void)id;
  return std::string();
#endif
}

bool FindDeviceId(
    ma_context* ctx,
    bool is_capture,
    const char* device_id_utf8,
    ma_device_id* out_id) {
  if (!ctx || !device_id_utf8 || device_id_utf8[0] == '\0' || !out_id) return false;
  ma_device_info* playback_infos = nullptr;
  ma_uint32 playback_count = 0;
  ma_device_info* capture_infos = nullptr;
  ma_uint32 capture_count = 0;
  if (ma_context_get_devices(
          ctx, &playback_infos, &playback_count, &capture_infos, &capture_count) != MA_SUCCESS) {
    return false;
  }
  const ma_device_info* infos = is_capture ? capture_infos : playback_infos;
  const ma_uint32 count = is_capture ? capture_count : playback_count;
  for (ma_uint32 i = 0; i < count; ++i) {
    if (DeviceIdToUtf8(infos[i].id) == device_id_utf8) {
      *out_id = infos[i].id;
      return true;
    }
  }
  return false;
}

void AppendJsonEscaped(std::string& out, const char* text) {
  out.push_back('"');
  if (text) {
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(text); *p; ++p) {
      switch (*p) {
        case '"':
          out += "\\\"";
          break;
        case '\\':
          out += "\\\\";
          break;
        case '\b':
          out += "\\b";
          break;
        case '\f':
          out += "\\f";
          break;
        case '\n':
          out += "\\n";
          break;
        case '\r':
          out += "\\r";
          break;
        case '\t':
          out += "\\t";
          break;
        default:
          if (*p < 0x20) {
            char buf[8];
            std::snprintf(buf, sizeof(buf), "\\u%04x", *p);
            out += buf;
          } else {
            out.push_back(static_cast<char>(*p));
          }
          break;
      }
    }
  }
  out.push_back('"');
}

struct PlaybackSession {
  ma_context context{};
  ma_device device{};
  bool has_context = false;
  bool has_device = false;
  int32_t channels = 1;
  std::atomic<bool> input_finished{false};
  std::atomic<bool> drained{false};
  PcmRingBuffer ring;

  PlaybackSession(int32_t sample_rate_hz, int32_t ch)
      : channels(ch),
        ring(static_cast<size_t>(sample_rate_hz) * static_cast<size_t>(ch) * 8) {}
};

void OnPlaybackData(ma_device* device, void* output, const void* /*input*/, ma_uint32 frame_count) {
  auto* session = static_cast<PlaybackSession*>(device->pUserData);
  if (!output || frame_count == 0) return;
  const size_t total_samples =
      static_cast<size_t>(frame_count) * static_cast<size_t>(session ? session->channels : 1);
  auto* out = static_cast<int16_t*>(output);
  if (!session) {
    std::memset(out, 0, total_samples * sizeof(int16_t));
    return;
  }
  const size_t popped = session->ring.Pop(out, total_samples);
  if (popped < total_samples) {
    std::memset(out + popped, 0, (total_samples - popped) * sizeof(int16_t));
    if (session->input_finished.load() && popped == 0) {
      session->drained.store(true);
    }
  }
}

}  // namespace

extern "C" {

LILYGO_AEC3_API void* aec3_create(int32_t sample_rate_hz, int32_t num_channels) {
  if (sample_rate_hz <= 0 || num_channels <= 0) return nullptr;
  auto* inst = new Aec3Instance();
  inst->sample_rate_hz = sample_rate_hz;
  inst->num_channels = num_channels;
  inst->samples_per_channel = sample_rate_hz / 100;

  webrtc::EchoCanceller3Config config;
  config.delay.use_external_delay_estimator = false;
  webrtc::EchoCanceller3Factory factory(config);
  inst->echo_control = factory.Create(sample_rate_hz, num_channels, num_channels);
  inst->hp_filter = std::make_unique<webrtc::HighPassFilter>(sample_rate_hz, num_channels);
  inst->ref_buffer = std::make_unique<webrtc::AudioBuffer>(
      sample_rate_hz, num_channels, sample_rate_hz, num_channels, sample_rate_hz, num_channels);
  inst->cap_buffer = std::make_unique<webrtc::AudioBuffer>(
      sample_rate_hz, num_channels, sample_rate_hz, num_channels, sample_rate_hz, num_channels);
  return inst;
}

LILYGO_AEC3_API void aec3_destroy(void* handle) {
  delete static_cast<Aec3Instance*>(handle);
}

LILYGO_AEC3_API void aec3_process_render(void* handle, const int16_t* pcm, int32_t num_samples) {
  auto* inst = static_cast<Aec3Instance*>(handle);
  if (!inst || !pcm || num_samples < inst->samples_per_channel * inst->num_channels) return;
  std::lock_guard<std::mutex> lock(inst->mutex);
  inst->ref_frame.UpdateFrame(
      0,
      pcm,
      static_cast<size_t>(inst->samples_per_channel),
      inst->sample_rate_hz,
      webrtc::AudioFrame::kNormalSpeech,
      webrtc::AudioFrame::kVadActive,
      static_cast<size_t>(inst->num_channels));
  inst->ref_buffer->CopyFrom(&inst->ref_frame);
  inst->ref_buffer->SplitIntoFrequencyBands();
  inst->echo_control->AnalyzeRender(inst->ref_buffer.get());
  inst->ref_buffer->MergeFrequencyBands();
}

LILYGO_AEC3_API void aec3_process_capture(
    void* handle,
    const int16_t* mic_pcm,
    int16_t* out_pcm,
    int32_t num_samples,
    int32_t delay_ms) {
  auto* inst = static_cast<Aec3Instance*>(handle);
  if (!inst || !mic_pcm || !out_pcm || num_samples < inst->samples_per_channel * inst->num_channels) {
    return;
  }
  std::lock_guard<std::mutex> lock(inst->mutex);
  inst->cap_frame.UpdateFrame(
      0,
      mic_pcm,
      static_cast<size_t>(inst->samples_per_channel),
      inst->sample_rate_hz,
      webrtc::AudioFrame::kNormalSpeech,
      webrtc::AudioFrame::kVadActive,
      static_cast<size_t>(inst->num_channels));
  inst->cap_buffer->CopyFrom(&inst->cap_frame);
  inst->echo_control->AnalyzeCapture(inst->cap_buffer.get());
  inst->cap_buffer->SplitIntoFrequencyBands();
  inst->hp_filter->Process(inst->cap_buffer.get(), true);
  inst->echo_control->SetAudioBufferDelay(delay_ms);
  inst->echo_control->ProcessCapture(inst->cap_buffer.get(), false);
  inst->cap_buffer->MergeFrequencyBands();
  inst->cap_buffer->CopyTo(&inst->cap_frame);
  std::memcpy(
      out_pcm,
      inst->cap_frame.data(),
      static_cast<size_t>(inst->samples_per_channel * inst->num_channels) * sizeof(int16_t));
}

LILYGO_AEC3_API void* aec3_live_start(int32_t sample_rate_hz) {
  return aec3_live_start_devices(sample_rate_hz, nullptr, nullptr);
}

LILYGO_AEC3_API void* aec3_live_start_devices(
    int32_t sample_rate_hz,
    const char* capture_device_id,
    const char* playback_device_id) {
  if (sample_rate_hz != 16000 && sample_rate_hz != 32000 && sample_rate_hz != 48000) {
    return nullptr;
  }
  auto* session = new LiveCaptureSession(sample_rate_hz);
  session->aec = static_cast<Aec3Instance*>(aec3_create(sample_rate_hz, 1));
  if (!session->aec) {
    delete session;
    return nullptr;
  }

  if (ma_context_init(nullptr, 0, nullptr, &session->context) != MA_SUCCESS) {
    aec3_destroy(session->aec);
    delete session;
    return nullptr;
  }
  session->has_context = true;

  ma_device_id matched_playback{};
  const bool has_playback_id =
      FindDeviceId(&session->context, false, playback_device_id, &matched_playback);
  ma_device_id matched_capture{};
  const bool has_capture_id =
      FindDeviceId(&session->context, true, capture_device_id, &matched_capture);

  // Start WASAPI loopback on target/default playback device so speaker output is fed to AEC3.
  ma_device_config loopback_cfg = ma_device_config_init(ma_device_type_loopback);
  loopback_cfg.capture.format = ma_format_s16;
  loopback_cfg.capture.channels = 1;
  if (has_playback_id) {
    loopback_cfg.capture.pDeviceID = &matched_playback;
  }
  loopback_cfg.sampleRate = static_cast<ma_uint32>(sample_rate_hz);
  loopback_cfg.periodSizeInMilliseconds = 10;
  loopback_cfg.dataCallback = OnLoopbackData;
  loopback_cfg.pUserData = session;
  if (ma_device_init(&session->context, &loopback_cfg, &session->loopback_device) == MA_SUCCESS) {
    if (ma_device_start(&session->loopback_device) == MA_SUCCESS) {
      session->has_loopback = true;
    } else {
      ma_device_uninit(&session->loopback_device);
    }
  }

  // Start microphone capture on target/default capture device.
  ma_device_config capture_cfg = ma_device_config_init(ma_device_type_capture);
  capture_cfg.capture.format = ma_format_s16;
  capture_cfg.capture.channels = 1;
  if (has_capture_id) {
    capture_cfg.capture.pDeviceID = &matched_capture;
  }
  capture_cfg.sampleRate = static_cast<ma_uint32>(sample_rate_hz);
  capture_cfg.periodSizeInMilliseconds = 10;
  capture_cfg.dataCallback = OnCaptureData;
  capture_cfg.pUserData = session;
  if (ma_device_init(&session->context, &capture_cfg, &session->capture_device) != MA_SUCCESS ||
      ma_device_start(&session->capture_device) != MA_SUCCESS) {
    if (session->has_loopback) {
      ma_device_uninit(&session->loopback_device);
    }
    ma_context_uninit(&session->context);
    aec3_destroy(session->aec);
    delete session;
    return nullptr;
  }
  session->has_capture = true;
  return session;
}

LILYGO_AEC3_API int32_t aec3_live_read(void* handle, int16_t* out_pcm, int32_t max_samples) {
  auto* session = static_cast<LiveCaptureSession*>(handle);
  if (!session || !out_pcm || max_samples <= 0) return -1;
  if (session->failed.load()) return -1;
  return static_cast<int32_t>(session->output_ring.Pop(out_pcm, static_cast<size_t>(max_samples)));
}

LILYGO_AEC3_API void aec3_live_stop(void* handle) {
  auto* session = static_cast<LiveCaptureSession*>(handle);
  if (!session) return;
  if (session->has_capture) {
    ma_device_uninit(&session->capture_device);
  }
  if (session->has_loopback) {
    ma_device_uninit(&session->loopback_device);
  }
  if (session->has_context) {
    ma_context_uninit(&session->context);
  }
  if (session->aec) {
    aec3_destroy(session->aec);
  }
  delete session;
}

LILYGO_AEC3_API int32_t aec3_list_audio_devices(
    int32_t is_capture,
    char* out_json,
    int32_t max_bytes) {
  if (!out_json || max_bytes <= 2) return -1;
  ma_context ctx{};
  if (ma_context_init(nullptr, 0, nullptr, &ctx) != MA_SUCCESS) {
    return -1;
  }
  ma_device_info* playback_infos = nullptr;
  ma_uint32 playback_count = 0;
  ma_device_info* capture_infos = nullptr;
  ma_uint32 capture_count = 0;
  const ma_result res = ma_context_get_devices(
      &ctx, &playback_infos, &playback_count, &capture_infos, &capture_count);
  if (res != MA_SUCCESS) {
    ma_context_uninit(&ctx);
    return -1;
  }

  const ma_device_info* infos = is_capture ? capture_infos : playback_infos;
  const ma_uint32 count = is_capture ? capture_count : playback_count;
  std::string json = "[";
  bool first = true;
  for (ma_uint32 i = 0; i < count; ++i) {
    const std::string id = DeviceIdToUtf8(infos[i].id);
    if (id.empty()) continue;
    if (!first) json.push_back(',');
    first = false;
    json += "{\"id\":";
    AppendJsonEscaped(json, id.c_str());
    json += ",\"name\":";
    AppendJsonEscaped(json, infos[i].name);
    json += ",\"isDefault\":";
    json += (infos[i].isDefault ? "true" : "false");
    json.push_back('}');
  }
  json.push_back(']');
  ma_context_uninit(&ctx);

  const int32_t needed = static_cast<int32_t>(json.size());
  if (needed >= max_bytes) {
    return -needed;
  }
  std::memcpy(out_json, json.data(), json.size());
  out_json[json.size()] = '\0';
  return needed;
}

LILYGO_AEC3_API void* aec3_play_start(
    const char* playback_device_id,
    int32_t sample_rate_hz,
    int32_t channels) {
  if (sample_rate_hz <= 0 || channels <= 0) return nullptr;
  auto* session = new PlaybackSession(sample_rate_hz, channels);
  if (ma_context_init(nullptr, 0, nullptr, &session->context) != MA_SUCCESS) {
    delete session;
    return nullptr;
  }
  session->has_context = true;

  ma_device_id matched{};
  const bool has_id =
      FindDeviceId(&session->context, false, playback_device_id, &matched);
  ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
  cfg.playback.format = ma_format_s16;
  cfg.playback.channels = static_cast<ma_uint32>(channels);
  if (has_id) {
    cfg.playback.pDeviceID = &matched;
  }
  cfg.sampleRate = static_cast<ma_uint32>(sample_rate_hz);
  cfg.periodSizeInMilliseconds = 20;
  cfg.dataCallback = OnPlaybackData;
  cfg.pUserData = session;

  if (ma_device_init(&session->context, &cfg, &session->device) != MA_SUCCESS ||
      ma_device_start(&session->device) != MA_SUCCESS) {
    if (session->has_device) {
      ma_device_uninit(&session->device);
    }
    ma_context_uninit(&session->context);
    delete session;
    return nullptr;
  }
  session->has_device = true;
  return session;
}

LILYGO_AEC3_API int32_t aec3_play_write(
    void* handle,
    const int16_t* pcm,
    int32_t num_samples) {
  auto* session = static_cast<PlaybackSession*>(handle);
  if (!session || !pcm || num_samples <= 0) return 0;
  session->drained.store(false);
  session->ring.Push(pcm, static_cast<size_t>(num_samples));
  return num_samples;
}

LILYGO_AEC3_API void aec3_play_finish(void* handle) {
  auto* session = static_cast<PlaybackSession*>(handle);
  if (session) {
    session->input_finished.store(true);
  }
}

LILYGO_AEC3_API int32_t aec3_play_is_finished(void* handle) {
  auto* session = static_cast<PlaybackSession*>(handle);
  if (!session) return 1;
  return session->drained.load() ? 1 : 0;
}

LILYGO_AEC3_API void aec3_play_stop(void* handle) {
  auto* session = static_cast<PlaybackSession*>(handle);
  if (!session) return;
  if (session->has_device) {
    ma_device_uninit(&session->device);
  }
  if (session->has_context) {
    ma_context_uninit(&session->context);
  }
  delete session;
}

LILYGO_AEC3_API int16_t* aec3_alloc_i16(int32_t count) {
  if (count <= 0) return nullptr;
  return new int16_t[static_cast<size_t>(count)]();
}

LILYGO_AEC3_API void aec3_free(void* ptr) {
  delete[] static_cast<int16_t*>(ptr);
}

}  // extern "C"
