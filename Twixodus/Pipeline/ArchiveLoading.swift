// Steps 1–3 of the pipeline, bundled for the app: find the archive, read
// every tweet, clean the text up, and stitch the tweets into threads. This
// runs once when the user drops an archive; steps 4–7 (selection and the
// actual import) run later, every time the Import button is pressed.

import Foundation

/// A fully loaded archive: everything the import runs need, computed once.
public struct LoadedArchive: Sendable {
    public let ref: TwitterArchiveRef
    public let tweets: [Tweet]
    public let ownTweetIDs: Set<String>
    public let accountId: String?
    public let archiveUsername: String?
    public let adoptedOrphans: Int
    public let threads: [TweetThread]
    /// How many of the threads are direct retweets — counted at load time,
    /// because categorization later strips the "RT @" prefixes in place.
    public let retweetThreads: Int
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
            // Flag retweets from the RAW text — the pipeline rewrites fullText
            // in place, so the Retrieve step can't re-derive this later.
            tweet.isRetweet = ThreadCategorizer.isDirectRetweet([tweet])
            tweet.isTruncatedRetweet = tweet.isRetweet && looksTruncated(tweet.fullText)
            LinkExpansion.expandLinks(in: tweet, mediaFolder: ref.mediaFolder)
        }
        log("Expanded t.co links inside of tweets.")

        // Anything the Retrieve step fetched on an earlier run is applied
        // right away — offline, straight from the hydration folder.
        let hydration = HydrationStore(for: ref)
        if hydration.exists {
            hydration.load()
            let applied = HydrationOverlay.apply(tweets: tweets, store: hydration)
            if !applied.isEmpty {
                log("Applied earlier retrievals from \(hydration.folder.lastPathComponent): "
                    + "\(applied.retweets) retweet\(applied.retweets == 1 ? "" : "s") un-truncated, "
                    + "\(applied.quotes) quoted tweet\(applied.quotes == 1 ? "" : "s") attached, "
                    + "\(applied.mediaFiles) media file\(applied.mediaFiles == 1 ? "" : "s") restored.")
            }
        }

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
            retweetThreads: threads.filter(ThreadCategorizer.isDirectRetweet).count,
            warnings: warnings
        )
    }

    /// Whether a retweet's raw text was cut at 140 chars. Old Twitter always
    /// marks the cut with an ellipsis (sometimes cutting a t.co link in half
    /// on the way out). A retweet whose author happened to END on "..." gets
    /// fetched too — harmless, the retrieved text is simply the same.
    static func looksTruncated(_ rawText: String) -> Bool {
        let trimmed = rawText.pyStrip()
        return trimmed.hasSuffix("…") || trimmed.hasSuffix("...")
    }
}
