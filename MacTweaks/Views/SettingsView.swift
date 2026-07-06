import SwiftUI
import AppKit
import FinderSync

struct SettingsView: View {
    @ObservedObject var settings: SharedSettingsStore
    let keyboardController: KeyboardDeleteController

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var launchAtLoginError: String?
    @State private var finderExtensionEnabled = FIFinderSyncController.isExtensionEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "switch.2") }
            finderActionsTab
                .tabItem { Label("Finder Actions", systemImage: "folder") }
            keyboardTab
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 620)
        .onAppear {
            refreshFinderExtensionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshFinderExtensionStatus()
        }
    }

    private var generalTab: some View {
        settingsPage {
            settingsSection("App") {
                toggleRow(
                    title: "Enable Mac Tweaks",
                    detail: settings.masterEnabled ? "Finder actions and keyboard tweaks are active." : "All tweaks are paused.",
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
        }
    }

    private var finderActionsTab: some View {
        settingsPage {
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
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var keyboardTab: some View {
        settingsPage {
            settingsSection("Finder Keyboard") {
                toggleRow(
                    title: "Backspace/Delete moves items to Trash",
                    detail: "Works only while Finder is active.",
                    help: "Maps Backspace/Delete to Finder's Move to Trash command after permissions are granted.",
                    isOn: $settings.deleteKeyEnabled
                )
                rowDivider()
                statusRow(
                    title: "Keyboard tap",
                    status: keyboardController.isRunning ? "Running" : "Stopped",
                    tone: keyboardController.isRunning ? .green : .secondary,
                    help: "Shows whether the low-level keyboard listener is currently active."
                )
            }

            settingsSection("Required Access") {
                permissionRow(
                    title: "Accessibility",
                    status: KeyboardDeleteController.isAccessibilityTrusted ? "Granted" : "Required",
                    tone: KeyboardDeleteController.isAccessibilityTrusted ? .green : .orange,
                    buttonTitle: "Request",
                    help: "Required so Mac Tweaks can confirm Finder focus and route keyboard events correctly.",
                    action: {
                        KeyboardDeleteController.requestAccessibilityPermission()
                        keyboardController.refresh()
                    }
                )
                rowDivider()
                permissionRow(
                    title: "Input Monitoring",
                    status: KeyboardDeleteController.canListenToInputEvents ? "Granted" : "Required",
                    tone: KeyboardDeleteController.canListenToInputEvents ? .green : .orange,
                    buttonTitle: "Request",
                    help: "Required for the Backspace/Delete keyboard tweak.",
                    action: {
                        KeyboardDeleteController.requestInputEventPermission()
                        keyboardController.refresh()
                    }
                )
            }
        }
    }

    private var permissionsTab: some View {
        settingsPage {
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
                    status: KeyboardDeleteController.isAccessibilityTrusted ? "Granted" : "Required",
                    tone: KeyboardDeleteController.isAccessibilityTrusted ? .green : .orange,
                    buttonTitle: "Open Settings",
                    help: "System privacy permission used by the fallback menu and keyboard tweak.",
                    action: openAccessibilitySettings
                )
                rowDivider()
                permissionRow(
                    title: "Input Monitoring",
                    status: KeyboardDeleteController.canListenToInputEvents ? "Granted" : "Required",
                    tone: KeyboardDeleteController.canListenToInputEvents ? .green : .orange,
                    buttonTitle: "Open Settings",
                    help: "System privacy permission required for listening to Backspace/Delete.",
                    action: openInputMonitoringSettings
                )
            }
        }
    }

    private func settingsPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func finderActionTitle(_ action: FinderMenuAction) -> String {
        switch action {
        case .createNewFileHere:
            return "Create New File Here"
        case .openInIDE:
            let ideName = settings.ideApplicationURL?.deletingPathExtension().lastPathComponent ?? "IDE"
            return "Open in \(ideName)"
        case .copyPath:
            return "Copy Path"
        case .openTerminalHere:
            let terminalName = settings.terminalApplicationURL?.deletingPathExtension().lastPathComponent ?? "Terminal"
            return "Open in \(terminalName)"
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

    private func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
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
