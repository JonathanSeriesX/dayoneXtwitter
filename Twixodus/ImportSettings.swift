import Foundation

struct ImportSettings: Codable, Equatable, Sendable {
    var journalName: String = AppStrings.Defaults.journalName
    var includeReplies: Bool = true
    var replyJournalName: String = AppStrings.Defaults.replyJournalName
    var ignoreRetweets: Bool = false
    var skipAlreadyImported: Bool = false
    var startDate: Date = ImportSettings.defaultStartDate
    var endDate: Date = ImportSettings.defaultEndDate
    var processTitlesWithLLM: Bool = true
    var ollamaAPIURL: String = AppStrings.Defaults.ollamaAPIURL
    var ollamaModelName: String = AppStrings.Defaults.ollamaModelName
    var ollamaPrompt: String = AppStrings.Defaults.ollamaPrompt

    static var defaultStartDate: Date {
        Self.configDateFormatter.date(from: "20 March 2006") ?? Date.distantPast
    }

    static var defaultEndDate: Date {
        Self.configDateFormatter.date(from: "20 April 2069") ?? Date.distantFuture
    }

    static func load() -> ImportSettings {
        ImportSettings()
    }

    func save() {
        // Intentionally no-op: the app is single-run and should not persist settings.
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
