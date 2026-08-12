// Step 3 of the pipeline: stitch the flat list of tweets into threads.
//
// A thread is a tweet plus every reply-to-self hanging off it. Two jobs live
// here:
//
//   * adoptOrphanSelfReplies() first repairs replies whose parent tweet was
//     deleted before the archive was exported, so they don't end up as broken
//     "Replied to myself" entries;
//   * combineThreads() then groups the tweets into threads, in reading order,
//     splitting a thread that carries more media files than one Day One entry
//     can hold.

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

    /// Counts the number of media items in a single tweet.
    /// extended_entities is preferred as it includes all media, even in quote
    /// tweets; entities is the fallback when it's not present.
    static func countMedia(_ tweet: Tweet) -> Int {
        tweet.mediaForCounting.count
    }

    /// Groups tweets into chronological threads, splitting a thread if its
    /// cumulative media count exceeds mediaLimit.
    ///
    /// When a thread is split, the tweet that would have exceeded the limit
    /// becomes the starting tweet of the next thread segment.
    ///
    /// Returns the threads: each one holds its tweets in reading order — the
    /// root first, then the replies, depth-first, so that when a thread forks,
    /// each branch is emitted contiguously.
    public static func combineThreads(_ tweets: [Tweet], mediaLimit: Int = 26) -> [TweetThread] {
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

        // --- Step 3: build the threads, splitting on the media limit ---
        var finalThreads: [TweetThread] = []
        // Tweets already assigned to a thread, to avoid reprocessing.
        var processedIds = Set<String>()

        for root in sortedRoots {
            // If this "root" was already processed as part of another thread
            // that got split, skip it.
            if processedIds.contains(root.idStr) { continue }

            // This stack holds all tweets in the conversation chain starting
            // from the root, visited depth-first so that when a thread forks,
            // each branch is emitted contiguously (the full first branch, then
            // the next) instead of interleaving branches level by level.
            // Chronologically-first branches come first. We drain the stack,
            // starting a new thread segment whenever the media limit is hit.
            var superThreadStack: [Tweet] = [root]

            while !superThreadStack.isEmpty {
                // Start a new thread segment
                var currentSegment: TweetThread = []
                var mediaCountInSegment = 0

                // Build the segment until the stack is empty or the media limit is reached
                while let nextTweet = superThreadStack.last {
                    let mediaInNextTweet = countMedia(nextTweet)

                    // SPLIT CONDITION:
                    // If the segment is not empty and adding the next tweet would
                    // exceed the limit. A non-empty check is vital so a tweet with
                    // many media files can still start its own thread.
                    if !currentSegment.isEmpty,
                       mediaCountInSegment + mediaInNextTweet > mediaLimit {
                        // Stop building this segment. nextTweet becomes the start
                        // of the next segment in the next outer loop iteration.
                        break
                    }

                    // The tweet fits. Pop it from the stack and process it.
                    let currentTweet = superThreadStack.removeLast()
                    currentSegment.append(currentTweet)
                    processedIds.insert(currentTweet.idStr)
                    mediaCountInSegment += mediaInNextTweet

                    // Find its children and push them onto the stack in reverse ID
                    // order, so the oldest child is popped (and emitted) first.
                    let children = childrenMap[currentTweet.idStr] ?? []
                    let sortedChildren = children.stableSorted {
                        (Int($0.idStr) ?? 0) > (Int($1.idStr) ?? 0)
                    }
                    superThreadStack.append(contentsOf: sortedChildren)
                }

                if !currentSegment.isEmpty {
                    finalThreads.append(currentSegment)
                }
            }
        }

        return finalThreads
    }
}
