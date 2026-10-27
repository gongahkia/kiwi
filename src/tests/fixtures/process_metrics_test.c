#ifdef __APPLE__
#define _DARWIN_C_SOURCE 1
#endif
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

uint64_t kiwi_process_resident_bytes(void);
double kiwi_process_monotonic_seconds(void);
const char *kiwi_process_monotonic_clock(void);

static double expected_clock(void) {
  struct timespec value;
#ifdef __APPLE__
  assert(strcmp(kiwi_process_monotonic_clock(), "CLOCK_MONOTONIC_RAW") == 0);
  assert(clock_gettime(CLOCK_MONOTONIC_RAW, &value) == 0);
#else
  assert(strcmp(kiwi_process_monotonic_clock(), "CLOCK_MONOTONIC") == 0);
  assert(clock_gettime(CLOCK_MONOTONIC, &value) == 0);
#endif
  return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

int main(void) {
  double previous = 0;
  for (unsigned i = 0; i < 10000; ++i) {
    double lower = expected_clock();
    double measured = kiwi_process_monotonic_seconds();
    double upper = expected_clock();
    assert(measured >= previous && measured >= lower && measured <= upper);
    previous = measured;
  }
  const size_t bytes = 16 * 1024 * 1024;
  uint64_t before = kiwi_process_resident_bytes();
  assert(before > 0);
  double start = kiwi_process_monotonic_seconds();
  assert(start >= 0);
  volatile unsigned char *allocation = malloc(bytes);
  assert(allocation);
  for (size_t i = 0; i < bytes; ++i) allocation[i] = (unsigned char)i;
  struct timespec delay = {0, 10000000};
  nanosleep(&delay, NULL);
  assert(kiwi_process_monotonic_seconds() >= start + 0.005);
  uint64_t after = kiwi_process_resident_bytes();
  assert(after > before + bytes / 2);
  assert(allocation[bytes - 1] == 255);
  free((void *)allocation);
  puts("Process metrics tests passed: 10,000 ordered clock-domain checks and resident growth after touching 16 MiB.");
  return 0;
}
