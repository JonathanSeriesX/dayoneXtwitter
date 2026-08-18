// The Retrieve step's scan: walks the loaded archive against the hydration
// store and lists what a retrieval run could fetch —
//
//   * truncated retweets (the archive cut them at 140 chars, and their media
//     entities fell off entirely),
//   * quoted tweets (only their URL is in the archive, not their content),
//   * media files the archive references but doesn't contain (Twitter's
//     exporter routinely drops videos; the URLs still work).
//
// Everything already in the store — including tombstoned tweets, which would
// come back tombstoned again — is counted as done, so re-runs are incremental.

import Foundation

public struct HydrationPlan {

    /// A file the archive references but doesn't contain, with a live URL.
    public struct MediaItem {
        public let tweetId: String
        public let fileName: String  // "<tweet id>-<file>", the archive's convention
        public let sourceURL: String
    }

    public var pendingRetweets: [Tweet] = []
    public var retweetsDone = 0

    /// Distinct quoted status IDs to fetch, with the @handle for the logs.
    public var pendingQuotes: [(statusId: String, handle: String)] = []
    public var quotesDone = 0
    public var quotesUnavailable = 0

    public var pendingMedia: [MediaItem] = []
    public var mediaDone = 0

    public var totalPending: Int {
        pendingRetweets.count + pendingQuotes.count + pendingMedia.count
    }

    public var retweetsTotal: Int { pendingRetweets.count + retweetsDone }
    public var quotesTotal: Int { pendingQuotes.count + quotesDone }
    public var mediaTotal: Int { pendingMedia.count + mediaDone }
}

public enum HydrationPlanner {

    /// Scans the archive's tweets against the store.
    public static func plan(
        tweets: [Tweet],
        ownTweetIDs: Set<String>,
        archiveUsername: String?,
        store: HydrationStore
    ) -> HydrationPlan {
        var plan = HydrationPlan()
        var quotesSeen = Set<String>()
        let fm = FileManager.default

        for tweet in tweets {
            // -- Truncated retweets ------------------------------------------
            if tweet.isTruncatedRetweet {
                if store.retweets[tweet.idStr] != nil {
                    plan.retweetsDone += 1
                } else {
                    plan.pendingRetweets.append(tweet)
                }
            }

            // -- Quoted tweets ------------------------------------------------
            // A retweet's quote link belongs to the retweeted author's text,
            // not ours — skipped. Quotes of one's own tweets are skipped too:
            // their content is already in the archive.
            if !tweet.isRetweet,
               let (handle, statusId) = ThreadCategorizer.extractQuoteTarget(tweet),
               !ownTweetIDs.contains(statusId),
               !isOwnHandle(handle, archiveUsername: archiveUsername) {
                if let record = store.quotes[statusId] {
                    if record.isOK {
                        plan.quotesDone += 1
                    } else {
                        plan.quotesUnavailable += 1
                    }
                } else if !quotesSeen.contains(statusId) {
                    quotesSeen.insert(statusId)
                    plan.pendingQuotes.append((statusId, handle))
                }
            }

            // -- Missing media -----------------------------------------------
            for path in tweet.mediaFiles {
                if fm.fileExists(atPath: path) {
                    // Already substituted from the hydration folder on an
                    // earlier run — count it as retrieved, not as fine.
                    if path.hasPrefix(store.folder.path) {
                        plan.mediaDone += 1
                    }
                    continue
                }
                let fileName = (path as NSString).lastPathComponent
                if fm.fileExists(atPath: store.mediaPath(fileName).path) {
                    plan.mediaDone += 1
                    continue
                }
                if let source = archiveSourceURL(tweet: tweet, fileName: fileName) {
                    plan.pendingMedia.append(HydrationPlan.MediaItem(
                        tweetId: tweet.idStr, fileName: fileName, sourceURL: source))
                }
            }
        }

        return plan
    }

    private static func isOwnHandle(_ handle: String, archiveUsername: String?) -> Bool {
        guard let username = archiveUsername, !username.isEmpty else { return false }
        return handle.lowercased() == "@\(username)".lowercased()
    }

    /// Recovers the download URL for an archive-referenced file from the
    /// tweet's own media entities — the exporter kept the URLs even when it
    /// dropped the files. Matches LinkExpansion's file-name derivation, best
    /// MP4 for videos, plus original size for photos.
    static func archiveSourceURL(tweet: Tweet, fileName: String) -> String? {
        var mediaEntities = tweet.extendedMedia ?? []
        if mediaEntities.isEmpty {
            mediaEntities = tweet.entitiesMedia
        }

        for media in mediaEntities {
            if media.type == "photo" {
                guard let mediaURL = media.mediaURLHTTPS else { continue }
                if derivedName(tweet: tweet, url: mediaURL, isVideo: false) == fileName {
                    return mediaURL + "?name=orig"
                }
            } else if media.type == "video" || media.type == "animated_gif" {
                let mp4s = media.videoVariants.compactMap { variant -> (Int, String)? in
                    guard variant.contentType == "video/mp4",
                          let bitrate = Int(variant.bitrate ?? ""),
                          let url = variant.url
                    else { return nil }
                    return (bitrate, url)
                }
                guard let best = mp4s.max(by: { $0.0 < $1.0 })?.1 else { continue }
                if derivedName(tweet: tweet, url: best, isVideo: true) == fileName {
                    return best
                }
            }
        }
        return nil
    }

    /// "<tweet id>-<basename>", exactly as LinkExpansion derives it.
    private static func derivedName(tweet: Tweet, url: String, isVideo: Bool) -> String {
        var name = (url as NSString).lastPathComponent
        if let q = name.firstIndex(of: "?") {
            name = String(name[..<q])
        }
        if isVideo {
            name = ((name as NSString).deletingPathExtension) + ".mp4"
        }
        return "\(tweet.idStr)-\(name)"
    }
}
