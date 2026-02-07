import Foundation

struct ArchiveLocation: Sendable, Equatable {
    let droppedURL: URL
    let archiveRootURL: URL
    let dataDirectoryURL: URL
    let tweetsJSURL: URL
    let extractedFromZip: Bool

    var displayName: String {
        archiveRootURL.lastPathComponent
    }
}

struct ArchiveOverview: Sendable {
    let archivePath: String
    let statusesFilePath: String
    let sourcePath: String
    let sourceWasZip: Bool
    let archiveUsername: String?
    let archiveDisplayName: String?
    let totalTweets: Int
    let threadsBeforeDateFilter: Int
    let threadsInDateRange: Int
    let alreadyImported: Int
    let pendingToImport: Int
    let earliestTweetDate: Date?
    let latestTweetDate: Date?
}

struct PreparedImportContext: Sendable {
    let archive: ArchiveLocation
    let statusesFileURL: URL
    let totalTweets: Int
    let filteredThreads: [[Tweet]]
    let pendingThreads: [[Tweet]]
    let alreadyProcessedIDs: Set<String>
    let ownTweetIDs: Set<String>
    let overview: ArchiveOverview
}

struct ImportProgressSnapshot: Sendable {
    let totalThreads: Int
    let alreadyImported: Int
    let importedThisRun: Int
    let skippedThisRun: Int
    let failedThisRun: Int
    let currentIndex: Int
    let currentTweetID: String?
    let currentCategory: String?
    let statusMessage: String

    var completedTotal: Int {
        min(totalThreads, alreadyImported + currentIndex)
    }

    var fraction: Double {
        guard totalThreads > 0 else { return 0 }
        return Double(completedTotal) / Double(totalThreads)
    }
}

struct ImportRunSummary: Sendable {
    let totalThreads: Int
    let alreadyImported: Int
    let importedThisRun: Int
    let skippedThisRun: Int
    let failedThisRun: Int
    let attemptedThisRun: Int
    let wasCancelled: Bool
    let statusMessage: String
}

enum ImportEngineError: LocalizedError {
    case droppedItemIsNotFileSystemURL
    case unsupportedDropType
    case zipExtractionFailed(String)
    case noTwitterArchiveFound(URL)
    case tweetsFileMissing(URL)
    case tweetsFileReadFailed(path: String, details: String)
    case invalidTweetsJSON(path: String, reason: String, preview: String)
    case cannotDecodeTweets(path: String, details: String, preview: String)

    var errorDescription: String? {
        switch self {
        case .droppedItemIsNotFileSystemURL:
            return "Dropped item is not a valid local file URL."
        case .unsupportedDropType:
            return "Drop a folder or a .zip archive."
        case .zipExtractionFailed(let details):
            return "Failed to extract zip archive: \(details)"
        case .noTwitterArchiveFound(let directory):
            return "Could not find a Twitter archive under \(directory.path)."
        case .tweetsFileMissing(let archiveRoot):
            return "Could not find data/tweets.js under \(archiveRoot.path)."
        case let .tweetsFileReadFailed(path, details):
            return "Unable to read tweets.js at \(path): \(details)"
        case let .invalidTweetsJSON(path, reason, preview):
            return """
            tweets.js is not in the expected format.
            Path: \(path)
            Reason: \(reason)
            Preview: \(preview)
            """
        case let .cannotDecodeTweets(path, details, preview):
            return """
            Unable to decode tweets.js JSON payload.
            Path: \(path)
            Details: \(details)
            Preview: \(preview)
            """
        }
    }
}

struct ThreadAggregate: Sendable {
    let text: String
    let tags: [String]
    let mediaFiles: [String]
    let date: Date
    let coordinate: (latitude: Double, longitude: Double)?
}

actor ImportCoordinator {
    func resolveAndPrepare(dropURL: URL, settings: ImportSettings) throws -> PreparedImportContext {
        let engine = TwitterImportEngine()
        let archive = try engine.resolveDrop(url: dropURL)
        return try engine.prepareImportContext(archive: archive, settings: settings)
    }

    func refresh(archive: ArchiveLocation, settings: ImportSettings) throws -> PreparedImportContext {
        let engine = TwitterImportEngine()
        return try engine.prepareImportContext(archive: archive, settings: settings)
    }

    func runImport(
        context: PreparedImportContext,
        settings: ImportSettings,
        progress: @escaping @Sendable (ImportProgressSnapshot) -> Void
    ) async -> ImportRunSummary {
        let engine = TwitterImportEngine()
        return await engine.runImport(context: context, settings: settings, progress: progress)
    }
}
