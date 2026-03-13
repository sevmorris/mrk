import Foundation

enum PackageKind: String, Codable, Hashable {
    case formula
    case cask
    case tap
}

struct TldrExample: Identifiable, Hashable {
    let id = UUID()
    let description: String
    let command: String
}

struct ManSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let content: String
}

struct BrewPackage: Identifiable, Hashable {
    var id: String { name + ":" + kind.rawValue }

    let name: String
    let kind: PackageKind

    // Basic
    var description: String = ""
    var version: String = ""
    var homepage: String = ""

    // Extended
    var license: String = ""
    var tap: String = ""
    var dependencies: [String] = []
    var buildDependencies: [String] = []
    var caveats: String = ""
    var outdated: Bool = false
    var conflicts: [String] = []
    var tldr: [TldrExample] = []
    var tldrSummary: String = ""
    var manSections: [ManSection] = []
    var reverseDependencies: [String] = []
    var installDate: Date? = nil

    // State
    var isInstalled: Bool = false
    var isInBrewfile: Bool = false
    var brewfileSection: String? = nil

    static func == (lhs: BrewPackage, rhs: BrewPackage) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(kind)
    }

    func with(
        description: String? = nil,
        version: String? = nil,
        homepage: String? = nil,
        isInBrewfile: Bool? = nil
    ) -> BrewPackage {
        var copy = self
        if let v = description  { copy.description  = v }
        if let v = version      { copy.version      = v }
        if let v = homepage     { copy.homepage     = v }
        if let v = isInBrewfile { copy.isInBrewfile = v }
        return copy
    }
}
