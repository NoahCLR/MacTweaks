#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d /tmp/mac-tweaks-install.XXXXXX)"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_NAME="Mac Tweaks.app"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
INSTALL_APP="/Applications/$APP_NAME"
EXTENSION_ID="com.ncleroy.MacTweaks.FinderExtension"

source "$ROOT_DIR/Scripts/signing-common.sh"

echo "Building Mac Tweaks..."
trap 'rm -rf "$BUILD_DIR"' EXIT
xcodebuild \
  -project "$ROOT_DIR/MacTweaks.xcodeproj" \
  -scheme MacTweaks \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build did not produce $BUILT_APP" >&2
  exit 1
fi

ensure_signing_identity
sign_app_bundle "$BUILT_APP"

echo "Installing to /Applications..."
osascript -e 'tell application "Mac Tweaks" to quit' >/dev/null 2>&1 || true
rm -rf "$INSTALL_APP"
ditto "$BUILT_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

echo "Registering Finder Sync extension..."
pluginkit -a "$INSTALL_APP/Contents/PlugIns/MacTweaksFinderExtension.appex" || true
sleep 1
pluginkit -e use -i "$EXTENSION_ID" || true

echo "Launching Mac Tweaks..."
open "$INSTALL_APP"

echo ""
echo "Installed. If Finder actions do not appear, open System Settings > General > Login Items & Extensions > Finder Extensions and enable Mac Tweaks Finder Actions."
