#!/bin/bash
#
# Embeds the Boris engine binary into the app bundle's Resources directory.
#
# Supports:
#   - Universal Mach-O fat binaries (arm64 + x86_64) or automatic lipo merging
#     if discrete single-architecture binaries are available.
#   - Matching codesign identity and hardened runtime options for App Sandbox
#     execution compliance.
#
# Search order:
#   1. Explicit env overrides: SOLIPSIST_BORIS_BIN, or SOLIPSIST_BORIS_ARM64_BIN + SOLIPSIST_BORIS_X86_64_BIN
#   2. Prebuilt kits next to this repo (SUPPORT-NOT-FOR-GITHUB / sibling kit)
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

find_arch_binaries() {
  local arm_cand=(
    "${SOLIPSIST_BORIS_ARM64_BIN:-}"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin/aarch64-macos/boris"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin/arm64/boris"
    "$SRCROOT/../boris/zig-out/bin/aarch64-macos/boris"
  )
  local x86_cand=(
    "${SOLIPSIST_BORIS_X86_64_BIN:-}"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin/x86_64-macos/boris"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin/x86_64/boris"
    "$SRCROOT/../boris/zig-out/bin/x86_64-macos/boris"
  )

  local arm_bin=""
  local x86_bin=""

  for c in "${arm_cand[@]}"; do
    if [[ -n "$c" && -x "$c" ]]; then
      arm_bin="$c"
      break
    fi
  done

  for c in "${x86_cand[@]}"; do
    if [[ -n "$c" && -x "$c" ]]; then
      x86_bin="$c"
      break
    fi
  done

  if [[ -n "$arm_bin" && -n "$x86_bin" ]]; then
    echo "$arm_bin|$x86_bin"
    return 0
  fi
  return 1
}

bundle_and_sign() {
  local target="$DEST_DIR/boris"
  chmod +x "$target"

  local arch_info
  arch_info="$(lipo -archs "$target" 2>/dev/null || echo "unknown")"
  local size_info
  size_info="$(du -h "$target" | cut -f1)"
  echo "embed-boris: bundled $target (arch: $arch_info, size: $size_info)"

  # Codesign matching host application identity & runtime options for App Sandbox execution
  local sign_identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
  if [[ -n "$sign_identity" ]]; then
    echo "embed-boris: signing $target with identity '$sign_identity' (runtime hardened)"
    codesign --force --options runtime --sign "$sign_identity" "$target" 2>/dev/null || {
      echo "embed-boris: notice: ad-hoc signing fallback"
      codesign --force --options runtime --sign - "$target" 2>/dev/null || true
    }
  fi

  # Embed companion binaries (boris-editor, oliver, etc.) if available
  local comp_candidates=(
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin"
    "$SRCROOT/../boris-agent-kit/bin"
  )
  for cdir in "${comp_candidates[@]}"; do
    if [[ -d "$cdir" ]]; then
      for comp in boris-editor oliver boris-package boris-source-rag; do
        if [[ -x "$cdir/$comp" && ! -f "$DEST_DIR/$comp" ]]; then
          cp "$cdir/$comp" "$DEST_DIR/$comp"
          chmod +x "$DEST_DIR/$comp"
          if [[ -n "$sign_identity" ]]; then
            codesign --force --options runtime --sign "$sign_identity" "$DEST_DIR/$comp" 2>/dev/null || \
            codesign --force --options runtime --sign - "$DEST_DIR/$comp" 2>/dev/null || true
          fi
          echo "embed-boris: bundled companion $comp"
        fi
      done
    fi
  done
}

mkdir -p "$DEST_DIR"

# 1. Check if discrete arm64 and x86_64 binaries are available for lipo
if ARCH_PAIR="$(find_arch_binaries)"; then
  ARM_BIN="${ARCH_PAIR%%|*}"
  X86_BIN="${ARCH_PAIR##*|}"
  echo "embed-boris: creating universal fat binary from $ARM_BIN and $X86_BIN"
  lipo -create -output "$DEST_DIR/boris" "$ARM_BIN" "$X86_BIN"
  bundle_and_sign
  exit 0
fi

# 2. Check for prebuilt single or universal binary
if BIN="$(find_prebuilt)"; then
  cp "$BIN" "$DEST_DIR/boris"
  bundle_and_sign
  exit 0
fi

# Explicit opt-out only (ci.yml sets SKIP_EMBED_BORIS=1 for the PR/app
# compile job, which cannot vendor an engine). Release CI now provides
# discrete arm64/x86_64 binaries via SOLIPSIST_BORIS_*_BIN, so it must NOT
# be skipped on GITHUB_ACTIONS: a release without an embedded engine is a
# silent failure.
if [[ "${SKIP_EMBED_BORIS:-}" == "1" ]]; then
  echo "embed-boris: SKIP_EMBED_BORIS=1 — compiling without a bundle"
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

cp "$BIN" "$DEST_DIR/boris"
bundle_and_sign
