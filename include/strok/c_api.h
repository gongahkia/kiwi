#ifndef STROK_C_API_H
#define STROK_C_API_H

#include <stdint.h>

/*
 * C ABI policy:
 *
 * - Future exported functions use STROK_C_API and STROK_C_CALL. The build
 *   defining STROK_C_API_BUILD owns their exported definitions; consumers only
 *   import them on Windows.
 * - All ABI scalars use fixed-width integer types from <stdint.h>. Future public
 *   structures begin with version and size fields and grow only additively within
 *   one ABI major version.
 * - No C++ exceptions, references, STL types, or C++ object layouts cross this
 *   boundary. ABI functions report failures through C-safe result values.
 */

#define STROK_C_ABI_VERSION_MAJOR 1u
#define STROK_C_ABI_VERSION_MINOR 0u
#define STROK_C_ABI_VERSION ((STROK_C_ABI_VERSION_MAJOR << 16) | STROK_C_ABI_VERSION_MINOR)

#if defined(_WIN32) || defined(__CYGWIN__)
  #if defined(STROK_C_API_BUILD)
    #define STROK_C_API __declspec(dllexport)
  #else
    #define STROK_C_API __declspec(dllimport)
  #endif
  #define STROK_C_CALL __cdecl
#elif defined(__GNUC__) || defined(__clang__)
  #define STROK_C_API __attribute__((visibility("default")))
  #define STROK_C_CALL
#else
  #define STROK_C_API
  #define STROK_C_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* C ABI declarations are added in later compatibility layers. */

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* STROK_C_API_H */
