import XCTest

final class TwitterArchiveLoaderTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("twixodus-loader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeArchive(named name: String, parts: [String: String]) throws -> URL {
        let data = tempDir.appendingPathComponent("\(name)/data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        for (file, content) in parts {
            try content.write(to: data.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        return tempDir.appendingPathComponent(name)
    }

    private let sampleTweetJS = """
        window.YTD.tweets.part0 = [
          {
            "tweet" : {
              "id_str" : "123",
              "full_text" : "hello world",
              "created_at" : "Fri Mar 21 04:40:00 +0000 2006",
              "favorite_count" : "5",
              "retweet_count" : "2",
              "source" : "web",
              "entities" : { "hashtags" : [ { "text" : "hi" } ], "urls" : [ ], "user_mentions" : [ ] }
            }
          }
        ]
        """

    func testFindsArchiveWhenFolderIsArchiveRoot() throws {
        let root = try makeArchive(named: "twitter-2026-01-15-abc", parts: ["tweets.js": sampleTweetJS])
        let archive = try TwitterArchiveLoader.findArchive(at: root)
        XCTAssertEqual(archive.tweetsJSPaths.map(\.lastPathComponent), ["tweets.js"])
    }

    func testFindsNewestArchiveInsideContainerFolder() throws {
        _ = try makeArchive(named: "twitter-2024-01-01-old", parts: ["tweets.js": sampleTweetJS])
        _ = try makeArchive(named: "twitter-2026-01-15-new", parts: ["tweets.js": sampleTweetJS])
        let archive = try TwitterArchiveLoader.findArchive(at: tempDir)
        XCTAssertTrue(archive.dataFolder.path.contains("twitter-2026-01-15-new"))
    }

    func testMultiPartArchiveLoadedInOrder() throws {
        let root = try makeArchive(named: "twitter-2026-01-15-abc", parts: [
            "tweets.js": sampleTweetJS,
            "tweets-part1.js": sampleTweetJS.replacingOccurrences(of: "123", with: "456"),
            "tweets-part2.js": sampleTweetJS.replacingOccurrences(of: "123", with: "789"),
        ])
        let archive = try TwitterArchiveLoader.findArchive(at: root)
        XCTAssertEqual(
            archive.tweetsJSPaths.map(\.lastPathComponent),
            ["tweets.js", "tweets-part1.js", "tweets-part2.js"])

        let (tweets, ownIDs) = try TwitterArchiveLoader.loadTweets(from: archive)
        XCTAssertEqual(tweets.map(\.idStr), ["123", "456", "789"])
        XCTAssertEqual(ownIDs, ["123", "456", "789"])
    }

    func testMissingArchiveThrows() {
        XCTAssertThrowsError(try TwitterArchiveLoader.findArchive(at: tempDir))
    }

    func testTweetFieldsParsed() throws {
        let root = try makeArchive(named: "twitter-2026-01-15-abc", parts: ["tweets.js": sampleTweetJS])
        let archive = try TwitterArchiveLoader.findArchive(at: root)
        let (tweets, _) = try TwitterArchiveLoader.loadTweets(from: archive)

        let tweet = try XCTUnwrap(tweets.first)
        XCTAssertEqual(tweet.fullText, "hello world")
        XCTAssertEqual(tweet.createdAt, PipelineDates.date(2006, 3, 21, 4, 40, 0))
        XCTAssertEqual(tweet.favoriteCount, 5)
        XCTAssertEqual(tweet.retweetCount, 2)
        XCTAssertEqual(tweet.hashtags, ["hi"])
        XCTAssertNil(tweet.extendedMedia)
    }

    func testAccountInfoParsed() throws {
        let accountJS = """
            window.YTD.account.part0 = [
              {
                "account" : {
                  "email" : "x@example.com",
                  "createdVia" : "web",
                  "username" : "JonathanSeriesX",
                  "accountId" : "381554576",
                  "createdAt" : "2011-09-27T17:29:22.000Z",
                  "accountDisplayName" : "Jonathan"
                }
              }
            ]
            """
        let root = try makeArchive(named: "twitter-2026-01-15-abc",
                                   parts: ["tweets.js": sampleTweetJS, "account.js": accountJS])
        let archive = try TwitterArchiveLoader.findArchive(at: root)
        let info = TwitterArchiveLoader.loadAccountInfo(from: archive)
        XCTAssertEqual(info.accountId, "381554576")
        XCTAssertEqual(info.username, "JonathanSeriesX")
    }
}

final class DayOneCLITests: XCTestCase {

    func testCommandOrderIsOptionsFirstThenNew() {
        let cli = DayOneCLI(binaryPath: "/usr/local/bin/dayone")
        let command = cli.buildCommand(
            text: "entry text",
            journal: "Tweets",
            tags: ["f1", "quali"],
            date: PipelineDates.date(2020, 5, 17, 9, 30, 0),
            coordinate: (latitude: 51.5, longitude: -0.12),
            attachments: ["/tmp/a.jpg", "/tmp/b.mp4"]
        )
        XCTAssertEqual(command, [
            "--journal", "Tweets",
            "--date", "2020-05-17 09:30:00",
            "-z", "UTC",
            "--coordinate", "51.5", "-0.12",
            "--tags", "f1", "quali",
            "--attachments", "/tmp/a.jpg", "/tmp/b.mp4",
            "--", "new", "entry text",
        ])
    }

    func testMinimalCommand() {
        let cli = DayOneCLI(binaryPath: "/usr/local/bin/dayone")
        XCTAssertEqual(
            cli.buildCommand(text: "hi", journal: nil, tags: [], date: nil,
                             coordinate: nil, attachments: []),
            ["--", "new", "hi"])
    }
}

final class OllamaNormalizeTests: XCTestCase {

    func testStripsQuotesAndTrailingPeriod() {
        XCTAssertEqual(OllamaClient.normalizeTitle("\u{201C}Wrote about Formula 1.\u{201D}"),
                       "Wrote about Formula 1")
    }

    func testDeclinedTitleGivesNil() {
        XCTAssertNil(OllamaClient.normalizeTitle("Tweeted"))
        XCTAssertNil(OllamaClient.normalizeTitle(" tweeted. "))
        XCTAssertNil(OllamaClient.normalizeTitle(""))
    }

    func testRamblingTitlesRejected() {
        XCTAssertNil(OllamaClient.normalizeTitle(String(repeating: "long ", count: 20)))
        XCTAssertNil(OllamaClient.normalizeTitle("one two three four five six seven eight nine ten eleven"))
    }

    func testFirstLineOnlyAndCapitalized() {
        XCTAssertEqual(OllamaClient.normalizeTitle("wrote about cars\nand some rambling"),
                       "Wrote about cars")
    }
}
