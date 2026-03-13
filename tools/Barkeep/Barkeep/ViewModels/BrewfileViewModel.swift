import SwiftUI

@Observable
@MainActor
final class BrewfileViewModel {
    var nodes: [BrewfileNode] = []
    var isLoading = false
    var error: String? = nil
    var selectedEntry: BrewfileEntry? = nil
    var selectedDetail: BrewPackage? = nil
    var isLoadingDetail = false
    var filterText = ""
    var outdatedNames: Set<String> = []

    /// Cache of fully-loaded package details, keyed by entry name.
    private var detailCache: [String: BrewPackage] = [:]

    // MARK: - Computed

    var allEntries: [BrewfileEntry] {
        BrewfileParser.entries(from: nodes)
    }

    var sections: [(name: String, entries: [BrewfileEntry])] {
        BrewfileParser.sections(from: nodes)
    }

    var filteredSections: [(name: String, entries: [BrewfileEntry])] {
        guard !filterText.isEmpty else { return sections }
        return sections.compactMap { section in
            let hits = section.entries.filter {
                $0.name.localizedCaseInsensitiveContains(filterText)
            }
            return hits.isEmpty ? nil : (name: section.name, entries: hits)
        }
    }

    var sectionNames: [String] {
        sections.map { $0.name }
    }

    // MARK: - Load

    func load(from url: URL) {
        isLoading = true
        error = nil
        do {
            nodes = try BrewfileParser.parse(url: url)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        detailCache.removeAll()
        Task { outdatedNames = await BrewRunner.shared.outdatedNames() }
    }

    // MARK: - On-demand detail

    func loadDetail(for entry: BrewfileEntry) async {
        guard entry.kind != .tap else { return }

        // Return cached detail immediately if available.
        if let cached = detailCache[entry.name] {
            selectedDetail = cached
            isLoadingDetail = false
            return
        }

        selectedDetail = nil
        isLoadingDetail = true

        // Phase 1: fast fetch — brew info only.
        let infos = try? await BrewRunner.shared.info(names: [entry.name], kind: entry.kind)
        guard var pkg = infos?.first else {
            isLoadingDetail = false
            return
        }
        pkg.isInBrewfile    = true
        pkg.brewfileSection = entry.section

        // Show basic info immediately.
        selectedDetail = pkg
        isLoadingDetail = false

        // Phase 2: background-fetch expensive data concurrently.
        let capturedName = entry.name
        async let tldrFetch = BrewRunner.shared.tldr(for: capturedName)
        async let manFetch  = BrewRunner.shared.manPage(for: capturedName)
        async let usesFetch = BrewRunner.shared.uses(for: capturedName)

        let (tldrResult, manResult, usesResult) = await (tldrFetch, manFetch, usesFetch)

        // Guard against stale updates — only apply if the user hasn't navigated away.
        guard selectedEntry?.name == capturedName else { return }

        pkg.tldr                = tldrResult.examples
        pkg.tldrSummary         = tldrResult.summary
        pkg.manSections         = manResult
        pkg.reverseDependencies = usesResult

        selectedDetail = pkg
        detailCache[capturedName] = pkg
    }

    // MARK: - Mutations

    func contains(name: String, kind: PackageKind) -> Bool {
        allEntries.contains { $0.name == name && $0.kind == kind }
    }

    func add(name: String, kind: PackageKind, section: String, brewfileURL: URL) {
        guard !contains(name: name, kind: kind) else { return }
        let raw   = BrewfileEntry.canonicalLine(name: name, kind: kind)
        let entry = BrewfileEntry(name: name, kind: kind, section: section, rawLine: raw)

        // Insert after the last entry in the matching section, or append
        if let idx = nodes.indices.last(where: {
            if case .entry(let e) = nodes[$0] { return e.section == section } else { return false }
        }) {
            nodes.insert(.entry(entry), at: nodes.index(after: idx))
        } else {
            if !nodes.isEmpty { nodes.append(.blank) }
            nodes.append(.comment("# \(section)"))
            nodes.append(.entry(entry))
        }

        save(to: brewfileURL)
    }

    func remove(entry: BrewfileEntry, brewfileURL: URL) {
        nodes.removeAll {
            if case .entry(let e) = $0 { return e.id == entry.id }
            return false
        }
        if selectedEntry?.id == entry.id { selectedEntry = nil }
        save(to: brewfileURL)
    }

    // MARK: - Private

    private func save(to url: URL) {
        try? BrewfileParser.write(nodes: nodes, to: url)
    }
}
