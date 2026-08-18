// The Retrieve step's run loop: works through a HydrationPlan item by item —
// fetch, download, record — reporting progress the same way ImportEngine
// does, with pause/cancel between items via the shared ImportControl.
//
// The endpoint is unofficial and its limits unpublished, so the loop is
// deliberately polite: sequential requests with a fixed breather in between,
// exponential backoff when one fails, and the whole run aborts after enough
// consecutive failures to look like a block rather than a blip. Progress is
// saved to the store as it goes, so a cancelled run keeps everything it
// fetched.

import Foundation

public struct HydrationRunResult {
    public var retweetsRetrieved = 0
    public var quotesRetrieved = 0
    public var unavailable = 0
    public var filesDownloaded = 0
    public var failures = 0
    public var wasCancelled = false
    public var abortedByErrors = false
}

public final class HydrationEngine {

    private let store: HydrationStore
    private let client: SyndicationClient
    private let control: ImportControl
    private let callbacks: ImportCallbacks

    /// The breather between syndication requests, in nanoseconds.
    private static let pace: UInt64 = 400_000_000
    /// Backoff ladder for a failed request, in seconds.
    private static let backoff: [Double] = [2, 8, 20]
    /// This many consecutive dead requests means we're blocked — stop the run.
    private static let abortAfter = 8

    private var consecutiveFailures = 0
    private var processedSinceSave = 0
    private var done = 0
    private var total = 0

    public init(
        store: HydrationStore,
        client: SyndicationClient = SyndicationClient(),
        control: ImportControl,
        callbacks: ImportCallbacks
    ) {
        self.store = store
        self.client = client
        self.control = control
        self.callbacks = callbacks
    }

    public func run(plan: HydrationPlan) async -> HydrationRunResult {
        var result = HydrationRunResult()
        total = plan.totalPending
        callbacks.progress(0, total)

        // -- Truncated retweets: fetch the RT's own ID; the endpoint answers
        // with the original tweet, full text and attachments included.
        for tweet in plan.pendingRetweets {
            guard await keepGoing(&result) else { return finish(result) }
            callbacks.activity("Retrieving retweet \(tweet.idStr)…")

            switch await fetchWithBackoff(id: tweet.idStr) {
            case .tweet(var data):
                data.media = await downloadMedia(data.media, ownerId: tweet.idStr, result: &result)
                store.retweets[tweet.idStr] = record(ok: data)
                result.retweetsRetrieved += 1
                let attachments = data.media.filter { $0.fileName != nil }.count
                log("Retweet of @\(data.screenName): full text recovered"
                    + (attachments > 0 ? " (+\(attachments) attachment\(attachments == 1 ? "" : "s"))" : ""),
                    .success)
            case .unavailable(let reason):
                store.retweets[tweet.idStr] = record(unavailable: reason)
                result.unavailable += 1
                log("Retweet \(tweet.idStr) is gone: \(reason)", .warning)
            case .failed(let reason):
                result.failures += 1
                log("Couldn't retrieve retweet \(tweet.idStr): \(reason) — will retry next run", .warning)
            }
            await step(&result)
        }

        // -- Quoted tweets: fetch each distinct quoted status once.
        for (statusId, handle) in plan.pendingQuotes {
            guard await keepGoing(&result) else { return finish(result) }
            callbacks.activity("Retrieving quoted tweet by \(handle)…")

            switch await fetchWithBackoff(id: statusId) {
            case .tweet(let data):
                store.quotes[statusId] = record(ok: data)
                result.quotesRetrieved += 1
                log("Quoted tweet by @\(data.screenName) retrieved", .success)
            case .unavailable(let reason):
                store.quotes[statusId] = record(unavailable: reason)
                result.unavailable += 1
                log("Quoted tweet by \(handle) is gone: \(reason)", .warning)
            case .failed(let reason):
                result.failures += 1
                log("Couldn't retrieve quoted tweet \(statusId): \(reason) — will retry next run", .warning)
            }
            await step(&result)
        }

        // -- Missing archive media: plain downloads, no syndication involved.
        for item in plan.pendingMedia {
            guard await keepGoing(&result) else { return finish(result) }
            callbacks.activity("Downloading \(item.fileName)…")

            do {
                let bytes = try await client.download(item.sourceURL, to: store.mediaPath(item.fileName))
                result.filesDownloaded += 1
                consecutiveFailures = 0
                log("Downloaded \(item.fileName) (\(Self.byteCount(bytes)))", .success)
            } catch {
                result.failures += 1
                consecutiveFailures += 1
                log("Couldn't download \(item.fileName): \(error.localizedDescription)", .warning)
            }
            await step(&result)
        }

        return finish(result)
    }

    // MARK: - One fetch, with backoff

    /// One syndication fetch; transient failures are retried on a backoff
    /// ladder before giving up on the item.
    private func fetchWithBackoff(id: String) async -> SyndicationOutcome {
        var outcome = await client.fetch(id: id)
        for delay in Self.backoff {
            guard case .failed = outcome, !control.isCancelled else { break }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            outcome = await client.fetch(id: id)
        }
        if case .failed = outcome {
            consecutiveFailures += 1
        } else {
            consecutiveFailures = 0
        }
        return outcome
    }

    /// Downloads a fetched tweet's attachments into the store's media folder,
    /// stamping each item's fileName on success.
    private func downloadMedia(
        _ media: [HydratedMediaFile], ownerId: String, result: inout HydrationRunResult
    ) async -> [HydratedMediaFile] {
        var stamped = media
        for index in stamped.indices {
            guard !control.isCancelled else { break }
            let item = stamped[index]
            let fileName = SyndicationClient.fileName(
                ownerTweetId: ownerId, sourceURL: item.sourceURL, type: item.type)
            do {
                let bytes = try await client.download(item.sourceURL, to: store.mediaPath(fileName))
                stamped[index].fileName = fileName
                result.filesDownloaded += 1
                log("Downloaded \(fileName) (\(Self.byteCount(bytes)))", .info)
            } catch {
                result.failures += 1
                log("Couldn't download \(fileName): \(error.localizedDescription)", .warning)
            }
        }
        return stamped
    }

    // MARK: - Housekeeping between items

    private func record(ok data: HydratedTweetData) -> HydrationRecord {
        HydrationRecord(status: HydrationRecord.statusOK, reason: nil, fetchedAt: Date(), tweet: data)
    }

    private func record(unavailable reason: String) -> HydrationRecord {
        HydrationRecord(status: HydrationRecord.statusUnavailable, reason: reason,
                        fetchedAt: Date(), tweet: nil)
    }

    /// Progress + periodic save + the breather, after every item.
    private func step(_ result: inout HydrationRunResult) async {
        done += 1
        callbacks.progress(done, total)
        processedSinceSave += 1
        if processedSinceSave >= 20 {
            saveStore()
        }
        try? await Task.sleep(nanoseconds: Self.pace)
    }

    /// Honors pause, cancel, and the too-many-failures abort. False stops the run.
    private func keepGoing(_ result: inout HydrationRunResult) async -> Bool {
        if consecutiveFailures >= Self.abortAfter {
            log("\(Self.abortAfter) requests in a row failed — the endpoint is likely "
                + "rate-limiting us. Stopping; everything retrieved so far is saved, "
                + "run Retrieve again later.", .error)
            result.abortedByErrors = true
            return false
        }
        while control.isPaused && !control.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if control.isCancelled {
            result.wasCancelled = true
            return false
        }
        return true
    }

    private func finish(_ result: HydrationRunResult) -> HydrationRunResult {
        saveStore()
        callbacks.activity("")
        return result
    }

    private func saveStore() {
        processedSinceSave = 0
        do {
            try store.save()
        } catch {
            log("Couldn't save the retrieval cache to \(store.folder.path): "
                + "\(error.localizedDescription)", .error)
        }
    }

    private func log(_ message: String, _ kind: ImportLogKind) {
        callbacks.log(message, kind)
    }

    private static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
