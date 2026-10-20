#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build --disable-sandbox --build-system native -c release --arch arm64
BUILD_DIR=$(swift build --disable-sandbox --build-system native -c release --arch arm64 --show-bin-path)
APP="$PWD/dist/Mac Buddy.app"
STAGE="$PWD/dist/.MacBuddy-build-$$.app"
PREVIOUS="$PWD/dist/.MacBuddy-previous-$$.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BUILD_DIR/MacBuddy" "$STAGE/Contents/MacOS/MacBuddy"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp -R Resources/Fonts "$STAGE/Contents/Resources/Fonts"
cp THIRD_PARTY_NOTICES.md "$STAGE/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp LICENSE "$STAGE/Contents/Resources/LICENSE"
codesign --force --sign - "$STAGE"
codesign --verify --strict "$STAGE"
# Replace the bundle by rename, never truncate a running executable's inode.
if [[ -e "$APP" ]]; then mv "$APP" "$PREVIOUS"; fi
if mv "$STAGE" "$APP"; then
    print "Built $APP"
    if [[ -e "$PREVIOUS" ]]; then print "Previous build retained at $PREVIOUS"; fi
else
    if [[ -e "$PREVIOUS" ]]; then mv "$PREVIOUS" "$APP"; fi
    exit 1
fi
