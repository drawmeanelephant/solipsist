#!/bin/bash
#
# Populates a universal bin directory with lipo-merged companion tools so
# that embed-boris.sh can find them during the release build.
#
# Usage: populate-universal-companions.sh DEST_DIR
#
# Expects /tmp/boris-universal-boris-* files from the cross-build step.

set -euo pipefail

DEST_DIR="${1:?usage: populate-universal-companions.sh DEST_DIR}"

mkdir -p "$DEST_DIR"

TOOLS="boris-editor boris-package boris-source-rag boris-content-audit"
bundled=0
for tool in $TOOLS; do
  universal="/tmp/boris-universal-$tool"
  if [[ -f "$universal" ]]; then
    cp "$universal" "$DEST_DIR/$tool"
    chmod +x "$DEST_DIR/$tool"
    echo "populate-companions: $tool → $DEST_DIR/$tool"
    bundled=$((bundled + 1))
  else
    echo "populate-companions: notice: $tool not universal — skipped" >&2
  fi
done
echo "populate-companions: bundled $bundled tool(s)"
