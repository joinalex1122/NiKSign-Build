#include "NiKZipCheck.h"
#include "unzip.h"
int NiKZipCheck(const char *path, uint64_t *entries, uint64_t *expandedBytes) {
    if (!path || !entries || !expandedBytes) return -1;
    *entries = 0; *expandedBytes = 0;
    unzFile file = unzOpen64(path);
    if (!file) return -2;
    int result = unzGoToFirstFile(file);
    while (result == UNZ_OK) {
        unz_file_info64 info;
        if (unzGetCurrentFileInfo64(file, &info, NULL, 0, NULL, 0, NULL, 0) != UNZ_OK) {
            unzClose(file); return -3;
        }
        if (++*entries > 50000 || info.uncompressed_size > 1073741824ULL - *expandedBytes) {
            unzClose(file); return -4;
        }
        *expandedBytes += info.uncompressed_size;
        result = unzGoToNextFile(file);
    }
    unzClose(file);
    return result == UNZ_END_OF_LIST_OF_FILE && *entries > 0 ? 0 : -5;
}
