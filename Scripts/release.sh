#!/bin/zsh
set -euo pipefail

# Builds, signs, and publishes a release:
#   1. refuses to run on a dirty tree, runs the tests
#   2. builds Release and signs it with the stable identity (see signing-common.sh)
#   3. zips the app, pushes the version tag, creates the GitHub release
#   4. rewrites the cask in the Homebrew tap with the new version + sha256
# The version comes from CFBundleShortVersionString in MacTweaks/Resources/Info.plist.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Tweaks.app"
APP_REPO="NoahCLR/MacTweaks"
TAP_REPO="NoahCLR/homebrew-tap"
CASK_TOKEN="mac-tweaks"

source "$ROOT_DIR/Scripts/signing-common.sh"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit or stash before releasing." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/MacTweaks/Resources/Info.plist")"
TAG="v$VERSION"

if gh release view "$TAG" --repo "$APP_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on $APP_REPO. Bump CFBundleShortVersionString first." >&2
  exit 1
fi

BUILD_DIR="$(mktemp -d /tmp/mac-tweaks-release.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
DERIVED_DATA="$BUILD_DIR/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"

echo "Running tests..."
xcodebuild \
  -project "$ROOT_DIR/MacTweaks.xcodeproj" \
  -scheme MacTweaks \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test

echo "Building Release $VERSION..."
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

ZIP_PATH="$BUILD_DIR/MacTweaks-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$ZIP_PATH"
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "Artifact: $ZIP_PATH"
echo "SHA256:   $SHA256"

echo "Tagging $TAG and pushing..."
git -C "$ROOT_DIR" tag "$TAG" 2>/dev/null || echo "Tag $TAG already exists locally."
git -C "$ROOT_DIR" push origin HEAD "$TAG"

echo "Creating GitHub release $TAG..."
gh release create "$TAG" "$ZIP_PATH" \
  --repo "$APP_REPO" \
  --title "Mac Tweaks $VERSION" \
  --notes "Install or upgrade with:

\`\`\`sh
brew install --no-quarantine NoahCLR/tap/$CASK_TOKEN
\`\`\`"

echo "Updating cask in $TAP_REPO..."
TAP_DIR="$BUILD_DIR/homebrew-tap"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth 1
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/$CASK_TOKEN.rb" <<EOF
cask "$CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$APP_REPO/releases/download/v#{version}/MacTweaks-#{version}.zip"
  name "Mac Tweaks"
  desc "Menu bar utility with opt-in Finder and keyboard tweaks"
  homepage "https://github.com/$APP_REPO"

  depends_on macos: ">= :sonoma"

  app "Mac Tweaks.app"

  uninstall quit: "com.noah.MacTweaks"

  zap trash: [
    "~/Library/Application Support/Mac Tweaks/Settings.plist",
    "~/Library/Preferences/com.noah.MacTweaks.plist",
    "~/Library/Preferences/com.noah.MacTweaks.shared.plist",
  ]

  caveats <<~EOS
    Mac Tweaks is signed with a development certificate and is not notarized.
    If macOS blocks the first launch, either reinstall with:
      brew reinstall --cask --no-quarantine $CASK_TOKEN
    or right-click "Mac Tweaks" in /Applications and choose Open once.

    After launching, enable the tweaks you want and grant the permissions
    each one needs (the app's Settings window links to the right panes):
      - Finder extension: System Settings > General > Login Items & Extensions
      - Accessibility + Input Monitoring: System Settings > Privacy & Security
  EOS
end
EOF

git -C "$TAP_DIR" add "Casks/$CASK_TOKEN.rb"
if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "Cask unchanged; nothing to push to the tap."
else
  git -C "$TAP_DIR" commit -m "$CASK_TOKEN $VERSION"
  git -C "$TAP_DIR" push
fi

echo ""
echo "Released Mac Tweaks $VERSION."
echo "Install with: brew install --no-quarantine ${TAP_REPO%%/homebrew-*}/tap/$CASK_TOKEN"
