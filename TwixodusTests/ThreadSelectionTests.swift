import XCTest

final class ThreadSelectionTests: XCTestCase {

    private let start = PipelineDates.date(2025, 6, 29)
    private let end = PipelineDates.date(2025, 12, 31, 23, 59, 59)

    private func thread(root: Date, replies: [Date]) -> TweetThread {
        var tweets = [Fixtures.tweet(id: "1", createdAt: root)]
        for (i, date) in replies.enumerated() {
            tweets.append(Fixtures.tweet(id: "\(i + 2)", createdAt: date, replyToStatus: "1"))
        }
        return tweets
    }

    func testThreadInsideRangeIsInRange() {
        let t = thread(root: PipelineDates.date(2025, 7, 1), replies: [])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate([t], startDate: start, endDate: end)
        XCTAssertEqual(inRange.count, 1)
        XCTAssertTrue(extended.isEmpty)
    }

    func testThreadBeforeRangeIsDropped() {
        let t = thread(root: PipelineDates.date(2024, 1, 1), replies: [PipelineDates.date(2024, 2, 1)])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate([t], startDate: start, endDate: end)
        XCTAssertTrue(inRange.isEmpty)
        XCTAssertTrue(extended.isEmpty)
    }

    func testThreadAfterRangeIsDropped() {
        let t = thread(root: PipelineDates.date(2026, 1, 1), replies: [])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate([t], startDate: start, endDate: end)
        XCTAssertTrue(inRange.isEmpty)
        XCTAssertTrue(extended.isEmpty)
    }

    func testOldThreadExtendedInsideRangeIsExtended() {
        let t = thread(
            root: PipelineDates.date(2024, 1, 1),
            replies: [PipelineDates.date(2024, 6, 1), PipelineDates.date(2025, 8, 1)])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate([t], startDate: start, endDate: end)
        XCTAssertTrue(inRange.isEmpty)
        XCTAssertEqual(extended.count, 1)
    }

    func testRangeBoundariesAreInclusive() {
        let atStart = thread(root: start, replies: [])
        let atEnd = thread(root: end, replies: [])
        let (inRange, _) = ThreadSelection.partitionThreadsByDate(
            [atStart, atEnd], startDate: start, endDate: end)
        XCTAssertEqual(inRange.count, 2)
    }

    // MARK: - Grown-thread detection (in-range root, already imported)

    /// The resume scenario: the last import covered through July 1 15:59; the
    /// new range starts on July 1. A thread rooted at 15:59 that gained a
    /// tweet after the coverage point must get the full re-import treatment.
    func testProcessedInRangeThreadGrownPastCoverageIsExtended() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let t = thread(root: covered, replies: [PipelineDates.date(2025, 7, 2)])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            [t], startDate: start, endDate: end,
            processedIDs: ["1"], coveredThrough: covered)
        XCTAssertTrue(inRange.isEmpty)
        XCTAssertEqual(extended.count, 1)
    }

    /// A brand-new thread on the overlap day (posted after the old archive was
    /// exported) is an ordinary import — no re-import, no delete reminder.
    func testUnprocessedThreadPastCoverageStaysInRange() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let t = thread(
            root: PipelineDates.date(2025, 7, 1, 20, 0, 0),
            replies: [PipelineDates.date(2025, 7, 2)])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            [t], startDate: start, endDate: end,
            processedIDs: [], coveredThrough: covered)
        XCTAssertEqual(inRange.count, 1)
        XCTAssertTrue(extended.isEmpty)
    }

    func testProcessedThreadUnchangedSinceCoverageStaysInRange() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let t = thread(root: PipelineDates.date(2025, 7, 1), replies: [covered])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            [t], startDate: start, endDate: end,
            processedIDs: ["1"], coveredThrough: covered)
        XCTAssertEqual(inRange.count, 1)
        XCTAssertTrue(extended.isEmpty)
    }

    /// Growth beyond the range's end doesn't belong to this run — a later run
    /// whose range reaches it will catch the thread as a classic extension.
    func testGrowthAfterEndDateDoesNotTriggerReimport() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let t = thread(root: PipelineDates.date(2025, 7, 1), replies: [PipelineDates.date(2026, 3, 1)])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            [t], startDate: start, endDate: end,
            processedIDs: ["1"], coveredThrough: covered)
        XCTAssertEqual(inRange.count, 1)
        XCTAssertTrue(extended.isEmpty)
    }

    func testWithoutCoveragePointBehavesAsBefore() {
        let t = thread(root: PipelineDates.date(2025, 7, 1), replies: [PipelineDates.date(2025, 8, 1)])
        let (inRange, extended) = ThreadSelection.partitionThreadsByDate(
            [t], startDate: start, endDate: end, processedIDs: ["1"])
        XCTAssertEqual(inRange.count, 1)
        XCTAssertTrue(extended.isEmpty)
    }

    // MARK: - filterToDebugIDs

    func testDebugFilterMatchesAnyTweetInThread() {
        let a = thread(root: PipelineDates.date(2025, 7, 1), replies: [PipelineDates.date(2025, 7, 2)])  // ids 1, 2
        let b = [Fixtures.tweet(id: "30", createdAt: PipelineDates.date(2025, 8, 1))]

        // Root ID and mid-thread ID both select the thread.
        XCTAssertEqual(ThreadSelection.filterToDebugIDs([a, b], ids: ["1"]).count, 1)
        XCTAssertEqual(ThreadSelection.filterToDebugIDs([a, b], ids: ["2"]).count, 1)
        XCTAssertEqual(ThreadSelection.filterToDebugIDs([a, b], ids: ["30"])[0][0].idStr, "30")
        XCTAssertTrue(ThreadSelection.filterToDebugIDs([a, b], ids: ["999"]).isEmpty)
    }

    // MARK: - preview

    private let fullStart = PipelineDates.date(2006, 3, 21)
    private let fullEnd = PipelineDates.date(2069, 4, 20)

    func testPreviewOfFirstImportTakesEverything() {
        let threads = [
            [Fixtures.tweet(id: "10", createdAt: PipelineDates.date(2025, 7, 1))],
            [Fixtures.tweet(id: "20", createdAt: PipelineDates.date(2025, 8, 1))],
        ]
        let preview = ThreadSelection.preview(
            threads, startDate: fullStart, endDate: fullEnd,
            processedIDs: [], coveredThrough: nil)
        XCTAssertEqual(preview.newThreads, 2)
        XCTAssertEqual(preview.grownThreads, 0)
        XCTAssertEqual(preview.alreadyImported, 0)
        XCTAssertEqual(preview.pending, 2)
    }

    func testPreviewCountsNewGrownAndAlreadyImported() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let newThread = [Fixtures.tweet(id: "20", createdAt: PipelineDates.date(2025, 7, 1, 20, 0, 0))]
        let grownThread = thread(root: covered, replies: [PipelineDates.date(2025, 7, 2)])  // ids 1, 2
        let unchanged = [Fixtures.tweet(id: "30", createdAt: PipelineDates.date(2025, 6, 30))]

        let preview = ThreadSelection.preview(
            [newThread, grownThread, unchanged], startDate: fullStart, endDate: fullEnd,
            processedIDs: ["1", "30"], coveredThrough: covered)
        XCTAssertEqual(preview.newThreads, 1)
        XCTAssertEqual(preview.grownThreads, 1)
        XCTAssertEqual(preview.alreadyImported, 1)
        XCTAssertEqual(preview.pending, 2)
    }

    /// A grown thread whose extension marker is already in the ledger was
    /// re-imported before — it counts as done, not as pending again.
    func testPreviewGrownThreadWithMarkerCountsAsAlreadyImported() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let grownThread = thread(root: covered, replies: [PipelineDates.date(2025, 7, 2)])
        let preview = ThreadSelection.preview(
            [grownThread], startDate: fullStart, endDate: fullEnd,
            processedIDs: ["1", ImportLedger.extensionMarker(grownThread)],
            coveredThrough: covered)
        XCTAssertEqual(preview.grownThreads, 0)
        XCTAssertEqual(preview.alreadyImported, 1)
        XCTAssertEqual(preview.pending, 0)
    }

    /// The interrupted-import case: entries in the ledger but no coverage
    /// point recorded yet — the remainder is pending, nothing counts as grown.
    func testPreviewOfInterruptedImportShowsRemainder() {
        let threads = [
            [Fixtures.tweet(id: "10", createdAt: PipelineDates.date(2025, 7, 1))],
            [Fixtures.tweet(id: "20", createdAt: PipelineDates.date(2025, 8, 1))],
            [Fixtures.tweet(id: "30", createdAt: PipelineDates.date(2025, 9, 1))],
        ]
        let preview = ThreadSelection.preview(
            threads, startDate: fullStart, endDate: fullEnd,
            processedIDs: ["10"], coveredThrough: nil)
        XCTAssertEqual(preview.newThreads, 2)
        XCTAssertEqual(preview.grownThreads, 0)
        XCTAssertEqual(preview.alreadyImported, 1)
    }

    func testCountTweetsBefore() {
        let t = thread(
            root: PipelineDates.date(2024, 1, 1),
            replies: [PipelineDates.date(2024, 6, 1), PipelineDates.date(2025, 8, 1)])
        XCTAssertEqual(ThreadSelection.countTweetsBefore(t, startDate: start), 2)
    }

    /// A completed import always took the whole thread as the archive had it,
    /// so the previous copy can hold more than "tweets before the range".
    func testCountTweetsBeforeUsesCoveragePointWhenLater() {
        let covered = PipelineDates.date(2025, 7, 1, 15, 59, 0)
        let t = thread(root: covered, replies: [PipelineDates.date(2025, 7, 2)])
        // Without the coverage point the old copy would look empty (root is
        // not before the range start)…
        XCTAssertEqual(ThreadSelection.countTweetsBefore(t, startDate: start), 0)
        // …with it, the root is correctly counted as already imported.
        XCTAssertEqual(
            ThreadSelection.countTweetsBefore(t, startDate: start, coveredThrough: covered), 1)
    }

    func testTweetURL() {
        XCTAssertEqual(
            ThreadSelection.tweetURL(tweetId: "42", username: "me"),
            "https://twitter.com/me/status/42")
        XCTAssertEqual(
            ThreadSelection.tweetURL(tweetId: "42", username: nil),
            "https://twitter.com/i/web/status/42")
    }

    func testReimportReportMentionsEverything() {
        let entry = ImportedEntry(
            tweetId: "42", title: "Wrote a thread", category: "Wrote a thread",
            journal: "Tweets", date: PipelineDates.date(2024, 1, 1, 15, 30),
            tweetCount: 7, previousTweetCount: 4)
        let report = ThreadSelection.formatReimportReport([entry], username: "me")

        XCTAssertTrue(report.contains("1 thread(s) were re-imported in full"))
        XCTAssertTrue(report.contains("01 January 2024, 15:30 — “Wrote a thread”"))
        XCTAssertTrue(report.contains("Journal: Tweets"))
        XCTAssertTrue(report.contains("≈4 tweets (the shorter, previously imported copy)"))
        XCTAssertTrue(report.contains("New entry: 7 tweets"))
        XCTAssertTrue(report.contains("https://twitter.com/me/status/42"))
    }

    func testReimportReportWithoutPreviousCount() {
        let entry = ImportedEntry(
            tweetId: "42", title: "T", category: "Tweeted", journal: "Tweets",
            date: PipelineDates.date(2024, 1, 1), tweetCount: 3)
        let report = ThreadSelection.formatReimportReport([entry], username: nil)
        XCTAssertTrue(report.contains("the shorter, previously imported copy"))
        XCTAssertTrue(report.contains("https://twitter.com/i/web/status/42"))
    }
}

final class ImportLedgerTests: XCTestCase {

    private var tempFile: URL!

    override func setUp() {
        super.setUp()
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("twixodus-tests-\(UUID().uuidString)")
            .appendingPathComponent("ledger.txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile.deletingLastPathComponent())
        super.tearDown()
    }

    func testEmptyLedgerLoadsEmpty() {
        let ledger = ImportLedger(fileURL: tempFile)
        XCTAssertTrue(ledger.loadProcessedIDs().isEmpty)
    }

    func testRememberPersistsAcrossReload() {
        let ledger = ImportLedger(fileURL: tempFile)
        var ids = Set<String>()
        ledger.rememberProcessed(tweetId: "1", reimportMarker: nil, processedIDs: &ids)
        ledger.rememberProcessed(tweetId: "2", reimportMarker: "2+9", processedIDs: &ids)
        XCTAssertEqual(ids, ["1", "2", "2+9"])

        let reloaded = ImportLedger(fileURL: tempFile).loadProcessedIDs()
        XCTAssertEqual(reloaded, ["1", "2", "2+9"])
    }

    func testNoDuplicateLinesWritten() throws {
        let ledger = ImportLedger(fileURL: tempFile)
        var ids = Set<String>()
        ledger.rememberProcessed(tweetId: "1", reimportMarker: nil, processedIDs: &ids)
        ledger.rememberProcessed(tweetId: "1", reimportMarker: nil, processedIDs: &ids)

        let content = try String(contentsOf: tempFile, encoding: .utf8)
        XCTAssertEqual(content, "1\n")
    }

    func testExtensionMarker() {
        let thread = [
            Fixtures.tweet(id: "10"),
            Fixtures.tweet(id: "11", replyToStatus: "10"),
            Fixtures.tweet(id: "15", replyToStatus: "11"),
        ]
        XCTAssertEqual(ImportLedger.extensionMarker(thread), "10+15")
    }
}
