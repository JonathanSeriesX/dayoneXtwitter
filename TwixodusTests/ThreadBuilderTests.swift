import XCTest

/// Shared fixture helpers for the pipeline tests.
enum Fixtures {
    static func tweet(
        id: String,
        text: String = "Hello world",
        createdAt: Date = PipelineDates.date(2020, 1, 1, 12, 0, 0),
        likes: Int = 0,
        retweets: Int = 0,
        source: String? = nil,
        replyToStatus: String? = nil,
        replyToUser: String? = nil,
        replyToScreenName: String? = nil,
        urls: [URLEntity] = [],
        hashtags: [String] = [],
        mentions: [UserMention] = [],
        entitiesMedia: [MediaEntity] = [],
        extendedMedia: [MediaEntity]? = nil,
        coordinate: (latitude: Double, longitude: Double)? = nil
    ) -> Tweet {
        Tweet(
            idStr: id,
            fullText: text,
            createdAt: createdAt,
            favoriteCount: likes,
            retweetCount: retweets,
            source: source,
            inReplyToStatusIdStr: replyToStatus,
            inReplyToUserIdStr: replyToUser,
            inReplyToScreenName: replyToScreenName,
            urls: urls,
            hashtags: hashtags,
            userMentions: mentions,
            entitiesMedia: entitiesMedia,
            extendedMedia: extendedMedia,
            coordinate: coordinate
        )
    }

    static func photo(tco: String, mediaURL: String = "https://pbs.twimg.com/media/img.jpg") -> MediaEntity {
        MediaEntity(url: tco, type: "photo", mediaURLHTTPS: mediaURL, videoVariants: [])
    }
}

final class ThreadBuilderTests: XCTestCase {

    // MARK: - combineThreads

    func testStandaloneTweetsBecomeSingleThreads() {
        let tweets = [Fixtures.tweet(id: "1"), Fixtures.tweet(id: "2")]
        let threads = ThreadBuilder.combineThreads(tweets)
        XCTAssertEqual(threads.count, 2)
        XCTAssertEqual(threads.map { $0[0].idStr }, ["1", "2"])
    }

    func testSelfReplyChainBecomesOneThread() {
        let tweets = [
            Fixtures.tweet(id: "3", replyToStatus: "2"),
            Fixtures.tweet(id: "1"),
            Fixtures.tweet(id: "2", replyToStatus: "1"),
        ]
        let threads = ThreadBuilder.combineThreads(tweets)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].map(\.idStr), ["1", "2", "3"])
    }

    func testForkedThreadIsEmittedDepthFirst() {
        // 1 ── 2 ── 3
        //   └─ 4 ── 5
        // Branches are emitted contiguously, chronologically-first branch first.
        let tweets = [
            Fixtures.tweet(id: "1"),
            Fixtures.tweet(id: "2", replyToStatus: "1"),
            Fixtures.tweet(id: "4", replyToStatus: "1"),
            Fixtures.tweet(id: "3", replyToStatus: "2"),
            Fixtures.tweet(id: "5", replyToStatus: "4"),
        ]
        let threads = ThreadBuilder.combineThreads(tweets)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].map(\.idStr), ["1", "2", "3", "4", "5"])
    }

    func testReplyToStrangerStartsItsOwnThread() {
        // The parent tweet is not in the archive, so the reply roots a thread.
        let tweets = [Fixtures.tweet(id: "10", replyToStatus: "999", replyToScreenName: "somebody")]
        let threads = ThreadBuilder.combineThreads(tweets)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0][0].idStr, "10")
    }

    func testMediaHeavyThreadStaysWhole() {
        // Threads always come out whole — fitting Day One's attachment limit
        // is ThreadSplitter's job at entry-posting time, not the builder's.
        func mediaTweet(id: String, count: Int, replyTo: String? = nil) -> Tweet {
            let media = (0..<count).map { Fixtures.photo(tco: "https://t.co/m\(id)_\($0)") }
            return Fixtures.tweet(id: id, replyToStatus: replyTo, extendedMedia: media)
        }
        let tweets = [
            mediaTweet(id: "1", count: 20),
            mediaTweet(id: "2", count: 20, replyTo: "1"),
            mediaTweet(id: "3", count: 2, replyTo: "2"),
        ]
        let threads = ThreadBuilder.combineThreads(tweets)
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads[0].map(\.idStr), ["1", "2", "3"])
    }

    func testRootsSortedNumericallyNotLexically() {
        let tweets = [Fixtures.tweet(id: "100"), Fixtures.tweet(id: "99")]
        let threads = ThreadBuilder.combineThreads(tweets)
        XCTAssertEqual(threads.map { $0[0].idStr }, ["99", "100"])
    }

    // MARK: - adoptOrphanSelfReplies

    func testOrphanSelfReplyIsAdoptedViaAccountId() {
        let orphan = Fixtures.tweet(
            id: "2", replyToStatus: "404", replyToUser: "381554576", replyToScreenName: "OldName")
        let adopted = ThreadBuilder.adoptOrphanSelfReplies(
            [orphan], ownAccountId: "381554576", currentUsername: nil)
        XCTAssertEqual(adopted, 1)
        XCTAssertNil(orphan.inReplyToStatusIdStr)
        XCTAssertNil(orphan.inReplyToUserIdStr)
        XCTAssertNil(orphan.inReplyToScreenName)
    }

    func testOrphanReplyToSomeoneElseIsNotAdopted() {
        let orphan = Fixtures.tweet(
            id: "2", replyToStatus: "404", replyToUser: "12345", replyToScreenName: "friend")
        let adopted = ThreadBuilder.adoptOrphanSelfReplies(
            [orphan], ownAccountId: "381554576", currentUsername: nil)
        XCTAssertEqual(adopted, 0)
        XCTAssertEqual(orphan.inReplyToStatusIdStr, "404")
    }

    func testUsernameFallbackIsCaseInsensitive() {
        let orphan = Fixtures.tweet(
            id: "2", replyToStatus: "404", replyToScreenName: "jonathanseriesx")
        let adopted = ThreadBuilder.adoptOrphanSelfReplies(
            [orphan], ownAccountId: nil, currentUsername: "JonathanSeriesX")
        XCTAssertEqual(adopted, 1)
    }

    func testReplyWithParentInArchiveIsNotAdopted() {
        let parent = Fixtures.tweet(id: "1")
        let reply = Fixtures.tweet(id: "2", replyToStatus: "1", replyToUser: "381554576")
        let adopted = ThreadBuilder.adoptOrphanSelfReplies(
            [parent, reply], ownAccountId: "381554576", currentUsername: nil)
        XCTAssertEqual(adopted, 0)
        XCTAssertEqual(reply.inReplyToStatusIdStr, "1")
    }
}
