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

    func testCountTweetsBefore() {
        let t = thread(
            root: PipelineDates.date(2024, 1, 1),
            replies: [PipelineDates.date(2024, 6, 1), PipelineDates.date(2025, 8, 1)])
        XCTAssertEqual(ThreadSelection.countTweetsBefore(t, startDate: start), 2)
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
        let report = ThreadSelection.formatReimportReport([entry], startDate: start, username: "me")

        XCTAssertTrue(report.contains("1 thread(s) were re-imported in full"))
        XCTAssertTrue(report.contains("01 January 2024, 15:30 — “Wrote a thread”"))
        XCTAssertTrue(report.contains("Journal: Tweets"))
        XCTAssertTrue(report.contains("≈4 tweets (those posted before 29 June 2025)"))
        XCTAssertTrue(report.contains("New entry: 7 tweets"))
        XCTAssertTrue(report.contains("https://twitter.com/me/status/42"))
    }

    func testReimportReportWithoutPreviousCount() {
        let entry = ImportedEntry(
            tweetId: "42", title: "T", category: "Tweeted", journal: "Tweets",
            date: PipelineDates.date(2024, 1, 1), tweetCount: 3)
        let report = ThreadSelection.formatReimportReport([entry], startDate: start, username: nil)
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
