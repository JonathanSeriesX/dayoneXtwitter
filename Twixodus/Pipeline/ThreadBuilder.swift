// Step 3 of the pipeline: stitch the flat list of tweets into threads.
//
// A thread is a tweet plus every reply-to-self hanging off it. Two jobs live
// here:
//
//   * adoptOrphanSelfReplies() first repairs replies whose parent tweet was
//     deleted before the archive was exported, so they don't end up as broken
//     "Replied to myself" entries;
//   * combineThreads() then groups the tweets into threads, in reading order.
//     Threads always come out whole — fitting a media-heavy thread into Day
//     One's attachment limit is ThreadSplitter's job, at entry-posting time.

import Foundation

public enum ThreadBuilder {

    /// Turns replies-to-self whose parent tweet is missing from the archive
    /// into plain tweets, by stripping their reply markers in place.
    ///
    /// Normally a reply to one's own tweet is threaded under its parent. But if
    /// that parent was deleted before the archive was generated, the reply would
    /// be published as "Replied to <myself>" with a dead conversation link.
    /// Publishing the leftovers as an ordinary tweet (or thread root) is better.
    ///
    /// Detection uses inReplyToUserIdStr against the archive's account ID,
    /// which is stable across username changes; if no account ID is available,
    /// falls back to comparing inReplyToScreenName with currentUsername.
    ///
    /// Returns the number of tweets adopted.
    public static func adoptOrphanSelfReplies(
        _ tweets: [Tweet], ownAccountId: String?, currentUsername: String?
    ) -> Int {
        let archiveIds = Set(tweets.map(\.idStr))
        var adopted = 0

        for tweet in tweets {
            guard let parentId = tweet.inReplyToStatusIdStr, !archiveIds.contains(parentId) else {
                continue
            }

            let isSelfReply: Bool
            if let ownAccountId {
                isSelfReply = tweet.inReplyToUserIdStr == ownAccountId
            } else if let username = currentUsername, !username.isEmpty {
                isSelfReply = (tweet.inReplyToScreenName ?? "").lowercased() == username.lowercased()
            } else {
                isSelfReply = false
            }

            if isSelfReply {
                tweet.inReplyToStatusIdStr = nil
                tweet.inReplyToUserIdStr = nil
                tweet.inReplyToScreenName = nil
                adopted += 1
            }
        }

        return adopted
    }

    /// Groups tweets into chronological threads.
    ///
    /// Returns the threads: each one holds its tweets in reading order — the
    /// root first, then the replies, depth-first, so that when a thread forks,
    /// each branch is emitted contiguously.
    public static func combineThreads(_ tweets: [Tweet]) -> [TweetThread] {
        // --- Step 1: map every tweet's ID to its replies found in the archive ---
        let tweetIds = Set(tweets.map(\.idStr))
        var childrenMap: [String: [Tweet]] = [:]
        var allChildIds = Set<String>()

        for tweet in tweets {
            if let parentId = tweet.inReplyToStatusIdStr, tweetIds.contains(parentId) {
                // Only consider replies where the parent tweet is also in our archive
                childrenMap[parentId, default: []].append(tweet)
                allChildIds.insert(tweet.idStr)
            }
        }

        // --- Step 2: identify and sort the root tweets (oldest ID first) ---
        let sortedRoots = tweets
            .filter { !allChildIds.contains($0.idStr) }
            .stableSorted { (Int($0.idStr) ?? 0) < (Int($1.idStr) ?? 0) }

        // --- Step 3: walk each conversation depth-first into one thread ------
        var finalThreads: [TweetThread] = []

        for root in sortedRoots {
            // The stack holds the conversation chain starting from the root,
            // visited depth-first so that when a thread forks, each branch is
            // emitted contiguously (the full first branch, then the next)
            // instead of interleaving branches level by level.
            var thread: TweetThread = []
            var stack: [Tweet] = [root]

            while let current = stack.popLast() {
                thread.append(current)
                // Push the children in reverse ID order, so the oldest child
                // is popped (and emitted) first.
                let children = childrenMap[current.idStr] ?? []
                stack.append(contentsOf: children.stableSorted {
                    (Int($0.idStr) ?? 0) > (Int($1.idStr) ?? 0)
                })
            }

            finalThreads.append(thread)
        }

        return finalThreads
    }
}
