#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

uint64_t kiwi_process_resident_bytes(void);
double kiwi_process_monotonic_seconds(void);

int main(void) {
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
  puts("Process metrics tests passed: monotonic time and resident growth after touching 16 MiB.");
  return 0;
}
