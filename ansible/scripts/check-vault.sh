#!/usr/bin/env bash
set -euo pipefail
rc=0
for f in "$@"; do
  if ! head -n1 "$f" | grep -q '^\$ANSIBLE_VAULT;'; then
    echo "not encrypted: $f" >&2
    rc=1
  fi
done
exit $rc
