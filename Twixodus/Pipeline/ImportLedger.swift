// The ledger of what was already imported, so re-runs never duplicate entries.
//
// Every successfully imported thread leaves one line in the ledger file:
//
//   * an ordinary thread is recorded by its root tweet's ID;
//   * a re-imported (extended) thread is additionally recorded as
//     "<root id>+<last tweet id>" (see extensionMarker), so running the same
//     date range twice doesn't import the same extension over and over — while
//     a *further* extension later still will be picked up.
//
// The app keeps one ledger per Twitter account in Application Support, so an
// archive imported today and a fresh archive of the same account imported next
// year share their history — only the new tweets get imported.

import Foundation

public final class ImportLedger {

    /// ~/Library/Application Support/Twixodus
    public static var appSupportFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Twixodus", isDirectory: true)
    }

    public let fileURL: URL

    /// One ledger per account; the account ID is stable across username
    /// changes. Archives without account.js share the "default" ledger.
    public init(accountId: String?) {
        let name = accountId.flatMap { $0.isEmpty ? nil : $0 } ?? "default"
        fileURL = Self.appSupportFolder
            .appendingPathComponent("ledgers", isDirectory: true)
            .appendingPathComponent("processed_tweets-\(name).txt")
    }

    /// For tests: a ledger at an explicit location.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads the IDs and markers of everything already imported.
    public func loadProcessedIDs() -> Set<String> {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        var ids = Set<String>()
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.pyStrip()
            if !trimmed.isEmpty {
                ids.insert(trimmed)
            }
        }
        return ids
    }

    /// Appends one ID (or extension marker) to the ledger file. Throws when
    /// the line can't be written — a silently lost line would make the next
    /// run import the same thread again.
    private func append(_ id: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let data = Data("\(id)\n".utf8)
        // FileHandle only opens existing files; a fresh ledger is created by
        // the write(to:) below instead.
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL)
        }
    }

    /// Records a thread as processed — in the file and in the in-memory set —
    /// without ever writing the same ID twice. Throws when the ledger file
    /// can't be written; IDs are only added to the set once safely on disk.
    public func rememberProcessed(
        tweetId: String, reimportMarker: String?, processedIDs: inout Set<String>
    ) throws {
        for id in [tweetId, reimportMarker].compactMap({ $0 }) {
            if !processedIDs.contains(id) {
                try append(id)
                processedIDs.insert(id)
            }
        }
    }

    /// Identifies a thread together with its current last tweet, so a thread
    /// that was imported once and extended later can be told apart from the
    /// copy already in Day One. The '+' keeps these markers distinct from
    /// plain tweet IDs.
    public static func extensionMarker(_ thread: TweetThread) -> String {
        "\(thread.first!.idStr)+\(thread.last!.idStr)"
    }
}
