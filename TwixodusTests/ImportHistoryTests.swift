import XCTest

final class ImportHistoryTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("twixodus-history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("last_import-test.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func testLoadWithoutFileReturnsNil() {
        XCTAssertNil(ImportHistory(fileURL: fileURL).load())
    }

    func testRecordAndLoadRoundTrip() {
        let history = ImportHistory(fileURL: fileURL)
        let covered = PipelineDates.date(2026, 1, 15, 23, 59, 59)
        history.recordCovered(through: covered, finishedAt: PipelineDates.date(2026, 8, 18))
        XCTAssertEqual(history.load()?.coveredThrough, covered)
        XCTAssertEqual(history.load()?.updatedAt, PipelineDates.date(2026, 8, 18))
    }

    func testRecordOnlyMovesForward() {
        let history = ImportHistory(fileURL: fileURL)
        history.recordCovered(through: PipelineDates.date(2026, 1, 15))
        // A later re-run of an old range must not shrink the coverage…
        history.recordCovered(through: PipelineDates.date(2020, 5, 1))
        XCTAssertEqual(history.load()?.coveredThrough, PipelineDates.date(2026, 1, 15))
        // …but a newer run still advances it.
        history.recordCovered(through: PipelineDates.date(2027, 2, 2))
        XCTAssertEqual(history.load()?.coveredThrough, PipelineDates.date(2027, 2, 2))
    }

    func testOneHistoryPerAccountNextToTheLedger() {
        XCTAssertTrue(ImportHistory(accountId: "381554576").fileURL.path
            .hasSuffix("Twixodus/ledgers/last_import-381554576.json"))
        // No account.js in the archive → the shared "default" history,
        // mirroring the ledger's naming.
        XCTAssertTrue(ImportHistory(accountId: nil).fileURL.path
            .hasSuffix("Twixodus/ledgers/last_import-default.json"))
        XCTAssertTrue(ImportHistory(accountId: "").fileURL.path
            .hasSuffix("Twixodus/ledgers/last_import-default.json"))
    }
}
