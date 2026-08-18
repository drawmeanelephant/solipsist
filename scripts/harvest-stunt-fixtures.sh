#!/usr/bin/env bash
# Rebuild Tests/Fixtures from Stunts/ using a local boris binary.
# Does not run in CI. Never writes into Stunts/ permanently.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BORIS="${SOLIPSIST_BORIS_BIN:-}"
if [[ -z "$BORIS" || ! -x "$BORIS" ]]; then
  for c in \
    "$ROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris" \
    "$ROOT/../grok-base/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris"
  do
    if [[ -x "$c" ]]; then BORIS="$c"; break; fi
  done
fi
if [[ ! -x "${BORIS:-}" ]]; then
  echo "harvest: no boris binary (set SOLIPSIST_BORIS_BIN)" >&2
  exit 1
fi

FIX="$ROOT/Tests/Fixtures"
STUNTS="$ROOT/Stunts"
TMP="$ROOT/.stunt-harvest"
rm -rf "$TMP"
mkdir -p "$TMP" "$FIX/happy-ir" "$FIX/dogfood-ir" "$FIX/broken-frontmatter" "$FIX/broken-parent" "$FIX/validate-happy" "$FIX/plan-happy"

(cd "$STUNTS/happy" && "$BORIS" --out "$TMP/happy-ir" --input content --quiet)
cp "$TMP/happy-ir/"*.json "$FIX/happy-ir/"

(cd "$STUNTS/dogfood" && "$BORIS" --out "$TMP/dogfood-ir" --input content --quiet)
cp "$TMP/dogfood-ir/"*.json "$FIX/dogfood-ir/"

(cd "$STUNTS/happy" && "$BORIS" validate --input content --report "$FIX/validate-happy/html-build-report.json")
(cd "$STUNTS/happy" && "$BORIS" plan --profile boris.json > "$FIX/plan-happy/plan.json")

(cd "$STUNTS" && "$BORIS" --out "$TMP/broken-fm" --input broken-frontmatter --quiet || true)
cp "$TMP/broken-fm/build-report.json" "$FIX/broken-frontmatter/"

(cd "$STUNTS" && "$BORIS" --out "$TMP/broken-parent" --input broken-parent --quiet || true)
cp "$TMP/broken-parent/build-report.json" "$FIX/broken-parent/"

rm -rf "$TMP"
echo "harvest: wrote $FIX"
