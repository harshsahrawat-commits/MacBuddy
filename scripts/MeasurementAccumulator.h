#ifndef MAC_BUDDY_MEASUREMENT_ACCUMULATOR_H
#define MAC_BUDDY_MEASUREMENT_ACCUMULATOR_H
#include <stdint.h>

typedef struct {
    double seconds, largest_gap;
    uint64_t cpu_nanoseconds;
    unsigned gaps;
} MBMeasurementIntervals;

// Long intervals may contain system sleep, App Nap, or scheduling delays. Do not
// treat unobserved wall time as active CPU time, and do not attribute its CPU delta.
static inline void mb_measurement_add(MBMeasurementIntervals *m, double seconds, uint64_t cpu_nanoseconds) {
    if (seconds <= 0) return;
    if (seconds > 5) {
        m->gaps++;
        if (seconds > m->largest_gap) m->largest_gap = seconds;
        return;
    }
    m->seconds += seconds;
    m->cpu_nanoseconds += cpu_nanoseconds;
}
static inline double mb_measurement_cpu(const MBMeasurementIntervals *m) {
    return m->seconds > 0 ? m->cpu_nanoseconds / 1e9 / m->seconds * 100 : 0;
}
#endif
