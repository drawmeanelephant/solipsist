#!/bin/bash
#
# Copies the Boris engine binary into the app bundle's Resources so the
# app can find it at runtime (BorisBinary.locate checks
# Bundle.main.resourceURL/boris).
#
# Search order:
#   1. SOLIPSIST_BORIS_BIN
#   2. Prebuilt kit next to this repo (SUPPORT-NOT-FOR-GITHUB / sibling kit)
#   3. Existing zig-out in a boris checkout
#   4. Build from BORIS_REPO_DIR (default: ../boris)
#
# Usage: embed-boris.sh SRCROOT DEST_DIR

set -euo pipefail

SRCROOT="${1:?usage: embed-boris.sh SRCROOT DEST_DIR}"
DEST_DIR="${2:?usage: embed-boris.sh SRCROOT DEST_DIR}"

find_prebuilt() {
  if [[ -n "${SOLIPSIST_BORIS_BIN:-}" && -x "${SOLIPSIST_BORIS_BIN}" ]]; then
    echo "${SOLIPSIST_BORIS_BIN}"
    return 0
  fi
  local candidates=(
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris"
    "$SRCROOT/../boris-agent-kit/bin/boris"
    "$SRCROOT/../boris/zig-out/bin/boris"
    "$SRCROOT/../../boris/zig-out/bin/boris"
    "$SRCROOT/../../../boris/zig-out/bin/boris"
  )
  local c
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

bundle_binary() {
  local src="$1"
  mkdir -p "$DEST_DIR"
  cp "$src" "$DEST_DIR/boris"
  chmod +x "$DEST_DIR/boris"
  echo "embed-boris: bundled $DEST_DIR/boris ($(du -h "$DEST_DIR/boris" | cut -f1)) from $src"
}

if BIN="$(find_prebuilt)"; then
  bundle_binary "$BIN"
  exit 0
fi

# CI compiles the app without a bundled engine. Local `make build` still
# requires a kit or a boris checkout.
if [[ "${SKIP_EMBED_BORIS:-}" == "1" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "embed-boris: no engine available — compiling without a bundle"
  mkdir -p "$DEST_DIR"
  exit 0
fi

BORIS_REPO="${BORIS_REPO_DIR:-$SRCROOT/../boris}"
BIN="$BORIS_REPO/zig-out/bin/boris"

if [[ ! -x "$BIN" ]]; then
  echo "embed-boris: building Boris engine (first run takes a few minutes)…"
  (cd "$BORIS_REPO" && zig build) || {
    echo "embed-boris: FAILED to find or build a boris binary" >&2
    echo "embed-boris: set SOLIPSIST_BORIS_BIN or place the agent kit under SUPPORT-NOT-FOR-GITHUB/" >&2
    exit 1
  }
fi

bundle_binary "$BIN"
