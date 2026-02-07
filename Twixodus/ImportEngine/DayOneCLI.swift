import Foundation

struct DayOnePayload: Sendable {
    let text: String
    let journal: String?
    let tags: [String]
    let date: Date?
    let coordinate: (latitude: Double, longitude: Double)?
    let attachments: [String]
}

struct DayOneCommandResult: Sendable {
    let success: Bool
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

final class DayOneCLI {
    private let fileManager = FileManager.default

    func availabilityError() -> String? {
        resolveExecutablePath() == nil ? "Could not find Day One CLI executable ('dayone')." : nil
    }

    func installedExecutablePath() -> String? {
        resolveExecutablePath()
    }

    func listJournals() -> (journals: [String]?, error: String?) {
        guard let executablePath = resolveExecutablePath() else {
            return (nil, "Day One CLI is not installed.")
        }

        let result = runCommand(executablePath: executablePath, arguments: ["journals"])
        guard result.success else {
            let detail = result.stderr.trimmedNilIfEmpty ?? "Day One CLI failed to list journals."
            return (nil, detail)
        }

        let lines = result.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (lines, nil)
    }

    func addPost(payload: DayOnePayload) -> DayOneCommandResult {
        guard let executablePath = resolveExecutablePath() else {
            return DayOneCommandResult(
                success: false,
                stdout: "",
                stderr: "Could not find Day One CLI executable ('dayone').",
                exitCode: -1
            )
        }

        var arguments = ["new", payload.text]

        if let journal = payload.journal?.trimmedNilIfEmpty {
            arguments += ["--journal", journal]
        }

        if !payload.tags.isEmpty {
            arguments.append("--tags")
            arguments.append(contentsOf: payload.tags)
        }

        if let date = payload.date {
            arguments += ["--date", Self.utcOutputFormatter.string(from: date), "-z", "UTC"]
        }

        if let coordinate = payload.coordinate {
            arguments += ["--coordinate", String(coordinate.latitude), String(coordinate.longitude)]
        }

        if !payload.attachments.isEmpty {
            arguments.append("--attachments")
            arguments.append(contentsOf: payload.attachments)
        }

        let initial = runCommand(executablePath: executablePath, arguments: arguments)
        if initial.success || payload.attachments.isEmpty {
            return initial
        }

        if let attachmentIndex = arguments.firstIndex(of: "--attachments") {
            let retryArguments = Array(arguments[..<attachmentIndex])
            return runCommand(executablePath: executablePath, arguments: retryArguments)
        }

        return initial
    }

    private func runCommand(executablePath: String, arguments: [String]) -> DayOneCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return DayOneCommandResult(
                success: process.terminationStatus == 0,
                stdout: stdout,
                stderr: stderr,
                exitCode: process.terminationStatus
            )
        } catch {
            return DayOneCommandResult(
                success: false,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: -1
            )
        }
    }

    private func resolveExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/dayone",
            "/usr/local/bin/dayone",
            "/usr/bin/dayone",
            "/opt/homebrew/bin/dayone2",
            "/usr/local/bin/dayone2",
            "/usr/bin/dayone2"
        ]

        if let existing = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return existing
        }

        if let discovered = which("dayone") {
            return discovered
        }

        if let discovered = which("dayone2") {
            return discovered
        }

        return nil
    }

    private func which(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let output, !output.isEmpty else { return nil }
            return output
        } catch {
            return nil
        }
    }

    private static let utcOutputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
