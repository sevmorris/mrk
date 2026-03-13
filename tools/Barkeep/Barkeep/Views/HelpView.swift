import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header("Barkeep", subtitle: "Homebrew package manager")

                section("Overview") {
                    text("Barkeep manages your Brewfile from a single window. It reads and writes your Brewfile directly, preserving all comments, section headers, and formatting.")
                }

                section("Package List") {
                    text("Shows everything tracked in your Brewfile, grouped by section. Select a package to view its details.")
                    steps([
                        "Select a package to see its description, version, dependencies, and more",
                        "Use the filter bar to search by name",
                        "Packages with available updates show an orange arrow icon",
                    ])
                }

                section("Package Details") {
                    text("Displayed when a package is selected. Fetched on demand from Homebrew and supplemental sources.")
                    definition("Stats grid",        as: "Type, version, license, section, tap, and install date")
                    definition("Description",       as: "Package description from Homebrew")
                    definition("Caveats",           as: "Post-install notes from the formula")
                    definition("Dependencies",      as: "Runtime and build dependencies")
                    definition("Conflicts with",    as: "Packages that cannot be installed alongside this one")
                    definition("Examples",          as: "Usage examples from tldr (requires tldr to be installed)")
                    definition("Required by",       as: "Other installed packages that depend on this one")
                    definition("Man page",          as: "NAME, SYNOPSIS, and DESCRIPTION from the man page")
                    definition("Homepage",          as: "Opens the package's homepage in your browser")
                }

                section("Actions Panel") {
                    text("Available actions for the selected package.")
                    definition("Upgrade",              as: "Upgrade to the latest version (shown when an update is available)")
                    definition("Install",              as: "Install the package via brew")
                    definition("Uninstall",            as: "Remove the package from your system")
                    definition("Remove from Brewfile", as: "Delete the entry from your Brewfile without uninstalling")
                }

                section("Console") {
                    text("Click the terminal icon in the toolbar to show the console. It streams live output from any brew command Barkeep runs.")
                }

                section("Toolbar") {
                    definition("Filename + path", as: "The currently active Brewfile")
                    definition("N updates",       as: "Number of installed packages with available updates")
                    definition("⏹  Stop",         as: "Cancel a running brew command (visible while running)")
                    definition("⌥  Console",      as: "Toggle the output console")
                    definition("⟳  Refresh",      as: "Reload the Brewfile and re-check for updates")
                    definition("📁  Folder",       as: "Change the active Brewfile")
                }

                section("Keyboard Shortcuts") {
                    definition("⌘O", as: "Choose a different Brewfile")
                    definition("⌘R", as: "Refresh")
                    definition("⌘?", as: "Open this help window")
                }

                section("Notes") {
                    text("Barkeep writes your Brewfile in-place using atomic replacement. All comments, blank lines, and section headers are preserved verbatim.")
                    text("tldr examples require the tldr command-line tool to be installed (brew install tldr).")
                }
            }
            .padding(24)
        }
        .frame(width: 540, height: 660)
    }

    // MARK: - Layout helpers

    private func header(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 20)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.bottom, 18)
    }

    private func text(_ string: String) -> some View {
        Text(string)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func definition(_ term: String, as meaning: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(term)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 170, alignment: .leading)
            Text(meaning)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1).")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, alignment: .trailing)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
