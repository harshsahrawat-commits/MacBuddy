#include "NativeTelemetry.h"
#include "MBClock.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <libproc.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>

// Read-only SMC user-client protocol. No write command is implemented.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCPLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key; SMCVersion version; SMCPLimit limits; SMCKeyInfo info;
    uint8_t result, status, command; uint32_t data; uint8_t bytes[32];
} SMCData;
_Static_assert(sizeof(SMCData) == 80, "Unexpected SMC ABI layout");
static io_connect_t smc = IO_OBJECT_NULL;
static int attempted_smc = 0;
typedef struct { const char *key; SMCKeyInfo info; int probed, available; } Sensor;
// M4-family mappings cross-checked against Stats' MIT-licensed sensor definitions.
// Only keys actually present, correctly typed, and returning plausible data contribute.
static Sensor cpu_sensors[] = {
    {"Te05"}, {"Te0S"}, {"Te09"}, {"Te0H"},
    {"Tp01"}, {"Tp05"}, {"Tp09"}, {"Tp0D"}, {"Tp0V"}, {"Tp0Y"}, {"Tp0b"}, {"Tp0e"}
};
static Sensor gpu_sensors[] = {
    {"Tg0G"}, {"Tg0H"}, {"Tg0K"}, {"Tg0L"}, {"Tg0d"}, {"Tg0e"}, {"Tg0j"}, {"Tg0k"}, {"Tg1U"}, {"Tg1k"}
};
static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint8_t)s[3];
}
static int call_smc(SMCData *in, SMCData *out) {
    size_t size = sizeof(*out);
    kern_return_t result = IOConnectCallStructMethod(smc, 2, in, sizeof(*in), out, &size);
    return result == KERN_SUCCESS && size == sizeof(*out) && out->result == 0;
}
static int read_sensor(Sensor *s, double *temperature) {
    SMCData input = {0}, output = {0};
    input.key = fourcc(s->key);
    if (!s->probed) {
        input.command = 9; // get key info
        s->available = call_smc(&input, &output) && output.info.size > 0 && output.info.size <= 32;
        s->info = output.info;
        s->probed = 1;
    }
    if (!s->available) return 0;
    memset(&output, 0, sizeof(output));
    input.info = s->info;
    input.command = 5; // read bytes
    if (!call_smc(&input, &output)) return 0;
    double value;
    if (s->info.type == fourcc("flt ") && s->info.size == 4) {
        float f; memcpy(&f, output.bytes, 4); value = f;
    } else if (s->info.type == fourcc("sp78") && s->info.size == 2) {
        int16_t fixed = (int16_t)(((uint16_t)output.bytes[0] << 8) | output.bytes[1]);
        value = fixed / 256.0;
    } else { return 0; }
    // Sensor validity bounds, NOT thermal safety thresholds.
    if (!isfinite(value) || value <= 0 || value > 150) return 0;
    *temperature = value; return 1;
}
static int mean_temperature(Sensor *sensors, size_t count, double *value) {
    double total = 0, v; int valid = 0;
    for (size_t i=0; i<count; i++) if (read_sensor(&sensors[i], &v)) { total += v; valid++; }
    if (valid) *value = total / valid;
    return valid;
}
static void temperatures(MBMetrics *out) {
    if (!attempted_smc) {
        attempted_smc = 1;
        char brand[128] = {0}; size_t n = sizeof(brand);
        // Do not apply M4 mappings speculatively to different chips.
        if (sysctlbyname("machdep.cpu.brand_string", brand, &n, NULL, 0) != 0 || !strstr(brand, "Apple M4")) return;
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (service) {
            if (IOServiceOpen(service, mach_task_self(), 0, &smc) != KERN_SUCCESS) smc = IO_OBJECT_NULL;
            IOObjectRelease(service);
        }
    }
    if (!smc) return;
    out->cpu_sensor_count = mean_temperature(cpu_sensors, sizeof(cpu_sensors)/sizeof(Sensor), &out->cpu_temperature);
    out->gpu_sensor_count = mean_temperature(gpu_sensors, sizeof(gpu_sensors)/sizeof(Sensor), &out->gpu_temperature);
    out->cpu_temperature_valid = out->cpu_sensor_count > 0;
    out->gpu_temperature_valid = out->gpu_sensor_count > 0;
}
static void gpu(MBMetrics *out) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"));
    if (!service) return;
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
    IOObjectRelease(service);
    if (!value) return;
    if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        CFTypeRef number = CFDictionaryGetValue((CFDictionaryRef)value, CFSTR("Device Utilization %"));
        if (number && CFGetTypeID(number) == CFNumberGetTypeID()) {
            double result;
            if (CFNumberGetValue((CFNumberRef)number, kCFNumberDoubleType, &result) && isfinite(result) && result >= 0 && result <= 100) {
                out->gpu_percent = result; out->gpu_valid = 1;
            }
        }
    }
    CFRelease(value);
}
void mb_read_metrics(MBMetrics *out) {
    memset(out, 0, sizeof(*out));
    mach_port_t host = mach_host_self();
    host_cpu_load_info_data_t load; mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&load, &count) == KERN_SUCCESS) {
        out->cpu_user = load.cpu_ticks[CPU_STATE_USER]; out->cpu_system = load.cpu_ticks[CPU_STATE_SYSTEM];
        out->cpu_idle = load.cpu_ticks[CPU_STATE_IDLE]; out->cpu_nice = load.cpu_ticks[CPU_STATE_NICE];
        out->cpu_valid = 1;
    }
    vm_statistics64_data_t vm; count = HOST_VM_INFO64_COUNT;
    uint64_t total = 0; size_t size = sizeof(total);
    if (sysctlbyname("hw.memsize", &total, &size, NULL, 0) == 0 &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        vm_size_t page = 0; host_page_size(host, &page);
        int64_t anonymous = (int64_t)vm.active_count + vm.inactive_count + vm.speculative_count - vm.purgeable_count - vm.external_page_count;
        uint64_t used = ((uint64_t)(anonymous > 0 ? anonymous : 0) + vm.wire_count + vm.compressor_page_count) * page;
        out->memory_total = total; out->memory_used = used > total ? total : used;
        out->compressed = (uint64_t)vm.compressor_page_count * page;
        out->swapout_bytes = vm.swapouts * page; out->memory_valid = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap; size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) {
        out->swap_used = swap.xsu_used; out->swap_valid = 1;
    }
    int pressure = 0; size = sizeof(pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, NULL, 0) == 0 &&
        (pressure == 1 || pressure == 2 || pressure == 4)) {
        out->pressure = pressure; out->pressure_valid = 1;
    }
    gpu(out); temperatures(out);
}
size_t mb_read_processes(MBProcess *out, size_t capacity) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return 0;
    size_t allocation = (size_t)bytes + 4096;
    pid_t *pids = calloc(1, allocation);
    if (!pids) return 0;
    int actual = proc_listpids(PROC_ALL_PIDS, 0, pids, (int)allocation);
    size_t filled = 0;
    for (int i=0; i<actual/(int)sizeof(pid_t) && filled<capacity; i++) {
        if (pids[i] <= 0) continue;
        struct rusage_info_v2 usage = {0};
        if (proc_pid_rusage(pids[i], RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) continue;
        MBProcess *p = &out[filled]; memset(p, 0, sizeof(*p));
        if (proc_name(pids[i], p->name, sizeof(p->name)) <= 0) continue;
        p->pid = pids[i]; p->birth = usage.ri_proc_start_abstime;
        p->cpu_nanoseconds = mb_cpu_nanoseconds(usage.ri_user_time, usage.ri_system_time);
        p->footprint = usage.ri_phys_footprint; filled++;
    }
    free(pids); return filled;
}
void mb_close_sensors(void) {
    if (smc) IOServiceClose(smc);
    smc = IO_OBJECT_NULL; attempted_smc = 0;
    for (size_t i=0;i<sizeof(cpu_sensors)/sizeof(Sensor);i++) cpu_sensors[i].probed=0;
    for (size_t i=0;i<sizeof(gpu_sensors)/sizeof(Sensor);i++) gpu_sensors[i].probed=0;
}
