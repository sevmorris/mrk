import SwiftUI

struct BrewfilePickerView: View {
    @Environment(AppState.self) var appState

    private var hasMrkBrewfile: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/mrk/Brewfile")
    }

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome to Barkeep")
                    .font(.title2.bold())
                Text("Choose a Brewfile to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button("Choose Brewfile…") {
                    pickFile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if hasMrkBrewfile {
                    Button("Use ~/mrk/Brewfile") {
                        let url = URL(fileURLWithPath: NSHomeDirectory() + "/mrk/Brewfile")
                        appState.brewfilePath = url
                        appState.showBrewfilePicker = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            if let path = appState.brewfilePath {
                Text(path.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 20)
            }
        }
        .frame(width: 420, height: 300)
        .padding(40)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Brewfile"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            appState.brewfilePath = url
            appState.showBrewfilePicker = false
        }
    }
}
