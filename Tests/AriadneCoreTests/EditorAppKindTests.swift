import AppKit
import AriadneCore
import XCTest

final class EditorAppKindTests: XCTestCase {
    func testDisplayNamesAndCLICommands() {
        XCTAssertEqual(EditorAppKind.zed.displayName, "Zed")
        XCTAssertEqual(EditorAppKind.cursor.displayName, "Cursor")
        XCTAssertEqual(EditorAppKind.vscode.displayName, "Visual Studio Code")
        XCTAssertEqual(EditorAppKind.windsurf.displayName, "Windsurf")

        XCTAssertEqual(EditorAppKind.zed.cliCommandName, "zed")
        XCTAssertEqual(EditorAppKind.cursor.cliCommandName, "cursor")
        XCTAssertEqual(EditorAppKind.vscode.cliCommandName, "code")
        XCTAssertEqual(EditorAppKind.windsurf.cliCommandName, "windsurf")

        XCTAssertFalse(EditorAppKind.zed.understandsCodeWorkspaceFiles)
        XCTAssertTrue(EditorAppKind.vscode.understandsCodeWorkspaceFiles)
    }

    func testMissingInstallHintMentionsCommand() {
        XCTAssertTrue(EditorAppKind.zed.missingInstallHint.contains("Install Zed"))
        XCTAssertTrue(EditorAppKind.zed.missingInstallHint.contains("`zed`"))
    }

    func testCodableRoundTrip() throws {
        for kind in EditorAppKind.allCases {
            let encoded = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(EditorAppKind.self, from: encoded)
            XCTAssertEqual(decoded, kind)
        }
    }

    func testDefaultEnterActionLegacyRawValueMapping() {
        XCTAssertEqual(DefaultEnterAction(legacyRawValue: "vscode"), DefaultEnterAction.editor)
        XCTAssertEqual(DefaultEnterAction(legacyRawValue: "editor"), DefaultEnterAction.editor)
        XCTAssertEqual(DefaultEnterAction(legacyRawValue: "kitty"), DefaultEnterAction.kitty)
        XCTAssertEqual(DefaultEnterAction(legacyRawValue: "both"), DefaultEnterAction.both)
        XCTAssertNil(DefaultEnterAction(legacyRawValue: "bogus"))
    }

    func testOpenActionTitlesAreEditorAware() {
        XCTAssertEqual(OpenActionType.editor.title(for: .zed), "Open in Zed")
        XCTAssertEqual(OpenActionType.editor.title(for: .vscode), "Open in Visual Studio Code")
        XCTAssertEqual(OpenActionType.both.title(for: .cursor), "Open in Cursor & Kitty")
        XCTAssertEqual(OpenActionType.editor.shortLabel(for: .windsurf), "Windsurf")
        XCTAssertEqual(DefaultEnterAction.editor.title(for: .zed), "Open in Zed")
    }

    @MainActor
    func testSettingsDefaultsToZedAndPersists() {
        let suiteName = "AriadneEditorSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.editorApp, .zed)
        XCTAssertEqual(store.defaultEnterAction, .editor)
        XCTAssertEqual(store.customEditorPath(for: .zed), "")

        store.editorApp = .cursor
        store.setCustomEditorPath("/Applications/Cursor.app", for: .cursor)
        store.defaultEnterAction = .both

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.editorApp, .cursor)
        XCTAssertEqual(reloaded.customEditorPath(for: .cursor), "/Applications/Cursor.app")
        XCTAssertEqual(reloaded.defaultEnterAction, .both)
    }

    @MainActor
    func testLegacySettingsMigrateGracefully() {
        let suiteName = "AriadneLegacySettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Values persisted by earlier releases.
        defaults.set("vscode", forKey: "ariadne.defaultEnterAction")
        defaults.set("/Applications/Visual Studio Code.app", forKey: "ariadne.customVSCodePath")

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.defaultEnterAction, .editor)
        XCTAssertEqual(store.editorApp, .zed)
        XCTAssertEqual(store.customEditorPath(for: .vscode), "/Applications/Visual Studio Code.app")
    }

    // MARK: - ProjectLauncher Detection

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriadneEditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testDetectsAppBundleInSearchDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fakeApp = dir.appendingPathComponent("Zed.app")
        try FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)

        let launcher = ProjectLauncher(
            homeDirectoryURL: dir,
            applicationBundleLookup: { _ in nil },
            appSearchDirectories: [dir.path],
            cliSearchDirectories: []
        )

        XCTAssertEqual(launcher.detectEditorTarget(for: .zed)?.url.path, fakeApp.path)
    }

    func testDetectsCLIExecutableInSearchDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let cli = dir.appendingPathComponent("cursor")
        try Data().write(to: cli)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: cli.path
        )

        let launcher = ProjectLauncher(
            homeDirectoryURL: dir,
            applicationBundleLookup: { _ in nil },
            appSearchDirectories: [dir.path],
            cliSearchDirectories: [dir.path]
        )

        XCTAssertEqual(launcher.detectEditorTarget(for: .cursor)?.url.path, cli.path)
    }

    func testReturnsNilWhenEditorIsNotInstalled() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let launcher = ProjectLauncher(
            homeDirectoryURL: dir,
            applicationBundleLookup: { _ in nil },
            appSearchDirectories: [dir.path],
            cliSearchDirectories: [dir.path]
        )

        XCTAssertNil(launcher.detectEditorTarget(for: .windsurf))
    }

    func testCustomPathOverridesDetection() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let customApp = dir.appendingPathComponent("My Fancy Editor.app")
        try FileManager.default.createDirectory(at: customApp, withIntermediateDirectories: true)

        let launcher = ProjectLauncher(
            homeDirectoryURL: dir,
            applicationBundleLookup: { _ in nil },
            appSearchDirectories: [],
            cliSearchDirectories: []
        )

        XCTAssertNil(launcher.detectEditorTarget(for: .vscode))
        XCTAssertEqual(
            launcher.detectEditorTarget(for: .vscode, customPath: customApp.path)?.url.path,
            customApp.path
        )
    }
}
