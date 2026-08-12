import XCTest

final class EntryComposerTests: XCTestCase {

    private var config = ImportConfig(
        journalName: "Tweets Test",
        replyJournalName: "Twitter Replies Test",
        currentUsername: "JonathanSeriesX",
        shuffleMode: false,
        processTitlesWithLLM: false
    )

    // MARK: - escapeMarkdown

    func testEscapeInlineMarkdownChars() {
        XCTAssertEqual(
            EntryComposer.escapeMarkdown("a*b`c|d!e"),
            "a\\*b\\`c\\|d\\!e")
    }

    func testFirstLineHeadingIsKept() {
        let escaped = EntryComposer.escapeMarkdown("# Title\n\nbody")
        XCTAssertTrue(escaped.hasPrefix("# Title"))
    }

    func testLaterHeadingIsEscaped() {
        let escaped = EntryComposer.escapeMarkdown("# Title\n# fake heading")
        XCTAssertEqual(escaped, "# Title\n\\# fake heading")
    }

    func testListAndBlockquoteMarkersEscaped() {
        XCTAssertEqual(
            EntryComposer.escapeMarkdown("x\n- item\n+ plus\n> quote"),
            "x\n\\- item\n\\+ plus\n\\> quote")
    }

    // MARK: - aggregateThreadData

    func testMetricsWithUsernameAreLinks() {
        let tweet = Fixtures.tweet(id: "42", text: "hello", likes: 3, retweets: 2)
        let content = EntryComposer.aggregateThreadData([tweet], config: config)
        let url = "https://twitter.com/JonathanSeriesX/status/42"
        XCTAssertEqual(
            content.text,
            "hello\n\n[Likes: 3](\(url)/likes) ⭐️   [Retweets: 2](\(url)/retweets) 🔁   [Open on twitter.com](\(url))\n___\n")
    }

    func testMetricsWithoutUsernameArePlainText() {
        var config = self.config
        config.currentUsername = nil
        let tweet = Fixtures.tweet(id: "42", text: "hello", likes: 1)
        let content = EntryComposer.aggregateThreadData([tweet], config: config)
        XCTAssertEqual(content.text, "hello\n\nLikes: 1 ⭐️\n___\n")
    }

    func testZeroMetricsProduceOnlyOpenLink() {
        let tweet = Fixtures.tweet(id: "42", text: "quiet tweet")
        let content = EntryComposer.aggregateThreadData([tweet], config: config)
        XCTAssertEqual(
            content.text,
            "quiet tweet\n\n[Open on twitter.com](https://twitter.com/JonathanSeriesX/status/42)\n___\n")
    }

    func testTimeGapNoteAppearsAfterTenMinutes() {
        let start = PipelineDates.date(2020, 1, 1, 12, 0, 0)
        let thread = [
            Fixtures.tweet(id: "1", text: "first", createdAt: start),
            Fixtures.tweet(id: "2", text: "second", createdAt: start.addingTimeInterval(2 * 3600),
                           replyToStatus: "1"),
        ]
        let content = EntryComposer.aggregateThreadData(thread, config: config)
        XCTAssertTrue(content.text.contains(" (sent 2 hours later)"), content.text)
    }

    func testSmallTimeGapIsNotNoted() {
        let start = PipelineDates.date(2020, 1, 1, 12, 0, 0)
        let thread = [
            Fixtures.tweet(id: "1", text: "first", createdAt: start),
            Fixtures.tweet(id: "2", text: "second", createdAt: start.addingTimeInterval(9 * 60),
                           replyToStatus: "1"),
        ]
        let content = EntryComposer.aggregateThreadData(thread, config: config)
        XCTAssertFalse(content.text.contains("(sent"))
    }

    func testTagsMediaDateAndCoordinateCollected() {
        let start = PipelineDates.date(2019, 6, 1, 8, 30, 0)
        let first = Fixtures.tweet(id: "1", text: "a", createdAt: start, hashtags: ["f1"],
                                   coordinate: (latitude: 51.5, longitude: -0.12))
        first.mediaFiles = ["/m/1-a.jpg"]
        let second = Fixtures.tweet(id: "2", text: "b", createdAt: start.addingTimeInterval(60),
                                    replyToStatus: "1", hashtags: ["quali", "f1"])
        second.mediaFiles = ["/m/2-b.jpg"]

        let content = EntryComposer.aggregateThreadData([first, second], config: config)
        XCTAssertEqual(content.tags, ["f1", "quali", "f1"])
        XCTAssertEqual(content.mediaFiles, ["/m/1-a.jpg", "/m/2-b.jpg"])
        XCTAssertEqual(content.date, start)
        XCTAssertEqual(content.coordinate?.latitude, 51.5)
        XCTAssertEqual(content.coordinate?.longitude, -0.12)
    }

    // MARK: - formatSourceMarkdown

    func testSourceLinkBecomesMarkdown() {
        let html = "<a href=\"http://twitter.com/download/android\" rel=\"nofollow\">Twitter for Android</a>"
        XCTAssertEqual(
            EntryComposer.formatSourceMarkdown(html),
            "[Twitter for Android](http://twitter.com/download/android)")
    }

    func testPlainSourceStaysPlain() {
        XCTAssertEqual(EntryComposer.formatSourceMarkdown("web"), "web")
    }

    func testNilAndEmptySourceGiveNil() {
        XCTAssertNil(EntryComposer.formatSourceMarkdown(nil))
        XCTAssertNil(EntryComposer.formatSourceMarkdown(""))
    }

    // MARK: - buildEntryContent

    func testOwnTweetGetsTitleHeadingAndSourceFooter() {
        let tweet = Fixtures.tweet(
            id: "1", text: "hello",
            source: "<a href=\"https://mobile.twitter.com\" rel=\"nofollow\">Twitter Web App</a>")
        let text = EntryComposer.buildEntryContent(
            entryText: "hello\n\n___\n", firstTweet: tweet, category: "Tweeted",
            title: "Tweeted", config: config)
        XCTAssertTrue(text.hasPrefix("# Tweeted\n"))
        XCTAssertTrue(text.contains("Sent from [Twitter Web App](https://mobile.twitter.com)"), text)
    }

    func testReplyGetsConversationFooterInsteadOfSource() {
        let tweet = Fixtures.tweet(id: "9", text: "@alice yes", replyToStatus: "555")
        let text = EntryComposer.buildEntryContent(
            entryText: "@alice yes\n\n___\n", firstTweet: tweet,
            category: "Replied to @alice", title: "Replied to @alice", config: config)
        XCTAssertTrue(
            text.contains("In response to [this tweet](https://twitter.com/i/web/status/555), "
                          + "which is part of the conversation with @alice"),
            text)
        XCTAssertFalse(text.contains("Sent from"))
    }

    func testShowTweetSourceOffOmitsFooter() {
        var config = self.config
        config.showTweetSource = false
        let tweet = Fixtures.tweet(
            id: "1", text: "hello",
            source: "<a href=\"https://x.com\">X</a>")
        let text = EntryComposer.buildEntryContent(
            entryText: "hello\n", firstTweet: tweet, category: "Tweeted",
            title: "Tweeted", config: config)
        XCTAssertFalse(text.contains("Sent from"))
    }

    // MARK: - targetJournal

    func testRepliesGoToReplyJournal() {
        XCTAssertEqual(
            EntryComposer.targetJournal(category: "Replied to @a", tweetId: "1", config: config),
            "Twitter Replies Test")
    }

    func testRepliesSkippedWithoutReplyJournal() {
        var config = self.config
        config.replyJournalName = nil
        XCTAssertNil(
            EntryComposer.targetJournal(category: "Replied to @a", tweetId: "1", config: config))
    }

    func testRetweetsSkippedWhenIgnored() {
        var config = self.config
        config.ignoreRetweets = true
        XCTAssertNil(
            EntryComposer.targetJournal(category: "Retweeted @a", tweetId: "1", config: config))
        XCTAssertEqual(
            EntryComposer.targetJournal(category: "Tweeted", tweetId: "1", config: config),
            "Tweets Test")
    }

    // MARK: - generateEntryTitle

    func testLLMTitleUsedForThreads() async {
        var config = self.config
        config.processTitlesWithLLM = true
        let title = await EntryComposer.generateEntryTitle(
            entryText: "text", category: "Wrote a thread", threadLength: 3,
            mediaFiles: [], config: config
        ) { _, _ in "Wrote about Formula 1" }
        XCTAssertEqual(title, "Wrote about Formula 1")
    }

    func testCategoryKeptWhenLLMDeclines() async {
        var config = self.config
        config.processTitlesWithLLM = true
        let title = await EntryComposer.generateEntryTitle(
            entryText: "text", category: "Wrote a thread", threadLength: 3,
            mediaFiles: [], config: config
        ) { _, _ in nil }
        XCTAssertEqual(title, "Wrote a thread")
    }

    func testRepliesNeverGetLLMTitles() async {
        var config = self.config
        config.processTitlesWithLLM = true
        var llmCalled = false
        let title = await EntryComposer.generateEntryTitle(
            entryText: "text", category: "Replied to @a", threadLength: 2,
            mediaFiles: [], config: config
        ) { _, _ in
            llmCalled = true
            return "should not happen"
        }
        XCTAssertEqual(title, "Replied to @a")
        XCTAssertFalse(llmCalled)
    }

    func testSingleTweetsTitledOnlyWhenEnabled() async {
        var config = self.config
        config.processTitlesWithLLM = true
        config.llmTitlesForSingleTweets = false
        let title = await EntryComposer.generateEntryTitle(
            entryText: "text", category: "Tweeted", threadLength: 1,
            mediaFiles: [], config: config
        ) { _, _ in "Not wanted" }
        XCTAssertEqual(title, "Tweeted")

        config.llmTitlesForSingleTweets = true
        let titled = await EntryComposer.generateEntryTitle(
            entryText: "text", category: "Tweeted", threadLength: 1,
            mediaFiles: [], config: config
        ) { _, _ in "Shared a thought" }
        XCTAssertEqual(titled, "Shared a thought")
    }

    // MARK: - Humanize

    func testNaturalDelta() {
        XCTAssertEqual(Humanize.naturalDelta(30 * 60), "30 minutes")
        XCTAssertEqual(Humanize.naturalDelta(65 * 60), "an hour")
        XCTAssertEqual(Humanize.naturalDelta(3 * 3600), "3 hours")
        XCTAssertEqual(Humanize.naturalDelta(86_400), "a day")
        XCTAssertEqual(Humanize.naturalDelta(5 * 86_400), "5 days")
        XCTAssertEqual(Humanize.naturalDelta(40 * 86_400), "a month")
        XCTAssertEqual(Humanize.naturalDelta(100 * 86_400), "3 months")
        XCTAssertEqual(Humanize.naturalDelta(365 * 86_400), "a year")
        XCTAssertEqual(Humanize.naturalDelta(370 * 86_400), "1 year, 5 days")
        XCTAssertEqual(Humanize.naturalDelta(395 * 86_400), "1 year, 1 month")
        XCTAssertEqual(Humanize.naturalDelta(3 * 365 * 86_400), "3 years")
    }
}
