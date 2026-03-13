import SwiftUI

struct ConsoleView: View {
    let log: ProcessingLog

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CONSOLE")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    log.clear()
                } label: {
                    Text("Clear")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if log.entries.isEmpty {
                Text("No output yet.")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(log.entries) { entry in
                                Text(entry.message)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(color(for: entry.level))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: log.entries.count) { _, _ in
                        if let last = log.entries.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(.background.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(8)
    }

    private func color(for level: LogLevel) -> AnyShapeStyle {
        switch level {
        case .info:    return AnyShapeStyle(.primary)
        case .verbose: return AnyShapeStyle(.secondary)
        case .error:   return AnyShapeStyle(.red)
        }
    }
}
