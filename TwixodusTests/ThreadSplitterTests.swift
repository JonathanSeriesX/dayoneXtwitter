import XCTest

final class ThreadSplitterTests: XCTestCase {

    /// A tweet dragging `media` fake attachments.
    private func tweet(_ id: String, media: Int) -> Tweet {
        let t = Fixtures.tweet(id: id, createdAt: PipelineDates.date(2020, 1, 1, 12, 0, 0))
        t.mediaFiles = (0..<media).map { "/tmp/\(id)-\($0).jpg" }
        return t
    }

    private func sizes(_ parts: [TweetThread]) -> [Int] { parts.map(\.count) }
    private func attachments(_ part: TweetThread) -> Int {
        part.reduce(0) { $0 + $1.mediaFiles.count }
    }

    func testThreadAtTheLimitStaysWhole() {
        // 10 tweets × 3 = exactly 30 — allowed, no split.
        let thread = (1...10).map { tweet("\($0)", media: 3) }
        XCTAssertEqual(sizes(ThreadSplitter.split(thread)), [10])
    }

    func testTextOnlyThreadStaysWhole() {
        let thread = (1...80).map { tweet("\($0)", media: 0) }
        XCTAssertEqual(sizes(ThreadSplitter.split(thread)), [80])
    }

    func testOverloadedThreadSplitsInBalancedHalves() {
        // 11 tweets × 4 = 44 attachments → two parts, 5 + 6 tweets, not 10 + 1.
        let thread = (1...11).map { tweet("\($0)", media: 4) }
        let parts = ThreadSplitter.split(thread)
        XCTAssertEqual(sizes(parts).sorted(), [5, 6])
        for part in parts {
            XCTAssertLessThanOrEqual(attachments(part), ThreadSplitter.maxAttachmentsPerEntry)
        }
        // Contiguous and order-preserving.
        XCTAssertEqual(parts.flatMap { $0.map(\.idStr) }, thread.map(\.idStr))
    }

    func testUsesTheFewestPartsPossible() {
        // 16 tweets × 4 = 64 attachments → ceil(64/30) = 3 parts, evenly sized.
        let thread = (1...16).map { tweet("\($0)", media: 4) }
        let parts = ThreadSplitter.split(thread)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(sizes(parts).reduce(0, +), 16)
        for part in parts {
            XCTAssertTrue((5...6).contains(part.count), "sizes: \(sizes(parts))")
            XCTAssertLessThanOrEqual(attachments(part), ThreadSplitter.maxAttachmentsPerEntry)
        }
    }

    func testAttachmentLimitBeatsBalanceWhenTheyConflict() {
        // Nine light tweets and one 29-attachment monster: an even 5+5 would
        // put 33 in the second part, so the cut must slide to 8+2.
        let thread = (1...9).map { tweet("\($0)", media: 1) } + [tweet("10", media: 29)]
        let parts = ThreadSplitter.split(thread)
        XCTAssertEqual(sizes(parts), [8, 2])
        for part in parts {
            XCTAssertLessThanOrEqual(attachments(part), ThreadSplitter.maxAttachmentsPerEntry)
        }
    }

    func testEveryPartAlwaysRespectsTheLimit() {
        // A messy mix of media counts, checked exhaustively.
        let counts = [4, 0, 4, 4, 1, 4, 4, 0, 4, 4, 2, 4, 4, 4, 0, 4, 3, 4]
        let thread = counts.enumerated().map { tweet("\($0.offset + 1)", media: $0.element) }
        let parts = ThreadSplitter.split(thread)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.flatMap { $0.map(\.idStr) }, thread.map(\.idStr))
        for part in parts {
            XCTAssertLessThanOrEqual(attachments(part), ThreadSplitter.maxAttachmentsPerEntry)
        }
    }
}
