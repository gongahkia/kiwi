#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifndef KIWI_APP_LUA_ROOT_RELATIVE
#error "KIWI_APP_LUA_ROOT_RELATIVE must be defined"
#endif

#ifndef KIWI_APP_TERMINFO_RELATIVE
#error "KIWI_APP_TERMINFO_RELATIVE must be defined"
#endif

#ifndef KIWI_APP_WGPU_LIBRARY_RELATIVE
#error "KIWI_APP_WGPU_LIBRARY_RELATIVE must be defined"
#endif

#ifndef KIWI_APP_SURFACE_LIBRARY_RELATIVE
#error "KIWI_APP_SURFACE_LIBRARY_RELATIVE must be defined"
#endif

#ifndef KIWI_APP_INTEGRATION_RELATIVE
#error "KIWI_APP_INTEGRATION_RELATIVE must be defined"
#endif

#ifndef KIWI_APP_RELEASE
#error "KIWI_APP_RELEASE must be defined"
#endif

#ifndef KIWI_APP_PID_FILE_RELATIVE
#error "KIWI_APP_PID_FILE_RELATIVE must be defined"
#endif

#ifndef KIWI_APP_ROOT_PARENT_COMPONENTS
#error "KIWI_APP_ROOT_PARENT_COMPONENTS must be defined"
#endif

#define KIWI_LUA_OK 0
#define KIWI_LUA_GLOBALSINDEX (-10002)

typedef struct lua_State lua_State;

static char kiwi_pid_path[PATH_MAX];

typedef struct KiwiLuaApi {
  void *library;
  lua_State *(*luaL_newstate)(void);
  void (*luaL_openlibs)(lua_State *state);
  int (*luaL_loadfile)(lua_State *state, const char *path);
  int (*lua_pcall)(lua_State *state, int arguments, int results, int error_function);
  void (*lua_close)(lua_State *state);
  void (*lua_createtable)(lua_State *state, int array_count, int record_count);
  const char *(*lua_pushstring)(lua_State *state, const char *value);
  void (*lua_rawseti)(lua_State *state, int index, int array_index);
  void (*lua_setfield)(lua_State *state, int index, const char *name);
  const char *(*lua_tolstring)(lua_State *state, int index, size_t *length);
} KiwiLuaApi;

static int kiwi_set_environment(const char *name, const char *value) {
  if (setenv(name, value, 1) == 0) return 0;
  fprintf(stderr, "Kiwi app host: could not set %s: %s\n", name, strerror(errno));
  return 1;
}

static int kiwi_remove_components(char *path, size_t count) {
  for (size_t component = 0; component < count; component += 1) {
    char *const slash = strrchr(path, '/');
    if (slash == NULL || slash == path) return 1;
    *slash = '\0';
  }
  return 0;
}

static int kiwi_application_paths(char *root, size_t root_size, char *bundle, size_t bundle_size) {
  char executable[PATH_MAX];
  uint32_t executable_size = (uint32_t)sizeof(executable);
  if (_NSGetExecutablePath(executable, &executable_size) != 0) {
    fputs("Kiwi app host: executable path is too long\n", stderr);
    return 1;
  }
  char resolved[PATH_MAX];
  if (realpath(executable, resolved) == NULL) {
    fprintf(stderr, "Kiwi app host: could not resolve executable path: %s\n", strerror(errno));
    return 1;
  }
  if (strlen(resolved) >= bundle_size || strlen(resolved) >= root_size) {
    fputs("Kiwi app host: resolved application path is too long\n", stderr);
    return 1;
  }
  (void)snprintf(bundle, bundle_size, "%s", resolved);
  (void)snprintf(root, root_size, "%s", resolved);
  if (kiwi_remove_components(bundle, 3) != 0 ||
      kiwi_remove_components(root, 3 + KIWI_APP_ROOT_PARENT_COMPONENTS) != 0) {
    fputs("Kiwi app host: executable is not inside a Kiwi.app-style bundle\n", stderr);
    return 1;
  }
  return 0;
}

static int kiwi_join(char *output, size_t output_size, const char *left, const char *right) {
  int written = snprintf(output, output_size, "%s/%s", left, right);
  return written < 0 || (size_t)written >= output_size;
}

static int kiwi_configure_environment(const char *root, const char *bundle) {
  char lua_root[PATH_MAX];
  char terminfo[PATH_MAX];
  char wgpu_library[PATH_MAX];
  char surface_library[PATH_MAX];
  char integration_directory[PATH_MAX];
  char lua_path[PATH_MAX * 2 + 32];
  if (kiwi_join(lua_root, sizeof(lua_root), root, KIWI_APP_LUA_ROOT_RELATIVE) != 0 ||
      kiwi_join(terminfo, sizeof(terminfo), root, KIWI_APP_TERMINFO_RELATIVE) != 0 ||
      kiwi_join(wgpu_library, sizeof(wgpu_library), root, KIWI_APP_WGPU_LIBRARY_RELATIVE) != 0 ||
      kiwi_join(surface_library, sizeof(surface_library), root, KIWI_APP_SURFACE_LIBRARY_RELATIVE) != 0 ||
      kiwi_join(integration_directory, sizeof(integration_directory), root, KIWI_APP_INTEGRATION_RELATIVE) != 0) {
    fputs("Kiwi app host: application resource path is too long\n", stderr);
    return 1;
  }
  int lua_path_length = snprintf(lua_path, sizeof(lua_path), "%s/?.lua;%s/?/init.lua;;", lua_root, lua_root);
  if (lua_path_length < 0 || (size_t)lua_path_length >= sizeof(lua_path)) {
    fputs("Kiwi app host: Lua module path is too long\n", stderr);
    return 1;
  }
  const char *existing_path = getenv("PATH");
  size_t path_length = strlen(root) + strlen("/bin:") + (existing_path == NULL ? 0 : strlen(existing_path)) + 1;
  char *path = malloc(path_length);
  if (path == NULL) {
    fputs("Kiwi app host: out of memory while configuring PATH\n", stderr);
    return 1;
  }
  (void)snprintf(path, path_length, "%s/bin:%s", root, existing_path == NULL ? "" : existing_path);
  int failed = kiwi_set_environment("KIWI_ROOT", root) ||
               kiwi_set_environment("KIWI_APP_BUNDLE", bundle) ||
               kiwi_set_environment("KIWI_LUA_ROOT", lua_root) ||
               kiwi_set_environment("KIWI_WGPU_LIB", wgpu_library) ||
               kiwi_set_environment("KIWI_SURFACE_LIB", surface_library) ||
               kiwi_set_environment("TERMINFO", terminfo) ||
               kiwi_set_environment("KIWI_TERMINFO", terminfo) ||
               kiwi_set_environment("KIWI_INTEGRATION_DIR", integration_directory) ||
               kiwi_set_environment("LUA_PATH", lua_path) ||
               kiwi_set_environment("PATH", path);
  if (!failed) failed = kiwi_set_environment("KIWI_RELEASE", KIWI_APP_RELEASE ? "1" : "0");
  free(path);
  return failed;
}

static void *kiwi_load_luajit(void) {
  const char *const configured = getenv("KIWI_LUAJIT_LIB");
  const char *const compatibility_configured = getenv("KIWI_VT_LUAJIT_LIB");
  static const char *const names[] = {
      "/opt/homebrew/opt/luajit/lib/libluajit-5.1.2.dylib",
      "/usr/local/opt/luajit/lib/libluajit-5.1.2.dylib",
      "/opt/homebrew/lib/libluajit-5.1.2.dylib",
      "/usr/local/lib/libluajit-5.1.2.dylib",
      "libluajit-5.1.2.dylib",
      "libluajit-5.1.dylib",
      "libluajit.dylib",
      NULL,
  };
  if (configured != NULL && configured[0] != '\0') {
    void *library = dlopen(configured, RTLD_NOW | RTLD_GLOBAL);
    if (library != NULL) return library;
  }
  if (compatibility_configured != NULL && compatibility_configured[0] != '\0') {
    void *library = dlopen(compatibility_configured, RTLD_NOW | RTLD_GLOBAL);
    if (library != NULL) return library;
  }
  for (size_t index = 0; names[index] != NULL; index += 1) {
    void *library = dlopen(names[index], RTLD_NOW | RTLD_GLOBAL);
    if (library != NULL) return library;
  }
  fprintf(stderr, "Kiwi app host: LuaJIT runtime unavailable%s%s: %s\n",
          configured == NULL || configured[0] == '\0' ? "" : " at ",
          configured == NULL || configured[0] == '\0' ? "" : configured,
          dlerror() == NULL ? "dlopen failed" : dlerror());
  return NULL;
}

static int kiwi_load_lua_api(KiwiLuaApi *lua) {
  memset(lua, 0, sizeof(*lua));
  lua->library = kiwi_load_luajit();
  if (lua->library == NULL) return 1;

#define KIWI_LOAD_LUA_SYMBOL(field, symbol) \
  do { \
    lua->field = dlsym(lua->library, symbol); \
    if (lua->field == NULL) { \
      fprintf(stderr, "Kiwi app host: LuaJIT runtime is missing %s\n", symbol); \
      dlclose(lua->library); \
      lua->library = NULL; \
      return 1; \
    } \
  } while (0)

  KIWI_LOAD_LUA_SYMBOL(luaL_newstate, "luaL_newstate");
  KIWI_LOAD_LUA_SYMBOL(luaL_openlibs, "luaL_openlibs");
  KIWI_LOAD_LUA_SYMBOL(luaL_loadfile, "luaL_loadfile");
  KIWI_LOAD_LUA_SYMBOL(lua_pcall, "lua_pcall");
  KIWI_LOAD_LUA_SYMBOL(lua_close, "lua_close");
  KIWI_LOAD_LUA_SYMBOL(lua_createtable, "lua_createtable");
  KIWI_LOAD_LUA_SYMBOL(lua_pushstring, "lua_pushstring");
  KIWI_LOAD_LUA_SYMBOL(lua_rawseti, "lua_rawseti");
  KIWI_LOAD_LUA_SYMBOL(lua_setfield, "lua_setfield");
  KIWI_LOAD_LUA_SYMBOL(lua_tolstring, "lua_tolstring");
#undef KIWI_LOAD_LUA_SYMBOL
  return 0;
}

static void kiwi_push_arguments(KiwiLuaApi *lua, lua_State *state, const char *script, int argc, char *argv[]) {
  lua->lua_createtable(state, argc + 1, 0);
  lua->lua_pushstring(state, argv[0]);
  lua->lua_rawseti(state, -2, -1);
  lua->lua_pushstring(state, script);
  lua->lua_rawseti(state, -2, 0);
  for (int index = 1; index < argc; index += 1) {
    lua->lua_pushstring(state, argv[index]);
    lua->lua_rawseti(state, -2, index);
  }
  lua->lua_setfield(state, KIWI_LUA_GLOBALSINDEX, "arg");
}

static int kiwi_write_pid_file(const char *root, char *path, size_t path_size) {
  if (KIWI_APP_PID_FILE_RELATIVE[0] == '\0') return 0;
  if (kiwi_join(path, path_size, root, KIWI_APP_PID_FILE_RELATIVE) != 0) {
    fputs("Kiwi app host: development PID path is too long\n", stderr);
    return 1;
  }
  FILE *file = fopen(path, "w");
  if (file == NULL) {
    fprintf(stderr, "Kiwi app host: could not write %s: %s\n", path, strerror(errno));
    return 1;
  }
  int write_failed = fprintf(file, "%ld\n", (long)getpid()) < 0;
  if (fclose(file) != 0) write_failed = 1;
  if (write_failed) {
    fprintf(stderr, "Kiwi app host: could not write %s: %s\n", path, strerror(errno));
    return 1;
  }
  return 0;
}

static void kiwi_remove_pid_file(void) {
  if (kiwi_pid_path[0] != '\0') (void)unlink(kiwi_pid_path);
}

static void kiwi_handle_termination_signal(int signal_number) {
  kiwi_remove_pid_file();
  _exit(128 + signal_number);
}

static int kiwi_install_pid_cleanup(const char *path) {
  if (path[0] == '\0') return 0;
  size_t length = strlen(path);
  if (length >= sizeof(kiwi_pid_path)) {
    fputs("Kiwi app host: development PID path is too long\n", stderr);
    return 1;
  }
  memcpy(kiwi_pid_path, path, length + 1);
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = kiwi_handle_termination_signal;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  static const int termination_signals[] = { SIGHUP, SIGINT, SIGTERM };
  for (size_t index = 0; index < sizeof(termination_signals) / sizeof(termination_signals[0]); index += 1) {
    if (sigaction(termination_signals[index], &action, NULL) != 0) {
      fprintf(stderr, "Kiwi app host: could not install PID cleanup: %s\n", strerror(errno));
      kiwi_remove_pid_file();
      return 1;
    }
  }
  return 0;
}

int main(int argc, char *argv[]) {
  char root[PATH_MAX];
  char bundle[PATH_MAX];
  char script[PATH_MAX];
  char pid_path[PATH_MAX] = { 0 };
  if (kiwi_application_paths(root, sizeof(root), bundle, sizeof(bundle)) != 0 ||
      kiwi_configure_environment(root, bundle) != 0) return 1;
  if (kiwi_join(script, sizeof(script), root, KIWI_APP_LUA_ROOT_RELATIVE "/kiwi/app/main.lua") != 0) {
    fputs("Kiwi app host: application entrypoint path is too long\n", stderr);
    return 1;
  }
  if (kiwi_write_pid_file(root, pid_path, sizeof(pid_path)) != 0 ||
      kiwi_install_pid_cleanup(pid_path) != 0) return 1;

  KiwiLuaApi lua;
  if (kiwi_load_lua_api(&lua) != 0) {
    kiwi_remove_pid_file();
    return 1;
  }
  lua_State *state = lua.luaL_newstate();
  if (state == NULL) {
    fputs("Kiwi app host: could not create a LuaJIT state\n", stderr);
    dlclose(lua.library);
    kiwi_remove_pid_file();
    return 1;
  }
  lua.luaL_openlibs(state);
  kiwi_push_arguments(&lua, state, script, argc, argv);
  int status = lua.luaL_loadfile(state, script);
  if (status == KIWI_LUA_OK) status = lua.lua_pcall(state, 0, 0, 0);
  if (status != KIWI_LUA_OK) {
    size_t length = 0;
    const char *message = lua.lua_tolstring(state, -1, &length);
    fprintf(stderr, "Kiwi app host: Lua application failed: %.*s\n", (int)(length > 1024 ? 1024 : length), message == NULL ? "unknown error" : message);
  }
  lua.lua_close(state);
  dlclose(lua.library);
  kiwi_remove_pid_file();
  return status == KIWI_LUA_OK ? 0 : 1;
}
