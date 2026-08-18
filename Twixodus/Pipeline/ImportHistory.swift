// The per-account memory of how far imports have come — so next year's fresh
// archive doesn't need the date range dialed in by hand.
//
// After every fully completed run (nothing failed, cancelled, or cut off by
// the per-run limit) the app records the day the run covered through, next to
// the account's ledger. When an archive of the same account is loaded later,
// the configure screen reads this back and offers to start right where the
// last import ended. The suggested range overlaps the old one by up to a day —
// harmless, because the ledger already skips imported threads.

import Foundation

public struct ImportHistory {

    public struct Record: Codable {
        /// The latest moment any completed run has covered through.
        public var coveredThrough: Date
        /// When that run finished.
        public var updatedAt: Date

        public init(coveredThrough: Date, updatedAt: Date) {
            self.coveredThrough = coveredThrough
            self.updatedAt = updatedAt
        }
    }

    public let fileURL: URL

    /// One history per account, right next to the account's ledger.
    public init(accountId: String?) {
        let name = accountId.flatMap { $0.isEmpty ? nil : $0 } ?? "default"
        fileURL = ImportLedger.appSupportFolder
            .appendingPathComponent("ledgers", isDirectory: true)
            .appendingPathComponent("last_import-\(name).json")
    }

    /// For tests: a history file at an explicit location.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> Record? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(Record.self, from: data)
    }

    /// Records that a completed run covered everything through `date`. The
    /// record only moves forward: re-running an old range later doesn't
    /// shrink what's already covered.
    public func recordCovered(through date: Date, finishedAt: Date = Date()) {
        if let existing = load(), existing.coveredThrough >= date { return }
        guard let data = try? Self.encoder.encode(
            Record(coveredThrough: date, updatedAt: finishedAt)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
