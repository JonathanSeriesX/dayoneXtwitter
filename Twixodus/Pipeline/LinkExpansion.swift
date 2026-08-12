// Step 2 of the pipeline: clean up each tweet's text for Day One.
//
// Twitter stores every link and media attachment in the text as an opaque
// https://t.co/... URL. For each tweet, in place:
//
//   * ordinary links become Markdown links to their real destination,
//   * media links become Day One [{attachment}] placeholders, and the matching
//     files from the archive's media folder are listed in tweet.mediaFiles,
//   * truncated t.co links (from very old retweets) become "[link truncated]".

import Foundation

public enum LinkExpansion {

    /// Rewrites one tweet's fullText as described above, in place.
    /// mediaFolder is the archive's tweets_media folder; the attachment paths
    /// point into it.
    public static func expandLinks(in tweet: Tweet, mediaFolder: URL) {
        let fullText = tweet.fullText
        guard !fullText.isEmpty, !tweet.idStr.isEmpty else { return }

        let links = collectLinks(tweet)
        let mediaByTco = collectMedia(tweet)

        var text = replaceLinksInText(fullText, links: links, mediaByTco: mediaByTco)
        let (processed, mediaFiles) = replaceMediaInText(
            text, mediaByTco: mediaByTco, tweetId: tweet.idStr, mediaFolder: mediaFolder
        )
        text = processed

        tweet.fullText = text.pyStrip()
        tweet.mediaFiles = mediaFiles
    }

    private struct LinkReplacement {
        let tcoURL: String
        let markdownLink: String
    }

    private struct MediaInfo {
        let mediaURL: String
        let type: String
    }

    /// Pairs each non-media t.co URL with the Markdown link to replace it with.
    private static func collectLinks(_ tweet: Tweet) -> [LinkReplacement] {
        var links: [LinkReplacement] = []
        for entity in tweet.urls {
            guard let tco = entity.url, let expanded = entity.expandedURL else { continue }
            let linkText = entity.displayURL ?? expanded
            links.append(LinkReplacement(tcoURL: tco, markdownLink: "[\(linkText)](\(expanded))"))
        }
        return links
    }

    /// Maps each media t.co URL to its downloadable file(s): the direct image
    /// URL for photos, the highest-bitrate MP4 for videos and GIFs.
    /// Insertion order is preserved (the replacement order depends on it).
    private static func collectMedia(_ tweet: Tweet) -> [(tco: String, items: [MediaInfo])] {
        var order: [String] = []
        var byTco: [String: [MediaInfo]] = [:]

        var mediaEntities = tweet.extendedMedia ?? []
        if mediaEntities.isEmpty {
            mediaEntities = tweet.entitiesMedia
        }

        for media in mediaEntities {
            guard let tco = media.url else { continue }

            var item: MediaInfo?
            if media.type == "photo" {
                if let mediaURL = media.mediaURLHTTPS {
                    item = MediaInfo(mediaURL: mediaURL, type: media.type ?? "")
                }
            } else if media.type == "video" || media.type == "animated_gif" {
                var mp4s: [(bitrate: Int, url: String)] = []
                for variant in media.videoVariants {
                    guard variant.contentType == "video/mp4",
                          let bitrateStr = variant.bitrate,
                          let bitrate = Int(bitrateStr),
                          let url = variant.url
                    else { continue }
                    mp4s.append((bitrate, url))
                }
                if let best = mp4s.max(by: { $0.bitrate < $1.bitrate }) {
                    item = MediaInfo(mediaURL: best.url, type: media.type ?? "")
                }
            }

            if let item {
                if byTco[tco] == nil {
                    order.append(tco)
                    byTco[tco] = []
                }
                byTco[tco]?.append(item)
            }
        }

        return order.map { ($0, byTco[$0]!) }
    }

    /// This regex specifically targets t.co links followed by an ellipsis.
    private static let truncatedTco = PyRegex(#"https?://t\.co/[A-Za-z0-9]+(?:\.\.\.|…)"#)

    private static func replaceLinksInText(
        _ text: String,
        links: [LinkReplacement],
        mediaByTco: [(tco: String, items: [MediaInfo])]
    ) -> String {
        // First, replace truncated t.co links with [link truncated]
        var processed = truncatedTco.sub("[link truncated]", text)

        let mediaTcoSet = Set(mediaByTco.map(\.tco))
        let sortedLinks = links.stableSorted { $0.tcoURL.count > $1.tcoURL.count }
        for link in sortedLinks {
            if mediaTcoSet.contains(link.tcoURL) { continue }
            // Only the full, non-truncated t.co links are replaced here.
            processed = processed.replacingOccurrences(of: link.tcoURL, with: link.markdownLink, options: .literal)
        }
        return processed
    }

    private static func replaceMediaInText(
        _ text: String,
        mediaByTco: [(tco: String, items: [MediaInfo])],
        tweetId: String,
        mediaFolder: URL
    ) -> (text: String, mediaFiles: [String]) {
        var processed = text
        var mediaFiles: [String] = []

        let sorted = mediaByTco.stableSorted { $0.tco.count > $1.tco.count }
        for (tco, items) in sorted {
            let placeholders = String(repeating: "[{attachment}]", count: items.count)
            processed = processed.replacingOccurrences(of: tco, with: placeholders, options: .literal)

            for item in items {
                var filename = (item.mediaURL as NSString).lastPathComponent
                if let q = filename.firstIndex(of: "?") {
                    filename = String(filename[..<q])
                }
                if item.type == "video" || item.type == "animated_gif" {
                    filename = ((filename as NSString).deletingPathExtension) + ".mp4"
                }
                // Archived media files are named "<tweet id>-<original filename>".
                mediaFiles.append(mediaFolder.appendingPathComponent("\(tweetId)-\(filename)").path)
            }
        }

        return (processed, mediaFiles)
    }
}
