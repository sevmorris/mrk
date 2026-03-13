import Foundation

enum BrewfileParser {

    // MARK: - Parse

    static func parse(url: URL) throws -> [BrewfileNode] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(string: content)
    }

    static func parse(string: String) -> [BrewfileNode] {
        var nodes: [BrewfileNode] = []
        var currentSection = "General"

        let lines = string.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            // Drop the trailing empty element that split always produces
            if i == lines.count - 1 && line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                nodes.append(.blank)
            } else if trimmed.hasPrefix("#") {
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                // Only treat as a section header if it doesn't look like a commented-out entry
                if !body.isEmpty && !looksLikeEntry(body) { currentSection = body }
                nodes.append(.comment(line))
            } else if let entry = parseEntry(line: trimmed, section: currentSection) {
                nodes.append(.entry(entry))
            } else {
                nodes.append(.unknown(line))
            }
        }
        return nodes
    }

    /// Returns true if a string (already stripped of the leading #) looks like a commented-out entry.
    private static func looksLikeEntry(_ body: String) -> Bool {
        let pattern = #"^(brew|cask|tap|mas)\s+""#
        return (try? NSRegularExpression(pattern: pattern))
            .flatMap { $0.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) } != nil
    }

    private static func parseEntry(line: String, section: String) -> BrewfileEntry? {
        // Matches: brew "name", cask "name", tap "org/name"
        // Also handles optional trailing comments and arguments after the name
        let pattern = #"^(brew|cask|tap)\s+"([^"]+)""#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
            let kindRange = Range(match.range(at: 1), in: line),
            let nameRange = Range(match.range(at: 2), in: line)
        else { return nil }

        let kindStr = String(line[kindRange])
        let name    = String(line[nameRange])

        let kind: PackageKind
        switch kindStr {
        case "brew": kind = .formula
        case "cask": kind = .cask
        case "tap":  kind = .tap
        default: return nil
        }

        return BrewfileEntry(name: name, kind: kind, section: section, rawLine: line)
    }

    // MARK: - Write (lossless)

    static func write(nodes: [BrewfileNode], to url: URL) throws {
        let content = nodes.map { $0.rawLine }.joined(separator: "\n") + "\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    static func entries(from nodes: [BrewfileNode]) -> [BrewfileEntry] {
        nodes.compactMap {
            if case .entry(let e) = $0 { return e }
            return nil
        }
    }

    /// Group entries into named sections for display.
    /// Section name is derived from the comment immediately preceding a run of entries.
    static func sections(from nodes: [BrewfileNode]) -> [(name: String, entries: [BrewfileEntry])] {
        var result: [(name: String, entries: [BrewfileEntry])] = []
        var currentSection = "General"
        var currentEntries: [BrewfileEntry] = []

        for node in nodes {
            switch node {
            case .comment(let raw):
                let body = String(raw.trimmingCharacters(in: .whitespaces).dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { continue }
                if !currentEntries.isEmpty {
                    result.append((name: currentSection, entries: currentEntries))
                    currentEntries = []
                }
                currentSection = body
            case .entry(let e):
                currentEntries.append(e)
            default:
                break
            }
        }
        if !currentEntries.isEmpty {
            result.append((name: currentSection, entries: currentEntries))
        }
        return result
    }
}
