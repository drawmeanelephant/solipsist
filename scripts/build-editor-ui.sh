#!/bin/bash
#
# build-editor-ui.sh — compile the Boris editor's Svelte shell.
#
# `make build` bundles editor/ui/dist verbatim and refuses to run npm
# itself (needs node + network). This script is the explicit half of that
# split: resolve the boris checkout the same way embed-boris.sh does,
# then `npm ci && npm run build` inside editor/ui.
#
# Usage: build-editor-ui.sh [--check]
#   --check   Report freshness only (exit 1 when dist is missing or stale);
#             used by `make doctor` to catch a forgotten rebuild.
#
# Env: BORIS_REPO_DIR — required from worktrees, else the script derives
# the checkout from SOLIPSIST_BORIS_BIN inside a repo, then sibling dirs.

set -euo pipefail

CHECK_ONLY=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "build-editor-ui: FAIL — not inside a git repo" >&2
  exit 1
fi

# Mirror of embed-boris.sh's resolve_boris_repo().
resolve_boris_repo() {
  if [[ -n "${BORIS_REPO_DIR:-}" && -d "${BORIS_REPO_DIR}" ]]; then
    echo "${BORIS_REPO_DIR}"
    return 0
  fi

  if [[ -n "${SOLIPSIST_BORIS_BIN:-}" ]]; then
    local bindir
    bindir="$(dirname "${SOLIPSIST_BORIS_BIN}")"
    if [[ "$(basename "$bindir")" == "bin" && "$(basename "$(dirname "$bindir")")" == "zig-out" ]]; then
      local repo
      repo="$(dirname "$(dirname "$bindir")")"
      if [[ -f "$repo/build.zig" && -d "$repo/editor" ]]; then
        echo "$repo"
        return 0
      fi
    fi
  fi

  local c
  for c in "$ROOT/../boris" "$ROOT/../../boris" "$ROOT/../../../boris"; do
    if [[ -f "$c/build.zig" && -d "$c/editor" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

if ! repo="$(resolve_boris_repo)"; then
  echo "build-editor-ui: FAIL — no boris checkout found (set BORIS_REPO_DIR)" >&2
  exit 1
fi

ui_dir="$repo/editor/ui"
dist="$ui_dir/dist"
if [[ ! -d "$ui_dir" ]]; then
  echo "build-editor-ui: FAIL — no editor/ui in $repo" >&2
  exit 1
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  if [[ ! -f "$dist/index.html" ]]; then
    echo "build-editor-ui: stale — editor/ui/dist missing in $repo (run 'make editor-ui')" >&2
    exit 1
  fi
  newest="$(find "$ui_dir/src" "$ui_dir/package.json" -type f -newer "$dist/index.html" -print -quit 2>/dev/null || true)"
  if [[ -n "$newest" ]]; then
    echo "build-editor-ui: stale — editor UI sources changed since last build (e.g. $newest; run 'make editor-ui')" >&2
    exit 1
  fi
  echo "build-editor-ui: ok — editor/ui/dist is fresh"
  exit 0
fi

command -v npm >/dev/null 2>&1 || {
  echo "build-editor-ui: FAIL — npm not found (install Node.js 20+)" >&2
  exit 1
}

echo "build-editor-ui: building $ui_dir"
(cd "$ui_dir" && npm ci && npm run build)

if [[ ! -f "$dist/index.html" ]]; then
  echo "build-editor-ui: FAIL — npm build completed but $dist/index.html is missing" >&2
  exit 1
fi
echo "build-editor-ui: ok — $dist ready (bundled by 'make build')"
