#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static char *app_root(void) {
  char executable[PATH_MAX];
  uint32_t executable_size = (uint32_t)sizeof(executable);
  if (_NSGetExecutablePath(executable, &executable_size) != 0) {
    fputs("Kiwi launcher: executable path is too long\n", stderr);
    return NULL;
  }

  char resolved[PATH_MAX];
  if (realpath(executable, resolved) == NULL) {
    fprintf(stderr, "Kiwi launcher: could not resolve executable path: %s\n", strerror(errno));
    return NULL;
  }
  for (int component = 0; component < 4; component += 1) {
    char *const slash = strrchr(resolved, '/');
    if (slash == NULL || slash == resolved) {
      fputs("Kiwi launcher: executable is not inside a Kiwi.app bundle\n", stderr);
      return NULL;
    }
    *slash = '\0';
  }
  return strdup(resolved);
}

int main(int argc, char *argv[]) {
  char *const root = app_root();
  if (root == NULL) return 1;

  const size_t launcher_length = strlen(root) + strlen("/bin/kiwi") + 1;
  const size_t bundle_length = strlen(root) + strlen("/Kiwi.app") + 1;
  char *const launcher = malloc(launcher_length);
  char *const bundle = malloc(bundle_length);
  char **const arguments = calloc((size_t)argc + 1, sizeof(*arguments));
  if (launcher == NULL || bundle == NULL || arguments == NULL) {
    fputs("Kiwi launcher: out of memory\n", stderr);
    free(arguments);
    free(bundle);
    free(launcher);
    free(root);
    return 1;
  }
  snprintf(launcher, launcher_length, "%s/bin/kiwi", root);
  snprintf(bundle, bundle_length, "%s/Kiwi.app", root);
  if (setenv("KIWI_APP_BUNDLE", bundle, 1) != 0) {
    fprintf(stderr, "Kiwi launcher: could not set KIWI_APP_BUNDLE: %s\n", strerror(errno));
    free(arguments);
    free(bundle);
    free(launcher);
    free(root);
    return 1;
  }
  arguments[0] = launcher;
  for (int index = 1; index < argc; index += 1) arguments[index] = argv[index];

  const pid_t child = fork();
  if (child < 0) {
    fprintf(stderr, "Kiwi launcher: could not fork: %s\n", strerror(errno));
    free(arguments);
    free(bundle);
    free(launcher);
    free(root);
    return 1;
  }
  if (child == 0) {
    execv(launcher, arguments);
    fprintf(stderr, "Kiwi launcher: could not execute %s: %s\n", launcher, strerror(errno));
    _exit(127);
  }
  int child_status;
  while (waitpid(child, &child_status, 0) < 0) {
    if (errno != EINTR) {
      fprintf(stderr, "Kiwi launcher: could not wait for child: %s\n", strerror(errno));
      free(arguments);
      free(bundle);
      free(launcher);
      free(root);
      return 1;
    }
  }
  const int status = WIFEXITED(child_status) ? WEXITSTATUS(child_status) : 1;
  free(arguments);
  free(bundle);
  free(launcher);
  free(root);
  return status;
}
