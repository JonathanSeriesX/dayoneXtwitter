// Step 4 of the pipeline: pick which threads to import for the date range.
//
// A thread whose first tweet falls inside the configured range is imported as
// usual. Threads that *started* before the range but were extended with new
// tweets inside it are a special case: Day One can't update an existing entry,
// so the whole thread has to be imported again and the older, shorter copy
// deleted by hand. This module finds those threads, and formats the reminder
// to delete the duplicates.

import Foundation

public enum ThreadSelection {

    /// Splits threads into the ones to import normally and the ones to re-import.
    ///
    /// Returns (inRange, extended):
    ///   - inRange: threads whose first tweet was posted within the date range.
    ///   - extended: threads that began before the range but gained at least one
    ///     tweet inside it. Those already live in Day One as a shorter entry, so
    ///     they get imported again in full and reported to the user.
    ///
    /// Threads that started after the range, or that ended before it, are dropped.
    public static func partitionThreadsByDate(
        _ threads: [TweetThread], startDate: Date, endDate: Date
    ) -> (inRange: [TweetThread], extended: [TweetThread]) {
        var inRange: [TweetThread] = []
        var extended: [TweetThread] = []

        for thread in threads {
            guard let rootDate = thread.first?.createdAt else { continue }

            if startDate <= rootDate && rootDate <= endDate {
                inRange.append(thread)
            } else if rootDate < startDate,
                      thread.dropFirst().contains(where: { startDate <= $0.createdAt && $0.createdAt <= endDate }) {
                extended.append(thread)
            }
        }

        return (inRange, extended)
    }

    /// Counts the tweets of a thread posted before the range — i.e. how big the
    /// already-imported copy of this thread is expected to be.
    public static func countTweetsBefore(_ thread: TweetThread, startDate: Date) -> Int {
        thread.filter { $0.createdAt < startDate }.count
    }

    /// Builds a link to a tweet, falling back to the account-agnostic URL.
    public static func tweetURL(tweetId: String, username: String?) -> String {
        if let username, !username.isEmpty {
            return "https://twitter.com/\(username)/status/\(tweetId)"
        }
        return "https://twitter.com/i/web/status/\(tweetId)"
    }

    private static let reportDateFormatter = PipelineDates.formatter("dd MMMM yyyy, HH:mm")
    private static let reportDayFormatter = PipelineDates.formatter("dd MMMM yyyy")

    /// Formats the list of re-imported threads into a reminder to delete the
    /// older duplicates.
    public static func formatReimportReport(
        _ reimported: [ImportedEntry], startDate: Date, username: String?
    ) -> String {
        let line = String(repeating: "=", count: 72)
        let header = """
            \(line)
            ⚠️  ACTION REQUIRED — \(reimported.count) thread(s) were re-imported in full
            \(line)
            These threads were started before the current date range, but you added
            more tweets to them within it. Day One can't extend an existing entry, so
            each one was imported again as a complete thread — which leaves an older,
            shorter copy in your journal. Delete the older copy of each:

            """

        var blocks: [String] = []
        for (i, entry) in reimported.enumerated() {
            let dateStr = reportDateFormatter.string(from: entry.date)
            let oldEntryStr: String
            if let count = entry.previousTweetCount, count != 0 {
                oldEntryStr = "≈\(count) tweets (those posted before \(reportDayFormatter.string(from: startDate)))"
            } else {
                oldEntryStr = "the shorter, previously imported copy"
            }
            blocks.append("""

                \(i + 1). \(dateStr) — “\(entry.title)”
                   Journal: \(entry.journal)
                   Old entry to delete: \(oldEntryStr)
                   New entry: \(entry.tweetCount) tweets
                   First tweet: \(tweetURL(tweetId: entry.tweetId, username: username))

                """)
        }

        let footer = """

            Both copies share the same entry date, so searching that date in Day One
            will show them side by side — keep the longer one.

            """

        return header + blocks.joined() + footer
    }
}
