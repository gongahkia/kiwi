#!/bin/sh
set -eu

printf '%s' "$(basename "$0")" >> "$KIWI_SSH_TEST_LOG"
for argument in "$@"; do printf '|%s' "$argument" >> "$KIWI_SSH_TEST_LOG"; done
printf '\n' >> "$KIWI_SSH_TEST_LOG"
