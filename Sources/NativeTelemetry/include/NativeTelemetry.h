#ifndef MAC_BUDDY_TELEMETRY_H
#define MAC_BUDDY_TELEMETRY_H
#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint64_t cpu_user, cpu_system, cpu_idle, cpu_nice;
    uint64_t memory_total, memory_used, compressed, swap_used, swapout_bytes;
    int cpu_valid, memory_valid, swap_valid, pressure_valid, pressure;
    double gpu_percent, cpu_temperature, gpu_temperature;
    int gpu_valid, cpu_temperature_valid, gpu_temperature_valid;
    int cpu_sensor_count, gpu_sensor_count;
} MBMetrics;

typedef struct {
    int32_t pid;
    uint64_t birth, cpu_nanoseconds, footprint;
    char name[256];
} MBProcess;

void mb_read_metrics(MBMetrics *out);
size_t mb_read_processes(MBProcess *out, size_t capacity);
void mb_close_sensors(void);
#endif
