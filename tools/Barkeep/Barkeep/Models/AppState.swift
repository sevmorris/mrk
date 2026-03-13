import SwiftUI

@Observable
@MainActor
final class AppState {
    var showBrewfilePicker = false

    var brewfilePath: URL? {
        didSet {
            UserDefaults.standard.set(brewfilePath?.path, forKey: "BrewfilePath")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "BrewfilePath") {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.path) {
                brewfilePath = url
            }
        }
        if brewfilePath == nil {
            let def = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("mrk/Brewfile")
            if FileManager.default.fileExists(atPath: def.path) {
                brewfilePath = def
            }
        }
    }
}
