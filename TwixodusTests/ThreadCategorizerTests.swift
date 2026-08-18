import XCTest

final class ThreadCategorizerTests: XCTestCase {

    private let context = ThreadCategorizer.Context(
        ownTweetIDs: ["100", "200"], currentUsername: "JonathanSeriesX")

    func testStandaloneTweet() {
        let category = ThreadCategorizer.threadCategory(
            [Fixtures.tweet(id: "1", text: "just a thought")], context: context)
        XCTAssertEqual(category, "Tweeted")
    }

    func testMultiTweetThread() {
        let thread = [
            Fixtures.tweet(id: "1", text: "part one"),
            Fixtures.tweet(id: "2", text: "part two", replyToStatus: "1"),
        ]
        XCTAssertEqual(ThreadCategorizer.threadCategory(thread, context: context), "Wrote a thread")
    }

    func testRetweetExtractsNameAndStripsPrefixInPlace() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "RT @cooluser: the actual content",
            mentions: [UserMention(screenName: "CoolUser", name: "Cool User")]
        )
        let category = ThreadCategorizer.threadCategory([tweet], context: context)
        XCTAssertEqual(category, "Retweeted Cool User")
        XCTAssertEqual(tweet.fullText, "the actual content")
    }

    func testRetweetFallsBackToHandleWhenNotInMentions() {
        let tweet = Fixtures.tweet(id: "1", text: "RT @stranger: hi")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Retweeted @stranger")
    }

    func testReplyListsNamesInTextOrder() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "@alice @bob I agree with both of you",
            replyToStatus: "555",
            mentions: [
                UserMention(screenName: "bob", name: "Bob B"),
                UserMention(screenName: "alice", name: "Alice A"),
            ]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Replied to Alice A and Bob B")
    }

    func testReplyFallsBackToInReplyToScreenName() {
        let tweet = Fixtures.tweet(
            id: "1", text: "no mentions in text", replyToStatus: "555",
            replyToScreenName: "carol")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Replied to @carol")
    }

    func testReplyWithThreeNamesUsesOxfordComma() {
        let tweet = Fixtures.tweet(
            id: "1", text: "@a @b @c hello", replyToStatus: "5")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Replied to @a, @b, and @c")
    }

    func testQuoteTweetOfSomeoneElse() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "look at this [take](https://twitter.com/somebody/status/999)",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://twitter.com/somebody/status/999",
                             displayURL: nil)]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted @somebody")
    }

    func testQuoteOfOwnArchivedTweetIsQuotedMyself() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "still true https://t.co/q",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://twitter.com/WhoeverIWasThen/status/100",
                             displayURL: nil)]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted myself")
    }

    func testQuoteOfOwnUsernameIsQuotedMyselfEvenIfNotInArchive() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "deleted but mine https://t.co/q",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://twitter.com/jonathanseriesx/status/12345",
                             displayURL: nil)]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted myself")
    }

    // MARK: - Fallbacks that used to produce joke titles (SOB-83)

    func testRetweetWithoutColonRecoversHandleWithoutMutatingText() {
        // "RT @xdadevelopers Thread: …" — the strict extractor needs a colon
        // right after the handle, so it fails; the fallback reads the handle
        // without stripping the prefix.
        let tweet = Fixtures.tweet(id: "1", text: "RT @xdadevelopers Thread: official updates list")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Retweeted @xdadevelopers")
        XCTAssertEqual(tweet.fullText, "RT @xdadevelopers Thread: official updates list",
                       "the fallback must not mutate the text")
    }

    func testManualQuoteRecoversInlineHandle() {
        // Pre-quote-tweet era: commentary, then " RT @user: …" — no status URL.
        let tweet = Fixtures.tweet(id: "1", text: "Agreed! RT @AngelWZR: build 9364 is ready")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted @AngelWZR")
    }

    func testManualQuoteOfMyself() {
        let tweet = Fixtures.tweet(id: "1", text: "still true RT @JonathanSeriesX: called it")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted myself")
    }

    func testNamelessQuoteFallsBackToSomeone() {
        // "RT :" quotes nobody by name; a twitter link that isn't a status
        // link forces the quote branch without a parseable target.
        let tweet = Fixtures.tweet(
            id: "1",
            text: "Overslept! RT : first time late for work https://t.co/q",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://twitter.com/i/redirect",
                             displayURL: nil)]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted someone")
    }

    func testHashbangAndMobileStatusLinksAreParsed() {
        let hashbang = Fixtures.tweet(
            id: "1", text: "https://t.co/q",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://twitter.com/#!/oldtimer/status/123",
                             displayURL: nil)])
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([hashbang], context: context),
            "Quoted @oldtimer")

        // mobile./statuses links don't pass the quote-link gate (it wants a
        // literal https://twitter.com or https://x.com), but the manual-RT
        // branch still resolves them through the same loosened regex.
        let mobile = Fixtures.tweet(
            id: "2", text: "so true RT @onthego: commuting thoughts https://t.co/q",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "http://mobile.twitter.com/onthego/statuses/456",
                             displayURL: nil)])
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([mobile], context: context),
            "Quoted @onthego")
    }

    func testBareAtSignIsJustATweetNotACallout() {
        // "@ не нашел…" — an @ with no handle after it is an ordinary tweet.
        let tweet = Fixtures.tweet(id: "1", text: "@ couldn't find the support form anywhere")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Tweeted")
    }

    func testXDotComQuoteAlsoDetected() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "https://t.co/q",
            urls: [URLEntity(url: "https://t.co/q",
                             expandedURL: "https://x.com/somebody/status/777",
                             displayURL: nil)]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Quoted @somebody")
    }

    func testMediaLinkIsNotMistakenForQuote() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "photo [{attachment}]",
            urls: [URLEntity(url: "https://t.co/pic",
                             expandedURL: "https://twitter.com/me/status/1/photo/1",
                             displayURL: nil)],
            extendedMedia: [Fixtures.photo(tco: "https://t.co/pic")]
        )
        XCTAssertEqual(ThreadCategorizer.threadCategory([tweet], context: context), "Tweeted")
    }

    func testCalloutTweet() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "@support your app is broken",
            mentions: [UserMention(screenName: "support", name: "App Support")]
        )
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Callout to App Support")
    }

    func testDotCalloutTweet() {
        let tweet = Fixtures.tweet(id: "1", text: ".@everyone hear ye")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Callout to @everyone")
    }

    func testReplyBeatsCallout() {
        let tweet = Fixtures.tweet(
            id: "1", text: "@alice sure thing", replyToStatus: "5")
        XCTAssertEqual(
            ThreadCategorizer.threadCategory([tweet], context: context),
            "Replied to @alice")
    }

    func testJoinNamesNaturalLanguage() {
        XCTAssertEqual(ThreadCategorizer.joinNamesNaturalLanguage([]), "")
        XCTAssertEqual(ThreadCategorizer.joinNamesNaturalLanguage(["A"]), "A")
        XCTAssertEqual(ThreadCategorizer.joinNamesNaturalLanguage(["A", "B"]), "A and B")
        XCTAssertEqual(ThreadCategorizer.joinNamesNaturalLanguage(["A", "B", "C"]), "A, B, and C")
    }
}
