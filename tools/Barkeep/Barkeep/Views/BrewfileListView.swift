import SwiftUI

struct BrewfileListView: View {
    @Bindable var vm: BrewfileViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar(text: $vm.filterText)
            Divider()

            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filteredSections.isEmpty {
                emptyLabel(vm.filterText.isEmpty ? "No Brewfile loaded" : "No matches")
            } else {
                List(selection: Binding(
                    get: { vm.selectedEntry?.id },
                    set: { id in
                        if let entry = vm.allEntries.first(where: { $0.id == id }) {
                            vm.selectedEntry = entry
                            Task { await vm.loadDetail(for: entry) }
                        }
                    }
                )) {
                    ForEach(vm.filteredSections, id: \.name) { section in
                        Section(section.name) {
                            ForEach(section.entries) { entry in
                                PackageRowView(
                                    name: entry.name,
                                    kind: entry.kind,
                                    hasUpdate: vm.outdatedNames.contains(entry.name)
                                )
                                .tag(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}
