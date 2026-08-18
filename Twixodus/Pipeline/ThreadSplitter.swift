// Day One rejects entries with more than 30 attachments, and a single tweet
// can carry up to 4 — so a media-heavy thread must become several entries.
// The split is contiguous and minimal: the fewest parts that fit under the
// limit, balanced by tweet count (an 11-tweet thread becomes 5 + 6, not
// 10 + 1), drifting from an even split only when the attachments demand it.

import Foundation

public enum ThreadSplitter {

    /// Day One's hard cap on attachments per entry.
    public static let maxAttachmentsPerEntry = 30

    /// Splits a thread into contiguous parts that each fit the attachment
    /// limit. Almost every thread comes back whole.
    public static func split(_ thread: TweetThread) -> [TweetThread] {
        let n = thread.count
        var prefix = [0]
        for tweet in thread { prefix.append(prefix[prefix.count - 1] + tweet.mediaFiles.count) }
        let total = prefix[n]
        guard total > maxAttachmentsPerEntry, n > 1 else { return [thread] }

        let minParts = (total + maxAttachmentsPerEntry - 1) / maxAttachmentsPerEntry
        for parts in max(2, minParts)...n {
            if let split = balancedSplit(thread, into: parts, attachmentPrefix: prefix) {
                return split
            }
        }
        // Unreachable with real archives (one tweet has at most 4 attachments,
        // so one-tweet-per-part always fits) — but if a corrupt tweet alone
        // exceeded the limit, let Day One report it instead of dropping media.
        return [thread]
    }

    /// The most even split (by tweet count) of the thread into exactly `parts`
    /// contiguous parts, each within the attachment limit — or nil when the
    /// attachments can't fit into that many parts.
    private static func balancedSplit(
        _ thread: TweetThread, into parts: Int, attachmentPrefix prefix: [Int]
    ) -> [TweetThread]? {
        let n = thread.count
        guard parts <= n else { return nil }
        let ideal = Double(n) / Double(parts)

        // cost[i][j]: the lowest imbalance — sum of (part size − ideal)² —
        // splitting the first i tweets into j valid parts. cut[i][j] remembers
        // where the last of those parts starts.
        var cost = [[Double]](repeating: [Double](repeating: .infinity, count: parts + 1), count: n + 1)
        var cut = [[Int]](repeating: [Int](repeating: 0, count: parts + 1), count: n + 1)
        cost[0][0] = 0

        for j in 1...parts {
            for i in j...n {
                for p in (j - 1)..<i where cost[p][j - 1].isFinite {
                    guard prefix[i] - prefix[p] <= maxAttachmentsPerEntry else { continue }
                    let deviation = Double(i - p) - ideal
                    let candidate = cost[p][j - 1] + deviation * deviation
                    if candidate < cost[i][j] {
                        cost[i][j] = candidate
                        cut[i][j] = p
                    }
                }
            }
        }
        guard cost[n][parts].isFinite else { return nil }

        var bounds = [n]
        for j in stride(from: parts, through: 1, by: -1) {
            bounds.append(cut[bounds[bounds.count - 1]][j])
        }
        let ordered = [Int](bounds.reversed())  // [0, cut, …, n]
        return (1..<ordered.count).map { Array(thread[ordered[$0 - 1]..<ordered[$0]]) }
    }
}
