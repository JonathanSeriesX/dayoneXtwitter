// The data types that flow through Twixodus.
//
// The importer is a straight pipeline. Data changes shape a few times on its
// way from the Twitter archive to Day One, and every shape is defined here:
//
//     tweets.js files ──(1 TwitterArchiveLoader)──▶  [Tweet]
//     [Tweet]         ──(2 LinkExpansion)─────────▶  the same Tweets, text cleaned up
//     [Tweet]         ──(3 ThreadBuilder)─────────▶  [TweetThread]
//     [TweetThread]   ──(4 ThreadSelection)───────▶  [PlannedImport]
//     PlannedImport   ──(5 ImportEngine)──────────▶  EntryContent ─▶ entry in Day One
//     each success    ─────────────────────────────▶  ImportedEntry (for the report)

import Foundation

/// One tweet from tweets.js. The archive wraps every tweet in an extra
/// `{"tweet": {...}}` dict; the loader unwraps it into this class. It is a
/// reference type on purpose: the pipeline mutates tweets in place, exactly
/// like the original script mutated the raw dicts —
///   * LinkExpansion rewrites `fullText` and fills `mediaFiles`,
///   * ThreadBuilder strips the reply markers off orphaned self-replies,
///   * ThreadCategorizer strips "RT @user:" prefixes.
public final class Tweet {
    public let idStr: String
    public var fullText: String
    /// Parsed from "Fri Mar 21 04:40:00 +0000 2006"; treated as a naive UTC
    /// wall-clock everywhere (all formatters in the pipeline use UTC).
    public let createdAt: Date
    public let favoriteCount: Int
    public let retweetCount: Int
    /// The HTML "source" field — the client the tweet was posted from.
    public let source: String?

    public var inReplyToStatusIdStr: String?
    public var inReplyToUserIdStr: String?
    public var inReplyToScreenName: String?

    public let urls: [URLEntity]
    public let hashtags: [String]
    public let userMentions: [UserMention]
    /// entities.media (missing key → empty).
    public let entitiesMedia: [MediaEntity]
    /// extended_entities.media, or nil when the tweet has no extended_entities
    /// at all — the distinction matters for media counting, which mirrors
    /// Python's `tweet.get("extended_entities", tweet.get("entities", {}))`.
    public let extendedMedia: [MediaEntity]?
    /// (latitude, longitude) from the "coordinates" field, if geotagged.
    public let coordinate: (latitude: Double, longitude: Double)?

    /// Absolute paths of the archived media files, filled by LinkExpansion.
    public var mediaFiles: [String] = []

    public init(
        idStr: String,
        fullText: String,
        createdAt: Date,
        favoriteCount: Int,
        retweetCount: Int,
        source: String?,
        inReplyToStatusIdStr: String?,
        inReplyToUserIdStr: String?,
        inReplyToScreenName: String?,
        urls: [URLEntity],
        hashtags: [String],
        userMentions: [UserMention],
        entitiesMedia: [MediaEntity],
        extendedMedia: [MediaEntity]?,
        coordinate: (latitude: Double, longitude: Double)?
    ) {
        self.idStr = idStr
        self.fullText = fullText
        self.createdAt = createdAt
        self.favoriteCount = favoriteCount
        self.retweetCount = retweetCount
        self.source = source
        self.inReplyToStatusIdStr = inReplyToStatusIdStr
        self.inReplyToUserIdStr = inReplyToUserIdStr
        self.inReplyToScreenName = inReplyToScreenName
        self.urls = urls
        self.hashtags = hashtags
        self.userMentions = userMentions
        self.entitiesMedia = entitiesMedia
        self.extendedMedia = extendedMedia
        self.coordinate = coordinate
    }

    /// The media list used for counting and for [{attachment}] expansion:
    /// extended_entities.media when the tweet has extended_entities (even an
    /// empty one), entities.media otherwise.
    public var mediaForCounting: [MediaEntity] {
        extendedMedia ?? entitiesMedia
    }
}

/// One entities.urls item: a t.co link and where it really points.
public struct URLEntity {
    public let url: String?
    public let expandedURL: String?
    public let displayURL: String?

    public init(url: String?, expandedURL: String?, displayURL: String?) {
        self.url = url
        self.expandedURL = expandedURL
        self.displayURL = displayURL
    }
}

/// One media item (photo/video/GIF) attached to a tweet.
public struct MediaEntity {
    public let url: String?  // the t.co link that stands in for it in the text
    public let type: String?  // "photo", "video", "animated_gif"
    public let mediaURLHTTPS: String?
    /// video_info.variants, kept in file order.
    public let videoVariants: [VideoVariant]

    public init(url: String?, type: String?, mediaURLHTTPS: String?, videoVariants: [VideoVariant]) {
        self.url = url
        self.type = type
        self.mediaURLHTTPS = mediaURLHTTPS
        self.videoVariants = videoVariants
    }
}

public struct VideoVariant {
    public let contentType: String?
    public let bitrate: String?
    public let url: String?

    public init(contentType: String?, bitrate: String?, url: String?) {
        self.contentType = contentType
        self.bitrate = bitrate
        self.url = url
    }
}

/// One entities.user_mentions item.
public struct UserMention {
    public let screenName: String
    public let name: String?

    public init(screenName: String, name: String?) {
        self.screenName = screenName
        self.name = name
    }
}

/// A thread is its tweets in reading order: the root tweet first, then the
/// replies, depth-first (a whole side branch before the next one starts).
/// A standalone tweet is simply a thread of length one.
public typealias TweetThread = [Tweet]

/// Where the unpacked Twitter archive lives on disk.
public struct TwitterArchiveRef {
    /// .../twitter-<date>-<hash>/data
    public let dataFolder: URL
    /// tweets.js, tweets-part1.js, ... in order.
    public let tweetsJSPaths: [URL]

    public init(dataFolder: URL, tweetsJSPaths: [URL]) {
        self.dataFolder = dataFolder
        self.tweetsJSPaths = tweetsJSPaths
    }

    /// The folder holding the archived photo and video files.
    public var mediaFolder: URL { dataFolder.appendingPathComponent("tweets_media") }

    /// The file holding the account metadata (username, account ID).
    public var accountJSPath: URL { dataFolder.appendingPathComponent("account.js") }
}

/// One thread that made it through selection, and how to import it.
public struct PlannedImport {
    public let thread: TweetThread
    /// True means the thread already sits in Day One in a shorter form (it
    /// gained new tweets inside the configured date range), so it is imported
    /// again in full and the user is reminded to delete the old copy.
    public let isReimport: Bool

    public init(thread: TweetThread, isReimport: Bool) {
        self.thread = thread
        self.isReimport = isReimport
    }
}

/// Everything that goes into one Day One entry.
public struct EntryContent {
    public var text: String  // the entry body, in Markdown
    public var tags: [String]  // from the tweets' hashtags
    public var mediaFiles: [String]  // absolute paths of photos/videos to attach
    public var date: Date?  // when the thread's first tweet was posted
    public var coordinate: (latitude: Double, longitude: Double)?
}

/// A receipt for one successfully created Day One entry.
public struct ImportedEntry {
    public let tweetId: String  // ID of the thread's root tweet
    public let title: String
    public let category: String  // "Wrote a thread", "Replied to ...", etc.
    public let journal: String
    public let date: Date
    public let tweetCount: Int
    /// Only set for re-imported threads: how many tweets the old, shorter copy
    /// in Day One should have — it helps the user find and delete that copy.
    public var previousTweetCount: Int?

    public init(tweetId: String, title: String, category: String, journal: String,
                date: Date, tweetCount: Int, previousTweetCount: Int? = nil) {
        self.tweetId = tweetId
        self.title = title
        self.category = category
        self.journal = journal
        self.date = date
        self.tweetCount = tweetCount
        self.previousTweetCount = previousTweetCount
    }
}

/// The port of config.py: everything the pipeline needs to know, passed as a
/// value instead of read from module globals. The app builds one of these from
/// its Settings screen; the tests and the dump tool build their own.
public struct ImportConfig {
    public var journalName: String
    /// Journal for replies, or nil to skip replies altogether.
    public var replyJournalName: String?
    /// The account's current username, or nil if the account is gone forever.
    public var currentUsername: String?
    /// Max threads to process per run, or nil for no limit.
    public var maxThreadsToProcess: Int?
    /// true: go over threads in a random order; false: start from the oldest.
    public var shuffleMode: Bool
    public var ignoreRetweets: Bool
    /// End entries with "Sent from <client>" (Twitter for Android, etc.).
    public var showTweetSource: Bool
    /// Point links that lead to tweets at xcancel.com instead of twitter.com.
    public var useXcancelLinks: Bool
    /// Only threads started between these two dates are processed
    /// (naive UTC, same semantics as the Python config dates).
    public var startDate: Date
    public var endDate: Date
    /// How far the previous completed import of this account reached (from
    /// ImportHistory), or nil when unknown. Lets the run spot threads that
    /// were imported whole but gained tweets since.
    public var lastCoveredThrough: Date?

    public var processTitlesWithLLM: Bool
    public var llmTitlesForSingleTweets: Bool
    /// How many attached images to show the LLM per entry (0 to disable vision).
    public var llmMaxImages: Int
    public var ollamaHost: String
    public var ollamaModelName: String
    public var ollamaTimeout: TimeInterval
    public var ollamaTitlePrompt: String

    public init(
        journalName: String = "Tweets",
        replyJournalName: String? = "Twitter Replies",
        currentUsername: String? = nil,
        maxThreadsToProcess: Int? = nil,
        shuffleMode: Bool = true,
        ignoreRetweets: Bool = false,
        showTweetSource: Bool = true,
        useXcancelLinks: Bool = false,
        startDate: Date = PipelineDates.date(2006, 3, 21),
        endDate: Date = PipelineDates.date(2069, 4, 20),
        lastCoveredThrough: Date? = nil,
        processTitlesWithLLM: Bool = false,
        llmTitlesForSingleTweets: Bool = true,
        llmMaxImages: Int = 26,
        ollamaHost: String = "http://localhost:11434",
        ollamaModelName: String = "qwen3.5:9b-mlx",
        ollamaTimeout: TimeInterval = 60,
        ollamaTitlePrompt: String = ImportConfig.defaultTitlePrompt
    ) {
        self.journalName = journalName
        self.replyJournalName = replyJournalName
        self.currentUsername = currentUsername
        self.maxThreadsToProcess = maxThreadsToProcess
        self.shuffleMode = shuffleMode
        self.ignoreRetweets = ignoreRetweets
        self.showTweetSource = showTweetSource
        self.useXcancelLinks = useXcancelLinks
        self.startDate = startDate
        self.endDate = endDate
        self.lastCoveredThrough = lastCoveredThrough
        self.processTitlesWithLLM = processTitlesWithLLM
        self.llmTitlesForSingleTweets = llmTitlesForSingleTweets
        self.llmMaxImages = llmMaxImages
        self.ollamaHost = ollamaHost
        self.ollamaModelName = ollamaModelName
        self.ollamaTimeout = ollamaTimeout
        self.ollamaTitlePrompt = ollamaTitlePrompt
    }

    public static let defaultTitlePrompt = """
        You are titling entries in a personal journal built from the author's old tweets.
        Write a title for the tweet below: one short action phrase, 3 to 8 words, past tense, describing what the author did or felt. Examples of good titles:
        Wrote about Formula 1
        Expressed frustration at airport security
        Posted a meme about cats
        Shared photos from a music festival
        Complained about the weather
        Rules: start with a past-tense verb, no period at the end, no quotes, no emoji.
        You don't care if the tweet's language is different.
        Deliver answer in a beautiful natural British English.
        Only state what you can actually see in the text or attached images; strive not to invent specifics.
        If the tweet is too short, vague, or unclear to title honestly, reply with exactly: Tweeted
        Here is the tweet:

        """
}

/// Naive-UTC date helpers: the whole pipeline thinks in UTC wall-clock time,
/// exactly like the Python script thought in naive datetimes.
public enum PipelineDates {
    public static let utc = TimeZone(identifier: "UTC")!

    public static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal
    }

    public static func date(_ year: Int, _ month: Int, _ day: Int,
                            _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return utcCalendar.date(from: components)!
    }

    /// Formatter factory: en_US_POSIX + UTC, like C-locale strftime on naive datetimes.
    public static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = format
        return f
    }
}
