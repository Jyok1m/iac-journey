#!/usr/bin/env bash
set -euo pipefail

fail=0
for f in "$@"; do
  echo "REFUSE: $f - ne commite pas de .env (chiffre-le ou utilise .env.example)."
  fail=1
done
exit $fail
