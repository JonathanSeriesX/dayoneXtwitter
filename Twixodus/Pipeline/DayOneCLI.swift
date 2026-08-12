// Step 6 of the pipeline: hand a finished entry to the Day One CLI.
//
// This is the only type that talks to Day One. addPost() builds the `dayone`
// command line, stages the attachments where the sandboxed CLI can read them,
// and runs it.

import Foundation

public final class DayOneCLI {

    /// The Day One CLI is sandboxed (com.apple.security.app-sandbox) and can
    /// only read files inside the app's group container. Attachments passed
    /// from anywhere else are silently dropped: the entry is created, exit
    /// code is 0, but the media bytes never arrive and the images stay blank
    /// forever. So every attachment is staged into this folder first, and
    /// cleaned up afterwards.
    static let stagingDir = NSString(
        string: "~/Library/Group Containers/5U8NS4GX82.dayoneapp2/twixodus-staging"
    ).expandingTildeInPath

    /// Where the `dayone` binary usually lands. GUI apps don't inherit the
    /// shell's PATH, so the well-known locations are checked directly.
    private static let binaryCandidates = [
        "/usr/local/bin/dayone",
        "/opt/homebrew/bin/dayone",
        "/usr/bin/dayone",
    ]

    /// Finds the Day One CLI binary, or nil when it isn't installed.
    public static func resolveBinary() -> String? {
        for candidate in binaryCandidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        // Last resort: whatever PATH the process does have.
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = "\(dir)/dayone"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private let binaryPath: String
    private let log: (String) -> Void

    public init(binaryPath: String, log: @escaping (String) -> Void = { _ in }) {
        self.binaryPath = binaryPath
        self.log = log
    }

    /// Creates a new entry in the Day One app using the CLI.
    ///
    /// If creating an entry with attachments fails, it automatically retries
    /// creating the same entry without the attachments.
    ///
    /// Returns true if the command was executed successfully.
    public func addPost(
        text: String,
        journal: String? = nil,
        tags: [String] = [],
        date: Date? = nil,
        coordinate: (latitude: Double, longitude: Double)? = nil,
        attachments: [String] = []
    ) -> Bool {
        // Stage attachments inside the Day One group container — the sandboxed
        // CLI can't read them from anywhere else (see stagingDir).
        let staged = attachments.isEmpty ? [] : stageAttachments(attachments)
        defer { cleanupStaged(staged) }

        let success = execute(buildCommand(
            text: text, journal: journal, tags: tags, date: date,
            coordinate: coordinate, attachments: staged
        ))

        // If the first attempt failed AND we were trying to add attachments,
        // retry the command without the attachments.
        if !success, !staged.isEmpty {
            log("Warning: Failed to add entry with attachments. Retrying without them...")
            return execute(buildCommand(
                text: text, journal: journal, tags: tags, date: date,
                coordinate: coordinate, attachments: []
            ))
        }

        return success
    }

    // MARK: - Attachment staging

    /// Copies attachments into the Day One group container so the sandboxed
    /// CLI can read them. Returns the staged paths. Files that can't be copied
    /// are passed through unstaged (the CLI will then skip their data, as before).
    private func stageAttachments(_ attachments: [String]) -> [String] {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: Self.stagingDir, withIntermediateDirectories: true)
        } catch {
            log("Warning: can't create staging dir \(Self.stagingDir): \(error.localizedDescription)")
            return attachments
        }

        var staged: [String] = []
        for (i, path) in attachments.enumerated() {
            // The index prefix prevents collisions between same-named files.
            let name = String(format: "%02d-", i) + (path as NSString).lastPathComponent
            let target = (Self.stagingDir as NSString).appendingPathComponent(name)
            do {
                if fm.fileExists(atPath: target) {
                    try fm.removeItem(atPath: target)
                }
                try fm.copyItem(atPath: path, toPath: target)
                staged.append(target)
            } catch {
                log("Warning: couldn't stage attachment \(path): \(error.localizedDescription)")
                staged.append(path)
            }
        }
        return staged
    }

    /// Removes staged copies. The CLI copies them into its own PendingMedia
    /// queue synchronously, so they're disposable as soon as the command returns.
    private func cleanupStaged(_ staged: [String]) {
        for path in staged where path.hasPrefix(Self.stagingDir) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Command construction & execution

    private static let cliDateFormatter = PipelineDates.formatter("yyyy-MM-dd HH:mm:ss")

    /// Assembles the Day One CLI invocation (without the binary itself).
    ///
    /// Per the CLI documentation, all options must come BEFORE the `new` command:
    ///     dayone --journal J --attachments p1 p2 -- new <text>
    /// The `--` terminator is required after list-valued options such as
    /// --attachments and --tags, so the command isn't swallowed as another list
    /// item; it's harmless otherwise, so it is always included.
    func buildCommand(
        text: String,
        journal: String?,
        tags: [String],
        date: Date?,
        coordinate: (latitude: Double, longitude: Double)?,
        attachments: [String]
    ) -> [String] {
        var command: [String] = []

        if let journal {
            command.append(contentsOf: ["--journal", journal])
        }
        if let date {
            // The entry dates are naive UTC wall-clock values, so the zone is
            // pinned to UTC to match.
            command.append(contentsOf: ["--date", Self.cliDateFormatter.string(from: date)])
            command.append(contentsOf: ["-z", "UTC"])
        }
        if let coordinate {
            command.append(contentsOf: ["--coordinate", "\(coordinate.latitude)", "\(coordinate.longitude)"])
        }
        if !tags.isEmpty {
            command.append("--tags")
            command.append(contentsOf: tags)
        }
        if !attachments.isEmpty {
            command.append("--attachments")
            command.append(contentsOf: attachments)
        }

        command.append(contentsOf: ["--", "new", text])
        return command
    }

    /// Runs the CLI once. Arguments are passed as a list — never through a
    /// shell — so nothing in the entry text can be interpreted as shell syntax.
    private func execute(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            log("Error: could not run \(binaryPath): \(error.localizedDescription)")
            return false
        }

        // Read both pipes before waiting, so a chatty CLI can't deadlock on a
        // full pipe buffer.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            // The Day One CLI outputs the UUID of the new entry on success.
            let out = String(data: outData, encoding: .utf8)?.pyStrip() ?? ""
            log("Success: \(out)")
            return true
        } else {
            let err = String(data: errData, encoding: .utf8)?.pyStrip() ?? ""
            log("Error executing Day One command. Exit Code: \(process.terminationStatus)")
            log("Error Details: \(err)")
            return false
        }
    }
}
