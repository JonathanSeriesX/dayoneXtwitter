// Applies the hydration store to the loaded archive, in place — the same
// mutate-the-Tweet approach the rest of the pipeline uses. Runs right after
// LinkExpansion when an archive with an existing store is opened, and again
// after every Retrieve run. Applying it twice is safe: every rewrite is
// computed from the store, never from the current text.
//
//   * A truncated retweet's text is rebuilt in full from the retrieved
//     original — links expanded to Markdown, media t.co links replaced with
//     Day One [{attachment}] placeholders — and its attachments point into
//     the store's media folder.
//   * A quote tweet gets its retrieved quoted tweet attached (rendered as a
//     blockquote by EntryComposer), and the bare status link the archive left
//     at the end of the text is dropped in its favor.
//   * Archive-referenced media files that are missing on disk are repointed
//     at the store's downloaded copies.

import Foundation

public enum HydrationOverlay {

    public struct Applied {
        public var retweets = 0
        public var quotes = 0
        public var mediaFiles = 0
        public var isEmpty: Bool { retweets == 0 && quotes == 0 && mediaFiles == 0 }
    }

    @discardableResult
    public static func apply(tweets: [Tweet], store: HydrationStore) -> Applied {
        var applied = Applied()
        let fm = FileManager.default

        for tweet in tweets {
            if let record = store.retweets[tweet.idStr], record.isOK, let data = record.tweet {
                rebuildRetweet(tweet, from: data, store: store)
                applied.retweets += 1
            }

            if !tweet.isRetweet,
               let (_, statusId) = ThreadCategorizer.extractQuoteTarget(tweet),
               let record = store.quotes[statusId], record.isOK, let data = record.tweet {
                tweet.hydratedQuote = HydratedQuote(
                    statusId: statusId,
                    screenName: data.screenName,
                    name: data.displayName,
                    createdAt: data.createdAtDate,
                    text: cleanedText(data, dropMedia: true)
                )
                stripTrailingQuoteLink(tweet, statusId: statusId)
                applied.quotes += 1
            }

            for (index, path) in tweet.mediaFiles.enumerated() where !fm.fileExists(atPath: path) {
                let substitute = store.mediaPath((path as NSString).lastPathComponent)
                if fm.fileExists(atPath: substitute.path) {
                    tweet.mediaFiles[index] = substitute.path
                    applied.mediaFiles += 1
                }
            }
        }

        return applied
    }

    // MARK: - Retweets

    /// Replaces the cut-off "RT @user: …" text with the retrieved original,
    /// keeping the RT prefix if the tweet still carries one (categorization
    /// strips it later, in place — see ThreadCategorizer).
    private static func rebuildRetweet(_ tweet: Tweet, from data: HydratedTweetData, store: HydrationStore) {
        var files: [String] = []
        var text = expandURLs(in: data.text, urls: data.urls)

        // Group the attachments by their t.co placeholder, like LinkExpansion:
        // a multi-photo tweet repeats one t.co for all its photos.
        var order: [String] = []
        var byTco: [String: [HydratedMediaFile]] = [:]
        for item in data.media {
            let key = item.tco ?? ""
            if byTco[key] == nil { order.append(key) }
            byTco[key, default: []].append(item)
        }

        for tco in order {
            let downloaded = (byTco[tco] ?? []).compactMap { item -> String? in
                guard let fileName = item.fileName else { return nil }
                let path = store.mediaPath(fileName).path
                return FileManager.default.fileExists(atPath: path) ? path : nil
            }
            files.append(contentsOf: downloaded)
            let placeholders = String(repeating: "[{attachment}]", count: downloaded.count)
            if !tco.isEmpty, text.contains(tco) {
                text = text.replacingOccurrences(of: tco, with: placeholders, options: .literal)
            } else if !placeholders.isEmpty {
                text += " \(placeholders)"
            }
        }

        let keepPrefix = tweet.fullText.hasPrefix("RT @") || tweet.fullText.hasPrefix("RT \"@")
        tweet.fullText = (keepPrefix ? "RT @\(data.screenName): \(text)" : text).pyStrip()
        tweet.mediaFiles = files
    }

    // MARK: - Quotes

    /// The retrieved tweet's text with its links expanded and, optionally, its
    /// trailing media t.co links dropped (a blockquote can't show them anyway;
    /// the quote's header links to the original).
    private static func cleanedText(_ data: HydratedTweetData, dropMedia: Bool) -> String {
        var text = expandURLs(in: data.text, urls: data.urls)
        if dropMedia {
            for item in data.media {
                if let tco = item.tco {
                    text = text.replacingOccurrences(of: tco, with: "", options: .literal)
                }
            }
        }
        return text.pyStrip()
    }

    private static func expandURLs(in text: String, urls: [HydratedURL]) -> String {
        var result = text
        for url in urls.stableSorted(by: { $0.tco.count > $1.tco.count }) {
            let label = url.display ?? url.expanded
            result = result.replacingOccurrences(
                of: url.tco, with: "[\(label)](\(url.expanded))", options: .literal)
        }
        return result
    }

    /// Drops the quoted-status link when it's the last thing in the tweet —
    /// the blockquote that replaces it carries the same link. A link in the
    /// middle of a sentence stays: the text needs it to read well.
    private static func stripTrailingQuoteLink(_ tweet: Tweet, statusId: String) {
        let pattern = PyRegex(
            #"\s*\[[^\]\n]*\]\(https?://[^)\s]*/status(?:es)?/"# + statusId + #"[^)]*\)\s*$"#
        )
        let stripped = pattern.sub("", tweet.fullText)
        if stripped != tweet.fullText {
            tweet.fullText = stripped.pyStrip()
        }
    }
}
