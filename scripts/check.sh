#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift run --disable-sandbox --build-system native MacBuddyChecks

mkdir -p tmp
xcrun clang -O2 -I Sources/NativeTelemetry/include scripts/native-checks.c Sources/NativeTelemetry/NativeTelemetry.c -framework IOKit -framework CoreFoundation -o tmp/native-checks
tmp/native-checks

xcrun clang -O2 scripts/measure.c -o tmp/measure-peak-check
xcrun clang -O2 scripts/memory-peak-check.c -o tmp/memory-peak-check
tmp/memory-peak-check "$PWD/tmp/measure-peak-check"
