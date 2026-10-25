/* Independent POSIX ERE oracle for generated ASCII search cases. */
#define _POSIX_C_SOURCE 200809L
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
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
    int result = regcomp(&expression, line, REG_EXTENDED);
    if (result != 0) { puts("invalid"); continue; }
    regfree(&expression);
    /* Darwin's unanchored ERE optimization can skip valid starts with bounded
       repeats. Anchor each candidate offset and inspect the outer capture;
       the input and its ^/$ semantics remain intact. This is deliberately an
       independent, slow oracle, not the product's matching algorithm. */
    size_t size = strlen(line) + 64;
    char *anchored = malloc(size);
    if (anchored == NULL) return 2;
    int found = 0;
    for (size_t offset = 0; offset <= strlen(text); offset++) {
      snprintf(anchored, size, "^.{%zu}(%s)", offset, line);
      if (regcomp(&expression, anchored, REG_EXTENDED) != 0) { free(anchored); return 2; }
      regmatch_t matches[2];
      result = regexec(&expression, text, 2, matches, 0);
      if (result == 0) {
        printf("%lld %lld\n", (long long)matches[1].rm_so + 1, (long long)matches[1].rm_eo);
        found = 1;
      } else if (result != REG_NOMATCH) { regfree(&expression); free(anchored); return 2; }
      regfree(&expression);
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
