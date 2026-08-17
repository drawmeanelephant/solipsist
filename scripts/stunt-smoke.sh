#!/bin/bash
set -euo pipefail

# stunt-smoke: Exercise the bundled or environment Boris engine against Stunts.
# Exits 0 gracefully if no engine binary is found.

BORIS_BIN="${SOLIPSIST_BORIS_BIN:-}"
if [[ -z "$BORIS_BIN" ]]; then
    if [[ -x "../boris/zig-out/bin/boris" ]]; then
        BORIS_BIN="../boris/zig-out/bin/boris"
    elif [[ -x "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris" ]]; then
        BORIS_BIN="SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris"
    elif command -v boris >/dev/null 2>&1; then
        BORIS_BIN="$(command -v boris)"
    fi
fi

if [[ -z "$BORIS_BIN" || ! -x "$BORIS_BIN" ]]; then
    echo "stunt-smoke: no boris binary found — skipping engine smoke run"
    exit 0
fi

echo "==> Using boris at $BORIS_BIN"
"$BORIS_BIN" --version

TMP_OUT="$(mktemp -d /tmp/solipsist-stunt-smoke.XXXXXX)"
trap 'rm -rf "$TMP_OUT"' EXIT

echo "==> Stunts/happy"
"$BORIS_BIN" build --input Stunts/happy --out "$TMP_OUT/happy"
test -f "$TMP_OUT/happy/build-report.json"
test -f "$TMP_OUT/happy/graph.json"

echo "==> Stunts/broken-frontmatter"
if "$BORIS_BIN" build --input Stunts/broken-frontmatter --out "$TMP_OUT/broken-frontmatter" 2>/dev/null; then
    echo "Expected broken-frontmatter to fail!"
    exit 1
fi
test -f "$TMP_OUT/broken-frontmatter/build-report.json"

echo "==> Stunts/broken-parent"
if "$BORIS_BIN" build --input Stunts/broken-parent --out "$TMP_OUT/broken-parent" 2>/dev/null; then
    echo "Expected broken-parent to fail!"
    exit 1
fi
test -f "$TMP_OUT/broken-parent/build-report.json"

echo "==> Stunt smoke suite passed successfully!"
