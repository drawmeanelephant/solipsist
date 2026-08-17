#!/bin/bash
# Solipsist — testdata wrapper
# Generates a realistic test corpus in /tmp if boris-testdata exists.
# Exits 0 if no testdata binary is present.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTDATA="${SOLIPSIST_TESTDATA_BIN:-}"

if [[ -z "$TESTDATA" || ! -x "$TESTDATA" ]]; then
  for c in \
    "$ROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris-testdata" \
    "$ROOT/../boris-agent-kit/bin/boris-testdata" \
    "$ROOT/../boris/zig-out/bin/boris-testdata" \
    "$ROOT/../../boris/zig-out/bin/boris-testdata" \
    "$ROOT/../../../boris/zig-out/bin/boris-testdata"
  do
    if [[ -x "$c" ]]; then TESTDATA="$c"; break; fi
  done
fi

if [[ -z "${TESTDATA:-}" || ! -x "${TESTDATA:-}" ]]; then
  echo "stunt-from-testdata: no testdata binary (exit 0)"
  exit 0
fi

OUT_DIR="/tmp/solipsist-testdata-$(date +%s)"
mkdir -p "$OUT_DIR"

"$TESTDATA" generate --recipe readme-realistic-v1 --out "$OUT_DIR" --force

echo "$OUT_DIR"
exit 0
