import AriadneCore
import XCTest

final class FuzzyMatcherTests: XCTestCase {
    private let sampleProjects: [Project] = [
        Project(
            id: "/Users/dev/Projects/my-cool-app",
            name: "my-cool-app",
            path: "/Users/dev/Projects/my-cool-app",
            directoryPath: "/Users/dev/Projects/my-cool-app",
            displayPath: "~/Projects/my-cool-app",
            kind: .folder,
            source: .vsCodeRecent,
            recencyRank: 0
        ),
        Project(
            id: "/Users/dev/Projects/ariadne",
            name: "Ariadne",
            path: "/Users/dev/Projects/ariadne",
            directoryPath: "/Users/dev/Projects/ariadne",
            displayPath: "~/Projects/ariadne",
            kind: .folder,
            source: .vsCodeRecent,
            recencyRank: 1
        ),
        Project(
            id: "/Users/dev/Work/swift-api-server",
            name: "swift-api-server",
            path: "/Users/dev/Work/swift-api-server",
            directoryPath: "/Users/dev/Work/swift-api-server",
            displayPath: "~/Work/swift-api-server",
            kind: .folder,
            source: .vsCodeRecent,
            recencyRank: 2
        )
    ]

    func testEmptyQueryPreservesInputOrder() {
        let results = FuzzyMatcher.filterAndSort(projects: sampleProjects, query: "   ")
        XCTAssertEqual(results.map(\.project.name), ["my-cool-app", "Ariadne", "swift-api-server"])
        XCTAssertTrue(results.allSatisfy { $0.matchedNameIndices.isEmpty })
    }

    func testWordBoundaryAndPrefixMatching() {
        let results = FuzzyMatcher.filterAndSort(projects: sampleProjects, query: "mca")
        XCTAssertEqual(results.first?.project.name, "my-cool-app")
        XCTAssertEqual(results.first?.matchedNameIndices, Set([0, 3, 8]))

        let prefix = FuzzyMatcher.filterAndSort(projects: sampleProjects, query: "ari")
        XCTAssertEqual(prefix.first?.project.name, "Ariadne")
        XCTAssertEqual(prefix.first?.matchedNameIndices, Set([0, 1, 2]))
    }

    func testMultiTermMatchesAcrossPathAndName() {
        let results = FuzzyMatcher.filterAndSort(projects: sampleProjects, query: "work api")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.project.name, "swift-api-server")
    }
}
