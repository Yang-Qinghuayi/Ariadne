import AppKit
import Foundation

public enum LaunchTarget: Equatable, Sendable {
    case appBundle(URL)
    case cliExecutable(URL)

    public var url: URL {
        switch self {
        case .appBundle(let url), .cliExecutable(let url):
            return url
        }
    }

    public var displayPath: String {
        url.path
    }
}

public enum ProjectLaunchError: LocalizedError, Sendable {
    case editorNotFound(EditorAppKind)
    case kittyNotFound
    case directoryNotFound(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .editorNotFound(let editor):
            return "\(editor.displayName) was not found. Install \(editor.displayName) or set its path in Settings."
        case .kittyNotFound:
            return "Kitty terminal was not found. Install Kitty or set its path in Settings."
        case .directoryNotFound(let path):
            return "Project directory does not exist: \(path)"
        case .launchFailed(let message):
            return message
        }
    }
}

public final class ProjectLauncher {
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let applicationBundleLookup: (String) -> URL?
    private let appSearchDirectories: [String]
    private let cliSearchDirectories: [String]

    public init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil,
        applicationBundleLookup: ((String) -> URL?)? = nil,
        appSearchDirectories: [String]? = nil,
        cliSearchDirectories: [String]? = nil
    ) {
        let home = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        self.fileManager = fileManager
        self.homeDirectoryURL = home
        self.applicationBundleLookup = applicationBundleLookup ?? { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        self.appSearchDirectories = appSearchDirectories ?? [
            "/Applications",
            home.appendingPathComponent("Applications").path
        ]
        self.cliSearchDirectories = cliSearchDirectories ?? [
            home.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]
    }

    // MARK: - Discovery

    public func detectEditorTarget(for editor: EditorAppKind, customPath: String = "") -> LaunchTarget? {
        if let custom = resolveCustomTarget(customPath) {
            return custom
        }

        for bundleID in editor.bundleIdentifiers {
            if let appURL = applicationBundleLookup(bundleID),
               fileManager.fileExists(atPath: appURL.path)
            {
                return .appBundle(appURL)
            }
        }

        for directory in appSearchDirectories {
            for bundleName in editor.appBundleNames {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(bundleName).path
                if fileManager.fileExists(atPath: candidate) {
                    return .appBundle(URL(fileURLWithPath: candidate))
                }
            }
        }

        for directory in cliSearchDirectories {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(editor.cliCommandName).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return .cliExecutable(URL(fileURLWithPath: candidate))
            }
        }

        return nil
    }

    public func detectKittyTarget(customPath: String = "") -> LaunchTarget? {
        if let custom = resolveCustomTarget(customPath) {
            return custom
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.kovidgoyal.kitty"),
           fileManager.fileExists(atPath: appURL.path)
        {
            return .appBundle(appURL)
        }

        let appCandidates = [
            "/Applications/kitty.app",
            homeDirectoryURL.appendingPathComponent("Applications/kitty.app").path,
            "/Applications/Kitty.app",
            homeDirectoryURL.appendingPathComponent("Applications/Kitty.app").path
        ]
        for path in appCandidates where fileManager.fileExists(atPath: path) {
            return .appBundle(URL(fileURLWithPath: path))
        }

        let cliCandidates = [
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty",
            "/Applications/kitty.app/Contents/MacOS/kitty",
            homeDirectoryURL.appendingPathComponent("Applications/kitty.app/Contents/MacOS/kitty").path
        ]
        for path in cliCandidates where fileManager.isExecutableFile(atPath: path) {
            return .cliExecutable(URL(fileURLWithPath: path))
        }

        return nil
    }

    // MARK: - Actions

    @MainActor
    public func perform(
        action: OpenActionType,
        on project: Project,
        editor: EditorAppKind,
        customEditorPath: String = "",
        customKittyPath: String = "",
        kittyMode: KittyLaunchMode = .newOSWindow,
        kittyRemoteSocket: String = ""
    ) async throws {
        switch action {
        case .editor:
            try await openInEditor(project: project, editor: editor, customPath: customEditorPath)
        case .kitty:
            try await openInKitty(
                project: project,
                customPath: customKittyPath,
                mode: kittyMode,
                remoteSocket: kittyRemoteSocket
            )
        case .both:
            try await openInEditor(project: project, editor: editor, customPath: customEditorPath)
            try await openInKitty(
                project: project,
                customPath: customKittyPath,
                mode: kittyMode,
                remoteSocket: kittyRemoteSocket
            )
        case .revealInFinder:
            revealInFinder(project: project)
        case .copyPath:
            copyPathToPasteboard(project: project)
        }
    }

    @MainActor
    public func openInEditor(
        project: Project,
        editor: EditorAppKind,
        customPath: String = ""
    ) async throws {
        guard let target = detectEditorTarget(for: editor, customPath: customPath) else {
            throw ProjectLaunchError.editorNotFound(editor)
        }

        // Editors that cannot open `.code-workspace` files receive the resolved
        // project directory instead (e.g. Zed).
        let openPath = editor.understandsCodeWorkspaceFiles ? project.path : project.directoryPath
        let openURL = URL(fileURLWithPath: openPath)

        switch target {
        case .appBundle(let appURL):
            try await openURLsWithApp([openURL], applicationURL: appURL)
        case .cliExecutable(let exeURL):
            try runDetachedProcess(executable: exeURL, arguments: [openPath])
        }
    }

    @MainActor
    public func openInKitty(
        project: Project,
        customPath: String = "",
        mode: KittyLaunchMode = .newOSWindow,
        remoteSocket: String = ""
    ) async throws {
        guard let target = detectKittyTarget(customPath: customPath) else {
            throw ProjectLaunchError.kittyNotFound
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: project.directoryPath, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectLaunchError.directoryNotFound(project.directoryPath)
        }

        let dirURL = URL(fileURLWithPath: project.directoryPath)

        switch mode {
        case .newOSWindow:
            try await openKittyNewOSWindow(dirURL: dirURL, target: target)

        case .singleInstanceCLI:
            if let kittyBinary = resolveKittyExecutable(from: target) {
                try runDetachedProcess(
                    executable: kittyBinary,
                    arguments: ["--single-instance", "--directory", project.directoryPath]
                )
                if case .appBundle(let appURL) = target {
                    try? await activateApp(at: appURL)
                }
            } else {
                try await openKittyNewOSWindow(dirURL: dirURL, target: target)
            }

        case .newTab:
            let launchedTab = tryLaunchKittyTabViaRemoteControl(
                directoryPath: project.directoryPath,
                target: target,
                configuredSocket: remoteSocket
            )
            if launchedTab {
                if case .appBundle(let appURL) = target {
                    try? await activateApp(at: appURL)
                }
            } else {
                try await openKittyNewOSWindow(dirURL: dirURL, target: target)
            }
        }
    }

    @MainActor
    public func revealInFinder(project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
    }

    @MainActor
    public func copyPathToPasteboard(project: Project) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.path, forType: .string)
    }

    // MARK: - Internal Helpers

    @MainActor
    private func openKittyNewOSWindow(dirURL: URL, target: LaunchTarget) async throws {
        switch target {
        case .appBundle(let appURL):
            try await openURLsWithApp([dirURL], applicationURL: appURL)
        case .cliExecutable(let exeURL):
            try runDetachedProcess(executable: exeURL, arguments: ["--directory", dirURL.path])
        }
    }

    @MainActor
    private func openURLsWithApp(_ urls: [URL], applicationURL: URL) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: config) { _, error in
                if let error {
                    continuation.resume(throwing: ProjectLaunchError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    @MainActor
    private func activateApp(at applicationURL: URL) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: config) { _, error in
                if let error {
                    continuation.resume(throwing: ProjectLaunchError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func tryLaunchKittyTabViaRemoteControl(
        directoryPath: String,
        target: LaunchTarget,
        configuredSocket: String
    ) -> Bool {
        guard let kittenBinary = resolveKittenExecutable(from: target) ?? resolveKittyExecutable(from: target) else {
            return false
        }

        let isKitten = kittenBinary.lastPathComponent == "kitten"
        var socketCandidates: [String] = []
        let trimmedConfigured = configuredSocket.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedConfigured.isEmpty {
            socketCandidates.append(trimmedConfigured)
        } else {
            socketCandidates.append(contentsOf: discoverKittySocketAddresses())
        }

        // Try each discovered socket (or no --to flag if user set KITTY_LISTEN_ON)
        let toArguments: [[String]] = socketCandidates.isEmpty ? [[]] : socketCandidates.map { ["--to", $0] }

        for toArgs in toArguments {
            var args: [String] = isKitten ? ["@"] : ["@"]
            args.append(contentsOf: toArgs)
            args.append(contentsOf: ["launch", "--type=tab", "--cwd", directoryPath])

            let process = Process()
            process.executableURL = kittenBinary
            process.arguments = args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                let deadline = Date().addingTimeInterval(1.5)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.02)
                }
                if process.isRunning {
                    process.terminate()
                    continue
                }
                if process.terminationStatus == 0 {
                    return true
                }
            } catch {
                continue
            }
        }

        return false
    }

    private func resolveCustomTarget(_ rawPath: String) -> LaunchTarget? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if expanded.hasSuffix(".app"), fileManager.fileExists(atPath: expanded) {
            return .appBundle(url)
        }
        if fileManager.isExecutableFile(atPath: expanded) {
            return .cliExecutable(url)
        }
        return nil
    }

    private func resolveKittyExecutable(from target: LaunchTarget) -> URL? {
        switch target {
        case .cliExecutable(let url):
            return url
        case .appBundle(let appURL):
            let insideApp = appURL.appendingPathComponent("Contents/MacOS/kitty")
            if fileManager.isExecutableFile(atPath: insideApp.path) {
                return insideApp
            }
            for fallback in ["/opt/homebrew/bin/kitty", "/usr/local/bin/kitty"] where fileManager.isExecutableFile(atPath: fallback) {
                return URL(fileURLWithPath: fallback)
            }
            return nil
        }
    }

    private func resolveKittenExecutable(from target: LaunchTarget) -> URL? {
        if case .appBundle(let appURL) = target {
            let insideApp = appURL.appendingPathComponent("Contents/MacOS/kitten")
            if fileManager.isExecutableFile(atPath: insideApp.path) {
                return insideApp
            }
        }
        for fallback in ["/opt/homebrew/bin/kitten", "/usr/local/bin/kitten"] where fileManager.isExecutableFile(atPath: fallback) {
            return URL(fileURLWithPath: fallback)
        }
        return nil
    }

    private func discoverKittySocketAddresses() -> [String] {
        let tmpDir = "/tmp"
        guard let entries = try? fileManager.contentsOfDirectory(atPath: tmpDir) else {
            return []
        }

        var addresses: [String] = []
        for entry in entries where entry.contains("kitty") {
            let fullPath = "\(tmpDir)/\(entry)"
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileType = attrs[.type] as? FileAttributeType,
               fileType == .typeSocket
            {
                addresses.append("unix:\(fullPath)")
            }
        }
        return addresses
    }

    private func runDetachedProcess(executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ProjectLaunchError.launchFailed("Failed to run \(executable.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
