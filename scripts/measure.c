#include <libproc.h>
#include "MeasurementAccumulator.h"
#include "../Sources/NativeTelemetry/include/MBClock.h"
#include <sys/resource.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

// Read-only, single-process measurement. CPU is expressed as percent of one core.
static double monotonic(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
int main(int argc, char **argv) {
    if (argc < 3 || argc > 4 || (argc == 4 && strcmp(argv[3], "--observed-duration") != 0)) { fprintf(stderr, "Usage: measure PID SECONDS [--observed-duration]\n"); return 2; }
    int observedDuration = argc == 4;
    pid_t pid = (pid_t)atoi(argv[1]); int seconds = atoi(argv[2]);
    if (pid <= 0 || seconds < 1 || seconds > 86400) return 2;
    struct rusage_info_v4 start = {0}, end = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&start) != 0) { perror("proc_pid_rusage"); return 1; }
    double began = monotonic(), sum = 0, peak = 0; int count = 0;
    pthread_once(&mb_timebase_once, mb_initialize_timebase);
    printf("START format=3 pid=%d wall=%ld duration=%d duration_basis=%s timebase=%u/%u lifetime_peak_mib=%.2f\n", pid, time(NULL), seconds, observedDuration ? "observed" : "wall", mb_timebase.numer, mb_timebase.denom, start.ri_lifetime_max_phys_footprint / 1048576.0); fflush(stdout);
    double lastObservation = began, reportedPeak = 0;
    struct rusage_info_v4 previous = start;
    MBMeasurementIntervals intervals = {0};
    do {
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&end) != 0 || end.ri_proc_start_abstime != start.ri_proc_start_abstime) { fprintf(stderr, "Process exited or PID changed. Measurement invalid.\n"); return 1; }
        double observed = monotonic();
        double gap = observed - lastObservation;
        mb_measurement_add(&intervals, gap, mb_cpu_nanoseconds(end.ri_user_time - previous.ri_user_time, end.ri_system_time - previous.ri_system_time));
        if(gap > 5) { printf("GAP wall=%ld elapsed=%.1f unobserved_seconds=%.1f\n", time(NULL), observed-began, gap); fflush(stdout); }
        lastObservation = observed;
        previous = end;
        double mib = end.ri_phys_footprint / 1048576.0; sum += mib; if (mib > peak) peak = mib; count++;
        if(mib > reportedPeak + 1) { reportedPeak=mib; printf("PEAK wall=%ld elapsed=%.1f footprint=%.2fMiB\n",time(NULL),monotonic()-began,mib);fflush(stdout); }
        if (count % 60 == 0) { printf("PROGRESS elapsed=%.0f observed=%.0f observed_cpu=%.4f%% footprint=%.2fMiB\n", monotonic()-began, intervals.seconds, mb_measurement_cpu(&intervals), mib); fflush(stdout); }
        if ((observedDuration ? intervals.seconds : monotonic() - began) >= seconds) break;
        if (observedDuration && monotonic() - began > seconds * 12.0) break;
        sleep(1);
    } while (1);
    double elapsed = monotonic() - began;
    double cpu = mb_cpu_nanoseconds(end.ri_user_time - start.ri_user_time, end.ri_system_time - start.ri_system_time) / 1e9 / elapsed * 100;
    printf("PID %d; %.1f wall seconds; wall-time mean CPU %.3f%% of one core; mean physical footprint %.2f MiB; peak footprint %.2f MiB; %d observations\n", pid, elapsed, cpu, sum / count, peak, count);
    printf("OBSERVED seconds=%.1f mean_cpu=%.4f%% of one core (excludes long observation gaps)\n", intervals.seconds, mb_measurement_cpu(&intervals));
    // The kernel remembers sub-second peaks that polling can miss. This counter
    // covers the whole process lifetime, including UI use before this window.
    printf("LIFETIME_PEAK start_mib=%.2f end_mib=%.2f increased=%s scope=process-lifetime-not-measurement-window\n", start.ri_lifetime_max_phys_footprint / 1048576.0, end.ri_lifetime_max_phys_footprint / 1048576.0, end.ri_lifetime_max_phys_footprint > start.ri_lifetime_max_phys_footprint ? "yes" : "no");
    if (observedDuration && intervals.seconds < seconds) { printf("INCOMPLETE: insufficient observed time before wall-time limit\n"); return 3; }
    printf("COMPLETE wall=%ld observation_gaps=%u largest_gap_seconds=%.1f\n", time(NULL), intervals.gaps, intervals.largest_gap);
    return 0;
}
