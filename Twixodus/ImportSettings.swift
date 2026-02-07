import Foundation

struct ImportSettings: Codable, Equatable, Sendable {
    var journalName: String = "Tweets"
    var includeReplies: Bool = true
    var replyJournalName: String = "Twitter Replies"
    var currentUsername: String = "JonathanSeriesX"
    var ignoreRetweets: Bool = false
    var startDate: Date = ImportSettings.defaultStartDate
    var endDate: Date = ImportSettings.defaultEndDate
    var processTitlesWithLLM: Bool = true
    var ollamaAPIURL: String = "http://localhost:11434/api/generate"
    var ollamaModelName: String = "qwen3"
    var ollamaPrompt: String = "Figure out what subject this tweet is about. Deliver a very short answer, like 'about weather' or 'about Formula 1'. First word must be lowercase. No period at the end."

    static let defaultsKey = "Twixodus.ImportSettings"

    static var defaultStartDate: Date {
        Self.configDateFormatter.date(from: "20 March 2006") ?? Date.distantPast
    }

    static var defaultEndDate: Date {
        Self.configDateFormatter.date(from: "20 April 2069") ?? Date.distantFuture
    }

    static func load() -> ImportSettings {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode(ImportSettings.self, from: data)
        else {
            return ImportSettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    var normalizedCurrentUsername: String? {
        currentUsername.trimmedNilIfEmpty
    }

    var normalizedReplyJournalName: String? {
        guard includeReplies else { return nil }
        return replyJournalName.trimmedNilIfEmpty
    }

    private static let configDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMMM yyyy"
        return formatter
    }()
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
