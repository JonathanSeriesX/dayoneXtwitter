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

    /// Matches status links across the site's eras: twitter.com and x.com,
    /// the mobile. subdomain, the 2010s "#!/" hashbang paths, and the old
    /// "/statuses/" form — all of which appear in real archives.
    private static let quoteStatusRegex =
        PyRegex(#"^https?://(?:www\.|mobile\.)?(?:twitter\.com|x\.com)/(?:#!/)?([^/]+)/status(?:es)?/(\d+)"#)

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

    private static let inlineRetweetHandleRegex = PyRegex(#"(?s)\bRT\s+["]?@([A-Za-z0-9_]+)"#)

    /// Last-ditch name recovery for old-style manual retweets whose structure
    /// defeats the stricter extractors (e.g. no colon after the handle):
    /// grabs the first @handle following an "RT" marker, reading the text
    /// without mutating it. Returns nil when the RT names nobody ("RT : …").
    private static func inlineRetweetHandle(_ tweet: Tweet) -> String? {
        inlineRetweetHandleRegex.search(tweet.fullText).flatMap { $0.group(1) }
    }

    /// Names the quoted author when there is no parseable status URL — the
    /// pre-quote-tweet era's manual "… RT @user: …" quotes. Falls back to
    /// "someone" so the title never reads "Quoted None".
    private static func fallbackQuoteTarget(_ tweet: Tweet, context: Context) -> String {
        guard let handle = inlineRetweetHandle(tweet) else { return "someone" }
        if let username = context.currentUsername, !username.isEmpty,
           handle.lowercased() == username.lowercased() {
            return "myself"
        }
        return "@\(handle)"
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

    /// Whether the thread would be categorized as a retweet — a direct retweet
    /// starts with "RT @" (or the quoted variation). Read-only, so it can be
    /// used at archive load, before categorization strips the prefix in place.
    public static func isDirectRetweet(_ thread: TweetThread) -> Bool {
        guard let first = thread.first else { return false }
        return first.fullText.hasPrefix("RT @") || first.fullText.hasPrefix("RT \"@")
    }

    /// What a thread is, as far as the journal it lands in is concerned.
    /// threadCategory() branches on this, and so can callers that must NOT
    /// categorize — kind() is read-only, while categorization rewrites the
    /// tweet's text in place and may run only once per thread.
    public enum ThreadKind {
        case retweet
        case quote
        case reply
        /// The user's own: a thread, a callout, or a plain tweet.
        case own
    }

    /// Whether the tweet carries a Twitter/X link that isn't one of its own
    /// media placeholders — the marker of a quote tweet in archives that
    /// predate quoted_status_id_str.
    private static func hasNonMediaTwitterLink(_ tweet: Tweet) -> Bool {
        var mediaUrlsTco = Set(tweet.extendedMedia?.compactMap(\.url) ?? [])
        if mediaUrlsTco.isEmpty {
            mediaUrlsTco = Set(tweet.entitiesMedia.compactMap(\.url))
        }
        for urlEntity in tweet.urls {
            guard let expanded = urlEntity.expandedURL else { continue }
            if (expanded.contains("https://twitter.com") || expanded.contains("https://x.com")),
               !(urlEntity.url.map { mediaUrlsTco.contains($0) } ?? false) {
                return true
            }
        }
        return false
    }

    /// Whether replyCategory() will find anyone to name. When it can't, the
    /// thread isn't treated as a reply at all (it keeps a plain title and the
    /// ordinary journal), so kind() must agree.
    private static func replyNamesSomeone(_ tweet: Tweet) -> Bool {
        if handleRegex.search(tweet.fullText) != nil { return true }
        return !(tweet.inReplyToScreenName ?? "").isEmpty
    }

    /// Categorizes a thread without touching it. The branch order is
    /// threadCategory()'s, which is the point: both must agree on which
    /// journal a thread is bound for.
    public static func kind(_ thread: TweetThread) -> ThreadKind {
        guard let first = thread.first else { return .own }

        if isDirectRetweet(thread) { return .retweet }

        let isReply = first.inReplyToStatusIdStr != nil
        if hasNonMediaTwitterLink(first) && !isReply { return .quote }
        if first.fullText.contains(" RT @") { return .quote }
        if isReply && replyNamesSomeone(first) { return .reply }

        return .own
    }

    /// Whether the run will skip this thread outright because of the config:
    /// a retweet with retweets off, a reply with no reply journal. Read-only,
    /// so the Retrieve step can ask before anything is categorized.
    public static func isSkippedByConfig(_ thread: TweetThread, config: ImportConfig) -> Bool {
        switch kind(thread) {
        case .retweet: return config.ignoreRetweets
        case .reply: return config.replyJournalName == nil
        case .quote, .own: return false
        }
    }

    /// Categorizes a tweet thread based on the characteristics of its first
    /// tweet: 'Wrote a thread' (multiple tweets), 'Retweeted ...',
    /// 'Quoted ...', 'Replied to ...', 'Callout to ...', or a plain 'Tweeted'.
    public static func threadCategory(_ thread: TweetThread, context: Context) -> String {
        guard let first = thread.first else {
            return "Empty threat"  // again, we should just segfault at this point
        }

        // Which branch to take is kind()'s call — read-only, and shared with
        // the callers that need the journal without categorizing. Only the
        // naming (and the RT prefix strip) happens here.
        switch kind(thread) {
        case .retweet:
            if let name = extractRetweetInPlace(first) {
                return "Retweeted \(name)"
            }
            // The strict extractor failed (no colon after the handle, say) —
            // recover the handle read-only so the title still names someone.
            if let handle = inlineRetweetHandle(first) {
                return "Retweeted \(displayName(caseInsensitiveNameMap(first), handle))"
            }
            return "Retweeted someone"

        case .quote:
            let name = describeQuoteTarget(first, context: context)
            return "Quoted \(name ?? fallbackQuoteTarget(first, context: context))"

        case .reply:
            return replyCategory(first)

        case .own:
            // A bare "@" with nothing readable after it isn't a callout — it's
            // just a tweet that happens to start with the character.
            let isReply = first.inReplyToStatusIdStr != nil
            let isCallout = !isReply
                && (first.fullText.hasPrefix("@") || first.fullText.hasPrefix(".@"))
            if isCallout, let callouts = extractCallouts(first) {
                return "Callout to \(callouts)"
            }
            // A thread with more than one tweet is always a thread of one's own.
            if thread.count > 1 {
                return "Wrote a thread"
            }
            return "Tweeted"
        }
    }
}
