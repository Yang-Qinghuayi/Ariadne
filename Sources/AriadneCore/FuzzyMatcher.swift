import Foundation

public struct ScoredProject: Identifiable, Hashable, Sendable {
    public let project: Project
    public let score: Int
    public let matchedNameIndices: Set<Int>

    public var id: String { project.id }

    public init(project: Project, score: Int, matchedNameIndices: Set<Int>) {
        self.project = project
        self.score = score
        self.matchedNameIndices = matchedNameIndices
    }
}

public enum FuzzyMatcher {
    public static func filterAndSort(projects: [Project], query: String) -> [ScoredProject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return projects.map { ScoredProject(project: $0, score: 0, matchedNameIndices: []) }
        }

        let terms = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
        guard !terms.isEmpty else {
            return projects.map { ScoredProject(project: $0, score: 0, matchedNameIndices: []) }
        }

        var results: [ScoredProject] = []
        results.reserveCapacity(projects.count)

        for (index, project) in projects.enumerated() {
            var totalScore = 0
            var combinedNameIndices: Set<Int> = []
            var matchedAllTerms = true

            for term in terms {
                let nameMatch = match(pattern: term, in: project.name)
                let pathMatch = match(pattern: term, in: project.displayPath)

                if let nameMatch {
                    totalScore += nameMatch.score * 3
                    combinedNameIndices.formUnion(nameMatch.indices)
                } else if let pathMatch {
                    totalScore += pathMatch.score
                } else {
                    matchedAllTerms = false
                    break
                }
            }

            guard matchedAllTerms else { continue }

            // Preserve recency & pinned tie-breakers subtly
            if project.isPinned {
                totalScore += 40
            }
            let recencyBoost = max(0, 30 - index)
            totalScore += recencyBoost

            results.append(
                ScoredProject(
                    project: project,
                    score: totalScore,
                    matchedNameIndices: combinedNameIndices
                )
            )
        }

        results.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.project.isPinned != rhs.project.isPinned {
                return lhs.project.isPinned && !rhs.project.isPinned
            }
            if lhs.project.recencyRank != rhs.project.recencyRank {
                return lhs.project.recencyRank < rhs.project.recencyRank
            }
            return lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
        }

        return results
    }

    public static func match(pattern: String, in target: String) -> (score: Int, indices: Set<Int>)? {
        let patternChars = Array(pattern.lowercased())
        let targetOriginal = Array(target)
        let targetChars = Array(target.lowercased())

        guard !patternChars.isEmpty else { return (0, []) }
        guard patternChars.count <= targetChars.count else { return nil }

        // 1. Check exact / prefix / contiguous substring first for best indices & highest score
        let lowerPattern = String(patternChars)
        let lowerTarget = String(targetChars)

        if lowerTarget == lowerPattern {
            return (1200, Set(0..<targetChars.count))
        }

        if lowerTarget.hasPrefix(lowerPattern) {
            let indices = Set(0..<patternChars.count)
            return (800 - targetChars.count, indices)
        }

        if let substringStart = findContiguousStart(pattern: patternChars, in: targetChars) {
            let indices = Set(substringStart..<(substringStart + patternChars.count))
            let boundaryBonus = isWordBoundary(at: substringStart, in: targetOriginal) ? 140 : 0
            let score = 450 + boundaryBonus - substringStart - max(0, targetChars.count - patternChars.count)
            return (score, indices)
        }

        // 2. Greedy subsequence match preferring word boundaries and consecutive characters
        var matchedIndices: [Int] = []
        matchedIndices.reserveCapacity(patternChars.count)

        var searchStart = 0
        for pChar in patternChars {
            var foundAt: Int?
            var bestCandidateScore = Int.min

            for idx in searchStart..<targetChars.count {
                guard targetChars[idx] == pChar else { continue }
                var localScore = 10
                if let prev = matchedIndices.last, idx == prev + 1 {
                    localScore += 45
                }
                if isWordBoundary(at: idx, in: targetOriginal) {
                    localScore += 35
                }
                localScore -= idx
                if localScore > bestCandidateScore {
                    bestCandidateScore = localScore
                    foundAt = idx
                    // Immediately accept consecutive match or boundary at earliest spot if consecutive
                    if let prev = matchedIndices.last, idx == prev + 1 {
                        break
                    }
                }
            }

            guard let chosen = foundAt else {
                return nil
            }
            matchedIndices.append(chosen)
            searchStart = chosen + 1
        }

        var score = 150
        for (offset, idx) in matchedIndices.enumerated() {
            if offset > 0 && idx == matchedIndices[offset - 1] + 1 {
                score += 30
            }
            if isWordBoundary(at: idx, in: targetOriginal) {
                score += 25
            }
        }
        score -= (matchedIndices.last ?? 0) - (matchedIndices.first ?? 0)
        score -= targetChars.count

        return (score, Set(matchedIndices))
    }

    private static func findContiguousStart(pattern: [Character], in target: [Character]) -> Int? {
        guard pattern.count <= target.count else { return nil }
        let limit = target.count - pattern.count
        var bestStart: Int?

        for start in 0...limit {
            var allEqual = true
            for j in 0..<pattern.count where target[start + j] != pattern[j] {
                allEqual = false
                break
            }
            if allEqual {
                if isWordBoundary(at: start, in: target) {
                    return start
                }
                if bestStart == nil {
                    bestStart = start
                }
            }
        }
        return bestStart
    }

    private static func isWordBoundary(at index: Int, in chars: [Character]) -> Bool {
        if index == 0 { return true }
        let prev = chars[index - 1]
        let curr = chars[index]
        if prev == "/" || prev == "-" || prev == "_" || prev == "." || prev == " " {
            return true
        }
        if prev.isLowercase && curr.isUppercase {
            return true
        }
        return false
    }
}
