import XCTest

final class HydrationTests: XCTestCase {

    private var config = ImportConfig(
        journalName: "Tweets Test",
        replyJournalName: "Twitter Replies Test",
        currentUsername: "JonathanSeriesX",
        importOrder: .oldestFirst,
        processTitlesWithLLM: false
    )

    private func makeStore() -> HydrationStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("twitter-2026-01-15-\(UUID().uuidString)")
        return HydrationStore(archiveRoot: root)
    }

    private func okRecord(_ data: HydratedTweetData) -> HydrationRecord {
        HydrationRecord(status: HydrationRecord.statusOK, reason: nil, fetchedAt: Date(), tweet: data)
    }

    private func original(
        id: String = "999",
        screenName: String = "daken_",
        name: String? = "Arthur",
        createdAt: String? = "2017-11-17T22:53:57.000Z",
        text: String,
        urls: [HydratedURL] = [],
        media: [HydratedMediaFile] = []
    ) -> HydratedTweetData {
        HydratedTweetData(idStr: id, screenName: screenName, name: name,
                          createdAt: createdAt, text: text, urls: urls, media: media)
    }

    // MARK: - Store folder naming

    func testHydrationFolderNameForDatedArchive() {
        let url = HydrationStore.folderURL(
            for: URL(fileURLWithPath: "/x/twitter-2026-08-17-abcdef0123"))
        XCTAssertEqual(url.path, "/x/twitter-2026-08-17-hydration")
    }

    func testHydrationFolderNameForOtherFolders() {
        let url = HydrationStore.folderURL(for: URL(fileURLWithPath: "/x/my-archive"))
        XCTAssertEqual(url.path, "/x/my-archive-hydration")
    }

    // MARK: - Truncation detection

    func testTruncationDetection() {
        XCTAssertTrue(ArchiveLoading.looksTruncated("RT @a: cut here…"))
        XCTAssertTrue(ArchiveLoading.looksTruncated("RT @a: cut https://t.co/abc…"))
        XCTAssertTrue(ArchiveLoading.looksTruncated("RT @a: old style..."))
        XCTAssertFalse(ArchiveLoading.looksTruncated("RT @a: complete tweet"))
    }

    // MARK: - Planner

    func testPlannerSplitsPendingFromDone() {
        let store = makeStore()
        let pending = Fixtures.tweet(id: "1", text: "RT @a: cut…")
        pending.isRetweet = true
        pending.isTruncatedRetweet = true
        let done = Fixtures.tweet(id: "2", text: "RT @b: cut…")
        done.isRetweet = true
        done.isTruncatedRetweet = true
        store.retweets["2"] = okRecord(original(text: "full"))

        let plan = HydrationPlanner.plan(
            tweets: [pending, done], ownTweetIDs: ["1", "2"],
            archiveUsername: "me", store: store)
        XCTAssertEqual(plan.pendingRetweets.map(\.idStr), ["1"])
        XCTAssertEqual(plan.retweetsDone, 1)
    }

    func testPlannerFindsQuotesAndSkipsOwnAndRetweets() {
        let store = makeStore()
        let quoteURL = URLEntity(
            url: "https://t.co/q1",
            expandedURL: "https://x.com/somebody/status/555",
            displayURL: "x.com/somebody/s…")
        let quote = Fixtures.tweet(id: "1", text: "comment", urls: [quoteURL])
        let sameQuote = Fixtures.tweet(id: "2", text: "again", urls: [quoteURL])
        let selfQuote = Fixtures.tweet(id: "3", text: "mine", urls: [URLEntity(
            url: "https://t.co/q2",
            expandedURL: "https://x.com/whoever/status/42",
            displayURL: nil)])
        let retweetWithLink = Fixtures.tweet(id: "4", text: "RT @a: look", urls: [quoteURL])
        retweetWithLink.isRetweet = true

        let plan = HydrationPlanner.plan(
            tweets: [quote, sameQuote, selfQuote, retweetWithLink],
            ownTweetIDs: ["1", "2", "3", "4", "42"],
            archiveUsername: "me", store: store)
        // The two tweets quoting 555 collapse into one fetch; the self-quote
        // (id 42 is in the archive) and the retweet's link are skipped.
        XCTAssertEqual(plan.pendingQuotes.map(\.statusId), ["555"])
    }

    func testPlannerFindsMissingMediaSource() {
        let store = makeStore()
        let video = MediaEntity(
            url: "https://t.co/v", type: "video", mediaURLHTTPS: nil,
            videoVariants: [
                VideoVariant(contentType: "video/mp4", bitrate: "832000",
                             url: "https://video.twimg.com/ext_tw_video/1/pu/vid/640x360/low.mp4"),
                VideoVariant(contentType: "video/mp4", bitrate: "2176000",
                             url: "https://video.twimg.com/ext_tw_video/1/pu/vid/1280x720/high.mp4?tag=1"),
            ])
        let tweet = Fixtures.tweet(id: "7", text: "clip", extendedMedia: [video])
        tweet.mediaFiles = ["/nonexistent/tweets_media/7-high.mp4"]

        let plan = HydrationPlanner.plan(
            tweets: [tweet], ownTweetIDs: ["7"], archiveUsername: nil, store: store)
        XCTAssertEqual(plan.pendingMedia.count, 1)
        XCTAssertEqual(plan.pendingMedia[0].fileName, "7-high.mp4")
        XCTAssertEqual(plan.pendingMedia[0].sourceURL,
                       "https://video.twimg.com/ext_tw_video/1/pu/vid/1280x720/high.mp4?tag=1")
    }

    // MARK: - Overlay

    func testOverlayRebuildsTruncatedRetweet() {
        let store = makeStore()
        let tweet = Fixtures.tweet(id: "1", text: "RT @daken_: cut off here…")
        tweet.isRetweet = true
        tweet.isTruncatedRetweet = true
        store.retweets["1"] = okRecord(original(
            text: "the full text with a link https://t.co/abc",
            urls: [HydratedURL(tco: "https://t.co/abc",
                               expanded: "https://example.com/page",
                               display: "example.com/page")]))

        HydrationOverlay.apply(tweets: [tweet], store: store)
        XCTAssertEqual(
            tweet.fullText,
            "RT @daken_: the full text with a link [example.com/page](https://example.com/page)")
    }

    func testOverlayOmitsPrefixWhenAlreadyStripped() {
        // Categorization strips "RT @user:" in place; a later overlay run must
        // not bring it back.
        let store = makeStore()
        let tweet = Fixtures.tweet(id: "1", text: "cut off here…")
        tweet.isRetweet = true
        tweet.isTruncatedRetweet = true
        store.retweets["1"] = okRecord(original(text: "the full text"))

        HydrationOverlay.apply(tweets: [tweet], store: store)
        XCTAssertEqual(tweet.fullText, "the full text")
    }

    func testOverlayAttachesQuoteAndStripsTrailingLink() {
        let store = makeStore()
        let tweet = Fixtures.tweet(
            id: "1",
            text: "Ребят, научите [x.com/unusual_whales…](https://x.com/unusual_whales/status/555)",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://x.com/unusual_whales/status/555",
                             displayURL: "x.com/unusual_whales…")])
        store.quotes["555"] = okRecord(original(
            id: "555", screenName: "unusual_whales", name: "unusual_whales",
            createdAt: "2026-01-12T15:00:00.000Z",
            text: "\"Gen Z has cut down on their effort at work,\" per YF."))

        HydrationOverlay.apply(tweets: [tweet], store: store)
        XCTAssertEqual(tweet.fullText, "Ребят, научите")
        XCTAssertEqual(tweet.hydratedQuote?.name, "unusual_whales")
        XCTAssertEqual(tweet.hydratedQuote?.statusId, "555")
    }

    func testOverlayKeepsMidTextLink() {
        let store = makeStore()
        let tweet = Fixtures.tweet(
            id: "1",
            text: "see [x.com/a/status/555](https://x.com/a/status/555) which is wild",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://x.com/a/status/555",
                             displayURL: nil)])
        store.quotes["555"] = okRecord(original(id: "555", screenName: "a", text: "quoted"))

        HydrationOverlay.apply(tweets: [tweet], store: store)
        XCTAssertTrue(tweet.fullText.contains("which is wild"))
        XCTAssertTrue(tweet.fullText.contains("x.com/a/status/555"))
        XCTAssertNotNil(tweet.hydratedQuote)
    }

    // MARK: - The blockquote in the entry

    func testQuoteBlockFormat() {
        let quote = HydratedQuote(
            statusId: "555", screenName: "unusual_whales", name: "unusual_whales",
            createdAt: PipelineDates.date(2026, 1, 12, 15, 0, 0),
            text: "\"Gen Z has cut down on their effort at work,\" per YF.")
        let block = EntryComposer.quoteBlock(
            quote, quotingDate: PipelineDates.date(2026, 1, 14), useXcancelLinks: false)
        let marker = EntryComposer.blockquoteMarker
        XCTAssertEqual(block, marker
            + "Quoting [unusual_whales from Jan 12](https://twitter.com/unusual_whales/status/555):\n"
            + marker
            + "\"Gen Z has cut down on their effort at work,\" per YF.")
    }

    func testQuoteBlockAddsYearWhenDifferent() {
        let quote = HydratedQuote(
            statusId: "5", screenName: "a", name: "Somebody",
            createdAt: PipelineDates.date(2013, 5, 1), text: "old wisdom")
        let block = EntryComposer.quoteBlock(
            quote, quotingDate: PipelineDates.date(2026, 1, 14), useXcancelLinks: false)
        XCTAssertTrue(block.contains("Somebody from May 1, 2013"))
    }

    func testQuoteBlockSurvivesMarkdownEscaping() {
        let tweet = Fixtures.tweet(id: "1", text: "my comment")
        tweet.hydratedQuote = HydratedQuote(
            statusId: "555", screenName: "a", name: "Somebody",
            createdAt: nil, text: "quoted line")
        let content = EntryComposer.aggregateThreadData([tweet], config: config)
        let entry = EntryComposer.buildEntryContent(
            entryText: content.text, firstTweet: tweet, category: "Quoted @a",
            title: "Quoted @a", config: config, isContinuation: false)
        // The injected blockquote renders as a real one...
        XCTAssertTrue(entry.contains("> Quoting [Somebody](https://twitter.com/a/status/555):"))
        XCTAssertTrue(entry.contains("> quoted line"))
        // ...while a ">" typed in tweet text stays escaped (see escapeMarkdown).
        XCTAssertFalse(entry.contains(EntryComposer.blockquoteMarker))
    }

    func testQuoteBlockUsesXcancelHost() {
        let quote = HydratedQuote(
            statusId: "5", screenName: "a", name: "S", createdAt: nil, text: "t")
        let block = EntryComposer.quoteBlock(
            quote, quotingDate: PipelineDates.date(2026, 1, 1), useXcancelLinks: true)
        XCTAssertTrue(block.contains("https://xcancel.com/a/status/5"))
    }

    // MARK: - Store round-trip

    func testStoreRoundTrip() throws {
        let store = makeStore()
        store.retweets["1"] = okRecord(original(text: "hello"))
        store.quotes["2"] = HydrationRecord(
            status: HydrationRecord.statusUnavailable, reason: "suspended",
            fetchedAt: Date(), tweet: nil)
        try store.save()
        defer { try? FileManager.default.removeItem(at: store.folder) }

        let reloaded = HydrationStore(archiveRoot: store.folder
            .deletingLastPathComponent()
            .appendingPathComponent("twitter-2026-01-15-whatever"))
        XCTAssertEqual(reloaded.folder.path, store.folder.path)
        XCTAssertTrue(reloaded.exists)
        reloaded.load()
        XCTAssertEqual(reloaded.retweets["1"]?.tweet?.text, "hello")
        XCTAssertEqual(reloaded.quotes["2"]?.reason, "suspended")
        XCTAssertFalse(reloaded.quotes["2"]!.isOK)
    }

    // MARK: - Syndication token

    func testTokenDerivation() {
        // The widget's JS: ((id / 1e15) * Math.PI).toString(36)
        //                       .replace(/(0+|\.)/g, '')
        let token = SyndicationClient.token(for: "1899882561553207629")
        XCTAssertEqual(token, "4lsnnlkevnz4k")
        XCTAssertFalse(token.contains("0"))
        XCTAssertFalse(token.contains("."))
        // Deterministic: same id, same token.
        XCTAssertEqual(token, SyndicationClient.token(for: "1899882561553207629"))
    }
}
