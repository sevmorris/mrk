import SwiftUI

struct PackageDetailView: View {
    let name: String
    let kind: PackageKind
    var description: String = ""
    var version: String = ""
    var homepage: String = ""
    var section: String = ""
    var isInBrewfile: Bool = true
    var license: String = ""
    var tap: String = ""
    var dependencies: [String] = []
    var buildDependencies: [String] = []
    var caveats: String = ""
    var outdated: Bool = false
    var conflicts: [String] = []
    var tldrSummary: String = ""
    var tldrExamples: [TldrExample] = []
    var manSections: [ManSection] = []
    var reverseDependencies: [String] = []
    var installDate: Date? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Header ──────────────────────────────────────────────
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: kind == .cask ? "app.gift" : "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.title2.bold())
                    Spacer()
                    if outdated {
                        Label("Update available", systemImage: "arrow.up.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(16)

                Divider()

                // ── Stats grid ──────────────────────────────────────────
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 1
                ) {
                    statCell(label: "TYPE",        value: kind == .cask ? "Cask" : "Formula")
                    statCell(label: "IN BREWFILE",  value: isInBrewfile ? "Yes" : "No",
                             valueColor: isInBrewfile ? .primary : .orange)
                    if !version.isEmpty {
                        statCell(label: "VERSION", value: version)
                    }
                    if !license.isEmpty {
                        statCell(label: "LICENSE", value: license)
                    }
                    if !section.isEmpty {
                        statCell(label: "SECTION", value: section)
                    }
                    if !tap.isEmpty && tap != "homebrew/core" && tap != "homebrew/cask" {
                        statCell(label: "TAP", value: tap)
                    }
                    if let date = installDate {
                        statCell(label: "INSTALLED", value: date.formatted(.relative(presentation: .named)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                // ── Description ─────────────────────────────────────────
                if !description.isEmpty {
                    Divider()
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                }

                // ── Caveats ─────────────────────────────────────────────
                if !caveats.isEmpty {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.body)
                            .padding(.top, 1)
                        Text(caveats)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(.orange.opacity(0.06))
                }

                // ── Dependencies ────────────────────────────────────────
                if !dependencies.isEmpty || !buildDependencies.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        if !dependencies.isEmpty {
                            depRow(label: "Runtime", names: dependencies)
                        }
                        if !buildDependencies.isEmpty {
                            depRow(label: "Build", names: buildDependencies)
                        }
                    }
                    .padding(16)
                }

                // ── Conflicts ───────────────────────────────────────────
                if !conflicts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("CONFLICTS WITH")
                        FlowLayout(spacing: 6) {
                            ForEach(conflicts, id: \.self) { name in
                                Text(name)
                                    .font(.system(.footnote, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(16)
                }

                // ── tldr ────────────────────────────────────────────────
                if !tldrExamples.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            sectionLabel("EXAMPLES")
                            Spacer()
                            Text("via tldr")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }

                        if !tldrSummary.isEmpty {
                            Text(tldrSummary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(tldrExamples) { example in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(example.description)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Text(example.command)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.primary.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .padding(16)
                }

                // ── Reverse dependencies ────────────────────────────────
                if !reverseDependencies.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("REQUIRED BY")
                        FlowLayout(spacing: 6) {
                            ForEach(reverseDependencies, id: \.self) { name in
                                Text(name)
                                    .font(.system(.footnote, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.primary.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                }

                // ── Man page ────────────────────────────────────────────
                if !manSections.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        sectionLabel("MAN PAGE")
                        ForEach(manSections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .kerning(0.3)
                                    .foregroundStyle(.secondary)
                                Text(section.content)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(16)
                }

                // ── Homepage ────────────────────────────────────────────
                if let url = URL(string: homepage), !homepage.isEmpty {
                    Divider()
                    Link(destination: url) {
                        HStack {
                            Image(systemName: "globe").font(.footnote)
                            Text(homepage)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func statCell(label: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospaced())
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func depRow(label: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(label.uppercased() + " DEPENDENCIES")
            FlowLayout(spacing: 6) {
                ForEach(names, id: \.self) { dep in
                    Text(dep)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Simple flow layout for dependency pills

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { row in row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in computeRows(proposal: ProposedViewSize(bounds.size), subviews: subviews) {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        for subview in subviews {
            let w = subview.sizeThatFits(.unspecified).width
            if rowWidth + w > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            rowWidth += w + spacing
        }
        return rows
    }
}
