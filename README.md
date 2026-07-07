# Mac Tweaks

Mac Tweaks is a native macOS menu bar utility for opt-in Finder and keyboard tweaks. It runs as an `LSUIElement` app, so it lives in the menu bar and never shows a Dock icon. Every tweak is off by default and can be toggled individually.

## Tweaks

Finder right-click actions (shown in the context menu, with configurable order):

- **Create New File Here** — creates an empty file in the folder you clicked
- **Open in IDE** — opens the clicked folder or file's folder in your editor (defaults to Visual Studio Code when installed)
- **Copy Path** — copies the full path(s) of the selection to the clipboard
- **Open in Terminal** — opens your terminal in the clicked folder

Keyboard tweaks, scoped to Finder only:

- **Backspace/Delete moves the selection to Trash** (no ⌘ required)
- **Paste clipboard as a file** — in a Finder window or on the Desktop, ⌘V turns raw clipboard data into a file in the current folder: a screenshot or copied image becomes a `.png` (or `.jpg` when copied as JPEG), and copied text becomes `.rtf`/`.txt`. Files are named like `Pasted Image 2026-07-07 at 14.30.05.png`. Copied *files* still paste normally, and ⌘V while renaming an item is left alone. Images take priority when the clipboard holds both an image and text; each type can be toggled off individually.
- **Cut & paste files to move them (⌘X / ⌘V)** — Windows-style file moving: ⌘X marks the selected files, and the next plain ⌘V moves them into the current folder. The move is performed by Finder itself, so **⌘Z undoes it** and name conflicts, permissions, and cross-volume moves are handled the usual way. A ⌘C in between cancels the cut ("last cut-or-copy wins"), and ⌘X inside a rename or search field still cuts text normally.

## Install

### Homebrew

```sh
brew install NoahCLR/tap/mac-tweaks
xattr -dr com.apple.quarantine "/Applications/Mac Tweaks.app"
```

The `xattr` line is needed because Mac Tweaks is built without a paid Apple Developer account: it is signed but not notarized, so Gatekeeper blocks the first launch of a quarantined copy. If you'd rather not clear the quarantine flag, launch the app once, let macOS block it, then approve it under System Settings → Privacy & Security → **Open Anyway**. The same applies after `brew upgrade`.

### Build from source

No paid Apple Developer Program membership required:

```sh
./Scripts/install-local.sh
```

The script builds the app, signs it with a stable identity, installs it to `/Applications`, registers the Finder extension, and launches it. Signing uses a self-signed certificate named `Mac Tweaks Local Code Signing`, created automatically on first run. See [Development](#development) for details.

## First-run setup

Launch **Mac Tweaks** (it appears in the menu bar), open **Settings** from its menu, and enable the tweaks you want. Depending on which tweaks you enable, macOS needs some one-time approvals:

1. **Finder extension** (right-click actions): System Settings → General → Login Items & Extensions → Finder Extensions → enable **Mac Tweaks Finder Actions**.
2. **Accessibility** (Backspace-to-Trash, Paste-as-file, and Cut & paste tweaks, plus the Option+right-click fallback menu): System Settings → Privacy & Security → Accessibility → enable **Mac Tweaks**.
3. **Input Monitoring** (Backspace-to-Trash, Paste-as-file, and Cut & paste tweaks): System Settings → Privacy & Security → Input Monitoring → enable **Mac Tweaks**.
4. **Finder automation**: the first time the delete, paste-as-file, or cut & paste tweak acts, macOS asks to allow Mac Tweaks to control Finder — click Allow.

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

`./Scripts/install-local.sh` installs a local build to `/Applications`. A *stable* signing identity matters: re-signing with a different identity resets the app's Accessibility/Input Monitoring permissions. The script signs with a self-signed certificate (`Mac Tweaks Local Code Signing`) that it creates once and reuses for every build — this also keeps personal Apple ID details out of the signature. To sign with a different identity instead (for example an `Apple Development` certificate), set `MAC_TWEAKS_SIGNING_IDENTITY` to its exact name; verify available identities with `security find-identity -v -p codesigning`.

### Releasing

`./Scripts/release.sh` builds and signs a Release configuration, uploads the zip to a GitHub release, and updates the Homebrew cask in [NoahCLR/homebrew-tap](https://github.com/NoahCLR/homebrew-tap). It refuses to run on a dirty tree, runs the tests first, and derives the version from `CFBundleShortVersionString`.

## License

[MIT](LICENSE)
