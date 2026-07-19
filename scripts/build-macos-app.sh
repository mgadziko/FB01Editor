#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Forest FB-01 Editor"
EXECUTABLE_NAME="FB01EditorApp"
BUNDLE_ID="com.gadzikowski.FB01Editor"
ICON_FILE="AppIcon.icns"
BUILD_TIMESTAMP="$(date +%y%m%d-%H%M)"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"
ICON_PATH="$ROOT_DIR/Resources/$ICON_FILE"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/fb01-editor-app.XXXXXX")"
STAGED_APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$STAGED_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Missing icon: $ICON_PATH" >&2
  exit 1
fi

rm -rf "$STAGED_APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/$ICON_FILE"

/usr/libexec/PlistBuddy -c "Clear dict" "$CONTENTS_DIR/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_FILE" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :FB01EditorBuildTimestamp string $BUILD_TIMESTAMP" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS_DIR/Info.plist"

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$STAGED_APP_DIR"
  xattr -rd com.apple.macl "$STAGED_APP_DIR" >/dev/null 2>&1 || true
  xattr -rd com.apple.provenance "$STAGED_APP_DIR" >/dev/null 2>&1 || true
  xattr -d com.apple.FinderInfo "$STAGED_APP_DIR" >/dev/null 2>&1 || true
  xattr -d "com.apple.fileprovider.fpfs#P" "$STAGED_APP_DIR" >/dev/null 2>&1 || true
fi

if command -v codesign >/dev/null 2>&1; then
  if ! codesign --force --sign - "$STAGED_APP_DIR" >/dev/null 2>&1; then
    if command -v xattr >/dev/null 2>&1; then
      xattr -rd com.apple.macl "$STAGED_APP_DIR" >/dev/null 2>&1 || true
      xattr -rd com.apple.provenance "$STAGED_APP_DIR" >/dev/null 2>&1 || true
      xattr -d com.apple.FinderInfo "$STAGED_APP_DIR" >/dev/null 2>&1 || true
      xattr -d "com.apple.fileprovider.fpfs#P" "$STAGED_APP_DIR" >/dev/null 2>&1 || true
    fi

    if ! codesign --force --sign - "$STAGED_APP_DIR" >/dev/null 2>&1; then
      echo "warning: ad-hoc signing failed; leaving local development app bundle unsigned" >&2
    fi
  fi
fi

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto --noextattr --norsrc --noacl "$STAGED_APP_DIR" "$APP_DIR"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIR"
  xattr -rd com.apple.macl "$APP_DIR" >/dev/null 2>&1 || true
  xattr -rd com.apple.provenance "$APP_DIR" >/dev/null 2>&1 || true
  xattr -d com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1 || true
  xattr -d "com.apple.fileprovider.fpfs#P" "$APP_DIR" >/dev/null 2>&1 || true
fi

if command -v SetFile >/dev/null 2>&1; then
  SetFile -a bc "$APP_DIR" >/dev/null 2>&1 || true
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
