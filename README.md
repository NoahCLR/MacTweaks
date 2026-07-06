# Mac Tweaks

Mac Tweaks is a native macOS menu bar utility for opt-in Finder and keyboard tweaks. It runs as an `LSUIElement` app, so it lives in the menu bar and never shows a Dock icon. Every tweak is off by default and can be toggled individually.

## Tweaks

Finder right-click actions (shown in the context menu, with configurable order):

- **Create New File Here** — creates an empty file in the folder you clicked
- **Open in IDE** — opens the clicked folder or file's folder in your editor (defaults to Visual Studio Code when installed)
- **Copy Path** — copies the full path(s) of the selection to the clipboard
- **Open in Terminal** — opens your terminal in the clicked folder

Keyboard tweak, scoped to Finder only:

- **Backspace/Delete moves the selection to Trash** (no ⌘ required)

## Install

### Homebrew

```sh
brew install --no-quarantine NoahCLR/tap/mac-tweaks
```

`--no-quarantine` is recommended: Mac Tweaks is built without a paid Apple Developer account, so it is signed but not notarized. If you install without the flag, macOS will block the first launch — right-click **Mac Tweaks** in `/Applications` and choose **Open** once to approve it.

### Build from source

No paid Apple Developer Program membership required:

```sh
./Scripts/install-local.sh
```

The script builds the app, signs it with a stable identity, installs it to `/Applications`, registers the Finder extension, and launches it. It prefers an `Apple Development` certificate from your free Apple Account when Xcode has created one; otherwise it creates a stable self-signed certificate named `Mac Tweaks Local Code Signing`. See [Development](#development) for details.

## First-run setup

Launch **Mac Tweaks** (it appears in the menu bar), open **Settings** from its menu, and enable the tweaks you want. Depending on which tweaks you enable, macOS needs some one-time approvals:

1. **Finder extension** (right-click actions): System Settings → General → Login Items & Extensions → Finder Extensions → enable **Mac Tweaks Finder Actions**.
2. **Accessibility** (Backspace-to-Trash tweak and the Option+right-click fallback menu): System Settings → Privacy & Security → Accessibility → enable **Mac Tweaks**.
3. **Input Monitoring** (Backspace-to-Trash tweak): System Settings → Privacy & Security → Input Monitoring → enable **Mac Tweaks**.
4. **Finder automation**: the first time the delete tweak acts, macOS asks to allow Mac Tweaks to control Finder — click Allow.

The app's settings window shows the live permission status and links to the right System Settings panes.

Updates installed with `brew upgrade` keep these grants: releases are always signed with the same identity, which is what macOS ties the permissions to.

## Development

Open `MacTweaks.xcodeproj` in Xcode and run the `MacTweaks` scheme, or use the command line:

```sh
# Build (no signing needed for verification)
xcodebuild -project MacTweaks.xcodeproj -scheme MacTweaks -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build

# Run tests
xcodebuild -project MacTweaks.xcodeproj -scheme MacTweaks -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Targets: `Mac Tweaks` (app), `MacTweaksFinderExtension` (Finder Sync extension embedded in the app), `MacTweaksTests`.

### Local install and signing

`./Scripts/install-local.sh` installs a local build to `/Applications`. A *stable* signing identity matters: re-signing with a different identity resets the app's Accessibility/Input Monitoring permissions. The script prefers an `Apple Development` certificate from your free Apple Account. To set one up:

1. Open Xcode → Settings → Accounts and add your Apple Account.
2. Select the account, open **Manage Certificates**, and create an **Apple Development** certificate.
3. Rerun `./Scripts/install-local.sh`.

The certificate must include its private key — verify with `security find-identity -v -p codesigning`. Without one, the script falls back to creating a stable self-signed certificate.

### Releasing

`./Scripts/release.sh` builds and signs a Release configuration, uploads the zip to a GitHub release, and updates the Homebrew cask in [NoahCLR/homebrew-tap](https://github.com/NoahCLR/homebrew-tap). It refuses to run on a dirty tree, runs the tests first, and derives the version from `CFBundleShortVersionString`.

## License

[MIT](LICENSE)
