// The optional xcancel.com link rewrite (config.useXcancelLinks).
//
// Only URLs that lead to a tweet are touched: a status link keeps its path
// and gets its host swapped for xcancel.com (a Nitter instance that mirrors
// Twitter's status URLs, /likes, /retweets and /i/web/status/ included).
// Everything else keeps its link: profile links, the "Sent from <client>"
// source links (twitter.com/download/...), and unrelated domains that merely
// end in "x.com" ("somesitex.com") never match.

import Foundation

public enum XcancelLinks {

    public static let host = "xcancel.com"

    /// A URL that leads to a tweet: twitter.com or x.com (with the usual
    /// www./mobile. prefixes) followed by /<user>/status(es)/<id> or
    /// /i/web/status/<id>. The host alternation sits right after "://", so
    /// look-alike domains can't match; the path must contain /status/<digits>,
    /// so client links like twitter.com/download/android can't either.
    private static let tweetURL = PyRegex(
        #"https?://(?:www\.|mobile\.)?(?:twitter\.com|x\.com)/((?:i/(?:web/)?status|[A-Za-z0-9_]+/status(?:es)?)/\d[^\s<>()\[\]"']*)"#
    )

    /// Repoints every tweet link in the text at xcancel.com. Markdown link
    /// labels are left alone — a label has no scheme, so only the URL half
    /// of [label](url) matches and the tweet's visible text stays as posted.
    public static func rewriteTweetLinks(in text: String) -> String {
        // Cheap pre-check: most tweets link to no tweets at all.
        guard text.contains("twitter.com/") || text.contains("x.com/") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return tweetURL.regex.stringByReplacingMatches(
            in: text, range: range, withTemplate: "https://\(host)/$1")
    }
}
