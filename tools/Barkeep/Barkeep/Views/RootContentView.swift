import SwiftUI

struct RootContentView: View {
    @Environment(AppState.self) var appState
    @State private var brewfileVM  = BrewfileViewModel()
    @State private var log         = ProcessingLog()
    @State private var isRunning   = false
    @State private var showConsole = false
    @State private var alertMessage: String? = nil

    var body: some View {
        @Bindable var appState = appState

        Group {
            if appState.brewfilePath == nil || appState.showBrewfilePicker {
                BrewfilePickerView()
                    .environment(appState)
            } else {
                mainWindow
            }
        }
        .onChange(of: appState.brewfilePath) { _, url in
            guard let url else { return }
            brewfileVM.load(from: url)
        }
        .onAppear {
            if let url = appState.brewfilePath { brewfileVM.load(from: url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .barkeepRefresh)) { _ in
            if let url = appState.brewfilePath { brewfileVM.load(from: url) }
        }
        .alert("Error", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Main layout

    private var mainWindow: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HStack(spacing: 0) {
                BrewfileListView(vm: brewfileVM)
                    .frame(width: 240)

                Divider()

                VStack(spacing: 0) {
                    detailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showConsole {
                        Divider()
                        ConsoleView(log: log)
                            .frame(height: 170)
                    }
                }

                Divider()

                ActionPanelView(
                    brewfileVM:  brewfileVM,
                    log:         log,
                    isRunning:   $isRunning,
                    onError:     { alertMessage = $0 },
                    brewfilePath: appState.brewfilePath!
                )
                .frame(width: 220)
            }
        }
        .frame(minWidth: 860, minHeight: 520)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Brewfile path
            if let url = appState.brewfilePath {
                Text(url.lastPathComponent)
                    .font(.subheadline.bold())
                Text(url.deletingLastPathComponent().path
                         .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if brewfileVM.isLoading {
                ProgressView().controlSize(.small)
            }

            if !brewfileVM.outdatedNames.isEmpty {
                Label("\(brewfileVM.outdatedNames.count) updates", systemImage: "arrow.up.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if isRunning {
                Button {
                    Task { await BrewRunner.shared.cancel() }
                } label: {
                    Image(systemName: "stop.circle").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }

            toolbarButton(icon: showConsole ? "terminal.fill" : "terminal",
                          active: showConsole, help: "Toggle console") {
                withAnimation(.easeInOut(duration: 0.2)) { showConsole.toggle() }
            }

            toolbarButton(icon: "arrow.clockwise", help: "Refresh") {
                guard let url = appState.brewfilePath else { return }
                brewfileVM.load(from: url)
            }
            .disabled(isRunning)

            toolbarButton(icon: "folder", help: "Change Brewfile") {
                appState.showBrewfilePicker = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let entry = brewfileVM.selectedEntry {
            if brewfileVM.isLoadingDetail {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailView(for: brewfileVM.selectedDetail,
                           fallbackName: entry.name,
                           fallbackKind: entry.kind,
                           section: entry.section)
            }
        } else {
            EmptyStateView()
        }
    }

    @ViewBuilder
    private func detailView(
        for pkg: BrewPackage?,
        fallbackName: String = "",
        fallbackKind: PackageKind = .formula,
        section: String = ""
    ) -> some View {
        PackageDetailView(
            name:              pkg?.name              ?? fallbackName,
            kind:              pkg?.kind              ?? fallbackKind,
            description:       pkg?.description       ?? "",
            version:           pkg?.version           ?? "",
            homepage:          pkg?.homepage          ?? "",
            section:           pkg?.brewfileSection   ?? section,
            isInBrewfile:      true,
            license:           pkg?.license           ?? "",
            tap:               pkg?.tap               ?? "",
            dependencies:      pkg?.dependencies      ?? [],
            buildDependencies: pkg?.buildDependencies ?? [],
            caveats:           pkg?.caveats           ?? "",
            outdated:          pkg?.outdated ?? brewfileVM.outdatedNames.contains(pkg?.name ?? fallbackName),
            conflicts:         pkg?.conflicts         ?? [],
            tldrSummary:       pkg?.tldrSummary       ?? "",
            tldrExamples:         pkg?.tldr                ?? [],
            manSections:          pkg?.manSections          ?? [],
            reverseDependencies:  pkg?.reverseDependencies  ?? [],
            installDate:          pkg?.installDate
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func toolbarButton(
        icon: String,
        active: Bool = false,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
