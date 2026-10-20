#include "../Sources/NativeTelemetry/include/MBClock.h"
#include "MeasurementAccumulator.h"
#include "../Sources/NativeTelemetry/include/NativeTelemetry.h"
#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
static double process_cpu(void) { struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return t.tv_sec + t.tv_nsec/1e9; }
int main(void) {
    MBMeasurementIntervals intervals = {0};
    mb_measurement_add(&intervals, 1, 10000000);
    mb_measurement_add(&intervals, 7200, 3000000000ULL);
    mb_measurement_add(&intervals, 1, 10000000);
    if (intervals.seconds != 2 || intervals.gaps != 1 || intervals.largest_gap != 7200 || fabs(mb_measurement_cpu(&intervals)-1.0)>0.0001) {
        fputs("FAIL measurement counted unobserved sleep as active time\n", stderr); return 1;
    }
    puts("PASS CPU measurement excludes long gaps instead of diluting active usage");
    if (mb_scale_ticks(24000000,0,125,3) != 1000000000 || mb_scale_ticks(12000000,12000000,125,3) != 1000000000 || mb_scale_ticks(42,8,1,1) != 50 || mb_scale_ticks(UINT64_MAX,UINT64_MAX,125,3) != UINT64_MAX) { fputs("FAIL clock conversion\n",stderr); return 1; }
    MBProcess *before=calloc(4096,sizeof(MBProcess)), *after=calloc(4096,sizeof(MBProcess));
    size_t n=mb_read_processes(before,4096);uint64_t start=0,end=0;
    for(size_t i=0;i<n;i++) if(before[i].pid==getpid())start=before[i].cpu_nanoseconds;
    double began=process_cpu();volatile unsigned long work=0;while(process_cpu()-began<0.12) work++;
    n=mb_read_processes(after,4096);double elapsed=process_cpu()-began;
    for(size_t i=0;i<n;i++) if(after[i].pid==getpid())end=after[i].cpu_nanoseconds;
    free(before);free(after);
    double measured=(end-start)/1e9;
    if(start==0 || end<=start || fabs(measured-elapsed)>0.035) { fprintf(stderr,"FAIL native CPU clock: measured %.6fs vs CPU clock %.6fs\n", measured,elapsed);return 1; }
    printf("PASS native Apple-silicon CPU timebase: adapter %.6fs vs process CPU clock %.6fs\n",measured,elapsed);return 0;
}
