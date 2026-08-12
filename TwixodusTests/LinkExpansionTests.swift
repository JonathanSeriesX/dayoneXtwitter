import XCTest

final class LinkExpansionTests: XCTestCase {

    private let mediaFolder = URL(fileURLWithPath: "/archive/data/tweets_media")

    func testOrdinaryLinkBecomesMarkdown() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "Check this out https://t.co/abc123",
            urls: [URLEntity(url: "https://t.co/abc123",
                             expandedURL: "https://example.com/article",
                             displayURL: "example.com/article")]
        )
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(
            tweet.fullText,
            "Check this out [example.com/article](https://example.com/article)")
        XCTAssertEqual(tweet.mediaFiles, [])
    }

    func testLinkWithoutDisplayURLFallsBackToExpanded() {
        let tweet = Fixtures.tweet(
            id: "1",
            text: "https://t.co/abc",
            urls: [URLEntity(url: "https://t.co/abc",
                             expandedURL: "https://example.com",
                             displayURL: nil)]
        )
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "[https://example.com](https://example.com)")
    }

    func testPhotoBecomesAttachmentPlaceholder() {
        let tweet = Fixtures.tweet(
            id: "42",
            text: "look! https://t.co/pic1",
            extendedMedia: [Fixtures.photo(tco: "https://t.co/pic1",
                                           mediaURL: "https://pbs.twimg.com/media/XYZ.jpg")]
        )
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "look! [{attachment}]")
        XCTAssertEqual(tweet.mediaFiles, ["/archive/data/tweets_media/42-XYZ.jpg"])
    }

    func testMultiplePhotosOnOneTcoURL() {
        let tweet = Fixtures.tweet(
            id: "42",
            text: "four pics https://t.co/pics",
            extendedMedia: [
                Fixtures.photo(tco: "https://t.co/pics", mediaURL: "https://pbs.twimg.com/media/A.jpg"),
                Fixtures.photo(tco: "https://t.co/pics", mediaURL: "https://pbs.twimg.com/media/B.png"),
            ]
        )
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "four pics [{attachment}][{attachment}]")
        XCTAssertEqual(tweet.mediaFiles, [
            "/archive/data/tweets_media/42-A.jpg",
            "/archive/data/tweets_media/42-B.png",
        ])
    }

    func testVideoPicksHighestBitrateMp4AndRenamesToMp4() {
        let video = MediaEntity(
            url: "https://t.co/vid",
            type: "video",
            mediaURLHTTPS: "https://pbs.twimg.com/ext_tw_video_thumb/1/pu/img/thumb.jpg",
            videoVariants: [
                VideoVariant(contentType: "application/x-mpegURL", bitrate: nil,
                             url: "https://video.twimg.com/pl/list.m3u8"),
                VideoVariant(contentType: "video/mp4", bitrate: "632000",
                             url: "https://video.twimg.com/vi/320x568/low.mp4"),
                VideoVariant(contentType: "video/mp4", bitrate: "2176000",
                             url: "https://video.twimg.com/vi/720x1280/high.mp4?tag=12"),
            ]
        )
        let tweet = Fixtures.tweet(id: "7", text: "movie https://t.co/vid", extendedMedia: [video])
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "movie [{attachment}]")
        XCTAssertEqual(tweet.mediaFiles, ["/archive/data/tweets_media/7-high.mp4"])
    }

    func testAnimatedGifIsTreatedLikeVideo() {
        let gif = MediaEntity(
            url: "https://t.co/gif",
            type: "animated_gif",
            mediaURLHTTPS: "https://pbs.twimg.com/tweet_video_thumb/T.jpg",
            videoVariants: [
                VideoVariant(contentType: "video/mp4", bitrate: "0",
                             url: "https://video.twimg.com/tweet_video/T.mp4")
            ]
        )
        let tweet = Fixtures.tweet(id: "8", text: "https://t.co/gif", extendedMedia: [gif])
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "[{attachment}]")
        XCTAssertEqual(tweet.mediaFiles, ["/archive/data/tweets_media/8-T.mp4"])
    }

    func testTruncatedTcoLinkBecomesPlaceholderText() {
        let tweet = Fixtures.tweet(id: "1", text: "RT @old: something https://t.co/abcd1234…")
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "RT @old: something [link truncated]")
    }

    func testTruncatedTcoLinkWithThreeDots() {
        let tweet = Fixtures.tweet(id: "1", text: "old https://t.co/abcd1234...")
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "old [link truncated]")
    }

    func testMediaTcoNotDoubleProcessedAsLink() {
        // The same t.co appears in both urls and media entities — media wins.
        let tweet = Fixtures.tweet(
            id: "9",
            text: "pic https://t.co/both",
            urls: [URLEntity(url: "https://t.co/both",
                             expandedURL: "https://twitter.com/u/status/9/photo/1",
                             displayURL: "pic.twitter.com/both")],
            extendedMedia: [Fixtures.photo(tco: "https://t.co/both",
                                           mediaURL: "https://pbs.twimg.com/media/P.jpg")]
        )
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "pic [{attachment}]")
    }

    func testEntitiesMediaUsedWhenNoExtendedEntities() {
        let tweet = Fixtures.tweet(
            id: "10",
            text: "old style https://t.co/legacy",
            entitiesMedia: [Fixtures.photo(tco: "https://t.co/legacy",
                                           mediaURL: "https://pbs.twimg.com/media/L.jpg")],
            extendedMedia: nil
        )
        LinkExpansion.expandLinks(in: tweet, mediaFolder: mediaFolder)
        XCTAssertEqual(tweet.fullText, "old style [{attachment}]")
        XCTAssertEqual(tweet.mediaFiles, ["/archive/data/tweets_media/10-L.jpg"])
    }
}
