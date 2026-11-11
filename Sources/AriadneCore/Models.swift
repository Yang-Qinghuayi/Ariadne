import Carbon.HIToolbox
import Foundation

public enum ProjectKind: String, Codable, Hashable, Sendable {
    case folder
    case workspace

    public var badgeLabel: String {
        switch self {
        case .folder:
            return "Folder"
        case .workspace:
            return "Workspace"
        }
    }
}

public enum ProjectSource: String, Codable, Hashable, Sendable {
    case vsCodeRecent
    case vsCodeWorkspaceStorage
    case vsCodeInsiders
    case projectManager
    case customFolder

    public var displayName: String {
        switch self {
        case .vsCodeRecent:
            return "VS Code"
        case .vsCodeWorkspaceStorage:
            return "VS Code History"
        case .vsCodeInsiders:
            return "VS Code Insiders"
        case .projectManager:
            return "Project Manager"
        case .customFolder:
            return "Custom Folder"
        }
    }
}

public struct Project: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let directoryPath: String
    public let displayPath: String
    public let kind: ProjectKind
    public let source: ProjectSource
    public let gitBranch: String?
    public let recencyRank: Int
    public let lastModified: Date
    public let lastOpenedByUser: Date?
    public let isPinned: Bool

    public init(
        id: String,
        name: String,
        path: String,
        directoryPath: String,
        displayPath: String,
        kind: ProjectKind,
        source: ProjectSource,
        gitBranch: String? = nil,
        recencyRank: Int = Int.max,
        lastModified: Date = .distantPast,
        lastOpenedByUser: Date? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.directoryPath = directoryPath
        self.displayPath = displayPath
        self.kind = kind
        self.source = source
        self.gitBranch = gitBranch
        self.recencyRank = recencyRank
        self.lastModified = lastModified
        self.lastOpenedByUser = lastOpenedByUser
        self.isPinned = isPinned
    }

    public func with(
        isPinned: Bool? = nil,
        lastOpenedByUser: Date? = nil
    ) -> Project {
        Project(
            id: id,
            name: name,
            path: path,
            directoryPath: directoryPath,
            displayPath: displayPath,
            kind: kind,
            source: source,
            gitBranch: gitBranch,
            recencyRank: recencyRank,
            lastModified: lastModified,
            lastOpenedByUser: lastOpenedByUser ?? self.lastOpenedByUser,
            isPinned: isPinned ?? self.isPinned
        )
    }
}

public enum OpenActionType: String, CaseIterable, Codable, Sendable, Identifiable {
    case vscode
    case kitty
    case both
    case revealInFinder
    case copyPath

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .vscode:
            return "Open in VS Code"
        case .kitty:
            return "Open in Kitty"
        case .both:
            return "Open in VS Code & Kitty"
        case .revealInFinder:
            return "Reveal in Finder"
        case .copyPath:
            return "Copy Project Path"
        }
    }

    public var shortLabel: String {
        switch self {
        case .vscode:
            return "VS Code"
        case .kitty:
            return "Kitty"
        case .both:
            return "Both"
        case .revealInFinder:
            return "Finder"
        case .copyPath:
            return "Copy"
        }
    }
}

public enum DefaultEnterAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case vscode
    case kitty
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .vscode:
            return "Open in VS Code"
        case .kitty:
            return "Open in Kitty"
        case .both:
            return "Open in VS Code & Kitty"
        }
    }

    public var actionType: OpenActionType {
        switch self {
        case .vscode:
            return .vscode
        case .kitty:
            return .kitty
        case .both:
            return .both
        }
    }

    public var commandReturnActionType: OpenActionType {
        switch self {
        case .vscode:
            return .kitty
        case .kitty:
            return .vscode
        case .both:
            return .kitty
        }
    }
}

public enum KittyLaunchMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case newOSWindow
    case newTab
    case singleInstanceCLI

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newOSWindow:
            return "New OS Window (kitty.app)"
        case .newTab:
            return "New Tab (Remote Control)"
        case .singleInstanceCLI:
            return "Single Instance CLI (kitty -1 -d)"
        }
    }

    public var description: String {
        switch self {
        case .newOSWindow:
            return "Opens a new Kitty OS window directly at the project folder without needing remote control."
        case .newTab:
            return "Opens a new tab via Kitty remote control socket if enabled, falling back to a new OS window."
        case .singleInstanceCLI:
            return "Launches via kitty --single-instance --directory."
        }
    }
}

public struct HotKeyDescriptor: Equatable, Codable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public static let defaultLauncher = HotKeyDescriptor(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey)
    )

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public var displayString: String {
        KeyCodeTranslator.format(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    public var displayTokens: [String] {
        KeyCodeTranslator.tokens(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }
}

public struct ProjectDiscoveryConfig: Equatable, Sendable {
    public var includeVSCode: Bool
    public var includeVSCodeInsiders: Bool
    public var includeProjectManager: Bool
    public var hideMissingProjects: Bool
    public var customScanDirectories: [String]
    public var pinnedPaths: Set<String>
    public var lastOpenedTimestamps: [String: Date]

    public init(
        includeVSCode: Bool = true,
        includeVSCodeInsiders: Bool = false,
        includeProjectManager: Bool = true,
        hideMissingProjects: Bool = true,
        customScanDirectories: [String] = [],
        pinnedPaths: Set<String> = [],
        lastOpenedTimestamps: [String: Date] = [:]
    ) {
        self.includeVSCode = includeVSCode
        self.includeVSCodeInsiders = includeVSCodeInsiders
        self.includeProjectManager = includeProjectManager
        self.hideMissingProjects = hideMissingProjects
        self.customScanDirectories = customScanDirectories
        self.pinnedPaths = pinnedPaths
        self.lastOpenedTimestamps = lastOpenedTimestamps
    }
}
