import Foundation

extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func replacingRegex(pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: template)
    }

    func matches(forRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: self) else { return nil }
            return String(self[matchRange])
        }
    }

    func captureGroups(forRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: self)
            else {
                return nil
            }
            return String(self[matchRange])
        }
    }
}
