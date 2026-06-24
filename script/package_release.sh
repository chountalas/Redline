#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Redline"
BUNDLE_ID="com.connorhountalas.Redline"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos/RedlineMac"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/staging"
APP_PATH="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_PATH/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
ENGINE_DIR="$APP_RESOURCES/Engine"
ENGINE_BIN="$ENGINE_DIR/bin"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SRC="$PACKAGE_DIR/AppIcon.icns"
VERSION="${VERSION:-$(awk -F '"' '/^version =/{print $2; exit}' "$ROOT_DIR/pyproject.toml")}"
ZIP_PATH="$DIST_DIR/$APP_NAME-$VERSION-arm64.zip"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-arm64.dmg"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENGINE_PYTHON="${ENGINE_PYTHON:-python3.13}"
RUNTIME_PYTHON="${RUNTIME_PYTHON:-/opt/homebrew/opt/python@3.13/bin/python3.13}"
UV="${UV:-uv}"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  TIMESTAMP_FLAG="--timestamp=none"
else
  TIMESTAMP_FLAG="--timestamp"
fi

cd "$ROOT_DIR"

rm -rf "$DIST_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$STAGING_DIR"

swift build \
  --package-path "$PACKAGE_DIR" \
  --configuration release \
  --arch arm64

BUILD_BINARY="$(swift build \
  --package-path "$PACKAGE_DIR" \
  --configuration release \
  --arch arm64 \
  --show-bin-path)/$APP_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "Expected executable not found: $BUILD_BINARY" >&2
  exit 1
fi

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_SRC" "$APP_RESOURCES/AppIcon.icns"

"$ENGINE_PYTHON" -m venv --copies "$ENGINE_DIR"
VIRTUAL_ENV="$ENGINE_DIR" "$UV" sync --active --frozen --extra mcp --no-dev --no-editable --link-mode copy
rm -rf "$ENGINE_BIN"
rm -f "$ENGINE_DIR/pyvenv.cfg" "$ENGINE_DIR/.lock" "$ENGINE_DIR/.gitignore"
find "$ENGINE_DIR" -name "direct_url.json" -delete
mkdir -p "$ENGINE_BIN"

cat >"$ENGINE_BIN/redline" <<'SH'
#!/bin/sh
set -e
SOURCE="$0"
while [ -L "$SOURCE" ]; do
  DIR="$(CDPATH= cd -- "$(dirname -- "$SOURCE")" && pwd)"
  TARGET="$(readlink "$SOURCE")"
  case "$TARGET" in
    /*) SOURCE="$TARGET" ;;
    *) SOURCE="$DIR/$TARGET" ;;
  esac
done
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$SOURCE")" && pwd)"
ENGINE_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON="${REDLINE_ENGINE_PYTHON:-/opt/homebrew/opt/python@3.13/bin/python3.13}"
if [ ! -x "$PYTHON" ]; then
  echo "Redline requires Homebrew python@3.13. Install with: brew install python@3.13" >&2
  exit 127
fi
export PYTHONPATH="$ENGINE_DIR/lib/python3.13/site-packages${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONSAFEPATH=1
exec "$PYTHON" -P -m redline.cli "$@"
SH

cat >"$ENGINE_BIN/redline-mcp" <<'SH'
#!/bin/sh
set -e
SOURCE="$0"
while [ -L "$SOURCE" ]; do
  DIR="$(CDPATH= cd -- "$(dirname -- "$SOURCE")" && pwd)"
  TARGET="$(readlink "$SOURCE")"
  case "$TARGET" in
    /*) SOURCE="$TARGET" ;;
    *) SOURCE="$DIR/$TARGET" ;;
  esac
done
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$SOURCE")" && pwd)"
ENGINE_DIR="$(dirname "$SCRIPT_DIR")"
PYTHON="${REDLINE_ENGINE_PYTHON:-/opt/homebrew/opt/python@3.13/bin/python3.13}"
if [ ! -x "$PYTHON" ]; then
  echo "Redline requires Homebrew python@3.13. Install with: brew install python@3.13" >&2
  exit 127
fi
export PYTHONPATH="$ENGINE_DIR/lib/python3.13/site-packages${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONSAFEPATH=1
exec "$PYTHON" -P -m redline.mcp_server "$@"
SH

chmod +x "$ENGINE_BIN/redline" "$ENGINE_BIN/redline-mcp"
find "$ENGINE_DIR" -type d -name "__pycache__" -exec rm -rf {} +
find "$ENGINE_DIR" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
if [[ ! -x "$RUNTIME_PYTHON" ]]; then
  echo "Expected runtime Python not found: $RUNTIME_PYTHON" >&2
  exit 1
fi
"$ENGINE_BIN/redline" --version >/dev/null
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$ENGINE_DIR/lib/python3.13/site-packages" "$RUNTIME_PYTHON" - <<'PY'
import mcp.server.fastmcp
import redline.mcp_server
PY
find "$ENGINE_DIR" -type d -name "__pycache__" -exec rm -rf {} +
find "$ENGINE_DIR" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null

find "$ENGINE_DIR" -type f \( -name "*.so" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' binary; do
    codesign --force --options runtime "$TIMESTAMP_FLAG" --sign "$SIGN_IDENTITY" "$binary"
  done

codesign --force --deep --options runtime "$TIMESTAMP_FLAG" --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > checksums.txt
)

echo "$ZIP_PATH"
echo "$DMG_PATH"
