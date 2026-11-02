#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD/tests" "$BUILD/module-cache"
CLANG_MODULE_CACHE_PATH="$BUILD/module-cache" xcrun swiftc -D MACPILOT_TEST -parse-as-library -module-cache-path "$BUILD/module-cache" -O -o "$BUILD/tests/benchmark" "$ROOT/Sources/Core.swift" "$ROOT/Sources/HistoryStore.swift" "$ROOT/Sources/MacPilot.swift" "$ROOT/Tests/Benchmark.swift"
"$BUILD/tests/benchmark"
