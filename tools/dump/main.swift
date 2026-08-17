// twixodus-dump: runs pipeline steps 1–5b headlessly (no Day One, no LLM) and
// prints every composed entry as JSON, keyed by root tweet ID:
//
//     twixodus-dump <archive folder> [username|-] > swift.json
//
// It was built to verify the Swift port against the original Python pipeline
// (byte-identical over the full real archive before the Python code was
// deleted). It remains useful as a golden-file harness: dump once, change
// the pipeline, dump again, diff.

import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: twixodus-dump <archive folder> [username|-]\n".utf8))
    exit(2)
}

let root = URL(fileURLWithPath: arguments[1])
var username: String? = arguments.count >= 3 ? arguments[2] : "JonathanSeriesX"
if username == "-" { username = nil }

var config = ImportConfig()
config.currentUsername = username
config.shuffleMode = false
config.processTitlesWithLLM = false
config.journalName = "Tweets Test"
config.replyJournalName = "Twitter Replies Test"

let stderrLog: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }

do {
    let archive = try ArchiveLoading.load(root: root, log: stderrLog)
    let context = ThreadCategorizer.Context(
        ownTweetIDs: archive.ownTweetIDs, currentUsername: config.currentUsername)

    let isoFormatter = PipelineDates.formatter("yyyy-MM-dd'T'HH:mm:ss")

    var output: [String: Any] = [:]
    for thread in archive.threads {
        let rootId = thread[0].idStr
        let category = ThreadCategorizer.threadCategory(thread, context: context)
        let content = EntryComposer.aggregateThreadData(thread, config: config)
        // LLM is off, so the title is always the category — same as Python.
        let title = category
        let entryText = EntryComposer.buildEntryContent(
            entryText: content.text, firstTweet: thread[0], category: category,
            title: title, config: config)
        let journal = EntryComposer.targetJournal(
            category: category, tweetId: rootId, config: config)

        output[rootId] = [
            "category": category,
            "title": title,
            "journal": journal ?? NSNull(),
            "text": entryText,
            "tags": content.tags,
            "media": content.mediaFiles,
            "date": content.date.map { isoFormatter.string(from: $0) } ?? NSNull(),
            "coordinate": content.coordinate.map { [$0.latitude, $0.longitude] } ?? NSNull(),
            "tweet_count": thread.count,
        ] as [String: Any]
    }

    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
} catch {
    stderrLog("error: \(error.localizedDescription)")
    exit(1)
}
