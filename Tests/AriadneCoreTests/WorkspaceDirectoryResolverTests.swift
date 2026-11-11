import AriadneCore
import Foundation
import XCTest

final class WorkspaceDirectoryResolverTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriadneResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testResolvesSingleFolderJSONCWorkspace() throws {
        let workspacesDir = tempDir.appendingPathComponent("workspaces", isDirectory: true)
        let targetRepo = tempDir.appendingPathComponent("repos/swift-service", isDirectory: true)
        try FileManager.default.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetRepo, withIntermediateDirectories: true)

        let wsFile = workspacesDir.appendingPathComponent("swift-service.code-workspace")
        let jsonc = """
        {
            // Single folder workspace with comments and trailing commas
            "folders": [
                {
                    "path": "../repos/swift-service",
                },
            ],
            /* Ignore URL-like comment inside string */
            "settings": {
                "remoteUrl": "https://example.com//keep-slashes"
            },
        }
        """
        try jsonc.write(to: wsFile, atomically: true, encoding: .utf8)

        let resolved = WorkspaceDirectoryResolver.resolveDirectory(forWorkspaceFile: wsFile.path)
        XCTAssertEqual(resolved, targetRepo.standardizedFileURL.path)
    }

    func testResolvesMultiRootWorkspaceToParentDirectory() throws {
        let monorepo = tempDir.appendingPathComponent("monorepo", isDirectory: true)
        let frontend = monorepo.appendingPathComponent("frontend", isDirectory: true)
        let backend = monorepo.appendingPathComponent("backend", isDirectory: true)
        try FileManager.default.createDirectory(at: frontend, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backend, withIntermediateDirectories: true)

        let wsFile = monorepo.appendingPathComponent("monorepo.code-workspace")
        let content = """
        {
            "folders": [
                { "path": "frontend" },
                { "path": "backend" }
            ]
        }
        """
        try content.write(to: wsFile, atomically: true, encoding: .utf8)

        let resolved = WorkspaceDirectoryResolver.resolveDirectory(forWorkspaceFile: wsFile.path)
        XCTAssertEqual(resolved, monorepo.standardizedFileURL.path)
    }

    func testReadsGitBranchAndWorktreeGitFile() throws {
        let repo = tempDir.appendingPathComponent("repo", isDirectory: true)
        let gitDir = repo.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/feat/kitty-launcher\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(WorkspaceDirectoryResolver.readGitBranch(in: repo.path), "feat/kitty-launcher")

        // Detached HEAD
        try "1234567890abcdef1234567890abcdef12345678\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(WorkspaceDirectoryResolver.readGitBranch(in: repo.path), "1234567")

        // Git worktree file
        let worktree = tempDir.appendingPathComponent("wt", isDirectory: true)
        let externalGit = tempDir.appendingPathComponent("external-git", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalGit, withIntermediateDirectories: true)
        try "gitdir: ../external-git\n".write(
            to: worktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try "ref: refs/heads/main\n".write(
            to: externalGit.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertEqual(WorkspaceDirectoryResolver.readGitBranch(in: worktree.path), "main")
    }
}
