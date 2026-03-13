import Foundation

enum BrewError: LocalizedError {
    case notFound
    case failed(Int32)
    case failedWithMessage(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Homebrew not found. Install from https://brew.sh"
        case .failed(let code):
            return "brew exited with status \(code)"
        case .failedWithMessage(let msg):
            return msg.isEmpty ? "brew command failed" : msg
        }
    }
}

actor BrewRunner {
    static let shared = BrewRunner()

    private var runningProcess: Process?

    // MARK: - Executable

    private func brewExecutable() throws -> URL {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        throw BrewError.notFound
    }

    private static func brewEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["HOME"] = NSHomeDirectory()
        return env
    }

    // MARK: - Run (streaming)

    /// Run brew with streaming output. Each output line is passed to `onOutput` on the main actor.
    func run(
        _ args: [String],
        onOutput: @MainActor @Sendable @escaping (String, LogLevel) -> Void
    ) async throws {
        let brew = try brewExecutable()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = brew
            process.arguments = args
            process.environment = Self.brewEnvironment()

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            nonisolated(unsafe) var resumed = false

            func emit(_ text: String, level: LogLevel) {
                for line in text.components(separatedBy: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty {
                        Task { await onOutput(t, level) }
                    }
                }
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                if let s = String(data: handle.availableData, encoding: .utf8) { emit(s, level: .verbose) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                if let s = String(data: handle.availableData, encoding: .utf8) { emit(s, level: .verbose) }
            }

            process.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                guard !resumed else { return }
                resumed = true
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BrewError.failed(p.terminationStatus))
                }
            }

            do {
                runningProcess = process
                try process.run()
            } catch {
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: error)
            }
        }

        runningProcess = nil
    }

    func cancel() {
        runningProcess?.terminate()
        runningProcess = nil
    }

    // MARK: - Capture (non-streaming)

    func capture(_ args: [String]) async throws -> String {
        let brew = try brewExecutable()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = brew
            process.arguments = args
            process.environment = Self.brewEnvironment()

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            nonisolated(unsafe) var stderrData = Data()
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrData.append(handle.availableData)
            }

            process.terminationHandler = { p in
                errPipe.fileHandleForReading.readabilityHandler = nil
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } else {
                    let msg = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(throwing: BrewError.failedWithMessage(msg))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Convenience queries

    func listFormulae() async throws -> [String] {
        let out = try await capture(["list", "--formula", "--full-name"])
        return out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    func listCasks() async throws -> [String] {
        let out = try await capture(["list", "--cask"])
        return out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Fetch detailed info for one or more packages via `brew info --json=v2`.
    func info(names: [String], kind: PackageKind) async throws -> [BrewPackage] {
        guard !names.isEmpty else { return [] }
        let flag = kind == .cask ? "--cask" : "--formula"
        let json = try await capture(["info", "--json=v2", flag] + names)
        return parseInfoJSON(json, kind: kind)
    }

    private func parseInfoJSON(_ json: String, kind: PackageKind) -> [BrewPackage] {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var packages: [BrewPackage] = []

        if kind == .formula, let formulae = root["formulae"] as? [[String: Any]] {
            for f in formulae {
                let name    = f["name"]     as? String ?? ""
                let desc    = f["desc"]     as? String ?? ""
                let home    = f["homepage"] as? String ?? ""
                let version = (f["versions"] as? [String: Any])?["stable"] as? String ?? ""
                let license = f["license"]  as? String ?? ""
                let tap     = f["tap"]      as? String ?? ""
                let deps    = f["dependencies"]       as? [String] ?? []
                let buildDeps = f["build_dependencies"] as? [String] ?? []
                let caveats = f["caveats"]  as? String ?? ""
                let outdated  = f["outdated"] as? Bool ?? false
                let conflicts = f["conflicts_with"] as? [String] ?? []
                let installTime = (f["installed"] as? [[String: Any]])?.first?["time"] as? TimeInterval

                var pkg = BrewPackage(name: name, kind: .formula,
                                      description: desc, version: version, homepage: home,
                                      isInstalled: true)
                pkg.license          = license
                pkg.tap              = tap
                pkg.dependencies     = deps
                pkg.buildDependencies = buildDeps
                pkg.caveats          = caveats.trimmingCharacters(in: .whitespacesAndNewlines)
                pkg.outdated         = outdated
                pkg.conflicts        = conflicts
                pkg.installDate      = installTime.map { Date(timeIntervalSince1970: $0) }
                packages.append(pkg)
            }
        } else if kind == .cask, let casks = root["casks"] as? [[String: Any]] {
            for c in casks {
                let token   = c["token"]    as? String ?? ""
                let desc    = c["desc"]     as? String ?? ""
                let home    = c["homepage"] as? String ?? ""
                let version = c["version"]  as? String ?? ""
                let tap     = c["tap"]      as? String ?? ""
                let caveats = c["caveats"]  as? String ?? ""
                let outdated = c["outdated"] as? Bool ?? false
                let conflicts = (c["conflicts_with"] as? [String: Any])?["cask"] as? [String] ?? []
                let installTime = c["installed_time"] as? TimeInterval

                var pkg = BrewPackage(name: token, kind: .cask,
                                      description: desc, version: version, homepage: home,
                                      isInstalled: true)
                pkg.tap         = tap
                pkg.caveats     = caveats.trimmingCharacters(in: .whitespacesAndNewlines)
                pkg.outdated    = outdated
                pkg.conflicts   = conflicts
                pkg.installDate = installTime.map { Date(timeIntervalSince1970: $0) }
                packages.append(pkg)
            }
        }

        return packages
    }

    // MARK: - Outdated

    /// Returns the names of all outdated formulae and casks.
    func outdatedNames() async -> Set<String> {
        guard let json = try? await capture(["outdated", "--json"]),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        var names = Set<String>()
        if let formulae = root["formulae"] as? [[String: Any]] {
            formulae.compactMap { $0["name"] as? String }.forEach { names.insert($0) }
        }
        if let casks = root["casks"] as? [[String: Any]] {
            casks.compactMap { $0["name"] as? String }.forEach { names.insert($0) }
        }
        return names
    }

    // MARK: - Man page

    /// Fetches and parses the man page for a formula, returning key sections.
    /// Returns empty array for casks or when no man page exists.
    func manPage(for name: String) async -> [ManSection] {
        // Use Process directly with /usr/bin/man to avoid shell injection via package name.
        // Pipe through col -b to strip backspace formatting.
        guard let manOut = try? await captureRaw("/usr/bin/man", args: [name]),
              let raw = try? await captureRawInput("/usr/bin/col", args: ["-b"], input: manOut),
              !raw.isEmpty
        else { return [] }
        return parseManPage(raw)
    }

    private func parseManPage(_ raw: String) -> [ManSection] {
        // Sections we care about, in display order
        let wantedTitles = ["NAME", "SYNOPSIS", "DESCRIPTION"]

        var sections: [(title: String, lines: [String])] = []
        var currentTitle = ""
        var currentLines: [String] = []

        for line in raw.components(separatedBy: "\n") {
            // Section headers: unindented ALL-CAPS words (optionally with spaces/parens)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isHeader = !line.hasPrefix(" ") && !line.hasPrefix("\t")
                && !trimmed.isEmpty
                && trimmed == trimmed.uppercased()
                && trimmed.range(of: #"^[A-Z][A-Z\s\(\)]+$"#, options: .regularExpression) != nil

            if isHeader {
                if !currentTitle.isEmpty && !currentLines.isEmpty {
                    sections.append((title: currentTitle, lines: currentLines))
                }
                currentTitle = trimmed
                currentLines = []
            } else if !currentTitle.isEmpty {
                currentLines.append(line)
            }
        }
        if !currentTitle.isEmpty && !currentLines.isEmpty {
            sections.append((title: currentTitle, lines: currentLines))
        }

        return sections
            .filter { wantedTitles.contains($0.title) }
            .compactMap { s -> ManSection? in
                let content = s.lines
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return nil }
                return ManSection(title: s.title, content: content)
            }
    }

    // MARK: - Reverse dependencies

    /// Returns installed packages that depend on the given formula.
    func uses(for name: String) async -> [String] {
        let out = (try? await capture(["uses", "--installed", name])) ?? ""
        return out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    // MARK: - tldr

    /// Fetch and parse tldr examples for a package. Returns empty array if tldr isn't installed
    /// or no page exists for this package.
    func tldr(for name: String) async -> (summary: String, examples: [TldrExample]) {
        guard let tldrPath = ["tldr", "/opt/homebrew/bin/tldr", "/usr/local/bin/tldr"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) ||
                            ($0 == "tldr" && ProcessInfo.processInfo.environment["PATH"] != nil) })
        else { return ("", []) }

        // Resolve `tldr` via PATH if needed
        let execPath: String
        if tldrPath == "tldr" {
            execPath = (try? await capture(["which", "tldr"])) ?? ""
        } else {
            execPath = tldrPath
        }
        guard !execPath.isEmpty, FileManager.default.isExecutableFile(atPath: execPath.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return ("", [])
        }

        guard let raw = try? await captureRaw(execPath.trimmingCharacters(in: .whitespacesAndNewlines),
                                              args: ["--raw", name])
        else { return ("", []) }

        return parseTldr(raw)
    }

    private func captureRaw(_ executable: String, args: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = Self.brewEnvironment()

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = Pipe() // discard

            process.terminationHandler = { p in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } else {
                    continuation.resume(throwing: BrewError.failed(p.terminationStatus))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Like captureRaw but feeds `input` to the process's stdin.
    private func captureRawInput(_ executable: String, args: [String], input: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.environment = Self.brewEnvironment()

            let inPipe  = Pipe()
            let outPipe = Pipe()
            process.standardInput  = inPipe
            process.standardOutput = outPipe
            process.standardError  = Pipe() // discard

            process.terminationHandler = { p in
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } else {
                    continuation.resume(throwing: BrewError.failed(p.terminationStatus))
                }
            }
            do {
                try process.run()
                if let inputData = input.data(using: .utf8) {
                    inPipe.fileHandleForWriting.write(inputData)
                }
                inPipe.fileHandleForWriting.closeFile()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parseTldr(_ raw: String) -> (summary: String, examples: [TldrExample]) {
        var summaryLines: [String] = []
        var examples: [TldrExample] = []
        var pendingDescription = ""

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("> ") {
                // Summary / description line
                let text = String(line.dropFirst(2))
                    .replacingOccurrences(of: "<", with: "")
                    .replacingOccurrences(of: ">", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !text.hasPrefix("More information:") {
                    summaryLines.append(text)
                }
            } else if line.hasPrefix("- ") {
                // Example description
                pendingDescription = String(line.dropFirst(2))
                    .trimmingCharacters(in: .init(charactersIn: ": "))
            } else if line.hasPrefix("`") && line.hasSuffix("`") && !pendingDescription.isEmpty {
                // Command — strip surrounding backticks and {{placeholder}} braces
                var cmd = String(line.dropFirst().dropLast())
                cmd = cmd.replacingOccurrences(of: "{{", with: "")
                cmd = cmd.replacingOccurrences(of: "}}", with: "")
                examples.append(TldrExample(description: pendingDescription, command: cmd))
                pendingDescription = ""
            }
        }

        let summary = summaryLines
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (summary, examples)
    }
}
