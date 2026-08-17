#!/bin/bash
# Solipsist — Stunt smoke script
# Runs Boris engine against Stunts and validates expected contracts and exit codes.
# Exits 0 if no binary is present.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BORIS="${SOLIPSIST_BORIS_BIN:-}"

if [[ -z "$BORIS" || ! -x "$BORIS" ]]; then
  for c in \
    "$ROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris" \
    "$ROOT/../boris-agent-kit/bin/boris" \
    "$ROOT/../boris/zig-out/bin/boris" \
    "$ROOT/../../boris/zig-out/bin/boris" \
    "$ROOT/../../../boris/zig-out/bin/boris"
  do
    if [[ -x "$c" ]]; then BORIS="$c"; break; fi
  done
fi

if [[ -z "${BORIS:-}" || ! -x "${BORIS:-}" ]]; then
  echo "stunt-smoke: no boris binary found; skipping smoke tests (exit 0)"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUNTS="$ROOT/Stunts"

echo "==> Running smoke tests with $BORIS"

# 1. Happy IR build
echo "==> Testing Stunts/happy IR build"
(cd "$STUNTS/happy" && "$BORIS" --out "$TMP/happy-ir" --input content --quiet)
if ! grep -q '"ok": true' "$TMP/happy-ir/build-report.json"; then
  echo "ERROR: expected ok: true in happy build-report.json" >&2
  exit 1
fi

# 2. Happy validate
echo "==> Testing Stunts/happy validate"
(cd "$STUNTS/happy" && "$BORIS" validate --input content --report "$TMP/validate.json")

# 3. Happy plan
echo "==> Testing Stunts/happy plan"
(cd "$STUNTS/happy" && "$BORIS" plan --profile boris.json > "$TMP/plan.json")

# 4. Broken frontmatter
echo "==> Testing Stunts/broken-frontmatter"
(cd "$STUNTS" && "$BORIS" --out "$TMP/broken-fm" --input broken-frontmatter --quiet || true)
if ! grep -q 'EFRONTMATTER' "$TMP/broken-fm/build-report.json"; then
  echo "ERROR: expected EFRONTMATTER in broken-frontmatter build-report.json" >&2
  exit 1
fi

# 5. Broken parent
echo "==> Testing Stunts/broken-parent"
(cd "$STUNTS" && "$BORIS" --out "$TMP/broken-parent" --input broken-parent --quiet || true)
if ! grep -q 'EPARENTMISSING' "$TMP/broken-parent/build-report.json"; then
  echo "ERROR: expected EPARENTMISSING in broken-parent build-report.json" >&2
  exit 1
fi

echo "==> Stunt smoke tests passed!"
exit 0
