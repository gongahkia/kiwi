#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: scripts/check-dco.sh <git-rev-range>" >&2
  exit 64
fi

commits_output="$(git rev-list --reverse "$1")"
if [[ -z "$commits_output" ]]; then
  echo "No commits to check."
  exit 0
fi

missing=0
while IFS= read -r commit; do
  if git log -1 --format=%B "$commit" \
    | git interpret-trailers --parse \
    | grep -Eiq '^Signed-off-by: .+ <[^>]+>$'; then
    continue
  fi

  subject="$(git log -1 --format=%s "$commit")"
  short="${commit:0:12}"
  echo "::error title=DCO sign-off missing::$short $subject is missing a Signed-off-by trailer."
  missing=1
done <<< "$commits_output"

if [[ "$missing" -ne 0 ]]; then
  echo "Every PR commit must include Signed-off-by. Use git commit -s or git commit --amend -s." >&2
fi

exit "$missing"
