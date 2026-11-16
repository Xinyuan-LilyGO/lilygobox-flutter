#include "codec.h"
#include "lzma/Lzma2Enc.h"
#include "lzma/Lzma2Dec.h"
#include "lzma/Alloc.h"
#include "zstd/zstd.h"

int lb_lzma2_encode(const unsigned char *input,size_t size,unsigned char *output,size_t *output_size,unsigned char *property){
  CLzma2EncHandle encoder=Lzma2Enc_Create(&g_Alloc,&g_Alloc);
  if(!encoder)return SZ_ERROR_MEM;
  CLzma2EncProps props;Lzma2EncProps_Init(&props);
  props.lzmaProps.level=9;props.lzmaProps.algo=1;props.lzmaProps.btMode=1;
  props.lzmaProps.fb=273;props.lzmaProps.mc=128;
  props.lzmaProps.dictSize=1<<26;
  if(size<(1<<26)){unsigned dict=1<<12;while(dict<size&&dict<(1<<26))dict<<=1;props.lzmaProps.dictSize=dict;}
  props.lzmaProps.numThreads=1;props.numTotalThreads=1;
  props.blockSize=LZMA2_ENC_PROPS_BLOCK_SIZE_SOLID;
  int result=Lzma2Enc_SetProps(encoder,&props);
  if(!result){*property=Lzma2Enc_WriteProperties(encoder);Lzma2Enc_SetDataSize(encoder,size);result=Lzma2Enc_Encode2(encoder,NULL,output,output_size,NULL,input,size,NULL);}
  Lzma2Enc_Destroy(encoder);return result;
}
int lb_lzma2_decode(const unsigned char *input,size_t size,unsigned char *output,size_t *output_size,unsigned char property){
  ELzmaStatus status;SizeT source_size=size;
  int result=Lzma2Decode(output,output_size,input,&source_size,property,LZMA_FINISH_END,&status,&g_Alloc);
  if(result==SZ_OK&&(source_size!=size||status!=LZMA_STATUS_FINISHED_WITH_MARK))return SZ_ERROR_DATA;
  return result;
}
size_t lb_zstd_bound(size_t size){return ZSTD_compressBound(size);}
size_t lb_zstd_encode(const unsigned char *input,size_t size,unsigned char *output,size_t capacity,int level){return ZSTD_compress(output,capacity,input,size,level);}
size_t lb_zstd_decode(const unsigned char *input,size_t size,unsigned char *output,size_t capacity){return ZSTD_decompress(output,capacity,input,size);}
int lb_zstd_error(size_t result){return ZSTD_isError(result);}
// Progress/cancellation additions to the application-owned codec API.
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
typedef struct { volatile LONG cancelled; } lb_cancel_state;
#else
#include <stdatomic.h>
typedef struct { atomic_int cancelled; } lb_cancel_state;
#endif

void *lb_cancel_create(void) { return calloc(1, sizeof(lb_cancel_state)); }
void lb_cancel_set(void *state) {
#ifdef _WIN32
  InterlockedExchange(&((lb_cancel_state *)state)->cancelled, 1);
#else
  atomic_store(&((lb_cancel_state *)state)->cancelled, 1);
#endif
}
int lb_cancel_get(void *state) {
  if (!state) return 0;
#ifdef _WIN32
  return InterlockedCompareExchange(&((lb_cancel_state *)state)->cancelled, 0, 0) != 0;
#else
  return atomic_load(&((lb_cancel_state *)state)->cancelled) != 0;
#endif
}
void lb_cancel_free(void *state) { free(state); }

typedef struct {
  ICompressProgress api;
  lb_codec_progress callback;
  void *cancel;
} lb_progress;

static SRes lb_report_progress(ICompressProgressPtr progress, UInt64 input, UInt64 output) {
  const lb_progress *state = (const lb_progress *)progress;
  if (lb_cancel_get(state->cancel)) return SZ_ERROR_PROGRESS;
  if (state->callback) state->callback(input, output);
  return lb_cancel_get(state->cancel) ? SZ_ERROR_PROGRESS : SZ_OK;
}

int lb_lzma2_encode_progress(const unsigned char *input, size_t size,
    unsigned char *output, size_t *output_size, unsigned char *property,
    lb_codec_progress callback, void *cancel) {
  if (lb_cancel_get(cancel)) return SZ_ERROR_PROGRESS;
  CLzma2EncHandle encoder = Lzma2Enc_Create(&g_Alloc, &g_Alloc);
  if (!encoder) return SZ_ERROR_MEM;
  CLzma2EncProps props; Lzma2EncProps_Init(&props);
  props.lzmaProps.level=9; props.lzmaProps.algo=1; props.lzmaProps.btMode=1;
  props.lzmaProps.fb=273; props.lzmaProps.mc=128; props.lzmaProps.dictSize=1<<26;
  if(size<(1<<26)){unsigned dict=1<<12;while(dict<size&&dict<(1<<26))dict<<=1;props.lzmaProps.dictSize=dict;}
  props.lzmaProps.numThreads=1; props.numTotalThreads=1;
  props.blockSize=LZMA2_ENC_PROPS_BLOCK_SIZE_SOLID;
  lb_progress progress = {{lb_report_progress}, callback, cancel};
  int result=Lzma2Enc_SetProps(encoder,&props);
  if(!result){
    *property=Lzma2Enc_WriteProperties(encoder); Lzma2Enc_SetDataSize(encoder,size);
    result=Lzma2Enc_Encode2(encoder,NULL,output,output_size,NULL,input,size,&progress.api);
  }
  Lzma2Enc_Destroy(encoder);
  return lb_cancel_get(cancel) ? SZ_ERROR_PROGRESS : result;
}

int lb_lzma2_decode_progress(const unsigned char *input, size_t size,
    unsigned char *output, size_t *output_size, unsigned char property,
    lb_codec_progress callback, void *cancel) {
  CLzma2Dec decoder; Lzma2Dec_Construct(&decoder);
  int result = Lzma2Dec_AllocateProbs(&decoder, property, &g_Alloc);
  if (result != SZ_OK) return result;
  // Decode directly into the caller's final output buffer. No extra dictionary.
  decoder.decoder.dic = output;
  decoder.decoder.dicBufSize = *output_size;
  Lzma2Dec_Init(&decoder);
  size_t consumed = 0;
  ELzmaStatus status = LZMA_STATUS_NOT_SPECIFIED;
  while (result == SZ_OK) {
    if (lb_cancel_get(cancel)) { result=SZ_ERROR_PROGRESS; break; }
    const size_t before = decoder.decoder.dicPos;
    size_t limit = before + 1024 * 1024;
    if (limit > *output_size) limit = *output_size;
    SizeT remaining = size - consumed;
    result = Lzma2Dec_DecodeToDic(&decoder, limit, input + consumed, &remaining,
        limit == *output_size ? LZMA_FINISH_END : LZMA_FINISH_ANY, &status);
    consumed += remaining;
    if (callback) callback(consumed, decoder.decoder.dicPos);
    if (result != SZ_OK || status == LZMA_STATUS_FINISHED_WITH_MARK) break;
    if (decoder.decoder.dicPos == before && remaining == 0) { result=SZ_ERROR_DATA; break; }
    if (decoder.decoder.dicPos == *output_size) { result=SZ_ERROR_DATA; break; }
  }
  if (result == SZ_OK && (consumed != size || status != LZMA_STATUS_FINISHED_WITH_MARK ||
      decoder.decoder.dicPos != *output_size)) result=SZ_ERROR_DATA;
  *output_size = decoder.decoder.dicPos;
  Lzma2Dec_FreeProbs(&decoder, &g_Alloc);
  return lb_cancel_get(cancel) ? SZ_ERROR_PROGRESS : result;
}
