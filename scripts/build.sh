#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
APP="$BUILD/MacPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/module-cache"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
MACMON="${MACMON_BIN:-$BUILD/macmon/macmon}"
if [[ -x "$MACMON" ]]; then
  cp "$MACMON" "$APP/Contents/Resources/macmon"
  cp "$ROOT/ThirdParty/macmon-LICENSE" "$APP/Contents/Resources/MACMON-LICENSE"
  codesign --force --sign - "$APP/Contents/Resources/macmon"
else
  rm -f "$APP/Contents/Resources/macmon" "$APP/Contents/Resources/MACMON-LICENSE"
  printf '%s\n' 'macmon absent : le collecteur facultatif sera indisponible. Voir scripts/fetch-macmon.sh.'
fi
CLANG_MODULE_CACHE_PATH="$BUILD/module-cache" xcrun swiftc -parse-as-library -module-cache-path "$BUILD/module-cache" -O -o "$APP/Contents/MacOS/MacPilot" "$ROOT/Sources/Core.swift" "$ROOT/Sources/HistoryStore.swift" "$ROOT/Sources/MacPilot.swift"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Application : %s\n' "$APP"
