// Tests for the ImportEngine run loop: limits, pause/cancel, failures,
// re-import planning and the ledger interaction. The Day One CLI is replaced
// by a scripted mock (EntryPosting), and the ledger writes to a temp file.

import XCTest

// MARK: - Test doubles & helpers

/// A scripted Day One: returns the next result from `results` (defaulting to
/// success once the script runs out) and records every call.
private final class MockPoster: EntryPosting {
    var results: [Bool]
    private(set) var calls: [(text: String, journal: String?, attachments: [String])] = []
    /// Invoked after each call with the 1-based call number — used by the
    /// cancellation tests to cancel mid-run.
    var onCall: ((Int) -> Void)?

    init(results: [Bool] = []) {
        self.results = results
    }

    func addPost(
        text: String, journal: String?, tags: [String], date: Date?,
        coordinate: (latitude: Double, longitude: Double)?, attachments: [String]
    ) -> Bool {
        let result = calls.count < results.count ? results[calls.count] : true
        calls.append((text: text, journal: journal, attachments: attachments))
        onCall?(calls.count)
        return result
    }
}

private final class ProgressRecorder {
    private(set) var history: [(imported: Int, total: Int)] = []
    var last: (imported: Int, total: Int)? { history.last }
    func record(_ imported: Int, _ total: Int) { history.append((imported, total)) }
}

final class ImportEngineTests: XCTestCase {

    private var ledgerURL: URL!

    override func setUp() {
        super.setUp()
        ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("twixodus-tests-\(UUID().uuidString)")
            .appendingPathComponent("ledger.txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ledgerURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeTweet(
        _ id: String, date: Date = PipelineDates.date(2020, 5, 1),
        text: String = "hello world",
        replyToId: String? = nil, replyToScreenName: String? = nil
    ) -> Tweet {
        Tweet(
            idStr: id, fullText: text, createdAt: date,
            favoriteCount: 0, retweetCount: 0, source: nil,
            inReplyToStatusIdStr: replyToId, inReplyToUserIdStr: nil,
            inReplyToScreenName: replyToScreenName,
            urls: [], hashtags: [], userMentions: [],
            entitiesMedia: [], extendedMedia: nil, coordinate: nil
        )
    }

    private func makeEngine(
        threadsConfig config: ImportConfig,
        poster: MockPoster,
        control: ImportControl = ImportControl(),
        progress: ProgressRecorder = ProgressRecorder()
    ) -> ImportEngine {
        ImportEngine(
            config: config,
            context: .init(ownTweetIDs: [], currentUsername: "tester"),
            ledger: ImportLedger(fileURL: ledgerURL),
            dayOne: poster,
            ollama: nil,
            categoryCache: ImportEngine.CategoryCache(),
            control: control,
            callbacks: ImportCallbacks(progress: { progress.record($0, $1) })
        )
    }

    /// The test config: deterministic order, both journals set, no LLM.
    private func makeConfig(
        maxThreads: Int? = nil, replyJournal: String? = "Replies", ignoreRetweets: Bool = false
    ) -> ImportConfig {
        ImportConfig(
            journalName: "Tweets",
            replyJournalName: replyJournal,
            currentUsername: "tester",
            maxThreadsToProcess: maxThreads,
            shuffleMode: false,
            ignoreRetweets: ignoreRetweets
        )
    }

    private var ledger: ImportLedger { ImportLedger(fileURL: ledgerURL) }

    // MARK: - The happy path

    func testImportsRecordLedgerAndFinishProgressAt100Percent() async {
        let poster = MockPoster()
        let progress = ProgressRecorder()
        let engine = makeEngine(threadsConfig: makeConfig(), poster: poster, progress: progress)

        let threads = [[makeTweet("1")], [makeTweet("2")], [makeTweet("3")]]
        let result = await engine.run(threads: threads)

        XCTAssertEqual(result.importedCount, 3)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.totalPending, 3)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertFalse(result.stoppedAtLimit)
        XCTAssertEqual(poster.calls.count, 3)
        XCTAssertEqual(ledger.loadProcessedIDs(), ["1", "2", "3"])
        XCTAssertEqual(progress.last?.imported, 3)
        XCTAssertEqual(progress.last?.total, 3)
    }

    // MARK: - SOB-70: the limit counts imports, not iterations

    func testAlreadyImportedThreadsDontConsumeTheLimit() async {
        // Three of five threads are already in the ledger, and the limit is 2.
        // The old loop-index check would stop before importing anything new.
        var processed = Set<String>()
        for id in ["1", "2", "3"] {
            ledger.rememberProcessed(tweetId: id, reimportMarker: nil, processedIDs: &processed)
        }

        let poster = MockPoster()
        let engine = makeEngine(threadsConfig: makeConfig(maxThreads: 2), poster: poster)
        let threads = ["1", "2", "3", "4", "5"].map { [makeTweet($0)] }
        let result = await engine.run(threads: threads)

        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.skippedAlreadyImported, 3)
        XCTAssertFalse(result.stoppedAtLimit, "nothing pending was left behind")
        XCTAssertTrue(ledger.loadProcessedIDs().isSuperset(of: ["4", "5"]))
    }

    func testStoppedAtLimitOnlyWhenPendingThreadsRemain() async {
        let poster = MockPoster()
        let engine = makeEngine(threadsConfig: makeConfig(maxThreads: 1), poster: poster)
        let result = await engine.run(threads: [[makeTweet("1")], [makeTweet("2")]])

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertTrue(result.stoppedAtLimit)
        XCTAssertEqual(ledger.loadProcessedIDs(), ["1"])
    }

    func testFailuresCountAgainstTheLimit() async {
        // A dead Day One must not make the run churn through the whole archive:
        // failed attempts consume the budget too.
        let poster = MockPoster(results: [false, false])
        let engine = makeEngine(threadsConfig: makeConfig(maxThreads: 2), poster: poster)
        let result = await engine.run(threads: ["1", "2", "3"].map { [makeTweet($0)] })

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertTrue(result.stoppedAtLimit)
        XCTAssertEqual(poster.calls.count, 2)
    }

    // MARK: - SOB-71: failures are counted, unrecorded, and retried next run

    func testFailedPostsAreCountedAndRetriedOnTheNextRun() async {
        let failing = MockPoster(results: [false, false])
        let progress = ProgressRecorder()
        let engine = makeEngine(threadsConfig: makeConfig(), poster: failing, progress: progress)
        let threads = [[makeTweet("1")], [makeTweet("2")]]
        let result = await engine.run(threads: threads)

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertEqual(result.totalPending, 2)
        XCTAssertTrue(ledger.loadProcessedIDs().isEmpty, "failed threads must not enter the ledger")
        // The progress denominator shrinks with each failure, so the bar
        // still completes instead of freezing short of 100%.
        XCTAssertEqual(progress.last?.total, 0)

        // The next run picks the same threads up again and succeeds.
        let retryResult = await makeEngine(threadsConfig: makeConfig(), poster: MockPoster())
            .run(threads: threads)
        XCTAssertEqual(retryResult.importedCount, 2)
        XCTAssertEqual(ledger.loadProcessedIDs(), ["1", "2"])
    }

    // MARK: - SOB-69: cancellation via ImportControl

    func testCancelBeforeRunStopsImmediately() async {
        let control = ImportControl()
        control.cancel()
        let poster = MockPoster()
        let engine = makeEngine(threadsConfig: makeConfig(), poster: poster, control: control)
        let result = await engine.run(threads: [[makeTweet("1")]])

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(poster.calls.count, 0)
    }

    func testCancelMidRunStopsAfterTheCurrentThread() async {
        let control = ImportControl()
        let poster = MockPoster()
        poster.onCall = { n in
            if n == 1 { control.cancel() }
        }
        let engine = makeEngine(threadsConfig: makeConfig(), poster: poster, control: control)
        let result = await engine.run(threads: ["1", "2", "3"].map { [makeTweet($0)] })

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(poster.calls.count, 1)
        XCTAssertEqual(ledger.loadProcessedIDs(), ["1"], "the finished entry stays recorded")
    }

    func testCancelWhilePausedUnblocksTheRun() async {
        let control = ImportControl()
        control.setPaused(true)
        let poster = MockPoster()
        let engine = makeEngine(threadsConfig: makeConfig(), poster: poster, control: control)

        let run = Task { await engine.run(threads: [[makeTweet("1")]]) }
        try? await Task.sleep(nanoseconds: 400_000_000)  // let it settle into the pause loop
        control.cancel()
        let result = await run.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(poster.calls.count, 0)
    }

    func testControlResetClearsBothFlags() {
        let control = ImportControl()
        control.setPaused(true)
        control.cancel()
        control.reset()
        XCTAssertFalse(control.isPaused)
        XCTAssertFalse(control.isCancelled)
    }

    // MARK: - SOB-74: threads without a target journal don't stall the progress bar

    func testReplyWithoutReplyJournalIsSkippedButMarkedProcessed() async {
        let poster = MockPoster()
        let progress = ProgressRecorder()
        let engine = makeEngine(
            threadsConfig: makeConfig(replyJournal: nil), poster: poster, progress: progress)
        let reply = makeTweet("1", text: "sure thing", replyToId: "999", replyToScreenName: "bob")
        let result = await engine.run(threads: [[reply]])

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.skippedNoJournal, 1)
        XCTAssertEqual(result.totalPending, 1)
        XCTAssertEqual(poster.calls.count, 0)
        XCTAssertEqual(ledger.loadProcessedIDs(), ["1"], "skips are recorded so they aren't re-planned")
        XCTAssertEqual(progress.last?.total, 0, "the denominator shrank, so the bar can complete")
    }

    func testIgnoredRetweetIsSkippedButMarkedProcessed() async {
        let poster = MockPoster()
        let engine = makeEngine(
            threadsConfig: makeConfig(ignoreRetweets: true), poster: poster)
        let retweet = makeTweet("1", text: "RT @somebody: their brilliant take")
        let result = await engine.run(threads: [[retweet]])

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.skippedNoJournal, 1)
        XCTAssertEqual(poster.calls.count, 0)
        XCTAssertEqual(ledger.loadProcessedIDs(), ["1"])
    }

    func testReplyGoesToTheReplyJournal() async {
        let poster = MockPoster()
        let engine = makeEngine(threadsConfig: makeConfig(), poster: poster)
        let reply = makeTweet("1", text: "sure thing", replyToId: "999", replyToScreenName: "bob")
        let result = await engine.run(threads: [[reply]])

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(poster.calls.first?.journal, "Replies")
    }

    // MARK: - Re-import planning

    func testExtendedThreadIsReimportedWithMarkerAndReport() async {
        // The thread started before the range but gained a tweet inside it.
        var processed = Set<String>()
        ledger.rememberProcessed(tweetId: "1", reimportMarker: nil, processedIDs: &processed)

        var config = makeConfig()
        config.startDate = PipelineDates.date(2020, 1, 1)
        config.endDate = PipelineDates.date(2020, 12, 31)

        let thread = [
            makeTweet("1", date: PipelineDates.date(2019, 12, 1)),
            makeTweet("2", date: PipelineDates.date(2020, 2, 1)),
        ]
        let poster = MockPoster()
        let engine = makeEngine(threadsConfig: config, poster: poster)
        let result = await engine.run(threads: [thread])

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertNotNil(result.reimportReport)
        XCTAssertTrue(ledger.loadProcessedIDs().contains("1+2"), "the extension marker is recorded")

        // Running the same range again must not import the extension twice.
        let secondResult = await makeEngine(threadsConfig: config, poster: MockPoster())
            .run(threads: [thread])
        XCTAssertEqual(secondResult.importedCount, 0)
        XCTAssertEqual(secondResult.skippedAlreadyImported, 1)
    }

    // MARK: - countPendingImports

    func testCountPendingImportsUsesExtensionMarkersForReimports() {
        let engine = makeEngine(threadsConfig: makeConfig(), poster: MockPoster())
        let ordinary = PlannedImport(thread: [makeTweet("1")], isReimport: false)
        let extended = PlannedImport(
            thread: [makeTweet("2"), makeTweet("3")], isReimport: true)

        // Nothing processed: both pending.
        XCTAssertEqual(engine.countPendingImports([ordinary, extended], processedIDs: []), 2)
        // The ordinary thread's root ID retires it; the re-import needs its marker.
        XCTAssertEqual(engine.countPendingImports([ordinary, extended], processedIDs: ["1", "2"]), 1)
        XCTAssertEqual(
            engine.countPendingImports([ordinary, extended], processedIDs: ["1", "2+3"]), 0)
    }
}

// MARK: - SOB-73: unparseable archive parts throw instead of dropping tweets

final class ArchiveParseFailureTests: XCTestCase {

    private func writeTempFile(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("twixodus-parse-\(UUID().uuidString).js")
        try content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFileWithoutJSONArrayThrows() throws {
        let url = try writeTempFile("window.YTD.tweets.part0 = oops, no array here")
        XCTAssertThrowsError(try TwitterArchiveLoader.loadTweetsFromFile(url)) { error in
            guard case ArchiveError.malformed = error else {
                return XCTFail("expected ArchiveError.malformed, got \(error)")
            }
        }
    }

    func testTruncatedJSONThrows() throws {
        let url = try writeTempFile(#"window.YTD.tweets.part0 = [{"tweet": {"id_str": "1""#)
        XCTAssertThrowsError(try TwitterArchiveLoader.loadTweetsFromFile(url)) { error in
            guard case ArchiveError.malformed = error else {
                return XCTFail("expected ArchiveError.malformed, got \(error)")
            }
        }
    }

    func testUnexpectedShapeThrows() throws {
        let url = try writeTempFile(#"window.YTD.tweets.part0 = ["just", "strings"]"#)
        XCTAssertThrowsError(try TwitterArchiveLoader.loadTweetsFromFile(url)) { error in
            guard case ArchiveError.malformed = error else {
                return XCTFail("expected ArchiveError.malformed, got \(error)")
            }
        }
    }

    func testMalformedIndividualTweetsAreSkippedWithAWarning() throws {
        let url = try writeTempFile("""
            window.YTD.tweets.part0 = [
              {"tweet": {"id_str": "1", "created_at": "Fri Mar 21 04:40:00 +0000 2006", "full_text": "hi"}},
              {"tweet": {"id_str": "2"}},
              {"notATweet": true}
            ]
            """)
        var warnings: [String] = []
        let tweets = try TwitterArchiveLoader.loadTweetsFromFile(url) { warnings.append($0) }
        XCTAssertEqual(tweets.map(\.idStr), ["1"])
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("2 of 3"), "got: \(warnings)")
    }
}

// MARK: - SOB-72: missing attachments are skipped individually

final class DayOneAttachmentFilterTests: XCTestCase {

    func testMissingAttachmentsAreSkippedWithAWarningEach() {
        // A nonexistent binary makes execute() fail fast — the interesting
        // part is the warning log for each missing file, which happens first.
        var logged: [(String, ImportLogKind)] = []
        let cli = DayOneCLI(binaryPath: "/nonexistent/dayone") { logged.append(($0, $1)) }

        _ = cli.addPost(
            text: "entry",
            attachments: ["/definitely/not/there.jpg", "/also/missing.mp4"]
        )

        let warnings = logged.filter { $0.1 == .warning && $0.0.contains("missing from the archive") }
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings[0].0.contains("/definitely/not/there.jpg"))
        XCTAssertTrue(warnings[1].0.contains("/also/missing.mp4"))
    }
}
