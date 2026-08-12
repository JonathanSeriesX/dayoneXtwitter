// Step 5a of the pipeline: name what kind of tweet a thread is.
//
// Every thread gets a human-readable category derived from its first tweet:
// "Wrote a thread", "Tweeted", "Replied to <names>", "Retweeted <name>",
// "Quoted <name or myself>", or "Callout to <names>". The category becomes the
// entry's fallback title, and decides which journal the entry lands in
// (replies go to their own journal, see EntryComposer.targetJournal).
//
// Heads-up for maintainers: categorization also cleans the tweet's text in
// place — a retweet's "RT @user:" prefix is stripped while the retweeted user
// is extracted. So threadCategory() must run before the entry text is
// composed, exactly once per thread.

import Foundation

public enum ThreadCategorizer {

    /// What the categorizer needs to know about the archive's owner.
    public struct Context {
        /// IDs of every tweet in the loaded archive, i.e. the user's own
        /// tweets. Quoting one of these is quoting yourself, no matter which
        /// username the account had at the time.
        public let ownTweetIDs: Set<String>
        public let currentUsername: String?

        public init(ownTweetIDs: Set<String>, currentUsername: String?) {
            self.ownTweetIDs = ownTweetIDs
            self.currentUsername = currentUsername
        }
    }

    /// Case-insensitive lookup from screen_name (handle) to real name.
    private static func caseInsensitiveNameMap(_ tweet: Tweet) -> [String: String?] {
        var map: [String: String?] = [:]
        for mention in tweet.userMentions {
            map[mention.screenName.lowercased()] = mention.name
        }
        return map
    }

    /// Python's `name_map.get(handle) or f"@{handle}"`: the @handle fallback
    /// kicks in for a missing entry, a null name, AND an empty-string name.
    private static func displayName(_ map: [String: String?], _ handle: String) -> String {
        if let name = map[handle.lowercased()] ?? nil, !name.isEmpty {
            return name
        }
        return "@\(handle)"
    }

    /// Joins a list of names into a natural-language string.
    /// e.g., ["A", "B", "C"] -> "A, B, and C"
    static func joinNamesNaturalLanguage(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }

    private static let leadingCalloutRegex = PyRegex(#"^\s*["]?\.?@([A-Za-z0-9_]+)["]?\s*"#)

    /// If a tweet (not a reply) begins with one or more @handles (callouts),
    /// extracts each handle in order and returns a natural-language string of
    /// display names: real name if found, otherwise "@handle".
    /// Returns nil when no leading callouts are found.
    static func extractCallouts(_ tweet: Tweet) -> String? {
        let text = tweet.fullText
        let nameMap = caseInsensitiveNameMap(tweet)

        var handles: [String] = []
        var rest = Substring(text)
        // Repeatedly match a leading @handle (with optional surrounding quotes/spaces)
        while let m = leadingCalloutRegex.match(String(rest)) {
            guard let handle = m.group(1) else { break }
            handles.append(handle)
            rest = String(rest)[m.endIndex...]
        }

        if handles.isEmpty { return nil }

        // Look up names case-insensitively and fall back to @handle
        let displayNames = handles.map { displayName(nameMap, $0) }
        return joinNamesNaturalLanguage(displayNames)
    }

    // A word boundary before RT ensures we don't match it as part of another
    // word (e.g., "DIRT"); the required whitespace after RT prevents "RT.".
    // (?s) makes . match newlines, like Python's re.DOTALL.
    private static let retweetRegex = PyRegex(#"(?s)\bRT\s+["]?@([A-Za-z0-9_]+)["]?:\s*(.*)"#)

    /// If fullText contains "RT @handle: ..." (or variations with quotes),
    /// strips the text to just the content after that prefix — in place — and
    /// returns the retweeted user's name (or @handle if not in entities).
    /// Returns nil if no RT found.
    static func extractRetweetInPlace(_ tweet: Tweet) -> String? {
        guard let m = retweetRegex.search(tweet.fullText),
              let handle = m.group(1)
        else { return nil }

        tweet.fullText = m.group(2) ?? ""

        let nameMap = caseInsensitiveNameMap(tweet)
        return displayName(nameMap, handle)
    }

    private static let quoteStatusRegex =
        PyRegex(#"^https?://(?:www\.)?(?:twitter\.com|x\.com)/([^/]+)/status/(\d+)"#)

    /// If the tweet is a quote-tweet, finds the quoted status URL in
    /// entities.urls and returns ("@somebody", "12345").
    /// Returns nil if no quote URL is found.
    static func extractQuoteTarget(_ tweet: Tweet) -> (handle: String, statusId: String)? {
        for urlEntity in tweet.urls {
            guard let expanded = urlEntity.expandedURL else { continue }
            if let m = quoteStatusRegex.match(expanded),
               let user = m.group(1), let statusId = m.group(2) {
                return ("@\(user)", statusId)
            }
        }
        return nil
    }

    /// Names whoever the tweet quotes: "myself" for one's own tweets, otherwise
    /// the @handle from the quoted status URL.
    ///
    /// A quote is "myself" if the quoted tweet ID is in the loaded archive — which
    /// also covers tweets quoted under an old, since-changed username — or if the
    /// handle matches the current username (covers own tweets deleted from the archive).
    private static func describeQuoteTarget(_ tweet: Tweet, context: Context) -> String? {
        guard let (handle, statusId) = extractQuoteTarget(tweet) else { return nil }
        if context.ownTweetIDs.contains(statusId) {
            return "myself"
        }
        if let username = context.currentUsername, !username.isEmpty,
           handle.lowercased() == "@\(username)".lowercased() {
            return "myself"
        }
        return handle
    }

    private static let handleRegex = PyRegex(#"@([A-Za-z0-9_]+)"#)

    /// Categorizes a reply tweet by extracting all @handles from fullText
    /// in order, then mapping each to its real name if present in entities,
    /// or falling back to the @nickname.
    private static func replyCategory(_ tweet: Tweet) -> String {
        guard tweet.inReplyToStatusIdStr != nil else { return "Not a reply" }

        let nameMap = caseInsensitiveNameMap(tweet)

        // Extract handles in the order they appear from the fullText, so the
        // order of names in the "Replied to" string matches the tweet.
        // Duplicates are removed while preserving order.
        var seen = Set<String>()
        var handles: [String] = []
        for m in handleRegex.findAll(tweet.fullText) {
            guard let handle = m.group(1) else { continue }
            if !seen.contains(handle) {
                handles.append(handle)
                seen.insert(handle)
            }
        }

        // If no handles found in text, fall back to inReplyToScreenName
        if handles.isEmpty, let screenName = tweet.inReplyToScreenName, !screenName.isEmpty {
            handles = [screenName]
        }

        if handles.isEmpty { return "Not a reply" }

        let displayNames = handles.map { displayName(nameMap, $0) }
        return "Replied to \(joinNamesNaturalLanguage(displayNames))"
    }

    /// Categorizes a tweet thread based on the characteristics of its first
    /// tweet: 'Wrote a thread' (multiple tweets), 'Retweeted ...',
    /// 'Quoted ...', 'Replied to ...', 'Callout to ...', or a plain 'Tweeted'.
    public static func threadCategory(_ thread: TweetThread, context: Context) -> String {
        guard let first = thread.first else {
            return "Empty threat"  // again, we should just segfault at this point
        }

        // A direct retweet starts with "RT @" (or the quoted variation).
        let isRetweet = first.fullText.hasPrefix("RT @") || first.fullText.hasPrefix("RT \"@")

        let isReply = first.inReplyToStatusIdStr != nil
        let isCallout = !isReply
            && (first.fullText.hasPrefix("@") || first.fullText.hasPrefix(".@"))

        // Check for Twitter/X links in urls entities that are NOT media URLs.
        // This helps identify quote tweets that are not explicitly marked with
        // 'quoted_status_id_str'. Media t.co URLs are excluded so media links
        // aren't incorrectly identified as quote tweets.
        var mediaUrlsTco = Set(first.extendedMedia?.compactMap(\.url) ?? [])
        if mediaUrlsTco.isEmpty {
            mediaUrlsTco = Set(first.entitiesMedia.compactMap(\.url))
        }

        var hasNonMediaTwitterLink = false
        for urlEntity in first.urls {
            guard let expanded = urlEntity.expandedURL else { continue }
            // A link counts if it points to twitter.com or x.com and its t.co
            // URL is not one of the media t.co URLs.
            if (expanded.contains("https://twitter.com") || expanded.contains("https://x.com")),
               !(urlEntity.url.map { mediaUrlsTco.contains($0) } ?? false) {
                hasNonMediaTwitterLink = true
                break
            }
        }

        // Categorize based on tweet properties, with more specific categories first.

        // A single tweet starting with "RT @", and not part of a larger thread, is a retweet.
        if isRetweet {
            let name = extractRetweetInPlace(first)
            return "Retweeted \(name ?? "None")"  // "None": faithful to the Python original
        }

        // A tweet with a non-media Twitter/X link and not a reply is a quote tweet.
        if hasNonMediaTwitterLink && !isReply {
            let name = describeQuoteTarget(first, context: context)
            return "Quoted \(name ?? "None")"
        }

        if first.fullText.contains(" RT @") {
            let name = describeQuoteTarget(first, context: context)
            return "Quoted \(name ?? "None")"
        }

        if isReply {
            return replyCategory(first)
        }

        if isCallout {
            return "Callout to \(extractCallouts(first) ?? "[]")"
        }

        // A thread with more than one tweet is always a thread of one's own.
        if thread.count > 1 {
            return "Wrote a thread"
        }

        return "Tweeted"
    }
}
