// LilygoBox native codec interface. SDK dependencies retain their own licenses.
#include <stddef.h>
#include <stdint.h>
#ifdef _WIN32
#define LB_API __declspec(dllexport)
#else
#define LB_API __attribute__((visibility("default")))
#endif
LB_API int lb_lzma2_encode(const uint8_t *input,size_t size,uint8_t *output,size_t *output_size,uint8_t *property);
LB_API int lb_lzma2_decode(const uint8_t *input,size_t size,uint8_t *output,size_t *output_size,uint8_t property);
LB_API size_t lb_zstd_bound(size_t size);
LB_API size_t lb_zstd_encode(const uint8_t *input,size_t size,uint8_t *output,size_t capacity,int level);
LB_API size_t lb_zstd_decode(const uint8_t *input,size_t size,uint8_t *output,size_t capacity);
LB_API int lb_zstd_error(size_t result);
typedef void (*lb_codec_progress)(uint64_t input_size, uint64_t output_size);
LB_API void *lb_cancel_create(void);
LB_API void lb_cancel_set(void *state);
LB_API int lb_cancel_get(void *state);
LB_API void lb_cancel_free(void *state);
LB_API int lb_lzma2_encode_progress(const uint8_t *input,size_t size,uint8_t *output,size_t *output_size,uint8_t *property,lb_codec_progress progress,void *cancel);
LB_API int lb_lzma2_decode_progress(const uint8_t *input,size_t size,uint8_t *output,size_t *output_size,uint8_t property,lb_codec_progress progress,void *cancel);
