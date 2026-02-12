import Foundation

enum AppStrings {
    enum Alert {
        static let importErrorTitle = "Import Error"
        static let okButton = "OK"
    }

    enum Navigation {
        static let continueButton = "Continue"
        static let backButton = "Back"
        static let startImportButton = "Start Import"
        static let importingButton = "Importing..."
        static let cancelImportButton = "Cancel Import"
        static let closeButton = "Close"
    }

    enum Wizard {
        static let drop = "Drop Archive"
        static let prerequisites = "Prerequisites"
        static let settings = "Import Settings"
        static let progress = "Import Progress"
        static let done = "Finished"
        static let dropShort = "1"
        static let prerequisitesShort = "2"
        static let settingsShort = "3"
        static let progressShort = "4"
        static let doneShort = "5"
    }

    enum DropStep {
        static let title = "Step 1: Drop Archive"
        static let analyzingTitle = "Analyzing archive"
        static let analyzingDetails = "Please wait while archive stats are generated."
        static let tweetsLabel = "Tweets"
        static let threadsLabel = "Threads"
        static let dateRangeLabel = "Date Range"
        static let dragTitle = "Drag and drop here"
        static let dragSubtitle = "Twitter archive folder or .zip"
        static let chooseArchiveButton = "Choose Archive"
    }

    enum PrerequisitesStep {
        static let title = "Step 2: Pre-requisites"
        static let intro = "Naming of threads will be enabled only if Ollama responds."
        static let ollamaURLLabel = "Ollama URL"
        static let ollamaURLPlaceholder = "http://localhost:11434/api/generate"
        static let modelLabel = "Model"
        static let modelPlaceholder = "qwen3:8b"
        static let optionalBadge = "Optional"
        static let checkingButton = "Checking..."
        static let recheckButton = "Re-check"
        static let appStoreButton = "Open App Store"
        static let cliGuideButton = "Open CLI Guide"
    }

    enum SettingsStep {
        static let title = "Step 3: Import Settings"
        static let archiveUserPrefix = "Archive user: @"
        static let tweetJournalLabel = "Tweet Journal"
        static let tweetJournalPlaceholder = "Tweets"
        static let importRepliesLabel = "Import Replies"
        static let replyJournalLabel = "Reply Journal"
        static let replyJournalPlaceholder = "Twitter Replies"
        static let ignoreRetweetsLabel = "Ignore Retweets"
        static let dateRangeLabel = "Date Range"
        static let dateRangeSeparator = "-"
        static let withinDateRangeLabel = "Within the date range:"
        static let withinDateRangeThreadsLabel = "Threads"
    }

    enum ProgressStep {
        static let title = "Step 4: Import Progress"
        static let progressLabel = "Progress"
        static let importedLabel = "Imported"
        static let skippedLabel = "Skipped"
        static let failedLabel = "Failed"
        static let totalLabel = "Total"
    }

    enum DoneStep {
        static let title = "Import Finished"
        static let details = "You can now review imported entries in Day One."
        static let logTitle = "Import Log"
        static let donationTitle = "Support Twixodus"
        static let donationDetails = "If this app helped you, consider supporting the project:"
        static let buyMeCoffeeLabel = "Buy me a coffee"
        static let buyMeCoffeeURL = "https://coff.ee/jonathunky"
        static let usdtLabel = "USDT TRC20:"
        static let usdtAddress = "TKa6wmqpLvMQwacU1wnPgFWZHFaDRV9jFs"
    }

    enum Prerequisites {
        static let dayOneAppID = "dayone-app"
        static let dayOneCLIID = "dayone-cli"
        static let ollamaID = "ollama-localhost"

        static let dayOneAppTitle = "Day One app installation"
        static let dayOneCLITitle = "Day One CLI installation"
        static let ollamaTitle = "Ollama on localhost"
        static let ollamaRunningTitle = "Ollama is running on localhost"

        static let checkingApplications = "Checking /Applications"
        static let checkingCLI = "Checking dayone executable"
        static let checkingOllama = "Checking model response via configured URL and model name."
        static let installDayOneHint = "Install Day One from the Mac App Store."
        static let installDayOneCLIHints = "Follow Day One CLI guide and ensure 'dayone' is in PATH."
        static let dayOneAppStoreURL = "https://apps.apple.com/tr/app/day-one/id1055511498?mt=12"
        static let dayOneCLIGuideURL = "https://dayoneapp.com/guides/day-one-for-mac/command-line-interface-cli/"
    }

    enum ViewModel {
        static let initialStatus = "Drop a Twitter archive folder or zip file to begin."
        static let selectArchiveTitle = "Select Twitter Archive"
        static let selectArchiveMessage = "Choose a Twitter archive folder or zip file"

        static let dropInvalidItem = "Drop a local folder or .zip archive."
        static func failedToReadDroppedItem(_ details: String) -> String {
            "Failed to read dropped item: \(details)"
        }
        static let failedToDecodeDroppedURL = "Could not decode dropped file URL."

        static let analyzingArchiveStatus = "Analyzing archive..."
        static func analyzingLog(_ path: String) -> String {
            "Analyzing: \(path)"
        }
        static let archiveReadyStatus = "Archive ready. Review stats, then continue."
        static func archiveReadyLog(totalTweets: Int, threadsInRange: Int) -> String {
            "Archive ready: \(totalTweets) tweets, \(threadsInRange) thread(s) in date range."
        }

        static let refreshingPreviewStatus = "Refreshing preview..."
        static let previewRefreshedStatus = "Preview refreshed."
        static let previewRefreshedLog = "Preview refreshed with updated settings."

        static let requiredPrereqError = "Please satisfy required prerequisites before continuing."
        static let llmEnabledLog = "LLM titles enabled for this import (Ollama hello check passed)."
        static let llmDisabledLog = "LLM titles disabled for this import (Ollama hello check failed)."

        static let resetFlowStatus = "Drop a Twitter archive folder or zip file to begin."
        static let resetFlowLog = "Reset flow. Waiting for a new archive."

        static let missingArchiveError = "Drop an archive before importing."
        static let requiredPrereqStartImportError = "Required prerequisites are not satisfied."
        static let preparingImportStatus = "Preparing import..."
        static let importStartedLog = "Import started."
        static let importCancelledStatus = "Import cancelled."
        static func importCancelledLog(_ attempted: Int) -> String {
            "Import cancelled after \(attempted) thread(s)."
        }

        static let cancellingImportStatus = "Cancelling import..."
        static let cancellationRequestedLog = "Cancellation requested."

        static let settingsResetLog = "Settings reset to defaults."
        static let readyStatus = "Ready"
        static let attentionStatus = "Attention"
        static let missingStatus = "Missing"
        static let checkingStatus = "Checking"
        static let errorStatus = "Error"
        static func errorLog(_ message: String) -> String {
            "Error: \(message)"
        }

        static let dash = "-"

        static let dayOneAppPathPrimary = "/Applications/Day One.app"
        static let dayOneAppPathUserSuffix = "/Applications/Day One.app"

        static let emptyModelError = "Model name is empty. Set it and click Re-check."
        static let invalidOllamaURLError = "Invalid Ollama URL. Use something like http://localhost:11434/api/generate."
        static let failedEncodeOllamaBodyError = "Failed to encode Ollama request body."
        static let missingHTTPResponseError = "No HTTP response from Ollama."
        static let unexpectedOllamaResponseError = "Unexpected Ollama response format."
        static let ollamaExpectedHello = "hello"
        static let ollamaHelloPrompt = "please say the word hello and nothing else"
        static func ollamaUnexpectedAnswer(_ normalized: String) -> String {
            "Model answered '\(normalized)'. Expected exactly 'hello'."
        }
        static let ollamaHelloSuccess = "Model answered 'hello'."
        static func ollamaConnectionFailed(_ details: String) -> String {
            "Connection failed: \(details)"
        }
        static func ollamaHTTPError(statusCode: Int, preview: String, suffix: String) -> String {
            "HTTP \(statusCode). \(preview)\(suffix)"
        }
    }

    enum Defaults {
        static let journalName = "Tweets"
        static let replyJournalName = "Twitter Replies"
        static let ollamaAPIURL = "http://localhost:11434/api/generate"
        static let ollamaModelName = "qwen3:8b"
        static let ollamaPrompt = "Figure out what subject this tweet is about. Deliver a very short answer, like 'about weather' or 'about Formula 1'. First word must be lowercase. No period at the end."
    }
}
