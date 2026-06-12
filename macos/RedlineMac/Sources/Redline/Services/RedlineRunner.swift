import Foundation

enum RedlineRunError: LocalizedError, Equatable {
    case processLaunchFailed(String)
    case processFailed(String)
    case invalidJSON(String)
    case engine(code: String, message: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed(let message):
            message
        case .processFailed(let message):
            message
        case .invalidJSON(let message):
            message
        case .engine(_, let message):
            message
        case .cancelled:
            "Check cancelled."
        }
    }
}

/// The engine's `{"error":{"code","message"}}` stdout envelope (Phase 2). Private — only
/// `RedlineRunner.engineError(from:)` decodes it.
private struct EngineErrorEnvelope: Decodable {
    struct Payload: Decodable { let code: String; let message: String }
    let error: Payload
}

struct RedlineRunner {
    let repoRoot: URL

    static func defaultRepoRoot() -> URL {
        if let envRoot = ProcessInfo.processInfo.environment["REDLINE_REPO_ROOT"], !envRoot.isEmpty {
            return URL(fileURLWithPath: envRoot)
        }

        let bundleURL = Bundle.main.bundleURL
        let distURL = bundleURL.deletingLastPathComponent()
        let candidate = distURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("pyproject.toml").path) {
            return candidate
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    var sourceCheckoutRoot: URL? {
        let pyprojectURL = repoRoot.appendingPathComponent("pyproject.toml")
        guard FileManager.default.fileExists(atPath: pyprojectURL.path) else { return nil }
        return repoRoot
    }

    func commandPrefix() -> [String] {
        sourceCheckoutRoot == nil ? ["redline", "check"] : ["uv", "run", "redline", "check"]
    }

    func workingDirectoryURL() -> URL {
        sourceCheckoutRoot ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func run(
        leasePDF: URL,
        profile: ReviewProfile,
        dealSheet: URL?,
        context: String,
        failOn: FailOn,
        provider: LLMProvider,
        model: String,
        baseURL: String,
        apiKey: String,
        thread: String = "",
        onLaunch: @Sendable (Process) -> Void = { _ in }
    ) async throws -> CheckReport {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.currentDirectoryURL = workingDirectoryURL()
            var temporaryFiles: [URL] = []

            func writeTemporaryTextFile(prefix: String, contents: String) -> URL? {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(prefix)-\(UUID().uuidString).txt")
                guard (try? contents.write(to: url, atomically: true, encoding: .utf8)) != nil else {
                    return nil
                }
                temporaryFiles.append(url)
                return url
            }

            var arguments = commandPrefix() + [
                leasePDF.path,
                "--json",
                "--profile",
                profile.rawValue,
                "--fail-on",
                failOn.rawValue,
                "--provider",
                provider.rawValue,
            ]

            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedModel.isEmpty {
                arguments.append(contentsOf: ["--model", trimmedModel])
            }

            let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedBaseURL.isEmpty {
                arguments.append(contentsOf: ["--base-url", trimmedBaseURL])
            }

            if let dealSheet {
                arguments.append(contentsOf: ["--deal", dealSheet.path])
            }

            let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContext.isEmpty {
                if let url = writeTemporaryTextFile(prefix: "redline-context", contents: trimmedContext) {
                    arguments.append(contentsOf: ["--context-file", url.path])
                } else {
                    arguments.append(contentsOf: ["--context", trimmedContext])
                }
            }

            let trimmedThread = thread.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedThread.isEmpty {
                if let url = writeTemporaryTextFile(prefix: "redline-thread", contents: thread) {
                    arguments.append(contentsOf: ["--thread", url.path])
                }
            }

            process.arguments = arguments

            var environment = ProcessInfo.processInfo.environment
            // A Finder-launched app inherits only launchd's minimal PATH (/usr/bin:/bin:…),
            // which omits where uv/codex actually live (~/.local/bin, Homebrew, ~/.cargo/bin).
            // Prepend the standard tool dirs so `env uv` — and uv→codex — resolve no matter how
            // the app was launched. Existing PATH entries are kept, at lower priority.
            let home = NSHomeDirectory()
            let toolDirs = [
                "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin",
            ]
            let basePATH = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = (toolDirs + [basePATH]).joined(separator: ":")
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAPIKey.isEmpty {
                environment["REDLINE_API_KEY"] = trimmedAPIKey
            }
            process.environment = environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let filesToClean = temporaryFiles
            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                for file in filesToClean { try? FileManager.default.removeItem(at: file) }

                if let report = try? JSONDecoder().decode(CheckReport.self, from: outputData) {
                    continuation.resume(returning: report)
                    return
                }

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: RedlineRunError.cancelled)
                    return
                }

                if let engineError = RedlineRunner.engineError(from: outputData) {
                    continuation.resume(throwing: engineError)
                    return
                }

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                let message = error.isEmpty ? output : error
                if process.terminationStatus == 0 {
                    continuation.resume(
                        throwing: RedlineRunError.invalidJSON("Redline returned non-JSON output.")
                    )
                } else {
                    continuation.resume(
                        throwing: RedlineRunError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
                    )
                }
            }

            do {
                try process.run()
                onLaunch(process)
            } catch {
                for file in temporaryFiles { try? FileManager.default.removeItem(at: file) }
                continuation.resume(
                    throwing: RedlineRunError.processLaunchFailed(error.localizedDescription)
                )
            }
        }
    }
}

protocol RedlineRunning {
    func run(
        leasePDF: URL,
        profile: ReviewProfile,
        dealSheet: URL?,
        context: String,
        failOn: FailOn,
        provider: LLMProvider,
        model: String,
        baseURL: String,
        apiKey: String,
        thread: String,
        onLaunch: @Sendable (Process) -> Void
    ) async throws -> CheckReport
}

extension RedlineRunner: RedlineRunning {}

extension RedlineRunner {
    /// Parse the engine's `{"error":{"code","message"}}` stdout envelope (Phase 2) into a
    /// typed error, or nil if the bytes aren't that envelope. Static + pure so it's unit-testable.
    static func engineError(from stdout: Data) -> RedlineRunError? {
        guard let env = try? JSONDecoder().decode(EngineErrorEnvelope.self, from: stdout) else { return nil }
        return .engine(code: env.error.code, message: env.error.message)
    }
}
