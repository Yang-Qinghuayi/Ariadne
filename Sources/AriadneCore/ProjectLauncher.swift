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
    case vsCodeNotFound
    case kittyNotFound
    case directoryNotFound(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .vsCodeNotFound:
            return "Visual Studio Code was not found. Install VS Code or set its path in Settings."
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

    public init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
    }

    // MARK: - Discovery

    public func detectVSCodeTarget(customPath: String = "") -> LaunchTarget? {
        if let custom = resolveCustomTarget(customPath) {
            return custom
        }

        for bundleID in ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"] {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               fileManager.fileExists(atPath: appURL.path)
            {
                return .appBundle(appURL)
            }
        }

        let appCandidates = [
            "/Applications/Visual Studio Code.app",
            homeDirectoryURL.appendingPathComponent("Applications/Visual Studio Code.app").path,
            "/Applications/Visual Studio Code - Insiders.app",
            homeDirectoryURL.appendingPathComponent("Applications/Visual Studio Code - Insiders.app").path
        ]
        for path in appCandidates where fileManager.fileExists(atPath: path) {
            return .appBundle(URL(fileURLWithPath: path))
        }

        let cliCandidates = [
            "/opt/homebrew/bin/code",
            "/usr/local/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
        ]
        for path in cliCandidates where fileManager.isExecutableFile(atPath: path) {
            return .cliExecutable(URL(fileURLWithPath: path))
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
        customVSCodePath: String = "",
        customKittyPath: String = "",
        kittyMode: KittyLaunchMode = .newOSWindow,
        kittyRemoteSocket: String = ""
    ) async throws {
        switch action {
        case .vscode:
            try await openInVSCode(project: project, customPath: customVSCodePath)
        case .kitty:
            try await openInKitty(
                project: project,
                customPath: customKittyPath,
                mode: kittyMode,
                remoteSocket: kittyRemoteSocket
            )
        case .both:
            try await openInVSCode(project: project, customPath: customVSCodePath)
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
    public func openInVSCode(project: Project, customPath: String = "") async throws {
        guard let target = detectVSCodeTarget(customPath: customPath) else {
            throw ProjectLaunchError.vsCodeNotFound
        }

        let projectURL = URL(fileURLWithPath: project.path)
        switch target {
        case .appBundle(let appURL):
            try await openURLsWithApp([projectURL], applicationURL: appURL)
        case .cliExecutable(let exeURL):
            try runDetachedProcess(executable: exeURL, arguments: [project.path])
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
