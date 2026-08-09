#include <strok/c_api.h>

int main(void) {
  const uint32_t version = STROK_C_ABI_VERSION;
  return version == UINT32_C(0x00010000) ? 0 : 1;
}
