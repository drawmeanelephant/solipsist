#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
products="$repo_root/build/Build/Products/Debug"
library="$products/Solipsist.app/Contents/MacOS/Solipsist.debug.dylib"
if [[ ! -f "$library" ]]; then
    echo "Build the Debug app first (SKIP_EMBED_BORIS=1 make build)." >&2
    exit 1
fi

temp_root="$(mktemp -d "${TMPDIR:-/tmp/}compose-native-smoke.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT
bundle="$temp_root/ComposeNativeSmoke.app"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.drawmeanelephant.compose-native-smoke</string>
  <key>CFBundleName</key><string>Compose Native Smoke</string>
  <key>CFBundleExecutable</key><string>ComposeNativeSmoke</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

xcrun swiftc -parse-as-library -I "$products" \
    -Xlinker -rpath -Xlinker "$(dirname "$library")" \
    "$repo_root/Tests/Native/ComposeSourceSwitchSmoke.swift" "$library" \
    -o "$bundle/Contents/MacOS/ComposeNativeSmoke"
SOLIPSIST_OLIVER_BIN=/nonexistent/oliver "$bundle/Contents/MacOS/ComposeNativeSmoke"
