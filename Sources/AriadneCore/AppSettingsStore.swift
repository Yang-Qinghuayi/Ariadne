import Combine
import Foundation

@MainActor
public final class AppSettingsStore: ObservableObject {
    private enum Keys {
        static let hotKey = "ariadne.hotKey"
        static let defaultEnterAction = "ariadne.defaultEnterAction"
        static let kittyLaunchMode = "ariadne.kittyLaunchMode"
        static let includeVSCode = "ariadne.includeVSCode"
        static let includeVSCodeInsiders = "ariadne.includeVSCodeInsiders"
        static let includeProjectManager = "ariadne.includeProjectManager"
        static let hideMissingProjects = "ariadne.hideMissingProjects"
        static let customScanDirectories = "ariadne.customScanDirectories"
        static let customVSCodePath = "ariadne.customVSCodePath"
        static let customKittyPath = "ariadne.customKittyPath"
        static let kittyRemoteSocket = "ariadne.kittyRemoteSocket"
        static let pinnedPaths = "ariadne.pinnedPaths"
        static let lastOpenedTimestamps = "ariadne.lastOpenedTimestamps"
        static let hasLaunchedBefore = "ariadne.hasLaunchedBefore"
    }

    private let defaults: UserDefaults

    @Published public var hotKey: HotKeyDescriptor {
        didSet { saveCodable(hotKey, key: Keys.hotKey) }
    }

    @Published public var defaultEnterAction: DefaultEnterAction {
        didSet { defaults.set(defaultEnterAction.rawValue, forKey: Keys.defaultEnterAction) }
    }

    @Published public var kittyLaunchMode: KittyLaunchMode {
        didSet { defaults.set(kittyLaunchMode.rawValue, forKey: Keys.kittyLaunchMode) }
    }

    @Published public var includeVSCode: Bool {
        didSet { defaults.set(includeVSCode, forKey: Keys.includeVSCode) }
    }

    @Published public var includeVSCodeInsiders: Bool {
        didSet { defaults.set(includeVSCodeInsiders, forKey: Keys.includeVSCodeInsiders) }
    }

    @Published public var includeProjectManager: Bool {
        didSet { defaults.set(includeProjectManager, forKey: Keys.includeProjectManager) }
    }

    @Published public var hideMissingProjects: Bool {
        didSet { defaults.set(hideMissingProjects, forKey: Keys.hideMissingProjects) }
    }

    @Published public var customScanDirectories: [String] {
        didSet { defaults.set(customScanDirectories, forKey: Keys.customScanDirectories) }
    }

    @Published public var customVSCodePath: String {
        didSet { defaults.set(customVSCodePath, forKey: Keys.customVSCodePath) }
    }

    @Published public var customKittyPath: String {
        didSet { defaults.set(customKittyPath, forKey: Keys.customKittyPath) }
    }

    @Published public var kittyRemoteSocket: String {
        didSet { defaults.set(kittyRemoteSocket, forKey: Keys.kittyRemoteSocket) }
    }

    @Published public var pinnedPaths: Set<String> {
        didSet { defaults.set(Array(pinnedPaths), forKey: Keys.pinnedPaths) }
    }

    @Published public var lastOpenedTimestamps: [String: Date] {
        didSet { saveCodable(lastOpenedTimestamps, key: Keys.lastOpenedTimestamps) }
    }

    @Published public var hasLaunchedBefore: Bool {
        didSet { defaults.set(hasLaunchedBefore, forKey: Keys.hasLaunchedBefore) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.hotKey),
           let decoded = try? JSONDecoder().decode(HotKeyDescriptor.self, from: data)
        {
            self.hotKey = decoded
        } else {
            self.hotKey = .defaultLauncher
        }

        if let rawAction = defaults.string(forKey: Keys.defaultEnterAction),
           let action = DefaultEnterAction(rawValue: rawAction)
        {
            self.defaultEnterAction = action
        } else {
            self.defaultEnterAction = .vscode
        }

        if let rawKittyMode = defaults.string(forKey: Keys.kittyLaunchMode),
           let mode = KittyLaunchMode(rawValue: rawKittyMode)
        {
            self.kittyLaunchMode = mode
        } else {
            self.kittyLaunchMode = .newOSWindow
        }

        self.includeVSCode = defaults.object(forKey: Keys.includeVSCode) as? Bool ?? true
        self.includeVSCodeInsiders = defaults.object(forKey: Keys.includeVSCodeInsiders) as? Bool ?? false
        self.includeProjectManager = defaults.object(forKey: Keys.includeProjectManager) as? Bool ?? true
        self.hideMissingProjects = defaults.object(forKey: Keys.hideMissingProjects) as? Bool ?? true
        self.customScanDirectories = defaults.stringArray(forKey: Keys.customScanDirectories) ?? []
        self.customVSCodePath = defaults.string(forKey: Keys.customVSCodePath) ?? ""
        self.customKittyPath = defaults.string(forKey: Keys.customKittyPath) ?? ""
        self.kittyRemoteSocket = defaults.string(forKey: Keys.kittyRemoteSocket) ?? ""
        self.pinnedPaths = Set(defaults.stringArray(forKey: Keys.pinnedPaths) ?? [])

        if let data = defaults.data(forKey: Keys.lastOpenedTimestamps),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        {
            self.lastOpenedTimestamps = decoded
        } else {
            self.lastOpenedTimestamps = [:]
        }

        self.hasLaunchedBefore = defaults.bool(forKey: Keys.hasLaunchedBefore)
    }

    public var discoveryConfig: ProjectDiscoveryConfig {
        ProjectDiscoveryConfig(
            includeVSCode: includeVSCode,
            includeVSCodeInsiders: includeVSCodeInsiders,
            includeProjectManager: includeProjectManager,
            hideMissingProjects: hideMissingProjects,
            customScanDirectories: customScanDirectories,
            pinnedPaths: pinnedPaths,
            lastOpenedTimestamps: lastOpenedTimestamps
        )
    }

    public func togglePin(for projectPath: String) {
        if pinnedPaths.contains(projectPath) {
            pinnedPaths.remove(projectPath)
        } else {
            pinnedPaths.insert(projectPath)
        }
    }

    public func recordOpened(projectPath: String, at date: Date = Date()) {
        var updated = lastOpenedTimestamps
        updated[projectPath] = date
        // Keep history bounded to latest 300 entries
        if updated.count > 300 {
            let trimmed = updated.sorted { $0.value > $1.value }.prefix(300)
            updated = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
        lastOpenedTimestamps = updated
    }

    public func resetHotKeyToDefault() {
        hotKey = .defaultLauncher
    }

    private func saveCodable<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
