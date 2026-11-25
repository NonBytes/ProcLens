#import "DiskIO.h"
#import <libproc.h>
#import <sys/proc_info.h>
#import <mach/machine.h>

// PROC_PIDARCHINFO / proc_archinfo are missing from the macOS 15 SDK headers
// shipped with some Xcode/CI toolchains; declare them ourselves when absent
// so architecture detection still compiles there.
#ifndef PROC_PIDARCHINFO
struct proc_archinfo {
    cpu_type_t    p_cputype;
    cpu_subtype_t p_cpusubtype;
};
#define PROC_PIDARCHINFO 19
#define PROC_PIDARCHINFO_SIZE (sizeof(struct proc_archinfo))
#endif
