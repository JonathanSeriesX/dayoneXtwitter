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
