#!/bin/sh
# Block commits that contain private terms (names, IDs, addresses, hostnames).
# The term list lives outside this public repo: one case-insensitive regex per line in
# $PRIVATE_TERMS_FILE (default ~/.config/private-terms.txt). Install as a pre-commit hook:
#   ln -s ../../scripts/check-private-terms.sh .git/hooks/pre-commit
terms="${PRIVATE_TERMS_FILE:-$HOME/.config/private-terms.txt}"
if [ ! -s "$terms" ]; then
  echo "check-private-terms: no term list at $terms; refusing to commit unchecked." >&2
  exit 1
fi
hits=$(git diff --cached -U0 --no-color | grep '^+' | grep -v '^+++' | grep -inEf "$terms")
if [ -n "$hits" ]; then
  echo "check-private-terms: staged changes contain private terms:" >&2
  echo "$hits" >&2
  exit 1
fi
