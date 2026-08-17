#!/usr/bin/env bash
#
# pr-cop.sh — read-only PR status + drift report for a GitHub repo.
#
# Prints every open PR against REPO with:
#   • CI status rollup  (passing / failing / pending / none)
#   • mergeable state   (MERGEABLE / CONFLICTING / UNKNOWN)
#   • draft flag
#   • drift flag        (head branch is behind BASE_BRANCH on the remote)
#
# Uses the `gh` CLI only; every call is a read. This script never merges,
# pushes, force-pushes, or mutates any state.
#
# Usage:  scripts/pr-cop.sh [REPO]
#   REPO                 owner/repo to watch (default: drawmeanelephant/solipsist)
#
# Env:
#   PR_COP_BASE_BRANCH   base branch for the drift comparison (default: main)
#   PR_COP_RETRIES       attempts for the open-PR list query before giving
#                        up (default: 5, ~15s apart; transient GitHub API
#                        503s are retried)
#   PR_COP_TSV_FILE      read per-PR rows from FILE (same TSV columns the
#                        script generates from `gh pr list`) instead of the
#                        live repo. Testing aid only — drift still queries
#                        the live compare API per PR.

set -euo pipefail

REPO="${1:-drawmeanelephant/solipsist}"
BASE_BRANCH="${PR_COP_BASE_BRANCH:-main}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Collect one TSV row per open PR -------------------------------------
# Columns: number, headRefName, title, baseRefName, isDraft, mergeable, checkStates
# The list query can hit transient GitHub API failures (503s); retry a few
# times before giving up so the watcher survives blips.
collect_rows() {
  local file="$1" attempts="${PR_COP_RETRIES:-5}" attempt=0
  while (( attempt < attempts )); do
    if gh pr list --repo "$REPO" --state open --json \
        number,title,headRefName,baseRefName,isDraft,mergeable,statusCheckRollup \
        --jq '.[] | [.number, .headRefName, (.title | gsub("[\r\n\t]";" ")), .baseRefName, (.isDraft|tostring), (.mergeable // "UNKNOWN"), ([.statusCheckRollup[]? | (.conclusion // .state)] | join(","))] | @tsv' \
        > "$file"; then
      return 0
    fi
    attempt=$((attempt + 1))
    echo "pr-cop: gh pr list attempt $attempt/$attempts failed — retrying in 15s" >&2
    sleep 15
  done
  echo "pr-cop: gh pr list failed for $REPO after $attempts attempts" >&2
  return 1
}

if [[ -n "${PR_COP_TSV_FILE:-}" ]]; then
  rows_file="$PR_COP_TSV_FILE"
else
  rows_file="$tmp/prs.tsv"
  collect_rows "$rows_file" || exit 1
fi

rows=()
while IFS= read -r row; do
  rows+=("$row")
done < "$rows_file"

echo "pr-cop: open PRs against $REPO (base: $BASE_BRANCH)"
if (( ${#rows[@]} == 0 )); then
  echo "  No open PRs."
  exit 0
fi

# Worst-case status of a comma-separated check-state list.
ci_status() {
  local cs="$1"
  [[ -z "$cs" ]] && { echo "none"; return; }
  if [[ "$cs" =~ FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE ]]; then
    echo "failing"; return
  fi
  if [[ "$cs" =~ PENDING|IN_PROGRESS|QUEUED|EXPECTED|WAITING|REQUESTED ]]; then
    echo "pending"; return
  fi
  echo "passing"
}

printf '%-6s %-7s %-8s %-11s %-11s %s\n' "#PR" "state" "ci" "mergeable" "drift" "title"

failing=0
drifting=0
for row in "${rows[@]}"; do
  IFS=$'\t' read -r num head title base draft mergeable checks <<< "$row" || true

  ci="$(ci_status "${checks:-}")"

  behind="$(gh api "repos/$REPO/compare/$BASE_BRANCH...$head" --jq '.behind_by' 2>/dev/null || echo unknown)"
  if [[ "$behind" =~ ^[0-9]+$ ]]; then
    if (( behind > 0 )); then
      drift="behind $behind"
      drifting=$((drifting + 1))
    else
      drift="clean"
    fi
  else
    drift="unknown"
  fi

  [[ "$ci" == "failing" ]] && failing=$((failing + 1))

  state="open"
  [[ "$draft" == "true" ]] && state="draft"

  printf '%-6s %-7s %-8s %-11s %-11s %s\n' \
    "#$num" "$state" "$ci" "$mergeable" "$drift" "$title"
done

echo
echo "Summary: ${#rows[@]} open PR(s) — $failing failing CI, $drifting drifted from $BASE_BRANCH."
