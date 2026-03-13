import SwiftUI

struct InstalledListView: View {
    @Bindable var vm: InstalledViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar(text: $vm.filterText)
            Divider()

            if vm.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading packages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filteredFormulae.isEmpty && vm.filteredCasks.isEmpty {
                emptyLabel(vm.filterText.isEmpty ? "No packages found" : "No matches")
            } else {
                List(selection: Binding(
                    get: { vm.selectedPackage?.id },
                    set: { id in
                        let all = vm.formulae + vm.casks
                        if let pkg = all.first(where: { $0.id == id }) {
                            vm.selectedPackage = pkg
                            Task { await vm.loadDetail(for: pkg) }
                        }
                    }
                )) {
                    if !vm.filteredFormulae.isEmpty {
                        Section("Formulae (\(vm.filteredFormulae.count))") {
                            ForEach(vm.filteredFormulae) { pkg in
                                PackageRowView(name: pkg.name, kind: pkg.kind,
                                               untracked: !pkg.isInBrewfile)
                                    .tag(pkg.id)
                            }
                        }
                    }
                    if !vm.filteredCasks.isEmpty {
                        Section("Casks (\(vm.filteredCasks.count))") {
                            ForEach(vm.filteredCasks) { pkg in
                                PackageRowView(name: pkg.name, kind: pkg.kind,
                                               untracked: !pkg.isInBrewfile)
                                    .tag(pkg.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}
