#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Ariadne"
BUNDLE_ID="com.ariadne.launcher"
MIN_MACOS="13.0"

RAW_VERSION="${ARIADNE_VERSION:-$(cat VERSION | tr -d '[:space:]')}"
BUILD_NUMBER="${ARIADNE_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      RAW_VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Artifact version keeps tag/suffix (e.g. 0.1.0 or 0.1.0-main.abc1234)
ARTIFACT_VERSION="${RAW_VERSION#v}"
# CFBundleShortVersionString must be numeric X.Y.Z for macOS LaunchServices
SHORT_VERSION="$(echo "$ARTIFACT_VERSION" | sed -E 's/^([0-9]+(\.[0-9]+){0,2}).*/\1/')"
if ! [[ "$SHORT_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  SHORT_VERSION="0.1.0"
fi
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  BUILD_NUMBER="1"
fi

echo "==> Packaging $APP_NAME $ARTIFACT_VERSION (CFBundleShortVersionString=$SHORT_VERSION, CFBundleVersion=$BUILD_NUMBER)"

DIST_DIR="$ROOT_DIR/dist"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Building arm64 release binary..."
swift build -c release --arch arm64
ARM_BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "==> Building x86_64 release binary..."
swift build -c release --arch x86_64
X86_BIN_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"

APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "==> Creating universal binary via lipo..."
lipo -create \
  "$ARM_BIN_DIR/$APP_NAME" \
  "$X86_BIN_DIR/$APP_NAME" \
  -output "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
lipo -info "$MACOS_DIR/$APP_NAME"

echo "==> Generating AppIcon.icns..."
ICON_WORK="$DIST_DIR/icon_work"
ICONSET_DIR="$ICON_WORK/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
MASTER_ICON="$ICON_WORK/AppIcon-1024.png"

swift "$ROOT_DIR/scripts/generate-icon.swift" "$MASTER_ICON"

sips -z 16 16     "$MASTER_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$MASTER_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$MASTER_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$MASTER_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$MASTER_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$MASTER_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$MASTER_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$MASTER_ICON" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICON_WORK"

echo "==> Writing Info.plist & PkgInfo..."
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Ariadne Contributors.</string>
</dict>
</plist>
EOF

echo "==> Code signing app bundle..."
if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ZIP_NAME="${APP_NAME}-${ARTIFACT_VERSION}-macOS-universal.zip"
DMG_NAME="${APP_NAME}-${ARTIFACT_VERSION}-macOS-universal.dmg"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Creating ZIP archive: $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Creating DMG image: $DMG_NAME"
DMG_STAGE="$DIST_DIR/dmg_stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

for attempt in 1 2 3 4 5; do
  if hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"; then
    break
  fi
  if [[ "$attempt" -eq 5 ]]; then
    echo "Failed to create DMG after 5 attempts" >&2
    exit 1
  fi
  echo "hdiutil create retry $attempt/5..."
  sleep 2
done
rm -rf "$DMG_STAGE"

if [[ -n "${APPLE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$DMG_PATH"
fi

echo "==> Generating SHA-256 checksums..."
(
  cd "$DIST_DIR"
  shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > checksums.txt
)

ls -lh "$DIST_DIR"
cat "$DIST_DIR/checksums.txt"
