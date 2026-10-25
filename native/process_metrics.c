#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

/* Internal benchmark observations, not peak RSS or system-wide memory. */
uint64_t kiwi_process_resident_bytes(void) {
#ifdef __APPLE__
  mach_task_basic_info_data_t info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
  return info.resident_size;
#else
  FILE *file = fopen("/proc/self/statm", "r");
  if (!file) return 0;
  unsigned long long virtual_pages, resident_pages;
  int read = fscanf(file, "%llu %llu", &virtual_pages, &resident_pages);
  fclose(file);
  long page_size = sysconf(_SC_PAGESIZE);
  if (read != 2 || page_size <= 0 || resident_pages > UINT64_MAX / (uint64_t)page_size) return 0;
  return (uint64_t)resident_pages * (uint64_t)page_size;
#endif
}

double kiwi_process_monotonic_seconds(void) {
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
  return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}
