#pragma once

#include <stdint.h>

#ifdef _WIN32
#  ifdef LILYGO_AEC3_EXPORTS
#    define LILYGO_AEC3_API __declspec(dllexport)
#  else
#    define LILYGO_AEC3_API __declspec(dllimport)
#  endif
#else
#  define LILYGO_AEC3_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Frame-by-frame Google WebRTC AEC3 API (10ms per frame, e.g. 160 samples @ 16kHz).
LILYGO_AEC3_API void* aec3_create(int32_t sample_rate_hz, int32_t num_channels);
LILYGO_AEC3_API void aec3_destroy(void* handle);
LILYGO_AEC3_API void aec3_process_render(void* handle, const int16_t* pcm, int32_t num_samples);
LILYGO_AEC3_API void aec3_process_capture(
    void* handle,
    const int16_t* mic_pcm,
    int16_t* out_pcm,
    int32_t num_samples,
    int32_t delay_ms);

// Windows WASAPI live mic + loopback AEC3 capture API.
LILYGO_AEC3_API void* aec3_live_start(int32_t sample_rate_hz);
LILYGO_AEC3_API void* aec3_live_start_devices(
    int32_t sample_rate_hz,
    const char* capture_device_id,
    const char* playback_device_id);
LILYGO_AEC3_API int32_t aec3_live_read(void* handle, int16_t* out_pcm, int32_t max_samples);
LILYGO_AEC3_API void aec3_live_stop(void* handle);
LILYGO_AEC3_API int32_t aec3_list_audio_devices(
    int32_t is_capture,
    char* out_json,
    int32_t max_bytes);

// Windows WASAPI targeted playback API (PCM 16-bit).
LILYGO_AEC3_API void* aec3_play_start(
    const char* playback_device_id,
    int32_t sample_rate_hz,
    int32_t channels);
LILYGO_AEC3_API int32_t aec3_play_write(
    void* handle,
    const int16_t* pcm,
    int32_t num_samples);
LILYGO_AEC3_API void aec3_play_finish(void* handle);
LILYGO_AEC3_API int32_t aec3_play_is_finished(void* handle);
LILYGO_AEC3_API void aec3_play_stop(void* handle);

LILYGO_AEC3_API int16_t* aec3_alloc_i16(int32_t count);
LILYGO_AEC3_API void aec3_free(void* ptr);

#ifdef __cplusplus
}
#endif
