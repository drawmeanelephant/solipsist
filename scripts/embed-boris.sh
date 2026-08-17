#!/usr/bin/env bash
#
# Builds the Boris engine and copies its binary into the app bundle's
# Resources so the app can find it at runtime (BorisBinary.locate checks
# Bundle.main.resourceURL/boris).
#
# The boris checkout lives at ../boris by default; override with
# BORIS_REPO_DIR. Rebuilds only when the binary is missing.
#
# Usage: embed-boris.sh SRCROOT DEST_DIR

set -euo pipefail

SRCROOT="${1:?usage: embed-boris.sh SRCROOT DEST_DIR}"
DEST_DIR="${2:?usage: embed-boris.sh SRCROOT DEST_DIR}"

BORIS_REPO="${BORIS_REPO_DIR:-$SRCROOT/../boris}"
BIN="$BORIS_REPO/zig-out/bin/boris"

if [[ ! -x "$BIN" ]]; then
  echo "embed-boris: building Boris engine (first run takes a few minutes)…"
  (cd "$BORIS_REPO" && zig build) || {
    echo "embed-boris: FAILED to build Boris engine" >&2
    exit 1
  }
fi

mkdir -p "$DEST_DIR"
cp "$BIN" "$DEST_DIR/boris"
chmod +x "$DEST_DIR/boris"
echo "embed-boris: bundled $DEST_DIR/boris ($(du -h "$DEST_DIR/boris" | cut -f1))"
