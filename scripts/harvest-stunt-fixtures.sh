#!/usr/bin/env bash
# Rebuild Tests/Fixtures from Stunts/ using a local boris binary.
# Does not run in CI. Never writes into Stunts/ permanently.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BORIS="${SOLIPSIST_BORIS_BIN:-}"
if [[ -z "$BORIS" || ! -x "$BORIS" ]]; then
  for c in \
    "$ROOT/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris" \
    "$ROOT/../grok-base/SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/boris-agent-kit/bin/boris" \
    "/tmp/boris-pin-test/zig-out/bin/boris" \
    "/tmp/boris/zig-out/bin/boris"
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
mkdir -p "$TMP" "$FIX/happy-ir" "$FIX/dogfood-ir" "$FIX/broken-frontmatter" "$FIX/broken-parent" "$FIX/validate-happy" "$FIX/validate-failure" "$FIX/plan-happy" "$FIX/plan-editions" "$FIX/timings" "$FIX/validate-watch"

# Helper: run IR build inside the stunt dir so output stays workspace-relative.
harvest_ir() {
  local stunt="$1" dest="$2"
  rm -rf "$STUNTS/$stunt/.boris"
  (cd "$STUNTS/$stunt" && "$BORIS" --out .boris --input content --quiet 2>/dev/null || true)
  mkdir -p "$dest"
  cp "$STUNTS/$stunt/.boris/"*.json "$dest/" 2>/dev/null || true
  rm -rf "$STUNTS/$stunt/.boris"
}

harvest_ir "happy" "$TMP/happy-ir"
cp "$TMP/happy-ir/"*.json "$FIX/happy-ir/"

harvest_ir "dogfood" "$TMP/dogfood-ir"
cp "$TMP/dogfood-ir/"*.json "$FIX/dogfood-ir/"

# Timings (stdout JSON, workspace-relative IR still required)
rm -rf "$STUNTS/happy/.boris"
(cd "$STUNTS/happy" && "$BORIS" --out .boris --input content --timings --quiet > "$TMP/timings-happy.json" 2>/dev/null)
cp "$TMP/timings-happy.json" "$FIX/timings/happy-ir-timings.json"
rm -rf "$STUNTS/happy/.boris"

rm -rf "$STUNTS/dogfood/.boris"
(cd "$STUNTS/dogfood" && "$BORIS" --out .boris --input content --timings --quiet > "$TMP/timings-dogfood.json" 2>/dev/null)
cp "$TMP/timings-dogfood.json" "$FIX/timings/dogfood-ir-timings.json"
rm -rf "$STUNTS/dogfood/.boris"

# BuildTarget timings shape: single target with --timings (same phase keys, html mode eventual)
# Use happy's single public target; keep it as IR timings which already covers phases/counters shape.
# Duplicate for html mode via a synthetic html build with --timings would need a dist dir.
rm -rf "$STUNTS/happy/dist" "$STUNTS/happy/.boris"
(cd "$STUNTS/happy" && "$BORIS" build --html-dir dist --input content --timings --quiet > "$TMP/timings-html.json" 2>/dev/null || true)
if [[ -s "$TMP/timings-html.json" ]]; then
  cp "$TMP/timings-html.json" "$FIX/timings/happy-html-timings.json"
fi
rm -rf "$STUNTS/happy/dist" "$STUNTS/happy/.boris"

# Validate reports: happy success + failure dual
(cd "$STUNTS/happy" && "$BORIS" validate --input content --report "$FIX/validate-happy/html-build-report.json")
# broken-wikilink is a content root with a single bad wikilink; validate fails with dual diagnostics
(cd "$STUNTS" && "$BORIS" validate --input broken-wikilink --report "$TMP/validate-failure.json" 2>/dev/null || true)
cp "$TMP/validate-failure.json" "$FIX/validate-failure/html-build-report.json"

# Plans: happy bare + editions with scope/split_size
(cd "$STUNTS/happy" && "$BORIS" plan --profile boris.json > "$FIX/plan-happy/plan.json")
# editions fixture: synthesize a temp profile that carries rag/context scope/split_size
TMP_PROF="$TMP/plan-editions"
mkdir -p "$TMP_PROF/content" "$FIX/plan-editions"
cat > "$TMP_PROF/boris.json" <<'JSON'
{
  "format": "boris-publication-profile",
  "schema_version": 1,
  "input": "content",
  "input_format": "markdown",
  "site": { "title": "Harvest Editions", "url": "https://example.com" },
  "targets": [{ "name": "public", "output": "dist", "public": true, "theme": "themes/boris" }],
  "editions": {
    "ir": { "output": ".boris" },
    "rag": { "output": "rag", "scope": "guides", "split_size": 262144 },
    "context": { "output": "context", "scope": "reference", "split_size": 131072 }
  }
}
JSON
echo "---\nid: a\ntitle: A\n---\nhello" > "$TMP_PROF/content/a.md"
mkdir -p "$TMP_PROF/themes/boris/layouts"
echo "<html></html>" > "$TMP_PROF/themes/boris/layouts/main.html"
(cd "$TMP_PROF" && "$BORIS" plan --profile boris.json > "$FIX/plan-editions/plan.json")

# Broken IR fixtures — run inside each broken dir with --input . and relative .boris
for broken in broken-frontmatter broken-parent; do
  rm -rf "$STUNTS/$broken/.boris"
  (cd "$STUNTS/$broken" && "$BORIS" --out .boris --input . --quiet 2>/dev/null || true)
  mkdir -p "$FIX/$broken"
  cp "$STUNTS/$broken/.boris/build-report.json" "$FIX/$broken/" 2>/dev/null || true
  rm -rf "$STUNTS/$broken/.boris"
done

# ValidateWatch NDJSON mode:validate — capture first seconds of the daemon's stderr
# The daemon writes hello + build-started + build-succeeded/failed on stderr with --watch-json.
# We timeout after 2s and keep whatever was emitted.
rm -rf "$STUNTS/happy/.boris"
( cd "$STUNTS/happy" && timeout 3 "$BORIS" validate --watch --watch-json --input content 2> "$TMP/validate-watch.ndjson" || true ) &
sleep 1
# also feed a file change to trigger a rebuild is unnecessary — initial cycle already emits.
sleep 1
pkill -f "validate --watch" 2>/dev/null || true
wait 2>/dev/null || true
if [[ -s "$TMP/validate-watch.ndjson" ]]; then
  head -n 20 "$TMP/validate-watch.ndjson" > "$FIX/validate-watch/validate-watch.ndjson"
else
  # Fallback probe-shaped fixture (still bf464a0-accurate) if live capture raced
  cat > "$FIX/validate-watch/validate-watch.ndjson" <<'NDJSON'
{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}
{"event":"build-started","phase":"initial","mode":"validate","targets":["default"]}
{"event":"build-succeeded","phase":"initial","mode":"validate","targets":["default"],"pages_written":null,"duration_ms":22}
{"event":"watcher-started","mode":"validate","targets":["default"]}
NDJSON
fi
rm -rf "$STUNTS/happy/.boris"

rm -rf "$TMP"
echo "harvest: wrote $FIX"
