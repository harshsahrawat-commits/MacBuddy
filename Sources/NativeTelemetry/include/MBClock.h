#ifndef MAC_BUDDY_CLOCK_H
#define MAC_BUDDY_CLOCK_H
#include <stdint.h>
#include <mach/mach_time.h>
#include <pthread.h>

// proc_pid_rusage CPU counters use Mach absolute-time ticks, not nanoseconds.
// A 128-bit intermediate avoids overflow when scaling Apple silicon's 125/3 timebase.
static inline uint64_t mb_scale_ticks(uint64_t user, uint64_t system, uint32_t numerator, uint32_t denominator) {
    if (!denominator) return 0;
    __uint128_t value = ((__uint128_t)user + system) * numerator / denominator;
    return value > UINT64_MAX ? UINT64_MAX : (uint64_t)value;
}
static mach_timebase_info_data_t mb_timebase;
static pthread_once_t mb_timebase_once = PTHREAD_ONCE_INIT;
static void mb_initialize_timebase(void) { mach_timebase_info(&mb_timebase); }
static inline uint64_t mb_cpu_nanoseconds(uint64_t user, uint64_t system) {
    pthread_once(&mb_timebase_once, mb_initialize_timebase);
    return mb_scale_ticks(user, system, mb_timebase.numer, mb_timebase.denom);
}
#endif
