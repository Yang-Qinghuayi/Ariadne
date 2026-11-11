import AriadneCore
import Foundation
import SQLite3
import XCTest

final class VSCodeProjectLoaderTests: XCTestCase {
    private var tempRoot: URL!
    private var homeDir: URL!
    private var appSupportDir: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriadneLoaderTests-\(UUID().uuidString)", isDirectory: true)
        homeDir = tempRoot.appendingPathComponent("Home", isDirectory: true)
        appSupportDir = homeDir.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testLoadsFromStateVSCDBAndWorkspaceStorageDeduplicated() throws {
        let projAlpha = homeDir.appendingPathComponent("Projects/alpha app", isDirectory: true)
        let projBeta = homeDir.appendingPathComponent("Projects/项目Beta", isDirectory: true)
        let projGamma = homeDir.appendingPathComponent("Projects/gamma-history", isDirectory: true)
        let projMissing = homeDir.appendingPathComponent("Projects/deleted-proj", isDirectory: true)
        let singleFile = homeDir.appendingPathComponent("Notes/todo.md")
        let workspaceDir = homeDir.appendingPathComponent("Projects/my-ws-target", isDirectory: true)
        let workspaceFile = homeDir.appendingPathComponent("Workspaces/custom.code-workspace")

        for dir in [projAlpha, projBeta, projGamma, workspaceDir, singleFile.deletingLastPathComponent(), workspaceFile.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try "hello".write(to: singleFile, atomically: true, encoding: .utf8)
        try #"{"folders":[{"path":"../Projects/my-ws-target"}]}"#.write(to: workspaceFile, atomically: true, encoding: .utf8)

        let codeUserDir = appSupportDir.appendingPathComponent("Code/User", isDirectory: true)
        let globalStorageDir = codeUserDir.appendingPathComponent("globalStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: globalStorageDir, withIntermediateDirectories: true)

        let entriesPayload: [String: Any] = [
            "entries": [
                ["folderUri": projAlpha.absoluteString],
                ["folderUri": projBeta.absoluteString],
                ["workspace": ["id": "ws1", "configPath": workspaceFile.absoluteString]],
                ["folderUri": projMissing.absoluteString],
                ["fileUri": singleFile.absoluteString],
                ["folderUri": "vscode-remote://ssh-remote+box/srv/remote-app"]
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: entriesPayload)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        let dbURL = globalStorageDir.appendingPathComponent("state.vscdb")
        try createStateVSCDB(at: dbURL, recentlyOpenedJSON: jsonString)

        // Add workspaceStorage entries (one duplicate of alpha, one historical gamma)
        let wsAlphaDir = codeUserDir.appendingPathComponent("workspaceStorage/hash1", isDirectory: true)
        let wsGammaDir = codeUserDir.appendingPathComponent("workspaceStorage/hash2", isDirectory: true)
        try FileManager.default.createDirectory(at: wsAlphaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wsGammaDir, withIntermediateDirectories: true)

        try JSONSerialization.data(withJSONObject: ["folder": projAlpha.absoluteString])
            .write(to: wsAlphaDir.appendingPathComponent("workspace.json"))
        try JSONSerialization.data(withJSONObject: ["folder": projGamma.absoluteString])
            .write(to: wsGammaDir.appendingPathComponent("workspace.json"))

        let loader = VSCodeProjectLoader(appSupportBaseURL: appSupportDir, homeDirectoryURL: homeDir)
        let projects = loader.loadProjects(config: ProjectDiscoveryConfig())

        // Expect: alpha, beta, custom workspace, gamma (missing, single file, and remote excluded)
        XCTAssertEqual(projects.count, 4)
        XCTAssertEqual(projects[0].name, "alpha app")
        XCTAssertEqual(projects[0].path, projAlpha.standardizedFileURL.path)
        XCTAssertEqual(projects[0].directoryPath, projAlpha.standardizedFileURL.path)
        XCTAssertEqual(projects[0].displayPath, "~/Projects/alpha app")

        XCTAssertEqual(projects[1].name, "项目Beta")
        XCTAssertEqual(projects[2].name, "custom")
        XCTAssertEqual(projects[2].kind, .workspace)
        XCTAssertEqual(projects[2].path, workspaceFile.standardizedFileURL.path)
        XCTAssertEqual(projects[2].directoryPath, workspaceDir.standardizedFileURL.path)

        XCTAssertEqual(projects[3].name, "gamma-history")
        XCTAssertEqual(projects[3].source, .vsCodeWorkspaceStorage)
    }

    func testLoadsProjectManagerAndCustomFoldersAndRespectsPins() throws {
        let projPM = homeDir.appendingPathComponent("Code/pm-project", isDirectory: true)
        let projCustom = homeDir.appendingPathComponent("Sandbox/custom-tool", isDirectory: true)
        try FileManager.default.createDirectory(at: projPM, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projCustom, withIntermediateDirectories: true)

        let pmDir = appSupportDir.appendingPathComponent("Code/User/globalStorage/alefragnani.project-manager", isDirectory: true)
        try FileManager.default.createDirectory(at: pmDir, withIntermediateDirectories: true)
        let pmEntries: [[String: Any]] = [
            ["name": "My PM App", "rootPath": "$home/Code/pm-project", "enabled": true],
            ["name": "Disabled App", "rootPath": "$home/Code/disabled", "enabled": false]
        ]
        try JSONSerialization.data(withJSONObject: pmEntries)
            .write(to: pmDir.appendingPathComponent("projects.json"))

        let config = ProjectDiscoveryConfig(
            includeVSCode: true,
            includeVSCodeInsiders: false,
            includeProjectManager: true,
            hideMissingProjects: true,
            customScanDirectories: [homeDir.appendingPathComponent("Sandbox").path],
            pinnedPaths: [projCustom.standardizedFileURL.path]
        )

        let loader = VSCodeProjectLoader(appSupportBaseURL: appSupportDir, homeDirectoryURL: homeDir)
        let projects = loader.loadProjects(config: config)

        XCTAssertEqual(projects.count, 2)
        // Pinned custom-tool comes first
        XCTAssertEqual(projects[0].name, "custom-tool")
        XCTAssertTrue(projects[0].isPinned)
        XCTAssertEqual(projects[1].name, "My PM App")
        XCTAssertEqual(projects[1].source, .projectManager)
    }

    private func createStateVSCDB(at url: URL, recentlyOpenedJSON: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            XCTFail("Failed to create test SQLite DB")
            return
        }
        defer { sqlite3_close(db) }

        let createSQL = "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
        XCTAssertEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)

        let insertSQL = "INSERT INTO ItemTable (key, value) VALUES (?, ?);"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "history.recentlyOpenedPathsList", -1, transient)
        sqlite3_bind_text(stmt, 2, recentlyOpenedJSON, -1, transient)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }
}
