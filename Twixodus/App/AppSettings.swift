// The app's persistent settings — the GUI equivalent of config.py. Every
// value survives app restarts via UserDefaults; buildConfig() turns the lot
// into the ImportConfig the pipeline consumes.

import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {

    private static let defaults = UserDefaults.standard

    // MARK: - Journals

    @AppStorage("journalName") var journalName = "Tweets"
    @AppStorage("importReplies") var importReplies = true
    @AppStorage("replyJournalName") var replyJournalName = "Twitter Replies"

    // MARK: - Account

    /// Off means the account is gone forever: no twitter.com links are written.
    @AppStorage("accountStillExists") var accountStillExists = true
    @AppStorage("currentUsername") var currentUsername = ""

    // MARK: - Date range & limits

    @AppStorage("startDateEpoch") private var startDateEpoch: Double = 0
    @AppStorage("endDateEpoch") private var endDateEpoch: Double = 0
    @AppStorage("limitThreads") var limitThreads = false
    @AppStorage("maxThreadsToProcess") var maxThreadsToProcess = 100

    // MARK: - Options

    @AppStorage("shuffleMode") var shuffleMode = true
    @AppStorage("ignoreRetweets") var ignoreRetweets = false
    @AppStorage("showTweetSource") var showTweetSource = true

    // MARK: - LLM titles

    @AppStorage("llmTitlesEnabled") var llmTitlesEnabled = true
    @AppStorage("llmTitlesForSingleTweets") var llmTitlesForSingleTweets = true
    @AppStorage("llmMaxImages") var llmMaxImages = 26
    @AppStorage("ollamaHost") var ollamaHost = "http://localhost:11434"
    @AppStorage("ollamaModelName") var ollamaModelName = "qwen3.5:9b-mlx"
    @AppStorage("ollamaTimeout") var ollamaTimeout = 60
    @AppStorage("ollamaTitlePrompt") var ollamaTitlePrompt = ImportConfig.defaultTitlePrompt

    // MARK: - Date range as Dates

    /// The pickers work in calendar days; the pipeline thinks in naive UTC.
    /// Dates are stored as epochs and normalized to UTC midnight on the way
    /// into the pipeline.
    var startDate: Date {
        get { startDateEpoch > 0 ? Date(timeIntervalSince1970: startDateEpoch) : PipelineDates.date(2006, 3, 21) }
        set { startDateEpoch = newValue.timeIntervalSince1970; objectWillChange.send() }
    }

    var endDate: Date {
        get { endDateEpoch > 0 ? Date(timeIntervalSince1970: endDateEpoch) : Date() }
        set { endDateEpoch = newValue.timeIntervalSince1970; objectWillChange.send() }
    }

    // MARK: - Pipeline config

    /// Converts a picker-chosen date to the same calendar day at UTC midnight.
    private static func utcDay(_ date: Date, endOfDay: Bool) -> Date {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let midnight = PipelineDates.date(local.year!, local.month!, local.day!)
        // The end of the range is inclusive: anything posted on that day counts.
        return endOfDay ? midnight.addingTimeInterval(86_399) : midnight
    }

    func buildConfig() -> ImportConfig {
        let username = currentUsername.pyTrimmedOrNil()
        return ImportConfig(
            journalName: journalName,
            replyJournalName: importReplies ? replyJournalName.pyTrimmedOrNil() : nil,
            currentUsername: accountStillExists ? username : nil,
            maxThreadsToProcess: limitThreads && maxThreadsToProcess > 0 ? maxThreadsToProcess : nil,
            shuffleMode: shuffleMode,
            ignoreRetweets: ignoreRetweets,
            showTweetSource: showTweetSource,
            startDate: Self.utcDay(startDate, endOfDay: false),
            endDate: Self.utcDay(endDate, endOfDay: true),
            processTitlesWithLLM: llmTitlesEnabled,
            llmTitlesForSingleTweets: llmTitlesForSingleTweets,
            llmMaxImages: llmMaxImages,
            ollamaHost: ollamaHost,
            ollamaModelName: ollamaModelName,
            ollamaTimeout: TimeInterval(ollamaTimeout),
            ollamaTitlePrompt: ollamaTitlePrompt
        )
    }
}

extension String {
    /// Trimmed string, or nil when empty — for optional settings fields.
    func pyTrimmedOrNil() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
