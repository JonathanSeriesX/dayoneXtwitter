// Steps 1–3 of the pipeline, bundled for the app: find the archive, read
// every tweet, clean the text up, and stitch the tweets into threads. This
// runs once when the user drops an archive; steps 4–7 (selection and the
// actual import) run later, every time the Import button is pressed.

import Foundation

/// A fully loaded archive: everything the import runs need, computed once.
public struct LoadedArchive {
    public let ref: TwitterArchiveRef
    public let tweets: [Tweet]
    public let ownTweetIDs: Set<String>
    public let accountId: String?
    public let archiveUsername: String?
    public let adoptedOrphans: Int
    public let threads: [TweetThread]
    /// Non-fatal problems found while loading (e.g. malformed tweets that had
    /// to be skipped), so the UI can show them instead of losing them.
    public let warnings: [String]

    /// The date span of the archive's threads (by root tweet), for the UI.
    public var threadDateRange: ClosedRange<Date>? {
        let dates = threads.compactMap { $0.first?.createdAt }
        guard let min = dates.min(), let max = dates.max() else { return nil }
        return min...max
    }
}

public enum ArchiveLoading {

    /// Runs pipeline steps 1–3 over the folder the user dropped.
    public static func load(
        root: URL,
        stage: (String) -> Void = { _ in },
        log: (String) -> Void = { _ in }
    ) throws -> LoadedArchive {
        // ---- Step 1: find the Twitter archive and read every tweet --------
        stage("Reading tweets…")
        let ref = try TwitterArchiveLoader.findArchive(at: root)
        // The loader only logs problems, so its messages double as warnings
        // for the UI.
        var warnings: [String] = []
        let warn: (String) -> Void = { message in
            warnings.append(message)
            log(message)
        }
        let (tweets, ownTweetIDs) = try TwitterArchiveLoader.loadTweets(from: ref, log: warn)
        log("Using archive folder \(ref.dataFolder.path)")
        let partCount = ref.tweetsJSPaths.count > 1 ? " across \(ref.tweetsJSPaths.count) files" : ""
        log("Found \(tweets.count) tweets in the archive\(partCount).")

        let account = TwitterArchiveLoader.loadAccountInfo(from: ref)

        // ---- Step 2: clean up each tweet's text ---------------------------
        stage("Cleaning up links…")
        let adopted = ThreadBuilder.adoptOrphanSelfReplies(
            tweets, ownAccountId: account.accountId, currentUsername: account.username
        )
        if adopted > 0 {
            log("Adopted \(adopted) self-repl(ies) whose parent tweet is gone from the "
                + "archive; they will be published as ordinary tweets.")
        }
        for tweet in tweets {
            LinkExpansion.expandLinks(in: tweet, mediaFolder: ref.mediaFolder)
        }
        log("Expanded t.co links inside of tweets.")

        // ---- Step 3: stitch the tweets into threads -----------------------
        stage("Building threads…")
        let threads = ThreadBuilder.combineThreads(tweets)
        log("Converted those tweets into \(threads.count) threads.")

        return LoadedArchive(
            ref: ref,
            tweets: tweets,
            ownTweetIDs: ownTweetIDs,
            accountId: account.accountId,
            archiveUsername: account.username,
            adoptedOrphans: adopted,
            threads: threads,
            warnings: warnings
        )
    }
}
