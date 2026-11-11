import AppKit
import AriadneCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var hotKeyManager: GlobalHotKeyManager
    @ObservedObject var launcherViewModel: LauncherViewModel
    let launcher: ProjectLauncher

    var body: some View {
        TabView {
            GeneralSettingsTab(
                settingsStore: settingsStore,
                hotKeyManager: hotKeyManager
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            AppsSettingsTab(
                settingsStore: settingsStore,
                launcher: launcher
            )
            .tabItem {
                Label("VS Code & Kitty", systemImage: "terminal")
            }

            SourcesSettingsTab(
                settingsStore: settingsStore,
                launcherViewModel: launcherViewModel
            )
            .tabItem {
                Label("Sources", systemImage: "folder.badge.gearshape")
            }
        }
        .frame(width: 560, height: 470)
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var hotKeyManager: GlobalHotKeyManager

    @State private var launchAtLoginEnabled = false
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Global Shortcut") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Toggle Ariadne Launcher")
                        .font(.system(size: 13, weight: .medium))
                    ShortcutRecorderView(
                        settingsStore: settingsStore,
                        hotKeyManager: hotKeyManager
                    )
                }
                .padding(.vertical, 4)
            }

            Section("Behavior") {
                Picker("Default Enter (⏎) Action", selection: $settingsStore.defaultEnterAction) {
                    ForEach(DefaultEnterAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Launcher Keyboard Shortcuts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        shortcutRow("⏎", settingsStore.defaultEnterAction.actionType.title)
                        shortcutRow("⌘⏎", settingsStore.defaultEnterAction.commandReturnActionType.title)
                    }
                    HStack(spacing: 16) {
                        shortcutRow("⌥⏎", "Open in VS Code & Kitty")
                        shortcutRow("Tab / ⌘K", "All Actions Menu")
                    }
                    HStack(spacing: 16) {
                        shortcutRow("⌘P", "Pin / Unpin Project")
                        shortcutRow("⌘1–⌘9", "Quick Open Project")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Startup & App") {
                Toggle("Launch Ariadne at Login", isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { updateLaunchAtLogin($0) }
                ))

                if let loginItemError {
                    Text(loginItemError)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersionString)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshLaunchAtLoginStatus()
        }
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(desc)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLogin(_ enable: Bool) {
        loginItemError = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            if !Bundle.main.bundlePath.hasSuffix(".app") {
                loginItemError = "Launch at Login requires running Ariadne.app bundle."
            } else {
                loginItemError = error.localizedDescription
            }
        }
    }
}

// MARK: - VS Code & Kitty Tab

private struct AppsSettingsTab: View {
    @ObservedObject var settingsStore: AppSettingsStore
    let launcher: ProjectLauncher

    var body: some View {
        Form {
            Section("Visual Studio Code") {
                appDetectionRow(
                    title: "Detected",
                    target: launcher.detectVSCodeTarget(customPath: settingsStore.customVSCodePath)
                )

                HStack {
                    TextField("Auto-detect (/Applications/Visual Studio Code.app)", text: $settingsStore.customVSCodePath)
                        .textFieldStyle(.roundedBorder)

                    Button("Choose…") {
                        if let selected = chooseApplicationOrBinary(startingAt: "/Applications") {
                            settingsStore.customVSCodePath = selected
                        }
                    }

                    if !settingsStore.customVSCodePath.isEmpty {
                        Button("Clear") {
                            settingsStore.customVSCodePath = ""
                        }
                    }
                }
            }

            Section("Kitty Terminal") {
                appDetectionRow(
                    title: "Detected",
                    target: launcher.detectKittyTarget(customPath: settingsStore.customKittyPath)
                )

                HStack {
                    TextField("Auto-detect (/Applications/kitty.app)", text: $settingsStore.customKittyPath)
                        .textFieldStyle(.roundedBorder)

                    Button("Choose…") {
                        if let selected = chooseApplicationOrBinary(startingAt: "/Applications") {
                            settingsStore.customKittyPath = selected
                        }
                    }

                    if !settingsStore.customKittyPath.isEmpty {
                        Button("Clear") {
                            settingsStore.customKittyPath = ""
                        }
                    }
                }

                Picker("Launch Mode", selection: $settingsStore.kittyLaunchMode) {
                    ForEach(KittyLaunchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(settingsStore.kittyLaunchMode.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                if settingsStore.kittyLaunchMode == .newTab {
                    TextField("Optional socket (e.g. unix:/tmp/kitty)", text: $settingsStore.kittyRemoteSocket)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func appDetectionRow(title: String, target: LaunchTarget?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let target {
                Label(target.displayPath, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Label("Not found", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func chooseApplicationOrBinary(startingAt directory: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: directory)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

// MARK: - Sources Tab

private struct SourcesSettingsTab: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var launcherViewModel: LauncherViewModel

    var body: some View {
        Form {
            Section("VS Code Project Sources") {
                Toggle("Visual Studio Code (state.vscdb & workspaceStorage)", isOn: $settingsStore.includeVSCode)
                Toggle("Visual Studio Code Insiders", isOn: $settingsStore.includeVSCodeInsiders)
                Toggle("VS Code Project Manager Extension (projects.json)", isOn: $settingsStore.includeProjectManager)
                Toggle("Hide deleted or missing directories", isOn: $settingsStore.hideMissingProjects)
            }

            Section("Custom Scan Folders") {
                if settingsStore.customScanDirectories.isEmpty {
                    Text("Optionally add parent folders (e.g. ~/Projects) to index subfolders alongside VS Code history.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settingsStore.customScanDirectories, id: \.self) { dir in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(dir)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                settingsStore.customScanDirectories.removeAll { $0 == dir }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    Button("Add Folder…") {
                        if let folder = chooseDirectory() {
                            if !settingsStore.customScanDirectories.contains(folder) {
                                settingsStore.customScanDirectories.append(folder)
                            }
                        }
                    }

                    Spacer()

                    Text("\(launcherViewModel.allProjects.count) projects indexed")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    Button("Refresh Now") {
                        launcherViewModel.refreshProjects()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
