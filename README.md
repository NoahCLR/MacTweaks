# Mac Tweaks

Mac Tweaks is a lightweight macOS menu bar app that adds practical Finder shortcuts, clipboard tools, and screen OCR.

It lives in the menu bar without adding a Dock icon, and every feature can be enabled or disabled independently.

## What it does

### Finder right-click actions

Add these actions to Finder's context menu and arrange them in your preferred order:

- **Create New File Here** — create an empty file in the folder you clicked.
- **Open in IDE** — open the selected file or folder in your chosen editor.
- **Copy Path** — copy the full path of one or more selected items.
- **Open in Terminal** — open your terminal in the selected folder.

### Finder keyboard shortcuts

- **Backspace/Delete to Trash** — move the selected Finder items to Trash without holding ⌘.
- **⌘X / ⌘V to move files** — use Windows-style cut and paste for files. Finder performs the move, so ⌘Z still undoes it.

### Clipboard to file

Press ⌘V in Finder or on the Desktop to save copied content directly into the current folder. Images become `.png` or `.jpg` files, rich text becomes `.rtf`, and plain text becomes `.txt`. Copied files continue to paste normally.

### OCR to Clipboard

Press a configurable shortcut, drag over any part of the screen, and Mac Tweaks copies the recognized text to your clipboard. OCR runs locally using Apple's Vision framework, and the temporary screenshot is deleted immediately after processing.

## Install

Mac Tweaks requires **macOS 14 or later**.

### Homebrew

```sh
brew install NoahCLR/tap/mac-tweaks
xattr -dr com.apple.quarantine "/Applications/Mac Tweaks.app"
```

Mac Tweaks is signed but not notarized because it is built without a paid Apple Developer account. Gatekeeper therefore blocks the first launch of a quarantined copy. The `xattr` command clears that quarantine flag.

Alternatively, launch the app once, let macOS block it, then approve it under System Settings → Privacy & Security → **Open Anyway**. The same step may be needed after `brew upgrade`.

### Build from source

No paid Apple Developer Program membership is required:

```sh
./Scripts/install-local.sh
```

The script builds Mac Tweaks, signs it with a stable local identity, installs it in `/Applications`, registers the Finder extension, and launches it. See [Development](#development) for signing details.

## First-run setup

Launch Mac Tweaks, click its menu bar icon, and open **Settings**. The Permissions tab guides you to the one-time macOS approvals needed by the features you use.

| Approval | Used by |
| --- | --- |
| **Finder Extension** | Finder right-click actions |
| **Accessibility** | Finder keyboard and clipboard shortcuts, the compatibility menu, and the global OCR shortcut |
| **Screen Recording** | Capturing the selected screen region for OCR only |
| **Finder Automation** | Clipboard-to-file, cut/paste files, and the Option+right-click compatibility menu |

To enable the Finder extension manually, open System Settings → General → Login Items & Extensions → Finder Extensions and turn on **Mac Tweaks Finder Actions**. macOS asks for Finder Automation the first time one of the listed features reads Finder state; choose **Allow**.

The Permissions tab does not request permissions automatically. Accessibility and Screen Recording are independent and can be granted in either order. Clicking **Continue** requests only that row; if macOS has already shown its prompt, the action changes to **Open Settings** so you can flip the switch directly. Input Monitoring is not required.

Updates installed with `brew upgrade` keep these approvals because releases use the same stable signing identity.

## Behavior details

### Clipboard to file

- Images take priority when the clipboard contains both an image and text.
- PNG and JPEG data are preserved; other image formats are converted to PNG.
- Image and text handling can be switched off separately.
- Pasting copied files, or pasting while renaming or searching in Finder, is left to Finder.
- New files receive timestamped names such as `Pasted Image 2026-07-07 at 14.30.05.png`.

### Cut and paste files

- A plain ⌘V moves files only after Mac Tweaks has seen a matching ⌘X.
- Copying something else with ⌘C cancels the pending cut.
- Finder handles undo, name conflicts, permissions, and moves between volumes.
- ⌘X in a rename or search field continues to cut text normally.

### Finder menu compatibility

The Finder Sync extension provides the normal right-click menu. An optional **Option+right-click compatibility menu** provides the same actions in Finder locations where extensions are unreliable.

## Development

Open `MacTweaks.xcodeproj` in Xcode and run the `MacTweaks` scheme, or use the command line:

```sh
# Build without signing
xcodebuild -project MacTweaks.xcodeproj -scheme MacTweaks -configuration Debug -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build

# Run tests
xcodebuild -project MacTweaks.xcodeproj -scheme MacTweaks -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Targets: `Mac Tweaks` (app), `MacTweaksFinderExtension` (embedded Finder Sync extension), and `MacTweaksTests`.

### Local install and signing

`./Scripts/install-local.sh` installs a local build in `/Applications`. A stable signing identity matters because macOS ties Accessibility and Screen Recording approvals to the signature; changing it resets those approvals.

The script creates and reuses a self-signed certificate named `Mac Tweaks Local Code Signing`. This also keeps personal Apple ID details out of the signature. To use another identity, set `MAC_TWEAKS_SIGNING_IDENTITY` to its exact name. List available identities with `security find-identity -v -p codesigning`.

### Releasing

`./Scripts/release.sh` builds and signs a Release configuration, runs the tests, uploads the archive to a GitHub release, and updates the Homebrew cask in [NoahCLR/homebrew-tap](https://github.com/NoahCLR/homebrew-tap). It derives the version from `CFBundleShortVersionString` and refuses to run from a dirty worktree.

## License

[MIT](LICENSE)
