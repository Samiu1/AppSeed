#!/bin/bash
#
# Builds AppSeedEngine.app and AppSeed.app for Apple Silicon (arm64 only, per
# spec — no universal binaries) using only the Xcode Command Line Tools.
#
# The engine is compiled first and embedded into
# AppSeed.app/Contents/Resources/Engine/AppSeedEngine.app on every build —
# the same guarantee an Xcode "Copy Files" build phase with a target
# dependency would provide.
#
# Output: build/AppSeedEngine.app and build/AppSeed.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
OBJ="$BUILD/obj"
TARGET_TRIPLE="arm64-apple-macos13.0"
# APPSEED_SDK overrides the SDK when the default one doesn't match the
# installed Swift toolchain (Command Line Tools updates can leave the default
# MacOSX.sdk one patch version behind the compiler, which hard-errors).
SDK="${APPSEED_SDK:-$(xcrun --show-sdk-path)}"
export SDKROOT="$SDK"

rm -rf "$BUILD"
mkdir -p "$OBJ"

echo "== Default icon =="
DEFAULT_PNG="$OBJ/default-icon.png"
swift -sdk "$SDK" "$ROOT/Scripts/make-default-icon.swift" "$DEFAULT_PNG"

# sips + iconutil, with Apple's exact iconset naming convention — iconutil
# silently produces a corrupt .icns if any filename deviates.
ICONSET="$OBJ/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    DOUBLE=$((SIZE * 2))
    sips -z "$SIZE" "$SIZE" "$DEFAULT_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    sips -z "$DOUBLE" "$DOUBLE" "$DEFAULT_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
DEFAULT_ICNS="$OBJ/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$DEFAULT_ICNS"

echo "== AppSeedEngine.app =="
ENGINE_APP="$BUILD/AppSeedEngine.app"
mkdir -p "$ENGINE_APP/Contents/MacOS" "$ENGINE_APP/Contents/Resources"
swiftc -O \
    -target "$TARGET_TRIPLE" \
    -sdk "$SDK" \
    "$ROOT/Shared/"*.swift \
    "$ROOT/AppSeedEngine/Core/"*.swift \
    "$ROOT/AppSeedEngine/Inject/"*.swift \
    -o "$ENGINE_APP/Contents/MacOS/AppSeedEngine"
cp "$ROOT/AppSeedEngine/Resources/Info.plist" "$ENGINE_APP/Contents/Info.plist"
cp "$ROOT/AppSeedEngine/Resources/AppConfig.json" "$ENGINE_APP/Contents/Resources/AppConfig.json"
cp "$DEFAULT_ICNS" "$ENGINE_APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature for the template. Every clone is re-signed by the factory
# after mutation anyway (see AppFactory.stripQuarantineAndSign).
codesign --force --deep --sign - "$ENGINE_APP"

echo "== AppSeed.app =="
FACTORY_APP="$BUILD/AppSeed.app"
mkdir -p "$FACTORY_APP/Contents/MacOS" "$FACTORY_APP/Contents/Resources/Engine"
swiftc -O \
    -target "$TARGET_TRIPLE" \
    -sdk "$SDK" \
    "$ROOT/Shared/"*.swift \
    "$ROOT/AppSeed/App/"*.swift \
    "$ROOT/AppSeed/Factory/"*.swift \
    "$ROOT/AppSeed/Views/"*.swift \
    -o "$FACTORY_APP/Contents/MacOS/AppSeed"
cp "$ROOT/AppSeed/Resources/Info.plist" "$FACTORY_APP/Contents/Info.plist"
cp "$DEFAULT_ICNS" "$FACTORY_APP/Contents/Resources/AppIcon.icns"
# Embed the compiled engine blueprint — the factory clones this at runtime.
cp -R "$ENGINE_APP" "$FACTORY_APP/Contents/Resources/Engine/AppSeedEngine.app"
codesign --force --deep --sign - "$FACTORY_APP"

echo "== Verify =="
codesign --verify --deep --strict "$ENGINE_APP"
codesign --verify --deep --strict "$FACTORY_APP"
echo "Engine:  $(du -sh "$ENGINE_APP" | cut -f1)  $ENGINE_APP"
echo "Factory: $(du -sh "$FACTORY_APP" | cut -f1)  $FACTORY_APP"
echo "Done."
