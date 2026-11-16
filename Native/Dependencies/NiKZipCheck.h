#ifndef NIK_ZIP_CHECK_H
#define NIK_ZIP_CHECK_H
#include <stdint.h>
// Return 0 for readable, bounded metadata; negative for malformed/oversized ZIP.
int NiKZipCheck(const char *path, uint64_t *entries, uint64_t *expandedBytes);
#endif
