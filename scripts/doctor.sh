#!/bin/bash
#
# doctor.sh — Solipsist environment + repo-hygiene check.
#
# Fails on hard problems (forbidden files tracked or staged, missing
# required files, no Xcode on macOS). Warns on soft problems (missing
# optional tools, no boris binary found). macOS-only checks are skipped
# elsewhere, so docs and script work stay verifiable off-Mac.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "doctor: FAIL — not inside a git repo" >&2
  exit 1
fi
cd "$ROOT"

fail=0
warn=0

fail_msg() { echo "doctor: FAIL — $1" >&2; fail=$((fail + 1)); }
warn_msg() { echo "doctor: warn — $1" >&2; warn=$((warn + 1)); }
ok_msg()   { echo "doctor: ok — $1"; }

# Forbidden: transport binaries and local-only dirs must never be
# committed. vendor/boris-agent-kit/ is pin metadata and is allowed.
FORBIDDEN_RE='^(SUPPORT-NOT-FOR-GITHUB/|boris/|oliver/|boris-agent-kit/)|^Resources/boris$|\.tar\.gz$|(^|/)\.DS_Store$'

forbidden_tracked="$(git ls-files -z | tr '\0' '\n' | grep -E "$FORBIDDEN_RE" || true)"
if [[ -n "$forbidden_tracked" ]]; then
  fail_msg "forbidden files are tracked by git:"
  echo "$forbidden_tracked" >&2
else
  ok_msg "no forbidden files tracked"
fi

forbidden_staged="$(git diff --cached --name-only -z | tr '\0' '\n' | grep -E "$FORBIDDEN_RE" || true)"
if [[ -n "$forbidden_staged" ]]; then
  fail_msg "forbidden files are staged for commit:"
  echo "$forbidden_staged" >&2
else
  ok_msg "nothing forbidden staged"
fi

# Required files.
for f in Project.yml Makefile README.md AGENTS.md \
         docs/ROADMAP.md docs/HARNESS.md docs/MISSION.md docs/ONBOARDING.md \
         scripts/embed-boris.sh scripts/doctor.sh; do
  if [[ -e "$f" ]]; then
    ok_msg "$f present"
  else
    fail_msg "$f missing"
  fi
done

# Portable tools.
for cmd in git curl unzip python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok_msg "tool: $cmd"
  else
    warn_msg "tool missing: $cmd"
  fi
done

if [[ -x ".tools/xcodegen/xcodegen/bin/xcodegen" ]]; then
  ok_msg "XcodeGen vendored (.tools/)"
elif command -v xcodegen >/dev/null 2>&1; then
  ok_msg "xcodegen on PATH"
else
  warn_msg "XcodeGen not vendored — run 'make tools' on a Mac"
fi

# Engine resolution (mirrors the Makefile/embed search order, minus the
# app-bundle slot which only exists after a build).
find_boris() {
  if [[ -n "${SOLIPSIST_BORIS_BIN:-}" && -x "${SOLIPSIST_BORIS_BIN}" ]]; then
    echo "${SOLIPSIST_BORIS_BIN}"
    return 0
  fi
  local c
  for c in \
    "$ROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris" \
    "$ROOT/../boris-agent-kit/bin/boris" \
    "$ROOT/../boris/zig-out/bin/boris"; do
    if [[ -x "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  if command -v boris >/dev/null 2>&1; then
    command -v boris
    return 0
  fi
  return 1
}

if boris_bin="$(find_boris)"; then
  ok_msg "boris engine resolves to: $boris_bin"
else
  warn_msg "no boris binary found (SOLIPSIST_BORIS_BIN, kit, ../boris, or PATH) — engine smoke runs will skip"
fi

# macOS-only checks.
if [[ "$(uname -s)" == "Darwin" ]]; then
  if command -v xcodebuild >/dev/null 2>&1; then
    ok_msg "xcodebuild: $(xcodebuild -version | head -1 | tr '\n' ' ')"
  else
    fail_msg "xcodebuild not found — install Xcode"
  fi
  if command -v sw_vers >/dev/null 2>&1; then
    ok_msg "macOS $(sw_vers -productVersion)"
  fi
  for cmd in swiftformat swiftlint; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok_msg "tool: $cmd"
    else
      warn_msg "tool missing: $cmd (brew install $cmd, or CI covers it)"
    fi
  done
else
  warn_msg "not macOS — app build/test need a Mac; docs, scripts, and hygiene checks run here"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "doctor: FAILED ($warn warning(s))" >&2
  exit 1
fi
echo "doctor: healthy ($warn warning(s))"
