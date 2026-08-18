// The workaround for the paywalled X API: cdn.syndication.twimg.com is the
// backend of embedded tweets, and it answers without any authentication.
// Two properties make it perfect for filling an archive's gaps:
//
//   * asking for a RETWEET's own ID returns the ORIGINAL tweet — full text,
//     not the 140-character "RT @user: …" cut the archive stores;
//   * the response carries mediaDetails with direct pbs/video.twimg.com URLs,
//     so attachments the archive never included can be downloaded.
//
// Deleted/protected tweets come back as a TweetTombstone with a human-readable
// reason. The endpoint is unofficial: the client paces itself and backs off
// on rate limits, and computes the endpoint's token the way the embed widget
// does in case the currently-ignored parameter ever starts being validated.

import Foundation

public enum SyndicationOutcome {
    case tweet(HydratedTweetData)
    /// The endpoint answered, but the tweet is gone — with the reason.
    case unavailable(String)
    /// Transient trouble (network, rate limit); safe to retry later.
    case failed(String)
}

public final class SyndicationClient {

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetching one tweet

    public func fetch(id: String) async -> SyndicationOutcome {
        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "token", value: Self.token(for: id)),
        ]

        let data: Data
        let status: Int
        do {
            let (body, response) = try await session.data(from: components.url!)
            data = body
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return .failed(error.localizedDescription)
        }

        switch status {
        case 200:
            break
        case 404:
            return .unavailable("Deleted or never existed")
        case 429, 403:
            return .failed("Rate limited (HTTP \(status))")
        default:
            return .failed("HTTP \(status)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("Unparseable response")
        }
        if json["__typename"] as? String == "TweetTombstone" {
            let tombstone = json["tombstone"] as? [String: Any]
            let text = (tombstone?["text"] as? [String: Any])?["text"] as? String
            return .unavailable(Self.cleanTombstone(text) ?? "Tweet unavailable")
        }
        guard let parsed = Self.parseTweet(json) else {
            return .failed("Unexpected response shape")
        }
        return .tweet(parsed)
    }

    /// Strips the boilerplate "Learn more" tail off a tombstone reason.
    private static func cleanTombstone(_ text: String?) -> String? {
        guard var text else { return nil }
        if let range = text.range(of: " Learn more") {
            text = String(text[..<range.lowerBound])
        }
        return text.pyStrip()
    }

    // MARK: - Parsing

    private static func parseTweet(_ json: [String: Any]) -> HydratedTweetData? {
        guard let idStr = json["id_str"] as? String,
              let text = json["text"] as? String,
              let user = json["user"] as? [String: Any],
              let screenName = user["screen_name"] as? String
        else { return nil }

        let entities = json["entities"] as? [String: Any] ?? [:]
        var urls: [HydratedURL] = []
        for item in entities["urls"] as? [[String: Any]] ?? [] {
            guard let tco = item["url"] as? String,
                  let expanded = item["expanded_url"] as? String
            else { continue }
            urls.append(HydratedURL(
                tco: tco, expanded: expanded,
                display: item["display_url"] as? String))
        }

        // entities.media[i] and mediaDetails[i] describe the same attachment;
        // entities.media carries the t.co placeholder, mediaDetails the
        // downloadable URL. Zip them by position.
        let entityMedia = entities["media"] as? [[String: Any]] ?? []
        var media: [HydratedMediaFile] = []
        for (index, detail) in (json["mediaDetails"] as? [[String: Any]] ?? []).enumerated() {
            guard let type = detail["type"] as? String,
                  let source = bestSourceURL(detail, type: type)
            else { continue }
            let tco = index < entityMedia.count
                ? entityMedia[index]["url"] as? String
                : entityMedia.first?["url"] as? String
            media.append(HydratedMediaFile(tco: tco, type: type, sourceURL: source, fileName: nil))
        }

        return HydratedTweetData(
            idStr: idStr,
            screenName: screenName,
            name: user["name"] as? String,
            createdAt: json["created_at"] as? String,
            text: text,
            urls: urls,
            media: media
        )
    }

    /// The best-quality download URL: the original-size image for photos, the
    /// highest-bitrate MP4 for videos and GIFs (same rule as LinkExpansion).
    private static func bestSourceURL(_ detail: [String: Any], type: String) -> String? {
        if type == "photo" {
            guard let url = detail["media_url_https"] as? String else { return nil }
            return url + "?name=orig"
        }
        let videoInfo = detail["video_info"] as? [String: Any]
        let variants = videoInfo?["variants"] as? [[String: Any]] ?? []
        let mp4s = variants.compactMap { variant -> (bitrate: Int, url: String)? in
            guard variant["content_type"] as? String == "video/mp4",
                  let url = variant["url"] as? String
            else { return nil }
            // GIF variants often carry no bitrate at all — treat that as 0.
            let bitrate = (variant["bitrate"] as? Int)
                ?? Int(variant["bitrate"] as? String ?? "") ?? 0
            return (bitrate, url)
        }
        return mp4s.max { $0.bitrate < $1.bitrate }?.url
            ?? (detail["media_url_https"] as? String)
    }

    // MARK: - Downloading media

    /// Downloads one attachment to the given location. Returns the byte count.
    public func download(_ sourceURL: String, to destination: URL) async throws -> Int {
        guard let url = URL(string: sourceURL) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return data.count
    }

    /// The file name an attachment downloads to, following the archive's own
    /// "<tweet id>-<original file name>" convention. Videos and GIFs get .mp4,
    /// like LinkExpansion expects.
    public static func fileName(ownerTweetId: String, sourceURL: String, type: String) -> String {
        var name = (sourceURL as NSString).lastPathComponent
        if let q = name.firstIndex(of: "?") {
            name = String(name[..<q])
        }
        if type == "video" || type == "animated_gif" {
            name = ((name as NSString).deletingPathExtension) + ".mp4"
        }
        return "\(ownerTweetId)-\(name)"
    }

    // MARK: - The endpoint's token

    /// The token the embed widget derives from the tweet ID:
    /// ((id / 1e15) * π) in base 36, with every "0" and "." removed. The
    /// endpoint currently accepts anything here, but computing the real value
    /// costs nothing and survives the day it starts checking.
    static func token(for id: String) -> String {
        guard let n = Double(id) else { return "x" }
        var value = n / 1e15 * Double.pi
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")

        var integerPart = Int(value)
        value -= Double(integerPart)
        var head = ""
        repeat {
            head = String(digits[integerPart % 36]) + head
            integerPart /= 36
        } while integerPart > 0

        var tail = ""
        for _ in 0..<11 {
            value *= 36
            let digit = Int(value)
            tail += String(digits[min(digit, 35)])
            value -= Double(digit)
        }

        let token = (head + "." + tail)
            .replacingOccurrences(of: "0", with: "")
            .replacingOccurrences(of: ".", with: "")
        return token.isEmpty ? "x" : token
    }
}
