import Foundation

enum LogLevel {
    case info
    case verbose
    case error
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let level: LogLevel
}

@Observable
final class ProcessingLog {
    var entries: [LogEntry] = []

    func append(_ message: String, level: LogLevel = .info) {
        entries.append(LogEntry(message: message, level: level))
    }

    func clear() {
        entries = []
    }
}
