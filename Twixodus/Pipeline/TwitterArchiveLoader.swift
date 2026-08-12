// Step 1 of the pipeline: find the Twitter archive and read every tweet.
//
// An unpacked Twitter archive is a folder named twitter-<YYYY-MM-DD>-<hash>.
// The tweets live in <archive>/data/ — in a single tweets.js, or split into
// tweets.js, tweets-part1.js, tweets-part2.js, ... when the archive is large.
// Threads regularly span that split, so every part is always loaded before
// threads are assembled.

import Foundation

public enum ArchiveError: LocalizedError {
    case notFound(searched: String)
    case unreadable(file: String, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let searched):
            return "Couldn't find data/tweets.js in \(searched). "
                + "Drop your Twitter archive (the .zip, or the unpacked folder)."
        case .unreadable(let file, let underlying):
            return "Couldn't read \(file): \(underlying)"
        }
    }
}

public enum TwitterArchiveLoader {

    // MARK: - Finding the archive

    /// Finds the archive at (or inside) the given folder.
    ///
    /// Accepts either the archive root itself (a folder with data/tweets.js in
    /// it) or a folder holding one or more twitter-* archives — in that case
    /// the newest one wins, since the folder name embeds the export date.
    public static func findArchive(at root: URL) throws -> TwitterArchiveRef {
        let fm = FileManager.default

        var dataFolder: URL?
        let direct = root.appendingPathComponent("data")
        if fm.fileExists(atPath: direct.appendingPathComponent("tweets.js").path) {
            dataFolder = direct
        } else {
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]))
                ?? []
            let candidates = children
                .filter { $0.lastPathComponent.hasPrefix("twitter-") }
                .filter { fm.fileExists(atPath: $0.appendingPathComponent("data/tweets.js").path) }
            // The folder name embeds the export date, so the lexically largest
            // folder name is the newest export.
            dataFolder = candidates
                .max { $0.lastPathComponent < $1.lastPathComponent }?
                .appendingPathComponent("data")
        }

        guard let dataFolder else {
            throw ArchiveError.notFound(searched: root.path)
        }

        let partPattern = PyRegex(#"^tweets-part(\d+)\.js$"#)
        let all = (try? fm.contentsOfDirectory(at: dataFolder, includingPropertiesForKeys: nil)) ?? []
        let parts = all
            .filter { $0.lastPathComponent == "tweets.js" || partPattern.match($0.lastPathComponent) != nil }
            .stableSorted { partNumber($0) < partNumber($1) }

        return TwitterArchiveRef(dataFolder: dataFolder, tweetsJSPaths: parts)
    }

    /// Sort key for archive parts: tweets.js is part 0, tweets-part<N>.js is part N.
    private static func partNumber(_ url: URL) -> Int {
        let pattern = PyRegex(#"^tweets-part(\d+)\.js$"#)
        if let m = pattern.match(url.lastPathComponent), let n = Int(m.group(1) ?? "") {
            return n
        }
        return 0
    }

    // MARK: - Loading the tweets

    /// Loads and combines tweets from every tweets*.js part of the archive.
    /// Returns the tweets plus the set of their IDs (the user's own tweets) —
    /// ThreadCategorizer reads that set to say "Quoted myself".
    public static func loadTweets(from archive: TwitterArchiveRef,
                                  log: (String) -> Void = { _ in }) throws -> (tweets: [Tweet], ownTweetIDs: Set<String>) {
        var tweets: [Tweet] = []
        for path in archive.tweetsJSPaths {
            tweets.append(contentsOf: try loadTweetsFromFile(path, log: log))
        }
        let ownIDs = Set(tweets.map(\.idStr))
        return (tweets, ownIDs)
    }

    /// The archive's date format: "Fri Mar 21 04:40:00 +0000 2006".
    private static let createdAtFormatter = PipelineDates.formatter("EEE MMM dd HH:mm:ss Z yyyy")

    /// Loads the tweets from one tweets*.js file.
    ///
    /// The file is JavaScript, not JSON: a `window.YTD.tweets.partN = ` prefix
    /// followed by a JSON array. Everything before the first '[' is cut off.
    static func loadTweetsFromFile(_ url: URL, log: (String) -> Void = { _ in }) throws -> [Tweet] {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ArchiveError.unreadable(file: url.path, underlying: error.localizedDescription)
        }

        guard let start = content.firstIndex(of: "[") else {
            log("Error: JSON data could not be located in \(url.lastPathComponent).")
            return []
        }

        let jsonData = Data(content[start...].utf8)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: jsonData)
        } catch {
            log("JSON decoding failed in \(url.lastPathComponent): \(error.localizedDescription)")
            return []
        }

        guard let items = parsed as? [[String: Any]] else {
            log("Error: unexpected JSON shape in \(url.lastPathComponent).")
            return []
        }

        return items.compactMap { wrapper in
            guard let tweetDict = wrapper["tweet"] as? [String: Any] else { return nil }
            return parseTweet(tweetDict)
        }
    }

    private static func parseTweet(_ dict: [String: Any]) -> Tweet? {
        guard
            let idStr = dict["id_str"] as? String,
            let createdAtStr = dict["created_at"] as? String,
            let createdAt = createdAtFormatter.date(from: createdAtStr)
        else { return nil }

        let entities = dict["entities"] as? [String: Any] ?? [:]
        let extendedEntities = dict["extended_entities"] as? [String: Any]

        let urls = (entities["urls"] as? [[String: Any]] ?? []).map { u in
            URLEntity(
                url: u["url"] as? String,
                expandedURL: u["expanded_url"] as? String,
                displayURL: u["display_url"] as? String
            )
        }

        let hashtags = (entities["hashtags"] as? [[String: Any]] ?? [])
            .compactMap { $0["text"] as? String }

        let mentions = (entities["user_mentions"] as? [[String: Any]] ?? []).compactMap { m -> UserMention? in
            guard let screenName = m["screen_name"] as? String else { return nil }
            return UserMention(screenName: screenName, name: m["name"] as? String)
        }

        var coordinate: (latitude: Double, longitude: Double)?
        if let coords = dict["coordinates"] as? [String: Any],
           let pair = coords["coordinates"] as? [Any], pair.count >= 2,
           let longitude = asDouble(pair[0]), let latitude = asDouble(pair[1]) {
            coordinate = (latitude: latitude, longitude: longitude)
        }

        return Tweet(
            idStr: idStr,
            fullText: dict["full_text"] as? String ?? "",
            createdAt: createdAt,
            favoriteCount: asInt(dict["favorite_count"]) ?? 0,
            retweetCount: asInt(dict["retweet_count"]) ?? 0,
            source: dict["source"] as? String,
            inReplyToStatusIdStr: dict["in_reply_to_status_id_str"] as? String,
            inReplyToUserIdStr: dict["in_reply_to_user_id_str"] as? String,
            inReplyToScreenName: dict["in_reply_to_screen_name"] as? String,
            urls: urls,
            hashtags: hashtags,
            userMentions: mentions,
            entitiesMedia: parseMedia(entities["media"]),
            extendedMedia: extendedEntities.map { parseMedia($0["media"]) },
            coordinate: coordinate
        )
    }

    private static func parseMedia(_ raw: Any?) -> [MediaEntity] {
        (raw as? [[String: Any]] ?? []).map { m in
            let variants = ((m["video_info"] as? [String: Any])?["variants"] as? [[String: Any]] ?? [])
                .map { v in
                    VideoVariant(
                        contentType: v["content_type"] as? String,
                        bitrate: v["bitrate"] as? String,
                        url: v["url"] as? String
                    )
                }
            return MediaEntity(
                url: m["url"] as? String,
                type: m["type"] as? String,
                mediaURLHTTPS: m["media_url_https"] as? String,
                videoVariants: variants
            )
        }
    }

    private static func asInt(_ value: Any?) -> Int? {
        if let s = value as? String { return Int(s) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private static func asDouble(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    // MARK: - Account metadata

    public struct AccountInfo {
        public let accountId: String?
        public let username: String?
    }

    /// Reads the account ID and username from the archive's account.js. The ID
    /// is stable across username changes; returns nils if unavailable.
    public static func loadAccountInfo(from archive: TwitterArchiveRef) -> AccountInfo {
        guard let content = try? String(contentsOf: archive.accountJSPath, encoding: .utf8),
              let start = content.firstIndex(of: "["),
              let parsed = try? JSONSerialization.jsonObject(with: Data(content[start...].utf8)),
              let accounts = parsed as? [[String: Any]],
              let account = accounts.first?["account"] as? [String: Any]
        else {
            return AccountInfo(accountId: nil, username: nil)
        }
        return AccountInfo(
            accountId: account["accountId"] as? String,
            username: account["username"] as? String
        )
    }
}
