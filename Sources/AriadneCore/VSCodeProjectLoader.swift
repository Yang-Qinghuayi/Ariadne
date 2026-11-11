import Foundation
import SQLite3

public final class VSCodeProjectLoader {
    private let fileManager: FileManager
    private let appSupportBaseURL: URL
    private let homeDirectoryURL: URL

    public init(
        fileManager: FileManager = .default,
        appSupportBaseURL: URL? = nil,
        homeDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let resolvedHome = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        self.homeDirectoryURL = resolvedHome
        if let appSupportBaseURL {
            self.appSupportBaseURL = appSupportBaseURL
        } else {
            self.appSupportBaseURL = fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? resolvedHome.appendingPathComponent("Library/Application Support")
        }
    }

    public func loadProjects(config: ProjectDiscoveryConfig = ProjectDiscoveryConfig()) -> [Project] {
        var candidatesByPath: [String: CandidateProject] = [:]
        var latestStateDBModification: Date = .distantPast

        if config.includeVSCode {
            let codeRoot = appSupportBaseURL.appendingPathComponent("Code", isDirectory: true)
            if let dbDate = modificationDate(of: codeRoot.appendingPathComponent("User/globalStorage/state.vscdb")),
               dbDate > latestStateDBModification {
                latestStateDBModification = dbDate
            }
            collectFromVSCodeDirectory(
                codeRoot,
                recentSource: .vsCodeRecent,
                storageSource: .vsCodeWorkspaceStorage,
                into: &candidatesByPath
            )
        }

        if config.includeVSCodeInsiders {
            let insidersRoot = appSupportBaseURL.appendingPathComponent("Code - Insiders", isDirectory: true)
            if let dbDate = modificationDate(of: insidersRoot.appendingPathComponent("User/globalStorage/state.vscdb")),
               dbDate > latestStateDBModification {
                latestStateDBModification = dbDate
            }
            collectFromVSCodeDirectory(
                insidersRoot,
                recentSource: .vsCodeInsiders,
                storageSource: .vsCodeInsiders,
                into: &candidatesByPath
            )
        }

        if config.includeProjectManager {
            if config.includeVSCode {
                let pmFile = appSupportBaseURL.appendingPathComponent(
                    "Code/User/globalStorage/alefragnani.project-manager/projects.json"
                )
                collectFromProjectManager(pmFile, into: &candidatesByPath)
            }
            if config.includeVSCodeInsiders {
                let pmFile = appSupportBaseURL.appendingPathComponent(
                    "Code - Insiders/User/globalStorage/alefragnani.project-manager/projects.json"
                )
                collectFromProjectManager(pmFile, into: &candidatesByPath)
            }
        }

        for dir in config.customScanDirectories {
            collectFromCustomDirectory(dir, into: &candidatesByPath)
        }

        var projects: [Project] = []
        projects.reserveCapacity(candidatesByPath.count)

        for (normalizedPath, candidate) in candidatesByPath {
            if config.hideMissingProjects {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDir) else {
                    continue
                }
                if candidate.kind == .folder && !isDir.boolValue {
                    continue
                }
                if candidate.kind == .workspace && isDir.boolValue {
                    continue
                }
            }

            let directoryPath: String
            switch candidate.kind {
            case .folder:
                directoryPath = normalizedPath
            case .workspace:
                directoryPath = WorkspaceDirectoryResolver.resolveDirectory(
                    forWorkspaceFile: normalizedPath,
                    fileManager: fileManager
                )
            }

            let displayName = candidate.preferredName ?? defaultProjectName(for: normalizedPath, kind: candidate.kind)
            let displayPath = abbreviatePath(normalizedPath)
            let gitBranch = WorkspaceDirectoryResolver.readGitBranch(in: directoryPath, fileManager: fileManager)
            let isPinned = config.pinnedPaths.contains(normalizedPath)
            let lastOpenedByUser = config.lastOpenedTimestamps[normalizedPath]

            let project = Project(
                id: normalizedPath,
                name: displayName,
                path: normalizedPath,
                directoryPath: directoryPath,
                displayPath: displayPath,
                kind: candidate.kind,
                source: candidate.source,
                gitBranch: gitBranch,
                recencyRank: candidate.recencyRank,
                lastModified: candidate.lastModified,
                lastOpenedByUser: lastOpenedByUser,
                isPinned: isPinned
            )
            projects.append(project)
        }

        return sortProjects(projects, stateDBModifiedAt: latestStateDBModification)
    }

    // MARK: - VS Code Collection

    private func collectFromVSCodeDirectory(
        _ root: URL,
        recentSource: ProjectSource,
        storageSource: ProjectSource,
        into map: inout [String: CandidateProject]
    ) {
        let userDir = root.appendingPathComponent("User", isDirectory: true)

        // 1. state.vscdb (history.recentlyOpenedPathsList)
        let stateDB = userDir.appendingPathComponent("globalStorage/state.vscdb")
        if fileManager.fileExists(atPath: stateDB.path) {
            let dbMtime = modificationDate(of: stateDB) ?? .distantPast
            let recentEntries = readRecentlyOpenedFromSQLite(at: stateDB)
            for (index, entry) in recentEntries.enumerated() {
                mergeCandidate(
                    path: entry.path,
                    kind: entry.kind,
                    source: recentSource,
                    preferredName: entry.label,
                    recencyRank: index,
                    lastModified: dbMtime,
                    into: &map
                )
            }
        }

        // 2. Legacy storage.json fallback
        let legacyStorage = root.appendingPathComponent("storage.json")
        if fileManager.fileExists(atPath: legacyStorage.path),
           let data = try? Data(contentsOf: legacyStorage),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let openedList = json["openedPathsList"] as? [String: Any]
        {
            let mtime = modificationDate(of: legacyStorage) ?? .distantPast
            if let entries = openedList["entries"] as? [[String: Any]] {
                for (index, entry) in entries.enumerated() {
                    if let parsed = parseRecentlyOpenedEntry(entry) {
                        mergeCandidate(
                            path: parsed.path,
                            kind: parsed.kind,
                            source: recentSource,
                            preferredName: parsed.label,
                            recencyRank: 1000 + index,
                            lastModified: mtime,
                            into: &map
                        )
                    }
                }
            } else if let workspaces = openedList["workspaces3"] as? [String] {
                for (index, uri) in workspaces.enumerated() {
                    if let resolved = resolveFileURI(uri) {
                        let kind: ProjectKind = resolved.hasSuffix(".code-workspace") ? .workspace : .folder
                        mergeCandidate(
                            path: resolved,
                            kind: kind,
                            source: recentSource,
                            preferredName: nil,
                            recencyRank: 1000 + index,
                            lastModified: mtime,
                            into: &map
                        )
                    }
                }
            }
        }

        // 3. workspaceStorage/*/workspace.json (captures all historical projects)
        let workspaceStorageDir = userDir.appendingPathComponent("workspaceStorage", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(
            at: workspaceStorageDir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                let workspaceJSON = child.appendingPathComponent("workspace.json")
                guard fileManager.fileExists(atPath: workspaceJSON.path),
                      let data = try? Data(contentsOf: workspaceJSON),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }

                let mtime = modificationDate(of: workspaceJSON) ?? modificationDate(of: child) ?? .distantPast
                if let folderURI = json["folder"] as? String,
                   let path = resolveFileURI(folderURI)
                {
                    mergeCandidate(
                        path: path,
                        kind: .folder,
                        source: storageSource,
                        preferredName: nil,
                        recencyRank: Int.max,
                        lastModified: mtime,
                        into: &map
                    )
                } else if let workspaceURI = json["workspace"] as? String,
                          let path = resolveFileURI(workspaceURI)
                {
                    let kind: ProjectKind = path.hasSuffix(".code-workspace") ? .workspace : .folder
                    mergeCandidate(
                        path: path,
                        kind: kind,
                        source: storageSource,
                        preferredName: nil,
                        recencyRank: Int.max,
                        lastModified: mtime,
                        into: &map
                    )
                }
            }
        }
    }

    // MARK: - SQLite Reader

    private func readRecentlyOpenedFromSQLite(at dbURL: URL) -> [ParsedEntry] {
        if let direct = queryRecentlyOpened(sqlitePath: dbURL.path) {
            return direct
        }

        // Fallback: copy state.vscdb (+ WAL/SHM) to temp directory if VS Code holds a lock
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("ariadne-vscdb-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: tempDir) }

            let tempDB = tempDir.appendingPathComponent("state.vscdb")
            try fileManager.copyItem(at: dbURL, to: tempDB)

            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: dbURL.path + suffix)
                if fileManager.fileExists(atPath: sidecar.path) {
                    let tempSidecar = URL(fileURLWithPath: tempDB.path + suffix)
                    try? fileManager.copyItem(at: sidecar, to: tempSidecar)
                }
            }

            return queryRecentlyOpened(sqlitePath: tempDB.path) ?? []
        } catch {
            return []
        }
    }

    private func queryRecentlyOpened(sqlitePath: String) -> [ParsedEntry]? {
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(sqlitePath, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 300)

        let query = "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList' LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        let stepResult = sqlite3_step(stmt)
        if stepResult == SQLITE_ROW {
            guard let cText = sqlite3_column_text(stmt, 0) else {
                return []
            }
            let jsonString = String(cString: cText)
            return parseRecentlyOpenedJSON(jsonString)
        } else if stepResult == SQLITE_DONE {
            return []
        } else {
            return nil
        }
    }

    private func parseRecentlyOpenedJSON(_ jsonString: String) -> [ParsedEntry] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]]
        else {
            return []
        }

        return entries.compactMap(parseRecentlyOpenedEntry(_:))
    }

    private func parseRecentlyOpenedEntry(_ entry: [String: Any]) -> ParsedEntry? {
        let rawLabel = entry["label"] as? String
        let cleanLabel = (rawLabel?.isEmpty == false) ? rawLabel : nil

        if let folderURI = entry["folderUri"] as? String {
            guard let path = resolveFileURI(folderURI) else { return nil }
            return ParsedEntry(path: path, kind: .folder, label: cleanLabel)
        }

        if let workspaceObj = entry["workspace"] as? [String: Any],
           let configURI = workspaceObj["configPath"] as? String
        {
            guard let path = resolveFileURI(configURI) else { return nil }
            let kind: ProjectKind = path.hasSuffix(".code-workspace") ? .workspace : .folder
            return ParsedEntry(path: path, kind: kind, label: cleanLabel)
        }

        // Intentionally ignore single file entries ("fileUri")
        return nil
    }

    // MARK: - Project Manager & Custom Directories

    private func collectFromProjectManager(_ fileURL: URL, into map: inout [String: CandidateProject]) {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return
        }

        let mtime = modificationDate(of: fileURL) ?? .distantPast
        for item in items {
            if let enabled = item["enabled"] as? Bool, !enabled {
                continue
            }
            let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferredName = (name?.isEmpty == false) ? name : nil

            if let rootPath = item["rootPath"] as? String, !rootPath.isEmpty {
                let resolved = expandHomeTokens(rootPath)
                let kind: ProjectKind = resolved.hasSuffix(".code-workspace") ? .workspace : .folder
                mergeCandidate(
                    path: resolved,
                    kind: kind,
                    source: .projectManager,
                    preferredName: preferredName,
                    recencyRank: Int.max,
                    lastModified: mtime,
                    into: &map
                )
            } else if let paths = item["paths"] as? [String], let firstPath = paths.first, !firstPath.isEmpty {
                let resolved = expandHomeTokens(firstPath)
                let kind: ProjectKind = resolved.hasSuffix(".code-workspace") ? .workspace : .folder
                mergeCandidate(
                    path: resolved,
                    kind: kind,
                    source: .projectManager,
                    preferredName: preferredName,
                    recencyRank: Int.max,
                    lastModified: mtime,
                    into: &map
                )
            }
        }
    }

    private func collectFromCustomDirectory(_ rawDirPath: String, into map: inout [String: CandidateProject]) {
        let expanded = expandHomeTokens(rawDirPath)
        let dirURL = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children {
            var childIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDir) else { continue }
            if childIsDir.boolValue {
                if child.lastPathComponent == "node_modules" || child.lastPathComponent == "build" {
                    continue
                }
                let mtime = modificationDate(of: child) ?? .distantPast
                mergeCandidate(
                    path: child.standardizedFileURL.path,
                    kind: .folder,
                    source: .customFolder,
                    preferredName: nil,
                    recencyRank: Int.max,
                    lastModified: mtime,
                    into: &map
                )
            } else if child.pathExtension == "code-workspace" {
                let mtime = modificationDate(of: child) ?? .distantPast
                mergeCandidate(
                    path: child.standardizedFileURL.path,
                    kind: .workspace,
                    source: .customFolder,
                    preferredName: nil,
                    recencyRank: Int.max,
                    lastModified: mtime,
                    into: &map
                )
            }
        }
    }

    // MARK: - Helpers

    private func mergeCandidate(
        path: String,
        kind: ProjectKind,
        source: ProjectSource,
        preferredName: String?,
        recencyRank: Int,
        lastModified: Date,
        into map: inout [String: CandidateProject]
    ) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if var existing = map[normalized] {
            if recencyRank < existing.recencyRank {
                existing.recencyRank = recencyRank
                existing.source = source
            }
            if lastModified > existing.lastModified {
                existing.lastModified = lastModified
            }
            if existing.preferredName == nil, let preferredName {
                existing.preferredName = preferredName
            }
            map[normalized] = existing
        } else {
            map[normalized] = CandidateProject(
                path: normalized,
                kind: kind,
                source: source,
                preferredName: preferredName,
                recencyRank: recencyRank,
                lastModified: lastModified
            )
        }
    }

    private func sortProjects(_ projects: [Project], stateDBModifiedAt: Date) -> [Project] {
        projects.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            let lhsUserOpenedAfterDB = (lhs.lastOpenedByUser ?? .distantPast) > stateDBModifiedAt
            let rhsUserOpenedAfterDB = (rhs.lastOpenedByUser ?? .distantPast) > stateDBModifiedAt
            if lhsUserOpenedAfterDB != rhsUserOpenedAfterDB {
                return lhsUserOpenedAfterDB
            }
            if lhsUserOpenedAfterDB && rhsUserOpenedAfterDB,
               let lDate = lhs.lastOpenedByUser,
               let rDate = rhs.lastOpenedByUser,
               lDate != rDate
            {
                return lDate > rDate
            }

            if lhs.recencyRank != rhs.recencyRank {
                return lhs.recencyRank < rhs.recencyRank
            }

            if let lDate = lhs.lastOpenedByUser, let rDate = rhs.lastOpenedByUser, lDate != rDate {
                return lDate > rDate
            } else if (lhs.lastOpenedByUser != nil) != (rhs.lastOpenedByUser != nil) {
                return lhs.lastOpenedByUser != nil
            }

            if lhs.lastModified != rhs.lastModified {
                return lhs.lastModified > rhs.lastModified
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func resolveFileURI(_ uriString: String) -> String? {
        guard uriString.hasPrefix("file://") else {
            return nil
        }
        if let url = URL(string: uriString), url.isFileURL {
            return url.standardizedFileURL.path
        }
        let stripped = String(uriString.dropFirst("file://".count))
        let decoded = stripped.removingPercentEncoding ?? stripped
        guard decoded.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: decoded).standardizedFileURL.path
    }

    private func expandHomeTokens(_ rawPath: String) -> String {
        let home = homeDirectoryURL.path
        var expanded = rawPath
        if expanded == "$home" {
            expanded = home
        } else if expanded.hasPrefix("$home/") {
            expanded = home + String(expanded.dropFirst("$home".count))
        } else if expanded == "~" {
            expanded = home
        } else if expanded.hasPrefix("~/") {
            expanded = home + String(expanded.dropFirst(1))
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = homeDirectoryURL.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private func defaultProjectName(for path: String, kind: ProjectKind) -> String {
        let url = URL(fileURLWithPath: path)
        if kind == .workspace && url.pathExtension == "code-workspace" {
            let base = url.deletingPathExtension().lastPathComponent
            if !base.isEmpty {
                return base
            }
        }
        let last = url.lastPathComponent
        return last.isEmpty ? path : last
    }

    private func modificationDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private struct ParsedEntry {
        let path: String
        let kind: ProjectKind
        let label: String?
    }

    private struct CandidateProject {
        let path: String
        let kind: ProjectKind
        var source: ProjectSource
        var preferredName: String?
        var recencyRank: Int
        var lastModified: Date
    }
}
