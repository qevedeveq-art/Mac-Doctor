#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD/tests" "$BUILD/module-cache"
CLANG_MODULE_CACHE_PATH="$BUILD/module-cache" xcrun swiftc -parse-as-library -module-cache-path "$BUILD/module-cache" -o "$BUILD/tests/unit" "$ROOT/Sources/Core.swift" "$ROOT/Tests/Tests.swift"
MACMON="${MACMON_BIN:-$BUILD/macmon/macmon}"
if [[ -x "$MACMON" ]]; then "$BUILD/tests/unit" "$MACMON"; else "$BUILD/tests/unit"; fi
if [[ -x /opt/homebrew/bin/mo && -x "$MACMON" ]]; then
  xcrun clang -O2 -o "$BUILD/tests/test-sleep" "$ROOT/Tests/test-sleep.c"
  codesign --force --sign - "$BUILD/tests/test-sleep"
  CLANG_MODULE_CACHE_PATH="$BUILD/module-cache" xcrun swiftc -D MACPILOT_TEST -parse-as-library -module-cache-path "$BUILD/module-cache" -O -o "$BUILD/tests/integration" "$ROOT/Sources/Core.swift" "$ROOT/Sources/HistoryStore.swift" "$ROOT/Sources/MacPilot.swift" "$ROOT/Tests/Integration.swift"
  "$BUILD/tests/integration" "$MACMON" "$BUILD/tests/test-sleep"
else
  printf '%s\n' 'Tests d’intégration réels ignorés : Mole et macmon sont nécessaires.'
fi
