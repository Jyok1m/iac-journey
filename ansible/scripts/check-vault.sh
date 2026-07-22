#!/usr/bin/env bash
set -euo pipefail

fail=0
for f in "$@"; do
  [ -f "$f" ] || continue
  if ! head -c 20 "$f" | grep -q "^\$ANSIBLE_VAULT"; then
    echo "REFUSE: $f nest pas chiffre (ansible-vault)."
    fail=1
  fi
done
exit $fail
