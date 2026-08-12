// Small helpers that reproduce Python string semantics exactly. The port was
// verified byte-identical against the Python pipeline over a real archive;
// these helpers are where the subtle differences (splitlines, strip) hide.

import Foundation

extension String {
    /// Python str.strip() — trims whitespace and newlines from both ends.
    func pyStrip() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Python str.strip(chars) — trims any of the given characters from both ends.
    func pyStrip(charactersIn chars: String) -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: chars))
    }

    /// Python str.rstrip(chars).
    func pyRstrip(charactersIn chars: String) -> String {
        let set = CharacterSet(charactersIn: chars)
        var result = self
        while let scalar = result.unicodeScalars.last, set.contains(scalar) {
            result.unicodeScalars.removeLast()
        }
        return result
    }

    /// Python str.lstrip().
    func pyLstrip() -> String {
        guard let index = firstIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(self[index...])
    }

    /// Python str.splitlines(): one element per line, no trailing empty
    /// element for a final line break. Python splits on far more than \n —
    /// \r, \r\n, \v, \f, the C1 NEL and the Unicode line/paragraph separators
    /// all count — and escape_md relies on that: split-then-join is what
    /// normalizes a tweet's stray \r characters to \n.
    /// "a\n\n" → ["a", ""], "" → [].
    func pySplitlines() -> [String] {
        let boundaries: Set<Unicode.Scalar> = [
            "\n", "\r", "\u{0B}", "\u{0C}", "\u{1C}", "\u{1D}", "\u{1E}",
            "\u{85}", "\u{2028}", "\u{2029}",
        ]
        var lines: [String] = []
        var current = ""
        var previousWasCR = false

        for scalar in unicodeScalars {
            if previousWasCR && scalar == "\n" {
                // \r\n is a single line boundary.
                previousWasCR = false
                continue
            }
            previousWasCR = scalar == "\r"
            if boundaries.contains(scalar) {
                lines.append(current)
                current = ""
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

/// Stable sort — Swift's sort() is not guaranteed stable, Python's is, and the
/// link-replacement order relies on it.
extension Array {
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// NSRegularExpression conveniences used across the pipeline port.
struct PyRegex {
    let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // Patterns are compile-time constants ported from the Python source;
        // a failure here is a programmer error.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// re.match — anchored at the start; returns the matched groups.
    func match(_ string: String) -> PyMatch? {
        let range = NSRange(string.startIndex..., in: string)
        guard let m = regex.firstMatch(in: string, options: .anchored, range: range) else { return nil }
        return PyMatch(result: m, string: string)
    }

    /// re.search — first match anywhere.
    func search(_ string: String) -> PyMatch? {
        let range = NSRange(string.startIndex..., in: string)
        guard let m = regex.firstMatch(in: string, range: range) else { return nil }
        return PyMatch(result: m, string: string)
    }

    /// re.finditer.
    func findAll(_ string: String) -> [PyMatch] {
        let range = NSRange(string.startIndex..., in: string)
        return regex.matches(in: string, range: range).map { PyMatch(result: $0, string: string) }
    }

    /// re.sub with a literal replacement (no backreference expansion).
    func sub(_ replacement: String, _ string: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        let escaped = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: escaped)
    }
}

struct PyMatch {
    let result: NSTextCheckingResult
    let string: String

    /// group(i); group(0) is the whole match.
    func group(_ index: Int) -> String? {
        let nsRange = result.range(at: index)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: string) else { return nil }
        return String(string[range])
    }

    /// m.end() — the UTF-16 offset just past the whole match, as a String.Index.
    var endIndex: String.Index {
        Range(result.range, in: string)!.upperBound
    }
}
