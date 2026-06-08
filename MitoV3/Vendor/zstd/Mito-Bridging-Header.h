#ifndef MITO_BRIDGING_HEADER_H
#define MITO_BRIDGING_HEADER_H

#include <stddef.h>

// Minimal Zstandard decompression API, implemented by the vendored single-file
// decoder (Vendor/zstd/zstddeclib.c). Used to read modern Anki .anki21b
// collections, which are zstd-compressed SQLite.
size_t ZSTD_decompress(void *dst, size_t dstCapacity, const void *src, size_t srcSize);
unsigned long long ZSTD_getFrameContentSize(const void *src, size_t srcSize);
unsigned ZSTD_isError(size_t code);

#endif /* MITO_BRIDGING_HEADER_H */
