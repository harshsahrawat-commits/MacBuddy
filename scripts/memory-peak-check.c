#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

// A real short allocation burst between the observer's one-second samples.
// It runs in this disposable process, never in the user's Mac Buddy instance.
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int output[2]; if (pipe(output) != 0) return 1;
    char pid[32]; snprintf(pid, sizeof(pid), "%d", getpid());
    pid_t observer = fork();
    if (observer < 0) return 1;
    if (observer == 0) {
        close(output[0]); dup2(output[1], STDOUT_FILENO); close(output[1]);
        execl(argv[1], argv[1], pid, "3", NULL); _exit(127);
    }
    close(output[1]);
    FILE *stream = fdopen(output[0], "r");
    if (!stream) return 1;
    char line[2048];
    if (!fgets(line, sizeof(line), stream) || strncmp(line, "START ", 6) != 0) {
        fputs("FAIL memory observer did not start\n", stderr); fclose(stream); waitpid(observer, NULL, 0); return 1;
    }
    usleep(250000);
    size_t length = 96 * 1024 * 1024;
    volatile unsigned char *burst = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (burst == MAP_FAILED) { fclose(stream); waitpid(observer, NULL, 0); return 1; }
    size_t page = (size_t)getpagesize();
    for (size_t i = 0; i < length; i += page) burst[i] = 1;
    usleep(10000);
    munmap((void *)burst, length);
    double start = 0, end = 0;
    int found = 0, complete = 0;
    while (fgets(line, sizeof(line), stream)) {
        if (sscanf(line, "LIFETIME_PEAK start_mib=%lf end_mib=%lf", &start, &end) == 2) found = 1;
        if (strncmp(line, "COMPLETE ", 9) == 0) complete = 1;
    }
    fclose(stream);
    int status = 0; waitpid(observer, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0 || !complete || !found || end < start + 64) {
        fprintf(stderr, "FAIL short memory burst not preserved: start=%.2f end=%.2f found=%d\n", start, end, found); return 1;
    }
    printf("PASS kernel lifetime peak preserves brief memory burst: %.2f -> %.2f MiB\n", start, end);
    return 0;
}
