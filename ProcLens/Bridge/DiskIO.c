#include "DiskIO.h"
#include <libproc.h>
#include <sys/resource.h>
#include <string.h>

DiskIOResult fetch_disk_io(int pid) {
    DiskIOResult result = {0, 0};
    struct rusage_info_v4 ri;
    memset(&ri, 0, sizeof(ri));
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ri) == 0) {
        result.read_bytes = ri.ri_diskio_bytesread;
        result.write_bytes = ri.ri_diskio_byteswritten;
    }
    return result;
}
