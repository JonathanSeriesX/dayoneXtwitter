import XCTest

final class XcancelLinksTests: XCTestCase {

    private var config = ImportConfig(
        journalName: "Tweets Test",
        replyJournalName: "Twitter Replies Test",
        currentUsername: "JonathanSeriesX",
        importOrder: .oldestFirst,
        useXcancelLinks: true,
        processTitlesWithLLM: false
    )

    // MARK: - rewriteTweetLinks

    func testStatusLinksAreRewritten() {
        XCTAssertEqual(
            XcancelLinks.rewriteTweetLinks(in: "see https://twitter.com/jack/status/20 wow"),
            "see https://xcancel.com/jack/status/20 wow")
        XCTAssertEqual(
            XcancelLinks.rewriteTweetLinks(in: "see https://x.com/jack/status/20?s=46 wow"),
            "see https://xcancel.com/jack/status/20?s=46 wow")
    }

    func testHostVariantsAreRewritten() {
        XCTAssertEqual(
            XcancelLinks.rewriteTweetLinks(in: "https://mobile.twitter.com/jack/status/20"),
            "https://xcancel.com/jack/status/20")
        XCTAssertEqual(
            XcancelLinks.rewriteTweetLinks(in: "http://www.x.com/jack/statuses/20"),
            "https://xcancel.com/jack/statuses/20")
        XCTAssertEqual(
            XcancelLinks.rewriteTweetLinks(in: "https://twitter.com/i/web/status/99"),
            "https://xcancel.com/i/web/status/99")
    }

    func testMarkdownLinkKeepsItsLabel() {
        // LinkExpansion produces [display](expanded); only the URL half has a
        // scheme, so the visible label must stay as the tweet showed it.
        XCTAssertEqual(
            XcancelLinks.rewriteTweetLinks(
                in: "[x.com/jack/status/2…](https://x.com/jack/status/20?s=46)"),
            "[x.com/jack/status/2…](https://xcancel.com/jack/status/20?s=46)")
    }

    func testLookalikeDomainsAreLeftAlone() {
        for url in [
            "https://somesitex.com/jack/status/20",  // merely ends in "x.com"
            "https://faketwitter.com/jack/status/20",
            "https://x.company/jack/status/20",
            "https://twitter.com.evil.io/jack/status/20",
        ] {
            XCTAssertEqual(XcancelLinks.rewriteTweetLinks(in: url), url)
        }
    }

    func testNonTweetTwitterLinksAreLeftAlone() {
        for url in [
            "http://twitter.com/download/android",  // the "Sent from" client link
            "https://twitter.com/jack",             // profile, not a tweet
            "https://x.com/settings/account",
        ] {
            XCTAssertEqual(XcancelLinks.rewriteTweetLinks(in: url), url)
        }
    }

    // MARK: - Entry composition with the setting on

    func testMetricsLinksUseXcancel() {
        let tweet = Fixtures.tweet(id: "42", text: "hello", likes: 3, retweets: 2)
        let content = EntryComposer.aggregateThreadData([tweet], config: config)
        let url = "https://xcancel.com/JonathanSeriesX/status/42"
        XCTAssertEqual(
            content.text,
            "hello\n\n[Likes: 3](\(url)/likes) ⭐️   [Retweets: 2](\(url)/retweets) 🔁   [Open on xcancel.com](\(url))\n___\n")
    }

    func testMetricsLinksStayOnTwitterWhenDisabled() {
        var config = self.config
        config.useXcancelLinks = false
        let tweet = Fixtures.tweet(id: "42", text: "hello")
        let content = EntryComposer.aggregateThreadData([tweet], config: config)
        XCTAssertEqual(
            content.text,
            "hello\n\n[Open on twitter.com](https://twitter.com/JonathanSeriesX/status/42)\n___\n")
    }

    func testReplyContextLinkUsesXcancel() {
        let tweet = Fixtures.tweet(id: "42", text: "@bob agreed", replyToStatus: "99")
        let entry = EntryComposer.buildEntryContent(
            entryText: "@bob agreed\n", firstTweet: tweet,
            category: "Replied to @bob", title: "Replied to @bob", config: config)
        XCTAssertTrue(entry.contains("(https://xcancel.com/i/web/status/99)"), entry)
    }

    func testSentFromFooterIsNeverRewritten() {
        let tweet = Fixtures.tweet(
            id: "42", text: "hello",
            source: #"<a href="http://twitter.com/download/android" rel="nofollow">Twitter for Android</a>"#)
        let entry = EntryComposer.buildEntryContent(
            entryText: "hello\n", firstTweet: tweet,
            category: "Tweeted", title: "Tweeted", config: config)
        XCTAssertTrue(entry.contains("(http://twitter.com/download/android)"), entry)
        XCTAssertFalse(entry.contains("xcancel"), entry)
    }
}
