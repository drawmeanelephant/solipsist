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
# Boris search order:
#   1. Explicit env overrides: SOLIPSIST_BORIS_BIN, or SOLIPSIST_BORIS_ARM64_BIN + SOLIPSIST_BORIS_X86_64_BIN
#   2. Prebuilt kits next to this repo (SUPPORT-NOT-FOR-GITHUB / sibling kit)
#   3. Existing zig-out in a boris checkout
#   4. Build from BORIS_REPO_DIR (default: ../boris)
#
# Oliver (compose preview renderer) is embedded alongside boris so the
# release app renders previews without SOLIPSIST_OLIVER_BIN. Provenance:
# oliver is NOT shipped by the boris agent kit — source it from the oliver
# repo's own build (../oliver/zig-out/bin/oliver) or a kit that carries it.
# Search order: SOLIPSIST_OLIVER_BIN, kit bin dirs, oliver repo zig-out.
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

  # Embed companion binaries (boris-editor, boris-package, boris-source-rag,
  # boris-content-audit) from kit bin dirs when available.
  local comp_candidates=(
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin"
    "$SRCROOT/../boris-agent-kit/bin"
  )
  local search_index_found=0
  for cdir in "${comp_candidates[@]}"; do
    if [[ -d "$cdir" ]]; then
      for comp in boris-editor boris-package boris-source-rag boris-content-audit; do
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
      # Notice-skip: boris-search-index exists in the kit but the app
      # does not locate or run it — do not embed it.
      if [[ -x "$cdir/boris-search-index" ]]; then
        search_index_found=1
      fi
    fi
  done
  if [[ "$search_index_found" -eq 1 ]]; then
    echo "embed-boris: notice: boris-search-index present in kit but not bundled (unused by app)"
  fi

  bundle_oliver "$sign_identity"
}

find_oliver() {
  if [[ -n "${SOLIPSIST_OLIVER_BIN:-}" && -x "${SOLIPSIST_OLIVER_BIN}" ]]; then
    echo "${SOLIPSIST_OLIVER_BIN}"
    return 0
  fi

  # Kit bin dirs (a kit that ships oliver) first, then the oliver repo build.
  # Depth mirrors the boris candidates so both the main checkout and nested
  # worktrees resolve the sibling oliver checkout.
  local candidates=(
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/oliver"
    "$SRCROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/bin/oliver"
    "$SRCROOT/../boris-agent-kit/bin/oliver"
    "$SRCROOT/../oliver/zig-out/bin/oliver"
    "$SRCROOT/../../oliver/zig-out/bin/oliver"
    "$SRCROOT/../../../oliver/zig-out/bin/oliver"
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

# Bundles the oliver renderer with the same codesign identity/path as boris.
# Skips when already present (companion/kit path won). Absence is a notice,
# not a failure: preview falls back to SOLIPSIST_OLIVER_BIN / dev checkouts.
bundle_oliver() {
  local sign_identity="${1:--}"
  if [[ -f "$DEST_DIR/oliver" ]]; then
    return 0
  fi
  local oliver
  if ! oliver="$(find_oliver)"; then
    echo "embed-boris: notice: no oliver binary found — compose preview falls back to SOLIPSIST_OLIVER_BIN"
    return 0
  fi
  cp "$oliver" "$DEST_DIR/oliver"
  chmod +x "$DEST_DIR/oliver"
  if [[ -n "$sign_identity" ]]; then
    codesign --force --options runtime --sign "$sign_identity" "$DEST_DIR/oliver" 2>/dev/null || \
    codesign --force --options runtime --sign - "$DEST_DIR/oliver" 2>/dev/null || true
  fi
  echo "embed-boris: bundled oliver (provenance: $oliver)"
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
