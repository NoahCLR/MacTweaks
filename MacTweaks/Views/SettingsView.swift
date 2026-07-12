import SwiftUI
import AppKit
import FinderSync

/// Lets code outside the view (the status-menu "needs attention" row) steer the
/// Settings window to a specific tab. The view consumes and clears the request.
final class SettingsRouter: ObservableObject {
    @Published var requestedTab: SettingsTab?
}

struct SettingsView: View {
    @ObservedObject var settings: SharedSettingsStore
    @ObservedObject var router: SettingsRouter
    @ObservedObject var permissionOnboarding: PermissionOnboardingCoordinator
    let keyboardController: KeyboardDeleteController
    let ocrController: ScreenCaptureOCRController

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var launchAtLoginError: String?
    @State private var finderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 20) {
            tabBar
                .padding(.horizontal, 24)

            // The content ScrollView is full-width so its scroll indicator gets its
            // own lane at the window edge; the cards inside are inset 24 (matching
            // the tab bar) so the scrollbar never overlaps a control.
            Group {
                switch selection {
                case .general: generalTab
                case .finderTweaks: finderTweaksTab
                case .clipboardTweaks: clipboardTweaksTab
                case .permissions: permissionsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 24)
        .frame(minWidth: 820, minHeight: 620)
        .onAppear {
            refreshFinderExtensionStatus()
            applyRequestedTab()
            permissionOnboarding.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshFinderExtensionStatus()
            permissionOnboarding.refresh()
        }
        .onChange(of: router.requestedTab) { _, _ in
            applyRequestedTab()
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection == .permissions {
                permissionOnboarding.refresh()
            }
        }
    }

    private func applyRequestedTab() {
        guard let tab = router.requestedTab else { return }
        selection = tab
        router.requestedTab = nil
    }

    // Custom segmented tab bar: full-width, equal-width tabs so the selection
    // aligns with the content cards below (the stock TabView strip is centered and
    // narrower). Liquid Glass container on macOS 26, material fallback otherwise.
    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selection == tab
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = tab }
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected {
                        Capsule(style: .continuous).fill(Color.accentColor)
                    }
                }
            }
        }
        .padding(5)
        .modifier(GlassCapsule())
        .focusEffectDisabled()
    }

    private var generalTab: some View {
        settingsPage {
            settingsSection("App") {
                toggleRow(
                    title: "Enable Mac Tweaks",
                    detail: settings.masterEnabled ? "Finder and clipboard tweaks are active." : "All tweaks are paused.",
                    help: "Turns every Mac Tweaks Finder and keyboard feature on or off.",
                    isOn: $settings.masterEnabled
                )
                rowDivider()
                toggleRow(
                    title: "Launch at Login",
                    detail: "Start Mac Tweaks automatically when you sign in.",
                    help: "Keeps the menu bar app available after restarting or signing back in.",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLoginController.setEnabled(newValue)
                        launchAtLoginError = nil
                    } catch {
                        launchAtLoginError = error.localizedDescription
                        launchAtLogin = LaunchAtLoginController.isEnabled
                    }
                }

                if let launchAtLoginError {
                    rowDivider()
                    Text(launchAtLoginError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private var finderTweaksTab: some View {
        settingsPage {
            if finderKeyboardTweaksNeedPermission {
                permissionNotice
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Right-Click Actions") {
                        finderActionToggleRow(.createNewFileHere)
                        rowDivider()
                        finderActionToggleRow(.openInIDE)
                        rowDivider()
                        finderActionToggleRow(.copyPath)
                        rowDivider()
                        finderActionToggleRow(.openTerminalHere)
                    }

                    settingsSection("Default Apps") {
                        appPickerRow(
                            title: "IDE",
                            value: settings.ideApplicationURL?.deletingPathExtension().lastPathComponent ?? "Not selected",
                            systemImage: "hammer",
                            actionTitle: "Choose...",
                            help: "App used by the Open in IDE Finder action.",
                            action: chooseIDE
                        )
                        rowDivider()
                        appPickerRow(
                            title: "Terminal",
                            value: settings.terminalApplicationURL?.deletingPathExtension().lastPathComponent ?? "Not selected",
                            systemImage: "terminal",
                            actionTitle: "Choose...",
                            help: "Terminal app used by the Open Terminal Finder action.",
                            action: chooseTerminal
                        )
                    }

                    settingsSection("Behavior") {
                        toggleRow(
                            title: "Compatibility Option-right-click menu",
                            detail: "Fallback menu for Finder locations where extensions are unreliable.",
                            help: "Shows Mac Tweaks actions from the app when Finder Sync menus are missing, mainly on Desktop and cloud folders.",
                            isOn: $settings.enhancedFinderMenusEnabled
                        )
                        rowDivider()
                        toggleRow(
                            title: "Open containing folder for files",
                            detail: "Open IDE and terminal actions target the parent folder for selected files.",
                            help: "When a file is selected, opens its folder instead of passing the file itself to the IDE or terminal.",
                            isOn: $settings.openContainingFolderForFiles
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 16) {
                    settingsSection("Menu Order") {
                        HStack {
                            Text("Right-click menu order")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Reset") {
                                settings.resetFinderActionOrder()
                            }
                            .help("Restore the default right-click menu order.")
                        }
                        .padding(.bottom, 6)

                        finderActionOrderList
                    }

                    settingsSection("Finder Coverage") {
                        HStack {
                            Text("Monitored folders")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Add...") {
                                addMonitoredFolder()
                            }
                            .help("Add folders where Finder Sync should offer Mac Tweaks actions.")
                            Button("Restore Defaults") {
                                settings.resetMonitoredFolders()
                            }
                            .help("Monitor the standard Finder locations again.")
                        }
                        .padding(.bottom, 6)

                        monitoredFolderList
                    }

                    settingsSection("Finder Keyboard") {
                        toggleRow(
                            title: "Backspace/Delete moves items to Trash",
                            detail: "Works only while Finder is active.",
                            help: "Maps Backspace/Delete to Finder's Move to Trash command after permissions are granted.",
                            isOn: $settings.deleteKeyEnabled
                        )
                        rowDivider()
                        statusRow(
                            title: "Currently remapping Backspace",
                            status: keyboardController.isRunning ? "Active" : "Inactive",
                            tone: keyboardController.isRunning ? .green : .secondary,
                            help: "Whether Backspace/Delete is being remapped to Move to Trash right now. Turns Active once the toggle above is on and Accessibility is granted (see the Permissions tab)."
                        )
                        rowDivider()
                        toggleRow(
                            title: "Cut & paste files with ⌘X / ⌘V (Windows-style move)",
                            detail: "In Finder, ⌘X marks the selected files and the next ⌘V moves them into the current folder. ⌘Z undoes the move.",
                            help: "⌘X copies the selection to the clipboard and marks it as a cut; a following plain ⌘V asks Finder to move those files. Finder performs the move, so it is undoable and handles permissions, name conflicts, and cross-volume moves. A ⌘C in between cancels the cut. ⌘X inside a rename field still cuts text normally.",
                            isOn: $settings.cutFilesEnabled
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var clipboardTweaksTab: some View {
        settingsPage {
            if clipboardTweaksNeedPermission {
                permissionNotice
            }

            settingsSection("Paste Clipboard as File") {
                toggleRow(
                    title: "Paste clipboard as a file",
                    detail: "In Finder, ⌘V turns clipboard data (like a screenshot) into a file in the current folder.",
                    help: "Intercepts ⌘V while Finder is frontmost. Copied files and rename fields still paste normally; only raw image or text data becomes a file.",
                    isOn: $settings.clipboardToFileEnabled
                )
                if settings.clipboardToFileEnabled {
                    rowDivider()
                    toggleRow(
                        title: "Images",
                        detail: "Screenshots and copied images are saved as .png (or .jpg when copied as JPEG).",
                        help: "PNG and JPEG data keep their format; anything else (e.g. a TIFF screenshot) is saved as PNG.",
                        isOn: $settings.pasteImageAsFile
                    )
                    rowDivider()
                    toggleRow(
                        title: "Text",
                        detail: "Copied text is saved as .rtf when styled, otherwise .txt.",
                        help: "Only used when the clipboard has no image. Rich text is preserved as .rtf; plain text becomes UTF-8 .txt.",
                        isOn: $settings.pasteTextAsFile
                    )
                }
            }

            settingsSection("OCR to Clipboard") {
                toggleRow(
                    title: "Copy text from a screen selection",
                    detail: "Press the shortcut, drag to select any part of the screen, and the text in it is copied to the clipboard.",
                    help: "Runs macOS's screen capture, recognizes text in the selection with the Vision framework, and puts it on the clipboard. Works over any app. Needs Accessibility and Screen Recording permission (see the Permissions tab).",
                    isOn: $settings.ocrEnabled
                )
                if settings.ocrEnabled {
                    rowDivider()
                    shortcutRow
                    rowDivider()
                    statusRow(
                        title: "Currently listening for the shortcut",
                        status: ocrController.isRunning ? "Active" : "Inactive",
                        tone: ocrController.isRunning ? .green : .secondary,
                        help: "Whether the OCR shortcut is being watched right now. Turns Active once the toggle above is on and Accessibility is granted. Capturing the selection also needs Screen Recording."
                    )
                }
            }
        }
    }

    private var shortcutRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut")
                    .font(.body)
                Text("Click the field, then press the key combination you want.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ShortcutRecorderField(hotKey: $settings.ocrHotKey)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }

    /// The keyboard/clipboard tweaks all rely on Accessibility for their modifying
    /// event taps. Each tab shows an inline pointer to the Permissions tab when one of *its*
    /// tweaks is enabled but a required permission is still missing (grant lives
    /// only on that tab).
    private var finderKeyboardTweaksNeedPermission: Bool {
        (settings.deleteKeyEnabled || settings.cutFilesEnabled) && eventTapPermissionMissing
    }

    private var clipboardTweaksNeedPermission: Bool {
        (settings.clipboardToFileEnabled || settings.ocrEnabled) && eventTapPermissionMissing
    }

    private var eventTapPermissionMissing: Bool {
        !permissionOnboarding.snapshot.accessibilityGranted
    }

    private var permissionNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Permissions required")
                    .font(.body.weight(.medium))
                Text("These tweaks need Accessibility access to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Permissions") {
                withAnimation(.easeOut(duration: 0.15)) { selection = .permissions }
            }
            .help("Grant Accessibility on the Permissions tab.")
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var permissionsTab: some View {
        settingsPage {
            permissionSetupGuide

            settingsSection("Finder Extension") {
                permissionRow(
                    title: "Finder Extension",
                    status: finderExtensionEnabled ? "Enabled" : "Disabled",
                    tone: finderExtensionEnabled ? .green : .orange,
                    buttonTitle: finderExtensionEnabled ? "Manage" : "Enable",
                    help: "Finder Sync extension that adds Mac Tweaks actions to Finder right-click menus.",
                    action: openExtensionsSettings
                )
            }

            settingsSection("Privacy Permissions") {
                permissionRow(
                    title: "Accessibility",
                    status: accessibilityStatus,
                    tone: permissionOnboarding.snapshot.accessibilityGranted ? .green : .orange,
                    buttonTitle: accessibilityButtonTitle,
                    help: "Allows Mac Tweaks to observe and replace input events for its keyboard shortcuts and compatibility menu.",
                    action: accessibilityButtonAction
                )
                rowDivider()
                permissionRow(
                    title: "Screen Recording",
                    status: screenRecordingStatus,
                    tone: screenRecordingTone,
                    buttonTitle: screenRecordingButtonTitle,
                    isEnabled: screenRecordingActionEnabled,
                    help: "Allows OCR to Clipboard to capture the selected part of the screen. It is not requested while OCR is turned off.",
                    action: screenRecordingButtonAction
                )
            }
        }
    }

    private var permissionSetupGuide: some View {
        settingsSection("Permission Setup") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: privacyPermissionsReady ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(privacyPermissionsReady ? Color.green : Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    if privacyPermissionsReady {
                        Text("Required permissions are ready")
                            .font(.body.weight(.semibold))
                        Text(permissionReadyDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Choose permissions individually")
                            .font(.body.weight(.semibold))
                        Text("Each Continue button below asks macOS for that permission only. Accessibility and Screen Recording are independent, so you can grant them in either order. Returning here only refreshes their status.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }

    private var privacyPermissionsReady: Bool {
        permissionOnboarding.snapshot.accessibilityGranted
            && (!settings.ocrEnabled || permissionOnboarding.snapshot.screenCaptureGranted)
    }

    private var permissionReadyDetail: String {
        if settings.ocrEnabled {
            return "Accessibility and Screen Recording are granted."
        }
        return "Accessibility is granted. Screen Recording is not needed while OCR to Clipboard is off."
    }

    private var accessibilityStatus: String {
        if permissionOnboarding.snapshot.accessibilityGranted { return "Granted" }
        return permissionOnboarding.hasRequested(.accessibility) ? "Enable in System Settings" : "Required"
    }

    private var accessibilityButtonTitle: String {
        if permissionOnboarding.snapshot.accessibilityGranted
            || permissionOnboarding.hasRequested(.accessibility) {
            return "Open Settings"
        }
        return "Continue"
    }

    /// The closure is selected while the button is rendered. A queued click on a
    /// stale Continue button can therefore only repeat `request` (which is a
    /// coordinator no-op), never turn into Open Settings mid-click.
    private var accessibilityButtonAction: () -> Void {
        if permissionOnboarding.snapshot.accessibilityGranted
            || permissionOnboarding.hasRequested(.accessibility) {
            return { openAccessibilitySettings() }
        }
        return { permissionOnboarding.request(.accessibility) }
    }

    private var screenRecordingStatus: String {
        if permissionOnboarding.snapshot.screenCaptureGranted { return "Granted" }
        if !settings.ocrEnabled { return "Not needed while OCR is off" }
        return permissionOnboarding.hasRequested(.screenRecording)
            ? "Enable in System Settings"
            : "Required for OCR to Clipboard"
    }

    private var screenRecordingTone: StatusTone {
        if permissionOnboarding.snapshot.screenCaptureGranted { return .green }
        return settings.ocrEnabled ? .orange : .secondary
    }

    private var screenRecordingButtonTitle: String {
        if permissionOnboarding.snapshot.screenCaptureGranted { return "Open Settings" }
        if !settings.ocrEnabled { return "Not Needed" }
        if permissionOnboarding.hasRequested(.screenRecording) { return "Open Settings" }
        return "Continue"
    }

    private var screenRecordingActionEnabled: Bool {
        if permissionOnboarding.snapshot.screenCaptureGranted { return true }
        return settings.ocrEnabled
    }

    private var screenRecordingButtonAction: () -> Void {
        if permissionOnboarding.snapshot.screenCaptureGranted {
            return { openScreenRecordingSettings() }
        }
        if !settings.ocrEnabled {
            return {}
        }
        if permissionOnboarding.hasRequested(.screenRecording) {
            return { openScreenRecordingSettings() }
        }
        return { requestScreenRecordingIfEligible() }
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func toggleRow(title: String, detail: String, help: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
            }
            .frame(maxWidth: 520, alignment: .leading)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .help(help)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .help(help)
    }

    private func finderActionToggleRow(_ action: FinderMenuAction) -> some View {
        let detail = finderActionDetail(action)

        return toggleRow(
            title: finderActionTitle(action),
            detail: detail,
            help: detail,
            isOn: finderActionBinding(action)
        )
    }

    private func appPickerRow(
        title: String,
        value: String,
        systemImage: String,
        actionTitle: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(actionTitle, action: action)
                .frame(minWidth: 86, alignment: .trailing)
                .help(help)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .help(help)
    }

    private func statusRow(title: String, status: String, tone: StatusTone, help: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            statusBadge(status, tone: tone)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .help(help)
    }

    private func permissionRow(
        title: String,
        status: String,
        tone: StatusTone,
        buttonTitle: String,
        isEnabled: Bool = true,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                statusBadge(status, tone: tone)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .frame(minWidth: 104, alignment: .trailing)
                .disabled(!isEnabled)
                .help(help)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .help(help)
    }

    private func statusBadge(_ text: String, tone: StatusTone) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tone.foregroundStyle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tone.backgroundStyle, in: Capsule())
    }

    private func rowDivider() -> some View {
        Divider()
    }

    private var finderActionOrderList: some View {
        VStack(spacing: 0) {
            ForEach(settings.finderActionOrder) { action in
                finderActionOrderRow(action)
                    .padding(.vertical, 8)
                if settings.finderActionOrder.last != action {
                    rowDivider()
                        .padding(.leading, 30)
                }
            }
        }
    }

    private var monitoredFolderList: some View {
        VStack(spacing: 0) {
            if settings.monitoredFolderURLs.isEmpty {
                Text("No folders selected")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(settings.monitoredFolderURLs, id: \.path) { url in
                    monitoredFolderRow(url)
                        .padding(.vertical, 8)
                    if settings.monitoredFolderURLs.last?.path != url.path {
                        rowDivider()
                            .padding(.leading, 8)
                    }
                }
            }
        }
    }

    private func chooseIDE() {
        let panel = NSOpenPanel()
        panel.title = "Choose IDE"
        panel.message = "Choose the app that should open Finder items."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.chooseIDEApplication(url)
    }

    private func chooseTerminal() {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal"
        panel.message = "Choose the terminal app that should open Finder folders."
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.chooseTerminalApplication(url)
    }

    private func finderActionOrderRow(_ action: FinderMenuAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(.tertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(finderActionTitle(action))
                    .font(.callout)
                if !isFinderActionEnabled(action) {
                    Text("Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                settings.moveFinderAction(action, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(settings.finderActionOrder.first == action)
            .help("Move up")

            Button {
                settings.moveFinderAction(action, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(settings.finderActionOrder.last == action)
            .help("Move down")
        }
    }

    private func monitoredFolderRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(url.path)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                removeMonitoredFolder(url)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Remove folder")
        }
        .help(url.path)
    }

    // Settings labels stay generic ("Open in IDE" / "Open in Terminal") because the
    // chosen app is shown in the Default Apps section below; the actual Finder menu
    // uses the dynamic app name via FinderMenuAction.title(settings:).
    private func finderActionTitle(_ action: FinderMenuAction) -> String {
        switch action {
        case .createNewFileHere:
            return "Create New File Here"
        case .openInIDE:
            return "Open in IDE"
        case .copyPath:
            return "Copy Path"
        case .openTerminalHere:
            return "Open in Terminal"
        }
    }

    private func finderActionDetail(_ action: FinderMenuAction) -> String {
        switch action {
        case .createNewFileHere:
            return "Adds a blank file in the current Finder folder."
        case .openInIDE:
            return "Uses \(settings.ideApplicationURL?.deletingPathExtension().lastPathComponent ?? "the selected IDE")."
        case .copyPath:
            return "Copies selected Finder item paths."
        case .openTerminalHere:
            return "Uses \(settings.terminalApplicationURL?.deletingPathExtension().lastPathComponent ?? "the selected terminal")."
        }
    }

    private func finderActionBinding(_ action: FinderMenuAction) -> Binding<Bool> {
        switch action {
        case .createNewFileHere:
            return $settings.createFileEnabled
        case .openInIDE:
            return $settings.openInIDEEnabled
        case .copyPath:
            return $settings.copyPathEnabled
        case .openTerminalHere:
            return $settings.openTerminalEnabled
        }
    }

    private func isFinderActionEnabled(_ action: FinderMenuAction) -> Bool {
        switch action {
        case .createNewFileHere:
            return settings.createFileEnabled
        case .openInIDE:
            return settings.openInIDEEnabled
        case .copyPath:
            return settings.copyPathEnabled
        case .openTerminalHere:
            return settings.openTerminalEnabled
        }
    }

    private func addMonitoredFolder() {
        let panel = NSOpenPanel()
        panel.title = "Add Monitored Finder Folder"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(settings.addMonitoredFolder)
    }

    private func removeMonitoredFolder(_ url: URL) {
        guard let index = settings.monitoredFolderURLs.firstIndex(where: { $0.path == url.path }) else { return }
        settings.removeMonitoredFolders(at: IndexSet(integer: index))
    }

    private func requestScreenRecordingIfEligible() {
        permissionOnboarding.refresh()
        guard settings.ocrEnabled else { return }
        permissionOnboarding.request(.screenRecording)
    }

    private func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openScreenRecordingSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openExtensionsSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            refreshFinderExtensionStatus()
        }
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshFinderExtensionStatus() {
        finderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case finderTweaks
    case clipboardTweaks
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .finderTweaks: return "Finder Tweaks"
        case .clipboardTweaks: return "Clipboard Tweaks"
        case .permissions: return "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "switch.2"
        case .finderTweaks: return "folder"
        case .clipboardTweaks: return "doc.on.clipboard"
        case .permissions: return "lock.shield"
        }
    }
}

/// Wraps content in a Liquid Glass capsule on macOS 26+, falling back to a
/// material-filled capsule on earlier systems (the app deploys to macOS 14).
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(in: Capsule(style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }
}

private enum StatusTone {
    case green
    case orange
    case secondary

    var foregroundStyle: AnyShapeStyle {
        switch self {
        case .green:
            return AnyShapeStyle(.green)
        case .orange:
            return AnyShapeStyle(.orange)
        case .secondary:
            return AnyShapeStyle(.secondary)
        }
    }

    var backgroundStyle: AnyShapeStyle {
        switch self {
        case .green:
            return AnyShapeStyle(.green.opacity(0.12))
        case .orange:
            return AnyShapeStyle(.orange.opacity(0.12))
        case .secondary:
            return AnyShapeStyle(.secondary.opacity(0.12))
        }
    }
}
