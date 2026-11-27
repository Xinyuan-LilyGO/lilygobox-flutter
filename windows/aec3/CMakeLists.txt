cmake_minimum_required(VERSION 3.14)
project(lilygo_aec3 LANGUAGES C CXX)

set(WEBRTC_AEC3_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../third_party/webrtc_aec3")

file(GLOB AEC3_CORE_SOURCES
  "${WEBRTC_AEC3_ROOT}/audio_processing/aec3/*.cc"
)
list(FILTER AEC3_CORE_SOURCES EXCLUDE REGEX ".*_unittest\\.cc$")

set(WEBRTC_AUDIO_PROCESS_SOURCES
  "${WEBRTC_AEC3_ROOT}/audio_processing/audio_frame.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/audio_buffer.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/high_pass_filter.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/splitting_filter.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/splitting_filter_c.c"
  "${WEBRTC_AEC3_ROOT}/audio_processing/sparse_fir_filter.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/three_band_filter_bank.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/channel_buffer.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/utility/cascaded_biquad_filter.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/utility/delay_estimator.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/utility/delay_estimator_wrapper.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/utility/ooura_fft.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/utility/ooura_fft_sse2.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/logging/apm_data_dumper.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/channel_layout.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/resampler/push_sinc_resampler.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/resampler/sinc_resampler.cc"
  "${WEBRTC_AEC3_ROOT}/audio_processing/resampler/sinc_resampler_sse.cc"
  "${WEBRTC_AEC3_ROOT}/api/echo_canceller3_config.cc"
  "${WEBRTC_AEC3_ROOT}/api/echo_canceller3_factory.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/checks.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/time_utils.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/logging.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/memory/aligned_malloc.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/race_checker.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/string_encode.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/string_utils.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/platform_thread_types.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/strings/string_builder.cc"
  "${WEBRTC_AEC3_ROOT}/base/rtc_base/critical_section.cc"
  "${WEBRTC_AEC3_ROOT}/base/system_wrappers/source/field_trial.cc"
  "${WEBRTC_AEC3_ROOT}/base/system_wrappers/source/metrics.cc"
  "${WEBRTC_AEC3_ROOT}/base/system_wrappers/source/cpu_features.cc"
  "${WEBRTC_AEC3_ROOT}/base/abseil/absl/types/bad_optional_access.cc"
  "${WEBRTC_AEC3_ROOT}/base/abseil/absl/base/internal/throw_delegate.cc"
  "${WEBRTC_AEC3_ROOT}/base/abseil/absl/strings/string_view.cc"
  "${WEBRTC_AEC3_ROOT}/base/abseil/absl/strings/internal/memutil.cc"
  "${WEBRTC_AEC3_ROOT}/base/abseil/absl/strings/ascii.cc"
)

add_library(lilygo_aec3 SHARED
  "lilygo_aec3.cpp"
  ${AEC3_CORE_SOURCES}
  ${WEBRTC_AUDIO_PROCESS_SOURCES}
)

target_compile_features(lilygo_aec3 PRIVATE cxx_std_17)
target_compile_definitions(lilygo_aec3 PRIVATE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
  WEBRTC_WIN
  WEBRTC_APM_DEBUG_DUMP=0
  _CRT_SECURE_NO_WARNINGS
)
target_compile_options(lilygo_aec3 PRIVATE /W0 /EHsc /utf-8)
target_include_directories(lilygo_aec3 PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${WEBRTC_AEC3_ROOT}"
  "${WEBRTC_AEC3_ROOT}/audio_processing"
  "${WEBRTC_AEC3_ROOT}/audio_processing/aec3"
  "${WEBRTC_AEC3_ROOT}/audio_processing/include"
  "${WEBRTC_AEC3_ROOT}/audio_processing/utility"
  "${WEBRTC_AEC3_ROOT}/audio_processing/logging"
  "${WEBRTC_AEC3_ROOT}/base"
  "${WEBRTC_AEC3_ROOT}/base/abseil"
)
target_link_libraries(lilygo_aec3 PRIVATE
  ole32
  winmm
  avrt
)
