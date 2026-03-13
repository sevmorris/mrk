import Foundation

// Lossless representation of a single line in the Brewfile
enum BrewfileNode {
    case comment(String)      // # Section header
    case blank                // empty line
    case entry(BrewfileEntry) // brew/cask/tap line
    case unknown(String)      // unrecognised line (mas, etc.) — preserved verbatim

    var rawLine: String {
        switch self {
        case .comment(let s): return s
        case .blank:          return ""
        case .entry(let e):   return e.rawLine
        case .unknown(let s): return s
        }
    }
}

struct BrewfileEntry: Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: PackageKind
    var section: String    // the comment header in effect when this entry was parsed
    var rawLine: String    // original text — used for write-back

    init(name: String, kind: PackageKind, section: String, rawLine: String) {
        self.id      = UUID()
        self.name    = name
        self.kind    = kind
        self.section = section
        self.rawLine = rawLine
    }

    // Generate a canonical Brewfile line for new entries
    static func canonicalLine(name: String, kind: PackageKind) -> String {
        switch kind {
        case .formula: return #"brew "\#(name)""#
        case .cask:    return #"cask "\#(name)""#
        case .tap:     return #"tap "\#(name)""#
        }
    }
}
