#ifndef DiskIO_h
#define DiskIO_h

#include <stdint.h>

typedef struct {
    uint64_t read_bytes;
    uint64_t write_bytes;
} DiskIOResult;

DiskIOResult fetch_disk_io(int pid);

#endif
