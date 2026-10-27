#include <stdio.h>
#include <stdint.h>
#include <time.h>
static uint64_t ns(clockid_t clock) {
 struct timespec t;
 if (clock_gettime(clock,&t)) return 0;
 return (uint64_t)t.tv_sec*1000000000ULL+(uint64_t)t.tv_nsec;
}
int main(void) {
 uint64_t mono=ns(CLOCK_MONOTONIC),raw=ns(CLOCK_MONOTONIC_RAW),end=raw+45000000000ULL;
 uint64_t count=0,back=0,rawback=0,worst=0;
 do {
  uint64_t a=ns(CLOCK_MONOTONIC),b=ns(CLOCK_MONOTONIC_RAW);
  if(a<mono) { back++; if(mono-a>worst)worst=mono-a; if(back<=5)printf("backstep_ns=%llu previous=%llu current=%llu\n",(unsigned long long)(mono-a),(unsigned long long)mono,(unsigned long long)a); }
  if(b<raw)rawback++;
  mono=a;raw=b;count++;
 } while(raw<end);
 printf("samples=%llu monotonic_backsteps=%llu worst_backstep_ns=%llu raw_backsteps=%llu\n",(unsigned long long)count,(unsigned long long)back,(unsigned long long)worst,(unsigned long long)rawback);
}
