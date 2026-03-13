import SwiftUI

struct ActionPanelView: View {
    @Bindable var brewfileVM: BrewfileViewModel
    var log: ProcessingLog
    @Binding var isRunning: Bool
    var onError: (String) -> Void
    var brewfilePath: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTIONS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let entry = brewfileVM.selectedEntry {
                        // Update badge in actions if outdated
                        if brewfileVM.outdatedNames.contains(entry.name) {
                            actionButton("Upgrade", icon: "arrow.up.circle.fill", tint: .orange) {
                                Task { await runBrew(["upgrade", entry.name]) }
                            }
                            Divider().padding(.vertical, 2)
                        }

                        actionButton("Install", icon: "arrow.down.circle") {
                            Task { await runBrew(["install", entry.name]) }
                        }

                        actionButton("Uninstall", icon: "trash", role: .destructive) {
                            Task {
                                var args = ["uninstall"]
                                if entry.kind == .cask { args.append("--cask") }
                                args.append(entry.name)
                                await runBrew(args)
                            }
                        }

                        Divider().padding(.vertical, 2)

                        actionButton("Remove from Brewfile", icon: "minus.circle", role: .destructive) {
                            brewfileVM.remove(entry: entry, brewfileURL: brewfilePath)
                        }
                    } else {
                        Text("Select a package\nto see actions.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func actionButton(
        _ label: String,
        icon: String,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(label, systemImage: icon)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            tint.map { AnyShapeStyle($0) }
            ?? (role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        )
        .disabled(isRunning)
        .padding(.vertical, 2)
    }

    // MARK: - Brew execution

    private func runBrew(_ args: [String]) async {
        guard !isRunning else { return }
        isRunning = true
        log.clear()
        log.append("$ brew " + args.joined(separator: " "))

        do {
            try await BrewRunner.shared.run(args) { @MainActor line, level in
                log.append(line, level: level)
            }
            log.append("Done.")
            // Refresh outdated list after upgrade/install/uninstall
            brewfileVM.outdatedNames = await BrewRunner.shared.outdatedNames()
        } catch {
            log.append("Error: \(error.localizedDescription)", level: .error)
            onError(error.localizedDescription)
        }

        isRunning = false
    }
}
