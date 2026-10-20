#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build --disable-sandbox --build-system native -c release --arch arm64 --product MacBuddy
BIN_DIR=$(swift build --disable-sandbox --build-system native -c release --arch arm64 --show-bin-path)
mkdir -p tmp
xcrun swiftc -swift-version 5 -O -module-cache-path "$PWD/.build/module-cache" \
    -I "$BIN_DIR/Modules" \
    -Xcc "-fmodule-map-file=$BIN_DIR/NativeTelemetry.build/module.modulemap" \
    -Xcc "-fmodule-map-file=$PWD/Sources/CSQLite/module.modulemap" \
    Sources/MacBuddy/MonitorModel.swift scripts/scheduler-checks.swift \
    "$BIN_DIR"/MacBuddyCore.build/*.o "$BIN_DIR"/NativeTelemetry.build/*.o \
    -lsqlite3 -framework IOKit -framework CoreFoundation -o tmp/scheduler-checks
tmp/scheduler-checks
