#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef KIWI_SOURCE_ROOT
#error "KIWI_SOURCE_ROOT must be defined"
#endif

#ifndef KIWI_SOURCE_LUAJIT
#error "KIWI_SOURCE_LUAJIT must be defined"
#endif

static int set_environment(const char *name, const char *value) {
  if (setenv(name, value, 1) == 0) return 0;
  fprintf(stderr, "Kiwi launcher: could not set %s: %s\n", name, strerror(errno));
  return 1;
}

int main(int argc, char *argv[]) {
  const char *const root = KIWI_SOURCE_ROOT;
  const char *const luajit = KIWI_SOURCE_LUAJIT;
  const size_t root_length = strlen(root);
  const char *const lua_path_suffix = "/src/?.lua;";
  const char *const lua_path_middle = "/src/?/init.lua;;";
  const char *const script_suffix = "/src/kiwi/app/main.lua";
  const char *const pid_suffix = "/.build/kiwi-dev.pid";
  const size_t lua_path_length = root_length * 2 + strlen(lua_path_suffix) + strlen(lua_path_middle) + 1;
  const size_t script_length = root_length + strlen(script_suffix) + 1;
  const size_t pid_path_length = root_length + strlen(pid_suffix) + 1;
  char *const lua_path = malloc(lua_path_length);
  char *const script = malloc(script_length);
  char *const pid_path = malloc(pid_path_length);
  char **const arguments = calloc((size_t)argc + 2, sizeof(*arguments));

  if (lua_path == NULL || script == NULL || pid_path == NULL || arguments == NULL) {
    fputs("Kiwi launcher: out of memory\n", stderr);
    free(arguments);
    free(pid_path);
    free(script);
    free(lua_path);
    return 1;
  }

  snprintf(lua_path, lua_path_length, "%s%s%s%s", root, lua_path_suffix, root, lua_path_middle);
  snprintf(script, script_length, "%s%s", root, script_suffix);
  snprintf(pid_path, pid_path_length, "%s%s", root, pid_suffix);
  if (set_environment("KIWI_ROOT", root) != 0 || set_environment("LUA_PATH", lua_path) != 0) {
    free(arguments);
    free(pid_path);
    free(script);
    free(lua_path);
    return 1;
  }

  arguments[0] = (char *)luajit;
  arguments[1] = script;
  for (int index = 1; index < argc; index += 1) arguments[index + 1] = argv[index];
  const pid_t child = fork();
  if (child < 0) {
    fprintf(stderr, "Kiwi launcher: could not fork: %s\n", strerror(errno));
    free(arguments);
    free(pid_path);
    free(script);
    free(lua_path);
    return 1;
  }
  if (child == 0) {
    execv(luajit, arguments);
    fprintf(stderr, "Kiwi launcher: could not execute %s: %s\n", luajit, strerror(errno));
    _exit(127);
  }

  FILE *pid_file = fopen(pid_path, "w");
  int pid_write_failed = pid_file == NULL;
  if (!pid_write_failed && fprintf(pid_file, "%ld\n", (long)child) < 0) pid_write_failed = 1;
  if (!pid_write_failed) {
    if (fclose(pid_file) != 0) pid_write_failed = 1;
    pid_file = NULL;
  }
  if (pid_write_failed) {
    fprintf(stderr, "Kiwi launcher: could not write %s: %s\n", pid_path, strerror(errno));
    if (pid_file != NULL) fclose(pid_file);
    kill(child, SIGTERM);
    waitpid(child, NULL, 0);
    free(arguments);
    free(pid_path);
    free(script);
    free(lua_path);
    return 1;
  }

  int child_status;
  while (waitpid(child, &child_status, 0) < 0) {
    if (errno != EINTR) {
      fprintf(stderr, "Kiwi launcher: could not wait for child: %s\n", strerror(errno));
      unlink(pid_path);
      free(arguments);
      free(pid_path);
      free(script);
      free(lua_path);
      return 1;
    }
  }
  unlink(pid_path);
  free(arguments);
  free(pid_path);
  free(script);
  free(lua_path);
  return WIFEXITED(child_status) ? WEXITSTATUS(child_status) : 1;
}
