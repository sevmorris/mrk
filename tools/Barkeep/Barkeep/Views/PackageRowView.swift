import SwiftUI

/// Shared row used by both the Brewfile and Installed lists.
struct PackageRowView: View {
    let name: String
    let kind: PackageKind
    var hasUpdate: Bool = false
    var untracked: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind == .cask ? "app.gift" : "shippingbox")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if hasUpdate {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help("Update available")
            }

            if untracked {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Not tracked in Brewfile")
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Shared helpers for list views

func filterBar(text: Binding<String>) -> some View {
    HStack {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.tertiary)
            .font(.caption)
        TextField("Filter", text: text)
            .textFieldStyle(.plain)
            .font(.body)
        if !text.wrappedValue.isEmpty {
            Button { text.wrappedValue = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.background.opacity(0.5))
}

func emptyLabel(_ text: String) -> some View {
    Text(text)
        .font(.body)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
