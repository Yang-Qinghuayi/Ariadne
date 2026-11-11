import Foundation

public enum WorkspaceDirectoryResolver {
    public static func resolveDirectory(forWorkspaceFile workspacePath: String, fileManager: FileManager = .default) -> String {
        let workspaceURL = URL(fileURLWithPath: workspacePath).standardizedFileURL
        let parentDir = workspaceURL.deletingLastPathComponent().path

        guard let data = try? Data(contentsOf: workspaceURL),
              let rawText = String(data: data, encoding: .utf8)
        else {
            return parentDir
        }

        let cleanedJSON = stripJSONC(rawText)
        guard let cleanedData = cleanedJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: cleanedData) as? [String: Any],
              let folders = object["folders"] as? [[String: Any]]
        else {
            return parentDir
        }

        var resolvedDirectories: [String] = []
        for entry in folders {
            if let folderPath = entry["path"] as? String, !folderPath.isEmpty {
                let candidateURL: URL
                if folderPath.hasPrefix("/") {
                    candidateURL = URL(fileURLWithPath: folderPath).standardizedFileURL
                } else if folderPath.hasPrefix("~") {
                    let expanded = NSString(string: folderPath).expandingTildeInPath
                    candidateURL = URL(fileURLWithPath: expanded).standardizedFileURL
                } else {
                    candidateURL = workspaceURL
                        .deletingLastPathComponent()
                        .appendingPathComponent(folderPath)
                        .standardizedFileURL
                }

                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDir), isDir.boolValue {
                    resolvedDirectories.append(candidateURL.path)
                }
            } else if let uriString = entry["uri"] as? String,
                      let url = URL(string: uriString),
                      url.isFileURL
            {
                let path = url.standardizedFileURL.path
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    resolvedDirectories.append(path)
                }
            }
        }

        if resolvedDirectories.count == 1 {
            return resolvedDirectories[0]
        }

        var parentIsDir: ObjCBool = false
        if fileManager.fileExists(atPath: parentDir, isDirectory: &parentIsDir), parentIsDir.boolValue {
            return parentDir
        }

        return resolvedDirectories.first ?? parentDir
    }

    public static func readGitBranch(in directoryPath: String, fileManager: FileManager = .default) -> String? {
        let dirURL = URL(fileURLWithPath: directoryPath)
        let dotGitURL = dirURL.appendingPathComponent(".git")

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGitURL.path, isDirectory: &isDir) else {
            return nil
        }

        let headURL: URL
        if isDir.boolValue {
            headURL = dotGitURL.appendingPathComponent("HEAD")
        } else if let gitFile = try? String(contentsOf: dotGitURL, encoding: .utf8) {
            let trimmed = gitFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("gitdir:") else { return nil }
            let rawGitDir = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedGitDir: URL
            if rawGitDir.hasPrefix("/") {
                resolvedGitDir = URL(fileURLWithPath: rawGitDir)
            } else {
                resolvedGitDir = dirURL.appendingPathComponent(rawGitDir).standardizedFileURL
            }
            headURL = resolvedGitDir.appendingPathComponent("HEAD")
        } else {
            return nil
        }

        guard let headContent = try? String(contentsOf: headURL, encoding: .utf8) else {
            return nil
        }

        let trimmedHead = headContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        if trimmedHead.hasPrefix(refPrefix) {
            return String(trimmedHead.dropFirst(refPrefix.count))
        }
        let generalRefPrefix = "ref: "
        if trimmedHead.hasPrefix(generalRefPrefix) {
            let fullRef = String(trimmedHead.dropFirst(generalRefPrefix.count))
            return fullRef.split(separator: "/").last.map(String.init) ?? fullRef
        }
        if trimmedHead.count >= 7 {
            return String(trimmedHead.prefix(7))
        }
        return nil
    }

    static func stripJSONC(_ input: String) -> String {
        // First strip // and /* */ comments while preserving string literals
        let chars = Array(input)
        var withoutComments: [Character] = []
        withoutComments.reserveCapacity(chars.count)

        var i = 0
        var inString = false
        var isEscaped = false

        while i < chars.count {
            let c = chars[i]
            if inString {
                withoutComments.append(c)
                if isEscaped {
                    isEscaped = false
                } else if c == "\\" {
                    isEscaped = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            if c == "\"" {
                inString = true
                withoutComments.append(c)
                i += 1
                continue
            }

            if c == "/", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "/" {
                    i += 2
                    while i < chars.count && chars[i] != "\n" && chars[i] != "\r" {
                        i += 1
                    }
                    continue
                } else if next == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") {
                        i += 1
                    }
                    i = min(i + 2, chars.count)
                    continue
                }
            }

            withoutComments.append(c)
            i += 1
        }

        // Now strip trailing commas before } or ] outside strings
        var result: [Character] = []
        result.reserveCapacity(withoutComments.count)
        inString = false
        isEscaped = false
        var idx = 0

        while idx < withoutComments.count {
            let c = withoutComments[idx]
            if inString {
                result.append(c)
                if isEscaped {
                    isEscaped = false
                } else if c == "\\" {
                    isEscaped = true
                } else if c == "\"" {
                    inString = false
                }
                idx += 1
                continue
            }

            if c == "\"" {
                inString = true
                result.append(c)
                idx += 1
                continue
            }

            if c == "," {
                var lookahead = idx + 1
                while lookahead < withoutComments.count && withoutComments[lookahead].isWhitespace {
                    lookahead += 1
                }
                if lookahead < withoutComments.count && (withoutComments[lookahead] == "]" || withoutComments[lookahead] == "}") {
                    idx += 1
                    continue
                }
            }

            result.append(c)
            idx += 1
        }

        return String(result)
    }
}
