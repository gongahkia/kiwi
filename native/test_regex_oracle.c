/* Independent POSIX ERE oracle for generated ASCII search cases. */
#define _POSIX_C_SOURCE 200809L
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  /* A broken system oracle must fail the gate, never hang CI indefinitely. */
  alarm(60);
  setvbuf(stdout, NULL, _IONBF, 0);
  FILE *input = fopen(argv[1], "rb");
  if (input == NULL) return 2;
  char *line = NULL;
  size_t capacity = 0;
  while (getline(&line, &capacity, input) >= 0) {
    char *text = strchr(line, '\t');
    if (text == NULL || strlen(line) > 65536) return 2;
    *text++ = '\0';
    text[strcspn(text, "\r\n")] = '\0';
    regex_t expression;
    int result = regcomp(&expression, line, REG_EXTENDED | REG_NOSUB);
    if (result != 0) { puts("invalid"); continue; }
    regfree(&expression);
    /* Darwin's unanchored ERE optimization can skip valid starts with bounded
       repeats. Use capture-free existence queries at each candidate offset,
       then constrain the suffix to find the longest end without depending on
       libc's submatch disambiguation. Inputs with deeply nested repetition
       use Darwin only in the generator because glibc can still stall on them.
       The full input and ^/$ semantics remain intact. This is deliberately
       an independent, slow oracle, not the product's matching algorithm. */
    size_t size = strlen(line) + 128;
    char *anchored = malloc(size);
    if (anchored == NULL) return 2;
    int found = 0;
    size_t length = strlen(text);
    for (size_t offset = 0; offset <= length; offset++) {
      snprintf(anchored, size, "^.{%zu}(%s)", offset, line);
      if (regcomp(&expression, anchored, REG_EXTENDED | REG_NOSUB) != 0) { free(anchored); return 2; }
      result = regexec(&expression, text, 0, NULL, 0);
      regfree(&expression);
      if (result == 0) {
        for (size_t suffix = 0; suffix <= length - offset; suffix++) {
          snprintf(anchored, size, "^.{%zu}(%s).{%zu}$", offset, line, suffix);
          if (regcomp(&expression, anchored, REG_EXTENDED | REG_NOSUB) != 0) { free(anchored); return 2; }
          result = regexec(&expression, text, 0, NULL, 0);
          regfree(&expression);
          if (result == 0) {
            printf("%zu %zu\n", offset + 1, length - suffix);
            found = 1;
            break;
          }
          if (result != REG_NOMATCH) { free(anchored); return 2; }
        }
        if (!found) { free(anchored); return 2; }
      } else if (result != REG_NOMATCH) { free(anchored); return 2; }
      if (found) break;
    }
    if (!found) puts("none");
    free(anchored);
  }
  int failed = ferror(input);
  free(line);
  fclose(input);
  return failed ? 2 : 0;
}
